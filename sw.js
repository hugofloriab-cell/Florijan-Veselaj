/* ------------------------------------------------------------------
 * Service Worker
 *  • met le menu en cache (consultation même avec un réseau capricieux)
 *  • affiche la notification de rappel et rouvre l'application au clic
 * ------------------------------------------------------------------ */

const CACHE = "resto-menu-v4";

const PRECACHE = [
  "./",
  "./index.html",
  "./admin.html",
  "./manifest.webmanifest",
  "./assets/css/styles.css",
  "./assets/css/admin.css",
  "./assets/js/config.js",
  "./assets/js/contenu.js",
  "./assets/contenu.json",
  "./assets/js/serveur.js",
  "./assets/js/db.js",
  "./assets/js/flipbook.js",
  "./assets/js/reminder.js",
  "./assets/js/review.js",
  "./assets/js/app.js",
  "./assets/js/admin.js",
  "./assets/img/favicon.svg",
  "./assets/img/icon-192.png",
  "./assets/img/icon-512.png",
  "./assets/img/logo-tilleuls.png",
  "./assets/menu/tilleuls-1.svg",
  "./assets/menu/tilleuls-2.svg",
  "./assets/menu/tilleuls-3.svg",
  "./assets/menu/tilleuls-4.svg",
  "./assets/menu/tilleuls-5.svg",
  "./assets/menu/tilleuls-6.svg",
  "./assets/menu/tilleuls-7.svg",
  "./assets/menu/tilleuls-8.svg",
  "./assets/menu/tilleuls-9.svg",
  "./assets/menu/tilleuls-10.svg",
  "./assets/menu/tilleuls-11.svg"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      // addAll échoue en bloc si un fichier manque : on tolère les absents.
      .then((cache) => Promise.all(PRECACHE.map((url) => cache.add(url).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return;

  const url = new URL(req.url);
  if (url.origin !== location.origin) return; // polices, PDF.js… : on laisse passer

  // Navigation : réseau d'abord, cache en secours (hors ligne)
  if (req.mode === "navigate") {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then((r) => r || caches.match("./index.html")))
    );
    return;
  }

  // Le contenu éditable doit toujours venir du réseau quand il est joignable :
  // sinon une carte mise à jour resterait invisible derrière le cache.
  if (url.pathname.endsWith("/assets/contenu.json")) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req))
    );
    return;
  }

  // Code et feuilles de style : réseau d'abord, cache en secours.
  //
  // Servir le code depuis le cache sans jamais le revérifier revient à
  // graver la version installée le premier jour : une correction ne
  // parviendrait plus à un client qui a déjà ouvert l'application. Le
  // cache reste le filet hors ligne, il ne décide plus de la version.
  if (/\.(js|css)$/.test(url.pathname)) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res && res.status === 200 && res.type === "basic") {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(req, copy));
          }
          return res;
        })
        .catch(() => caches.match(req))
    );
    return;
  }

  // Images, polices, pages de la carte : cache d'abord, puis réseau.
  // Ces fichiers ne changent qu'à la faveur d'une nouvelle carte, et le
  // gain d'affichage est immédiat.
  event.respondWith(
    caches.match(req).then((cached) => {
      if (cached) return cached;
      return fetch(req).then((res) => {
        if (res && res.status === 200 && res.type === "basic") {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      });
    })
  );
});

/* --------- Clic sur la notification de rappel --------------------- */
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || "./index.html?avis=1";

  event.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ("focus" in client) {
          client.postMessage({ type: "ouvrir-avis" });
          return client.focus();
        }
      }
      return self.clients.openWindow(target);
    })
  );
});
