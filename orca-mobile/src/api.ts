/**
 * ORCA API client — same FastAPI contract the web app uses.
 * Backend = laptop (Vercel deployment baad mein decide hoga).
 * Base URL yahan se badlo (Info tab mein editable bhee hoga):
 *   dev:  http://<laptop-LAN-IP>:8000
 *
 * Rule (web jaisi): koi bhi source fail ho toh HONEST error/bool —
 * kabhi invented value nahi. Timeout ke baad UI reason dikhata hai.
 */
import AsyncStorage from "@react-native-async-storage/async-storage";

const BASE_KEY = "orca_api_base";
const DEFAULT_BASE = "http://192.168.1.5:8000"; // EDIT: apne laptop ka LAN IP

let base = DEFAULT_BASE;

export async function initApiBase(): Promise<string> {
  try {
    const v = await AsyncStorage.getItem(BASE_KEY);
    if (v && /^https?:\/\//.test(v)) base = v;
  } catch { /* storage blocked */ }
  return base;
}

export async function setApiBase(v: string): Promise<void> {
  base = v.trim().replace(/\/$/, "");
  try { await AsyncStorage.setItem(BASE_KEY, base); } catch { /* ok */ }
}

export const getApiBase = () => base;

async function apiGet<T>(path: string, timeoutMs = 60_000): Promise<T> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(`${base}${path}`, { signal: ctrl.signal });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return (await r.json()) as T;
  } finally { clearTimeout(t); }
}

/* ── types (web/lib/orca-client.ts ke saath aligned, minimal subset) ── */
export interface FieldHotspot {
  lat: number; lon: number; chl: number;
  distance_km: number; distance_nm: number; bearing: string;
  bloom?: boolean; coast_km?: number | null; caveat?: string | null;
}
export interface FieldResponse {
  type: "field";
  chl: { points: { lat: number; lon: number; chl?: number | null }[]; date?: string; n: number; error?: string | null; land_masked?: number };
  met: { points: Record<string, unknown>[]; n: number; error?: string | null };
  hotspots: FieldHotspot[];
  generated_at: string;
  note: string;
}
export interface Advisory {
  verdict?: string; text?: string; generated_at?: string;
  [k: string]: unknown; // rich payload — D2 mein fields map karenge
}
export interface RouteCheck {
  ok: boolean | null; detour: boolean; reason: string;
  legs: [number, number][]; distance_nm: number; bearing_deg: number;
}
export interface Health {
  build_commit?: string; status?: string;
  [k: string]: unknown;
}

export const fetchHealth = () => apiGet<Health>("/api/v1/health", 8_000);
export const fetchAdvisory = (lat: number, lon: number) =>
  apiGet<Advisory>(`/api/v1/advisory?lat=${lat}&lon=${lon}`, 110_000);
export const fetchField = (lat: number, lon: number) =>
  apiGet<FieldResponse>(`/api/v1/field?lat=${lat}&lon=${lon}`, 90_000);
export const fetchRouteCheck = (aLa: number, aLo: number, bLa: number, bLo: number) =>
  apiGet<RouteCheck>(`/api/v1/route-check?from_lat=${aLa}&from_lon=${aLo}&to_lat=${bLa}&to_lon=${bLo}`, 20_000);
