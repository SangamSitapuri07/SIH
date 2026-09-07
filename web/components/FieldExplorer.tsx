"use client";

/**
 * Visual Explorer — full-screen REAL map (OpenStreetMap tiles, same as
 * the main map) where every dot is a REAL sampled measurement around
 * the clicked point. Six switchable layers, one per data family:
 *   🎣 Fish spots  (chlorophyll productivity — NOAA VIIRS, real pixels)
 *   🌊 Waves       (height, m — Open-Meteo marine model)
 *   〰️ Swell        (long-period swell, m)
 *   💨 Wind gusts  (kn — the number that capsizes small boats)
 *   🌀 Current     (surface current, kn)
 *   🌡️ SST         (sea-surface temperature, °C)
 * Plus the 48 h evidence charts (same arrays as the verdict) and the
 * ranked hotspot list. Zero illustration, zero mock — every dot is API
 * data; failed sources show their real error.
 */
import { useEffect, useMemo, useState } from "react";
import dynamic from "next/dynamic";
import { MapContainer, TileLayer, CircleMarker, Tooltip, Polyline } from "react-leaflet";
import "leaflet/dist/leaflet.css";
import LineChart from "@/components/LineChart";
import { Lang } from "@/lib/i18n";
import { fetchField, FieldPoint, FieldResponse } from "@/lib/orca-client";
import { chlColor, waveColor, windColor, currentColor, sstColor } from "@/components/fieldColors";

const Ocean3D = dynamic(() => import("@/components/Ocean3D"), { ssr: false });

type Trend = {
  labels: string[];
  wave_m: (number | null)[];
  swell_m?: (number | null)[];
  wind_kn: (number | null)[];
  gust_kn: (number | null)[];
  current_kn?: (number | null)[];
  sst_c?: (number | null)[];
};

type LayerId = "chl" | "wave" | "swell" | "wind" | "current" | "sst";

