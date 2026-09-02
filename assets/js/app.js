/* ------------------------------------------------------------------
 * Application — assemblage des briques
 * ------------------------------------------------------------------ */

(function () {
  "use strict";

  const cfg = window.APP_CONFIG;
  let flipbook = null;
  let openSheets = [];

  /* ============================ UI ============================== */
  const UI = {
    overlay: null,

    openSheet(id) {
      const node = document.getElementById(id);
      if (!node || openSheets.includes(id)) return;
      openSheets.push(id);
      node.hidden = false;
      this.overlay.hidden = false;
      document.body.classList.add("is-locked");
      requestAnimationFrame(() => {
        node.classList.add("is-open");
        this.overlay.classList.add("is-visible");
      });
    },

    closeSheet(id) {
      const node = document.getElementById(id);
      if (!node) return;
      openSheets = openSheets.filter((s) => s !== id);
      node.classList.remove("is-open");
      if (!openSheets.length) {
        this.overlay.classList.remove("is-visible");
        document.body.classList.remove("is-locked");
      }
      setTimeout(() => {
        if (!node.classList.contains("is-open")) node.hidden = true;
        if (!openSheets.length) this.overlay.hidden = true;
      }, 320);
    },

    closeTop() {
      if (openSheets.length) this.closeSheet(openSheets[openSheets.length - 1]);
    },

    toast(message, ms) {
      const t = document.getElementById("toast");
      t.textContent = message;
      t.hidden = false;
      requestAnimationFrame(() => t.classList.add("is-visible"));
      clearTimeout(t._timer);
      t._timer = setTimeout(() => {
        t.classList.remove("is-visible");
        setTimeout(() => (t.hidden = true), 300);
      }, ms || 3200);
    }
  };
  window.UI = UI;

  /* ====================== Identité visuelle ===================== */
  function applyBranding() {
    const r = cfg.restaurant;
    document.title = `Menu · ${r.name}`;
    document.getElementById("brandName").textContent = r.name;
    document.getElementById("brandTagline").textContent = r.tagline || "";

    const mark = document.getElementById("brandMark");
    if (r.logoUrl) {
      mark.innerHTML = `<img src="${r.logoUrl}" alt="${r.name}">`;
      mark.classList.add("brand__mark--img");
    } else {
      mark.textContent = r.monogram || r.name.slice(0, 2).toUpperCase();
    }

    const list = document.getElementById("infoList");
    const rows = [];
    if (r.hours) rows.push(["Service", r.hours, null]);
    if (r.address) rows.push(["Adresse", r.address, "https://maps.google.com/?q=" + encodeURIComponent(r.address)]);
    if (r.phone) rows.push(["Téléphone", r.phone, "tel:" + r.phone.replace(/\s/g, "")]);
    if (r.wifi) rows.push(["Wi-Fi", `${r.wifi.ssid} — mot de passe : ${r.wifi.password}`, null]);
    if (cfg.menu.downloadUrl) rows.push(["Menu", "Télécharger le PDF", cfg.menu.downloadUrl]);

    list.innerHTML = rows
      .map(([label, value, href]) => {
        const body = href
          ? `<a href="${href}" target="_blank" rel="noopener">${value}</a>`
          : `<span>${value}</span>`;
        return `<li><small>${label}</small>${body}</li>`;
      })
      .join("");
  }

  /* ========================= Flipbook =========================== */
  async function initFlipbook() {
    const source =
      cfg.menu.type === "pdf"
        ? { pdfUrl: cfg.menu.pdfUrl, pdfjs: cfg.menu.pdfjs || undefined }
        : { images: cfg.menu.images };

    flipbook = new Flipbook(document.getElementById("flipbook"), Object.assign(source, {
      onPageChange: (i) => {
        if (i > 0) hideHint();
      }
    }));
    await flipbook.load();
  }

  /* ====================== Plein écran =========================== */
  const FS_ENTRER = "M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5";
  const FS_SORTIR = "M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5";

  function initFullscreen() {
    const btn = document.getElementById("fsBtn");
    const el = document.documentElement;
    const demander = el.requestFullscreen || el.webkitRequestFullscreen;
    // Safari iOS n'expose rien sur documentElement : inutile d'afficher un
    // bouton qui ne ferait rien. Là-bas, c'est « Ajouter à l'écran d'accueil ».
    if (!demander) return;

    const actif = () => Boolean(document.fullscreenElement || document.webkitFullscreenElement);
    const entrer = () =>
      Promise.resolve(demander.call(el, { navigationUI: "hide" })).catch(() => {});
    const sortir = () =>
      Promise.resolve((document.exitFullscreen || document.webkitExitFullscreen).call(document))
        .catch(() => {});

    const sync = () => {
      const on = actif();
      document.body.classList.toggle("is-fullscreen", on);
      btn.querySelector("path").setAttribute("d", on ? FS_SORTIR : FS_ENTRER);
      btn.setAttribute("aria-label", on ? "Quitter le plein écran" : "Plein écran");
    };

    btn.hidden = false;
    btn.addEventListener("click", () => (actif() ? sortir() : entrer()));
    document.addEventListener("fullscreenchange", sync);
    document.addEventListener("webkitfullscreenchange", sync);
    sync();

    // Le plein écran exige un geste utilisateur : on saisit le premier
    // contact avec la carte, une fois la pop-up d'accueil écartée.
    if (cfg.ui && cfg.ui.autoFullscreen) {
      document.getElementById("flipbook").addEventListener(
        "pointerup",
        () => {
          if (actif() || openSheets.length) return;
          entrer().then(() => {
            if (actif()) UI.toast("Plein écran. Touchez ⤢ en haut pour en sortir.", 3500);
          });
        },
        { once: true }
      );
    }
  }

  let hintTimer = null;
  function hideHint() {
    const hint = document.getElementById("swipeHint");
    if (!hint || hint.classList.contains("is-gone")) return;
    hint.classList.add("is-gone");
    clearTimeout(hintTimer);
    setTimeout(() => (hint.hidden = true), 400);
  }

  /* ==================== Pop-up de rappel ======================== */
  let chosenDelay = cfg.reminder.defaultDelay;

  function buildDelays() {
    const wrap = document.getElementById("delays");
    const legend = wrap.querySelector("legend");
    wrap.innerHTML = "";
    if (legend) wrap.appendChild(legend);

    cfg.reminder.delays.forEach((min) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "delay";
      btn.dataset.value = String(min);
      btn.setAttribute("aria-pressed", String(min === chosenDelay));
      btn.innerHTML = `<strong>${min}</strong><small>min</small>`;
      if (min === chosenDelay) btn.classList.add("is-on");
      btn.addEventListener("click", () => selectDelay(min));
      wrap.appendChild(btn);
    });
    selectDelay(chosenDelay);
  }

  function selectDelay(min) {
    chosenDelay = min;
    document.querySelectorAll(".delay").forEach((b) => {
      const on = Number(b.dataset.value) === min;
      b.classList.toggle("is-on", on);
      b.setAttribute("aria-pressed", String(on));
    });
    document.getElementById("reminderConfirmDelay").textContent = `${min} min`;
    document.getElementById("reminderConfirm").disabled = false;
  }

  function openReminderModal() {
    UI.openSheet("reminderModal");
    if ("Notification" in window && Notification.permission === "default") {
      document.getElementById("permNote").hidden = false;
    }
  }

  async function confirmReminder() {
    const btn = document.getElementById("reminderConfirm");
    btn.classList.add("is-loading");

    // La permission est demandée au moment du choix : le geste utilisateur
    // est encore « frais », ce que les navigateurs exigent.
    await Reminder.requestPermission();

    // Le rappel est armé tout de suite ; on n'attend pas la notification
    // pour rendre la main, sinon la fenêtre resterait figée le temps que
    // le Service Worker réponde (ou pas).
    const enCours = Reminder.schedule(chosenDelay);
    btn.classList.remove("is-loading");
    UI.closeSheet("reminderModal");

    // Message honnête : sans serveur, le rappel n'est émis que si la page
    // vit encore. Et on n'annonce une notification que si elle a pu partir.
    const { notifiable } = await enCours;
    UI.toast(
      notifiable
        ? `C'est noté. Gardez cette page ouverte : nous vous prévenons dans ${chosenDelay} minutes.`
        : `C'est noté ! Le minuteur reste affiché en bas de l'écran.`,
      5000
    );
  }

  /* ==================== Minuteur visible ======================== */
  function renderCountdown(state) {
    const box = document.getElementById("countdown");
    document.body.classList.toggle("has-countdown", Boolean(state));
    if (!state) {
      box.hidden = true;
      return;
    }
    const total = state.delay * 60 * 1000;
    const left = Math.max(0, state.dueAt - Date.now());
    const done = 1 - left / total;

    box.hidden = false;
    document.getElementById("countdownTime").textContent = Reminder.formatRemaining(left);
    document.getElementById("countdownFill").style.setProperty("--p", (done * 100).toFixed(1) + "%");
  }

  /* ====================== Démarrage ============================= */
  function bindGlobal() {
    UI.overlay = document.getElementById("overlay");

    UI.overlay.addEventListener("click", () => UI.closeTop());
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") UI.closeTop();
    });
    document.querySelectorAll("[data-close-sheet]").forEach((btn) => {
      btn.addEventListener("click", () => UI.closeTop());
    });

    document.getElementById("reviewClose").addEventListener("click", () => UI.closeSheet("reviewSheet"));
    document.getElementById("reviewBtn").addEventListener("click", () => ReviewFlow.open());
    document.getElementById("infoBtn").addEventListener("click", () => UI.openSheet("infoSheet"));

    document.getElementById("reminderConfirm").addEventListener("click", confirmReminder);
    document.getElementById("reminderSkip").addEventListener("click", () => {
      Reminder.snooze(cfg.reminder.snoozeHours);
      UI.closeSheet("reminderModal");
    });
    document.getElementById("reminderNow").addEventListener("click", () => {
      Reminder.snooze(cfg.reminder.snoozeHours);
      UI.closeSheet("reminderModal");
      setTimeout(() => ReviewFlow.open(), 340);
    });

    document.getElementById("countdown").addEventListener("click", (e) => {
      if (e.target.id === "countdownCancel") return;
      Reminder.complete();
      ReviewFlow.open();
    });
    document.getElementById("countdownCancel").addEventListener("click", (e) => {
      e.stopPropagation();
      Reminder.cancel();
      UI.toast("Rappel annulé.");
    });

    // Retour depuis une notification (?avis=1)
    if (new URLSearchParams(location.search).get("avis") === "1") {
      history.replaceState(null, "", location.pathname);
      setTimeout(() => ReviewFlow.open(), 500);
    }

    // Le Service Worker peut demander l'ouverture du formulaire
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.addEventListener("message", (e) => {
        if (e.data && e.data.type === "ouvrir-avis") ReviewFlow.open();
      });
    }
  }

  function registerSw() {
    if (!("serviceWorker" in navigator)) return;
    if (location.protocol === "file:") return; // nécessite http(s)
    navigator.serviceWorker.register("sw.js").catch((err) => {
      console.warn("[SW] non enregistré :", err);
    });
  }

  /** Bandeau d'avertissement quand un aperçu local masque la version publiée. */
  function bandeauApercu() {
    const bar = document.createElement("div");
    bar.className = "preview-bar";
    bar.innerHTML =
      '<span>Aperçu local — les clients voient encore la version publiée.</span>' +
      '<button type="button">Revenir</button>';
    bar.querySelector("button").addEventListener("click", () => {
      Contenu.supprimerLocal();
      location.reload();
    });
    document.body.insertBefore(bar, document.body.firstChild);
  }

  async function start() {
    // Surcouches (carte, liens, identité) avant tout affichage.
    const etat = await Contenu.appliquer();
    if (etat.local) bandeauApercu();

    applyBranding();
    bindGlobal();
    buildDelays();
    ReviewFlow.init();
    initFullscreen();
    registerSw();

    Reminder.init({
      onTick: renderCountdown,
      onFire: () => {
        renderCountdown(null);
        if (document.visibilityState === "visible") {
          ReviewFlow.open();
        } else {
          // Le formulaire s'ouvrira au retour sur l'onglet.
          document.addEventListener("visibilitychange", function once() {
            if (document.visibilityState !== "visible") return;
            document.removeEventListener("visibilitychange", once);
            ReviewFlow.open();
          });
        }
      }
    });

    // Avis restés en local faute de réseau : nouvelle tentative.
    ReviewFlow.viderFileAttente();
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible") ReviewFlow.viderFileAttente();
    });

    await initFlipbook();
    hintTimer = setTimeout(hideHint, 6000);

    // Pop-up d'accueil : uniquement si aucun rappel n'est déjà en cours.
    const pending = Reminder.state();
    if (cfg.reminder.askOnOpen && !pending && !Reminder.isSnoozed()) {
      setTimeout(openReminderModal, 900);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
