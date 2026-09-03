"""Global Fishing Watch (GFW) adapter — real fishing vessel activity.

Global Fishing Watch (https://globalfishingwatch.org) publishes
AIS-derived fishing effort data for >190,000 fishing vessels globally.
The data shows where fishing vessels ACTUALLY go — a ground-truth
proxy for where fish are caught.

This is gold for ORCA because:
- It's a real-world validation: satellite chlorophyll shows where
  plankton are, AIS shows where the boats go. The overlap = good zones.
- It covers the Indian Ocean fully via the IOTC (Indian Ocean
  Tuna Commission) RFMO region.
- Daily resolution, 0.01° grid (1km), 2012-2024.
- Free API for non-commercial research.

Authentication:
- Register at https://globalfishingwatch.org (free)
- Get API Access Token from your profile
- Set the env var GFW_API_TOKEN (or pass token= parameter)

Usage:
    from pipeline.gfw import get_fishing_effort
    hours = get_fishing_effort(19.0, 72.8, "2026-08-01", "2026-08-30")
    # Returns: {"hours": 47.3, "vessel_ids": 12, "source": "GFW IOTC", ...}

For research: https://globalfishingwatch.org/our-apis/
For SDK:      https://github.com/GlobalFishingWatch/gfw-api-python-client
For data:     https://globalfishingwatch.org/data-download/datasets/public-fishing-effort
"""
from __future__ import annotations

import gzip
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path
from typing import Any


# Auto-load .env from project root (so GFW_API_TOKEN can be set
# in .env file without having to export it in every terminal).
def _load_dotenv_quiet(path: Path) -> None:
    if not path.exists():
        return
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k, v = k.strip(), v.strip().strip('"').strip("'")
            if k and k not in os.environ:
                os.environ[k] = v
    except Exception:
        pass


_THIS = Path(__file__).resolve()
for _p in (_THIS.parent.parent, _THIS.parent.parent.parent, Path.cwd()):
    _load_dotenv_quiet(_p / ".env")


# GFW API v3 base URL
GFW_API_BASE = "https://gateway.api.globalfishingwatch.org/v3"

# IOTC = Indian Ocean Tuna Commission RFMO region
DEFAULT_REGION = "IOTC"
DEFAULT_REGION_SOURCE = "RFMO"

# Public fishing effort dataset (since 2012)
DATASET_FISHING_EFFORT = "public-global-fishing-effort:latest"

# GFW free API empirical limit: ~90 days (despite docs saying 366)
GFW_SAFE_MAX_DAYS = 90
# 4 days ago is the most recent data available
GFW_LATEST_DELAY_DAYS = 4


# Browser-like headers — Cloudflare (fronting GFW) blocks bot-looking requests
_BROWSER_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "application/json",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept-Encoding": "gzip, deflate, br",
    "Origin": "https://globalfishingwatch.org",
    "Referer": "https://globalfishingwatch.org/",
}

def get_token() -> str | None:
    """Get the GFW API token from environment."""
    return os.environ.get("GFW_API_TOKEN")


def _clamp_date_range(start_date: str, end_date: str) -> tuple[str, str]:
    """Clamp date range to GFW's allowed window (last 90 days empirically)."""
    today = date.today()
    latest_allowed = today - timedelta(days=GFW_LATEST_DELAY_DAYS)
    earliest_allowed = today - timedelta(days=GFW_SAFE_MAX_DAYS)

    if isinstance(start_date, str):
        start = date.fromisoformat(start_date)
    else:
        start = start_date
    if isinstance(end_date, str):
        end = date.fromisoformat(end_date)
    else:
        end = end_date

    if end < earliest_allowed:
        shift = (earliest_allowed - end).days
        start = start + timedelta(days=shift)
        end = end + timedelta(days=shift)

    if end > latest_allowed:
        end = latest_allowed
        if start > end:
            start = end - timedelta(days=min(30, GFW_SAFE_MAX_DAYS))

    if start > end:
        start = end

    return start.isoformat(), end.isoformat()


def _make_request(url: str, tok: str, method: str = "GET",
                  body: dict | None = None, timeout: int = 60) -> dict | None:
    """Make a GFW API request with browser-like headers and return JSON."""
    headers = {**_BROWSER_HEADERS, "Authorization": f"Bearer {tok}"}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
        if raw[:2] == b"\x1f\x8b":  # gzip magic number
            raw = gzip.decompress(raw)
        return json.loads(raw.decode("utf-8"))


