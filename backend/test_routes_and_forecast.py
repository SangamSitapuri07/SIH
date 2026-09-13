import unittest
from unittest.mock import patch

import routes_v1
from data_providers import DataProvidersEngine


class RouteAndForecastTests(unittest.TestCase):
    def test_land_crossing_does_not_fabricate_detour(self):
        provider = DataProvidersEngine()
        result = provider.verify_route(22.1, 71.0, 22.2, 71.1)
        self.assertTrue(result["land_hit"])
        self.assertIsNone(result["detour"])
        self.assertEqual(result["legs"], [[22.1, 71.0], [22.2, 71.1]])
        self.assertIn("No verified marine detour", result["reason"])

    def test_route_advisory_marks_missing_live_point_unverified(self):
        class Provider:
            def verify_route(self, from_lat, from_lon, to_lat, to_lon):
                return {
                    "ok": True,
                    "land_hit": False,
                    "distance_km": 1.0,
                    "distance_nm": 0.5,
                    "bearing_deg": 90.0,
                    "legs": [[from_lat, from_lon], [to_lat, to_lon]],
                    "detour": None,
                }

            def fetch_zone_snapshot(self, lat, lon, include_gfw=False):
                return {"error": True, "reason": "upstream unavailable"}

        with patch.object(routes_v1, "providers", Provider()):
            result = routes_v1.route_advisory(20.9, 70.37, 20.8, 70.27)

        self.assertEqual(result["verdict"]["level"], "UNVERIFIED")
        self.assertTrue(all(point["state"] == "unverified" for point in result["points"]))
        self.assertTrue(all(point["wave_m"] is None for point in result["points"]))

    def test_advisory_uses_provider_hourly_values(self):
        class Provider:
            def fetch_zone_snapshot(self, lat, lon, include_gfw=False):
                return {
                    "latitude": lat,
                    "longitude": lon,
                    "timestamp": 1,
                    "variables": {
                        "wave_height_m": 1.0,
                        "wave_period_s": 5.0,
                        "wind_speed_kn": 8.0,
                        "wind_gust_kn": 12.0,
                        "sst_celsius": 28.0,
                        "current_speed_kn": 1.0,
                        "chlorophyll_mg_m3": None,
                    },
                    "hourly_forecast": {
                        "time": ["2026-09-13T00:00", "2026-09-13T01:00"],
                        "wave_height_m": [2.2, 3.8],
                        "wind_speed_kn": [9.0, 21.0],
                        "wind_gust_kn": [13.0, 25.0],
                    },
                    "sources_used": [],
                    "sources_failed": [],
                    "pfz": [],
                }

        class Agent:
            def run_collaborative_reasoning(self, snapshot):
                return {
                    "verdict": "GOOD",
                    "headline_en": "Conditions acceptable",
                    "headline_hi": "",
                    "headline_te": "",
                    "plain_en": "",
                    "plain_hi": "",
                    "agents": [],
                    "data_coverage": {},
                }

        with patch.object(routes_v1, "providers", Provider()), patch.object(routes_v1, "agents_engine", Agent()):
            result = routes_v1.get_advisory(20.9, 70.37)

        self.assertEqual(result["hourly_chart"][0]["wave_m"], 2.2)
        self.assertEqual(result["hourly_chart"][1]["wind_kn"], 21.0)
        self.assertEqual(result["hourly_chart"][1]["state"], "caution")
        self.assertIsNotNone(result["safe_window"])


from safe_window import find_safe_departure_window


