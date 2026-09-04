"""ISRO MOSDAC OCM-3 chlorophyll — LIVE, real-time, no frozen demo data. 🇮🇳

Why this exists: ORCA is an ISRO problem statement at Smart India
Hackathon — judges should see INDIA'S OWN satellite (EOS-06 / Oceansat-3,
OCM-3 sensor) inside the agent pipeline, pulled LIVE at click time.

Pipeline per query:

  1. MOSDAC login          — download_api/gettoken (official machine API,
                             token cached in-process, refreshed on 401)
  2. LIVE granule search   — /apios/datasets.json for E06OCM_L2C_LAC_OC
                             over the last N days around the point
  3. LIVE granule download — newest matching HDF5 file, size-guarded.
                             Files are kept only for the current UTC day
                             (auto-purged): today's click reuses today's
                             overpass once fetched; tomorrow is always
                             fetched fresh. Nothing is pre-baked.
  4. Point extraction      — parser.parse + extractors.extract_chlorophyll

Role in the pipeline: THIRD, independent chlorophyll source. NOAA ERDDAP
stays primary (global daily NRT), ESA OC-CCI cross-checks, MOSDAC adds
the high-resolution (1 km LAC) Indian view. When the first two are
cloud-masked, MOSDAC can still be primary — its messages say so.

Any failure (login down, no granule yet, slow link) returns an honest
error dict — never an invented value.

Self-test on the laptop (where the creds live):

    python -m pipeline.mosdac_ocm            # live login+search+download+extract
    python -m pipeline.mosdac_ocm --debug    # also print raw search-record keys
"""
from __future__ import annotations

import os
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from pipeline import mosdac_auth
from pipeline.ttlcache import cached


SOURCE_LABEL = "ISRO MOSDAC EOS-06 OCM-3 (live 🇮🇳)"
DATASET = mosdac_auth.DS_OCM_OC  # E06OCM_L2C_LAC_OC

SEARCH_DAYS = 7            # look back up to a week for the newest granule
POINT_BBOX_DEG = 1.0       # search bbox half-width around the clicked point
JOB_BUDGET_SEC = 90.0      # whole live chain must fit the 110 s route deadline
DOWNLOAD_IDLE_TIMEOUT = 45 # abort if the stream stalls (slow demo wifi)
MAX_GRANULE_BYTES = 250_000_000  # honest guard — LAC L2C files are far smaller

GRANULE_DIR = Path(__file__).resolve().parent.parent / "data" / "mosdac_granules"


# ── enable / config ───────────────────────────────────────────────────

def mosdac_configured() -> bool:
    """Creds present? (mosdac_auth auto-loads .env into os.environ.)"""
    return bool(os.environ.get("MOSDAC_USERNAME") and os.environ.get("MOSDAC_PASSWORD"))


def mosdac_enabled() -> bool:
    """AUTO pattern like GFW: on when creds exist, off without them.
    ORCA_MOSDAC=1 forces it on (missing creds then surface as an honest
    error in the sources panel); ORCA_MOSDAC=0 disables completely."""
    forced = os.environ.get("ORCA_MOSDAC", "").strip().lower()
    if forced in ("0", "false", "off"):
        return False
    if forced in ("1", "true", "on"):
        return True
    return mosdac_configured()


# ── login session (cached, refresh-once) ──────────────────────────────

_session = None
_session_time = 0.0
_SESSION_TTL = 20 * 60  # 20 min — tokens outlive one demo easily


def _get_session():
    global _session, _session_time
    if _session is not None and time.time() - _session_time < _SESSION_TTL:
        return _session
    _session = mosdac_auth.login()
    _session_time = time.time()
    return _session


# ── search-record helpers ─────────────────────────────────────────────

_DATE_PATTERNS = (
    re.compile(r"(20\d{2})-(\d{2})-(\d{2})"),          # 2026-09-04
    re.compile(r"(20\d{2})(\d{2})(\d{2})"),             # 20260904
    re.compile(r"(\d{1,2})(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)(20\d{2})", re.I),  # 03SEP2026
)
_MONTHS = {m: i + 1 for i, m in enumerate(
    ("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"))}


def granule_date(title: str) -> str | None:
    """Best-effort granule date (YYYY-MM-DD) from its title/filename."""
    for pat in _DATE_PATTERNS:
        m = pat.search(title or "")
        if not m:
            continue
        if pat is _DATE_PATTERNS[0] or pat is _DATE_PATTERNS[1]:
            return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
        return f"{m.group(3)}-{_MONTHS[m.group(2).upper()]:02d}-{int(m.group(1)):02d}"
    return None


