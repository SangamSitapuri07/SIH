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
import json
import os
import tempfile
import httpx

from mosdac_datasets import DatasetSpec
from mosdac_parsers import parse_product


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
        request_json = json.dumps(request, sort_keys=True, separators=(",", ":"), default=str)
        digest = hashlib.sha256(request_json.encode()).hexdigest()[:16]
        return f"MOSDAC_{spec.dataset_id}_{digest}"

    def _cache_path(self, spec: DatasetSpec, request: Dict[str, Any]) -> Path:
        return self.cache_root / f"{self.cache_key(spec, request)}.json"

    def cache_result(self, spec: DatasetSpec, request: Dict[str, Any], result: Dict[str, Any]) -> Path:
        """Persist only a successful parsed product; failures never become cache hits."""
        if result.get("status") not in (None, "fresh", "live"):
            raise ValueError("Only fresh MOSDAC results may be cached")
        path = self._cache_path(spec, request)
        path.write_text(json.dumps(result, ensure_ascii=True, sort_keys=True), encoding="utf-8")
        return path

    def read_cached(self, spec: DatasetSpec, request: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        path = self._cache_path(spec, request)
        if not path.is_file():
            return None
        try:
            result = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        fetched_at = result.get("fetched_at") or result.get("provenance", {}).get("fetched_at")
        if not fetched_at:
            return None
        try:
            fetched = datetime.fromisoformat(fetched_at.replace("Z", "+00:00"))
        except ValueError:
            return None
        age = datetime.now(timezone.utc) - fetched
        result["status"] = "fresh" if age <= spec.cache_ttl else "stale"
        return result

    def fetch(self, spec: DatasetSpec, request: Dict[str, Any]) -> Dict[str, Any]:
        """Search and download through the official configuration-driven API flow."""
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
        search_timeout = float(os.getenv("ORCA_PROVIDER_TIMEOUT_SECONDS", "12"))
        download_timeout = float(os.getenv("ORCA_MOSDAC_TIMEOUT_SECONDS", "60"))
        search_url = "https://mosdac.gov.in/apios/datasets.json"
        token_url = "https://mosdac.gov.in/download_api/gettoken"
        download_url = "https://mosdac.gov.in/download_api/download"
        search_params = {key: request[key] for key in ("startTime", "endTime", "count", "boundingBox", "gId") if request.get(key)}
        search_params["datasetId"] = spec.dataset_id
        try:
            with httpx.Client(timeout=download_timeout, follow_redirects=True) as client:
                search_response = client.get(search_url, params=search_params, timeout=search_timeout)
                search_response.raise_for_status()
                search_payload = search_response.json()
                entries = search_payload.get("entries", [])
                if not entries:
                    return {"status": "unavailable", "dataset_id": spec.dataset_id, "reason": "MOSDAC search returned no files."}
                entries.sort(key=lambda e: e.get("startTime", e.get("id", "")), reverse=True)
                entry = entries[0]
                token_response = client.post(token_url, json={"username": self.username, "password": self.password}, timeout=download_timeout)
                if token_response.status_code in (400, 401):
                    return {"status": "authentication_failed", "dataset_id": spec.dataset_id, "reason": "MOSDAC authentication failed."}
                token_response.raise_for_status()
                access_token = token_response.json().get("access_token")
                if not access_token:
                    return {"status": "authentication_failed", "dataset_id": spec.dataset_id, "reason": "MOSDAC authentication returned no access token."}
                raw_dir = self.cache_root / "raw"
                raw_dir.mkdir(parents=True, exist_ok=True)
                filename = Path(str(entry.get("identifier", entry.get("id", "mosdac_product")))).name
                raw_file = raw_dir / filename
                for download_attempt in range(2):
                    with client.stream("GET", download_url, params={"id": entry["id"]}, headers={"Authorization": f"Bearer {access_token}"}, timeout=download_timeout) as response:
                        if response.status_code == 401 and download_attempt == 0:
                            # Token expired — refresh once and retry
                            token_response = client.post(token_url, json={"username": self.username, "password": self.password}, timeout=download_timeout)
                            if token_response.status_code in (400, 401):
                                return {"status": "authentication_failed", "dataset_id": spec.dataset_id, "reason": "MOSDAC token refresh failed."}
                            token_response.raise_for_status()
                            access_token = token_response.json().get("access_token", access_token)
                            continue
                        if response.status_code == 404:
                            return {"status": "download_failed", "dataset_id": spec.dataset_id, "reason": "MOSDAC download returned 404."}
                        response.raise_for_status()
                        with raw_file.open("wb") as output:
                            for chunk in response.iter_bytes():
                                output.write(chunk)
                        break
            result = parse_product(spec, raw_file)
            result.update({
                "status": "live",
                "fetched_at": fetched_at,
                "valid_until": (datetime.fromisoformat(fetched_at.replace("Z", "+00:00")) + spec.cache_ttl).isoformat().replace("+00:00", "Z"),
                "raw_request_id": str(entry["id"]),
                "source_url": download_url,
            })
            self.cache_result(spec, request, result)
            return result
        except httpx.HTTPStatusError as exc:
            reason = f"MOSDAC request failed: HTTP {exc.response.status_code}"
            if exc.response.status_code == 500:
                reason += f" — datasetId '{spec.dataset_id}' may not exist on MOSDAC (500 = unknown ID, not 404)"
            return {
                "status": "unavailable",
                "dataset_id": spec.dataset_id,
                "reason": reason,
                "provenance": Provenance("MOSDAC", spec.dataset_id, search_url, None, fetched_at, None, "unavailable", None).to_dict(),
            }
        except (httpx.HTTPError, KeyError, ValueError, OSError) as exc:
            return {
                "status": "unavailable",
                "dataset_id": spec.dataset_id,
                "reason": f"MOSDAC request failed: {type(exc).__name__}: {exc}",
                "provenance": Provenance("MOSDAC", spec.dataset_id, search_url, None, fetched_at, None, "unavailable", None).to_dict(),
            }

    def parse_file(self, spec: DatasetSpec, raw_file: Path) -> Dict[str, Any]:
        """Parse an actual downloaded product; never fabricate normalized values."""
        result = parse_product(spec, raw_file)
        fetched_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        result["status"] = "fresh"
        result["fetched_at"] = fetched_at
        result["valid_until"] = (
            datetime.fromisoformat(fetched_at.replace("Z", "+00:00")) + spec.cache_ttl
        ).isoformat().replace("+00:00", "Z")
        result["raw_request_id"] = None
        return result
