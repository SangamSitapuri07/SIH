/**
 * ℹ️ जानकारी — backend health + API base editor (dev-time LAN IP badlo)
 * + honesty charter. Ye screen judges ko bhi dikhane layak hai.
 */
import React, { useEffect, useState } from "react";
import { ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from "react-native";
import { C, FS } from "../theme";
import StatusStrip from "../components/StatusStrip";
import { fetchHealth, getApiBase, setApiBase, Health } from "../api";

export default function InfoScreen() {
  const [health, setHealth] = useState<Health | null>(null);
  const [healthErr, setHealthErr] = useState<string | null>(null);
  const [base, setBase] = useState(getApiBase());
  const [saved, setSaved] = useState(false);

  const ping = async () => {
    setHealthErr(null);
    try { setHealth(await fetchHealth()); }
    catch (e) { setHealth(null); setHealthErr(`backend se jawab nahi (${e instanceof Error ? e.message : e}) — laptop pe FastAPI chalu? same WiFi?`); }
  };
  useEffect(() => { ping(); }, []);

  return (
    <View style={st.wrap}>
      <StatusStrip />
      <ScrollView contentContainerStyle={st.body}>
        <Text style={st.h}>ℹ️ जानकारी & settings</Text>

        <View style={st.card}>
          <Text style={st.h2}>Backend (FastAPI) ka pata</Text>
          <Text style={st.dim}>Phone aur laptop same WiFi pe hone chahiye (dev). URL badal ke 💾 dabao:</Text>
          <TextInput
            value={base}
            onChangeText={(v) => { setBase(v); setSaved(false); }}
            autoCapitalize="none" autoCorrect={false} keyboardType="url"
            style={st.input} placeholder="http://192.168.x.x:8000" placeholderTextColor="#475569"
          />
          <TouchableOpacity style={st.btn} onPress={async () => { await setApiBase(base); setSaved(true); ping(); }}>
            <Text style={st.btnTxt}>{saved ? "✓ saved + rechecked" : "💾 save & recheck"}</Text>
          </TouchableOpacity>
        </View>

        <View style={st.card}>
          <Text style={st.h2}>Backend health</Text>
          {healthErr && <Text style={st.err}>{healthErr}</Text>}
          {health && (
            <>
              <Text style={st.kv}>status: <Text style={st.ok}>{String(health.status ?? "?")}</Text></Text>
              <Text style={st.kv}>build: <Text style={st.okMono}>⎇ {String(health.build_commit ?? "unknown")}</Text></Text>
              {Object.entries(health)
                .filter(([k, v]) => typeof v !== "object" && !["status", "build_commit"].includes(k))
                .slice(0, 20)
                .map(([k, v]) => <Text key={k} style={st.kv}>{k}: <Text style={st.dim}>{String(v)}</Text></Text>)}
            </>
          )}
        </View>

        <View style={st.card}>
          <Text style={st.h2}>🛡️ ORCA honesty charter</Text>
          <Text style={st.dim}>
            · Har number asli source se — NOAA/MOSDAC/Open-Meteo/GFW/INCOIS.{"\n"}
            · Source fail ho toh ASLI reason dikhta hai, kabhi fake value nahi.{"\n"}
            · Land hotspots = GLOBE 1km mask se hamesha bahar (kabhi zameen pe machali-spot nahi).{"\n"}
            · Purana data fresh dikhna kabhi nahi — timestamp + OFFLINE badge hamesha.{"\n"}
            · GPS satellites ka hai, internet ka nahi — offline me bhi position/trace/guidance chalti hai.
          </Text>
        </View>

        <View style={st.card}>
          <Text style={st.h2}>Version</Text>
          <Text style={st.dim}>ORCA Android 0.1.0 (D1 scaffold) · SIH 2026 PS 176 · Team ORCA (Punjab, Ludhiana)</Text>
        </View>
      </ScrollView>
    </View>
  );
}

const st = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: C.bg },
  body: { padding: 14, gap: 10, paddingBottom: 30 },
  h: { color: C.text, fontSize: FS.big, fontWeight: "800" },
  h2: { color: C.text, fontSize: FS.base, fontWeight: "700" },
  dim: { color: C.dim, fontSize: FS.small, lineHeight: 20 },
  err: { color: C.red, fontSize: FS.small, lineHeight: 19 },
  card: { backgroundColor: C.surface, borderRadius: 12, borderWidth: 1, borderColor: C.line, padding: 12, gap: 8 },
  input: { backgroundColor: C.surface2, borderRadius: 10, borderWidth: 1, borderColor: C.line, color: C.text, paddingHorizontal: 12, paddingVertical: 10, fontSize: FS.base },
  btn: { backgroundColor: "#0b2b33", borderRadius: 10, borderWidth: 1, borderColor: "#155e75", paddingVertical: 10, alignItems: "center" },
  btnTxt: { color: C.cyan, fontWeight: "700", fontSize: FS.base },
  kv: { color: C.text, fontSize: FS.small },
  ok: { color: C.emerald },
  okMono: { color: C.emerald, fontVariant: ["tabular-nums"] },
});
