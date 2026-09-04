"""Regression tests for the 2026-09-04 screenshot-review bug batch.

Bug #3: Satellite tag followed the CROSS-CHECK source's success instead of
        the primary (NOAA) measurement — cloud-masked OC-CCI flipped the
        chip to "no data" while real chlorophyll was displayed.
Bug #2: Marine Risk quoted a 2.5 m+ rough-seas warning yet concluded
        "low" because wave_caution weighed only 1 (threshold is 2).
Bug #1: Gale-force gusts next to a "calm" sustained reading never
        escalated — gust severity was always just "info".
"""
from __future__ import annotations

from pipeline.agents import marine_risk, satellite, weather


# ── Bug #3: satellite tag must follow the PRIMARY measurement ─────────

def test_satellite_low_chl_without_crosscheck_is_low_not_unknown():
    """chl present (NOAA) but OC-CCI cloud-masked → 'low', NOT 'unknown'."""
    snap = {
        "chlorophyll": 0.21,
        "chlorophyll_source": "NOAA ERDDAP",
        "chlorophyll_unit": "mg/m^3",
        # note: no chlorophyll_occci key → cross-check absent
    }
    res = satellite.analyze(snap)
    assert res["risk_level"] == "low", res
    # And the honesty note about the missing cross-check must be visible
    types = [f["type"] for f in res["findings"]]
    assert "chl_cross_check_missing" in types


def test_satellite_absent_chl_still_unknown():
    """Genuinely no chlorophyll at all → 'unknown' (that IS no data)."""
    res = satellite.analyze({"chlorophyll": None})
    assert res["risk_level"] == "unknown"


def test_satellite_bloom_still_moderate():
    snap = {"chlorophyll": 6.5, "chlorophyll_source": "NOAA", "chlorophyll_unit": "mg/m^3"}
    assert satellite.analyze(snap)["risk_level"] == "moderate"


# ── Bug #2: marine risk must ESCALATE on the warning it quotes ────────

def _ocean_with_wave_caution():
    return {
        "agent": "ocean",
        "findings": [{
            "type": "wave_caution", "severity": "warn", "value": 2.74,
            "msg": "Max wave height 2.74m — rough seas, exercise caution.",
        }],
        "summary": "rough", "risk_level": "moderate",
    }


def test_marine_risk_escalates_on_wave_caution():
    """2.5 m+ waves (IMD small-craft caution) → at least 'moderate'."""
    res = marine_risk.analyze({}, agent_results=[_ocean_with_wave_caution()])
    assert res["risk_level"] in ("moderate", "high", "critical"), res
    assert res["risk_score"] >= 2


def test_marine_risk_calm_stays_low():
    ocean = {"agent": "ocean", "findings": [{
        "type": "wave_calm", "severity": "good", "value": 0.8, "msg": "calm"}],
        "summary": "calm", "risk_level": "low"}
    res = marine_risk.analyze({}, agent_results=[ocean])
    assert res["risk_level"] == "low"


def test_marine_risk_sees_gale_gusts():
    """A gale-gust finding from weather must matter to a boat."""
    wx = {"agent": "weather", "findings": [{
        "type": "gale_gusts", "severity": "warn", "value": 15.2,
        "msg": "Gale-force gusts to 15.2 m/s"}],
        "summary": "gusty", "risk_level": "moderate"}
    res = marine_risk.analyze({}, agent_results=[wx])
    assert res["risk_score"] >= 2
    assert res["risk_level"] != "low"


# ── Bug #1: gust escalation in the weather agent itself ────────────────

def test_weather_gale_gusts_escalate_risk(monkeypatch):
    """Sustained 5 m/s looking 'safe' + 16 m/s gusts → NOT safe."""
    import pipeline.ttlcache as ttlcache
    ttlcache.clear()  # don't let a cached fetch shadow the patch
    fake = {
        "daily": {
            "wind_speed_10m_max": [5.0],
            "wind_gusts_10m_max": [16.0],
            "precipitation_sum": [0.0],
            "weather_code": [1],
            "temperature_2m_max": [30.0],
            "temperature_2m_min": [26.0],
        }
    }
    monkeypatch.setattr(weather, "_fetch", lambda *a, **k: fake)
    res = weather.analyze({"lat": 13.08, "lon": 80.28, "date": "2026-09-04"})
    types = [f["type"] for f in res["findings"]]
    assert "gale_gusts" in types
    assert res["risk_level"] in ("moderate", "high")
    # and the calm finding must quote the gust number, not hide it
    calm = next(f for f in res["findings"] if f["type"] == "wind_calm")
    assert "gusts 16.0" in calm["msg"]


def test_weather_light_gusts_stay_calm(monkeypatch):
    import pipeline.ttlcache as ttlcache
    ttlcache.clear()
    fake = {
        "daily": {
            "wind_speed_10m_max": [4.0],
            "wind_gusts_10m_max": [5.5],
            "precipitation_sum": [0.0],
            "weather_code": [0],
            "temperature_2m_max": [30.0],
            "temperature_2m_min": [26.0],
        }
    }
    monkeypatch.setattr(weather, "_fetch", lambda *a, **k: fake)
    res = weather.analyze({"lat": 13.08, "lon": 80.28, "date": "2026-09-04"})
    assert res["risk_level"] == "low"
