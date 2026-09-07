# ORCA — Complete UI Design Prompt

> Copy the section below the line into any AI design tool (v0, Figma AI, Lovable, Cursor, or a human designer brief). It is fully self-contained.

---

# UI DESIGN BRIEF — "ORCA: Marine EcOsystem Reasoning with Collaborative Agents"

## 1. Product Context (read first)

ORCA is a **marine intelligence platform for Indian fishermen** built for Smart India Hackathon 2026 (ISRO problem statement). A fisherman opens the app, taps a point on the sea map OR asks a question in his own language ("Kal subah machli ke liye jaa sakte hain?"), and a team of **9 AI agents** fuses live data from ISRO's MOSDAC (OCM-3 satellite), NOAA, Copernicus OC-CCI, Open-Meteo, INCOIS and Global Fishing Watch into a single GO / CAUTION / NO-GO verdict with full reasoning transparency.

**Design north star:** trust. Every number is real and live, every failed data source is honestly shown, every recommendation explains *why*. The UI must feel like a **professional vessel bridge console** — calm, dense, legible at a glance in bright sunlight on a rocking boat (also used on laptops by judges).

**Core users:**
1. **Fisherman** (primary): low digital literacy, uses phone, needs Instagram-simple: big verdict, big text, native language (Hindi/English toggle).
2. **Judges/researchers** (secondary): desktop, want to inspect agent reasoning, data provenance, latencies.

**Absolute design rules (never break):**
- **R1 — No fake data anywhere.** Status chips, latencies, freshness times must come from real API state. If a source is down, show it DOWN.
- **R2 — Verdict readability in 1 second.** GO = green, CAUTION = amber, NO-GO = red. Never use color alone — always pair with icon + text.
- **R3 — Honesty is a feature.** "3 sources unreachable" is shown proudly with reasons, not hidden.
- **R4 — Bilingual.** Every label has a Hindi (hi) + English version. Layout must not break with longer Hindi strings.
- **R5 — Map stays a real map.** The interactive map (react-leaflet + OpenStreetMap tiles) is NOT replaced by illustrations or gradients.
- **R6 — Mobile-first for the fisherman, desktop-rich for judges.**

## 2. Visual Identity

**Personality:** serious ocean-tech. Think "Vercel dashboard meets naval chart plotter". NOT a consumer app, NOT playful, NOT purple-gradient AI slop.

**Logo/brand mark:** a simple geometric whale/wave glyph (three parallel wave lines), one weight, monochrome cyan. Wordmark: **ORCA** in bold tracking-tight uppercase, sub-label "Marine Intelligence" in regular weight cyan-300/80.

**Mood keywords:** deep-sea, console, glass, precise, trustworthy, calm.

## 3. Design Tokens

### Colors (dark theme only — single theme, done perfectly)

| Token | Hex | Usage |
|---|---|---|
| `--bg` | `#070D1A` | app background |
| `--bg-elevated` | `#0B1322` | headers, rail, top bars |
| `--panel` | `#0E1729` | cards, chat bubbles, tiles |
| `--panel-2` | `#131E35` | hover states, inner cards, inputs-filled |
| `--border` | `#1C2A45` | default borders (1px) |
| `--border-soft` | `#16233C` | page-level separators |
| `--text` | `#DBE4F3` | primary text |
| `--text-dim` | `#7D8DB0` | secondary text, labels |
| `--text-faint` | `#4D5D80` | placeholders, captions |
| `--accent` | `#22D3EE` (cyan-400) | links, active states, focus rings, live indicators |
| `--accent-dim` | `#0E7490` | accent fills at low opacity |

**Semantic (from ORCA logic — never recolor arbitrarily):**
- GO/safe: emerald `#34D399` (10% opacity bg + 25% border + 300 text)
- CAUTION: amber `#FBBF24`
- NO-GO/danger: red `#EF4444`, with subtle outer glow `box-shadow: 0 0 20px #EF444425` on critical alerts only
- Info: slate
- Simulated/demo alert badge: violet `#A78BFA` (explicitly different = honesty)

All semantic colors are used as: **10% bg + 25–40% border + 300-level text** (the "ghost badge" pattern). Vivid solid fills are reserved for exactly ONE element per screen (the verdict banner).

### Typography

- Font: **Geist Sans** (Vercel) for UI, **Geist Mono** for: lat/long, timestamps, knots, latencies, cache keys, source names.
- Scale: 10 (chip text) / 11 (caption+uppercase labels, tracking-wider) / 12 (secondary) / 14 (body) / 17 (card titles) / 24–32 (verdict & key numbers only).
- Weights: 400 body, 500 labels, 600 section heads, 700–800 verdicts only.
- Rule: numbers that matter (wave height, wind) are ALWAYS ≥ 20px bold. A fisherman squints in sunlight.

