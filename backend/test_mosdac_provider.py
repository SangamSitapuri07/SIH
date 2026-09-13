import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from mosdac_datasets import DATASET_REGISTRY
from mosdac_provider import MosdacProvider


SAMPLE_ROOT = Path(__file__).parents[1] / "mosdac"


class MosdacProviderTests(unittest.TestCase):
    def test_real_chlorophyll_sample_is_normalized_and_cached(self):
        with TemporaryDirectory() as cache_dir:
            provider = MosdacProvider(cache_dir)
            spec = DATASET_REGISTRY["E06OCM_L4_AC"]
            result = provider.parse_file(spec, SAMPLE_ROOT / "E06OCML4AC_20260330_25km_v1.0.1.nc")
            self.assertEqual(result["status"], "fresh")
            self.assertEqual(result["variable"], "chla")
            self.assertEqual(result["observed_at"], "2026-03-30T00:00:00Z")
            self.assertIn("fetched_at", result)
            provider.cache_result(spec, {"latitude": 20.9, "longitude": 70.37}, result)
            cached = provider.read_cached(spec, {"latitude": 20.9, "longitude": 70.37})
            self.assertEqual(cached["status"], "fresh")
            self.assertEqual(cached["raw_file_reference"], result["raw_file_reference"])

    def test_failed_result_is_not_cached(self):
        with TemporaryDirectory() as cache_dir:
            provider = MosdacProvider(cache_dir)
            spec = DATASET_REGISTRY["E06OCM_L4_AC"]
            with self.assertRaises(ValueError):
                provider.cache_result(spec, {"date": "latest"}, {"status": "unavailable"})
            self.assertIsNone(provider.read_cached(spec, {"date": "latest"}))

    def test_analyzed_wind_sample_parses_uv_components(self):
        with TemporaryDirectory() as cache_dir:
            provider = MosdacProvider(cache_dir)
            spec = DATASET_REGISTRY["E06SCT_L4_AWV6HOURLY"]
            result = provider.parse_file(spec, SAMPLE_ROOT / "E06SCTL4AH_2026255_0000_25km_v1.0.0.nc")
            self.assertEqual(result["status"], "fresh")
            self.assertEqual(result["variable"], "wind_speed")
            self.assertEqual(result["unit"], "m/s")
            self.assertIn("wind_direction", result)
            self.assertEqual(result["quality"], "computed_from_uv")

    def test_hdf5_ww12_sample_parses_wind_data(self):
        with TemporaryDirectory() as cache_dir:
            provider = MosdacProvider(cache_dir)
            spec = DATASET_REGISTRY["E06SCT_L3_WW12"]
            result = provider.parse_file(spec, SAMPLE_ROOT / "E06SCTL3WW2026255_12km_v1.0.5.h5")
            self.assertEqual(result["status"], "fresh")
            self.assertEqual(result["variable"], "wind_speed")
            self.assertEqual(result["unit"], "m/s")
            self.assertIn("observed_at", result)


if __name__ == "__main__":
    unittest.main()

