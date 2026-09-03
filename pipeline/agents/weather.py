"""Agent 3: Weather & Hazard 🌦️

Processes IMD-style weather data (cyclones, rainfall, lightning, wind,
marine warnings). For the v1 implementation we use Open-Meteo's free
weather API which has the variables we need:

  - wind_speed_10m_max     (daily max wind, m/s)
  - precipitation_sum      (daily total precipitation, mm)
  - weather_code          (WMO weather interpretation)
  - temperature_2m_max/min (for context)

For real IMD bulletins we'd need to scrape mausam.imd.gov.in or use
the MOSDAC atmospheric data products. The Open-Meteo source gives us
~80% of the value with zero auth.

Risk thresholds (WMO/IMD conventions):
  - wind < 8 m/s   (Beaufort 5)     : safe for small craft
  - wind 8-14 m/s  (BF 5-7)          : caution
  - wind 14-20 m/s (BF 7-8, Gale)    : small craft advisory
  - wind > 20 m/s  (BF 9+, Storm)    : dangerous — stay on land

Inputs: ZoneSnapshot (lat, lon, date)
Outputs: dict of findings
"""
from __future__ import annotations

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


WEATHER_URL = "https://api.open-meteo.com/v1/forecast"
SOURCE_LABEL = "Open-Meteo Weather (WMO/ECMWF)"


def _fetch(lat: float, lon: float, start_date: str, end_date: str) -> dict:
    """Fetch daily weather summary."""
    params = {
        "latitude": f"{lat:.4f}",
        "longitude": f"{lon:.4f}",
        "daily": "wind_speed_10m_max,wind_gusts_10m_max,precipitation_sum,weather_code,temperature_2m_max,temperature_2m_min",
        "start_date": start_date,
        "end_date": end_date,
        "timezone": "auto",
        "wind_speed_unit": "ms",
    }
    url = f"{WEATHER_URL}?{urllib.parse.urlencode(params)}"
    print(f"[Weather] {lat:.2f},{lon:.2f} {start_date}..{end_date}", file=sys.stderr)
    req = urllib.request.Request(url, headers={"User-Agent": "ORCA/1.0"})
    with urllib.request.urlopen(req, timeout=15) as r:
        return json.loads(r.read().decode("utf-8"))


