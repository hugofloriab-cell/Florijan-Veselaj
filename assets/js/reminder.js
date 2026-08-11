/* ------------------------------------------------------------------
 * Rappel « laisser un avis »
 * ------------------------------------------------------------------
 * Le rappel survit au rechargement de la page et à la mise en veille :
 * on stocke l'échéance (timestamp) et on la revérifie à chaque retour
 * sur l'onglet, plutôt que de se fier au seul setTimeout.
 *
 * Deux canaux de déclenchement :
 *   1. Notification Web locale (si l'utilisateur l'a acceptée)
 *   2. Minuteur visuel dans l'application (toujours actif, sans permission)
 * ------------------------------------------------------------------ */

window.Reminder = (function () {
  const KEY = "resto-rappel";
  const SNOOZE_KEY = "resto-rappel-report";

  let timer = null;
  let tick = null;
  let onFire = null;
  let onTick = null;

  function read() {
    try {
      return JSON.parse(localStorage.getItem(KEY) || "null");
    } catch (_) {
      return null;
    }
  }

  function write(state) {
    if (state) localStorage.setItem(KEY, JSON.stringify(state));
    else localStorage.removeItem(KEY);
  }

  function clearTimers() {
    if (timer) clearTimeout(timer);
    if (tick) clearInterval(tick);
    timer = tick = null;
  }

  async function notify(state) {
    if (!("Notification" in window) || Notification.permission !== "granted") return false;

    const name = (window.APP_CONFIG && APP_CONFIG.restaurant.name) || "Votre restaurant";
    const payload = {
      body: "Avez-vous une minute pour nous dire comment s'est passé votre repas ?",
      icon: "assets/img/icon-192.png",
      badge: "assets/img/icon-192.png",
      tag: "avis-rappel",
      renotify: true,
      requireInteraction: true,
      data: { url: location.pathname + "?avis=1" },
      vibrate: [90, 60, 90]
    };

    try {
      if ("serviceWorker" in navigator) {
        const reg = await navigator.serviceWorker.getRegistration();
        if (reg) {
          // Passe par le Service Worker : la notification reste visible même
          // si l'onglet est fermé, et le clic rouvre l'application.
          await reg.showNotification(name, payload);
          return true;
        }
      }
      new Notification(name, payload);
      return true;
    } catch (err) {
      console.warn("[Rappel] notification impossible :", err);
      return false;
    }
  }

  function fire() {
    const state = read();
    if (!state || state.fired) return;
    clearTimers();
    state.fired = true;
    state.firedAt = Date.now();
    write(state);

    if (document.visibilityState !== "visible") notify(state);
    if (onFire) onFire(state);
    if (onTick) onTick(null);
  }

  function arm() {
    clearTimers();
    const state = read();
    if (!state || state.fired) {
      if (onTick) onTick(null);
      return;
    }

    const remaining = state.dueAt - Date.now();
    if (remaining <= 0) return fire();

    // setTimeout est bridé en arrière-plan : on le complète par un
    // contrôle périodique et un contrôle au retour sur l'onglet.
    timer = setTimeout(fire, Math.min(remaining, 2147483000));
    tick = setInterval(() => {
      const s = read();
      if (!s || s.fired) return clearTimers();
      if (s.dueAt - Date.now() <= 0) return fire();
      if (onTick) onTick(s);
    }, 1000);

    if (onTick) onTick(state);
  }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") arm();
  });

  return {
    init(handlers) {
      onFire = handlers.onFire;
      onTick = handlers.onTick;
      arm();
    },

    /** Demande la permission de notifier. Ne bloque jamais le rappel. */
    async requestPermission() {
      if (!("Notification" in window)) return "unsupported";
      if (Notification.permission !== "default") return Notification.permission;
      try {
        return await Notification.requestPermission();
      } catch (_) {
        return "denied";
      }
    },

    /** Programme le rappel dans `minutes` minutes. */
    schedule(minutes) {
      const state = {
        delay: minutes,
        createdAt: Date.now(),
        dueAt: Date.now() + minutes * 60 * 1000,
        fired: false
      };
      write(state);
      arm();
      return state;
    },

    cancel() {
      clearTimers();
      write(null);
      if (onTick) onTick(null);
    },

    /** Marque le rappel comme traité (avis envoyé ou refusé). */
    complete() {
      clearTimers();
      write(null);
      if (onTick) onTick(null);
    },

    state: read,

    remaining() {
      const s = read();
      return s && !s.fired ? Math.max(0, s.dueAt - Date.now()) : 0;
    },

    /* --- Report de la pop-up d'accueil ---------------------------- */
    snooze(hours) {
      localStorage.setItem(SNOOZE_KEY, String(Date.now() + hours * 3600 * 1000));
    },

    isSnoozed() {
      const until = Number(localStorage.getItem(SNOOZE_KEY) || 0);
      return Date.now() < until;
    },

    formatRemaining(ms) {
      const total = Math.ceil(ms / 1000);
      const m = Math.floor(total / 60);
      const s = total % 60;
      return `${m}:${String(s).padStart(2, "0")}`;
    }
  };
})();
