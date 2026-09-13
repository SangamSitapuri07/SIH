"""
ORCA Box — Proactive Ingestion Daemon
=====================================
Turns ORCA Box from a passive request-scoped server into a proactive
edge-intelligence node. A background asyncio loop continuously ingests data
for watched coordinates, updates the advisory caches, and broadcasts real
SSE events (`data.updated`, `alert.push`, `telemetry`) through the EventHub.

Design constraints honored:
  - No cloud dependency: everything runs on the edge box.
  - Never blocks the API: the daemon runs as its own asyncio task; blocking
    provider work is offloaded to a thread via asyncio.to_thread.
  - Alerting is edge-conservative: only flips that *increase* risk wake the
    fisherman. Recovery flips are broadcast as data.updated only.
"""

import asyncio
import logging
import time
from typing import Any, Dict, List, Optional, Set

from event_hub import event_hub

logger = logging.getLogger("orca.ingestion")

_VERDICT_ORDER = {"GOOD": 0, "CAUTION": 1, "NO-GO": 2}


class IngestionDaemon:
    def __init__(
        self,
        providers_engine: Any,
        agents_engine: Any,
        poll_interval_s: float = 600.0,
        cyclone_interval_s: float = 1800.0,
        advisory_cache: Optional[dict] = None,
        advisory_cache_times: Optional[dict] = None,
        route_advisory_fn: Optional[Any] = None,
    ) -> None:
        self.providers = providers_engine
        self.agents = agents_engine
        self.poll_interval_s = poll_interval_s
        self.cyclone_interval_s = cyclone_interval_s
        self._advisory_cache = advisory_cache if advisory_cache is not None else {}
        self._advisory_cache_times = advisory_cache_times if advisory_cache_times is not None else {}
        self._route_advisory_fn = route_advisory_fn

        self._watched: Dict[str, Dict[str, Any]] = {}  # key -> {"lat","lon","label"}
        self._last_verdicts: Dict[str, str] = {}
        self._last_cyclone_ids: Set[str] = set()
        self._cyclone_seeded = False
        self._task: Optional[asyncio.Task] = None
        self._running = False
        self._last_tick_stats: Dict[str, Any] = {}

    # ------------------------------------------------------------- watchlist

    def watch(self, lat: float, lon: float, label: str = "") -> str:
        """Register a coordinate for proactive ingestion. Returns the key."""
        key = f"{round(lat, 2)}_{round(lon, 2)}"
        self._watched[key] = {"lat": round(lat, 2), "lon": round(lon, 2), "label": label}
        return key

    def unwatch(self, lat: float, lon: float) -> None:
        self._watched.pop(f"{round(lat, 2)}_{round(lon, 2)}", None)

    @property
    def watched_keys(self) -> List[str]:
        return list(self._watched.keys())

    # ------------------------------------------------------------ lifecycle

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._task = asyncio.get_event_loop().create_task(self._run())

    async def stop(self) -> None:
        self._running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

    # ------------------------------------------------------------ main loop

    async def _run(self) -> None:
        logger.info(
            "Ingestion daemon started (poll=%.0fs, cyclone=%.0fs)",
            self.poll_interval_s,
            self.cyclone_interval_s,
        )
        while self._running:
            started = time.monotonic()
            try:
                await self._tick()
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # daemon must never die
                logger.exception("Ingestion tick failed: %s", exc)

            elapsed = time.monotonic() - started
            sleep_s = max(5.0, self.poll_interval_s - elapsed)
            await asyncio.sleep(sleep_s)

    async def _tick(self) -> None:
        loop_stats: Dict[str, Any] = {
            "coordinates_polled": 0,
            "data_updated_events": 0,
            "alerts_pushed": 0,
            "errors": 0,
        }

        cyclone_task = asyncio.create_task(self._check_cyclones())

        for key, coord in list(self._watched.items()):
            try:
                await self._ingest_coordinate(coord, loop_stats)
                loop_stats["coordinates_polled"] += 1
            except Exception as exc:
                loop_stats["errors"] += 1
                logger.warning("Ingest failed for %s: %s", key, exc)
                await event_hub.publish(
                    "telemetry",
                    {
                        "category": "ingestion_error",
                        "coordinate": key,
                        "reason": str(exc)[:200],
                    },
                )

        await cyclone_task
        self._last_tick_stats = {**loop_stats, "at": int(time.time())}

    async def _ingest_coordinate(self, coord: Dict[str, Any], loop_stats: Dict[str, Any]) -> None:
        lat, lon = coord["lat"], coord["lon"]

        # Blocking network work happens off the event loop.
        snap = await asyncio.to_thread(self.providers.fetch_zone_snapshot, lat, lon)
        if snap.get("error"):
            raise RuntimeError(snap.get("reason", "snapshot error"))

        verdict = self._deterministic_verdict(snap)
        now = int(time.time())
        key = f"{round(lat, 2)}_{round(lon, 2)}"

        # 1. Always broadcast fresh data.
        await event_hub.publish(
            "data.updated",
            {
                "latitude": lat,
                "longitude": lon,
                "label": coord.get("label", ""),
                "verdict": verdict,
                "wave_height_m": snap["variables"].get("wave_height_m"),
                "wind_speed_kn": snap["variables"].get("wind_speed_kn"),
                "wind_gust_kn": snap["variables"].get("wind_gust_kn"),
                "ingested_at": now,
            },
        )
        loop_stats.setdefault("data_updated_events", 0)
        loop_stats["data_updated_events"] += 1

        # 2. Risk-increase flips become alerts.
        previous = self._last_verdicts.get(key)
        self._last_verdicts[key] = verdict
        if previous is not None and _VERDICT_ORDER[verdict] > _VERDICT_ORDER[previous]:
            wave_txt = snap["variables"].get("wave_height_m")
            gust_txt = snap["variables"].get("wind_gust_kn")
            label = coord.get("label") or f"{lat:.2f}, {lon:.2f}"
            await event_hub.publish(
                "alert.push",
                {
                    # AlertDto-compatible fields (app renders these directly)
                    "id": f"alert-{now}-{key}",
                    "severity": "critical" if verdict == "NO-GO" else "warning",
                    "title": self._verdict_headline(verdict),
                    "title_hi": self._verdict_headline_hi(verdict),
                    "message": (
                        f"Sea state worsened at {label}: waves {wave_txt} m, "
                        f"gusts {gust_txt} kn. Previous status: {previous}."
                    ),
                    "message_hi": (
                        f"{label} पर समुद्र की स्थिति बिगड़ी: लहरें {wave_txt} मीटर, "
                        f"झोंके {gust_txt} समुद्री मील। पहले की स्थिति: {previous}."
                    ),
                    "source": "ORCA Ingestion",
                    "issued_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
                    "affected_area": label,
                    "is_active": True,
                    # Extra context for power clients
                    "category": "verdict_change",
                    "latitude": lat,
                    "longitude": lon,
                    "from_verdict": previous,
                    "to_verdict": verdict,
                },
            )
            loop_stats.setdefault("alerts_pushed", 0)
            loop_stats["alerts_pushed"] += 1

        # 3. Refresh the advisory response cache with the new snapshot.
        self._refresh_advisory_cache(lat, lon, snap, verdict)

    def _deterministic_verdict(self, snap: Dict[str, Any]) -> str:
        """Same worst-case fold as the Marine Risk agent — no LLM needed."""
        variables = snap.get("variables", {})
        wave_h = variables.get("wave_height_m")
        wind_kn = variables.get("wind_speed_kn")
        gust_kn = variables.get("wind_gust_kn")
        if wave_h is None or wind_kn is None or gust_kn is None:
            return "CAUTION"  # conservative on incomplete data
        if wave_h >= 4.0 or gust_kn >= 34.0:
            return "NO-GO"
        if wave_h >= 2.5 or wind_kn >= 20.0:
            return "CAUTION"
        return "GOOD"

    def _verdict_headline(self, verdict: str) -> str:
        return {
            "GOOD": "Conditions improved — safe to sail",
            "CAUTION": "Caution advised — moderate sea",
            "NO-GO": "DANGER — do not go to sea",
        }.get(verdict, verdict)

    def _verdict_headline_hi(self, verdict: str) -> str:
        return {
            "GOOD": "स्थिति सुधरी — जाना सुरक्षित है",
            "CAUTION": "सावधानी बरतें — मध्यम समुद्र",
            "NO-GO": "खतरा — समुद्र में न जाएं",
        }.get(verdict, verdict)

    async def _check_cyclones(self) -> None:
        """Broadcast an alert for each *new* GDACS/JTWC cyclone event."""
        try:
            result = await asyncio.to_thread(self.providers.fetch_cyclone_sources)
        except Exception as exc:
            logger.warning("Cyclone check failed: %s", exc)
            return

        gdacs_events = result.get("gdacs", [])
        current_ids: Set[str] = set()
        for feature in gdacs_events:
            props = feature.get("properties", {}) or {}
            event_id = str(props.get("eventid") or props.get("eventname") or props.get("alertlevel", ""))
            if not event_id:
                continue
            current_ids.add(event_id)
            if not self._cyclone_seeded:
                continue  # first pass: baseline, no alert storm
            if event_id in self._last_cyclone_ids:
                continue
            name = props.get("eventname", "Cyclone")
            level = props.get("alertlevel", "")
            await event_hub.publish(
                "alert.push",
                {
                    # AlertDto-compatible fields (app renders these directly)
                    "id": f"alert-{int(time.time())}-cyclone-{event_id}",
                    "severity": "critical",
                    "title": f"Cyclone alert: {name} ({level})",
                    "title_hi": f"चक्रवात चेतावनी: {name} ({level})",
                    "message": (
                        f"Tropical system '{name}' is active in the region "
                        f"(alert level {level}). Return to harbour and postpone trips."
                    ),
                    "message_hi": (
                        f"क्षेत्र में चक्रवाती तूफ़ान '{name}' सक्रिय है "
                        f"(चेतावनी स्तर {level})। बंदरगाह लौटें और यात्रा स्थगित करें।"
                    ),
                    "source": "GDACS / JTWC",
                    "issued_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "affected_area": "Region-wide",
                    "is_active": True,
                    # Extra context for power clients
                    "category": "cyclone",
                    "event_id": event_id,
                    "event_name": name,
                    "alert_level": level,
                },
            )

        self._last_cyclone_ids = current_ids
        self._cyclone_seeded = True

    def _refresh_advisory_cache(self, lat: float, lon: float, snap: dict, verdict: str) -> None:
        """Keep the advisory response cache aligned with ingested data.

        Just invalidates the response-cache entry; the next app request
        rebuilds it from the (already-cached) snapshot — cheap and simple.
        """
        self._advisory_cache.pop((round(lat, 2), round(lon, 2), False), None)
        self._advisory_cache_times.pop((round(lat, 2), round(lon, 2), False), None)

    def status(self) -> Dict[str, Any]:
        return {
            "running": self._running,
            "poll_interval_s": self.poll_interval_s,
            "cyclone_interval_s": self.cyclone_interval_s,
            "watched": [
                {"key": k, **coord} for k, coord in self._watched.items()
            ],
            "last_verdicts": dict(self._last_verdicts),
            "last_tick": self._last_tick_stats,
        }
