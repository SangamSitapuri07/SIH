"""Agent 7: Marine Risk 🚨

Combines ocean and weather conditions to generate
marine risk levels: Low / Moderate / High / Critical.

This is a "vessel safety" agent — it asks: "should a fisherman
go out today in this zone?"

Inputs: ZoneSnapshot + other agent results
Outputs: dict of findings + overall risk level
"""
from __future__ import annotations

from typing import Any


# Risk weights
WEIGHTS = {
    "wave_high": 5,
    "wave_caution": 1,
    "sst_extreme": 1,
    "stale_data": 1,
    "low_source_coverage": 1,
    "all_sources_failed": 5,
    "bloom_risk": 2,
}

RISK_THRESHOLDS = {
    0: "low",
    2: "moderate",
    4: "high",
    8: "critical",
}


def _score_to_risk(score: int) -> str:
    if score >= 8:
        return "critical"
    if score >= 4:
        return "high"
    if score >= 2:
        return "moderate"
    return "low"


def analyze(snap: dict[str, Any], agent_results: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []
    score = 0
    agent_results = agent_results or []

    # Aggregate wave risk from ocean agent
    ocean_result = next((a for a in agent_results if a.get("agent") == "ocean"), {})
    for f in ocean_result.get("findings", []):
        if f["type"] == "wave_warning_high":
            score += 5
            findings.append(f)
        elif f["type"] == "wave_caution":
            score += 1
            findings.append(f)

    # Aggregate validation warnings
    val_result = next((a for a in agent_results if a.get("agent") == "validation"), {})
    for f in val_result.get("findings", []):
        if f["severity"] == "error":
            score += 2
            findings.append({
                "type": f["type"],
                "severity": "high",
                "value": f.get("value"),
                "msg": "Data error: " + f["msg"],
            })
        elif f["type"] == "low_source_coverage":
            score += 1
            findings.append(f)

    # Aggregate ecology warnings
    eco_result = next((a for a in agent_results if a.get("agent") == "marine_ecology"), {})
    for f in eco_result.get("findings", []):
        if f["type"] == "bloom_risk":
            score += 2
            findings.append(f)

    risk = _score_to_risk(score)
    color = {
        "low": "🟢",
        "moderate": "🟡",
        "high": "🟠",
        "critical": "🔴",
    }[risk]

    if risk == "critical":
        summary = f"{color} CRITICAL risk — DO NOT venture out. Multiple severe warnings active."
    elif risk == "high":
        summary = f"{color} HIGH risk — only experienced crew with appropriate vessels should consider going out."
    elif risk == "moderate":
        summary = f"{color} MODERATE risk — proceed with caution, monitor conditions."
    elif risk == "low":
        summary = f"{color} LOW risk — conditions acceptable for normal operations."
    else:
        summary = "Risk level unknown — insufficient data."

    return {
        "agent": "marine_risk",
        "findings": findings,
        "summary": summary,
        "risk_level": risk,
        "risk_score": score,
    }
