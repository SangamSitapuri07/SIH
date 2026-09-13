# ORCA Data Inventory

Date: 2026-09-13

Legend:

- **Implemented**: active backend/frontend path exists.
- **Partial**: source or contract is present, but integration is incomplete.
- **Not implemented**: no active real-data provider path.
- **Prototype only**: bundled fixture; never valid as Live Mode data.
- **Cached**: last real response may be reused with freshness/staleness metadata.

## Live Data

| Data / variable | Unit | Real source | ORCA endpoint / consumer | Status | Notes |
|---|---:|---|---|---|---|
| Wave height | m | Open-Meteo Marine | `/api/v1/zone`, `/api/v1/advisory`, Map, Home | Implemented | Live request path exists; no coordinate-generated fallback allowed. |
| Wave period | s | Open-Meteo Marine | Zone, advisory, agents | Implemented | Must retain provider timestamp. |
| Swell height | m | Open-Meteo Marine | Zone/advisory | Implemented | Returned when provider supplies it. |
| Swell period | s | Open-Meteo Marine | Advisory/chart | Not implemented | Requested upstream but not mapped into the zone response or chart. |
| Ocean current speed | kn | Open-Meteo Marine | Zone/advisory | Implemented, provenance partial | Converted from provider km/h using `km/h / 1.852`; raw response metadata is still not retained. |
| Ocean current direction | degrees | Open-Meteo Marine | Zone/advisory | Implemented, provenance partial | Returned from the live provider; full source timestamp/provenance mapping remains. |
| Sea surface temperature | C | Open-Meteo Marine | Zone/advisory | Implemented | Live field requested. |
| Sustained wind | kn | Open-Meteo Forecast | Advisory, safety rules | Implemented | Backend requests knot output. |
| Wind gust | kn | Open-Meteo Forecast | Advisory, safety rules | Implemented | Backend requests knot output. |
| Wind direction | degrees | Open-Meteo Forecast | Zone/advisory | Implemented, provenance partial | Returned from the live provider; full source timestamp/provenance mapping remains. |
| Rain / precipitation | mm | Open-Meteo Forecast | Weather context | Not implemented | Add current/hourly mapping before displaying. |
| Visibility | km | Open-Meteo Forecast | Weather context | Not implemented | Candidate field from audit. |
| Cloud cover | percent | Open-Meteo Forecast | Weather context | Not implemented | Candidate field from audit. |
| Pressure | hPa | Open-Meteo Forecast | Weather context | Not implemented | Candidate field from audit. |
| CAPE | J/kg | Open-Meteo Forecast | Weather hazard context | Not implemented | Candidate field from audit. |
| Lightning potential | provider unit | Open-Meteo Forecast | Weather hazard context | Not implemented | Must confirm provider field and unit first. |
| Daily weather code | WMO code | Open-Meteo Forecast | Weather context | Not implemented | Do not convert to text without preserving raw code. |
| Forecast hourly values | provider units | Open-Meteo Marine/Forecast | `/api/v1/advisory` hourly chart | Implemented, safe-window partial | Real hourly wave and wind values are requested and returned; safe departure interval selection remains pending. |
| Chlorophyll-a | mg/m3 | NOAA CoastWatch ERDDAP VIIRS DINEOF | PFZ/map/agents | Implemented, provider may fail | Audit dataset/query is wired; cloud/no-data remains unavailable rather than fabricated. |
| MOSDAC Tier-S products | product-specific | MOSDAC authenticated Download API | Backend provider, planner, parser, cache | Implemented: 4 verified & enabled, 1 parser-ready | `E06OCM_L4_AC`, `E06SCT_L4_UI`, `E06SCT_L4_AWV6HOURLY`, and `E06SCT_L3_WW12` passed live search/download/parse/normalize/cache verification. `E06OCM_L3_LAC_CQ` catalog entry is live; download returned 404 for archived entry; schema-discovery parser ready. |
| Chlorophyll cross-check | mg/m3 | ESA OC-CCI via ERDDAP | Satellite cross-check | Not implemented | Use only as a separately labeled product. |
| PFZ advisory geometry | GeoJSON lines | INCOIS PFZ GeoServer WFS | Map/alerts/agents | Implemented | Uses `PFZ_Automation:pfzlines`; failures are reported. |
| India EEZ geometry | GeoJSON polygon | INCOIS PFZ GeoServer WFS | Map/geography | Not implemented | Candidate layer `PFZ_Automation:India_EEZ`. |
| Cyclone warning | CAP/RSS | IMD CAP feed | `/api/v1/alerts` | Partial | Official RSS is fetched and filtered to 48 hours; linked CAP XML fields, polygon relevance, expiry, and caching remain. |
| Tropical cyclone event | GeoJSON | GDACS TC API | Alerts/safety context | Implemented, basic | Events are wired; distance-based 300/800 km folding remains. |
| Cyclone headline | RSS | JTWC RSS | Alerts corroboration | Implemented, headline only | Full track parsing is not enabled. |
| Fishing effort and fleet | hours, vessel count, flag/gear groups | Global Fishing Watch 4Wings | `/api/v1/zone`, `/api/v1/reason`, `/api/v1/advisory` with `include_gfw=true` | Implemented, optional | Official Bearer-token effort/fleet reports, bounded Polygon request, date clamping, six-hour atomic cache, persisted cooldown, and honest failure states. |
| Station observations | provider units | data.gov.in IMD AWS | Weather cross-check | Not implemented | Requires backend-only `DATA_GOV_IN_KEY`. |
| Bathymetry/depth | m | GEBCO or official hydrographic data | Map/route/agents | Not implemented | Do not use hardcoded depth. |
| Land/water classification | boolean/raster class | Versioned GLOBE or official raster | Route/map/safety | Partial, not safety-grade | Current implementation is a regional geographic heuristic, not a bundled GLOBE raster. |
| Restricted zones | geometry + notice | Official notices/datasets | Route/map | Not implemented | Current approximate circles are not sufficient for a safety claim. |
| Harbour/place search | coordinates/name | OpenStreetMap Nominatim | Map search | Partial | Search data only; not marine conditions. |
| Base map tiles | PNG tiles | OpenStreetMap | Flutter Map | Implemented | Real map tiles; attribution and rate limits apply. |
| Wave overlay tiles | PNG tiles | ORCA server/provider | Map layer | Not implemented | No backend tile route exists; hide or implement the layer. |
| PFZ overlay tiles | PNG tiles | ORCA server/provider | Map layer | Not implemented | No backend tile route exists; hide or implement the layer. |

