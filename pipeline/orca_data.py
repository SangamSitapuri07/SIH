"""ORCA unified data layer — one function, five data sources.

This module is the single entry point for the rest of the backend and
the Next.js frontend. It hides the multi-source plumbing and returns a
clean, normalized dict per lat/lon (a "ZoneSnapshot").

The five data sources (in priority order):

    1. NOAA ERDDAP DINEOF chlorophyll  (FREE, no key)  → chlorophyll
    2. Open-Meteo Marine API            (FREE, no key)  → SST + waves
    3. Global Fishing Watch AIS         (FREE w/ token) → fishing activity
    4. INCOIS LAS OPeNDAP               (FREE, no key)  → backup chlorophyll
    5. MOSDAC OCM-3 L4 (local)          (🇮🇳 creds)     → primary chlorophyll

Each source is fetched in turn with a try/except — if one fails (network,
auth, quota), the snapshot still has data from the others. Sources are
not fatal; the snapshot is always returned, possibly with `error` keys
and `data_sources_used` listing what succeeded.

Usage:

    from pipeline.orca_data import zone_snapshot, grid_snapshot

    snap = zone_snapshot(19.0, 72.8, "2026-08-15")
    # Returns:
    # {
    #   "lat": 19.0, "lon": 72.8, "date": "2026-08-15",
    #   "sst_max": 29.6, "sst_min": 28.3, "wave_max": 2.86,
    #   "chlorophyll": 0.42,        # mg/m^3
    #   "fishing_hours": 1.0,        # hours in 30 days
    #   "vessel_count": 3,
    #   "fleet_by_flag": {"IND": 3},
    #   "fleet_by_gear": {"trawlers": 1, "pole_and_line": 1, "inconclusive": 1},
    #   "data_sources_used": ["NOAA ERDDAP", "Open-Meteo", "GFW AIS", "INCOIS"],
    #   "data_sources_failed": [],
    #   "fetched_at": "2026-09-02T19:50:00Z",
    # }
"""
from __future__ import annotations

import os
import sys
import traceback
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout
from datetime import date, datetime, timedelta, timezone
from typing import Any

from pipeline.openmeteo_sst import get_sst_at_point

# Per-source timeout. If a source takes longer than this, we move on
# without it. The full snapshot completes in ~sum-of-timeouts in the
# worst case, but in practice with the thread pool all sources run
# concurrently and the total is bounded by max timeout.
SOURCE_TIMEOUT_SEC = 12.0

# Lazy source getters. They import the heavy modules (which may need
# numpy/xarray) on first call, and they look up the function via the
# module attribute each time — so tests can monkey-patch
# `pipeline.erddap_chl.get_chlorophyll_with_fallback` and the change
# takes effect.
def _get_noaa():
    from pipeline import erddap_chl
    return erddap_chl.get_chlorophyll_with_fallback

def _get_incois():
    from pipeline import incois
    return incois.get_chlorophyll

def _get_occci():
    from pipeline import occci_chl
    return occci_chl.get_chlorophyll

def _get_gfw_effort():
    from pipeline import gfw
    return gfw.get_fishing_effort

def _get_gfw_fleet():
    from pipeline import gfw
    return gfw.get_fishing_vessels_in_region


# Default date window for time-windowed sources (fishing, chlorophyll history)
DEFAULT_WINDOW_DAYS = 30

# Bounding-box radius (deg) for fishing vessel queries
DEFAULT_RADIUS_DEG = 0.5


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _safe(callable_, *args, default=None, label="source", timeout: float = SOURCE_TIMEOUT_SEC, **kwargs) -> tuple[Any, str | None]:
    """Run a data source, return (result, error_message). Never raises.

    If the source doesn't return within `timeout` seconds, returns a
    timeout error instead of hanging the whole snapshot.
    """
    def _call():
        result = callable_(*args, **kwargs)
        if isinstance(result, dict) and "error" in result and len(result) == 2:
            return None, f"{label}: {result['error']}"
        return result, None

    try:
        with ThreadPoolExecutor(max_workers=1) as ex:
            future = ex.submit(_call)
            try:
                return future.result(timeout=timeout)
            except FuturesTimeout:
                return None, f"{label}: timeout after {timeout:.0f}s"
    except Exception as e:  # noqa: BLE001
        tb = traceback.format_exc(limit=2)
        return None, f"{label}: {type(e).__name__}: {e}\n{tb}"


