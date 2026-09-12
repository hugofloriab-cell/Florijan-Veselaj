# Premier essai sur l'établi

À faire **avant** de souder quoi que ce soit dans un boîtier : valider la chaîne
complète — capteur, radio, tablette — avec la carte simplement branchée en USB.

Une heure suffit. Vous avez déjà tout le nécessaire.

---

## 1. Ce qu'il faut, et ce qu'il ne faut pas encore

| Nécessaire maintenant | Pas encore |
| --- | --- |
| La carte ESP32 | La batterie et son module de charge |
| La sonde DS18B20 étanche | Le MOSFET et les résistances de 1 MΩ |
| La résistance de 4,7 kΩ | L'ILS et l'aimant |
| Un câble USB et un ordinateur | Le boîtier et le presse-étoupe |
| Une plaque d'essai ou trois fils | Le fer à souder |

Le mode banc d'essai du programme est fait pour ça : il neutralise tout ce qui
n'est pas encore câblé.

## 2. Alimentation

Pour ce premier essai, **alimentez la carte par son port USB-C**, batterie
débranchée. C'est plus simple, et cela évite le piège ci-dessous.

Pour le montage sur accu : `OUT+` du TP4056 vers `VIN`, `OUT-` vers `GND`.

> ### ⚠ Ne jamais brancher l'USB pendant que l'accu est relié à `VIN`
>
> Sur la plupart des cartes DevKit, le 5 V de l'USB et la broche `VIN` sont sur
> le même réseau, parfois sans diode de séparation selon la version. Le 5 V
> remonte alors dans la sortie du TP4056 et pousse du courant dans l'accu à
> travers les transistors de protection, hors de tout contrôle de charge. Sur
> un accu LiPo souple, c'est un risque d'emballement thermique.
>
> **Débranchez l'accu avant de brancher l'USB**, et inversement. C'est une
> règle simple qui vaut quelle que soit la version de votre carte.

Enfin, sachez ce que donne `VIN` sur cette carte : le régulateur AMS1117 a
besoin d'environ 1 V de plus en entrée qu'en sortie. Un accu plein (4,2 V)
passe ; vers 3,7 V la marge disparaît et la carte redémarre en boucle. Vous
n'exploiterez donc qu'environ la moitié de la capacité de l'accu — ce qui,
avec la veille de 5 à 15 mA d'une DevKit, ne change pas grand-chose : voir
« Si vous partez d'une carte ESP32 DevKit » dans le [README](README.md).

## 3. Câblage de la sonde — trois fils et une résistance

Le DS18B20 sort trois fils. **Le code couleur est le point où tout le monde se
trompe**, parce qu'il n'est pas intuitif :

| Fil | Rôle | Va sur |
| --- | --- | --- |
| **rouge** | alimentation (VDD) | `3V3` |
| **jaune** | **données** (1-Wire) | `D4` |
| **noir** | masse (GND) | `GND` |

Le **jaune porte les données**, pas la masse. Le **noir est la masse**, comme
partout ailleurs en électricité. Inverser les deux ne marche pas et peut abîmer
le capteur : sa masse se retrouve sur une sortie logique, et sa ligne de données
sous sa propre masse quand la broche passe à l'état haut.

La résistance de 4,7 kΩ se monte entre le **rouge et le jaune** — entre
l'alimentation et les données. Sans elle, la ligne reste à zéro et le capteur
ne répond jamais.

```
   DS18B20                     ESP32 (DevKit / WROOM-32)

   rouge  ───────────────────► 3V3
            │
          4,7 kΩ
            │
   jaune  ──┴────────────────► D4   (GPIO4, données 1-Wire)

   noir   ───────────────────► GND
```

Sur une carte **ESP32-C3** (XIAO, SuperMini), les données vont sur GPIO5 — le
programme s'adapte tout seul, seules les broches physiques changent. Le détail
est dans `config.h`.

> **Si la trace affiche `T=-32768`**, c'est presque toujours le code couleur.
> Les sondes bon marché n'utilisent pas toutes les mêmes teintes : sur
> certaines le fil de données est blanc, bleu ou vert. Le rouge reste
> l'alimentation et le noir la masse ; en cas de doute, essayez le troisième
> fil sur `D4` et remettez les deux autres sur `3V3` et `GND`.

