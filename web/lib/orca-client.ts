// ORCA client — calls the Python pipeline via subprocess for the live demo.
// In production this would be HTTP calls to the FastAPI backend.

export interface ZoneSnapshot {
  lat: number;
  lon: number;
  date: string;
  fetched_at?: string;
  sst_max?: number;
  sst_min?: number;
  sst_mean?: number;
  wave_max?: number;
  wave_mean?: number;
  chlorophyll?: number;
  chlorophyll_unit?: string;
  chlorophyll_source?: string;
  fishing_hours?: number;
  vessel_count?: number;
  fleet_by_flag?: Record<string, number>;
  fleet_by_gear?: Record<string, number>;
  pfz_score?: number;
  data_sources_used?: string[];
  data_sources_failed?: string[];
}

export interface AgentFinding {
  type: string;
  severity: string;
  value?: any;
  msg: string;
}

export interface AgentResult {
  agent: string;
  findings: AgentFinding[];
  summary: string;
  risk_level: string;
  verdict?: string;
  risk_score?: number;
}

export interface OrcaInsight {
  zone: { lat: number; lon: number; date: string };
  agents: AgentResult[];
  overall_risk: string;
  summary: string;
  recommendation: string;
  data_sources_used: string[];
  data_sources_failed: string[];
  fetched_at: string;
}

export interface DemoZone {
  name: string;
  lat: number;
  lon: number;
}

// Real coordinates for 8 Indian coastal zones. These are NOT
// dummy data — they are real lat/lon coordinates that get sent
// to the FastAPI backend (which fetches real NOAA, Open-Meteo, GFW
// data for the exact point). They're just a UI convenience to give
// the user a starting point; you can also right-click anywhere on
// the map to analyze an arbitrary point.
export const INDIAN_COASTAL_ZONES: DemoZone[] = [
  { name: "Mumbai offshore",      lat: 19.0, lon: 72.8 },
  { name: "Goa offshore",         lat: 15.5, lon: 73.7 },
  { name: "Cochin offshore",      lat:  9.5, lon: 76.0 },
  { name: "Chennai offshore",     lat: 13.5, lon: 80.5 },
  { name: "Visakhapatnam",        lat: 17.5, lon: 83.5 },
  { name: "Kandla/Gujarat",       lat: 22.5, lon: 68.5 },
  { name: "Andaman (Port Blair)", lat: 12.0, lon: 92.5 },
  { name: "Lakshadweep",          lat: 10.5, lon: 72.5 },
];

// Call the FastAPI backend.
// In dev: tries localhost:8000 first (direct, bypasses Next.js proxy
// which has known issues with long-running requests like GFW queries).
// Falls back to /api/v1/... (Next.js proxy) for production builds.
const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE || "http://localhost:8000";

export async function fetchInsight(
  lat: number,
  lon: number,
  date: string = "2026-08-15"
): Promise<OrcaInsight> {
  const url = `${API_BASE}/api/v1/reason?lat=${lat}&lon=${lon}&date=${date}&include_gfw=true`;
  const res = await fetch(url, {
    cache: "no-store",
    // Long timeout for multi-source queries (GFW + NOAA + Open-Meteo + INCOIS)
    signal: AbortSignal.timeout(60_000),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`API ${res.status}: ${err.slice(0, 200)}`);
  }
  return res.json();
}
