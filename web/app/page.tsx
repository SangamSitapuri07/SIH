"use client";

import { useRef, useState } from "react";
import dynamic from "next/dynamic";
import {
  Advisory,
  DEFAULT_ZONE,
  DemoZone,
  INDIAN_COASTAL_ZONES,
  OrcaAlert,
  OrcaInsight,
  fetchInsight,
} from "@/lib/orca-client";
import { t, Lang } from "@/lib/i18n";
import InsightPanel from "@/components/InsightPanel";
import AskOrca from "@/components/AskOrca";
import AdvisoryCard from "@/components/AdvisoryCard";
import AlertsPanel from "@/components/AlertsPanel";
import SettingsPanel from "@/components/SettingsPanel";

// react-leaflet uses window/document — client-only
const MapView = dynamic(() => import("@/components/MapView"), { ssr: false });

type Tab = "map" | "ask" | "advisory" | "alerts" | "settings";

export default function Home() {
  const [tab, setTab] = useState<Tab>("map");
  const [lang, setLang] = useState<Lang>("hi");
  const [zone, setZone] = useState<DemoZone>(DEFAULT_ZONE);
  const [insight, setInsight] = useState<OrcaInsight | null>(null);
  const [insightLoading, setInsightLoading] = useState(false);
  const [advisory, setAdvisory] = useState<Advisory | null>(null);
  const [ticker, setTicker] = useState<OrcaAlert[]>([]);

  const insightBusyRef = useRef(false);

  const handleSelectZone = (z: DemoZone) => {
    // One live analysis at a time: concurrent clicks on a slow network
    // each spawn a full 10-agent chain and starve each other.
    if (insightBusyRef.current) return;
    insightBusyRef.current = true;
    setZone(z);
    setAdvisory(null); // stale until re-fetched
    // keep the old deep-insight behaviour for the Map tab
    setInsightLoading(true);
    setInsight(null);
    fetchInsight(z.lat, z.lon)
      .then(setInsight)
      .catch((err) => {
        const timedOut =
          err instanceof Error &&
          (err.name === "TimeoutError" || /timed out/i.test(err.message) || /API 504/.test(err.message));
        setInsight({
          zone: { lat: z.lat, lon: z.lon, date: new Date().toISOString().slice(0, 10) },
          agents: [],
          overall_risk: "unknown",
          summary: timedOut
            ? (lang === "hi"
                ? "नेटवर्क धीमा है और विश्लेषण समय से पहले पूरा नहीं हुआ। कुछ सेकंड बाद उसी बिंदु पर दोबारा क्लिक करें — कैश होने से दूसरी बार तेज़ चलेगा।"
                : "Slow network — the analysis didn't finish in time. Click the same point again in a few seconds; caches make the retry much faster.")
            : (lang === "hi"
                ? `ORCA API तक नहीं पहुँच पाए। ${err instanceof Error ? err.message : String(err)}`
                : `Failed to reach the ORCA API. ${err instanceof Error ? err.message : String(err)}`),
          recommendation: timedOut
            ? (lang === "hi" ? "दोबारा प्रयास करें — backend ज़िंदा है, बस धीमा है।" : "Retry — the backend is alive, just slow.")
            : (lang === "hi" ? "जाँचें कि FastAPI backend port 8000 पर चल रहा है।" : "Check that the FastAPI backend is running on port 8000."),
          data_sources_used: [],
          data_sources_failed: [timedOut ? "Network: analysis timed out (retry warms the cache)" : "API: backend unreachable"],
          fetched_at: new Date().toISOString(),
        });
      })
      .finally(() => {
        insightBusyRef.current = false;
        setInsightLoading(false);
      });
  };

  const TABS: { id: Tab; label: string }[] = [
    { id: "map", label: t(lang, "tab_map") },
    { id: "ask", label: t(lang, "tab_ask") },
    { id: "advisory", label: t(lang, "tab_advisory") },
    { id: "alerts", label: t(lang, "tab_alerts") },
    { id: "settings", label: t(lang, "tab_settings") },
  ];

  return (
    <div className="h-screen flex flex-col">
      {/* header */}
      <header className="bg-gradient-to-r from-blue-900 to-cyan-700 text-white px-4 py-2.5 shadow-md">
        <div className="flex items-center justify-between gap-3">
          <div>
            <h1 className="text-xl font-bold leading-tight">🐋 ORCA</h1>
            <p className="text-[11px] opacity-80">{t(lang, "app_tagline")} · SIH 2026 PS 176</p>
          </div>
          <nav className="flex gap-1 bg-white/10 rounded-full p-1">
            {TABS.map(({ id, label }) => (
              <button
                key={id}
                onClick={() => setTab(id)}
                className={`text-xs sm:text-sm rounded-full px-3 py-1.5 transition ${
                  tab === id ? "bg-white text-blue-900 font-semibold" : "text-white/90 hover:bg-white/20"
                }`}
              >
                {label}
              </button>
            ))}
          </nav>
        </div>
      </header>

      {/* alert ticker — any active warning scrolls by */}
      {ticker.length > 0 && (
        <div className="bg-red-700 text-white text-xs px-4 py-1.5 flex items-center gap-3 overflow-hidden">
          <span className="font-bold animate-pulse shrink-0">{t(lang, "ticker_prefix")}</span>
          <div className="whitespace-nowrap overflow-hidden text-ellipsis">
            {ticker.map((a) => `${a.simulated ? "[DEMO] " : ""}${lang === "hi" ? a.title_hi : a.title_en} (till ${a.valid_until.slice(11, 16)} UTC)`).join("  ·  ")}
          </div>
        </div>
      )}

      {/* tab content — Map tab keeps its own layout */}
      <div className="flex-1 overflow-hidden" hidden={tab !== "map"}>
        <div className="h-full grid grid-cols-1 md:grid-cols-[2fr_1fr]">
          <div className="relative">
            <MapView zones={INDIAN_COASTAL_ZONES} selected={zone} onSelect={handleSelectZone} lang={lang} />
            <div className="absolute bottom-4 left-4 bg-white/95 rounded shadow p-3 text-xs max-w-xs z-[1000]">
              <div className="font-semibold mb-1">
                {zone.name}
              </div>
              <div className="text-gray-600">
                {t(lang, "map_click_hint")}
              </div>
            </div>
          </div>
          <div className="bg-gray-50 border-l overflow-hidden">
            <InsightPanel insight={insight} loading={insightLoading} zoneName={zone.name} lang={lang} />
          </div>
        </div>
      </div>

      <div className="flex-1 overflow-hidden" hidden={tab !== "ask"}>
        <AskOrca zone={zone} lang={lang} onVerdict={setAdvisory} />
      </div>

      <div className="flex-1 overflow-hidden" hidden={tab !== "advisory"}>
        <AdvisoryCard zone={zone} lang={lang} advisory={advisory} setAdvisory={setAdvisory} />
      </div>

      <div className="flex-1 overflow-hidden" hidden={tab !== "alerts"}>
        <AlertsPanel zone={zone} lang={lang} ticker={ticker} setTicker={setTicker} />
      </div>

      <div className="flex-1 overflow-hidden" hidden={tab !== "settings"}>
        <SettingsPanel zone={zone} setZone={setZone} lang={lang} setLang={setLang} />
      </div>
    </div>
  );
}
