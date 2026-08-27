/* Service worker de la check-list petit déjeuner.
   Objectif : la fiche doit s'ouvrir même sans réseau, une fois installée.
   Changer CACHE à chaque mise en ligne pour que les tablettes récupèrent
   la nouvelle version. */
var CACHE = "checklist-pdj-v1";
var CORE = [
  "./",
  "./index.html",
  "./manifest.webmanifest",
  "./icone-192.png",
  "./icone-512.png",
  "./icone-maskable-512.png"
];

self.addEventListener("install", function(e){
  e.waitUntil(
    caches.open(CACHE)
      .then(function(c){ return c.addAll(CORE); })
      .then(function(){ return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function(e){
  e.waitUntil(
    caches.keys()
      .then(function(keys){
        return Promise.all(keys.map(function(k){
          return k === CACHE ? null : caches.delete(k);
        }));
      })
      .then(function(){ return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function(e){
  var req = e.request;
  if(req.method !== "GET") return;

  /* Page : on sert le cache immédiatement (démarrage à 6h00 sans attendre le
     réseau) et on rafraîchit en arrière-plan pour la prochaine ouverture. */
  if(req.mode === "navigate"){
    e.respondWith(
      caches.match("./index.html").then(function(hit){
        var live = fetch(req).then(function(res){
          if(res && res.ok){
            var copy = res.clone();
            caches.open(CACHE).then(function(c){ c.put("./index.html", copy); });
          }
          return res;
        }).catch(function(){ return hit; });
        return hit || live;
      })
    );
    return;
  }

  e.respondWith(
    caches.match(req).then(function(hit){
      if(hit) return hit;
      return fetch(req).then(function(res){
        if(res && res.ok && (res.type === "basic" || res.type === "cors")){
          var copy = res.clone();
          caches.open(CACHE).then(function(c){ c.put(req, copy); });
        }
        return res;
      }).catch(function(){ return hit; });
    })
  );
});
