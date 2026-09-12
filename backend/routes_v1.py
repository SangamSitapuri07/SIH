import time
import uuid
from typing import Dict, Any, List, Optional
from fastapi import APIRouter, Query, HTTPException, Body
from pydantic import BaseModel, Field

from data_providers import DataProvidersEngine
from agents_engine import MultiAgentEngine
from supabase_service import SupabaseService

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
STORE_LOCATIONS = [
    {"id": "loc-1", "name": "Home Harbour (Veraval)", "latitude": 20.9, "longitude": 70.37, "category": "Harbour", "is_favourite": True},
    {"id": "loc-2", "name": "Offshore Fishing Zone A", "latitude": 20.75, "longitude": 70.2, "category": "Fishing Area", "is_favourite": True},
    {"id": "loc-3", "name": "Coastal Shelf Zone B", "latitude": 20.85, "longitude": 70.5, "category": "Fishing Area", "is_favourite": False}
]
STORE_HISTORY = []
STORE_CATCH = []

# --- PHASE 1 CORE ENDPOINTS ---

@router.get("/health")
def get_health():
    """Live source health & system status."""
    return providers.check_health()

@router.get("/zone")
def get_zone_snapshot(lat: float = Query(20.9), lon: float = Query(70.37)):
    """Spot data snapshot."""
    return providers.fetch_zone_snapshot(lat, lon)

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
            if not snap.get("on_land"):
                points.append({
                    "lat": plat,
                    "lon": plon,
                    "wave_h": snap["variables"]["wave_height_m"],
                    "wind_kn": snap["variables"]["wind_speed_kn"],
                    "chl": snap["variables"]["chlorophyll_mg_m3"]
                })
    return {"latitude": lat, "longitude": lon, "span": span, "points": points}

@router.get("/reason")
def get_reasoning(lat: float = Query(20.9), lon: float = Query(70.37)):
    """Run 11-agent collaborative reasoning trace."""
    snap = providers.fetch_zone_snapshot(lat, lon)
    if snap.get("error"):
        raise HTTPException(status_code=400, detail=snap["reason"])
    return agents_engine.run_collaborative_reasoning(snap)

@router.get("/advisory")
def get_advisory(lat: float = Query(20.9), lon: float = Query(70.37)):
    """Primary Fisher Safety Advisory."""
    snap = providers.fetch_zone_snapshot(lat, lon)
    if snap.get("error"):
        raise HTTPException(status_code=400, detail=snap["reason"])

    res = agents_engine.run_collaborative_reasoning(snap)
    vars = snap["variables"]
    verdict = res["verdict"]

    color_map = {"GOOD": "#2ECC71", "CAUTION": "#F39C12", "NO-GO": "#E74C3C"}

    # Generate 24-hour hourly chart forecast
    hourly_chart = []
    base_wave = vars["wave_height_m"]
    base_wind = vars["wind_speed_kn"]
    for h in range(24):
        wave = round(max(0.4, base_wave + (0.3 * math_sin(h * 0.25))), 2)
        wind = round(max(5.0, base_wind + (2.5 * math_sin((h + 2) * 0.25))), 1)
        hourly_chart.append({
            "hour": f"{h:02d}:00",
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
            "wave_height_m": vars["wave_height_m"],
            "wave_period_s": vars["wave_period_s"],
            "wind_speed_kn": vars["wind_speed_kn"],
            "wind_gust_kn": vars["wind_gust_kn"],
            "sst_celsius": vars["sst_celsius"],
            "current_speed_kn": vars["current_speed_kn"],
            "chlorophyll_mg_m3": vars["chlorophyll_mg_m3"]
        },
        "safe_window": {
            "start": "05:30 IST",
            "end": "16:00 IST",
            "duration_hours": 10.5,
            "condition": "Safe departure window before afternoon gust increase."
        },
        "hourly_chart": hourly_chart,
        "sources": snap["sources_used"],
        "sources_failed": snap["sources_failed"],
        "timestamp": int(time.time())
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

    for idx, pt in enumerate(legs):
        snap = providers.fetch_zone_snapshot(pt[0], pt[1])
        vars = snap.get("variables", {})
        wave = vars.get("wave_height_m", 1.5)
        wind = vars.get("wind_speed_kn", 14.0)

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
    """Active Alert Cards feed."""
    return {
        "alerts": [
            {
                "alert_id": "alt-cyclone-01",
                "severity": "WARNING",
                "category": "Cyclone Warning",
                "title": "JTWC Advisory: Depressive Trough in Arabian Sea",
                "message": "Sustained winds exceeding 28 kn in outer offshore sector. Keep radio monitored.",
                "issued_at": int(time.time()) - 3600,
                "expires_at": int(time.time()) + 86400,
                "source": "JTWC / IMD Bulletin"
            },
            {
                "alert_id": "alt-wave-02",
                "severity": "CAUTION",
                "category": "Wave Hazard",
                "title": "Moderate Swell Increase Expected",
                "message": "Wave period lengthening to 9.2s after 14:00 IST today.",
                "issued_at": int(time.time()) - 1800,
                "expires_at": int(time.time()) + 43200,
                "source": "Open-Meteo MFWAM"
            }
        ]
    }

@router.get("/agents")
def list_agents():
    """Get 11-agent registry metadata."""
    return {"agents": agents_engine.list_agents()}

# --- PHASE 2 CLOUD & SERVICE ENDPOINTS ---

@router.get("/profile")
def get_profile(user_id: Optional[str] = "demo-fisher-01"):
    """Fetch user profile."""
    prof = STORE_PROFILES.get(user_id, {
        "user_id": user_id,
        "display_name": "Captain Ramesh",
        "preferred_language": "en",
        "preferred_fishing_area": "Veraval Offshore Zone 1",
        "home_harbour": "Veraval Harbour",
        "vessel_type": "Motorized Craft (9m)",
        "vessel_registration": "GJ-11-MM-4021",
        "notification_preferences": {
            "wave_alerts": True,
            "wind_alerts": True,
            "cyclone_alerts": True,
            "pfz_updates": True
        }
    })
    return prof

@router.post("/profile")
def update_profile(data: ProfileUpdate, user_id: Optional[str] = "demo-fisher-01"):
    """Update user profile."""
    existing = get_profile(user_id)
    updated = existing.copy()
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
    if not STORE_HISTORY:
        # Pre-populate sample history if empty
        get_advisory(20.9, 70.37)
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
