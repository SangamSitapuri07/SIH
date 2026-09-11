"use client";

/* B19 — ORCA Live Beacon "Samudri Rakshak Net" (web lab, MRCC-style dispatch).
 * Workflow (research: real maritime SAR / MRCC — Maritime Rescue
 * Coordination Centre ka standard):
 *   MAYDAY → fisher 1-tap SOS (kuch type/copy NAHI)
 *   TRACE  → backend KHUD nearest beacons dhoondhta hai
 *   RELAY  → un boats ke ping mein hi RESCUE REQUEST (accept/decline)
 *   ACK    → accepted rescuer ka live doori/bearing/ETA victim tak
 *   ESCALATE → 60s no-accept → radius 10→25→50 NM aur boats ko
 *   RESOLVE → victim "theek hoon" ya rescuer "pahunch gaya"
 * Is page pe koi fake/demo boat invent nahi hota — sab backend se. */

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  LiveBoat,
  LiveNearbyResponse,
  LiveStats,
  MySosStatus,
  RescueRequestPayload,
  fmtLat,
  fmtLon,
  liveBoat,
  liveNearby,
  livePing,
  liveRescueAnswer,
  liveRescueComplete,
  liveSos,
  liveSosClear,
  liveStart,
  liveStats,
  liveStop,
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

function Trend({ prev, cur }: { prev: number | undefined; cur: number }) {
  if (prev === undefined) return null;
  if (cur < prev - 0.02) return <span className="text-emerald-400 font-bold" title="qareeb aa raha">↓</span>;
  if (cur > prev + 0.02) return <span className="text-amber-400 font-bold" title="door ja raha">↑</span>;
  return <span className="text-[#4D5D80]">→</span>;
}