def get_fishing_effort(
    lat: float,
    lon: float,
    start_date: str,
    end_date: str,
    radius_deg: float = 0.5,
    token: str | None = None,
) -> dict[str, Any] | None:
    """Fetch apparent fishing hours near (lat, lon) for a date range.

    Uses the 4Wings API report endpoint with a custom GeoJSON polygon.
    Returns total fishing hours and vessel count within the bbox.

    IMPORTANT: All query params go in the URL (not body). Only the
    geojson polygon goes in the body. URL-encoding must use %3A for
    colons, %2C for commas in date-range.

    Args:
        lat: Latitude
        lon: Longitude
        start_date: Start date (YYYY-MM-DD)
        end_date: End date (YYYY-MM-DD)
        radius_deg: Half-width of bounding box (default 0.5° = ~50km)
        token: GFW API token (default: read from GFW_API_TOKEN env var)

    Returns:
        {
            "hours": float,
            "vessel_ids": int,
            "lat": float, "lon": float,
            "start_date": str, "end_date": str,
            "source": "Global Fishing Watch",
        }
    """
    tok = token or get_token()
    if not tok:
        return {
            "error": "GFW_API_TOKEN not set",
            "note": "register at https://globalfishingwatch.org and set env var",
        }

    actual_start, actual_end = _clamp_date_range(start_date, end_date)
    print(f"[GFW] Querying {actual_start} to {actual_end}", file=sys.stderr)

    bbox = {
        "min_lat": lat - radius_deg,
        "max_lat": lat + radius_deg,
        "min_lon": lon - radius_deg,
        "max_lon": lon + radius_deg,
    }

    # GFW expects dates in ISO 8601 with time component
    start_iso = f"{actual_start}T00:00:00.000Z"
    end_iso = f"{actual_end}T00:00:00.000Z"

    # ALL params as query string, only geojson in body
    # URL-encode colons (:) and commas (,) in date-range
    params = {
        "datasets[0]": DATASET_FISHING_EFFORT,
        "date-range": f"{start_iso},{end_iso}",
        "format": "JSON",
        "spatial-resolution": "LOW",
        "temporal-resolution": "ENTIRE",
        "group-by": "VESSEL_ID",
        "spatial-aggregation": "true",
    }
    query = urllib.parse.urlencode(params)
    url = f"{GFW_API_BASE}/4wings/report?{query}"

    body = {
        "geojson": {
            "type": "Polygon",
            "coordinates": [[
                [bbox["min_lon"], bbox["min_lat"]],
                [bbox["max_lon"], bbox["min_lat"]],
                [bbox["max_lon"], bbox["max_lat"]],
                [bbox["min_lon"], bbox["max_lat"]],
                [bbox["min_lon"], bbox["min_lat"]],
            ]],
        },
    }

    try:
        data = _make_request(url, tok, method="POST", body=body, timeout=60)
        # Real GFW response shape (from docs):
        # {
        #   "total": 497.88,
        #   "entries": [
        #     {
        #       "date": "2026-05-06T00:00:00.000Z",
        #       "vesselIDs": ["3e09e89...", ...],
        #       "hours": 12.4
        #     },
        #     ...
        #   ]
        # }
        # or grouped: entries: [{dataset_key: [...]}]
        total_hours = float(data.get("total", 0) or 0)
        entries = data.get("entries", data.get("data", []))
        all_vessel_ids: set[str] = set()

        def collect_vessels(item: dict) -> None:
            for k in ("vesselIDs", "vesselIds", "vessel_ids", "vessel_id"):
                v = item.get(k)
                if isinstance(v, list):
                    all_vessel_ids.update(str(x) for x in v)
                elif isinstance(v, int):
                    pass  # already a count, not IDs
            for k in ("hours", "Apparent Fishing Hours"):
                v = item.get(k)
                if isinstance(v, (int, float)):
                    nonlocal total_hours
                    if total_hours == 0:
                        total_hours = float(v)

        for entry in entries:
            if isinstance(entry, dict):
                if "vesselIDs" in entry or "hours" in entry or "date" in entry:
                    collect_vessels(entry)
                else:
                    for dataset_key, items in entry.items():
                        if isinstance(items, list):
                            for item in items:
                                if isinstance(item, dict):
                                    collect_vessels(item)
                        elif isinstance(items, dict):
                            collect_vessels(items)

        return {
            "hours": total_hours,
            "vessel_ids": len(all_vessel_ids),
            "vessel_id_sample": sorted(all_vessel_ids)[:3],
            "lat": lat,
            "lon": lon,
            "start_date": actual_start,
            "end_date": actual_end,
            "requested_start": start_date,
            "requested_end": end_date,
            "source": "Global Fishing Watch (POST /4wings/report)",
            "bbox": bbox,
            "n_entries": len(entries),
        }
    except urllib.error.HTTPError as e:
        body_text = ""
        try:
            raw = e.read()
            if raw[:2] == b"\x1f\x8b":
                raw = gzip.decompress(raw)
            body_text = raw.decode("utf-8")[:500]
        except Exception:
            pass
        return {
            "error": f"HTTP {e.code}: {e.reason}",
            "details": body_text,
            "source": "GFW",
        }
    except Exception as e:  # noqa: BLE001
        return {"error": str(e), "source": "GFW"}


