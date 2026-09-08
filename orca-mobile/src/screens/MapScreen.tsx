/**
 * 🗺️ नक्शा — D1: hotspot cards from /field (caveat दिखता है, GLOBE land-
 * masked). D3: asli MapLibre map + grid dots + long-press card + 3D sheet.
 */
import React, { useEffect, useState } from "react";
import { ActivityIndicator, ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";
import { C, FS } from "../theme";
import StatusStrip from "../components/StatusStrip";
import { fetchField, FieldResponse } from "../api";

const ORIGIN = { lat: 20.9, lon: 70.37 };

export default function MapScreen({ navigation }: { navigation: { navigate: (t: string, p?: object) => void } }) {
  const [data, setData] = useState<FieldResponse | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = async () => {
    setBusy(true); setErr(null);
    try { setData(await fetchField(ORIGIN.lat, ORIGIN.lon)); }
    catch (e) { setData(null); setErr(`field data nahi aaya (${e instanceof Error ? e.message : e})`); }
    finally { setBusy(false); }
  };
  useEffect(() => { load(); }, []);

  return (
    <View style={st.wrap}>
      <StatusStrip />
      <ScrollView contentContainerStyle={st.body}>
        <Text style={st.h}>🎣 टॉप मछली-हॉटस्पॉट {data?.chl.date ? <Text style={st.dim}>· NOAA {data.chl.date}</Text> : null}</Text>
        {busy && <ActivityIndicator color={C.cyan} size="large" />}
        {err && <Text style={st.err}>{err}</Text>}
        {!!data?.chl.land_masked && (
          <Text style={st.landNote}>🛡️ {data.chl.land_masked} zameen-wale pixels hata diye (GLOBE 1km mask se — hotspot kabhi zameen pe nahi)</Text>
        )}
        {data?.hotspots.map((h, i) => (
          <View key={i} style={st.card}>
            <View style={st.rowBetween}>
              <Text style={st.hs}>#{i + 1} · {h.lat.toFixed(2)}°N, {h.lon.toFixed(2)}°E</Text>
              <Text style={st.stat}><Text style={st.chl}>{h.chl}</Text> mg/m³</Text>
            </View>
            <Text style={st.dim}>{h.distance_nm} NM {h.bearing}{(h.coast_km != null) ? ` · तट ~${Math.round(h.coast_km)} km` : ""}</Text>
            {!!h.caveat && <Text style={st.caveat}>⚠️ {h.caveat}</Text>}
            <TouchableOpacity
              style={st.goBtn}
              onPress={() => navigation.navigate("Navigate", { target: h })}
            >
              <Text style={st.goTxt}>🧭 जाओ — navigate</Text>
            </TouchableOpacity>
          </View>
        ))}
        <Text style={st.note}>D3 me yahin asli map aayega (MapLibre + OSM tiles + OpenSeaMap buoys) — ye list-window pehle hi real data se live hai.</Text>
      </ScrollView>
    </View>
  );
}

const st = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: C.bg },
  body: { padding: 14, gap: 10 },
  h: { color: C.emerald, fontSize: FS.base, fontWeight: "700" },
  dim: { color: C.dim, fontSize: FS.small },
  err: { color: C.red, fontSize: FS.base },
  landNote: { color: C.cyan, fontSize: FS.tiny, lineHeight: 16 },
  card: { backgroundColor: C.surface, borderRadius: 12, borderWidth: 1, borderColor: C.line, padding: 12, gap: 6 },
  rowBetween: { flexDirection: "row", justifyContent: "space-between" },
  hs: { color: C.text, fontSize: FS.base, fontWeight: "600" },
  stat: { color: C.dim, fontSize: FS.small },
  chl: { color: C.emerald, fontSize: FS.big, fontWeight: "700" },
  caveat: { color: C.amber, fontSize: FS.tiny, backgroundColor: "#1a1206", borderRadius: 8, padding: 8, lineHeight: 16 },
  goBtn: { backgroundColor: "#0b2b33", borderRadius: 10, borderWidth: 1, borderColor: "#155e75", paddingVertical: 10, alignItems: "center", marginTop: 2 },
  goTxt: { color: C.cyan, fontWeight: "700", fontSize: FS.base },
  note: { color: C.dim, fontSize: FS.small, marginTop: 6, lineHeight: 20 },
});
