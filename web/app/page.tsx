"use client";

import { useEffect, useRef, useState } from "react";
import dynamic from "next/dynamic";
import {
  Advisory,
  DEFAULT_ZONE,
  DemoZone,
  INDIAN_COASTAL_ZONES,
  OrcaAlert,
  OrcaInsight,
  fetchHealth,
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

/** Header chips show the REAL backend-reported source status — nothing cosmetic */
const SRC_LABEL: Record<string, string> = {
  mosdac: "MOSDAC",
  noaa_erddap: "NOAA",
  esa_occci: "OC-CCI",
  openmeteo: "Open-Meteo",
  gfw: "GFW",
  incois_pfz_wfs: "INCOIS PFZ",
  incois_las: "INCOIS",
  jtwc: "JTWC",
};
const SRC_ORDER = ["mosdac", "noaa_erddap", "esa_occci", "openmeteo", "gfw", "incois_pfz_wfs", "incois_las", "jtwc"];

function SourceChips() {
  const [sources, setSources] = useState<Record<string, string> | null>(null);

  useEffect(() => {
    let alive = true;
    const pull = () => {
      fetchHealth()
        .then((h) => { if (alive) setSources(h.data_sources ?? {}); })
        .catch(() => { if (alive) setSources(null); });
    };
    pull();
    const id = setInterval(pull, 60_000);
    return () => { alive = false; clearInterval(id); };
  }, []);

  if (sources === null) {
    return (
      <span className="text-[10px] sm:text-[11px] font-semibold px-2.5 py-1 rounded-md bg-red-500/10 border border-red-500/40 text-red-300">
        backend ●DOWN
      </span>
    );
  }
  const keys = SRC_ORDER.filter((k) => k in sources);
  return (
    <div className="flex items-center gap-1.5 flex-wrap justify-end">
      {keys.map((k, i) => {
        const v = String(sources[k]);
        const live = v.toLowerCase().includes("live");
        return (
          <span
            key={k}
            title={v}
            className={`text-[10px] sm:text-[11px] font-semibold px-2.5 py-1 rounded-md border ${
              live
                ? "bg-emerald-500/10 border-emerald-500/30 text-emerald-300"
                : "bg-amber-500/10 border-amber-500/30 text-amber-300"
            } ${i > 3 ? "hidden lg:inline-block" : i > 1 ? "hidden sm:inline-block" : ""}`}
          >
            {SRC_LABEL[k] ?? k} {live ? "●LIVE" : "●SETUP"}
          </span>
        );
      })}
    </div>
  );
}

export default function Home() {
  const [tab, setTab] = useState<Tab>("map");
  const [lang, setLang] = useState<Lang>("hi");
  const [zone, setZone] = useState<DemoZone>(DEFAULT_ZONE);
  const [insight, setInsight] = useState<OrcaInsight | null>(null);
  const [insightLoading, setInsightLoading] = useState(false);
  const [advisory, setAdvisory] = useState<Advisory | null>(null);
  const [ticker, setTicker] = useState<OrcaAlert[]>([]);

  const insightBusyRef = useRef(false);
  const pendingZoneRef = useRef<DemoZone | null>(null);
  const runIdRef = useRef(0);

  // Latest click WINS: rapid clicks queue up and only the newest zone
  // gets analyzed next — no dropped clicks, no parallel agent-chains
  // strangling the network.
  const handleSelectZone = (z: DemoZone) => {
    pendingZoneRef.current = z;
    setZone(z);
    setAdvisory(null); // stale until re-fetched
    setInsight(null);
    setInsightLoading(true);
    if (insightBusyRef.current) return; // runNext() picks it up when free
    runNextInsight();
  };

  const runNextInsight = () => {
    const z = pendingZoneRef.current;
    if (!z) return;
    pendingZoneRef.current = null;
    insightBusyRef.current = true;
    const myId = ++runIdRef.current;
    fetchInsight(z.lat, z.lon)
      .then((r) => { if (runIdRef.current === myId) setInsight(r); })
      .catch((err) => {
        if (runIdRef.current !== myId) return; // superseded by a newer click
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
        if (pendingZoneRef.current) {
          runNextInsight(); // a newer click was queued while we worked
        } else if (runIdRef.current === myId) {
          setInsightLoading(false);
        }
      });
  };

  const TABS: { id: Tab; label: string; icon: string }[] = [
    { id: "map", label: t(lang, "tab_map"), icon: "🗺️" },
    { id: "ask", label: t(lang, "tab_ask"), icon: "💬" },
    { id: "advisory", label: t(lang, "tab_advisory"), icon: "🛡️" },
    { id: "alerts", label: t(lang, "tab_alerts"), icon: "🚨" },
    { id: "settings", label: t(lang, "tab_settings"), icon: "⚙️" },
  ];

  return (
    <div className="h-screen flex overflow-hidden bg-[#0A1628] text-slate-200">
      {/* left icon rail */}
      <aside className="w-14 sm:w-16 shrink-0 flex flex-col items-center gap-1.5 py-3 bg-[#081120] border-r border-[#1E3356]">
        <div className="mb-2 text-2xl" title="ORCA">🐋</div>
        {TABS.map(({ id, label, icon }) => (
          <button
            key={id}
            onClick={() => setTab(id)}
            title={label}
            className={`w-11 sm:w-12 flex flex-col items-center gap-0.5 py-2 rounded-lg transition ${
              tab === id
                ? "bg-[#123055] text-cyan-300 shadow-[inset_0_0_0_1px_#22d3ee33]"
                : "text-slate-500 hover:bg-[#0E1D36] hover:text-slate-300"
            }`}
          >
            <span className="text-lg leading-none">{icon}</span>
            <span className="text-[9px] font-medium leading-none">{label}</span>
          </button>
        ))}
        <div className="mt-auto text-[9px] text-slate-600 [writing-mode:vertical-rl] rotate-180 select-none">
          SIH 2026 · PS 176
        </div>
      </aside>

      {/* main column */}
      <div className="flex-1 min-w-0 flex flex-col">
        {/* header */}
        <header className="shrink-0 bg-[#0B1830] border-b border-[#1E3356] px-3 sm:px-4 py-2">
          <div className="flex items-center justify-between gap-3">
            <div className="min-w-0">
              <h1 className="text-lg font-extrabold tracking-wide text-white leading-tight">
                ORCA <span className="text-[11px] font-medium text-cyan-400/90 tracking-normal">Marine Intelligence</span>
              </h1>
              <p className="text-[10px] text-slate-500 truncate">{t(lang, "app_tagline")}</p>
            </div>
            <SourceChips />
          </div>
        </header>

        {/* alert ticker — any active warning scrolls by */}
        {ticker.length > 0 && (
          <div className="shrink-0 bg-red-950/80 border-b border-red-800/60 text-red-200 text-xs px-4 py-1.5 flex items-center gap-3 overflow-hidden">
            <span className="font-bold animate-pulse shrink-0">{t(lang, "ticker_prefix")}</span>
            <div className="whitespace-nowrap overflow-hidden text-ellipsis">
              {ticker.map((a) => `${a.simulated ? "[DEMO] " : ""}${lang === "hi" ? a.title_hi : a.title_en} (till ${a.valid_until.slice(11, 16)} UTC)`).join("  ·  ")}
            </div>
          </div>
        )}

        {/* tab content — Map tab keeps its own layout (map component untouched) */}
        <div className="flex-1 overflow-hidden" hidden={tab !== "map"}>
          <div className="h-full grid grid-cols-1 md:grid-cols-[2fr_1fr]">
            <div className="relative">
              <MapView zones={INDIAN_COASTAL_ZONES} selected={zone} onSelect={handleSelectZone} lang={lang} />
              <div className="absolute bottom-4 left-4 bg-[#0E1D36]/90 backdrop-blur border border-[#1E3356] rounded-lg shadow-lg p-3 text-xs max-w-xs z-[1000]">
                <div className="font-semibold text-slate-100 mb-1">
                  {zone.name}
                </div>
                <div className="text-slate-400">
                  {t(lang, "map_click_hint")}
                </div>
              </div>
            </div>
            <div className="bg-[#0B1830] border-l border-[#1E3356] overflow-hidden">
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
    </div>
  );
}
