# ORCA — Figma AI Prompt Set (v1, 2026-09-08)

> Use: Figma → First Draft / AI generator. Generate ONE screen at a time on an **iPhone frame 393×852**. First paste the **MASTER STYLE PROMPT** so every screen shares the same design system, then each screen prompt. Replace nothing — these prompts already encode our locked decisions (Flutter plan, 5 tabs, 11 languages, 3 display modes, zoom, honesty-first).

---

## 0. MASTER STYLE PROMPT (paste first / keep as design system)

```
Design system for "ORCA" — a marine ecosystem + fisherman-safety Android app
for Indian coastal fishermen (Smart India Hackathon, ISRO problem statement).

STYLE: clean, calm, card-based mobile UI like a modern weather+maps app.
Rounded cards (radius 16-20), soft shadows, generous whitespace, big readable
typography. This is for fishermen aged 18-60, used on a moving boat in glare
and rain — HUGE touch targets (min 48dp), no tiny text (min 15sp body),
numbers extra large and bold.

COLORS (dark theme is DEFAULT):
- Background deep-navy #070D1A, card surface #0F1830, hairline #1C2A45
- Primary ocean-teal #14B8A6, cyan accent #22D3EE
- Success/GO green #34D399, warning amber #F59E0B, danger red #EF4444
- Text primary #E6EEF9, secondary #8FA3C0
Also show a LIGHT-MODE variant of every screen: background #F4F7FB,
cards pure white, text #0B1526, same accent colors.

SEMANTIC COLOR SYSTEM (never change meaning):
green = safe/GO, amber = caution/watch, red = danger/NO-GO/SOS.
Verdicts must pair color + icon + word (color-blind safe).

TYPOGRAPHY: rounded geometric sans (like Nunito/Poppins). Hindi Devanagari
script must render correctly — labels are primarily in Hindi with small
English subtitles. Example headline: "समुद्र में जाना" with verdict
"THEEK है" / "NAHI" / "ध्यान से".

BOTTOM NAV (5 tabs, icons + labels in Hindi):
1. मुखपृष्ठ (Home) 2. नक्शा (Map) 3. नेविगेट (Navigate/compass)
4. SOS — always RED and slightly larger 5. जानकारी (Info)

GLOBAL ELEMENTS on every screen:
- Top status strip: 📡 network (online green / offline red), 🛰️ GPS
  accuracy chip like "±21 m", language icon 🌐, display-mode icon
  (moon/sun cycle), zoom A-/A+ buttons.
- Honesty chips: small pills showing data source + freshness, e.g.
  "NOAA chl · 2h purana", "Open-Meteo · abhi".
- Offline banner state: full-width red bar "नेटवर्क नहीं — offline mode,
  last saved data dikha rahe hain".
```

---

## 1. HOME (मुखपृष्ठ) — verdict-first

```
Design the Home screen of ORCA for fishermen. Top: greeting "सुप्रभात",
app name ORCA, notification bell with 2 alerts, avatar "RS".

HERO VERDICT CARD (full width, tallest card, gradient ocean-teal):
- Question row: "आज समुद्र में जाना" (18sp)
- GIANT verdict (32sp bold) with icon: "THEEK है ✅" in green
  (show alternate states as separate frames: amber "ध्यान से ⚠️",
  red "NAHI जाएं ❌ — लहरें 3.2 m")
- Subline: "लहरें 1.2 m · हवा 12 kn · SST 28.2 °C" (units in English)
- Honesty strip inside card: tiny pills "Open-Meteo · abhi",
  "NOAA chl · 2h", "GLOBE ✓"
- Below: "6 डेटा स्रोतों से reasoning" + 6 tiny source chips:
  Satellite / Water / Wind / Land-mask / Fusion / Advisory
  (each with green dot = ok, amber = stale, red = failed)

TILE ROW (2x3 grid of small metric cards):
- लहरें 1.2 m (green) · हवा 12 kn · Gust 22 kn · SST 28.2 °C ·
  Current 0.8 kn · Visibility — each with tiny 48h sparkline.

CARD "मछली-क्षेत्र (hotspots)": top 3 rows like
"#1 20.63°N 70.71°E · chl 2.19 mg/m³ · 42 NM NE" with small 🧭 button.
One row shows amber badge "coastal bloom — turbidity caveat".

CARD "Agent alerts" with "See all": two alert rows —
1) ⚠️ amber icon "संभावित algal bloom, Zone C — Satellite + Water data
   dono agree, high confidence" > chevron
2) 🐟 "नया hotspot cluster मिला — Veraval से 51 NM NNW" > chevron

CARD "48 घंटे का पूर्वानुमान": line chart (waves m + wind kn, two lines,
green/cyan) with time axis aaj/kal/parso, tap hint "chart pe dabao =
detail".
```

