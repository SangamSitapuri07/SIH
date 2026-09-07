"use client";

/**
 * Visual Explorer — full-screen map where every dot is a REAL sampled
 * measurement around the clicked point. Three switchable layers:
 *   🎣 Fish spots  (chlorophyll productivity hotspots — green/size)
 *   🌊 Waves       (color + size by height, m)
 *   💨 Wind        (color + size by speed, kn)
 * Plus the 48h trend strip (same arrays as the verdict) and the
 * ranked hotspot list. Zero illustration, zero mock — every dot is API data.
 */
import { useEffect, useMemo, useState } from "react";
import { MapContainer, TileLayer, CircleMarker, Tooltip, Polyline } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import Sparkline from "@/components/Sparkline";
import { Lang } from "@/lib/i18n";
import { fetchField, FieldResponse } from "@/lib/orca-client";

type Trend = { labels: string[]; wave_m: (number | null)[]; wind_kn: (number | null)[]; gust_kn: (number | null)[] };

type LayerId = "chl" | "waves" | "wind";

/* color ramps — readable on dark tiles */
function chlColor(v: number): string {
  if (v >= 5) return "#ef4444";      // bloom-level
  if (v >= 2) return "#f59e0b";      // high
  if (v >= 0.5) return "#34d399";    // productive
  return "#475569";                  // low
}
function waveColor(v: number): string {
  if (v >= 4) return "#ef4444";
  if (v >= 2.5) return "#f59e0b";
  if (v >= 1.2) return "#22d3ee";
  return "#38bdf8";
}
function windColor(v: number): string {
  if (v >= 34) return "#ef4444";     // gale
  if (v >= 28) return "#f59e0b";
  if (v >= 15) return "#a78bfa";
  return "#818cf8";
}

