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
   Laisse le temps de choisir la sonde dans la liste. */
#define FENETRE_MANUELLE_S 120

/* N'ouvrir une fenêtre radio qu'un réveil sur N. Mesurer coûte presque rien,
   émettre coûte tout : ce réglage permet de garder un relevé toutes les
   30 minutes — ce qu'exige la fiche — en ne parlant que quelques fois par jour.

     1  → une fenêtre à chaque mesure (48/jour)   ~3,8 mAh/jour
     6  → une fenêtre toutes les 3 h (8/jour)     ~2,0 mAh/jour
    12  → une fenêtre toutes les 6 h (4/jour)     ~1,8 mAh/jour

   L'aimant ouvre toujours une fenêtre, quel que soit ce réglage : la
   synchronisation quotidienne reste immédiate. Une température hors seuils en
   ouvre une aussi, pour que l'écart puisse être vu sans attendre. */
#define ANNONCE_UN_CYCLE_SUR 6

/* Puissance d'émission Bluetooth. C'est le pic de courant à l'émission — plus
   de 100 mA par bouffée — qui fait décrocher une alimentation juste : la carte
   redémarre alors en boucle pendant la fenêtre d'annonce, avec un
   POWERON_RESET dans la trace.

   Baisser la puissance réduit ce pic, et consomme moins. On perd de la portée,
   mais une sonde aimantée sur une porte de frigo n'a que quelques mètres à
   couvrir.

     ESP_PWR_LVL_P9    +9 dBm   portée maximale, pic le plus fort
     ESP_PWR_LVL_P3    +3 dBm   réglage par défaut du cœur Arduino
     ESP_PWR_LVL_N0     0 dBm   bon compromis, portée ~10 m
     ESP_PWR_LVL_N9    -9 dBm   pour une alimentation fragile, portée ~3 m
     ESP_PWR_LVL_N12  -12 dBm   minimum

   Si la carte redémarre en boucle, descendez d'un cran. */
#define PUISSANCE_BLE ESP_PWR_LVL_N0

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

/* Bornes de la source d'énergie, mesurées avant le régulateur. Deux montages
   sont prévus : gardez celui qui correspond au vôtre, commentez l'autre.

   A — 3 piles AA lithium (Energizer L91), le montage de la nomenclature.
       Tension à vide d'une L91 neuve : 1,80 V ; palier de service : ~1,55 V ;
       fin de vie exploitable : ~1,15 V (le régulateur décroche en dessous).
       Environ deux ans d'autonomie, remplacement en trente secondes. */
#define PILE_PLEINE_MV 4900
#define PILE_VIDE_MV   3450

/* B — accu lithium rechargeable à un élément (18650, LiPo) avec un module de
       charge TP4056. 4,20 V à pleine charge ; on s'arrête à 3,40 V : en
       dessous le régulateur décroche, et la décharge profonde abîme l'accu.
       Décommentez ces deux lignes et commentez les deux précédentes.

#define PILE_PLEINE_MV 4200
#define PILE_VIDE_MV   3400
*/

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

/* ---------- Carte et brochage ---------- */

/* Le programme s'adapte à la puce choisie dans l'IDE Arduino. Deux familles
   sont gérées :

     ESP32-C3  — Seeed XIAO ESP32C3, ESP32-C3 SuperMini.  Veille 5 à 44 µA.
                 C'est la cible de la nomenclature : autonomie de deux ans.

     ESP32     — DevKit V1, NodeMCU-32S, WROOM-32 en général.  Parfaite pour
                 mettre au point sur l'établi, mais sa veille se compte en
                 milliampères à cause du régulateur, de la LED d'alimentation
                 et de la puce USB restés alimentés : quelques jours d'autonomie
                 sur accu, pas quelques mois. Voir « Cartes ESP32 DevKit » dans
                 le README avant de la mettre en service sur batterie.

   Les broches sont choisies pour respecter trois contraintes : réveil possible
   depuis la veille profonde (broches RTC), convertisseur ADC1 utilisable
   pendant que la radio émet, et broches de « strapping » évitées. */

