/**
 * 🏠 मुखपृष्ठ — ek nazar mein verdict. D1: advisory fetch + giant verdict
 * + honest stamp + retry. D2: 48h charts + quick tiles + jagah picker.
 */
import React, { useCallback, useEffect, useState } from "react";
import { ActivityIndicator, ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { C, FS } from "../theme";
import StatusStrip from "../components/StatusStrip";
import { fetchAdvisory, Advisory } from "../api";

// D1 default zone: Veraval offshore (PFZ validation ground).
// Jagah-picker (GPS/manual) D2 me aayega.
const ORIGIN = { lat: 20.9, lon: 70.37, label: "वेरावल के पास (Gujarat)" };

export default function HomeScreen() {
  const [adv, setAdv] = useState<Advisory | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setBusy(true); setErr(null);
    try { setAdv(await fetchAdvisory(ORIGIN.lat, ORIGIN.lon)); }
    catch (e) {
      setAdv(null);
      setErr(`advisory nahi mili — backend chal raha hai na? (${e instanceof Error ? e.message : e})`);
    } finally { setBusy(false); }
  }, []);
  useEffect(() => { load(); }, [load]);

  const verdict = (adv?.verdict ?? adv?.text ?? null) as string | null;

  return (
    <View style={st.wrap}>
      <StatusStrip />
      <ScrollView contentContainerStyle={st.body}>
        <Text style={st.zone}>📍 {ORIGIN.label} <Text style={st.zoneDim}>(बदलना D2 में आएगा)</Text></Text>
        <View style={st.card}>
          {busy && <ActivityIndicator color={C.cyan} size="large" />}
          {!busy && verdict && (
            <>
              <Text style={st.verdictLabel}>आज समुद्र में जाना:</Text>
              <Text style={st.verdict}>{verdict}</Text>
              {!!adv?.generated_at && (
                <Text style={st.stamp}>data: {String(adv.generated_at).replace("T", " ").slice(0, 19)} UTC</Text>
              )}
            </>
          )}
          {!busy && err && (
            <>
              <Text style={st.errTxt}>{err}</Text>
              <TouchableOpacity style={st.btn} onPress={load}>
                <Text style={st.btnTxt}>🔄 फिर कोशिश करो</Text>
              </TouchableOpacity>
            </>
          )}
        </View>
        <Text style={st.hint}>
          Agle din: 48 घंटे के charts (लहरें/हवा/पानी), छोटी boats के लिए plain-language सलाह — sab usi advisory se, koi alag number nahi.
        </Text>
      </ScrollView>
    </View>
  );
}

const st = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: C.bg },
  body: { padding: 14, gap: 12 },
  zone: { color: C.text, fontSize: FS.base },
  zoneDim: { color: C.dim, fontSize: FS.small },
  card: { backgroundColor: C.surface, borderRadius: 14, borderWidth: 1, borderColor: C.line, padding: 18, minHeight: 160, justifyContent: "center", gap: 8 },
  verdictLabel: { color: C.dim, fontSize: FS.base },
  verdict: { color: C.text, fontSize: FS.verdict, fontWeight: "700", lineHeight: FS.big * 1.35 },
  stamp: { color: C.dim, fontSize: FS.small },
  errTxt: { color: C.red, fontSize: FS.base },
  btn: { backgroundColor: C.surface2, borderRadius: 10, borderWidth: 1, borderColor: "#24405F", paddingVertical: 12, alignItems: "center", marginTop: 6 },
  btnTxt: { color: C.cyan, fontSize: FS.base, fontWeight: "600" },
  hint: { color: C.dim, fontSize: FS.small, lineHeight: 20 },
});
