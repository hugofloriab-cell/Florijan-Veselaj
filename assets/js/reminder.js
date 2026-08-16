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

  /**
   * Service Worker actif, ou null.
   * `getRegistration()` peut répondre avant la fin de l'activation ; `ready`
   * attend l'activation, mais ne se résout jamais si l'enregistrement a
   * échoué — d'où la course avec un délai.
   */
  async function swPret(delai) {
    if (!("serviceWorker" in navigator)) return null;
    try {
      return await Promise.race([
        navigator.serviceWorker.ready,
        new Promise((r) => setTimeout(() => r(null), delai || 3000))
      ]);
    } catch (_) {
      return null;
    }
  }

  function contenu(titre, corps) {
    return [
      titre,
      {
        body: corps,
        icon: "assets/img/icon-192.png",
        badge: "assets/img/icon-192.png",
        tag: "avis-rappel", // même tag : la 2e notification remplace la 1re
        renotify: true,
        requireInteraction: true,
        data: { url: location.pathname + "?avis=1" },
        vibrate: [90, 60, 90]
      }
    ];
  }

  async function envoyer(titre, corps) {
    if (!("Notification" in window) || Notification.permission !== "granted") return false;
    const [t, payload] = contenu(titre, corps);

    // 1,5 s suffit : le Service Worker est enregistré au chargement de la
    // page, donc déjà actif quand le client choisit son délai.
    const reg = await swPret(1500);
    if (reg && reg.showNotification) {
      // Chrome Android n'accepte QUE cette voie : le constructeur Notification
      // y lève une exception (« Illegal constructor »).
      try {
        await reg.showNotification(t, payload);
        return true;
      } catch (err) {
        console.warn("[Rappel] showNotification a échoué :", err);
      }
    }

    try {
      new Notification(t, payload);
      return true;
    } catch (err) {
      console.warn("[Rappel] notification impossible :", err);
      return false;
    }
  }

  function notify() {
    const nom = (window.APP_CONFIG && APP_CONFIG.restaurant.name) || "Votre restaurant";
    return envoyer(nom, "Avez-vous une minute pour nous dire comment s'est passé votre repas ?");
  }

  function fire() {
    const state = read();
    if (!state || state.fired) return;
    clearTimers();
    state.fired = true;
    state.firedAt = Date.now();
    write(state);

    if (document.visibilityState !== "visible") notify();
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

    /**
     * Programme le rappel dans `minutes` minutes.
     * Résout avec `{ state, notifiable }` : `notifiable` dit si une
     * notification a réellement pu être postée, pour que l'interface
     * n'annonce pas ce qui n'arrivera pas.
     */
    async schedule(minutes) {
      const state = {
        delay: minutes,
        createdAt: Date.now(),
        dueAt: Date.now() + minutes * 60 * 1000,
        fired: false
      };
      write(state);
      arm();

      // Notification de confirmation, postée tout de suite.
      // C'est la seule présence dans le volet de notifications dont on soit
      // sûr : une fois l'onglet fermé, plus aucun script ne tourne et le
      // rappel différé ne peut plus être émis sans serveur (voir README).
      // Même `tag` : la notification de rappel viendra la remplacer.
      const cfg = window.APP_CONFIG && APP_CONFIG.reminder;
      let notifiable = false;
      if (!cfg || cfg.confirmNotification !== false) {
        const heure = new Date(state.dueAt).toLocaleTimeString("fr-FR", {
          hour: "2-digit",
          minute: "2-digit"
        });
        const nom = (window.APP_CONFIG && APP_CONFIG.restaurant.name) || "Votre restaurant";
        notifiable = await envoyer(nom, `Rappel prévu vers ${heure}. Touchez pour laisser votre avis.`);
      } else {
        const d = await this.diagnostic();
        notifiable = d.permission === "granted";
      }
      return { state, notifiable };
    },

    /** État réel des notifications, pour informer le client sans mentir. */
    async diagnostic() {
      const permission = "Notification" in window ? Notification.permission : "unsupported";
      return { permission, serviceWorker: Boolean(await swPret(1500)) };
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