#if defined(CONFIG_IDF_TARGET_ESP32C3)

  /* Seules les GPIO 0 à 5 réveillent l'ESP32-C3 : l'ILS doit y rester.
     GPIO2 est une broche de strapping au démarrage, on l'évite. */
  #define BROCHE_ILS         4   /* D2  — ILS/bouton vers la masse          */
  #define BROCHE_PILE        3   /* D1  — milieu du pont diviseur (ADC1)    */
  #define BROCHE_PONT       10   /* D10 — grille du MOSFET, ferme le pont   */
  #define BROCHE_1WIRE       5   /* D3  — données DS18B20                   */
  #define BROCHE_CAPTEUR_VCC 21  /* D6  — alimentation commutée du capteur  */

#elif defined(CONFIG_IDF_TARGET_ESP32)

  /* GPIO33 est une broche RTC : elle sait réveiller la puce (ext0).
     GPIO34 est en entrée seule, sans rappel interne — idéal pour un pont
     diviseur, et sur ADC1, le seul convertisseur utilisable radio allumée.
     GPIO 0, 2, 12 et 15 sont des broches de strapping : écartées.
     GPIO4 (D4) porte les données 1-Wire : broche ordinaire, sans contrainte. */
  #define BROCHE_ILS        33
  #define BROCHE_PILE       34   /* ADC1_CH6, entrée seule                  */
  #define BROCHE_PONT       25
  #define BROCHE_1WIRE       4   /* D4  — données DS18B20 (fil jaune)       */
  #define BROCHE_CAPTEUR_VCC -1  /* fil rouge sur 3V3 : rien à commuter     */

#else
  #error "Puce non gérée. Choisissez une carte ESP32 ou ESP32-C3 dans l'IDE."
#endif

/* BROCHE_CAPTEUR_VCC à -1 signifie : le fil rouge du DS18B20 est câblé sur
   3V3 en permanence, le programme ne commute rien. C'est le montage le plus
   naturel à souder à la main, et il ne coûte que le microampère consommé par
   le capteur au repos — négligeable devant tout le reste.

   Pour gagner ce microampère, câblez le fil rouge sur une broche ordinaire
   (GPIO19 par exemple) et indiquez-la ici à la place de -1. */

/* Mettre à 0 tant que l'ILS n'est pas câblé. Une broche de réveil laissée en
   l'air déclenche des réveils parasites qui vident les piles — et sur
   l'établi, l'ILS est justement ce qu'on n'a pas encore soudé. */
#define REVEIL_MANUEL_ACTIF 1

/* ---------- Mémoire ---------- */

/* Nombre de relevés gardés en mémoire RTC. 512 × 8 octets = 4 Ko.
   À 30 minutes d'intervalle : 10,6 jours de réserve avant débordement. */
#define CAPACITE_TAMPON 512

/* ---------- Mise au point ---------- */

/* 1 = trace sur le port série (115200 bauds). À laisser à 0 en service :
   l'initialisation du port série coûte quelques dizaines de millisecondes
   éveillé à chaque réveil. */
#define TRACE 0

/* ---------- Banc d'essai ---------- */

/* Mettre à 1 pour la mise au point sur l'établi, avant d'avoir soudé l'ILS,
   le pont de mesure et la batterie. Ce mode :

     - mesure toutes les minutes au lieu de 30, pour ne pas attendre ;
     - laisse la radio allumée 60 s par cycle, le temps de trouver la sonde ;
     - écrit la trace sur le port série ;
     - coupe le réveil par aimant — une broche de réveil en l'air déclenche
       des réveils parasites ;
     - ouvre une fenêtre radio à chaque cycle, pour que l'appairage d'essai ne
       demande pas d'attendre ;
     - annonce une batterie pleine, le pont diviseur n'étant pas encore câblé.

   À REMETTRE À 0 AVANT LA MISE EN SERVICE : laissé à 1, il ramène l'autonomie
   de deux ans à quelques semaines. La fiche affiche un avertissement tant
   qu'une sonde annonce une cadence de banc d'essai. */
#define MODE_BANC 1

#if MODE_BANC
  #undef  INTERVALLE_MINUTES
  #define INTERVALLE_MINUTES 1
  #undef  FENETRE_ANNONCE_S
  #define FENETRE_ANNONCE_S 60
  #undef  REVEIL_MANUEL_ACTIF
  #define REVEIL_MANUEL_ACTIF 0
  #undef  ANNONCE_UN_CYCLE_SUR
  #define ANNONCE_UN_CYCLE_SUR 1
  #undef  TRACE
  #define TRACE 1
  #define PILE_SIMULEE 1
#else
  #define PILE_SIMULEE 0
#endif
