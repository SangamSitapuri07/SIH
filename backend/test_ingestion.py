"""Tests for the proactive ingestion daemon and SSE event hub."""

import asyncio
import unittest

from event_hub import EventHub
from ingestion import IngestionDaemon


def _snapshot(wave=1.0, wind=8.0, gust=12.0):
    return {
        "latitude": 18.92,
        "longitude": 72.83,
        "timestamp": 1,
        "variables": {
            "wave_height_m": wave,
            "wave_period_s": 6.0,
            "wind_speed_kn": wind,
            "wind_gust_kn": gust,
            "sst_celsius": 28.0,
            "chlorophyll_mg_m3": None,
        },
        "hourly_forecast": {"time": [], "wave_height_m": [], "wind_speed_kn": []},
        "sources_used": [],
        "sources_failed": [],
        "pfz": [],
    }


class FakeProviders:
    def __init__(self, snapshots=None, cyclones=None):
        self.snapshots = snapshots or [_snapshot()]
        self.cyclones = cyclones or {"gdacs": [], "jtwc": [], "sources_failed": []}
        self.snapshot_calls = 0

    def fetch_zone_snapshot(self, lat, lon, include_gfw=False):
        self.snapshot_calls += 1
        snap = dict(self.snapshots[min(self.snapshot_calls - 1, len(self.snapshots) - 1)])
        snap["latitude"] = lat
        snap["longitude"] = lon
        return snap

    def fetch_cyclone_sources(self):
        return self.cyclones


class EventHubTests(unittest.TestCase):
    def test_publish_fans_out_to_all_subscribers(self):
        async def run():
            hub = EventHub()
            q1 = await hub.subscribe()
            q2 = await hub.subscribe()
            await hub.publish("data.updated", {"latitude": 1.0})
            ev1 = await asyncio.wait_for(q1.get(), timeout=1)
            ev2 = await asyncio.wait_for(q2.get(), timeout=1)
            self.assertEqual(ev1["type"], "data.updated")
            self.assertEqual(ev2["type"], "data.updated")
            await hub.unsubscribe(q1)
            await hub.unsubscribe(q2)
            self.assertEqual(hub.subscriber_count, 0)

        asyncio.new_event_loop().run_until_complete(run())

    def test_slow_subscriber_drops_oldest_not_newest(self):
        async def run():
            hub = EventHub()
            q = await hub.subscribe()
            for i in range(70):  # exceed the 64-cap
                await hub.publish("telemetry", {"seq": i})
            # Oldest dropped: first event seen must be seq=6, newest seq=69.
            first = await asyncio.wait_for(q.get(), timeout=1)
            self.assertEqual(first["data"]["seq"], 6)
            self.assertEqual(q.qsize(), 63)

        asyncio.new_event_loop().run_until_complete(run())


