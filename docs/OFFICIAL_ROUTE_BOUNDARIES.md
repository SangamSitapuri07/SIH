# Route-boundary contract

With no `ORCA_BOUNDARY_GEOJSON`, the first route request automatically downloads and caches the public Marine Regions Territorial Seas v4 plus EEZ v12 polygons for mainland/Lakshadweep and Andaman/Nicobar at `~/.orca/india_marine_regions_v12_v4.geojson`. Territorial-sea coverage is required for near-shore departures; EEZ alone legally starts outside it. This enables coast/reference geometry routing but remains `REFERENCE_AVAILABLE`: it is not Indian NHO ENC or restricted-area clearance. `POST /api/v1/route-boundaries/refresh` retries the download.

For authority-issued navigation data, set `ORCA_BOUNDARY_GEOJSON` to a WGS84 GeoJSON FeatureCollection. An invalid or expired operator file fails closed; it never falls back to OpenStreetMap or hand-written coast boxes.

```json
{
  "type": "FeatureCollection",
  "metadata": {
    "authority": "Issuing authority name",
    "dataset": "Dataset/publication identifier",
    "version": "2026-09",
    "published_at": "2026-09-01T00:00:00Z",
    "expires_at": "2027-09-01T00:00:00Z",
    "crs": "EPSG:4326"
  },
  "features": [
    {
      "type": "Feature",
      "properties": {"orca_role": "navigable", "name": "Authorised navigation waters"},
      "geometry": {"type": "MultiPolygon", "coordinates": []}
    },
    {
      "type": "Feature",
      "properties": {"orca_role": "prohibited", "name": "No-entry zone"},
      "geometry": {"type": "Polygon", "coordinates": []}
    }
  ]
}
```

`navigable` is an allow-list. `prohibited` polygons override it. Only Polygon and MultiPolygon geometry is accepted. Keep the official file outside Git when its licence or sensitivity prohibits redistribution. Restart the backend after replacing it; startup validation records a SHA-256 checksum in every verified route response.

This is decision-support software, not a replacement for current official nautical charts, Notices to Mariners, VTS directions, COLREGs, or the skipper's judgment.
