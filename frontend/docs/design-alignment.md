# ORCA — reference alignment and data-provenance review

This document records how each shipped screen was checked against the ORCA
reference workspace (screenshots + its published design tokens) and states,
per screen, where every marine value actually comes from. It is a review aid,
not a specification of new behaviour.

The reference was used **only** as a visual and interaction reference. No code,
image, icon, fixture, credential or dataset was copied from it. Every marine
value in this app comes from the ORCA FastAPI backend or from an explicit
unavailable / cached / stale / forecast state.

## 1. Design tokens now shared with the reference

`lib/core/theme/orca_theme.dart` is the single source of truth. Values below are
the ones transcribed from the reference stylesheet.

| Area | Reference value | Where it lands |
| --- | --- | --- |
| Canvas | `#f2f8f9` | `OrcaTheme.background`, `Scaffold` backgrounds |
| Sidebar / top bar | `#f8fcfc` | `OrcaSidebar`, `OrcaAppBar` |
| Structural hairlines | `#d9e9eb` (shell), `#e4eff0` (dividers) | `shellBorder`, `divider` |
| Card | `#fff`, border `#dcebed`, radius 16, `0 8px 26px rgba(29,89,105,.045)` | `OrcaCard` |
| Ink | `#12354a` headings, `#68828c` body, `#20495a` card headings | `textPrimary`, `textSecondary`, `headingSoft` |
| Accent | `#20b4b1` bar, `#d9f3f2` active fill, `#149ea0` eyebrow | `accent`, `accentSoft`, `accentDark` |
| Status pills | live `#e2f8f3/#147a65`, cached `#e9f2f7/#427288`, stale `#fff2d8/#9a6316`, unavailable `#f2e9ea/#914b52` | `OrcaStateChip` |
| Severity | high `#fde5e2/#c2453b`, medium `#fff1d7/#b77817`, low `#e2f4f3/#168b8c` | alert + result fills |
| Verdict panel | `linear-gradient(140deg,#123c52,#14536a 72%,#167180)`, padding 28, ring top-right | `OrcaHeroPanel` |
| Buttons | primary `#153e53`/white, outline border `#cfe2e5`, radius 9, padding 10/14 | `OrcaPillButton` |
| Layout | sidebar 248 (208 ≤1020), top bar 79, content column 1380 with 27/34/46 padding, radius 16/13 | `OrcaTheme` layout constants |
| Breakpoints | ≤1020 single column, ≤740 mobile (67 px bottom bar) | `compactBreakpoint`, `mobileBreakpoint` |
| Verdict type | 68 px / `-0.09em` (60 px compact) | `OrcaType.heroVerdict(Compact)` |

**Documented deviation:** the reference typesets in *Manrope* / *DM Mono*. Those
fonts ship in this environment only as `woff2`, which Flutter cannot bundle, so
the ramp keeps **Inter** (`kOrcaSans`) at the reference sizes, weights and
letter-spacing. Substituting a TTF for `kOrcaSans` is a one-line change.

## 2. Screen-by-screen

For each screen: what matches the reference, and what each value's provenance is.

### Command Center / Overview (`features/advisory`, `features/command_center`)

Matches the reference hierarchy: eyebrow `MORNING BRIEF · <date>` → large
greeting heading → one-line summary → `Ask ORCA` / `Plan a trip` actions on the
same row, then the decision panel, then conditions, then signals.

- Verdict word and confidence — backend `/api/v1/advisory` only. The client
  never computes or invents a verdict; when the backend omits it the panel shows
  `Unavailable`.
- Condition cards — one tile per variable the backend actually returned, each
  with its own state chip and provenance line (source, observed time, validity).
- Signals — sourced from real advisory risk factors; an empty list renders the
  reference empty state, not placeholder rows.
- Map preview — real tile provider; if the grid call has not answered the base
  chart stays and the overlay is labelled unavailable.
- Agent/service status — real `/api/v1/agents` statuses. `LIVE` appears only
  when the SSE channel is genuinely connected.

**States:** fresh = live; repeat fetch within TTL = `Cached`; validity elapsed =
`Stale`; provider down = `Source unavailable`; no network = `Offline`.

### Marine Map (`features/map`)

