"""Agent registry and orchestrator.

The orchestrator (Pipeline class) is the only thing main.py needs to call.
It runs the Planner, then the agents the planner chose, then the Reasoner.
"""
from __future__ import annotations

import logging
from typing import Any

from .base import AgentContext, AgentResult
from .gis_agent import GISAgent
from .ocean_agent import OceanAgent
from .planner import PlannerAgent
from .reasoner import ReasonerAgent
from .risk_agent import RiskAgent
from .weather_agent import WeatherAgent

log = logging.getLogger(__name__)


# A registry: name -> instance. Adding a new agent is one line here.
AGENTS: dict[str, Any] = {
    "planner": PlannerAgent(),
    "weather": WeatherAgent(),
    "ocean": OceanAgent(),
    "gis": GISAgent(),
    "risk": RiskAgent(),
    "reasoner": ReasonerAgent(),
}


class Pipeline:
    """Runs the planner then the chosen agents then the reasoner.

    The Pipeline is the only thing the API layer needs to know about.
    Each agent writes its result into `ctx.scratch` so downstream agents
    can read it. This is the "shared working memory" pattern that real
    agentic systems use.
    """

    def __init__(self, agents: dict[str, Any] | None = None) -> None:
        self.agents = agents or AGENTS

    async def run(
        self,
        user_text: str,
        user_location: tuple[float, float] | None = None,
        language: str = "en",
    ) -> dict:
        ctx = AgentContext(
            user_text=user_text,
            user_location=user_location,
            language=language,
        )

        # Step 1: Planner
        planner_result = await self.agents["planner"].timed_run(ctx)
        ctx.scratch["planner"] = _result_to_dict(planner_result)

        chosen = planner_result.payload.get("agents_to_call", ["reasoner"])
        # Always make sure reasoner runs last
        if "reasoner" in chosen:
            chosen.remove("reasoner")
        chosen.append("reasoner")

        # Step 2: run the chosen agents in order, writing each into scratch
        for name in chosen:
            if name == "planner":
                continue
            if name not in self.agents:
                log.warning("Unknown agent requested: %s", name)
                continue
            result = await self.agents[name].timed_run(ctx)
            ctx.scratch[name] = _result_to_dict(result)

        # Step 3: return the reasoner's payload (the full OrcaResponse)
        reasoner_result = ctx.scratch.get("reasoner", {})
        return reasoner_result.get("payload", {}).get("response", {})


def _result_to_dict(result: AgentResult) -> dict:
    return {
        "agent_name": result.agent_name,
        "summary": result.summary,
        "confidence": result.confidence,
        "data_sources": result.data_sources,
        "payload": result.payload,
        "duration_ms": result.duration_ms,
    }
