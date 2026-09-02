"""Planner agent — the brain of ORCA.

The Planner looks at the user's natural-language query and decides:
  1. What *intent* it expresses (PFZ, safety, route, biology, geofence, weather)
  2. Which specialist agents to invoke, in what order
  3. Any extra parameters to extract (locations, dates, vessel type, etc.)

We deliberately use a hand-crafted rule-based classifier instead of an LLM.
Reasons:
  * Hackathon-friendly: no API key, fully offline, deterministic.
  * Judges can read every line and see the exact logic.
  * Easy to add new intents: just edit the keyword maps below.

The structure here is the same one a real LLM-based planner would produce,
just with a tiny rules engine instead of a 70B-parameter model.
"""
from __future__ import annotations

import re
from typing import Any

from .base import AgentContext, AgentResult, BaseAgent


# Keyword maps: intent -> list of (regex, weight). Highest weighted match wins.
# Add new keywords here as you discover them in real user queries.
INTENT_KEYWORDS: dict[str, list[tuple[str, float]]] = {
    "pfz": [
        (r"\bpfz\b", 1.0),
        (r"potential\s+fish", 1.0),
        (r"where.*fish", 0.8),
        (r"best.*fish", 0.7),
        (r"fish(ing)?\s+zone", 1.0),
        (r"fish\s+productivity", 0.7),
        # Hindi
        (r"मछली", 0.9),
        (r"मछली.*मिल", 1.0),       # where to find fish
        (r"मछली.*कहाँ", 1.0),
        (r"मछली.*कहा", 1.0),
        (r"फिशिंग", 0.9),
        (r"शिकार", 0.6),
        # Tamil
        (r"மீன்", 0.9),
        (r"மீன்.*எங்கே", 1.0),
        (r"மீன்பிடி", 1.0),
    ],
    "safety": [
        (r"\bsafe\b", 1.0),
        (r"safety", 0.9),
        (r"\brisks?\b", 0.8),
        (r"danger", 0.9),
        (r"ventur.*sea", 0.7),
        (r"go out", 0.6),
        (r"go fishing", 0.6),
        # Hindi
        (r"सुरक्ष", 1.0),
        (r"सुरक्षित", 1.0),
        (r"खतर", 0.9),
        (r"कल.*समुद्र", 0.8),
        (r"समुद्र.*जा", 0.7),
        # Tamil
        (r"பாதுகாப்பு", 1.0),
        (r"பாதுக", 0.8),
        (r"ஆபத்து", 0.9),
    ],
    "weather": [
        (r"weather", 1.0),
        (r"forecast", 0.9),
        (r"rain", 0.7),
        (r"wind", 0.7),
        (r"storm", 0.9),
        (r"cyclone", 1.0),
        # Hindi
        (r"मौसम", 0.9),
        (r"बारिश", 0.7),
        (r"तूफान", 1.0),
        # Tamil
        (r"வானிலை", 1.0),
        (r"மழை", 0.7),
    ],
    "route": [
        (r"\broute\b", 1.0),
        (r"navigation", 0.9),
        (r"path", 0.7),
        (r"from\s+.+\s+to\s+", 0.8),
        (r"routemap", 1.0),
        # Hindi
        (r"रास्ता", 0.9),
        (r"मार्ग", 0.9),
        # Tamil
        (r"வழி", 0.9),
    ],
    "geofence": [
        (r"border", 0.9),
        (r"boundary", 0.9),
        (r"restricted", 1.0),
        (r"protected\s+area", 1.0),
        (r"mpa", 0.9),
        (r"marine\s+protected", 1.0),
        (r"avoid", 0.6),
        # Hindi
        (r"सीमा", 0.9),
        (r"प्रतिबंध", 1.0),
        # Tamil
        (r"எல்லை", 0.9),
    ],
    "biology": [
        (r"why.*fish.*decline", 1.0),
        (r"productivity", 0.7),
        (r"chlorophyll", 1.0),
        (r"biodiversity", 1.0),
        (r"ecosystem", 0.9),
    ],
}


class PlannerAgent(BaseAgent):
    name = "planner"

    async def run(self, ctx: AgentContext) -> AgentResult:
        text = ctx.user_text.lower()
        scores: dict[str, float] = {}

        for intent, patterns in INTENT_KEYWORDS.items():
            for pattern, weight in patterns:
                if re.search(pattern, text):
                    scores[intent] = scores.get(intent, 0.0) + weight

        if not scores:
            intent = "unknown"
            agents_to_call = ["weather"]  # Always run weather for any marine query
            confidence = 0.3
        else:
            intent = max(scores, key=scores.get)
            confidence = min(1.0, scores[intent] / 2.0)

            # Decide which specialist agents to invoke based on intent.
            # This is the orchestration policy — feel free to tweak.
            agent_map: dict[str, list[str]] = {
                "pfz": ["weather", "ocean", "gis", "reasoner"],
                "safety": ["weather", "ocean", "gis", "risk", "reasoner"],
                "weather": ["weather", "reasoner"],
                "route": ["weather", "ocean", "gis", "risk", "reasoner"],
                "geofence": ["gis", "reasoner"],
                "biology": ["ocean", "gis", "reasoner"],
                "unknown": ["weather", "reasoner"],
            }
            agents_to_call = agent_map.get(intent, ["weather", "reasoner"])

        return AgentResult(
            agent_name=self.name,
            summary=f"Detected intent: {intent} (confidence {confidence:.2f}). "
                    f"Will call: {', '.join(agents_to_call)}",
            confidence=confidence,
            data_sources=["rule-based intent classifier"],
            payload={"intent": intent, "agents_to_call": agents_to_call},
        )
