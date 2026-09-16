import unittest

from fishing_zones import recommend


class Provider:
    def fetch_incois_pfz(self):
        features = []
        for index, lon in enumerate((72.1, 72.2, 72.3, 72.4, 72.5)):
            features.append({
                'properties': {
                    'UID': f'new-{index}', 'Year': 2026, 'Julian_day': 250,
                    'SECTORBOUN': 3, 'Length': 20,
                },
                'geometry': {
                    'type': 'LineString',
                    'coordinates': [[lon, 18.0], [lon, 19.0]],
                },
            })
        features.append({
            'properties': {'UID': 'old', 'Year': 2025, 'Julian_day': 100},
            'geometry': {
                'type': 'LineString',
                'coordinates': [[72.01, 18.0], [72.01, 19.0]],
            },
        })
        return {
            'status': 'fresh', 'source': 'INCOIS PFZ GeoServer',
            'dataset': 'PFZ_Automation:pfzlines', 'features': features,
        }

    def fetch_route_weather_batch(self, points):
        return [{
            'variables': {
                'wave_height_m': 1.0,
                'wind_speed_kn': 8.0,
                'wind_gust_kn': 12.0,
            },
            'sources_used': [{'name': 'Open-Meteo Marine'}],
        } for _ in points]


class FishingZoneTests(unittest.TestCase):
    def test_latest_official_lines_are_weather_gated_and_limited(self):
        result = recommend(Provider(), 18.5, 72.0, max_km=250, limit=4)
        self.assertTrue(result['found'])
        self.assertEqual(len(result['recommendations']), 4)
        self.assertTrue(all(item['weather_state'] == 'GOOD' for item in result['recommendations']))
        self.assertTrue(all(item['uid'] != 'old' for item in result['recommendations']))
        self.assertIn('not catch probability', result['reason'])


if __name__ == '__main__':
    unittest.main()