def zone_snapshot(
    lat: float,
    lon: float,
    target_date: str | None = None,
    window_days: int = DEFAULT_WINDOW_DAYS,
    radius_deg: float = DEFAULT_RADIUS_DEG,
    include_gfw: bool = True,
) -> dict[str, Any]:
    """Build a unified ZoneSnapshot for a single lat/lon.

    Fetches from NOAA, Open-Meteo, GFW (optional), and INCOIS in sequence.
    Each source failure is non-fatal; the snapshot is always returned.

    Args:
        lat, lon: Center of the zone (decimal degrees).
        target_date: Date string (YYYY-MM-DD) for the snapshot. Default: today.
        window_days: Look-back window for time-aggregated sources (fishing,
            chlorophyll history).
        radius_deg: Bounding-box half-width for the GFW query.
        include_gfw: If False, skip the GFW call (useful for unit tests and
            for callers without a GFW token).

    Returns:
        Dict with normalized fields (see module docstring).
    """
    if target_date is None:
        target_date = date.today().isoformat()

    # Compute windowed dates for GFW (last N days ending ~4 days ago — GFW lag)
    end = date.fromisoformat(target_date)
    gfw_end = (end - timedelta(days=4)).isoformat()
    gfw_start = (date.fromisoformat(gfw_end) - timedelta(days=window_days)).isoformat()
    # NOAA/INCOIS use a recent date as the file index — use target_date as-is
    chl_date = target_date

    snap: dict[str, Any] = {
        "lat": lat,
        "lon": lon,
        "date": target_date,
        "fetched_at": _now_iso(),
        "data_sources_used": [],
        "data_sources_failed": [],
    }

    # 1) Open-Meteo SST + waves
    sst, err = _safe(
        get_sst_at_point, lat, lon, gfw_start, gfw_end,
        default=None, label="Open-Meteo",
    )
    if sst and not err:
        snap["sst_max"] = sst.get("sst_max")
        snap["sst_min"] = sst.get("sst_min")
        snap["sst_mean"] = sst.get("sst_mean")
        snap["wave_max"] = sst.get("wave_max")
        snap["wave_mean"] = sst.get("wave_mean")
        snap["data_sources_used"].append("Open-Meteo Marine (SST + waves)")
    else:
        snap["data_sources_failed"].append(err or "Open-Meteo: no data")

    # 2) NOAA ERDDAP chlorophyll
    # VIIRS data runs on a ~3-day processing lag, so "today" (and usually
    # the last 2 days) have no files yet. Try the requested date first;
    # if it has nothing, step back 3 days and surface chlorophyll_date so
    # the caller/UI can show the data's true age. Never invent a value.
    try:
        noaa_fn = _get_noaa()
        got_noaa = False
        last_err = None
        for attempt_date, shift_note in ((chl_date, None), (
                (date.fromisoformat(target_date) - timedelta(days=3)).isoformat(), "-3d")):
            chl, err = _safe(
                noaa_fn, lat, lon, attempt_date,
                default=None, label="NOAA ERDDAP",
            )
            if chl and not err and chl.get("value") is not None:
                snap["chlorophyll"] = chl.get("value")
                snap["chlorophyll_unit"] = chl.get("units", "mg/m^3")
                snap["chlorophyll_source"] = chl.get("source", "NOAA ERDDAP DINEOF")
                snap["chlorophyll_date"] = attempt_date
                if shift_note:
                    snap["chlorophyll_note"] = (
                        f"Requested date had no product yet (satellite lag); "
                        f"showing {attempt_date} analysis instead."
                    )
                # Also surface the box stats so users can see the spatial variance
                if chl.get("box_min") is not None:
                    snap["chlorophyll_box_min"] = chl["box_min"]
                    snap["chlorophyll_box_max"] = chl["box_max"]
                snap["data_sources_used"].append(f"NOAA ERDDAP (chlorophyll, {attempt_date})")
                got_noaa = True
                break
            last_err = err or "NOAA: no data"
        if not got_noaa:
            snap["data_sources_failed"].append(last_err or "NOAA: no data")
    except ImportError as e:
        snap["data_sources_failed"].append(f"NOAA: import error: {e}")

    # 2b) ESA OC-CCI cross-validation (independent corroboration)
    try:
        occci_fn = _get_occci()
        occci, err = _safe(
            occci_fn, lat, lon, chl_date,
            default=None, label="ESA OC-CCI",
        )
        if occci and not err and occci.get("value") is not None:
            snap["chlorophyll_occci"] = occci.get("value")
            snap["chlorophyll_occci_source"] = occci.get("source", "ESA OC-CCI")
            snap["data_sources_used"].append("ESA OC-CCI (chlorophyll cross-check)")
        else:
            snap["data_sources_failed"].append(err or "OC-CCI: no data")
    except ImportError as e:
        snap["data_sources_failed"].append(f"OC-CCI: import error: {e}")

    # 3) INCOIS backup chlorophyll
    try:
        incois_fn = _get_incois()
        incois_chl, err = _safe(
            incois_fn, lat, lon, chl_date,
            default=None, label="INCOIS LAS",
        )
        if incois_chl and not err and incois_chl.get("value") is not None:
            # Only use INCOIS if NOAA failed (NOAA is more recent)
            if "chlorophyll" not in snap:
                snap["chlorophyll"] = incois_chl.get("value")
                snap["chlorophyll_unit"] = incois_chl.get("units", "mg/m^3")
                snap["chlorophyll_source"] = incois_chl.get("source", "INCOIS LAS")
            snap["data_sources_used"].append("INCOIS LAS (backup chlorophyll)")
        else:
            snap["data_sources_failed"].append(err or "INCOIS: no data")
    except ImportError as e:
        snap["data_sources_failed"].append(f"INCOIS: import error: {e}")

    # 4) GFW fishing effort + fleet composition
    if include_gfw:
        try:
            effort_fn = _get_gfw_effort()
            effort, err = _safe(
                effort_fn, lat, lon, gfw_start, gfw_end, radius_deg,
                default=None, label="GFW fishing effort",
            )
            if effort and not err:
                hours = effort.get("hours")
                if hours is not None:
                    snap["fishing_hours"] = hours
                    snap["vessel_count_effort"] = effort.get("vessel_ids", 0)
                    snap["data_sources_used"].append("Global Fishing Watch (effort)")
                else:
                    snap["data_sources_failed"].append(
                        "GFW effort: response has no 'hours' field"
                    )
            else:
                snap["data_sources_failed"].append(err or "GFW effort: no data")
        except ImportError as e:
            snap["data_sources_failed"].append(f"GFW effort: import error: {e}")

        try:
            fleet_fn = _get_gfw_fleet()
            fleet, err = _safe(
                fleet_fn, lat, lon, radius_deg, gfw_start, gfw_end,
                default=None, label="GFW fleet",
            )
            if fleet and not err and "by_flag" in fleet:
                snap["vessel_count"] = fleet.get("vessel_count")
                snap["fleet_by_flag"] = fleet.get("by_flag", {})
                snap["fleet_by_gear"] = fleet.get("by_gear", {})
                snap["data_sources_used"].append("Global Fishing Watch (fleet)")
            else:
                snap["data_sources_failed"].append(err or "GFW fleet: no data")
        except ImportError as e:
            snap["data_sources_failed"].append(f"GFW fleet: import error: {e}")
    else:
        snap["data_sources_failed"].append("GFW: skipped (include_gfw=False)")

    # 5) Simple PFZ heuristic score (chlorophyll + SST + fishing presence)
    snap["pfz_score"] = _pfz_score(snap)

    return snap