const LAYERS: {
  id: LayerId; label: string; labelHi: string; unit: string;
  color: (v: number) => string;
  radius: (v: number) => number;
  legend: string; legendHi: string;
  fromChl?: boolean;
}[] = [
  {
    id: "chl", label: "Fish spots", labelHi: "मछली के ठिकाने", unit: "mg/m³",
    color: chlColor, fromChl: true,
    radius: (v) => Math.min(13, 4 + Math.sqrt(v) * 3),
    legend: "chlorophyll: <0.5 low · 0.5-2 productive · 2-5 high · >5 bloom",
    legendHi: "क्लोरोफिल: <0.5 कम · 0.5-2 अच्छा · 2-5 ज़्यादा · >5 ब्लूम",
  },
  {
    id: "wave", label: "Waves", labelHi: "लहरें", unit: "m",
    color: waveColor,
    radius: (v) => Math.min(12, 3.5 + v * 2.2),
    legend: "waves: <1.2 calm · 1.2-2.5 workable · 2.5-4 caution · >4 unsafe",
    legendHi: "लहरें: <1.2 शांत · 1.2-2.5 चलने लायक · 2.5-4 सावधानी · >4 खतरनाक",
  },
  {
    id: "swell", label: "Swell", labelHi: "उमड़ी (swell)", unit: "m",
    color: waveColor,
    radius: (v) => Math.min(12, 3.5 + v * 2.2),
    legend: "swell: long rollers — ≥2.5 m makes landing/beaching risky",
    legendHi: "swell: लंबी उमड़ती लहरें — 2.5 m+ पर किनारे उतरना जोखिम",
  },
  {
    id: "wind", label: "Wind gusts", labelHi: "हवा (gusts)", unit: "kn",
    color: windColor,
    radius: (v) => Math.min(12, 3 + v * 0.28),
    legend: "gusts: <15 fine · 15-28 watchful · 28-34 caution · >34 gale",
    legendHi: "झोंके: <15 ठीक · 15-28 नज़र रखें · 28-34 सावधानी · >34 तूफ़ान",
  },
  {
    id: "current", label: "Current", labelHi: "धारा", unit: "kn",
    color: currentColor,
    radius: (v) => Math.min(12, 3.5 + v * 2),
    legend: "current: <0.6 weak · 0.6-1.5 normal · 1.5-3 strong · >3 very strong",
    legendHi: "धारा: <0.6 कमज़ोर · 0.6-1.5 सामान्य · 1.5-3 तेज़ · >3 बहुत तेज़",
  },
  {
    id: "sst", label: "SST", labelHi: "समुद्र तापमान", unit: "°C",
    color: sstColor,
    radius: () => 8,  // SST varies by fractions of a degree — colour honestly, no fake sizing
    legend: "SST: <26 cool · 26-28.5 baitfish band · 28.5-30 warm · >30 hot",
    legendHi: "तापमान: <26 ठंडा · 26-28.5 मछली-बैंड · 28.5-30 गर्म · >30 बहुत गर्म",
  },
];

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
  const [view, setView] = useState<"map" | "3d">("map");

  useEffect(() => {
    let alive = true;
    setErr(null); setData(null); setLayer("chl"); setView("map");
    fetchField(lat, lon)
      .then((j) => { if (alive) setData(j); })
      .catch((e) => {
        if (alive) setErr(lang === "hi"
          ? `फ़ील्ड डेटा नहीं आया — backend चल रहा है? (${e instanceof Error ? e.message : e})`
          : `Field data failed — is the backend running? (${e instanceof Error ? e.message : e})`);
      });
    return () => { alive = false; };
  }, [lat, lon, lang]);

  const active = LAYERS.find((l) => l.id === layer)!;
  const spots = useMemo(() => {
    if (!data) return [];
    return active.fromChl ? data.chl.points : data.met.points;
  }, [data, active]);

  const valOf = (p: FieldPoint): number | null | undefined => {
    switch (layer) {
      case "chl": return p.chl;
      case "wave": return p.wave_m;
      case "swell": return p.swell_m;
      case "wind": return p.gust_kn ?? p.wind_kn;
      case "current": return p.current_kn;
      case "sst": return p.sst_c;
    }
  };

  const has = (a?: (number | null)[]) => !!a && a.some((v) => v != null);

  return (
    <div className="fixed inset-0 z-[2000] bg-[#070D1A]/97 flex flex-col fade-up">
      {/* header */}
      <div className="shrink-0 flex items-start justify-between px-4 py-2.5 border-b border-[#16233C] gap-2">
        <div className="flex items-center gap-2.5 flex-wrap min-w-0">
          <h2 className="text-base font-bold text-white shrink-0">
            🔬 {lang === "hi" ? "विज़ुअल एक्सप्लोरर" : "Visual Explorer"}
          </h2>
          <span className="text-[11px] text-slate-500 font-mono shrink-0">{lat.toFixed(2)}°N, {lon.toFixed(2)}°E · ±1.2°</span>
          {/* view toggle: 2D map vs living 3D ocean (same real data) */}
          <div className="flex gap-1 bg-[#0E1729] border border-[#1C2A45] rounded-lg p-1 shrink-0">
            <button
              onClick={() => setView("map")}
              className={`text-[11px] rounded-md px-2.5 py-1.5 transition ${
                view === "map" ? "bg-cyan-500/15 text-cyan-300 font-semibold" : "text-slate-400 hover:text-slate-200"
              }`}
            >
              🗺️ {lang === "hi" ? "नक्शा" : "Map"}
            </button>
            <button
              onClick={() => setView("3d")}
              disabled={!data || !data.met.points.length}
              title={!data ? (lang === "hi" ? "पहले grid load होने दो" : "wait for the grid to load") : undefined}
              className={`text-[11px] rounded-md px-2.5 py-1.5 transition disabled:opacity-40 ${
                view === "3d" ? "bg-cyan-500/15 text-cyan-300 font-semibold" : "text-slate-400 hover:text-slate-200"
              }`}
            >
              🌊 {lang === "hi" ? "3D समुद्र" : "3D Ocean"}
            </button>
          </div>
          {/* layer switcher (map view) — wraps on small screens */}
          {view === "map" && (
            <div className="flex flex-wrap gap-1 bg-[#0E1729] border border-[#1C2A45] rounded-lg p-1">
              {LAYERS.map((l) => (
                <button
                  key={l.id}
                  onClick={() => setLayer(l.id)}
                  className={`text-[11px] rounded-md px-2.5 py-1.5 transition ${
                    layer === l.id ? "bg-cyan-500/15 text-cyan-300 font-semibold" : "text-slate-400 hover:text-slate-200"
                  }`}
                >
                  {lang === "hi" ? l.labelHi : l.label}
                </button>
              ))}
            </div>
          )}
        </div>
        <button
          onClick={onClose}
          className="text-slate-400 hover:text-white text-xl leading-none px-2 py-1 shrink-0"
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
            <div className="absolute inset-0 flex items-center justify-center text-slate-200 text-sm z-[1001] bg-[#070D1A]/85 text-center px-6">
              ⏳ {lang === "hi"
                ? "असली ग्रिड सैंपल हो रहा है… (NOAA satellite + Open-Meteo models — पहली बार 15-30 सेकंड लग सकते हैं)"
                : "Sampling the real grid… (NOAA satellite + Open-Meteo models — first load can take 15-30 s)"}
            </div>
          )}
          {err && (
            <div className="absolute inset-0 flex items-center justify-center text-red-300 text-sm z-[1001] px-6 text-center">{err}</div>
          )}
          {view === "3d" && data ? (
            <Ocean3D key={`${lat}:${lon}:${data.generated_at}`} data={data} lang={lang} />
          ) : (
          <>
          <MapContainer center={[lat, lon]} zoom={9} style={{ height: "100%", width: "100%", background: "#070D1A" }}>
            <TileLayer
              attribution="&copy; OpenStreetMap contributors"
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            {/* center point */}
            <CircleMarker center={[lat, lon]} radius={8}
              pathOptions={{ color: "#0ea5e9", weight: 3, fillColor: "#22d3ee", fillOpacity: 0.55 }}>
              <Tooltip permanent direction="top" offset={[0, -10]}>📍 {lang === "hi" ? "आपका बिंदु" : "Your point"}</Tooltip>
            </CircleMarker>
            {/* hotspot lines (chl layer) */}
            {layer === "chl" && data?.hotspots.map((h, i) => (
              <Polyline key={`hs-${i}`} positions={[[lat, lon], [h.lat, h.lon]]}
                pathOptions={{ color: "#059669", weight: 2, dashArray: "5 6", opacity: 0.75 }} />
            ))}
            {/* data spots */}
            {spots.map((p, i) => {
              const v = valOf(p);
              if (v == null) return null;
              const color = active.color(v as number);
              const isHot = layer === "chl" && data?.hotspots.some((h) => h.lat === p.lat && h.lon === p.lon);
              return (
                <CircleMarker
                  key={`${layer}-sp-${i}`}
                  center={[p.lat, p.lon]}
                  radius={active.radius(v as number)}
                  pathOptions={{
                    color: "#0B1322", weight: isHot ? 3 : 1,
                    fillColor: color, fillOpacity: isHot ? 0.95 : 0.78,
                  }}
                >
                  <Tooltip>
                    <div className="text-xs">
                      <strong>{p.lat.toFixed(2)}°, {p.lon.toFixed(2)}°</strong><br />
                      {p.chl != null && <>🎣 chl: <b>{p.chl}</b> mg/m³<br /></>}
                      {p.wave_m != null && <>🌊 waves: <b>{p.wave_m}</b> m · swell {p.swell_m ?? "—"} m<br /></>}
                      {p.wind_kn != null && <>💨 wind: <b>{p.wind_kn}</b> kn · gusts <b>{p.gust_kn ?? "—"}</b> kn<br /></>}
                      {p.current_kn != null && <>🌀 current: <b>{p.current_kn}</b> kn<br /></>}
                      {p.sst_c != null && <>🌡️ SST: <b>{p.sst_c}</b> °C</>}
                    </div>
                  </Tooltip>
                </CircleMarker>
              );
            })}
          </MapContainer>
          {/* legend */}
          <div className="absolute bottom-3 left-3 z-[1000] surface-2 px-3 py-2 text-[10px] text-slate-300 space-y-1 max-w-[320px]">
            <div className="font-semibold text-slate-100">
              {lang === "hi" ? active.labelHi : active.label} ({active.unit})
            </div>
            <div>{lang === "hi" ? active.legendHi : active.legend}</div>
            {layer === "chl" && (
              <div className="text-slate-500">{lang === "hi" ? "ज़्यादा chl = ज़्यादा प्लांक्टन = मछली का खाना" : "more chl = more plankton = fish food"}</div>
            )}
          </div>
          </>
          )}
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

          {/* 48 h evidence charts (same arrays as the verdict) */}
          {trend && trend.labels.length > 1 && (
            <div className="space-y-3">
              <div className="text-[11px] font-semibold uppercase tracking-wider text-slate-500">
                📈 {lang === "hi" ? "आपके बिंदु का ट्रेंड (48 घंटे)" : "Your point — 48 h trend"}
              </div>
              <div className="surface p-3">
                <div className="text-[10px] text-slate-500 mb-1">🌊 {lang === "hi" ? "लहरें + swell (m)" : "Waves + swell (m)"}</div>
                <LineChart
                  labels={trend.labels} unit=" m"
                  series={[
                    { label: lang === "hi" ? "लहरें" : "waves", values: trend.wave_m, color: "#22d3ee" },
                    ...(has(trend.swell_m) ? [{ label: "swell", values: trend.swell_m!, color: "#818cf8", dashed: true }] : []),
                  ]}
                  thresholds={[
                    { value: 2.5, color: "#f59e0b", label: "2.5" },
                    { value: 4, color: "#ef4444", label: "4" },
                  ]}
                />
              </div>
              <div className="surface p-3">
                <div className="text-[10px] text-slate-500 mb-1">💨 {lang === "hi" ? "हवा + gusts (kn)" : "Wind + gusts (kn)"}</div>
                <LineChart
                  labels={trend.labels} unit=" kn"
                  series={[
                    { label: lang === "hi" ? "हवा" : "wind", values: trend.wind_kn, color: "#a78bfa" },
                    { label: "gusts", values: trend.gust_kn, color: "#f472b6", dashed: true },
                  ]}
                  thresholds={[
                    { value: 20, color: "#f59e0b", label: "20" },
                    { value: 34, color: "#ef4444", label: "34" },
                  ]}
                />
              </div>
              {has(trend.current_kn) && (
                <div className="surface p-3">
                  <div className="text-[10px] text-slate-500 mb-1">🌀 {lang === "hi" ? "धारा (kn)" : "Current (kn)"}</div>
                  <LineChart
                    labels={trend.labels} unit=" kn"
                    series={[{ label: "current", values: trend.current_kn!, color: "#34d399" }]}
                    thresholds={[{ value: 3, color: "#f59e0b", label: "3" }]}
                  />
                </div>
              )}
              {has(trend.sst_c) && (
                <div className="surface p-3">
                  <div className="text-[10px] text-slate-500 mb-1">🌡️ SST (°C)</div>
                  <LineChart
                    labels={trend.labels} unit="°C"
                    series={[{ label: "SST", values: trend.sst_c!, color: "#fbbf24" }]}
                  />
                </div>
              )}
            </div>
          )}

          {/* data provenance */}
          {data && (
            <div className="surface p-3 text-[10px] text-slate-500 space-y-1">
              <div><span className="text-slate-300 font-semibold">chlorophyll:</span> {data.chl.source ?? "—"}{data.chl.error ? ` · ⚠️ ${data.chl.error}` : ` · ${data.chl.n} cells`}</div>
              <div><span className="text-slate-300 font-semibold">waves/wind/current/SST:</span> {data.met.source ?? "—"}{data.met.error ? ` · ⚠️ ${data.met.error}` : ` · ${data.met.n} cells`}</div>
              <div className="italic pt-1">{data.note}</div>
              <div>generated: {new Date(data.generated_at).toLocaleString()}</div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
