/* ------------------------------------------------------------------
 * Langue de l'application
 * ------------------------------------------------------------------
 * La langue est choisie dans cet ordre :
 *   1. le choix explicite du client, gardé sur son téléphone
 *   2. les réglages de son téléphone (`navigator.languages`)
 *   3. le français, langue du restaurant
 *
 * Tout ce qui est écrit dans la page porte un `data-t` : le module
 * remplace le texte au chargement et à chaque bascule. Les textes
 * produits par le code passent, eux, par `T()`.
 *
 * La carte elle-même suit la langue quand une version anglaise a été
 * publiée ; sinon le client voit la carte française, ce qui vaut mieux
 * qu'une page vide.
 * ------------------------------------------------------------------ */

window.I18n = (function () {
  const CLE = "resto-langue";
  const LANGUES = ["fr", "en"];

  const DICO = {
    /* --- en-tête et carte ---------------------------------------- */
    "app.titre": ["Menu · Restaurant Les Tilleuls", "Menu · Restaurant Les Tilleuls"],
    "nav.pleinEcran": ["Plein écran", "Full screen"],
    "nav.quitterPleinEcran": ["Quitter le plein écran", "Exit full screen"],
    "nav.infos": ["Informations pratiques", "Practical information"],
    "nav.avis": ["Donner mon avis", "Leave a review"],
    "nav.langue": ["English", "Français"],
    "nav.langueTitre": ["Read the menu in English", "Lire la carte en français"],
    "carte.indice": [
      "Glissez pour tourner · double-tapez pour zoomer",
      "Swipe to turn · double-tap to zoom"
    ],
    "carte.precedent": ["Page précédente", "Previous page"],
    "carte.suivant": ["Page suivante", "Next page"],
    "carte.chargement": ["Chargement de la carte…", "Loading the menu…"],

    /* --- pop-up de rappel ---------------------------------------- */
    "rappel.titre": ["Bon appétit !", "Enjoy your meal!"],
    "rappel.texte": [
      "Souhaitez-vous qu'on vous propose de laisser un avis un peu plus tard, une fois votre repas terminé ?",
      "Shall we invite you to leave a review a little later, once you have finished?"
    ],
    "rappel.choisir": ["Choisir un délai", "Choose a delay"],
    "rappel.min": ["MIN", "MIN"],
    "rappel.valider": ["Me rappeler dans", "Remind me in"],
    "rappel.maintenant": ["Donner mon avis tout de suite", "Leave a review now"],
    "rappel.non": ["Non merci", "No thanks"],
    "rappel.dans": ["Rappel dans", "Reminder in"],
    "rappel.toucher": [
      "Touchez pour donner votre avis maintenant",
      "Tap to leave your review now"
    ],
    "rappel.annule": ["Rappel annulé.", "Reminder cancelled."],
    "rappel.note": [
      "Nous vous enverrons une notification : gardez simplement cette page ouverte. Sans autorisation, un minuteur reste affiché dans l'application.",
      "We will send you a notification: simply keep this page open. Without permission, a timer stays visible in the app."
    ],
    "rappel.notifTitre": ["Restaurant Les Tilleuls", "Restaurant Les Tilleuls"],
    "rappel.notifCorps": [
      "Avez-vous une minute pour nous dire comment s'est passé votre repas ?",
      "Do you have a minute to tell us how your meal was?"
    ],
    "rappel.notifPrevu": ["Rappel prévu vers", "Reminder set for around"],
    "rappel.notifToucher": [
      "Touchez pour laisser votre avis.",
      "Tap to leave your review."
    ],

    /* --- formulaire d'avis --------------------------------------- */
    "avis.titre": ["Votre avis compte", "Your opinion matters"],
    "avis.accroche": [
      "Comment s'est passé votre moment chez nous ?",
      "How was your time with us?"
    ],
    "avis.noter": ["Touchez une étoile pour noter", "Tap a star to rate"],
    "avis.note1": ["Très décevant", "Very disappointing"],
    "avis.note2": ["Décevant", "Disappointing"],
    "avis.note3": ["Correct, sans plus", "Fair, nothing more"],
    "avis.note4": ["Très bon moment", "A very good time"],
    "avis.note5": ["Excellent, un vrai plaisir !", "Excellent, a real pleasure!"],
    "avis.commentaire": ["Votre commentaire", "Your comment"],
    "avis.commentairePlaceholder": [
      "Ce qui vous a plu, ou ce qu'on pourrait améliorer…",
      "What you enjoyed, or what we could improve…"
    ],
    "avis.photo": ["Une photo de votre plat ?", "A photo of your dish?"],
    "avis.photoAppareil": ["Prendre une photo", "Take a photo"],
    "avis.photoGalerie": ["Choisir dans la galerie", "Choose from gallery"],
    "avis.photoRetirer": ["Retirer la photo", "Remove photo"],
    "avis.complement": [
      "Informations complémentaires (facultatif)",
      "Additional information (optional)"
    ],
    "avis.table": ["Numéro de table", "Table number"],
    "avis.contact": ["Pour être recontacté", "To be contacted"],
    "avis.contactPlaceholder": [
      "E-mail ou téléphone (facultatif)",
      "Email or phone (optional)"
    ],
    "avis.envoyer": ["Envoyer mon avis", "Send my review"],
    "avis.facultatif": ["(facultatif)", "(optional)"],
    "avis.fermer": ["Fermer", "Close"],
    "avis.plusTard": ["Plus tard", "Later"],

    /* --- après envoi --------------------------------------------- */
    // « {plateformes} » est remplacé par les noms réellement configurés.
    "avis.routagePublic": [
      "Merci ! Nous vous proposerons de partager cet avis sur {plateformes}.",
      "Thank you! We will invite you to share this review on {plateformes}."
    ],
    "avis.routagePublicSansNom": [
      "Merci ! Nous vous proposerons de partager cet avis publiquement.",
      "Thank you! We will invite you to share this review publicly."
    ],
    "avis.routagePrive": [
      "Votre message sera transmis directement au gérant, en privé. Il ne sera pas publié.",
      "Your message will go straight to the manager, privately. It will not be published."
    ],
    "avis.mentions": [
      "Vos informations restent chez le restaurant. Aucune donnée n'est revendue ni publiée sans votre action.",
      "Your information stays with the restaurant. Nothing is sold or published without your action."
    ],
    "avis.merci": ["Merci beaucoup !", "Thank you very much!"],
    "avis.merciTexte": [
      "Votre retour nous fait très plaisir. Partagez-le en public : c'est ce qui aide le plus une maison comme la nôtre.",
      "Your feedback means a great deal to us. Sharing it publicly is what helps a place like ours the most."
    ],
    "avis.priveTexte": [
      "Votre message vient d'être transmis directement au gérant, en privé. Il n'est publié nulle part.",
      "Your message has gone straight to the manager, privately. It is not published anywhere."
    ],
    "avis.priveSuite": [
      "C'est exactement ce genre de retour qui nous permet de corriger le tir. Nous en sommes sincèrement désolés et nous espérons vous revoir.",
      "This is exactly the kind of feedback that lets us put things right. We are sincerely sorry, and we hope to see you again."
    ],
    "avis.merciPublic": [
      "Merci ! Nous vous proposerons de partager cet avis publiquement.",
      "Thank you! We will invite you to share this review publicly."
    ],
    "avis.merciFranchise": ["Merci de votre franchise", "Thank you for your candour"],
    "avis.prive": [
      "Votre message sera transmis directement au gérant, en privé. Il ne sera pas publié.",
      "Your message goes straight to the manager, privately. It will not be published."
    ],
    "avis.priveCourt": ["directement au gérant", "straight to the manager"],
    "avis.copier": ["Copier mon commentaire", "Copy my comment"],
    "avis.copie": ["Commentaire copié ✓", "Comment copied ✓"],
    "avis.copieRatee": [
      "Copie impossible — sélectionnez le texte",
      "Copy failed — please select the text"
    ],
    "avis.collerAilleurs": [
      "Vous n'aurez plus qu'à le coller sur la plateforme choisie.",
      "You will just need to paste it on the platform you choose."
    ],
    "avis.photoNonTransmise": [
      "Votre photo reste chez nous : les plateformes ne l'accepteront pas depuis ce lien.",
      "Your photo stays with us: the platforms will not accept it from this link."
    ],
    "avis.erreurImage": ["Ce fichier n'est pas une image.", "This file is not an image."],
    "avis.imageIllisible": ["Image illisible.", "Unreadable image."],

    /* --- desserts ------------------------------------------------- */
    "dessert.voir": ["Voir les desserts", "See the desserts"],
    "dessert.plusTard": ["Une autre fois", "Another time"],

    /* --- infos pratiques ----------------------------------------- */
    "infos.titre": ["Informations pratiques", "Practical information"],
    "infos.horaires": ["Horaires", "Opening hours"],
    "infos.adresse": ["Adresse", "Address"],
    "infos.telephone": ["Téléphone", "Phone"],
    "infos.wifi": ["Wi-Fi", "Wi-Fi"],
    "infos.hotel": ["Notre hôtel", "Our hotel"],
    "infos.motDePasse": ["mot de passe", "password"],
    "infos.telecharger": ["Télécharger le PDF", "Download the PDF"],

    /* --- divers --------------------------------------------------- */
    "ui.pleinEcranAstuce": [
      "Plein écran. Touchez ⤢ en haut pour en sortir.",
      "Full screen. Tap ⤢ at the top to exit."
    ],
    "ui.apercuLocal": [
      "Aperçu local — les clients voient encore la version publiée.",
      "Local preview — customers still see the published version."
    ],
    "ui.apercuRevenir": ["Revenir", "Go back"]
  };

  let langue = "fr";

  function detecter() {
    try {
      const choisi = localStorage.getItem(CLE);
      if (LANGUES.includes(choisi)) return choisi;
    } catch (_) {
      /* stockage refusé : on suit le téléphone */
    }
    const reglages = navigator.languages && navigator.languages.length
      ? navigator.languages
      : [navigator.language || "fr"];
    for (const l of reglages) {
      const court = String(l).slice(0, 2).toLowerCase();
      if (LANGUES.includes(court)) return court;
    }
    // Ni français ni anglais dans les réglages : l'anglais est le plus
    // sûr pour un visiteur étranger.
    return "en";
  }

  function T(cle, secours) {
    const e = DICO[cle];
    if (!e) return secours === undefined ? cle : secours;
    return e[langue === "en" ? 1 : 0] || e[0];
  }

  /** Remplace les textes de la page portant un `data-t`. */
  function appliquerDOM(racine) {
    (racine || document).querySelectorAll("[data-t]").forEach((el) => {
      const cle = el.getAttribute("data-t");
      const ou = el.getAttribute("data-t-attr");
      const valeur = T(cle, null);
      if (valeur === null) return;
      if (ou) el.setAttribute(ou, valeur);
      else el.textContent = valeur;
    });
    document.documentElement.lang = langue;
  }

  return {
    T,
    langue: () => langue,
    estAnglais: () => langue === "en",
    autre: () => (langue === "en" ? "fr" : "en"),

    init() {
      langue = detecter();
      appliquerDOM();
      return langue;
    },

    /** Bascule et mémorise le choix — il prime ensuite sur le téléphone. */
    basculer(vers) {
      langue = LANGUES.includes(vers) ? vers : langue === "en" ? "fr" : "en";
      try {
        localStorage.setItem(CLE, langue);
      } catch (_) {
        /* le choix ne survivra pas à la fermeture, tant pis */
      }
      appliquerDOM();
      document.dispatchEvent(new CustomEvent("langue:change", { detail: langue }));
      return langue;
    },

    appliquerDOM
  };
})();
