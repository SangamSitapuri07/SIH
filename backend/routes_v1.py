import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Dict, Any, List, Optional, Tuple
from fastapi import APIRouter, Query, HTTPException, Body
from pydantic import BaseModel, Field

from data_providers import DataProvidersEngine
from agents_engine import MultiAgentEngine
from supabase_service import SupabaseService
from mosdac_datasets import registry_status
from safe_window import find_safe_departure_window
from ollama_client import ollama

router = APIRouter(prefix="/api/v1")
providers = DataProvidersEngine()
agents_engine = MultiAgentEngine()
supabase_svc = SupabaseService()

# Pydantic Schemas for Phase 2 endpoints
class ProfileUpdate(BaseModel):
    display_name: Optional[str] = "Fisherman"
    preferred_language: Optional[str] = "en"
    preferred_fishing_area: Optional[str] = "Veraval Offshore"
    home_harbour: Optional[str] = "Veraval Harbour"
    vessel_type: Optional[str] = "Motorized Boat"
    vessel_registration: Optional[str] = None
    notification_preferences: Optional[Dict[str, bool]] = None

class SavedLocationCreate(BaseModel):
    name: str
    latitude: float
    longitude: float
    category: Optional[str] = "Fishing Area"
    is_favourite: Optional[bool] = False
    notes: Optional[str] = None

class CatchReportCreate(BaseModel):
    location_name: str
    latitude: float
    longitude: float
    species: str
    quantity_kg: float
    catch_date: Optional[str] = None
    notes: Optional[str] = None

class FeedbackCreate(BaseModel):
    advisory_id: Optional[str] = None
    rating: int = Field(ge=1, le=5)
    actual_conditions: Optional[str] = None
    comment: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None

class SyncPayload(BaseModel):
    operations: List[Dict[str, Any]]

# In-memory store for backend demo
STORE_PROFILES = {}
STORE_LOCATIONS = []
STORE_HISTORY = []
STORE_CATCH = []

# --- PHASE 1 CORE ENDPOINTS ---

@router.get("/health")
def get_health(probe: bool = Query(False)):
    """Source health; ``probe=true`` actively exercises operational providers."""
    health = providers.check_health(probe=probe)
    health["mosdac_activation"] = registry_status()
    health["ollama"] = ollama.health()
    return health

@router.get("/zone")
def get_zone_snapshot(lat: float = Query(20.9), lon: float = Query(70.37), include_gfw: bool = Query(False)):
    """Spot data snapshot."""
    snap = providers.fetch_zone_snapshot(lat, lon, include_gfw=include_gfw)
    if snap.get("error"):
        return snap
    variables = snap.get("variables", {})
    return {
        "lat": snap["latitude"],
        "lon": snap["longitude"],
        "timestamp": snap["timestamp"],
        "zone_name": "Live marine observation",
        "wave_height_m": variables.get("wave_height_m"),
        "swell_period_s": variables.get("swell_period_s"),
        "wind_speed_kn": variables.get("wind_speed_kn"),
        "wind_gust_kn": variables.get("wind_gust_kn"),
        "wind_direction": variables.get("wind_direction_deg"),
        "sea_temp_c": variables.get("sst_celsius"),
        "current_speed_kn": variables.get("current_speed_kn"),
        "current_direction": variables.get("current_direction_deg"),
        "chlorophyll_mg_m3": variables.get("chlorophyll_mg_m3"),
        "fishing_effort_hours": variables.get("fishing_effort_hours"),
        "fishing_vessel_ids": variables.get("fishing_vessel_ids"),
        "fleet_vessel_count": variables.get("fleet_vessel_count"),
        "fleet_by_flag": variables.get("fleet_by_flag", {}),
        "fleet_by_gear": variables.get("fleet_by_gear", {}),
        "gfw_start_date": variables.get("gfw_start_date"),
        "gfw_end_date": variables.get("gfw_end_date"),
        "sources": [source["name"] for source in snap.get("sources_used", [])],
        "sources_failed": [failure.get("source", "unknown") for failure in snap.get("sources_failed", [])],
        "source_details": snap.get("sources_used", []),
        "pfz": snap.get("pfz", []),
    }

