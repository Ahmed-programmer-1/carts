const CACHE = "library-v6-shell";
const SHELL = [
  "./",
  "./index.html",
  "./style.css",
  "./app.js",
  "./sites.json",
  "./manifest.json",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/icon-maskable-512.png"
];

self.addEventListener("install", e => {
  e.waitUntil(
    caches.open(CACHE)
      .then(c => Promise.all(SHELL.map(url => c.add(url).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

// The public site sends the full list of lesson/image URLs here after loading
// sites.json, so the whole library (not just pages you've opened) gets cached
// for offline use. Skips anything already cached, so it won't re-download on
// every visit.
self.addEventListener("message", e => {
  if (e.data && e.data.type === "PRECACHE_URLS" && Array.isArray(e.data.urls)) {
    e.waitUntil((async () => {
      const cache = await caches.open(CACHE);
      const missing = [];
      for (const url of e.data.urls) {
        const hit = await cache.match(url);
        if (!hit) missing.push(url);
      }
      await Promise.all(missing.map(u => cache.add(u).catch(() => null)));
    })());
  }
});

self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  const u = new URL(e.request.url);

  // sites.json: always try network first so new content shows up, fall back to cache offline
  if (u.pathname.endsWith("/sites.json")) {
    e.respondWith(
      fetch(e.request)
        .then(r => { const copy = r.clone(); caches.open(CACHE).then(c => c.put(e.request, copy)); return r })
        .catch(() => caches.match(e.request))
    );
    return;
  }

  // never intercept admin.html or the GitHub API — always go to network
  if (u.pathname.endsWith("/admin.html") || u.hostname.endsWith("github.com")) return;

  if (u.origin === location.origin) {
    e.respondWith((async () => {
      const cached = await caches.match(e.request);
      if (cached) {
        // serve from cache instantly, refresh in the background for next time
        fetch(e.request).then(r => {
          if (r.ok) caches.open(CACHE).then(c => c.put(e.request, r.clone()));
        }).catch(() => {});
        return cached;
      }
      try {
        const r = await fetch(e.request);
        if (r.ok) caches.open(CACHE).then(c => c.put(e.request, r.clone()));
        return r;
      } catch (err) {
        return new Response("", { status: 503, statusText: "Offline" });
      }
    })());
  }
});