## 2. MAP (नक्शा) — live ocean explorer

```
Design the Map screen. Full-bleed ocean map (light blue-grey sea,
pale green/white landmass — Indian west coast, Gulf of Khambhat).

TOP: rounded search bar "zone, hotspot ya buoy khojo…" + avatar.
Filter chips row below: [सभी layers] active teal pill, [पानी की गुणवत्ता],
[मछली-क्षेत्र], [Jokhim], [बोये/sensors].

LEGEND CARD (top-left, white, small): red dot Jokhim zone (risk),
green dot Surakshit (safe), blue dot sensor buoy, fish icon hotspot.

MAP CONTENT: scattered circular markers — green ring markers (safe zones
Zone A, Zone B labels), blue ring buoys "WQ-04", red pulsing marker with
soft red halo "Zone C — algal bloom risk", fish icons on 3 hotspot points
with tiny chl values. Grid dots layer (small teal dots = live data cells).
Right side: big + / − zoom buttons and a ⌖ my-location FAB (GPS).

BOTTOM SHEET (persistent, rounded top): pink/amber tinted alert card —
"⚠️ Zone C — algal bloom jokhim · tap karke detail dekho" with chevron.
Second state of the sheet: hotspot detail card — coordinates, chl value,
distance/bearing "42 NM NE", caveat amber strip "coastal bloom: satellite
chl mislead kar sakta hai — INCOIS PFZ se cross-check karo", and a big
teal button "🧭 यहां जाओ (Navigate)".

Show OPENSTREETMAP-style tile texture, grid lines subtle. Also a toggle
chip for "समुद्री निशान (seamarks)" overlay.
```

## 3. NAVIGATE (नेविगेट) — marine GPS HUD

```
Design the Navigate screen — a marine chartplotter HUD for a fisherman
steering to a fish hotspot. Dark map background with a CYAN course line
from user's boat (blue dot, accuracy circle) to target (fish icon),
thin grey breadcrumb trail behind the boat.

TOP TARGET CARD: "🎯 20.63°N 70.71°E · chl 2.19 mg/m³" + Close ✕.

BIG HUD GRID (2 rows x 3 cols, numbers 32sp bold cyan):
- दूरी 42.1 NM · दिशा 048° NE · ETA 3h 20m
- रफ्तार 12.4 kn · भटकाव 0.2 NM ✓ · steering hint "↱ 25° बाएं घुड़ो" (amber)

SAFETY STRIP below HUD: green pill "✅ सीधा रास्ता पूरा पानी में
(GLOBE verified)" — alternate frame with red pill "❌ रास्ता ज़मीन से
होकर जाता है — reroute dikhao", and amber pill "⚠️ रास्ता verify
नहीं हुआ (mask सर्वर down)".

BUTTONS: [⏺ Trace ON] green outline, [⚓ समुद्री निशान] outline,
[Bahut bada red button: 🆘 SOS].

Off-course state frame: top red banner "रास्ते से 0.8 NM दूर —
↰ 40° बाएं मुड़ो" with haptic icon. Arrival state frame: confetti-free,
simple green banner "पहुंच गए! hotspot 0.2 NM — मछली शुभ हो 🐟".
Sunlight: show a "dhoop mode" frame — pure black background, yellow #FFE600
numbers, ultra-bold.
```

## 4. SOS (🆘) — zero-network emergency

