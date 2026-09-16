import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from marine_router import MarineRoutePlanner, OfficialBoundaryStore


class MarineRoutePlannerTests(unittest.TestCase):
    def test_local_globe_mask_routes_without_remote_eez_download(self):
        class Globe:
            @staticmethod
            def is_land(lat, lon):
                return False

        with tempfile.TemporaryDirectory() as directory, patch(
            'marine_router._globe_land', Globe(),
        ), patch.dict('os.environ', {
            'ORCA_EEZ_CACHE_PATH': str(Path(directory) / 'missing.geojson'),
        }):
            store = OfficialBoundaryStore()
            result = MarineRoutePlanner(store).plan((18.9, 72.2), (18.5, 72.4))

        self.assertEqual(store.state.status, 'LAND_MASK_AVAILABLE')
        self.assertEqual(result['status'], 'LAND_MASK_ROUTE_GEOMETRY')
        self.assertFalse(result['regulatory_verified'])

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