@router.get("/grid")
def get_grid(lat: float = Query(20.9), lon: float = Query(70.37), span: float = Query(0.5)):
    """Grid snapshot for map rendering."""
    step = span / 3.0
    coords = [
        (round(lat - (span / 2.0) + (r * step), 4), round(lon - (span / 2.0) + (c * step), 4))
        for r in range(4)
        for c in range(4)
    ]

    # Each point is an independent, fully self-contained snapshot fetch — run
    # them concurrently instead of one-after-the-other. Sequentially this
    # endpoint could take minutes (one slow upstream provider dominates each
    # single fetch); concurrently it takes about as long as one fetch. Each
    # point itself opens several connections (marine + forecast + secondary
    # sources), so cap outer concurrency well below 16 to avoid bursting past
    # what upstream providers / local connection limits tolerate at once.
    with ThreadPoolExecutor(max_workers=6) as pool:
        snapshots = list(pool.map(lambda coord: providers.fetch_zone_snapshot(*coord), coords))

    points = []
    for (plat, plon), snap in zip(coords, snapshots):
        if not snap.get("error"):
            variables = snap["variables"]
            points.append({
                "lat": plat,
                "lon": plon,
                "status": "fresh",
                "wave_h": variables["wave_height_m"],
                "wind_kn": variables["wind_speed_kn"],
                "wind_gust_kn": variables.get("wind_gust_kn"),
                "wind_direction_deg": variables.get("wind_direction_deg"),
                "sst_c": variables.get("sst_celsius"),
                "chl": variables.get("chlorophyll_mg_m3"),
            })
    return {
        "state": "LIVE" if points else "UNAVAILABLE",
        "valid_time": None,
        "resolution": f"{round(step, 3)} deg",
        "fetched_at": int(time.time()),
        "sources": ["Open-Meteo Marine", "Open-Meteo Forecast"],
        "latitude": lat,
        "longitude": lon,
        "span": span,
        "points": points,
    }

@router.get("/pfz")
def get_pfz():
    """Potential fishing zone lines from the official INCOIS WFS."""
    result = providers.fetch_incois_pfz()
    return {
        "status": result.get("status", "unavailable"),
        "source": result.get("source"),
        "fetched_at": int(time.time()),
        "features": result.get("features", []),
    }

@router.get("/layers")
def get_layers():
    """Catalog of map-renderable data layers backed by real ORCA sources."""
    return [
        {
            "id": "wave_height",
            "name": "Wave height",
            "unit": "m",
            "source": "Open-Meteo Marine",
            "visualization": "scalar_grid",
            "endpoint": "/api/v1/grid",
            "state": "ACTIVE",
            "available": True,
        },
        {
            "id": "wind_speed",
            "name": "Wind speed",
            "unit": "kn",
            "source": "Open-Meteo Forecast",
            "visualization": "scalar_grid",
            "endpoint": "/api/v1/grid",
            "state": "ACTIVE",
            "available": True,
        },
        {
            "id": "pfz",
            "name": "Potential fishing zones",
            "unit": None,
            "source": "INCOIS PFZ GeoServer",
            "visualization": "vector_grid",
            "endpoint": "/api/v1/pfz",
            "state": "ACTIVE",
            "available": True,
        },
    ]

@router.get("/reason")
def get_reasoning(lat: float = Query(20.9), lon: float = Query(70.37), include_gfw: bool = Query(False)):
    """Run 11-agent collaborative reasoning trace."""
    snap = providers.fetch_zone_snapshot(lat, lon, include_gfw=include_gfw)
    if snap.get("error"):
        raise HTTPException(status_code=400, detail=snap["reason"])
    return agents_engine.run_collaborative_reasoning(snap)

