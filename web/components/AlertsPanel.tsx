"use client";

import { useCallback, useEffect, useState } from "react";
import { DemoZone, OrcaAlert, fetchAlerts, simulateAlert } from "@/lib/orca-client";
import { t, Lang } from "@/lib/i18n";

function AlertCard({ a, lang }: { a: OrcaAlert; lang: Lang }) {
  const [open, setOpen] = useState(false);
  const warn = a.severity === "warning";
  return (
    <div
      className={`rounded-lg border p-4 bg-white cursor-pointer ${warn ? "border-red-400" : "border-amber-300"}`}
      onClick={() => setOpen((o) => !o)}
    >
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="font-semibold text-slate-800 text-sm">
            {warn ? "🔴" : "🟡"} {lang === "hi" ? a.title_hi : a.title_en}
          </div>
          <div className="text-xs text-slate-500 mt-0.5">
            {a.code} · issued {a.issued_at.slice(11, 16)} UTC · valid till {a.valid_until.slice(11, 16)} UTC · {a.source}
          </div>
        </div>
        <div className="flex flex-col items-end gap-1">
          <span className={`text-[10px] font-bold uppercase rounded px-2 py-0.5 text-white ${warn ? "bg-red-600" : "bg-amber-500"}`}>
            {a.severity}
          </span>
          {a.simulated && (
            <span className="text-[10px] font-bold rounded px-2 py-0.5 bg-purple-100 text-purple-800 border border-purple-300">
              {t(lang, "simulated_badge")}
            </span>
          )}
        </div>
      </div>
      {open && (
        <p className="text-sm text-slate-600 mt-2 whitespace-pre-wrap">{a.msg_en}</p>
      )}
    </div>
  );
}

export default function AlertsPanel({
  zone,
  lang,
  ticker,
  setTicker,
}: {
  zone: DemoZone;
  lang: Lang;
  ticker: OrcaAlert[];
  setTicker: (a: OrcaAlert[]) => void;
}) {
  const [alerts, setAlerts] = useState<OrcaAlert[]>([]);
  const [busy, setBusy] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const r = await fetchAlerts();
      setAlerts(r.alerts);
      setTicker(r.alerts.filter((a) => a.severity === "warning"));
    } catch {
      /* backend offline — keep old list */
    }
  }, [setTicker]);

  useEffect(() => {
    refresh();
    const id = setInterval(refresh, 60_000);
    return () => clearInterval(id);
  }, [refresh]);

  const evaluate = async () => {
    setBusy("eval");
    try {
      const r = await fetchAlerts(zone.lat, zone.lon);
      setAlerts(r.alerts);
      setTicker(r.alerts.filter((a) => a.severity === "warning"));
    } finally {
      setBusy(null);
    }
  };

  const simulate = async () => {
    setBusy("sim");
    try {
      await simulateAlert(zone.lat, zone.lon);
      await refresh();
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="h-full overflow-y-auto bg-slate-100 p-4 space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h2 className="font-bold text-slate-800">{t(lang, "alerts_title")}</h2>
        <div className="flex gap-2">
          <button
            onClick={evaluate}
            disabled={busy !== null}
            className="text-xs bg-blue-600 hover:bg-blue-700 text-white rounded px-3 py-2 disabled:opacity-50"
          >
            {busy === "eval" ? "…" : t(lang, "evaluate_here")}
          </button>
          <button
            onClick={simulate}
            disabled={busy !== null}
            className="text-xs bg-purple-600 hover:bg-purple-700 text-white rounded px-3 py-2 disabled:opacity-50"
            title={lang === "hi" ? "अभ्यास अलर्ट — असली नहीं" : "drill alert — not real"}
          >
            {busy === "sim" ? "…" : t(lang, "simulate")}
          </button>
        </div>
      </div>

      <p className="text-xs text-slate-500">{t(lang, "alerts_note")}</p>

      {alerts.length === 0 ? (
        <div className="rounded-lg border border-green-300 bg-green-50 p-6 text-center">
          <div className="text-3xl mb-2">✅</div>
          <p className="text-sm text-green-800">{t(lang, "no_alerts")}</p>
        </div>
      ) : (
        <div className="space-y-2">
          {alerts.map((a) => <AlertCard key={a.id} a={a} lang={lang} />)}
        </div>
      )}
    </div>
  );
}