### Spacing & shape

- 4px grid. Card padding 16px. Section gaps 16px. Dense but breathable.
- Radius: 10px cards, 12px buttons/rail icons, 9999px chips & pills. Verdict banner: 12px.
- Borders: always 1px `--border`; surfaces never float on pure black — always on `--bg` with border.
- Shadows: almost none in-console; use borders for separation. Only floating map overlays get real shadows.

### Iconography

- Line icons, stroke 1.8px, `currentColor`, 18–20px (Lucide/Feather style). Custom set: waves (brand), map, chat, shield (advisory), bell (alerts), settings, satellite, anchor, check, send, refresh, activity, globe.
- **NO emojis as UI icons.** Emojis allowed only inside *data content* itself (e.g. the ⛈️ inside a weather finding message coming from the API).

### Motion

- Micro only: 150ms color/background transitions; 300ms fade-up (6px) for panels; `chip-dot` 2.2s pulse on LIVE indicators; skeleton shimmer while agents run.
- No bounces, no spring physics, no parallax. It's a console, not a toy.

## 4. App Shell (every screen sits inside this)

Desktop frame (≥768px), three parts:

**A. Left icon rail (64px wide, `--bg-elevated`, right border `--border-soft`):**
- Top: brand glyph in a 36px rounded tile (cyan gradient tint + 30% cyan border).
- 5 nav buttons stacked, 48px each: icon 19px + 9px label under it. Tabs: **Map, Ask, Advisory, Alerts, Settings**.
- Active state: 10% cyan bg, cyan icon, plus a 3px-wide cyan accent bar on the button's left edge. Inactive: `--text-faint`, hover to `--text-dim`.
- Bottom: vertical-rotated "SIH 2026 · PS 176" in 8px tracking-widest `--text-faint`.

**B. Top header (56px, `--bg-elevated`, bottom border `--border-soft`):**
- Left: ORCA wordmark + "Marine Intelligence" + tagline (truncate, hidden < md).
- Right: **live source chips** (see components §5.4) — max 4 visible on mobile, all on lg.

**C. Alert ticker (conditional, 28px):** only when a live warning exists; red 10% bg, red 25% bottom border, pulsing "ALERT:" prefix, single-line ellipsis: `title · valid till HH:MM UTC`. Multiple alerts joined by `·`.

Mobile (<768px): rail collapses to a bottom tab bar, header keeps brand + 2 chips, all tab contents go full-width single column.

## 5. Screen-by-screen spec

### 5.1 MAP tab (home) — "tap the sea, get the truth"

Layout: `grid 2fr / 1fr` (map left, insight panel right).

**Map (left):** real interactive map (react-leaflet, dark CartoDB tiles if available else styled OSM). On top of it (z-index safe):
- Coastal zone markers (small cyan pins) + tapped-point crosshair with lat/long readout.
- Floating zone card (bottom-left, `surface-2` + backdrop-blur): zone name (semibold white) + "click anywhere to analyze" hint.
- Layer toggles (top-right, vertical stack of small ghost buttons): SST / Chlorophyll / Wind / Vessels.
- **Do NOT draw fake ocean data layers.** Overlays must be real data-driven; if a layer has no data, the toggle shows a greyed "no data" state.

**InsightPanel (right, `--bg-elevated`, left border):** vertical scroll, in order:
1. **Zone header**: name (17px bold), mono sub-line `19.56°, 78.99° · 2026-09-07`.
2. **OVERALL RISK card**: ghost semantic bg by level (low/moderate/high/critical = green/amber/orange/red), 11px uppercase label "OVERALL RISK", 24px extra-bold level, plus coverage line `5/8 variables known · 2 sources down` when limited.
3. **RECOMMENDATION card** (`--panel`): 11px cyan uppercase label, 14px medium text — the one line a fisherman must read.
4. **SUMMARY card** (slightly darker panel): pre-line body text dim.
5. **DATA SOURCES**: flex-wrap chips — used sources = green ghost chips with ✓; below, a collapsed `<details>` block "⚠️ N failed sources" (red ghost) listing each failure with the real reason after the colon.
6. **AGENT REASONING (9)**: list of collapsible rows. Each row: emoji-free agent icon + name, right-aligned risk badge; expanded = summary + findings list, each finding prefixed `[severity]` in mono with severity-colored text. Agents with no data sink to bottom at 60% opacity with a "no data" badge.
7. Footer: `fetched: <localtime>` in faint 11px.

