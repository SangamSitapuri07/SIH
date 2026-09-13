"""
ORCA Box — Event Hub
====================
In-process async pub/sub backbone for the live SSE stream.

Ingestion daemon (and any other producer) publishes events; every connected
SSE client gets its own subscriber queue. Slow consumers never block
producers: each queue is bounded and drops the *oldest* queued event when
full (telemetry favors recency over completeness).

Event taxonomy (all events carry `type`, `timestamp`, and `data`):
  - `telemetry`       — periodic system health / ingestion heartbeat
  - `data.updated`    — fresh snapshot ingested for a coordinate
  - `alert.push`      — safety-relevant change (verdict flip, cyclone, etc.)
"""

import asyncio
import time
from collections import deque
from typing import Any, AsyncIterator, Dict, List

_MAX_QUEUE_PER_CLIENT = 64


class EventHub:
    """Fan-out broadcast bus with per-subscriber bounded queues."""

    def __init__(self) -> None:
        self._subscribers: List[asyncio.Queue] = []
        self._recent: deque = deque(maxlen=128)  # replay buffer for diagnostics
        self._lock = asyncio.Lock()

    async def subscribe(self) -> asyncio.Queue:
        queue: asyncio.Queue = asyncio.Queue(maxsize=_MAX_QUEUE_PER_CLIENT)
        async with self._lock:
            self._subscribers.append(queue)
        return queue

    async def unsubscribe(self, queue: asyncio.Queue) -> None:
        async with self._lock:
            if queue in self._subscribers:
                self._subscribers.remove(queue)

    @property
    def subscriber_count(self) -> int:
        return len(self._subscribers)

    async def publish(self, event_type: str, data: Dict[str, Any]) -> None:
        """Broadcast one event to every subscriber (never blocks producers)."""
        event: Dict[str, Any] = {
            "type": event_type,
            "timestamp": int(time.time()),
            "data": data,
        }
        self._recent.append(event)

        async with self._lock:
            queues = list(self._subscribers)

        for queue in queues:
            if queue.full():
                try:
                    queue.get_nowait()  # drop oldest — recency over completeness
                except asyncio.QueueEmpty:
                    pass
            try:
                queue.put_nowait(event)
            except asyncio.QueueFull:  # pragma: no cover — defensive
                pass

    def recent_events(self, limit: int = 20) -> List[Dict[str, Any]]:
        """Latest published events (for /api/v1/events/recent diagnostics)."""
        return list(self._recent)[-limit:]


# Module-level singleton — shared by the stream route and the ingestion daemon.
event_hub = EventHub()
