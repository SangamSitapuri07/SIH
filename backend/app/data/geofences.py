"""Mock marine geofences — marine protected areas, restricted waters.

These polygons are coarse real-world locations for India's most prominent
MPAs. INCOIS, the Indian Coast Guard, and state forest departments publish
authoritative geofences; for the hackathon we approximate.

Each geofence has:
  * name           — human label
  * centroid       — (lat, lon)
  * polygon        — list of (lat, lon) for the map
  * alert_radius_km — distance within which to warn the user
  * kind           — "mpa" | "border" | "restricted" | "eco_sensitive"
"""
from __future__ import annotations


GEOFENCES: list[dict] = [
    {
        "name": "Gulf of Kutch Marine National Park",
        "centroid": (22.45, 69.75),
        "polygon": [
            (22.65, 69.55),
            (22.65, 69.95),
            (22.25, 69.95),
            (22.25, 69.55),
        ],
        "alert_radius_km": 30,
        "kind": "mpa",
    },
    {
        "name": "Sundarbans Reserved Forest (Marine Belt)",
        "centroid": (21.95, 89.30),
        "polygon": [
            (22.20, 89.00),
            (22.20, 89.60),
            (21.70, 89.60),
            (21.70, 89.00),
        ],
        "alert_radius_km": 40,
        "kind": "eco_sensitive",
    },
    {
        "name": "Gulf of Mannar Marine National Park",
        "centroid": (9.10, 79.20),
        "polygon": [
            (9.30, 78.95),
            (9.30, 79.45),
            (8.90, 79.45),
            (8.90, 78.95),
        ],
        "alert_radius_km": 25,
        "kind": "mpa",
    },
    {
        "name": "Malvan Marine Sanctuary",
        "centroid": (16.05, 73.45),
        "polygon": [
            (16.20, 73.30),
            (16.20, 73.60),
            (15.90, 73.60),
            (15.90, 73.30),
        ],
        "alert_radius_km": 20,
        "kind": "mpa",
    },
    {
        "name": "Marine National Park, Gulf of Kutch (West)",
        "centroid": (22.50, 68.30),
        "polygon": [
            (22.70, 68.10),
            (22.70, 68.50),
            (22.30, 68.50),
            (22.30, 68.10),
        ],
        "alert_radius_km": 35,
        "kind": "mpa",
    },
    {
        "name": "Pirotan Island Restricted Zone",
        "centroid": (22.60, 70.00),
        "polygon": [
            (22.65, 69.95),
            (22.65, 70.05),
            (22.55, 70.05),
            (22.55, 69.95),
        ],
        "alert_radius_km": 10,
        "kind": "restricted",
    },
]
