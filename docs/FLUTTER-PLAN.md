# ORCA — Android App Plan (FLUTTER)

> **Status: ACTIVE PLAN** (2026-09-08). Ye document `docs/ANDROID-PLAN.md` (React Native/Expo) ko **supersede** karta hai.
> Decision change ka reason: user ne Flutter choose kiya — development easy, single codebase, UI polish fast, aur Play Store ke bina bhi direct APK install possible.
> Backend (`FastAPI`) mein **zero change** — app wahi real endpoints use karegi. Real data only, koi dummy nahi.

---

> **Phone UX pillar #1: "har cheez 1-2 button ke andar" — fisherman ke liye app, IT professional ke liye nahi. Har core kaam (verdict, map, nav, SOS, language/mode/zoom switch) 1 seedha tap; har secondary kaam max 2 taps. Teeno access pillars (§2A languages · §2B modes/zoom) isi rule ke hote hain.**

## 1. Locked decisions

| # | Sawaal | Faisla | Note |
|---|--------|--------|------|
| 1 | Stack | **Flutter (stable) + Dart** | Native APK. Android Studio full IDE zaroori nahi — sirf **Android SDK (cmdline tools) + JDK 17** chahiye build ke liye |
| 2 | UI language | **MULTI-LANGUAGE**: हिन्दी + English + **saari coastal boli** (§2A table) — **saari 11 language files Day 1 se COMPLETE (koi placeholder nahi)**. Default = हिन्दी, first-launch pe picker | Flutter `easy_localization` + per-language JSON files; har string key se, koi hardcoded text nahi |
| 2b | Accessibility | **3 display modes — Light (WHITE/teal, DEFAULT = original reference theme · user-locked) + Dark + Dhoop · Zoom in/out (font scale 0.85×–1.75×) · In-app translator (ML Kit, offline)** | §2B — fishermen ki age/eyesight/dhoop sab ke liye |
| 3 | Native extras | **SAB**: direct SMS, background GPS, geofence notifications, haptics | Sab Flutter packages se possible (table §3) |
| 4 | Connectivity (samundar mein net nahi) | **Phase baad mein** decide — abhi offline SOS panel + cached advisory kaafi | Physics wahi hai (docs/OFFLINE.md) |
| 5 | Backend | Same laptop `FastAPI :8000` | App mein base-URL editor (Info tab) — LAN IP daal ke phone se connect |
| 6 | 3D globe | **WebView** mein web app ka Ocean3D (phase 2); native 3D nahi banana | `webview_flutter` package |
| 7 | UI design | **User reference images aayenge** → unke hisaab se exact design. Tab tak theme tokens (§4) locked | Tokens pehle se final hain, sirf layout reference se tune hoga |

---

## 2A. Languages — saari coastal boli (i18n by design)

India ki coastline = **9 states + 4 coastal UTs** → sirf Hindi se fishermen cover nahi honge. App **Day 1 se multi-language** banegi (baad mein retrofit karna = har screen phir se chhoona — avoid).

| # | Language | Coast (state/UT) | Fisheries context |
|---|----------|------------------|-------------------|
| 1 | **हिन्दी** (default) | pan-India + A&N Islands | sabse zyada lingua-franca |
| 2 | **English** | pan-India (official) | technical terms yahi rehte hain |
| 3 | **ગુજરાતી** (Gujarati) | Gujarat — **longest coast (~1600 km)**, largest fishing fleet | ₹ priority #1 (Veraval/Porbandar/Diu belt = humara primary demo zone bhi) |
| 4 | **ଓଡ଼ିଆ** (Odia) | Odisha (Paradip–Puri belt) | high artisanal fishing |
| 5 | **বাংলা** (Bengali) | West Bengal + A&N settlers | Sundarban/Digha belt |
| 6 | **தமிழ்** (Tamil) | Tamil Nadu + Puducherry + Karaikal | huge mechanised + kattumaram fleet |
| 7 | **తెలుగు** (Telugu) | Andhra Pradesh — **longest east coast** | Kakinada/Visakha belt |
| 8 | **മലയാളം** (Malayalam) | Kerala + Lakshadweep | densest small-scale fisheries |
| 9 | **ಕನ್ನಡ** (Kannada) | Karnataka | Mangaluru–Karwar belt |
| 10 | **मराठी** (Marathi) | Maharashtra | Mumbai–Ratnagiri koli community |
| 11 | **કોંકણી / Konkani** | Goa | small coast, vie for completeness |

