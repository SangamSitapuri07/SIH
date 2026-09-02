# Running the ORCA Flutter app

## Prereqs (one-time)

1. **Install Flutter SDK** — https://docs.flutter.dev/get-started/install
   (stable channel, version 3.22 or newer).
2. **Verify install** — `flutter doctor` should show green checks.
3. **Get a device or emulator**:
   - Android: enable USB debugging on your phone + install Android SDK
     (Android Studio installs both)
   - iOS: macOS only, with Xcode installed
   - Or: any Chrome browser works (`flutter run -d chrome`)

## Steps

```bash
# 1. Clone the repo (if you haven't)
git clone https://github.com/SangamSitapuri07/SIH.git
cd SIH
git checkout wwith

# 2. Start the backend (in a separate terminal)
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# 3. Run the Flutter app
cd ../app
flutter pub get
flutter run
```

## Configuring the backend URL

The default URL is `http://10.0.2.2:8000` which is the **Android emulator's**
alias for the host machine. If you run on a physical phone, edit
`lib/main.dart` and change to your laptop's LAN IP, e.g.:

```dart
const baseUrl = 'http://192.168.1.42:8000';
```

For Chrome (`flutter run -d chrome`) the default `localhost:8000` works.

## What you'll see

1. Empty state with a sailing icon and quick-prompt chips at the top
2. Type "Where is the nearest PFZ today?" or tap a chip
3. The agent steps stream in one by one (planner → weather → ocean → GIS → reasoner)
4. Final response card with the answer, a safety score pill, and an inline OpenStreetMap showing the PFZ polygon
5. Tap "Expand" on the map to see it full-screen with pan/zoom
6. Switch languages via the globe icon in the app bar

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `flutter: Connection refused` | Backend not running, or wrong URL in `main.dart` |
| `Map tiles don't load` | Phone has no internet, or you're using a corporate firewall |
| `flutter doctor` complains about Android SDK | Install Android Studio + accept licences: `flutter doctor --android-licenses` |
| `Could not resolve all packages` | `flutter clean && flutter pub get` |
