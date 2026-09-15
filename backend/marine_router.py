"""Fail-closed marine route geometry over authority-issued GeoJSON boundaries.

The router never treats a basemap or a hand-written bounding box as navigation
evidence.  ORCA_BOUNDARY_GEOJSON must point at a FeatureCollection whose
features declare `orca_role` = `navigable` or `prohibited`, and whose collection
metadata identifies the issuing authority and version.
"""
from __future__ import annotations

import hashlib
import heapq
import json
import math
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


REQUIRED_METADATA = ("authority", "dataset", "version", "published_at")


def haversine(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1 = map(math.radians, a); lat2, lon2 = map(math.radians, b)
    dlat, dlon = lat2-lat1, lon2-lon1
    return 6371.0088 * 2 * math.asin(math.sqrt(math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2))


def bearing(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lat2 = map(math.radians, (a[0], b[0])); dl = math.radians(b[1]-a[1])
    return (math.degrees(math.atan2(math.sin(dl)*math.cos(lat2), math.cos(lat1)*math.sin(lat2)-math.sin(lat1)*math.cos(lat2)*math.cos(dl)))+360)%360


def _rings(geometry: dict[str, Any]) -> Iterable[list[list[float]]]:
    kind, coords = geometry.get("type"), geometry.get("coordinates", [])
    if kind == "Polygon": yield from coords
    elif kind == "MultiPolygon":
        for polygon in coords: yield from polygon


def _inside_ring(lat: float, lon: float, ring: list[list[float]]) -> bool:
    inside = False
    j = len(ring)-1
    for i in range(len(ring)):
        xi, yi = ring[i][0], ring[i][1]; xj, yj = ring[j][0], ring[j][1]
        if ((yi > lat) != (yj > lat)) and lon < (xj-xi)*(lat-yi)/(yj-yi)+xi:
            inside = not inside
        j = i
    return inside


def _inside_geometry(lat: float, lon: float, geometry: dict[str, Any]) -> bool:
    kind, coords = geometry.get("type"), geometry.get("coordinates", [])
    polygons = [coords] if kind == "Polygon" else coords if kind == "MultiPolygon" else []
    for polygon in polygons:
        if polygon and _inside_ring(lat, lon, polygon[0]) and not any(_inside_ring(lat, lon, hole) for hole in polygon[1:]):
            return True
    return False


@dataclass(frozen=True)
class BoundaryState:
    ready: bool
    status: str
    reason: str
    metadata: dict[str, Any]
    checksum: str | None = None


class OfficialBoundaryStore:
    def __init__(self, path: str | None = None):
        self.path = path or os.getenv("ORCA_BOUNDARY_GEOJSON")
        self.features: list[dict[str, Any]] = []
        self.state = self._load()

    def _load(self) -> BoundaryState:
        if not self.path:
            return BoundaryState(False, "OFFICIAL_BOUNDARY_REQUIRED", "Set ORCA_BOUNDARY_GEOJSON to an authority-issued GeoJSON file.", {})
        try:
            raw = Path(self.path).read_bytes(); payload = json.loads(raw)
            metadata = payload.get("metadata") or {}
            missing = [key for key in REQUIRED_METADATA if not metadata.get(key)]
            if payload.get("type") != "FeatureCollection" or missing:
                raise ValueError("invalid FeatureCollection metadata; missing: " + ", ".join(missing))
            expires = metadata.get("expires_at")
            if expires and datetime.fromisoformat(str(expires).replace("Z", "+00:00")) <= datetime.now(timezone.utc):
                raise ValueError("official boundary dataset has expired")
            features = payload.get("features") or []
            roles = {str((f.get("properties") or {}).get("orca_role", "")).lower() for f in features}
            if "navigable" not in roles:
                raise ValueError("at least one feature with orca_role=navigable is required")
            for feature in features:
                if (feature.get("geometry") or {}).get("type") not in {"Polygon", "MultiPolygon"}:
                    raise ValueError("only Polygon and MultiPolygon boundary features are accepted")
            self.features = features
            return BoundaryState(True, "AVAILABLE", "Authority boundary loaded and validated.", metadata, hashlib.sha256(raw).hexdigest())
        except Exception as exc:
            return BoundaryState(False, "BOUNDARY_INVALID", str(exc), {})

    def classify(self, lat: float, lon: float) -> tuple[bool | None, str]:
        if not self.state.ready: return None, self.state.reason
        navigable = any(_inside_geometry(lat, lon, f["geometry"]) for f in self.features if str((f.get("properties") or {}).get("orca_role", "")).lower()=="navigable")
        prohibited = any(_inside_geometry(lat, lon, f["geometry"]) for f in self.features if str((f.get("properties") or {}).get("orca_role", "")).lower()=="prohibited")
        return navigable and not prohibited, "inside verified navigable waters" if navigable and not prohibited else "outside allowed waters or inside a prohibited zone"


class MarineRoutePlanner:
    """A* over a local WGS84 grid; all expanded nodes are boundary-verified."""
    def __init__(self, boundaries: OfficialBoundaryStore): self.boundaries = boundaries

    def plan(self, start: tuple[float,float], end: tuple[float,float], grid_km: float = 5.0) -> dict[str, Any]:
        if not self.boundaries.state.ready:
            return {"status":"BOUNDARY_UNVERIFIED", "verified":False, "reason":self.boundaries.state.reason, "routes":[]}
        for label, point in (("departure", start), ("destination", end)):
            allowed, reason = self.boundaries.classify(*point)
            if not allowed: return {"status":"NO_SAFE_ROUTE", "verified":True, "reason":f"{label.title()} is {reason}.", "routes":[]}
        midlat=(start[0]+end[0])/2; dlat=grid_km/111.0; dlon=grid_km/(111.0*max(.2, math.cos(math.radians(midlat))))
        margin=max(4, int(haversine(start,end)/grid_km*.35)); minlat=min(start[0],end[0])-margin*dlat; minlon=min(start[1],end[1])-margin*dlon
        def key(p): return (round((p[0]-minlat)/dlat), round((p[1]-minlon)/dlon))
        def point(k): return (minlat+k[0]*dlat, minlon+k[1]*dlon)
        def edge_allowed(a: tuple[float,float], b: tuple[float,float]) -> bool:
            # A grid node alone can jump across a narrow island/restricted
            # polygon. Verify the complete edge at <=1 km spacing.
            count = max(1, math.ceil(haversine(a, b)))
            return all(self.boundaries.classify(a[0]+(b[0]-a[0])*i/count, a[1]+(b[1]-a[1])*i/count)[0] is True for i in range(count+1))
        s,t=key(start),key(end); frontier=[(0.0,s)]; came={s:None}; cost={s:0.0}; max_nodes=25000
        while frontier and len(came)<max_nodes:
            _,cur=heapq.heappop(frontier)
            if cur==t: break
            for di,dj in ((-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)):
                nxt=(cur[0]+di,cur[1]+dj); pos=point(nxt)
                if abs(nxt[0]-s[0])>margin+abs(t[0]-s[0]) or abs(nxt[1]-s[1])>margin+abs(t[1]-s[1]): continue
                allowed,_=self.boundaries.classify(*pos)
                if not allowed or not edge_allowed(point(cur), pos): continue
                new=cost[cur]+haversine(point(cur),pos)
                if new<cost.get(nxt,float("inf")):
                    cost[nxt]=new; came[nxt]=cur; heapq.heappush(frontier,(new+haversine(pos,end),nxt))
        if t not in came: return {"status":"NO_SAFE_ROUTE", "verified":True, "reason":"No boundary-compliant path was found.", "routes":[]}
        path=[]; cur=t
        while cur is not None: path.append(point(cur)); cur=came[cur]
        path=list(reversed(path)); path[0]=start; path[-1]=end
        if not all(edge_allowed(a, b) for a, b in zip(path, path[1:])):
            return {"status":"NO_SAFE_ROUTE", "verified":True, "reason":"Endpoint connector crosses a prohibited or non-navigable area.", "routes":[]}
        distance=sum(haversine(a,b) for a,b in zip(path,path[1:]))
        coords=[[round(lat,5),round(lon,5)] for lat,lon in path]
        return {"status":"ROUTE_GEOMETRY_VERIFIED", "verified":True, "reason":"Every route node is inside authority-declared navigable waters and outside prohibited polygons.", "routes":[{"id":"balanced","label":"Balanced verified geometry","coordinates":coords,"distance_km":round(distance,1),"distance_nm":round(distance*.539957,1)}], "boundary":{"metadata":self.boundaries.state.metadata,"sha256":self.boundaries.state.checksum}}
