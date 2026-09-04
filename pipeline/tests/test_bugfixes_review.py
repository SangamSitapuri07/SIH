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


# ── Bug #1 (advisory card twin): gust band 28-34 kn must be CAUTION ────

def _patch_advisory_world(monkeypatch, *, gust_kn, wind_kn=10):
    """Neutral sea everywhere; only wind/gust varies."""
    from pipeline import advisory
    import pipeline.jtwc as jtwc
    import pipeline.ttlcache as ttlcache
    ttlcache.clear()
    monkeypatch.setattr(
        advisory, "zone_snapshot_cached",
        lambda *a, **k: {"lat": 13.0, "lon": 80.0, "sst_mean": 28.5,
                         "chlorophyll": 0.3,
                         "data_sources_used": [], "data_sources_failed": []})
    monkeypatch.setattr(
        advisory.fc, "get_point_forecast",
        lambda *a, **k: {
            "source": "mock",
            "now": {"wave_height_m": 0.8, "swell_height_m": 0.4,
                    "wind_kn": wind_kn, "gust_kn": gust_kn, "current_kn": 0.5,
                    "current_dir_deg": 90},
            "next24h": {"wave_max_m": 0.9, "gust_max_kn": gust_kn,
                        "rain_total_mm": 0.0},
            "next48h": {"wave_max_m": 0.9, "wind_max_kn": wind_kn,
                        "gust_max_kn": gust_kn},
        })
    monkeypatch.setattr(advisory.fc, "find_safe_window",
                        lambda *a, **k: {"found": False, "note": "mock"})
    monkeypatch.setattr(jtwc, "nearest_cyclone",
                        lambda *a, **k: {"found": False, "checked": True,
                                         "note": "No active tropical cyclone in the region right now."})
    monkeypatch.setattr(advisory.incois_pfz, "nearest_pfz",
                        lambda *a, **k: {"found": False})
    return advisory


def test_advisory_gusts_30kn_caution_not_comfortable(monkeypatch):
    """Chennai case: 10 kn sustained + 30 kn gusts was labelled
    'comfortable' while the UI tile glowed red-warn at >=28 kn."""
    advisory = _patch_advisory_world(monkeypatch, gust_kn=30)
    res = advisory.build_advisory(13.08, 80.28)
    gust_reason = next(
        (r for r in res["reasons"] if r["code"] == "gusts_high"), None)
    assert gust_reason is not None, [r["code"] for r in res["reasons"]]
    assert gust_reason["severity"] == "caution"
    assert res["verdict"] == "caution"


def test_advisory_quotes_gusts_even_when_calm(monkeypatch):
    """Below the caution band the info line still quotes BOTH numbers."""
    advisory = _patch_advisory_world(monkeypatch, gust_kn=22)
    res = advisory.build_advisory(13.08, 80.28)
    wind_reason = next(r for r in res["reasons"] if r["code"] == "wind_ok")
    assert "gusts 22" in wind_reason["msg"]
    assert "comfortable" not in wind_reason["msg"] or "sustained" in wind_reason["msg"]


# ── Now-vs-Peak labelling (review round 3) ─────────────────────────────

def test_ocean_uses_48h_peak_and_labels_both_numbers():
    """Reason panel must quote the 48h peak + 'now', and mark the 30-day
    window max as history — not as a silent contradiction."""
    from pipeline.agents import ocean
    snap = {"sst_mean": 28.0, "wave_max": 4.2,
            "wave_now_m": 1.48, "wave_peak_48h_m": 2.4}
    res = ocean.analyze(snap)
    calm = next(f for f in res["findings"] if f["type"] == "wave_calm")
    assert "2.4 m" in calm["msg"] and "1.48 m now" in calm["msg"]
    hist = next(f for f in res["findings"] if f["type"] == "wave_recent_window")
    assert "Past ~30-day" in hist["msg"] and "NOT today" in hist["msg"]
    assert res["risk_level"] == "low"


def test_ocean_without_forecast_labels_window_max_honestly():
    from pipeline.agents import ocean
    res = ocean.analyze({"sst_mean": 28.0, "wave_max": 3.1})
    w = next(f for f in res["findings"] if f["type"] == "wave_caution")
    assert "past ~30 days" in w["msg"]
    assert res["risk_level"] == "moderate"


def test_marine_risk_escalates_on_fresh_breeze():
    """The Vizag case: weather quoted 'Fresh breeze 10.2 m/s, exercise
    caution' but Marine Risk stayed LOW. Wind WARNs must count like wave
    WARNs."""
    wx = {"agent": "weather", "findings": [{
        "type": "fresh_breeze", "severity": "warn", "value": 10.2,
        "msg": "Fresh breeze 10.2 m/s (Beaufort 5). Exercise caution."}],
        "summary": "breezy", "risk_level": "moderate"}
    res = marine_risk.analyze({}, agent_results=[wx])
    assert res["risk_level"] != "low"
    assert res["risk_score"] >= 2


def test_advisory_wind_reason_labels_peak_and_now(monkeypatch):
    """'Wind 12 kn, gusts 17 kn' (tile) vs 'Wind up to 25 kn (gusts 32 kn)'
    (text) read as a contradiction; the text must now say which is peak
    and which is now."""
    advisory = _patch_advisory_world(monkeypatch, gust_kn=17, wind_kn=12)
    monkeypatch.setattr(
        advisory.fc, "get_point_forecast",
        lambda *a, **k: {
            "source": "mock",
            "now": {"wave_height_m": 1.48, "swell_height_m": 0.4,
                    "wind_kn": 12, "gust_kn": 17, "current_kn": 0.5,
                    "current_dir_deg": 90},
            "next24h": {"wave_max_m": 1.6, "gust_max_kn": 20,
                        "rain_total_mm": 0.0},
            "next48h": {"wave_max_m": 1.6, "wind_max_kn": 25,
                        "gust_max_kn": 32},
        })
    res = advisory.build_advisory(15.16, 82.09)
    r = next(r for r in res["reasons"] if r["code"] == "wind_strong")
    assert r["severity"] == "caution"
    assert "peak" in r["msg"] and "Right now: 12 kn" in r["msg"]


def test_advisory_flags_unusually_strong_current(monkeypatch):
    advisory = _patch_advisory_world(monkeypatch, gust_kn=10)
    monkeypatch.setattr(
        advisory.fc, "get_point_forecast",
        lambda *a, **k: {
            "source": "mock",
            "now": {"wave_height_m": 0.8, "swell_height_m": 0.4,
                    "wind_kn": 10, "gust_kn": 10, "current_kn": 6.03,
                    "current_dir_deg": 110},
            "next24h": {"wave_max_m": 0.9, "gust_max_kn": 10,
                        "rain_total_mm": 0.0},
            "next48h": {"wave_max_m": 0.9, "wind_max_kn": 10,
                        "gust_max_kn": 10},
        })
    res = advisory.build_advisory(15.16, 82.09)
    codes = [r["code"] for r in res["reasons"]]
    assert "current_strong" in codes
