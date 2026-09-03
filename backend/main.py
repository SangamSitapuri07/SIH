"""ORCA FastAPI backend — exposes the unified data layer + 6 agents
over HTTP for the Next.js frontend.

Endpoints:
  GET  /                       health check
  GET  /api/v1/health          service health
  GET  /api/v1/zone            ZoneSnapshot for one lat/lon
  GET  /api/v1/grid            grid of ZoneSnapshots for a bbox
  GET  /api/v1/reason          full multi-agent reasoning for one zone
  GET  /api/v1/datasets        list of data sources + status
  GET  /api/v1/zones           list of curated demo zones

Run locally:
  cd /home/user/SIH
  python -m uvicorn backend.main:app --reload --port 8000

Then the Next.js dev server proxies /api/* to it (see web/next.config.mjs).
"""
from __future__ import annotations

import os
import sys
import traceback
from datetime import date as date_cls
from pathlib import Path
from typing import Any


# ── Auto-load .env file (if it exists) ──
# Lets the user put GFW_API_TOKEN / MOSDAC_USERNAME / MOSDAC_PASSWORD
# in a .env file once and have the backend pick them up automatically.
# OS env vars always take precedence over .env (so $env:FOO = "x"
# in PowerShell still wins).
def _load_dotenv(path: Path) -> None:
    if not path.exists():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        v = v.strip().strip('"').strip("'")
        if k and k not in os.environ:
            os.environ[k] = v


PROJECT_ROOT = Path(__file__).resolve().parent.parent
_load_dotenv(PROJECT_ROOT / ".env")
# Also try the parent directory (some users put .env next to the venv)
_load_dotenv(PROJECT_ROOT.parent / ".env")

if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

from pipeline.orca_data import zone_snapshot, grid_snapshot, INDIAN_COASTAL_ZONES
from pipeline.reasoner import reason


app = FastAPI(
    title="ORCA — Marine Intelligence API",
    description="Marine EcOsystem Reasoning with Collaborative Agents · SIH 2026 PS 176",
    version="0.1.0",
)

# CORS for the Next.js dev server (and any other local frontend)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
        "http://localhost:3001",
        "http://127.0.0.1:3001",
        # The Arena preview proxy uses different hostnames; in dev we
        # allow any origin. Tighten this in production.
        "*",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Health & metadata ──

@app.get("/")
def root() -> dict[str, Any]:
    return {
        "service": "ORCA — Marine Intelligence API",
        "version": "0.1.0",
        "sih_problem_statement": "SIH 26176 (PS 176)",
        "endpoints": [
            "/api/v1/health",
            "/api/v1/zone",
            "/api/v1/grid",
            "/api/v1/reason",
            "/api/v1/datasets",
            "/api/v1/zones",
        ],
    }


@app.get("/api/v1/health")
def health() -> dict[str, Any]:
    gfw_token_set = bool(os.environ.get("GFW_API_TOKEN"))
    mosdac_user = os.environ.get("MOSDAC_USERNAME", "")
    mosdac_pwd = os.environ.get("MOSDAC_PASSWORD", "")
    mosdac_set = bool(mosdac_user and mosdac_pwd)
    return {
        "status": "ok",
        "version": "0.1.0",
        "credentials": {
            "gfw_token_configured": gfw_token_set,
            "mosdac_configured": mosdac_set,
        },
        "data_sources": {
            "openmeteo": "live (no key)",
            "noaa_erddap": "live (no key)",
            "esa_occci": "live (no key)",
            "gfw": "live" if gfw_token_set else "needs GFW_API_TOKEN env var or .env file",
            "incois_las": "server unreliable — fallback only",
            "mosdac": "live" if mosdac_set else "needs MOSDAC_USERNAME + MOSDAC_PASSWORD",
        },
    }


@app.get("/api/v1/datasets")
def datasets() -> dict[str, Any]:
    """List all data sources with metadata."""
    return {
        "sources": [
            {
                "id": "noaa_erddap_dineof",
                "name": "NOAA ERDDAP VIIRS DINEOF (chlorophyll)",
                "kind": "satellite",
                "cost": "free",
                "auth": "none",
                "coverage": "global, 0.025° daily, 3-day delay",
                "url": "https://coastwatch.noaa.gov/erddap/griddap/noaacwNPPN20VIIRSDINEOFDaily",
            },
            {
                "id": "openmeteo_marine",
                "name": "Open-Meteo Marine (SST + waves)",
                "kind": "weather_model",
                "cost": "free",
                "auth": "none",
                "coverage": "global, 0.08° daily, MeteoFrance model",
                "url": "https://marine-api.open-meteo.com/v1/marine",
            },
            {
                "id": "gfw_ais",
                "name": "Global Fishing Watch (AIS)",
                "kind": "vessel_tracking",
                "cost": "free with token",
                "auth": "GFW_API_TOKEN env var",
                "coverage": "global, 0.01° daily, 2012-present",
                "url": "https://gateway.api.globalfishingwatch.org/v3/4wings/report",
            },
            {
                "id": "incois_las",
                "name": "INCOIS LAS (chlorophyll backup)",
                "kind": "satellite",
                "cost": "free",
                "auth": "none",
                "coverage": "Indian Ocean, OCM-2",
                "url": "http://las.incois.gov.in/thredds/",
            },
            {
                "id": "mosdac_ocm3",
                "name": "MOSDAC OCM-3 L4 (🇮🇳 Indian daily chlorophyll)",
                "kind": "satellite",
                "cost": "free with credentials",
                "auth": "MOSDAC_USERNAME / MOSDAC_PASSWORD env vars",
                "coverage": "Indian Ocean, 1 km daily",
                "url": "https://www.mosdac.gov.in",
            },
        ],
        "agents": [
            {"id": "ocean", "name": "Ocean Analysis 🌊", "implemented": True},
            {"id": "satellite", "name": "Satellite Analysis 🛰️", "implemented": True},
            {"id": "weather", "name": "Weather & Hazard 🌦️", "implemented": True},
            {"id": "gis", "name": "GIS & Spatial 🗺️", "implemented": True},
            {"id": "marine_ecology", "name": "Marine Ecology 🐟", "implemented": True},
            {"id": "fisheries", "name": "Fisheries / PFZ 🎣", "implemented": True},
            {"id": "marine_risk", "name": "Marine Risk 🚨", "implemented": True},
            {"id": "anomaly", "name": "Anomaly Detection 🔍", "implemented": True},
            {"id": "validation", "name": "Data Validation ✅", "implemented": True},
            {"id": "orca_reasoning", "name": "ORCA Reasoning 🧠 (in reasoner.py)", "implemented": True},
        ],
    }


