import unittest
from types import SimpleNamespace
from datetime import datetime, timedelta, timezone
from trip_planner import TripPlanningEngine


class Provider:
    def verify_route(self, from_lat, from_lon, to_lat, to_lon):
        return {
            'ok': True, 'status': 'REFERENCE_ROUTE_GEOMETRY',
            'reason': 'Reference geometry only.', 'regulatory_verified': False,
            'distance_km': 400.0, 'distance_nm': 216.0,
            'legs': [[from_lat, from_lon], [to_lat, to_lon]],
            'sources': ['Marine Regions'],
        }

    def fetch_zone_snapshot(self, lat, lon, include_secondary=False):
        start = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
        times = [(start + timedelta(hours=i)).strftime('%Y-%m-%dT%H:00') for i in range(168)]
        return {
            'latitude': lat, 'longitude': lon,
            'variables': {},
            'hourly_forecast': {
                'time': times,
                'wave_height_m': [1.2] * 168,
                'wind_speed_kn': [10.0] * 168,
                'wind_gust_kn': [18.0] * 168,
            },
            'sources_used': [], 'sources_failed': [],
        }


class TripPlannerTests(unittest.TestCase):
    def request(self, **changes):
        values = dict(departure_at=None, duration_days=3, area_lat=18.5,
                      area_lon=72.5, area_radius_km=50, target_fish=['pomfret'],
                      boat_capacity_kg=500, crew_size=4, fuel_liters=200,
                      fuel_burn_lph=8, fuel_reserve_percent=30,
                      cruise_speed_kn=8, max_wave_m=2.5,
                      max_wind_kn=20, max_gust_kn=34,
                      experience_level='expert')
        values.update(changes)
        return SimpleNamespace(**values)

    def test_builds_complete_72_hour_offline_timeline(self):
        plan = TripPlanningEngine(Provider()).generate(self.request())
        self.assertEqual(len(plan['timeline']), 72)
        self.assertEqual(plan['verdict'], 'GOOD')
        self.assertTrue(plan['offline_ready'])
        self.assertEqual(plan['targets']['fish_activity_status'], 'NOT_MODELLED')
        self.assertEqual(plan['decision_engine']['type'], 'RULE_BASED_NOT_ML')
        self.assertEqual(len(plan['package_sha256']), 64)

    def test_vessel_limit_drives_no_go_without_fake_probability(self):
        plan = TripPlanningEngine(Provider()).generate(self.request(max_wave_m=1.0))
        self.assertEqual(plan['verdict'], 'NO_GO')
        self.assertGreater(len(plan['alerts']), 0)
        self.assertNotIn('storm_probability', plan['timeline'][0])

    def test_bundles_offline_route_and_uses_route_distance_for_fuel(self):
        plan = TripPlanningEngine(Provider()).generate(self.request(
            departure_lat=18.92, departure_lon=72.2,
            fuel_liters=200, fuel_burn_lph=5,
        ))
        self.assertEqual(plan['offline_navigation']['distance_km'], 400.0)
        self.assertEqual(len(plan['offline_navigation']['geometry']), 2)
        self.assertEqual(plan['fuel_assessment']['route_one_way_km'], 400.0)
        self.assertEqual(plan['fuel_assessment']['status'], 'INSUFFICIENT')
        self.assertEqual(plan['travel_assessment']['status'], 'FEASIBLE_DIRECT_OUT_AND_BACK')
        self.assertEqual(plan['verdict'], 'NO_GO')

    def test_route_too_long_for_trip_duration_is_no_go(self):
        class LongRouteProvider(Provider):
            def verify_route(self, *args):
                route = super().verify_route(*args)
                route.update(distance_km=1018.0, distance_nm=549.7)
                return route

        plan = TripPlanningEngine(LongRouteProvider()).generate(self.request(
            departure_lat=11.32, departure_lon=81.41,
            duration_days=3, fuel_liters=2000, fuel_burn_lph=5,
        ))
        self.assertEqual(plan['travel_assessment']['status'], 'EXCEEDS_TRIP_DURATION')
        self.assertGreater(plan['travel_assessment']['direct_round_trip_hours'], 72)
        self.assertEqual(plan['verdict'], 'NO_GO')


if __name__ == '__main__':
    unittest.main()
