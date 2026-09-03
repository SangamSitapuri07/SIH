"""INCOIS (Indian National Centre for Ocean Information Services) adapter.

INCOIS publishes Indian Ocean chlorophyll from OCEANSAT-2 OCM and
Oceansat-3 OCM-3, plus daily Potential Fishing Zone (PFZ) advisories
for 586 fish landing centers along the Indian coast.

INTEGRATION STATUS (as of 2026-09-03, after exhaustive testing):
  - OPeNDAP THREDDS server (las.incois.gov.in):  unreliable, often
    returns 30+ second timeouts. We try it first, but don't block on it.
  - ERDDAP server (erddap.incois.gov.in):  WORKING but has NO chlorophyll
    dataset — only AMSR-E SST (stale, last updated 2011), ASCAT winds,
    ARGO floats, OISST. So we don't use it for chlorophyll.
  - PFZ advisory:  only available as image + text on
    https://www.incois.gov.in/MarineFisheries/PfzAdvisory
    (no machine-readable JSON or CSV endpoint — would need OCR).

So the INCOIS adapter's current role is "try OPeNDAP once, fall back to
a clear 'unavailable' so other sources are used." This is honest
behavior — we don't fake Indian data.

If you have MOSDAC creds (pipeline/mosdac_auth.py), use that instead —
MOSDAC serves the raw Oceansat-3 OCM-3 L4 NetCDF directly.
"""
from __future__ import annotations

import math
from datetime import datetime
from typing import Any


# Best-known INCOIS OCM-2 OPeNDAP URL (may be flaky)
INCOIS_OPENDAP_BASE = (
    "http://las.incois.gov.in/thredds/id-b36be55868/"
    "data_home_las_datasets_oceancolour_Oceansat2-OCM.nc.jnl"
)

# INCOIS public PFZ advisory page (humans can read, machines cannot)
INCOIS_PFZ_URL = "https://www.incois.gov.in/MarineFisheries/PfzAdvisory"

# INCOIS ERDDAP (no chlorophyll but has other datasets)
INCOIS_ERDDAP_URL = "https://erddap.incois.gov.in/erddap/"

# Source label shown in the UI
SOURCE_LABEL = "INCOIS"


