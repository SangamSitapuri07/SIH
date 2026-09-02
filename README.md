# SIH 2026 — PS 176 — ORCA Marine Intelligence Platform

> **Problem:** ORCA Marine EcOsystem Reasoning with Collaborative Agents (SIH 2026, ISRO / Department of Space, Disaster Management theme)

A multi-agent AI platform for marine intelligence. Fishermen, researchers, and
coastal authorities can ask natural-language questions (English, Hindi, Tamil)
about fishing zones, safety, weather, navigation, and protected areas — and get
**explainable, map-backed answers** in real time.

## Live demo

- **API root (live in this sandbox):** http://localhost:8000/
- **Interactive docs (Swagger):** http://localhost:8000/docs
- **ReDoc:** http://localhost:8000/redoc

Try a quick query:
```bash
curl -X POST http://localhost:8000/ask \
  -H 'Content-Type: application/json' \
  -d '{"text":"Where is the nearest PFZ today?","location":[18.9,72.8]}'
```

## Architecture (one picture in words)

```
User (Flutter app)
    │  "Where is the nearest PFZ today?"
    ▼
FastAPI  ── POST /ask  (or  GET /stream for SSE)
    │
    ▼
┌─────────────── ORCA multi-agent pipeline ───────────────┐
│                                                         │
│  Planner (intent + agent selection, EN/HI/TA rules)    │
│      │                                                  │
│      ├── WeatherAgent  (Open-Meteo live + mock fallback)│
│      ├── OceanAgent    (SST + chlorophyll generator)   │
│      ├── GISAgent      (9 PFZ zones + 6 geofences)     │
│      ├── RiskAgent     (0..1 safety score)             │
│      └── Reasoner      (synthesizes + builds map)      │
│                                                         │
└─────────────────────────────────────────────────────────┘
    │
    ▼
OrcaResponse { answer_text, intent, map{points,polygons},
               alerts, reasoning[steps], safety_score }
```

## What's in this repo

```
wwith/                           (current branch)
├── docs/PS_176_ORCA.md          # Pinned problem statement
├── backend/                     # Python FastAPI + multi-agent pipeline
│   ├── app/agents/              # 6 agents (planner, weather, ocean, gis, risk, reasoner)
│   ├── app/data/                # Mock INCOIS + PFZ zones + geofences
│   ├── app/main.py              # FastAPI routes
│   ├── tests/                   # pytest, 5/5 passing
│   └── requirements.txt
├── app/                         # Flutter mobile app (coming next)
├── data/                        # Sample datasets
├── demo/                        # Demo script + screenshots
└── README.md                    # You are here
```

## Tech stack

- **Backend:** Python 3.11, FastAPI, httpx, Pydantic v2, pytest
- **Live data:** Open-Meteo (marine + weather, no API key required)
- **Mock data:** Realistic generators for INCOIS-style advisories
- **Mobile (in progress):** Flutter + flutter_map (OpenStreetMap) + http

## What makes this innovative (for judges)

1. **Hand-crafted agents, no LLM dependency** — every line of reasoning is
   auditable, which is exactly what an ISRO-aligned problem wants.
2. **Real-time streaming** — agents emit their steps one by one over SSE so
   the UI feels alive, not a single delayed blob.
3. **Explainable by design** — the response always includes a full
   `reasoning` chain so the user (and the judge) can see *why* the answer
   is what it is.
4. **Multilingual** — same pipeline handles English, Hindi, Tamil
   keywords out of the box.
5. **Geofencing + safety scoring** — uses real Indian marine protected
   area coordinates and a transparent penalty-based risk model.
6. **Graceful degradation** — if live APIs are unreachable (sandbox,
   patchy network on a fishing boat), the system falls back to realistic
   mock data without breaking the demo.

## How to run locally

```bash
# Backend
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# Mobile (coming next)
cd ../app
flutter pub get
flutter run
```

## Status

| Component | Status |
| --- | --- |
| Branch | `wwith` (from `main`) |
| PS text | ✅ Pinned in `docs/PS_176_ORCA.md` |
| Backend API | ✅ 5 agents, 3 endpoints, 5 tests passing |
| Multilingual (EN/HI/TA) | ✅ Planner + templates |
| Live data (Open-Meteo) | ✅ Wired with mock fallback |
| Real-time SSE stream | ✅ Working |
| Flutter mobile app | ⏳ Next step |
| Demo script + screenshots | ⏳ Final step |

## Next steps

1. Build Flutter app (chat + map + reasoning trace)
2. Wire the app to the backend (HTTP for /ask, SSE for streaming)
3. Add a few more agents: route planner, biology explainer
4. Polish + 1-page demo script for judges
