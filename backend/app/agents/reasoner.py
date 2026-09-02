"""Reasoner agent — the final synthesizer.

Takes all the upstream agent results and produces:
  * a friendly natural-language answer (templated, language-aware)
  * a map payload (PFZ polygons, geofence warnings, user marker)
  * any safety alerts to display prominently
  * a safety score (0..1) if a risk agent was run

The reasoner is what makes ORCA feel "agentic": instead of returning raw
data, it tells a story with the data, *and* shows its reasoning.
"""
from __future__ import annotations

from app.models import AgentStep, MapPayload, MapPoint, MapPolygon, OrcaResponse

from .base import AgentContext, AgentResult, BaseAgent


# Friendly, template-based response strings. Add more languages by extending
# this dict. The structure is: locale -> intent -> response string with
# {placeholders} for the values filled in below.
RESPONSE_TEMPLATES: dict[str, dict[str, str]] = {
    "en": {
        "pfz": (
            "The nearest Potential Fishing Zone to you is **{pfz_name}**, about "
            "{distance_km} km from your location. Productivity score is "
            "{productivity:.0%} with SST {sst} °C and chlorophyll {chl} mg/m³. "
            "Conditions look {verdict}."
        ),
        "safety": (
            "Safety check for your area: safety score **{score:.0%}**. "
            "Waves are {wave} m, winds {wind} km/h, and you are near "
            "{geofence_count} geofenced zone(s). {verdict}."
        ),
        "weather": "Current conditions: wave height {wave} m, wind speed {wind} km/h, SST {sst} °C.",
        "route": "Route planning will avoid the {geofence_count} restricted zone(s) near you.",
        "geofence": "You are near {geofence_count} geofenced zone(s). {details}",
        "biology": "Productivity near you is {productivity:.0%} — SST {sst} °C, chlorophyll {chl} mg/m³.",
        "unknown": "I parsed your question as a general marine query. Here's what I found: {weather}",
    },
    "hi": {
        "pfz": (
            "आपके स्थान से सबसे नज़दीकी संभावित मछली पकड़ने का क्षेत्र **{pfz_name}** है, "
            "लगभग {distance_km} किमी दूर। उत्पादकता स्कोर {productivity:.0%} है।"
        ),
        "safety": (
            "आपके क्षेत्र के लिए सुरक्षा स्कोर **{score:.0%}** है। "
            "लहरें {wave} मीटर, हवा {wind} किमी/घंटा। {verdict}।"
        ),
    },
}


def _verdict(score: float) -> str:
    if score >= 0.75:
        return "Conditions are favourable"
    if score >= 0.5:
        return "Conditions are borderline — exercise caution"
    return "Conditions are unsafe — recommend staying ashore"


