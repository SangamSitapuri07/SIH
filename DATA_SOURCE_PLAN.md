# ORCA Real Data Source Plan

Date: 2026-09-13
Scope: authoritative repository `C:\Users\sanga\Desktop\ORCA-SIH-2026`

## Purpose

This document is the data contract and acquisition plan for running ORCA without fabricated measurements, seeded demo records, or synthetic fallback values.

**Rule:** if a required live value cannot be fetched, validated, and timestamped, ORCA must show `unavailable`, use a clearly marked cached real value, or return an honest error. It must never calculate a replacement measurement from latitude/longitude or silently label a placeholder as live.

## Current Reality

| Area | Current state | Required action |
|---|---|---|
| Wave height, wave period, swell height, SST, currents | Active zone path requests Open-Meteo Marine; current speed is converted from km/h to knots | Add raw response, source timestamp, units, and provider metadata; map swell period |
| Sustained wind, gusts, direction | Active zone path requests Open-Meteo Forecast in knots | Add raw response and forecast issue time; request remaining weather context |
| Chlorophyll-a | NOAA ERDDAP is fetched by the active zone path | Add observation timestamp, quality/cloud handling, response provenance, and cache |
| PFZ lines | Official INCOIS GeoServer/WFS is fetched by the active zone path | Parse advisory date/expiry and add last-known-good cache |
| Fishing effort/AIS and fleet summary | Optional active GFW 4Wings effort/fleet paths when `include_gfw=true` | Keep the token backend-only; retain six-hour atomic cache, clamped date range, Polygon request, dataset, vessel IDs, flag/gear groups, and rate-limit status |
| Cyclone alerts | `/api/v1/alerts` fetches IMD RSS, GDACS GeoJSON, and JTWC RSS | Complete CAP XML/polygon parsing, geographic relevance, expiry, and cache |
| Land/water | Current code uses geographic rules, not a true raster | Add a versioned GLOBE/official raster and record its version |
| Map overlay tiles | Current `/api/v1/tiles/*` requests return 404 | Implement server-rendered or provider-native tiles; otherwise hide the layer |
| Agent reasoning | Runs after a valid live zone snapshot | Preserve source coverage and prevent explanations from overriding deterministic safety |
| Cache | Hive stores real responses with `fetched_at` and TTL | Preserve provenance and display stale/fresh state |

The existing `API-GUIDE.md` and frontend source catalog contain candidate/source descriptions, not proof that every listed source is live in this backend.

## Implemented Versus Pending

Implemented active paths: Open-Meteo marine/forecast snapshot with real hourly chart data, NOAA chlorophyll, INCOIS PFZ WFS, optional GFW 4Wings effort and fleet summaries, IMD RSS alert ingestion, GDACS cyclone events, JTWC headline ingestion, deterministic safety verdicts, frontend Hive response caching, and the MOSDAC provider/registry/cache architecture.

Implemented and live-verified MOSDAC products: `E06OCM_L4_AC` and `E06SCT_L4_UI`.

Pending or incomplete: raw source provenance for the general providers, provider-side cache/stale fallback, real safe-window calculation, IMD CAP XML and polygon relevance, GDACS distance folding, versioned land/water raster, official restricted zones, NOAA/PFZ quality and timestamp persistence, overlay tile routes, ESA/INCOIS ERDDAP cross-checks, GFW historical fleet-detail enrichment beyond the regional report, station observations, and the three disabled MOSDAC Tier-S products.

## Required Data Contract

Every fetched value must carry:

```json
{
  "value": 1.23,
  "unit": "m",
  "observed_at": "2026-09-12T00:00:00Z",
  "fetched_at": "2026-09-12T00:01:00Z",
  "valid_until": "2026-09-12T01:00:00Z",
  "source": "provider-name",
  "dataset": "provider-dataset-or-model-run",
  "source_url": "https://...",
  "quality": "fresh|stale|cloud_masked|missing|invalid",
  "raw_request_id": "optional-provider-id"
}
```

Do not replace missing values with constants such as `1.5`, `12.0`, `28.0`, or `10.0`. Those are not valid fallbacks.

