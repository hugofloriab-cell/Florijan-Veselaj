/* ------------------------------------------------------------------
 * Panneau gérant — consultation des avis restés privés
 * ------------------------------------------------------------------ */

(function () {
  "use strict";

  const cfg = window.APP_CONFIG;
  const SESSION_KEY = "resto-admin-session";
  let reviews = [];
  let filter = "prive";

  /* ------------------------------------------------------- outils */
  async function sha256(text) {
    const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf))
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");
  }
  // Utilitaire pour générer une nouvelle empreinte depuis la console.
  window.hashPassword = sha256;

  function toast(msg) {
    const t = document.getElementById("toast");
    t.textContent = msg;
    t.hidden = false;
    requestAnimationFrame(() => t.classList.add("is-visible"));
    clearTimeout(t._timer);
    t._timer = setTimeout(() => {
      t.classList.remove("is-visible");
      setTimeout(() => (t.hidden = true), 300);
    }, 3000);
  }

  const fmtDate = (ts) =>
    new Date(ts).toLocaleString("fr-FR", {
      weekday: "short",
      day: "numeric",
      month: "short",
      hour: "2-digit",
      minute: "2-digit"
    });

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, (c) => ({
      "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
    }[c]));
  }

  /* ----------------------------------------------------- connexion */
  function sessionValid() {
    if (window.Serveur && Serveur.actif()) return Boolean(Serveur.session());
    try {
      const s = JSON.parse(sessionStorage.getItem(SESSION_KEY) || "null");
      return s && s.until > Date.now();
    } catch (_) {
      return false;
    }
  }

  function openSession() {
    sessionStorage.setItem(
      SESSION_KEY,
      JSON.stringify({ until: Date.now() + cfg.admin.sessionMinutes * 60000 })
    );
  }

  let loggingIn = false;

  async function login(e) {
    e.preventDefault();
    if (loggingIn) return;
    loggingIn = true;
    const input = document.getElementById("password");
    const err = document.getElementById("loginError");

    if (window.Serveur && Serveur.actif()) {
      // Vérification côté serveur : tentatives limitées, mot de passe jamais
      // comparé dans la page.
      const email = document.getElementById("email").value.trim();
      try {
        await Serveur.connexion(email, input.value);
      } catch (e) {
        loggingIn = false;
        // Un diagnostic utile vaut mieux qu'un « Failed to fetch » opaque.
        if (e.statut === 400) {
          err.textContent = "E-mail ou mot de passe incorrect.";
        } else if (e.statut === undefined) {
          err.textContent =
            "Serveur injoignable. Vérifiez votre connexion, l'adresse du projet, " +
            "ou que le projet Supabase n'est pas en pause.";
        } else if (e.statut === 401 || e.statut === 403) {
          err.textContent = "Clé du projet refusée. Vérifiez la clé publique dans la configuration.";
        } else {
          err.textContent = "Connexion impossible : " + e.message;
        }
        input.value = "";
        input.focus();
        return;
      }
      loggingIn = false;
      err.textContent = "";
      openSession();
      showDashboard();
      return;
    }

    const hash = await sha256(input.value);
    loggingIn = false;

    if (hash !== cfg.admin.passwordSha256) {
      err.textContent = "Mot de passe incorrect.";
      input.value = "";
      input.focus();
      return;
    }
    err.textContent = "";
    openSession();
    showDashboard();
  }

  async function showDashboard() {
    document.getElementById("login").hidden = true;
    document.getElementById("dashboard").hidden = false;
    document.getElementById("adminSubtitle").textContent =
      cfg.restaurant.name + " · retours reçus en interne";
    await refresh();
  }

  /* -------------------------------------------------------- données */
  let alerte = "";

  async function refresh() {
    const locaux = await window.ReviewStore.all();

    if (window.Serveur && Serveur.actif()) {
      try {
        const distants = await Serveur.listerAvis();
        // Les avis encore en local et non partis sont affichés en plus,
        // pour que rien ne semble avoir disparu.
        const enAttente = locaux.filter((a) => !a.envoye);
        reviews = distants.concat(enAttente).sort((a, b) => b.createdAt - a.createdAt);
        alerte = enAttente.length
          ? `${enAttente.length} avis pas encore transmis (réseau) — ils repartiront tout seuls.`
          : "";
      } catch (e) {
        reviews = locaux;
        alerte = "Serveur injoignable : seuls les avis de cet appareil sont affichés.";
      }
    } else {
      reviews = locaux;
      alerte = "";
    }

    renderStats();
    renderList();
    const banniere = document.getElementById("alerte");
    if (banniere) {
      banniere.textContent = alerte;
      banniere.hidden = !alerte;
    }
  }

  const privateOnes = () => reviews.filter((r) => r.channel === "prive");

  function renderStats() {
    const priv = privateOnes();
    const pub = reviews.filter((r) => r.channel === "public");
    const unread = priv.filter((r) => !r.read).length;
    const avg = reviews.length
      ? (reviews.reduce((s, r) => s + r.rating, 0) / reviews.length).toFixed(1)
      : "–";

    document.getElementById("stats").innerHTML = [
      ["Avis privés", priv.length, unread ? unread + " non lu" + (unread > 1 ? "s" : "") : "à jour"],
      ["Redirigés", pub.length, "vers les plateformes"],
      ["Note moyenne", avg, "toutes notes confondues"]
    ]
      .map(
        ([label, value, sub]) => `
        <div class="stat">
          <small>${label}</small>
          <strong>${value}</strong>
          <span>${sub}</span>
        </div>`
      )
      .join("");

    // Répartition des notes
    const counts = [1, 2, 3, 4, 5].map((n) => reviews.filter((r) => r.rating === n).length);
    const max = Math.max(1, ...counts);
    document.getElementById("bars").innerHTML = counts
      .map((c, i) => {
        const n = i + 1;
        const cls = n >= cfg.review.threshold ? "bar--pub" : "bar--priv";
        return `
        <div class="bar ${cls}">
          <span class="bar__label">${n}★</span>
          <span class="bar__track"><span class="bar__fill" style="width:${(c / max) * 100}%"></span></span>
          <span class="bar__count">${c}</span>
        </div>`;
      })
      .join("");
  }

  function visible() {
    if (filter === "tous") return reviews;
    if (filter === "public") return reviews.filter((r) => r.channel === "public");
    if (filter === "non-lus") return privateOnes().filter((r) => !r.read);
    return privateOnes();
  }

  function renderList() {
    const list = visible();
    const box = document.getElementById("list");

    if (!list.length) {
      box.innerHTML = `<p class="empty">Aucun avis dans cette catégorie pour le moment.</p>`;
      return;
    }

    box.innerHTML = list
      .map((r) => {
        const stars = "★★★★★".slice(0, r.rating) + "☆☆☆☆☆".slice(0, 5 - r.rating);
        const badge =
          r.channel === "public"
            ? `<span class="badge badge--pub">Redirigé${r.platform ? " · " + r.platform : ""}</span>`
            : `<span class="badge badge--priv">Privé</span>`;

        return `
        <article class="card ${r.read ? "" : "is-new"}" data-id="${r.id}">
          <header class="card__head">
            <span class="card__stars" aria-label="${r.rating} sur 5">${stars}</span>
            ${badge}
            <time>${fmtDate(r.createdAt)}</time>
          </header>

          ${r.comment ? `<p class="card__comment">${escapeHtml(r.comment)}</p>` : `<p class="card__comment card__comment--none">Sans commentaire</p>`}

          ${r.photo ? `<img class="card__photo" src="${r.photo}" alt="Photo jointe" data-photo="${r.id}">` : ""}

          <ul class="card__meta">
            ${r.table ? `<li>Table ${escapeHtml(r.table)}</li>` : ""}
            ${r.contact ? `<li>Contact : ${escapeHtml(r.contact)}</li>` : ""}
            ${r.photoDropped ? `<li>Photo non conservée (mémoire saturée)</li>` : ""}
          </ul>

          <footer class="card__actions">
            <button class="link" data-act="read" type="button">${r.read ? "Marquer non lu" : "Marquer comme lu"}</button>
            <button class="link link--danger" data-act="del" type="button">Supprimer</button>
          </footer>
        </article>`;
      })
      .join("");
  }


  /* ==================================================================
   * ÉDITEUR DE CONTENU
   * ------------------------------------------------------------------
   * Avec un serveur, « Publier » publie vraiment : les changements
   * partent sur Supabase et tous les clients les voient à leur prochaine
   * ouverture. Sans serveur, le site est statique et rien ne peut être
   * écrit sur l'hébergement : l'éditeur produit alors `contenu.json`, que
   * le gérant dépose lui-même dans `assets/`.
   *
   * Dans les deux cas, l'aperçu local permet de tout voir avant.
   * ================================================================== */

  const PDFJS = {
    lib: "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",
    worker: "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js"
  };

  let brouillon = null; // configuration en cours d'édition

  function copie(o) {
    return JSON.parse(JSON.stringify(o));
  }

  function initBrouillon() {
    const c = window.APP_CONFIG;
    brouillon = {
      restaurant: copie(c.restaurant),
      menu: {
        type: "images",
        images: (c.menu.images || []).slice(),
        imagesEn: (c.menu.imagesEn || []).slice()
      },
      review: { threshold: c.review.threshold, publicLinks: copie(c.review.publicLinks) },
      reminder: { delays: c.reminder.delays.slice(), defaultDelay: c.reminder.defaultDelay },
      admin: { passwordSha256: c.admin.passwordSha256 }
    };
  }

  /* --------------------------------------------------- images */
  function compresser(fichier, maxLarg, qualite) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(fichier);
      const img = new Image();
      img.onload = () => {
        const k = Math.min(1, maxLarg / img.width);
        const cv = document.createElement("canvas");
        cv.width = Math.round(img.width * k);
        cv.height = Math.round(img.height * k);
        cv.getContext("2d").drawImage(img, 0, 0, cv.width, cv.height);
        URL.revokeObjectURL(url);
        resolve(cv.toDataURL("image/jpeg", qualite));
      };
      img.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error("Image illisible : " + fichier.name));
      };
      img.src = url;
    });
  }

  function chargerScript(src) {
    return new Promise((resolve, reject) => {
      const s = document.createElement("script");
      s.src = src;
      s.onload = resolve;
      s.onerror = () => reject(new Error("PDF.js n'a pas pu être chargé (connexion ?)"));
      document.head.appendChild(s);
    });
  }

  async function pdfEnImages(fichier, avance) {
    if (!window.pdfjsLib) await chargerScript(PDFJS.lib);
    if (!window.pdfjsLib) throw new Error("PDF.js introuvable");
    pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS.worker;

    const buf = await fichier.arrayBuffer();
    const doc = await pdfjsLib.getDocument({ data: buf }).promise;
    const out = [];
    for (let i = 1; i <= doc.numPages; i++) {
      avance(`Découpage du PDF… page ${i} sur ${doc.numPages}`);
      const page = await doc.getPage(i);
      const base = page.getViewport({ scale: 1 });
      // 1240 px : lisible jusqu'au zoom ×2 sur un téléphone, sans faire
      // peser la carte plusieurs mégaoctets — chaque client la télécharge.
      const vp = page.getViewport({ scale: 1240 / base.width });
      const cv = document.createElement("canvas");
      cv.width = Math.round(vp.width);
      cv.height = Math.round(vp.height);
      await page.render({ canvasContext: cv.getContext("2d"), viewport: vp }).promise;
      out.push(cv.toDataURL("image/jpeg", 0.66));
      cv.width = cv.height = 0;
    }
    return out;
  }

  /* Les deux cartes — française et anglaise — partagent le même éditeur.
     Seuls changent le tableau visé et les identifiants dans la page. */
  const CARTES = {
    fr: { cle: "images", pages: "menuPages", etat: "menuEtat", reset: "menuReset" },
    en: { cle: "imagesEn", pages: "menuPagesEn", etat: "menuEtatEn", reset: "menuResetEn" }
  };

  const estImportee = (src) => typeof src === "string" && src.startsWith("data:");

  const pagesDe = (langue) => {
    const cle = CARTES[langue].cle;
    if (!Array.isArray(brouillon.menu[cle])) brouillon.menu[cle] = [];
    return brouillon.menu[cle];
  };

  async function ajouterFichiers(liste, langue) {
    const c = CARTES[langue || "fr"];
    const etat = document.getElementById(c.etat);
    const fichiers = Array.from(liste);
    if (!fichiers.length) return;

    const images = [];
    try {
      for (const f of fichiers) {
        if (f.type === "application/pdf") {
          const pages = await pdfEnImages(f, (m) => (etat.textContent = m));
          images.push.apply(images, pages);
        } else if (f.type.startsWith("image/")) {
          etat.textContent = `Traitement de ${f.name}…`;
          images.push(await compresser(f, 1240, 0.7));
        }
      }
    } catch (err) {
      etat.textContent = "⚠ " + err.message;
      return;
    }

    if (!images.length) {
      etat.textContent = "Aucune image ni PDF reconnu dans votre sélection.";
      return;
    }
    brouillon.menu[c.cle] = images;
    etat.textContent = `${images.length} page${images.length > 1 ? "s" : ""} prête${images.length > 1 ? "s" : ""}.`;
    rendreMenu(langue);
    majPoids();
  }

  function rendreMenu(langue) {
    const l = langue || "fr";
    const box = document.getElementById(CARTES[l].pages);
    if (!box) return;
    const imgs = pagesDe(l);

    // Le retour en arrière n'a de sens que si une carte a été importée :
    // sinon c'est déjà celle de l'application qui s'affiche.
    const bouton = document.getElementById(CARTES[l].reset);
    if (bouton) bouton.hidden = !imgs.some(estImportee);
    if (!imgs.length) {
      box.innerHTML =
        l === "en"
          ? '<p class="edit__note">Aucune carte anglaise. Les clients dont le' +
            ' téléphone est en anglais verront la carte française.</p>'
          : "";
      return;
    }
    box.innerHTML = imgs
      .map(
        (src, i) => `
      <figure class="page-vignette">
        <img src="${src}" alt="Page ${i + 1}">
        <span class="page-vignette__num">${i + 1}</span>
        <span class="page-vignette__outils">
          <button type="button" data-move="-1" data-i="${i}" ${i === 0 ? "disabled" : ""} aria-label="Monter">↑</button>
          <button type="button" data-move="1" data-i="${i}" ${i === imgs.length - 1 ? "disabled" : ""} aria-label="Descendre">↓</button>
          <button type="button" data-del="${i}" aria-label="Supprimer">✕</button>
          <span hidden data-langue="${l}"></span>
        </span>
      </figure>`
      )
      .join("");
  }

  /* ---------------------------------------------------- liens */
  function rendreLiens() {
    const box = document.getElementById("liens");
    box.innerHTML = brouillon.review.publicLinks
      .map(
        (l, i) => `
      <div class="lien" data-i="${i}">
        <div class="lien__haut">
          <input type="text" data-champ="label" value="${(l.label || "").replace(/"/g, "&quot;")}" placeholder="Nom (Google, Tripadvisor…)">
          <button class="lien__sup" type="button" data-sup="${i}">Retirer</button>
        </div>
        <input type="text" data-champ="url" value="${(l.url || "").replace(/"/g, "&quot;")}" placeholder="https://…">
        <input type="text" data-champ="hint" value="${(l.hint || "").replace(/"/g, "&quot;")}" placeholder="Petite phrase sous le nom (facultatif)">
      </div>`
      )
      .join("");
  }

  /* ------------------------------------------------ formulaire */
  function remplirFormulaire() {
    const r = brouillon.restaurant;
    document.getElementById("fName").value = r.name || "";
    document.getElementById("fTagline").value = r.tagline || "";
    document.getElementById("fHours").value = r.hours || "";
    document.getElementById("fAddress").value = r.address || "";
    document.getElementById("fPhone").value = r.phone || "";
    document.getElementById("fHotel").value = (r.hotel && r.hotel.name) || "";
    document.getElementById("fHotelUrl").value = (r.hotel && r.hotel.url) || "";
    document.getElementById("logoApercu").style.backgroundImage =
      r.logoUrl ? `url("${r.logoUrl}")` : "none";
    document.getElementById("fSeuil").value = String(brouillon.review.threshold);
    document.getElementById("fDelais").value = brouillon.reminder.delays.join(", ");
    document.getElementById("fDelaiDefaut").value = String(brouillon.reminder.defaultDelay);
    rendreLiens();
    rendreMenu("fr");
    rendreMenu("en");
    majPoids();
    majPublication();
    document.getElementById("apercuStop").hidden = !window.Contenu.local();
  }

  function lireFormulaire() {
    const r = brouillon.restaurant;
    r.hotel = {
      name: document.getElementById("fHotel").value.trim(),
      url: document.getElementById("fHotelUrl").value.trim()
    };
    r.name = document.getElementById("fName").value.trim();
    r.tagline = document.getElementById("fTagline").value.trim();
    r.hours = document.getElementById("fHours").value.trim();
    r.address = document.getElementById("fAddress").value.trim();
    r.phone = document.getElementById("fPhone").value.trim();

    brouillon.review.threshold = Number(document.getElementById("fSeuil").value);

    document.querySelectorAll("#liens .lien").forEach((n) => {
      const l = brouillon.review.publicLinks[Number(n.dataset.i)];
      n.querySelectorAll("[data-champ]").forEach((inp) => {
        l[inp.dataset.champ] = inp.value.trim();
      });
    });
    brouillon.review.publicLinks = brouillon.review.publicLinks.filter((l) => l.label && l.url);

    const delais = document.getElementById("fDelais").value
      .split(",")
      .map((x) => parseInt(x, 10))
      .filter((x) => x > 0);
    if (delais.length) brouillon.reminder.delays = delais;
    const parDefaut = parseInt(document.getElementById("fDelaiDefaut").value, 10);
    brouillon.reminder.defaultDelay = brouillon.reminder.delays.includes(parDefaut)
      ? parDefaut
      : brouillon.reminder.delays[0];
  }

  async function appliquerMotDePasse() {
    const champ = document.getElementById("fMdp");
    const mdp = champ.value.trim();
    if (!mdp) return false;
    brouillon.admin.passwordSha256 = await sha256(mdp);
    champ.value = "";
    return true;
  }

  const surServeur = () => Boolean(window.Serveur && Serveur.actif());

  /** Rappelle quand la carte a été publiée pour la dernière fois. */
  function majPublication(date) {
    const el = document.getElementById("publication");
    if (!el) return;
    if (!surServeur()) {
      el.textContent =
        "Aucun serveur configuré : le bouton produit un fichier à déposer vous-même.";
      return;
    }
    // La date de publication voyage avec le contenu lui-même : inutile de
    // la redemander au serveur.
    const distant = window.Contenu.distant();
    const d = date || derniereMaj || (distant && distant.majLe);
    el.textContent = d
      ? "Dernière publication : " +
        new Date(d).toLocaleString("fr-FR", { dateStyle: "long", timeStyle: "short" })
      : "Jamais publié depuis ce panneau.";
    if (d) derniereMaj = d;
  }

  let derniereMaj = null;

  function majPoids() {
    const octets = new Blob([window.Contenu.fichier(brouillon)]).size;
    const mo = octets / 1048576;
    const taille = mo >= 1 ? `${mo.toFixed(2)} Mo` : `${Math.max(1, Math.round(octets / 1024))} Ko`;
    const el = document.getElementById("poids");

    // Une carte laissée sur les fichiers d'origine ne pèse rien : ce sont de
    // simples chemins. Le poids ne monte qu'après un import de pages.
    const importee = (brouillon.menu.images[0] || "").startsWith("data:");
    el.textContent =
      (surServeur() ? "À publier : " : "Fichier à déposer : ") +
      taille +
      (importee ? "" : " (la carte reste celle déjà en ligne).");

    if (mo > 4) {
      el.textContent +=
        surServeur()
          ? " C'est lourd : chaque client le téléchargera à l'ouverture. Réduisez" +
            " le nombre de pages, ou repartez d'un PDF plus léger."
          : " C'est lourd pour un téléphone en 4G — réduisez le nombre de pages" +
            " ou repartez d'un PDF plus léger.";
    }
  }

  /* ------------------------------------------------- actions */
  function telecharger(nom, contenu, type) {
    const blob = new Blob([contenu], { type: type });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = nom;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1500);
  }

  function bindEditeur() {
    document.getElementById("tabs").addEventListener("click", (e) => {
      const t = e.target.closest(".tab");
      if (!t) return;
      document.querySelectorAll(".tab").forEach((x) => x.classList.toggle("is-on", x === t));
      document.getElementById("tabAvis").hidden = t.dataset.tab !== "avis";
      document.getElementById("tabReglages").hidden = t.dataset.tab !== "reglages";
      document.getElementById("tabEnglish").hidden = t.dataset.tab !== "english";
      // Les deux onglets d'édition travaillent sur le même brouillon :
      // il ne doit être monté qu'une fois, sans quoi une saisie en cours
      // dans l'un serait effacée en passant dans l'autre.
      if (t.dataset.tab !== "avis" && !brouillon) {
        initBrouillon();
        remplirFormulaire();
      }
    });

    // les deux cartes, française et anglaise
    [
      { langue: "fr", drop: "menuDrop", input: "menuFiles", pages: "menuPages" },
      { langue: "en", drop: "menuDropEn", input: "menuFilesEn", pages: "menuPagesEn" }
    ].forEach(({ langue, drop: idDrop, input, pages }) => {
      const drop = document.getElementById(idDrop);
      const champ = document.getElementById(input);
      const boite = document.getElementById(pages);
      if (!drop || !champ || !boite) return;

      champ.addEventListener("change", (e) => {
        ajouterFichiers(e.target.files, langue);
        e.target.value = "";
      });
      ["dragover", "dragleave", "drop"].forEach((ev) =>
        drop.addEventListener(ev, (e) => {
          e.preventDefault();
          drop.classList.toggle("is-over", ev === "dragover");
          if (ev === "drop") ajouterFichiers(e.dataTransfer.files, langue);
        })
      );

      const reset = document.getElementById(CARTES[langue].reset);
      if (reset) {
        reset.addEventListener("click", () => {
          // Vider la liste suffit : une liste sans image importée n'est pas
          // publiée, et l'application reprend ses propres pages.
          brouillon.menu[CARTES[langue].cle] = [];
          document.getElementById(CARTES[langue].etat).textContent =
            "Carte de l'application rétablie. Publiez pour que les clients la voient.";
          rendreMenu(langue);
          majPoids();
        });
      }

      boite.addEventListener("click", (e) => {
        const b = e.target.closest("button");
        if (!b) return;
        const imgs = pagesDe(langue);
        if (b.dataset.del !== undefined) {
          imgs.splice(Number(b.dataset.del), 1);
        } else if (b.dataset.move) {
          const i = Number(b.dataset.i);
          const j = i + Number(b.dataset.move);
          if (j < 0 || j >= imgs.length) return;
          [imgs[i], imgs[j]] = [imgs[j], imgs[i]];
        }
        rendreMenu(langue);
        majPoids();
      });
    });

    // logo
    document.getElementById("fLogo").addEventListener("change", async (e) => {
      if (!e.target.files[0]) return;
      brouillon.restaurant.logoUrl = await compresser(e.target.files[0], 256, 0.9);
      document.getElementById("logoApercu").style.backgroundImage =
        `url("${brouillon.restaurant.logoUrl}")`;
      majPoids();
    });
    document.getElementById("logoReset").addEventListener("click", () => {
      brouillon.restaurant.logoUrl = "";
      document.getElementById("logoApercu").style.backgroundImage = "none";
    });

    // liens
    document.getElementById("lienAdd").addEventListener("click", () => {
      lireFormulaire();
      brouillon.review.publicLinks.push({ id: "p" + Date.now(), label: "", url: "", hint: "", color: "#4285F4" });
      rendreLiens();
    });
    document.getElementById("liens").addEventListener("click", (e) => {
      const b = e.target.closest("[data-sup]");
      if (!b) return;
      const i = Number(b.dataset.sup);
      lireFormulaire();
      brouillon.review.publicLinks.splice(i, 1);
      rendreLiens();
    });

    // aperçu / publication
    document.getElementById("apercuBtn").addEventListener("click", async () => {
      lireFormulaire();
      const change = await appliquerMotDePasse();
      window.Contenu.enregistrerLocal(brouillon);
      document.getElementById("apercuStop").hidden = false;
      toast(
        change
          ? "Aperçu actif sur cet appareil. Nouveau mot de passe pris en compte."
          : "Aperçu actif sur cet appareil. Ouvrez la carte pour le voir."
      );
      majPoids();
    });

    document.getElementById("apercuStop").addEventListener("click", () => {
      window.Contenu.supprimerLocal();
      // L'aperçu anglais a pu forcer la langue : on rend la main au
      // téléphone, sinon le gérant resterait bloqué en anglais.
      if (window.I18n) I18n.oublier();
      document.getElementById("apercuStop").hidden = true;
      toast("Aperçu annulé. Rechargez la carte pour revoir la version publiée.");
    });

    // L'aperçu anglais force la langue avant d'ouvrir la carte, sinon le
    // gérant — sur un téléphone français — verrait la version française.
    document.getElementById("apercuBtnEn").addEventListener("click", async () => {
      lireFormulaire();
      await appliquerMotDePasse();
      window.Contenu.enregistrerLocal(brouillon);
      if (window.I18n) I18n.apercu("en");
      document.getElementById("apercuStop").hidden = false;
      toast("Aperçu anglais actif. Ouvrez la carte pour le voir.");
      majPoids();
    });

    let publication = false;
    async function publier(idBouton) {
      if (publication) return;
      publication = true;
      const btn = document.getElementById(idBouton);
      const etiquette = btn.textContent;

      lireFormulaire();
      await appliquerMotDePasse();

      // Le serveur refuse au-delà de 6 Mo, et il a raison : chaque client
      // télécharge cette carte. Mieux vaut le dire ici, en clair, que de
      // laisser remonter un message de base de données.
      const octets = new Blob([window.Contenu.fichier(brouillon)]).size;
      if (octets > 5_500_000) {
        publication = false;
        toast(
          "Trop lourd pour être publié (" + (octets / 1048576).toFixed(1) +
            " Mo, maximum 5,5). Retirez des pages, ou confiez-moi le PDF : " +
            "je le convertis en pages dix fois plus légères."
        );
        return;
      }

      if (window.Serveur && Serveur.actif() && Serveur.session()) {
        btn.classList.add("is-loading");
        btn.textContent = "Publication…";
        try {
          await Serveur.publierContenu(window.Contenu.pourPublication(brouillon));
          // L'aperçu local ferait écran à ce qu'on vient de publier :
          // il n'a plus de raison d'être.
          window.Contenu.supprimerLocal();
          document.getElementById("apercuStop").hidden = true;
          majPublication(new Date());
          toast("Publié. Les clients verront les changements à leur prochaine ouverture.");
        } catch (e) {
          const raison =
            e.statut === undefined
              ? "serveur injoignable"
              : e.statut === 404
                ? "la table « contenu » n'existe pas encore sur le projet"
                : e.message || "erreur " + e.statut;
          toast("Publication impossible : " + raison + ".");
        } finally {
          btn.classList.remove("is-loading");
          btn.textContent = etiquette;
          publication = false;
        }
        majPoids();
        return;
      }

      telecharger("contenu.json", window.Contenu.fichier(brouillon), "application/json");
      majPoids();
      publication = false;
      toast("Déposez ce fichier dans le dossier assets/ de votre site.");
    }

    // Les deux boutons publient le même enregistrement : les cartes
    // française et anglaise voyagent ensemble.
    document.getElementById("publierBtn")
      .addEventListener("click", () => publier("publierBtn"));
    document.getElementById("publierBtnEn")
      .addEventListener("click", () => publier("publierBtnEn"));
  }

  /* ------------------------------------------------------- export */
  function download(name, content, type) {
    const blob = new Blob([content], { type });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  function exportData() {
    const stamp = new Date().toISOString().slice(0, 10);
    const rows = [["date", "note", "canal", "plateforme", "table", "contact", "commentaire", "photo"]];

    reviews.forEach((r) => {
      rows.push([
        new Date(r.createdAt).toISOString(),
        r.rating,
        r.channel,
        r.platform || "",
        r.table || "",
        r.contact || "",
        (r.comment || "").replace(/\s+/g, " "),
        r.photo ? "oui" : "non"
      ]);
    });

    const csv = rows
      .map((row) => row.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(";"))
      .join("\r\n");

    // BOM : Excel ouvre correctement les accents
    download(`avis-${stamp}.csv`, "﻿" + csv, "text/csv;charset=utf-8");
    // Le JSON conserve les photos, contrairement au CSV
    download(`avis-${stamp}.json`, JSON.stringify(reviews, null, 2), "application/json");
    toast("Export CSV + JSON téléchargé.");
  }

  /* ------------------------------------------------------ liaisons */
  function bind() {
    const form = document.getElementById("loginForm");
    // Comme pour le formulaire d'avis : certains contextes embarqués
    // n'émettent jamais l'événement `submit`.
    form.addEventListener("submit", login);
    form.querySelector('button[type="submit"]').addEventListener("click", login);

    document.getElementById("logoutBtn").addEventListener("click", () => {
      sessionStorage.removeItem(SESSION_KEY);
      if (window.Serveur && Serveur.actif()) Serveur.deconnexion();
      location.reload();
    });

    document.getElementById("exportBtn").addEventListener("click", exportData);

    document.getElementById("filters").addEventListener("click", (e) => {
      const chip = e.target.closest(".chip");
      if (!chip) return;
      filter = chip.dataset.filter;
      document.querySelectorAll(".chip").forEach((c) => c.classList.toggle("is-on", c === chip));
      renderList();
    });

    document.getElementById("list").addEventListener("click", async (e) => {
      const card = e.target.closest(".card");
      if (!card) return;
      const id = card.dataset.id;

      if (e.target.dataset.photo) {
        document.getElementById("lightboxImg").src = e.target.src;
        document.getElementById("lightbox").hidden = false;
        return;
      }

      const act = e.target.dataset.act;
      const courant = reviews.find((r) => r.id === id);
      if (act === "read") {
        if (courant && courant.distant) await Serveur.majAvis(id, { read: !courant.read });
        else await window.ReviewStore.update(id, { read: !courant.read });
        await refresh();
      }
      if (act === "del") {
        if (!confirm("Supprimer définitivement cet avis ?")) return;
        if (courant && courant.distant) await Serveur.supprimerAvis(id);
        else await window.ReviewStore.remove(id);
        await refresh();
        toast("Avis supprimé.");
      }
    });

    document.getElementById("clearBtn").addEventListener("click", async () => {
      if (!confirm("Effacer TOUS les avis de ce navigateur ? Cette action est irréversible.")) return;
      if (!confirm("Dernière confirmation : tout supprimer ?")) return;
      await window.ReviewStore.clear();
      await refresh();
      toast("Tous les avis ont été supprimés.");
    });

    const lb = document.getElementById("lightbox");
    document.getElementById("lightboxClose").addEventListener("click", () => (lb.hidden = true));
    lb.addEventListener("click", (e) => {
      if (e.target === lb) lb.hidden = true;
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") lb.hidden = true;
    });
  }

  bind();
  bindEditeur();

  // Les surcouches (carte, liens, mot de passe) avant toute vérification :
  // un mot de passe changé depuis `contenu.json` doit être celui qui compte.
  window.Contenu.appliquer().then(() => {
    if (window.Serveur && Serveur.actif()) {
      document.getElementById("champEmail").hidden = false;
      document.getElementById("loginIntro").textContent =
        "Accès réservé. Connectez-vous avec le compte du restaurant.";
    }
    if (sessionValid()) showDashboard();
    else document.getElementById("password").focus();
  });
})();
