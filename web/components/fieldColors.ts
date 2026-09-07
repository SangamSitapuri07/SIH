/** Shared colour ramps for the Explorer — identical thresholds in the
 *  2D map and the 3D ocean so both views tell the same story. All
 *  thresholds are the advisory's real small-craft limits. */

export function chlColor(v: number): string {
  if (v >= 5) return "#ef4444";      // bloom-level
  if (v >= 2) return "#f59e0b";      // high
  if (v >= 0.5) return "#34d399";    // productive
  return "#64748b";                  // low
}
export function waveColor(v: number): string {
  if (v >= 4) return "#ef4444";      // unsafe
  if (v >= 2.5) return "#f59e0b";    // caution
  if (v >= 1.2) return "#0891b2";    // workable
  return "#38bdf8";                  // calm
}
export function windColor(v: number): string {
  if (v >= 34) return "#ef4444";     // gale
  if (v >= 28) return "#f59e0b";     // gust caution
  if (v >= 15) return "#a78bfa";
  return "#818cf8";                  // light
}
export function currentColor(v: number): string {
  if (v >= 3) return "#ef4444";      // very strong
  if (v >= 1.5) return "#f59e0b";    // strong
  if (v >= 0.6) return "#34d399";    // normal drift
  return "#38bdf8";                  // weak
}
export function sstColor(v: number): string {
  if (v >= 30) return "#ef4444";     // hot
  if (v >= 28.5) return "#f59e0b";   // warm
  if (v >= 26) return "#34d399";     // baitfish-friendly band
  return "#38bdf8";                  // cool
}
