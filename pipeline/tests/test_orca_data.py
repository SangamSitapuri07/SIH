"""Tests for the unified orca_data layer (mostly offline with mocked sources)."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from pipeline import orca_data


def _mock_all(**overrides):
    """Replace every source with a stub. Pass overrides to customize."""
    # Patch the lazy getters on orca_data directly — they re-import each
    # call, so patching the source modules won't survive a re-import.
    orca_data._get_noaa = lambda: overrides.get(
        "noaa", lambda *a, **kw: {"error": "mock", "source": "NOAA"}
    )
    orca_data._get_incois = lambda: overrides.get(
        "incois", lambda *a, **kw: {"error": "mock", "source": "INCOIS"}
    )
    orca_data._get_occci = lambda: overrides.get(
        "occci", lambda *a, **kw: {"error": "mock", "source": "OC-CCI"}
    )
    orca_data.get_sst_at_point = overrides.get(
        "sst", lambda *a, **kw: {"error": "mock", "source": "Open-Meteo"}
    )
    orca_data._get_gfw_effort = lambda: overrides.get(
        "gfw_effort", lambda *a, **kw: {"error": "mock", "source": "GFW"}
    )
    orca_data._get_gfw_fleet = lambda: overrides.get(
        "gfw_fleet", lambda *a, **kw: {"error": "mock", "source": "GFW"}
    )


def test_zone_snapshot_offline():
    """All 6 sources fail gracefully, snapshot still returned with errors listed."""
    _mock_all()
    snap = orca_data.zone_snapshot(19.0, 72.8, "2026-08-15", include_gfw=True)
    assert snap["lat"] == 19.0
    assert snap["lon"] == 72.8
    assert snap["date"] == "2026-08-15"
    assert "data_sources_failed" in snap
    # 5 sources: Open-Meteo, NOAA, OC-CCI, INCOIS, GFW-effort, GFW-fleet = 6
    assert len(snap["data_sources_failed"]) == 6
    assert "data_sources_used" in snap
    assert len(snap["data_sources_used"]) == 0
    assert "fetched_at" in snap
    assert snap["pfz_score"] is None
    print("✅ test_zone_snapshot_offline passed")


def test_zone_snapshot_partial():
    """Open-Meteo works, others fail — partial snapshot still valid."""
    _mock_all(
        sst=lambda *a, **kw: {
            "sst_max": 29.6, "sst_min": 28.3, "sst_mean": 29.0,
            "wave_max": 2.86, "wave_mean": 2.1, "n_days": 30,
        },
    )
    snap = orca_data.zone_snapshot(19.0, 72.8, "2026-08-15", include_gfw=True)
    assert snap["sst_max"] == 29.6
    assert snap["sst_mean"] == 29.0
    assert snap["wave_max"] == 2.86
    assert "Open-Meteo Marine (SST + waves)" in snap["data_sources_used"]
    assert len(snap["data_sources_failed"]) == 5
    assert snap["pfz_score"] is not None and snap["pfz_score"] >= 0.5
    print(f"✅ test_zone_snapshot_partial passed (pfz_score={snap['pfz_score']})")


def test_zone_snapshot_full():
    """All 4 sources succeed — full snapshot."""
    _mock_all(
        sst=lambda *a, **kw: {
            "sst_max": 28.5, "sst_min": 28.0, "sst_mean": 28.3, "wave_max": 2.5, "wave_mean": 1.8,
        },
        noaa=lambda *a, **kw: {
            "value": 1.5, "units": "mg m^-3", "source": "NOAA ERDDAP DINEOF",
        },
        incois=lambda *a, **kw: {"error": "skipped, NOAA is primary"},
        gfw_effort=lambda *a, **kw: {"hours": 47.3, "vessel_ids": 12},
        gfw_fleet=lambda *a, **kw: {
            "vessel_count": 5, "by_flag": {"IND": 3, "LKA": 2}, "by_gear": {"trawler": 3, "gillnetter": 2},
        },
    )
    snap = orca_data.zone_snapshot(19.0, 72.8, "2026-08-15", include_gfw=True)
    assert snap["chlorophyll"] == 1.5
    assert snap["chlorophyll_source"].startswith("NOAA")
    assert snap["sst_max"] == 28.5
    assert snap["fishing_hours"] == 47.3
    assert snap["vessel_count"] == 5
    assert snap["fleet_by_flag"]["IND"] == 3
    assert snap["fleet_by_gear"]["trawler"] == 3
    assert snap["pfz_score"] is not None and snap["pfz_score"] >= 0.8
    print(f"✅ test_zone_snapshot_full passed (pfz_score={snap['pfz_score']})")


def test_zone_snapshot_incois_fallback():
    """NOAA fails, INCOIS succeeds — fallback path works."""
    _mock_all(
        noaa=lambda *a, **kw: {"error": "mock"},
        incois=lambda *a, **kw: {
            "value": 0.8, "units": "mg m^-3", "source": "INCOIS LAS",
        },
    )
    snap = orca_data.zone_snapshot(19.0, 72.8, "2026-08-15", include_gfw=False)
    assert snap["chlorophyll"] == 0.8
    assert snap["chlorophyll_source"].startswith("INCOIS")
    assert "INCOIS LAS (backup chlorophyll)" in snap["data_sources_used"]
    print("✅ test_zone_snapshot_incois_fallback passed")


def test_grid_snapshot_offline():
    """Grid call with all sources failing — still returns structure."""
    _mock_all()
    g = orca_data.grid_snapshot(18.0, 19.0, 72.0, 73.0, step_deg=1.0, include_gfw=False)
    assert g["n_points"] == 4
    assert len(g["points"]) == 4
    assert all("data_sources_failed" in p for p in g["points"])
    print(f"✅ test_grid_snapshot_offline passed (n_points={g['n_points']})")


def test_pfz_score_optimal_zone():
    """PFZ score peaks at chlorophyll ~1 mg/m^3 and SST 24-29°C."""
    snap = {"chlorophyll": 1.0, "sst_mean": 27.0, "fishing_hours": 5.0}
    score = orca_data._pfz_score(snap)
    assert score is not None and score >= 0.9
    print(f"✅ test_pfz_score_optimal_zone passed (score={score})")


def test_pfz_score_no_data():
    snap = {}
    assert orca_data._pfz_score(snap) is None
    print("✅ test_pfz_score_no_data passed")


def test_safe_helper():
    """The _safe wrapper never raises, returns (result, error_msg)."""
    def boom():
        raise RuntimeError("kaboom")
    res, err = orca_data._safe(boom, label="X")
    assert res is None
    assert "kaboom" in err
    assert "X" in err
    print("✅ test_safe_helper passed")


if __name__ == "__main__":
    test_zone_snapshot_offline()
    test_zone_snapshot_partial()
    test_zone_snapshot_full()
    test_zone_snapshot_incois_fallback()
    test_grid_snapshot_offline()
    test_pfz_score_optimal_zone()
    test_pfz_score_no_data()
    test_safe_helper()
    print("\n🎉 All 8 orca_data tests passed!")
