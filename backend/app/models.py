"""Pydantic request/response schemas for the ORCA API.

These are the contracts the Flutter app talks against. Keep them stable;
treat changes as breaking.
"""
from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


# --- User query ---------------------------------------------------------------


class UserQuery(BaseModel):
    """A natural-language question from the Flutter app."""

    text: str = Field(..., description="Question in any supported language")
    user_id: str | None = Field(
        default=None, description="Optional user identifier for personalization"
    )
    location: tuple[float, float] | None = Field(
        default=None,
        description="Optional (lat, lon) of the user, e.g. fishing village",
    )
    language: str | None = Field(
        default=None,
        description="Optional ISO 639-1 language code, e.g. 'en', 'hi', 'ta'",
    )


# --- Map payloads -------------------------------------------------------------


class MapPoint(BaseModel):
    lat: float
    lon: float
    label: str | None = None
    color: str | None = None  # hex, e.g. "#22c55e"
    metadata: dict[str, Any] = Field(default_factory=dict)


class MapPolygon(BaseModel):
    """A polygon drawn on the map (e.g. PFZ zone, geofence)."""

    name: str
    # Sequence of (lat, lon) pairs forming a closed ring
    coordinates: list[tuple[float, float]]
    color: str = "#22c55e"
    fill: bool = True
    metadata: dict[str, Any] = Field(default_factory=dict)


class MapPayload(BaseModel):
    points: list[MapPoint] = Field(default_factory=list)
    polygons: list[MapPolygon] = Field(default_factory=list)
    center: tuple[float, float] = (15.5, 73.8)  # default to west coast of India
    zoom: float = 6.0


# --- Agent trace --------------------------------------------------------------


class AgentStep(BaseModel):
    """One step in the agent reasoning chain, for explainability."""

    agent: str
    intent: str | None = None
    summary: str
    data_sources: list[str] = Field(default_factory=list)
    duration_ms: int = 0


# --- Response -----------------------------------------------------------------


class OrcaResponse(BaseModel):
    """Final synthesized answer returned to the Flutter app."""

    answer_text: str = Field(..., description="Human-readable explanation")
    language: str = "en"
    intent: Literal[
        "pfz",
        "safety",
        "route",
        "biology",
        "geofence",
        "weather",
        "unknown",
    ] = "unknown"
    confidence: float = Field(ge=0.0, le=1.0, default=0.5)
    map: MapPayload = Field(default_factory=MapPayload)
    alerts: list[str] = Field(default_factory=list)
    reasoning: list[AgentStep] = Field(default_factory=list)
    safety_score: float | None = Field(
        default=None, ge=0.0, le=1.0,
        description="0 = very unsafe, 1 = very safe",
    )
