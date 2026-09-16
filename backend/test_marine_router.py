import json
import tempfile
import unittest
from pathlib import Path

from marine_router import MarineRoutePlanner, OfficialBoundaryStore


class MarineRoutePlannerTests(unittest.TestCase):
    def test_cross_coast_route_uses_bounded_coarse_detour(self):
        # Synthetic authority geometry: navigable sea rectangle with a tall
        # land/prohibited-shaped hole. The east-west route must go around its
        # southern edge, matching the expensive cross-India search pattern.
        payload = {
            'type': 'FeatureCollection',
            'metadata': {
                'authority': 'test authority',
                'dataset': 'synthetic route fixture',
                'version': '1',
                'published_at': '2026-01-01T00:00:00Z',
            },
            'features': [{
                'type': 'Feature',
                'properties': {'orca_role': 'navigable'},
                'geometry': {
                    'type': 'Polygon',
                    'coordinates': [
                        [[65, 5], [90, 5], [90, 25], [65, 25], [65, 5]],
                        [[76, 8], [80, 8], [80, 24], [76, 24], [76, 8]],
                    ],
                },
            }],
        }
        path = None
        try:
            with tempfile.NamedTemporaryFile('w', suffix='.geojson', delete=False) as handle:
                json.dump(payload, handle)
                path = Path(handle.name)
            result = MarineRoutePlanner(OfficialBoundaryStore(str(path))).plan(
                (12.18, 81.26), (12.0, 75.0),
            )
        finally:
            if path is not None:
                path.unlink(missing_ok=True)

        self.assertEqual(result['status'], 'ROUTE_GEOMETRY_VERIFIED')
        route = result['routes'][0]
        self.assertGreater(len(route['coordinates']), 2)
        self.assertLess(min(point[0] for point in route['coordinates']), 8.1)


if __name__ == '__main__':
    unittest.main()