# ── Indian coastal zones ──
# These are real lat/lon coordinates for 8 Indian coastal zones. They
# are NOT dummy data — each click triggers a real FastAPI → NOAA ERDDAP
# → Open-Meteo → GFW → INCOIS call for that exact point. The 8 zones
# are just a UI convenience so the user has a starting point; you can
# also call /api/v1/zone or /api/v1/reason with any lat/lon.

@app.get("/api/v1/zones")
def list_zones() -> dict[str, Any]:
    """Real coordinates for 8 Indian coastal zones."""
    return {"zones": INDIAN_COASTAL_ZONES, "count": len(INDIAN_COASTAL_ZONES)}


# ── Core endpoints ──

@app.get("/api/v1/zone")
def get_zone(
    lat: float = Query(..., ge=-90, le=90, description="Latitude"),
    lon: float = Query(..., ge=-180, le=180, description="Longitude"),
    date: str | None = Query(None, description="YYYY-MM-DD (default: today)"),
    radius_deg: float = Query(0.5, ge=0.05, le=5.0, description="Bbox half-width"),
    include_gfw: bool = Query(True, description="Include GFW fishing data"),
) -> dict[str, Any]:
    """Single ZoneSnapshot: chlorophyll, SST, waves, fishing."""
    if date is not None:
        try:
            date_cls.fromisoformat(date)
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Invalid date: {date}, expected YYYY-MM-DD")
    try:
        return zone_snapshot(lat, lon, date, radius_deg=radius_deg, include_gfw=include_gfw)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"zone_snapshot failed: {type(e).__name__}: {e}\n{traceback.format_exc()}")


@app.get("/api/v1/grid")
def get_grid(
    min_lat: float = Query(...),
    max_lat: float = Query(...),
    min_lon: float = Query(...),
    max_lon: float = Query(...),
    step_deg: float = Query(1.0, ge=0.1, le=5.0),
    date: str | None = Query(None),
    include_gfw: bool = Query(False, description="GFW off by default for grids (expensive)"),
) -> dict[str, Any]:
    """Grid of ZoneSnapshots for a bbox. Use for map overlays."""
    if min_lat >= max_lat:
        raise HTTPException(status_code=400, detail="min_lat must be < max_lat")
    if min_lon >= max_lon:
        raise HTTPException(status_code=400, detail="min_lon must be < max_lon")
    # Warn on overly large grids
    n_pts = ((max_lat - min_lat) / step_deg + 1) * ((max_lon - min_lon) / step_deg + 1)
    if n_pts > 100 and include_gfw:
        raise HTTPException(
            status_code=400,
            detail=f"Grid too large for GFW ({int(n_pts)} points). Use include_gfw=false or smaller bbox.",
        )
    try:
        return grid_snapshot(min_lat, max_lat, min_lon, max_lon, date, step_deg, include_gfw)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"grid_snapshot failed: {type(e).__name__}: {e}\n{traceback.format_exc()}")


@app.get("/api/v1/reason")
def get_reason(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    date: str | None = Query(None, description="YYYY-MM-DD (default: today)"),
    include_gfw: bool = Query(True),
    agents: str | None = Query(None, description="Comma-separated agent IDs (default: all)"),
) -> dict[str, Any]:
    """Full multi-agent reasoning: snapshot + 6 agent results + final insight."""
    if date is not None:
        try:
            date_cls.fromisoformat(date)
        except ValueError:
            raise HTTPException(status_code=400, detail=f"Invalid date: {date}, expected YYYY-MM-DD")
    try:
        snap = zone_snapshot(lat, lon, date, include_gfw=include_gfw)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"zone_snapshot failed: {type(e).__name__}: {e}")

    agent_list = None
    if agents:
        agent_list = [a.strip() for a in agents.split(",") if a.strip()]

    try:
        insight = reason(snap, include_agents=agent_list)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=500, detail=f"reason failed: {type(e).__name__}: {e}\n{traceback.format_exc()}")

    # Attach the raw snapshot for full transparency
    insight["snapshot"] = snap
    return insight


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
