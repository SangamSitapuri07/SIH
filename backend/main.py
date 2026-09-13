import asyncio
import json
import time
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

load_dotenv(Path(__file__).with_name(".env"))

from event_hub import event_hub
import routes_v1
from routes_v1 import router as v1_router, providers, agents_engine
from routes_v1 import _ADVISORY_CACHE, _ADVISORY_CACHE_TIMES
from ingestion import IngestionDaemon

# Pydantic/asyncio context: the daemon is created in the lifespan hook so it
# binds to the running event loop.
ingestion_daemon: IngestionDaemon | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global ingestion_daemon
    ingestion_daemon = IngestionDaemon(
        providers_engine=providers,
        agents_engine=agents_engine,
        advisory_cache=_ADVISORY_CACHE,
        advisory_cache_times=_ADVISORY_CACHE_TIMES,
        poll_interval_s=600.0,   # per-coordinate snapshot refresh every 10 min
        cyclone_interval_s=1800.0,  # GDACS/JTWC check every 30 min
    )
    ingestion_daemon.watch(18.92, 72.83, label="Default (Mumbai Offshore)")
    ingestion_daemon.start()
    # Client-requested coordinates join the watchlist automatically.
    routes_v1.set_watch_hook(lambda lat, lon: ingestion_daemon.watch(lat, lon))
    try:
        yield
    finally:
        if ingestion_daemon:
            await ingestion_daemon.stop()


app = FastAPI(
    title="ORCA Box — Marine EcOsystem Reasoning with Collaborative Agents",
    description="Authoritative Edge Intelligence Server & Advisory Engine (Phase 2)",
    version="2.1.0",
    lifespan=lifespan,
)

# Enable CORS for Flutter APK client and local dev tools
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(v1_router)


@app.get("/")
def root():
    return {
        "system": "ORCA Box Server",
        "status": "OPERATIONAL",
        "phase": 3,
        "docs_url": "/docs",
        "health_check": "/api/v1/health",
    }


@app.get("/api/live/stream")
async def live_stream():
    """
    Server-Sent Events (SSE) live stream.

    Delivers real events published by the proactive ingestion daemon:
      - `telemetry`      : ingestion heartbeat / error telemetry
      - `data.updated`   : fresh snapshot ingested for a watched coordinate
      - `alert.push`     : safety-relevant change (verdict flip, cyclone)
    Each connected client gets an independent bounded queue; slow consumers
    never block ingestion.
    """
    queue = await event_hub.subscribe()

    async def event_generator():
        try:
            # Announce the connection with current daemon state.
            yield _sse(
                "connected",
                {
                    "message": "Connected to ORCA Box live stream",
                    "watched_coordinates": len(ingestion_daemon.watched_keys) if ingestion_daemon else 0,
                    "timestamp": int(time.time()),
                },
            )
            while True:
                try:
                    # Keepalives must land well inside the client's receive
                    # timeout (app uses 15s) — real events can be minutes
                    # apart now that ingestion is proactive.
                    event = await asyncio.wait_for(queue.get(), timeout=5.0)
                except asyncio.TimeoutError:
                    # Comment keepalive keeps intermediaries from closing us.
                    yield ": keepalive\n\n"
                    continue
                yield _sse(event["type"], event["data"])
        finally:
            await event_hub.unsubscribe(queue)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


def _sse(event_type: str, data: dict) -> str:
    return f"event: {event_type}\ndata: {json.dumps(data)}\n\n"


@app.get("/api/v1/events/recent")
async def recent_events(limit: int = 20):
    """Diagnostics: most recent hub events (for dashboards/debugging)."""
    return {"events": event_hub.recent_events(limit)}


@app.get("/api/v1/ingestion/status")
async def ingestion_status():
    """Diagnostics: watchlist, last verdicts, last tick stats."""
    if ingestion_daemon is None:
        return {"running": False, "watched": []}
    return ingestion_daemon.status()
