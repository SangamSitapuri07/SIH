# ORCA Android — Native App Plan (locked 2026-09-08)

**Decisions (user-locked):** native rewrite · all native extras (direct SMS,
background GPS, geofence notifications, haptics) · Hindi default UI ·
backend connectivity approach decided later (LAN first for dev).

Deadline: 20 Sept submission (~12 days). This plan is built to ship a
working APK in ~6-7 days with explicit risk gates.

---

## 0. Stack: React Native (Expo dev-client), NOT Flutter

- Team's codebase (Next.js/TS) is JS/TS — zero new language (Flutter =
  Dart + everything new).
- Three.js already runs in the web app; native RN rewrite of the 3D ocean
  is out-of-scope for this timeline → see §5.
- Expo dev-client build = real APK on the laptop; Expo Go for instant
  on-phone iteration over WiFi (QR scan).
- Native modules we need (SMS send, background location, MapLibre) require
  `expo prebuild` + a dev-build APK (NOT bare Expo Go) — planned for in
  the schedule (first dev build on Day 4).

## 1. Architecture (what "native" honestly means)

```
┌────────────────────────── ORCA Android (RN/Expo) ──────────────────────┐
│ Home(verdict) · Map(MapLibre-native) · Navigate · SOS · Info           │
│   ▲ data via HTTPS/LAN JSON                                            │
│   │ 3D Ocean = WebView embed of the EXISTING web page (§5)             │
└───────────────┬────────────────────────────────────────────────────────┘
                │ (same contract as the web app today)
        FastAPI :8000 (laptop)  →  NOAA/MOSDAC/Open-Meteo/GFW/INCOIS…
```

- "Native" = the **client**. The data brain stays the existing FastAPI
  pipeline (rebuilding that on-device is absurd and also un-honest:
  MOSDAC/GFW credentials live server-side).
- Phone ↔ laptop: dev = `http://<laptop-LAN-IP>:8000`. Demo-day option:
  laptop hotspot OR cloudflared tunnel (final decision deferred).

## 2. Screens & fisher-first UX (Hindi default)

Design tokens (shared with web for brand feel):
`bg #070D1A · surface #0A1120 · line #1C2A45 · cyan #22d3ee · emerald #34d399 · amber #f59e0b · red #ef4444 · text #DBE4F3`
Buttons min 48dp, text min 15sp base (sunlight-readable), verdict 22sp+.
Every screen: status strip (📡 online/offline · 🛰️ GPS accuracy · data time).

### Tab 1 — 🏠 मुखपृष्ठ (Home)
```
┌────────────────────────────────────────┐
│ ORCA  📡on  🛰️±21m        ⚙️          │
│ ┌────────────────────────────────────┐ │
│ │  आज समुद्र में जाना                  │ │
│ │  ▓▓▓▓▓▓▓▓▓▓░░░░░░░░ THEEK है        │ │ ← 3-colour verdict
│ │  लहरें 1.2m · हवा 12kn · SST 28°    │ │
│ │  (data: 2 मिनट पुराना, NOAA+MOSDAC) │ │
│ └────────────────────────────────────┘ │
│ [📍 मेरी जगह]  [🗺️ जगह चुनो]            │
│ ┌─ लहरें ─┐ ┌─ हवा ──┐ ┌─ पानी ──┐      │ ← tap = 48h chart
│ └────────┘ └────────┘ └────────┘      │
│ 6-source chips (green/amber/red)      │
└────────────────────────────────────────┘
```

### Tab 2 — 🗺️ नक्शा (Map explorer)
- MapLibre native map, OSM raster tiles (+ OpenSeaMap toggle).
- Real grid dots + hotspot markers (same /field payload as web).
- Long-press any dot → bottom-card with values + plain-language verdicts.
- Hotspot list = bottom sheet; each row has 🧭 "जाओ".
- "3D" button → §5 WebView sheet.

### Tab 3 — 🧭 Navigate
```
┌────────────────────────────────────────┐
│ 🎯 20.63°N 70.71°E · 2.19 mg/m³       │
│ ┌───────────┬───────────┬────────────┐ │
│ │ दूरी      │ दिशा       │ ETA        │ │ ← 32sp numbers
│ │ 42.1 NM   │ 048° NE   │ 3h 20m     │ │
│ ├───────────┼───────────┼────────────┤ │
│ │ रफ़्तार    │ course से │ 👆 ↱25°बाएं│ │
│ │ 12.4 kn   │ 0.2 NM ✓  │            │ │
│ └───────────┴───────────┴────────────┘ │
│ 🛟 सीधा रास्ता पूरा पानी (GLOBE ✓)     │
│ [⏺ Trace ON]   [⚓ समुद्री निशान]       │
└────────────────────────────────────────┘
```
- Geofence: 0.3 NM → local notification + long vibration (screen off OK,
  background location ON with battery honesty note).
