"use client";

/* B18 — ORCA Live Beacon "Samudri Rakshak Net" (web lab).
 * AIS-waali philosophy: phone = transponder. Beacon ON → anonymous
 * ping har N sec → SOS dabate hi paas ke ORCA boats alert.
 * Privacy: sirf tab live jab USER beacon ON rakhe; 2 h silence →
 * auto-delete; stop = instant delete. Data 100% backend se — koi
 * fake/demo boat nahi banata is page mein. */

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  LiveBoat,
  LiveNearbyResponse,
  fmtLat,
  fmtLon,
  liveBoat,
  liveNearby,
  livePing,
  liveSos,
  liveSosClear,
  liveStart,
  liveStats,
  liveStop,
  LiveStats,
} from "@/lib/orca-client";

type Phase = "idle" | "active";

const SESS_KEY = "orca.live.session";
const PUB_KEY = "orca.live.pubid";
const LABEL_KEY = "orca.live.label";

const C = {
  bg: "bg-[#0A0E1A]",
  card: "bg-[#121A2E] border border-[#1E2A44]",
  faint: "text-[#4D5D80]",
  body: "text-[#9FB0D1]",
  input:
    "w-full bg-[#0A0E1A] border border-[#1E2A44] rounded-lg px-3 py-2 text-sm text-white placeholder:text-[#34446A] focus:outline-none focus:border-cyan-500/60",
};

function fmtAge(sec: number): string {
  if (sec < 60) return `${Math.max(0, Math.round(sec))}s pehle`;
  if (sec < 3600) return `${Math.round(sec / 60)} min pehle`;
  return `${(sec / 3600).toFixed(1)} h pehle`;
}

function compass(deg: number): string {
  const dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
  return dirs[Math.round(((deg % 360) + 360) % 360 / 45) % 8];
}

/* ── SVG rescue radar — concentric NM rings, boats placed at REAL
 *    bearing+distance from the backend. SOS = pulsing red. ── */
function Radar({ boats, radiusNm, selfSos }: {
  boats: LiveBoat[];
  radiusNm: number;
  selfSos: boolean;
}) {
  const size = 300;
  const cx = size / 2;
  const maxR = size / 2 - 16;
  const px = maxR / radiusNm;
  return (
    <svg
      viewBox={`0 0 ${size} ${size}`}
      className="w-full max-w-[330px] mx-auto select-none"
      role="img"
      aria-label="rescue radar"
    >
      <circle cx={cx} cy={cx} r={maxR + 8} fill="#0A1020" stroke="#1E2A44" />
      {[0.25, 0.5, 0.75, 1].map((f) => (
        <circle key={f} cx={cx} cy={cx} r={maxR * f} fill="none" stroke="#16233C" strokeDasharray={f === 1 ? "" : "3 4"} />
      ))}
      <line x1={cx} y1={10} x2={cx} y2={size - 10} stroke="#16233C" />
      <line x1={10} y1={cx} x2={size - 10} y2={cx} stroke="#16233C" />
      <text x={cx + 4} y={24} fill="#4D5D80" fontSize={10}>N</text>
      <text x={cx + maxR - 10} y={cx - 4} fill="#4D5D80" fontSize={9}>{radiusNm} NM</text>
      <text x={cx + maxR / 2 - 8} y={cx - 4} fill="#33436B" fontSize={9}>{Math.round(radius_nm_half(radiusNm))} NM</text>
      {/* self */}
      <circle cx={cx} cy={cx} r={7} fill={selfSos ? "#EF4444" : "#22D3EE"} opacity={0.25} />
      <circle cx={cx} cy={cx} r={4} fill={selfSos ? "#EF4444" : "#22D3EE"} />
      {boats.map((b) => {
        const d = Math.min(b.distance_nm ?? radiusNm, radiusNm);
        const brg = (((b.bearing_deg ?? 0) % 360) + 360) % 360;
        const rad = (brg * Math.PI) / 180;
        const x = cx + d * px * Math.sin(rad);
        const y = cx - d * px * Math.cos(rad);
        return (
          <g key={b.pub_id}>
            {b.sos && (
              <circle cx={x} cy={y} r={6} fill="none" stroke="#EF4444" strokeWidth={1.6}>
                <animate attributeName="r" from="6" to="16" dur="1.4s" repeatCount="indefinite" />
                <animate attributeName="opacity" from="0.9" to="0" dur="1.4s" repeatCount="indefinite" />
              </circle>
            )}
            <circle cx={x} cy={y} r={b.sos ? 5.5 : 4} fill={b.sos ? "#EF4444" : "#64748B"} stroke={b.sos ? "#FCA5A5" : "#94A3B8"} strokeWidth={0.8} />
            <text x={x + 8} y={y + 3} fill={b.sos ? "#FCA5A5" : "#64748B"} fontSize={9} fontFamily="monospace">
              {b.label ?? b.pub_id}
              {typeof b.distance_nm === "number" ? ` · ${b.distance_nm}NM` : ""}
            </text>
          </g>
        );
      })}
    </svg>
  );
}
function radius_nm_half(r: number): number {
  return r / 2;
}

