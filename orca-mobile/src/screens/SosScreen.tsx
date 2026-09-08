/**
 * 🆘 SOS — zero-internet emergency. D1: position (expo-location), Coast
 * Guard 1554 + contact call/SMS-pop, nearest harbours (bundled, offline).
 * D4: react-native-sms DIRECT send (bina popup) — dev build chahiye.
 */
import React, { useEffect, useMemo, useState } from "react";
import { Linking, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from "react-native";
import * as Location from "expo-location";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { C, FS } from "../theme";
import StatusStrip from "../components/StatusStrip";
import { HARBOURS } from "../data/harbours";
import { bearingDeg, compass, haversineKm } from "../lib/marineMath";

const KEY = "orca_sos_contact";

export default function SosScreen() {
  const [pos, setPos] = useState<{ lat: number; lon: number; acc: number | null; spKn: number | null } | null>(null);
  const [msg, setMsg] = useState("GPS fix le raha hoon…");
  const [contact, setContact] = useState("");

  useEffect(() => {
    (async () => {
      try { setContact((await AsyncStorage.getItem(KEY)) ?? ""); } catch { /* ok */ }
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== "granted") { setMsg("GPS permission nahi mili — settings se do"); return; }
      try {
        const f = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.BestForNavigation });
        setPos({ lat: f.coords.latitude, lon: f.coords.longitude, acc: f.coords.accuracy, spKn: f.coords.speed != null && f.coords.speed >= 0 ? f.coords.speed * 1.943844 : null });
        setMsg("");
      } catch (e) { setMsg("GPS fix nahi mila (open sky dekho): " + (e instanceof Error ? e.message : e)); }
    })();
  }, []);

  const save = async (v: string) => { setContact(v); try { await AsyncStorage.setItem(KEY, v.trim()); } catch { /* ok */ } };

  const near = useMemo(() => {
    if (!pos) return [];
    return HARBOURS.map((h) => {
      const nm = haversineKm(pos.lat, pos.lon, h.lat, h.lon) / 1.852;
      const sp = pos.spKn;
      return { h, nm, brg: bearingDeg(pos.lat, pos.lon, h.lat, h.lon), etaMin: sp && sp > 0.5 ? (nm / sp) * 60 : null };
    }).sort((a, b) => a.nm - b.nm).slice(0, 3);
  }, [pos]);

  const num = contact.trim().replace(/[^\d+]/g, "");
  const smsBody = pos
    ? encodeURIComponent(`ORCA SOS: position ${pos.lat.toFixed(5)},${pos.lon.toFixed(5)} `
      + `(accuracy ${pos.acc != null ? Math.round(pos.acc) + "m" : "?"}) — need assistance.`)
    : "";

  return (
    <View style={st.wrap}>
      <StatusStrip gpsAcc={pos?.acc} />
      <ScrollView contentContainerStyle={st.body}>
        <Text style={st.h}>🆘 Emergency — yeh screen bina internet ke chalti hai</Text>
        <View style={st.posBox}>
          {!!msg && <Text style={st.warn}>{msg}</Text>}
          {pos && (
            <>
              <Text style={st.posLab}>आपकी position{pos.acc != null ? ` (±${Math.round(pos.acc)}m)` : ""}</Text>
              <Text style={st.pos}>{pos.lat.toFixed(5)}, {pos.lon.toFixed(5)}</Text>
              <Text style={st.dim}>{new Date().toISOString().replace("T", " ").slice(0, 19)} UTC</Text>
            </>
          )}
        </View>
        <TouchableOpacity style={st.cgBtn} onPress={() => Linking.openURL("tel:1554")}>
          <Text style={st.cgTxt}>📞 भारतीय Coast Guard — 1554</Text>
        </TouchableOpacity>
        <View style={st.card}>
          <Text style={st.dim}>आपका emergency contact (device pe save):</Text>
          <TextInput
            value={contact} onChangeText={save} placeholder="+91 98xxxxxx45" placeholderTextColor="#475569"
            keyboardType="phone-pad" style={st.input}
          />
          {!!num && (
            <View style={st.row}>
              <TouchableOpacity style={st.half} onPress={() => Linking.openURL(`tel:${num}`)}>
                <Text style={st.halfTxt}>📞 Call</Text>
              </TouchableOpacity>
              <TouchableOpacity style={[st.half, st.smsHalf]} onPress={() => Linking.openURL(`sms:${num}?body=${smsBody}`)}>
                <Text style={[st.halfTxt, { color: C.emerald }]}>✉️ SMS position</Text>
              </TouchableOpacity>
            </View>
          )}
          <Text style={st.dim}>SMS sirf 1-bar GSM signal me bhi chala jata hai — internet nahi chahiye. (Direct background send D4 APK me aayega)</Text>
        </View>
        <View style={st.card}>
          <Text style={st.dim}>📻 <Text style={{ color: C.text, fontWeight: "700" }}>VHF Channel 16</Text> — samudr me asli distress channel (har boat/Coast Guard sunti hai).</Text>
        </View>
        <View style={st.card}>
          <Text style={st.h2}>⚓ सबसे नज़दीकी बंदरगाह (71 real, offline list)</Text>
          {near.map(({ h, nm, brg, etaMin }, i) => (
            <View key={h.name} style={st.harRow}>
              <Text style={st.harName}>#{i + 1} {h.name}</Text>
              <Text style={st.harStat}>{nm.toFixed(1)} NM · {Math.round(brg)}° {compass(brg)}{etaMin != null ? `\nETA ${Math.round(etaMin)} min` : ""}</Text>
            </View>
          ))}
        </View>
      </ScrollView>
    </View>
  );
}

const st = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: C.bg },
  body: { padding: 14, gap: 10, paddingBottom: 30 },
  h: { color: C.red, fontSize: FS.base, fontWeight: "700" },
  h2: { color: C.text, fontSize: FS.base, fontWeight: "700", marginBottom: 4 },
  dim: { color: C.dim, fontSize: FS.small, lineHeight: 19 },
  warn: { color: C.amber, fontSize: FS.small },
  posBox: { backgroundColor: C.surface, borderRadius: 12, borderWidth: 1, borderColor: C.line, padding: 14 },
  posLab: { color: C.dim, fontSize: FS.small },
  pos: { color: C.cyan, fontSize: 26, fontWeight: "800", fontVariant: ["tabular-nums"] },
  cgBtn: { backgroundColor: "#3b0a0a", borderRadius: 12, borderWidth: 2, borderColor: C.red, paddingVertical: 16, alignItems: "center" },
  cgTxt: { color: "#fecaca", fontSize: FS.big, fontWeight: "800" },
  card: { backgroundColor: C.surface, borderRadius: 12, borderWidth: 1, borderColor: C.line, padding: 12, gap: 8 },
  input: { backgroundColor: C.surface2, borderRadius: 10, borderWidth: 1, borderColor: C.line, color: C.text, paddingHorizontal: 12, paddingVertical: 10, fontSize: FS.base },
  row: { flexDirection: "row", gap: 8 },
  half: { flex: 1, backgroundColor: C.surface2, borderRadius: 10, borderWidth: 1, borderColor: C.line, paddingVertical: 12, alignItems: "center" },
  smsHalf: { borderColor: "#14532d", backgroundColor: "#04180f" },
  halfTxt: { color: C.text, fontSize: FS.base, fontWeight: "700" },
  harRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", backgroundColor: C.surface2, borderRadius: 10, paddingHorizontal: 10, paddingVertical: 8 },
  harName: { color: C.text, fontSize: FS.base, flex: 1 },
  harStat: { color: C.cyan, fontSize: FS.small, textAlign: "right" },
});
