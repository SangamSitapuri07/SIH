# Prompt: Implement Global Fishing Watch in a Marine API

Copy everything below this line and paste it into another coding AI.

---

You are working on a Python FastAPI marine-intelligence backend. Implement a
production-quality Global Fishing Watch (GFW) integration using the GFW API
v3 `4wings/report` endpoint.

## Goal

Add real AIS-derived fishing data to a location snapshot:

1. Fishing effort in hours for a coordinate and date range.
2. Active vessel count.
3. Fleet breakdown by flag/country.
4. Fleet breakdown by gear type.
5. Honest source errors when the token is missing, the API fails, or the
   account is rate-limited.

Do not generate fake data, fallback values, or placeholder vessel counts.

## Required configuration

Read the token from the environment:

```dotenv
GFW_API_TOKEN=real_access_token_here
```

Never print the token, commit it, or return it through an API response.
Support an explicit function argument such as `token=` for tests, but use
`GFW_API_TOKEN` by default.

## GFW API

Use this base URL:

```text
https://gateway.api.globalfishingwatch.org/v3
```

Use this dataset:

```text
public-global-fishing-effort:latest
```

Use this endpoint:

```text
POST /4wings/report
```

Authentication:

```http
Authorization: Bearer <GFW_API_TOKEN>
Content-Type: application/json
Accept: application/json
```

Put report parameters in the query string. Put only the GeoJSON polygon in
the request body.

## Effort request

Implement a function with this contract:

```python
get_fishing_effort(
    lat: float,
    lon: float,
    start_date: str,
    end_date: str,
    radius_deg: float = 0.5,
    token: str | None = None,
) -> dict
```

Use query parameters equivalent to:

```text
datasets[0]=public-global-fishing-effort:latest
date-range=<start>T00:00:00.000Z,<end>T00:00:00.000Z
format=JSON
spatial-resolution=LOW
temporal-resolution=ENTIRE
group-by=VESSEL_ID
spatial-aggregation=true
```

Send a closed rectangular GeoJSON polygon:

```json
{
  "geojson": {
    "type": "Polygon",
    "coordinates": [[
      [min_lon, min_lat],
      [max_lon, min_lat],
      [max_lon, max_lat],
      [min_lon, max_lat],
      [min_lon, min_lat]
    ]]
  }
}
```

Normalize the response to something like:

```json
{
  "hours": 47.3,
  "vessel_ids": 12,
  "lat": 20.9,
  "lon": 70.37,
  "start_date": "2026-08-01",
  "end_date": "2026-08-30",
  "requested_start": "2026-08-01",
  "requested_end": "2026-08-30",
  "source": "Global Fishing Watch",
  "bbox": {},
  "n_entries": 12
}
```

Support both flat and grouped GFW response shapes. Count unique vessel IDs,
and read total effort from `total`, `hours`, or the equivalent documented
field without double-counting grouped entries.

## Fleet request

Implement a second function with this contract:

```python
get_fishing_vessels_in_region(
    lat: float,
    lon: float,
    radius_deg: float = 0.5,
    start_date: str | None = None,
    end_date: str | None = None,
    token: str | None = None,
) -> dict
```

Use the same endpoint and polygon, but use:

```text
group-by=FLAGANDGEARTYPE
```

Normalize to:

```json
{
  "vessel_count": 28,
  "by_flag": {"IND": 28},
  "by_gear": {"drifting_longlines": 19},
  "lat": 20.9,
  "lon": 70.37,
  "start_date": "2026-08-01",
  "end_date": "2026-08-30",
  "source": "Global Fishing Watch",
  "bbox": {}
}
```

Support vessel IDs represented as `vesselIDs`, `vesselIds`, or
`vessel_ids`. If the response supplies integer counts instead of ID arrays,
use those counts. Do not claim unique counts when uniqueness cannot be
determined.

## Date safety

GFW data may have a processing delay. Add a date-normalization helper that:

- Prevents future dates.
- Limits the usable range to the service/free-tier limit, approximately 90
  days unless the API's current documented limit says otherwise.
- Defaults the end date to approximately four days before today when omitted.
- Returns the actual clamped dates in the response.

Do not silently pretend that the requested date was used. Preserve both the
requested and actual date ranges.