**Implementation rules (honest + practical):**
- Flutter `easy_localization` + `assets/i18n/<lang>.json` — **har UI string key-based**; code mein koi hardcoded text nahi. New language add karna = ek JSON file, zero code change.
- **Numbers hamesha standard digits** (0-9) — regional digit systems (૧૨૩ / ୧୨୩) confuse karte hain boat pe; units English hi (`kn`, `m`, `°C`, `NM`).
- Tech/data terms (verdict, hotspot, chlorophyll, GPS, SOS) — **translate + bracket mein English**, warna "तरंग-ऊँचाई" jaisi force-fit translations mushkil ho jaati hain. Pattern: `लहरें 1.2 m` (shabd simple, unit English).
- Scripts: Devanagari/Gujarati/Odia/Bengali/Tamil/Telugu/Malayalam/Kannada sab **Noto Fonts family** se render hoti hain — Android ke system fonts kaafi, koi bundling nahi (APK lean).
- **Language picker**: first-launch pe full-screen bhasha chuno (flag nahi — language apne script mein likhi, jaise `தமிழ்`, `ગુજરાતી`); baad mein **StatusStrip ke 🌐 icon se 1-tap popup** (जानकारी tab mein bhi same list); `shared_preferences` mein persist.
- **SOS SMS body** bhi selected language mein + lat/lon numbers universal — coast guard ko English digits milte hain.
- **Koi placeholder approach NAHI** — 11 ke 11 JSON files **Day 1 mein poore likhe jaayenge** (har key × har bhasha filled). String count deliberately chhoti rakhenge (~120-150 keys) taaki quality > quantity: filler text nahi, sirf wo strings jo UI mein sach mein dikhti hain.
- Translation source: hum (AI-generated, native-grammar rules follow karte hue) + Info tab mein honest note: "अनुवाद AI-assisted — गलती मिले तो report karein" + feedback button.
- **Web app (Next.js) ke liye same i18n dictionary reuse** hogi (Phase 2 mein web bhi multilingual — hackathon ke liye app-first).

---

## 2B. Accessibility & Display modes (user-locked: sab Day-1 features)

Fishermen ka mix: umar 18-60+, dhoop mein screen, chhoti-dikhai aankhein, gloves/gile haath. To ye "extra" nahi — **core** hai:

| Feature | Detail | Implementation |
|---------|--------|----------------|
| **☀️ Light mode** (DEFAULT — user-locked) | **Original reference theme**: pure white bg + teal `#14B8A6` accents, simple flat cards | Flutter `ThemeMode` + persisted |
| **🌙 Dark mode** | Raat/early-morning sailing — slate `#0F172A` + same teal accents | Same token system ka dark twin |
| **🔆 Dhoop mode** | Yellow-on-black ultra contrast (already locked) — deck pe direct sunlight | **1 tap**: toggle har screen ke StatusStrip mein (sun→moon→dhoop icon cycle — default WHITE/light) + volume-down long-press shortcut (gile haath friendly) |
| **🔍 Zoom in/out** | **Text scale 0.85× → 1.75×** (7 steps) — A- / A+ buttons har screen ke corner mein; verdict/HUD jaise critical numbers hamesha relative scale honge | `MediaQuery.textScaler` app-wide + own scale factor in `shared_preferences`; map pe bhi +/− zoom buttons bade (pinch fail ho toh bhi chale) |
| **🌐 In-app translator** | कोई bhi advisory/verdict/caveat text → user ki chosen language mein translate. **On-device = OFFLINE chalega samundar mein** (net ka wait nahi) | `google_mlkit_translation` (real ML models, ~30MB per language pair, WiFi pe ek-baar download; Info tab mein manage/delete models) |
| **📢 Bade tap targets** | Min 48dp buttons, min 15sp base text (already locked) — test bhi rakhenge | Layout lint + golden tests |

**Honesty notes (Info tab mein saaf likha hoga):**
- Translator = ML model, 100% perfect nahi hota — critical safety info (SOS) ke saath **hamesha numbers standard digits + English fallback** rahega.
- Light mode mein bhi red/green verdict semantics same rehte hain (color-blind safe: text + icon bhi, sirf colour nahi).
- Zoom scale har screen pe test hoga: 1.75× pe koi text clip nahi honi chahiye (overflow = bug).

