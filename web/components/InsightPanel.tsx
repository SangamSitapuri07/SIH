"use client";

import { OrcaInsight } from "@/lib/orca-client";

const RISK_COLOR: Record<string, string> = {
  low: "bg-green-100 text-green-800 border-green-300",
  moderate: "bg-yellow-100 text-yellow-800 border-yellow-300",
  high: "bg-orange-100 text-orange-800 border-orange-300",
  critical: "bg-red-100 text-red-800 border-red-300",
  unknown: "bg-gray-100 text-gray-800 border-gray-300",
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
  fisheries: "🎣",
  marine_ecology: "🐟",
  marine_risk: "🚨",
  validation: "✅",
};

const AGENT_LABEL: Record<string, string> = {
  ocean: "Ocean Analysis",
  satellite: "Satellite Analysis",
  fisheries: "Fisheries / PFZ",
  marine_ecology: "Marine Ecology",
  marine_risk: "Marine Risk",
  validation: "Data Validation",
};

interface Props {
  insight: OrcaInsight | null;
  loading: boolean;
  zoneName: string;
}

export default function InsightPanel({ insight, loading, zoneName }: Props) {
  if (loading) {
    return (
      <div className="p-6 text-gray-500">
        <div className="animate-pulse">Analyzing {zoneName}…</div>
      </div>
    );
  }
  if (!insight) {
    return (
      <div className="p-6 text-gray-500">
        Click a marker on the map to analyze a zone.
      </div>
    );
  }

  return (
    <div className="p-6 space-y-4 overflow-y-auto h-full">
      <div>
        <h2 className="text-2xl font-bold text-gray-900">{zoneName}</h2>
        <p className="text-sm text-gray-500">
          {insight.zone.lat.toFixed(2)}°N, {insight.zone.lon.toFixed(2)}°E · {insight.zone.date}
        </p>
      </div>

      {/* Overall risk */}
      <div className={`rounded-lg border p-4 ${RISK_COLOR[insight.overall_risk] || RISK_COLOR.unknown}`}>
        <div className="text-xs uppercase tracking-wider opacity-70">Overall Risk</div>
        <div className="text-3xl font-bold">{insight.overall_risk.toUpperCase()}</div>
      </div>

      {/* Recommendation */}
      <div className="rounded-lg border border-gray-200 bg-white p-4">
        <div className="text-xs uppercase tracking-wider text-gray-500 mb-1">
          Recommendation
        </div>
        <div className="text-base font-medium text-gray-900">
          {insight.recommendation}
        </div>
      </div>

      {/* Summary */}
      <div className="rounded-lg border border-gray-200 bg-gray-50 p-4">
        <div className="text-xs uppercase tracking-wider text-gray-500 mb-1">
          Summary
        </div>
        <div className="text-sm text-gray-700">{insight.summary}</div>
      </div>

      {/* Data sources */}
      <div>
        <div className="text-xs uppercase tracking-wider text-gray-500 mb-2">
          Data sources used
        </div>
        <div className="flex flex-wrap gap-1">
          {insight.data_sources_used.map((s) => (
            <span key={s} className="text-xs bg-blue-50 text-blue-700 px-2 py-1 rounded">
              {s}
            </span>
          ))}
        </div>
        {insight.data_sources_failed.length > 0 && (
          <div className="mt-2 text-xs text-red-600">
            Failed: {insight.data_sources_failed.join("; ")}
          </div>
        )}
      </div>

      {/* Per-agent breakdown */}
      <div>
        <div className="text-xs uppercase tracking-wider text-gray-500 mb-2">
          Agent reasoning ({insight.agents.length} agents)
        </div>
        <div className="space-y-2">
          {insight.agents.map((a) => (
            <details
              key={a.agent}
              className="rounded border border-gray-200 bg-white p-2"
            >
              <summary className="cursor-pointer flex items-center justify-between">
                <span className="font-medium text-sm">
                  {AGENT_EMOJI[a.agent] || "•"} {AGENT_LABEL[a.agent] || a.agent}
                </span>
                <span className={`text-xs px-2 py-0.5 rounded ${RISK_COLOR[a.risk_level] || RISK_COLOR.unknown}`}>
                  {a.risk_level}
                </span>
              </summary>
              <div className="mt-2 text-xs text-gray-600">{a.summary}</div>
              {a.findings.length > 0 && (
                <ul className="mt-2 space-y-1">
                  {a.findings.map((f, i) => (
                    <li key={i} className={`text-xs ${SEVERITY_COLOR[f.severity] || ""}`}>
                      <span className="font-mono opacity-60">[{f.severity}]</span> {f.msg}
                    </li>
                  ))}
                </ul>
              )}
            </details>
          ))}
        </div>
      </div>

      <div className="text-xs text-gray-400">
        Fetched at {new Date(insight.fetched_at).toLocaleString()}
      </div>
    </div>
  );
}
