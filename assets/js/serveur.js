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
    const h = { apikey: conf().cleAnon, "Content-Type": "application/json" };
    // `Authorization` uniquement pour une vraie session. Les nouvelles clés
    // « sb_publishable_… » ne sont pas des jetons JWT : les envoyer en Bearer
    // ferait échouer la requête. Sans en-tête, le rôle « anon » est déduit de
    // `apikey` — ce qui marche avec les deux formats de clé.
    if (s) h.Authorization = "Bearer " + s.token;
    return h;
  }

  async function reponse(r) {
    if (r.ok) return r.status === 204 ? null : r.json();
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
        headers: { apikey: conf().cleAnon, "Content-Type": "application/json" },
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

    /** Dépôt d'un avis. Ouvert au public, en écriture seule. */
    async envoyerAvis(avis) {
      const r = await fetch(base() + "/rest/v1/avis", {
        method: "POST",
        headers: Object.assign(enTetes(false), { Prefer: "return=representation" }),
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

    async supprimerAvis(id) {
      const r = await fetch(base() + `/rest/v1/avis?id=eq.${encodeURIComponent(id)}`, {
        method: "DELETE",
        headers: enTetes(true)
      });
      return reponse(r);
    }
  };
})();
