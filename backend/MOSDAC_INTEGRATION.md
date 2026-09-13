# MOSDAC Integration

The backend uses the official MOSDAC Download API workflow. Search uses `GET https://mosdac.gov.in/apios/datasets.json` with `datasetId` and optional `startTime`, `endTime`, `count`, `boundingBox`, and `gId`. Downloads authenticate with `POST https://mosdac.gov.in/download_api/gettoken`, then stream `GET https://mosdac.gov.in/download_api/download?id=...` with the returned bearer token. Credentials are read only from backend environment variables.

## Key Trap: MOSDAC HTTP 500

MOSDAC returns HTTP 500 "Data unavailable for given parameters" for an **unknown** `datasetId` — not a 404. A one-letter typo looks exactly like "product unavailable". This caused three datasets to be incorrectly marked as blocked.

## ID Corrections

| Original (Typo) ID | Corrected ID | Live Files | Evidence |
|---|---|---|---|
| `E06SCT_L4_AWW6HOURLY` | `E06SCT_L4_AWV6HOURLY` | ~4,756 | AWV = Analyzed Wind Vector; search API returns gId=18401334 |
| `E06SCT_L3_WV12` | `E06SCT_L3_WW12` | ~1,069 | gId=18400558, "flagged wind vectors in global grid" |
| `E06SCT_L4_AWW` (Tier-A) | `E06SCT_L4_AWV` | ~1,330 | Live search confirms |
| `E06SCT_L4_AWW12km` (Tier-A) | `E06SCT_L4_AWV12km` | ~393 | Live search confirms |

## Activation

The registry is in `mosdac_datasets.py`. Registration never triggers network activity. Only enabled datasets are eligible for planning. Tier-A, Tier-B, Tier-C, and Tier-D entries are registered metadata-only and disabled.

Current Tier-S evidence:

| Dataset | Enabled | Implemented | Live result | Status |
| --- | ---: | ---: | --- | --- |
| `E06OCM_L4_AC` | yes | yes | Search, authenticated download, parser, normalization, provenance, and cache passed | `VERIFIED` |
| `E06SCT_L4_AWV6HOURLY` | yes | yes | Live search, token auth, download, u/v vector parsing, and hypot(u,v) wind speed calculation passed (`5.14 m/s`) | `VERIFIED` |
| `E06SCT_L4_UI` | yes | yes | Search, authenticated download, parser, normalization, provenance, and cache passed | `VERIFIED` |
| `E06OCM_L3_LAC_CQ` | no | yes | Product catalog entry live (157 files). Schema-discovery parser reads actual variable names. Download returned 404 for archived granule. | `PARSER_READY` |
| `E06SCT_L3_WW12` | yes | yes | Live search, token auth, download, and recursive HDF5 science_data parser passed | `VERIFIED` |

## Supplied Real Samples

Local products are kept under `mosdac/` and ignored by Git because they are large test inputs:

- `E06OCML4AC_20260329_25km_v1.0.1.nc`: classic NetCDF, dimensions `time=1`, `lev=1`, `lat=1080`, `lon=1440`; variable `chla`; `_FillValue` and `missing_value` are `-9.99e8`; time is days since `2026-03-29 00:00:00`; coordinate units are degrees north/east.
- `E06OCML4AC_20260330_25km_v1.0.1.nc`: same schema; time is days since `2026-03-30 00:00:00`.
- `E06SCTL4UI_2026254_25km_v1.0.5.nc`: classic NetCDF, `time=1`, `lev=1`, `lat=721`, `lon=1441`; variable `Upwelling_index`, unit `m^2/s`, fill value `-999999`; time is days since `11-09-2026 12:00`.
- `E06SCTL3WW2026255_12km_v1.0.5.h5`: HDF5 `science_data` group with ascending/descending wind direction, speed, and quality-flag arrays. Recursive HDF5 parser extracts wind values with scale/offset.
- `E06SCTL4AH_2026255_0000_25km_v1.0.0.nc`: classic NetCDF with `u` and `v` wind component variables. The `long_name` attribute reads "SIGMA0 VALUES" due to a MOSDAC metadata quirk — this is the correct AWV6HOURLY granule (Analyzed Wind Vectors computed using Particle Filter Technique). Parser computes wind speed = hypot(u, v) and meteorological direction.

The parser extracts only a requested or nearest valid coordinate cell. Fill, missing, NaN, and infinite values become `value=None` with `quality=unavailable`; no replacement measurement is generated. Scale and offset attributes are applied when present. Product timestamps are preserved as `observed_at`, and parser/fetch timestamps are separate.

## Provider Improvements

- **Timeout**: MOSDAC-specific timeout `ORCA_MOSDAC_TIMEOUT_SECONDS=60` (was using general 12s timeout).
- **Entry selection**: Picks newest search entry by `startTime`/`id`, not `entries[0]`.
- **Token retry**: On download 401, refreshes token once and retries.
- **HTTP 500 diagnostic**: Error message now indicates that HTTP 500 may mean the dataset ID is wrong.

## Cache and Provenance

Cache keys include the provider, dataset ID, and a stable hash of request parameters. Raw products are streamed to disk and normalized records retain the raw file reference and MOSDAC record ID. Only `live` or `fresh` parsed results may be cached. Search, authentication, download, parser, or validation failures cannot become successful cache entries. Cached records return `fresh` or `stale` based on the dataset TTL.

## Testing

Unit tests use the real local MOSDAC samples for parser and cache behavior. The live verification run used one bounded request per Tier-S dataset with credentials supplied through the ignored `backend/.env`; credentials and tokens were never printed. Mocked tests are not used to claim the live statuses above.

Typical commands:

```text
python -m unittest test_mosdac_datasets.py test_mosdac_provider.py
```

## Activation Summary

Four Tier-S products (`E06OCM_L4_AC`, `E06SCT_L4_UI`, `E06SCT_L4_AWV6HOURLY`, and `E06SCT_L3_WW12`) are live-verified and enabled in `mosdac_datasets.py`. `E06OCM_L3_LAC_CQ` is parser-ready.