def _try_opendap_chl(timeout_sec: float = 6.0) -> dict[str, Any] | None:
    """Try the INCOIS OPeNDAP server for chlorophyll. Returns dict or None.

    Uses SIGALRM on Unix to hard-cap the time. The INCOIS server is
    flaky, so this will return None (and an error message) most of the
    time. The caller is expected to gracefully fall back to other
    sources.
    """
    try:
        import xarray as xr
    except ImportError:
        return {
            "error": "xarray not installed (pip install xarray netCDF4)",
            "source": SOURCE_LABEL,
        }

    import signal
    import threading

    class TimeoutError_(Exception):  # noqa: N801
        pass

    def _alarm_handler(signum, frame):
        raise TimeoutError_(f"INCOIS OPeNDAP timed out after {timeout_sec}s")

    # SIGALRM only works in the main thread. zone_snapshot() calls this
    # inside a ThreadPoolExecutor worker thread, where signal.signal()
    # raises "ValueError: signal only works in main thread of the main
    # interpreter". In worker threads we skip the alarm — the caller's
    # future.result(timeout=...) already caps our runtime.
    old_handler = None
    on_main_thread = threading.current_thread() is threading.main_thread()
    if on_main_thread and hasattr(signal, "SIGALRM"):
        old_handler = signal.signal(signal.SIGALRM, _alarm_handler)
        signal.setitimer(signal.ITIMER_REAL, timeout_sec)

    try:
        with xr.open_dataset(INCOIS_OPENDAP_BASE, engine="netcdf4") as ds:
            # Get chlorophyll var (try several names)
            var_name = None
            for candidate in ("CHL", "chl", "chlor_a", "chlorophyll", "chlorophyll-a"):
                if candidate in ds.data_vars:
                    var_name = candidate
                    break
            if var_name is None:
                return {
                    "error": f"INCOIS dataset has no chlorophyll var. Vars: {list(ds.data_vars)[:5]}",
                    "source": SOURCE_LABEL,
                }

            lats = ds.coords.get("lat", ds.coords.get("latitude"))
            lons = ds.coords.get("lon", ds.coords.get("longitude"))
            if lats is None or lons is None:
                return {
                    "error": "INCOIS dataset missing lat/lon coords",
                    "source": SOURCE_LABEL,
                }

            # Just return the global mean as a fallback if we got this far
            arr = ds[var_name].values
            if hasattr(arr, "flatten"):
                flat = arr.flatten()
                flat = flat[~np_isnan(flat)]
                if len(flat) == 0:
                    return {"error": "INCOIS dataset is all NaN", "source": SOURCE_LABEL}
                return {
                    "value": float(flat.mean()),
                    "units": ds[var_name].attrs.get("units", "mg m^-3"),
                    "source": SOURCE_LABEL + " OCM-2 (OPeNDAP global mean)",
                    "note": "OPeNDAP returned a global mean; "
                            "we did not point-query due to server latency",
                }
            return {"error": "INCOIS dataset not an array", "source": SOURCE_LABEL}
    except TimeoutError_ as e:
        return {"error": str(e), "source": SOURCE_LABEL}
    except Exception as exc:  # noqa: BLE001
        err = str(exc)
        if "NetCDF" in err or "OPeNDAP" in err or "I/O" in err or "404" in err:
            err = f"INCOIS server unreachable: {type(exc).__name__}"
        return {"error": err, "source": SOURCE_LABEL, "pfz_url": INCOIS_PFZ_URL}
    finally:
        if old_handler is not None and hasattr(signal, "SIGALRM"):
            signal.setitimer(signal.ITIMER_REAL, 0)
            signal.signal(signal.SIGALRM, old_handler)


def np_isnan(arr):
    """Tiny helper to avoid pulling in numpy if not needed."""
    try:
        import numpy as np
        return np.isnan(arr)
    except ImportError:
        import math
        return [math.isnan(x) for x in arr]


def get_chlorophyll(
    lat: float,
    lon: float,
    date: str | datetime = "2026-08-15",
    timeout_sec: float = 6.0,
) -> dict[str, Any] | None:
    """Try to fetch chlorophyll from INCOIS. Returns dict with 'value'
    on success, or dict with 'error' on failure (the caller can decide
    whether to fall back to other sources).

    NOTE: INCOIS OPeNDAP is unreliable. We try once, briefly, then
    give up. Other sources (NOAA, ESA OC-CCI) are the primary
    chlorophyll providers. The Indian 🇮🇳 primary source is MOSDAC
    (pipeline/mosdac_auth.py) which requires credentials.
    """
    return _try_opendap_chl(timeout_sec=timeout_sec)


def get_sst(
    lat: float,
    lon: float,
    date: str | datetime = "2026-08-15",
) -> dict[str, Any] | None:
    """INCOIS doesn't expose machine-readable SST. Use Open-Meteo instead."""
    return {
        "error": "INCOIS SST endpoint not available. Use Open-Meteo Marine.",
        "source": SOURCE_LABEL,
        "alternative": "https://open-meteo.com/",
    }


def status() -> dict[str, Any]:
    """Return the current INCOIS integration status (for debugging)."""
    return {
        "opendap_url": INCOIS_OPENDAP_BASE,
        "opendap_known_issue": "Server is frequently slow/unresponsive",
        "erddap_url": INCOIS_ERDDAP_URL,
        "erddap_datasets": "15 griddap datasets, none for chlorophyll",
        "pfz_url": INCOIS_PFZ_URL,
        "pfz_format": "HTML + images (not machine-readable)",
        "recommendation": "Use MOSDAC for Indian 🇮🇳 chlorophyll (requires creds). "
                          "Use NOAA ERDDAP for global chlorophyll (no creds). "
                          "Use ESA OC-CCI for climate-quality cross-check (no creds).",
    }