---

## 2. App structure — 5 tabs (wireframe)

Bottom navigation bar, dark theme, bade touch targets (fisherman-friendly, haath gile bhi hon to chale):

```
┌─────────────────────────────────────┐
│  मुखपृष्ठ   नक्शा   नेविगेट   SOS   जानकारी │
│   (home)   (map)   (nav)  (sos)  (info)  │
└─────────────────────────────────────┘
```

| Tab | Kya dikhega (sab REAL, backend/live se) |
|-----|------------------------------------------|
| **मुखपृष्ठ** | Jagah picker (GPS / manual pin) → **verdict card** (28sp bold: "समझदार Bhavnagar जा सकते हो" / "NAHI — leher 3.2m"), quick tiles: leher (m), hawaa (kn), gust, SST, advisory-48h ka **fl_chart** line chart (leher + hawaa), data-freshness chip ("NOAA chl · 2h purana") |
| **नक्शा** | **flutter_map** + OSM tiles + OpenSeaMap seamark overlay toggle; hotspot markers (chl mg/m³ + caveat badge for coastal bloom), live grid dots (met cells, land-masked), long-press → uss point ka mini-card, GPS blue-dot + accuracy circle |
| **नेविगेट** | Meri GPS position → hotspot/chunk pe "🧭 जाओ" → `/api/v1/route-check` se verified course-line (cyan=SEA-ONLY, red=BLOCKED, amber=NOT verified); HUD: NM distance, course °, speed kn, ETA, off-course >0.5NM warning, steering hint (↱ 25° दाएं); trip breadcrumb trace (orange polyline, 20m jitter filter, 3000pt cap) |
| **SOS** | Zero-network panel: bada GPS readout, **Coast Guard 1554** (tel:), saved contact ko `tel:` + **direct SMS** (app ke andar se hi — telephony package, body: lat/lon/acc/time/speed), nearest 3 of 71 verified harbours (Dart mein compiled-in, koi fetch nahi) |
| **जानकारी** | Backend health + commit hash (⎇), base-URL editor, honesty charter (kya real hai / kya pending / failed fetch ke ASLI reasons), units legend, dhoop-mode toggle |

---

## 3. Flutter packages (sab pub.dev se)

| Kaam | Package | Kyun |
|------|---------|------|
| HTTP calls | `http` (ya `dio`) | FastAPI JSON endpoints |
| Map | `flutter_map` + OSM/OpenSeaMap tiles | Free, lightweight, offline-tile possible; MapLibre native (`maplibre_gl`) baad mein agar vector chahiye |
| Charts | `fl_chart` | 48h leher/hawaa line charts — smooth aur customizable |
| GPS | `geolocator` | position stream, accuracy, heading, speed |
| Background GPS / geofence | `geolocator` + **foreground service** (`flutter_foreground_task`) | App minimize pe bhi trace + geofence alerts |
| Direct SMS | `telephony` | SMS app khole bina seedha send (SOS ke liye critical) |
| Local notifications | `flutter_local_notifications` | Geofence enter/exit alerts |
| Haptics | `HapticFeedback` (built-in) + `vibration` | Verdict/arrival buzz |
| Local storage | `shared_preferences` + path_provider files | Offline packs (advisory/field JSON cache), SOS contact, trip trace persist |
| Net status | `connectivity_plus` | StatusStrip red banner "नेटवक nahi — offline mode" |
| WebView (3D, phase 2) | `webview_flutter` | Ocean3D globe as-is reuse |
| Screen wake (nav tab) | `wakelock_plus` | Navigation pe screen on rakhe |
| **On-device translator** | `google_mlkit_translation` | OFFLINE translation (samundar mein net nahi) — models WiFi pe ek-baar download, user manage karega |
| **i18n engine** | `easy_localization` | 11 complete JSON files, first-launch picker, runtime switch |

