"""Mock Potential Fishing Zones (PFZ) along the Indian coast.

These are coarse but real coordinates. INCOIS publishes real PFZ advisories
daily in shapefile form; for the hackathon we approximate the most reliable
zones from the Konkan-Mumbai coast (Arabian Sea) where chlorophyll blooms
are well-studied.

Each zone has:
  * name        — human label
  * centroid    — (lat, lon) for nearest-neighbour lookups
  * polygon     — list of (lat, lon) forming a closed ring for the map
  * reliability — 0..1 score for productivity confidence
"""
from __future__ import annotations


PFZ_ZONES: list[dict] = [
    {
        "name": "Konkan Coastal PFZ (North)",
        "centroid": (19.0, 72.85),
        "polygon": [
            (19.30, 72.65),
            (19.30, 73.10),
            (18.70, 73.10),
            (18.70, 72.65),
        ],
        "reliability": 0.82,
    },
    {
        "name": "Konkan Coastal PFZ (South)",
        "centroid": (17.7, 73.2),
        "polygon": [
            (18.00, 72.95),
            (18.00, 73.50),
            (17.40, 73.50),
            (17.40, 72.95),
        ],
        "reliability": 0.78,
    },
    {
        "name": "Goa Offshore PFZ",
        "centroid": (15.4, 73.7),
        "polygon": [
            (15.80, 73.30),
            (15.80, 74.20),
            (15.00, 74.20),
            (15.00, 73.30),
        ],
        "reliability": 0.74,
    },
    {
        "name": "Karnataka Coastal PFZ",
        "centroid": (13.9, 74.4),
        "polygon": [
            (14.30, 74.00),
            (14.30, 74.80),
            (13.50, 74.80),
            (13.50, 74.00),
        ],
        "reliability": 0.71,
    },
    {
        "name": "Kerala Coastal PFZ",
        "centroid": (10.2, 75.9),
        "polygon": [
            (10.60, 75.50),
            (10.60, 76.30),
            (9.80, 76.30),
            (9.80, 75.50),
        ],
        "reliability": 0.69,
    },
    {
        "name": "Tamil Nadu Coastal PFZ",
        "centroid": (11.5, 79.9),
        "polygon": [
            (11.90, 79.50),
            (11.90, 80.40),
            (11.10, 80.40),
            (11.10, 79.50),
        ],
        "reliability": 0.67,
    },
    {
        "name": "Andhra Coastal PFZ",
        "centroid": (15.9, 80.6),
        "polygon": [
            (16.30, 80.10),
            (16.30, 81.10),
            (15.50, 81.10),
            (15.50, 80.10),
        ],
        "reliability": 0.70,
    },
    {
        "name": "Odisha Coastal PFZ",
        "centroid": (19.8, 86.4),
        "polygon": [
            (20.20, 85.90),
            (20.20, 86.90),
            (19.40, 86.90),
            (19.40, 85.90),
        ],
        "reliability": 0.66,
    },
    {
        "name": "West Bengal Coastal PFZ",
        "centroid": (21.5, 88.0),
        "polygon": [
            (21.90, 87.50),
            (21.90, 88.50),
            (21.10, 88.50),
            (21.10, 87.50),
        ],
        "reliability": 0.62,
    },
]