## Source Matrix

### 1. Marine and Weather Conditions

| ORCA fields | Preferred source | Access | Candidate endpoint/documentation | Refresh/cache | Validation |
|---|---|---|---|---|---|
| `wave_height_m`, `wave_period_s`, swell height/period, ocean current speed/direction, sea surface temperature | Open-Meteo Marine, backed by marine models | No key for normal use; respect provider limits and attribution | `https://marine-api.open-meteo.com/v1/marine` and Open-Meteo Marine API docs | Current conditions: short TTL, e.g. 10-30 min; hourly forecast by model run | Coordinate is marine; numeric value; provider timestamp present; physical range checks |
| `wind_speed_kn`, `wind_gust_kn`, direction, rain | Open-Meteo Forecast | No key for normal use | `https://api.open-meteo.com/v1/forecast` and Open-Meteo Forecast API docs | Current/forecast cache 10-30 min | Convert units explicitly; gust must not be less than sustained wind without a documented provider exception |
| Forecast history/anomaly baseline | Open-Meteo Archive or a national meteorological archive | Usually no key; availability varies | `https://archive-api.open-meteo.com/v1/archive` | Cache by coordinate/date/model; never use an arbitrary default baseline | Compare same location, season, and variable; mark missing baseline |
| Official warnings and severe weather context | IMD Marine Weather Services and official bulletins | Public access varies; follow terms | `https://mausam.imd.gov.in/` and official marine bulletin links | Cache until bulletin expiry; preserve bulletin time | Parse issue time, valid time, area, severity, and source document |

### 2. Ocean Colour, Chlorophyll, and Satellite Data

| ORCA fields | Preferred source | Access | Candidate endpoint/documentation | Refresh/cache | Validation |
|---|---|---|---|---|---|
| `chlorophyll_mg_m3` | NOAA CoastWatch ERDDAP ocean-colour datasets | Usually public; dataset-specific limits | `https://coastwatch.noaa.gov/` and ERDDAP catalog | Daily/observation-dependent; retain source observation date | Reject land pixels, missing/cloud flags, impossible ranges; preserve quality flag |
| Independent chlorophyll cross-check | ESA Ocean Colour CCI or another NOAA ERDDAP mirror | Public dataset terms apply | Use the provider's official ERDDAP dataset metadata | Daily/weekly depending on product | Never average incompatible products silently; report disagreement |
| India-region satellite product | ISRO MOSDAC Oceansat-3 OCM-3 | Credentials may be required; keep only in backend `.env` | `https://www.mosdac.gov.in/` | Product-dependent; use a bounded download and record granule ID | Validate granule time, footprint, cloud mask, and processing version |
| Cloud/quality status | Same satellite product metadata | Same as source | Provider quality flags | Same as source | `cloud_masked` is a valid result; do not convert it to a chlorophyll number |

### 3. Fisheries and Fishing Activity

| ORCA fields | Preferred source | Access | Candidate endpoint/documentation | Refresh/cache | Validation |
|---|---|---|---|---|---|
| Potential Fishing Zone geometry | INCOIS official PFZ advisories/GeoServer WFS | Public endpoint if available; verify layer and terms | `https://incois.gov.in/` and the official PFZ GeoServer/WFS catalog | Daily advisory validity; store issue/expiry time | Geometry validity, region, issue date, and official layer name |
| Fishing effort / AIS-derived activity | Global Fishing Watch API | API token required; backend only | `https://globalfishingwatch.org/` and official API docs | Product-specific; obey quota and 429 backoff | Token present, response time range, geometry, aggregation unit, and API version |
| Port/harbour reference data | Official hydrographic/port authority data or OpenStreetMap/Nominatim for search only | Terms and rate limits apply | `https://www.openstreetmap.org/` / Nominatim policy | Long TTL for reference data | Do not treat geocoder results as live ocean conditions |

### 4. Storms and Alerts

