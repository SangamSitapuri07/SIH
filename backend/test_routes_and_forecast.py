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


if __name__ == "__main__":
    unittest.main()