```
Design the SOS screen — works with NO internet, for actual distress at sea.
Background darker red-tinted. Everything HUGE.

TOP: red banner "⚠️ Emergency — ye screen bina network ke kaam karti hai".
GIANT position card (black): your coordinates "20°54.3'N 70°22.1'E"
mono-space 28sp, "±18 m · abhi abhi · GPS satellites se" + refresh icon.

BUTTON STACK (full width, 64dp each):
1) SOLID RED: "📞 Coast Guard — 1554 को call करो" (biggest)
2) Dark card: "👤 Raju bhai को call"  3) Dark card: "💬 SMS भेजो —
   location ke saath" (sub: "app seedha SMS karega, network aate hi")

CARD "सबसे नज़दीक bands (harbour)": 3 rows — name, "12.4 NM NE",
"~1h 15m @ 10kn", small phone icon. e.g. Veraval / Porbandar / Mangrol.

CARD "agar koi signal nahi": VHF Channel 16 note, whistle/light signals,
text "raft mein raho, battery bachao" — calm iconography.

Offline: top strip shows red "नेटवर्क नहीं" — everything above still
rendered. Hindi labels with small English subtitles.
```

## 5. ASK ORCA (जानकारी/AI) — transparent reasoning chat

```
Design the "Ask ORCA" chat screen. Header: whale icon, "ORCA se poochho",
chip "6 agents active", avatar RS. Full chat: user bubble (teal) asks
"Zone C aaj kyon flag hua?"

AI ANSWER CARD (white): plain-language Hindi answer with keywords teal:
"Zone C mein possible algal bloom hai — satellite imagery aur buoy ke
nitrate levels dono se pata chala. Chlorophyll-a baseline se 2.3x zyada
hai. Hawa bloom ko coast ki taraf dhakel rahi hai."

REASONING TRACE CARD (this is our honesty USP — design it proudly):
title "REASONING TRACE", rows with colored dots:
🔴 Satellite agent — "chl anomaly detect hui" · 92% confidence
🟠 Water-quality agent — "nitrate spike, buoy WQ-04" · 88% confidence
🟢 Fusion agent — "dono signals cross-check kiye" · 95% confidence
(also a FAILED state row style: grey dot, "MOSDAC agent — link slow tha,
retry 10 min mein" — honest failure, never hidden)

QUICK-ACTION CHIPS row: [Zone officer ko batao] [Trend dikhao]
[Nakshe pe dekho] — teal outline pills.

INPUT BAR: rounded field "ORCA se kuch bhi poochho…" + mic icon +
teal send button. Suggested prompts above input:
"aaj machli kahan milegi?" / "lage hawa kab badhegi?"

Do NOT add unread counters or social features — this is a tool, not social.
```

## 6. INFO (जानकारी) — settings + honesty charter

```
Design the Info/Settings screen, scrolling list of rounded cards:

CARD "भाषा (Language)": grid of language pills each written in its own
script — हिन्दी (selected, teal fill) English, ગુજરાતી, ଓଡ଼ିଆ, বাংলা,
தமிழ், తెలుగు, മലയാളം, ಕನ್ನಡ, मराठी, કોંકણી.

CARD "Display": 3 segmented buttons — 🌙 Dark (active) / ☀️ Light /
🔆 Dhoop (sun mode) + text-size slider row "A- ——— A+" with live preview
sentence "लहरें 1.2 m".

CARD "Translator (offline)": "ML Kit on-device translation — samundar
mein bina network chalega" + downloaded model rows "हिन्दी ↔ ગુજરાતી ✓
32 MB" with delete icons + download button.

CARD "Backend connection": field with laptop IP "http://192.168.1.5:8000",
green dot "connected · commit ⎇ e6b3e0b", refresh button.

CARD "Data sources — live health": 6 rows (NOAA chlorophyll, ISRO MOSDAC
OCM-3, Open-Meteo marine, GLOBE land-mask, GFW, INCOIS PFZ) each with
status dot + last-updated + one-line honest status e.g. "MOSDAC —
download slow (98 KB/s), background mein poora ho raha".

CARD "Honesty charter" (heart icon): bullet list — "ye app kabhi data
invent nahi karta · har number ke saath source + time · failed fetch ka
asli reason dikhta hai · route sirf tab GREEN jab poora paani verified ho".
Version footer "ORCA v0.1 · SIH 2026 · Team — ISRO PS 26176".
```

## 7. First-launch LANGUAGE PICKER