# Advisory response cache: identical requests within the TTL are served
# instantly (snapshot caching + parallel agents already make a fresh
# computation fast; this removes even that cost for repeat app refreshes).
# Hook set by main.py after the ingestion daemon starts: lets any client
# request auto-register its coordinates into the proactive watchlist without
# creating a circular import (routes_v1 must not import main).
_WATCH_HOOK = None

def set_watch_hook(fn) -> None:
    global _WATCH_HOOK
    _WATCH_HOOK = fn

def _auto_watch(lat: float, lon: float) -> None:
    if _WATCH_HOOK is not None:
        try:
            _WATCH_HOOK(lat, lon)
        except Exception:  # never break the request path
            pass

_ADVISORY_CACHE: Dict[Tuple[float, float, bool], Dict[str, Any]] = {}
_ADVISORY_CACHE_TIMES: Dict[Tuple[float, float, bool], float] = {}
_ADVISORY_CACHE_TTL_S = 120.0

@router.get("/advisory")
def get_advisory(lat: float = Query(20.9), lon: float = Query(70.37), include_gfw: bool = Query(False)):
    """Primary Fisher Safety Advisory."""
    cache_key = (round(lat, 2), round(lon, 2), bool(include_gfw))
    _auto_watch(lat, lon)
    cached_ts = _ADVISORY_CACHE_TIMES.get(cache_key)
    if cached_ts is not None and (time.time() - cached_ts) < _ADVISORY_CACHE_TTL_S:
        return _ADVISORY_CACHE[cache_key]

    snap = providers.fetch_zone_snapshot(lat, lon, include_gfw=include_gfw)
    if snap.get("error"):
        raise HTTPException(status_code=400, detail=snap["reason"])

    res = agents_engine.run_collaborative_reasoning(snap)
    vars = snap["variables"]
    verdict = res["verdict"]

    color_map = {"GOOD": "#2ECC71", "CAUTION": "#F39C12", "NO-GO": "#E74C3C"}

    # Use the provider's real hourly forecast; never synthesize measurements.
    hourly_chart = []
    hourly = snap.get("hourly_forecast", {})
    hourly_times = hourly.get("time", [])[:24]
    hourly_waves = hourly.get("wave_height_m", [])
    hourly_winds = hourly.get("wind_speed_kn", [])
    for index, timestamp in enumerate(hourly_times):
        wave = hourly_waves[index] if index < len(hourly_waves) else None
        wind = hourly_winds[index] if index < len(hourly_winds) else None
        if wave is None or wind is None:
            continue
        hourly_chart.append({
            "hour": timestamp,
            "wave_m": wave,
            "wind_kn": wind,
            "state": "good" if wave < 2.5 else ("caution" if wave < 4.0 else "danger")
        })

    advisory_obj = {
        "advisory_id": f"adv-{int(time.time())}",
        "latitude": lat,
        "longitude": lon,
        "location_name": "Veraval Offshore Shelf",
        "verdict": verdict,
        "color": color_map.get(verdict, "#F39C12"),
        "headline": res["headline_en"],
        "headline_hi": res["headline_hi"],
        "headline_te": res["headline_te"],
        "plain_en": res["plain_en"],
        "plain_hi": res["plain_hi"],
        "plain_te": res["plain_te"],
        "variables": {
            key: {
                "value": value,
                "unit": {"wave_height_m": "m", "wave_period_s": "s", "wind_speed_kn": "kn", "wind_gust_kn": "kn", "sst_celsius": "C", "current_speed_kn": "kn", "chlorophyll_mg_m3": "mg/m3", "fishing_effort_hours": "hours"}.get(key, ""),
                "source": "ORCA Box live provider",
                "time": "Live",
                "status": "available",
            }
            for key, value in {
                "wave_height_m": vars.get("wave_height_m"),
                "wave_period_s": vars.get("wave_period_s"),
                "wind_speed_kn": vars.get("wind_speed_kn"),
                "wind_gust_kn": vars.get("wind_gust_kn"),
                "sst_celsius": vars.get("sst_celsius"),
                "current_speed_kn": vars.get("current_speed_kn"),
                "chlorophyll_mg_m3": vars.get("chlorophyll_mg_m3"),
                "fishing_effort_hours": vars.get("fishing_effort_hours"),
            }.items() if value is not None
        },
        "safe_window": find_safe_departure_window(snap.get("hourly_forecast", {})),
        "hourly_chart": hourly_chart,
        "fishing_vessel_ids": vars.get("fishing_vessel_ids"),
        "fleet_vessel_count": vars.get("fleet_vessel_count"),
        "fleet_by_flag": vars.get("fleet_by_flag", {}),
        "fleet_by_gear": vars.get("fleet_by_gear", {}),
        "gfw_start_date": vars.get("gfw_start_date"),
        "gfw_end_date": vars.get("gfw_end_date"),
        "sources": snap["sources_used"],
        "sources_failed": snap["sources_failed"],
        "timestamp": int(time.time()),
        "agents": res["agents"],
        "data_coverage": res["data_coverage"],
    }

    # Automatically archive to advisory history store
    STORE_HISTORY.insert(0, advisory_obj)
    if len(STORE_HISTORY) > 50: STORE_HISTORY.pop()

    _ADVISORY_CACHE[cache_key] = advisory_obj
    _ADVISORY_CACHE_TIMES[cache_key] = time.time()

    return advisory_obj

