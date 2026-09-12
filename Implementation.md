# ORCA Implemented Integrations

> Implementation reference for the ORCA FastAPI backend. This document lists
> only behavior that is present in the current codebase. Secrets are never
> included here.

## Quick Status

| Requested capability | Current status | API exposure |
|---|---|---|
| NOAA ERDDAP chlorophyll | Implemented, limited provenance | `/api/v1/zone`, `/api/v1/grid`, `/api/v1/reason`, `/api/v1/advisory` |
| NOAA quality and source timestamps | Partial | Provider returns fresh/cloud-masked/unreachable states, but observation timestamps and persistent stale cache are pending |
| INCOIS official PFZ advisory | Implemented | `/api/v1/advisory`, `/api/v1/layers` |
| INCOIS OPeNDAP chlorophyll backup | Implemented as backup | Zone snapshot sources |
| ESA OC-CCI chlorophyll | Implemented as cross-check/fallback | Zone snapshot sources |
| Global Fishing Watch effort | Implemented when token is configured and `include_gfw=true` | `/api/v1/zone`, `/api/v1/reason`, `/api/v1/advisory` |
| GFW fleet details | Implemented when token is configured and `include_gfw=true` | Fleet vessel count, flag breakdown, and gear breakdown in snapshots |
| GFW cache and rate-limit states | Implemented | Six-hour atomic JSON cache; persisted headers/cooldown; explicit authentication, permission, rate-limit, and unavailable states |
| MOSDAC EOS-06 OCM-3 chlorophyll | Implemented and live-verified in the dedicated provider | Backend MOSDAC provider, registry, parser, and cache; not yet wired into zone snapshots |
| MOSDAC AWW/AWV or WV12 | Not implemented as a live fetcher | Parser recognition/documentation only |
| MOSDAC Coastal Water Quality/CQ | Not implemented as a live fetcher | Catalog/documentation only |
| Station observations | Not implemented | No station-observation route or adapter |
| Real hourly advisory forecast | Implemented | `/api/v1/advisory` uses hourly Open-Meteo response values; safe-window selection is still pending |
| Route detour | Explicitly unverified | `/api/v1/route-check` returns no fabricated detour; route advisory reports `UNVERIFIED` when live samples are missing |

## Environment Configuration

Create a local `backend/.env` file. Do not commit it.

```dotenv
# Optional: enables Global Fishing Watch effort and fleet calls.
GFW_API_TOKEN=replace_with_real_gfw_access_token

# Optional: enables the live MOSDAC EOS-06 OCM-3 chain.
MOSDAC_USERNAME=replace_with_mosdac_username
MOSDAC_PASSWORD=replace_with_mosdac_password

# Optional switches.
# ORCA_MOSDAC=1 forces the MOSDAC adapter on; 0 disables it.
# Without this setting MOSDAC is enabled only when both credentials exist.
ORCA_MOSDAC=0

# ORCA_INCOIS_OPENDAP=0 disables the INCOIS OPeNDAP chlorophyll backup.
ORCA_INCOIS_OPENDAP=1
```

The backend loads `backend/.env` automatically from `backend/main.py`. Never
put a real token or password in this document.

Start the backend:

```powershell
python -m uvicorn backend.main:app --reload --port 8000
```

## Health and Configuration Check

```powershell
curl http://127.0.0.1:8000/api/v1/health
```

The response reports whether credentials are configured, source availability,
and in-memory cache statistics. It does not return secret values.

Example response shape:

```json
{
  "status": "ok",
  "version": "0.2.0",
  "credentials": {
    "gfw_token_configured": true,
    "mosdac_configured": true
  },
  "data_sources": {
    "noaa_erddap": "live (no key)",
    "esa_occci": "live (no key)",
    "gfw": "live",
    "incois_pfz_wfs": "live - official daily PFZ advisory lines (no key)",
    "mosdac": "live"
  }
}
```

## Main API Calls

### Zone snapshot

