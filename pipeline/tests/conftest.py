"""Shared test helpers — network gating for live-API tests."""
import socket

import pytest


def _network_up(host: str = "marine-api.open-meteo.com", port: int = 443, timeout: float = 4.0) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


requires_network = pytest.mark.skipif(
    not _network_up(),
    reason="live network/API unreachable from this machine — skipping live test",
)
