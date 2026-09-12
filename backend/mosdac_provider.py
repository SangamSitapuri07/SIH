"""Backend-only MOSDAC provider boundary.

The registry and planner are usable without credentials. Actual MOSDAC requests
remain fail-closed until the official catalogue metadata and Download API
contract are verified against an authenticated account.
"""

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional
import hashlib
import os
import tempfile

from mosdac_datasets import DatasetSpec


@dataclass(frozen=True)
class Provenance:
    source: str
    dataset_id: str
    source_url: Optional[str]
    observed_at: Optional[str]
    fetched_at: str
    valid_until: Optional[str]
    quality: str
    raw_request_id: Optional[str]
    raw_file: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return self.__dict__.copy()


class MosdacProvider:
    """Authentication, download, and parsing boundary for MOSDAC datasets."""

    def __init__(self, cache_root: Optional[str] = None):
        self.username = os.getenv("MOSDAC_USERNAME")
        self.password = os.getenv("MOSDAC_PASSWORD")
        self.cache_root = Path(cache_root or os.getenv("ORCA_MOSDAC_CACHE", tempfile.gettempdir())) / "orca_mosdac"
        self.cache_root.mkdir(parents=True, exist_ok=True)

    @property
    def credentials_configured(self) -> bool:
        return bool(self.username and self.password)

    def cache_key(self, spec: DatasetSpec, request: Dict[str, Any]) -> str:
        digest = hashlib.sha256(repr(sorted(request.items())).encode()).hexdigest()[:16]
        return f"{spec.dataset_id}_{digest}"

    def fetch(self, spec: DatasetSpec, request: Dict[str, Any]) -> Dict[str, Any]:
        """Fail closed until official MOSDAC API metadata is configured.

        This is intentionally not a fake success. The repository has no verified
        MOSDAC Download API URL, authentication flow, or authenticated sample
        file, so pretending to download a Tier-S product would violate the data
        policy.
        """
        fetched_at = datetime.now(timezone.utc).isoformat()
        if not self.credentials_configured:
            return {
                "status": "credential_required",
                "dataset_id": spec.dataset_id,
                "reason": "MOSDAC_USERNAME and MOSDAC_PASSWORD are not configured on ORCA Box.",
                "provenance": Provenance(
                    "MOSDAC", spec.dataset_id, None, None, fetched_at, None,
                    "missing", None,
                ).to_dict(),
            }
        return {
            "status": "api_contract_required",
            "dataset_id": spec.dataset_id,
            "reason": "Official MOSDAC catalogue and Download API contract has not been verified in this repository.",
            "provenance": Provenance(
                "MOSDAC", spec.dataset_id, None, None, fetched_at, None,
                "unavailable", None,
            ).to_dict(),
        }

    def parse_file(self, spec: DatasetSpec, raw_file: Path) -> Dict[str, Any]:
        """Dataset parser boundary; never returns fabricated normalized values."""
        if not raw_file.exists() or raw_file.stat().st_size == 0:
            raise ValueError(f"MOSDAC file is missing or empty: {raw_file}")
        raise NotImplementedError(
            f"No verified parser is registered for {spec.dataset_id}; obtain an authenticated sample file and official variable metadata first."
        )