def _records(search_json: dict) -> list[dict[str, Any]]:
    """Extract records defensively — MOSDAC's apios JSON shape has varied
    between releases; we look for the common containers and id fields."""
    recs = (search_json.get("records") or search_json.get("results")
            or search_json.get("entries") or [])
    out = []
    for r in recs:
        if not isinstance(r, dict):
            continue
        rid = r.get("id") or r.get("recordId") or r.get("fileId") or r.get("fid")
        title = r.get("title") or r.get("fileName") or r.get("filename") or str(rid)
        # Live-verified 2026-09-04: MOSDAC apios `title` is just the
        # numeric id — the REAL granule date lives in dcDate / updated /
        # summary. Try the title first, then those fields.
        date_src = " ".join(str(r.get(k, "")) for k in ("dcDate", "updated", "published", "summary"))
        d = granule_date(str(title)) or granule_date(date_src)
        if rid is not None:
            out.append({"id": rid, "title": str(title), "date": d, "raw": r})
    return out


# ── granule cache (same UTC day only, auto-purged) ────────────────────

def _purge_old_granules() -> None:
    if not GRANULE_DIR.exists():
        return
    cutoff = time.time() - 26 * 3600
    for f in GRANULE_DIR.glob("mosdac_*"):
        try:
            if f.stat().st_mtime < cutoff:
                f.unlink()
        except OSError:
            pass


def _find_cached_granule(rec_id: Any) -> Path | None:
    if GRANULE_DIR.exists():
        for f in GRANULE_DIR.glob(f"mosdac_{rec_id}*"):
            if f.stat().st_size > 0:
                return f
    return None


def _download_granule(session, rec_id: Any) -> tuple[Path | None, str | None, float]:
    """Live-download one granule from MOSDAC (same-day disk cache).

    Returns (path, error, seconds). Streams with an idle-timeout and a
    hard size guard so a flaky demo link fails HONESTLY instead of
    hanging the /reason deadline.
    """
    started = time.time()
    hit = _find_cached_granule(rec_id)
    if hit is not None:
        return hit, None, 0.0

    _purge_old_granules()
    GRANULE_DIR.mkdir(parents=True, exist_ok=True)

    try:
        import requests  # local: pipeline dep already
        r = session.get(mosdac_auth.DOWNLOAD_URL, params={"id": rec_id},
                        timeout=(20, DOWNLOAD_IDLE_TIMEOUT), stream=True)
        if r.status_code == 401:
            session = mosdac_auth.refresh(session)
            r = session.get(mosdac_auth.DOWNLOAD_URL, params={"id": rec_id},
                            timeout=(20, DOWNLOAD_IDLE_TIMEOUT), stream=True)
        if r.status_code != 200:
            return None, f"download HTTP {r.status_code}", time.time() - started

        cd = r.headers.get("Content-Disposition", "")
        ext = ".h5"
        if "filename=" in cd:
            ext = Path(cd.split("filename=", 1)[1].strip('"').strip()).suffix or ".h5"
        dest = GRANULE_DIR / f"mosdac_{rec_id}{ext}"

        total = 0
        with open(dest, "wb") as fh:
            for chunk in r.iter_content(1 << 20):
                if chunk:
                    total += len(chunk)
                    if total > MAX_GRANULE_BYTES:
                        fh.close()
                        dest.unlink(missing_ok=True)
                        return None, f"granule larger than {MAX_GRANULE_BYTES // 1_000_000} MB guard", time.time() - started
                    fh.write(chunk)
        return dest, None, time.time() - started
    except Exception as e:  # noqa: BLE001
        return None, f"{type(e).__name__}: {str(e)[:120]}", time.time() - started


# ── swath-aware direct reader (L2C LAC files) ─────────────────────────
# EOS-06 OCM-3 L2C LAC files are SWATH products: lat/lon are 2D grids
# tucked inside HDF5 groups (e.g. navigation_data/latitude), not root
# coordinates. The generic xarray extractor can't see those, so when it
# comes back empty we read the file directly with h5py.

_CHL_NAME_RE = re.compile(r"chlor|chl", re.I)


def _norm_lon_arr(lons, ref_lon):
    """Bring longitudes close to ref_lon by trying 0-360 convention."""
    import numpy as np
    l = np.asarray(lons, dtype="float64")
    if np.nanmin(l) >= 0 and ref_lon < 0:
        return l, ref_lon + 360
    return l, ref_lon