> Sab packages **Android-only constraints** respect karte hain (permissions `AndroidManifest.xml` mein: `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `SEND_SMS`, `FOREGROUND_SERVICE`, `POST_NOTIFICATIONS`, `INTERNET`, `VIBRATE`, `WAKE_LOCK`).

---

## 4. Theme tokens — **🌿 ORIGINAL REFERENCE THEME = FINAL** (user-locked 2026-09-08; saffron experiment SCRAPPED)

User ka final word: **"jo sabse pehle share kiya tha wahi CSS/color — simple UI, white bg, teal-green."** Palette Figma screenshots se seedha pick:

**Light (DEFAULT — ye hi app ka base look hai):**

| Token | Value | Kahan |
|-------|-------|-------|
| bg | `#FFFFFF` pure white | scaffold |
| card | `#FFFFFF` + hairline `#E5EAF0` + soft shadow | cards, sheets, chat bubbles |
| surface-alt | `#F3F6F9` | input bar, legends, inactive chips |
| **primary (teal-green)** | `#14B8A6` | filled chips, buttons, active tab, send icon, verdict ring |
| primary-deep | `#0D9488` | hero card gradient start (`#0D9488 → #14B8A6`), links |
| ok (GO green) | `#22C55E` | "Good"/healthy verdict, legends |
| warn (amber) | `#F59E0B` | algal-bloom alert card (`#FFF7EA` bg), caution |
| danger | `#EF4444` | risk/SOS |
| text | `#1F2937` | body |
| text-2 | `#6B7280` | subtitles, timestamps |
| hero card | teal gradient + white text + translucent chips (`#FFFFFF26` fill) | Home "Ecosystem health" style |
| alert card | amber tint `#FFF7EA` bg + `#F59E0B` icon | bottom-sheet alerts |
| mint avatar/chip | `#CCFBF1` bg + `#0F766E` text | "RS" avatar, agent-pills |

**Dark (raat mode — optional toggle):** bg `#0F172A`, card `#1E293B`, same teal `#14B8A6` accents, text `#E5EAF0`. (Structure same, sirf tokens swap.)

**Dhoop mode:** yellow `#FFE600` on pure black — fixed, palette-independent.

> Design rule: **simple flat cards, rounded 16-20, soft shadows, generous whitespace** — reference screenshots jaisa. Heavy gradients/glows NAHI (hero card ka soft teal gradient chhodkar — wo reference mein hai). AI-generated dark-blue + saffron experiment dono retired.

---

## 5. Backend contracts (SAME — koi change nahi)

| Endpoint | App use |
|----------|---------|
| `GET /health` | Info tab + StatusStrip (uptime, commit ⎇) |
| `GET /api/v1/advisory?lat=&lon=` | Home verdict + 48h series (leher/hawaa/SST + asli fetch status/reasons) |
| `GET /api/v1/field?lat=&lon=` | Map grid, hotspot cards (chl, caveat, land-masked cells, `land` flags) |
| `GET /api/v1/route-check?from_lat=&from_lon=&to_lat=&to_lon=` | Navigate course-line verification (GLOBE land-mask) |

Offline packs = inhi endpoints ka last-good JSON phone mein cache + 71 harbours compiled-in + land-mask honesty note.

---

## 6. Laptop setup (user side — ek baar)

1. **Flutter SDK** (stable) install + `flutter doctor`
2. **Android SDK cmdline tools + Platform-Tools + API 34** (Android Studio full IDE optional — sirf SDK chahiye)
3. **JDK 17**
4. Phone mein **USB debugging** on, USB se connect
5. `flutter create`-level scaffold hum repo mein bana denge; user side commands:
   ```powershell
   cd orca_flutter        # naya folder (orca-mobile RN wala reference ke liye rehta hai)
   flutter pub get
   flutter run            # phone pe install hota dev build
   flutter build apk --debug   # share karne layak APK
   ```
6. Info tab → backend LAN IP (`ipconfig` → IPv4, jaise `http://192.168.1.5:8000`) daalo

---

## 7. Schedule (D-day = 20 Sept freeze)

| Din | Kaam | Gate |
|-----|------|------|
| **D1** ✅ DONE (2026-09-08) | `orca_flutter/` scaffold: bottom-nav 5 tabs, theme (**light-white default + dark + dhoop**), api client, StatusStrip (net + mode/lang/zoom 1-tap), Info backend editor + live health check, **i18n engine + first-launch picker + 11/11 COMPLETE JSONs (44 keys each)** + **textScaler zoom 0.85–1.75× live** | Laptop pe `flutter run` verify pending (user) |
| **D2** | Home: verdict card + quick tiles + fl_chart 48h charts + jagah picker (GPS/manual) | Real advisory se numbers match (web se cross-check) |
| **D3** | नक्शा: flutter_map + hotspot markers + grid + long-press card + OpenSeaMap toggle | Tiles load, GLOBE-verified hotspots |
| **D4** | नेविगेट: GPS watch + route-check + HUD + **direct SMS (telephony)** + haptics | **GATE CHECK**: `flutter run` smooth + SMS phone se seedha gaya. Slip → extras D6/D7 pe, core pehle freeze |
| **D5** | Geofence (foreground service) + local notifications + trip trace persist | App minimize pe bhi breadcrumb + alert |
| **D6** | Offline packs (last-good JSON cache) + SOS polish + **translator model downloads manage UI** + dhoop/light/dark teeno modes ka final QA | Airplane mode test: SOS panel + cached advisory + translator (offline model) sab chale |
| **D7** | 3D WebView (Ocean3D) + **saari 11 language JSONs complete + proofread** + UI reference ke hisaab se final polish + **freeze** + release-shape APK | Har language mein 5 screens walkthrough; Judges demo checklist |

---

## 8. Honesty charter (app mein Info tab — judges ko bhi dikhta hai)

- Har data point ke saath **source + freshness** chip.
- Failed fetch pe **asli reason** (jaise "MOSDAC link crawling · background mein finish ho raha").
- Route-check: mask down → "NOT verified" (amber) — kabhi fake safe line nahi.
- Coastal hotspot pe turbidity caveat (INCOIS PFZ cross-check bolke).
- Land-mask: GLOBE 1km mask se land pixels drop — counter dikhata hai kitne masked hue.

---

## 9. Open items (user se)

1. ~~UI reference images~~ ✅ MIL GAYI (7 screens, user-approved). Design LOCKED — Figma ab band, gaps bhi hum code mein hi fix karenge (§10).
2. Laptop pe Flutter install confirm karo (§6) — D1 scaffold tabhi run kar paoge.
3. ~~Old `orca-mobile/` (RN scaffold)~~ — DELETED 2026-09-08 (user: "nayi file, purane mein mat milao"). Git history mein preserved. Mobile ka ek hi ghar ab: `orca_flutter/`.

---

## 10. Design gaps — USER-LOCKED ki hum KHUD Flutter mein implement karenge (no Figma)

Reference design (7 screens) ~90% complete hai. Ye 7 cheezein usme missing/partial thi — **coding ke time MANDATORY**, koi skip nahi (user ne explicitly bola hai):

| # | Gap (design mein nahi tha) | Kahan implement hoga | Day |
|---|---------------------------|----------------------|-----|
| 1 | **SOS "No Signal" card — VHF Channel 16** proper row (radio icon + "VHF Ch 16 par madad maango" + whistle/strobe + raft/battery tips, teeno ke English subtitles) | SOS screen | D6 |
| 2 | **Navigate ke 3 state variants**: (a) route BLOCKED red pill "रास्ता ज़मीन से होकर जाता है — दूसरा मार्ग दिखाया गया" + rerouted cyan line + dashed-red original; (b) off-course amber banner "रास्ते से 0.8 NM दूर — ↰ 40° बाएं मुड़ो"; (c) arrival green banner "पहुंच गए! hotspot 0.2 NM — मछली शुभ हो 🐟" | Navigate screen states | D4–D5 |
| 3 | **Language picker — 11/11 rows** visible (scrollable), reference design mein cut ho gayi thi | First-launch picker | D1 |
| 4 | **Home pe "📍 मेरी जगह" GPS chip** greeting ke neeche (lat/lon + ±accuracy + refresh) | Home | D2 |
| 5 | **Info mein "❤ ईमानदारी Charter" card** — 4 bullets (kabhi data invent nahi · har number ke saath source+time · failed fetch ka asli reason · route GREEN sirf verified) — **judges ke liye USP** | Info | D6 |
| 6 | **Dhoop mode preview** har critical screen pe QA (Home verdict, Navigate HUD, SOS) | D7 polish |
| 7 | Bottom nav ka **SOS tab har screen pe RED** (kuch designs mein inconsistent tha) | Global nav component | D1 |

> In sabka design "taste" reference screens se inherit hoga (dark #070D1A, teal #14B8A6, radius 16, same typography) — naya visual invent nahi karenge, consistency rahegi.
