# PS 176 — ORCA Marine EcOsystem Reasoning with Collaborative Agents

> **Official SIH 2026 problem statement, fetched and verified from the SIH portal.**

## Metadata

| Field | Value |
| --- | --- |
| S.No. | 176 |
| PS Number | SIH26176 |
| Title | ORCA Marine EcOsystem Reasoning with Collaborative Agents |
| Organization | Indian Space Research Organisation (ISRO) |
| Department | Department of Space / Indian Space Research Organisation |
| Category | Software |
| Theme | Disaster Management |
| Deadline for Idea Submission | 20 September 2026 |

## Background (paraphrased from the official PS)

The marine ecosystem supports livelihoods, food security, biodiversity, maritime transport, coastal resilience, and the blue economy. Every day, ISRO and other agencies generate huge volumes of satellite Earth Observation and oceanographic data — Sea Surface Temperature (SST), chlorophyll, weather forecasts, etc. Marine stakeholders (fishermen, researchers, coastal authorities, disaster management, maritime operators) need timely, context-aware access to this data. We need an **intelligent conversational platform** that lets users ask questions in natural language and get synthesized, evidence-based, explainable recommendations.

## The core idea

Build an **Agentic AI-powered conversational platform** for marine intelligence. Not a chatbot that just retrieves facts — a system that:

1. Understands user intent from natural language (including Indian regional languages)
2. Decomposes complex questions into tasks
3. Coordinates **multiple specialized AI agents** (planning, weather, ocean, GIS, risk, visualization, etc.)
4. Pulls data from satellite Earth Observation, GIS, weather, oceanographic, and marine-advisory sources
5. Reasons spatially + temporally + contextually
6. Returns **explainable** answers with maps, charts, alerts, and reasoning traces

## Example user queries the system must answer

- "Where is the nearest Potential Fishing Zone (PFZ) today?"
- "Is it safe to venture into the sea tomorrow morning?"
- "What are the tide, weather, and sea conditions near my fishing location?"
- "Are there any lightning or cyclone alerts in my area?"
- "Which regions show high chlorophyll and favourable SST?"
- "What is the safest route for a fishing vessel considering weather and sea-state?"
- "Why has fish productivity declined in a particular coastal region?"
- "Which fishing zones should be avoided due to hazardous conditions or geofencing restrictions?"

## Required capabilities (from official PS)

- Natural-language understanding of user intent
- Auto language detection + Indian regional language responses
- Multi-turn contextual conversation
- Autonomous discovery + integration of satellite/marine/meteo/geospatial datasets
- Spatial + temporal + contextual reasoning over heterogeneous sources
- Explainable, evidence-backed recommendations (maps, charts, advisories)
- Fishermen safety: alerts for adverse weather, high waves, lightning, cyclones
- Geofencing: warnings when approaching international maritime boundaries, restricted waters, marine protected areas, ecologically sensitive zones
- Route optimization + safe navigation + operational planning
- Evidence + reasoning shown alongside every response

## Encouraged architecture

A **modular multi-agent system** with specialized agents for:
- Planning
- Marine data discovery
- Weather intelligence
- Ocean analytics
- Geospatial reasoning
- Risk assessment
- Visualization
- Reporting
- User interaction

The agents should collaborate autonomously to solve complex marine intelligence problems behind an intuitive conversational UI.

---

_Source: [sih.gov.in/sih2026PS](https://sih.gov.in/sih2026PS), mirrored at [vedantchalke36/sih-2026-problem-statements](https://github.com/vedantchalke36/sih-2026-problem-statements/blob/main/ps_2026/SIH26176.md), License: CC-BY-4.0_
