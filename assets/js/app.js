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
    const perm = await Reminder.requestPermission();
    Reminder.schedule(chosenDelay);
    btn.classList.remove("is-loading");
    UI.closeSheet("reminderModal");

    UI.toast(
      perm === "granted"
        ? `C'est noté, nous vous notifierons dans ${chosenDelay} minutes.`
        : `C'est noté ! Le minuteur s'affiche en bas de l'écran.`,
      4000
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

  async function start() {
    applyBranding();
    bindGlobal();
    buildDelays();
    ReviewFlow.init();
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
