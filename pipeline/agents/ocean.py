"""Agent 1: Ocean Analysis 🌊

Analyzes SST, waves, currents, swell from Open-Meteo Marine API data.
Detects changes and anomalies in ocean conditions.

Inputs: ZoneSnapshot (from orca_data)
Outputs: dict of findings:
  {
    "agent": "ocean",
    "findings": [
      {"type": "sst_optimal", "severity": "info", "value": 29.0, "msg": "..."},
      {"type": "wave_warning", "severity": "warn", "value": 3.2, "msg": "..."},
      ...
    ],
    "summary": "SST within optimal range for pelagic fish; waves approaching small-craft caution.",
    "risk_level": "moderate",  # low | moderate | high | critical
  }
"""
from __future__ import annotations

from typing import Any


def analyze(snap: dict[str, Any]) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []

    sst_max = snap.get("sst_max")
    sst_min = snap.get("sst_min")
    sst_mean = snap.get("sst_mean")
    wave_max = snap.get("wave_max")
    wave_mean = snap.get("wave_mean")

    # SST analysis — pelagic fish (tuna, mackerel) prefer 24-29°C
    if sst_mean is not None:
        if 24 <= sst_mean <= 29:
            findings.append({
                "type": "sst_optimal",
                "severity": "good",
                "value": sst_mean,
                "msg": f"Mean SST {sst_mean}°C is in the optimal range for pelagic fish.",
            })
        elif 22 <= sst_mean <= 31:
            findings.append({
                "type": "sst_acceptable",
                "severity": "info",
                "value": sst_mean,
                "msg": f"Mean SST {sst_mean}°C is acceptable but not optimal.",
            })
        elif sst_mean < 22:
            findings.append({
                "type": "sst_cold",
                "severity": "warn",
                "value": sst_mean,
                "msg": f"Mean SST {sst_mean}°C is cold — likely upwelling, may reduce surface catch.",
            })
        else:  # > 31
            findings.append({
                "type": "sst_warm",
                "severity": "warn",
                "value": sst_mean,
                "msg": f"Mean SST {sst_mean}°C is warm — thermal stress, fish move deeper.",
            })

    # SST swing = frontal activity (good for fish aggregation)
    if sst_max is not None and sst_min is not None:
        sst_swing = sst_max - sst_min
        if sst_swing >= 2.0:
            findings.append({
                "type": "sst_front",
                "severity": "good",
                "value": sst_swing,
                "msg": f"SST swing {sst_swing:.1f}°C — strong thermal front, fish aggregate at boundaries.",
            })

    # Wave analysis — small-craft advisory thresholds (IMD standard)
    if wave_max is not None:
        if wave_max >= 4.0:
            findings.append({
                "type": "wave_warning_high",
                "severity": "high",
                "value": wave_max,
                "msg": f"Max wave height {wave_max}m — HIGH sea state, small craft should not venture out.",
            })
        elif wave_max >= 2.5:
            findings.append({
                "type": "wave_caution",
                "severity": "warn",
                "value": wave_max,
                "msg": f"Max wave height {wave_max}m — rough seas, exercise caution.",
            })
        else:
            findings.append({
                "type": "wave_calm",
                "severity": "good",
                "value": wave_max,
                "msg": f"Max wave height {wave_max}m — calm, safe for all vessel classes.",
            })

    # Risk level
    severities = [f["severity"] for f in findings]
    if "high" in severities or "critical" in severities:
        risk = "high"
    elif "warn" in severities:
        risk = "moderate"
    elif "good" in severities:
        risk = "low"
    else:
        risk = "unknown"

    # Summary
    if not findings:
        summary = "No ocean data available for this zone."
    else:
        n_good = sum(1 for f in findings if f["severity"] == "good")
        n_warn = sum(1 for f in findings if f["severity"] in ("warn", "high"))
        if n_warn > n_good:
            summary = f"Ocean conditions are concerning: {n_warn} warnings vs {n_good} positives."
        elif n_good > 0:
            summary = f"Ocean conditions are favorable: {n_good} positive signals."
        else:
            summary = "Ocean conditions are neutral."

    return {
        "agent": "ocean",
        "findings": findings,
        "summary": summary,
        "risk_level": risk,
    }
