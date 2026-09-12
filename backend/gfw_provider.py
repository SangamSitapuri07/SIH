"""Global Fishing Watch v3 4Wings provider."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
from typing import Any, Dict, Iterable, Optional

import httpx

GFW_REPORT_URL = "https://gateway.api.globalfishingwatch.org/v3/4wings/report"
GFW_DATASET = "public-global-fishing-effort:latest"
GFW_CACHE_TTL = timedelta(hours=6)
GFW_MAX_RANGE = timedelta(days=90)
GFW_MAX_ENTRIES = 128


class GfwProvider:
    def __init__(self, cache_root: Optional[str] = None, token: Optional[str] = None):
        self.token = (token if token is not None else os.getenv("GFW_API_TOKEN", "")).strip()
        root = cache_root or os.getenv("ORCA_GFW_CACHE") or os.path.join(os.getenv("TEMP", "."), "orca_gfw")
        self.cache_root = Path(root)
        self.cache_root.mkdir(parents=True, exist_ok=True)
        self.state_path = self.cache_root / "gfw_cache.json"

    @property
    def configured(self) -> bool:
        return bool(self.token)

    @staticmethod
    def _validate_coordinates(latitude: float, longitude: float, radius_deg: float) -> None:
        if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
            raise ValueError("Invalid fishing-effort coordinates")
        if not 0 < radius_deg <= 5:
            raise ValueError("Fishing-effort radius must be greater than 0 and no more than 5 degrees")

    @staticmethod
    def _polygon(latitude: float, longitude: float, radius_deg: float) -> Dict[str, Any]:
        min_lon, max_lon = longitude - radius_deg, longitude + radius_deg
        min_lat, max_lat = latitude - radius_deg, latitude + radius_deg
        return {"type": "Polygon", "coordinates": [[[min_lon, min_lat], [max_lon, min_lat], [max_lon, max_lat], [min_lon, max_lat], [min_lon, min_lat]]]}

    @staticmethod
    def _date_range(start_date: Optional[str], end_date: Optional[str]) -> Dict[str, str]:
        safe_end = datetime.now(timezone.utc).date() - timedelta(days=4)
        try:
            requested_end = date.fromisoformat(end_date) if end_date else safe_end
            requested_start = date.fromisoformat(start_date) if start_date else requested_end - timedelta(days=30)
        except ValueError as exc:
            raise ValueError("GFW dates must use YYYY-MM-DD") from exc
        actual_end = min(requested_end, safe_end)
        actual_start = max(min(requested_start, actual_end), actual_end - GFW_MAX_RANGE)
        return {
            "requested_start": start_date or actual_start.isoformat(),
            "requested_end": end_date or actual_end.isoformat(),
            "start_date": actual_start.isoformat(),
            "end_date": actual_end.isoformat(),
        }

    @staticmethod
    def _records(payload: Any) -> Iterable[Dict[str, Any]]:
        if isinstance(payload, list):
            for item in payload:
                yield from GfwProvider._records(item)
        elif isinstance(payload, dict):
            keys = {"hours", "total", "vessel_id", "vesselId", "vesselIDs", "vesselIds", "vessel_ids", "flag", "geartype"}
            if keys.intersection(payload):
                yield payload
            else:
                for value in payload.values():
                    yield from GfwProvider._records(value)

    @staticmethod
    def _value(record: Dict[str, Any], *keys: str) -> Any:
        return next((record[key] for key in keys if record.get(key) is not None), None)

    @staticmethod
    def _ids(record: Dict[str, Any]) -> set[str]:
        value = GfwProvider._value(record, "vessel_id", "vesselId", "vessel_ids", "vesselIds", "vesselIDs")
        if isinstance(value, (list, tuple, set)):
            return {str(item) for item in value if item is not None}
        return {str(value)} if isinstance(value, str) and value else set()

    def _state(self) -> Dict[str, Any]:
        try:
            value = json.loads(self.state_path.read_text(encoding="utf-8"))
            return value if isinstance(value, dict) else {}
        except (OSError, ValueError):
            return {}

    def _write_state(self, state: Dict[str, Any]) -> None:
        temporary = self.state_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(state, ensure_ascii=True, sort_keys=True), encoding="utf-8")
        temporary.replace(self.state_path)

    def _cache_key(self, operation: str, latitude: float, longitude: float, radius_deg: float, dates: Dict[str, str]) -> str:
        value = json.dumps({"operation": operation, "lat": latitude, "lon": longitude, "radius": radius_deg, "start": dates["start_date"], "end": dates["end_date"]}, sort_keys=True)
        return hashlib.sha256(value.encode()).hexdigest()

    def _cached(self, key: str, state: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        item = state.get("entries", {}).get(key)
        if not isinstance(item, dict):
            return None
        try:
            fetched = datetime.fromisoformat(item["fetched_at"].replace("Z", "+00:00"))
        except (KeyError, ValueError):
            return None
        if datetime.now(timezone.utc) - fetched > GFW_CACHE_TTL:
            return None
        result = dict(item)
        result["status"] = "cached"
        return result

    def _save_success(self, key: str, result: Dict[str, Any], state: Dict[str, Any]) -> None:
        entries = state.setdefault("entries", {})
        entries[key] = result
        if len(entries) > GFW_MAX_ENTRIES:
            recent = sorted(entries.items(), key=lambda item: item[1].get("fetched_at", ""), reverse=True)
            state["entries"] = dict(recent[:GFW_MAX_ENTRIES])
        self._write_state(state)

    @staticmethod
    def _error(status: str, reason: str, rate_limited: bool = False, headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
        result = {"status": status, "source": "GFW", "error": reason}
        if rate_limited:
            result["rate_limited"] = True
        if headers:
            result["rate_limit"] = {key: value for key, value in headers.items() if key.lower().startswith("x-ratelimit") or key.lower() == "retry-after"}
        return result

    def _normalize(self, operation: str, payload: Any, latitude: float, longitude: float, radius_deg: float, dates: Dict[str, str]) -> Dict[str, Any]:
        records = list(self._records(payload))
        ids = set().union(*(self._ids(record) for record in records))
        hours = sum(float(self._value(record, "hours") or 0) for record in records)
        if not hours and isinstance(payload, dict) and isinstance(payload.get("total"), (int, float)):
            hours = float(payload["total"])
        result: Dict[str, Any] = {
            "hours": round(hours, 6), "value": round(hours, 6), "fishing_hours": round(hours, 6), "unit": "hours",
            "vessel_ids": len(ids), "fishing_vessel_ids": len(ids),
            "lat": latitude, "lon": longitude, "radius_deg": radius_deg,
            "start_date": dates["start_date"], "end_date": dates["end_date"],
            "requested_start": dates["requested_start"], "requested_end": dates["requested_end"],
            "n_entries": len(records),
        }
        if operation == "fleet":
            flag_ids: Dict[str, set[str]] = {}
            gear_ids: Dict[str, set[str]] = {}
            flag_counts: Dict[str, int] = {}
            gear_counts: Dict[str, int] = {}
            count = 0
            for record in records:
                record_ids = self._ids(record)
                record_count = len(record_ids) or int(self._value(record, "vesselIDs", "vesselIds", "vessel_ids") or 0)
                count += record_count
                flag = self._value(record, "flag")
                gear = self._value(record, "geartype", "gear_type")
                if flag:
                    key = str(flag)
                    flag_ids.setdefault(key, set()).update(record_ids)
                    flag_counts[key] = flag_counts.get(key, 0) + record_count
                if gear:
                    key = str(gear)
                    gear_ids.setdefault(key, set()).update(record_ids)
                    gear_counts[key] = gear_counts.get(key, 0) + record_count
            by_flag = {key: len(value) if value else flag_counts[key] for key, value in flag_ids.items()}
            by_gear = {key: len(value) if value else gear_counts[key] for key, value in gear_ids.items()}
            result.update({"vessel_count": len(ids) or count, "fleet_vessel_count": len(ids) or count, "by_flag": by_flag, "fleet_by_flag": by_flag, "by_gear": by_gear, "fleet_by_gear": by_gear})
        return result

    def _report(self, operation: str, latitude: float, longitude: float, radius_deg: float, dates: Dict[str, str], group_by: str, token: Optional[str]) -> Dict[str, Any]:
        auth_token = (token if token is not None else self.token).strip()
        if not auth_token:
            return self._error("token_required", "GFW_API_TOKEN not set")
        try:
            self._validate_coordinates(latitude, longitude, radius_deg)
        except ValueError as exc:
            return self._error("invalid_request", str(exc))
        state = self._state()
        key = self._cache_key(operation, latitude, longitude, radius_deg, dates)
        cached = self._cached(key, state)
        if cached:
            return cached
        cooldown = state.get("rate_limited_until")
        if cooldown:
            try:
                if datetime.now(timezone.utc) < datetime.fromisoformat(cooldown.replace("Z", "+00:00")):
                    return self._error("rate_limited", "GFW cooldown is active", True)
            except ValueError:
                pass
        params = {"datasets[0]": GFW_DATASET, "date-range": f"{dates['start_date']}T00:00:00.000Z,{dates['end_date']}T00:00:00.000Z", "format": "JSON", "spatial-resolution": "LOW", "temporal-resolution": "ENTIRE", "group-by": group_by, "spatial-aggregation": "true"}
        headers = {"Authorization": f"Bearer {auth_token}", "Content-Type": "application/json", "Accept": "application/json"}
        body = {"geojson": self._polygon(latitude, longitude, radius_deg)}
        try:
            with httpx.Client(timeout=30.0, follow_redirects=True, headers=headers) as client:
                response = client.post(GFW_REPORT_URL, params=params, json=body)
                if response.status_code == 429:
                    response_headers = dict(response.headers)
                    retry_after = int(response_headers.get("Retry-After", "0") or 0)
                    remaining = response_headers.get("x-ratelimit-daily-remaining-requests")
                    if remaining not in (None, "0") and retry_after > 0:
                        response = client.post(GFW_REPORT_URL, params=params, json=body)
                    if response.status_code == 429:
                        reset_hours = float(response_headers.get("x-ratelimit-daily-reset-hours", "1") or 1)
                        state["rate_limited_until"] = (datetime.now(timezone.utc) + timedelta(hours=max(reset_hours, 1 / 60))).isoformat().replace("+00:00", "Z")
                        state["last_headers"] = response_headers
                        self._write_state(state)
                        return self._error("rate_limited", "GFW rate limit reached", True, response_headers)
                if response.status_code == 401:
                    return self._error("authentication_failed", "GFW authentication failed")
                if response.status_code == 403:
                    return self._error("permission_denied", "GFW dataset permission denied")
                response.raise_for_status()
                payload = response.json()
            result = self._normalize(operation, payload, latitude, longitude, radius_deg, dates)
            result.update({"status": "fresh", "fetched_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "source": "Global Fishing Watch", "dataset": GFW_DATASET, "source_url": GFW_REPORT_URL})
            self._save_success(key, result, state)
            return result
        except (httpx.HTTPError, ValueError, OSError) as exc:
            return self._error("unavailable", f"GFW request failed: {type(exc).__name__}")

    def fetch_effort(self, latitude: float, longitude: float, start_date: Optional[str] = None, end_date: Optional[str] = None, radius_deg: float = 0.5, token: Optional[str] = None) -> Dict[str, Any]:
        try:
            dates = self._date_range(start_date, end_date)
        except ValueError as exc:
            return self._error("invalid_request", str(exc))
        return self._report("effort", latitude, longitude, radius_deg, dates, "VESSEL_ID", token)

    def fetch_fishing_vessels_in_region(self, latitude: float, longitude: float, radius_deg: float = 0.5, start_date: Optional[str] = None, end_date: Optional[str] = None, token: Optional[str] = None) -> Dict[str, Any]:
        try:
            dates = self._date_range(start_date, end_date)
        except ValueError as exc:
            return self._error("invalid_request", str(exc))
        return self._report("fleet", latitude, longitude, radius_deg, dates, "FLAGANDGEARTYPE", token)


def get_fishing_effort(lat: float, lon: float, start_date: str, end_date: str, radius_deg: float = 0.5, token: Optional[str] = None) -> Dict[str, Any]:
    return GfwProvider(token=token).fetch_effort(lat, lon, start_date, end_date, radius_deg, token)


def get_fishing_vessels_in_region(lat: float, lon: float, radius_deg: float = 0.5, start_date: Optional[str] = None, end_date: Optional[str] = None, token: Optional[str] = None) -> Dict[str, Any]:
    return GfwProvider(token=token).fetch_fishing_vessels_in_region(lat, lon, radius_deg, start_date, end_date, token)
