import asyncio
import json
import time
from pathlib import Path
from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

load_dotenv(Path(__file__).with_name(".env"))

from routes_v1 import router as v1_router

app = FastAPI(
    title="ORCA Box — Marine EcOsystem Reasoning with Collaborative Agents",
    description="Authoritative Edge Intelligence Server & Advisory Engine (Phase 2)",
    version="2.0.0"
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
        "phase": 2,
        "docs_url": "/docs",
        "health_check": "/api/v1/health"
    }

@app.get("/api/live/stream")
async def live_stream():
    """
    Server-Sent Events (SSE) live stream delivering real-time telemetry,
    advisory updates, risk changes, and backend agent run events.
    """
    async def event_generator():
        yield f"event: connected\ndata: {json.dumps({'message': 'Connected to ORCA Box SSE Stream', 'timestamp': int(time.time())})}\n\n"
        
        count = 0
        while True:
            await asyncio.sleep(8)
            count += 1
            payload = {
                "event_id": f"evt-{count}",
                "timestamp": int(time.time()),
                "category": "telemetry",
                "system_status": "NORMAL",
                "active_agents": 11,
                "cached_freshness": "FRESH"
            }
            yield f"event: heartbeat\ndata: {json.dumps(payload)}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