| ORCA fields | Preferred source | Access | Candidate endpoint/documentation | Refresh/cache | Validation |
|---|---|---|---|---|---|
| Active tropical cyclone warnings | JTWC official warnings | Public text/products | `https://www.metoc.navy.mil/jtwc/jtwc.html` | Refresh frequently while active; cache until expiry | Parse storm ID, advisory time, warning area, movement, and expiry |
| Indian cyclone/marine warnings | IMD official bulletins | Public access varies | `https://mausam.imd.gov.in/` | Bulletin validity | Use official issue/validity fields; no manually authored alert text |
| Rule-generated safety flags | ORCA deterministic rules over validated live data | Internal computation, not external data | Backend rules | Same TTL as input values | Mark as `derived`, include input IDs and rule version; never call it an external alert |

### 5. Land, Bathymetry, and Geography

| ORCA fields | Preferred source | Access | Candidate source | Refresh/cache | Validation |
|---|---|---|---|---|---|
| Land/water mask | GLOBE 1 km or another versioned official raster | Bundle/version locally | Official raster distribution; document exact file/version | Immutable versioned asset | Point-in-pixel test; record raster version |
| Bathymetry/depth | GEBCO or an official hydrographic source, subject to license/terms | Public dataset with attribution | `https://www.gebco.net/` | Immutable/versioned raster or tile cache | Resolution, no-data handling, coastal uncertainty |
| Route geometry | Geodesic calculation over validated coordinates | No external measurement by itself | Internal geometry library | Per request; cache only with input coordinates | Coordinate bounds, antimeridian handling, and land-mask validation |

A mathematical route line is acceptable as geometry. A fabricated detour coordinate is not acceptable. If no valid detour can be computed against the land mask, return `unverified` or `blocked`.

## Minimum Viable Real Dataset

The first production-safe integration should require only these inputs:

1. Open-Meteo Marine: wave height, wave period, SST, current speed/direction.
2. Open-Meteo Forecast: sustained wind, gust, direction, forecast timestamp.
3. Versioned land/water raster for route validation.
4. Optional official cyclone warning feed for alerts.
5. Optional NOAA ERDDAP chlorophyll with quality flags.

The advisory can run with the first three if all required values are fresh and valid. It must not claim satellite/PFZ/AIS evidence when those sources were not fetched.

## Backend Integration Order

### Phase 1: Make current marine data trustworthy

- Create typed provider clients for Marine and Forecast.
- Store raw response, request URL, provider timestamps, model run, units, and quality flags.
- Use one shared `httpx.AsyncClient` or bounded client pool instead of creating a new client for every request.
- Return `sources_used` only for sources actually queried successfully.
- Return `sources_failed` with exception class, timeout, and provider URL without secrets.
- Add provider-specific timeout below the frontend request timeout.

### Phase 2: Add chlorophyll and official PFZ

- Select exact NOAA ERDDAP dataset IDs and variables.
- Select exact INCOIS PFZ layer and WFS fields.
- Write fixture-free integration tests using recorded real responses with provenance, not invented JSON.
- Add cloud/no-data/expired-product states.

### Phase 3: Alerts and activity

- Add JTWC/IMD parser tests using official sample documents.
- Add GFW only after the server-side token and quota behavior are documented.
- Keep credentials out of Flutter and out of logs.

### Phase 4: Map layers

- Implement `/api/v1/tiles` only after a real tile provider or server renderer is selected.
- If tiles cannot be produced, disable the layer and show its source status instead of returning repeated 404s.

## Validation Rules

### Common

- Latitude must be `-90..90`; longitude must be `-180..180`.
- Every measurement must have a source timestamp and fetch timestamp.
- Unit conversion must be explicit and tested.
- Reject NaN, infinity, missing values, and impossible physical ranges.
- Never combine values from different timestamps without saying so.
- Never present cached data as current.

### Safety inputs

- Wave `< 2.5 m`: potentially GOOD if every other required rule passes.
- Wave `>= 2.5 m`: CAUTION.
- Wave `>= 4.0 m`: NO-GO.
- Gust `>= 34 kn`: NO-GO.
- Sustained wind `>= 20 kn`: CAUTION.
- Unknown required safety input: `UNVERIFIED`, never GOOD.
- LLM output may explain the result but cannot override deterministic rules.