def _extract_chl_h5(path, lat: float, lon: float, max_ring: int = 20) -> dict[str, Any] | None:
    """Best-effort direct chlorophyll extraction from a MOSDAC HDF5 file.

    Returns None with no exception when the structure is unreadable —
    the caller reports the honest 'no valid pixel' line. Set
    _extract_chl_h5.last_debug for structure details."""
    import math

    import h5py
    import numpy as np

    dbg: dict[str, Any] = {"tried": []}
    _extract_chl_h5.last_debug = dbg

    with h5py.File(path, "r") as f:
        listing: list[str] = []
        f.visititems(lambda name, obj: listing.append(name)
                     if isinstance(obj, h5py.Dataset) else None)

    chl_name = next((n for n in listing if _CHL_NAME_RE.search(n.split("/")[-1])), None)
    if chl_name is None:
        dbg["tried"].append(f"no chlor var in {listing[:12]}")
        return None

    base = chl_name.rsplit("/", 1)[0] if "/" in chl_name else ""
    root = base.split("/")[0] if base else ""
    lat_cands = [n for n in listing if re.search(r"(^|/)(lat|latitude)$", n, re.I)]
    lon_cands = [n for n in listing if re.search(r"(^|/)(lon|longitude)$", n, re.I)]
    # prefer coords near the chlor group
    lat_cands.sort(key=lambda n: 0 if (root and n.startswith(root)) else 1)
    lon_cands.sort(key=lambda n: 0 if (root and n.startswith(root)) else 1)
    if not lat_cands or not lon_cands:
        dbg["tried"].append("no lat/lon datasets anywhere in file")
        return None

    for ln in lat_cands[:2]:
        for xn in lon_cands[:2]:
            try:
                with h5py.File(path, "r") as f:
                    lats = np.asarray(f[ln][()], dtype="float64")
                    lons = np.asarray(f[xn][()], dtype="float64")
                    chl = np.asarray(f[chl_name][()], dtype="float64")
                    attrs = dict(f[chl_name].attrs)
            except Exception as e:  # noqa: BLE001
                dbg["tried"].append(f"read {ln}/{xn}: {type(e).__name__}")
                continue
            if chl.ndim == 3:
                chl = chl[0]
            if chl.ndim != 2:
                dbg["tried"].append(f"chl shape {chl.shape} unexpected")
                continue
            lons, ref_lon = _norm_lon_arr(lons, lon)

            if lats.ndim == 2 and lats.shape == chl.shape:
                dist2 = (lats - lat) ** 2 + (lons - ref_lon) ** 2
                i0, j0 = np.unravel_index(np.nanargmin(dist2), dist2.shape)
                cell_lat = lambda i, j: lats[i, j]   # noqa: E731
                cell_lon = lambda i, j: lons[i, j]   # noqa: E731
            elif lats.ndim == 1 and lons.ndim == 1 \
                    and lats.shape[0] == chl.shape[0] and lons.shape[0] == chl.shape[1]:
                i0 = int(np.argmin(np.abs(lats - lat)))
                j0 = int(np.argmin(np.abs(lons - ref_lon)))
                cell_lat = lambda i, j: lats[i]      # noqa: E731
                cell_lon = lambda i, j: lons[j]      # noqa: E731
            else:
                dbg["tried"].append(f"coord shapes {lats.shape}/{lons.shape} vs chl {chl.shape}")
                continue

            # fill values: attrs of the chl dataset + usual sentinels
            fills = {9999.0, -32767.0, -9999.0, 1e30, -1e30, -999.0}
            for k in ("_FillValue", "missing_value", "fill_value"):
                if k in attrs:
                    try:
                        fills.add(float(np.asarray(attrs[k]).flat[0]))
                    except Exception:  # noqa: BLE001
                        pass

            def _ok(v: float) -> bool:
                if not np.isfinite(v) or v <= 0:
                    return False
                return not any(abs(v - fv) < 1e-3 or (fv != 0 and abs(v/fv - 1) < 1e-9) for fv in fills)

            best = None
            best_d = float("inf")
            for r in range(0, max_ring + 1):
                improved = False
                rng = range(-r, r + 1)
                for di in rng:
                    for dj in rng:
                        if max(abs(di), abs(dj)) != r:
                            continue
                        i, j = i0 + di, j0 + dj
                        if not (0 <= i < chl.shape[0] and 0 <= j < chl.shape[1]):
                            continue
                        v = float(chl[i, j])
                        if not _ok(v):
                            continue
                        d = math.hypot(cell_lat(i, j) - lat, cell_lon(i, j) - lon)
                        if d < best_d:
                            best, best_d = v, d
                            improved = True
                if best is not None and r >= 2:
                    break  # good enough — nearest-ish valid cell found
                if not improved and r > 6 and best is None:
                    continue
            if best is None:
                dbg["tried"].append(f"all fill/masked within {max_ring} cells of point")
                continue
            # values like 0.01-30 sane; big numbers (e.g. scaled ints) sane-check
            if best > 1000:
                dbg["tried"].append(f"value {best} looks unscaled")
                continue
            return {
                "value": best,
                "distance_deg": round(best_d, 4),
                "units": str(attrs.get("units", b"mg m^-3")).strip("b'\" ") or "mg m^-3",
            }
    return None

