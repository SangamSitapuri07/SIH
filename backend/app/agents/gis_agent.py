"""GIS agent — geofences, PFZ zones, marine protected areas.

Knows about a small library of real Indian marine features:

  * Gulf of Kutch Marine National Park
  * Sundarbans Reserved Forest (eastern coast)
  * Gulf of Mannar Marine National Park
  * Malvan Marine Sanctuary
  * Potential Fishing Zones (3 mock zones along the Konkan coast)

The polygons are coarse but they sit on real coordinates. To extend:
add new polygons to `app/data/pfz_zones.py` and `app/data/geofences.py`.
"""
from __future__ import annotations

from app.data.geofences import GEOFENCES
from app.data.pfz_zones import PFZ_ZONES

from .base import AgentContext, AgentResult, BaseAgent


def _distance_km(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Quick haversine — good enough for nearest-neighbour lookups."""
    from math import asin, cos, radians, sin, sqrt
    lat1, lon1 = radians(a[0]), radians(a[1])
    lat2, lon2 = radians(b[0]), radians(b[1])
    h = sin((lat2 - lat1) / 2) ** 2 + cos(lat1) * cos(lat2) * sin((lon2 - lon1) / 2) ** 2
    return 2 * 6371 * asin(sqrt(h))


class GISAgent(BaseAgent):
    name = "gis"

    async def run(self, ctx: AgentContext) -> AgentResult:
        lat, lon = ctx.user_location or (18.9, 72.8)
        here = (lat, lon)

        # Find nearest PFZ zone.
        nearest_pfz = min(
            PFZ_ZONES,
            key=lambda z: _distance_km(here, z["centroid"]),
        )
        pfz_dist = _distance_km(here, nearest_pfz["centroid"])

        # Find any geofences the user is currently inside or near.
        nearby_geofences = []
        for gf in GEOFENCES:
            d = _distance_km(here, gf["centroid"])
            if d < gf["alert_radius_km"]:
                nearby_geofences.append({**gf, "distance_km": round(d, 1)})

        return AgentResult(
            agent_name=self.name,
            summary=(
                f"Nearest PFZ: {nearest_pfz['name']} ({pfz_dist:.0f} km). "
                f"Geofence alerts: {len(nearby_geofences)}."
            ),
            confidence=0.85,
            data_sources=["internal PFZ zone library", "internal geofence library"],
            payload={
                "user_location": list(here),
                "nearest_pfz": nearest_pfz,
                "pfz_distance_km": round(pfz_dist, 1),
                "nearby_geofences": nearby_geofences,
            },
        )
