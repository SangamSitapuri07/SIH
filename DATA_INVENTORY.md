# ORCA Data Inventory

Date: 2026-09-12

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
| Swell period | s | Open-Meteo Marine | Advisory/chart | Partial | Provider field identified; full hourly chart integration remains. |
| Ocean current speed | kn | Open-Meteo Marine | Zone/advisory | Partial | Provider returns km/h according to audit; convert using `km/h / 1.852`. |
| Ocean current direction | degrees | Open-Meteo Marine | Zone/advisory | Partial | Raw field identified; display normalization remains. |
| Sea surface temperature | C | Open-Meteo Marine | Zone/advisory | Implemented | Live field requested. |
| Sustained wind | kn | Open-Meteo Forecast | Advisory, safety rules | Implemented | Backend requests knot output. |
| Wind gust | kn | Open-Meteo Forecast | Advisory, safety rules | Implemented | Backend requests knot output. |
| Wind direction | degrees | Open-Meteo Forecast | Zone/advisory | Partial | Request/DTO mapping needs full provenance. |
| Rain / precipitation | mm | Open-Meteo Forecast | Weather context | Not implemented | Add current/hourly mapping before displaying. |
| Visibility | km | Open-Meteo Forecast | Weather context | Not implemented | Candidate field from audit. |
| Cloud cover | percent | Open-Meteo Forecast | Weather context | Not implemented | Candidate field from audit. |
| Pressure | hPa | Open-Meteo Forecast | Weather context | Not implemented | Candidate field from audit. |
| CAPE | J/kg | Open-Meteo Forecast | Weather hazard context | Not implemented | Candidate field from audit. |
| Lightning potential | provider unit | Open-Meteo Forecast | Weather hazard context | Not implemented | Must confirm provider field and unit first. |
| Daily weather code | WMO code | Open-Meteo Forecast | Weather context | Not implemented | Do not convert to text without preserving raw code. |
| Forecast hourly values | provider units | Open-Meteo Marine/Forecast | Hourly chart/safe window | Partial | Current snapshot is available; multi-hour live forecast mapping remains. |
| Chlorophyll-a | mg/m3 | NOAA CoastWatch ERDDAP VIIRS DINEOF | PFZ/map/agents | Implemented, provider may fail | Audit dataset/query is wired; cloud/no-data remains unavailable rather than fabricated. |
| MOSDAC Tier-S products | product-specific | MOSDAC authenticated Download API | Backend planner/cache/provider boundary | Architecture implemented; downloads blocked | Dataset registry and fail-closed provider exist. Full activation needs official catalogue metadata, Download API contract, credentials, and authenticated sample files. |
| Chlorophyll cross-check | mg/m3 | ESA OC-CCI via ERDDAP | Satellite cross-check | Not implemented | Use only as a separately labeled product. |
| PFZ advisory geometry | GeoJSON lines | INCOIS PFZ GeoServer WFS | Map/alerts/agents | Implemented | Uses `PFZ_Automation:pfzlines`; failures are reported. |
| India EEZ geometry | GeoJSON polygon | INCOIS PFZ GeoServer WFS | Map/geography | Not implemented | Candidate layer `PFZ_Automation:India_EEZ`. |
| Cyclone warning | CAP 1.2 XML | IMD CAP feed | Alerts/safety context | Partial | RSS is wired with a 48-hour freshness gate; linked CAP XML/polygon relevance remains. |
| Tropical cyclone event | GeoJSON | GDACS TC API | Alerts/safety context | Implemented, basic | Events are wired; distance-based 300/800 km folding remains. |
| Cyclone headline | RSS | JTWC RSS | Alerts corroboration | Implemented, headline only | Full track parsing is not enabled. |
| Fishing effort | hours/km2 | Global Fishing Watch | Map/agents | Not implemented | Requires backend-only `GFW_API_TOKEN`; no token means unavailable. |
| Station observations | provider units | data.gov.in IMD AWS | Weather cross-check | Not implemented | Requires backend-only `DATA_GOV_IN_KEY`. |
| Bathymetry/depth | m | GEBCO or official hydrographic data | Map/route/agents | Not implemented | Do not use hardcoded depth. |
| Land/water classification | boolean/raster class | Versioned GLOBE or official raster | Route/map/safety | Partial | Current implementation is a simplified geographic heuristic, not a real raster. |
| Restricted zones | geometry + notice | Official notices/datasets | Route/map | Not implemented | Current approximate circles are not sufficient for a safety claim. |
| Harbour/place search | coordinates/name | OpenStreetMap Nominatim | Map search | Partial | Search data only; not marine conditions. |
| Base map tiles | PNG tiles | OpenStreetMap | Flutter Map | Implemented | Real map tiles; attribution and rate limits apply. |
| Wave overlay tiles | PNG tiles | ORCA server/provider | Map layer | Not implemented | Current requests return `404`; implement or disable the layer. |
| PFZ overlay tiles | PNG tiles | ORCA server/provider | Map layer | Not implemented | Current requests return `404`; implement or disable the layer. |

## Derived Data

| Derived value | Inputs required | Consumer | Status | Rule |
|---|---|---|---|---|
| Safety verdict | Wave, sustained wind, gust, land status | Home/Navigate | Implemented | Wave >= 4 m or gust >= 34 kn = NO-GO; wave >= 2.5 m or wind >= 20 kn = CAUTION. |
| Safety explanation | Validated live inputs | Home/AI Trace | Partial | LLM may explain; it cannot override deterministic verdict. |
| Safe departure window | Hourly marine/weather forecast | Home/Navigate | Partial | Must be computed from real forecast hours, not hardcoded times. |
| Route distance/bearing | User coordinates | Navigate | Implemented | Geometry is derived, not a measurement source. |
| Route detour | Versioned land/water mask | Navigate | Partial | Must not use a fabricated coordinate; return unverified if no valid detour. |
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
  -> validation and deterministic safety rules
  -> Hive cache with fetched_at/TTL
  -> Flutter UI
```

The next real-data integrations should be NOAA chlorophyll, INCOIS PFZ WFS, IMD CAP, GDACS cyclone events, and a versioned land/water raster.

## MOSDAC Dataset Activation

| Tier | Dataset IDs | Activation state |
|---|---|---|
| Tier-S | `E06OCM_L4_AC`, `E06SCT_L4_AWW6HOURLY`, `E06SCT_L4_UI`, `E06OCM_L3_LAC_CQ`, `E06SCT_L3_WV12` | Enabled in registry/planner; provider fails closed until official API metadata and authenticated files are verified. |
| Tier-A | `E06SCT_L2B_WV12`, `E06SCT_L4_AWW`, `E06SCT_L4_AWW12km`, `E06SCT_L3_WV25`, `E06SCT_L2B_WV25`, `E06OCM_L2C_LAC_PS`, `E06OCM_L3_LAC_PC`, `E06OCM_L2C_LAC_PR`, `E06OCM_L2C_LAC_OC`, `E06OCM_L2C_LAC_GA`, `E06OCM_L3_LAC_FL` | Registered and disabled. |
| Tier-B/C/D | All IDs from the activation brief | Registered and disabled; never planned or fetched. |