Matches the reference map workspace: large base map (radius 16, `#d8efef`
canvas, `#c7e0e2` frame) plus a right-hand inspector column, layer pills and a
legend, collapsing to a bottom sheet on phones.

- Tiles: the real provider configured in the app, with correct OpenStreetMap
  attribution rendered on the map.
- Layers: a layer can only be switched on when `/api/v1/layers` reports it
  available; unavailable products are listed with their backend status instead
  of drawing an empty or invented overlay.
- Wind: drawn from real `u`/`v` vector grid data only.
- Timeline: each timestamp selects the forecast valid time that matches it; if
  no forecast is supplied there is no timeline.
- Inspector: real selected-feature values plus provenance. Probing outside a
  responded grid yields `Source unavailable`.

**No** fake islands, PFZ polygons, vessel tracks, regulated boundaries or demo
markers exist anywhere in this code path.

### Advisory (`features/advisory`)

Decision + evidence, risk factors, validity window, provenance, and the
cached/stale banner. Numbers come only from `/api/v1/advisory`; the safe-window
strip is hidden when the backend returns no window rather than filled with a
plausible one.

### Route Safety (`features/navigate`)

Two-column desktop planner matching the reference route grid. Coordinates come
from the user's input, the working location, or saved locations — never
prefilled. The result block uses the reference `route safety result` styling and
shows only what `/api/v1/route-check` + `/api/v1/route-advisory` returned.

Land clearance is `UNVERIFIED` whenever the land-mask provider is unavailable
(which is its normal state here), and **no detour is ever drawn** because the
client is not allowed to invent one. Empty state: "Enter your trip details to
see a route safety answer."

### Alerts (`features/alerts`)

Priority filters as reference pills, concise feed rows with a severity rail
mirroring the reference fills, source and timestamp on every row, and unread
state tracked device-locally (never assumed from the server).

`/api/v1/alerts` returns 503 when no official feed answered, and the screen says
**unavailable** rather than "no alerts". Severity is never upgraded client-side;
IMD items that carry `UNSPECIFIED` stay neutral.

### Ask ORCA / Agent Network (`features/agents`)

Conversation workspace plus a transparent status/reasoning panel, matching the
reference assistant layout (chat column + 310 px panel, reference bubbles and
numbered reason steps).

The panel separates three things explicitly: the **deterministic backend
result**, the **source evidence** it used, and the **optional LLM explanation**
(which is labelled as such and fails safely — a failed LLM pass never removes or
alters the deterministic answer). Agent names and statuses are read from
`/api/v1/agents`; nothing is invented, and a run that fell back to the
deterministic engine says so.

### Data Sources / System Health (`features/settings`)

Real provider health from `/api/v1/health`: per-provider status
(`UNVERIFIED` / `CONFIGURED` / `CREDENTIAL_REQUIRED` / `UNAVAILABLE` / `FRESH` /
`CACHED` / `UNREACHABLE` / `FAILED`), cache freshness, availability, latest
update and recovery actions.

### Profile / Settings (`features/auth`, `features/settings`)

Localisation (en / hi / te) and the settings architecture are retained; the
server URL, language and health surfaces keep working as before.

## 3. How this was verified, and what was not

Verified in this environment:

- `tool/orca_static_check.py` (shipped in this folder) reports `issues: 0`:
  bracket balance, missing/broken imports, unknown class members and duplicate
  declarations across all 134 Dart files.
- Every relative and `package:orca_app/...` import resolves to a real file.
- Every `OrcaTheme.*` / `OrcaType.*` / `OrcaUi` member referenced anywhere in
  `lib/` or `test/` exists in the declaring file.
- `OrcaType` has no duplicate or orphaned declarations.
- No `SourceCatalog` references remain; the deleted network test stays deleted.
- Standing repairs re-checked: 45 s Dio timeouts, SSE `receiveTimeout:
  Duration.zero`, no `CrossAxisAlignment.stretch` outside an `IntrinsicHeight`,
  `home_screen.dart` desktop row not stretched.

**Not verified:** no Flutter/Dart SDK is reachable from this environment, so the
project was **not** compiled, analysed, formatted, tested or rendered. Screen
comparison is against the reference screenshots and the transcribed tokens, not
against a running ORCA build.