## 4. Où écrire et téléverser le programme

### Xcode ne flashe pas la sonde — ce sont deux moitiés séparées

Point de confusion fréquent, et il vaut mieux l'avoir en tête dès le départ :
ce projet a **deux moitiés qui ne partagent aucun outil**.

| | La sonde | L'application iPhone |
| --- | --- | --- |
| Langage | C++ (Arduino) | Swift / SwiftUI |
| Outil | **Arduino IDE** | **Xcode** |
| Fichiers | `firmware/sonde-haccp/` | `ios/SondesHACCP/` |
| Ce qu'on en fait | on téléverse dans l'ESP32 | on installe sur l'iPhone |

Xcode ne sait pas programmer un ESP32, et Arduino IDE ne sait pas fabriquer une
application iOS. Il n'existe pas d'outil « compatible avec les deux », et ce
n'est pas un manque : les deux moitiés ne se rencontrent qu'en Bluetooth, à
l'exécution, à travers le protocole décrit dans `PROTOCOLE-BLE.md`.

Concrètement, vous installerez les deux logiciels sur le Mac. Arduino IDE sert
une fois par sonde ; Xcode sert à l'application.

### Les trois façons de téléverser

Par ordre de commodité :

| Outil | Où | Remarque |
| --- | --- | --- |
| **Arduino IDE 2.x** | Application à installer, macOS / Windows / Linux | **Le choix recommandé.** Moniteur série intégré, c'est lui qu'on utilise ci-dessous. <https://www.arduino.cc/en/software> |
| **Arduino Cloud Editor** | Dans le navigateur, <https://app.arduino.cc/sketches> | Pratique sur un poste où l'on n'installe rien, mais exige quand même un petit agent local pour accéder au port USB, et gère moins bien les cartes ESP32 tierces. |
| **PlatformIO** | Extension de VS Code | Plus puissant, plus long à prendre en main. Inutile ici. |

**Sur Mac**, si la carte n'apparaît dans aucun port : la plupart des cartes
ESP32 utilisent une puce USB-série **CH340** ou **CP2102**. macOS reconnaît la
seconde d'origine, rarement la première — le pilote CH340 s'installe depuis le
site de WCH. Le port porte alors un nom du type `/dev/cu.usbserial-…` ou
`/dev/cu.wchusbserial-…`.

### Et les flasheurs en ligne ?

