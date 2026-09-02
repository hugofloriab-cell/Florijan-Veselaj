/* ------------------------------------------------------------------
 * CONFIGURATION DU RESTAURANT
 * ------------------------------------------------------------------
 * C'est le SEUL fichier à modifier pour personnaliser l'application.
 * ------------------------------------------------------------------ */

window.APP_CONFIG = {

  /* --- Identité du restaurant ------------------------------------ */
  restaurant: {
    name: "Restaurant Les Tilleuls",
    tagline: "Carte d'été · Cuisine de saison",
    // Initiales de secours, si le logo ne se charge pas
    monogram: "LT",
    logoUrl: "assets/img/logo-tilleuls.png",
    // À compléter : l'adresse et le téléphone n'étaient pas sur la carte
    address: "",
    phone: "",
    hours: "Du lundi au dimanche · 19 h – 21 h",
    wifi: null // ex. { ssid: "...", password: "..." }
  },

  /* --- Source du menu (flipbook) ---------------------------------
   * type: "images"  -> tableau `images` ci-dessous (jpg, png, webp, svg)
   * type: "pdf"     -> fichier `pdfUrl` (rendu via PDF.js)
   * ---------------------------------------------------------------- */
  menu: {
    type: "images",
    pdfUrl: "assets/menu/menu.pdf",
    images: [
      "assets/menu/tilleuls-1.svg",
      "assets/menu/tilleuls-2.svg",
      "assets/menu/tilleuls-3.svg",
      "assets/menu/tilleuls-4.svg",
      "assets/menu/tilleuls-5.svg",
      "assets/menu/tilleuls-6.svg",
      "assets/menu/tilleuls-7.svg",
      "assets/menu/tilleuls-8.svg",
      "assets/menu/tilleuls-9.svg",
      "assets/menu/tilleuls-10.svg",
      "assets/menu/tilleuls-11.svg"
    ],
    // Téléchargement du menu en PDF proposé au client (null = masqué)
    downloadUrl: null,
    // Où charger PDF.js (utile uniquement si type = "pdf").
    // Laisser null pour le CDN, ou pointer vers vos propres fichiers :
    //   { lib: "assets/vendor/pdf.min.js", worker: "assets/vendor/pdf.worker.min.js" }
    pdfjs: null
  },

  /* --- Rappel pour laisser un avis -------------------------------- */
  reminder: {
    // Délais proposés au client, en minutes
    delays: [5, 10, 15, 20, 30, 40],
    // Délai pré-sélectionné visuellement
    defaultDelay: 15,
    // Afficher la pop-up dès l'ouverture de l'application
    askOnOpen: true,
    // Ne plus reproposer la pop-up pendant X heures après un choix
    snoozeHours: 4,
    // Poster une notification de confirmation dès le choix du délai.
    // C'est la seule entrée garantie dans le volet de notifications :
    // une fois l'onglet fermé, plus rien ne peut être émis sans serveur.
    confirmNotification: true
  },

  /* --- Affichage --------------------------------------------------- */
  ui: {
    // Passe en plein écran au premier geste sur la carte, pour masquer la
    // barre d'adresse du navigateur. Sans effet sur iPhone : Safari
    // n'autorise pas le plein écran (le bouton y est alors masqué).
    autoFullscreen: true
  },

  /* --- Avis --------------------------------------------------------
   * Note >= threshold  -> redirection vers les plateformes publiques
   * Note <  threshold  -> conservation privée (panneau gérant)
   * ---------------------------------------------------------------- */
  review: {
    threshold: 4,
    // Liens publics (remplacer par vos vraies URL)
    publicLinks: [
      {
        id: "google",
        label: "Google",
        hint: "Le plus visible pour nous",
        // Lien extrait du QR code « Restaurant Les Tilleuls » de la carte papier
        url: "https://g.page/r/CTIvdw1e5rcAEAE/review",
        color: "#4285F4"
      }
      // Pour ajouter Tripadvisor ou Booking, copier ce bloc et remplacer l'URL.
    ],
    // Compression des photos jointes (limite le poids en base locale)
    photo: { maxSize: 1400, quality: 0.72 }
  },

  /* --- Panneau gérant ---------------------------------------------
   * Empreinte SHA-256 du mot de passe. Mot de passe par défaut : gerant2024
   * Pour en générer une autre, ouvrir la console du navigateur et lancer :
   *   await hashPassword("mon-mot-de-passe")
   * (la fonction est disponible sur la page admin.html)
   *
   * ATTENTION : cette protection est côté navigateur uniquement. Elle
   * empêche un client curieux d'entrer, pas un attaquant déterminé. Voir
   * la section « Sécurité » du README pour une mise en production.
   * ---------------------------------------------------------------- */
  admin: {
    passwordSha256: "79d76313af5869ead530fda57398464ff05be04f7885032902a1da54bf9a1422",
    sessionMinutes: 30
  },

  /* --- Serveur (Supabase) ------------------------------------------
   * Laisser `url` à null : l'application reste 100 % locale, et les avis
   * ne quittent pas le téléphone du client — donc ne vous parviennent pas.
   * Renseigné, le serveur devient la source de vérité : les avis arrivent
   * chez vous et le panneau gérant se connecte par e-mail + mot de passe.
   *
   * La clé « anon » est publique par nature : ce sont les règles RLS de
   * serveur/schema.sql qui protègent les données, pas son secret.
   * ---------------------------------------------------------------- */
  serveur: {
    url: "https://ynclfjvowjuclhswkxcl.supabase.co",
    // Clé publique du projet : « sb_publishable_… » (format actuel) ou
    // « anon public » (ancien format JWT). Les deux fonctionnent.
    cleAnon: "sb_publishable_qbmprvBhEftU7wSbsVXamw__dqi6DGh"
  },

  /* --- Envoi optionnel des avis privés vers un autre serveur --------
   * Laisser `endpoint` à null pour un fonctionnement 100 % local.
   * Si renseigné, chaque avis privé est aussi envoyé en POST (JSON).
   * ---------------------------------------------------------------- */
  sync: {
    endpoint: null,
    token: null
  }
};