def get_fishing_vessels_in_region(
    lat: float,
    lon: float,
    radius_deg: float = 0.5,
    start_date: str | None = None,
    end_date: str | None = None,
    token: str | None = None,
) -> dict[str, Any] | None:
    """List unique fishing vessels active in a bounding box."""
    tok = token or get_token()
    if not tok:
        return {"error": "GFW_API_TOKEN not set"}

    if end_date is None:
        end_date = (date.today() - timedelta(days=GFW_LATEST_DELAY_DAYS)).isoformat()
    if start_date is None:
        start = date.fromisoformat(end_date) - timedelta(days=30)
        start_date = start.isoformat()

    actual_start, actual_end = _clamp_date_range(start_date, end_date)

    bbox = {
        "min_lat": lat - radius_deg,
        "max_lat": lat + radius_deg,
        "min_lon": lon - radius_deg,
        "max_lon": lon + radius_deg,
    }
    start_iso = f"{actual_start}T00:00:00.000Z"
    end_iso = f"{actual_end}T00:00:00.000Z"

    params = {
        "datasets[0]": DATASET_FISHING_EFFORT,
        "date-range": f"{start_iso},{end_iso}",
        "format": "JSON",
        "spatial-resolution": "LOW",
        "temporal-resolution": "ENTIRE",
        "group-by": "FLAGANDGEARTYPE",
        "spatial-aggregation": "true",
    }
    query = urllib.parse.urlencode(params)
    url = f"{GFW_API_BASE}/4wings/report?{query}"

    body = {
        "geojson": {
            "type": "Polygon",
            "coordinates": [[
                [bbox["min_lon"], bbox["min_lat"]],
                [bbox["max_lon"], bbox["min_lat"]],
                [bbox["max_lon"], bbox["max_lat"]],
                [bbox["min_lon"], bbox["max_lat"]],
                [bbox["min_lon"], bbox["min_lat"]],
            ]],
        },
    }

    try:
        data = _make_request(url, tok, method="POST", body=body, timeout=60)
        entries = data.get("entries", data.get("data", []))
        by_flag: dict[str, int] = {}
        by_gear: dict[str, int] = {}
        all_vessel_ids: set[str] = set()

        def collect(item: dict) -> None:
            if not isinstance(item, dict):
                return
            flag = item.get("flag", "UNK") or "UNK"
            gear = item.get("geartype", "UNK") or "UNK"
            vessel_ids = item.get(
                "vesselIDs", item.get("vesselIds", item.get("vessel_ids", []))
            )
            if isinstance(vessel_ids, list):
                count = len(vessel_ids)
                all_vessel_ids.update(str(x) for x in vessel_ids)
            elif isinstance(vessel_ids, int):
                count = vessel_ids
            else:
                count = 0
            if count > 0:
                by_flag[flag] = by_flag.get(flag, 0) + count
                by_gear[gear] = by_gear.get(gear, 0) + count

        for entry in entries:
            if not isinstance(entry, dict):
                continue
            # Flat shape: entry itself has flag/geartype
            if "flag" in entry or "geartype" in entry or "vesselIDs" in entry:
                collect(entry)
            # Grouped shape: {dataset_key: [items]}
            else:
                for dataset_key, items in entry.items():
                    if isinstance(items, list):
                        for item in items:
                            collect(item)
                    elif isinstance(items, dict):
                        collect(items)

        return {
            "vessel_count": len(all_vessel_ids) if all_vessel_ids else sum(by_flag.values()),
            "by_flag": by_flag,
            "by_gear": by_gear,
            "lat": lat,
            "lon": lon,
            "start_date": actual_start,
            "end_date": actual_end,
            "source": "Global Fishing Watch",
            "bbox": bbox,
        }
    except urllib.error.HTTPError as e:
        body_text = ""
        try:
            raw = e.read()
            if raw[:2] == b"\x1f\x8b":
                raw = gzip.decompress(raw)
            body_text = raw.decode("utf-8")[:500]
        except Exception:
            pass
        return {
            "error": f"HTTP {e.code}: {e.reason}",
            "details": body_text,
            "source": "GFW",
        }
    except Exception as e:  # noqa: BLE001
        return {"error": str(e), "source": "GFW"}


# Indian Ocean RFMO + EEZ codes for convenience
INDIAN_OCEAN_REGIONS = {
    "iotc_rfmo": {"code": "IOTC", "source": "RFMO",
                  "description": "Indian Ocean Tuna Commission (all IOTC)"},
    "india_eez": {"code": "356", "source": "EEZ",
                  "description": "India Exclusive Economic Zone"},
    "sri_lanka_eez": {"code": "144", "source": "EEZ",
                      "description": "Sri Lanka EEZ"},
    "maldives_eez": {"code": "462", "source": "EEZ",
                     "description": "Maldives EEZ"},
}
