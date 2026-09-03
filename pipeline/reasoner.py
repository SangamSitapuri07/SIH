"""ORCA Reasoning & Orchestration Agent 🧠

Coordinates all agents. Combines their findings and resolves conflicts.
Generates the final explainable marine ecosystem insight.

This is the "brain" of ORCA. It:
  1. Receives a ZoneSnapshot
  2. Runs all 6 implemented agents in dependency order
  3. Aggregates risks (max of all agent risks)
  4. Synthesizes a final answer with source attribution
  5. Returns explainable text + structured findings

Usage:
    from pipeline.orca_data import zone_snapshot
    from pipeline.reasoner import reason

    snap = zone_snapshot(19.0, 72.8, "2026-08-15")
    insight = reason(snap)
    # Returns: {
    #   "zone": {...snapshot...},
    #   "agents": [<6 agent results>],
    #   "overall_risk": "low" | "moderate" | "high" | "critical",
    #   "summary": "Human-readable explanation",
    #   "recommendation": "Should a fisherman go out today?",
    # }
"""
from __future__ import annotations

from typing import Any

from pipeline.agents import run_all


RISK_ORDER = {"low": 0, "unknown": 1, "moderate": 2, "high": 3, "critical": 4}


def _max_risk(risks: list[str]) -> str:
    if not risks:
        return "unknown"
    return max(risks, key=lambda r: RISK_ORDER.get(r, 0))


def reason(
    snap: dict[str, Any],
    include_agents: list[str] | None = None,
) -> dict[str, Any]:
    """Run the full multi-agent reasoning on a ZoneSnapshot.

    Returns a dict with all agent results, an aggregated risk level,
    a human-readable summary, and an actionable recommendation.
    """
    agents = run_all(snap, include=include_agents)

    # Aggregate risks
    risks = [a.get("risk_level", "unknown") for a in agents]
    overall = _max_risk(risks)

    # Get key agent signals
    sat = next((a for a in agents if a["agent"] == "satellite"), {})
    fish = next((a for a in agents if a["agent"] == "fisheries"), {})
    ocean = next((a for a in agents if a["agent"] == "ocean"), {})
    eco = next((a for a in agents if a["agent"] == "marine_ecology"), {})
    risk_agent = next((a for a in agents if a["agent"] == "marine_risk"), {})

    # Build summary
    parts = []
    if fish.get("verdict") in ("highly_recommended", "recommended"):
        parts.append(f"🟢 PFZ verdict: {fish['verdict'].replace('_', ' ').title()}")
    elif fish.get("verdict") == "not_recommended":
        parts.append(f"🔴 PFZ verdict: Not recommended")
    elif fish.get("verdict") == "neutral":
        parts.append(f"🟡 PFZ verdict: Neutral")

    if "pfz_score" in snap and snap["pfz_score"] is not None:
        parts.append(f"Composite PFZ score: {snap['pfz_score']:.2f}/1.0")

    if risk_agent.get("summary"):
        parts.append(risk_agent["summary"])

    if ocean.get("summary") and ocean["summary"] != "No ocean data available for this zone.":
        parts.append(f"Ocean: {ocean['summary']}")

    if sat.get("summary") and "unavailable" not in sat["summary"]:
        parts.append(f"Satellite: {sat['summary']}")

    summary = " | ".join(parts) if parts else "Insufficient data for recommendation."

    # Recommendation
    if overall == "critical":
        rec = "🛑 STAY ON LAND. Critical marine conditions. No fishing recommended."
    elif overall == "high":
        rec = "⚠️ HIGH RISK. Only experienced crew with appropriate vessels should consider limited activity close to shore."
    elif overall == "moderate":
        rec = "🟡 MODERATE. Conditions are workable but watch for changing weather."
    elif overall == "low":
        if fish.get("verdict") in ("highly_recommended", "recommended"):
            rec = "✅ GOOD CONDITIONS. Suitable for fishing; chlorophyll and SST favorable."
        else:
            rec = "✅ Conditions OK but no strong fishing signal — try known grounds."
    else:
        rec = "❓ Insufficient data for a clear recommendation."

    return {
        "zone": {
            "lat": snap.get("lat"),
            "lon": snap.get("lon"),
            "date": snap.get("date"),
        },
        "agents": agents,
        "overall_risk": overall,
        "summary": summary,
        "recommendation": rec,
        "data_sources_used": snap.get("data_sources_used", []),
        "data_sources_failed": snap.get("data_sources_failed", []),
        "fetched_at": snap.get("fetched_at"),
    }
