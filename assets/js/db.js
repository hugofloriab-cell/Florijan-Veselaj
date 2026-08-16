/* ------------------------------------------------------------------
 * Stockage local des avis privés (IndexedDB + repli localStorage)
 * ------------------------------------------------------------------ */

window.ReviewStore = (function () {
  const DB_NAME = "resto-avis";
  const DB_VERSION = 1;
  const STORE = "reviews";
  const LS_KEY = "resto-avis-fallback";

  let dbPromise = null;

  function openDb() {
    if (dbPromise) return dbPromise;

    dbPromise = new Promise((resolve, reject) => {
      if (!("indexedDB" in window)) return reject(new Error("IndexedDB indisponible"));

      const req = indexedDB.open(DB_NAME, DB_VERSION);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains(STORE)) {
          const store = db.createObjectStore(STORE, { keyPath: "id" });
          store.createIndex("createdAt", "createdAt");
          store.createIndex("rating", "rating");
        }
      };
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    }).catch((err) => {
      // On mémorise l'échec pour basculer définitivement sur localStorage.
      dbPromise = Promise.reject(err);
      throw err;
    });

    return dbPromise;
  }

  /* --- Repli localStorage (mode privé de certains navigateurs) ----- */
  function lsRead() {
    try {
      return JSON.parse(localStorage.getItem(LS_KEY) || "[]");
    } catch (_) {
      return [];
    }
  }
  function lsWrite(list) {
    try {
      localStorage.setItem(LS_KEY, JSON.stringify(list));
      return true;
    } catch (_) {
      return false; // quota dépassé (photos volumineuses)
    }
  }

  function tx(mode, fn) {
    return openDb().then(
      (db) =>
        new Promise((resolve, reject) => {
          const t = db.transaction(STORE, mode);
          const store = t.objectStore(STORE);
          let result;
          try {
            result = fn(store);
          } catch (err) {
            reject(err);
            return;
          }
          t.oncomplete = () => resolve(result && result.__req ? result.__req.result : result);
          t.onerror = () => reject(t.error);
          t.onabort = () => reject(t.error);
        })
    );
  }

  function newId() {
    const rnd =
      window.crypto && crypto.randomUUID
        ? crypto.randomUUID()
        : Math.random().toString(36).slice(2) + Date.now().toString(36);
    return "avis_" + rnd;
  }

  return {
    /** Ajoute un avis. Renvoie l'avis complet tel que stocké. */
    async add(review) {
      const record = Object.assign(
        {
          id: newId(),
          createdAt: Date.now(),
          read: false,
          archived: false
        },
        review
      );

      try {
        await tx("readwrite", (store) => store.put(record));
      } catch (_) {
        const list = lsRead();
        list.push(record);
        if (!lsWrite(list)) {
          // Dernier recours : on retente sans la photo plutôt que tout perdre.
          const light = Object.assign({}, record, { photo: null, photoDropped: true });
          list[list.length - 1] = light;
          lsWrite(list);
          return light;
        }
      }
      return record;
    },

    /** Tous les avis, du plus récent au plus ancien. */
    async all() {
      let list;
      try {
        list = await tx("readonly", (store) => ({ __req: store.getAll() }));
      } catch (_) {
        list = lsRead();
      }
      return (list || []).sort((a, b) => b.createdAt - a.createdAt);
    },

    async update(id, patch) {
      try {
        const db = await openDb();
        const current = await new Promise((resolve, reject) => {
          const req = db.transaction(STORE, "readonly").objectStore(STORE).get(id);
          req.onsuccess = () => resolve(req.result);
          req.onerror = () => reject(req.error);
        });
        if (!current) return null;
        const next = Object.assign({}, current, patch);
        await tx("readwrite", (store) => store.put(next));
        return next;
      } catch (_) {
        const list = lsRead();
        const idx = list.findIndex((r) => r.id === id);
        if (idx === -1) return null;
        list[idx] = Object.assign({}, list[idx], patch);
        lsWrite(list);
        return list[idx];
      }
    },

    async remove(id) {
      try {
        await tx("readwrite", (store) => store.delete(id));
      } catch (_) {
        lsWrite(lsRead().filter((r) => r.id !== id));
      }
    },

    async clear() {
      try {
        await tx("readwrite", (store) => store.clear());
      } catch (_) {
        /* ignore */
      }
      lsWrite([]);
    }
  };
})();
