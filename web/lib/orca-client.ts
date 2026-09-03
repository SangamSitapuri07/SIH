// ORCA API client — talks to the FastAPI backend.
//
// REST: on localhost the browser calls http://127.0.0.1:8000 DIRECTLY
// (CORS enabled on the backend) because the Next.js dev proxy proved to
// be a broken middleman on Windows (all connections RST while the direct
// WebSocket worked). The relative "/api/*" proxy route remains as an
// automatic fallback and is still the primary route in the Arena preview.
//
// WebSocket: Next's HTTP rewrites can't proxy WS, so the browser connects
// straight to the backend. On the laptop that's ws://localhost:8000; in
// the E2B/Arena preview the hostname pattern is
//   UI:      https://3000-<sandboxid>.e2b.app
//   backend: wss://8000-<sandboxid>.e2b.app
// so we derive it by swapping the port prefix.

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
  chlorophyll_date?: string;
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
  data_coverage?: { known: number; total: number; sources_failed: number };
  fetched_at: string;
}

export interface DemoZone {
  name: string;
  lat: number;
  lon: number;
}

// Real coordinates for 8 Indian coastal zones. NOT dummy data — every
// click triggers real NOAA / Open-Meteo / GFW / INCOIS calls for the
// exact point. They are just a UI convenience as starting locations.
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

// Veraval = our lead demo zone (Gujarat, real PFZ validation ground)
export const DEFAULT_ZONE: DemoZone = { name: "Veraval/Gujarat", lat: 20.9, lon: 70.37 };

// ── Advisory ──────────────────────────────────────────────────────

export interface AdvisoryReason {
  severity: "info" | "caution" | "no_go";
  code: string;
  msg: string;
}

export interface Advisory {
  type: "advisory";
  lat: number;
  lon: number;
  verdict: "go" | "caution" | "no_go";
  icon: string;
  color: string;
  headline: string;
  headline_en: string;
  headline_hi: string;
  reasons: AdvisoryReason[];
  variables: {
    wave_height_m?: number | null;
    swell_m?: number | null;
    wind_kts?: number | null;
    gust_kts?: number | null;
    sst_c?: number | null;
    current_kn?: number | null;
    current_dir?: string | null;
    chlorophyll_mg_m3?: number | null;
    cyclone_dist_km?: number | null;
    cyclone_note?: string | null;
    nearest_pfz_km?: number | null;
    nearest_pfz_nm?: number | null;
    nearest_pfz_bearing?: string | null;
    pfz_advisory_date?: string | null;
  };
  outlook_48h?: Record<string, number | null>;
  safe_window: { found: boolean; from_utc?: string; to_utc?: string; hours?: number; note?: string };
  sources: string[];
  sources_failed: string[];
  generated_at: string;
  valid_until: string;
  disclaimer: string;
}

// ── Alerts ────────────────────────────────────────────────────────

export interface OrcaAlert {
  id: string;
  code: string;
  severity: "watch" | "warning";
  simulated: boolean;
  title_en: string;
  title_hi: string;
  msg_en: string;
  lat: number;
  lon: number;
  issued_at: string;
  valid_until: string;
  source: string;
  cyclone?: { name?: string; max_wind_kt?: number; intensity?: string };
  distance_km?: number;
}

// ── Chat ──────────────────────────────────────────────────────────

export interface ChatStep {
  agent: string;
  tool: string;
  args: Record<string, any>;
  summary: string;
}

export interface ChatFinal {
  answer: string;
  advisory: Advisory;
  layers: string[];
  routing: { intents: string[]; agents: string[]; tools: string[] };
  sources: string[];
  lang: string;
  steps?: ChatStep[];
}

// ── Fetch helpers ─────────────────────────────────────────────────
//
// Base-URL strategy (learnt the hard way on the user's Windows laptop):
// the Next.js dev proxy (browser → :3000 → :8000) was resetting every
// connection while the DIRECT :8000 WebSocket worked fine. So on
// localhost we call the backend DIRECTLY first (CORS is enabled there)
// and only fall back to the /api proxy if the direct call can't be
// made at all. Whichever route works is remembered for the session.

