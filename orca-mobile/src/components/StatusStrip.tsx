/**
 * StatusStrip — har screen ke top pe sachchai ki patti:
 * 📡 online/offline · 🛰️ GPS accuracy (jo screen bheje) · ⎇ build hash.
 * Koi state chhupi nahi — fisher ko hamesha pata ho app kis haal mein hai.
 */
import React, { useEffect, useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import NetInfo from "@react-native-community/netinfo";
import { C, FS } from "../theme";
import { fetchHealth } from "../api";

export default function StatusStrip({ gpsAcc }: { gpsAcc?: number | null }) {
  const [online, setOnline] = useState<boolean | null>(null);
  const [commit, setCommit] = useState<string | null>(null);

  useEffect(() => {
    const unsub = NetInfo.addEventListener((s) => {
      setOnline(s.isConnected == null ? null : s.isConnected);
    });
    fetchHealth()
      .then((h) => setCommit(h.build_commit ?? null))
      .catch(() => setCommit(null));
    return () => unsub();
  }, []);

  return (
    <View style={st.row}>
      <Text style={[st.chip, online === false ? st.bad : st.ok]}>
        {online === null ? "📡 …" : online ? "📡 on" : "📡 OFFLINE"}
      </Text>
      {gpsAcc != null && <Text style={[st.chip, st.ok]}>🛰️ ±{Math.round(gpsAcc)}m</Text>}
      {commit && <Text style={[st.chip, st.dim]}>⎇ {commit}</Text>}
    </View>
  );
}

const st = StyleSheet.create({
  row: { flexDirection: "row", gap: 6, paddingHorizontal: 10, paddingVertical: 6, backgroundColor: C.bg },
  chip: { fontSize: FS.tiny, color: C.text, backgroundColor: C.surface2, borderRadius: 6, paddingHorizontal: 8, paddingVertical: 3, borderWidth: 1, borderColor: C.line, overflow: "hidden" },
  ok: { borderColor: "#14532d", color: C.emerald },
  bad: { borderColor: C.red, color: C.red },
  dim: { color: C.dim },
});
