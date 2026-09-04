/* ------------------------------------------------------------------
 * Flipbook — livret interactif à pages tournantes
 * ------------------------------------------------------------------
 * • Sources acceptées : liste d'images OU fichier PDF (via PDF.js)
 * • Tourne les pages au doigt (le geste suit la page), au clic, au
 *   clavier, ou via la barre de navigation.
 * • Mode simple page (mobile) et mode double page (écran large).
 *
 * Usage :
 *   const fb = new Flipbook(el, { images: [...] });
 *   await fb.load();
 * ------------------------------------------------------------------ */

(function () {
  "use strict";

  // Par défaut PDF.js est chargé depuis un CDN. Pour un restaurant dont la
  // connexion est capricieuse, déposez les deux fichiers sur votre serveur et
  // renseignez `menu.pdfjs` dans config.js.
  const PDFJS_DEFAULT = {
    lib: "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js",
    worker: "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js"
  };

  const clamp = (v, min, max) => Math.min(max, Math.max(min, v));

  // Agrandissement de lecture, par défaut. Une page A4 fait 595 points de
  // large, un téléphone 390 : le texte y perd un tiers de sa taille, et les
  // prix deviennent pénibles à lire. Découper les pages n'y changerait rien
  // — l'échelle ne dépend que de la largeur montrée, jamais de la hauteur.
  // Seul le zoom agit, et `menu.lecture` dit quelle bande de la page il doit
  // cadrer (voir config.js).
  const ZOOM = 2.2;
  const LECTURE = { part: 1 / ZOOM, centre: 0.5 };

  const dit = (cle, secours) =>
    window.I18n && window.I18n.T ? window.I18n.T(cle, secours) : secours;

  class Flipbook {
    constructor(root, options) {
      this.root = root;
      this.opts = Object.assign(
        {
          images: null,
          pdfUrl: null,
          pdfjs: PDFJS_DEFAULT,
          lecture: null, // { part, centre } — voir config.js
          spreadMinWidth: 820, // au-delà : double page
          onPageChange: null,
          onReady: null
        },
        options || {}
      );

      // Cadrage de la lecture agrandie : quelle fraction de la largeur de
      // page montrer, et autour de quel point. Une maquette de carte pose
      // ses prix d'un côté et ses photos de l'autre, et n'en change pas
      // d'une page à l'autre par hasard : le cadrage se règle donc page par
      // page (menu.lecture dans config.js).
      const l = this.opts.lecture || {};
      this.lectureDefaut = this._bande(l.defaut);
      this.lecturePages = Array.isArray(l.pages) ? l.pages.map((b) => this._bande(b)) : [];

      this.pages = []; // URLs des pages
      this.index = 0; // page de gauche (double page) ou page courante
      this.spread = false;
      this.pageRatio = 1.414; // hauteur / largeur d'une page (A4 par défaut)
      this.turning = null; // { dir, progress, committed }
      this.zoom = 1;
      this.pan = { x: 0, y: 0 };
      this.destroyed = false;

      this._buildDom();
      this._bindEvents();
    }

    /** Normalise une bande de lecture, en se gardant d'un réglage aberrant. */
    _bande(b) {
      const src = b && typeof b === "object" ? b : LECTURE;
      return {
        part: clamp(Number(src.part) || LECTURE.part, 0.35, 1),
        centre: clamp(Number(src.centre) || LECTURE.centre, 0, 1)
      };
    }

    /** La bande de la page affichée, ou celle par défaut. */
    _lecture() {
      return this.lecturePages[this.index] || this.lectureDefaut;
    }

    /* ---------------------------------------------------------- DOM */
    _buildDom() {
      this.root.classList.add("fb");
      this.root.innerHTML = `
        <div class="fb-stage" aria-live="polite">
          <div class="fb-book">
            <div class="fb-pane fb-pane--left"><img alt="" draggable="false"></div>
            <div class="fb-pane fb-pane--right"><img alt="" draggable="false"></div>
            <div class="fb-gutter" aria-hidden="true"></div>
            <div class="fb-leaf" hidden>
              <div class="fb-face fb-face--front">
                <img alt="" draggable="false"><span class="fb-shade"></span>
              </div>
              <div class="fb-face fb-face--back">
                <img alt="" draggable="false"><span class="fb-shade"></span>
              </div>
            </div>
            <button class="fb-hit fb-hit--prev" type="button" aria-label="Page précédente"></button>
            <button class="fb-hit fb-hit--next" type="button" aria-label="Page suivante"></button>
          </div>
          <div class="fb-loader" role="status">
            <span class="fb-loader__ring"></span>
            <span class="fb-loader__label">Chargement du menu…</span>
          </div>

          <button class="fb-zoom" type="button" data-act="zoom">
            <svg class="fb-zoom__plus" viewBox="0 0 24 24" aria-hidden="true">
              <circle cx="11" cy="11" r="7"/><path d="M20 20l-4.3-4.3M11 8v6M8 11h6"/>
            </svg>
            <svg class="fb-zoom__moins" viewBox="0 0 24 24" aria-hidden="true">
              <circle cx="11" cy="11" r="7"/><path d="M20 20l-4.3-4.3M8 11h6"/>
            </svg>
            <span class="fb-zoom__mot"></span>
          </button>
        </div>

        <div class="fb-bar">
          <button class="fb-btn" type="button" data-act="prev" aria-label="Page précédente">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5l-7 7 7 7"/></svg>
          </button>
          <div class="fb-progress">
            <input class="fb-range" type="range" min="0" max="0" value="0" step="1"
                   aria-label="Naviguer dans le menu">
            <span class="fb-count">– / –</span>
          </div>
          <button class="fb-btn" type="button" data-act="next" aria-label="Page suivante">
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7"/></svg>
          </button>
        </div>
      `;

      this.el = {
        stage: this.root.querySelector(".fb-stage"),
        book: this.root.querySelector(".fb-book"),
        left: this.root.querySelector(".fb-pane--left img"),
        right: this.root.querySelector(".fb-pane--right img"),
        leaf: this.root.querySelector(".fb-leaf"),
        front: this.root.querySelector(".fb-face--front img"),
        frontShade: this.root.querySelector(".fb-face--front .fb-shade"),
        back: this.root.querySelector(".fb-face--back img"),
        backShade: this.root.querySelector(".fb-face--back .fb-shade"),
        loader: this.root.querySelector(".fb-loader"),
        loaderLabel: this.root.querySelector(".fb-loader__label"),
        zoom: this.root.querySelector(".fb-zoom"),
        zoomMot: this.root.querySelector(".fb-zoom__mot"),
        range: this.root.querySelector(".fb-range"),
        count: this.root.querySelector(".fb-count"),
        hitPrev: this.root.querySelector(".fb-hit--prev"),
        hitNext: this.root.querySelector(".fb-hit--next")
      };
    }

    /* ------------------------------------------------------ chargement */
    async load() {
      try {
        if (this.opts.pdfUrl) {
          this.pages = await this._loadPdf(this.opts.pdfUrl);
        } else {
          this.pages = (this.opts.images || []).slice();
        }
      } catch (err) {
        this._fail(err);
        return;
      }

      if (!this.pages.length) {
        this._fail(new Error("Aucune page à afficher"));
        return;
      }

      this.pageRatio = await this._measurePage(this.pages[0]);
      this._computeSpread();
      this.el.range.max = String(this.pages.length - 1);
      this.el.loader.hidden = true;
      this.root.classList.add("is-ready");
      this._syncZoom();
      this._fit();
      this._render();
      this._preload(0);
      if (this.opts.onReady) this.opts.onReady(this.pages.length);
    }

    _fail(err) {
      console.error("[Flipbook]", err);
      this.el.loader.innerHTML =
        '<p class="fb-error">Le menu n\'a pas pu être chargé.<br><small>' +
        (err && err.message ? err.message : "Erreur inconnue") +
        "</small></p>";
    }

    _loadScript(src) {
      return new Promise((resolve, reject) => {
        const existing = document.querySelector('script[src="' + src + '"]');
        if (existing) {
          if (existing.dataset.loaded) return resolve();
          existing.addEventListener("load", () => resolve());
          existing.addEventListener("error", () => reject(new Error("Script indisponible")));
          return;
        }
        const s = document.createElement("script");
        s.src = src;
        s.onload = () => {
          s.dataset.loaded = "1";
          resolve();
        };
        s.onerror = () => reject(new Error("Impossible de charger PDF.js (connexion ?)"));
        document.head.appendChild(s);
      });
    }

    async _loadPdf(url) {
      const src = Object.assign({}, PDFJS_DEFAULT, this.opts.pdfjs || {});
      await this._loadScript(src.lib);
      const pdfjsLib = window.pdfjsLib;
      if (!pdfjsLib) throw new Error("PDF.js introuvable");
      pdfjsLib.GlobalWorkerOptions.workerSrc = src.worker;

      const doc = await pdfjsLib.getDocument(url).promise;
      const dpr = clamp(window.devicePixelRatio || 1, 1, 2);
      const targetWidth = clamp(window.innerWidth * dpr, 720, 1600);
      const out = [];

      for (let i = 1; i <= doc.numPages; i++) {
        this.el.loaderLabel.textContent = `Chargement du menu… ${i}/${doc.numPages}`;
        const page = await doc.getPage(i);
        const base = page.getViewport({ scale: 1 });
        const viewport = page.getViewport({ scale: targetWidth / base.width });

        const canvas = document.createElement("canvas");
        canvas.width = Math.round(viewport.width);
        canvas.height = Math.round(viewport.height);
        await page.render({ canvasContext: canvas.getContext("2d"), viewport }).promise;

        const blob = await new Promise((res) => canvas.toBlob(res, "image/jpeg", 0.85));
        out.push(blob ? URL.createObjectURL(blob) : canvas.toDataURL("image/jpeg", 0.85));
        canvas.width = canvas.height = 0;
      }
      return out;
    }

    /* --------------------------------------------------------- rendu */

    /** Proportions réelles de la première page (A4 en cas d'échec). */
    _measurePage(src) {
      return new Promise((resolve) => {
        if (!src) return resolve(1.414);
        const img = new Image();
        const done = (r) => resolve(r);
        img.onload = () =>
          done(img.naturalWidth ? img.naturalHeight / img.naturalWidth : 1.414);
        img.onerror = () => done(1.414);
        img.src = src;
        // Un SVG sans dimensions intrinsèques ne déclenchera peut-être rien.
        setTimeout(() => done(1.414), 2500);
      });
    }

    /**
     * Pose la taille du livret en pixels. Le CSS seul n'y suffit pas : avec
     * `aspect-ratio`, une hauteur définie et un `max-width`, le navigateur
     * rogne la largeur sans recalculer la hauteur — le livret finissait
     * déformé, voire plus large que l'écran sur les téléphones hauts.
     */
    _fit() {
      const stage = this.el.stage;
      const cs = getComputedStyle(stage);
      const availW =
        stage.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
      const availH =
        stage.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
      if (availW <= 0 || availH <= 0) return;

      // En double page, le livret est deux fois plus large qu'une page.
      const bookRatio = this.spread ? this.pageRatio / 2 : this.pageRatio;
      const width = Math.min(availW, availH / bookRatio);

      this.el.book.style.width = Math.round(width) + "px";
      this.el.book.style.height = Math.round(width * bookRatio) + "px";
    }

    _computeSpread() {
      const wide = window.innerWidth >= this.opts.spreadMinWidth;
      if (wide === this.spread) return false;
      this.spread = wide;
      this.root.classList.toggle("is-spread", wide);
      if (wide) this.index = this.index - (this.index % 2); // aligne sur une page paire
      return true;
    }

    _src(i) {
      return i >= 0 && i < this.pages.length ? this.pages[i] : "";
    }

    _setImg(img, i) {
      const src = this._src(i);
      const pane = img.parentElement;
      if (src) {
        if (img.getAttribute("src") !== src) img.setAttribute("src", src);
        img.alt = `Menu, page ${i + 1}`;
        pane.classList.remove("is-blank");
      } else {
        img.removeAttribute("src");
        img.alt = "";
        pane.classList.add("is-blank");
      }
    }

    _render() {
      if (this.spread) {
        this._setImg(this.el.left, this.index);
        this._setImg(this.el.right, this.index + 1);
      } else {
        this._setImg(this.el.right, this.index);
        this._setImg(this.el.left, -1);
      }
      this._syncBar();
      if (this.opts.onPageChange) this.opts.onPageChange(this.index, this.pages.length);
    }

    _syncBar() {
      const total = this.pages.length;
      this.el.range.value = String(this.index);
      this.el.count.textContent = this.spread
        ? `${this.index + 1}–${Math.min(this.index + 2, total)} / ${total}`
        : `${this.index + 1} / ${total}`;
      this.el.hitPrev.disabled = !this._canGo("prev");
      this.el.hitNext.disabled = !this._canGo("next");
      this.root.querySelector('[data-act="prev"]').disabled = !this._canGo("prev");
      this.root.querySelector('[data-act="next"]').disabled = !this._canGo("next");
    }

    _preload(from) {
      const step = this.spread ? 2 : 1;
      [from - step, from + step, from + step * 2].forEach((i) => {
        const src = this._src(i);
        if (src) {
          const img = new Image();
          img.src = src;
        }
      });
    }

    /* ------------------------------------------------- navigation */
    _canGo(dir) {
      const step = this.spread ? 2 : 1;
      return dir === "next" ? this.index + step < this.pages.length : this.index - step >= 0;
    }

    next() {
      this._animateTurn("next");
    }
    prev() {
      this._animateTurn("prev");
    }

    goTo(i) {
      const step = this.spread ? 2 : 1;
      let target = clamp(i, 0, this.pages.length - 1);
      if (this.spread) target -= target % 2;
      if (target === this.index) return;
      // Saut direct (sans animation de tournage) au-delà d'une page d'écart
      if (Math.abs(target - this.index) > step) {
        this.index = target;
        this._recadrer();
        this._render();
        this._preload(target);
        return;
      }
      this._animateTurn(target > this.index ? "next" : "prev");
    }

    /* --------------------------------------------- moteur de rotation
     * Géométrie unifiée :
     *   next → la feuille pivote autour de son bord GAUCHE  (0 → -180°)
     *   prev → la feuille pivote autour de son bord DROIT   (0 → +180°)
     * Dans les deux cas la face avant montre la page courante et la face
     * arrière montre la page de destination, qui est aussi celle rendue
     * dessous : la transition est donc sans raccord.
     * -------------------------------------------------------------- */
    _beginTurn(dir) {
      if (this.turning || !this._canGo(dir)) return false;

      const i = this.index;
      const leaf = this.el.leaf;
      leaf.hidden = false;
      leaf.classList.toggle("fb-leaf--next", dir === "next");
      leaf.classList.toggle("fb-leaf--prev", dir === "prev");
      leaf.style.transition = "none";

      if (this.spread) {
        if (dir === "next") {
          this._setImg(this.el.left, i);
          this._setImg(this.el.right, i + 3);
          this._setImg(this.el.front, i + 1);
          this._setImg(this.el.back, i + 2);
        } else {
          this._setImg(this.el.left, i - 2);
          this._setImg(this.el.right, i + 1);
          this._setImg(this.el.front, i);
          this._setImg(this.el.back, i - 1);
        }
      } else {
        const dest = dir === "next" ? i + 1 : i - 1;
        this._setImg(this.el.right, dest);
        this._setImg(this.el.left, -1);
        this._setImg(this.el.front, i);
        this._setImg(this.el.back, dest);
      }

      this.turning = { dir, progress: 0 };
      this.root.classList.add("is-turning");
      this._applyTurn(0);
      return true;
    }

    _applyTurn(p) {
      if (!this.turning) return;
      const sign = this.turning.dir === "next" ? -1 : 1;
      // Léger easing sur la rotation pour un rendu plus « papier »
      const angle = sign * 180 * p;
      this.el.leaf.style.transform = `rotateY(${angle}deg)`;
      this.el.frontShade.style.opacity = (p * 0.6).toFixed(3);
      this.el.backShade.style.opacity = ((1 - p) * 0.6).toFixed(3);
      this.el.book.style.setProperty("--fb-turn", p.toFixed(3));
      this.turning.progress = p;
    }

    _endTurn(commit) {
      const dir = this.turning.dir;
      const step = this.spread ? 2 : 1;
      const leaf = this.el.leaf;

      const finish = () => {
        leaf.removeEventListener("transitionend", finish);
        clearTimeout(this._turnTimer);
        if (commit) this.index += dir === "next" ? step : -step;
        this.turning = null;
        leaf.hidden = true;
        leaf.style.transition = "none";
        leaf.style.transform = "rotateY(0deg)";
        this.root.classList.remove("is-turning");
        this.el.book.style.setProperty("--fb-turn", "0");
        this._recadrer();
        this._render();
        this._preload(this.index);
      };

      const from = this.turning.progress;
      const to = commit ? 1 : 0;
      if (Math.abs(to - from) < 0.002) return finish();

      const duration = Math.round(180 + Math.abs(to - from) * 300);

      // On fige l'état de départ puis on force un reflow : sans cela le
      // navigateur regroupe les deux écritures et n'anime rien.
      leaf.style.transition = "none";
      this._applyTurn(from);
      void leaf.offsetWidth;

      leaf.style.transition = `transform ${duration}ms cubic-bezier(.22,.61,.36,1)`;
      this.el.frontShade.style.transition = `opacity ${duration}ms linear`;
      this.el.backShade.style.transition = `opacity ${duration}ms linear`;
      leaf.addEventListener("transitionend", finish);
      this._turnTimer = setTimeout(finish, duration + 90); // filet de sécurité
      this._applyTurn(to);
    }

    _animateTurn(dir) {
      if (!this._beginTurn(dir)) return;
      this._endTurn(true);
    }

    /* ---------------------------------------------------- gestuelle */
    _bindEvents() {
      const stage = this.el.stage;

      let drag = null;

      const onDown = (e) => {
        if (this.zoom > 1) {
          drag = { pan: true, x: e.clientX, y: e.clientY, ox: this.pan.x, oy: this.pan.y };
          stage.setPointerCapture(e.pointerId);
          return;
        }
        if (this.turning || !this.pages.length) return;
        // Pas de capture ici : elle détournerait le clic des zones tactiles.
        // On la prendra seulement si un vrai glissé démarre.
        drag = { x: e.clientX, y: e.clientY, t: Date.now(), dir: null, moved: false };
      };

      const onMove = (e) => {
        if (!drag) return;

        if (drag.pan) {
          this.pan.x = drag.ox + (e.clientX - drag.x);
          this.pan.y = drag.oy + (e.clientY - drag.y);
          this._clampPan();
          this._applyZoom();
          return;
        }

        const dx = e.clientX - drag.x;
        const dy = e.clientY - drag.y;

        if (!drag.dir) {
          if (Math.abs(dx) < 12 || Math.abs(dx) < Math.abs(dy)) return; // geste vertical = scroll
          drag.dir = dx < 0 ? "next" : "prev";
          if (!this._beginTurn(drag.dir)) {
            drag = null;
            return;
          }
          drag.startX = e.clientX;
          try {
            stage.setPointerCapture(e.pointerId);
          } catch (_) {
            /* le glissé fonctionne aussi sans capture */
          }
        }

        drag.moved = true;
        e.preventDefault();
        const width = this.el.book.getBoundingClientRect().width || 1;
        const travel = drag.dir === "next" ? drag.startX - e.clientX : e.clientX - drag.startX;
        this._applyTurn(clamp(travel / (this.spread ? width / 2 : width), 0, 1));
      };

      const onUp = (e) => {
        if (!drag) return;
        const wasPan = drag.pan;
        const info = drag;
        drag = null;
        if (stage.hasPointerCapture && stage.hasPointerCapture(e.pointerId)) {
          stage.releasePointerCapture(e.pointerId);
        }
        if (info.moved) {
          // Empêche le clic « fantôme » sur les zones tactiles après un glissé
          this._suppressClick = true;
          clearTimeout(this._clickTimer);
          this._clickTimer = setTimeout(() => (this._suppressClick = false), 350);
        }
        if (wasPan || !this.turning) return;

        const elapsed = Date.now() - info.t;
        const flick = elapsed < 320 && this.turning.progress > 0.08;
        this._endTurn(flick || this.turning.progress > 0.32);
      };

      stage.addEventListener("pointerdown", onDown);
      stage.addEventListener("pointermove", onMove, { passive: false });
      stage.addEventListener("pointerup", onUp);
      stage.addEventListener("pointercancel", onUp);

      // Zones tactiles gauche / droite
      this.el.hitPrev.addEventListener("click", () => {
        if (!this._suppressClick) this.prev();
      });
      this.el.hitNext.addEventListener("click", () => {
        if (!this._suppressClick) this.next();
      });

      // Double-tap / double-clic : zoom
      let lastTap = 0;
      stage.addEventListener("pointerup", (e) => {
        if (this._suppressClick || this.turning) {
          lastTap = 0;
          return;
        }
        const now = Date.now();
        if (now - lastTap < 300) {
          this._toggleZoom(e);
          lastTap = 0;
        } else {
          lastTap = now;
        }
      });

      this.el.zoom.addEventListener("click", (e) => {
        e.stopPropagation(); // le geste de zoom ne doit pas tourner la page
        this._toggleZoom(null);
      });
      // Le bouton est dans la scène : sans cela, l'appui déclencherait aussi
      // le compte à rebours du double-tap.
      this.el.zoom.addEventListener("pointerdown", (e) => e.stopPropagation());
      this.el.zoom.addEventListener("pointerup", (e) => e.stopPropagation());

      this.root.querySelector('[data-act="prev"]').addEventListener("click", () => this.prev());
      this.root.querySelector('[data-act="next"]').addEventListener("click", () => this.next());
      this.el.range.addEventListener("input", (e) => this.goTo(Number(e.target.value)));

      document.addEventListener("keydown", (e) => {
        if (this.destroyed || !this.root.offsetParent) return;
        if (e.target.matches("input, textarea, select")) return;
        if (e.key === "ArrowLeft") this.prev();
        if (e.key === "ArrowRight") this.next();
      });

      window.addEventListener("resize", () => {
        const changed = this._computeSpread();
        this._fit();
        if (this.zoom > 1) {
          this._clampPan();
          this._applyZoom();
        }
        if (changed) this._render();
      });

      document.addEventListener("langue:change", () => this._syncZoom());
    }

    /**
     * Bornes du déplacement : la page agrandie peut glisser sous l'écran,
     * jamais s'en échapper. Sans cela un doigt un peu vif laisse le client
     * devant du vide, sans moyen évident de revenir sur la carte.
     */
    _bornes() {
      const stage = this.el.stage;
      const cs = getComputedStyle(stage);
      const dispoW =
        stage.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight);
      const dispoH =
        stage.clientHeight - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom);
      const w = parseFloat(this.el.book.style.width) || dispoW;
      const h = parseFloat(this.el.book.style.height) || dispoH;
      return {
        x: Math.max(0, (w * this.zoom - dispoW) / 2),
        y: Math.max(0, (h * this.zoom - dispoH) / 2)
      };
    }

    _clampPan() {
      const b = this._bornes();
      this.pan.x = clamp(this.pan.x, -b.x, b.x);
      this.pan.y = clamp(this.pan.y, -b.y, b.y);
    }

    /**
     * @param {{clientX:number, clientY:number}|null} e point touché, ou
     *   `null` pour le bouton loupe : on cadre alors le haut de la page,
     *   là où commence la lecture.
     */
    _toggleZoom(e) {
      if (this.zoom > 1) {
        this.zoom = 1;
        this.pan = { x: 0, y: 0 };
      } else {
        const bande = this._lecture();
        this.zoom = 1 / bande.part;
        const rect = this.el.book.getBoundingClientRect();
        if (e) {
          // Centre l'agrandissement sur le point touché
          this.pan = {
            x: (rect.left + rect.width / 2 - e.clientX) * (this.zoom - 1),
            y: (rect.top + rect.height / 2 - e.clientY) * (this.zoom - 1)
          };
        } else {
          // Bouton loupe : on cadre la bande de lecture, en haut de la page.
          const largeur = parseFloat(this.el.book.style.width) || rect.width;
          this.pan = {
            x: (0.5 - bande.centre) * largeur * this.zoom,
            y: this._bornes().y
          };
        }
        this._clampPan();
      }
      this.root.classList.toggle("is-zoomed", this.zoom > 1);
      this._syncZoom();
      this.el.book.style.transition = "transform 260ms ease";
      this._applyZoom();
      setTimeout(() => (this.el.book.style.transition = ""), 280);
    }

    /**
     * Reprend le cadrage de lecture sur la page qui vient d'arriver.
     *
     * L'agrandissement se garde d'une page à l'autre — un client qui lit de
     * près veut continuer ainsi — mais chaque page a sa colonne de texte, et
     * la lecture reprend en haut : sinon la page suivante s'ouvrirait au
     * milieu d'un plat, décalée sur une photo.
     */
    _recadrer() {
      if (this.zoom <= 1) return;
      const bande = this._lecture();
      const largeur = parseFloat(this.el.book.style.width) || 0;
      this.zoom = 1 / bande.part;
      this.pan = { x: (0.5 - bande.centre) * largeur * this.zoom, y: this._bornes().y };
      this._clampPan();
      this._applyZoom();
    }

    /** Étiquette et intitulé du bouton loupe, dans la langue du client. */
    _syncZoom() {
      if (!this.el.zoom) return;
      const agrandi = this.zoom > 1;
      const mot = agrandi
        ? dit("carte.reduire", "Vue d'ensemble")
        : dit("carte.agrandir", "Agrandir");
      this.el.zoomMot.textContent = mot;
      this.el.zoom.setAttribute("aria-label", mot);
      this.el.zoom.classList.toggle("is-on", agrandi);
    }

    _applyZoom() {
      this.el.book.style.transform = `translate(${this.pan.x}px, ${this.pan.y}px) scale(${this.zoom})`;
    }

    destroy() {
      this.destroyed = true;
      this.pages.forEach((u) => {
        if (typeof u === "string" && u.startsWith("blob:")) URL.revokeObjectURL(u);
      });
    }
  }

  window.Flipbook = Flipbook;
})();