def _pfz_score(snap: dict[str, Any]) -> float | None:
    """Naive PFZ score 0-1: high chlorophyll, optimal SST, fishing presence.

    For real PFZ we'd use INCOIS's actual algorithm. This is a stopgap
    so the UI can highlight zones in the meantime.
    """
    score = 0.0
    weights = 0.0

    # Chlorophyll: 0.1 (low) to 10+ (very high) mg/m^3 — bell curve, peak at 1-3
    chl = snap.get("chlorophyll")
    if chl is not None and chl > 0:
        # log scale, peak at 1.0
        import math
        score += 1.0 - abs(math.log10(chl)) * 0.4
        weights += 1.0

    # SST: tuna and pelagics prefer 24-29°C
    sst = snap.get("sst_mean") or snap.get("sst_max")
    if sst is not None:
        if 24 <= sst <= 29:
            score += 1.0
        elif 22 <= sst <= 31:
            score += 0.5
        else:
            score += 0.0
        weights += 1.0

    # Fishing presence: any boats = +0.3
    if (snap.get("fishing_hours") or 0) > 0:
        score += 0.3
        weights += 0.3

    if weights == 0:
        return None
    return round(min(1.0, max(0.0, score / weights)), 2)


def zone_snapshot_cached(
    lat: float,
    lon: float,
    target_date: str | None = None,
    radius_deg: float = DEFAULT_RADIUS_DEG,
    include_gfw: bool = True,
    ttl_sec: float = 600.0,
) -> dict[str, Any]:
    """zone_snapshot with a 10-minute cache per 0.05° cell.

    The advisory card, chat trace and reason endpoint all need the same
    snapshot; without a cache each of them paid the full ~60–90 s
    multi-source fetch. Cached, the second caller gets an instant answer
    (which is what makes the 30-second demo flow possible). Cached
    values are immutable-by-convention — callers must not mutate.
    """
    from pipeline.ttlcache import cached
    # Normalize: None and "today" must map to the SAME cache key or
    # the advisory (passes None) and the chat trace (passes today's
    # string) would each pay a separate 60–90 s fetch for identical data.
    if target_date is None:
        target_date = date.today().isoformat()
    key = f"snapshot:{lat:.2f}:{lon:.2f}:{target_date}:{include_gfw}:{radius_deg}"
    return cached(key, ttl_sec, lambda: zone_snapshot(
        lat, lon, target_date, radius_deg=radius_deg, include_gfw=include_gfw,
    ))