const BASE_KEY = "orca.apiBase";

function candidateBases(): string[] {
  if (typeof window === "undefined") return [""]; // SSR: relative proxy
  const remembered = sessionStorage.getItem(BASE_KEY);
  if (remembered != null) return [remembered];
  const h = location.hostname;
  if (h === "localhost" || h === "127.0.0.1") {
    // Direct backend first (bypasses the flaky dev proxy), proxy as backup
    return ["http://127.0.0.1:8000", ""];
  }
  const m = h.match(/^(\d+)-(.+)$/); // Arena preview: 3000-<sandbox>.e2b.app
  if (m) return ["", `${location.protocol}//8000-${m[2]}`]; // proxy first (known-good)
  return [""];
}

function isNetworkError(e: unknown): boolean {
  // fetch() rejects with TypeError only for network/CORS failures,
  // never for HTTP error statuses — those are real answers.
  return e instanceof TypeError;
}

async function apiFetch(path: string, init: RequestInit): Promise<Response> {
  const bases = candidateBases();
  let lastErr: unknown = null;
  for (const base of bases) {
    try {
      const res = await fetch(base + path, { cache: "no-store", ...init });
      if (typeof window !== "undefined") {
        try { sessionStorage.setItem(BASE_KEY, base); } catch { /* private mode */ }
      }
      return res;
    } catch (e) {
      lastErr = e;
      if (!isNetworkError(e)) throw e; // AbortError etc. — don't mask it
      // network error → try the next base
    }
  }
  try { sessionStorage.removeItem(BASE_KEY); } catch { /* noop */ }
  throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
}

async function apiGet<T>(path: string, timeoutMs = 90_000): Promise<T> {
  const res = await apiFetch(path, {
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API ${res.status}: ${body.slice(0, 200)}`);
  }
  return res.json();
}

async function apiPost<T>(path: string, body: unknown, timeoutMs = 220_000): Promise<T> {
  const res = await apiFetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API ${res.status}: ${text.slice(0, 200)}`);
  }
  return res.json();
}

// ── GFW deep-data switch ──────────────────────────────────────────
// Off by default = fast map clicks. When the user flips "Real fishing
// data (GFW)" in Settings, insight + advisory include REAL Global
// Fishing Watch effort/fleet (needs GFW_API_TOKEN in the backend .env).

export function gfwDeepEnabled(): boolean {
  if (typeof window === "undefined") return false;
  try { return localStorage.getItem("orca.gfwDeep") === "1"; } catch { return false; }
}

export function setGfwDeep(v: boolean): void {
  try { localStorage.setItem("orca.gfwDeep", v ? "1" : "0"); } catch { /* private mode */ }
}

export const fetchInsight = (lat: number, lon: number, date?: string) =>
  apiGet<OrcaInsight>(
    `/api/v1/reason?lat=${lat}&lon=${lon}${date ? `&date=${date}` : ""}&include_gfw=${gfwDeepEnabled()}`,
    220_000
  );

export const fetchAdvisory = (lat: number, lon: number) =>
  apiGet<Advisory>(`/api/v1/advisory?lat=${lat}&lon=${lon}&include_gfw=${gfwDeepEnabled()}`, 120_000);

export interface LayersResponse {
  type: "FeatureCollection";
  generated_at: string;
  features: any[];
  layer_types: string[];
  sources: string[];
  errors: string[];
}

export const fetchLayers = (types?: string[], bbox?: string) =>
  apiGet<LayersResponse>(
    `/api/v1/layers?${types ? `types=${types.join(",")}` : ""}${bbox ? `&bbox=${bbox}` : ""}`,
    90_000
  );

export const fetchAlerts = (lat?: number, lon?: number) =>
  apiGet<{ alerts: OrcaAlert[]; count: number; newly_evaluated: OrcaAlert[] }>(
    `/api/v1/alerts${lat != null && lon != null ? `?lat=${lat}&lon=${lon}` : ""}`,
    120_000
  );

