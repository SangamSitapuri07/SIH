"""Mock INCOIS data generator.

The real INCOIS API serves things like:
  * PFZ advisories (daily shapefile + KML)
  * High-wave alerts
  * Tsunami early warnings
  * Tide predictions

Most of these require institutional access. We generate realistic-looking
data here so the demo never depends on the live feed.
"""
from __future__ import annotations

import random
from datetime import datetime, timedelta


def generate_advisory(region: str = "west_coast") -> dict:
    """Return a fake but realistic INCOIS-style advisory."""
    now = datetime.utcnow()
    return {
        "issued_at": now.isoformat() + "Z",
        "valid_until": (now + timedelta(hours=24)).isoformat() + "Z",
        "region": region,
        "high_wave_warning": random.random() < 0.2,
        "storm_surge_warning": random.random() < 0.1,
        "tsunami_warning": False,  # never mock a tsunami
        "tide_high_m": round(random.uniform(0.8, 1.6), 2),
        "tide_low_m": round(random.uniform(0.1, 0.5), 2),
        "wind_speed_max_kmh": round(random.uniform(15, 45), 1),
        "sea_state": random.choice(["calm", "slight", "moderate", "rough"]),
        "fishermen_advice": random.choice([
            "Safe to venture into the sea.",
            "Exercise caution; small vessels advised to return by evening.",
            "Suspend fishing operations for the next 24 hours.",
        ]),
    }
