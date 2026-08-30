/* config.h — réglages propres à chaque sonde.
 *
 * C'est le seul fichier à modifier avant de téléverser. Une sonde = une copie
 * de ce fichier avec son emplacement et son offset d'étalonnage.
 */
#pragma once

/* ---------- Identité ---------- */

/* Libellé d'emplacement, 16 caractères maximum. Il apparaît tel quel dans la
   fiche. Exemples : "Chambre froide", "Congel coffre", "Banque froide". */
#define EMPLACEMENT "Chambre froide"

/* ---------- Cadence ---------- */

/* Intervalle entre deux mesures, en minutes. 30 = exigence de la fiche.
   Modifiable à distance par la commande 0x04. */
#define INTERVALLE_MINUTES 30

/* Durée de la fenêtre d'annonce automatique, en secondes, à chaque mesure.
   C'est le poste de consommation dominant : 15 s coûte environ 2,4 mAh/jour,
   30 s en coûte le double. En dessous de 10 s la tablette a du mal à
   accrocher la sonde. */
#define FENETRE_ANNONCE_S 15

/* Durée de la fenêtre ouverte par l'aimant ou le bouton, en secondes.
   Laisse le temps de choisir la sonde dans la liste de Chrome. */
#define FENETRE_MANUELLE_S 120

/* ---------- Seuils HACCP ---------- */

/* Bornes de conformité, en centièmes de degré.
   Enceinte positive (frigo, chambre froide) :  +100 à  +400  (+1 à +4 °C)
   Enceinte négative (congélateur)            : -2300 à -1800 (-23 à -18 °C)
   Ils ne servent qu'à lever le drapeau ALERTE_T et à déclencher l'alerte
   Wi-Fi ; la fiche refait le contrôle de son côté. */
#define SEUIL_MIN_CENTI 100
#define SEUIL_MAX_CENTI 400

/* ---------- Étalonnage ---------- */

/* Correction ajoutée à chaque mesure, en centièmes de degré.
   Se détermine dans un bain d'eau glacée : si la sonde affiche +0,4 °C là où
   la référence donne 0,0 °C, mettre -40. Voir « Étalonnage » dans le README.
   Réglable à distance par la commande 0x05. */
#define OFFSET_ETALONNAGE_CENTI 0

/* ---------- Pile ---------- */

/* Pack de 3 piles AA lithium (Energizer L91), mesuré avant le régulateur.
   Tension à vide d'une L91 neuve : 1,80 V ; palier de service : ~1,55 V ;
   fin de vie exploitable : ~1,15 V (le régulateur décroche en dessous). */
#define PILE_PLEINE_MV 4900
#define PILE_VIDE_MV   3450

/* Seuil sous lequel le drapeau PILE_FAIBLE est levé, en pourcentage.
   20 % d'un pack L91 laisse plusieurs semaines pour intervenir. */
#define PILE_FAIBLE_PCT 20

/* Rapport du pont diviseur (deux résistances de 1 MΩ = 2,0).
   À ajuster si vous mesurez un écart au multimètre. */
#define PONT_RAPPORT 2.0f

/* ---------- Alerte Wi-Fi (optionnelle) ---------- */

/* Mettre à 1 pour que la sonde allume le Wi-Fi et pousse une notification
   quand la température sort des seuils ou que la pile faiblit — y compris la
   nuit, tablette éteinte. Coût : quelques réveils Wi-Fi par an, invisible sur
   l'autonomie tant que l'enceinte est conforme.
   Une enceinte réellement en panne enverra une alerte toutes les 2 h : compter
   environ 0,4 mAh par alerte. */
#define ALERTE_WIFI 0

#if ALERTE_WIFI
  #define WIFI_SSID "NOM_DU_RESEAU"
  #define WIFI_MDP  "MOT_DE_PASSE"

  /* Service de notification. ntfy.sh est gratuit et sans compte : choisissez
     un nom de sujet long et non devinable, il tient lieu de mot de passe.
     La tablette et les téléphones s'y abonnent via l'application ntfy. */
  #define NTFY_SUJET "ibis-sisteron-froid-7f3a91c2"

  /* Délai minimal entre deux alertes pour un même défaut, en minutes. */
  #define ALERTE_REPOS_MINUTES 120

  /* Nombre de mesures consécutives hors seuils avant d'alerter. À 30 minutes
     d'intervalle, 2 mesures = 1 heure : assez pour ignorer une porte ouverte
     ou un cycle de dégivrage, assez tôt pour sauver la marchandise. */
  #define ALERTE_MESURES_CONSECUTIVES 2
#endif

/* ---------- Brochage (carte Seeed XIAO ESP32C3) ---------- */

/* Attention : seules les GPIO 0 à 5 réveillent l'ESP32-C3 depuis la veille
   profonde. L'ILS doit donc rester dans cette plage. GPIO2 est une broche de
   « strapping » au démarrage : on l'évite. */
#define BROCHE_ILS         4   /* D2  — ILS/bouton vers la masse            */
#define BROCHE_PILE        3   /* D1  — milieu du pont diviseur (ADC1)      */
#define BROCHE_PONT       10   /* D10 — grille du MOSFET, ferme le pont     */
#define BROCHE_1WIRE       5   /* D3  — données DS18B20                     */
#define BROCHE_CAPTEUR_VCC 21  /* D6  — alimentation commutée du DS18B20    */

/* ---------- Mémoire ---------- */

/* Nombre de relevés gardés en mémoire RTC. 512 × 8 octets = 4 Ko.
   À 30 minutes d'intervalle : 10,6 jours de réserve avant débordement. */
#define CAPACITE_TAMPON 512

/* ---------- Mise au point ---------- */

/* 1 = trace sur le port série (115200 bauds). À laisser à 0 en service :
   l'initialisation du port série coûte quelques dizaines de millisecondes
   éveillé à chaque réveil. */
#define TRACE 0
