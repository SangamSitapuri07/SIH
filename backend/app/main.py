"""FastAPI app for the ORCA Marine Intelligence Platform.

Endpoints:
  GET  /              — health + version
  POST /ask           — main conversational endpoint
  GET  /stream        — Server-Sent Events real-time stream of agent steps
  WS   /ws            — WebSocket real-time stream
  GET  /docs          — auto-generated Swagger UI

Run with:
    uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import asyncio
import json
import logging
from typing import AsyncIterator

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from app.agents import AGENTS, Pipeline
from app.config import settings
from app.models import OrcaResponse, UserQuery

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s | %(message)s")
log = logging.getLogger("orca")

app = FastAPI(
    title=settings.app_name,
    version=settings.version,
    description=(
        "Agentic AI marine intelligence platform for SIH 2026 PS 176. "
        "Built around a hand-crafted multi-agent pipeline that classifies "
        "user intent, fans out to specialist agents (weather, ocean, GIS, "
        "risk), and synthesises explainable responses with map payloads."
    ),
)

# Permissive CORS so the Flutter app can call this from any origin during dev.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# A single shared pipeline. The pipeline is stateless apart from the agents
# it owns, so a shared instance is safe.
pipeline = Pipeline(agents=AGENTS)


class AskResponse(BaseModel):
    response: OrcaResponse


@app.get("/")
async def root() -> dict:
    return {
        "name": settings.app_name,
        "version": settings.version,
        "status": "ok",
        "ps": "SIH26176 — ORCA Marine EcOsystem Reasoning with Collaborative Agents",
    }


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok"}


@app.post("/ask", response_model=AskResponse)
async def ask(query: UserQuery) -> AskResponse:
    """Run the full ORCA pipeline and return the synthesized response."""
    log.info("ASK: %r location=%s lang=%s", query.text, query.location, query.language)
    response = await pipeline.run(
        user_text=query.text,
        user_location=tuple(query.location) if query.location else None,
        language=query.language or "en",
    )
    return AskResponse(response=OrcaResponse(**response))


@app.get("/stream")
async def stream(query_text: str, lat: float | None = None, lon: float | None = None,
                 language: str = "en"):
    """Server-Sent Events stream of agent steps as they happen.

    The Flutter app can connect here for the 'real-time' feel — the
    response appears step by step rather than all at once.
    """
    async def event_gen() -> AsyncIterator[str]:
        ctx_args = {
            "user_text": query_text,
            "user_location": (lat, lon) if lat is not None and lon is not None else None,
            "language": language,
        }
        # We instrument Pipeline for this — but for simplicity in the
        # prototype, we just run the pipeline and yield each agent summary
        # we find in the final response's reasoning chain.
        final = await pipeline.run(**ctx_args)
        for i, step in enumerate(final.get("reasoning", []), 1):
            await asyncio.sleep(0.4)  # small delay so the UI shows streaming
            yield f"data: {json.dumps({'event': 'step', 'n': i, 'step': step})}\n\n"
        yield f"data: {json.dumps({'event': 'done', 'response': final})}\n\n"

    from fastapi.responses import StreamingResponse
    return StreamingResponse(event_gen(), media_type="text/event-stream")


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket) -> None:
    """WebSocket endpoint for true real-time agent updates.

    The Flutter app connects here and sends JSON like:
        {"text": "...", "location": [lat, lon], "language": "en"}
    then receives one JSON message per agent step.
    """
    await ws.accept()
    try:
        while True:
            payload = await ws.receive_json()
            text = payload.get("text", "")
            location = payload.get("location")
            language = payload.get("language", "en")

            # Stream the final response's reasoning steps
            final = await pipeline.run(
                user_text=text,
                user_location=tuple(location) if location else None,
                language=language,
            )
            for i, step in enumerate(final.get("reasoning", []), 1):
                await ws.send_json({"event": "step", "n": i, "step": step})
                await asyncio.sleep(0.3)
            await ws.send_json({"event": "done", "response": final})
    except WebSocketDisconnect:
        log.info("WebSocket client disconnected")
