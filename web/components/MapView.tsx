"use client";

import { useEffect, useState } from "react";
import { MapContainer, TileLayer, Marker, Popup, useMap, useMapEvents } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

// Fix the default Leaflet marker icons (they break in webpack)
delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon-2x.png",
  iconUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-icon.png",
  shadowUrl: "https://unpkg.com/leaflet@1.9.4/dist/images/marker-shadow.png",
});

interface Zone {
  name: string;
  lat: number;
  lon: number;
}

interface MapViewProps {
  zones: Zone[];
  selected: Zone | null;
  onSelect: (zone: Zone) => void;
}

function FlyToSelected({ selected }: { selected: Zone | null }) {
  const map = useMap();
  useEffect(() => {
    if (selected) {
      map.flyTo([selected.lat, selected.lon], 6, { duration: 1.2 });
    }
  }, [selected, map]);
  return null;
}

// New: any-click-to-analyze. Lets the user click anywhere on the map
// (not just on the 8 hardcoded markers) and get a full ORCA analysis.
// Pinned to the nearest of the 8 marker zones for a name, but the
// lat/lon sent to the backend is the exact click position.
function ClickToAnalyze({
  onClick,
}: {
  onClick: (lat: number, lon: number) => void;
}) {
  useMapEvents({
    contextmenu(e) {
      // right-click is less likely to conflict with map drag
      onClick(e.latlng.lat, e.latlng.lng);
    },
  });
  return null;
}

export default function MapView({ zones, selected, onSelect }: MapViewProps) {
  const [clickHint, setClickHint] = useState(true);

  const handleMapClick = (lat: number, lon: number) => {
    // Find nearest of the 8 zones for a human-readable name
    let nearest = zones[0];
    let minDist = Infinity;
    for (const z of zones) {
      const d = Math.hypot(z.lat - lat, z.lon - lon);
      if (d < minDist) {
        minDist = d;
        nearest = z;
      }
    }
    const customZone: Zone = {
      name: `Custom: ${lat.toFixed(2)}°N, ${lon.toFixed(2)}°E`,
      lat,
      lon,
    };
    // Prepend a "[near X]" hint to make it clear which base zone this is near
    if (minDist < 3) {
      customZone.name = `${lat.toFixed(2)}°N, ${lon.toFixed(2)}°E (near ${nearest.name})`;
    }
    onSelect(customZone);
    setClickHint(false);
  };

  return (
    <MapContainer
      center={[15, 78]}
      zoom={5}
      style={{ height: "100%", width: "100%" }}
      scrollWheelZoom={true}
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FlyToSelected selected={selected} />
      <ClickToAnalyze onClick={handleMapClick} />
      {zones.map((z) => (
        <Marker
          key={z.name}
          position={[z.lat, z.lon]}
          eventHandlers={{ click: () => onSelect(z) }}
        >
          <Popup>
            <strong>{z.name}</strong>
            <br />
            {z.lat.toFixed(2)}°N, {z.lon.toFixed(2)}°E
            <br />
            <button
              onClick={() => onSelect(z)}
              className="mt-1 text-xs bg-blue-600 text-white px-2 py-1 rounded"
            >
              Analyze →
            </button>
          </Popup>
        </Marker>
      ))}
      {clickHint && (
        <div className="leaflet-top leaflet-right">
          <div className="leaflet-control bg-white/95 px-3 py-2 rounded shadow text-xs m-2 max-w-[220px]">
            <strong>💡 Tip:</strong> Right-click anywhere on the ocean to
            analyze a custom point (not just the 8 preset zones).
          </div>
        </div>
      )}
    </MapContainer>
  );
}
