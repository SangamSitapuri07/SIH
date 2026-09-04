"""Tests for the ISRO MOSDAC OCM-3 LIVE adapter (all mocked — no network,
no real credentials; the honest live proof is `python -m pipeline.mosdac_ocm`
on a machine that has the creds)."""
from __future__ import annotations

import pytest

from pipeline import mosdac_ocm, mosdac_auth


@pytest.fixture(autouse=True)
def _no_real_creds(monkeypatch):
    monkeypatch.delenv("MOSDAC_USERNAME", raising=False)
    monkeypatch.delenv("MOSDAC_PASSWORD", raising=False)
    monkeypatch.delenv("ORCA_MOSDAC", raising=False)
    yield


def test_disabled_without_creds():
    assert mosdac_ocm.mosdac_enabled() is False
    monkey = dict(os_environ=False)
    assert mosdac_ocm.mosdac_configured() is False


def test_enabled_with_creds(monkeypatch):
    monkeypatch.setenv("MOSDAC_USERNAME", "u")
    monkeypatch.setenv("MOSDAC_PASSWORD", "p")
    assert mosdac_ocm.mosdac_enabled() is True


def test_env_overrides(monkeypatch):
    monkeypatch.setenv("MOSDAC_USERNAME", "u")
    monkeypatch.setenv("MOSDAC_PASSWORD", "p")
    monkeypatch.setenv("ORCA_MOSDAC", "0")
    assert mosdac_ocm.mosdac_enabled() is False
    monkeypatch.setenv("ORCA_MOSDAC", "1")
    assert mosdac_ocm.mosdac_enabled() is True


def test_granule_date_formats():
    assert mosdac_ocm.granule_date("E06OCM_L2C_LAC_OC_03SEP2026_...h5") == "2026-09-03"
    assert mosdac_ocm.granule_date("chlor_2026-09-03_LAC") == "2026-09-03"
    assert mosdac_ocm.granule_date("xyz_20260903") == "2026-09-03"
    assert mosdac_ocm.granule_date("no-date-here") is None


def test_records_defensive_shapes():
    j = {"records": [{"id": 42, "title": "E06OCM_L2C_LAC_OC_03SEP2026.h5"}]}
    recs = mosdac_ocm._records(j)
    assert len(recs) == 1 and recs[0]["id"] == 42
    assert recs[0]["date"] == "2026-09-03"
    assert mosdac_ocm._records({"totalResults": 0}) == []
    # alternate containers + id keys shouldn't crash
    j2 = {"results": [{"recordId": "abc", "fileName": "f_2026-09-01"}]}
    recs2 = mosdac_ocm._records(j2)
    assert recs2[0]["id"] == "abc" and recs2[0]["date"] == "2026-09-01"


def _patch_live_world(monkeypatch, extractor_value):
    monkeypatch.setenv("MOSDAC_USERNAME", "u")
    monkeypatch.setenv("MOSDAC_PASSWORD", "p")
    # reset the module-level session cache — one test's login must not
    # leak into the next
    monkeypatch.setattr(mosdac_ocm, "_session", None)
    monkeypatch.setattr(mosdac_ocm, "_session_time", 0.0)
    monkeypatch.setattr(mosdac_auth, "login", lambda: object())
    monkeypatch.setattr(
        mosdac_auth, "search",
        lambda *a, **k: {"totalResults": 1, "records": [
            {"id": 991, "title": "E06OCM_L2C_LAC_OC_03SEP2026_x.h5"}]})
    monkeypatch.setattr(
        mosdac_ocm, "_download_granule",
        lambda session, rid: ("/tmp/fake_mosdac_granule.h5", None, 12.3))
    import pipeline.parser as parser
    import pipeline.extractors as extractors
    monkeypatch.setattr(parser, "parse", lambda path: object())
    monkeypatch.setattr(extractors, "extract_chlorophyll",
                        lambda pf, lat, lon, debug=False: extractor_value)


