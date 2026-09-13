"""MOSDAC dataset registry and activation planner.

This module deliberately separates catalog knowledge from activation. Dataset IDs
are never fetched merely because they are registered. Only enabled datasets are
eligible for planning, and Tier-A/B/C/D entries remain disabled by default.
"""

from dataclasses import dataclass, field
from datetime import timedelta
from typing import Any, Dict, Iterable, List


@dataclass(frozen=True)
class DatasetSpec:
    dataset_id: str
    tier: str
    enabled: bool
    provider: str
    product_name: str
    description: str
    temporal_resolution: str
    spatial_resolution: str
    variables: tuple[str, ...]
    parser: str
    normalizer: str
    cache_ttl: timedelta
    requirements: tuple[str, ...]
    supports_background_sync: bool
    supports_on_demand: bool
    feature_flag: str
    metadata_verified: bool = False
    activation_note: str = ""
    implemented: bool = False
    verification_status: str = "REGISTERED"


TIER_S = (
    DatasetSpec(
        "E06OCM_L4_AC", "S", True, "MOSDAC", "Analyzed Chlorophyll",
        "Primary fishing and ecology satellite indicator.", "analyzed product", "catalogue-defined",
        ("chlorophyll_a", "quality_flag", "latitude", "longitude"),
        "mosdac_netcdf_or_hdf5", "orca_chlorophyll", timedelta(hours=6),
        ("MOSDAC_USERNAME", "MOSDAC_PASSWORD", "official_catalogue_metadata"),
        False, True, "ORCA_MOSDAC_TIER_S", activation_note="Live search, authenticated download, parsing, normalization, and cache verified against a real product.", implemented=True, verification_status="VERIFIED",
    ),
    DatasetSpec(
        "E06SCT_L4_AWV6HOURLY", "S", True, "MOSDAC", "6-hourly Analyzed Wind Vectors",
        "Particle Filter Technique near-real-time wind product.", "6-hourly", "catalogue-defined",
        ("u", "v", "wind_speed", "quality_flag", "latitude", "longitude"),
        "mosdac_netcdf_or_hdf5", "orca_wind", timedelta(hours=6),
        ("MOSDAC_USERNAME", "MOSDAC_PASSWORD", "official_catalogue_metadata"),
        False, True, "ORCA_MOSDAC_TIER_S", activation_note="Live search, authenticated download, u/v vector parsing, and cache verified against live MOSDAC API.", implemented=True, verification_status="VERIFIED",
    ),
    DatasetSpec(
        "E06SCT_L4_UI", "S", True, "MOSDAC", "Upwelling Index",
        "Indian Ocean upwelling/PFZ supporting indicator.", "catalogue-defined", "catalogue-defined",
        ("upwelling_index", "quality_flag", "latitude", "longitude"),
        "mosdac_netcdf_or_hdf5", "orca_upwelling", timedelta(hours=12),
        ("MOSDAC_USERNAME", "MOSDAC_PASSWORD", "official_catalogue_metadata"),
        False, True, "ORCA_MOSDAC_TIER_S", activation_note="Live search, authenticated download, parsing, normalization, and cache verified against a real product.", implemented=True, verification_status="VERIFIED",
    ),
    DatasetSpec(
        "E06OCM_L3_LAC_CQ", "S", False, "MOSDAC", "Coastal Water Quality Composite",
        "Daily coastal/environmental context product.", "daily", "catalogue-defined",
        ("auto_discover", "quality_flag", "latitude", "longitude"),
        "mosdac_netcdf_or_hdf5", "orca_water_quality", timedelta(days=1),
        ("MOSDAC_USERNAME", "MOSDAC_PASSWORD", "official_catalogue_metadata"),
        False, False, "ORCA_MOSDAC_TIER_S", activation_note="Product catalog entry live. Download returned 404 for archived entry; schema-discovery parser ready.", verification_status="PARSER_READY",
    ),
    DatasetSpec(
        "E06SCT_L3_WW12", "S", True, "MOSDAC", "Global Flagged Wind Vectors",
        "Supporting wind vector product at 12.5 km resolution.", "catalogue-defined", "12.5 km",
        ("wind_speed", "wind_direction", "quality_flag", "latitude", "longitude"),
        "mosdac_hdf5_wind", "orca_wind", timedelta(hours=12),
        ("MOSDAC_USERNAME", "MOSDAC_PASSWORD", "official_catalogue_metadata"),
        False, True, "ORCA_MOSDAC_TIER_S", activation_note="Live search, authenticated download, recursive HDF5 parsing, and cache verified against live MOSDAC API.", implemented=True, verification_status="VERIFIED",
    ),
)

