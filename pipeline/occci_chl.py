"""ESA OC-CCI v6.0 chlorophyll adapter — INDEPENDENT cross-validation.

OC-CCI (Ocean Colour Climate Change Initiative) is the gold-standard
global chlorophyll dataset, produced by Plymouth Marine Laboratory (PML)
on behalf of ESA. It merges SeaWiFS, MODIS-Aqua, MERIS, VIIRS, OLCI-S3A
and OLCI-S3B into a single climate-quality record.

Why add it: the user reported another AI saying our 0.93 mg/m³ value
was wrong. I cross-checked with 3 sources on 2026-08-15 for Chennai
(13.5, 80.5) in the same 0.2° box:

  NOAA VIIRS DINEOF: box mean 0.93   (but 5.14 coastal + 0.28 offshore
                                       averaged — misleading)
  NOAA VIIRS DINEOF: nearest cell 0.28  (open ocean, 0.07° away)
  ESA OC-CCI v6.0:   nearest cell 0.49  (open ocean, ~0.005° away)
  NASA Aqua MODIS:   similar to OC-CCI

The previous ORCA implementation used box-mean, which inflated
coastal blooms with offshore oligotrophic water. The fix in
`erddap_chl.py` takes the nearest cell instead. This new adapter
adds OC-CCI as an independent corroboration.

URL pattern: https://comet.nefsc.noaa.gov/erddap/griddap/occci_v6_daily_1km

Free, no auth, daily, 1 km resolution, 1997-present.
"""
from __future__ import annotations

import json
import math
import urllib.error
import urllib.request
from datetime import datetime
from typing import Any


ERDDAP_BASE = "https://comet.nefsc.noaa.gov/erddap/griddap/occci_v6_daily_1km"
SOURCE_LABEL = "ESA OC-CCI v6.0 (PML, 1 km, IPCC standard)"


def build_query_url(
    lat: float,
    lon: float,
    date: str | datetime,
    radius_deg: float = 0.05,
    variable: str = "chlor_a",
    ext: str = ".json",
) -> str:
    """Build OC-CCI ERDDAP .json query URL.

    OC-CCI is 2D (no altitude axis), so order is: time, lat, lon.
    """
    if isinstance(date, datetime):
        date_str = date.strftime("%Y-%m-%d")
    else:
        date_str = str(date)
    time_constraint = f"({date_str}T12:00:00Z):1:({date_str}T12:00:00Z)"
    lat_lo, lat_hi = lat - radius_deg, lat + radius_deg
    lon_lo, lon_hi = lon - radius_deg, lon + radius_deg
    query = (
        f"{variable}[{time_constraint}]"
        f"[({lat_lo:.4f}):1:({lat_hi:.4f})]"
        f"[({lon_lo:.4f}):1:({lon_hi:.4f})]"
    )
    return f"{ERDDAP_BASE}{ext}?{query}"


def get_chlorophyll(
    lat: float,
    lon: float,
    date: str | datetime,
    max_age_days: int = 7,
) -> dict[str, Any] | None:
    """Fetch ESA OC-CCI chlorophyll for (lat, lon) on date.

    Returns nearest cell (not box mean — chlorophyll is highly
    non-linear spatially, esp. near coasts).
    """
    last_err = None
    dates_to_try = [date] if date is not None else []
    if date is None:
        from datetime import date as date_cls, timedelta
        today = date_cls.today()
        dates_to_try = [
            (today - timedelta(days=d)).isoformat()
            for d in range(1, max_age_days)
        ]

    for try_date in dates_to_try:
        url = build_query_url(lat, lon, try_date, radius_deg=0.05)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ORCA/1.0"})
            with urllib.request.urlopen(req, timeout=15) as r:
                data = json.loads(r.read().decode("utf-8"))
            rows = data.get("table", {}).get("rows", [])
            if not rows:
                last_err = "empty response"
                continue

            # Find nearest cell with a valid value
            nearest = None
            nearest_dist = float("inf")
            n_vals = 0
            min_v = float("inf")
            max_v = -float("inf")
            actual_time = None
            for row in rows:
                v = row[3]  # chlor_a is column index 3
                if v is None:
                    continue
                n_vals += 1
                if actual_time is None:
                    actual_time = row[0]
                min_v = min(min_v, v)
                max_v = max(max_v, v)
                cell_lat = row[1]
                cell_lon = row[2]
                d = math.hypot(cell_lat - lat, cell_lon - lon)
                if d < nearest_dist:
                    nearest_dist = d
                    nearest = v
            if nearest is None:
                last_err = "no valid values"
                continue
            return {
                "value": nearest,
                "box_min": min_v if n_vals else None,
                "box_max": max_v if n_vals else None,
                "n_samples": n_vals,
                "units": "mg m^-3",
                "lat": lat,
                "lon": lon,
                "distance_deg": round(nearest_dist, 4),
                "source": SOURCE_LABEL,
                "date": (actual_time or str(try_date))[:10],
                "log10": math.log10(nearest) if nearest > 0 else None,
            }
        except urllib.error.HTTPError as e:
            last_err = f"HTTP {e.code}"
            continue
        except Exception as e:  # noqa: BLE001
            last_err = f"{type(e).__name__}: {e}"[:120]
            continue

    return {
        "error": f"OC-CCI failed: {last_err}",
        "source": SOURCE_LABEL,
    }
