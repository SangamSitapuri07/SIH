"""Safe Departure Window Calculator v2.1 — ORCA safety-threshold spec.

Three-tier hour classification:
  GOOD     wave < 2.0 m, sustained wind < 15 kn, gust < 25 kn
  CAUTION  wave < 2.5 m, sustained wind < 20 kn, gust < 34 kn
  NO-GO    any value at/above the CAUTION limits (or missing — fail-safe)
A departure window = contiguous non-NO-GO hours (>= MIN_HOURS, default 3);
quality GOOD only if EVERY hour is GOOD. Pure function — no network calls.
"""
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

GOOD = {"wave_m": 2.0, "wind_kn": 15.0, "gust_kn": 25.0}
CAUTION = {"wave_m": 2.5, "wind_kn": 20.0, "gust_kn": 34.0}
MIN_HOURS = 3
HORIZON_HOURS = 48          # spec: evaluate the 24-48 h series
IST_OFFSET = timedelta(hours=5, minutes=30)

WEEKDAYS = {
    "en": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"],
    "hi": ["सोम", "मंगल", "बुध", "गुरु", "शुक्र", "शनि", "रवि"],
    "te": ["సోమ", "మంగళ", "బుధ", "గురు", "శుక్ర", "శని", "ఆది"],
}


def _classify(w: Optional[float], wd: Optional[float], g: Optional[float]) -> str:
    if w is None or wd is None or g is None:
        return "NO-GO"      # cannot certify safety without evidence
    if w < GOOD["wave_m"] and wd < GOOD["wind_kn"] and g < GOOD["gust_kn"]:
        return "GOOD"
    if w < CAUTION["wave_m"] and wd < CAUTION["wind_kn"] and g < CAUTION["gust_kn"]:
        return "CAUTION"
    return "NO-GO"


