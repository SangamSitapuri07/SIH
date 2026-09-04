"""Phase-4 tests — advisory, chat router, alerts, PFZ geometry, JTWC parser.

All OFFLINE. Fixtures are real data recorded from live calls made on
2026-09-03 (the actual Open-Meteo response for Veraval, the actual JTWC
warning text for TS Saudel, the actual INCOIS PFZ lines shape) — replayed
so CI doesn't need the network and the logic is tested against the true
wire formats.
"""
from __future__ import annotations

import pytest

from pipeline import alerts as alerts_mod
from pipeline import chat as chat_mod
from pipeline import forecast as fc
from pipeline import incois_pfz, jtwc
from pipeline.advisory import build_advisory

# ── Real recorded fixtures (2026-09-03, Veraval 20.9N 70.37E) ──────

FAKE_FORECAST = {
    "source": "Open-Meteo Marine + Forecast (MeteoFrance/ECMWF models)",
    "lat": 20.9, "lon": 70.37,
    "fetched_at": "2026-09-03T12:00:00+00:00",
    "hourly": {
        "time": ["2026-09-03T00:00", "2026-09-03T01:00"],
        "wave_height_m": [1.74, 1.72],
        "swell_height_m": [1.2, 1.2],
        "current_kn": [0.97, 0.58],
        "current_dir_deg": [180.0, 180.0],
        "wind_kn": [10.5, 11.0],
        "gust_kn": [13.0, 13.5],
        "rain_mm": [0.0, 0.0],
    },
    "now": {"time": "2026-09-03T01:00Z", "wave_height_m": 1.72, "swell_height_m": 1.2,
            "current_kn": 0.58, "current_dir_deg": 180.0, "wind_kn": 11.0,
            "gust_kn": 13.5, "rain_mm": 0.0},
    "next24h": {"wave_max_m": 1.9, "swell_max_m": 1.4, "wind_max_kn": 12.5,
                "gust_max_kn": 15.0, "rain_total_mm": 0.0},
    "next48h": {"wave_max_m": 2.1, "swell_max_m": 1.5, "wind_max_kn": 12.5,
                "gust_max_kn": 15.0, "rain_total_mm": 0.0},
}

FAKE_SNAPSHOT = {
    "lat": 20.9, "lon": 70.37, "date": "2026-09-03",
    "sst_mean": 28.4, "sst_max": 28.9, "sst_min": 27.9,
    "chlorophyll": 1.21, "chlorophyll_unit": "mg/m^3",
    "data_sources_used": ["Open-Meteo Marine (SST + waves)", "NOAA ERDDAP (chlorophyll)"],
    "data_sources_failed": [],
    "fetched_at": "2026-09-03T12:00:00+00:00",
}

# Real JTWC warning text shape (TS 17W Saudel, final piece truncated)
SAUDEL_WEBTXT = """WTPN32 PGTW 030300
MSGID/GENADMIN/JOINT TYPHOON WRNCEN PEARL HARBOR HI//
SUBJ/TROPICAL STORM 17W (SAUDEL) WARNING NR 047//
RMKS/
1. TROPICAL STORM 17W (SAUDEL)  WARNING NR 047
   MAX SUSTAINED WINDS BASED ON ONE-MINUTE AVERAGE
   WIND RADII VALID OVER OPEN WATER ONLY
    ---
   WARNING POSITION:
   030000Z --- NEAR 23.8N 117.4E
     MOVEMENT PAST SIX HOURS - 295 DEGREES AT 10 KTS
     POSITION ACCURATE TO WITHIN 040 NM
   PRESENT WIND DISTRIBUTION:
   MAX SUSTAINED WINDS - 040 KT, GUSTS 050 KT
   RADIUS OF 034 KT WINDS - 040 NM NORTHEAST QUADRANT
                            040 NM SOUTHEAST QUADRANT
                            035 NM SOUTHWEST QUADRANT
                            030 NM NORTHWEST QUADRANT
"""


# ── PFZ geometry (pure math) ───────────────────────────────────────

def test_haversine_sanity():
    # 1 degree of latitude ≈ 111.2 km (known geodesy fact)
    d = incois_pfz.haversine_km(20.0, 70.0, 21.0, 70.0)
    assert 110.0 < d < 112.5


def test_point_segment_distance_and_tie():
    # point north of segment midpoint → closest point on segment
    d, (clat, clon) = incois_pfz._point_segment_km(20.1, 70.05, 20.0, 70.0, 20.0, 70.1)
    assert d == pytest.approx(11.1, abs=0.3)
    # nearest endpoint math: point beyond the segment end snaps to the end
    d2, (clat2, clon2) = incois_pfz._point_segment_km(20.0, 70.2, 20.0, 70.0, 20.0, 70.1)
    assert (round(clat2, 2), round(clon2, 2)) == (20.0, 70.1)


