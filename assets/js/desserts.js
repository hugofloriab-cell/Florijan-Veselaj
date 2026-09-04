/* ------------------------------------------------------------------
 * Le moment dessert
 * ------------------------------------------------------------------
 * Un temps après l'ouverture de la carte — quand le plat est fini —
 * l'application propose les desserts et ouvre la page correspondante.
 *
 * Même mécanique que le rappel « avis » : l'échéance est écrite dans
 * `localStorage` et revérifiée au retour sur l'onglet, plutôt que de se
 * fier au seul `setTimeout` que les navigateurs brident en arrière-plan.
 *
 * Limite assumée : une page fermée n'exécute plus rien. Si le client a
 * quitté l'onglet, la proposition l'attend à son retour ; elle ne peut
 * pas le rattraper. Seul un vrai serveur de notifications le pourrait.
 * ------------------------------------------------------------------ */

window.Desserts = (function () {
  const KEY = "resto-desserts";

  let timer = null;
  let onFire = null;

  const conf = () => {
    const c = (window.APP_CONFIG && window.APP_CONFIG.desserts) || {};
    // `en` ne porte que les textes : le délai, la page et les photos
    // valent pour les deux langues.
    return window.I18n && I18n.estAnglais() && c.en ? Object.assign({}, c, c.en) : c;
  };
  const actif = () => Number(conf().delay) > 0;

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

  function fire() {
    const state = read();
    if (!state || state.fired) return;
    if (timer) clearTimeout(timer);
    timer = null;

    state.fired = true;
    write(state);

    // Onglet au premier plan : la proposition s'affiche directement, une
    // notification par-dessus ne ferait que doubler le message.
    if (document.visibilityState === "visible") {
      if (onFire) onFire();
      return;
    }

    const c = conf();
    const nom = (window.APP_CONFIG && APP_CONFIG.restaurant.name) || "Votre restaurant";
    if (window.Reminder && Reminder.notifier) {
      Reminder.notifier(c.notifTitle || nom, c.notifBody || "", {
        tag: "desserts",
        url: location.pathname + "?desserts=1"
      });
    }
    // La feuille s'ouvrira au retour, que la notification soit passée ou non.
    document.addEventListener("visibilitychange", function once() {
      if (document.visibilityState !== "visible") return;
      document.removeEventListener("visibilitychange", once);
      if (onFire) onFire();
    });
  }

  function arm() {
    if (timer) clearTimeout(timer);
    timer = null;

    const state = read();
    if (!state || state.fired) return;

    const restant = state.dueAt - Date.now();
    if (restant <= 0) return fire();
    timer = setTimeout(fire, Math.min(restant, 2147483000));
  }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") arm();
  });

  return {
    /** Démarre le compte à rebours à la première ouverture de la carte. */
    init(handlers) {
      onFire = handlers && handlers.onFire;
      if (!actif()) return;

      if (!read()) {
        write({
          debut: Date.now(),
          dueAt: Date.now() + Number(conf().delay) * 60 * 1000,
          fired: false
        });
      }
      arm();
    },

    /** Le client a vu la proposition : on ne la reproposera pas. */
    terminer() {
      if (timer) clearTimeout(timer);
      timer = null;
      const state = read() || {};
      state.fired = true;
      state.vue = true;
      write(state);
    },

    /** Remet le compteur à zéro — utile pour un essai depuis le panneau. */
    reinitialiser() {
      write(null);
      this.init({ onFire: onFire });
    },

    etat: read,

    /** Millisecondes restantes, 0 si l'échéance est passée ou inactive. */
    restant() {
      const s = read();
      return s && !s.fired ? Math.max(0, s.dueAt - Date.now()) : 0;
    }
  };
})();