export const fetchHealth = () =>
  apiGet<{ status: string; version: string; gfw_token: boolean; [k: string]: any }>(
    `/api/v1/health`,
    15_000
  );

export const simulateAlert = (lat: number, lon: number) =>
  apiPost<{ created: OrcaAlert; note: string }>(
    `/api/v1/alerts/simulate`,
    { type: "cyclone", lat, lon },
    15_000
  );

export const postChatOnce = (
  message: string,
  lat: number,
  lon: number,
  lang?: string
) => apiPost<ChatFinal>(`/api/v1/chat`, { message, lat, lon, lang }, 260_000);

export const postFeedback = (payload: unknown) =>
  apiPost(`/api/v1/feedback`, payload, 15_000);

// ── WebSocket ─────────────────────────────────────────────────────

export function wsUrl(): string {
  if (typeof window === "undefined") return "ws://127.0.0.1:8000/ws/chat";
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const host = location.hostname;
  // Arena/E2B preview: 3000-<sandbox>.e2b.app → 8000-<sandbox>.e2b.app
  const m = host.match(/^(\d+)-(.+)$/);
  if (m && m[1] !== "8000") return `${proto}//8000-${m[2]}/ws/chat`;
  // Localhost: be explicit about IPv4 — on Windows "localhost" can resolve
  // to ::1 (IPv6) while uvicorn only listens on 127.0.0.1.
  if (host === "localhost") return `${proto}//127.0.0.1:8000/ws/chat`;
  return `${proto}//${host}:8000/ws/chat`;
}

export type ChatEventHandler = (ev: any) => void;

/**
 * Stream a chat answer over WebSocket (routing → agent steps → tokens →
 * final), with automatic fallback to the one-shot HTTP endpoint when the
 * socket can't connect (some corporate proxies block WS). Events passed
 * to `onEvent` are blueprint-shaped (chat.routing, chat.agent_step,
 * chat.token, chat.final, chat.slow_notice).
 */
export async function streamChat(
  message: string,
  lat: number,
  lon: number,
  lang: string,
  onEvent: ChatEventHandler,
): Promise<void> {
  const url = wsUrl();
  let ws: WebSocket | null = null;
  let gotAny = false;
  let finished = false;

  const wsPromise = new Promise<void>((resolve, reject) => {
    try {
      ws = new WebSocket(url);
    } catch (e) {
      reject(e);
      return;
    }
    const killer = setTimeout(() => {
      if (!finished) {
        try { ws?.close(); } catch { /* noop */ }
        reject(new Error("WebSocket timed out"));
      }
    }, 240_000);

    ws.onopen = () => {
      onEvent({ type: "chat.ws_open" });
      ws!.send(JSON.stringify({
        type: "chat.user_message", message, lat, lon, lang,
      }));
    };
    ws.onmessage = (msg) => {
      try {
        const ev = JSON.parse(String(msg.data));
        gotAny = true;
        if (ev.type === "chat.final") finished = true;
        onEvent(ev);
        if (ev.type === "chat.final" || ev.type === "chat.error") {
          clearTimeout(killer);
          resolve();
          ws?.close();
        }
      } catch { /* ignore non-JSON */ }
    };
    ws.onerror = () => {
      clearTimeout(killer);
      reject(new Error(`WebSocket error connecting to ${url}`));
    };
    ws.onclose = (c) => {
      clearTimeout(killer);
      if (!finished) {
        reject(new Error(`WebSocket closed (code ${c.code}) before final answer`));
      }
    };
  });

  try {
    await wsPromise;
  } catch (e) {
    if (!gotAny) {
      // Honest fallback: same real answer via HTTP, no live trace
      onEvent({ type: "chat.ws_fallback", payload: { reason: String(e) } });
      const final = await postChatOnce(message, lat, lon, lang);
      for (const step of final.steps ?? []) {
        onEvent({ type: "chat.agent_step", payload: step });
      }
      onEvent({ type: "chat.token", payload: { delta: final.answer } });
      onEvent({ type: "chat.final", payload: final });
    } else {
      throw e;
    }
  }
}
