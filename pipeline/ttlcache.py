"""Tiny in-process TTL (time-to-live) cache.

Why not pipeline/cache.py? That one is a persistent SQLite blob cache
built for 50 MB NetCDF downloads. The new Phase-4 modules (INCOIS PFZ
lines, JTWC cyclones, point forecasts) fetch small JSON/text responses
that expire in minutes-to-hours — a simple in-memory dict is the right
tool. Uvicorn runs one process, so module state is shared by every
HTTP request and WebSocket connection in that process.

Not for secrets, not for big data. Just "don't hammer the same public
server 10 times a minute".
"""
from __future__ import annotations

import threading
import time
from typing import Any, Callable, TypeVar

T = TypeVar("T")

_lock = threading.Lock()
_store: dict[str, tuple[float, Any]] = {}


def cached(key: str, ttl_sec: float, fn: Callable[[], T]) -> T:
    """Return cached value for `key` if fresh, else call fn() and cache it."""
    now = time.time()
    with _lock:
        ent = _store.get(key)
        if ent is not None and ent[0] > now:
            return ent[1]
    # Compute outside the lock so one slow fetch doesn't block readers
    value = fn()
    with _lock:
        _store[key] = (now + ttl_sec, value)
    return value


def cache_stats() -> dict[str, Any]:
    """Snapshot of what's cached — shown in the app's data-freshness panel."""
    now = time.time()
    with _lock:
        return {
            key: {"fresh_for_sec": round(exp - now)}
            for key, (exp, _v) in _store.items()
            if exp > now
        }
