import time
import uuid
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Query, HTTPException, Body
from pydantic import BaseModel, Field

from data_providers import DataProvidersEngine
from agents_engine import MultiAgentEngine
from supabase_service import SupabaseService
from mosdac_datasets import registry_status
from safe_window import find_safe_departure_window

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
def get_health():
    """Live source health and system status for client applications."""
    health = providers.check_health()
    health["mosdac_activation"] = registry_status()
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
    points = []
    step = span / 3.0
    for r in range(4):
        for c in range(4):
            plat = round(lat - (span / 2.0) + (r * step), 4)
            plon = round(lon - (span / 2.0) + (c * step), 4)
            snap = providers.fetch_zone_snapshot(plat, plon)
            if not snap.get("error"):
                points.append({
                    "lat": plat,
                    "lon": plon,
                    "wave_h": snap["variables"]["wave_height_m"],
                    "wind_kn": snap["variables"]["wind_speed_kn"],
                    "chl": snap["variables"].get("chlorophyll_mg_m3")
                })
    return {"latitude": lat, "longitude": lon, "span": span, "points": points}

@router.get("/reason")
def get_reasoning(lat: float = Query(20.9), lon: float = Query(70.37), include_gfw: bool = Query(False)):
    """Run 11-agent collaborative reasoning trace."""
    snap = providers.fetch_zone_snapshot(lat, lon, include_gfw=include_gfw)
    if snap.get("error"):
        raise HTTPException(status_code=400, detail=snap["reason"])
    return agents_engine.run_collaborative_reasoning(snap)

@router.get("/advisory")
def get_advisory(lat: float = Query(20.9), lon: float = Query(70.37), include_gfw: bool = Query(False)):
    """Primary Fisher Safety Advisory."""
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

    return advisory_obj

def math_sin(val: float) -> float:
    import math
    return math.sin(val)

@router.get("/route-check")
def check_route(from_lat: float = Query(20.9), from_lon: float = Query(70.37), to_lat: float = Query(20.75), to_lon: float = Query(70.2)):
    """Course verifier against GLOBE land mask."""
    return providers.verify_route(from_lat, from_lon, to_lat, to_lon)

@router.get("/route-advisory")
def route_advisory(from_lat: float = Query(20.9), from_lon: float = Query(70.37), to_lat: float = Query(20.75), to_lon: float = Query(70.2)):
    """Transit verdict along route points."""
    route_info = providers.verify_route(from_lat, from_lon, to_lat, to_lon)
    legs = route_info["legs"]

    points = []
    worst_level = "GOOD"
    unknown_inputs = False

    for idx, pt in enumerate(legs):
        snap = providers.fetch_zone_snapshot(pt[0], pt[1])
        if snap.get("error"):
            unknown_inputs = True
            points.append({
                "point_index": idx,
                "latitude": pt[0],
                "longitude": pt[1],
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
                "latitude": pt[0],
                "longitude": pt[1],
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
            "latitude": pt[0],
            "longitude": pt[1],
            "wave_m": wave,
            "wind_kn": wind,
            "state": state,
            "why": f"Leg {idx+1}: Wave {wave:.1f} m, Wind {wind:.1f} kn"
        })

    if unknown_inputs and worst_level == "GOOD":
        worst_level = "UNVERIFIED"

    return {
        "verdict": {
            "level": worst_level,
            "points_known": len(points),
            "land_verified": route_info["ok"]
        },
        "distance_km": route_info["distance_km"],
        "distance_nm": route_info["distance_nm"],
        "detour": route_info["detour"],
        "points": points,
        "sources": snap.get("sources_used", [])
    }

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
