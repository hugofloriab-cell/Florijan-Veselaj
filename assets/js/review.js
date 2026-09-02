/* ------------------------------------------------------------------
 * Formulaire d'évaluation + routage des avis
 * ------------------------------------------------------------------
 *   note >= seuil  →  on remercie et on oriente vers Google / Tripadvisor
 *                     / Booking (avis public)
 *   note <  seuil  →  l'avis reste en interne, visible uniquement dans
 *                     le panneau gérant. Rien n'est publié.
 * ------------------------------------------------------------------ */

window.ReviewFlow = (function () {
  const cfg = () => window.APP_CONFIG.review;

  let el = {};
  let state = { rating: 0, photo: null, submitting: false };
  let lastRecord = null;
  let onClose = null;

  const RATING_LABELS = {
    0: "Touchez une étoile pour noter",
    1: "Très décevant",
    2: "Décevant",
    3: "Correct, sans plus",
    4: "Très bon moment",
    5: "Excellent, un vrai plaisir !"
  };

  /* ------------------------------------------------------- photos */
  function compress(file) {
    return new Promise((resolve, reject) => {
      if (!file.type.startsWith("image/")) {
        return reject(new Error("Ce fichier n'est pas une image."));
      }
      const { maxSize, quality } = cfg().photo;
      const url = URL.createObjectURL(file);
      const img = new Image();

      img.onload = () => {
        const ratio = Math.min(1, maxSize / Math.max(img.width, img.height));
        const canvas = document.createElement("canvas");
        canvas.width = Math.round(img.width * ratio);
        canvas.height = Math.round(img.height * ratio);
        const ctx = canvas.getContext("2d");
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        URL.revokeObjectURL(url);
        resolve({
          dataUrl: canvas.toDataURL("image/jpeg", quality),
          width: canvas.width,
          height: canvas.height
        });
      };
      img.onerror = () => {
        URL.revokeObjectURL(url);
        reject(new Error("Image illisible."));
      };
      img.src = url;
    });
  }

  async function handleFile(file) {
    if (!file) return;
    el.photoError.textContent = "";
    el.photoBtns.classList.add("is-busy");
    try {
      const photo = await compress(file);
      state.photo = photo;
      el.photoPreviewImg.src = photo.dataUrl;
      el.photoPreview.hidden = false;
      el.photoBtns.hidden = true;
    } catch (err) {
      el.photoError.textContent = err.message;
    } finally {
      el.photoBtns.classList.remove("is-busy");
    }
  }

  function clearPhoto() {
    state.photo = null;
    el.photoPreview.hidden = true;
    el.photoPreviewImg.removeAttribute("src");
    el.photoBtns.hidden = false;
    el.camera.value = "";
    el.gallery.value = "";
  }

  /* ------------------------------------------------------- étoiles */
  function setRating(n) {
    state.rating = n;
    el.stars.querySelectorAll(".star").forEach((b) => {
      const v = Number(b.dataset.value);
      b.classList.toggle("is-on", v <= n);
      b.setAttribute("aria-checked", String(v === n));
    });
    el.ratingLabel.textContent = RATING_LABELS[n];
    el.submit.disabled = n === 0;
    el.form.dataset.rating = String(n);

    // On annonce clairement ce qui va se passer : pas de piège pour le client.
    if (n === 0) {
      el.routeHint.hidden = true;
    } else if (n >= cfg().threshold) {
      // La liste suit les plateformes réellement configurées.
      const noms = cfg().publicLinks.map((l) => l.label);
      const liste =
        noms.length > 1 ? noms.slice(0, -1).join(", ") + " ou " + noms[noms.length - 1] : noms[0];
      el.routeHint.hidden = false;
      el.routeHint.className = "route-hint route-hint--public";
      el.routeHint.textContent = liste
        ? `Merci ! Nous vous proposerons de partager cet avis sur ${liste}.`
        : "Merci ! Nous vous proposerons de partager cet avis publiquement.";
    } else {
      el.routeHint.hidden = false;
      el.routeHint.className = "route-hint route-hint--private";
      el.routeHint.textContent =
        "Votre message sera transmis directement au gérant, en privé. Il ne sera pas publié.";
    }
  }

  /* -------------------------------------------------------- envoi */
  async function sync(record) {
    const s = window.APP_CONFIG.sync;
    if (!s || !s.endpoint) return;
    try {
      await fetch(s.endpoint, {
        method: "POST",
        headers: Object.assign(
          { "Content-Type": "application/json" },
          s.token ? { Authorization: "Bearer " + s.token } : {}
        ),
        body: JSON.stringify(record)
      });
    } catch (err) {
      console.warn("[Avis] synchronisation impossible, l'avis reste en local :", err);
    }
  }

  async function submit(e) {
    e.preventDefault();
    if (state.submitting || state.rating === 0) return;
    state.submitting = true;
    el.submit.disabled = true;
    el.submit.classList.add("is-loading");

    const isPublic = state.rating >= cfg().threshold;
    const record = {
      rating: state.rating,
      comment: el.comment.value.trim(),
      photo: state.photo ? state.photo.dataUrl : null,
      channel: isPublic ? "public" : "prive",
      platform: null,
      table: el.table.value.trim() || null,
      contact: el.contact.value.trim() || null,
      locale: navigator.language || null
    };

    try {
      // Toujours écrire en local d'abord : si le réseau lâche, l'avis est
      // conservé et repartira tout seul. Rien ne se perd.
      lastRecord = await window.ReviewStore.add(record);
      envoyerAuServeur(lastRecord);
      if (!isPublic) sync(lastRecord); // ancien point d'intégration, optionnel
    } catch (err) {
      console.error("[Avis] enregistrement impossible :", err);
      lastRecord = record;
    }

    window.Reminder.complete();
    // `submitting` reste vrai jusqu'au prochain `reset()` : un second
    // événement tardif ne peut pas enregistrer l'avis en double.
    el.submit.classList.remove("is-loading");
    el.submit.disabled = false;

    showStep(isPublic ? "public" : "prive");
    document.dispatchEvent(new CustomEvent("avis:enregistre", { detail: lastRecord }));
  }

  /** Dépose l'avis sur le serveur, et le marque comme envoyé. */
  async function envoyerAuServeur(avis) {
    if (!window.Serveur || !Serveur.actif() || !avis.id) return false;
    try {
      await Serveur.envoyerAvis(avis);
      await window.ReviewStore.update(avis.id, { envoye: true });
      return true;
    } catch (err) {
      console.warn("[Avis] envoi différé :", err.message);
      return false;
    }
  }

  /** Reprend les avis qu'un incident réseau avait laissés sur place. */
  async function viderFileAttente() {
    if (!window.Serveur || !Serveur.actif()) return 0;
    let partis = 0;
    for (const a of await window.ReviewStore.all()) {
      if (a.envoye) continue;
      if (await envoyerAuServeur(a)) partis++;
    }
    return partis;
  }

  /* --------------------------------------------------------- vues */
  function showStep(name) {
    el.sheet.querySelectorAll("[data-step]").forEach((s) => {
      s.hidden = s.dataset.step !== name;
    });
    el.sheet.scrollTop = 0;

    if (name === "public") {
      const comment = el.comment.value.trim();
      el.copyRow.hidden = !comment;
      el.publicPhotoHint.hidden = !state.photo;
    }
  }

  function buildPublicLinks() {
    el.platforms.innerHTML = "";
    cfg().publicLinks.forEach((link) => {
      const a = document.createElement("a");
      a.className = "platform";
      a.href = link.url;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      a.style.setProperty("--brand", link.color);
      a.innerHTML = `
        <span class="platform__dot"></span>
        <span class="platform__text">
          <strong>${link.label}</strong>
          <small>${link.hint || ""}</small>
        </span>
        <svg class="platform__go" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>
      `;
      a.addEventListener("click", () => {
        if (lastRecord && lastRecord.id) {
          window.ReviewStore.update(lastRecord.id, { platform: link.id, redirectedAt: Date.now() });
        }
      });
      el.platforms.appendChild(a);
    });
  }

  async function copyComment() {
    const text = el.comment.value.trim();
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      el.copyBtn.textContent = "Commentaire copié ✓";
    } catch (_) {
      el.copyBtn.textContent = "Copie impossible — sélectionnez le texte";
    }
    setTimeout(() => (el.copyBtn.textContent = "Copier mon commentaire"), 2600);
  }

  function reset() {
    state = { rating: 0, photo: null, submitting: false };
    el.form.reset();
    clearPhoto();
    setRating(0);
    showStep("form");
  }

  return {
    init(handlers) {
      onClose = handlers && handlers.onClose;
      el = {
        sheet: document.getElementById("reviewSheet"),
        form: document.getElementById("reviewForm"),
        stars: document.getElementById("stars"),
        ratingLabel: document.getElementById("ratingLabel"),
        routeHint: document.getElementById("routeHint"),
        comment: document.getElementById("comment"),
        table: document.getElementById("tableNo"),
        contact: document.getElementById("contact"),
        camera: document.getElementById("photoCamera"),
        gallery: document.getElementById("photoGallery"),
        photoBtns: document.getElementById("photoButtons"),
        photoPreview: document.getElementById("photoPreview"),
        photoPreviewImg: document.getElementById("photoPreviewImg"),
        photoError: document.getElementById("photoError"),
        submit: document.getElementById("reviewSubmit"),
        platforms: document.getElementById("platforms"),
        copyRow: document.getElementById("copyRow"),
        copyBtn: document.getElementById("copyBtn"),
        publicPhotoHint: document.getElementById("publicPhotoHint")
      };

      // Étoiles
      el.stars.querySelectorAll(".star").forEach((btn) => {
        btn.addEventListener("click", () => setRating(Number(btn.dataset.value)));
      });
      el.stars.addEventListener("keydown", (e) => {
        if (e.key === "ArrowRight" || e.key === "ArrowUp") {
          setRating(Math.min(5, state.rating + 1));
          e.preventDefault();
        }
        if (e.key === "ArrowLeft" || e.key === "ArrowDown") {
          setRating(Math.max(1, state.rating - 1));
          e.preventDefault();
        }
      });

      // Photo
      el.camera.addEventListener("change", (e) => handleFile(e.target.files[0]));
      el.gallery.addEventListener("change", (e) => handleFile(e.target.files[0]));
      document.getElementById("photoRemove").addEventListener("click", clearPhoto);

      // Le clic double l'événement `submit` : certains contextes restreints
      // (application embarquée dans une iframe, webview) ne l'émettent jamais.
      // Le drapeau `submitting` empêche le double envoi quand les deux passent.
      el.form.addEventListener("submit", submit);
      el.submit.addEventListener("click", submit);
      el.copyBtn.addEventListener("click", copyComment);

      buildPublicLinks();
      setRating(0);
    },

    open(prefill) {
      reset();
      if (prefill && prefill.rating) setRating(prefill.rating);
      window.UI.openSheet("reviewSheet");
      setTimeout(() => {
        const first = el.stars.querySelector(".star");
        if (first) first.focus({ preventScroll: true });
      }, 260);
    },

    close() {
      window.UI.closeSheet("reviewSheet");
      if (onClose) onClose();
    },

    reset,
    viderFileAttente
  };
})();
