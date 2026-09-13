import os
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from mosdac_datasets import (
    DATASET_REGISTRY,
    TIER_A_IDS,
    TIER_B_IDS,
    TIER_C_IDS,
    TIER_D_IDS,
    enabled_datasets,
    plan_datasets,
    plan_profile,
    registry_status,
)
from mosdac_provider import MosdacProvider


class MosdacActivationTests(unittest.TestCase):
    def test_activation_matrix(self):
        status = registry_status()
        self.assertEqual(status["tier_s_enabled"], 4)
        self.assertEqual(status["tier_s_verified"], 4)
        self.assertEqual(status["tier_a_disabled"], len(TIER_A_IDS))
        self.assertEqual(status["tier_b_disabled"], len(TIER_B_IDS))
        self.assertEqual(status["tier_c_disabled"], len(TIER_C_IDS))
        self.assertEqual(status["tier_d_disabled"], len(TIER_D_IDS))
        self.assertEqual({spec.tier for spec in enabled_datasets()}, {"S"})

    def test_planner_never_selects_disabled_tiers(self):
        selected = plan_datasets(("wind_speed", "chlorophyll_a", "upwelling_index"))
        self.assertTrue(selected)
        self.assertTrue(all(spec.enabled and spec.tier == "S" for spec in selected))
        self.assertFalse(any(spec.dataset_id in TIER_A_IDS for spec in selected))

    def test_profiles_select_only_verified_enabled_products(self):
        self.assertEqual({spec.dataset_id for spec in plan_profile("FISHING")}, {"E06OCM_L4_AC", "E06SCT_L4_UI", "E06SCT_L4_AWV6HOURLY", "E06SCT_L3_WW12"})
        self.assertTrue(all(spec.enabled for spec in plan_profile("MARINE_ECOLOGY")))

    def test_no_credentials_fails_closed(self):
        old_username = os.environ.pop("MOSDAC_USERNAME", None)
        old_password = os.environ.pop("MOSDAC_PASSWORD", None)
        try:
            with TemporaryDirectory() as cache_dir:
                provider = MosdacProvider(cache_dir)
                result = provider.fetch(DATASET_REGISTRY["E06OCM_L4_AC"], {"date": "latest"})
            self.assertEqual(result["status"], "credential_required")
            self.assertEqual(result["provenance"]["quality"], "missing")
        finally:
            if old_username is not None:
                os.environ["MOSDAC_USERNAME"] = old_username
            if old_password is not None:
                os.environ["MOSDAC_PASSWORD"] = old_password


if __name__ == "__main__":
    unittest.main()
