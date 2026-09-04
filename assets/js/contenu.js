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

  /* Une page importée depuis le panneau est une image embarquée
     (« data:… ») ; une page livrée avec le code est un chemin de fichier.
     Seules les premières appartiennent au gérant. */
  const estImportee = (src) => typeof src === "string" && src.startsWith("data:");

  /* Chaque carte va avec son cadrage de lecture : `images` avec
     `lecture.pages`, `imagesEn` avec `lecture.pagesEn`. Les deux se
     gardent ou se jettent ensemble — un cadrage sans ses pages cadrerait
     de travers celles d'à côté. */
  const CARTES = [
    { pages: "images", cadrage: "pages" },
    { pages: "imagesEn", cadrage: "pagesEn" }
  ];

  /**
   * Retire d'un menu ce qui décrit la carte livrée avec le code.
   *
   * Sans cela, publier gèle la carte telle qu'elle était dans le navigateur
   * du gérant, et cette copie l'emporte ensuite sur le code : une nouvelle
   * carte livrée par mise à jour resterait invisible, et les clients
   * verraient indéfiniment l'ancienne. Le cadrage de lecture court le même
   * risque — mesuré sur un PDF, il ne décrit que celui-là et cadrerait de
   * travers son successeur.
   *
   * Ce que le gérant a lui-même importé reste : ses pages sont embarquées
   * dans la surcouche (« data:… »), et le cadrage que le panneau a mesuré
   * dessus les accompagne. Il publie sa carte et ses réglages, pas les
   * fichiers de l'application.
   */
  function elaguerMenu(menu) {
    if (!menu) return;
    CARTES.forEach(({ pages, cadrage }) => {
      const liste = menu[pages];
      const sienne = Array.isArray(liste) && liste.some(estImportee);
      if (!sienne) {
        delete menu[pages];
        if (menu.lecture) delete menu.lecture[cadrage];
      }
    });
    // Le cadrage de repli vient du code : il n'a rien à faire sur le serveur.
    if (menu.lecture) {
      delete menu.lecture.defaut;
      if (!Object.keys(menu.lecture).length) delete menu.lecture;
    }
  }

  function nettoyer(surcouche) {
    if (!surcouche) return surcouche;
    const c = surcouche.config || surcouche;
    if (c && c.menu) elaguerMenu(c.menu);
    return surcouche;
  }

  /* On garde la ligne entière — `maj_le` compris — et non les seules
     données : c'est cette colonne, écrite par le serveur, qui sert de
     repère pour savoir si la carte a changé. La date rangée dans les
     données, elle, vient du navigateur du gérant et ne coïncide pas. */
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
    const garde = cache();
    try {
      const ligne = await Serveur.lireContenu(opts.delaiServeur, garde && garde.maj_le);
      // Rien n'a bougé depuis la dernière visite : on garde ce qu'on a, et
      // les mégaoctets de la carte ne repassent pas sur le réseau.
      if (ligne && ligne.inchange && garde) return garde.donnees;
      if (ligne && ligne.donnees) {
        cache({ maj_le: ligne.maj_le, donnees: ligne.donnees });
        return ligne.donnees;
      }
      // Le serveur répond, mais rien n'a jamais été publié : le cache
      // deviendrait un fantôme. On l'efface.
      cache(null);
      return null;
    } catch (_) {
      // Serveur injoignable ou trop lent : la dernière version reçue vaut
      // mieux qu'une carte périmée du dépôt.
      return garde && garde.donnees;
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
        if (r.ok) publie = nettoyer(await r.json());
      } catch (_) {
        publie = null; // fichier absent (cas normal) ou hors ligne
      }

      distant = nettoyer(await lireDistant(opts));
      // L'aperçu du gérant suit la même règle : ses pages importées comptent,
      // les chemins du code non. Sans cela, un aperçu enregistré autrefois
      // continuerait d'imposer une carte périmée sur l'appareil du gérant,
      // et lui seul verrait la mauvaise version — le pire des cas.
      local = opts.ignorerLocal ? null : nettoyer(lireLocal());

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

    /** La configuration telle qu'elle doit être publiée.
     *
     * Les pages livrées avec le code et leur cadrage de lecture en sont
     * retirés : ce ne sont pas des réglages du gérant, et les publier les
     * figerait pour tout le monde. Voir `nettoyer`, qui applique la même
     * règle en lecture — une publication faite avant cette règle ne peut
     * donc plus nuire.
     */
    pourPublication(config) {
      const c = JSON.parse(JSON.stringify(config));
      elaguerMenu(c.menu);
      return c;
    },

    /** Contenu du fichier à déposer chez l'hébergeur. */
    fichier(config) {
      return JSON.stringify(
        { majLe: new Date().toISOString(), config: this.pourPublication(config) },
        null,
        2
      );
    }
  };
})();
