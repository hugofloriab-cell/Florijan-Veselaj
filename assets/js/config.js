/* ------------------------------------------------------------------
 * CONFIGURATION DU RESTAURANT
 * ------------------------------------------------------------------
 * C'est le SEUL fichier à modifier pour personnaliser l'application.
 * ------------------------------------------------------------------ */

window.APP_CONFIG = {

  /* --- Identité du restaurant ------------------------------------ */
  restaurant: {
    name: "Le Jardin d'Olivier",
    tagline: "Cuisine de saison · Maison depuis 1998",
    // Initiales affichées dans le monogramme (2 lettres conseillées)
    monogram: "JO",
    // Laisser vide pour utiliser le monogramme, ou mettre "assets/img/logo.png"
    logoUrl: "",
    address: "12 rue des Oliviers, 75011 Paris",
    phone: "+33 1 23 45 67 89",
    wifi: { ssid: "Jardin-Invites", password: "bienvenue" } // mettre à null pour masquer
  },

  /* --- Source du menu (flipbook) ---------------------------------
   * type: "images"  -> tableau `images` ci-dessous (jpg, png, webp, svg)
   * type: "pdf"     -> fichier `pdfUrl` (rendu via PDF.js)
   * ---------------------------------------------------------------- */
  menu: {
    type: "images",
    pdfUrl: "assets/menu/menu.pdf",
    images: [
      "assets/menu/page-1.svg",
      "assets/menu/page-2.svg",
      "assets/menu/page-3.svg",
      "assets/menu/page-4.svg",
      "assets/menu/page-5.svg",
      "assets/menu/page-6.svg"
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
    snoozeHours: 4
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
        url: "https://search.google.com/local/writereview?placeid=VOTRE_PLACE_ID",
        color: "#4285F4"
      },
      {
        id: "tripadvisor",
        label: "Tripadvisor",
        hint: "Pour les voyageurs",
        url: "https://www.tripadvisor.fr/UserReviewEdit-gVOTRE_ID",
        color: "#00AA6C"
      },
      {
        id: "booking",
        label: "Booking",
        hint: "Si vous séjournez chez nous",
        url: "https://www.booking.com/reviewit.fr.html?pagename=VOTRE_HOTEL",
        color: "#003580"
      }
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

  /* --- Envoi optionnel des avis privés vers un serveur -------------
   * Laisser `endpoint` à null pour un fonctionnement 100 % local.
   * Si renseigné, chaque avis privé est aussi envoyé en POST (JSON).
   * ---------------------------------------------------------------- */
  sync: {
    endpoint: null,
    token: null
  }
};