## Credentials and Security

Keep these only on ORCA Box/backend:

- Global Fishing Watch API token.
- MOSDAC credentials, if required.
- Any IMD/INCOIS credential or session token.
- Supabase service credentials.
- Ollama host/model settings.

Flutter should call ORCA Box only. Flutter must never contain provider secrets or connect directly to Ollama port `11434`.

Recommended backend environment variables:

```text
GFW_API_TOKEN=
MOSDAC_USERNAME=
MOSDAC_PASSWORD=
INCOIS_API_KEY=
ORCA_PROVIDER_TIMEOUT_SECONDS=12
ORCA_CACHE_DIRECTORY=
```

Do not commit `.env` files. Add a redacted `.env.example` with no real secrets.

## Cache Policy

The cache is useful and should remain, but cached data must be honest:

- Key by source, dataset, coordinate cell, time range, and request parameters.
- Store raw payload plus normalized payload and provenance.
- Store `fetched_at`, `observed_at`, `valid_until`, TTL, and source status.
- Fresh cache may satisfy a normal read.
- Stale cache may be used only when the provider fails and must be labeled `cached`/`stale` with age.
- Do not cache errors as successful measurements.
- Do not cache prototype fixtures in Real Mode.
- Clear or migrate cache when the provider schema or unit contract changes.

## Acceptance Checks Before Calling Data Real

For each source, record:

- Official source URL and dataset ID.
- Terms/attribution requirements.
- Authentication requirement.
- Example raw response captured from the source.
- Response timestamp and model/product version.
- Unit conversion test.
- Missing/cloud/no-data behavior.
- Timeout and retry policy.
- Cache TTL and stale display policy.
- Backend endpoint that exposes the normalized data.
- Flutter DTO and regression test.
- One live request log proving the source was queried.

## Immediate Next Work

1. Persist source timestamps, raw request metadata, quality, and provenance for Open-Meteo, NOAA, and PFZ responses.
2. Add bounded server-side cache and stale fallback for general providers.
3. Compute safe windows from the real hourly marine/forecast series.
4. Complete IMD CAP XML/polygon parsing and GDACS 300/800 km relevance folding; retain JTWC as headline corroboration.
5. Replace the geographic land heuristic with a versioned raster and keep detours unverified until pathfinding is validated.
6. Implement or disable map overlay tile routes so the UI does not request unavailable endpoints.
7. Add recorded-response integration tests with provenance and quality assertions.

Until these steps are complete, ORCA should describe unavailable sources honestly and must not claim that all sources listed in the older API guide are actively live.

## MOSDAC Activation Status

The backend now contains `backend/mosdac_datasets.py`, `backend/mosdac_provider.py`, and `backend/mosdac_parsers.py`. See `backend/MOSDAC_INTEGRATION.md` for the evidence record.

- `E06OCM_L4_AC` and `E06SCT_L4_UI` are implemented, live verified, and enabled in the planner.
- `E06SCT_L4_AWV6HOURLY` (corrected from `AWW` typo): Parser reads u/v components, computes wind speed via `hypot(u, v)`. The previously rejected sample `E06SCTL4AH_2026255_0000_25km_v1.0.0.nc` is the correct granule — the SIGMA0 VALUES long_name is a MOSDAC metadata quirk, not a product mismatch.
- `E06OCM_L3_LAC_CQ`: Product is live (157 files on MOSDAC). Schema-discovery parser replaces the hardcoded `water_quality` variable name that was never validated. Provider timeout increased to 60s.
- `E06SCT_L3_WW12` (corrected from `WV12` typo): Recursive HDF5 parser replaces the stub that always raised. The supplied `E06SCTL3WW2026255_12km_v1.0.5.h5` is the correct granule of the `E06SCT_L3_WW12` dataset (flagged wind vectors, 1,069 live files).
- Tier-A `E06SCT_L4_AWV` and `E06SCT_L4_AWV12km` corrected from `AWW`/`AWW12km` typos; registered and disabled.
- All other Tier-A/B/C/D IDs remain registered but disabled.
- Provider timeout for MOSDAC downloads increased from 12s to 60s (`ORCA_MOSDAC_TIMEOUT_SECONDS`).
- Provider now picks the newest search entry (not `entries[0]`) and retries the token once on download 401.

