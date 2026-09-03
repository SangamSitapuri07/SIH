"use client";

import { OrcaInsight } from "@/lib/orca-client";
import { t, Lang } from "@/lib/i18n";

const RISK_COLOR: Record<string, string> = {
  low: "bg-green-100 text-green-800 border-green-300",
  moderate: "bg-yellow-100 text-yellow-800 border-yellow-300",
  high: "bg-orange-100 text-orange-800 border-orange-300",
  critical: "bg-red-100 text-red-800 border-red-300",
  unknown: "bg-gray-100 text-gray-700 border-gray-300",
};

const RISK_DOT: Record<string, string> = {
  low: "🟢",
  moderate: "🟡",
  high: "🟠",
  critical: "🔴",
  unknown: "⚪",
};

const SEVERITY_COLOR: Record<string, string> = {
  good: "text-green-700",
  info: "text-gray-600",
  warn: "text-yellow-700",
  high: "text-orange-700",
  critical: "text-red-700",
  error: "text-red-700",
};

const AGENT_EMOJI: Record<string, string> = {
  ocean: "🌊",
  satellite: "🛰️",
  weather: "🌦️",
  gis: "🗺️",
  fisheries: "🎣",
  marine_ecology: "🐟",
  marine_risk: "🚨",
  anomaly: "📈",
  validation: "🔍",
};

const AGENT_LABEL: Record<string, { en: string; hi: string }> = {
  ocean: { en: "Ocean Analysis", hi: "समुद्र विश्लेषण" },
  satellite: { en: "Satellite Analysis", hi: "सैटेलाइट विश्लेषण" },
  weather: { en: "Weather", hi: "मौसम" },
  gis: { en: "GIS / Location", hi: "GIS / लोकेशन" },
  fisheries: { en: "Fisheries / PFZ", hi: "मत्स्य / PFZ" },
  marine_ecology: { en: "Marine Ecology", hi: "समुद्री पारिस्थितिकी" },
  marine_risk: { en: "Marine Risk", hi: "समुद्री जोखिम" },
  anomaly: { en: "Anomaly Detection", hi: "विसंगति जाँच" },
  validation: { en: "Data Validation", hi: "डेटा जाँच" },
};

interface Props {
  insight: OrcaInsight | null;
  loading: boolean;
  zoneName: string;
  lang: Lang;
}

/** "NOAA ERDDAP: timeout after 12s" -> ["NOAA ERDDAP", "timeout after 12s"] */
function splitFailure(f: string): [string, string] {
  const i = f.indexOf(":");
  if (i === -1) return [f, ""];
  return [f.slice(0, i), f.slice(i + 1).trim()];
}

