"""Weather agent — pulls live marine + weather data from Open-Meteo.

Open-Meteo is genuinely free, requires no API key, and gives us:
  * Wave height, period, direction (marine API)
  * Wind speed, gusts, temperature, precipitation (forecast API)

This is the only "real" live data source in the prototype. The rest is mocked
realistically so the demo always works even without internet.
"""
from __future__ import annotations

import asyncio
import logging

import httpx

from app.config import settings

from .base import AgentContext, AgentResult, BaseAgent

log = logging.getLogger(__name__)


class WeatherAgent(BaseAgent):
    name = "weather"

    def __init__(self, timeout: float = 5.0) -> None:
        self.timeout = timeout

    async def _fetch(self, lat: float, lon: float) -> dict:
        """Pull wave + wind in parallel from Open-Meteo."""
        marine_params = {
            "latitude": lat,
            "longitude": lon,
            "current": "wave_height,wave_direction,wave_period,sea_surface_temperature",
            "timezone": "auto",
        }
        weather_params = {
            "latitude": lat,
            "longitude": lon,
            "current": "temperature_2m,wind_speed_10m,wind_gusts_10m,precipitation",
            "timezone": "auto",
        }
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            marine, weather = await asyncio.gather(
                client.get(settings.open_meteo_marine_url, params=marine_params),
                client.get(settings.open_meteo_weather_url, params=weather_params),
            )
            marine.raise_for_status()
            weather.raise_for_status()
            return {
                "marine": marine.json().get("current", {}),
                "weather": weather.json().get("current", {}),
            }

    async def run(self, ctx: AgentContext) -> AgentResult:
        # Default to a point off the Konkan coast (Mumbai-ish) if no user location.
        lat, lon = ctx.user_location or (18.9, 72.8)

        try:
            data = await self._fetch(lat, lon)
            wave_h = data["marine"].get("wave_height")
            wind = data["weather"].get("wind_speed_10m")
            sst = data["marine"].get("sea_surface_temperature")
            summary = (
                f"Live conditions at ({lat:.2f}, {lon:.2f}): "
                f"wave height {wave_h} m, wind {wind} km/h, SST {sst} °C"
            )
            return AgentResult(
                agent_name=self.name,
                summary=summary,
                confidence=0.95,
                data_sources=["Open-Meteo Marine API", "Open-Meteo Forecast API"],
                payload={"lat": lat, "lon": lon, "data": data},
            )
        except Exception as exc:
            log.warning("Weather agent fell back to mock: %s", exc)
            # Graceful fallback so the demo never breaks
            return AgentResult(
                agent_name=self.name,
                summary=f"(offline) Mock weather: wave 1.2 m, wind 18 km/h, SST 28 °C",
                confidence=0.4,
                data_sources=["mock fallback"],
                payload={
                    "lat": lat,
                    "lon": lon,
                    "data": {
                        "wave_height": 1.2,
                        "wind_speed": 18,
                        "sst": 28.0,
                    },
                },
            )