```
Design a first-launch language selection screen — no flags (language ≠
country). Centered whale logo + "ORCA" + tagline "samundar, aapki bhasha
mein". Below: a clean vertical list of 11 large rounded buttons, each
language written in its OWN script (58dp rows): हिन्दी / English /
ગુજરાતી / ଓଡ଼ିଆ / বাংলা / தமிழ் / తెలుగు / മലയാളം / ಕನ್ನಡ / मराठी /
કોંકણી. Selected = teal fill with white text + check. Bottom sticky teal
button "आगे बढ़ें →". Soft ocean gradient background, gentle wave
illustration at bottom.
```

---

## Figma AI pro-tips (read before generating)
1. Generate screens one-by-one; re-paste MASTER STYLE with each prompt.
2. Ask for **both dark + light variants**: "duplicate this frame in light mode".
3. The reference screenshots user has (light theme teal/white) = good baseline — upload them to Figma as reference AND paste prompts, output will stay consistent.
4. Hindi text may get garbled by AI — tell it: "keep Devanagari labels exactly as written, do not translate".
5. Export assets at 2x for handoff; we implement in Flutter (not auto-export code).

---

# ~~GAP-FIX ROUND (v1.1)~~ — CANCELLED: user ne Figma band kar diya (final design mil gayi).
# Ye gaps ab FLUTTER-PLAN.md §10 mein locked hain — coding ke time khud implement karenge.
# (Prompts neeche history ke liye rakhe hain; use karne ki zaroorat NAHI.)

## G1. Navigate states (3 frames, same screen 393x852, dark theme)

```
Create 3 state variants of the Navigate HUD screen, same layout as the main
one, dark navy theme #070D1A, teal accents:
FRAME A "Route blocked": safety pill turns SOLID RED #EF4444 with text
"! रास्ता ज़मीन से होकर जाता है — दूसरा मार्ग दिखाया गया" and map shows
re-routed cyan line curving around a landmass, original line dashed red.
FRAME B "Off-course": full-width amber banner #F59E0B at top "रास्ते से
0.8 NM दूर — ↰ 40° बाएं मुड़ो", boat icon away from cyan line, orange
breadcrumb trail diverging.
FRAME C "Arrival": green banner #34D399 "पहुंच गए! hotspot 0.2 NM —
मछली शुभ हो", big circular [समाप्त करो] outline button target marker
pulsing green.
Keep Devanagari text exactly as written.
```

## G2. SOS no-signal card — corrected VHF line

```
Redesign only the "No Signal" info card on the SOS screen, dark theme:
title "अगर कोई signal नहीं". Bullet rows with small icons:
1. radio icon — "VHF Channel 16 पर मदद मांगो (emergency radio)"
2. whistle icon — "सीटी बजाओ / टॉर्च चमकाओ (strobe signals)"
3. raft icon — "साथ में रहो, battery बचाओ"
Text in Hindi exactly as given, small English subtitle under each.
Card background very dark red tint, white text, rounded 16.
```

## G3. First-launch language picker — FULL 11 rows

```
Regenerate the first-launch language picker with ALL 11 rows visible
(scrollable list), dark navy #070D1A, each row 52dp, language names in
their own script: हिन्दी (selected, teal #14B8A6 fill + white check),
English, ગુજરાતી, ଓଡ଼ିଆ, বাংলা, தமிழ், తెలుగు, മലയാളം, ಕನ್ನಡ, मराठी,
કોંકણી. Sticky bottom teal button "आगे बढ़ें (Continue) →".
Whale logo + "ORCA" + tagline "समुद्र — आपकी भाषा में" on top.
```

## G4. Home GPS chip + Info honesty card (2 small frames)

```
FRAME A: Home screen top area only — add a pill chip right under the
greeting row, dark card with green pulsing dot icon: "📍 मेरी जगह:
20°54'N 70°22'E · ±21 m" and small refresh icon.
FRAME B: Info screen new card titled "❤ ईमानदारी Charter (Honesty)" —
4 rows each with small icon: shield "ye app kabhi data invent नहीं करता",
clock "har number ke saath source + time", alert-triangle "failed fetch
ka असली reason दिखता है", map-pin "route GREEN sirf jab poora पानी
verified ho". Dark theme #0F1830 card, teal icons, white text.
```