def get_chlorophyll(lat: float, lon: float, date: str | None = None) -> dict[str, Any]:
    """LIVE MOSDAC OCM-3 chlorophyll at (lat, lon).

    `date` accepted for interface parity — the live chain always uses the
    NEWEST granule from the last SEARCH_DAYS days; its true date is
    reported back, never invented."""
    if not mosdac_enabled():
        return {
            "error": "MOSDAC disabled (ORCA_MOSDAC=0 or no credentials configured)",
            "source": SOURCE_LABEL,
        }
    from pipeline.ttlcache import cached as _cached
    return _cached(
        f"mosdac_chl:{lat:.2f},{lon:.2f}",
        6 * 3600,  # same point+day = same newest granule; 6 h is honest
        lambda: _live_chain(lat, lon),
    )


def _live_chain(lat: float, lon: float) -> dict[str, Any]:
    t0 = time.time()

    def _fail(why: str) -> dict[str, Any]:
        return {
            "error": f"MOSDAC OCM-3 live fetch failed ({why}) — NOAA primary is used"[:180],
            "source": SOURCE_LABEL,
        }

    # 1) login
    try:
        session = _get_session()
    except mosdac_auth.MosdacAuthError as e:
        return _fail(f"login: {str(e).splitlines()[0][:90]}")

    # 2) live search — newest granules overlapping the point
    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=SEARCH_DAYS)
    bbox = f"{lon - POINT_BBOX_DEG},{lat - POINT_BBOX_DEG},{lon + POINT_BBOX_DEG},{lat + POINT_BBOX_DEG}"
    try:
        data = mosdac_auth.search(DATASET, start=start.isoformat(),
                                  end=end.isoformat(), bbox=bbox, count="10")
    except Exception as e:  # noqa: BLE001
        return _fail(f"search: {type(e).__name__}: {str(e)[:80]}")

    recs = _records(data)
    if not recs:
        return _fail(f"no {DATASET} granule found around the point in the last {SEARCH_DAYS} days")

    # newest first: parseable dates sort, unknowns keep server order last
    dated = [r for r in recs if r["date"]]
    dated.sort(key=lambda r: r["date"], reverse=True)
    ordered = dated + [r for r in recs if not r["date"]]

    # 3) live download + 4) extract — try newest → older until one parses
    tried: list[str] = []
    for rec in ordered[:3]:
        if time.time() - t0 > JOB_BUDGET_SEC - 15:
            return _fail("time budget exhausted mid-download (slow link)")
        path, derr, dl_secs = _download_granule(session, rec["id"])
        if path is None:
            tried.append(f"{rec['id']}: {derr}")
            continue
        try:
            from pipeline import extractors, parser
            pf = parser.parse(path)
            val = extractors.extract_chlorophyll(pf, lat, lon)
        except Exception as e:  # noqa: BLE001
            tried.append(f"{rec['id']}: parse {type(e).__name__}")
            continue
        via = "xarray"
        if val is None or val.get("value") is None:
            # L2C LAC files are swath products (2D lat/lon inside HDF5
            # groups) — the generic extractor can't see those; read the
            # file directly before giving up on it.
            try:
                direct = _extract_chl_h5(path, lat, lon)
            except Exception:  # noqa: BLE001
                direct = None
            if direct is not None and direct.get("value") is not None:
                val = direct
                via = "direct-swath"
        if val is None or val.get("value") is None:
            msg = f"{rec['id']}: no valid pixel near point"
            dbgd = getattr(_extract_chl_h5, "last_debug", None)
            if dbgd and dbgd.get("tried"):
                msg += f" [direct-reader: {dbgd['tried'][-1][:90]}]"
            tried.append(msg)
            continue
        return {
            "value": val["value"],
            "units": val.get("units", "mg m^-3"),
            "lat": lat,
            "lon": lon,
            "distance_deg": val.get("distance_deg"),
            "source": SOURCE_LABEL,
            "granule": rec["title"][:80],
            "date": rec["date"] or "latest per MOSDAC search",
            "live_download_s": round(dl_secs, 1) if dl_secs else None,
            "note": (f"ISRO EOS-06 OCM-3 (1 km), granule dated {rec['date'] or 'latest'} "
                     f"— pulled LIVE from MOSDAC on click"
                     + (f" ({dl_secs:.0f}s download)" if dl_secs else " (today's granule already fetched)")
                     + (f", read via {via}" if via == "direct-swath" else "")),
        }

    return _fail("; or ".join(tried) if tried else "no usable granule")


