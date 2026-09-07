"""Tests for the GFW 429-quota fixes (2026-09):

- cooldown survives a "backend restart" (persisted to disk state)
- Retry-After / x-ratelimit-daily-reset-hours drive the pause length
- the error message says WHY (daily cap vs burst) using GFW's own headers
- the success cache survives a restart (disk fallback)
"""
import sys, os, time
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

import pytest

from pipeline import gfw


@pytest.fixture()
def isolated_gfw_state(tmp_path, monkeypatch):
    """Redirect the persistent state file into a tmp dir and reset memory."""
    fake = tmp_path / "gfw_cache.json"
    monkeypatch.setattr(gfw, "_CACHE_FILE", fake)
    monkeypatch.setattr(gfw, "_disk_state", None)
    monkeypatch.setattr(gfw, "_RATE_LIMIT_UNTIL", 0.0)
    monkeypatch.setattr(gfw, "_LAST_HEADERS", {})
    monkeypatch.setattr(gfw, "_result_cache", {})
    yield fake
    monkeypatch.setattr(gfw, "_disk_state", None)


def _fake_429(headers: dict) -> urllib.error.HTTPError:
    err = urllib.error.HTTPError(
        url="https://gateway.api.globalfishingwatch.org/v3/x",
        code=429, msg="Too Many Requests", hdrs=None, fp=None,
    )
    # urllib headers object substitute — our code only calls .get()
    err.headers = headers  # type: ignore[assignment]
    return err


def test_cooldown_survives_restart(isolated_gfw_state, monkeypatch):
    wait = gfw._note_429(_fake_429({"Retry-After": "900"}))
    assert wait == 900
    # simulate backend restart: memory gone, disk stays
    monkeypatch.setattr(gfw, "_RATE_LIMIT_UNTIL", 0.0)
    monkeypatch.setattr(gfw, "_disk_state", None)
    remaining = gfw._rate_limit_remaining()
    assert 850 < remaining <= 900, f"cooldown lost on restart: {remaining}"
    print("✅ cooldown survives restart")


def test_daily_reset_hours_beats_default(isolated_gfw_state):
    wait = gfw._note_429(_fake_429({"x-ratelimit-daily-reset-hours": "12"}))
    assert wait == 12 * 3600, f"daily-reset header ignored: {wait}"
    print("✅ daily-reset-hours drives pause")


def test_retry_after_beats_daily_reset(isolated_gfw_state):
    wait = gfw._note_429(_fake_429({
        "Retry-After": "300",
        "x-ratelimit-daily-reset-hours": "12",
    }))
    assert wait == 300
    print("✅ Retry-After preferred")


def test_quota_explanation_daily(isolated_gfw_state):
    gfw._LAST_HEADERS.update({
        "x-ratelimit-daily-remaining-requests": "0",
        "x-ratelimit-daily-current-usage": "55000",
        "x-ratelimit-daily-reset-hours": "11",
    })
    msg = gfw._quota_explanation()
    assert "DAILY quota" in msg and "11h" in msg
    print("✅ daily explanation:", msg[:80])


def test_quota_explanation_burst(isolated_gfw_state):
    gfw._LAST_HEADERS.update({
        "x-ratelimit-daily-remaining-requests": "48000",
        "x-ratelimit-daily-current-usage": "2000",
    })
    msg = gfw._quota_explanation()
    assert "Burst/per-minute" in msg and "48000" in msg
    print("✅ burst explanation:", msg[:80])


def test_quota_explanation_no_headers(isolated_gfw_state):
    msg = gfw._quota_explanation()
    assert "No rate-limit headers" in msg
    print("✅ no-headers explanation")


def test_success_cache_survives_restart(isolated_gfw_state, monkeypatch):
    key = "gfw:effort:19.00,72.80,0.50,a,b"
    value = {"hours": 47.3, "vessel_ids": 12}
    gfw._cache_put_success(key, value)
    # simulate restart: memory wiped, disk kept
    monkeypatch.setattr(gfw, "_result_cache", {})
    monkeypatch.setattr(gfw, "_disk_state", None)
    hit = gfw._cache_get(key)
    assert hit is not None and hit["hours"] == 47.3
    print("✅ success cache survives restart")


def test_error_never_cached(isolated_gfw_state):
    gfw._cache_put_success("gfw:k", {"error": "HTTP 429"})
    assert gfw._cache_get("gfw:k") is None
    print("✅ errors never cached")


def test_cache_served_during_cooldown(isolated_gfw_state, monkeypatch):
    """A pause must never hide data we already cached — cache beats cooldown."""
    gfw._note_429(_fake_429({"Retry-After": "600"}))
    assert gfw._rate_limit_remaining() > 0
    monkeypatch.setenv("GFW_API_TOKEN", "dummy-token")
    key = "gfw:effort:20.90,70.37,0.50,2026-08-04,2026-09-03"
    gfw._cache_put_success(key, {"hours": 47.3, "vessel_ids": 12})
    r = gfw.get_fishing_effort(20.9, 70.37, "2026-08-04", "2026-09-03")
    assert r is not None and r["hours"] == 47.3
    assert "paused" in r["cache"], r["cache"]
    # and the fake _make_request must never have fired — no monkeypatched stub even set
    print("✅ cache wins over cooldown:", r["cache"])


def test_uncached_point_waits_during_cooldown(isolated_gfw_state, monkeypatch):
    """No cached copy → the paused error must SAY that (honest scope)."""
    gfw._note_429(_fake_429({"Retry-After": "600"}))
    assert gfw._rate_limit_remaining() > 0
    monkeypatch.setenv("GFW_API_TOKEN", "dummy-token")
    r = gfw.get_fishing_effort(10.0, 75.0, "2026-08-01", "2026-09-01")
    assert r is not None and r.get("rate_limited") is True
    assert "No cached copy" in r["error"], r["error"]
    print("✅ uncached point honestly waits during cooldown")
