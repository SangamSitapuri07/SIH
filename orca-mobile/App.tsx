/**
 * ORCA Android — D1 shell: Hindi-default bottom tabs (thumb-zone),
 * fisher-first dark theme. Sab screens asli FastAPI data se baat karti
 * hain — koi mock nahi. (Plan: docs/ANDROID-PLAN.md)
 */
import React, { useEffect } from "react";
import { StatusBar, Text } from "react-native";
import { NavigationContainer, DefaultTheme } from "@react-navigation/native";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { C } from "./src/theme";
import { initApiBase } from "./src/api";
import HomeScreen from "./src/screens/HomeScreen";
import MapScreen from "./src/screens/MapScreen";
import NavigateScreen from "./src/screens/NavigateScreen";
import SosScreen from "./src/screens/SosScreen";
import InfoScreen from "./src/screens/InfoScreen";

const Tab = createBottomTabNavigator();

const theme = {
  ...DefaultTheme,
  dark: true,
  colors: {
    ...DefaultTheme.colors,
    background: C.bg,
    card: C.bg,
    border: C.line,
    text: C.text,
    primary: C.cyan,
  },
};

const icon = (glyph: string) => () => <Text style={{ fontSize: 20 }}>{glyph}</Text>;

export default function App() {
  useEffect(() => { initApiBase(); }, []);
  return (
    <SafeAreaProvider>
      <StatusBar barStyle="light-content" backgroundColor={C.bg} />
      <NavigationContainer theme={theme}>
        <Tab.Navigator
          screenOptions={{
            headerShown: false,
            tabBarStyle: { backgroundColor: C.bg, borderTopColor: C.line, height: 62, paddingBottom: 8, paddingTop: 6 },
            tabBarActiveTintColor: C.cyan,
            tabBarInactiveTintColor: C.dim,
            tabBarLabelStyle: { fontSize: 11, fontWeight: "600" },
          }}
        >
          <Tab.Screen name="Home" component={HomeScreen}
            options={{ title: "मुखपृष्ठ", tabBarIcon: icon("🏠") }} />
          <Tab.Screen name="Map" component={MapScreen}
            options={{ title: "नक्शा", tabBarIcon: icon("🗺️") }} />
          <Tab.Screen name="Navigate" component={NavigateScreen}
            options={{ title: "नेविगेट", tabBarIcon: icon("🧭") }} />
          <Tab.Screen name="SOS" component={SosScreen}
            options={{ title: "SOS", tabBarIcon: icon("🆘"),
              tabBarActiveTintColor: C.red }} />
          <Tab.Screen name="Info" component={InfoScreen}
            options={{ title: "जानकारी", tabBarIcon: icon("ℹ️") }} />
        </Tab.Navigator>
      </NavigationContainer>
    </SafeAreaProvider>
  );
}