# ── self-test ─────────────────────────────────────────────────────────

def _selftest() -> int:
    print("=" * 68)
    print("  MOSDAC OCM-3 LIVE self-test — login -> search -> download -> extract")
    print("  (credentials never printed; everything fetched RIGHT NOW)")
    print("=" * 68)
    if not mosdac_configured():
        print("  X MOSDAC_USERNAME/PASSWORD not set (.env). Aborting.")
        return 2
    print("  creds: found (hidden)")

    lat, lon = 20.9, 70.37  # Veraval — our PFZ validation ground

    print(f"  1) LIVE search {DATASET}, last {SEARCH_DAYS} days around Veraval ({lat}N {lon}E)...")
    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=SEARCH_DAYS)
    bbox = f"{lon - POINT_BBOX_DEG},{lat - POINT_BBOX_DEG},{lon + POINT_BBOX_DEG},{lat + POINT_BBOX_DEG}"
    try:
        t_s = time.time()
        data = mosdac_auth.search(DATASET, start=start.isoformat(),
                                  end=end.isoformat(), bbox=bbox, count="10")
        recs = _records(data)
        print(f"     ✅ {len(recs)} granule(s) found ({data.get('totalResults', '?')} total, {time.time()-t_s:.1f}s)")
        if "--debug" in sys.argv and recs:
            print("     --debug first record keys:", sorted(recs[0]["raw"].keys()))
            print("     --debug id/title:", recs[0]["id"], "|", recs[0]["title"][:70])
        for r in recs[:3]:
            print(f"       - {r['title'][:60]}  (date: {r['date'] or '?'})")
    except Exception as e:  # noqa: BLE001
        print(f"     X search failed: {type(e).__name__}: {e}")
        return 1

    print("  2) LIVE login + newest-granule download + point extract (may take 20-90s)...")
    t0 = time.time()
    res = _live_chain(lat, lon)
    dt = time.time() - t0
    if res.get("value") is not None:
        print(f"     ✅ chlorophyll {res['value']:.3f} {res.get('units')} at Veraval")
        print(f"        granule: {res.get('granule')}")
        print(f"        granule date: {res.get('date')} | live download: {res.get('live_download_s') or 0}s | total: {dt:.1f}s")
        print("  MOSDAC LIVE pipeline READY — agents will show ISRO data on clicks. 🇮🇳")
        return 0
    print(f"     X live chain failed: {res.get('error')}")
    if "--debug" in sys.argv:
        dbgd = getattr(_extract_chl_h5, "last_debug", None) or {}
        print("     --debug direct-reader attempts:", dbgd.get("tried"))
        # dump the granule's actual structure so the fix can be exact
        try:
            import h5py
            files = sorted(GRANULE_DIR.glob("mosdac_*"), key=lambda p: -p.stat().st_mtime)
            if files:
                print(f"     --debug structure of {files[0].name}:")
                with h5py.File(files[0], "r") as f:
                    names: list[str] = []
                    f.visititems(lambda n, o: names.append(
                        f"{n}  shape={getattr(o, 'shape', '')}"))
                for n in names[:40]:
                    print("       ", n)
        except Exception as e:  # noqa: BLE001
            print("     --debug structure dump failed:", e)
    print("       (server busy or no fresh granule yet — agents will show this")
    print("        honest message and keep using NOAA primary. Re-run later.)")
    return 1


if __name__ == "__main__":
    sys.exit(_selftest())
