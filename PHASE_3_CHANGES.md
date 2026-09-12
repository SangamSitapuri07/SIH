# ORCA Phase 3 Changes

Date: 2026-09-12

## Runtime Errors Fixed

- Advisory and map endpoints return `timestamp` as Unix epoch seconds. The Flutter DTOs now parse epoch numbers and ISO strings at the DTO boundary.
- The advisory backend sends flat numeric variables such as `wave_height_m`; the Flutter DTO now maps those values into `VariableItem` cards instead of dropping them and rendering `--`.
- The advisory safe-window contract accepts the backend's `start` and `end` keys as well as cached `from` and `to` keys.
- Alerts return an envelope (`{"alerts": [...]}`); the Flutter datasource now unwraps it.
- Alert `issued_at` and `expires_at` values now accept epoch seconds and ISO strings.
- Agent failures now distinguish connection refusal, request timeout, and HTTP/data errors instead of labeling every failure as an unreachable ORCA Box.

## Real Mode And Prototype Mode

- Real Mode remains the default.
- Prototype fixtures are loaded only when the persisted `settings.demo_mode` flag is explicitly enabled.
- Removed visible sample chat questions and answers from the normal application surface.
- Removed seeded backend saved locations.
- Removed automatic fake history generation.
- Removed seeded backend profile identity and vessel details. An unconfigured profile is now returned as empty.
- Removed hardcoded backend alert cards. Live Mode now returns verified alerts or an honest empty list.

## Live Data

- `/api/v1/zone` no longer calculates wave, wind, SST, current, or chlorophyll values from coordinates.
- The backend now requests live Open-Meteo Marine and Open-Meteo Forecast data for the requested coordinate.
- If the live provider is unavailable or returns incomplete required values, the endpoint returns an explicit error. It does not invent replacement measurements.
- OpenStreetMap base tiles remain real map tiles; they are not ocean measurements.

## Cache

- Advisory data was already persisted in Hive and is reused while fresh; if a live request fails, the last cached real advisory is returned with staleness metadata.
- Map probe data was already persisted in Hive and is reused if the live probe fails.
- Active alerts now persist in Hive and are reused when the alert request fails.
- Cache records include `fetched_at` and TTL metadata. Cached results retain their stale/fresh state instead of being presented as newly live data.
- The cache is local to the device/browser profile and survives closing and reopening the app. Clearing browser/app storage removes it.

## Performance

- Ollama attempt timeout was reduced from 25 seconds to 8 seconds.
- Once Ollama is unreachable, the backend marks it unavailable for the current process instead of repeating the timeout for every sequential agent.
- Deterministic safety evaluation remains authoritative and does not depend on LLM output.

## Validation

- Advisory DTO regression tests pass, including the exact production epoch timestamp.
- Map DTO regression tests pass, including the live zone epoch timestamp.
- Full Flutter test suite passed: 30 tests.
- Flutter web build passed.
- Backend Python syntax check passed.
- Local and LAN health endpoints previously returned HTTP 200.

## Current Limitations

- The external Open-Meteo Marine request timed out during the latest verification. `/api/v1/zone` returned an explicit `Live marine data unavailable: timed out` error rather than synthetic values; cached real data can still be used when available.
- Live endpoint verification returned `alerts=0`, `locations=0`, and `history=0` for a clean Real Mode backend.
- Full Flutter test suite passed: 30 tests. Backend `py_compile` passed.
- `flutter analyze` still exits nonzero because the repository contains existing warnings and infos; the changed files have no new analyzer errors after the alert contract fix.
- A physical Android device test and the complete manual responsive browser matrix remain outstanding.
- No APK was built because the requested acceptance criteria require those validation gates first.

## Files Changed In This Pass

- `backend/data_providers.py`
- `backend/ollama_client.py`
- `backend/routes_v1.py`
- `frontend/lib/features/advisory/data/dto/advisory_dto.dart`
- `frontend/lib/features/agents/presentation/widgets/chat_tab_view.dart`
- `frontend/lib/features/alerts/data/datasources/alerts_remote.dart`
- `frontend/lib/features/alerts/data/dto/alert_dto.dart`
- `frontend/lib/features/alerts/data/repositories/alerts_repo_impl.dart`
- `frontend/lib/features/alerts/presentation/providers/alerts_provider.dart`
- `frontend/test/features/map/zone_mapper_test.dart`
