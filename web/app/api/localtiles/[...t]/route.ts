/**
 * Local OSM tile proxy — runs INSIDE the Next.js dev server, so the 3D
 * ocean can fetch real map tiles same-origin with zero CORS risk and
 * zero dependency on the Python backend being restarted. Tiles are
 * cached in memory; the 3D loader tries this FIRST, then the FastAPI
 * /api/v1/tiles disk-cached proxy, then OSM direct.
 */
import { NextRequest } from "next/server";

const UA = { "User-Agent": "ORCA-SIH-2026/1.0 (student marine demo; single-user interactive map)" };
const cache = new Map<string, ArrayBuffer>();

export async function GET(_req: NextRequest, { params }: { params: { t: string[] } }) {
  const [zs, xs, ysRaw] = params.t ?? [];
  const ys = (ysRaw || "").replace(/\.png$/i, "");
  const z = Number(zs), x = Number(xs), y = Number(ys);
  const n = Number.isInteger(z) && z >= 0 && z <= 19 ? 2 ** z : 0;
  if (!n || !(x >= 0 && x < n) || !(y >= 0 && y < n)) {
    return new Response("bad tile coords", { status: 400 });
  }
  const key = `${z}/${x}/${y}`;
  let buf = cache.get(key);
  if (!buf) {
    let upstream: Response;
    try {
      upstream = await fetch(`https://tile.openstreetmap.org/${z}/${x}/${y}.png`, {
        headers: UA, cache: "no-store",
      });
    } catch (e) {
      return new Response(`OSM tile fetch failed: ${e instanceof Error ? e.message : e}`, { status: 502 });
    }
    if (!upstream.ok) return new Response(`OSM tile HTTP ${upstream.status}`, { status: 502 });
    buf = await upstream.arrayBuffer();
    if (cache.size > 1000) cache.clear(); // simple in-memory bound (dev server)
    cache.set(key, buf);
  }
  return new Response(buf, {
    headers: { "Content-Type": "image/png", "Cache-Control": "public, max-age=86400" },
  });
}