**Loading state:** pulsing cyan "⏳" line + hint that first analysis takes ~30s (agents are running), then skeleton cards.

### 5.2 ASK tab — conversational console

Layout: header strip (title + hint) over scrollable messages over input bar.

- **Empty state:** centered brand glyph 40px + one-line explanation that every answer is built from live data with agents shown.
- **User bubble:** right-aligned, solid cyan-700, white text, radius 16px with flat bottom-right corner.
- **ORCA bubble:** left-aligned `--panel` + border, radius 16px flat bottom-left, max-width 95%.
  - Top: row of **agent-step chips** (small pills, `--panel-2` bg, mono 10px) — one per agent that ran, e.g. "weather agent ✓ 200ms".
  - Body: pre-wrapped answer text.
  - If it produced a verdict: inline verdict chip (solid green/amber/red, icon + text) + headline in dim text.
  - If answered via HTTP fallback (websocket blocked): 10px faint note "answered via HTTP (same agents, trace replayed)" — honesty again.
- **While running:** a live bubble showing agent chips appearing one-by-one with pulse, then streaming tokens with `▌` cursor.
- **Input bar:** on `--bg-elevated`, top border; above it a row of quick-prompt pill buttons (`--panel-2`, hover to border-bright); input = filled `--bg` with `--border` → cyan on focus; send button = solid cyan-600.
- Language: user may type Hindi (Devanagari) or Hinglish in Roman — placeholder: "Apna sawaal likhiye… / Ask in Hindi or English…".

### 5.3 ADVISORY tab — the verdict screen (most important)

Purpose: 3-second safety decision. Hierarchy, top→bottom:

1. **Verdict banner** (the ONE vivid element): full-width, solid verdict color (green-600/amber-500/red-600), white text, radius 12px, 4px ring of same hue at 30%. Inside: 32px extrabold verdict word + icon ("✓ GO", "⚠ CAUTION", "⛔ NO-GO" / Hindi labels), headline sentence under it, refresh button on the right (white/20 bg ghost), meta line: `for Veraval (20.90°N, 70.37°E) · valid till 14:05 UTC`.
2. **Variable tile grid** (2 cols mobile → 4 cols desktop): tiles `--panel` + border, 10px uppercase dim label, 20px bold value, 11px sub-line. Tiles: Waves (now + 48h peak + swell), Wind (now + gusts + 48h peak), SST, Current (+direction), Chlorophyll (+PFZ date), Nearest PFZ (NM + bearing), Cyclone (km or "✓ clear"). **Warn rule:** any tile crossing its threshold gets amber border + amber value + faint amber glow.
3. **Safe window card:** clock icon + "Best window" + mono `09-07 04:30 → 09-07 10:00 UTC` in cyan + green hour-count chip; or honest "no safe window in next 48h (reason)".
4. **Reasons card:** list of bullet rows — icon by severity (⛔ no_go red / ⚠️ caution amber / ℹ️ info slate) + 14px dim text. **Every reason must quote real numbers** (e.g. "WMO 95 thunderstorm, 95% rain chance at 06 UTC").
5. **Sources footer card:** dim 12px: `Sources: Open-Meteo · MOSDAC OCM-3 · NOAA …`, `Failed: OC-CCI (cloud-masked)`, italic disclaimer, cyclone note. This footer is non-negotiable — the transparency IS the product.

### 5.4 ALERTS tab — proactive hazard watch

- Header row: title + two buttons: **Evaluate here** (solid cyan) and **Simulate drill** (violet-700 — visually separated because it creates a DEMO alert).
- Sub-note in dim 12px explaining alerts auto-refresh every 60s.
- **Alert card** (click to expand): `--panel`, border colored by severity (red-500/50 warning, amber-500/40 watch; warning gets faint red outer glow). Inside: severity emoji-dot + title (semibold white), meta line `code · issued · valid till · source` in mono dim, right side severity pill (solid) + violet SIMULATED badge if drill. Expanded shows full message pre-wrap.
- **Empty state:** green ghost card, big ✓, "No active alerts for your zone — seas are calm."

**Ticker rule:** any `warning`-severity alert also appears in global header ticker (§4C).

### 5.5 SETTINGS tab — control & trust

Single column, max-width 672px, stacked `surface` sections:
1. **Language**: two pill toggle buttons (हिंदी / English), active = solid cyan.
2. **Home port**: dark select listing all coastal zones with lat/long.
3. **GFW data toggle**: checkbox + explanation; auto-state text varies ("auto-detected token" vs "needs GFW_API_TOKEN").
4. **System status** (the trust dashboard): server status + version (green/red), GFW token ✓/✗, WebSocket liveness, and the **backend source list** — each source mono-name + its real status string from `/health`; expandable cache list with freshness minutes.
5. **Feedback**: textarea + 👍/👎 buttons, note that feedback saves server-side.
6. **Disclaimer**: small print — ORCA is decision support; final call is the skipper's; cross-check INCOIS/IMD bulletin.

