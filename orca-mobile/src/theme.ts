/**
 * ORCA design tokens — web ke saath same brand, phone ke liye tuned
 * (sunlight-readable: dark bg, bade numbers, min 48dp touch targets).
 */
export const C = {
  bg: "#070D1A",
  surface: "#0A1120",
  surface2: "#0E1B30",
  line: "#1C2A45",
  text: "#DBE4F3",
  dim: "#64748B",
  cyan: "#22D3EE",
  emerald: "#34D399",
  amber: "#F59E0B",
  red: "#EF4444",
  orange: "#FB923C",
} as const;

export const FS = {
  tiny: 11,
  small: 13,
  base: 15,      // sunlight floor — isse chhota mat jaana
  big: 20,
  verdict: 28,   // giant fisher verdict
  nav: 32,       // navigate HUD numbers
} as const;

export const DHOOP = {
  // "dhoop mode" (harsh sunlight on deck): yellow-on-black, zero blue light
  bg: "#000000",
  surface: "#0A0A00",
  text: "#FFE500",
  accent: "#FFD000",
} as const;
