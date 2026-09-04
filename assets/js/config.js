/* ------------------------------------------------------------------
 * CONFIGURATION DU RESTAURANT
 * ------------------------------------------------------------------
 * C'est le SEUL fichier à modifier pour personnaliser l'application.
 * ------------------------------------------------------------------ */

window.APP_CONFIG = {

  /* --- Identité du restaurant ------------------------------------ */
  restaurant: {
    name: "Restaurant Les Tilleuls",
    tagline: "Carte d'automne · Cuisine de saison",
    // Accroche servie aux téléphones réglés en anglais
    taglineEn: "Autumn menu · Seasonal cooking",
    // Initiales de secours, si le logo ne se charge pas
    monogram: "LT",
    logoUrl: "assets/img/logo-tilleuls.png",
    // Adresse et téléphone de l'hôtel qui accueille le restaurant.
    // Se règlent aussi depuis le panneau gérant, onglet Réglages.
    address: "",
    phone: "",
    // Repris de la couverture de la carte d'automne 2026
    hours: "Septembre : du lundi au dimanche · 19 h – 21 h · Octobre : du lundi au vendredi",
    hoursEn: "September: Monday to Sunday · 7 pm – 9 pm · October: Monday to Friday",
    // L'hôtel : son nom et le lien vers son site. Affichés dans
    // « Informations pratiques », sous l'adresse.
    hotel: { name: "Hôtel Ibis", url: "" },
    wifi: null // ex. { ssid: "...", password: "..." }
  },

  /* --- Source du menu (flipbook) ---------------------------------
   * Les pages sont celles du PDF du restaurant, photographiées à haute
   * définition (1800 px de large) et rien d'autre : même maquette, mêmes
   * photos, mêmes couleurs, mêmes polices. L'application ne recompose
   * jamais la carte.
   *
   * Un écran de téléphone ne fait que 390 points de large là où une page
   * A4 en fait 595 : le texte y est réduit d'un tiers, quoi qu'on fasse.
   * La lecture confortable passe donc par le zoom — bouton loupe, double
   * touche, ou pincement — et non par un découpage qui n'y changerait
   * rien (l'échelle ne dépend que de la largeur montrée).
   *
   * type: "images"  -> tableau `images` ci-dessous (jpg, png, webp, svg)
   * type: "pdf"     -> fichier `pdfUrl` (rendu via PDF.js)
   * ---------------------------------------------------------------- */
  menu: {
    type: "images",
    pdfUrl: "assets/menu/menu.pdf",
    images: [
      "assets/menu/carte-fr-1.webp",
      "assets/menu/carte-fr-2.webp",
      "assets/menu/carte-fr-3.webp",
      "assets/menu/carte-fr-4.webp",
      "assets/menu/carte-fr-5.webp",
      "assets/menu/carte-fr-6.webp",
      "assets/menu/carte-fr-7.webp",
      "assets/menu/carte-fr-8.webp",
      "assets/menu/carte-fr-9.webp"
    ],
    // Version anglaise, servie aux téléphones réglés en anglais. Tant
    // qu'elle est vide, ces clients voient la carte française : mieux vaut
    // une carte qu'ils lisent à moitié qu'un livret vide.
    imagesEn: [
      "assets/menu/carte-en-1.webp",
      "assets/menu/carte-en-2.webp",
      "assets/menu/carte-en-3.webp",
      "assets/menu/carte-en-4.webp",
      "assets/menu/carte-en-5.webp",
      "assets/menu/carte-en-6.webp",
      "assets/menu/carte-en-7.webp",
      "assets/menu/carte-en-8.webp",
      "assets/menu/carte-en-9.webp"
    ],
    /* Cadrage du bouton « Agrandir », page par page.
     *
     * `part`   : la fraction de la largeur de page montrée une fois agrandi
     * `centre` : autour de quel point de cette largeur (0 = bord gauche)
     *
     * Une page A4 réduite à la largeur d'un téléphone ramène les prix à
     * 7 px : lisibles de justesse, pénibles à table. Cadrer la colonne de
     * texte les remonte — sans toucher à la maquette, puisque le client
     * revient à la page entière d'une seule touche.
     *
     * Les valeurs viennent des boîtes de texte du PDF (outils/bandes.py),
     * page par page : la maquette alterne les colonnes — photos à gauche
     * page 2, à droite page 3 — et un cadrage unique couperait un nom de
     * plat sur deux. Le nom d'un plat et son prix tiennent toujours
     * ensemble à l'écran : les pages à colonne étroite y gagnent un fort
     * agrandissement, celles qui étalent leurs lignes d'un bord à l'autre
     * (les vins, les bières) un plus modeste, mais gardent leurs prix.
     *
     * `defaut` sert aux cartes importées depuis le panneau gérant, dont on
     * ne connaît pas la maquette.
     */
    lecture: {
      defaut: { part: 0.62, centre: 0.5 },
      pages: [
        { part: 0.787, centre: 0.497 },
        { part: 0.544, centre: 0.644 },
        { part: 0.862, centre: 0.511 },
        { part: 0.861, centre: 0.511 },
        { part: 0.862, centre: 0.511 },
        { part: 0.831, centre: 0.496 },
        { part: 0.831, centre: 0.496 },
        { part: 0.773, centre: 0.496 },
        { part: 0.837, centre: 0.499 }
      ]
    },

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

  /* --- Le moment dessert -------------------------------------------
   * Un temps après l'ouverture de la carte, l'application propose les
   * desserts et ouvre la page correspondante.
   *
   * À savoir : si le client a fermé l'onglet, rien ne peut lui être
   * envoyé — aucun script ne tourne plus. La proposition l'attend alors
   * à son retour. C'est la limite d'un site sans serveur d'envoi.
   * ---------------------------------------------------------------- */
  desserts: {
    // Délai depuis l'ouverture, en minutes. 0 ou null désactive.
    delay: 45,
    // Page à ouvrir (1 = couverture). Les desserts sont sur la page 3.
    page: 3,
    title: "Encore un peu de place ?",
    lead: "Nos desserts sortent de la cuisine, préparés du jour.",
    // Trois suggestions, reprises telles quelles de la carte
    picks: [
      {
        nom: "Cœur coulant au chocolat",
        prix: "9,00 €",
        note: "Crème fouettée sucrée et éclats de noisettes"
      },
      {
        nom: "Tarte fine aux pommes tiède",
        prix: "9,00 €",
        note: "Glace caramel beurre salé"
      },
      {
        nom: "Crémeux vanille et poire pochée",
        prix: "9,00 €",
        note: "Poire au vin épicé et croustillant spéculoos"
      }
    ],
    // Une ou deux photos. Deux se placent côte à côte.
    images: ["assets/img/dessert-moelleux.jpg", "assets/img/dessert-tarte.jpg"],
    // Version anglaise : seuls les textes changent, le reste est commun.
    en: {
      title: "Room for a little more?",
      lead: "Our desserts are made in-house, fresh each day.",
      picks: [
        {
          nom: "Chocolate fondant",
          prix: "9.00 €",
          note: "Sweetened whipped cream and hazelnut pieces"
        },
        {
          nom: "Warm thin apple tart",
          prix: "9.00 €",
          note: "Salted caramel ice cream"
        },
        {
          nom: "Vanilla cream and poached pear",
          prix: "9.00 €",
          note: "Pear poached in spiced wine and speculoos crumble"
        }
      ],
      notifTitle: "And to finish?",
      notifBody: "Chocolate fondant, warm thin apple tart… Tap to see the desserts."
    },
    // Texte de la notification, si le client a quitté l'onglet
    notifTitle: "Et pour finir ?",
    notifBody:
      "Cœur coulant au chocolat, tarte fine aux pommes tiède… " +
      "Touchez pour voir les desserts."
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
