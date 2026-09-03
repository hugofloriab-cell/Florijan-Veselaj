/* ------------------------------------------------------------------
 * Contenu éditable depuis le panneau gérant
 * ------------------------------------------------------------------
 * Quatre couches, de la plus faible à la plus forte :
 *
 *   1. config.js            valeurs d'usine, livrées avec le code
 *   2. assets/contenu.json  fichier déposé chez l'hébergeur
 *   3. le serveur           publié en un geste depuis le panneau gérant
 *   4. localStorage         aperçu local, visible du seul gérant
 *
 * Sans serveur, le panneau ne peut rien écrire sur un hébergement
 * statique : il produit alors le fichier de la couche 2, à déposer à la
 * main. Avec un serveur, la couche 3 rend ce détour inutile — le gérant
 * publie, et le changement est visible de tous en quelques secondes.
 *
 * Le serveur ne doit jamais retenir l'ouverture de la carte : sa lecture
 * est limitée dans le temps, et la dernière version reçue est gardée en
 * réserve pour un client hors ligne.
 * ------------------------------------------------------------------ */

window.Contenu = (function () {
  const CLE_LOCALE = "resto-contenu-local";
  const CLE_CACHE = "resto-contenu-serveur";
  const FICHIER = "assets/contenu.json";

  let publie = null;
  let distant = null;
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

  function cache(valeur) {
    try {
      if (valeur === undefined) {
        return JSON.parse(localStorage.getItem(CLE_CACHE) || "null");
      }
      if (valeur) localStorage.setItem(CLE_CACHE, JSON.stringify(valeur));
      else localStorage.removeItem(CLE_CACHE);
    } catch (_) {
      /* stockage plein ou refusé : on s'en passe */
    }
    return null;
  }

  /** La carte publiée sur le serveur, ou la dernière connue. */
  async function lireDistant(opts) {
    if (opts.ignorerDistant || !window.Serveur || !Serveur.actif()) return null;
    try {
      const ligne = await Serveur.lireContenu(opts.delaiServeur);
      if (ligne && ligne.donnees) {
        cache(ligne.donnees);
        return ligne.donnees;
      }
      // Le serveur répond, mais rien n'a jamais été publié : le cache
      // deviendrait un fantôme. On l'efface.
      cache(null);
      return null;
    } catch (_) {
      // Serveur injoignable ou trop lent : la dernière version reçue vaut
      // mieux qu'une carte périmée du dépôt.
      return cache();
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

      distant = await lireDistant(opts);
      local = opts.ignorerLocal ? null : lireLocal();

      let cfg = window.APP_CONFIG;
      if (publie) cfg = fusion(cfg, publie.config || publie);
      if (distant) cfg = fusion(cfg, distant.config || distant);
      if (local) cfg = fusion(cfg, local.config || local);
      // On remplit l'objet existant plutôt que de le remplacer : les modules
      // qui en gardent une référence continuent de voir les bonnes valeurs.
      Object.keys(cfg).forEach((k) => {
        window.APP_CONFIG[k] = cfg[k];
      });

      return {
        publie: Boolean(publie),
        distant: Boolean(distant),
        local: Boolean(local)
      };
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
    distant: () => distant,

    /** Contenu du fichier à déposer chez l'hébergeur. */
    fichier(config) {
      return JSON.stringify({ majLe: new Date().toISOString(), config: config }, null, 2);
    }
  };
})();