def test_live_chain_success(monkeypatch):
    _patch_live_world(monkeypatch, {
        "value": 0.77, "units": "mg m^-3", "distance_deg": 0.004})
    res = mosdac_ocm._live_chain(20.9, 70.37)
    assert res["value"] == 0.77
    assert res["date"] == "2026-09-03"
    assert res["source"] == mosdac_ocm.SOURCE_LABEL
    assert "LIVE" in res["note"]
    assert res["live_download_s"] == 12.3


def test_live_chain_honest_when_no_granule(monkeypatch):
    _patch_live_world(monkeypatch, None)
    # search returns nothing this time
    monkeypatch.setattr(mosdac_auth, "search", lambda *a, **k: {"totalResults": 0, "records": []})
    res = mosdac_ocm._live_chain(20.9, 70.37)
    assert res.get("value") is None
    assert "live fetch failed" in res["error"]
    assert "no E06OCM_L2C_LAC_OC granule" in res["error"]


def test_live_chain_honest_when_pixel_missing(monkeypatch):
    _patch_live_world(monkeypatch, None)  # extractor finds no valid pixel
    res = mosdac_ocm._live_chain(20.9, 70.37)
    assert res.get("value") is None
    assert "no valid pixel" in res["error"]
    assert "NOAA primary" in res["error"]


def test_live_chain_login_error_is_honest(monkeypatch):
    _patch_live_world(monkeypatch, None)
    def _boom():
        raise mosdac_auth.MosdacAuthError("401 Unauthorized: wrong username/password")
    monkeypatch.setattr(mosdac_auth, "login", _boom)
    res = mosdac_ocm._live_chain(20.9, 70.37)
    assert "login" in res["error"]
    assert "401" in res["error"]


# ── swath direct-reader on a SYNTHETIC HDF5 granule ────────────────────

def test_extract_chl_h5_swath_2d(tmp_path):
    """Simulates an EOS-06 OCM-3 L2C LAC file: 2D lat/lon inside groups,
    land-masked near the point, one valid pixel a few cells away."""
    h5py = __import__("h5py")
    import numpy as np
    p = tmp_path / "fake_ocm3.h5"
    with h5py.File(p, "w") as f:
        lats, lons = np.meshgrid(np.linspace(20.0, 21.0, 20),
                                 np.linspace(70.0, 71.0, 20), indexing="ij")
        f.create_dataset("navigation_data/latitude", data=lats)
        f.create_dataset("navigation_data/longitude", data=lons)
        chl = np.full((20, 20), -32767.0)
        chl[14, 5] = 0.83  # one valid clear-water pixel
        d = f.create_dataset("geophysical_data/chlor_a", data=chl)
        d.attrs["_FillValue"] = -32767.0
        d.attrs["units"] = "mg m^-3"
    res = mosdac_ocm._extract_chl_h5(str(p), 20.5, 70.5)
    assert res is not None and abs(res["value"] - 0.83) < 1e-6
    assert res["distance_deg"] < 0.4
    assert "mg" in res["units"]


def test_extract_chl_h5_pixel_forensics(tmp_path):
    """Review round-5 (2026-09-05): an 8x+ OCM-3-vs-NOAA gap must be
    DIAGNOSABLE — the extractor reports how far the chosen pixel drifted
    and what its own ~3 km neighbourhood reads, so the agent can tell a
    lone HOT pixel (cloud-contamination suspect) from a genuinely high
    patch. Grid reads 0.40 everywhere except one hot 3.20 pixel exactly
    at the query point."""
    h5py = __import__("h5py")
    import numpy as np
    p = tmp_path / "hot_pixel.h5"
    n = 30
    with h5py.File(p, "w") as f:
        lats, lons = np.meshgrid(np.linspace(10.0, 10.3, n),
                                 np.linspace(80.5, 80.8, n), indexing="ij")
        f.create_dataset("latitude", data=lats)
        f.create_dataset("longitude", data=lons)
        chl = np.full((n, n), 0.40)
        chl[15, 15] = 3.20  # lone hot pixel at the query point
        f.create_dataset("CHL", data=chl)
    # point maps exactly onto cell [15, 15] (step = 0.3/29)
    res = mosdac_ocm._extract_chl_h5(str(p), 10.0 + 15 * 0.3 / 29, 80.5 + 15 * 0.3 / 29)
    assert res is not None
    assert abs(res["value"] - 3.20) < 1e-6        # the exact pixel is picked
    assert res["pixel_km"] < 2.0                  # …right at the point
    assert res["ring_valid"] > 100                # whole ~3 km neighbourhood valid
    assert abs(res["ring_median"] - 0.40) < 1e-6  # …and it reads LOW → hot pixel


