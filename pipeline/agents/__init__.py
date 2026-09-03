"""Agent registry — maps agent name to its analyze() function.

All 9 functional agents (Ocean, Satellite, Weather, GIS, Fisheries,
Marine Ecology, Marine Risk, Anomaly, Data Validation) are in this
package. Agent 10 (ORCA Reasoning) is in pipeline/reasoner.py.

To add a new agent:
  1. Drop a file in this directory with a top-level `analyze(snap, ...)` function
  2. Register it in ALL_AGENTS below
"""
from .ocean import analyze as ocean_analyze
from .satellite import analyze as satellite_analyze
from .weather import analyze as weather_analyze
from .gis import analyze as gis_analyze
from .fisheries import analyze as fisheries_analyze
from .marine_ecology import analyze as marine_ecology_analyze
from .marine_risk import analyze as marine_risk_analyze
from .anomaly import analyze as anomaly_analyze
from .validation import analyze as validation_analyze


ALL_AGENTS = [
    ("ocean", ocean_analyze),
    ("satellite", satellite_analyze),
    ("weather", weather_analyze),
    ("gis", gis_analyze),
    ("fisheries", fisheries_analyze),
    ("marine_ecology", marine_ecology_analyze),
    ("marine_risk", marine_risk_analyze),
    ("anomaly", anomaly_analyze),
    ("validation", validation_analyze),
]


def run_all(snap: dict, include: list[str] | None = None) -> list[dict]:
    """Run the requested agents (or all by default) and return their results.

    Each agent gets the snapshot and (optionally) a list of previously-run
    agent results for cross-agent synthesis (ecology, risk).
    """
    results: list[dict] = []
    for name, fn in ALL_AGENTS:
        if include and name not in include:
            continue
        # Ecology and Risk want to see other agents' results
        if name in ("marine_ecology", "marine_risk"):
            res = fn(snap, agent_results=results)
        else:
            res = fn(snap)
        results.append(res)
    return results
