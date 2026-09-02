"""Risk agent — turns raw data from other agents into a 0..1 safety score.

Higher score = safer to go out. 0.0 = definitely stay ashore, 1.0 = calm seas.

Inputs come from `ctx.scratch` which the orchestrator populates from
Weather + Ocean + GIS results. The scoring function is intentionally
simple and explainable — judges can read it on the slide.
"""
from __future__ import annotations

from .base import AgentContext, AgentResult, BaseAgent


class RiskAgent(BaseAgent):
    name = "risk"

    async def run(self, ctx: AgentContext) -> AgentResult:
        weather = ctx.scratch.get("weather", {})
        ocean = ctx.scratch.get("ocean", {})
        gis = ctx.scratch.get("gis", {})

        # Pull values with safe fallbacks
        wave = (weather.get("payload", {}).get("data", {}).get("wave_height")) or 1.0
        wind = (weather.get("payload", {}).get("data", {}).get("wind_speed")) or 15.0
        geofence_count = len(gis.get("payload", {}).get("nearby_geofences", []))

        # Simple weighted penalty model
        score = 1.0
        score -= max(0.0, (wave - 1.5)) * 0.30          # waves > 1.5 m cost 0.3 per meter
        score -= max(0.0, (wind - 25.0)) * 0.015         # wind > 25 km/h costs 0.015 per km/h
        score -= 0.25 * geofence_count                   # being near a geofence is risky
        score = max(0.0, min(1.0, score))

        return AgentResult(
            agent_name=self.name,
            summary=f"Computed safety score: {score:.2f} (wave {wave} m, wind {wind} km/h, geofences {geofence_count})",
            confidence=0.8,
            data_sources=["weighted-penalty model on weather+ocean+gis"],
            payload={"safety_score": round(score, 2), "wave": wave, "wind": wind,
                     "geofence_count": geofence_count},
        )