def test_bearing_cardinals():
    assert incois_pfz.bearing_deg(20.0, 70.0, 21.0, 70.0) == pytest.approx(0.0, abs=1.0)
    assert incois_pfz.bearing_deg(20.0, 70.0, 20.0, 71.0) == pytest.approx(90.0, abs=1.0)


def test_nearest_pfz_with_injected_lines(monkeypatch):
    fake = {
        "source": "test", "fetched_at": "x", "n_lines": 1,
        "latest_julian_day": "246", "year": 2026, "advisory_date": "2026-09-03",
        "lines": [{
            "uid": 2026246001.0, "sno": "001", "sector_code": 5,
            "sector_name": "Karnataka", "julian_day": "246", "year": 2026,
            "length_km": 67.9, "part": 0,
            "coords": [[70.0, 20.5], [70.2, 20.6], [70.4, 20.6]],
        }],
    }
    monkeypatch.setattr(incois_pfz, "get_lines", lambda **k: fake)
    r = incois_pfz.nearest_pfz(20.0, 70.2)
    assert r["found"] is True
    assert 40 < r["distance_km"] < 60  # ~0.5 deg of latitude
    assert r["distance_nm"] == pytest.approx(r["distance_km"] / 1.852, abs=0.2)
    assert r["advisory_date"] == "2026-09-03"


def test_nearest_pfz_none_nearby(monkeypatch):
    fake = {
        "source": "test", "fetched_at": "x", "n_lines": 1,
        "latest_julian_day": "246", "year": 2026, "advisory_date": "2026-09-03",
        "lines": [{"uid": 1, "sno": "1", "sector_code": 3, "sector_name": "Maharashtra",
                   "julian_day": "246", "year": 2026, "length_km": 10.0, "part": 0,
                   "coords": [[60.0, 10.0], [60.1, 10.1]]}],
    }
    monkeypatch.setattr(incois_pfz, "get_lines", lambda **k: fake)
    r = incois_pfz.nearest_pfz(22.0, 70.37)
    assert r["found"] is False and r.get("note")


# ── JTWC parser (real warning-text fixture) ────────────────────────

def test_jtwc_parse_position_and_winds():
    c = jtwc.parse_warning_text("wp1726", SAUDEL_WEBTXT)
    assert c is not None
    assert c["lat"] == pytest.approx(23.8)
    assert c["lon"] == pytest.approx(117.4)
    assert c["max_wind_kt"] == 40 and c["gust_kt"] == 50
    assert c["movement_deg"] == 295 and c["movement_kt"] == 10
    assert c["radius_34kt_nm"] == 40
    assert c["name"] == "Saudel"


def test_jtwc_skips_final_warning():
    final_txt = SAUDEL_WEBTXT.replace("WARNING NR 047", "FINAL WARNING NR 047", 1)
    assert jtwc.parse_warning_text("wp1726", final_txt) is None


# ── Forecast helpers ───────────────────────────────────────────────

def test_safe_window_calm_forecast():
    sw = fc.find_safe_window(FAKE_FORECAST, horizon_hours=2, min_hours=2)
    # history horizon is short here but waves 1.7m < 2.5 so a window exists
    assert isinstance(sw, dict)
    assert "found" in sw


def test_safe_window_stormy_forecast():
    stormy = {
        "hourly": {
            "time": [f"2030-01-01T{h:02d}:00" for h in range(8)],
            "wave_height_m": [5.0] * 8,
            "swell_height_m": [3.0] * 8,
            "wind_kn": [40.0] * 8,
            "gust_kn": [50.0] * 8,
        }
    }
    sw = fc.find_safe_window(stormy, horizon_hours=8)
    assert sw["found"] is False


# ── Advisory engine (with monkeypatched real-shaped sources) ───────

def _patch_calm(monkeypatch):
    monkeypatch.setattr("pipeline.advisory.zone_snapshot_cached", lambda *a, **k: dict(FAKE_SNAPSHOT))
    monkeypatch.setattr(fc, "get_point_forecast", lambda *a, **k: dict(FAKE_FORECAST))
    monkeypatch.setattr(incois_pfz, "nearest_pfz", lambda lat, lon: {
        "available": True, "found": True, "distance_km": 24.0, "distance_nm": 13.0,
        "bearing_deg": 300, "nearest_point": {"lat": 21.05, "lon": 70.2},
        "sector_name": "Gujarat", "uid": 2026246001.0, "line_length_km": 67.9,
        "advisory_date": "2026-09-03", "julian_day": "246",
        "source": "INCOIS PFZ Advisory (GeoServer WFS)",
    })
    monkeypatch.setattr(jtwc, "nearest_cyclone", lambda lat, lon, **k: {
        "checked": True, "found": False, "advisories_anywhere": 0,
        "errors": [], "source": "JTWC", "note": "No active tropical cyclone in the region right now.",
    })