### 5.6 Component: Source chips (global)

- Pill, 11px medium, ghost style: LIVE = emerald (10% bg, 25% border, 300 text + **pulsing 1.5px dot**), SETUP-DEGRADED = amber, DOWN (whole backend) = red chip "backend down".
- Tooltip (`title` attr) carries the FULL real status string from `/api/v1/health` (e.g. "incois_las: server unreliable — fallback only").
- Order fixed: MOSDAC, NOAA, OC-CCI, Open-Meteo, GFW, INCOIS PFZ, INCOIS, JTWC. Mobile shows first 2–4.
- Refresh cadence: 60s silent poll. Never optimistic — mapping is literally `status.includes("live")`.

### 5.7 Global states

- **Backend unreachable**: full-tab centered state — plug glyph, one-line reason, cyan retry button. Never a blank screen, never a infinite spinner past 30s.
- **504 / slow first analysis**: friendly card "Slow network — agents still computing; click the same point again in 10–30s, it will be instant from cache" (bilingual).
- **Partial data**: never block the whole screen; per-agent "no data" badges + coverage line.

## 6. Accessibility & robustness

- Contrast: all text ≥ 4.5:1 on its surface (palette chosen to satisfy this; verify).
- Verdict states always icon+text+color (R2). Never rely on red/green alone.
- Focus-visible: 2px cyan outline on all interactive elements.
- `prefers-reduced-motion`: disable pulse/shimmer.
- Inputs `min-height` 40px, tap targets ≥ 40px.
- RTL not required; Devanagari must render correctly (test label: "सावधानी — तूफ़ानी हवाएँ").

## 7. Tech constraints (for implementation-accurate designs)

- Stack: **Next.js 14 (App Router) + React 18 + Tailwind CSS + react-leaflet**, FastAPI backend at :8000 (proxied via `/api/v1/*`), WebSocket `/ws/chat` with HTTP fallback.
- Fonts are local WOFF files (`GeistVF.woff`, `GeistMonoVF.woff`) via `@font-face` — no Google Fonts CDN (judges' venue may have flakey wifi; app must look identical offline).
- Dark theme only (no light mode in v1).
- No UI kit dependency beyond Tailwind; all components hand-built from §5 specs.
- Every piece of dynamic text comes from `/api/v1/*` responses shown in the field dictionary below — a mock design should use these EXACT shapes:

```
Insight  { zone{lat,lon,date}, overall_risk, recommendation, summary,
           agents[{agent,risk_level,summary,findings[{severity,msg}]}],
           data_sources_used[], data_sources_failed[], fetched_at }
Advisory { verdict: go|caution|no_go, icon, headline_en, headline_hi,
           variables{wave_height_m, swell_m, wind_kts, gust_kts, sst_c,
                     current_kn, current_dir, chlorophyll_mg_m3,
                     nearest_pfz_nm, nearest_pfz_bearing, cyclone_dist_km},
           safe_window{found,from_utc,to_utc,hours}, reasons[{severity,msg}],
           sources[], sources_failed[], disclaimer, valid_until }
Alert    { id, code, severity: warning|watch, title_en/hi, msg_en,
           issued_at, valid_until, source, simulated }
Health   { status, version, credentials{...}, data_sources{name:status}, cache }
Chat     (websocket events: chat.routing / chat.agent_step / chat.token / chat.final)
```

## 8. Do / Don't

**DO:** breathe data; mono numerals for coordinates; honest empty states; let the ONE verdict banner own all the saturation on screen; keep density.
**DON'T:** purple/pink gradients; glassmorphism overload (blur only on floating map cards); emoji icons; fake "AI thinking" theatrics; skeletons that last >30s without messaging; hiding failures; auto-playing anything; light-on-dark text below #7D8DB0 for meaningful content.

## 9. Acceptance checklist (a design is DONE when)

- [ ] Verdict readable in 1 second at arm's length on a phone
- [ ] Every screen shows data provenance somewhere visible
- [ ] Failed sources visible with real reasons, not red-error panic
- [ ] 9-agent reasoning visible without any click for the current answer
- [ ] Hindi labels fit without truncation on 360px width
- [ ] No mock/placeholder numbers in any design artifact
- [ ] Shell (rail + header + ticker) identical across all 5 tabs