## Caching and persistence

Cache only successful responses. Do not cache authentication errors, network
errors, or 429 responses as successful data.

The cache key must include operation, latitude, longitude, radius, start date,
and end date. Persist the cache and rate-limit state to a JSON file such as:

```text
data/gfw_cache.json
```

Persist at least `entries`, `rate_limited_until`, and `last_headers`.
Write the file atomically through a temporary file followed by replacement.
Prune expired entries and bound the maximum number of entries. A backend
restart must not erase a valid cache or an active GFW cooldown.

## Rate limits and retries

Handle HTTP 429 explicitly:

1. Read `Retry-After` when available.
2. Read GFW headers such as `x-ratelimit-daily-remaining-requests` and
   `x-ratelimit-daily-reset-hours`.
3. Retry at most once for a burst 429 when the daily quota remains.
4. Do not repeatedly retry daily quota exhaustion.
5. Persist a global cooldown timestamp.
6. Return an honest error object containing `rate_limited: true`.
7. Serve an existing successful cache entry during a cooldown when the cache
   key matches.

Throttle outbound calls enough to avoid rapidly triggering the free-tier burst
limiter. Use request timeouts and browser-compatible headers if required.

## FastAPI integration

Add GFW data to the existing location snapshot. The snapshot must still
return when GFW fails because GFW is optional.

Add a request option like:

```text
include_gfw=true|false
```

Expose the data through routes such as:

```text
GET /api/v1/zone?lat=20.9&lon=70.37&include_gfw=true
GET /api/v1/reason?lat=20.9&lon=70.37&include_gfw=true
GET /api/v1/advisory?lat=20.9&lon=70.37&include_gfw=true
```

The snapshot should contain normalized fields similar to:

```json
{
  "fishing_hours": 47.3,
  "fishing_vessel_ids": 12,
  "fleet_vessel_count": 28,
  "fleet_by_flag": {"IND": 28},
  "fleet_by_gear": {"drifting_longlines": 19},
  "gfw_start_date": "2026-08-01",
  "gfw_end_date": "2026-08-30",
  "data_sources_used": [
    "Global Fishing Watch (fishing effort)",
    "Global Fishing Watch (fleet)"
  ],
  "data_sources_failed": []
}
```

Use concurrent source fetching if the backend already has a source-gathering
layer, but give each GFW operation its own bounded timeout. A slow GFW call
must not block all other marine sources indefinitely.

## Error contract

Return structured, non-secret errors such as:

```json
{
  "error": "GFW_API_TOKEN not set",
  "source": "GFW"
}
```

For rate limits, return `source: "GFW"` and `rate_limited: true`. Never expose
authorization headers, tokens, passwords, or raw sensitive request bodies.

## Tests required

Add offline tests with mocked HTTP calls. Do not require credentials or live
network access. Cover:

1. Missing token returns an honest error.
2. Correct endpoint, query parameters, and polygon.
3. Flat and grouped effort responses parse correctly.
4. Fleet data groups by flag and gear.
5. Duplicate vessel IDs count once when IDs are available.
6. Dates clamp to the supported range.
7. Successful responses cache correctly with distinct location/date keys.
8. Cache state survives reload from the JSON file.
9. Burst 429 retries at most once.
10. Daily quota 429 creates a persisted cooldown.
11. Cached success is available while cooldown is active.
12. GFW failure does not fail the complete zone snapshot.
13. API responses never contain the token.

## Acceptance criteria

The implementation is complete only when:

- A real configured token can retrieve effort and fleet data.
- `/api/v1/zone?include_gfw=true` exposes normalized GFW fields.
- Missing credentials produce a clear source failure, not a crash.
- 429 handling avoids repeated quota-burning calls.
- Cache and cooldown survive backend restarts.
- All GFW tests pass offline.
- No secrets are committed or printed.
- API documentation lists the route, fields, date behavior, and failure
  behavior.

Before editing, inspect the repository and reuse its HTTP, cache,
configuration, typing, logging, and test conventions. Keep the change scoped
to the GFW integration and related snapshot/API tests. Do not rewrite
unrelated modules.

At the end, report files changed, routes updated, cache/rate-limit behavior,
tests executed, and anything that could not be verified without a real token.