```powershell
curl "http://127.0.0.1:8000/api/v1/zone?lat=20.9&lon=70.37&date=2026-09-03&include_gfw=true"
```

Relevant response fields include:

```json
{
  "lat": 20.9,
  "lon": 70.37,
  "date": "2026-09-03",
  "fetched_at": "2026-09-13T10:30:00+00:00",
  "chlorophyll": 1.21,
  "chlorophyll_source": "NOAA ERDDAP DINEOF",
  "chlorophyll_date": "2026-08-31",
  "chlorophyll_occci": 1.18,
  "chlorophyll_mosdac": 1.34,
  "fishing_hours": 47.3,
  "fleet_by_flag": {"IND": 28},
  "data_sources_used": [
    "NOAA ERDDAP (chlorophyll, 2026-08-31)",
    "ESA OC-CCI (chlorophyll cross-check)",
    "Global Fishing Watch (fishing effort)"
  ],
  "data_sources_failed": []
}
```

The values above are an illustrative response shape, not bundled fixture data.
Live values depend on the requested location, date, cloud cover, credentials,
and upstream availability.

### Multi-agent analysis

```powershell
curl "http://127.0.0.1:8000/api/v1/reason?lat=20.9&lon=70.37&include_gfw=true"
```

This returns the snapshot plus the ten-agent analysis, including satellite
cross-check findings and data-validation findings.

### Deterministic advisory

```powershell
curl "http://127.0.0.1:8000/api/v1/advisory?lat=20.9&lon=70.37&include_gfw=true"
```

The advisory combines the snapshot with weather thresholds, official INCOIS
PFZ proximity, and cyclone checks. It returns `go`, `caution`, or `no_go`
with source attribution.

### Dataset catalog

```powershell
curl http://127.0.0.1:8000/api/v1/datasets
```

This endpoint describes the configured source catalog and the ten agents. It
is metadata, not proof that every source succeeded for a particular request;
use `data_sources_used` and `data_sources_failed` in the snapshot for that.

## Implementation Details

### NOAA ERDDAP quality and timestamp behavior

The active backend implementation is in [backend/data_providers.py](backend/data_providers.py).

```python
# Conceptual call used by the snapshot pipeline.
result = get_chlorophyll(lat, lon, requested_date)

# The pipeline tries the requested date first, then processing-lag dates.
# The date of the returned product is preserved in the snapshot.
snapshot["chlorophyll_date"] = actual_product_date
snapshot["fetched_at"] = current_utc_timestamp()
```

The backend currently requests one ERDDAP point and reports `fresh`,
`cloud_masked`, or `unreachable`. Date-aware lag selection and persistent
stale fallback remain pending.

Physical-range validation and source timestamp persistence remain pending in
the active backend path.

### INCOIS PFZ quality and timestamps

Implemented in [backend/data_providers.py](backend/data_providers.py).

```python
from pipeline.incois_pfz import get_lines, nearest_pfz

lines = get_lines(latest_only=True)
nearest = nearest_pfz(20.9, 70.37)

assert "advisory_date" in lines
assert "fetched_at" in lines
```

The active WFS adapter returns official GeoJSON features and keeps the source
dataset label. Advisory-date extraction, nearest-line distance, and persistent
six-hour cache remain pending.

### ESA OC-CCI and INCOIS

ESA OC-CCI is fetched and retained as `chlorophyll_occci` for independent
cross-validation. If NOAA has no usable value, OC-CCI can become the primary
chlorophyll value.

INCOIS OPeNDAP is a conditional chlorophyll backup. It reads a small spatial
hyperslab rather than the complete remote array. INCOIS ERDDAP is documented
as a catalog/status reference, but it is **not** the current chlorophyll
fetcher. The official machine-readable PFZ integration is the INCOIS
GeoServer WFS above.

### GFW effort and persistence

Implemented in [backend/gfw_provider.py](backend/gfw_provider.py) and wired
through [backend/data_providers.py](backend/data_providers.py). GFW is optional
because reports can be slow; request it explicitly with `include_gfw=true`.