The remaining three Tier-S products have corrected IDs and rebuilt parsers. Enable them in the planner once live verification confirms real granules parse with valid values.

## Audit Reconciliation

Compared on 2026-09-12 with:

- Repository guide: `API-GUIDE.md`
- Downloaded audit: `C:\Users\Aryan Singh\Downloads\API-GIS-AUDIT.md`

The downloaded audit contains useful provider-level evidence, including exact URLs, query shapes, field names, unit conversions, failure modes, and GIS limitations. Its references to files such as `openmeteo_marine.py`, `incois.py`, `imd_cap.py`, `noaa_chl.py`, and `core/geo.py` describe the audited implementation, but those modules are not present in the active backend tree inspected here. They must therefore be treated as integration guidance, not as proof that this repository already implements those providers.

### Verified details to reuse

#### Open-Meteo Marine

Use the public endpoint:

```text
https://marine-api.open-meteo.com/v1/marine
```

Candidate request fields from the audit:

```text
current=wave_height,wave_period,wind_wave_height,swell_wave_height,
swell_wave_period,swell_wave_direction,sea_surface_temperature,
ocean_current_velocity,ocean_current_direction
hourly=wave_height,wave_period,swell_wave_height,swell_wave_period
forecast_days=3
timezone=auto
```

Important correction: the audit says `ocean_current_velocity` is returned in km/h and must be converted to knots by dividing by `1.852`. The active `backend/data_providers.py` currently passes that value through without this conversion; fix this before using current thresholds or displaying knots.

The audit records a real Mumbai offshore observation of approximately 1.12 m wave height, 29.6 C SST, and 0.8 kn current at its test time. Those values are evidence of a prior provider response, not fixtures to embed in ORCA.

#### Open-Meteo Forecast

Use:

```text
https://api.open-meteo.com/v1/forecast
```

Candidate current fields:

```text
temperature_2m,relative_humidity_2m,precipitation,weather_code,
cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m
```

Candidate hourly fields include visibility, CAPE, lightning potential, and precipitation probability. The audit says wind and gust values require km/h-to-knot conversion. The active backend requests knot output for wind speed but does not yet request or preserve the full weather context.

#### INCOIS PFZ WFS

The audit identifies the official endpoint and correct layer name:

```text
https://incois.gov.in/geoserver/PFZ_Automation/ows
```

Request shape:

```text
service=WFS
version=1.0.0
request=GetFeature
typeName=PFZ_Automation:pfzlines
outputFormat=application/json
```

Useful properties are `UID`, `Sno`, `SECTORBOUN`, `Julian_day`, `Year`, and `Length`. `PFZ_Automation:India_EEZ` is the candidate EEZ layer. The audit reports real 503 outages, so this provider needs a bounded timeout, a 3-hour cache, and a last-known-good result labeled with its age. Do not use `pfz_lines`; the audit records that name as a 404.

#### IMD CAP

The audit identifies this official CAP RSS feed:

```text
https://cap-sources.s3.amazonaws.com/in-imd-en/rss.xml
```

Each item links to CAP 1.2 XML. Required fields are event, severity, headline, instruction, area description, polygon, issue time, and expiry time. The audit's relevance gates are mandatory: discard items older than 48 hours for verdicts, apply polygon containment where possible, use state-name plus marine-keyword matching only as a weaker rule, and treat basin-wide cyclone/fisher alerts separately.

#### GDACS Tropical Cyclones

Candidate endpoint:

```text
https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH?eventlist=TC&bbox=60,0,100,30
```

Expected GeoJSON properties include `eventname`, `alertlevel`, `fromdate`, and `severitydata`. The audit describes a distance fold of 300 km for danger and 800 km for caution. Those distances must be implemented as versioned deterministic rules with the event timestamp and geometry retained.