export default function InsightPanel({ insight, loading, zoneName, lang }: Props) {
  if (loading) {
    return (
      <div className="p-6 text-gray-600 space-y-3">
        <div className="animate-pulse text-base font-medium">
          ⏳ {t(lang, "loading")}
        </div>
        <div className="text-sm text-gray-500 leading-relaxed">
          {t(lang, "panel_loading_hint")}
        </div>
      </div>
    );
  }
  if (!insight) {
    return (
      <div className="p-6 text-gray-500 text-sm leading-relaxed">
        👆 {t(lang, "panel_click_anywhere")}
      </div>
    );
  }

  const cov = insight.data_coverage;
  const coverageLimited = cov != null && cov.known < cov.total;
  // Agents WITH real measurements first; no-data agents sink to the bottom
  const agents = [...insight.agents].sort((a, b) => {
    const an = a.risk_level === "unknown" ? 1 : 0;
    const bn = b.risk_level === "unknown" ? 1 : 0;
    return an - bn;
  });

  return (
    <div className="p-5 space-y-4 overflow-y-auto h-full">
      <div>
        <h2 className="text-xl font-bold text-gray-900 leading-tight">{zoneName}</h2>
        <p className="text-xs text-gray-500 mt-0.5">
          {insight.zone.lat.toFixed(2)}°, {insight.zone.lon.toFixed(2)}° · {insight.zone.date}
        </p>
      </div>

      {/* Overall risk */}
      <div className={`rounded-lg border px-4 py-3 ${RISK_COLOR[insight.overall_risk] || RISK_COLOR.unknown}`}>
        <div className="text-[11px] font-semibold uppercase tracking-wider opacity-70">
          {t(lang, "panel_overall_risk")}
        </div>
        <div className="text-2xl font-extrabold leading-snug">
          {RISK_DOT[insight.overall_risk] || ""} {insight.overall_risk.toUpperCase()}
        </div>
        {coverageLimited && (
          <div className="mt-1 text-xs opacity-80 leading-snug">
            {cov!.known}/{cov!.total} {t(lang, "panel_coverage")}
            {cov!.sources_failed > 0 ? ` · ${cov!.sources_failed} ${lang === "hi" ? "स्रोत बंद" : "source(s) down"}` : ""}
          </div>
        )}
      </div>

      {/* Recommendation */}
      <div className="rounded-lg border border-gray-200 bg-white px-4 py-3">
        <div className="text-[11px] font-semibold uppercase tracking-wider text-gray-500 mb-1">
          {t(lang, "panel_recommendation")}
        </div>
        <div className="text-sm font-medium text-gray-900 leading-relaxed">
          {insight.recommendation}
        </div>
      </div>

      {/* Summary */}
      <div className="rounded-lg border border-gray-200 bg-gray-50 px-4 py-3">
        <div className="text-[11px] font-semibold uppercase tracking-wider text-gray-500 mb-1">
          {t(lang, "panel_summary")}
        </div>
        <div className="text-sm text-gray-700 leading-relaxed whitespace-pre-line">
          {insight.summary}
        </div>
      </div>

      {/* Data sources */}
      <div>
        <div className="text-[11px] font-semibold uppercase tracking-wider text-gray-500 mb-1.5">
          {t(lang, "panel_sources_used")}
        </div>
        <div className="flex flex-wrap gap-1.5">
          {insight.data_sources_used.map((s) => (
            <span key={s} className="text-xs bg-emerald-50 text-emerald-700 border border-emerald-200 px-2 py-1 rounded-md">
              ✓ {s}
            </span>
          ))}
        </div>
        {insight.data_sources_failed.length > 0 && (
          <details className="mt-2 rounded-lg border border-red-200 bg-red-50/60 px-3 py-2">
            <summary className="cursor-pointer text-xs font-medium text-red-700">
              ⚠️ {insight.data_sources_failed.length} {t(lang, "panel_failed_n")}
            </summary>
            <ul className="mt-2 space-y-1.5">
              {insight.data_sources_failed.map((f) => {
                const [label, why] = splitFailure(f);
                return (
                  <li key={f} className="text-xs leading-relaxed">
                    <span className="font-semibold text-red-800">{label}</span>
                    {why && <span className="text-red-700/90"> — {why}</span>}
                  </li>
                );
              })}
            </ul>
          </details>
        )}
      </div>

      {/* Per-agent breakdown */}
      <div>
        <div className="text-[11px] font-semibold uppercase tracking-wider text-gray-500 mb-1.5">
          {t(lang, "panel_agents_n")} ({insight.agents.length})
        </div>
        <div className="space-y-2">
          {agents.map((a) => {
            const noData = a.risk_level === "unknown";
            const label = AGENT_LABEL[a.agent];
            return (
              <details
                key={a.agent}
                className={`rounded-lg border bg-white px-3 py-2 ${
                  noData ? "border-gray-200 opacity-70" : "border-gray-300"
                }`}
              >
                <summary className="cursor-pointer flex items-center gap-2 list-none">
                  <span className="min-w-0 flex-1 text-sm font-medium text-gray-800 leading-snug break-words">
                    {AGENT_EMOJI[a.agent] || "•"} {label ? (lang === "hi" ? label.hi : label.en) : a.agent}
                  </span>
                  {noData ? (
                    <span className="shrink-0 text-[11px] px-2 py-0.5 rounded-md bg-gray-100 text-gray-500 border border-gray-200">
                      {t(lang, "panel_no_data")}
                    </span>
                  ) : (
                    <span className={`shrink-0 text-[11px] px-2 py-0.5 rounded-md border ${RISK_COLOR[a.risk_level] || RISK_COLOR.unknown}`}>
                      {a.risk_level}
                    </span>
                  )}
                </summary>
                <div className="mt-2 text-xs text-gray-600 leading-relaxed">{a.summary}</div>
                {a.findings.length > 0 && (
                  <ul className="mt-2 space-y-1">
                    {a.findings.map((f, i) => (
                      <li key={i} className={`text-xs leading-relaxed ${SEVERITY_COLOR[f.severity] || ""}`}>
                        <span className="font-mono opacity-60">[{f.severity}]</span> {f.msg}
                      </li>
                    ))}
                  </ul>
                )}
              </details>
            );
          })}
        </div>
      </div>

      <div className="text-[11px] text-gray-400 pb-2">
        {t(lang, "panel_fetched")}: {new Date(insight.fetched_at).toLocaleString()}
      </div>
    </div>
  );
}
