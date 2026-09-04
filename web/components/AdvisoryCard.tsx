"use client";

import { useEffect, useState } from "react";
import { Advisory, DemoZone, fetchAdvisory } from "@/lib/orca-client";
import { t, Lang } from "@/lib/i18n";

const VERDICT_STYLE: Record<string, { bg: string; ring: string; label_en: string; label_hi: string }> = {
  go: { bg: "bg-green-600", ring: "ring-green-300", label_en: "GO", label_hi: "जा सकते हैं" },
  caution: { bg: "bg-amber-500", ring: "ring-amber-300", label_en: "CAUTION", label_hi: "सावधानी" },
  no_go: { bg: "bg-red-600", ring: "ring-red-300", label_en: "NO-GO", label_hi: "मत जाइए" },
};

function Tile({ label, value, sub, warn }: { label: string; value: string; sub?: string; warn?: boolean }) {
  return (
    <div className={`rounded-lg border p-3 bg-white ${warn ? "border-amber-400" : "border-slate-200"}`}>
      <div className="text-[10px] uppercase tracking-wide text-slate-500">{label}</div>
      <div className={`text-lg font-bold ${warn ? "text-amber-600" : "text-slate-800"}`}>{value}</div>
      {sub && <div className="text-[11px] text-slate-500">{sub}</div>}
    </div>
  );
}

