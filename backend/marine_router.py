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
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlencode
from urllib.request import Request, urlopen


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


def _simplify_ring(ring: list[list[float]], tolerance: float = 0.0025) -> list[list[float]]:
    """Douglas-Peucker simplification (~250 m) for tractable reference routing."""
    if len(ring) <= 4: return ring
    def distance(point: list[float], start: list[float], end: list[float]) -> float:
        dx, dy = end[0]-start[0], end[1]-start[1]
        if dx == dy == 0: return math.hypot(point[0]-start[0], point[1]-start[1])
        t = max(0.0, min(1.0, ((point[0]-start[0])*dx+(point[1]-start[1])*dy)/(dx*dx+dy*dy)))
        return math.hypot(point[0]-(start[0]+t*dx), point[1]-(start[1]+t*dy))
    def rdp(points: list[list[float]]) -> list[list[float]]:
        index, maximum = 0, 0.0
        for i in range(1, len(points)-1):
            value = distance(points[i], points[0], points[-1])
            if value > maximum: index, maximum = i, value
        if maximum > tolerance:
            left, right = rdp(points[:index+1]), rdp(points[index:])
            return left[:-1] + right
        return [points[0], points[-1]]
    closed = ring[0] == ring[-1]
    simplified = rdp(ring[:-1] if closed else ring)
    if closed and simplified[0] != simplified[-1]: simplified.append(simplified[0])
    return simplified if len(simplified) >= 4 else ring


def _simplify_geometry(geometry: dict[str, Any]) -> None:
    kind, coords = geometry.get("type"), geometry.get("coordinates", [])
    if kind == "Polygon": geometry["coordinates"] = [_simplify_ring(ring) for ring in coords]
    elif kind == "MultiPolygon": geometry["coordinates"] = [[_simplify_ring(ring) for ring in polygon] for polygon in coords]