export default function FieldExplorer({
  lat, lon, lang, trend, onClose,
}: {
  lat: number; lon: number;
  lang: Lang;
  trend?: Trend | null;          // advisory hourly_chart when available
  onClose: () => void;
}) {
  const [data, setData] = useState<FieldResponse | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [layer, setLayer] = useState<LayerId>("chl");

  useEffect(() => {
    let alive = true;
    setErr(null); setData(null);
    fetchField(lat, lon)
      .then((j) => { if (alive) setData(j); })
      .catch((e) => {
        if (alive) setErr(lang === "hi"
          ? `फ़ील्ड डेटा नहीं आया — backend चल रहा है? (${e instanceof Error ? e.message : e})`
          : `Field data failed — is the backend running? (${e instanceof Error ? e.message : e})`);
      });
    return () => { alive = false; };
  }, [lat, lon, lang]);

  const spots = useMemo(() => {
    if (!data) return [];
    if (layer === "chl") return data.chl.points;
    return data.met.points;
  }, [data, layer]);

  const LAYERS: { id: LayerId; label: string; labelHi: string; unit: string }[] = [
    { id: "chl", label: "Fish spots (chlorophyll)", labelHi: "मछली के ठिकाने (क्लोरोफिल)", unit: "mg/m³" },
    { id: "waves", label: "Waves", labelHi: "लहरें", unit: "m" },
    { id: "wind", label: "Wind", labelHi: "हवा", unit: "kn" },
  ];

  return (
    <div className="fixed inset-0 z-[2000] bg-[#070D1A]/97 flex flex-col fade-up">
      {/* header */}
      <div className="shrink-0 flex items-center justify-between px-4 py-3 border-b border-[#16233C]">
        <div className="flex items-center gap-3 flex-wrap">
          <h2 className="text-base font-bold text-white">
            🔬 {lang === "hi" ? "विज़ुअल एक्सप्लोरर" : "Visual Explorer"}
          </h2>
          <span className="text-[11px] text-slate-500 font-mono">{lat.toFixed(2)}°N, {lon.toFixed(2)}°E · ±1.2°</span>
          {/* layer switcher */}
          <div className="flex gap-1 bg-[#0E1729] border border-[#1C2A45] rounded-lg p-0.5">
            {LAYERS.map((l) => (
              <button
                key={l.id}
                onClick={() => setLayer(l.id)}
                className={`text-xs rounded-md px-3 py-1.5 transition ${
                  layer === l.id ? "bg-cyan-500/15 text-cyan-300 font-semibold" : "text-slate-400 hover:text-slate-200"
                }`}
              >
                {lang === "hi" ? l.labelHi : l.label}
              </button>
            ))}
          </div>
        </div>
        <button
          onClick={onClose}
          className="text-slate-400 hover:text-white text-xl leading-none px-2 py-1"
          aria-label="close"
        >
          ✕
        </button>
      </div>

      {/* body */}
      <div className="flex-1 min-h-0 grid grid-cols-1 lg:grid-cols-[2fr_1fr]">
        {/* map */}
        <div className="relative">
          {!data && !err && (
            <div className="absolute inset-0 flex items-center justify-center text-slate-400 text-sm z-[1001] bg-[#070D1A]/80">
              ⏳ {lang === "hi" ? "असली ग्रिड सैंपल हो रहा है… (NOAA + Open-Meteo)" : "Sampling the real grid… (NOAA + Open-Meteo)"}
            </div>
          )}
          {err && (
            <div className="absolute inset-0 flex items-center justify-center text-red-300 text-sm z-[1001]">{err}</div>
          )}
          <MapContainer center={[lat, lon]} zoom={9} style={{ height: "100%", width: "100%", background: "#070D1A" }}>
            <TileLayer
              attribution="&copy; OpenStreetMap &copy; CARTO"
              url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
            />
            {/* center point */}
            <CircleMarker center={[lat, lon]} radius={9}
              pathOptions={{ color: "#22d3ee", weight: 2.5, fillColor: "#22d3ee", fillOpacity: 0.4 }}>
              <Tooltip permanent direction="top" offset={[0, -10]}>📍 {lang === "hi" ? "आपका बिंदु" : "Your point"}</Tooltip>
            </CircleMarker>
            {/* hotspot lines (chl layer) */}
            {layer === "chl" && data?.hotspots.map((h, i) => (
              <Polyline key={`hs-${i}`} positions={[[lat, lon], [h.lat, h.lon]]}
                pathOptions={{ color: "#34d399", weight: 1.5, dashArray: "4 6", opacity: 0.6 }} />
            ))}
            {/* data spots */}
            {spots.map((p, i) => {
              const v = layer === "chl" ? p.chl : layer === "waves" ? p.wave_m : p.wind_kn;
              if (v == null) return null;
              const color = layer === "chl" ? chlColor(v as number) : layer === "waves" ? waveColor(v as number) : windColor(v as number);
              const radius = layer === "chl"
                ? Math.min(13, 4 + Math.sqrt(v as number) * 3)
                : Math.min(12, 4 + (v as number) * 1.6);
              const isHot = layer === "chl" && data?.hotspots.some((h) => h.lat === p.lat && h.lon === p.lon);
              return (
                <CircleMarker
                  key={`sp-${i}`}
                  center={[p.lat, p.lon]}
                  radius={radius}
                  pathOptions={{
                    color, weight: isHot ? 3 : 1.5,
                    fillColor: color, fillOpacity: isHot ? 0.75 : 0.5,
                  }}
                >
                  <Tooltip>
                    <div className="text-xs">
                      <strong>{p.lat.toFixed(2)}°, {p.lon.toFixed(2)}°</strong><br />
                      {p.chl != null && <>🎣 chl: <b>{p.chl}</b> mg/m³<br /></>}
                      {p.wave_m != null && <>🌊 waves: <b>{p.wave_m}</b> m (swell {p.swell_m ?? "—"} m)<br /></>}
                      {p.wind_kn != null && <>💨 wind: <b>{p.wind_kn}</b> kn, gusts {p.gust_kn ?? "—"} kn<br /></>}
                      {p.current_kn != null && <>🌀 current: {p.current_kn} kn</>}
                    </div>
                  </Tooltip>
                </CircleMarker>
              );
            })}
          </MapContainer>
          {/* legend */}
          <div className="absolute bottom-3 left-3 z-[1000] surface-2 px-3 py-2 text-[10px] text-slate-400 space-y-1">
            {layer === "chl" && (
              <>
                <div className="font-semibold text-slate-300 mb-1">{lang === "hi" ? "क्लोरोफिल (mg/m³)" : "Chlorophyll (mg/m³)"}</div>
                <div><span className="inline-block h-2 w-2 rounded-full" style={{ background: "#475569" }} /> &lt;0.5 low · <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#34d399" }} /> 0.5-2 productive · <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#f59e0b" }} /> 2-5 high · <span className="inline-block h-2 w-2 rounded-full" style={{ background: "#ef4444" }} /> &gt;5 bloom</div>
                <div className="text-slate-600">{lang === "hi" ? "ज़्यादा chl = ज़्यादा प्लांक्टन = मछली का खाना" : "more chl = more plankton = fish food"}</div>
              </>
            )}
            {layer === "waves" && <div><span style={{ color: "#38bdf8" }}>●</span> &lt;1.2 calm · <span style={{ color: "#22d3ee" }}>●</span> 1.2-2.5 · <span style={{ color: "#f59e0b" }}>●</span> 2.5-4 caution · <span style={{ color: "#ef4444" }}>●</span> &gt;4 unsafe</div>}
            {layer === "wind" && <div><span style={{ color: "#818cf8" }}>●</span> &lt;15 kn · <span style={{ color: "#a78bfa" }}>●</span> 15-28 · <span style={{ color: "#f59e0b" }}>●</span> 28-34 caution · <span style={{ color: "#ef4444" }}>●</span> &gt;34 gale</div>}
          </div>
        </div>

        {/* right panel */}
        <div className="border-l border-[#16233C] overflow-y-auto p-4 space-y-4 bg-[#0A1120]">
          {/* hotspots */}
          <div>
            <div className="text-[11px] font-semibold uppercase tracking-wider text-emerald-300/90 mb-2">
              🎣 {lang === "hi" ? "टॉप मछली-हॉटस्पॉट" : "Top productivity hotspots"}
              {data?.chl.date ? <span className="text-slate-600 normal-case font-normal"> · NOAA {data.chl.date}</span> : ""}
            </div>
            {!data ? (
              <div className="text-xs text-slate-500">…</div>
            ) : data.hotspots.length === 0 ? (
              <div className="text-xs text-slate-500">
                {lang === "hi" ? "इस ग्रिड में chl डेटा नहीं (बादल/सीमा) — नीचे असली कारण देखें।" : "No chl data in this grid (clouds/edge) — real reason below."}
                {data.chl.error && <div className="mt-1 text-red-400/80">chlorophyll: {data.chl.error}</div>}
              </div>
            ) : (
              <ul className="space-y-1.5">
                {data.hotspots.map((h, i) => (
                  <li key={i} className="surface px-3 py-2 text-xs flex items-center justify-between gap-2">
                    <span className="text-slate-200 font-medium">
                      #{i + 1} · {h.lat.toFixed(2)}°N, {h.lon.toFixed(2)}°E
                    </span>
                    <span className="text-slate-400 text-right">
                      <b className="text-emerald-300">{h.chl}</b> mg/m³<br />
                      {h.distance_nm} NM {h.bearing}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {/* trends (same arrays as the verdict) */}
          {trend && trend.labels.length > 1 && (
            <div className="space-y-3">
              <div className="text-[11px] font-semibold uppercase tracking-wider text-slate-500">
                📈 {lang === "hi" ? "आपके बिंदु का ट्रेंड (48 घंटे)" : "Your point — 48 h trend"}
              </div>
              <div className="surface p-3">
                <div className="text-[10px] text-slate-500 mb-1">🌊 Waves (m)</div>
                <Sparkline values={trend.wave_m} warnAt={2.5} dangerAt={4} unit=" m" />
              </div>
              <div className="surface p-3">
                <div className="text-[10px] text-slate-500 mb-1">💨 Wind gusts (kn)</div>
                <Sparkline values={trend.gust_kn} warnAt={28} dangerAt={34} unit=" kn" color="#a78bfa" />
              </div>
            </div>
          )}

          {/* data provenance */}
          {data && (
            <div className="surface p-3 text-[10px] text-slate-500 space-y-1">
              <div><span className="text-slate-300 font-semibold">chlorophyll:</span> {data.chl.source ?? "—"}{data.chl.error ? ` · ⚠️ ${data.chl.error}` : ` · ${data.chl.n} cells`}</div>
              <div><span className="text-slate-300 font-semibold">waves/wind:</span> {data.met.source ?? "—"}{data.met.error ? ` · ⚠️ ${data.met.error}` : ` · ${data.met.n} cells`}</div>
              <div className="italic pt-1">{data.note}</div>
              <div>generated: {new Date(data.generated_at).toLocaleString()}</div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