export default function LiveBeaconPage() {
  const [phase, setPhase] = useState<Phase>("idle");
  const [session, setSession] = useState("");
  const [pubId, setPubId] = useState("");
  const [label, setLabel] = useState("");
  const [latTxt, setLatTxt] = useState("13.08");
  const [lonTxt, setLonTxt] = useState("80.29");
  const [intervalSec, setIntervalSec] = useState(5);
  const [pings, setPings] = useState(0);
  const [lastPingAt, setLastPingAt] = useState<number | null>(null);
  const [sos, setSos] = useState(false);
  const [sosNote, setSosNote] = useState("");
  const [sosConfirmUntil, setSosConfirmUntil] = useState(0);
  const [stopConfirmUntil, setStopConfirmUntil] = useState(0);
  const [nearbyRes, setNearbyRes] = useState<LiveNearbyResponse | null>(null);
  const [netStats, setNetStats] = useState<LiveStats | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  // rescue view (?track=<pub_id>)
  const [trackId, setTrackId] = useState<string | null>(null);
  const [trackBoat, setTrackBoat] = useState<LiveBoat | null>(null);
  const [trackErr, setTrackErr] = useState<string | null>(null);
  const [tick, setTick] = useState(0); // age refresh

  const coordsRef = useRef<{ lat: number; lon: number }>({ lat: 13.08, lon: 80.29 });
  const sessionRef = useRef("");
  sessionRef.current = session;
  const sosRef = useRef(false);
  sosRef.current = sos;

  const myCoords = useCallback((): { lat: number; lon: number } | null => {
    const lat = parseFloat(latTxt);
    const lon = parseFloat(lonTxt);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
    coordsRef.current = { lat, lon };
    return { lat, lon };
  }, [latTxt, lonTxt]);

  /* ── mount: rescue mode? resume session? network stats? ── */
  useEffect(() => {
    try {
      const q = new URLSearchParams(window.location.search);
      const t = q.get("track");
      if (t) setTrackId(t);
      const s = sessionStorage.getItem(SESS_KEY);
      const p = sessionStorage.getItem(PUB_KEY);
      const l = sessionStorage.getItem(LABEL_KEY);
      if (s && p) {
        setSession(s);
        setPubId(p);
        if (l) setLabel(l);
        setPhase("active");
      }
    } catch { /* SSR safety */ }
    liveStats().then(setNetStats).catch(() => setNetStats(null));
  }, []);

  /* ── ping loop — ping hi alert channel hai ── */
  useEffect(() => {
    if (phase !== "active" || !session) return;
    let cancelled = false;
    const beat = async () => {
      const c = coordsRef.current;
      try {
        const r = await livePing(sessionRef.current, c.lat, c.lon, {
          label: label || undefined,
        });
        if (cancelled) return;
        setPings((n) => n + 1);
        setLastPingAt(Date.now());
        setErr(null);
        if (r.sos_nearby_count > 0 && !sosRef.current) {
          // alerts UI picks this from nearbyRes merge; keep silent here
        }
      } catch (e) {
        if (!cancelled) setErr(`Ping fail — network/backend? (${e instanceof Error ? e.message : String(e)}) — ORCA retry karta rahega; position FAKE nahi hogi kabhi.`);
      }
    };
    beat();
    const t = setInterval(beat, Math.max(3, intervalSec) * 1000);
    return () => { cancelled = true; clearInterval(t); };
  }, [phase, session, intervalSec, label]);

  /* ── nearby radar refresh ── */
  useEffect(() => {
    if (phase !== "active" && !trackId) return;
    let cancelled = false;
    const pull = async () => {
      const c = coordsRef.current;
      try {
        const r = await liveNearby(c.lat, c.lon, 20);
        if (!cancelled) { setNearbyRes(r); setErr(null); }
      } catch { if (!cancelled) setNearbyRes(null); }
    };
    pull();
    const t = setInterval(pull, 10_000);
    return () => { cancelled = true; clearInterval(t); };
  }, [phase, trackId]);

  /* ── rescue view poll ── */
  useEffect(() => {
    if (!trackId) return;
    let cancelled = false;
    const pull = async () => {
      try {
        const r = await liveBoat(trackId);
        if (!cancelled) { setTrackBoat(r.boat); setTrackErr(null); }
      } catch (e) {
        if (!cancelled) {
          setTrackBoat(null);
          setTrackErr(e instanceof Error ? e.message : String(e));
        }
      }
    };
    pull();
    const t = setInterval(pull, 5_000);
    return () => { cancelled = true; clearInterval(t); };
  }, [trackId]);

  /* ── age tick ── */
  useEffect(() => {
    const t = setInterval(() => setTick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);
  void tick;

  const useMyGps = () => {
    if (!navigator.geolocation) { setErr("Is browser mein geolocation nahi — coords type kar do."); return; }
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLatTxt(pos.coords.latitude.toFixed(5));
        setLonTxt(pos.coords.longitude.toFixed(5));
        setBusy(false);
      },
      () => { setErr("GPS permission mila nahi — coords manually type kar do (demo ke liye best)."); setBusy(false); },
      { enableHighAccuracy: true, timeout: 10_000 },
    );
  };

  const startBeacon = async () => {
    const c = myCoords();
    if (!c) { setErr("Sahi lat/lon daalo pehle (±90 / ±180 ke andar)."); return; }
    setBusy(true);
    try {
      const r = await liveStart(c.lat, c.lon, label.trim() || undefined, session || undefined);
      setSession(r.session);
      setPubId(r.pub_id);
      setPhase("active");
      setErr(null);
      try {
        sessionStorage.setItem(SESS_KEY, r.session);
        sessionStorage.setItem(PUB_KEY, r.pub_id);
        sessionStorage.setItem(LABEL_KEY, label.trim());
      } catch { /* private mode */ }
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    }
    setBusy(false);
  };

  const fireSos = async () => {
    const nowT = Date.now();
    if (sosConfirmUntil < nowT) { setSosConfirmUntil(nowT + 4000); return; }
    setSosConfirmUntil(0);
    const c = myCoords();
    setBusy(true);
    try {
      await liveSos(session, sosNote.trim() || undefined, c?.lat, c?.lon);
      setSos(true);
      setErr(null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    }
    setBusy(false);
  };

  const clearSos = async () => {
    setBusy(true);
    try {
      await liveSosClear(session);
      setSos(false);
      setErr(null);
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    }
    setBusy(false);
  };

  const stopBeacon = async () => {
    const nowT = Date.now();
    if (stopConfirmUntil < nowT) { setStopConfirmUntil(nowT + 4000); return; }
    setStopConfirmUntil(0);
    setBusy(true);
    try { await liveStop(session); } catch { /* best-effort */ }
    try { sessionStorage.removeItem(SESS_KEY); sessionStorage.removeItem(PUB_KEY); sessionStorage.removeItem(LABEL_KEY); } catch { /* noop */ }
    setSession(""); setPubId(""); setPhase("idle"); setSos(false); setPings(0); setLastPingAt(null);
    setNearbyRes(null);
    liveStats().then(setNetStats).catch(() => setNetStats(null));
    setBusy(false);
  };

  const shareUrl = typeof window !== "undefined" && pubId
    ? `${window.location.origin}/live?track=${pubId}`
    : `/live?track=${pubId}`;

  const copyShare = async () => {
    try {
      await navigator.clipboard.writeText(shareUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch { setErr("Clipboard block hai — link manually select kar ke copy kar lo."); }
  };

  const otherBoats = (nearbyRes?.boats ?? []).filter((b) => b.pub_id !== pubId);
  const sosBoats = otherBoats.filter((b) => b.sos);

  /* ══════════════════ RESCUE VIEW ══════════════════ */
  if (trackId) {
    return (
      <div className={`min-h-screen ${C.bg} text-white flex flex-col items-center px-4 py-6`}>
        <div className="w-full max-w-lg">
          <div className="flex items-center justify-between mb-4">
            <h1 className="text-lg font-bold tracking-tight">🆘 RESCUE VIEW <span className={C.faint + " text-xs font-normal"}>Samudri Rakshak Net</span></h1>
            <button onClick={() => { setTrackId(null); history.replaceState(null, "", "/live"); }}
              className="text-xs text-cyan-300 hover:text-cyan-200 border border-[#1E2A44] rounded-lg px-3 py-1.5">← beacon apna</button>
          </div>
          {trackErr && (
            <div className={`${C.card} rounded-xl p-4 text-sm text-amber-300/90 leading-relaxed`}>
              ⚠️ {trackErr}
              <div className={`mt-2 text-xs ${C.faint}`}>ORCA kabhi purani/fake position nahi dikhata — agar beacon band ya expire ho gaya, hum seedha bolte hain.</div>
            </div>
          )}
          {trackBoat && (
            <div className={`rounded-xl p-4 border ${trackBoat.sos ? "border-red-500/60 bg-red-950/30" : C.card}`}>
              {trackBoat.sos && (
                <div className="flex items-center gap-2 mb-3">
                  <span className="relative flex h-3 w-3">
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
                    <span className="relative inline-flex rounded-full h-3 w-3 bg-red-500" />
                  </span>
                  <span className="text-red-300 font-bold text-sm tracking-wide">SOS ACTIVE — madad chahiye</span>
                </div>
              )}
              <div className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
                <div className={C.faint}>Boat</div>
                <div className="font-mono text-white">{trackBoat.label ?? trackBoat.pub_id}</div>
                <div className={C.faint}>Position</div>
                <div className="font-mono text-cyan-300">{fmtLat(trackBoat.lat)}, {fmtLon(trackBoat.lon)}</div>
                <div className={C.faint}>Last ping</div>
                <div className={trackBoat.age_sec > 120 ? "text-amber-300" : "text-emerald-300"}>{fmtAge(trackBoat.age_sec)}{trackBoat.age_sec > 120 ? " — purana, dhyan se" : " — LIVE"}</div>
                {trackBoat.sos_note && (<>
                  <div className={C.faint}>Message</div>
                  <div className="text-amber-200">{trackBoat.sos_note}</div>
                </>)}
                {typeof trackBoat.speed_kn === "number" && (<>
                  <div className={C.faint}>Speed</div>
                  <div>{trackBoat.speed_kn} kn {typeof trackBoat.heading_deg === "number" ? `· ${trackBoat.heading_deg}° ${compass(trackBoat.heading_deg)}` : ""}</div>
                </>)}
              </div>
              <div className={`mt-3 pt-3 border-t border-[#1E2A44] text-xs ${C.faint} leading-relaxed`}>
                📡 Har 5 sec auto-refresh · VHF Ch 16 pe bulate raho · Coastal emergency: Indian Coast Guard <span className="text-white font-semibold">1554</span> · SOLAS Reg 33: paas ki har badi ship legally madad karne ko bound hai.
              </div>
            </div>
          )}
          <div className={`mt-4 ${C.card} rounded-xl p-4`}>
            <div className={`text-xs ${C.faint} mb-2`}>Apna position daalo → doori/disha rescue ke liye:</div>
            <div className="flex gap-2">
              <input className={C.input} value={latTxt} onChange={(e) => setLatTxt(e.target.value)} placeholder="lat" inputMode="decimal" />
              <input className={C.input} value={lonTxt} onChange={(e) => setLonTxt(e.target.value)} placeholder="lon" inputMode="decimal" />
            </div>
            <NearbyFromMe latTxt={latTxt} lonTxt={lonTxt} myPubId="" />
          </div>
          <div className={`mt-4 text-[11px] ${C.faint} leading-relaxed text-center`}>
            Yeh link share karke koi bhi rescuer live track kar sakta hai — jab tak beacon ON hai. Privacy: raw session id kissi ko nahi milti.
          </div>
        </div>
      </div>
    );
  }

  /* ══════════════════ BEACON VIEW ══════════════════ */
  return (
    <div className={`min-h-screen ${C.bg} text-white flex flex-col items-center px-4 py-6`}>
      <div className="w-full max-w-5xl">
        {/* header */}
        <div className="flex items-center justify-between mb-4 flex-wrap gap-2">
          <div>
            <h1 className="text-lg font-bold tracking-tight">📡 Live Beacon <span className="text-cyan-300/90">· Samudri Rakshak Net</span></h1>
            <p className={`text-xs ${C.faint} mt-0.5`}>AIS waali philosophy, fishermen ke phones pe — anonymous · sirf jab tum beacon ON rakho · 2 h silence = auto-delete</p>
          </div>
          <Link href="/" className="text-xs text-cyan-300 hover:text-cyan-200 border border-[#1E2A44] rounded-lg px-3 py-1.5">← ORCA home</Link>
        </div>

        {/* error box */}
        {err && (
          <div className="mb-4 rounded-xl border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200">{err}</div>
        )}

        {/* SOS alert banner — paas ke boats ki */}
        {!sos && sosBoats.length > 0 && (
          <div className="mb-4 rounded-xl border border-red-500/70 bg-red-950/40 px-4 py-3">
            <div className="flex items-center gap-2">
              <span className="relative flex h-3 w-3">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-3 w-3 bg-red-500" />
              </span>
              <span className="text-red-200 font-bold text-sm">
                🚨 PAAS MEIN SOS! {sosBoats.map((b) => `${b.label ?? b.pub_id} — ${b.distance_nm} NM · ${b.bearing_deg}° ${compass(b.bearing_deg ?? 0)}`).join(" · ")}
              </span>
            </div>
            <div className="text-xs text-red-300/80 mt-1">Fishermen rescuing fishermen — tum sabse kareeb ho, madad hi asli coast guard hai. Track karo neeche se 👇</div>
          </div>
        )}

        {/* mera SOS banner */}
        {sos && (
          <div className="mb-4 rounded-xl border-2 border-red-500 bg-red-950/50 px-4 py-4">
            <div className="flex items-center gap-2">
              <span className="relative flex h-3.5 w-3.5">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-3.5 w-3.5 bg-red-500" />
              </span>
              <span className="text-red-200 font-bold">SOS BROADCAST HO RAHA HAI 🔴 — tumhari live position paas ke ORCA boats ko dikh rahi hai</span>
            </div>
            <div className="mt-2 flex items-center gap-2 flex-wrap">
              <code className="text-[11px] bg-black/40 border border-red-500/40 rounded-lg px-2 py-1.5 text-red-100 break-all">{shareUrl}</code>
              <button onClick={copyShare} className="text-xs bg-red-500/20 hover:bg-red-500/30 border border-red-400/50 rounded-lg px-3 py-1.5 text-red-100">
                {copied ? "✅ copy ho gaya" : "📋 link copy — family/rescue ko bhejo"}
              </button>
            </div>
            <div className="mt-3 text-xs text-red-300/80">Himmat rakho. Coast Guard <span className="font-bold text-white">1554</span> · VHF Ch 16 se paas ki ships bulao (SOLAS: wo legally aane ko bound hain).</div>
          </div>
        )}

        <div className="grid gap-4 lg:grid-cols-[1fr_1.1fr]">
          {/* ── LEFT: beacon control ── */}
          <div className={`${C.card} rounded-xl p-4`}>
            {phase === "idle" ? (
              <>
                <h2 className="text-sm font-bold text-white mb-1">▶️ Beacon shuru karo</h2>
                <p className={`text-xs ${C.body} mb-3 leading-relaxed`}>
                  Voyage ke waqt tumhara phone ek AIS-transponder ban jaata hai — anonymous, tumhare control mein. Paas ke boats tumhe dekh paayengi, aur tumhara SOS un tak seedha pahunchega.
                </p>
                <label className={`block text-xs ${C.faint} mb-1`}>Boat ka naam <span className="text-[#34446A]">(optional — jaise AIS pe ship ka naam dikhta hai)</span></label>
                <input className={`${C.input} mb-3`} value={label} onChange={(e) => setLabel(e.target.value)} maxLength={40} placeholder="e.g. SeaStar · Chennai" />
                <div className="grid grid-cols-2 gap-2 mb-3">
                  <div>
                    <label className={`block text-xs ${C.faint} mb-1`}>Latitude</label>
                    <input className={C.input} value={latTxt} onChange={(e) => setLatTxt(e.target.value)} inputMode="decimal" />
                  </div>
                  <div>
                    <label className={`block text-xs ${C.faint} mb-1`}>Longitude</label>
                    <input className={C.input} value={lonTxt} onChange={(e) => setLonTxt(e.target.value)} inputMode="decimal" />
                  </div>
                </div>
                <div className="flex gap-2 mb-3">
                  <button onClick={useMyGps} disabled={busy} className="flex-1 text-xs bg-[#0A0E1A] hover:bg-[#0E1526] border border-[#1E2A44] rounded-lg px-3 py-2 text-[#9FB0D1]">📍 Meri GPS location</button>
                  <button onClick={() => { setLatTxt("13.08000"); setLonTxt("80.29000"); }} className="text-xs bg-[#0A0E1A] hover:bg-[#0E1526] border border-[#1E2A44] rounded-lg px-3 py-2 text-[#4D5D80]">Chennai demo</button>
                </div>
                <button onClick={startBeacon} disabled={busy} className="w-full bg-cyan-500 hover:bg-cyan-400 disabled:opacity-50 text-[#06202A] font-bold rounded-xl px-4 py-3 text-sm transition-colors">
                  {busy ? "⏳ shuru ho raha…" : "🟢 VOYAGE BEACON SHURU KARO"}
                </button>
                {netStats && (
                  <div className={`mt-3 text-[11px] ${C.faint} text-center`}>
                    abhi network mein <span className="text-cyan-300 font-semibold">{netStats.active_boats}</span> live beacons · <span className={netStats.sos_active > 0 ? "text-red-400 font-semibold" : ""}>{netStats.sos_active}</span> SOS active
                  </div>
                )}
              </>
            ) : (
              <>
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <span className={`relative flex h-3 w-3`}>
                      <span className={`animate-ping absolute inline-flex h-full w-full rounded-full ${sos ? "bg-red-400" : "bg-emerald-400"} opacity-75`} />
                      <span className={`relative inline-flex rounded-full h-3 w-3 ${sos ? "bg-red-500" : "bg-emerald-400"}`} />
                    </span>
                    <span className={`text-sm font-bold ${sos ? "text-red-300" : "text-emerald-300"}`}>{sos ? "SOS broadcasting" : "Beacon LIVE"}</span>
                  </div>
                  <span className={`text-[10px] font-mono ${C.faint}`}>id {pubId}</span>
                </div>

                <div className="grid grid-cols-3 gap-2 mb-3 text-center">
                  <div className="bg-[#0A0E1A] border border-[#1E2A44] rounded-lg py-2">
                    <div className="text-lg font-bold text-white">{pings}</div>
                    <div className={`text-[9px] ${C.faint}`}>pings bheje</div>
                  </div>
                  <div className="bg-[#0A0E1A] border border-[#1E2A44] rounded-lg py-2">
                    <div className="text-lg font-bold text-white">{lastPingAt ? `${Math.round((Date.now() - lastPingAt) / 1000)}s` : "—"}</div>
                    <div className={`text-[9px] ${C.faint}`}>last ping age</div>
                  </div>
                  <div className="bg-[#0A0E1A] border border-[#1E2A44] rounded-lg py-2">
                    <div className="text-lg font-bold text-white">{nearbyRes?.count ?? 0}</div>
                    <div className={`text-[9px] ${C.faint}`}>boats 20 NM mein</div>
                  </div>
                </div>

                <div className="flex items-center gap-2 mb-3">
                  <label className={`text-xs ${C.faint}`}>Ping gap:</label>
                  {[5, 30].map((s) => (
                    <button key={s} onClick={() => setIntervalSec(s)}
                      className={`text-xs rounded-lg px-3 py-1.5 border ${intervalSec === s ? "border-cyan-400/60 text-cyan-300 bg-cyan-400/10" : "border-[#1E2A44] text-[#4D5D80]"}`}>
                      {s}s {s === 5 ? "(demo)" : "(asli voyage)"}
                    </button>
                  ))}
                </div>

                <div className="grid grid-cols-2 gap-2 mb-3">
                  <div>
                    <label className={`block text-xs ${C.faint} mb-1`}>Latitude <span className="text-[#34446A]">(ping yahi se jaata hai)</span></label>
                    <input className={C.input} value={latTxt} onChange={(e) => setLatTxt(e.target.value)} inputMode="decimal" />
                  </div>
                  <div>
                    <label className={`block text-xs ${C.faint} mb-1`}>Longitude</label>
                    <input className={C.input} value={lonTxt} onChange={(e) => setLonTxt(e.target.value)} inputMode="decimal" />
                  </div>
                </div>

                <input className={`${C.input} mb-3`} value={sosNote} onChange={(e) => setSosNote(e.target.value)} maxLength={140}
                  placeholder="SOS message (optional): 'engine fail, paani aa raha hai'" />

                {!sos ? (
                  <button onClick={fireSos} disabled={busy}
                    className={`w-full font-bold rounded-xl px-4 py-4 text-base transition-all ${sosConfirmUntil > Date.now()
                      ? "bg-red-500 text-white animate-pulse"
                      : "bg-red-950/60 hover:bg-red-900/60 text-red-300 border-2 border-red-500/70"}`}>
                    {sosConfirmUntil > Date.now() ? "⚠️ PAKKA? Dubara dabao — SOS chala jaayega" : "🚨 SOS — MUSHKIL MEIN HOON"}
                  </button>
                ) : (
                  <button onClick={clearSos} disabled={busy}
                    className="w-full bg-emerald-600 hover:bg-emerald-500 font-bold rounded-xl px-4 py-4 text-base text-white">
                    ✅ MAIN THEEK HOON — SOS band karo
                  </button>
                )}

                <button onClick={stopBeacon} disabled={busy}
                  className={`mt-2 w-full text-xs rounded-xl px-4 py-2.5 border transition-colors ${stopConfirmUntil > Date.now()
                    ? "border-amber-400/70 text-amber-300 bg-amber-400/10"
                    : "border-[#1E2A44] text-[#4D5D80] hover:text-[#9FB0D1]"}`}>
                  {stopConfirmUntil > Date.now() ? "⚠️ pakka? beacon band = position turant DELETE" : "⏹️ Voyage khatam — beacon band karo (poora delete)"}
                </button>

                <div className={`mt-3 text-[10px] ${C.faint} leading-relaxed`}>
                  Privacy promise: raw session id sirf tumhare paas — public mein sirf {pubId} dikhta hai. Beacon band ya 2 ghante silence → position ka koi record nahi bachta.
                </div>
              </>
            )}
          </div>

          {/* ── RIGHT: radar + boats ── */}
          <div className={`${C.card} rounded-xl p-4`}>
            <div className="flex items-center justify-between mb-2">
              <h2 className="text-sm font-bold text-white">🛰️ Paas ke ORCA boats <span className={`font-normal ${C.faint}`}>(20 NM · 10s auto-refresh)</span></h2>
              <span className={`text-[10px] font-mono ${C.faint}`}>{phase === "active" ? "LIVE" : "radar tab chalega jab beacon ON"}</span>
            </div>

            {phase === "active" ? (
              <>
                <Radar boats={otherBoats} radiusNm={20} selfSos={sos} />
                <div className="mt-3 space-y-2">
                  {otherBoats.length === 0 && (
                    <div className={`text-xs ${C.faint} text-center py-4 border border-dashed border-[#1E2A44] rounded-xl`}>
                      Abhi 20 NM mein koi doosra ORCA boat nahi — demo ke liye doosri window/device mein ek aur beacon kholo (coords thode door rakhna, e.g. 13.10, 80.31).
                    </div>
                  )}
                  {otherBoats.map((b) => (
                    <div key={b.pub_id}
                      className={`flex items-center gap-3 rounded-xl border px-3 py-2.5 ${b.sos ? "border-red-500/60 bg-red-950/30" : "border-[#1E2A44] bg-[#0A0E1A]"}`}>
                      <span className={`inline-block h-2.5 w-2.5 rounded-full ${b.sos ? "bg-red-500 animate-pulse" : "bg-slate-500"}`} />
                      <div className="min-w-0 flex-1">
                        <div className={`text-sm truncate ${b.sos ? "text-red-200 font-semibold" : "text-white"}`}>
                          {b.label ?? "ORCA boat"} <span className={`font-mono text-[10px] ${C.faint}`}>{b.pub_id}</span>
                        </div>
                        <div className={`text-[11px] ${C.faint}`}>
                          {typeof b.distance_nm === "number" ? `${b.distance_nm} NM` : "? NM"}
                          {typeof b.bearing_deg === "number" ? ` · ${b.bearing_deg}° ${compass(b.bearing_deg)}` : ""} · ping {fmtAge(b.age_sec)}
                          {b.sos && b.sos_note ? ` · "${b.sos_note}"` : ""}
                        </div>
                      </div>
                      {typeof b.bearing_deg === "number" && (
                        <span className={`text-base ${b.sos ? "text-red-300" : "text-slate-400"}`} style={{ transform: `rotate(${b.bearing_deg}deg)`, display: "inline-block" }}>➤</span>
                      )}
                      {b.sos && (
                        <button onClick={() => { setTrackId(b.pub_id); history.replaceState(null, "", `/live?track=${b.pub_id}`); }}
                          className="text-[11px] bg-red-500/20 hover:bg-red-500/30 border border-red-400/50 rounded-lg px-2.5 py-1.5 text-red-100 shrink-0">
                          🆘 Track
                        </button>
                      )}
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <div className={`text-xs ${C.faint} text-center py-10 border border-dashed border-[#1E2A44] rounded-xl leading-relaxed px-6`}>
                Pehle beacon shuru karo 👈 — phir yahan rescue radar jagega.<br />
                <span className="text-[#34446A]">Demo idea: 2 browser windows — Window A beacon @ 13.08,80.29 · Window B beacon @ 13.10,80.31 → A pe SOS dabao → B pe red alert + radar dot 🔴</span>
              </div>
            )}

            <div className={`mt-4 pt-3 border-t border-[#1E2A44] text-[10px] ${C.faint} leading-relaxed`}>
              <span className="text-[#9FB0D1] font-semibold">Honesty:</span> ye radar sirf backend ke REAL pings dikhata hai — is page pe koi fake/demo boat invent nahi hota. Position sirf utni purani jitna `age` likha hai; 12 h purana SOS server se automatically delete ho jaata hai. Bade ships ka live AIS swarm (aisstream.io integration) Phase 2 mein aa raha hai.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/** Rescue view ke andar: meri position se SOS boat tak ki doori/disha. */
function NearbyFromMe({ latTxt, lonTxt, myPubId }: { latTxt: string; lonTxt: string; myPubId: string }) {
  const [res, setRes] = useState<LiveNearbyResponse | null>(null);
  useEffect(() => {
    const lat = parseFloat(latTxt);
    const lon = parseFloat(lonTxt);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) { setRes(null); return; }
    let cancelled = false;
    const pull = async () => {
      try {
        const r = await liveNearby(lat, lon, 100);
        if (!cancelled) setRes(r);
      } catch { if (!cancelled) setRes(null); }
    };
    pull();
    const t = setInterval(pull, 10_000);
    return () => { cancelled = true; clearInterval(t); };
  }, [latTxt, lonTxt]);

  if (!res || res.boats.length === 0) return <div className={`mt-2 text-[11px] ${C.faint}`}>100 NM ke andar koi beacon nahi mila.</div>;
  return (
    <div className="mt-2 space-y-1.5">
      {res.boats.filter((b) => b.pub_id !== myPubId).slice(0, 4).map((b) => (
        <div key={b.pub_id} className={`flex items-center gap-2 text-[12px] rounded-lg border px-2.5 py-1.5 ${b.sos ? "border-red-500/50 text-red-200" : "border-[#1E2A44] text-[#9FB0D1]"}`}>
          <span className={`inline-block h-2 w-2 rounded-full ${b.sos ? "bg-red-500 animate-pulse" : "bg-slate-500"}`} />
          <span className="font-mono">{b.label ?? b.pub_id}</span>
          <span className="ml-auto">{b.distance_nm} NM · {b.bearing_deg}° {compass(b.bearing_deg ?? 0)}</span>
        </div>
      ))}
    </div>
  );
}
