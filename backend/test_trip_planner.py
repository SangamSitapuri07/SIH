import unittest
from types import SimpleNamespace
from datetime import datetime, timedelta, timezone
from trip_planner import TripPlanningEngine


class Provider:
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
        self.assertEqual(len(plan['package_sha256']), 64)

    def test_vessel_limit_drives_no_go_without_fake_probability(self):
        plan = TripPlanningEngine(Provider()).generate(self.request(max_wave_m=1.0))
        self.assertEqual(plan['verdict'], 'NO_GO')
        self.assertGreater(len(plan['alerts']), 0)
        self.assertNotIn('storm_probability', plan['timeline'][0])


if __name__ == '__main__':
    unittest.main()