def _geometry_bbox(geometry: dict[str, Any]) -> tuple[float, float, float, float]:
    points = [point for ring in _rings(geometry) for point in ring]
    if not points: return (0.0, 0.0, 0.0, 0.0)
    lons = [point[0] for point in points]; lats = [point[1] for point in points]
    return min(lats), min(lons), max(lats), max(lons)


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
    """Load an operator GeoJSON, or lazily cache Marine Regions India EEZ.

    Marine Regions is a public reference boundary, not an Indian NHO ENC and
    not evidence of regulatory/no-entry clearance.  That distinction is kept
    in metadata and every route response.
    """
    _WFS = "https://geo.vliz.be/geoserver/MarineRegions/wfs"
    _SOURCES = (
        ("MarineRegions:eez", "Indian Exclusive Economic Zone"),
        ("MarineRegions:eez", "Indian Exclusive Economic Zone (Andaman and Nicobar Islands)"),
        ("MarineRegions:eez_12nm", "Indian 12 NM"),
        ("MarineRegions:eez_12nm", "Indian 12 NM (Andaman and Nicobar Islands)"),
    )

    def __init__(self, path: str | None = None):
        self.path = path or os.getenv("ORCA_BOUNDARY_GEOJSON")
        self.cache_path = Path(os.getenv("ORCA_EEZ_CACHE_PATH", str(Path.home() / ".orca" / "india_marine_regions_v12_v4.geojson")))
        self.features: list[dict[str, Any]] = []
        self._prepared: list[tuple[str, dict[str, Any], tuple[float, float, float, float]]] = []
        self.state = self._load()

    def _validate(self, raw: bytes, *, reference: bool = False) -> BoundaryState:
        payload = json.loads(raw)
        metadata = payload.get("metadata") or {}
        missing = [key for key in REQUIRED_METADATA if not metadata.get(key)]
        if payload.get("type") != "FeatureCollection" or missing:
            raise ValueError("invalid FeatureCollection metadata; missing: " + ", ".join(missing))
        expires = metadata.get("expires_at")
        if expires and datetime.fromisoformat(str(expires).replace("Z", "+00:00")) <= datetime.now(timezone.utc):
            raise ValueError("boundary dataset has expired")
        features = payload.get("features") or []
        roles = {str((f.get("properties") or {}).get("orca_role", "")).lower() for f in features}
        if "navigable" not in roles:
            raise ValueError("at least one feature with orca_role=navigable is required")
        for feature in features:
            if (feature.get("geometry") or {}).get("type") not in {"Polygon", "MultiPolygon"}:
                raise ValueError("only Polygon and MultiPolygon boundary features are accepted")
        self.features = features
        # Index each MultiPolygon member independently. India EEZ features
        # contain mainland water plus many distant island polygons; one bbox
        # around the whole feature forced every point test to scan every ring.
        # Per-polygon bboxes make the common check touch only nearby geometry.
        self._prepared = []
        for feature in features:
            role = str((feature.get("properties") or {}).get("orca_role", "")).lower()
            geometry = feature["geometry"]
            geometries = (
                [{"type": "Polygon", "coordinates": coordinates}
                 for coordinates in geometry.get("coordinates", [])]
                if geometry.get("type") == "MultiPolygon" else [geometry]
            )
            self._prepared.extend(
                (role, item, _geometry_bbox(item)) for item in geometries
            )
        status = "REFERENCE_AVAILABLE" if reference else "AVAILABLE"
        reason = ("Marine Regions India territorial sea v4 + EEZ v12 reference loaded; coastal-water geometry can be routed, "
                  "but restricted-area and regulatory clearance remain unverified.") if reference else "Authority boundary loaded and validated."
        return BoundaryState(True, status, reason, metadata, hashlib.sha256(raw).hexdigest())

    def _load(self) -> BoundaryState:
        try:
            if self.path:
                return self._validate(Path(self.path).read_bytes())
            if self.cache_path.exists():
                return self._validate(self.cache_path.read_bytes(), reference=True)
            return BoundaryState(False, "REFERENCE_DOWNLOAD_REQUIRED", "India EEZ reference will download automatically on the first route request.", {})
        except Exception as exc:
            return BoundaryState(False, "BOUNDARY_INVALID", str(exc), {})

    def ensure_ready(self) -> None:
        if self.state.ready or self.path:
            return
        try:
            def fetch_source(source: tuple[str, str]) -> list[dict[str, Any]]:
                layer, name = source
                params = {
                    "service": "WFS", "version": "1.0.0", "request": "GetFeature",
                    "typeName": layer, "outputFormat": "application/json",
                    "CQL_FILTER": f"geoname='{name}'",
                }
                request = Request(
                    self._WFS + "?" + urlencode(params),
                    headers={"User-Agent": "ORCA-Box/3.0", "Accept": "application/json"},
                )
                last_error: Exception | None = None
                for _attempt in range(2):
                    try:
                        with urlopen(request, timeout=20) as response:
                            payload = json.load(response)
                        return payload.get("features", [])
                    except Exception as exc:
                        last_error = exc
                raise last_error or RuntimeError(f"empty WFS response for {name}")

            # The four mainland/island territorial-sea/EEZ features are
            # independent. Sequential 3×60s retries could block a first route
            # request for many minutes; bounded parallel downloads complete or
            # fail explicitly in roughly one provider timeout window.
            with ThreadPoolExecutor(max_workers=len(self._SOURCES)) as pool:
                source_features = list(pool.map(fetch_source, self._SOURCES))

            features: list[dict[str, Any]] = []
            for feature_group in source_features:
                for feature in feature_group:
                    props = dict(feature.get("properties") or {})
                    props.update(orca_role="navigable", boundary_tier="reference")
                    feature["properties"] = props
                    _simplify_geometry(feature.get("geometry") or {})
                    features.append(feature)
            if not features:
                raise ValueError("Marine Regions returned no India EEZ features")
            wrapped = {
                "type": "FeatureCollection",
                "metadata": {
                    "authority": "Flanders Marine Institute (VLIZ) / Marine Regions",
                    "dataset": "Indian territorial sea + EEZ, Marine Regions",
                    "version": "Territorial Seas v4 / EEZ v12", "published_at": "2023-01-01T00:00:00Z",
                    "crs": "EPSG:4326", "verification_tier": "reference_only",
                    "geometry_simplification_degrees": 0.0025,
                    "source_url": self._WFS,
                },
                "features": features,
            }
            raw = json.dumps(wrapped, separators=(",", ":")).encode()
            self.cache_path.parent.mkdir(parents=True, exist_ok=True)
            self.cache_path.write_bytes(raw)
            self.state = self._validate(raw, reference=True)
        except Exception as exc:
            self.state = BoundaryState(False, "REFERENCE_UNREACHABLE", f"Marine Regions EEZ download failed: {exc}", {})

    def classify(self, lat: float, lon: float) -> tuple[bool | None, str]:
        if not self.state.ready: return None, self.state.reason
        def contains(role: str) -> bool:
            return any(
                min_lat <= lat <= max_lat and min_lon <= lon <= max_lon and
                _inside_geometry(lat, lon, geometry)
                for item_role, geometry, (min_lat, min_lon, max_lat, max_lon) in self._prepared
                if item_role == role
            )
        navigable = contains("navigable")
        prohibited = contains("prohibited")
        if prohibited:
            return False, "inside a configured prohibited zone"
        if not navigable:
            return False, "outside the India territorial-sea/EEZ reference"
        return True, "inside the configured marine polygon"

