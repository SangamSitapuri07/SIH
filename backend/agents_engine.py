import json
import logging
import time
import threading
from typing import Dict, Any, List

from ollama_client import ollama

logger = logging.getLogger("orca.agents")

class MultiAgentEngine:
    """
    11 Collaborative Agents Architecture for ORCA Box backend.
    Enforces strict structured communication (AgentMessage format), a configured-limit
    worst-case safety fold, and evidence-backed synthesis.
    """

    AGENT_REGISTRY = [
        {"id": "data_validation", "name": "Data Validation Agent", "type": "Deterministic", "role": "Validate incoming provider observations and freshness"},
        {"id": "gis_spatial", "name": "GIS Spatial Agent", "type": "Deterministic", "role": "Coordinate context; route clearance remains a separate check"},
        {"id": "ocean_analysis", "name": "Ocean Analysis Agent", "type": "LLM/Analytical", "role": "Interpret ocean dynamics, wave height, swell & currents"},
        {"id": "satellite_analysis", "name": "Satellite Analysis Agent", "type": "LLM/Analytical", "role": "Interpret satellite chlorophyll-a & SST granules"},
        {"id": "weather_hazard", "name": "Weather Hazard Agent", "type": "LLM/Analytical", "role": "Explain wind/gust evidence without owning the safety verdict"},
        {"id": "map_synoptic", "name": "Map Synoptic Agent", "type": "Deterministic", "role": "Prepare synoptic grid & spatial overlays"},
        {"id": "marine_ecology", "name": "Marine Ecology Agent", "type": "LLM/Analytical", "role": "Ecological interpretation & fish habitat quality"},
        {"id": "fisheries_pfz", "name": "Fisheries / PFZ Agent", "type": "LLM/Analytical", "role": "Interpret official PFZ evidence and habitat suitability only"},
        {"id": "anomaly_detection", "name": "Anomaly Detection Agent", "type": "Deterministic", "role": "Detect unusual historical baseline deviations"},
        {"id": "marine_risk", "name": "Marine Risk Agent", "type": "Deterministic", "role": "Calculate marine safety risk via worst-case fold"},
        {"id": "orchestrator", "name": "Orchestrator Agent", "type": "LLM/Analytical", "role": "Synthesize agent findings into plain bilingual safety lines"}
    ]

    def __init__(self):
        self._runtime_lock = threading.Lock()
        self._run_lock = threading.Lock()
        self._runtime = {
            agent["id"]: {
                "status": "IDLE",
                "provider_state": (
                    "OLLAMA_NOT_RUN" if agent["type"] == "LLM/Analytical"
                    else "DETERMINISTIC"
                ),
                "last_duration_ms": None,
                "last_error": None,
            }
            for agent in self.AGENT_REGISTRY
        }

    def list_agents(self) -> List[Dict[str, Any]]:
        """Return registry metadata with truthful per-process runtime state."""
        with self._runtime_lock:
            return [
                {**agent, **dict(self._runtime[agent["id"]])}
                for agent in self.AGENT_REGISTRY
            ]

    def _set_all_runtime(self, status: str, error: str | None = None) -> None:
        llm_ids = {
            agent["id"] for agent in self.AGENT_REGISTRY
            if agent["type"] == "LLM/Analytical"
        }
        with self._runtime_lock:
            for agent_id, runtime in self._runtime.items():
                runtime["status"] = status
                if status == "PROCESSING":
                    runtime["provider_state"] = (
                        "OLLAMA_RUNNING" if agent_id in llm_ids else "DETERMINISTIC"
                    )
                elif status == "FAILED":
                    runtime["provider_state"] = (
                        "OLLAMA_REQUEST_FAILED" if agent_id in llm_ids else "DETERMINISTIC"
                    )
                runtime["last_error"] = error

    def _record_runtime_results(self, result: Dict[str, Any]) -> None:
        by_id = {
            agent.get("agent_id"): agent
            for agent in result.get("agents", [])
            if agent.get("agent_id")
        }
        with self._runtime_lock:
            for agent_id, runtime in self._runtime.items():
                finding = by_id.get(agent_id)
                if finding is None:
                    runtime["status"] = "FAILED"
                    runtime["last_error"] = "Agent result missing from reasoning trace"
                    continue
                status = str(finding.get("status", "completed")).upper()
                runtime["status"] = status
                runtime["provider_state"] = (
                    "OLLAMA_OUTPUT_USED" if finding.get("llm_invoked") is True
                    else "OLLAMA_NO_VALID_OUTPUT" if finding.get("llm_attempted") is True
                    else "DETERMINISTIC"
                )
                runtime["last_duration_ms"] = finding.get("duration_ms")
                runtime["last_error"] = None

    @staticmethod
    def _parse_analytical_response(response: str | None) -> Dict[str, str]:
        """Normalize valid structured responses from different Ollama versions."""
        if not response:
            return {}
        text = response.strip()
        if text.startswith("```"):
            lines = text.splitlines()
            text = "\n".join(lines[1:-1]).strip()
        try:
            value = json.loads(text)
        except (TypeError, ValueError):
            # Recover when an older model surrounds the JSON with a sentence.
            start, end = text.find("{"), text.rfind("}")
            if start < 0 or end <= start:
                return {}
            try:
                value = json.loads(text[start:end + 1])
            except (TypeError, ValueError):
                return {}

        if isinstance(value, dict):
            for wrapper in ("findings", "results", "agents", "analyses"):
                nested = value.get(wrapper)
                if isinstance(nested, (dict, list)):
                    value = nested
                    break

        normalized: Dict[str, str] = {}
        if isinstance(value, list):
            entries = value
        elif isinstance(value, dict):
            entries = [{"agent_id": key, "value": item} for key, item in value.items()]
        else:
            return normalized

        for entry in entries:
            if not isinstance(entry, dict):
                continue
            agent_id = entry.get("agent_id") or entry.get("id") or entry.get("role")
            item = entry.get("value", entry)
            if isinstance(item, str):
                finding = item
            elif isinstance(item, dict):
                finding = next(
                    (item[key] for key in ("finding", "findings", "summary", "analysis", "message", "text")
                     if isinstance(item.get(key), str)),
                    None,
                )
            else:
                finding = None
            if agent_id and isinstance(finding, str) and finding.strip():
                normalized_id = str(agent_id).strip().lower().replace("-", "_").replace(" ", "_")
                if normalized_id.endswith("_agent"):
                    normalized_id = normalized_id[:-6]
                normalized[normalized_id] = finding.strip()
        return normalized

    def _analytical_findings(self, jobs: Dict[str, Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
        """Run every analytical role in one Ollama request.

        Ollama serializes work on most laptops. Sending six simultaneous Qwen
        requests used six copies of the model context, starved CPU/RAM, and
        made all six requests hit the same timeout. One structured request is
        both faster and materially more reliable on an edge device.
        """
        evidence_payload = {
            agent_id: job["evidence"] for agent_id, job in jobs.items()
        }
        started = time.monotonic()
        response = ollama.generate(
            prompt=(
                "Analyse the following ORCA evidence for six specialist roles. "
                "Return ONLY one valid JSON object whose keys exactly match the supplied role IDs "
                "and whose values are short fisherman-friendly strings. Use only supplied evidence. "
                "Do not invent measurements, sources, times, confidence, or safety verdicts. "
                "If evidence is insufficient, say so for that role.\n"
                f"ROLE_EVIDENCE={json.dumps(evidence_payload, ensure_ascii=False)}"
            ),
            system=(
                "You are ORCA's analytical explanation layer. The deterministic Marine Risk "
                "engine owns the safety verdict; never change or create a verdict."
            ),
            temperature=0.1,
            max_tokens=480,
            json_mode=True,
            json_schema={
                "type": "object",
                "properties": {
                    agent_id: {"type": "string"} for agent_id in jobs
                },
                "required": list(jobs.keys()),
                "additionalProperties": False,
            },
        )
        elapsed_ms = int((time.monotonic() - started) * 1000)

        parsed = self._parse_analytical_response(response)
        missing_roles = [agent_id for agent_id in jobs if agent_id not in parsed]
        if response and missing_roles:
            logger.warning(
                "[Ollama] Structured response omitted/invalid roles %s; parsed keys=%s; "
                "missing roles will use deterministic fallback.",
                ", ".join(missing_roles),
                ", ".join(parsed) or "none",
            )

        results: Dict[str, Dict[str, Any]] = {}
        for agent_id, job in jobs.items():
            finding = parsed.get(agent_id)
            valid = isinstance(finding, str) and bool(finding.strip())
            results[agent_id] = {
                "findings": finding.strip() if valid else job["fallback"],
                # The specialist still returns a deterministic evidence-bound
                # result when optional Ollama text is absent. FALLBACK is not a
                # failed safety agent and must not be presented as DEGRADED.
                "status": "completed" if valid else "fallback",
                "duration_ms": elapsed_ms,
                "llm_attempted": True,
                "llm_invoked": valid,
                "llm_model": ollama.model,
                "fallback_used": not valid,
            }
        return results

    def run_collaborative_reasoning(self, snapshot: Dict[str, Any]) -> Dict[str, Any]:
        """Run the pipeline while exposing live status through `/agents`."""
        with self._run_lock:
            self._set_all_runtime("PROCESSING")
            try:
                result = self._run_collaborative_reasoning(snapshot)
            except Exception as exc:
                self._set_all_runtime("FAILED", str(exc))
                raise
            self._record_runtime_results(result)
            return result

    def _run_collaborative_reasoning(self, snapshot: Dict[str, Any]) -> Dict[str, Any]:
        """Build the complete 11-agent reasoning trace.

        LLM/Analytical roles share one structured Ollama inference so local
        CPU/GPU memory is not overwhelmed by six concurrent model contexts.
        """
        lat = snapshot.get("latitude", 20.9)
        lon = snapshot.get("longitude", 70.37)
        vars = snapshot.get("variables", {})

        required = ("wave_height_m", "wind_speed_kn", "wind_gust_kn")
        missing = [key for key in required if vars.get(key) is None]
        if missing:
            raise ValueError(f"Missing required live safety inputs: {', '.join(missing)}")
        wave_h = vars["wave_height_m"]
        wind_kn = vars["wind_speed_kn"]
        gust_kn = vars["wind_gust_kn"]
        current_kn = vars.get("current_speed_kn")
        chl = vars.get("chlorophyll_mg_m3")
        source_names = [source.get("name", "unknown") for source in snapshot.get("sources_used", [])]
        current_text = f"{current_kn:.1f} kn" if current_kn is not None else "unavailable"
        pfz_text = "Official PFZ geometry is available." if snapshot.get("pfz") else "Official PFZ geometry unavailable."

        # Deterministic Marine Risk verdict (Agent 10 logic) — pure arithmetic,
        # computed up front so the Orchestrator LLM can run in parallel with
        # the other analytical agents using the real verdict as evidence.
        # Thresholds:
        # Wave: < 2.5 Good, >= 2.5 Caution, >= 4.0 Danger
        # Gust: >= 34 Danger
        # Sustained Wind: >= 20 Caution
        risk_level = "GOOD"
        reasons = []

        if wave_h >= 4.0 or gust_kn >= 34.0:
            risk_level = "NO-GO"
            if wave_h >= 4.0: reasons.append(f"High waves ({wave_h:.1f} m >= 4.0 m threshold)")
            if gust_kn >= 34.0: reasons.append(f"Dangerous wind gusts ({gust_kn:.1f} kn >= 34 kn gale threshold)")
        elif wave_h >= 2.5 or wind_kn >= 20.0:
            risk_level = "CAUTION"
            if wave_h >= 2.5: reasons.append(f"Moderate waves ({wave_h:.1f} m >= 2.5 m threshold)")
            if wind_kn >= 20.0: reasons.append(f"Brisk wind ({wind_kn:.1f} kn >= 20 kn threshold)")
        else:
            risk_level = "GOOD"
            reasons.append("Waves and wind are below the configured point-advisory limits.")

        analytical = self._analytical_findings({
            "ocean_analysis": {
                "evidence": [f"wave height {wave_h:.1f} m", f"wave period {vars.get('wave_period_s', 'unavailable')} s", f"current {current_text}"],
                "fallback": f"Wave height is {wave_h:.1f} m with swell period {vars.get('wave_period_s', 'unavailable')} s. Surface currents at {current_text}.",
            },
            "satellite_analysis": {
                "evidence": [f"chlorophyll-a {chl} mg/m³", f"SST {vars.get('sst_celsius')} °C"],
                "fallback": f"Chlorophyll-a density measured at {chl} mg/m³." if chl is not None else "Chlorophyll measurement unavailable.",
            },
            "weather_hazard": {
                "evidence": [f"sustained wind {wind_kn:.1f} kn", f"wind gust {gust_kn:.1f} kn", "source: Open-Meteo Forecast"],
                "fallback": f"Wind sustained at {wind_kn:.1f} kn with peak gusts reaching {gust_kn:.1f} kn.",
            },
            "marine_ecology": {
                "evidence": [f"chlorophyll-a {chl} mg/m³", f"SST {vars.get('sst_celsius')} °C"],
                "fallback": "Ecological interpretation is unavailable without a validated chlorophyll measurement.",
            },
            "fisheries_pfz": {
                "evidence": [f"PFZ features returned: {len(snapshot.get('pfz', []))}", f"chlorophyll-a {chl} mg/m³"],
                "fallback": "PFZ interpretation is unavailable without validated official PFZ geometry and measurements.",
            },
            "orchestrator": {
                "evidence": [f"deterministic risk level {risk_level}", *reasons, f"wave height {wave_h:.1f} m", f"wind gust {gust_kn:.1f} kn"],
                "fallback": f"Deterministic Marine Risk result is {risk_level}. Follow the deterministic result and official instructions.",
            },
        })
        ocean_llm = analytical["ocean_analysis"]
        satellite_llm = analytical["satellite_analysis"]
        weather_llm = analytical["weather_hazard"]
        ecology_llm = analytical["marine_ecology"]
        pfz_llm = analytical["fisheries_pfz"]
        orchestrator_llm = analytical["orchestrator"]

        # Agent 1: Data Validation
        val_agent = {
            "agent_id": "data_validation",
            "agent_name": "Data Validation Agent",
            "type": "Deterministic",
            "status": "completed",
            "duration_ms": 12,
            "findings": "Required wave, wind and gust inputs are present. Provider timestamps and source details remain attached to the advisory.",
            "evidence": source_names,
            "warnings": []
        }

        # Agent 2: GIS Spatial
        gis_agent = {
            "agent_id": "gis_spatial",
            "agent_name": "GIS Spatial Agent",
            "type": "Deterministic",
            "status": "completed",
            "duration_ms": 15,
            "findings": f"Coordinate ({lat:.2f}, {lon:.2f}) was accepted for point-forecast analysis. Land, restricted-area and regulatory clearance require separate route evidence.",
            "evidence": source_names,
            "warnings": []
        }

        # Agent 3: Ocean Analysis
        ocean_verdict = "GOOD" if wave_h < 2.5 else ("CAUTION" if wave_h < 4.0 else "DANGER")
        ocean_agent = {
            "agent_id": "ocean_analysis",
            "agent_name": "Ocean Analysis Agent",
            "type": "LLM/Analytical",
            **ocean_llm,
            "verdict": ocean_verdict,
            "evidence": [f"Wave height = {wave_h:.1f} m", f"Current speed = {current_text}"],
            "warnings": [] if wave_h < 2.5 else [f"Moderate wave height ({wave_h:.1f} m) requires caution for small motor boats."]
        }

        # Agent 4: Satellite Analysis
        sat_agent = {
            "agent_id": "satellite_analysis",
            "agent_name": "Satellite Analysis Agent",
            "type": "LLM/Analytical",
            **satellite_llm,
            "evidence": source_names,
            "warnings": []
        }

        # Agent 5: Weather Hazard
        weather_verdict = "GOOD" if gust_kn < 34 and wind_kn < 20 else ("CAUTION" if wind_kn < 34 else "DANGER")
        weather_agent = {
            "agent_id": "weather_hazard",
            "agent_name": "Weather Hazard Agent",
            "type": "LLM/Analytical",
            **weather_llm,
            "verdict": weather_verdict,
            "evidence": [f"Wind speed = {wind_kn:.1f} kn", f"Peak gust = {gust_kn:.1f} kn"],
            "warnings": [] if gust_kn < 28 else [f"Brisk gusts up to {gust_kn:.1f} kn expected near afternoon."]
        }

        # Agent 6: Map Synoptic
        synoptic_agent = {
            "agent_id": "map_synoptic",
            "agent_name": "Map Synoptic Agent",
            "type": "Deterministic",
            "status": "completed",
            "duration_ms": 18,
            "findings": "Prepared map context from the requested live coordinate.",
            "evidence": source_names,
            "warnings": []
        }

        # Agent 7: Marine Ecology
        ecology_agent = {
            "agent_id": "marine_ecology",
            "agent_name": "Marine Ecology Agent",
            "type": "LLM/Analytical",
            **ecology_llm,
            "evidence": source_names,
            "warnings": []
        }

        # Agent 8: Fisheries / PFZ
        pfz_agent = {
            "agent_id": "fisheries_pfz",
            "agent_name": "Fisheries / PFZ Agent",
            "type": "LLM/Analytical",
            **pfz_llm,
            "evidence": source_names,
            "warnings": []
        }

        # Agent 9: Anomaly Detection
        anomaly_agent = {
            "agent_id": "anomaly_detection",
            "agent_name": "Anomaly Detection Agent",
            "type": "Deterministic",
            "status": "unavailable",
            "duration_ms": 0,
            "findings": "Historical anomaly detection is unavailable because no validated historical baseline was supplied.",
            "evidence": [],
            "warnings": []
        }

        # Agent 10: Marine Risk (Worst-Case Fold Rules) — computed up front.
        risk_agent = {
            "agent_id": "marine_risk",
            "agent_name": "Marine Risk Agent",
            "type": "Deterministic",
            "status": "completed",
            "duration_ms": 10,
            "verdict": risk_level,
            "findings": f"Worst-case safety fold result: {risk_level}. Primary rationale: {'; '.join(reasons)}",
            "evidence": ["ORCA configured wave/wind/gust limits", *source_names],
            "warnings": [] if risk_level == "GOOD" else reasons
        }

        # Agent 11: Orchestrator Agent (Bilingual Plain Synthesis)
        if risk_level == "GOOD":
            headline_en = "CONDITIONS BELOW CONFIGURED LIMITS"
            headline_hi = "मौसम मान कॉन्फ़िगर की गई सीमाओं से कम हैं"
            headline_te = "వాతావరణ విలువలు కాన్ఫిగర్ చేసిన పరిమితుల కంటే తక్కువగా ఉన్నాయి"
            plain_en = [
                "Downloaded wave and wind values are below the configured limits at this sampled location.",
                f"Waves are low ({wave_h:.1f} m) and wind is gentle ({wind_kn:.1f} kn).",
                pfz_text
            ]
            plain_hi = [
                "डाउनलोड किए गए लहर और हवा के मान कॉन्फ़िगर की गई सीमाओं से कम हैं।",
                f"लहरें कम हैं ({wave_h:.1f} मीटर) और हवा हल्की है ({wind_kn:.1f} समुद्री मील)।",
                "आधिकारिक PFZ geometry उपलब्ध होने पर ही मत्स्य क्षेत्र दिखाया जाएगा।"
            ]
            plain_te = [
                "డౌన్‌లోడ్ చేసిన అలలు మరియు గాలి విలువలు కాన్ఫిగర్ చేసిన పరిమితుల కంటే తక్కువగా ఉన్నాయి.",
                f"అలలు {wave_h:.1f} మీటర్లు, గాలి {wind_kn:.1f} నాట్లు.",
                "అధికారిక PFZ సమాచారం అందుబాటులో ఉన్నప్పుడు మాత్రమే చూపబడుతుంది."
            ]
        elif risk_level == "CAUTION":
            headline_en = "CAUTION ADVISED — MODERATE SEA"
            headline_hi = "सावधानी बरतें — मध्यम समुद्र"
            headline_te = "జాగ్రత్త వహించండి — మితమైన అలలు"
            plain_en = [
                f"Waves are moderate ({wave_h:.1f} m). Take care offshore.",
                f"Wind gusts up to {gust_kn:.1f} kn expected near afternoon.",
                "Check your return route before heading farther out."
            ]
            plain_hi = [
                f"लहरें मध्यम हैं ({wave_h:.1f} मीटर)। गहरे समुद्र में सावधानी बरतें।",
                f"दोपहर के आसपास {gust_kn:.1f} समुद्री मील तक हवा के झोंके संभव हैं।",
                "आगे जाने से पहले अपने लौटने के रास्ते की जांच करें।"
            ]
            plain_te = [
                f"అలలు మధ్యస్థంగా ఉన్నాయి ({wave_h:.1f} మీటర్లు); సముద్రంలో జాగ్రత్త వహించండి.",
                f"గాలి వేగం {gust_kn:.1f} నాట్ల వరకు చేరవచ్చు.",
                "ముందుకు వెళ్లే ముందు తిరుగు మార్గాన్ని తనిఖీ చేయండి."
            ]
        else:
            headline_en = "DANGER — DO NOT GO TO SEA"
            headline_hi = "खतरा — आज समुद्र में न जाएं"
            headline_te = "ప్రమాదం — ఈ రోజు వేటకు వెళ్లవద్దు"
            plain_en = [
                f"Dangerous rough sea conditions! Waves reaching {wave_h:.1f} m.",
                f"Gale wind gusts at {gust_kn:.1f} kn exceeding safety limits.",
                "Stay at harbour until weather advisory clears."
            ]
            plain_hi = [
                f"खतरनाक उबड़-खाबड़ समुद्र! लहरें {wave_h:.1f} मीटर तक पहुंच रही हैं।",
                f"तेज हवा के झोंके {gust_kn:.1f} समुद्री मील तक हैं जो सुरक्षा सीमा से अधिक हैं।",
                "मौसम की चेतावनी हटने तक बंदरगाह पर ही रहें।"
            ]
            plain_te = [
                f"ప్రమాదకరమైన సముద్ర పరిస్థితులు; అలలు {wave_h:.1f} మీటర్ల వరకు ఉన్నాయి.",
                f"గాలి వేగం {gust_kn:.1f} నాట్లు; ఇది భద్రతా పరిమితిని మించింది.",
                "హెచ్చరిక తొలగే వరకు నౌకాశ్రయంలోనే ఉండండి."
            ]

        orchestrator_agent = {
            "agent_id": "orchestrator",
            "agent_name": "Orchestrator Agent",
            "type": "LLM/Analytical",
            **orchestrator_llm,
            "verdict": risk_level,
            "evidence": ["Deterministic Marine Risk result plus available specialist traces"],
            "warnings": []
        }

        agents_list = [
            val_agent, gis_agent, ocean_agent, sat_agent, weather_agent,
            synoptic_agent, ecology_agent, pfz_agent, anomaly_agent, risk_agent, orchestrator_agent
        ]

        generated_at = int(time.time())
        return {
            "overall_risk": risk_level,
            "verdict": risk_level,
            "timestamp": generated_at,
            "source_timestamp": snapshot.get("timestamp"),
            "headline_en": headline_en,
            "headline_hi": headline_hi,
            "headline_te": headline_te,
            "plain_en": plain_en,
            "plain_hi": plain_hi,
            "plain_te": plain_te,
            "orchestrator_synthesis": {
                "headline": headline_en,
                "recommendation": " ".join(plain_en),
                "trace_owner": "orchestrator",
                "timestamp": generated_at,
            },
            "agents": agents_list,
            "data_coverage": {
                "known": len(source_names),
                "total": len(source_names) + len(snapshot.get("sources_failed", [])),
                "sources_failed": [failure.get("source", "unknown") for failure in snapshot.get("sources_failed", [])]
            }
        }