class IngestionDaemonTests(unittest.TestCase):
    def _daemon(self, providers, **kwargs):
        kwargs.setdefault("advisory_cache", {})
        kwargs.setdefault("advisory_cache_times", {})
        return IngestionDaemon(
            providers_engine=providers,
            agents_engine=None,
            **kwargs,
        )

    def test_verdict_flip_up_publishes_alert(self):
        async def run():
            # Sequence: GOOD -> CAUTION -> NO-GO
            providers = FakeProviders(
                snapshots=[_snapshot(1.0, 8.0, 12.0), _snapshot(3.0, 8.0, 12.0), _snapshot(5.0, 8.0, 40.0)]
            )
            daemon = self._daemon(providers, poll_interval_s=0.1)

            received = []
            q = await asyncio.get_event_loop().create_task(_noop()) if False else None
            from event_hub import event_hub as global_hub
            import ingestion

            # Use the global hub the daemon publishes through.
            sub = await global_hub.subscribe()
            daemon.watch(18.92, 72.83)
            await daemon._ingest_coordinate({"lat": 18.92, "lon": 72.83, "label": "t"}, {})
            await daemon._ingest_coordinate({"lat": 18.92, "lon": 72.83, "label": "t"}, {})
            await daemon._ingest_coordinate({"lat": 18.92, "lon": 72.83, "label": "t"}, {})

            while not sub.empty():
                received.append(await sub.get())

            types = [e["type"] for e in received]
            self.assertIn("alert.push", types)
            alerts = [e for e in received if e["type"] == "alert.push"]
            self.assertEqual(len(alerts), 2)  # GOOD->CAUTION, CAUTION->NO-GO
            self.assertEqual(alerts[0]["data"]["from_verdict"], "GOOD")
            self.assertEqual(alerts[0]["data"]["to_verdict"], "CAUTION")
            self.assertEqual(alerts[1]["data"]["to_verdict"], "NO-GO")
            self.assertEqual(alerts[1]["data"]["severity"], "critical")

        asyncio.new_event_loop().run_until_complete(run())

    def test_recovery_flip_does_not_alert(self):
        async def run():
            providers = FakeProviders(snapshots=[_snapshot(5.0, 8.0, 40.0), _snapshot(1.0, 8.0, 12.0)])
            daemon = self._daemon(providers, poll_interval_s=0.1)

            from event_hub import event_hub as global_hub

            sub = await global_hub.subscribe()
            daemon.watch(18.92, 72.83)
            await daemon._ingest_coordinate({"lat": 18.92, "lon": 72.83, "label": "t"}, {})
            await daemon._ingest_coordinate({"lat": 18.92, "lon": 72.83, "label": "t"}, {})

            alerts = []
            while not sub.empty():
                ev = await sub.get()
                if ev["type"] == "alert.push":
                    alerts.append(ev)
            self.assertEqual(len(alerts), 0)  # NO-GO -> GOOD must stay silent

        asyncio.new_event_loop().run_until_complete(run())

    def test_cyclone_alerts_only_for_new_events(self):
        async def run():
            gdacs = {
                "gdacs": [
                    {"properties": {"eventid": "TC-100", "eventname": "CYCLONE-A", "alertlevel": "Orange"}},
                    {"properties": {"eventid": "TC-200", "eventname": "CYCLONE-B", "alertlevel": "Red"}},
                ],
                "jtwc": [],
                "sources_failed": [],
            }
            providers = FakeProviders(cyclones=gdacs)
            daemon = self._daemon(providers, poll_interval_s=0.1)

            from event_hub import event_hub as global_hub

            sub = await global_hub.subscribe()

            await daemon._check_cyclones()  # baseline pass — no alerts
            baseline_alerts = [e for e in list(sub._queue) if e["type"] == "alert.push"]
            self.assertEqual(len(baseline_alerts), 0)

            # Add a brand-new cyclone.
            gdacs["gdacs"].append({"properties": {"eventid": "TC-300", "eventname": "CYCLONE-C", "alertlevel": "Red"}})
            await daemon._check_cyclones()
            alerts = []
            while not sub.empty():
                ev = await sub.get()
                if ev["type"] == "alert.push":
                    alerts.append(ev)
            self.assertEqual(len(alerts), 1)
            self.assertEqual(alerts[0]["data"]["event_id"], "TC-300")

        asyncio.new_event_loop().run_until_complete(run())

    def test_advisory_cache_invalidated_after_ingest(self):
        async def run():
            advisory_cache = {(18.92, 72.83, False): {"old": True}}
            advisory_times = {(18.92, 72.83, False): 12345.0}
            providers = FakeProviders()
            daemon = self._daemon(
                providers,
                poll_interval_s=0.1,
                advisory_cache=advisory_cache,
                advisory_cache_times=advisory_times,
            )
            daemon.watch(18.92, 72.83)
            await daemon._ingest_coordinate({"lat": 18.92, "lon": 72.83, "label": "t"}, {})
            self.assertNotIn((18.92, 72.83, False), advisory_cache)
            self.assertNotIn((18.92, 72.83, False), advisory_times)

        asyncio.new_event_loop().run_until_complete(run())


async def _noop():
    return None


if __name__ == "__main__":
    unittest.main()
