/* ORCA service worker — honest offline support for fishermen.
 *
 * What it DOES cache (safe, static imagery):
 *   - OpenStreetMap / OpenSeaMap tiles  (map pictures never expire)
 *   - App static chunks (_next/static) (the app shell)
 *
 * What it NEVER caches:
 *   - /api/* calls — serving stale marine data as if fresh would be the
 *     exact dishonesty this app exists to fight. API answers come from
 *     the network or not at all; the UI then shows its last-known data
 *     WITH its real timestamp and an OFFLINE badge.
 */
const TILES = "orca-tiles-v1";
const SHELL = "orca-shell-v1";
const MAX_TILES = 1800;

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const u = new URL(req.url);

  const isTile =
    u.hostname === "tile.openstreetmap.org" ||
    u.hostname.endsWith(".tile.openstreetmap.org") ||
    u.hostname === "tiles.openseamap.org";
  if (isTile) {
    e.respondWith(
      caches.open(TILES).then(async (cache) => {
        const hit = await cache.match(req);
        if (hit) return hit;
        try {
          const resp = await fetch(req);
          if (resp.ok) {
            cache.put(req, resp.clone());
            cache.keys().then((keys) => {
              if (keys.length > MAX_TILES) {
                keys.slice(0, keys.length - MAX_TILES).forEach((k) => cache.delete(k));
              }
            });
          }
          return resp;
        } catch (err) {
          // offline AND tile never seen before — honest empty picture,
          // the grid markers/position still show over it
          return Response.error();
        }
      })
    );
    return;
  }

  const isShell = u.origin === self.location.origin && u.pathname.startsWith("/_next/static");
  if (isShell) {
    e.respondWith(
      caches.open(SHELL).then(async (cache) => {
        const hit = await cache.match(req);
        if (hit) return hit;
        const resp = await fetch(req);
        if (resp.ok) cache.put(req, resp.clone());
        return resp;
      })
    );
    return;
  }
  // API calls & HTML: network-only. Fresh or honestly failed — never cached-stale.
});
