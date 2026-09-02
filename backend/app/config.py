"""Application configuration.

All values can be overridden via environment variables. For the hackathon
prototype we keep things simple — no secrets, no API keys required for the
mock paths. Open-Meteo (weather) is the only live free API we use.
"""
from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    app_name: str = "ORCA Marine Intelligence Platform"
    version: str = "0.1.0"

    # Live free data sources (no key required)
    open_meteo_marine_url: str = "https://marine-api.open-meteo.com/v1/marine"
    open_meteo_weather_url: str = "https://api.open-meteo.com/v1/forecast"

    # Where our mock INCOIS-like data lives. In production this would
    # be swapped for the real INCOIS API client.
    mock_incois_path: str = os.path.join(
        os.path.dirname(__file__), "data", "mock_incois.py"
    )

    # Real-time stream settings
    enable_websocket_stream: bool = True


settings = Settings()