Ils existent et fonctionnent bien : l'outil officiel d'Espressif
[esptool-js](https://espressif.github.io/esptool-js/) et
[ESP Web Tool](https://esp.huhn.me/) programment un ESP32 depuis une page web,
via l'API Web Serial, sans installer de pilote.

**Mais ils ne compilent pas.** Ils envoient dans la puce un fichier `.bin` déjà
compilé — il faut donc l'avoir fabriqué avant, avec Arduino IDE. Pour la
première sonde, ils ne font donc gagner aucune étape.

Ils deviennent intéressants **à partir de la deuxième sonde** : compilez une
fois dans Arduino IDE (*Croquis → Exporter les binaires compilés*), puis
programmez toutes les suivantes depuis la page web, sans rien réinstaller.
C'est aussi la façon de confier le travail à quelqu'un d'autre.

Deux réserves : il faut **Chrome ou Edge** sur le Mac — Safari ne gère pas
Web Serial, exactement comme il ne gère pas le Bluetooth web — et il faut
indiquer la bonne adresse d'écriture (`0x0` pour le binaire fusionné exporté
par Arduino IDE, `0x10000` pour le seul binaire d'application).

## 5. Programmation

> **Il n'y a rien à écrire.** Le programme de la sonde est terminé et se trouve
> dans ce dépôt. Cette section ne fait que le récupérer et le téléverser.

### 5.1 Récupérer le code sur le Mac

Le plus simple, sans rien installer de plus :

1. Téléchargez l'archive du projet :
   <https://github.com/hugofloriab-cell/Florijan-Veselaj/archive/refs/heads/claude/haccp-temperature-probes-pzo1eq.zip>
2. Double-cliquez le `.zip` dans *Téléchargements* pour le décompresser.
3. Le programme est dans
   `Florijan-Veselaj-claude-haccp-temperature-probes-pzo1eq/sondes/firmware/sonde-haccp/`.

Ce dossier contient **deux fichiers, et les deux comptent** :

| Fichier | Rôle |
| --- | --- |
| `sonde-haccp.ino` | le programme |
| `config.h` | les réglages — c'est le seul que vous modifierez |

> Arduino IDE exige que le fichier `.ino` soit dans un dossier **portant
> exactement le même nom** — ici `sonde-haccp/sonde-haccp.ino`. C'est déjà le
> cas : ne renommez ni ne déplacez rien, et gardez `config.h` à côté.

### 5.2 Ajouter les cartes ESP32 à Arduino IDE

L'ESP32 n'est pas fourni d'origine, il faut indiquer où le trouver.

1. **Arduino IDE → Réglages…** (`⌘,`)
2. Dans **URL de gestionnaire de cartes supplémentaires**, collez :
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
3. **OK**, puis *Outils → Type de carte → Gestionnaire de cartes…*
   (icône de carte dans la colonne de gauche).
4. Cherchez **esp32**, installez **esp32 by Espressif Systems** (version 3.x).
   Le téléchargement fait quelques centaines de mégaoctets : prévoyez dix
   minutes.

### 5.3 Installer les deux bibliothèques du capteur

*Outils → Gérer les bibliothèques…* (icône de livres), puis installez :

- **OneWire** de Paul Stoffregen
- **DallasTemperature** de Miles Burton
  (acceptez l'installation des dépendances si elle est proposée)

### 5.4 Régler la carte — dont le piège du partitionnement

Ouvrez `sonde-haccp.ino` (double-clic), puis dans le menu **Outils** :

| Réglage | Valeur |
| --- | --- |
| Type de carte | **ESP32 Dev Module** (ou **XIAO_ESP32C3** selon la carte) |
| **Partition Scheme** | **Huge APP (3MB No OTA/1MB SPIFFS)** |
| Port | `/dev/cu.usbserial-…` ou `/dev/cu.wchusbserial-…` |
| **Upload Speed** | **115200** — voir l'encadré ci-dessous |

> ### ⚠ Le partitionnement est le piège classique
>
> Le découpage par défaut ne réserve que 1,2 Mo au programme. Une application
> Bluetooth ESP32 approche cette limite, et la dépasse dès qu'on active
> l'option Wi-Fi. Vous verriez alors :
>
> ```
> text section exceeds available space in board
> Sketch too big
> ```
>
> Ce n'est pas une erreur du programme : c'est le découpage de la mémoire.
> **Huge APP** porte la place disponible à 3 Mo et règle la question
> définitivement.

> ### ⚠ Et le débit de téléversement
>
> Arduino IDE propose 921600 bauds par défaut. Beaucoup d'adaptateurs USB-série
> CH340 ne suivent pas à cette vitesse : la connexion s'établit, la puce est
> reconnue — adresse MAC lue, tout va bien — puis l'écriture échoue au moment
> précis du passage à haut débit :
>
> ```
> Uploading stub flasher...
> Changing baud rate to 921600...
> A fatal error occurred: Unable to verify flash chip connection
> Failed uploading: uploading error: exit status 2
> ```
>
> L'erreur parle de « flash chip connection », ce qui fait penser à un problème
> matériel. Il n'en est rien : **repassez Upload Speed à 115200**. Le
> téléversement prend une trentaine de secondes au lieu de dix — sans commune
> mesure avec le temps perdu à chercher.

### 5.5 Vérifier les réglages du programme

Ouvrez l'onglet **config.h** dans Arduino IDE et contrôlez, tout en bas :

```c
#define MODE_BANC 1
```

C'est ce qui donne un relevé par minute, la radio allumée 60 s et la trace
série. Le reste — brochage, seuils — est déjà réglé pour votre montage.

### 5.6 Téléverser

Bouton **→** (flèche). La première compilation prend une à deux minutes, les
suivantes sont rapides.

Si la carte n'est pas détectée, ou si le téléversement reste bloqué sur
`Connecting........_____` : maintenez **BOOT** enfoncé, appuyez brièvement sur
**EN** (ou **RST**), relâchez BOOT, et relancez.

## 6. Lire la trace

*Outils → Moniteur série*, **115200 bauds**. Toutes les minutes :

```
demarrage a froid
T=325 centi, pile=100% (4900 mV), attente=1, manuel=0
annonce HACCP-0A3F
veille 60 s (tics 61)
```

- `T=325` → **+3,25 °C**. Serrez la pointe inox entre vos doigts : la valeur
  doit monter franchement en quelques secondes.
- `pile=100%` → normal, le pont diviseur n'est pas câblé : le mode banc
  annonce une batterie pleine plutôt qu'une valeur au hasard.
- `attente=N` → relevés en mémoire, non encore récupérés par la tablette.
- `HACCP-0A3F` → le nom que vous chercherez dans la liste Bluetooth.

**Si `T` vaut −32768** : le capteur n'est pas lu. Dans l'ordre —

1. le **jaune** est-il bien sur `D4` et le **noir** sur `GND` ? C'est l'erreur
   la plus fréquente, les deux se confondent facilement ;
2. la résistance de 4,7 kΩ est-elle bien entre le **rouge et le jaune**, et non
   entre le rouge et le noir ? Entre rouge et noir, elle ne fait que consommer
   0,7 mA entre l'alimentation et la masse, sans jamais tirer la ligne de
   données vers le haut ;
3. le rouge est-il sur `3V3` ?
4. les trois soudures tiennent-elles vraiment ?

## 7. Relever depuis la fiche

Le Bluetooth du navigateur exige une adresse sécurisée : **la fiche doit être
ouverte depuis son adresse web**, pas depuis un fichier local.

> **Sur iPhone ou iPad, cette étape ne marchera pas** : Safari ne gère pas le
> Bluetooth web, et tous les navigateurs iOS reposent sur Safari. Utilisez la
> tablette Android, le navigateur **Bluefy** en dépannage, ou l'application
> SwiftUI du dossier [`ios/`](ios/README.md).

1. Sur un téléphone ou une tablette Android, ouvrir **Chrome** à l'adresse
   <https://hugofloriab-cell.github.io/Florijan-Veselaj/>
2. Section **2. Sondes de température** → **Appairer une sonde**.
3. Choisir `HACCP-XXXX` dans la liste. La carte doit être alimentée et dans sa
   fenêtre d'annonce — en mode banc elle émet 60 s par minute, vous tomberez
   dessus sans attendre.
4. Renseigner l'emplacement et le type d'enceinte.

La carte apparaît alors avec la température, la courbe et le bilan du jour.
Chaque appui sur **Relever les sondes** rapatrie les nouvelles mesures.

Un bandeau orange signalera que la sonde est en cadence de banc d'essai : c'est
voulu, il disparaîtra en passant en service.

## 8. Vérifier l'étalonnage

Un verre de glace pilée, un peu d'eau, on remue : le bain est à 0,0 °C tant
qu'il reste de la glace.

Plongez-y la pointe inox **et** votre thermomètre de référence. Après cinq
minutes, relevez depuis la fiche. Un DS18B20 sorti d'usine tombe en général
entre −0,5 et +0,5 °C. L'écart lu se corrige avec le bouton **Étalonner**, ou
dans `OFFSET_ETALONNAGE_CENTI`.

## 9. Essayer l'alerte Wi-Fi

Facultatif, et indépendant du Bluetooth. Cette option fait allumer le Wi-Fi à
la sonde **uniquement pour signaler un défaut** : température hors seuils sur
deux relevés consécutifs, ou pile faible. Elle est la seule façon d'être
prévenu la nuit sans qu'aucun appareil ne soit à portée.

### 9.1 S'abonner aux notifications

**ntfy.sh** est gratuit et sans compte.

1. Installez l'application **ntfy** (App Store ou Play Store).
2. *Ajouter un abonnement* → saisissez un nom de sujet **long et non
   devinable**, par exemple `ibis-sisteron-froid-7f3a91c2`.

> **Le nom du sujet est le seul mot de passe.** Qui le connaît lit vos alertes,
> et peut en publier de fausses. Inventez une suite qu'on ne devine pas — pas
> `ibis-froid`.

Sans téléphone sous la main, ouvrez simplement `https://ntfy.sh/VOTRE-SUJET`
dans un navigateur : les messages y arrivent en direct.

### 9.2 Configurer la sonde

Dans `config.h` :

```c
#define ALERTE_WIFI 1

#if ALERTE_WIFI
  #define WIFI_SSID "le-nom-de-votre-box"
  #define WIFI_MDP  "le-mot-de-passe"
  #define NTFY_SUJET "ibis-sisteron-froid-7f3a91c2"
```

> ### ⚠ Ne publiez jamais ces lignes
>
> Le dépôt GitHub est **public**. Si vous y poussez un `config.h` contenant le
> vrai mot de passe de la box de l'hôtel, il devient lisible par tout le monde
> — et le retirer plus tard ne l'effacera pas de l'historique. Gardez ce
> fichier sur votre Mac uniquement.

Deux limites de l'ESP32 à connaître :

- **2,4 GHz uniquement.** Si votre box diffuse deux réseaux séparés, indiquez
  celui en 2,4 GHz. Avec un réseau unique fusionné, ça passe en général.
- **Pas de portail captif, pas de Wi-Fi d'entreprise.** Un réseau à page
  d'accueil ou à identifiants individuels ne fonctionnera pas.

### 9.3 Déclencher l'alerte pour de vrai

Le plus simple : **ne rien faire de spécial.** Les seuils par défaut sont ceux
d'une enceinte positive, `+1` à `+4 °C`. Sur un établi à 21 °C, la sonde est
donc déjà largement hors normes.

Gardez `MODE_BANC 1`, téléversez, et attendez **deux minutes** — le temps de
deux relevés consécutifs hors seuils. La notification arrive sur le téléphone.

La trace série raconte ce qui se passe :

```
T=+21,50 C (2150 centi), ...
alerte poussee, code http 200
```

| Trace | Signification |
| --- | --- |
| `code http 200` | ntfy a accepté, la notification est partie |
| `wifi indisponible (etat 6)` | mauvais SSID ou mot de passe, ou réseau 5 GHz |
| `ouverture https impossible` | la connexion TLS a échoué |
| aucune ligne d'alerte | moins de deux relevés hors seuils, ou délai de repos en cours |

### 9.4 Pour recommencer l'essai

Après une alerte, la sonde se tait **2 heures** (`ALERTE_REPOS_MINUTES`) : sans
ce repos, une enceinte en panne enverrait une notification par relevé.

Pour relancer un essai tout de suite, appuyez sur **EN**. La remise à zéro
efface le compteur de repos, et deux relevés plus tard une nouvelle
notification part.

### 9.5 Ce que coûte l'option

Rien, tant que les enceintes sont conformes : le Wi-Fi n'est jamais allumé.

Une enceinte réellement en panne envoie une alerte toutes les 2 heures, soit
environ **0,4 mAh par alerte** — 5 mAh par jour de panne. Sans effet sur
l'autonomie, d'autant qu'une panne se règle en quelques heures.

## 10. Passer en service

Une fois l'essai concluant, dans `config.h` :

- **`MODE_BANC` à 0** — sans quoi l'autonomie tombe de deux ans à quelques
  semaines ;
- `EMPLACEMENT` — `"Chambre froide"`, `"Congel coffre"`…
- `SEUIL_MIN_CENTI` / `SEUIL_MAX_CENTI` — `100`/`400` en positif,
  `-2300`/`-1800` en négatif ;
- `REVEIL_MANUEL_ACTIF` à 1 seulement quand l'ILS est réellement soudé ;
- les bornes de batterie (§ « Pile ») selon piles AA ou accu rechargeable.

Puis le montage définitif : voir `README.md`, § 4 (câblage complet) et § 8
(mise en service sur l'enceinte).
