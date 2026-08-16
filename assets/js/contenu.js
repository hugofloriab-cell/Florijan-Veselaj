/* ------------------------------------------------------------------
 * Contenu éditable depuis le panneau gérant
 * ------------------------------------------------------------------
 * Trois couches, de la plus faible à la plus forte :
 *
 *   1. config.js            valeurs d'usine, livrées avec le code
 *   2. assets/contenu.json  version publiée, vue par TOUS les clients
 *   3. localStorage         aperçu local, visible du seul gérant
 *
 * Le site étant statique, le panneau gérant ne peut rien écrire sur
 * l'hébergement : il produit le fichier `contenu.json` que le gérant dépose
 * ensuite chez son hébergeur. La couche 3 permet de tout voir et régler
 * avant de publier.
 * ------------------------------------------------------------------ */

window.Contenu = (function () {
  const CLE_LOCALE = "resto-contenu-local";
  const FICHIER = "assets/contenu.json";

  let publie = null;
  let local = null;

  /** Fusion profonde : les tableaux sont remplacés, pas concaténés. */
  function fusion(base, ajout) {
    if (!ajout || typeof ajout !== "object" || Array.isArray(ajout)) {
      return ajout === undefined ? base : ajout;
    }
    const out = Object.assign({}, base);
    Object.keys(ajout).forEach((k) => {
      out[k] =
        base && typeof base[k] === "object" && !Array.isArray(base[k])
          ? fusion(base[k], ajout[k])
          : ajout[k];
    });
    return out;
  }

  function lireLocal() {
    try {
      return JSON.parse(localStorage.getItem(CLE_LOCALE) || "null");
    } catch (_) {
      return null;
    }
  }

  return {
    /** Charge les surcouches et les applique à window.APP_CONFIG. */
    async appliquer(options) {
      const opts = options || {};

      try {
        // `no-store` : sans cela, une carte mise à jour resterait invisible
        // derrière le cache du navigateur.
        const r = await fetch(FICHIER, { cache: "no-store" });
        if (r.ok) publie = await r.json();
      } catch (_) {
        publie = null; // fichier absent (cas normal) ou hors ligne
      }

      local = opts.ignorerLocal ? null : lireLocal();

      let cfg = window.APP_CONFIG;
      if (publie) cfg = fusion(cfg, publie.config || publie);
      if (local) cfg = fusion(cfg, local.config || local);
      // On remplit l'objet existant plutôt que de le remplacer : les modules
      // qui en gardent une référence continuent de voir les bonnes valeurs.
      Object.keys(cfg).forEach((k) => {
        window.APP_CONFIG[k] = cfg[k];
      });

      return { publie: Boolean(publie), local: Boolean(local) };
    },

    /** Enregistre l'aperçu local (visible du seul gérant). */
    enregistrerLocal(config) {
      localStorage.setItem(
        CLE_LOCALE,
        JSON.stringify({ majLe: Date.now(), config: config })
      );
    },

    supprimerLocal() {
      localStorage.removeItem(CLE_LOCALE);
    },

    local: lireLocal,
    publie: () => publie,

    /** Contenu du fichier à déposer chez l'hébergeur. */
    fichier(config) {
      return JSON.stringify({ majLe: new Date().toISOString(), config: config }, null, 2);
    }
  };
})();