## Derived Data

| Derived value | Inputs required | Consumer | Status | Rule |
|---|---|---|---|---|
| Safety verdict | Wave, sustained wind, gust, land status | Home/Navigate | Implemented | Wave >= 4 m or gust >= 34 kn = NO-GO; wave >= 2.5 m or wind >= 20 kn = CAUTION. |
| Safety explanation | Validated live inputs | Home/AI Trace | Partial | LLM may explain; it cannot override deterministic verdict. |
| Safe departure window | Hourly marine/weather forecast | Home/Navigate | Not implemented | Real hourly values are available; selecting a safe departure interval remains pending. |
| Route distance/bearing | User coordinates | Navigate | Implemented | Geometry is derived, not a measurement source. |
| Route detour | Versioned land/water mask | Navigate | Not implemented | Fabricated detours were removed; route returns no detour and `UNVERIFIED` until a verified raster/pathfinder exists. |
| Cached freshness | Real response timestamps | All data screens | Implemented | Hive cache stores fetched time and TTL; UI must show stale/live honestly. |
| Data coverage | Successful/failed provider calls | Home/AI/Info | Partial | Must count only providers actually queried in the request. |

## User Data

| Data | Source | Storage | Status | Live-mode rule |
|---|---|---|---|---|
| Profile | User input/Supabase | Local cache + backend/Supabase | Partial | No seeded identity or vessel details. Empty means unconfigured. |
| Saved places | User input | Local cache + sync backend | Partial | Starts empty; no seeded locations. |
| Advisory history | Real completed advisories | Local cache/backend | Partial | Starts empty; no automatic sample history. |
| Catch reports | User input | Local cache + sync backend | Partial | Starts empty; no fake reports. |
| Alerts | IMD/GDACS/JTWC/rules | Local cache | Partial | Live Mode returns real alerts or empty; no hardcoded alert cards. |

## Prototype-Only Data

| Fixture | File | Allowed when |
|---|---|---|
| Advisory | `frontend/assets/fixtures/advisory.json` | Explicit `Show Prototype` enabled. |
| Agent reasoning | `frontend/assets/fixtures/reason.json` | Explicit `Show Prototype` enabled. |
| Alerts | `frontend/assets/fixtures/alerts.json` | Explicit `Show Prototype` enabled. |
| Health | `frontend/assets/fixtures/health.json` | Explicit `Show Prototype` enabled. |
| Map zone | `frontend/assets/fixtures/zone.json` | Explicit `Show Prototype` enabled. |
| Route check/advisory | `frontend/assets/fixtures/route_check.json`, `route_advisory.json` | Explicit `Show Prototype` enabled. |

Prototype fixtures must never appear because a live request failed, timed out, or returned no data.

## Current Real Data Path

```text
Flutter Live Mode
  -> ORCA Box FastAPI
  -> Open-Meteo Marine + Open-Meteo Forecast
  -> NOAA chlorophyll + INCOIS PFZ when those calls succeed
  -> validation and deterministic safety rules
  -> Hive cache with fetched_at/TTL
  -> Flutter UI
```

Alerts use separate IMD, GDACS, and JTWC calls through `/api/v1/alerts`; they are not inputs to the zone snapshot. The next work is to add source timestamps/provenance and honest server-side caching, calculate a safe departure interval from the real hourly series, and replace the land heuristic with a versioned raster.

## MOSDAC Dataset Activation

| Tier | Dataset IDs | Activation state |
|---|---|---|
| Tier-S | `E06OCM_L4_AC`, `E06SCT_L4_AWV6HOURLY`, `E06SCT_L4_UI`, `E06OCM_L3_LAC_CQ`, `E06SCT_L3_WW12` | `E06OCM_L4_AC`, `E06SCT_L4_UI`, `E06SCT_L4_AWV6HOURLY`, and `E06SCT_L3_WW12` enabled and live verified against official MOSDAC Download API. `E06OCM_L3_LAC_CQ` catalog entry live with schema-discovery parser ready; download returned 404 for archived granule. |
| Tier-A | `E06SCT_L2B_WV12`, `E06SCT_L4_AWV`, `E06SCT_L4_AWV12km`, `E06SCT_L3_WV25`, `E06SCT_L2B_WV25`, `E06OCM_L2C_LAC_PS`, `E06OCM_L3_LAC_PC`, `E06OCM_L2C_LAC_PR`, `E06OCM_L2C_LAC_OC`, `E06OCM_L2C_LAC_GA`, `E06OCM_L3_LAC_FL` | Registered and disabled. `AWV` and `AWV12km` IDs corrected from previous `AWW` typos. |
| Tier-B/C/D | All IDs from the activation brief | Registered and disabled; never planned or fetched. |