#### JTWC

The audit identifies the RSS feed:

```text
https://www.metoc.navy.mil/jtwc/rss/jtwc.rss
```

It is suitable for corroborating headlines. Full track parsing is not established by the audit and must not be claimed until official product parsing is implemented and tested.

#### NOAA ERDDAP Chlorophyll

The audit provides a concrete primary dataset and query pattern:

```text
https://coastwatch.noaa.gov/erddap/griddap/noaacwNPPN20VIIRSDINEOFDaily.csv
```

The query must include the altitude axis `[(0)]`, use integer strides such as `:3:`, and place the griddap constraint in the URL path/query exactly as required by ERDDAP. Requests need the ORCA User-Agent because the audit observed 403 responses with the default `httpx` User-Agent.

The reported backup is:

```text
https://comet.nefsc.noaa.gov/erddap/griddap/occci_v6_daily_1km.csv
```

The audit reports VIIRS chlorophyll around 1.228 mg/m3 at 18.79 N, 72.62 E observed 2026-09-09 and 31 valid grid cells. These are test evidence only. A real integration must retain the observation date, cell coordinates, quality/cloud state, dataset ID, and raw response.

The audit explicitly retires `erdMH1chla1day` because its data ended in 2022-07. Do not use it.

#### MOSDAC

The audit confirms the portal is reachable but OCM-3 data access is registration/order-based rather than an unauthenticated public API. Keep MOSDAC as an optional backend credential integration only. Until credentials and a granule download are verified, use NOAA as the labeled chlorophyll source and report MOSDAC as unavailable rather than claiming MOSDAC measurements.

#### INCOIS ERDDAP/THREDDS

The audit reports timeout/000 from its test environment. Keep it as a probe-only source until a real response can be captured. Do not use it as a silent fallback.

#### Global Fishing Watch and data.gov.in

- GFW requires a server-side `GFW_API_TOKEN`; empty token means the feature is disabled and no fishing effort value is shown.
- IMD station observations through data.gov.in require `DATA_GOV_IN_KEY`; no key means the feature is unavailable.

Neither credential belongs in Flutter.

#### OSM and GIS

The audit reports real OSM tiles at:

```text
https://tile.openstreetmap.org/{z}/{x}/{y}.png
```

The active Flutter map already uses this source directly. The audit's GIS implementation is described as demo-grade simplified polygons with approximately 5-20 km fidelity and approximate restricted-zone circles. This is not sufficient for a safety-critical land-clearance claim. Replace it with a versioned GLOBE/official raster and official restricted-zone notices before labeling a route safe.

The audit also reports a 24-hour OSM proxy cache. That cache must retain OSM attribution and must not be confused with marine observation caching.

## Updated Priority Order From Both Documents

1. Keep Open-Meteo Marine and Forecast as the live measurement providers, with timestamps, provenance, and unit conversion.
2. Extend NOAA VIIRS ERDDAP with recorded-response tests and cloud/no-data quality handling.
3. Extend INCOIS PFZ WFS with advisory-date parsing and a three-hour last-known-good cache.
4. Complete IMD CAP XML parsing and geographic relevance filtering.
5. Add GDACS distance-based 300/800 km severity folding; keep JTWC as corroboration until track parsing exists.
6. Replace the simplified GIS land heuristic with a versioned raster; keep route detours unverified until pathfinding is validated.
7. Add MOSDAC, GFW, data.gov.in, and INCOIS ERDDAP only after credentials or reachable real responses are available.
8. Implement or disable the `/api/v1/tiles/waves`, `/api/v1/tiles/pfz`, and related overlay routes; repeated 404s must not remain in the UI.

## Conflicts Resolved

- `API-GUIDE.md` claims a broad 12-source pipeline and several live statuses.
- `API-GIS-AUDIT.md` supplies stronger evidence and records important real failures, but references a provider-module tree absent from this repository.
- The active repository code is the final authority for what is currently implemented. The plan now records audit evidence as integration requirements, not as current runtime capability.
