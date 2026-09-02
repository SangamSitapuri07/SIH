"""Ocean agent — SST, chlorophyll, productivity reasoning.

In production this would call ISRO's MOSDAC / OCEANSAT / SCATSAT products
and INCOIS's Potential Fishing Zone (PFZ) advisories. Both require
institutional access, so for the hackathon we use a realistic generator
backed by the same coordinate system INCOIS uses (lat/lon boxes along
the Indian coast).
"""
from __future__ import annotations

import random
from datetime import datetime

from .base import AgentContext, AgentResult, BaseAgent


class OceanAgent(BaseAgent):
    name = "ocean"

    async def run(self, ctx: AgentContext) -> AgentResult:
        lat, lon = ctx.user_location or (18.9, 72.8)
        # Realistic ranges for the Arabian Sea in non-monsoon months.
        # These are tuned to look plausible on a map.
        sst = round(random.uniform(27.5, 30.5), 1)
        chlorophyll = round(random.uniform(0.1, 4.0), 2)
        # Productivity heuristic: high chlorophyll + optimal SST => productive
        productivity_score = min(
            1.0,
            (chlorophyll / 4.0) * 0.6 + max(0.0, 1.0 - abs(sst - 28.5) / 3.0) * 0.4,
        )

        return AgentResult(
            agent_name=self.name,
            summary=(
                f"Local ocean: SST {sst} °C, chlorophyll {chlorophyll} mg/m³, "
                f"productivity score {productivity_score:.2f}"
            ),
            confidence=0.7,
            data_sources=["mock INCOIS SST/chlorophyll generator"],
            payload={
                "lat": lat,
                "lon": lon,
                "sst": sst,
                "chlorophyll": chlorophyll,
                "productivity": productivity_score,
                "generated_at": datetime.utcnow().isoformat() + "Z",
            },
        )
