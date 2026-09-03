"use client";

import { useState } from "react";
import dynamic from "next/dynamic";
import { INDIAN_COASTAL_ZONES, fetchInsight, OrcaInsight, DemoZone } from "@/lib/orca-client";
import InsightPanel from "@/components/InsightPanel";

// react-leaflet uses window/document, so it must be client-only
const MapView = dynamic(() => import("@/components/MapView"), { ssr: false });

export default function Home() {
  const [selected, setSelected] = useState<DemoZone | null>(null);
  const [insight, setInsight] = useState<OrcaInsight | null>(null);
  const [loading, setLoading] = useState(false);

  const handleSelect = async (zone: DemoZone) => {
    setSelected(zone);
    setLoading(true);
    setInsight(null);
    try {
      const result = await fetchInsight(zone.lat, zone.lon, "2026-08-15");
      setInsight(result);
    } catch (err) {
      console.error("fetchInsight failed:", err);
      setInsight({
        zone: { lat: zone.lat, lon: zone.lon, date: "2026-08-15" },
        agents: [],
        overall_risk: "unknown",
        summary: `Failed to reach the ORCA API. ${err instanceof Error ? err.message : String(err)}`,
        recommendation: "Check that the FastAPI backend is running on port 8000.",
        data_sources_used: [],
        data_sources_failed: ["API: backend unreachable"],
        fetched_at: new Date().toISOString(),
      });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="h-screen flex flex-col">
      {/* Header */}
      <header className="bg-gradient-to-r from-blue-900 to-cyan-700 text-white px-6 py-4 shadow-md">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">🐋 ORCA</h1>
            <p className="text-sm opacity-80">
              Marine EcOsystem Reasoning with Collaborative Agents · SIH 2026 PS 176
            </p>
          </div>
          <div className="text-xs opacity-70 text-right">
            <div>ISRO · Department of Space</div>
            <div>Real-time ocean intelligence</div>
          </div>
        </div>
      </header>

      {/* Main: map + side panel */}
      <div className="flex-1 grid grid-cols-1 md:grid-cols-[2fr_1fr] overflow-hidden">
        <div className="relative">
          <MapView
            zones={INDIAN_COASTAL_ZONES}
            selected={selected}
            onSelect={handleSelect}
          />
          <div className="absolute bottom-4 left-4 bg-white/95 rounded shadow p-3 text-xs max-w-xs z-[1000]">
            <div className="font-semibold mb-1">Click any marker, or right-click anywhere</div>
            <div className="text-gray-600">
              8 curated Indian coastal zones plus free-click anywhere on the
              ocean. Each analysis runs 9 AI agents across 4+ real data
              sources (NOAA chlorophyll, Open-Meteo SST, GFW fishing fleet,
              INCOIS).
            </div>
          </div>
        </div>
        <div className="bg-gray-50 border-l overflow-hidden">
          <InsightPanel
            insight={insight}
            loading={loading}
            zoneName={selected?.name || ""}
          />
        </div>
      </div>
    </div>
  );
}