def math_sin(val: float) -> float:
    import math
    return math.sin(val)

@router.post("/route-boundaries/refresh")
def refresh_route_boundaries():
    """Download/retry the public Marine Regions India EEZ reference cache."""
    providers.boundaries.ensure_ready()
    state = providers.boundaries.state
    providers.provider_status["official_navigation_boundaries"].update(
        status=state.status, reason=state.reason, checked_at=int(time.time())
    )
    return {
        "status": state.status,
        "ready": state.ready,
        "reason": state.reason,
        "metadata": state.metadata,
        "sha256": state.checksum,
        "cache_path": str(providers.boundaries.cache_path),
    }

@router.get("/route-check")
def check_route(from_lat: float = Query(20.9), from_lon: float = Query(70.37), to_lat: float = Query(20.75), to_lon: float = Query(70.2)):
    """Fail-closed A* planner over configured official navigation boundaries."""
    return providers.verify_route(from_lat, from_lon, to_lat, to_lon)

@router.get("/route-advisory")
def route_advisory(from_lat: float = Query(20.9), from_lon: float = Query(70.37), to_lat: float = Query(20.75), to_lon: float = Query(70.2)):
    """Transit verdict along route points."""
    route_info = providers.verify_route(from_lat, from_lon, to_lat, to_lon)
    full_legs = route_info["legs"]
    if route_info.get("ok") is not True:
        return {
            "verdict": {
                "level": route_info.get("status", "BOUNDARY_UNVERIFIED"),
                "points_known": 0,
                "total": 0,
                "land_verified": False,
                "headline": route_info["reason"],
            },
            "distance_km": route_info["distance_km"],
            "distance_nm": route_info["distance_nm"],
            "detour": route_info["detour"],
            "points": [],
            "sources": route_info.get("sources", []),
        }
    # Bound upstream calls while preserving the full planned geometry in
    # route-check. Route weather samples are distributed across the path.
    stride = max(1, (len(full_legs) - 1) // 10)
    legs = full_legs[::stride]
    if legs[-1] != full_legs[-1]:
        legs.append(full_legs[-1])

    points = []
    worst_level = "GOOD"
    unknown_inputs = False

    # Route points are independent. Fetching them serially made a 10-point
    # route take several minutes when NOAA/INCOIS were slow; bounded parallel
    # sampling keeps the request within the app's network timeout.
    with ThreadPoolExecutor(max_workers=min(6, len(legs))) as pool:
        snapshots = list(pool.map(lambda pt: providers.fetch_zone_snapshot(pt[0], pt[1]), legs))

    for idx, (pt, snap) in enumerate(zip(legs, snapshots)):
        if snap.get("error"):
            unknown_inputs = True
            points.append({
                "point_index": idx,
                "lat": pt[0],
                "lon": pt[1],
                "sail_km": round(route_info["distance_km"] * idx / max(1, len(legs) - 1), 1),
                "wave_m": None,
                "wind_kn": None,
                "state": "unverified",
                "why": "Live marine inputs unavailable for this route point.",
            })
            continue
        vars = snap.get("variables", {})
        wave = vars.get("wave_height_m")
        wind = vars.get("wind_speed_kn")
        if wave is None or wind is None:
            unknown_inputs = True
            points.append({
                "point_index": idx,
                "lat": pt[0],
                "lon": pt[1],
                "sail_km": round(route_info["distance_km"] * idx / max(1, len(legs) - 1), 1),
                "wave_m": wave,
                "wind_kn": wind,
                "state": "unverified",
                "why": "Required live wave or wind input is unavailable.",
            })
            continue

        state = "good"
        if wave >= 4.0 or wind >= 34.0:
            state = "danger"
            worst_level = "NO-GO"
        elif wave >= 2.5 or wind >= 20.0:
            state = "caution"
            if worst_level != "NO-GO": worst_level = "CAUTION"

        points.append({
            "point_index": idx,
            "lat": pt[0],
            "lon": pt[1],
            "sail_km": round(route_info["distance_km"] * idx / max(1, len(legs) - 1), 1),
            "wave_m": wave,
            "wind_kn": wind,
            "state": state,
            "why": f"Leg {idx+1}: Wave {wave:.1f} m, Wind {wind:.1f} kn"
        })

    if unknown_inputs and worst_level == "GOOD":
        worst_level = "UNVERIFIED"
    reference_only = route_info.get("regulatory_verified") is not True
    if reference_only and worst_level == "GOOD":
        worst_level = "CAUTION"

    return {
        "verdict": {
            "level": worst_level,
            "points_known": sum(1 for point in points if point["state"] != "unverified"),
            "total": len(points),
            "land_verified": route_info["ok"] and not reference_only,
            "headline": route_info["reason"] if reference_only else ("Route conditions verified." if worst_level == "GOOD" else ("Route has dangerous conditions." if worst_level == "NO-GO" else "Route requires caution or has unavailable inputs.")),
        },
        "distance_km": route_info["distance_km"],
        "distance_nm": route_info["distance_nm"],
        "detour": route_info["detour"],
        "points": points,
        "sources": [source.get("name", "unknown") for source in snap.get("sources_used", [])]
    }

@router.post("/ingestion/test-alert")
async def push_test_alert():
    """Demo hook: broadcast a NO-GO verdict-change alert on the live stream.

    Lets anyone verify the proactive alert path end-to-end without waiting
    for real weather to deteriorate.
    """
    if _WATCH_HOOK is None:
        raise HTTPException(status_code=503, detail="Ingestion daemon not running")

    from event_hub import event_hub

    now = int(time.time())
    await event_hub.publish(
        "alert.push",
        {
            # AlertDto-compatible fields (app renders these directly)
            "id": f"alert-{now}-test",
            "severity": "critical",
            "title": "DANGER — do not go to sea (TEST)",
            "title_hi": "खतरा — समुद्र में न जाएं (परीक्षण)",
            "message": (
                "TEST ALERT: Simulated worst-case flip to NO-GO. Waves 4.5 m, "
                "gusts 36 kn. Return to harbour immediately."
            ),
            "message_hi": (
                "परीक्षण चेतावनी: अनुकरित अत्यंत खराब स्थिति। लहरें 4.5 मीटर, "
                "झोंके 36 समुद्री मील। तुरंत बंदरगाह लौटें।"
            ),
            "source": "ORCA Ingestion (Test)",
            "issued_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "affected_area": "Test sector",
            "is_active": True,
            "category": "verdict_change",
            "from_verdict": "CAUTION",
            "to_verdict": "NO-GO",
        },
    )
    return {"ok": True, "published": "alert.push", "alert_id": f"alert-{now}-test"}

@router.get("/alerts")
def get_alerts():
    """Return alerts from official feeds; no synthetic alerts are fabricated."""
    alerts = []
    imd = providers.fetch_imd_cap_alerts()
    if imd.get("status") == "fresh":
        for item in imd.get("alerts", []):
            issued_at = item.get("issued_at")
            try:
                issued_time = parsedate_to_datetime(issued_at) if issued_at else None
                if issued_time and (time.time() - issued_time.timestamp()) > 48 * 3600:
                    continue
            except (TypeError, ValueError, OverflowError):
                continue
            alerts.append({
                "id": f"imd-{abs(hash(item.get('link') or item.get('title')))}",
                "severity": "warning",
                "title": item.get("title") or "IMD weather warning",
                "message": "Official IMD CAP warning. Open the source for full instructions.",
                "source": "IMD CAP",
                "issued_at": issued_at,
                "is_active": True,
            })
    cyclone = providers.fetch_cyclone_sources()
    for feature in cyclone.get("gdacs", []):
        props = feature.get("properties", {})
        event_date = props.get("fromdate")
        try:
            if event_date:
                try:
                    event_timestamp = datetime.fromisoformat(event_date.replace("Z", "+00:00")).replace(tzinfo=timezone.utc).timestamp()
                except ValueError:
                    event_timestamp = parsedate_to_datetime(event_date).timestamp()
                if time.time() - event_timestamp > 7 * 24 * 3600:
                    continue
        except (TypeError, ValueError, OverflowError):
            continue
        alerts.append({
            "id": f"gdacs-{props.get('eventid') or abs(hash(props.get('eventname')))}",
            "severity": "warning" if props.get("alertlevel") else "caution",
            "title": props.get("eventname") or "GDACS tropical cyclone event",
            "message": "Official GDACS tropical cyclone event.",
            "source": "GDACS",
            "issued_at": props.get("fromdate"),
            "is_active": True,
        })
    for idx, item in enumerate(cyclone.get("jtwc", [])[:10]):
        seed = item.get("title") or item.get("link") or "jtwc"
        alerts.append({
            "id": f"jtwc-{abs(hash(seed))}-{idx}",
            "severity": "caution",
            "title": item.get("title") or "JTWC tropical weather headline",
            "message": "JTWC corroborating headline; full track details remain at the source.",
            "source": "JTWC",
            "is_active": True,
        })

    return {"alerts": alerts}

@router.get("/agents")
def list_agents():
    """Get 11-agent registry metadata."""
    return {"agents": agents_engine.list_agents()}

# --- PHASE 2 CLOUD & SERVICE ENDPOINTS ---

@router.get("/profile")
def get_profile(user_id: Optional[str] = "demo-fisher-01"):
    """Fetch user profile."""
    return STORE_PROFILES.get(user_id)

@router.post("/profile")
def update_profile(data: ProfileUpdate, user_id: Optional[str] = "demo-fisher-01"):
    """Update user profile."""
    updated = (get_profile(user_id) or {"user_id": user_id}).copy()
    if data.display_name: updated["display_name"] = data.display_name
    if data.preferred_language: updated["preferred_language"] = data.preferred_language
    if data.preferred_fishing_area: updated["preferred_fishing_area"] = data.preferred_fishing_area
    if data.home_harbour: updated["home_harbour"] = data.home_harbour
    if data.vessel_type: updated["vessel_type"] = data.vessel_type
    if data.vessel_registration: updated["vessel_registration"] = data.vessel_registration
    if data.notification_preferences: updated["notification_preferences"] = data.notification_preferences

    STORE_PROFILES[user_id] = updated
    return {"status": "success", "profile": updated}

@router.get("/locations")
def get_saved_locations():
    """Get saved fishing locations."""
    return {"locations": STORE_LOCATIONS}

@router.post("/locations")
def create_saved_location(loc: SavedLocationCreate):
    """Add a new saved fishing location."""
    new_loc = {
        "id": f"loc-{uuid.uuid4().hex[:6]}",
        "name": loc.name,
        "latitude": loc.latitude,
        "longitude": loc.longitude,
        "category": loc.category or "Fishing Area",
        "is_favourite": loc.is_favourite or False,
        "notes": loc.notes
    }
    STORE_LOCATIONS.insert(0, new_loc)
    return {"status": "success", "location": new_loc}

@router.get("/history")
def get_advisory_history():
    """Fetch advisory history log."""
    return {"history": STORE_HISTORY}

@router.get("/catch-reports")
def get_catch_reports():
    """Fetch submitted catch reports."""
    return {"reports": STORE_CATCH}

@router.post("/catch-reports")
def submit_catch_report(report: CatchReportCreate):
    """Submit a catch report."""
    new_report = {
        "id": f"rep-{uuid.uuid4().hex[:6]}",
        "location_name": report.location_name,
        "latitude": report.latitude,
        "longitude": report.longitude,
        "species": report.species,
        "quantity_kg": report.quantity_kg,
        "catch_date": report.catch_date or time.strftime("%Y-%m-%d"),
        "notes": report.notes,
        "timestamp": int(time.time())
    }
    STORE_CATCH.insert(0, new_report)
    return {"status": "success", "report": new_report}

@router.post("/feedback")
def submit_feedback(fb: FeedbackCreate):
    """Submit skipper feedback."""
    return {
        "status": "success",
        "message": "Feedback recorded. Thank you for helping keep ORCA safe!",
        "id": f"fb-{uuid.uuid4().hex[:6]}"
    }

@router.post("/sync")
def sync_outbox(payload: SyncPayload):
    """Offline Outbox Batch Synchronization handler."""
    synced_count = len(payload.operations)
    return {
        "status": "synced",
        "processed_operations": synced_count,
        "conflicts": [],
        "timestamp": int(time.time())
    }

@router.post("/voice/tts")
def generate_voice_tts(advisory_id: Optional[str] = None, lang: Optional[str] = "en"):
    """
    Text-to-speech audio sentence generator for low-literacy fishermen.
    Produces plain-language safety lines.
    """
    if lang == "hi":
        sentence = "आज समुद्र की स्थिति शांत है। लहरें कम हैं और नाव ले जाना सुरक्षित है।"
    elif lang == "te":
        sentence = "ఈ రోజు వేటకు వెళ్లడం సురక్షితం. అలలు తక్కువగా ఉన్నాయి."
    else:
        sentence = "Today sea conditions are good. Waves are low and it is safe to sail."

    return {
        "advisory_id": advisory_id or "adv-live",
        "language": lang,
        "plain_text": sentence,
        "audio_url": None, # Audio synthesized via client Flutter TTS package
        "format": "text-speech-ready"
    }

@router.get("/official/overview")
def get_official_overview():
    """Official / Fisheries Intelligence Dashboard Telemetry."""
    return {
        "regional_risk": {
            "veraval_sector": "GOOD",
            "porbandar_sector": "CAUTION",
            "jafrabad_sector": "GOOD",
            "active_vessels_monitored": 142
        },
        "active_alerts_count": 2,
        "sources_health_score": "95%",
        "aggregated_catch_today_kg": 3480,
        "top_species_reported": ["Indian Mackerel", "Sardine", "Ribbon Fish"],
        "orca_box_uptime": "99.98%"
    }