- Keep-awake; "dhoop mode" = yellow-on-black + Android brightness boost.

### Tab 4 — 🆘 SOS (always red, every tab bar)
- Giant position, Coast Guard **1554** one-tap, contact call/SMS
  (**direct send** via react-native-sms — Android-only dev build; see
  §6.permissions), nearest-3 of 71 bundled harbours + ETAs, VHF 16 note.
- Works with zero network; opens from any tab in ≤1 tap.

### Tab 5 — ℹ️ जानकारी
Live source-health table, honesty notes (masked/cloud days), how-to-read
guide, "ye app data kab invent nahi karta" charter, credits/version ⎇.

## 3. Offline strategy (native)

- GPS: works with zero internet (same physics as web).
- Map tiles: MapLibre **offline packs** (download Gujarat coast z8-13 =
  honest pre-load step before sailing; size ~40-80 MB, user-initiated).
- Harbours/SOS: bundled in APK (already land-mask verified list).
- API: never cached-as-fresh; offline = last-known values WITH timestamp
  + red offline strip. (Same rule as web — non-negotiable.)

## 4. Data contracts (zero new backend work)

- `GET /api/v1/advisory?lat&lon` → verdict card + trends
- `GET /api/v1/field?lat&lon` → grid + hotspots(+caveat) + charts
- `GET /api/v1/route-check?…` → course legality
- `GET /api/v1/health` → build ⎇ + source chips
- All already CORS-open for the web app; phone hits same endpoints.

## 5. 3D Ocean on native — pragmatic embed (first), native GL (maybe never)

- RN + Three.js via `expo-gl` is real but a multi-day perf/compat fight.
- Decision: 3D tab opens a full-screen **WebView** of the existing
  Next.js 3D view (served from laptop). Same real data, same animation,
  zero rewrite. Timebox: if `expo-gl` proves smooth in a 2-hour spike on
  Day 7, upgrade; else ship WebView proudly with the honest note "3D
  engine humari web pipeline pe chalta hai (device GL se)".

## 6. Native extras (user locked: ALL)

| Extra | Plugin | Honest caveats we ship |
|---|---|---|
| Direct SMS send | `react-native-sms` (dev build) | Google Play sideload fine; Play-Store listing of SMS-permission apps = extra review (demo APK unaffected) |
| Background GPS trace | `expo-location` + `expo-task-manager` | persistent notification + battery note; never hidden |
| Geofence arrival | `expo-location` geofencing | only while nav active; shown as "ORCA hotspot watch" |
| Notifications | `expo-notifications` | local only (no server push) |
| Haptics | `expo-haptics` | verdict change, turn hint, arrival |
| Sunlight boost | `expo-brightness` | "dhoop mode" only, restores after |

## 7. Risk register + gates

| Risk | Mitigation |
|---|---|
| 12-day timeline slips | **Gate Day-4:** verdict+map flow on phone? no → freeze to Capacitor-wrap plan (1-day APK from existing web) |
| WebGL 3D weak on old phones | WebView embed is the plan; native GL only if spike wins |
| SMS permission Play policy | demo APK sideload; Play listing is post-hackathon |
| MapLibre offline pack bugs | test Day 6 morning; fallback = tiles cache-as-you-look (auto) |
| Phone can't reach laptop on demo day | laptop hotspot preset; cloudflared tunnel dry-run Day 9 |

## 8. Day-by-day

- **D1**: plan (this doc) + scaffold (`orca-mobile/`) + theme/i18n + tabs
  skeleton + API client. Laptop: install Android Studio + SDK + JDK17.
- **D2**: Home verdict screen live from FastAPI + 48h charts.
- **D3**: Map explorer (MapLibre, grid dots, hotspot sheet, long-press card).
- **D4**: first dev APK (prebuild) + SMS direct send in SOS + GATE CHECK.
- **D5**: Navigate HUD + trace + geofence arrival + haptics.
- **D6**: offline packs + dhoop mode + polish; demo rehearsal.
- **D7**: 3D WebView sheet (+2h expo-gl spike) + store listing notes; freeze D8-12.

Safety net (unchanged): the web app stays demo-able all along.
