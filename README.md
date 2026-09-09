# ORCA — Marine Intelligence Frontends

> **SIH 2026 · Problem Statement 176 (SIH26176)**
> **Marine EcOsystem Reasoning with Collaborative Agents**
> Organization: **ISRO · Department of Space** · Theme: Disaster Management

ORCA turns **only real, live ocean data** (12 sources — satellites, weather
models, fishing-fleet activity) into explainable decisions for India's
fishermen, in **11 languages**, with total honesty: *a source that fails says
so, with its real reason. Nothing is ever invented.*

> 🔧 **Backend moved:** the FastAPI data engine now lives in the sister repo
> **[SangamSitapuri07/ORCA-backend](https://github.com/SangamSitapuri07/ORCA-backend)**
> (`backend/` + `pipeline/` + tests + run docs). This repo holds the frontends.

## 📱 orca_flutter/ — the fishermen-first Android app

- **6 tabs:** Home (AI verdict + 48 h evidence chart) · Map (tap any sea point
  → live data, harbour search) · Navigate · **AI** (10-agent cards) · **SOS**
  (SMS without internet, satellite-truth card) · Info
 - **Voyage planner (wizard):** asks intent (🎣 fishing / 🏝️ return) →
  start (GPS / manual coords) → destination style, then **recommends**
  real spots — today's govt PFZ advisories + satellite chl blooms,
  each weather-gated with an auditable score card — pick → full analysis
- **Transit verdict (route-advisory):** the land-verified course sampled every
  ~30 km against live marine forecasts → **GO / CAUTION / NO-GO** with per-km
  observed numbers — worst point decides, never an average that hides danger
- **Live navigation alerts (offline):** off-course siren, turn cues,
  back-on-course recovery — pure GPS + route legs, works with no network
- **Plan-anywhere mode:** set a manual start point and plan a real sea route
  from anywhere (even inland) — honestly labelled; live steering pauses
- **Return-to-harbour:** nearest of 71 real Indian harbours, 100 % offline
- **145 i18n keys × 11 languages**, keysets machine-checked equal

## 🌐 web/ — Next.js dashboard (judges / desktop)

Live map + insight panel driven by the same backend (`/tiles`, `/advisory`,
`/reason`) — real data tiles rendered server-side.

## Setup (short)

1. Run the backend from the sister repo:
   `git clone https://github.com/SangamSitapuri07/ORCA-backend` →
   `pip install -r backend/requirements.txt -r pipeline/requirements.txt` →
   `uvicorn backend.main:app --host 0.0.0.0 --port 8000`
2. App: `cd orca_flutter && flutter pub get && flutter run`
   (phone + laptop same WiFi → Info tab → backend URL `IP:8000`)
3. Web: `cd web && npm install && npm run dev`

## Repo map

| Path | Kya hai |
|---|---|
| `orca_flutter/` | 📱 Flutter Android app (9 dart tests incl. marine-math verified vs Python) |
| `web/` | Next.js dashboard |
| `docs/` | FLUTTER-PLAN, ANDROID-PLAN, FIGMA/UI prompts, design assets |
| `update-orca.ps1` | one-command pull helper |

## Timeline

- **Idea submission deadline: 20 September 2026**
- Final target: working app + dashboard over live data × 8 Indian coastal zones

## Data sources (via backend)

Open-Meteo Marine/Forecast/Daily (MeteoFrance & ECMWF) · NOAA ERDDAP ·
ESA OC-CCI · ISRO MOSDAC OCM-3 · INCOIS LAS + official daily PFZ lines ·
Global Fishing Watch · JTWC · GLOBE 1 km land mask · Nominatim.

*For SIH 2026 demonstration. Team: Sangam Sitapuri et al. (Punjab).*