TIER_A_IDS = (
    "E06SCT_L2B_WV12", "E06SCT_L4_AWV", "E06SCT_L4_AWV12km", "E06SCT_L3_WV25",
    "E06SCT_L2B_WV25", "E06OCM_L2C_LAC_PS", "E06OCM_L3_LAC_PC", "E06OCM_L2C_LAC_PR",
    "E06OCM_L2C_LAC_OC", "E06OCM_L2C_LAC_GA", "E06OCM_L3_LAC_FL",
)

TIER_B_IDS = (
    "E06OCM_L2C_LAC_AD", "E06OCM_L2C_LAC_EV", "E06OCM_L2C_LAC_SR", "E06SCT_L3_SIG12_HH",
    "E06SCT_L3_SIG12_W", "E06SCT_L3_SIG25_HH", "E06SCT_L3_SIG25_W", "E06SCT_L2A_SIG12",
    "E06SCT_L2A_SIG25", "E06SCT_L1B_SIG",
)

TIER_C_IDS = (
    "E06SCT_L4_BT_GLB", "E06SCT_L4_BT_IND", "E06SCT_L4_BT_NP", "E06SCT_L4_BT_SP",
    "E06SCT_L4_GAM_IND", "E06SCT_L4_GAM_NP", "E06SCT_L4_GAM_SP", "E06SCT_L4_SIG_GLB",
    "E06SCT_L4_SIG_IND", "E06SCT_L4_SIG_NP", "E06SCT_L4_SIG_SP",
)

TIER_D_IDS = (
    "E06SCT_L3_GS_GLB12", "E06SCT_L3_GS_GLB25", "E06SCT_L4_SI_NP", "E06SCT_L4_SM_NP_DLY",
)


def _metadata_only(dataset_id: str, tier: str) -> DatasetSpec:
    return DatasetSpec(
        dataset_id, tier, False, "MOSDAC", "Metadata-only dataset",
        "Registered for future activation; not fetched by default.", "unknown", "unknown", (),
        "not_implemented", "not_implemented", timedelta(days=1),
        ("official_catalogue_metadata",), False, False, f"ORCA_MOSDAC_TIER_{tier}",
        activation_note="Disabled by policy; explicit feature-flag change required.",
    )


DATASET_REGISTRY: Dict[str, DatasetSpec] = {
    spec.dataset_id: spec for spec in TIER_S
}
for _tier, _ids in (("A", TIER_A_IDS), ("B", TIER_B_IDS), ("C", TIER_C_IDS), ("D", TIER_D_IDS)):
    for _dataset_id in _ids:
        DATASET_REGISTRY[_dataset_id] = _metadata_only(_dataset_id, _tier)


def enabled_datasets(registry: Dict[str, DatasetSpec] = DATASET_REGISTRY) -> List[DatasetSpec]:
    return [spec for spec in registry.values() if spec.enabled]


def plan_datasets(requirements: Iterable[str], registry: Dict[str, DatasetSpec] = DATASET_REGISTRY) -> List[DatasetSpec]:
    """Select only enabled datasets whose normalized variables satisfy requirements."""
    requested = set(requirements)
    return [
        spec for spec in enabled_datasets(registry)
        if requested.intersection(spec.variables)
    ]


REQUIREMENT_PROFILES = {
    "SAFETY": ("wind", "waves", "cyclone", "current", "land/route safety"),
    "FISHING": ("chlorophyll_a", "upwelling_index", "wind_speed", "current", "marine conditions"),
    "MARINE_ECOLOGY": ("chlorophyll_a", "water_quality", "phytoplankton", "POC", "PAR", "optical properties"),
    "NAVIGATION": ("wind_speed", "waves", "current", "land/route safety"),
}


def plan_profile(profile: str, registry: Dict[str, DatasetSpec] = DATASET_REGISTRY) -> List[DatasetSpec]:
    """Plan only enabled datasets satisfying the named ORCA profile."""
    try:
        requirements = REQUIREMENT_PROFILES[profile.upper()]
    except KeyError as exc:
        raise ValueError(f"Unknown ORCA requirement profile: {profile}") from exc
    return plan_datasets(requirements, registry)


def registry_status(registry: Dict[str, DatasetSpec] = DATASET_REGISTRY) -> Dict[str, Any]:
    return {
        "total": len(registry),
        "tier_s_enabled": sum(spec.tier == "S" and spec.enabled for spec in registry.values()),
        "tier_s_verified": sum(spec.tier == "S" and spec.verification_status == "VERIFIED" for spec in registry.values()),
        "tier_a_disabled": sum(spec.tier == "A" and not spec.enabled for spec in registry.values()),
        "tier_b_disabled": sum(spec.tier == "B" and not spec.enabled for spec in registry.values()),
        "tier_c_disabled": sum(spec.tier == "C" and not spec.enabled for spec in registry.values()),
        "tier_d_disabled": sum(spec.tier == "D" and not spec.enabled for spec in registry.values()),
        "tier_s_status": {spec.dataset_id: spec.verification_status for spec in registry.values() if spec.tier == "S"},
    }
