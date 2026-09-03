/* ------------------------------------------------------------------
 * Liaison avec Supabase (facultative)
 * ------------------------------------------------------------------
 * Sans `serveur.url` dans config.js, l'application reste 100 % locale et
 * ce module ne fait rien. Renseigné, il devient la source de vérité des
 * avis : ils quittent le téléphone du client pour arriver chez le gérant.
 *
 * Appels REST directs, sans bibliothèque : rien à charger, rien à mettre
 * à jour, et le comportement reste lisible.
 *
 * Sécurité : la clé « anon » est publique par nature — elle vit dans la
 * page. Ce qui protège réellement les données, ce sont les règles RLS
 * définies dans `serveur/schema.sql` : le public peut écrire un avis,
 * jamais en lire un. La lecture exige une vraie connexion.
 * ------------------------------------------------------------------ */

window.Serveur = (function () {
  const CLE_SESSION = "resto-serveur-session";

  const conf = () => (window.APP_CONFIG && window.APP_CONFIG.serveur) || {};
  const actif = () => Boolean(conf().url && conf().cleAnon);
  const base = () => String(conf().url).replace(/\/+$/, "");

  /* ------------------------------------------------------- session */
  function session() {
    try {
      const s = JSON.parse(sessionStorage.getItem(CLE_SESSION) || "null");
      return s && s.expireLe > Date.now() ? s : null;
    } catch (_) {
      return null;
    }
  }

  function enTetes(avecSession) {
    const s = avecSession ? session() : null;
    // Supabase attend la clé dans les deux en-têtes, et le client officiel
    // fait de même : `apikey` désigne le projet, `Authorization` porte
    // l'identité. Sans ce second en-tête, la requête n'obtient pas le rôle
    // « anon » et se heurte aux règles RLS — « new row violates row-level
    // security policy », même quand le dépôt public est autorisé.
    return {
      apikey: conf().cleAnon,
      Authorization: "Bearer " + (s ? s.token : conf().cleAnon),
      "Content-Type": "application/json"
    };
  }

  async function reponse(r) {
    if (r.ok) {
      // Un dépôt réussi ne renvoie pas de corps : `r.json()` échouerait sur
      // une réponse vide. On lit le texte, et on ne l'analyse que s'il y en a.
      const texte = await r.text();
      return texte ? JSON.parse(texte) : null;
    }
    let detail = "";
    try {
      const e = await r.json();
      detail = e.message || e.error_description || e.msg || e.hint || "";
    } catch (_) {
      /* corps non lisible */
    }
    const err = new Error(detail || `Erreur ${r.status}`);
    err.statut = r.status;
    throw err;
  }

  return {
    actif,
    session,

    /** Connexion du gérant (compte Supabase, vérifié côté serveur). */
    async connexion(email, motDePasse) {
      const r = await fetch(base() + "/auth/v1/token?grant_type=password", {
        method: "POST",
        headers: enTetes(false),
        body: JSON.stringify({ email: email, password: motDePasse })
      });
      const d = await reponse(r);
      const s = {
        token: d.access_token,
        // On se garde une minute de marge sur l'expiration annoncée.
        expireLe: Date.now() + (d.expires_in - 60) * 1000,
        email: (d.user && d.user.email) || email
      };
      sessionStorage.setItem(CLE_SESSION, JSON.stringify(s));
      return s;
    },

    deconnexion() {
      sessionStorage.removeItem(CLE_SESSION);
    },

    /** Dépôt d'un avis. Ouvert au public, en écriture seule.
     *
     * `return=minimal` est délibéré : redemander la ligne écrite obligerait
     * le client à pouvoir la relire, donc à ouvrir la lecture au public —
     * exactement ce que les règles RLS interdisent. On écrit, et on s'en
     * tient là. */
    async envoyerAvis(avis) {
      const r = await fetch(base() + "/rest/v1/avis", {
        method: "POST",
        headers: Object.assign(enTetes(false), { Prefer: "return=minimal" }),
        body: JSON.stringify({
          note: avis.rating,
          commentaire: avis.comment || null,
          photo: avis.photo || null,
          canal: avis.channel,
          plateforme: avis.platform || null,
          table_no: avis.table || null,
          contact: avis.contact || null,
          cree_le: new Date(avis.createdAt || Date.now()).toISOString()
        })
      });
      const lignes = await reponse(r);
      return Array.isArray(lignes) ? lignes[0] : lignes;
    },

    /** Lecture des avis — réservée au gérant connecté. */
    async listerAvis() {
      if (!session()) throw new Error("Session expirée");
      const r = await fetch(
        base() + "/rest/v1/avis?select=*&order=cree_le.desc&limit=500",
        { headers: enTetes(true) }
      );
      const lignes = await reponse(r);
      return (lignes || []).map((l) => ({
        id: l.id,
        createdAt: new Date(l.cree_le).getTime(),
        rating: l.note,
        comment: l.commentaire || "",
        photo: l.photo || null,
        channel: l.canal,
        platform: l.plateforme || null,
        table: l.table_no || null,
        contact: l.contact || null,
        read: Boolean(l.lu),
        distant: true
      }));
    },

    async majAvis(id, patch) {
      const corps = {};
      if ("read" in patch) corps.lu = patch.read;
      if ("platform" in patch) corps.plateforme = patch.platform;
      const r = await fetch(base() + `/rest/v1/avis?id=eq.${encodeURIComponent(id)}`, {
        method: "PATCH",
        headers: enTetes(true),
        body: JSON.stringify(corps)
      });
      return reponse(r);
    },

    /** La carte publiée. Lecture ouverte : les clients doivent la voir. */
    async lireContenu(delai) {
      // Un serveur lent ne doit pas retenir l'ouverture de la carte : au-delà
      // du délai, on rend la main et l'application se rabat sur ce qu'elle a.
      const stop = new AbortController();
      const minuteur = setTimeout(() => stop.abort(), delai || 2500);
      try {
        const r = await fetch(
          base() + "/rest/v1/contenu?id=eq.carte&select=donnees,maj_le",
          { headers: enTetes(false), signal: stop.signal, cache: "no-store" }
        );
        const lignes = await reponse(r);
        return (lignes && lignes[0]) || null;
      } finally {
        clearTimeout(minuteur);
      }
    },

    /** Publie la carte. Réservé au gérant connecté. */
    async publierContenu(config) {
      if (!session()) throw new Error("Session expirée");
      const corps = {
        id: "carte",
        donnees: { majLe: new Date().toISOString(), config: config },
        maj_le: new Date().toISOString()
      };
      // `resolution=merge-duplicates` : la première publication insère, les
      // suivantes remplacent la même ligne. Pas de doublon possible.
      const r = await fetch(base() + "/rest/v1/contenu?on_conflict=id", {
        method: "POST",
        headers: Object.assign(enTetes(true), {
          Prefer: "resolution=merge-duplicates,return=minimal"
        }),
        body: JSON.stringify(corps)
      });
      return reponse(r);
    },

    async supprimerAvis(id) {
      const r = await fetch(base() + `/rest/v1/avis?id=eq.${encodeURIComponent(id)}`, {
        method: "DELETE",
        headers: enTetes(true)
      });
      return reponse(r);
    }
  };
})();
