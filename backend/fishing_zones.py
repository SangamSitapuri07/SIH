"""Evidence-backed fishing-area suggestions near a user-selected map point.

Candidates come only from the latest official INCOIS PFZ line geometry. The
module never creates synthetic "hotspots". Each nearest point is independently
weather-gated; missing weather remains UNVERIFIED rather than being scored safe.
"""
from __future__ import annotations

import math
from typing import Any

from marine_router import bearing, haversine


def _closest_on_segment(
    lat: float, lon: float, a: list[float], b: list[float],
) -> tuple[float, float]:
    """Closest (lat, lon) on a short GeoJSON lon/lat segment."""
    scale = max(0.01, math.cos(math.radians(lat)))
    ax, ay = (a[0] - lon) * scale, a[1] - lat
    bx, by = (b[0] - lon) * scale, b[1] - lat
    dx, dy = bx - ax, by - ay
    denominator = dx * dx + dy * dy
    fraction = 0.0 if denominator == 0 else max(
        0.0, min(1.0, -(ax * dx + ay * dy) / denominator)
    )
    return (
        lat + ay + fraction * dy,
        lon + (ax + fraction * dx) / scale,
    )


def _closest_on_line(
    lat: float, lon: float, coordinates: list[list[float]],
) -> tuple[float, tuple[float, float]]:
    best_distance = math.inf
    best_point = (lat, lon)
    for start, end in zip(coordinates, coordinates[1:]):
        if len(start) < 2 or len(end) < 2:
            continue
        point = _closest_on_segment(lat, lon, start, end)
        distance = haversine((lat, lon), point)
        if distance < best_distance:
            best_distance, best_point = distance, point
    return best_distance, best_point


def _polylines(feature: dict[str, Any]) -> list[list[list[float]]]:
    geometry = feature.get("geometry") or {}
    coordinates = geometry.get("coordinates") or []
    if geometry.get("type") == "LineString":
        return [coordinates]
    if geometry.get("type") == "MultiLineString":
        return coordinates
    return []


def _freshest(features: list[dict[str, Any]]) -> list[dict[str, Any]]:
    def edition(feature: dict[str, Any]) -> tuple[int, int]:
        properties = feature.get("properties") or {}
        try:
            return int(properties.get("Year") or 0), int(properties.get("Julian_day") or 0)
        except (TypeError, ValueError):
            return 0, 0

    newest = max((edition(feature) for feature in features), default=(0, 0))
    if newest == (0, 0):
        return features
    return [feature for feature in features if edition(feature) == newest]


def _weather_state(snapshot: dict[str, Any]) -> tuple[str, str]:
    if snapshot.get("error"):
        return "UNVERIFIED", snapshot.get("reason", "Weather provider unavailable")
    variables = snapshot.get("variables") or {}
    wave = variables.get("wave_height_m")
    wind = variables.get("wind_speed_kn")
    gust = variables.get("wind_gust_kn")
    if wave is None or wind is None or gust is None:
        return "UNVERIFIED", "Required wave, wind or gust evidence is missing"
    if wave >= 4.0 or wind >= 34.0 or gust >= 34.0:
        return "DANGER", f"Wave {wave:.1f} m · wind {wind:.1f} kn · gust {gust:.1f} kn"
    if wave >= 2.5 or wind >= 20.0 or gust >= 25.0:
        return "CAUTION", f"Wave {wave:.1f} m · wind {wind:.1f} kn · gust {gust:.1f} kn"
    return "GOOD", f"Wave {wave:.1f} m · wind {wind:.1f} kn · gust {gust:.1f} kn"


def recommend(
    providers: Any, lat: float, lon: float, *, max_km: float = 250.0, limit: int = 4,
) -> dict[str, Any]:
    pfz = providers.fetch_incois_pfz()
    if pfz.get("status") != "fresh":
        return {
            "found": False,
            "recommendations": [],
            "reason": pfz.get("reason", "Official INCOIS PFZ geometry unavailable"),
            "source": pfz.get("source", "INCOIS PFZ GeoServer"),
        }

    features = _freshest(list(pfz.get("features") or []))
    candidates: list[dict[str, Any]] = []
    seen: set[tuple[float, float]] = set()
    for feature in features:
        properties = feature.get("properties") or {}
        for line in _polylines(feature):
            if len(line) < 2:
                continue
            distance, point = _closest_on_line(lat, lon, line)
            if not math.isfinite(distance) or distance > max_km:
                continue
            key = (round(point[0], 2), round(point[1], 2))
            if key in seen:
                continue
            seen.add(key)
            candidates.append({
                "lat": round(point[0], 5),
                "lon": round(point[1], 5),
                "distance_km": round(distance, 1),
                "distance_nm": round(distance * 0.539957, 1),
                "bearing_deg": round(bearing((lat, lon), point), 1),
                "kind": "OFFICIAL_PFZ",
                "uid": properties.get("UID"),
                "year": properties.get("Year"),
                "julian_day": properties.get("Julian_day"),
                "sector_code": properties.get("SECTORBOUN"),
                "line_length_km": properties.get("Length"),
            })

    candidates.sort(key=lambda item: item["distance_km"])
    # Weather-gate a few extra nearby lines, then return the best four. This is
    # ranking for usability, never a catch probability.
    pool = candidates[: max(limit * 2, limit)]
    snapshots = providers.fetch_route_weather_batch([
        (item["lat"], item["lon"]) for item in pool
    ]) if pool else []
    state_order = {"GOOD": 0, "CAUTION": 1, "UNVERIFIED": 2, "DANGER": 3}
    for index, candidate in enumerate(pool):
        snapshot = snapshots[index] if index < len(snapshots) else {
            "error": True, "reason": "Weather response omitted this point",
        }
        state, evidence = _weather_state(snapshot)
        variables = snapshot.get("variables") or {}
        candidate.update(
            weather_state=state,
            weather_evidence=evidence,
            wave_m=variables.get("wave_height_m"),
            wind_kn=variables.get("wind_speed_kn"),
            gust_kn=variables.get("wind_gust_kn"),
            sources=[source.get("name", "unknown") for source in snapshot.get("sources_used", [])],
        )
    pool.sort(key=lambda item: (state_order[item["weather_state"]], item["distance_km"]))
    selected = pool[:limit]
    return {
        "found": bool(selected),
        "recommendations": selected,
        "candidates_evaluated": len(pool),
        "reason": (
            "Latest official INCOIS PFZ line points ranked by weather state and distance. "
            "Rank is not catch probability or navigational clearance."
            if selected else f"No latest INCOIS PFZ line lies within {max_km:.0f} km"
        ),
        "source": pfz.get("source"),
        "dataset": pfz.get("dataset"),
        "source_url": pfz.get("source_url"),
    }
