"""Base classes for all ORCA agents.

Every agent is a small, testable unit. Each one takes some context, does its
work, and returns a structured `AgentResult`. The Planner orchestrates which
agents run; the Reasoner combines their outputs.
"""
from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any


@dataclass
class AgentContext:
    """Shared state passed between agents in one query."""

    user_text: str
    user_location: tuple[float, float] | None = None
    language: str = "en"
    # Free-form scratchpad agents can read/write
    scratch: dict[str, Any] = field(default_factory=dict)


@dataclass
class AgentResult:
    """What an agent returns after doing its work."""

    agent_name: str
    summary: str
    confidence: float = 0.5
    data_sources: list[str] = field(default_factory=list)
    payload: dict[str, Any] = field(default_factory=dict)
    duration_ms: int = 0


class BaseAgent(ABC):
    """Every specialist agent inherits from this and implements `run`."""

    name: str = "base"

    @abstractmethod
    async def run(self, ctx: AgentContext) -> AgentResult: ...

    async def timed_run(self, ctx: AgentContext) -> AgentResult:
        """Helper that times the agent and returns a result with duration."""
        start = time.perf_counter()
        try:
            result = await self.run(ctx)
        except Exception as exc:  # noqa: BLE001 - we want to surface errors
            return AgentResult(
                agent_name=self.name,
                summary=f"Agent failed: {exc!s}",
                confidence=0.0,
                duration_ms=int((time.perf_counter() - start) * 1000),
            )
        result.duration_ms = int((time.perf_counter() - start) * 1000)
        return result
