# ORCA — Marine Intelligence Platform

> **SIH 2026 · Problem Statement 176 (SIH26176)**
> **Marine EcOsystem Reasoning with Collaborative Agents**
> Organization: **ISRO · Department of Space** · Theme: Disaster Management

ORCA is a multi-agent AI system that combines real-time satellite ocean
data, weather models, and global fishing-fleet activity into explainable,
actionable marine intelligence for India's coastal communities.

## What it does

- **Pulls live ocean data** from 4 satellite + AIS systems
- **Runs 6 collaborating AI agents** (Ocean, Satellite, Fisheries, Marine
  Ecology, Marine Risk, Data Validation) over the same data
- **Generates a single recommendation** per zone: "Should a fisherman go
  out today?" with a colour-coded risk level
- **Cites every data source** so the answer is explainable

## Architecture

```
Next.js UI (web/)                  ← what the user sees
        ↓ HTTP
FastAPI backend (backend/)          ← (in progress)
        ↓ Python imports
Unified data layer (pipeline/orca_data.py)
        ↓
┌───────┼───────┬───────┬───────┐
NOAA   Open    GFW    INCOIS
ERDDAP Meteo   AIS    LAS
(chl)  (SST)   (fish) (chl)
```

**10 AI agents** (6 implemented, 3 stubbed):
1. 🌊 Ocean Analysis — SST, waves, currents
2. 🛰️ Satellite Analysis — chlorophyll, ocean colour
3. 🌦️ Weather & Hazard — IMD cyclones, wind (via Open-Meteo)
4. 🗺️ GIS & Spatial — coastlines, EEZ, ports
5. 🐟 Marine Ecology — cross-agent ecosystem patterns
6. 🎣 Fisheries / PFZ — combines all signals into a verdict
7. 🚨 Marine Risk — vessel-safety risk level
8. 🔍 Anomaly Detection — vs 30-year baseline
9. ✅ Data Validation — quality checks
10. 🧠 ORCA Reasoning — orchestrates all 9

## Data sources (all live, all verified)

| Source | What it gives | Cost | Status |
|--------|---------------|------|--------|
| NOAA ERDDAP DINEOF | Chlorophyll, daily, 0.025° | Free, no key | ✅ |
| Open-Meteo Marine | SST 0.08°, wave height, daily | Free, no key | ✅ |
| Global Fishing Watch | Fishing hours, vessel fleet, gear type | Free + token | ✅ |
| INCOIS LAS OPeNDAP | Indian Ocean chlorophyll backup | Free, no key | ✅ Adapter ready |
| MOSDAC OCM-3 L4 | 🇮🇳 Indian daily chlorophyll | Free + creds | 🔄 Pending |
| Open-Meteo Weather | Cyclones, rainfall, IMD-style wind | Free, no key | ⏳ Agent 3 stub |

## Quick start

```bash
# Backend / data layer
cd pipeline/
pip install -r requirements.txt
python -m pytest tests/                 # 81 tests pass
python demo_orca_reasoner.py            # full live pipeline demo

# Frontend
cd web/
npm install
npm run dev                             # http://localhost:3000
```

Set the GFW token in your shell:
```bash
export GFW_API_TOKEN="your-token"       # get one at globalfishingwatch.org
```

## Repository layout

```
.
├── pipeline/                 # Python data layer + agents
│   ├── orca_data.py          # unified ZoneSnapshot (5 sources → 1 dict)
│   ├── reasoner.py           # orchestrates the 10 agents
│   ├── agents/               # one file per agent
│   ├── erddap_chl.py         # NOAA chlorophyll adapter
│   ├── openmeteo_sst.py      # SST + waves adapter
│   ├── gfw.py                # Global Fishing Watch adapter
│   ├── incois.py             # INCOIS LAS adapter
│   ├── mosdac_auth.py        # MOSDAC SSO login
│   ├── parser.py             # NetCDF / HDF5 parser
│   └── tests/                # 81 tests
│
├── web/                      # Next.js frontend
│   ├── app/page.tsx          # map + insight panel
│   ├── components/           # MapView, InsightPanel
│   └── lib/orca-client.ts    # API client
│
├── backend/                  # FastAPI (preserved in mvp-prototype)
│
├── docs/
│   ├── PS_176_ORCA.md        # problem statement
│   ├── PLAN.md               # build plan
│   ├── MOSDAC_CATALOG.md     # MOSDAC dataset catalog
│   └── ...
│
└── mvp-prototype/            # earlier prototype (preserved)
```

## SIH 2026 timeline

- **Idea submission deadline**: 20 September 2026
- **Prototype target**: 5 working agents + 1 dashboard (this commit)
- **Final demo**: 10 agents + full data layer + 8 Indian coastal zones

## License

For SIH 2026 demonstration. Data source attribution: NOAA, Copernicus
(MeteoFrance via Open-Meteo), Global Fishing Watch, INCOIS, MOSDAC/ISRO.
