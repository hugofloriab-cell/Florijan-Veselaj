# Sondes de température autonomes

Enregistreurs de température sur piles pour les enceintes froides du petit
déjeuner, qui déversent leurs relevés directement dans la fiche
(`checklist-petit-dejeuner.html`, section **2. Sondes de température**).

| Objectif demandé | Ce que fait le montage |
| --- | --- |
| Relevé toutes les 30 minutes | Oui, cadence tenue même sans tablette à portée |
| Envoi direct dans l'application | Oui, en Bluetooth, sans serveur ni compte |
| Autonomie de plusieurs mois | **18 à 24 mois** sur 3 piles AA lithium |
| Alerte de pile faible | Oui, dans la fiche ; en temps réel avec l'option Wi-Fi |
| Suivi de l'autonomie | Oui, autonomie restante estimée sur la pente de décharge réelle |

---

## 1. Le choix technique, et pourquoi

### Bluetooth plutôt que Wi-Fi

La fiche est une page autonome : pas de serveur, pas de compte, tout reste sur
la tablette. Une sonde Wi-Fi doit envoyer ses relevés *quelque part* — il
faudrait donc monter et maintenir un serveur, ce qui change la nature du projet
et son coût d'exploitation.

En Bluetooth, la sonde parle directement à la tablette : rien à héberger, rien
à payer, et les données ne sortent jamais de l'hôtel.

Le Bluetooth coûte aussi bien moins cher en énergie. Un envoi Wi-Fi complet
(association, DHCP, TLS) consomme autant qu'une centaine de fenêtres Bluetooth.

### Enregistreur plutôt qu'émetteur

La sonde ne diffuse pas en continu : elle **mesure et stocke**, puis n'allume sa
radio que 15 secondes toutes les 30 minutes. La tablette vient chercher
l'historique une fois par jour.

Conséquence importante : **la cadence de 30 minutes est tenue même si personne
n'est là**. Un week-end sans ouvrir la tablette ne crée aucun trou — la sonde
garde 10 jours de relevés en réserve.

### Le boîtier dehors, le capteur dedans

C'est le point qui fait la différence entre un montage qui marche et un qui
déçoit :

- le 2,4 GHz traverse très mal une porte de congélateur (tôle + mousse) : de
  l'intérieur, la portée tombe souvent à quelques dizaines de centimètres ;
- une pile à −23 °C perd l'essentiel de sa capacité et de sa tension utile.

On place donc le **boîtier à l'extérieur**, aimanté sur la porte, et on fait
passer le seul câble de la sonde sous le joint. L'électronique et les piles
restent à température ambiante, la portée reste bonne, et l'autonomie annoncée
est celle qu'on obtient réellement.

### Ce que ce montage ne fait pas

À dire franchement, pour éviter une mauvaise surprise :

- **Pas d'alerte en temps réel la nuit**, en Bluetooth seul. Si un congélateur
  lâche à 3 h du matin, la sonde enregistre tout et la fiche l'affiche en rouge
  au premier relevé du matin — mais personne n'est réveillé. L'option Wi-Fi du
  § 7 lève cette limite pour environ 0 € de plus.
- **Ce n'est pas un enregistreur certifié NF EN 12830.** Voir § 9 : à traiter
  comme un outil de surveillance qui complète le relevé officiel, pas comme un
  matériel qui le remplace de plein droit.
- **Les relevés non synchronisés sont perdus si on retire les piles.** D'où la
  consigne : synchroniser avant de changer les piles. La fiche prévient
  plusieurs semaines à l'avance.

### La voie courte, si vous préférez ne rien fabriquer

Des enregistreurs Bluetooth tout faits existent (SensorPush, Elitech, Testo
174 T, Inkbird), entre 25 et 90 € pièce. Ils sont excellents, mais leurs
protocoles sont fermés : ils fonctionnent avec **leur** application, pas avec la
vôtre. Le double emploi — leur appli pour les relevés, la vôtre pour la
check-list — est précisément ce que ce projet évite.

Si l'intégration dans la fiche n'est finalement pas indispensable, un Testo
174 T reste le choix le plus simple et le plus défendable en contrôle.

---

## 2. Nomenclature — prototype (1 sonde)

Version à monter sur plaque à trous, sans circuit imprimé à faire fabriquer.
C'est celle à commander **en premier**, en un seul exemplaire, pour valider la
portée dans votre cuisine avant d'en faire dix.

