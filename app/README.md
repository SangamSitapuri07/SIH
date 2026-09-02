# ORCA Flutter App

Mobile client for the ORCA Marine Intelligence Platform.

## What it does

- **Chat screen** — type a marine question in English, Hindi, or Tamil
- **Live map** — see PFZ zones, geofences, your location, all on OpenStreetMap
- **Real-time agent steps** — watch the planner → weather → ocean → GIS → risk → reasoner fire one by one
- **Reasoning trace** — every response shows *why* the answer is what it is
- **Safety score** — color-coded 0..1 with the verdict
- **Alerts** — geofence warnings and unsafe-conditions notices at the top

## How to run

```bash
flutter pub get
flutter run
```

You need Flutter SDK on your machine and either:
- An Android phone with USB debugging enabled, or
- An iPhone with Xcode, or
- An Android emulator

For quick testing without a phone, the app also runs in Chrome (`flutter run -d chrome`).

## Project structure

```
app/
├── pubspec.yaml           # dependencies (flutter_map, http, etc.)
├── lib/
│   ├── main.dart          # entry point, theme
│   ├── api/
│   │   ├── orca_client.dart   # REST + SSE client for the backend
│   │   └── models.dart        # data classes matching the backend
│   ├── screens/
│   │   ├── chat_screen.dart   # main screen
│   │   └── map_screen.dart    # OpenStreetMap view
│   ├── widgets/
│   │   ├── agent_trace.dart   # shows the streaming reasoning
│   │   ├── response_card.dart # one agent-step card
│   │   └── alert_banner.dart  # safety / geofence warnings
│   └── theme.dart         # Material 3 theme
├── android/               # Android build config (auto-generated)
├── ios/                   # iOS build config (auto-generated)
└── test/                  # widget tests
```

## Configuration

The app expects the backend at `http://10.0.2.2:8000` by default (Android emulator's host alias). For a physical phone, change the URL in `lib/api/orca_client.dart` to your laptop's LAN IP, e.g. `http://192.168.1.10:8000`.