class ReasonerAgent(BaseAgent):
    name = "reasoner"

    async def run(self, ctx: AgentContext) -> AgentResult:
        # Pull upstream results from scratch (set by the orchestrator)
        weather = ctx.scratch.get("weather", {}).get("payload", {}).get("data", {})
        ocean = ctx.scratch.get("ocean", {}).get("payload", {})
        gis = ctx.scratch.get("gis", {}).get("payload", {})
        risk = ctx.scratch.get("risk", {}).get("payload", {})
        planner = ctx.scratch.get("planner", {}).get("payload", {})

        intent = planner.get("intent", "unknown")
        # Pick the language dict. Always include an "unknown" fallback
        # so we can always build a response, even if the language only
        # covers a subset of intents.
        if ctx.language in RESPONSE_TEMPLATES:
            lang = ctx.language
        else:
            lang = "en"
        templates = dict(RESPONSE_TEMPLATES[lang])  # shallow copy
        # Make sure we always have an "unknown" key — borrow from English
        # if the current language doesn't define one.
        if "unknown" not in templates:
            templates["unknown"] = RESPONSE_TEMPLATES["en"]["unknown"]

        # Build context for the template
        verdict = _verdict(risk.get("safety_score", 0.6)) if risk else "—"
        nearest_pfz = gis.get("nearest_pfz") or {}
        geofence_count = len(gis.get("nearby_geofences", []))

        template = templates.get(intent, templates["unknown"])
        try:
            answer_text = template.format(
                pfz_name=nearest_pfz.get("name", "nearby zone"),
                distance_km=gis.get("pfz_distance_km", "?"),
                productivity=ocean.get("productivity", 0.5),
                sst=ocean.get("sst", weather.get("sea_surface_temperature", "?")),
                chl=ocean.get("chlorophyll", "?"),
                score=risk.get("safety_score", 0.6),
                wave=weather.get("wave_height", "?"),
                wind=weather.get("wind_speed", "?"),
                geofence_count=geofence_count,
                verdict=verdict,
                details=", ".join(
                    f"{g['name']} ({g['distance_km']} km)"
                    for g in gis.get("nearby_geofences", [])
                ),
                weather=ctx.scratch.get("weather", {}).get("summary", ""),
            )
        except (KeyError, IndexError, ValueError) as exc:
            # Fall back to English if the template can't fill cleanly,
            # so the API never returns an empty answer.
            import logging
            logging.getLogger(__name__).warning("template fill failed: %s", exc)
            answer_text = RESPONSE_TEMPLATES["en"][intent if intent in RESPONSE_TEMPLATES["en"] else "unknown"].format(
                pfz_name=nearest_pfz.get("name", "nearby zone"),
                distance_km=gis.get("pfz_distance_km", "?"),
                productivity=ocean.get("productivity", 0.5),
                sst=ocean.get("sst", weather.get("sea_surface_temperature", "?")),
                chl=ocean.get("chlorophyll", "?"),
                score=risk.get("safety_score", 0.6),
                wave=weather.get("wave_height", "?"),
                wind=weather.get("wind_speed", "?"),
                geofence_count=geofence_count,
                verdict=verdict,
                details=", ".join(
                    f"{g['name']} ({g['distance_km']} km)"
                    for g in gis.get("nearby_geofences", [])
                ),
                weather=ctx.scratch.get("weather", {}).get("summary", ""),
            )
        # Last-resort guarantee: if the answer is still empty, build a
        # plain concatenation from the agent summaries so the API never
        # breaks.
        if not answer_text or not answer_text.strip():
            parts = []
            for key in ("weather", "ocean", "gis", "risk"):
                s = ctx.scratch.get(key, {}).get("summary")
                if s:
                    parts.append(s)
            answer_text = " | ".join(parts) or "No information available."

        # Build the map payload
        polygons: list[MapPolygon] = []
        if nearest_pfz and nearest_pfz.get("polygon"):
            polygons.append(
                MapPolygon(
                    name=nearest_pfz.get("name", "PFZ"),
                    coordinates=[tuple(p) for p in nearest_pfz["polygon"]],
                    color="#22c55e",
                )
            )
        for gf in gis.get("nearby_geofences", []):
            if gf.get("polygon"):
                polygons.append(
                    MapPolygon(
                        name=gf["name"],
                        coordinates=[tuple(p) for p in gf["polygon"]],
                        color="#ef4444",
                    )
                )

        points: list[MapPoint] = []
        if ctx.user_location:
            points.append(MapPoint(lat=ctx.user_location[0], lon=ctx.user_location[1],
                                   label="You", color="#3b82f6"))
        if nearest_pfz and nearest_pfz.get("centroid"):
            c = nearest_pfz["centroid"]
            points.append(MapPoint(lat=c[0], lon=c[1],
                                   label=nearest_pfz.get("name"), color="#22c55e"))

        alerts: list[str] = []
        if risk.get("safety_score", 1.0) < 0.5:
            alerts.append("⚠️ Conditions unsafe. Recommend staying ashore.")
        for gf in gis.get("nearby_geofences", []):
            alerts.append(f"⛔ Near {gf['name']} — restricted zone.")

        # Build the full reasoning trace (one entry per upstream agent)
        reasoning: list[AgentStep] = []
        for key in ("planner", "weather", "ocean", "gis", "risk"):
            entry = ctx.scratch.get(key)
            if not entry:
                continue
            reasoning.append(AgentStep(
                agent=entry.get("agent_name", key),
                summary=entry.get("summary", ""),
                data_sources=entry.get("data_sources", []),
                duration_ms=entry.get("duration_ms", 0),
            ))

        center = ctx.user_location or (18.9, 72.8)
        # Defensive defaults: if anything went wrong upstream, ensure
        # the response is never missing required fields.
        if not answer_text or not answer_text.strip():
            parts = []
            for key in ("weather", "ocean", "gis", "risk"):
                s = ctx.scratch.get(key, {}).get("summary")
                if s:
                    parts.append(s)
            answer_text = ("Marine information for your query: "
                           + " | ".join(parts)
                           + ("." if parts else "No data available."))
        response = OrcaResponse(
            answer_text=answer_text,
            language=lang,
            intent=intent if intent in {
                "pfz", "safety", "route", "biology", "geofence", "weather", "unknown"
            } else "unknown",
            confidence=ctx.scratch.get("planner", {}).get("confidence", 0.5),
            map=MapPayload(points=points, polygons=polygons,
                           center=center, zoom=6.5),
            alerts=alerts,
            reasoning=reasoning,
            safety_score=risk.get("safety_score"),
        )

        return AgentResult(
            agent_name=self.name,
            summary=f"Synthesized final answer ({len(reasoning)} agent steps).",
            confidence=0.9,
            data_sources=["templated response generator", "map payload builder"],
            payload={"response": response.model_dump()},
        )
