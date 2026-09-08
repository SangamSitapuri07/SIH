/**
 * 🧭 Navigate — D1: route-check + live numbers (GPS chalu ho toh origin
 * live, warna honest "map point"). D5: geofence arrival + background
 * trace + haptics + dhoop mode; marine GPS jaisa course-line guidance.
 */
import React, { useEffect, useMemo, useState } from "react";
import { ActivityIndicator, StyleSheet, Switch, Text, View } from "react-native";
import * as Location from "expo-location";
import { C, FS } from "../theme";
import StatusStrip from "../components/StatusStrip";
import { fetchRouteCheck, FieldHotspot, RouteCheck } from "../api";
import { bearingDeg, compass, haversineKm } from "../lib/marineMath";

const ANCHOR = { lat: 20.9, lon: 70.37 };

export default function NavigateScreen({ route }: { route: { params?: { target?: FieldHotspot } } }) {
  const target = route.params?.target ?? null;
  const [gpsOn, setGpsOn] = useState(false);
  const [pos, setPos] = useState<{ lat: number; lon: number; acc: number | null; speedKn: number | null } | null>(null);
  const [gpsMsg, setGpsMsg] = useState<string | null>(null);
  const [rc, setRc] = useState<RouteCheck | null>(null);

  useEffect(() => {
    let sub: Location.LocationSubscription | null = null;
    (async () => {
      if (!gpsOn) return;
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== "granted") { setGpsMsg("GPS permission nahi mili — settings me allow karo"); setGpsOn(false); return; }
      setGpsMsg(null);
      sub = await Location.watchPositionAsync(
        { accuracy: Location.Accuracy.BestForNavigation, timeInterval: 2000, distanceInterval: 5 },
        (f) => setPos({
          lat: f.coords.latitude, lon: f.coords.longitude,
          acc: f.coords.accuracy, speedKn: f.coords.speed != null && f.coords.speed >= 0 ? f.coords.speed * 1.943844 : null,
        }),
      );
    })();
    return () => { sub?.remove(); };
  }, [gpsOn]);

  const origin = pos ?? { ...ANCHOR, acc: null, speedKn: null };

  useEffect(() => {
    if (!target) return;
    setRc(null);
    fetchRouteCheck(origin.lat, origin.lon, target.lat, target.lon).then(setRc).catch(() => setRc(null));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target?.lat, target?.lon]);

  const nav = useMemo(() => {
    if (!target) return null;
    const km = haversineKm(origin.lat, origin.lon, target.lat, target.lon);
    const brg = bearingDeg(origin.lat, origin.lon, target.lat, target.lon);
    const nm = km / 1.852;
    const etaMin = origin.speedKn && origin.speedKn > 0.5 ? (nm / origin.speedKn) * 60 : null;
    return { nm, brg, etaMin, arrived: nm < 0.3 };
  }, [origin.lat, origin.lon, origin.speedKn, target]);

  return (
    <View style={st.wrap}>
      <StatusStrip gpsAcc={origin.acc} />
      <View style={st.body}>
        {!target && (
          <Text style={st.msg}>
            🧭 Pehle <Text style={{ color: C.emerald }}>नक्शा tab</Text> me kisi hotspot pe "🧭 जाओ" dabao — phir yahan guidance aayegi.
          </Text>
        )}
        {!!gpsMsg && <Text style={st.warn}>{gpsMsg}</Text>}
        <View style={st.gpsRow}>
          <Text style={st.gpsTxt}>{gpsOn ? "📍 LIVE GPS" : "📍 origin: मैप बिंदु (GPS band)"}</Text>
          <Switch value={gpsOn} onValueChange={setGpsOn} trackColor={{ true: "#155e75" }} thumbColor={gpsOn ? C.cyan : "#475569"} />
        </View>
        {target && nav && (
          <>
            <Text style={st.tg}>🎯 {target.lat.toFixed(2)}°N, {target.lon.toFixed(2)}°E · {target.chl} mg/m³</Text>
            <View style={st.grid}>
              <View style={st.cell}><Text style={st.lab}>दूरी</Text><Text style={st.val}>{nav.nm.toFixed(1)} NM</Text></View>
              <View style={st.cell}><Text style={st.lab}>दिशा</Text><Text style={st.val}>{Math.round(nav.brg)}° {compass(nav.brg)}</Text></View>
              <View style={st.cell}><Text style={st.lab}>रफ़्तार</Text><Text style={st.val}>{origin.speedKn != null ? `${origin.speedKn.toFixed(1)} kn` : "—"}</Text></View>
              <View style={st.cell}><Text style={st.lab}>ETA</Text><Text style={st.val}>{nav.etaMin != null ? `${Math.round(nav.etaMin)} min` : "—"}</Text></View>
            </View>
            {nav.arrived && <Text style={st.arrived}>🎉 पहुंच गए! hotspot yahin hai</Text>}
            <View style={[st.rcBox, rc?.ok === false ? st.rcBad : rc?.ok === true ? st.rcOk : st.rcIdle]}>
              {!rc && <ActivityIndicator color={C.cyan} />}
              {rc && (
                <Text style={st.rcTxt}>
                  {rc.ok === true ? `🛟 ${rc.detour ? "seedha zameen se guzarta — detour waypoint bana diya" : "seedha raasta poora paani"} (GLOBE ✓)`
                    : rc.ok === false ? "⛔ raasta zameen se guzarta — BLOCKED (fake line nahi)"
                    : "⚠️ UNVERIFIED — land mask uplabdh nahi"}
                </Text>
              )}
            </View>
          </>
        )}
        <Text style={st.note}>Course-line guidance (samundar me roads nahi hote — marine GPS bhi yahi deta hai). Turn hints + "pahunch gaye" vibration + trace D5 me.</Text>
      </View>
    </View>
  );
}

const st = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: C.bg },
  body: { padding: 14, gap: 12 },
  msg: { color: C.text, fontSize: FS.base, lineHeight: 24 },
  warn: { color: C.amber, fontSize: FS.small },
  gpsRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", backgroundColor: C.surface, borderWidth: 1, borderColor: C.line, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 8 },
  gpsTxt: { color: C.text, fontSize: FS.base },
  tg: { color: C.text, fontSize: FS.base, fontWeight: "600" },
  grid: { flexDirection: "row", flexWrap: "wrap", gap: 10 },
  cell: { width: "47%", backgroundColor: C.surface2, borderRadius: 12, borderWidth: 1, borderColor: C.line, padding: 12 },
  lab: { color: C.dim, fontSize: FS.tiny },
  val: { color: C.cyan, fontSize: FS.nav * 0.7, fontWeight: "700", marginTop: 2 },
  arrived: { color: C.emerald, fontSize: FS.big, fontWeight: "700", textAlign: "center" },
  rcBox: { borderRadius: 12, borderWidth: 1, padding: 12, alignItems: "center" },
  rcOk: { borderColor: "#14532d", backgroundColor: "#04180f" },
  rcBad: { borderColor: C.red, backgroundColor: "#1d0505" },
  rcIdle: { borderColor: C.line, backgroundColor: C.surface },
  rcTxt: { color: C.text, fontSize: FS.base },
  note: { color: C.dim, fontSize: FS.small, lineHeight: 20 },
});