Prix indicatifs, hors frais de port, à vérifier au moment de commander.

| # | Désignation | Référence | Où | Qté | ~ PU |
| --- | --- | --- | --- | --- | --- |
| 1 | Carte microcontrôleur Wi-Fi + Bluetooth 5 | **Seeed XIAO ESP32C3** (SKU 113991054) | Mouser, Digi-Key, Seeed | 1 | 5,50 € |
| 2 | Sonde de température étanche inox Ø6 × 50 mm, câble 2 m | **DS18B20 waterproof 2 m** | Amazon, AZ-Delivery, Reichelt | 1 | 4,50 € |
| 3 | Résistance 4,7 kΩ ±1 % 1/4 W (rappel 1-Wire) | — | Mouser, Farnell | 1 | 0,10 € |
| 4 | Résistance 1 MΩ ±1 % 1/4 W (pont de mesure pile) | — | idem | 2 | 0,10 € |
| 5 | Résistance 1 MΩ ±5 % (rappel de l'ILS) | — | idem | 1 | 0,10 € |
| 6 | Transistor MOSFET canal N, seuil logique | **2N7002** (ou BSS138) | Mouser | 1 | 0,15 € |
| 7 | Condensateur céramique 100 nF X7R 50 V | — | idem | 1 | 0,10 € |
| 8 | Condensateur 220 µF 10 V (réserve pour les pics radio) | — | idem | 1 | 0,40 € |
| 9 | Diode Schottky (anti-inversion, isole l'USB des piles) | **1N5819** | idem | 1 | 0,15 € |
| 10 | ILS — interrupteur à lame souple, verre 2 × 14 mm, normalement ouvert | générique « reed switch NO » | Amazon, Farnell | 1 | 1,50 € |
| 11 | Aimant néodyme Ø10 × 3 mm (déclenche la synchronisation) | — | — | 1 | 0,60 € |
| 12 | Coupleur 3 × AA avec fils | type **Keystone 2478** | Mouser, Farnell | 1 | 2,00 € |
| 13 | Piles AA lithium **−40 à +60 °C** | **Energizer Ultimate Lithium L91** | grande surface, Amazon | 3 | 2,00 € |
| 14 | Boîtier étanche IP65, env. 100 × 70 × 50 mm | Hammond 1554 ou Gainta G2xx | Mouser, Farnell | 1 | 8,00 € |
| 15 | Presse-étoupe M12 IP68 (sortie du câble de sonde) | — | — | 1 | 0,80 € |
| 16 | Plaque à trous 50 × 70 mm + fil câblé 0,25 mm² | — | — | 1 | 1,00 € |
| 17 | Aimants adhésifs Ø20 mm ou adhésif **3M VHB 4941** | — | — | 2 | 2,00 € |

**Total ≈ 33 € la sonde.**

### Ne pas se tromper sur les piles

Le poste où l'économie se paie cher. **Prendre des AA lithium (Li-FeS₂),
pas des alcalines** :

| | Alcaline AA | **Lithium AA (L91)** | LiPo rechargeable |
| --- | --- | --- | --- |
| Plage de service | 0 à +50 °C | **−40 à +60 °C** | 0 à +45 °C en charge |
| Capacité à faible débit | ~2 700 mAh | **~3 000 mAh** | 1 000–2 500 mAh |
| Tenue en tension | s'affaisse tôt | **palier très plat** | plat |
| Fuites en cuisine | fréquentes après 2 ans | **très rares** | sans objet |
| Autonomie ici | 12–15 mois | **18–24 mois** | 4–8 mois |

Vous parliez de **recharger** les sondes : avec 3 AA lithium, le sujet
disparaît. On remplace 6 € de piles tous les 18 à 24 mois, sans démonter la
sonde de sa porte, sans immobiliser un chargeur, et sans le risque d'un accu
lithium-ion en cuisine. Les piles s'achètent dans n'importe quel commerce de
Sisteron le jour où la fiche prévient.

Un accu rechargeable reste possible (18650 + convertisseur TPS63020 + module de
charge TP4056, environ +8 €), mais il divise l'autonomie par trois, impose un
démontage tous les 4 à 8 mois, et interdit toute charge sous 0 °C.

### Outillage et étalonnage

À prévoir une fois, pas par sonde :

- fer à souder fin, étain, pince coupante, gaine thermorétractable ;
- câble USB-C (téléversement du programme) ;
- multimètre (vérification du pont diviseur) ;
- **un thermomètre de référence étalonné** — indispensable, et de toute façon
  déjà exigé par le plan de maîtrise sanitaire ;
- de la glace pilée et de l'eau, pour le point 0 °C.

---

## 3. Nomenclature — série (à partir de 10 sondes)

Une fois le prototype validé, un petit circuit imprimé divise la consommation
de veille par neuf (44 µA → 5 µA) et supprime le câblage à la main.

| Poste | Prototype | Série |
| --- | --- | --- |
| Microcontrôleur | XIAO ESP32C3 (carte toute faite) | **ESP32-C3-MINI-1-N4** (module nu) — 2,30 € |
| Alimentation | régulateur de la carte, 44 µA au repos | **TPS7A0233PDBVR** (25 nA au repos) — 1,00 € |
| Horloge | oscillateur RC interne, dérive quelques % | **quartz 32,768 kHz** (ABS07-32.768KHZ-T) + 2 × 12 pF — 0,60 € |
| Assemblage | plaque à trous, ~45 min par sonde | PCB 2 couches 40 × 60 mm, assemblé (JLCPCB) — ~12 €/pièce pour 10 |
| Veille | 44 µA | **5 µA** |
| Autonomie | 18–24 mois | **~2,7 ans** |

Le quartz n'est pas indispensable — la fiche corrige la dérive après coup
(§ 6 du `PROTOCOLE-BLE.md`) — mais il rend les horodatages exacts à la seconde,
ce qui est plus confortable à présenter en cas de contrôle.

Coût série ≈ **22 à 26 € la sonde**, tout compris.

---

## 4. Câblage

Broches de la carte XIAO ESP32C3. Les GPIO 0 à 5 sont les seules à pouvoir
réveiller l'ESP32-C3 depuis la veille profonde : l'ILS doit rester dans cette
plage.

```
        3 × AA lithium (4,5 V)
              │
              ├──►│──┬────────────────► XIAO, pastille 5V
             1N5819 │
                   ═╪═ 220 µF
                    │
                   ─┴─ masse commune ──► XIAO, pastille GND


   Mesure de la pile — le pont n'est fermé que pendant la mesure,
   sinon ses 2 MΩ consommeraient plus que l'ESP32 endormi :

        4,5 V ──┬── 1 MΩ ──┬── 1 MΩ ──┬── drain 2N7002
                           │          │
                    D1 (GPIO3) ◄──────┤   source ── masse
                           │              grille ◄── D10 (GPIO10)
                          ═╪═ 100 nF


   Sonde DS18B20 (3 fils, câble 2 m) :

        rouge  ──────────────────────► D6  (GPIO21)   alimentation commutée
        jaune  ──┬───────────────────► D3  (GPIO5)    données 1-Wire
                 └── 4,7 kΩ ── rouge
        noir   ──────────────────────► GND


   Réveil manuel — l'aimant approché du boîtier ferme l'ILS :

        3,3 V ── 1 MΩ ──┬────────────► D2  (GPIO4)
                        │
                       ILS
                        │
                       GND
```

Trois détails qui comptent :

- **Le DS18B20 est alimenté par une broche** (D6), pas par le 3,3 V permanent.
  Hors mesure, il ne consomme rien du tout.
- **La diode 1N5819** évite deux ennuis : une inversion de piles, et surtout le
  retour du 5 V USB dans le coupleur si l'on branche l'ordinateur en laissant
  les piles en place.
- **Le condensateur de 220 µF** encaisse les pointes de courant de l'émission
  radio. Sans lui, la tension s'effondre en fin de vie des piles et la sonde
  redémarre en boucle.

---

## 5. Programmation

1. Installer **Arduino IDE 2.x**, puis, dans *Outils → Type de carte →
   Gestionnaire de cartes*, le paquet **esp32 by Espressif Systems** (version
   3.x). Choisir la carte **XIAO_ESP32C3**.
2. Dans *Outils → Gérer les bibliothèques*, installer **OneWire** (Paul
   Stoffregen) et **DallasTemperature** (Miles Burton).
3. Ouvrir `firmware/sonde-haccp/sonde-haccp.ino`.
4. Modifier **`config.h`** — c'est le seul fichier à toucher :
   - `EMPLACEMENT` : `"Chambre froide"`, `"Congel coffre"`, `"Banque froide"`…
   - `SEUIL_MIN_CENTI` / `SEUIL_MAX_CENTI` : `100` / `400` pour une enceinte
     positive (+1 à +4 °C), `-2300` / `-1800` pour une négative (−23 à −18 °C).
     Ce sont les normes déjà inscrites sur la fiche.
5. Téléverser. Si la carte n'est pas détectée : maintenir **BOOT**, appuyer
   brièvement sur **RESET**, relâcher BOOT.
6. Pour un premier essai, mettre `TRACE` à `1` dans `config.h` et ouvrir le
   moniteur série à 115200 bauds : chaque réveil affiche température, tension,
   nombre de relevés en attente.

**Remettre `TRACE` à `0` avant la mise en service** : l'initialisation du port
série allonge le temps de réveil à chaque cycle.

### Étalonnage

À faire une fois par sonde, à refaire une fois par an — cette vérification
périodique fait partie du plan de maîtrise sanitaire, sonde maison ou non.

1. Remplir un verre de glace pilée, compléter avec un peu d'eau, remuer.
   Le bain est à 0,0 °C tant qu'il reste de la glace.
2. Y plonger la sonde inox **et** le thermomètre de référence, attendre 5 min.
3. Passer l'aimant sur le boîtier, synchroniser depuis la fiche, lire la valeur.
4. L'écart donne l'offset : sonde à **+0,4 °C** pour une référence à 0,0 °C
   → `OFFSET_ETALONNAGE_CENTI` = **−40**. Reprogrammer, ou envoyer la
   commande `0x05` depuis la fiche (bouton *Étalonner*).
5. Noter la date et l'écart dans le registre — c'est ce qu'on vous demandera.

---

## 6. Autonomie — le calcul

Consommation de la version prototype, 15 secondes d'annonce toutes les
30 minutes :

| Poste | Courant | Durée par jour | Coût par jour |
| --- | --- | --- | --- |
| Veille profonde | 44 µA | 23 h 47 | 1,06 mAh |
| Réveil + mesure DS18B20 (48 ×) | 25 mA | 58 s | 0,40 mAh |
| Fenêtres d'annonce (48 × 15 s) | 11 mA | 12 min | 2,20 mAh |
| Synchronisation quotidienne | 30 mA | 20 s | 0,17 mAh |
| **Total** | | | **≈ 3,8 mAh** |

3 piles L91 en série fournissent 3 000 mAh, dont environ 2 850 exploitables
avant le décrochage du régulateur :

**2 850 ÷ 3,8 ≈ 750 jours, soit à peu près deux ans.**

Le poste dominant est la fenêtre d'annonce, et c'est le seul levier qui compte :

| `FENETRE_ANNONCE_S` | Consommation | Autonomie | Confort de synchronisation |
| --- | --- | --- | --- |
| 30 s | 6,0 mAh/j | 16 mois | la tablette accroche du premier coup |
| **15 s** (par défaut) | **3,8 mAh/j** | **24 mois** | bon compromis |
| 8 s | 2,7 mAh/j | 34 mois | il faut parfois passer l'aimant |
| 0 s (aimant seul) | 1,6 mAh/j | 4,8 ans | synchronisation toujours manuelle |

Dans tous les cas on est très au-delà des « quelques mois » demandés. L'aimant
reste disponible en permanence : même à 0 seconde d'annonce, un passage
d'aimant ouvre immédiatement une fenêtre de 2 minutes.

Ces chiffres sont des estimations calculées, pas des mesures. Comptez une
marge : la première sonde vous donnera le chiffre réel, que la fiche affichera
ensuite d'elle-même à partir de la pente de décharge observée.

---

## 7. Option Wi-Fi — l'alerte de nuit

La sonde embarque déjà le Wi-Fi : il ne coûte rien de plus à l'achat, seulement
quelques lignes de configuration.

Mettre `ALERTE_WIFI` à `1` dans `config.h` et renseigner le réseau. La sonde
allume alors le Wi-Fi **uniquement pour signaler un défaut** :

- température hors seuils sur 2 relevés consécutifs (soit 1 heure — assez pour
  ignorer une porte ouverte ou un dégivrage, assez tôt pour sauver le stock) ;
- pile passée sous 20 %.

La notification part sur **ntfy.sh**, gratuit et sans compte : on choisit un nom
de sujet long et non devinable, qui tient lieu de mot de passe, et la tablette
et les téléphones de l'équipe s'y abonnent avec l'application ntfy (Android,
iOS). L'alerte arrive en quelques secondes, écran verrouillé.

En marche normale la radio Wi-Fi n'est jamais alimentée : l'autonomie ne bouge
pas. Une enceinte réellement en panne enverra une alerte toutes les 2 heures,
soit environ 0,4 mAh par alerte — sans effet mesurable.

C'est la réponse à votre demande d'être prévenu quand une pile arrive à sec :
en Bluetooth seul, la fiche prévient dès qu'on l'ouvre ; avec le Wi-Fi, le
téléphone sonne sans rien ouvrir.

---

## 8. Mise en service

1. **Monter la sonde**, piles en place, capot fermé, presse-étoupe serré.
2. **Fixer le boîtier à l'extérieur** de l'enceinte — aimants ou VHB, à hauteur
   d'homme, hors des projections de nettoyage.
3. **Passer le câble sous le joint de porte.** Un câble de 4 mm ne compromet
   pas l'étanchéité d'un joint magnétique. Sur une chambre froide, utiliser le
   passe-câble existant.
4. **Placer l'extrémité inox** au milieu de l'enceinte, à mi-hauteur, jamais
   contre une paroi ni devant l'évaporateur. Pour une chambre froide positive,
   le point le plus chaud est le plus pertinent : c'est lui qui déclenchera.
5. **Ouvrir la fiche** sur la tablette, section *Sondes de température*,
   bouton **Appairer une sonde**.
6. **Passer l'aimant** sur le boîtier : la sonde apparaît dans la liste de
   Chrome. La sélectionner.
7. Nommer l'emplacement, choisir le type d'enceinte (positive / négative),
   valider. Les seuils se règlent tout seuls sur les normes de la fiche.
8. Laisser tourner 24 h, puis vérifier la courbe : les cycles de dégivrage
   doivent apparaître comme de brèves remontées régulières. C'est le signe que
   la sonde est bien placée.

Au quotidien, il n'y a plus qu'à appuyer sur **Relever les sondes** en fin de
service, avant de clôturer la fiche.

---

## 9. Ce que dit la réglementation

À lire avant de présenter ces sondes à un contrôle.

Le règlement **CE 852/2004** impose de **maîtriser** les températures et d'en
apporter la preuve. Il n'impose pas un matériel homologué pour
l'auto-surveillance interne : la méthode est libre, c'est le plan de maîtrise
sanitaire qui la décrit.

En revanche, la norme **NF EN 12830** définit les enregistreurs de température
pour denrées, et **NF EN 13486** leur vérification périodique. Un montage
maison, aussi soigné soit-il, **n'est pas certifié EN 12830** — impossible de
prétendre le contraire.

En pratique :

- Ces sondes sont un **outil de surveillance continue** : elles voient la nuit,
  les week-ends et les pannes lentes, que le relevé manuel biquotidien manque
  par construction.
- Elles **ne remplacent pas** le relevé officiel tant que votre plan de maîtrise
  sanitaire ne les a pas intégrées. Continuez à pointer les relevés de la fiche.
- Faites-les **valider par votre vétérinaire-conseil ou le service qualité
  Accor** avant de les inscrire au PMS. Le registre d'étalonnage annuel (§ 5)
  est ce qui rendra la démarche recevable.
- L'export CSV de la fiche est fait pour ça : il donne l'historique horodaté,
  ouvrable dans Excel, à joindre au dossier.

---

## 10. Fichiers

| Fichier | Contenu |
| --- | --- |
| `PROTOCOLE-BLE.md` | Format des trames — contrat entre la sonde et la fiche |
| `firmware/sonde-haccp/sonde-haccp.ino` | Programme de la sonde |
| `firmware/sonde-haccp/config.h` | Réglages propres à chaque sonde |

Côté fiche, tout est dans `checklist-petit-dejeuner.html`, bloc
`/* ============ Sondes ============ */`.

> **Le firmware n'a pas été essayé sur du matériel réel** — il n'y en avait pas
> ici. Il est écrit pour compiler et fonctionner tel quel, mais comptez une
> séance de mise au point sur la première sonde. Le mode `TRACE` est là pour ça.
>
> Pour essayer l'application **sans attendre les composants** : ouvrez la fiche
> avec `?demo=1` à la fin de l'adresse. Deux sondes fictives apparaissent, avec
> une semaine de relevés et un incident de congélateur, ce qui permet de valider
> l'écran, les alertes et l'export avant de souder quoi que ce soit.