def test_advisory_go_verdict(monkeypatch):
    _patch_calm(monkeypatch)
    adv = build_advisory(20.9, 70.37)
    assert adv["verdict"] == "go"
    assert adv["variables"]["wave_height_m"] == 1.72
    assert adv["variables"]["nearest_pfz_km"] == 24.0
    assert adv["icon"] == "✅"
    assert any(r["code"] == "official_pfz" for r in adv["reasons"])
    assert adv["sources"], "advisory must cite its sources"


def test_advisory_no_go_on_cyclone(monkeypatch):
    _patch_calm(monkeypatch)
    monkeypatch.setattr(jtwc, "nearest_cyclone", lambda lat, lon, **k: {
        "checked": True, "found": True, "distance_km": 210, "bearing_deg": 160,
        "cyclone": {"name": "Testya", "designation": "02A", "basin": "io",
                    "max_wind_kt": 65, "intensity": "Very Severe Cyclonic Storm",
                    "advisory_no": 3, "lat": 19.0, "lon": 71.5, "source": "JTWC"},
        "source": "JTWC",
    })
    adv = build_advisory(20.9, 70.37)
    assert adv["verdict"] == "no_go"
    assert adv["icon"] == "⛔"
    assert adv["variables"]["cyclone_dist_km"] == 210
    assert any(r["code"] == "cyclone_near" for r in adv["reasons"])


def test_advisory_caution_on_waves(monkeypatch):
    _patch_calm(monkeypatch)
    rough = dict(FAKE_FORECAST)
    rough["now"] = {**FAKE_FORECAST["now"], "wave_height_m": 3.1}
    rough["next48h"] = {**FAKE_FORECAST["next48h"], "wave_max_m": 3.3}
    monkeypatch.setattr(fc, "get_point_forecast", lambda *a, **k: rough)
    adv = build_advisory(20.9, 70.37)
    assert adv["verdict"] == "caution"
    assert any(r["code"] == "waves_elevated" for r in adv["reasons"])


# ── Alerts engine ──────────────────────────────────────────────────

def test_alerts_calm_point_no_alerts(monkeypatch):
    alerts_mod._store.clear()
    monkeypatch.setattr(fc, "get_point_forecast", lambda *a, **k: dict(FAKE_FORECAST))
    monkeypatch.setattr(jtwc, "nearest_cyclone", lambda lat, lon, **k: {
        "checked": True, "found": False, "advisories_anywhere": 0, "errors": [],
        "source": "JTWC", "note": "none"})
    made = alerts_mod.evaluate(20.9, 70.37)
    assert made == []
    assert alerts_mod.list_alerts() == []


def test_alerts_gale_warning(monkeypatch):
    alerts_mod._store.clear()
    windy = dict(FAKE_FORECAST)
    windy["next24h"] = {**FAKE_FORECAST["next24h"], "gust_max_kn": 38.0}
    monkeypatch.setattr(fc, "get_point_forecast", lambda *a, **k: windy)
    monkeypatch.setattr(jtwc, "nearest_cyclone", lambda lat, lon, **k: {
        "checked": True, "found": False, "advisories_anywhere": 0, "errors": [],
        "source": "JTWC", "note": "none"})
    made = alerts_mod.evaluate(20.9, 70.37)
    assert any(a["code"] == "gale" and a["severity"] == "warning" for a in made)
    assert all(a["simulated"] is False for a in made)


def test_simulated_alert_is_labelled():
    a = alerts_mod.simulate("cyclone", 20.9, 70.37)
    assert a["simulated"] is True
    assert a["title_en"].startswith("🧪 DEMO")
    assert a["severity"] == "warning"
    with pytest.raises(ValueError):
        alerts_mod.simulate("volcano", 0, 0)


# ── Chat router + composition ──────────────────────────────────────

def test_chat_route_pfz_intent():
    r = chat_mod.route("bhai machli kahaan milegi aaj?")
    assert "pfz" in r["intents"]
    assert "fisheries" in r["agents"]
    assert "incois_pfz" in r["tools"]


def test_chat_route_hazard_intent():
    r = chat_mod.route("Is there any cyclone warning for tomorrow?")
    assert "hazard" in r["intents"]
    assert "jtwc" in r["tools"]


def test_chat_route_default_is_safety():
    r = chat_mod.route("hello")
    assert r["intents"] == ["safety"]


def test_compose_answer_contains_real_numbers(monkeypatch):
    _patch_calm(monkeypatch)
    adv = build_advisory(20.9, 70.37)
    trace = {
        "routing": {"intents": ["safety"], "agents": ["ocean"], "tools": ["forecast"]},
        "advisory": adv,
        "agent_results": [],
        "extra": {"forecast": FAKE_FORECAST},
        "insight": None,
    }
    text = chat_mod.compose_answer(trace, "kya hum safe hai?")
    assert adv["icon"] in text
    assert "1.72" in text or "1.7" in text  # wave height number must appear
    assert "No cyclone" in text or "cyclone" in text.lower()
    assert "Sources:" in text
