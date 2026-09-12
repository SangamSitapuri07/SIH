import json
import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

from gfw_provider import GFW_DATASET, GFW_REPORT_URL, GfwProvider


class FakeResponse:
    def __init__(self, payload, status_code=200, headers=None):
        self.payload = payload
        self.status_code = status_code
        self.headers = headers or {}

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"status {self.status_code}")

    def json(self):
        return self.payload


class FakeClient:
    response = FakeResponse({"entries": [{"hours": 2.5}, {"hours": 1.25}]})
    calls = []

    def __init__(self, *args, **kwargs):
        self.kwargs = kwargs

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def post(self, url, params=None, json=None):
        self.calls.append({"url": url, "params": params, "json": json, "headers": self.kwargs.get("headers")})
        return self.response


class GfwProviderTests(unittest.TestCase):
    def test_missing_token_fails_closed(self):
        with patch.dict(os.environ, {"GFW_API_TOKEN": ""}, clear=False):
            with TemporaryDirectory() as cache_dir:
                result = GfwProvider(cache_dir).fetch_effort(20.9, 70.37)
        self.assertEqual(result["status"], "token_required")

    def test_report_request_aggregates_hours_and_caches(self):
        FakeClient.calls = []
        FakeClient.response = FakeResponse({"entries": [{"hours": 2.5}, {"hours": 1.25}]})
        with patch.dict(os.environ, {"GFW_API_TOKEN": "test-token"}, clear=False):
            with TemporaryDirectory() as cache_dir:
                with patch("gfw_provider.httpx.Client", FakeClient):
                    provider = GfwProvider(cache_dir)
                    result = provider.fetch_effort(20.9, 70.37, "2026-08-01", "2026-08-30")
                    cached = provider.fetch_effort(20.9, 70.37, "2026-08-01", "2026-08-30")

        self.assertEqual(result["status"], "fresh")
        self.assertEqual(result["value"], 3.75)
        self.assertEqual(result["unit"], "hours")
        self.assertEqual(result["dataset"], GFW_DATASET)
        self.assertEqual(cached["status"], "cached")
        self.assertEqual(len(FakeClient.calls), 1)
        self.assertEqual(FakeClient.calls[0]["url"], GFW_REPORT_URL)
        self.assertEqual(FakeClient.calls[0]["params"]["datasets[0]"], GFW_DATASET)
        self.assertEqual(FakeClient.calls[0]["json"]["geojson"]["type"], "Polygon")
        self.assertTrue(FakeClient.calls[0]["headers"]["Authorization"].startswith("Bearer "))
        self.assertNotIn("test-token", json.dumps(result))

    def test_dates_clamp_and_fleet_groups_are_normalized(self):
        FakeClient.calls = []
        FakeClient.response = FakeResponse({
            "entries": [
                {"vesselIDs": ["a", "b"], "flag": "IND", "geartype": "drifting_longlines"},
                {"vesselIDs": ["b", "c"], "flag": "IND", "geartype": "trawlers"},
            ]
        })
        with TemporaryDirectory() as cache_dir:
            with patch("gfw_provider.httpx.Client", FakeClient):
                result = GfwProvider(cache_dir, token="test-token").fetch_fishing_vessels_in_region(
                    20.9, 70.37, start_date="2020-01-01", end_date="2099-01-01"
                )
        self.assertEqual(result["vessel_count"], 3)
        self.assertEqual(result["by_flag"], {"IND": 3})
        self.assertEqual(result["by_gear"], {"drifting_longlines": 2, "trawlers": 2})
        self.assertEqual(result["requested_start"], "2020-01-01")
        self.assertNotEqual(result["end_date"], "2099-01-01")
        self.assertEqual(FakeClient.calls[0]["params"]["group-by"], "FLAGANDGEARTYPE")

    def test_daily_quota_cooldown_persists_across_provider_reload(self):
        FakeClient.calls = []
        FakeClient.response = FakeResponse(
            {"error": "Too Many Requests"},
            status_code=429,
            headers={"x-ratelimit-daily-remaining-requests": "0", "x-ratelimit-daily-reset-hours": "1"},
        )
        with TemporaryDirectory() as cache_dir:
            with patch("gfw_provider.httpx.Client", FakeClient):
                first = GfwProvider(cache_dir, token="test-token").fetch_effort(20.9, 70.37, "2026-08-01", "2026-08-02")
                second = GfwProvider(cache_dir, token="test-token").fetch_effort(20.9, 70.37, "2026-08-02", "2026-08-03")
        self.assertTrue(first["rate_limited"])
        self.assertEqual(second["status"], "rate_limited")
        self.assertEqual(len(FakeClient.calls), 1)


if __name__ == "__main__":
    unittest.main()