class MarineRoutePlanner:
    """A* over a local WGS84 grid; all expanded nodes are boundary-verified."""
    def __init__(self, boundaries: OfficialBoundaryStore): self.boundaries = boundaries

    def plan(self, start: tuple[float,float], end: tuple[float,float], grid_km: float = 5.0) -> dict[str, Any]:
        self.boundaries.ensure_ready()
        if not self.boundaries.state.ready:
            return {"status":"BOUNDARY_UNVERIFIED", "verified":False, "reason":self.boundaries.state.reason, "routes":[]}
        for label, point in (("departure", start), ("destination", end)):
            allowed, reason = self.boundaries.classify(*point)
            if not allowed: return {"status":"NO_SAFE_ROUTE", "verified":True, "reason":f"{label.title()} is {reason}.", "routes":[]}
        direct_km = haversine(start, end)
        # Long cross-coast routes need enough southward search room to go
        # around the Indian peninsula, but a 5 km global grid exceeds the
        # client's 45-second request window. Preserve fine coastal routing for
        # short legs and use a bounded coarse planning grid for long legs.
        grid_km = max(grid_km, 20.0 if direct_km > 700 else 10.0 if direct_km > 250 else 5.0)
        midlat=(start[0]+end[0])/2; dlat=grid_km/111.0; dlon=grid_km/(111.0*max(.2, math.cos(math.radians(midlat))))
        margin_km = min(1100.0, max(40.0, direct_km * (1.05 if direct_km > 500 else 0.45)))
        margin=max(4, math.ceil(margin_km/grid_km)); minlat=min(start[0],end[0])-margin*dlat; minlon=min(start[1],end[1])-margin*dlon
        def key(p): return (round((p[0]-minlat)/dlat), round((p[1]-minlon)/dlon))
        def point(k): return (minlat+k[0]*dlat, minlon+k[1]*dlon)
        allowed_cache: dict[tuple[int, int], bool] = {}
        def is_allowed(position: tuple[float, float]) -> bool:
            cache_key = (round(position[0] * 10000), round(position[1] * 10000))
            if cache_key not in allowed_cache:
                allowed_cache[cache_key] = self.boundaries.classify(*position)[0] is True
            return allowed_cache[cache_key]
        def edge_allowed(a: tuple[float,float], b: tuple[float,float], spacing_km: float = 5.0) -> bool:
            # During search sample every 5 km; the final selected path is
            # rechecked at <=1 km spacing before it can be returned.
            count = max(1, math.ceil(haversine(a, b) / spacing_km))
            return all(is_allowed((a[0]+(b[0]-a[0])*i/count, a[1]+(b[1]-a[1])*i/count)) for i in range(count+1))
        def success(path: list[tuple[float, float]]) -> dict[str, Any]:
            distance=sum(haversine(a,b) for a,b in zip(path,path[1:]))
            coords=[[round(lat,5),round(lon,5)] for lat,lon in path]
            reference = self.boundaries.state.status == "REFERENCE_AVAILABLE"
            status = "REFERENCE_ROUTE_GEOMETRY" if reference else "ROUTE_GEOMETRY_VERIFIED"
            reason = ("Path stays inside the Marine Regions India territorial-sea/EEZ reference geometry. Regulatory/restricted-area clearance is not verified."
                      if reference else "Every route edge is inside authority-declared navigable waters and outside prohibited polygons.")
            return {"status":status, "verified":True, "regulatory_verified":not reference, "reason":reason, "routes":[{"id":"balanced","label":"Balanced EEZ geometry" if reference else "Balanced verified geometry","coordinates":coords,"distance_km":round(distance,1),"distance_nm":round(distance*.539957,1)}], "boundary":{"metadata":self.boundaries.state.metadata,"sha256":self.boundaries.state.checksum}}
        # Most fishing legs stay on one side of the coast. Do not run A* when
        # the complete great-circle approximation already remains in water.
        if edge_allowed(start, end, 1.0):
            return success([start, end])
        s,t=key(start),key(end); frontier=[(0.0,s)]; came={s:None}; cost={s:0.0}; max_nodes=60000
        while frontier and len(came)<max_nodes:
            _,cur=heapq.heappop(frontier)
            if cur==t: break
            for di,dj in ((-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)):
                nxt=(cur[0]+di,cur[1]+dj); pos=point(nxt)
                if abs(nxt[0]-s[0])>margin+abs(t[0]-s[0]) or abs(nxt[1]-s[1])>margin+abs(t[1]-s[1]): continue
                if not is_allowed(pos) or not edge_allowed(point(cur), pos): continue
                new=cost[cur]+haversine(point(cur),pos)
                if new<cost.get(nxt,float("inf")):
                    cost[nxt]=new; came[nxt]=cur; heapq.heappush(frontier,(new+haversine(pos,end),nxt))
        if t not in came: return {"status":"NO_SAFE_ROUTE", "verified":True, "reason":"No boundary-compliant path was found.", "routes":[]}
        path=[]; cur=t
        while cur is not None: path.append(point(cur)); cur=came[cur]
        path=list(reversed(path)); path[0]=start; path[-1]=end
        if not all(edge_allowed(a, b, 1.0) for a, b in zip(path, path[1:])):
            return {"status":"NO_SAFE_ROUTE", "verified":True, "reason":"Endpoint connector crosses a prohibited or non-navigable area.", "routes":[]}
        return success(path)