def test_extract_chl_h5_all_masked_returns_none(tmp_path):
    h5py = __import__("h5py")
    import numpy as np
    p = tmp_path / "masked.h5"
    with h5py.File(p, "w") as f:
        lats, lons = np.meshgrid(np.linspace(20.0, 21.0, 12),
                                 np.linspace(70.0, 71.0, 12), indexing="ij")
        f.create_dataset("geolocation/lat", data=lats)
        f.create_dataset("geolocation/lon", data=lons)
        f.create_dataset("geophysical_data/chl", data=np.full((12, 12), -999.0))
    assert mosdac_ocm._extract_chl_h5(str(p), 20.5, 70.5) is None


def test_records_date_from_dcdate():
    """Real apios shape seen 2026-09-04: title is the numeric id; date
    lives in dcDate/updated."""
    j = {"records": [{"id": 18352886,
                      "dcDate": "2026-09-03T10:15:00Z",
                      "updated": "2026-09-03T11:00:00Z"}]}
    recs = mosdac_ocm._records(j)
    assert recs[0]["date"] == "2026-09-03"


# ── client-side coverage filter (the Maldives-scene lesson) ────────────

def test_boundbox_contains_comma_format():
    bb = "65.0,18.0,72.5,23.5"  # minLon,minLat,maxLon,maxLat
    assert mosdac_ocm._boundbox_contains(bb, 20.9, 70.37) is True
    assert mosdac_ocm._boundbox_contains(bb, 5.0, 60.0) is False
    assert mosdac_ocm._boundbox_contains("", 20.9, 70.37) is None


def test_boundbox_contains_wkt_polygon():
    bb = "POLYGON((53.4 -0.1, 68.2 -0.1, 68.2 8.3, 53.4 8.3, 53.4 -0.1))"
    assert mosdac_ocm._boundbox_contains(bb, 20.9, 70.37) is False
    assert mosdac_ocm._boundbox_contains(bb, 4.0, 60.0) is True


def test_live_chain_skips_non_covering_granules(monkeypatch):
    """The 2026-09-04 bug: search returned south-of-India scenes for a
    Veraval point. Non-covering records must be skipped BEFORE download;
    with no covering candidates the error must say so honestly."""
    monkeypatch.setenv("MOSDAC_USERNAME", "u")
    monkeypatch.setenv("MOSDAC_PASSWORD", "p")
    monkeypatch.setattr(mosdac_ocm, "_session", None)
    monkeypatch.setattr(mosdac_ocm, "_session_time", 0.0)
    monkeypatch.setattr(mosdac_auth, "login", lambda: object())
    monkeypatch.setattr(
        mosdac_auth, "search",
        lambda *a, **k: {"totalResults": 2, "records": [
            {"id": 1, "dcDate": "2026-09-04", "boundbox": "53.4,-0.1,68.2,8.3"},
            {"id": 2, "dcDate": "2026-09-03", "boundbox": "53.4,-0.1,68.2,8.3"}]})
    downloads = []
    monkeypatch.setattr(
        mosdac_ocm, "_download_granule",
        lambda s, rid: downloads.append(rid) or (None, "should-not-be-called", 0.0))
    res = mosdac_ocm._live_chain(20.9, 70.37)
    assert downloads == [], "must NOT download granules that don't cover the point"
    assert "NONE covers this point" in res["error"]