export default function AdvisoryCard({
  zone,
  lang,
  advisory,
  setAdvisory,
}: {
  zone: DemoZone;
  lang: Lang;
  advisory: Advisory | null;
  setAdvisory: (a: Advisory | null) => void;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    setError(null);
    try {
      const a = await fetchAdvisory(zone.lat, zone.lon);
      setAdvisory(a);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [zone.lat, zone.lon]);

  if (loading && !advisory) {
    return (
      <div className="h-full flex items-center justify-center text-slate-500">
        <div className="text-center">
          <div className="text-3xl mb-2 animate-bounce">🌊</div>
          <p className="text-sm">{t(lang, "loading")}</p>
          <p className="text-xs mt-1 opacity-70">10 agents · 6 live sources weave into one verdict</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="h-full flex items-center justify-center">
        <div className="text-center max-w-sm">
          <div className="text-3xl mb-2">🔌</div>
          <p className="text-sm text-slate-600 mb-3">{error}</p>
          <button onClick={load} className="bg-blue-600 text-white rounded px-4 py-2 text-sm">
            {t(lang, "refresh")}
          </button>
        </div>
      </div>
    );
  }

  if (!advisory) return null;

  const v = advisory.variables;
  const st = VERDICT_STYLE[advisory.verdict] ?? VERDICT_STYLE.caution;
  const sw = advisory.safe_window;

  return (
    <div className="h-full overflow-y-auto bg-slate-100 p-4 space-y-4">
      {/* verdict banner: icon + shape + colour (readable by anyone) */}
      <div className={`rounded-xl ${st.bg} text-white p-5 shadow-lg ring-4 ${st.ring}`}>
        <div className="flex items-center justify-between">
          <div>
            <div className="text-4xl font-black flex items-center gap-3">
              <span>{advisory.icon}</span>
              <span>{lang === "hi" ? st.label_hi : st.label_en}</span>
            </div>
            <p className="mt-1 text-sm opacity-95">
              {lang === "hi" ? advisory.headline_hi : advisory.headline_en}
            </p>
          </div>
          <button
            onClick={load}
            disabled={loading}
            className="bg-white/20 hover:bg-white/30 rounded px-3 py-2 text-sm disabled:opacity-50"
          >
            {loading ? "…" : t(lang, "refresh")}
          </button>
        </div>
        <div className="mt-2 text-xs opacity-80">
          {t(lang, "advisory_for")} {zone.name} ({zone.lat.toFixed(2)}°N, {zone.lon.toFixed(2)}°E) ·{" "}
          {t(lang, "valid_until")} {advisory.valid_until.slice(11, 16)} UTC
        </div>
      </div>

      {/* variable tiles — every number is live */}
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
        <Tile label={`🌊 ${t(lang, "waves")} (${t(lang, "now")})`} value={v.wave_height_m != null ? `${v.wave_height_m} m` : "—"} warn={(v.wave_height_m ?? 0) >= 2.5} sub={`${t(lang, "peak_48h")}: ${advisory.outlook_48h?.wave_max_m ?? "—"} m · ${t(lang, "swell")}: ${v.swell_m ?? "—"} m`} />
        <Tile label={`💨 ${t(lang, "wind")} (${t(lang, "now")})`} value={v.wind_kts != null ? `${Math.round(v.wind_kts)} kn` : "—"} sub={`${t(lang, "gusts")}: ${v.gust_kts != null ? Math.round(v.gust_kts) : "—"} kn · ${t(lang, "peak_48h")}: ${advisory.outlook_48h?.gust_max_kn != null ? Math.round(advisory.outlook_48h.gust_max_kn) : "—"} kn`} warn={(v.gust_kts ?? 0) >= 28} />
        <Tile label={`🌡️ ${t(lang, "sst")}`} value={v.sst_c != null ? `${v.sst_c.toFixed(1)} °C` : "—"} />
        <Tile label={`🌀 ${t(lang, "current")}`} value={v.current_kn != null ? `${v.current_kn} kn` : "—"} sub={v.current_dir ?? undefined} />
        <Tile label={`🛰️ ${t(lang, "chlorophyll")}`} value={v.chlorophyll_mg_m3 != null ? `${v.chlorophyll_mg_m3.toFixed(2)} mg/m³` : "—"} sub={v.pfz_advisory_date ? `PFZ: ${v.pfz_advisory_date}` : undefined} />
        <Tile label={`🎣 ${t(lang, "nearest_pfz")}`} value={v.nearest_pfz_nm != null ? `${v.nearest_pfz_nm} NM` : "—"} sub={v.nearest_pfz_bearing ? `${v.nearest_pfz_bearing} · INCOIS` : "none nearby today"} />
        <Tile label={`⚠️ ${t(lang, "cyclone")}`} value={v.cyclone_dist_km != null ? `${v.cyclone_dist_km} km` : "✓ clear"} warn={v.cyclone_dist_km != null && v.cyclone_dist_km < 800} />
      </div>

      {/* safe window */}
      <div className="rounded-lg border border-slate-200 bg-white p-4">
        <h3 className="text-sm font-semibold mb-1">⏱️ {t(lang, "safe_window")}</h3>
        {sw.found ? (
          <p className="text-sm text-slate-700">
            <span className="font-mono font-semibold">{sw.from_utc?.slice(5, 16).replace("T", " ")}</span>
            {" → "}
            <span className="font-mono font-semibold">{sw.to_utc?.slice(5, 16).replace("T", " ")}</span> UTC
            <span className="ml-2 text-xs bg-green-100 text-green-800 rounded px-2 py-0.5">{sw.hours} h</span>
          </p>
        ) : (
          <p className="text-sm text-slate-500">{t(lang, "no_safe_window")} {sw.note ? `(${sw.note})` : ""}</p>
        )}
      </div>

      {/* reasons */}
      <div className="rounded-lg border border-slate-200 bg-white p-4">
        <h3 className="text-sm font-semibold mb-2">🔎 {t(lang, "reasons")}</h3>
        <ul className="space-y-1.5">
          {advisory.reasons.map((r, i) => (
            <li key={i} className="text-sm flex gap-2">
              <span className={
                r.severity === "no_go" ? "text-red-600" :
                r.severity === "caution" ? "text-amber-600" : "text-slate-400"
              }>
                {r.severity === "no_go" ? "⛔" : r.severity === "caution" ? "⚠️" : "ℹ️"}
              </span>
              <span className="text-slate-700">{r.msg}</span>
            </li>
          ))}
        </ul>
      </div>

      {/* sources footer — full transparency */}
      <div className="rounded-lg border border-slate-200 bg-white p-4 text-xs text-slate-500 space-y-1">
        <div><span className="font-semibold text-slate-600">{t(lang, "sources")}:</span> {advisory.sources.join(" · ")}</div>
        {advisory.sources_failed.length > 0 && (
          <div><span className="font-semibold text-slate-600">{t(lang, "failed_sources")}:</span> {advisory.sources_failed.join(" · ")}</div>
        )}
        <div className="italic">{advisory.disclaimer}</div>
        <div>{t(lang, "cyclone")}: {v.cyclone_note}</div>
      </div>
    </div>
  );
}
