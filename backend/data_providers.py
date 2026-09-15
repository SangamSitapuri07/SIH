import os
import time
import math
import html
import re
import threading
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from email.utils import parsedate_to_datetime
from typing import Dict, Any, List
import httpx
from gfw_provider import GfwProvider
from mosdac_provider import MosdacProvider
from marine_router import OfficialBoundaryStore, MarineRoutePlanner, haversine, bearing


class DataProvidersEngine:
    """
    Scientific Data Providers Engine for ORCA Box.
    Implements 12 external sources + 1 offline land mask with explicit health status,
    timeouts, retries, and honest provenance assembly.
    """

    def __init__(self):
        self.gfw = GfwProvider()
        self.mosdac = MosdacProvider()
        self.boundaries = OfficialBoundaryStore()
        self.route_planner = MarineRoutePlanner(self.boundaries)
        # TTL cache for zone snapshots: identical coordinates within the TTL
        # return instantly instead of re-hitting every upstream provider.
        self._snapshot_cache: Dict[str, Dict[str, Any]] = {}
        self._snapshot_cache_times: Dict[str, float] = {}
        self._snapshot_cache_lock = threading.Lock()
        self._snapshot_ttl_s = float(os.getenv("SNAPSHOT_CACHE_TTL_S", "600"))
        self.provider_status = {
            "open_meteo_marine": {"name": "Open-Meteo Marine (MFWAM/ECMWF)", "status": "UNVERIFIED", "latency_ms": None},
            "open_meteo_forecast": {"name": "Open-Meteo Forecast (ECMWF IFS)", "status": "UNVERIFIED", "latency_ms": None},
            "noaa_erddap": {"name": "NOAA CoastWatch ERDDAP (Chlorophyll-a)", "status": "UNVERIFIED", "latency_ms": None},
            "isro_mosdac": {
                "name": "ISRO MOSDAC OCM-3 (Oceansat-3)",
                "status": "CONFIGURED" if self.mosdac.credentials_configured else "CREDENTIAL_REQUIRED",
                "latency_ms": None,
                "reason": "Credentials configured; access has not been checked yet." if self.mosdac.credentials_configured else "Set MOSDAC_USERNAME and MOSDAC_PASSWORD to enable authenticated products.",
            },
            "incois_pfz": {"name": "INCOIS PFZ (GeoServer WFS)", "status": "UNVERIFIED", "latency_ms": None},
            "incois_las": {"name": "INCOIS Live Access Server", "status": "NOT_INTEGRATED", "latency_ms": None, "reason": "No verified LAS dataset contract is used by this build."},
            "gfw_ais": {
                "name": "Global Fishing Watch (AIS Effort)",
                "status": "CONFIGURED" if self.gfw.configured else "TOKEN_REQUIRED",
                "latency_ms": None,
                "reason": "Token configured; no GFW request has run yet." if self.gfw.configured else "Set GFW_API_TOKEN to enable AIS effort and fleet queries.",
            },
            "jtwc_cyclone": {"name": "JTWC US Navy Cyclone Warnings", "status": "UNVERIFIED", "latency_ms": None},
            "official_navigation_boundaries": {
                "name": "Official Navigation Boundaries (GeoJSON)",
                "status": self.boundaries.state.status,
                "latency_ms": None,
                "reason": self.boundaries.state.reason,
                "offline": True,
            },
        }

    def _record_provider(self, key: str, status: str, *, latency_ms: int | None = None,
                         reason: str | None = None, observed_at: str | None = None) -> None:
        item = self.provider_status[key]
        item.update(status=status, latency_ms=latency_ms, checked_at=int(time.time()))
        if reason:
            item["reason"] = reason
        else:
            item.pop("reason", None)
        if observed_at:
            item["observed_at"] = observed_at

    def check_health(self, probe: bool = False) -> Dict[str, Any]:
        """Return observed provider health, optionally running live probes.

        A normal read is fast and reports the latest real request state. The
        explicit Info-screen refresh uses ``probe=True`` to exercise the
        operational zone, GFW and cyclone paths rather than merely repeating
        configuration metadata.
        """
        if probe:
            def probe_zone() -> None:
                try:
                    self.fetch_zone_snapshot(18.92, 72.83, include_gfw=True)
                except Exception as exc:
                    # Individual providers normally return structured errors;
                    # this guard keeps diagnostics available for unexpected
                    # failures without claiming success.
                    self._record_provider("open_meteo_marine", "UNREACHABLE", reason=str(exc))
                    self._record_provider("open_meteo_forecast", "UNREACHABLE", reason=str(exc))

            def probe_cyclones() -> None:
                try:
                    self.fetch_cyclone_sources()
                except Exception as exc:
                    self._record_provider("jtwc_cyclone", "UNREACHABLE", reason=str(exc))

            def probe_mosdac() -> None:
                result = self.mosdac.check_access()
                raw_status = str(result.get("status", "unavailable")).upper()
                status = {
                    "CONNECTED": "CONNECTED",
                    "CREDENTIAL_REQUIRED": "CREDENTIAL_REQUIRED",
                    "AUTHENTICATION_FAILED": "AUTHENTICATION_FAILED",
                    "UNREACHABLE": "UNREACHABLE",
                }.get(raw_status, "UNAVAILABLE")
                self._record_provider(
                    "isro_mosdac", status,
                    latency_ms=result.get("latency_ms"),
                    reason=result.get("reason"),
                )

            with ThreadPoolExecutor(max_workers=3) as pool:
                futures = [
                    pool.submit(probe_zone),
                    pool.submit(probe_cyclones),
                    pool.submit(probe_mosdac),
                ]
                for future in futures:
                    future.result()

        usable = {"FRESH", "AVAILABLE", "CACHED", "CONNECTED"}
        core_ok = all(
            self.provider_status[key]["status"] in usable
            for key in ("open_meteo_marine", "open_meteo_forecast")
        )
        return {
            "status": "HEALTHY" if core_ok else "DEGRADED",
            "timestamp": int(time.time()),
            "version": "2.2.0",
            "data_sources": {key: dict(value) for key, value in self.provider_status.items()},
            "cache": {
                "active_entries": len(self._snapshot_cache),
                "ttl_seconds": self._snapshot_ttl_s,
            },
        }

    def _get(self, url: str, **kwargs: Any) -> httpx.Response:
        headers = kwargs.pop("headers", {})
        timeout_s = float(kwargs.pop("timeout_s", 3.0))
        headers.setdefault("User-Agent", "ORCA-Box/3.0 (SIH26176)")
        # Most metadata feeds fail fast. Large griddap services may need a
        # longer TLS/read window, supplied explicitly by their caller.
        with httpx.Client(timeout=timeout_s, headers=headers, follow_redirects=True) as client:
            response = client.get(url, **kwargs)
            response.raise_for_status()
            return response

    @staticmethod
    def _rss_items(text: str) -> List[Dict[str, Any]]:
        """Parse RSS items, tolerating JTWC's occasionally malformed CDATA."""
        try:
            root = ET.fromstring(text)
            return [
                {
                    "title": item.findtext("title"),
                    "link": item.findtext("link"),
                    "issued_at": item.findtext("pubDate"),
                }
                for item in root.findall(".//item")
            ]
        except ET.ParseError:
            # JTWC occasionally publishes HTML/CDATA that is not strict XML.
            # Recover only explicit RSS item fields; never synthesize alerts.
            items: List[Dict[str, Any]] = []
            for block in re.findall(r"<item\b[^>]*>(.*?)</item>", text, flags=re.I | re.S):
                def field(name: str) -> str | None:
                    match = re.search(
                        rf"<{name}\b[^>]*>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</{name}>",
                        block,
                        flags=re.I | re.S,
                    )
                    if not match:
                        return None
                    return html.unescape(re.sub(r"<[^>]+>", " ", match.group(1))).strip()
                items.append({"title": field("title"), "link": field("link"), "issued_at": field("pubDate")})
            if not items and "<rss" not in text.lower():
                raise
            return items

    def fetch_noaa_chlorophyll(self, lat: float, lon: float) -> Dict[str, Any]:
        """Read the nearest real VIIRS chlorophyll value from NOAA ERDDAP.

        ERDDAP's `.csv` response has a second units row, which the old parser
        attempted to convert to float and consequently rejected every valid
        response. The old ±0.02° range was also narrower than this dataset's
        ~0.083° grid and used ascending latitude against a descending axis.
        A coordinate-constrained JSON request lets ERDDAP select the nearest
        real grid cell and avoids both failure modes.
        """
        dataset = "noaacwNPPN20VIIRSDINEOFDaily"
        url = f"https://coastwatch.noaa.gov/erddap/griddap/{dataset}.json"
        query = f"?chlor_a[(last)][(0.0)][({lat:.5f})][({lon:.5f})]"
        started = time.perf_counter()
        try:
            response = self._get(url + query, timeout_s=15.0)
            payload = response.json()
            table = payload.get("table", {})
            columns = table.get("columnNames", [])
            rows = table.get("rows", [])
            chlorophyll_index = columns.index("chlor_a")
            values = []
            for row in rows:
                if not isinstance(row, list) or chlorophyll_index >= len(row):
                    continue
                try:
                    value = float(row[chlorophyll_index])
                except (TypeError, ValueError):
                    continue
                if math.isfinite(value) and value >= 0:
                    values.append(value)
            if not values:
                self._record_provider(
                    "noaa_erddap", "UNAVAILABLE",
                    latency_ms=round((time.perf_counter() - started) * 1000),
                    reason="Latest grid cell has no valid chlorophyll value (cloud/quality mask).",
                )
                return {
                    "status": "cloud_masked",
                    "source": "NOAA CoastWatch ERDDAP",
                    "reason": "Latest grid cell has no valid chlorophyll value",
                }
            observed_at = str(rows[0][0]) if rows and rows[0] else None
            self._record_provider(
                "noaa_erddap", "FRESH",
                latency_ms=round((time.perf_counter() - started) * 1000),
                observed_at=observed_at,
            )
            return {
                "status": "fresh",
                "value": values[0],
                "unit": "mg/m3",
                "source": "NOAA CoastWatch ERDDAP",
                "dataset": dataset,
                "source_url": url,
            }
        except (httpx.HTTPError, ValueError, KeyError, IndexError) as exc:
            self._record_provider(
                "noaa_erddap", "UNREACHABLE",
                latency_ms=round((time.perf_counter() - started) * 1000),
                reason=str(exc),
            )
            return {
                "status": "unreachable",
                "source": "NOAA CoastWatch ERDDAP",
                "reason": str(exc),
            }

    def fetch_incois_pfz(self) -> Dict[str, Any]:
        """Fetch official INCOIS PFZ lines when the government WFS is available."""
        url = "https://incois.gov.in/geoserver/PFZ_Automation/ows"
        params = {
            "service": "WFS",
            "version": "1.0.0",
            "request": "GetFeature",
            "typeName": "PFZ_Automation:pfzlines",
            "outputFormat": "application/json",
        }
        started = time.perf_counter()
        try:
            response = self._get(url, params=params)
            payload = response.json()
            self._record_provider(
                "incois_pfz", "FRESH",
                latency_ms=round((time.perf_counter() - started) * 1000),
            )
            return {
                "status": "fresh",
                "source": "INCOIS PFZ GeoServer",
                "dataset": "PFZ_Automation:pfzlines",
                "source_url": url,
                "features": payload.get("features", []),
            }
        except (httpx.HTTPError, ValueError, KeyError) as exc:
            self._record_provider(
                "incois_pfz", "UNREACHABLE",
                latency_ms=round((time.perf_counter() - started) * 1000),
                reason=str(exc),
            )
            return {"status": "unreachable", "source": "INCOIS PFZ GeoServer", "reason": str(exc)}

    def fetch_imd_cap_alerts(self) -> Dict[str, Any]:
        """Fetch current IMD CAP headlines; linked CAP XML is parsed later."""
        url = "https://cap-sources.s3.amazonaws.com/in-imd-en/rss.xml"
        try:
            root = ET.fromstring(self._get(url).text)
            alerts = []
            for item in root.findall(".//item"):
                alerts.append({
                    "title": item.findtext("title"),
                    "link": item.findtext("link"),
                    "issued_at": item.findtext("pubDate"),
                    "source": "IMD CAP",
                })
            return {"status": "fresh", "source": "IMD CAP", "source_url": url, "alerts": alerts}
        except (httpx.HTTPError, ET.ParseError) as exc:
            return {"status": "unreachable", "source": "IMD CAP", "reason": str(exc)}

    def fetch_cyclone_sources(self) -> Dict[str, Any]:
        """Fetch GDACS cyclone events and JTWC corroborating headlines."""
        gdacs_url = "https://www.gdacs.org/gdacsapi/api/events/geteventlist/SEARCH?eventlist=TC&bbox=60,0,100,30"
        jtwc_url = "https://www.metoc.navy.mil/jtwc/rss/jtwc.rss"
        result: Dict[str, Any] = {"gdacs": [], "jtwc": [], "sources_failed": []}
        try:
            result["gdacs"] = self._get(gdacs_url).json().get("features", [])
        except (httpx.HTTPError, ValueError) as exc:
            result["sources_failed"].append({"source": "GDACS", "reason": str(exc)})
        jtwc_started = time.perf_counter()
        try:
            response = self._get(jtwc_url, timeout_s=15.0)
            parsed_items = self._rss_items(response.text)
            result["jtwc"] = [
                {**item, "source": "JTWC"}
                for item in parsed_items
            ]
            latest_time = next((item.get("issued_at") for item in parsed_items if item.get("issued_at")), None)
            if latest_time:
                try:
                    latest_time = parsedate_to_datetime(latest_time).isoformat()
                except (TypeError, ValueError):
                    latest_time = None
            self._record_provider(
                "jtwc_cyclone", "AVAILABLE",
                latency_ms=round((time.perf_counter() - jtwc_started) * 1000),
                observed_at=latest_time,
            )
        except (httpx.HTTPError, ET.ParseError) as exc:
            self._record_provider(
                "jtwc_cyclone", "UNREACHABLE",
                latency_ms=round((time.perf_counter() - jtwc_started) * 1000),
                reason=str(exc),
            )
            result["sources_failed"].append({"source": "JTWC", "reason": str(exc)})
        return result

    def is_land(self, lat: float, lon: float) -> bool | None:
        """Return False only for authority-verified navigable water.

        Unknown is represented by None; the previous hand-written Mumbai and
        Gujarat boxes were not a land-mask dataset and were unsafe to report as
        GLOBE verification.
        """
        allowed, _ = self.boundaries.classify(lat, lon)
        return None if allowed is None else not allowed

    def fetch_zone_snapshot(self, lat: float, lon: float, include_gfw: bool = False) -> Dict[str, Any]:
        """Fetch live marine and forecast observations for a coordinate.

        Results are cached per (lat, lon) for SNAPSHOT_CACHE_TTL_S seconds
        (default 10 min) — repeat requests within the window are served from
        memory in microseconds instead of re-fetching all upstream sources.
        """
        now_ts = int(time.time())
        on_land = self.is_land(lat, lon)

        if on_land:
            return {
                "error": True,
                "reason": "Selected coordinates are on land.",
                "latitude": lat,
                "longitude": lon
            }

        cache_key = f"{round(lat, 2)}_{round(lon, 2)}_{bool(include_gfw)}"
        with self._snapshot_cache_lock:
            cached_ts = self._snapshot_cache_times.get(cache_key)
            if cached_ts is not None and (now_ts - cached_ts) < self._snapshot_ttl_s:
                return dict(self._snapshot_cache[cache_key])

        marine_url = "https://marine-api.open-meteo.com/v1/marine"
        forecast_url = "https://api.open-meteo.com/v1/forecast"
        marine_params = {
            "latitude": lat,
            "longitude": lon,
            "current": "wave_height,wave_period,wind_wave_height,wind_wave_direction,swell_wave_height,swell_wave_period,ocean_current_velocity,ocean_current_direction,sea_surface_temperature",
            "hourly": "wave_height,wave_period,swell_wave_height,swell_wave_period",
            "forecast_days": 3,
            "timezone": "UTC",
        }
        forecast_params = {
            "latitude": lat,
            "longitude": lon,
            "current": "wind_speed_10m,wind_gusts_10m",
            "hourly": "wind_speed_10m,wind_gusts_10m",
            "forecast_days": 3,
            "wind_speed_unit": "kn",
            "timezone": "UTC",
        }

        try:
            started = time.perf_counter()
            # These two calls are independent — running them concurrently
            # instead of one-after-the-other roughly halves this endpoint's
            # latency (was ~8.5s serial, now ~= the slower single call).
            with httpx.Client(timeout=12.0) as client, ThreadPoolExecutor(max_workers=2) as pool:
                marine_future = pool.submit(client.get, marine_url, params=marine_params)
                forecast_future = pool.submit(client.get, forecast_url, params=forecast_params)
                marine_response = marine_future.result()
                forecast_response = forecast_future.result()
            marine_response.raise_for_status()
            forecast_response.raise_for_status()
            marine = marine_response.json().get("current", {})
            forecast_payload = forecast_response.json()
            forecast = forecast_payload.get("current", {})
            hourly = forecast_payload.get("hourly", {})
            wave_height = marine.get("wave_height")
            wave_period = marine.get("wave_period")
            wind_speed_kn = forecast.get("wind_speed_10m")
            wind_gust_kn = forecast.get("wind_gusts_10m")
            sst_celsius = marine.get("sea_surface_temperature")
            current_kn = marine.get("ocean_current_velocity")
            if current_kn is not None:
                current_kn = current_kn / 1.852
            if any(value is None for value in (wave_height, wind_speed_kn, wind_gust_kn)):
                raise ValueError("Open-Meteo returned incomplete live marine data")
            latency_ms = round((time.perf_counter() - started) * 1000)
            self._record_provider(
                "open_meteo_marine", "FRESH", latency_ms=latency_ms,
                observed_at=marine.get("time"),
            )
            self._record_provider(
                "open_meteo_forecast", "FRESH", latency_ms=latency_ms,
                observed_at=forecast.get("time"),
            )
        except (httpx.HTTPError, ValueError, KeyError) as exc:
            failed_latency = round((time.perf_counter() - started) * 1000)
            self._record_provider("open_meteo_marine", "UNREACHABLE", latency_ms=failed_latency, reason=str(exc))
            self._record_provider("open_meteo_forecast", "UNREACHABLE", latency_ms=failed_latency, reason=str(exc))
            return {
                "error": True,
                "reason": f"Live marine data unavailable: {exc}",
                "latitude": lat,
                "longitude": lon,
            }

        # Secondary sources (NOAA, INCOIS, GFW) each have their own bounded
        # timeout — run them concurrently instead of serially (was up to ~30s
        # worst case, now ~= the slowest single source).
        with ThreadPoolExecutor(max_workers=4) as pool:
            futures = {
                "chlorophyll": pool.submit(self.fetch_noaa_chlorophyll, lat, lon),
                "pfz": pool.submit(self.fetch_incois_pfz),
            }
            if include_gfw:
                futures["gfw_effort"] = pool.submit(self.gfw.fetch_effort, lat, lon)
                futures["gfw_fleet"] = pool.submit(self.gfw.fetch_fishing_vessels_in_region, lat, lon)

            chlorophyll = futures["chlorophyll"].result()
            pfz = futures["pfz"].result()
            gfw_effort = futures["gfw_effort"].result() if "gfw_effort" in futures else {"status": "not_requested", "source": "Global Fishing Watch"}
            gfw_fleet = futures["gfw_fleet"].result() if "gfw_fleet" in futures else {"status": "not_requested", "source": "Global Fishing Watch"}
        if include_gfw:
            gfw_statuses = {str(gfw_effort.get("status")), str(gfw_fleet.get("status"))}
            if gfw_statuses.intersection({"fresh", "cached"}):
                self._record_provider("gfw_ais", "FRESH" if "fresh" in gfw_statuses else "CACHED")
            else:
                reason = str(gfw_effort.get("error") or gfw_fleet.get("error") or "GFW returned no usable result")
                if "token_required" in gfw_statuses:
                    status = "TOKEN_REQUIRED"
                elif "authentication_failed" in gfw_statuses or "permission_denied" in gfw_statuses:
                    status = "AUTHENTICATION_FAILED"
                elif "rate_limited" in gfw_statuses:
                    status = "RATE_LIMITED"
                else:
                    status = "UNAVAILABLE"
                self._record_provider("gfw_ais", status, reason=reason)
        sources_used = [
            {"name": "Open-Meteo Marine", "dataset": "Live marine current", "latency_ms": latency_ms, "status": "FRESH"},
            {"name": "Open-Meteo Forecast", "dataset": "Live ECMWF forecast current", "latency_ms": latency_ms, "status": "FRESH"},
        ]
        sources_failed = []
        if chlorophyll.get("status") == "fresh":
            sources_used.append({"name": chlorophyll["source"], "dataset": chlorophyll["dataset"], "status": "FRESH"})
        else:
            sources_failed.append(chlorophyll)
        if pfz.get("status") == "fresh":
            sources_used.append({"name": pfz["source"], "dataset": pfz["dataset"], "status": "FRESH"})
        else:
            sources_failed.append(pfz)
        for gfw_result, label in ((gfw_effort, "fishing effort"), (gfw_fleet, "fleet")):
            if gfw_result.get("status") in {"fresh", "cached"}:
                sources_used.append({"name": f"{gfw_result['source']} ({label})", "dataset": gfw_result["dataset"], "status": gfw_result["status"].upper()})
            elif include_gfw:
                sources_failed.append(gfw_result)

        result = {
            "latitude": lat,
            "longitude": lon,
            "timestamp": now_ts,
            "on_land": on_land,
            "variables": {
                "wave_height_m": wave_height,
                "wave_period_s": wave_period,
                "swell_height_m": marine.get("swell_wave_height"),
                "swell_period_s": marine.get("swell_wave_period"),
                "wind_speed_kn": wind_speed_kn,
                "wind_gust_kn": wind_gust_kn,
                "wind_direction_deg": forecast.get("wind_direction_10m"),
                "sst_celsius": sst_celsius,
                "current_speed_kn": current_kn,
                "current_direction_deg": marine.get("ocean_current_direction"),
                "chlorophyll_mg_m3": chlorophyll.get("value"),
                "fishing_effort_hours": gfw_effort.get("hours"),
                "fishing_vessel_ids": gfw_effort.get("vessel_ids"),
                "fleet_vessel_count": gfw_fleet.get("vessel_count"),
                "fleet_by_flag": gfw_fleet.get("by_flag", {}),
                "fleet_by_gear": gfw_fleet.get("by_gear", {}),
                "gfw_start_date": gfw_effort.get("start_date") or gfw_fleet.get("start_date"),
                "gfw_end_date": gfw_effort.get("end_date") or gfw_fleet.get("end_date"),
            },
            "hourly_forecast": {
                "time": hourly.get("time", []),
                "wave_height_m": marine_response.json().get("hourly", {}).get("wave_height", []),
                "wind_speed_kn": hourly.get("wind_speed_10m", []),
                "wind_gust_kn": hourly.get("wind_gusts_10m", []),
            },
            "pfz": pfz.get("features", []),
            "sources_used": sources_used,
            "sources_failed": sources_failed
        }

        with self._snapshot_cache_lock:
            self._snapshot_cache[cache_key] = result
            self._snapshot_cache_times[cache_key] = now_ts
        return result

    def verify_route(self, from_lat: float, from_lon: float, to_lat: float, to_lon: float) -> Dict[str, Any]:
        """Plan a fail-closed path through official navigable polygons."""
        start = (from_lat, from_lon)
        end = (to_lat, to_lon)
        plan = self.route_planner.plan(start, end)
        boundary_state = self.boundaries.state
        self.provider_status["official_navigation_boundaries"].update(
            status=boundary_state.status,
            reason=boundary_state.reason,
            checked_at=int(time.time()),
        )
        route = plan.get("routes", [None])[0] if plan.get("routes") else None
        legs = route["coordinates"] if route else [[from_lat, from_lon], [to_lat, to_lon]]
        distance_km = route.get("distance_km") if route else round(haversine(start, end), 1)
        return {
            "ok": True if plan.get("verified") and route else None,
            "land_hit": None if not plan.get("verified") else not bool(route),
            "distance_km": distance_km,
            "distance_nm": route.get("distance_nm") if route else round(distance_km * 0.539957, 1),
            "bearing_deg": round(bearing(start, end), 1),
            "legs": legs,
            "detour": bool(route and len(legs) > 2),
            "reason": plan["reason"],
            "status": plan["status"],
            "regulatory_verified": plan.get("regulatory_verified", False),
            "alternatives": plan.get("routes", []),
            "boundary": plan.get("boundary"),
            "sources": [self.boundaries.state.metadata.get("authority")] if self.boundaries.state.ready else [],
        }
