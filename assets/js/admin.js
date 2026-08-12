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
  async function refresh() {
    reviews = await window.ReviewStore.all();
    renderStats();
    renderList();
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
      if (act === "read") {
        const current = reviews.find((r) => r.id === id);
        await window.ReviewStore.update(id, { read: !current.read });
        await refresh();
      }
      if (act === "del") {
        if (!confirm("Supprimer définitivement cet avis ?")) return;
        await window.ReviewStore.remove(id);
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
  if (sessionValid()) showDashboard();
  else document.getElementById("password").focus();
})();