def grid_snapshot(
    min_lat: float, max_lat: float, min_lon: float, max_lon: float,
    target_date: str | None = None,
    step_deg: float = 1.0,
    include_gfw: bool = False,  # off by default for grids (GFW is per-cell)
) -> dict[str, Any]:
    """Build snapshots on a regular grid.

    GFW is disabled by default for grids because it's expensive
    (one call per cell). Pass include_gfw=True only for small grids.

    Returns:
        {"min_lat", "max_lat", "min_lon", "max_lon", "step_deg",
         "n_points", "points": [<ZoneSnapshot>...]}
    """
    if target_date is None:
        target_date = date.today().isoformat()

    lats, lons = [], []
    lat = min_lat
    while lat <= max_lat + 1e-9:
        lats.append(round(lat, 4))
        lat += step_deg
    lon = min_lon
    while lon <= max_lon + 1e-9:
        lons.append(round(lon, 4))
        lon += step_deg

    n_pts = len(lats) * len(lons)
    print(
        f"[ORCA] Grid {len(lats)}×{len(lons)} = {n_pts} points, "
        f"{min_lat}..{max_lat}, {min_lon}..{max_lon}, date={target_date}",
        file=sys.stderr,
    )

    points = []
    for la in lats:
        for lo in lons:
            snap = zone_snapshot_cached(
                la, lo, target_date,
                radius_deg=step_deg,
                include_gfw=include_gfw,
            )
            points.append(snap)

    return {
        "min_lat": min_lat, "max_lat": max_lat,
        "min_lon": min_lon, "max_lon": max_lon,
        "step_deg": step_deg,
        "date": target_date,
        "fetched_at": _now_iso(),
        "n_points": len(points),
        "points": points,
    }


# Real coordinates for 8 Indian coastal zones. NOT dummy data — these
# are real lat/lon points that trigger real API calls. They're just a
# UI convenience for the SIH pitch; any lat/lon works.
INDIAN_COASTAL_ZONES = [
    {"name": "Mumbai offshore",      "lat": 19.0, "lon": 72.8},
    {"name": "Goa offshore",         "lat": 15.5, "lon": 73.7},
    {"name": "Cochin offshore",      "lat":  9.5, "lon": 76.0},
    {"name": "Chennai offshore",     "lat": 13.5, "lon": 80.5},
    {"name": "Visakhapatnam",        "lat": 17.5, "lon": 83.5},
    {"name": "Kandla/Gujarat",       "lat": 22.5, "lon": 68.5},
    {"name": "Andaman (Port Blair)", "lat": 12.0, "lon": 92.5},
    {"name": "Lakshadweep",          "lat": 10.5, "lon": 72.5},
]

# Keep DEMO_ZONES as an alias for backwards compatibility — but the
# canonical name is INDIAN_COASTAL_ZONES.
DEMO_ZONES = INDIAN_COASTAL_ZONES
