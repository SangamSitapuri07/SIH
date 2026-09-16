"""Evidence-first pre-trip forecast package generator.

This module deliberately separates measured/model inputs from deterministic
risk rules. It never invents catch weights, profit, storm probabilities or
species behaviour models when no validated dataset/model is installed.
"""
from __future__ import annotations

import hashlib
import json
import math
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from typing import Any

from marine_router import haversine


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse_time(value: str | None) -> datetime:
    if not value:
        return datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None: parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _number(series: list[Any], index: int) -> float | None:
    if index >= len(series) or series[index] is None: return None
    try:
        value = float(series[index])
        return value if math.isfinite(value) else None
    except (TypeError, ValueError):
        return None


class TripPlanningEngine:
    def __init__(self, providers: Any):
        self.providers = providers

    @staticmethod
    def _area_points(lat: float, lon: float, radius_km: float) -> list[tuple[float, float]]:
        # Centre + cardinal/inter-cardinal perimeter samples. These represent an
        # uncertain fishing area, not a fabricated vessel track.
        points = [(lat, lon)]
        lat_step = radius_km / 111.0
        lon_step = radius_km / (111.0 * max(.2, math.cos(math.radians(lat))))
        for angle in range(0, 360, 45):
            r = math.radians(angle)
            points.append((lat + lat_step * math.cos(r), lon + lon_step * math.sin(r)))
        return [(round(a, 5), round(b, 5)) for a, b in points]

    @staticmethod
    def _classify(wave: float | None, wind: float | None, gust: float | None,
                  limits: dict[str, float]) -> tuple[str, float, list[str]]:
        missing = [name for name, value in (("wave", wave), ("wind", wind), ("gust", gust)) if value is None]
        if missing: return "UNVERIFIED", 1.0, ["Missing " + ", ".join(missing)]
        ratios = {
            "wave": wave / limits["max_wave_m"],
            "wind": wind / limits["max_wind_kn"],
            "gust": gust / limits["max_gust_kn"],
        }
        peak = max(ratios.values())
        reasons = [f"{name} at {ratio*100:.0f}% of vessel limit" for name, ratio in ratios.items() if ratio >= .7]
        if peak >= 1: return "NO_GO", min(1.0, peak), reasons
        if peak >= .7: return "CAUTION", peak, reasons
        return "GOOD", peak, reasons or ["Wave, wind and gust below 70% of configured limits"]

    def generate(self, request: Any) -> dict[str, Any]:
        start = _parse_time(request.departure_at)
        duration_hours = request.duration_days * 24
        points = self._area_points(request.area_lat, request.area_lon, request.area_radius_km)
        departure_lat = getattr(request, "departure_lat", None)
        departure_lon = getattr(request, "departure_lon", None)
        if (departure_lat is None) != (departure_lon is None):
            raise ValueError("Both departure_lat and departure_lon are required for offline navigation")
        route_info = None
        if departure_lat is not None and departure_lon is not None:
            route_info = self.providers.verify_route(
                departure_lat, departure_lon, request.area_lat, request.area_lon
            )

        with ThreadPoolExecutor(max_workers=6) as pool:
            snapshots = list(pool.map(
                lambda p: self.providers.fetch_zone_snapshot(p[0], p[1], include_secondary=False),
                points,
            ))

        usable = [snapshot for snapshot in snapshots if not snapshot.get("error")]
        cyclone_payload = self.providers.fetch_cyclone_sources() if hasattr(self.providers, "fetch_cyclone_sources") else {"gdacs": [], "jtwc": [], "sources_failed": []}
        cyclone_events = []
        for feature in cyclone_payload.get("gdacs", []):
            geometry = feature.get("geometry") or {}
            coordinates = geometry.get("coordinates") or []
            if geometry.get("type") != "Point" or len(coordinates) < 2: continue
            event_point = (float(coordinates[1]), float(coordinates[0]))
            distance = haversine((request.area_lat, request.area_lon), event_point)
            if distance <= 1200:
                props = feature.get("properties") or {}
                cyclone_events.append({
                    "source": "GDACS", "event_id": props.get("eventid"),
                    "name": props.get("eventname"), "alert_level": props.get("alertlevel"),
                    "from_date": props.get("fromdate"), "to_date": props.get("todate"),
                    "distance_from_area_km": round(distance, 1),
                    "position": {"lat": event_point[0], "lon": event_point[1]},
                })
        limits = {
            "max_wave_m": request.max_wave_m,
            "max_wind_kn": request.max_wind_kn,
            "max_gust_kn": request.max_gust_kn,
        }
        timeline: list[dict[str, Any]] = []
        for hour in range(duration_hours):
            target = start + timedelta(hours=hour)
            samples = []
            for point, snapshot in zip(points, snapshots):
                if snapshot.get("error"): continue
                hourly = snapshot.get("hourly_forecast", {})
                times = hourly.get("time") or []
                # Open-Meteo timestamps are hourly UTC strings.
                key = target.strftime("%Y-%m-%dT%H:00")
                index = next((i for i, value in enumerate(times) if str(value) >= key), None)
                if index is None: continue
                samples.append({
                    "lat": point[0], "lon": point[1],
                    "wave_m": _number(hourly.get("wave_height_m") or [], index),
                    "wind_kn": _number(hourly.get("wind_speed_kn") or [], index),
                    "gust_kn": _number(hourly.get("wind_gust_kn") or [], index),
                })
            waves = [s["wave_m"] for s in samples if s["wave_m"] is not None]
            winds = [s["wind_kn"] for s in samples if s["wind_kn"] is not None]
            gusts = [s["gust_kn"] for s in samples if s["gust_kn"] is not None]
            wave, wind, gust = (max(waves) if waves else None, max(winds) if winds else None, max(gusts) if gusts else None)
            state, risk, reasons = self._classify(wave, wind, gust, limits)
            timeline.append({
                "hour": hour, "valid_at": _iso(target), "state": state,
                "risk_index": round(risk, 3), "worst_wave_m": wave,
                "worst_wind_kn": wind, "worst_gust_kn": gust,
                "area_samples_known": len(samples), "area_samples_total": len(points),
                "reasons": reasons,
            })

        # Detect deterioration from actual forecast deltas, not a claimed storm probability.
        alerts = []
        for i, item in enumerate(timeline):
            previous = timeline[max(0, i-3)]
            changes = []
            for key, label, threshold in (("worst_wave_m", "Wave", .75), ("worst_wind_kn", "Wind", 7.0), ("worst_gust_kn", "Gust", 10.0)):
                if item[key] is not None and previous[key] is not None and item[key] - previous[key] >= threshold:
                    changes.append(f"{label} rises {previous[key]:.1f} to {item[key]:.1f} in <=3h")
            if item["state"] in {"NO_GO", "UNVERIFIED"} or changes:
                alerts.append({"valid_at": item["valid_at"], "severity": "DANGER" if item["state"] == "NO_GO" else "WARNING", "state": item["state"], "evidence": changes or item["reasons"]})

        for event in cyclone_events:
            alerts.append({
                "valid_at": event.get("from_date"), "severity": "DANGER" if str(event.get("alert_level", "")).lower() == "red" else "WARNING",
                "state": "CYCLONE_EVENT", "evidence": [f"GDACS {event.get('name') or 'tropical cyclone'} is {event['distance_from_area_km']:.0f} km from planned-area centre"],
                "source": "GDACS",
            })

        first_unsafe = next((item for item in timeline if item["state"] in {"NO_GO", "UNVERIFIED"}), None)
        known = sum(item["area_samples_known"] for item in timeline)
        total = sum(item["area_samples_total"] for item in timeline)
        states = {item["state"] for item in timeline}
        if not usable or "UNVERIFIED" in states: verdict = "UNVERIFIED"
        elif "NO_GO" in states: verdict = "NO_GO"
        elif "CAUTION" in states: verdict = "CAUTION"
        else: verdict = "GOOD"

        speed_kmh = request.cruise_speed_kn * 1.852
        # When a departure is supplied, fuel/return calculations use the
        # verified port-to-area route—not the fishing-area radius. The radius
        # fallback remains only for older API clients that did not send a port.
        one_way_km = (
            float(route_info["distance_km"])
            if route_info is not None and route_info.get("ok") is True
            else request.area_radius_km
        )
        round_trip_hours = (2 * one_way_km / speed_kmh) if speed_kmh > 0 else None
        required_fuel = round_trip_hours * request.fuel_burn_lph if round_trip_hours is not None else None
        usable_fuel = request.fuel_liters * (1 - request.fuel_reserve_percent / 100)
        return_deadline = None
        if first_unsafe and round_trip_hours is not None:
            unsafe_at = _parse_time(first_unsafe["valid_at"])
            return_deadline = _iso(unsafe_at - timedelta(hours=(round_trip_hours / 2) + 2))
        fuel = {
            "status": "UNVERIFIED" if request.fuel_burn_lph <= 0 else ("INSUFFICIENT" if required_fuel > usable_fuel else "SUFFICIENT_FOR_DIRECT_OUT_AND_BACK"),
            "available_liters": request.fuel_liters, "reserve_percent": request.fuel_reserve_percent,
            "route_one_way_km": round(one_way_km, 1),
            "estimated_direct_round_trip_liters": round(required_fuel, 1) if required_fuel is not None and request.fuel_burn_lph > 0 else None,
            "note": "Fishing/search/idle fuel is not estimated; operator must add it." if request.fuel_burn_lph > 0 else "Fuel burn rate was not provided.",
        }
        travel = {
            "status": (
                "ROUTE_UNVERIFIED" if route_info is not None and route_info.get("ok") is not True
                else "EXCEEDS_TRIP_DURATION" if round_trip_hours is not None and round_trip_hours > duration_hours
                else "FEASIBLE_DIRECT_OUT_AND_BACK"
            ),
            "one_way_hours": round(round_trip_hours / 2, 1) if round_trip_hours is not None else None,
            "direct_round_trip_hours": round(round_trip_hours, 1) if round_trip_hours is not None else None,
            "trip_duration_hours": duration_hours,
            "time_remaining_after_direct_travel_hours": round(max(0, duration_hours - round_trip_hours), 1) if round_trip_hours is not None else None,
            "note": "Travel estimate excludes fishing/search/idle time and weather/current speed effects.",
        }
        if route_info is not None and route_info.get("ok") is not True:
            verdict = "UNVERIFIED"
            alerts.append({
                "valid_at": _iso(start), "severity": "DANGER", "state": "ROUTE_UNVERIFIED",
                "evidence": [route_info.get("reason", "Offline route geometry is unavailable")],
            })
        else:
            if travel["status"] == "EXCEEDS_TRIP_DURATION":
                verdict = "NO_GO"
                alerts.append({
                    "valid_at": _iso(start), "severity": "DANGER", "state": "TRIP_TIME_INFEASIBLE",
                    "evidence": [
                        f"Direct return travel needs {travel['direct_round_trip_hours']:.1f} h, exceeding the {duration_hours} h trip duration before fishing time"
                    ],
                })
            if fuel["status"] == "INSUFFICIENT":
                verdict = "NO_GO"
                alerts.append({
                    "valid_at": _iso(start), "severity": "DANGER", "state": "FUEL_INSUFFICIENT",
                    "evidence": [
                        f"Direct out-and-back requires {fuel['estimated_direct_round_trip_liters']:.1f} L before fishing/search/idle allowance; only {usable_fuel:.1f} L is usable after reserve"
                    ],
                })
            elif fuel["status"] == "UNVERIFIED" and verdict != "NO_GO":
                verdict = "UNVERIFIED"
            if route_info is not None and route_info.get("regulatory_verified") is not True and verdict == "GOOD":
                verdict = "CAUTION"

        if route_info is not None and route_info.get("ok") is not True:
            return_reason = "Return route geometry is unverified; do not depart on this package."
        elif travel["status"] == "EXCEEDS_TRIP_DURATION":
            return_reason = "Direct out-and-back travel exceeds the selected trip duration before fishing time."
        elif fuel["status"] == "INSUFFICIENT":
            return_reason = "Available fuel after reserve is insufficient even for direct out-and-back travel."
        elif first_unsafe:
            return_reason = "Deadline includes estimated one-way travel from the planned area plus a 2-hour buffer."
        else:
            return_reason = "No NO_GO weather hour in downloaded horizon; forecast expiry is not a safety guarantee."

        navigation = None if route_info is None else {
            "status": route_info.get("status"), "ok": route_info.get("ok"),
            "geometry": route_info.get("legs", []),
            "distance_km": route_info.get("distance_km"),
            "distance_nm": route_info.get("distance_nm"),
            "departure": {"lat": departure_lat, "lon": departure_lon},
            "destination": {"lat": request.area_lat, "lon": request.area_lon},
            "boundary_reason": route_info.get("reason"),
            "regulatory_verified": route_info.get("regulatory_verified", False),
            "sources": route_info.get("sources", []),
            "offline_rules": {
                "off_route_warning_km": 2.0,
                "method": "Local GPS projection onto downloaded route polyline",
                "requires_internet": False,
            },
        }

        generated = datetime.now(timezone.utc)
        package = {
            "schema_version": "1.0", "trip_id": f"trip-{generated.strftime('%Y%m%d')}-{uuid.uuid4().hex[:8]}",
            "generated_at": _iso(generated), "departure_at": _iso(start),
            "decision_engine": {
                "name": "ORCA Deterministic Offline Safety Engine", "version": "1.1",
                "type": "RULE_BASED_NOT_ML",
                "method": "Worst-case area forecast samples compared with operator-configured vessel limits",
                "forecast_inputs": ["Open-Meteo Marine", "Open-Meteo Forecast"],
                "not_predicted": ["catch probability", "expected catch weight", "profit", "storm probability"],
            },
            "forecast_valid_until": timeline[-1]["valid_at"] if timeline else None,
            "offline_ready": bool(timeline) and known > 0 and (
                route_info is None or route_info.get("ok") is True
            ),
            "verdict": verdict, "coverage": {"known": known, "total": total, "ratio": round(known/total, 3) if total else 0},
            "area": {"center": {"lat": request.area_lat, "lon": request.area_lon}, "radius_km": request.area_radius_km, "sample_points": [{"lat": a, "lon": b} for a,b in points]},
            "trip_profile": {
                "trip_name": getattr(request, "trip_name", None),
                "vessel_name": getattr(request, "vessel_name", None),
                "shore_contact": getattr(request, "shore_contact", None),
                "duration_days": request.duration_days, "crew_size": request.crew_size,
                "boat_capacity_kg": request.boat_capacity_kg,
                "experience_level": request.experience_level,
                "cruise_speed_kn": request.cruise_speed_kn,
                "expected_return_at": _iso(start + timedelta(hours=duration_hours)),
            },
            "vessel_limits": limits, "timeline": timeline, "alerts": alerts,
            "offline_navigation": navigation,
            "cyclone_watch": {
                "gdacs_events": cyclone_events,
                "jtwc_headlines": cyclone_payload.get("jtwc", []),
                "sources_failed": cyclone_payload.get("sources_failed", []),
                "spatial_note": "GDACS point distances are informational; JTWC RSS headlines have no machine-readable track geometry in this integration.",
            },
            "return_decision": {"first_unsafe_at": first_unsafe["valid_at"] if first_unsafe else None, "return_before": return_deadline, "travel_buffer_hours": round((round_trip_hours / 2) + 2, 1) if round_trip_hours is not None else None, "reason": return_reason},
            "travel_assessment": travel,
            "fuel_assessment": fuel,
            "targets": {"species": request.target_fish, "fish_activity_status": "NOT_MODELLED", "reason": "No validated species-occurrence/catch model is installed; ORCA will not fabricate activity scores or expected catch."},
            "pre_departure_checklist": [
                "Download package and verify forecast_valid_until", "Confirm fuel plus reserve and engine condition",
                "Check lifejackets/PFDs for every person", "Test primary and backup communications",
                "Review official warnings, chart corrections and return route", "Share trip plan and expected return time with shore contact",
            ],
            "emergency_guidance": [
                "Follow the vessel emergency plan and skipper instructions", "Put on PFDs and account for all crew",
                "Use VHF Channel 16/distress equipment where applicable", "Transmit position, vessel identity, emergency and assistance required",
                "Do not abandon the vessel unless remaining aboard is more dangerous",
            ],
            "data_gaps": {
                "historical_analogue": "NOT_INTEGRATED", "tides": "NOT_INTEGRATED",
                "satellite_cloud_imagery": "NOT_INTEGRATED", "species_migration": "NOT_INTEGRATED",
                "pressure_fog_pattern_model": "NOT_INTEGRATED",
                "expected_catch_or_profit": "NOT_PREDICTED",
            },
            "sources": ["Open-Meteo Marine hourly forecast", "Open-Meteo Forecast hourly wind/gust", "GDACS tropical cyclone events", "JTWC RSS headlines"],
            "operational_note": "Decision support only. Re-check forecasts before departure and follow official warnings, charts, VTS and Coast Guard instructions.",
        }
        # UTF-8 canonical JSON contract is shared with the Flutter verifier.
        canonical = json.dumps(
            package, sort_keys=True, separators=(",", ":"), ensure_ascii=False
        ).encode("utf-8")
        package["package_sha256"] = hashlib.sha256(canonical).hexdigest()
        return package