/* ── SVG rescue radar — REAL bearing+distance. SOS = pulsing red,
 *    madad mein gayi boat = teal ring (on_rescue social badge). ── */
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
    <svg viewBox={`0 0 ${size} ${size}`} className="w-full max-w-[330px] mx-auto select-none" role="img" aria-label="rescue radar">
      <circle cx={cx} cy={cx} r={maxR + 8} fill="#0A1020" stroke="#1E2A44" />
      {[0.25, 0.5, 0.75, 1].map((f) => (
        <circle key={f} cx={cx} cy={cx} r={maxR * f} fill="none" stroke="#16233C" strokeDasharray={f === 1 ? "" : "3 4"} />
      ))}
      <line x1={cx} y1={10} x2={cx} y2={size - 10} stroke="#16233C" />
      <line x1={10} y1={cx} x2={size - 10} y2={cx} stroke="#16233C" />
      <text x={cx + 4} y={24} fill="#4D5D80" fontSize={10}>N</text>
      <text x={cx + maxR - 10} y={cx - 4} fill="#4D5D80" fontSize={9}>{radiusNm} NM</text>
      <text x={cx + maxR / 2 - 8} y={cx - 4} fill="#33436B" fontSize={9}>{Math.round(radiusNm / 2)} NM</text>
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
            {b.on_rescue && !b.sos && <circle cx={x} cy={y} r={8} fill="none" stroke="#2DD4BF" strokeWidth={1.4} strokeDasharray="3 2" />}
            <circle cx={x} cy={y} r={b.sos ? 5.5 : 4} fill={b.sos ? "#EF4444" : b.on_rescue ? "#2DD4BF" : "#64748B"} stroke={b.sos ? "#FCA5A5" : "#94A3B8"} strokeWidth={0.8} />
            <text x={x + 8} y={y + 3} fill={b.sos ? "#FCA5A5" : b.on_rescue ? "#5EEAD4" : "#64748B"} fontSize={9} fontFamily="monospace">
              {b.label ?? b.pub_id}{typeof b.distance_nm === "number" ? ` · ${b.distance_nm}NM` : ""}
            </text>
          </g>
        );
      })}
    </svg>
  );
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
  const [mySos, setMySos] = useState<MySosStatus | null>(null);
  const [resolvedMsg, setResolvedMsg] = useState<string | null>(null);
  const [rescueReq, setRescueReq] = useState<RescueRequestPayload | null>(null);
  const [rescueEndedMsg, setRescueEndedMsg] = useState<string | null>(null);
  const [nearbyRes, setNearbyRes] = useState<LiveNearbyResponse | null>(null);
  const [netStats, setNetStats] = useState<LiveStats | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState(false);
  const [accTrends, setAccTrends] = useState<Record<string, number>>({});
  const [trackId, setTrackId] = useState<string | null>(null);
  const [trackBoat, setTrackBoat] = useState<LiveBoat | null>(null);
  const [trackErr, setTrackErr] = useState<string | null>(null);
  const [tick, setTick] = useState(0);

  const coordsRef = useRef<{ lat: number; lon: number }>({ lat: 13.08, lon: 80.29 });
  const sessionRef = useRef("");
  sessionRef.current = session;
  const sosRef = useRef(false);
  sosRef.current = sos;
  const prevAccRef = useRef<Record<string, number>>({});
  const prevRescDistRef = useRef<number | null>(null);
  const resolvedShownRef = useRef<string | null>(null);
  const labelRef = useRef("");
  labelRef.current = label;
  /** ping-loop rescue-request accepted-state compare ke liye */
  const rescueWasAcceptedRef = useRef(false);

  const myCoords = useCallback((): { lat: number; lon: number } | null => {
    const lat = parseFloat(latTxt);
    const lon = parseFloat(lonTxt);
    if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
    coordsRef.current = { lat, lon };
    return { lat, lon };
  }, [latTxt, lonTxt]);

  /* ── mount: rescue mode? resume session? stats? ── */
  useEffect(() => {
    try {
      const q = new URLSearchParams(window.location.search);
      const t = q.get("track");
      if (t) setTrackId(t);
      const s = sessionStorage.getItem(SESS_KEY);
      const p = sessionStorage.getItem(PUB_KEY);
      const l = sessionStorage.getItem(LABEL_KEY);
      if (s && p) {
        setSession(s); setPubId(p);
        if (l) setLabel(l);
        setPhase("active");
      }
    } catch { /* SSR safety */ }
    liveStats().then(setNetStats).catch(() => setNetStats(null));
  }, []);

  /* ── ping loop — ping hi alert channel hai (request + status sab andar) ── */
  useEffect(() => {
    if (phase !== "active" || !session) return;
    let cancelled = false;
    const beat = async () => {
      const c = coordsRef.current;
      try {
        const r = await livePing(sessionRef.current, c.lat, c.lon, { label: labelRef.current || undefined });
        if (cancelled) return;
        setPings((n) => n + 1);
        setLastPingAt(Date.now());
        setErr(null);
        setMySos(r.my_sos);
        // rescuer: request aayi/gayi?
        const hadAccepted = rescueWasAcceptedRef.current;
        rescueWasAcceptedRef.current = r.rescue_request?.my_state === "accepted";
        setRescueReq(r.rescue_request);
        if (hadAccepted && !r.rescue_request && !cancelled) {
          setRescueEndedMsg("Rescue case band ho gaya — ho sakta hai victim theek ho gaya ho ya rescue complete ho gaya ho. 🙏");
        }
        if (!r.rescue_request) prevRescDistRef.current = null;
        // victim: rescuer ne complete kiya?
        if (r.sos_resolved && resolvedShownRef.current !== r.sos_resolved.case_id) {
          resolvedShownRef.current = r.sos_resolved.case_id;
          setSos(false); setMySos(null);
          setResolvedMsg(r.sos_resolved.by === "rescuer"
            ? "✅ RESCUE HO GAYA — rescuer ne 'pahunch gaya / sab safe' mark kiya. Tumhara SOS auto-clear ho gaya."
            : "SOS case close ho gaya.");
        }
      } catch (e) {
        if (!cancelled) setErr(`Ping fail — network/backend? (${e instanceof Error ? e.message : String(e)}) — ORCA retry karta rahega; position FAKE nahi hogi kabhi.`);
      }
    };
    beat();
    const t = setInterval(beat, Math.max(3, intervalSec) * 1000);
    return () => { cancelled = true; clearInterval(t); };
  }, [phase, session, intervalSec]);

  /* victim: accepted rescuers ke distance trends */
  useEffect(() => {
    if (!mySos) { prevAccRef.current = {}; setAccTrends({}); return; }
    const trends: Record<string, number> = {};
    for (const a of mySos.accepted) trends[a.pub_id] = prevAccRef.current[a.pub_id] ?? a.distance_nm;
    prevAccRef.current = Object.fromEntries(mySos.accepted.map((a) => [a.pub_id, a.distance_nm]));
    setAccTrends(trends);
  }, [mySos]);

  /* ── radar refresh ── */
  useEffect(() => {
    if (phase !== "active" && !trackId) return;
    let cancelled = false;
    const pull = async () => {
      const c = coordsRef.current;
      try {
        const r = await liveNearby(c.lat, c.lon, 20);
        if (!cancelled) setNearbyRes(r);
      } catch { if (!cancelled) setNearbyRes(null); }
    };
    pull();
    const t = setInterval(pull, 10_000);
    return () => { cancelled = true; clearInterval(t); };
  }, [phase, trackId]);

  /* ── rescue view poll (family / share link) ── */
  useEffect(() => {
    if (!trackId) return;
    let cancelled = false;
    const pull = async () => {
      try {
        const r = await liveBoat(trackId);
        if (!cancelled) { setTrackBoat(r.boat); setTrackErr(null); }
      } catch (e) {
        if (!cancelled) { setTrackBoat(null); setTrackErr(e instanceof Error ? e.message : String(e)); }
      }
    };
    pull();
    const t = setInterval(pull, 5_000);
    return () => { cancelled = true; clearInterval(t); };
  }, [trackId]);

  useEffect(() => {
    const t = setInterval(() => setTick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, []);
  void tick;

  const useMyGps = () => {
    if (!navigator.geolocation) { setErr("Is browser mein geolocation nahi — coords type kar do."); return; }
    setBusy(true);
    navigator.geolocation.getCurrentPosition(
      (pos) => { setLatTxt(pos.coords.latitude.toFixed(5)); setLonTxt(pos.coords.longitude.toFixed(5)); setBusy(false); },
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
      setSession(r.session); setPubId(r.pub_id); setPhase("active"); setErr(null);
      try {
        sessionStorage.setItem(SESS_KEY, r.session);
        sessionStorage.setItem(PUB_KEY, r.pub_id);
        sessionStorage.setItem(LABEL_KEY, label.trim());
      } catch { /* private mode */ }
    } catch (e) { setErr(e instanceof Error ? e.message : String(e)); }
    setBusy(false);
  };

  const fireSos = async () => {
    const nowT = Date.now();
    if (sosConfirmUntil < nowT) { setSosConfirmUntil(nowT + 4000); return; }
    setSosConfirmUntil(0);
    const c = myCoords();
    setBusy(true);
    try {
      const r = await liveSos(session, sosNote.trim() || undefined, c?.lat, c?.lon);
      setSos(true);
      setMySos(r.case);
      setResolvedMsg(null);
      setErr(null);
    } catch (e) { setErr(e instanceof Error ? e.message : String(e)); }
    setBusy(false);
  };

  const clearSos = async () => {
    setBusy(true);
    try {
      await liveSosClear(session);
      setSos(false); setMySos(null); setErr(null);
    } catch (e) { setErr(e instanceof Error ? e.message : String(e)); }
    setBusy(false);
  };

  const answerRescue = async (accept: boolean) => {
    if (!rescueReq) return;
    setBusy(true);
    try {
      const r = await liveRescueAnswer(session, rescueReq.case_id, accept);
      if (accept && r.rescue) setRescueReq(r.rescue);
      if (!accept) setRescueReq(null);
      setErr(null);
    } catch (e) { setErr(e instanceof Error ? e.message : String(e)); }
    setBusy(false);
  };

  const completeRescue = async () => {
    if (!rescueReq) return;
    setBusy(true);
    try {
      await liveRescueComplete(session, rescueReq.case_id);
      setRescueReq(null);
      setRescueEndedMsg("✅ TUMNE RESCUE COMPLETE MARK KIYA — ek zindagi bachayi. Victim ka SOS auto-clear ho gaya. 🙏");
    } catch (e) { setErr(e instanceof Error ? e.message : String(e)); }
    setBusy(false);
  };

  const stopBeacon = async () => {
    const nowT = Date.now();
    if (stopConfirmUntil < nowT) { setStopConfirmUntil(nowT + 4000); return; }
    setStopConfirmUntil(0);
    setBusy(true);
    try { await liveStop(session); } catch { /* best-effort */ }
    try { sessionStorage.removeItem(SESS_KEY); sessionStorage.removeItem(PUB_KEY); sessionStorage.removeItem(LABEL_KEY); } catch { /* noop */ }
    setSession(""); setPubId(""); setPhase("idle"); setSos(false); setMySos(null);
    setRescueReq(null); setResolvedMsg(null); setRescueEndedMsg(null);
    setPings(0); setLastPingAt(null); setNearbyRes(null);
    liveStats().then(setNetStats).catch(() => setNetStats(null));
    setBusy(false);
  };

  const shareUrl = typeof window !== "undefined" && pubId
    ? `${window.location.origin}/live?track=${pubId}` : `/live?track=${pubId}`;

  const copyShare = async () => {
    try { await navigator.clipboard.writeText(shareUrl); setCopied(true); setTimeout(() => setCopied(false), 2000); }
    catch { setErr("Clipboard block hai — link manually copy kar lo."); }
  };

  const otherBoats = (nearbyRes?.boats ?? []).filter((b) => b.pub_id !== pubId);
  const sosBoats = otherBoats.filter((b) => b.sos);
  const rescTrendPrev = rescueReq ? (prevRescDistRef.current ?? undefined) : undefined;
  if (rescueReq) prevRescDistRef.current = rescueReq.distance_nm;

  /* ══════════════════ RESCUE VIEW (share link) ══════════════════ */
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
              <div className={`mt-2 text-xs ${C.faint}`}>ORCA kabhi purani/fake position nahi dikhata — beacon band/expire ho gaya toh seedha bolte hain.</div>
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
                {trackBoat.sos_note && (<><div className={C.faint}>Message</div><div className="text-amber-200">{trackBoat.sos_note}</div></>)}
                {typeof trackBoat.speed_kn === "number" && (<><div className={C.faint}>Speed</div><div>{trackBoat.speed_kn} kn {typeof trackBoat.heading_deg === "number" ? `· ${trackBoat.heading_deg}° ${compass(trackBoat.heading_deg)}` : ""}</div></>)}
              </div>
              <div className={`mt-3 pt-3 border-t border-[#1E2A44] text-xs ${C.faint} leading-relaxed`}>
                📡 Har 5 sec auto-refresh · VHF Ch 16 pe bulate raho · Indian Coast Guard <span className="text-white font-semibold">1554</span> · SOLAS Reg 33: paas ki har badi ship legally madad karne ko bound hai.
              </div>
            </div>
          )}
          <div className={`mt-4 text-[11px] ${C.faint} leading-relaxed text-center`}>
            Yeh link family/rescue team ke liye hai — live track jab tak beacon ON hai. Fishermen ke beech ki madad app ke andar hi hoti hai (uske liye link ki zaroorat nahi).
          </div>
        </div>
      </div>
    );
  }

  /* ══════════════════ BEACON VIEW ══════════════════ */
  return (
    <div className={`min-h-screen ${C.bg} text-white flex flex-col items-center px-4 py-6`}>
      <div className="w-full max-w-5xl">
        <div className="flex items-center justify-between mb-4 flex-wrap gap-2">
          <div>
            <h1 className="text-lg font-bold tracking-tight">📡 Live Beacon <span className="text-cyan-300/90">· Samudri Rakshak Net</span></h1>
            <p className={`text-xs ${C.faint} mt-0.5`}>1-tap SOS → system KHUD paas ke boats trace karke unhe request bhejta hai — fishermen rescuing fishermen</p>
          </div>
          <Link href="/" className="text-xs text-cyan-300 hover:text-cyan-200 border border-[#1E2A44] rounded-lg px-3 py-1.5">← ORCA home</Link>
        </div>

        {err && <div className="mb-4 rounded-xl border border-red-500/50 bg-red-950/30 px-4 py-3 text-sm text-red-200">{err}</div>}

        {/* ═══ RESCUE REQUEST (mujh pe aayi) ═══ */}
        {rescueReq && (
          <div className={`mb-4 rounded-xl border-2 ${rescueReq.my_state === "accepted" ? "border-emerald-500 bg-emerald-950/30" : "border-amber-400 bg-amber-950/30"} px-4 py-4`}>
            <div className="flex items-center gap-2 mb-2">
              <span className="relative flex h-3.5 w-3.5">
                <span className={`animate-ping absolute inline-flex h-full w-full rounded-full ${rescueReq.my_state === "accepted" ? "bg-emerald-400" : "bg-amber-400"} opacity-75`} />
                <span className={`relative inline-flex rounded-full h-3.5 w-3.5 ${rescueReq.my_state === "accepted" ? "bg-emerald-500" : "bg-amber-400"}`} />
              </span>
              <span className={`font-bold ${rescueReq.my_state === "accepted" ? "text-emerald-200" : "text-amber-200"}`}>
                {rescueReq.my_state === "accepted" ? "🚤 TUM MADAD PE JA RAHE HO — course yeh raha" : "🆘 RESCUE REQUEST — paas mein ek bhai mushkil mein hai!"}
              </span>
            </div>
            <div className="grid sm:grid-cols-3 gap-2 text-sm mb-3">
              <div className="bg-black/30 border border-[#1E2A44] rounded-lg px-3 py-2">
                <div className={`text-[10px] ${C.faint}`}>Victim</div>
                <div className="font-semibold text-white">{rescueReq.victim.label ?? rescueReq.victim.pub_id}</div>
                {rescueReq.victim.sos_note && <div className="text-[11px] text-amber-200 mt-0.5">"{rescueReq.victim.sos_note}"</div>}
              </div>
              <div className="bg-black/30 border border-[#1E2A44] rounded-lg px-3 py-2">
                <div className={`text-[10px] ${C.faint}`}>Doori · disha (tumse)</div>
                <div className="font-bold text-lg text-white">
                  {rescueReq.distance_nm} NM <Trend prev={rescTrendPrev} cur={rescueReq.distance_nm} />
                  <span className={`text-sm ${C.body}`}> · {rescueReq.bearing_deg}° {compass(rescueReq.bearing_deg)}</span>
                  <span className="inline-block text-cyan-300" style={{ transform: `rotate(${rescueReq.bearing_deg}deg)` }}> ➤</span>
                </div>
              </div>
              <div className="bg-black/30 border border-[#1E2A44] rounded-lg px-3 py-2">
                <div className={`text-[10px] ${C.faint}`}>SOS kitna purana</div>
                <div className="text-white">{rescueReq.victim.sos_age_sec !== undefined ? fmtAge(rescueReq.victim.sos_age_sec) : fmtAge(rescueReq.offer_age_sec)}</div>
                {rescueReq.my_state !== "accepted" && (
                  <div className={`text-[10px] mt-0.5 ${rescueReq.expires_in_sec < 120 ? "text-red-400" : C.faint}`}>
                    request {Math.floor(rescueReq.expires_in_sec / 60)}:{String(rescueReq.expires_in_sec % 60).padStart(2, "0")} min mein expire
                  </div>
                )}
              </div>
            </div>
            {rescueReq.my_state === "accepted" ? (
              <div className="flex gap-2 flex-wrap">
                <button onClick={completeRescue} disabled={busy}
                  className="flex-1 min-w-[220px] bg-emerald-600 hover:bg-emerald-500 font-bold rounded-xl px-4 py-3.5 text-white">
                  ✅ PAHUNCH GAYA / SAB SAFE — rescue complete
                </button>
                <div className={`text-[11px] ${C.faint} basis-full`}>Course har ping pe taaza hota rehta hai (doori ↓ ghat rahi hai toh sahi ja rahe ho). VHF Ch 16 se contact karte raho.</div>
              </div>
            ) : (
              <div className="flex gap-2 flex-wrap">
                <button onClick={() => answerRescue(true)} disabled={busy}
                  className="flex-1 min-w-[180px] bg-emerald-600 hover:bg-emerald-500 font-bold rounded-xl px-4 py-3.5 text-white text-base">
                  ✅ MADAD KARUNGA — course milega
                </button>
                <button onClick={() => answerRescue(false)} disabled={busy}
                  className="bg-[#0A0E1A] hover:bg-[#0E1526] border border-[#1E2A44] rounded-xl px-4 py-3.5 text-[#9FB0D1]">
                  ❌ Nahi paaunga
                </button>
              </div>
            )}
          </div>
        )}

        {rescueEndedMsg && !rescueReq && (
          <div className="mb-4 rounded-xl border border-emerald-500/50 bg-emerald-950/30 px-4 py-3 text-sm text-emerald-200 flex items-start justify-between gap-3">
            <span>{rescueEndedMsg}</span>
            <button onClick={() => setRescueEndedMsg(null)} className="text-emerald-300/70 hover:text-emerald-200 text-xs shrink-0">✕</button>
          </div>
        )}

        {/* ═══ MERA SOS + DISPATCH STATUS ═══ */}
        {sos && (
          <div className="mb-4 rounded-xl border-2 border-red-500 bg-red-950/50 px-4 py-4">
            <div className="flex items-center gap-2">
              <span className="relative flex h-3.5 w-3.5">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-75" />
                <span className="relative inline-flex rounded-full h-3.5 w-3.5 bg-red-500" />
              </span>
              <span className="text-red-200 font-bold">SOS BROADCAST HO RAHA HAI 🔴</span>
            </div>

            {mySos && (
              <>
                <div className="mt-3 flex flex-wrap gap-2">
                  <span className="text-xs bg-black/40 border border-red-500/40 rounded-lg px-2.5 py-1.5 text-red-100">🛰️ <b>{mySos.dispatched}</b> boats ko request gayi ({mySos.tier_nm} NM)</span>
                  <span className="text-xs bg-black/40 border border-[#1E2A44] rounded-lg px-2.5 py-1.5 text-[#9FB0D1]">👀 <b>{mySos.seen}</b> ne dekha</span>
                  {mySos.declined > 0 && <span className="text-xs bg-black/40 border border-[#1E2A44] rounded-lg px-2.5 py-1.5 text-[#9FB0D1]">❌ <b>{mySos.declined}</b> ne mana</span>}
                  <span className={`text-xs rounded-lg px-2.5 py-1.5 border ${mySos.accepted.length ? "border-emerald-400/60 bg-emerald-400/10 text-emerald-200" : "border-[#1E2A44] bg-black/40 text-[#4D5D80]"}`}>
                    ✅ <b>{mySos.accepted.length}</b> AA {mySos.accepted.length === 1 ? "RAHA HAI" : "RAHE HAIN"}
                  </span>
                </div>

                {mySos.status === "open" && mySos.accepted.length === 0 && (
                  <div className="mt-2 text-xs text-amber-300/90 bg-amber-400/10 border border-amber-400/30 rounded-lg px-3 py-2">
                    ⏳ {mySos.escalate_in_sec !== null
                      ? `Koi accept nahi? System KHUD radius badha dega — abhi ${mySos.tier_nm} NM, ${mySos.escalate_in_sec}s mein ${mySos.tiers_nm[Math.min((mySos.tiers_nm.indexOf(mySos.tier_nm) + 1), mySos.tiers_nm.length - 1)]} NM tak aur boats ko request jaayegi.`
                      : `Maximum radius (${mySos.tier_nm} NM) tak request jaa chuki — Coast Guard 1554 / VHF Ch 16 bhi try karo.`}
                  </div>
                )}

                {mySos.accepted.length > 0 && (
                  <div className="mt-3 space-y-2">
                    {mySos.accepted.map((a) => (
                      <div key={a.pub_id} className="rounded-xl border border-emerald-400/50 bg-emerald-950/30 px-4 py-3">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-emerald-300 font-bold">🚤 {a.label ?? "ORCA boat"} MADAD PE AA RAHA HAI</span>
                          {typeof a.eta_min === "number"
                            ? <span className="text-xs bg-emerald-400/20 border border-emerald-400/40 rounded-lg px-2 py-1 text-emerald-100">ETA ~{a.eta_min} min</span>
                            : <span className={`text-xs ${C.faint}`}>(speed unknown — doori live dekho, ETA invent nahi karenge)</span>}
                        </div>
                        <div className="mt-1 text-sm text-emerald-100">
                          <b className="text-lg">{a.distance_nm} NM</b> <Trend prev={accTrends[a.pub_id]} cur={a.distance_nm} /> · {a.bearing_deg}° {compass(a.bearing_deg)}
                          <span className="inline-block text-emerald-300" style={{ transform: `rotate(${a.bearing_deg}deg)` }}> ➤</span>
                          <span className={`text-xs ml-2 ${a.age_sec > 60 ? "text-amber-300" : C.faint}`}>· uska ping {fmtAge(a.age_sec)}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}

            <div className="mt-3 text-xs text-red-300/80">Himmat rakho. Coast Guard <span className="font-bold text-white">1554</span> · VHF Ch 16 se paas ki ships bulao (SOLAS Reg 33: wo legally aane ko bound hain).</div>
            <div className={`mt-2 pt-2 border-t border-red-500/20 flex items-center gap-2 flex-wrap`}>
              <span className={`text-[10px] ${C.faint}`}>family/rescue team ke liye backup link:</span>
              <code className="text-[10px] bg-black/40 border border-red-500/30 rounded-lg px-2 py-1 text-red-100/80 break-all">{shareUrl}</code>
              <button onClick={copyShare} className="text-[10px] bg-red-500/10 hover:bg-red-500/20 border border-red-400/40 rounded-lg px-2 py-1 text-red-100/80">
                {copied ? "✅ copied" : "copy"}
              </button>
            </div>
          </div>
        )}

        {resolvedMsg && !sos && (
          <div className="mb-4 rounded-xl border border-emerald-500/60 bg-emerald-950/40 px-4 py-3 text-sm text-emerald-200 flex items-start justify-between gap-3">
            <span>{resolvedMsg}</span>
            <button onClick={() => setResolvedMsg(null)} className="text-emerald-300/70 hover:text-emerald-200 text-xs shrink-0">✕</button>
          </div>
        )}

        <div className="grid gap-4 lg:grid-cols-[1fr_1.1fr]">
          {/* ── LEFT: beacon control ── */}
          <div className={`${C.card} rounded-xl p-4`}>
            {phase === "idle" ? (
              <>
                <h2 className="text-sm font-bold text-white mb-1">▶️ Beacon shuru karo</h2>
                <p className={`text-xs ${C.body} mb-3 leading-relaxed`}>
                  Voyage ke waqt tumhara phone ek AIS-transponder ban jaata hai — anonymous, tumhare control mein. SOS dabate hi system paas ke boats ko khud se request bhejta hai; tumhe sirf madad ka intezaar karna hai.
                </p>
                <label className={`block text-xs ${C.faint} mb-1`}>Boat ka naam <span className="text-[#34446A]">(optional — boats isi naam se pehchanengi)</span></label>
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
                    abhi network mein <span className="text-cyan-300 font-semibold">{netStats.active_boats}</span> live beacons · <span className={netStats.sos_active > 0 ? "text-red-400 font-semibold" : ""}>{netStats.sos_active}</span> SOS
                  </div>
                )}
                <div className={`mt-4 pt-3 border-t border-[#1E2A44] text-[11px] ${C.faint} leading-relaxed`}>
                  <span className="text-[#9FB0D1] font-semibold">SOS ke baad kya hota hai (automatic):</span><br />
                  1️⃣ backend paas ke beacons trace karta hai (10 NM)<br />
                  2️⃣ unhe request jaati hai — ✅ madad / ❌ mana<br />
                  3️⃣ jo accept kare uski live doori + ETA tumhe dikhti hai<br />
                  4️⃣ 60s mein koi accept nahi → 25 → 50 NM tak badhta hai
                </div>
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
                    <label className={`block text-xs ${C.faint} mb-1`}>Latitude</label>
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
              <h2 className="text-sm font-bold text-white">🛰️ Paas ke ORCA boats <span className={`font-normal ${C.faint}`}>(20 NM · 10s refresh)</span></h2>
              <span className={`text-[10px] font-mono ${C.faint}`}>{phase === "active" ? "LIVE" : "radar tab chalega jab beacon ON"}</span>
            </div>

            {phase === "active" ? (
              <>
                <Radar boats={otherBoats} radiusNm={20} selfSos={sos} />
                <div className="mt-3 space-y-2">
                  {otherBoats.length === 0 && (
                    <div className={`text-xs ${C.faint} text-center py-4 border border-dashed border-[#1E2A44] rounded-xl`}>
                      Abhi 20 NM mein koi doosra ORCA boat nahi — demo ke liye doosri window/device mein ek aur beacon kholo (coords thode door, e.g. 13.10, 80.31).
                    </div>
                  )}
                  {otherBoats.map((b) => (
                    <div key={b.pub_id}
                      className={`flex items-center gap-3 rounded-xl border px-3 py-2.5 ${b.sos ? "border-red-500/60 bg-red-950/30" : "border-[#1E2A44] bg-[#0A0E1A]"}`}>
                      <span className={`inline-block h-2.5 w-2.5 rounded-full ${b.sos ? "bg-red-500 animate-pulse" : b.on_rescue ? "bg-teal-400" : "bg-slate-500"}`} />
                      <div className="min-w-0 flex-1">
                        <div className={`text-sm truncate ${b.sos ? "text-red-200 font-semibold" : "text-white"}`}>
                          {b.label ?? "ORCA boat"} <span className={`font-mono text-[10px] ${C.faint}`}>{b.pub_id}</span>
                          {b.on_rescue && !b.sos && <span className="ml-1.5 text-[10px] bg-teal-400/15 border border-teal-400/40 rounded px-1.5 py-0.5 text-teal-300">🚤 madad mein</span>}
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
                    </div>
                  ))}
                </div>
              </>
            ) : (
              <div className={`text-xs ${C.faint} text-center py-10 border border-dashed border-[#1E2A44] rounded-xl leading-relaxed px-6`}>
                Pehle beacon shuru karo 👈 — phir yahan rescue radar jagega.<br />
                <span className="text-[#34446A]">Demo: Window A beacon @ 13.08,80.29 → SOS · Window B beacon @ 13.10,80.31 → RESCUE REQUEST aayegi ✅/❌ · accept karo toh dono taraf live tracking + ETA</span>
              </div>
            )}

            <div className={`mt-4 pt-3 border-t border-[#1E2A44] text-[10px] ${C.faint} leading-relaxed`}>
              <span className="text-[#9FB0D1] font-semibold">Honesty:</span> radar sirf backend ke REAL pings dikhata hai — is page pe koi fake/demo boat invent nahi hota. Doori/bearing/ETA sab REAL GPS pings se; speed na ho toh ETA nahi dikhate. Request marzi se accept hoti hai — koi force nahi. Position utni hi purani jitna `age` likha hai; 12 h purana SOS server se auto-delete.
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

/* Rescue-view ke andar helper — ab simple reh gaya (family view). */