def _iso_z(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _ist_local(dt_utc: datetime, show_day: bool, lang: str = "en") -> str:
    dt_ist = dt_utc + IST_OFFSET
    time_str = dt_ist.strftime("%I:%M %p").lstrip("0")
    if show_day:
        day_name = WEEKDAYS[lang][dt_ist.weekday()]
        return f"{time_str} {day_name}"
    return time_str


def find_safe_departure_window(hourly: Dict[str, Any],
                               min_hours: int = MIN_HOURS,
                               horizon_hours: int = HORIZON_HOURS) -> Dict[str, Any]:
    times: List[str] = hourly.get("time") or []
    waves: List[Optional[float]] = hourly.get("wave_height_m") or []
    winds: List[Optional[float]] = hourly.get("wind_speed_kn") or []
    gusts: List[Optional[float]] = hourly.get("wind_gust_kn") or []
    # waves come from the marine API, winds from the forecast API — trim to common length
    n = min(len(times), len(waves), len(winds), len(gusts))
    if n == 0:
        return {
            "status": "UNAVAILABLE",
            "note": "No hourly forecast series available.",
            "recommendation_en": "Departure window unknown — no forecast timeline.",
            "recommendation_hi": "पूर्वानुमान उपलब्ध नहीं है, प्रस्थान समय अज्ञात है।",
            "recommendation_te": "సూచన లేనందున బయలుదేరే సమయం తెలియదు.",
        }

    now_key = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:00")
    start = next((i for i in range(n) if times[i] >= now_key), None)
    if start is None:
        return {
            "status": "UNAVAILABLE",
            "note": "Forecast series is entirely in the past.",
            "recommendation_en": "Departure window unknown — forecast series expired.",
            "recommendation_hi": "पूर्वानुमान समाप्त हो गया है, प्रस्थान समय अज्ञात है।",
            "recommendation_te": "సూచన గడువు ముగింది, బయలుదేరే సమయం తెలియదు.",
        }
    end = min(n, start + horizon_hours)

    classes = [_classify(waves[k], winds[k], gusts[k]) for k in range(start, end)]
    currently_safe = classes[0] != "NO-GO"

    runs, run_start = [], None
    for idx, c in enumerate(classes + ["NO-GO"]):     # sentinel closes a trailing run
        if c != "NO-GO":
            if run_start is None:
                run_start = idx
        elif run_start is not None:
            runs.append((run_start, idx))
            run_start = None
    runs = [(a, b) for (a, b) in runs if (b - a) >= min_hours]

    if not runs:
        return {
            "status": "UNAVAILABLE",
            "note": f"No {min_hours}h+ departure window within safety limits in the next {horizon_hours}h.",
            "currently_safe": currently_safe,
            "recommendation_en": f"No safe departure window in the next {horizon_hours} hours — sea conditions exceed safety limits.",
            "recommendation_hi": f"अगले {horizon_hours} घंटों में प्रस्थान के लिए कोई सुरक्षित समय नहीं है।",
            "recommendation_te": f"తరువాతి {horizon_hours} గంటల్లో బయలుదేరడానికి సురక్షిత సమయం లేదు.",
            "thresholds": {"good": GOOD, "caution": CAUTION, "min_hours": min_hours},
        }

    a, b = runs[0]                # earliest qualifying window
    quality = "GOOD" if all(classes[i] == "GOOD" for i in range(a, b)) else "CAUTION"

    window_waves = [w for w in waves[start + a: start + b] if w is not None]
    window_winds = [w for w in winds[start + a: start + b] if w is not None]
    window_gusts = [g for g in gusts[start + a: start + b] if g is not None]

    max_wave = max(window_waves) if window_waves else 0.0
    max_wind = max(window_winds) if window_winds else 0.0
    max_gust = max(window_gusts) if window_gusts else 0.0

    raw_start_str = times[start + a]
    start_dt = datetime.fromisoformat(raw_start_str.replace("Z", "+00:00")).replace(tzinfo=timezone.utc)
    duration = b - a
    end_dt = start_dt + timedelta(hours=duration)     # exclusive end

    crosses_midnight = (start_dt + IST_OFFSET).date() != (end_dt + IST_OFFSET).date()
    s_en, e_en = _ist_local(start_dt, crosses_midnight, "en"), _ist_local(end_dt, crosses_midnight, "en")
    s_hi, e_hi = _ist_local(start_dt, crosses_midnight, "hi"), _ist_local(end_dt, crosses_midnight, "hi")
    s_te, e_te = _ist_local(start_dt, crosses_midnight, "te"), _ist_local(end_dt, crosses_midnight, "te")

    # Horizon note when window is closed by forecast series boundary rather than weather
    is_horizon_bounded = (start + b) == end
    note = "Window extends to the end of the forecast horizon — re-check before it closes." if is_horizon_bounded else None

    if quality == "GOOD":
        recommendation_en = (f"Optimal departure window between {s_en} and {e_en} "
                             f"(max wave {max_wave:.1f} m, max wind {max_wind:.1f} kn).")
        recommendation_hi = f"{s_hi} से {e_hi} के बीच प्रस्थान के लिए सर्वोत्तम समय।"
        recommendation_te = f"{s_te} నుండి {e_te} వరకు బయలుదేరడానికి అనుకూలమైన సమయం."
    else:
        recommendation_en = (f"Marginal departure window between {s_en} and {e_en} "
                             f"(max wave {max_wave:.1f} m, max wind {max_wind:.1f} kn) — "
                             f"conditions within caution limits; small craft exercise care.")
        recommendation_hi = f"{s_hi} से {e_hi} तक सीमांत समय है — छोटी नावों को सावधानी बरतनी चाहिए।"
        recommendation_te = f"{s_te} నుండి {e_te} వరకు జాగ్రత్తతో బయలుదేరండి — చిన్న పడవలు జాగ్రత్త వహించాలి."

    return {
        "status": "AVAILABLE" if quality == "GOOD" else "CAUTION",
        "start_time": _iso_z(start_dt),
        "end_time": _iso_z(end_dt),
        "duration_hours": duration,
        "max_wave_m": round(max_wave, 2),
        "max_wind_kn": round(max_wind, 1),
        "max_gust_kn": round(max_gust, 1),
        "window_quality": quality,
        "currently_safe": currently_safe,
        "note": note,
        "recommendation_en": recommendation_en,
        "recommendation_hi": recommendation_hi,
        "recommendation_te": recommendation_te,
        "thresholds": {"good": GOOD, "caution": CAUTION, "min_hours": min_hours},
    }