def analyze(snap: dict[str, Any]) -> dict[str, Any]:
    findings: list[dict[str, Any]] = []
    lat = snap.get("lat")
    lon = snap.get("lon")
    target_date = snap.get("date")

    if lat is None or lon is None or target_date is None:
        return {
            "agent": "weather",
            "findings": [{
                "type": "no_location",
                "severity": "info",
                "value": None,
                "msg": "No lat/lon/date — cannot fetch weather.",
            }],
            "summary": "No location data.",
            "risk_level": "unknown",
        }

    try:
        data = _fetch(lat, lon, target_date, target_date)
    except urllib.error.HTTPError as e:
        return {
            "agent": "weather",
            "findings": [{
                "type": "weather_api_error",
                "severity": "info",
                "value": e.code,
                "msg": f"Weather API returned HTTP {e.code}.",
            }],
            "summary": f"Weather API error {e.code}.",
            "risk_level": "unknown",
        }
    except Exception as e:  # noqa: BLE001
        return {
            "agent": "weather",
            "findings": [{
                "type": "weather_api_unreachable",
                "severity": "info",
                "value": None,
                "msg": f"Weather API unreachable: {type(e).__name__}.",
            }],
            "summary": "Weather data unavailable.",
            "risk_level": "unknown",
        }

    daily = data.get("daily", {})
    wind_max = daily.get("wind_speed_10m_max", [None])[0]
    gust_max = daily.get("wind_gusts_10m_max", [None])[0]
    precip = daily.get("precipitation_sum", [None])[0]
    t_max = daily.get("temperature_2m_max", [None])[0]
    t_min = daily.get("temperature_2m_min", [None])[0]
    wx_code = daily.get("weather_code", [None])[0]

    # Wind analysis (m/s, WMO thresholds)
    if wind_max is not None:
        if wind_max >= 20:
            findings.append({
                "type": "storm_warning",
                "severity": "high",
                "value": wind_max,
                "msg": f"Storm-force winds {wind_max:.1f} m/s (Beaufort 9+). Stay on land.",
            })
        elif wind_max >= 14:
            findings.append({
                "type": "gale_warning",
                "severity": "warn",
                "value": wind_max,
                "msg": f"Gale-force winds {wind_max:.1f} m/s (Beaufort 7-8). Small craft advisory.",
            })
        elif wind_max >= 10:
            findings.append({
                "type": "fresh_breeze",
                "severity": "warn",
                "value": wind_max,
                "msg": f"Fresh breeze {wind_max:.1f} m/s (Beaufort 5). Exercise caution.",
            })
        elif wind_max >= 8:
            findings.append({
                "type": "wind_moderate",
                "severity": "info",
                "value": wind_max,
                "msg": f"Moderate breeze {wind_max:.1f} m/s (Beaufort 4-5).",
            })
        else:
            findings.append({
                "type": "wind_calm",
                "severity": "good",
                "value": wind_max,
                "msg": f"Light winds {wind_max:.1f} m/s — safe conditions.",
            })

    # Gust analysis
    if gust_max is not None and wind_max is not None and gust_max > wind_max * 1.5:
        findings.append({
            "type": "gusty",
            "severity": "info",
            "value": gust_max,
            "msg": f"Wind gusts to {gust_max:.1f} m/s ({(gust_max/wind_max):.1f}× sustained).",
        })

    # Precipitation
    if precip is not None:
        if precip >= 50:
            findings.append({
                "type": "heavy_rain",
                "severity": "warn",
                "value": precip,
                "msg": f"Heavy rainfall {precip:.1f} mm/day — possible flooding, low visibility.",
            })
        elif precip >= 10:
            findings.append({
                "type": "rain",
                "severity": "info",
                "value": precip,
                "msg": f"Moderate rainfall {precip:.1f} mm/day.",
            })

    # Air temperature (for context, not safety)
    if t_max is not None and t_min is not None:
        findings.append({
            "type": "air_temp",
            "severity": "info",
            "value": f"{t_min:.0f}-{t_max:.0f}°C",
            "msg": f"Air temperature {t_min:.0f}°C to {t_max:.0f}°C.",
        })

    # WMO weather code → human label
    WX_LABELS = {
        0: "Clear sky", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
        45: "Fog", 48: "Rime fog",
        51: "Light drizzle", 53: "Moderate drizzle", 55: "Dense drizzle",
        61: "Light rain", 63: "Moderate rain", 65: "Heavy rain",
        71: "Light snow", 73: "Moderate snow", 75: "Heavy snow",
        80: "Light showers", 81: "Moderate showers", 82: "Violent showers",
        95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Severe thunderstorm",
    }
    if wx_code is not None:
        label = WX_LABELS.get(wx_code, f"Code {wx_code}")
        sev = "warn" if wx_code >= 95 else "info" if wx_code >= 51 else "good"
        findings.append({
            "type": "weather_condition",
            "severity": sev,
            "value": wx_code,
            "msg": f"Conditions: {label}.",
        })

    # Risk
    severities = [f["severity"] for f in findings]
    if "high" in severities or "critical" in severities:
        risk = "high"
    elif "warn" in severities:
        risk = "moderate"
    elif "good" in severities:
        risk = "low"
    else:
        risk = "unknown"

    if risk == "high":
        summary = f"🌦️ Storm conditions — wind {wind_max} m/s, dangerous."
    elif risk == "moderate":
        summary = f"🌦️ Cautionary weather — wind {wind_max} m/s, {precip or 0}mm rain."
    elif risk == "low":
        summary = f"🌦️ Favorable weather — wind {wind_max} m/s."
    else:
        summary = "🌦️ Weather data unavailable."

    return {
        "agent": "weather",
        "findings": findings,
        "summary": summary,
        "risk_level": risk,
        "source": SOURCE_LABEL,
    }
