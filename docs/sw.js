/* Service worker de la check-list petit déjeuner.
   Objectif : la fiche doit s'ouvrir même sans réseau, une fois installée.
   Changer CACHE à chaque mise en ligne pour que les tablettes récupèrent
   la nouvelle version. */
var CACHE = "checklist-pdj-v7";
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

  /* Page : on interroge d'abord le réseau, pour que les corrections
     apportées à la fiche apparaissent dès l'ouverture suivante. Au-delà
     de 2,5 secondes — wifi absent ou capricieux à 6h00 — on bascule sur
     la copie conservée sur l'appareil. */
  if(req.mode === "navigate"){
    e.respondWith(
      new Promise(function(resolve){
        var repondu = false;
        function repondre(r){ if(!repondu && r){ repondu = true; resolve(r); } }

        var secours = setTimeout(function(){
          caches.match("./index.html").then(repondre);
        }, 2500);

        fetch(req).then(function(res){
          clearTimeout(secours);
          if(res && res.ok){
            var copie = res.clone();
            caches.open(CACHE).then(function(c){ c.put("./index.html", copie); });
          }
          repondre(res);
        }).catch(function(){
          clearTimeout(secours);
          caches.match("./index.html").then(function(hit){
            repondre(hit || new Response(
              "<h1>Fiche indisponible</h1><p>Ouvrez la fiche une fois avec du réseau.</p>",
              { headers:{ "Content-Type":"text/html; charset=utf-8" } }));
          });
        });
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