```python
from gfw_provider import GfwProvider

effort = GfwProvider().fetch_effort(
  20.9, 70.37, "2026-08-01", "2026-08-30", radius_deg=0.5
)
```

Successful effort and fleet responses are cached for six hours by operation,
region, radius, and actual date range. Dates are capped at four days before
today and a maximum 90-day range; requested and actual dates are both returned.
A 429, 401, or 403 is returned as an explicit status; daily quota cooldown and
rate-limit headers survive restart, and no failed response is cached as data.

Live verification completed on 2026-09-13 with a configured backend token:

- Effort report: `1.0` hours for the bounded test region and date range.
- Fleet report: request completed with `fresh` status; no vessel IDs were
  returned for that test region, so no count was fabricated.

### MOSDAC OCM-3 chlorophyll

Implemented in [backend/mosdac_provider.py](backend/mosdac_provider.py),
[backend/mosdac_parsers.py](backend/mosdac_parsers.py), and
[backend/mosdac_datasets.py](backend/mosdac_datasets.py).

```python
from mosdac_provider import MosdacProvider
from mosdac_datasets import DATASET_REGISTRY

result = MosdacProvider().fetch(
  DATASET_REGISTRY["E06OCM_L4_AC"],
  {"startTime": "2026-03-30", "endTime": "2026-03-30", "count": "1"},
)
```

The live chain follows the official MOSDAC search, token, and streamed
download flow. `E06OCM_L4_AC` and `E06SCT_L4_UI` have passed live search,
download, parser, normalization, provenance, and cache verification. Other
Tier-S products remain disabled until product-specific evidence is available.

## Explicitly Not Implemented

The following items are not currently live API integrations:

1. **Station observations:** there is no station adapter, observation model,
  or `/api/v1/stations` route.
2. **MOSDAC AWW/AWV and WV12:** registered but disabled; live verification or
  product metadata is insufficient for a safe parser.
3. **MOSDAC Coastal Water Quality/CQ:** registered but disabled because the
  requested live product was unavailable and no sample was supplied.
4. **Safe-window calculation:** hourly values are now real, but no safe
  departure interval is selected yet.
5. **Versioned land raster:** the current route check remains a regional
  heuristic and cannot claim safety-grade raster accuracy.

Do not describe these three areas as implemented until adapters, snapshot
fields, API exposure, and offline tests are added.

## Offline Verification

Run the backend tests from the repository root:

```powershell
python -m pytest -q
```

The integration tests mock external network calls. Real credential checks are
available through:

```powershell
python tools/verify_credentials.py
```

That script reports whether GFW and MOSDAC credentials work without printing
the MOSDAC password.

## Source Map

| Responsibility | File |
|---|---|
| FastAPI routes and `.env` loading | [backend/main.py](../backend/main.py) |
| Unified snapshot and source fallback logic | [pipeline/orca_data.py](../pipeline/orca_data.py) |
| NOAA chlorophyll | [pipeline/erddap_chl.py](../pipeline/erddap_chl.py) |
| ESA OC-CCI | [pipeline/occci_chl.py](../pipeline/occci_chl.py) |
| INCOIS backup and status | [pipeline/incois.py](../pipeline/incois.py) |
| Official INCOIS PFZ WFS | [pipeline/incois_pfz.py](../pipeline/incois_pfz.py) |
| GFW effort/fleet/cache | [pipeline/gfw.py](../pipeline/gfw.py) |
| MOSDAC authentication | [pipeline/mosdac_auth.py](../pipeline/mosdac_auth.py) |
| MOSDAC OCM-3 live chain | [pipeline/mosdac_ocm.py](../pipeline/mosdac_ocm.py) |
| Data quality agent | [pipeline/agents/validation.py](../pipeline/agents/validation.py) |
| Source/integration tests | [pipeline/tests](../pipeline/tests) |