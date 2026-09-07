"use client";

/**
 * Tiny SVG sparkline for the advisory's real 48 h hourly series.
 * Renders the EXACT arrays the verdict rules read — same numbers,
 * just drawn as a trend a fisherman can glance at.
 */
export default function Sparkline({
  values,
  warnAt,
  dangerAt,
  unit,
  color = "#22d3ee",
  height = 44,
}: {
  values: (number | null)[];
  warnAt?: number;     // draw an amber dashed threshold line
  dangerAt?: number;   // draw a red dashed threshold line
  unit?: string;
  color?: string;
  height?: number;
}) {
  const nums = values.filter((v): v is number => v != null);
  if (nums.length < 2) return <div className="text-[10px] text-slate-600">no trend data</div>;

  const w = 100; // viewBox width, stretched by CSS
  const pad = 3;
  const min = Math.min(...nums, warnAt ?? Infinity, dangerAt ?? Infinity);
  const max = Math.max(...nums, warnAt ?? -Infinity, dangerAt ?? -Infinity);
  const span = max - min || 1;

  const px = values
    .map((v, i) => {
      if (v == null) return null;
      const x = pad + (i / (values.length - 1)) * (w - 2 * pad);
      const y = height - pad - ((v - min) / span) * (height - 2 * pad - 10);
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .filter(Boolean) as string[];

  const lastPt = px[px.length - 1].split(",").map(Number);
  const lastV = nums[nums.length - 1];
  const peakV = Math.max(...nums);
  const lineFor = (v: number) => height - pad - ((v - min) / span) * (height - 2 * pad - 10);

  return (
    <div className="relative">
      <svg
        viewBox={`0 0 ${w} ${height}`}
        preserveAspectRatio="none"
        className="w-full"
        style={{ height }}
        aria-label={`trend, last ${lastV} ${unit ?? ""}, peak ${peakV} ${unit ?? ""}`}
      >
        {/* threshold bands first (under the line) */}
        {warnAt != null && (
          <line x1={0} x2={w} y1={lineFor(warnAt)} y2={lineFor(warnAt)}
                stroke="#f59e0b" strokeWidth="0.5" strokeDasharray="2 2" opacity="0.7" />
        )}
        {dangerAt != null && (
          <line x1={0} x2={w} y1={lineFor(dangerAt)} y2={lineFor(dangerAt)}
                stroke="#ef4444" strokeWidth="0.6" strokeDasharray="3 2" opacity="0.8" />
        )}
        {/* area fill */}
        <polygon
          points={`${pad},${height - pad} ${px.join(" ")} ${lastPt[0]},${height - pad}`}
          fill={color} opacity="0.12"
        />
        {/* trend line */}
        <polyline points={px.join(" ")} fill="none" stroke={color} strokeWidth="1.6" strokeLinejoin="round" />
        {/* last point */}
        <circle cx={lastPt[0]} cy={lastPt[1]} r="1.8" fill={color} />
      </svg>
      <div className="flex justify-between text-[9px] text-slate-500 -mt-0.5">
        <span>now</span>
        <span className="font-medium text-slate-300">
          {peakV.toFixed(1)}{unit} peak
        </span>
        <span>+48h</span>
      </div>
    </div>
  );
}