class SafeDepartureWindowTests(unittest.TestCase):
    def _make_series(self, count=48, wave=1.5, wind=10.0, gust=18.0, start_iso=None):
        from datetime import datetime, timedelta, timezone
        if start_iso is None:
            base_dt = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
        else:
            base_dt = datetime.fromisoformat(start_iso.replace("Z", "+00:00")).replace(tzinfo=timezone.utc)
        times = [(base_dt + timedelta(hours=i)).strftime("%Y-%m-%dT%H:00:00Z") for i in range(count)]
        waves = [wave] * count if isinstance(wave, (int, float)) or wave is None else wave
        winds = [wind] * count if isinstance(wind, (int, float)) or wind is None else wind
        gusts = [gust] * count if isinstance(gust, (int, float)) or gust is None else gust
        return {"time": times, "wave_height_m": waves, "wind_speed_kn": winds, "wind_gust_kn": gusts}

    def test_t1_safe_window_then_deteriorating(self):
        # 9 hours safe (GOOD), then gust spike to 40 kn
        gusts = [18.0] * 9 + [40.0] * 39
        hourly = self._make_series(count=48, gust=gusts)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "AVAILABLE")
        self.assertEqual(res["duration_hours"], 9)
        self.assertEqual(res["window_quality"], "GOOD")
        self.assertTrue(res["currently_safe"])

    def test_t2_delayed_safe_window(self):
        # 12 hours storm, then 36 hours safe
        waves = [3.5] * 12 + [1.2] * 36
        hourly = self._make_series(count=48, wave=waves)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "AVAILABLE")
        self.assertFalse(res["currently_safe"])
        self.assertEqual(res["duration_hours"], 36)

    def test_t3_twenty_four_hour_storm_then_calm(self):
        waves = [4.0] * 24 + [1.0] * 24
        hourly = self._make_series(count=48, wave=waves)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "AVAILABLE")
        self.assertEqual(res["duration_hours"], 24)

    def test_t4_storm_whole_horizon(self):
        hourly = self._make_series(count=48, wave=4.5)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "UNAVAILABLE")
        self.assertTrue("recommendation_en" in res)
        self.assertTrue("recommendation_hi" in res)
        self.assertTrue("recommendation_te" in res)

    def test_t5_gust_28kn_caution_tier(self):
        hourly = self._make_series(count=48, gust=28.0)  # above GOOD 25, below CAUTION 34
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "CAUTION")
        self.assertEqual(res["window_quality"], "CAUTION")

    def test_t6_metrics_and_trilingual_strings(self):
        hourly = self._make_series(count=48, wave=1.8, wind=14.0, gust=22.0)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["max_wave_m"], 1.8)
        self.assertEqual(res["max_wind_kn"], 14.0)
        self.assertTrue(len(res["recommendation_en"]) > 0)
        self.assertTrue(len(res["recommendation_hi"]) > 0)
        self.assertTrue(len(res["recommendation_te"]) > 0)

    def test_t7_gust_series_all_none_failsafe(self):
        hourly = self._make_series(count=48, gust=None)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "UNAVAILABLE")

    def test_t8_empty_series(self):
        res = find_safe_departure_window({})
        self.assertEqual(res["status"], "UNAVAILABLE")
        self.assertIn("note", res)

    def test_t9_safe_runs_under_minimum_hours(self):
        # alternating 2h safe, 2h unsafe
        waves = ([1.0, 1.0, 4.0, 4.0] * 12)[:48]
        hourly = self._make_series(count=48, wave=waves)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "UNAVAILABLE")

    def test_t10_exactly_three_safe_hours(self):
        waves = [1.0, 1.0, 1.0] + [4.0] * 45
        hourly = self._make_series(count=48, wave=waves)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "AVAILABLE")
        self.assertEqual(res["duration_hours"], 3)

    def test_t11_forty_eight_hour_window_crosses_midnight(self):
        hourly = self._make_series(count=48, wave=1.2, wind=10.0, gust=15.0)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "AVAILABLE")
        self.assertEqual(res["duration_hours"], 48)
        self.assertIsNotNone(res["note"])
        self.assertIn("forecast horizon", res["note"])
        # Verify day names are formatted in trilingual strings
        self.assertRegex(res["recommendation_en"], r"\d{1,2}:\d{2} [AP]M [A-Z][a-z]{2}")
        self.assertTrue(len(res["recommendation_hi"]) > 0)
        self.assertTrue(len(res["recommendation_te"]) > 0)

    def test_t12_same_day_window_no_day_clutter_and_no_note(self):
        # 6h window starting now, then storm for remaining hours
        waves = [1.2] * 6 + [4.0] * 42
        hourly = self._make_series(count=48, wave=waves)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["status"], "AVAILABLE")
        self.assertEqual(res["duration_hours"], 6)
        self.assertIsNone(res["note"])  # closed by weather, not horizon boundary

    def test_t13_half_knot_wind_decimal_display(self):
        hourly = self._make_series(count=48, wind=12.5)
        res = find_safe_departure_window(hourly)
        self.assertEqual(res["max_wind_kn"], 12.5)
        self.assertIn("12.5 kn", res["recommendation_en"])


if __name__ == "__main__":
    unittest.main()


