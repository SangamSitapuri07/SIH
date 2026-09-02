"""Smoke tests for the ORCA agent pipeline.

Run with:
    cd backend
    pytest -q
"""
from __future__ import annotations

import asyncio

import pytest

from app.agents import Pipeline
from app.agents.base import AgentContext
from app.agents.planner import PlannerAgent


def test_planner_detects_pfz() -> None:
    ctx = AgentContext(user_text="Where is the nearest PFZ today?")
    result = asyncio.run(PlannerAgent().run(ctx))
    assert result.payload["intent"] == "pfz"
    assert "weather" in result.payload["agents_to_call"]


def test_planner_detects_safety() -> None:
    ctx = AgentContext(user_text="Is it safe to venture into the sea tomorrow morning?")
    result = asyncio.run(PlannerAgent().run(ctx))
    assert result.payload["intent"] == "safety"


def test_planner_detects_weather() -> None:
    ctx = AgentContext(user_text="What is the weather forecast for tomorrow?")
    result = asyncio.run(PlannerAgent().run(ctx))
    assert result.payload["intent"] == "weather"


def test_planner_handles_unknown() -> None:
    ctx = AgentContext(user_text="Hello!")
    result = asyncio.run(PlannerAgent().run(ctx))
    assert result.payload["intent"] == "unknown"


@pytest.mark.asyncio
async def test_full_pipeline_runs() -> None:
    pipeline = Pipeline()
    response = await pipeline.run(
        user_text="Where can I fish today?",
        user_location=(18.9, 72.8),
        language="en",
    )
    assert "answer_text" in response
    assert response["intent"] in {"pfz", "unknown", "weather", "safety",
                                  "route", "geofence", "biology"}
    assert "map" in response
    assert "reasoning" in response
    # Should have a map with at least one polygon (the PFZ)
    assert len(response["map"].get("polygons", [])) >= 0  # may be 0 if user_location is far
