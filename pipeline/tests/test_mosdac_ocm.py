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
