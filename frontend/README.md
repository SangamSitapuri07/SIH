# ORCA — Flutter client

Marine decision-support client for the ORCA backend (`../backend`). Flutter +
Riverpod + go_router + flutter_map, with a Hive cache, offline outbox,
connectivity watcher and an SSE live channel.

Every marine value shown comes from the FastAPI backend or from an explicit
unavailable / cached / stale / forecast state. There are no bundled fixtures and
no fallback dataset — see `docs/design-alignment.md` for the screen-by-screen
provenance review.

## Run it

The app needs the backend running for any real data. Without it the UI is
expected to render its honest "unavailable" states, not placeholder values.

**Terminal 1 — backend**

```powershell
cd ..\backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8000
```

Check <http://127.0.0.1:8000/api/v1/health> returns JSON before starting the app.

**Terminal 2 — app**

```powershell
cd frontend
flutter pub get
flutter gen-l10n                 # regenerates lib/l10n/app_localizations*.dart
flutter run -d chrome            # or: -d windows, or a device id from flutter devices
```

The client defaults to `http://127.0.0.1:8000`. The Android emulator uses
`10.0.2.2:8000` automatically; for a physical device set your machine's LAN
address in **Profile → server settings**.

## Check it

```powershell
python tool\orca_static_check.py   # no Flutter needed: structure, imports, members
flutter analyze
flutter test
dart format --output=none --set-exit-if-changed lib test
```

`tool/orca_static_check.py` catches the mistakes that are cheap to catch from
source text (unbalanced brackets, missing or broken imports, references to class
members that do not exist, duplicate declarations). It is not a substitute for
`flutter analyze`.

`analysis_options.yaml` treats `missing_required_param` and `missing_return` as
errors and enables `strict-casts`, `strict-inference` and `strict-raw-types`, so
the analyzer is stricter here than in a default Flutter project.

## What to expect with no providers configured

| Surface | State |
| --- | --- |
| Verdict, conditions, signals | `Unavailable` — the deterministic verdict is the backend's, never the client's |
| Map base layer | Renders: real tiles with OpenStreetMap attribution |
| Map overlays | Only layers `/api/v1/layers` reports available; otherwise listed as unavailable |
| Alerts | `unavailable`, not "no alerts" — `/api/v1/alerts` answers 503 with no official feed |
| Route safety | `UNVERIFIED` — the land mask is unavailable, and the client never draws a detour |
| Stream chip | `LIVE` only when the SSE channel is genuinely connected |

## Localisation

English, Hindi and Telugu. Strings live in `lib/l10n/app_*.arb`; run
`flutter gen-l10n` after editing them. `l10n_untranslated.json` lists any
remaining gaps.
