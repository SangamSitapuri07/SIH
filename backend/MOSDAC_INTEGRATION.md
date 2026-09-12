# MOSDAC Integration

The backend uses the official MOSDAC Download API workflow. Search uses `GET https://mosdac.gov.in/apios/datasets.json` with `datasetId` and optional `startTime`, `endTime`, `count`, `boundingBox`, and `gId`. Downloads authenticate with `POST https://mosdac.gov.in/download_api/gettoken`, then stream `GET https://mosdac.gov.in/download_api/download?id=...` with the returned bearer token. Credentials are read only from backend environment variables.

## Activation

The registry is in `mosdac_datasets.py`. Registration never triggers network activity. Only enabled datasets are eligible for planning. Tier-A, Tier-B, Tier-C, and Tier-D entries are registered metadata-only and disabled.

Current Tier-S evidence:

| Dataset | Enabled | Implemented | Live result | Status |
| --- | ---: | ---: | --- | --- |
| `E06OCM_L4_AC` | yes | yes | Search, authenticated download, parser, normalization, provenance, and cache passed | `VERIFIED` |
| `E06SCT_L4_AWW6HOURLY` | no | no | Live request failed with an HTTP error; supplied similarly named file is `OSCAT3_GLO_25km` sigma0 data | `LIVE_VERIFICATION_FAILED` |
| `E06SCT_L4_UI` | yes | yes | Search, authenticated download, parser, normalization, provenance, and cache passed | `VERIFIED` |
| `E06OCM_L3_LAC_CQ` | no | no | Live download was unavailable; no Coastal Water Quality sample was supplied | `LIVE_VERIFICATION_FAILED` |
| `E06SCT_L3_WV12` | no | no | Live request failed with an HTTP error; supplied HDF5 lacks geolocation, time, scaling, and product metadata | `METADATA_VERIFICATION_BLOCKED` |

These statuses are evidence-based. The five Tier-S datasets are not all verified.

## Supplied Real Samples

Local products are kept under `mosdac/` and ignored by Git because they are large test inputs:

- `E06OCML4AC_20260329_25km_v1.0.1.nc`: classic NetCDF, dimensions `time=1`, `lev=1`, `lat=1080`, `lon=1440`; variable `chla`; `_FillValue` and `missing_value` are `-9.99e8`; time is days since `2026-03-29 00:00:00`; coordinate units are degrees north/east.
- `E06OCML4AC_20260330_25km_v1.0.1.nc`: same schema; time is days since `2026-03-30 00:00:00`.
- `E06SCTL4UI_2026254_25km_v1.0.5.nc`: classic NetCDF, `time=1`, `lev=1`, `lat=721`, `lon=1441`; variable `Upwelling_index`, unit `m^2/s`, fill value `-999999`; time is days since `11-09-2026 12:00`.
- `E06SCTL3WW2026255_12km_v1.0.5.h5`: HDF5 `science_data` group with ascending/descending wind direction, speed, and quality-flag arrays. The file itself does not provide the geolocation, time, scaling, or product metadata required for a normalized observation.
- `E06SCTL4AH_2026255_0000_25km_v1.0.0.nc`: classic NetCDF with `u` and `v` variables whose long name is `SIGMA0 VALUES`, global history identifies `OSCAT3_GLO_25km`; it is not accepted as `E06SCT_L4_AWW6HOURLY`.

The parser extracts only a requested or nearest valid coordinate cell. Fill, missing, NaN, and infinite values become `value=None` with `quality=unavailable`; no replacement measurement is generated. Scale and offset attributes are applied when present. Product timestamps are preserved as `observed_at`, and parser/fetch timestamps are separate.

## Cache and Provenance

Cache keys include the provider, dataset ID, and a stable hash of request parameters. Raw products are streamed to disk and normalized records retain the raw file reference and MOSDAC record ID. Only `live` or `fresh` parsed results may be cached. Search, authentication, download, parser, or validation failures cannot become successful cache entries. Cached records return `fresh` or `stale` based on the dataset TTL.

## Testing

Unit tests use the real local MOSDAC samples for parser and cache behavior. The live verification run used one bounded request per Tier-S dataset with credentials supplied through the ignored `backend/.env`; credentials and tokens were never printed. Mocked tests are not used to claim the live statuses above.

Typical commands:

```text
python -m unittest discover -s backend -p "test_*.py" -v
```

The official client archive was inspected from `mdapi.py` and `config.json`; it is not copied into the repository. Its shipped configuration uses `username/email`, `skip_user_input`, and `generate_error_logs/error_logs_dir`, while the backend adapter uses the same documented request flow with environment credentials and no interactive prompt.

## Limitations

The three unverified Tier-S products remain disabled and do not participate in normal advisory planning or background synchronization. Enable them only after a real product-specific sample, official metadata, successful live download, parser validation, and cache round-trip are demonstrated.
