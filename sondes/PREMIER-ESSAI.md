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

## 8. La température lue ne ressemble pas à la pièce

C'est la réaction normale au premier essai : la trace affiche 24, 27, 32 °C, et
il ne fait manifestement pas ça dans la pièce. Le réflexe est de soupçonner
l'étalonnage. C'est presque toujours la mauvaise piste.

### Un DS18B20 ne se dérègle pas

C'est un capteur **numérique**, étalonné en usine, garanti **±0,5 °C** de −10 à
+85 °C. Il n'envoie pas une tension à interpréter mais un nombre déjà converti :
il n'y a aucune chaîne analogique susceptible de dériver, ni résistance à
ajuster, ni rien à régler.

D'où la règle qui fait gagner du temps :

> **Un écart de plusieurs degrés n'est jamais un problème d'étalonnage.**
> C'est un problème de ce que la pointe mesure réellement.

Un écart d'étalonnage, ça vaut 0,3 °C. Pas 8.

### Ce que la pointe mesure vraiment

Par ordre de fréquence :

1. **La chaleur de la carte.** Une DevKit dissipe en permanence : régulateur
   AMS1117, puce USB-série, LED d'alimentation. Ça chauffe peu, mais la pointe
   inox posée à côté, ou le câble enroulé autour de la carte, suffit à faire
   monter la lecture de plusieurs degrés. Une lecture à 32 °C dans une pièce à
   22 °C, c'est exactement cette signature.

2. **La pointe n'est pas dans l'air qu'on croit.** Contre un mur, sous un
   coussin, dans un pli de tissu, posée sur du carrelage, coincée sous
   l'ordinateur : elle mesure la surface, pas la pièce. Le carrelage est plus
   froid que l'air, un couvre-lit bien plus chaud.

3. **Le temps de réponse.** L'inox a de la masse. Déplacée d'un endroit à un
   autre, la pointe met **cinq bonnes minutes** à suivre. Les premières lectures
   après un déplacement décrivent l'endroit d'avant.

Le test qui tranche en une minute : tenez la pointe **en l'air, à bout de bras,
loin de la carte et de votre main**, attendez cinq minutes, et regardez la
trace. Si la lecture descend franchement, le capteur va très bien — il mesurait
autre chose.

### Le point de référence qui ne coûte rien

Pas besoin de thermomètre étalon. Un verre de **glace pilée avec un peu d'eau,
remué**, est à **0,0 °C** tant qu'il reste de la glace : c'est de la physique,
pas un réglage, et c'est bon à quelques centièmes. Aucun thermomètre de cuisine
n'est aussi fiable.

1. Remplissez un verre de glace, ajoutez un fond d'eau, remuez.
2. Plongez-y la pointe inox sur cinq bons centimètres — pas le câble, pas la
   jonction.
3. Attendez **cinq minutes**, en remuant de temps en temps.
4. Lisez la trace.

| Lecture | Verdict |
| --- | --- |
| entre −0,5 et +0,5 °C | Le capteur est bon. L'écart dans la pièce venait du placement. |
| écart franc et stable | Là, et là seulement, un offset se justifie. |
| `-32768` | Ce n'est pas l'étalonnage, c'est le câblage (§ 3). |

### Corriger, si c'est vraiment nécessaire

`OFFSET_ETALONNAGE_CENTI` dans `config.h`, en centièmes de degré, **du signe
opposé à l'erreur** : la sonde affiche +0,4 °C dans la glace, on met `-40`.

```cpp
#define OFFSET_ETALONNAGE_CENTI -40
```

La fiche sait aussi l'écrire dans la sonde sans retéléverser (bouton
**Étalonner**, commande `0x05` du protocole).

> **Ne mettez jamais un offset pour rattraper un placement.** Il s'appliquerait
> ensuite à *toutes* les mesures, y compris dans le froid, où il n'y a plus de
> carte pour chauffer la pointe. Une sonde « corrigée » de −8 °C sur un
> réfrigérateur à +3 °C annoncerait −5 °C : elle passerait d'un outil de
> contrôle à un mensonge enregistré toutes les 30 minutes. L'offset se
> détermine dans la glace, jamais à l'estime.

## 9. Si la carte redémarre en boucle

Symptôme observé sur la carte d'essai, et le plus déroutant de tous :

```
annonce HACCP-C456
ets Jul 29 2019 12:21:46
rst:0x1 (POWERON_RESET)
demarrage a froid          ← et ça recommence, indéfiniment
```

`POWERON_RESET` juste après la ligne `annonce` signifie que l'alimentation
s'est réellement effondrée — pas un plantage logiciel. Le signe qui ne trompe
pas : `demarrage a froid` réapparaît à chaque tour, donc la mémoire de
sauvegarde est perdue, donc le 3,3 V est bien tombé.

La cause est le **pic de courant de l'émission Bluetooth** : plus de 100 mA par
bouffée, sur une alimentation qui n'a pas la réserve pour l'encaisser.

### L'expérience qui tranche

Avant de chercher, isolez la radio. Commentez les deux lignes qui l'allument :

```cpp
  // demarrerAnnonce();
  // tenirFenetre(fenetre);
```

Téléversez et regardez la trace :

| Résultat | Conclusion |
| --- | --- |
| `rst:0x5 (DEEPSLEEP_RESET)`, plus de `demarrage a froid`, `veille 59 s` | C'est la radio. Voir ci-dessous. |
| Toujours `POWERON_RESET` | Ce n'est pas la radio : bouton EN enfoncé, court-circuit, ou câble USB. |

Le temps de veille est un indice supplémentaire : `veille 5 s` quand la radio
occupe 60 s du cycle d'une minute, `veille 59 s` sans elle. C'est le programme
qui calcule juste.

### Les remèdes, du plus simple au plus lourd

1. **Baisser la puissance d'émission.** C'est le réglage `PUISSANCE_BLE` de
   `config.h`. En mode banc, il est **déjà** au minimum utile
   (`ESP_PWR_LVL_N9`, −9 dBm) : sur l'établi, le téléphone est à un mètre, la
   portée n'a aucune importance. Rien à faire donc, sauf si vous avez modifié
   ce réglage — dans ce cas remettez-le, ou descendez d'un cran jusqu'à
   `ESP_PWR_LVL_N12`.

   De `+3` à `-9 dBm`, le pic chute nettement. La portée passe d'une quinzaine
   de mètres à trois ou quatre — sans importance pour une sonde aimantée sur
   une porte de frigo, et la fenêtre radio consomme moins.

   Le passage en service (§ 11) repasse à `ESP_PWR_LVL_N0`, soit une dizaine
   de mètres. Si la carte se remet à redémarrer à ce moment-là, c'est le
   condensateur du point 2 qu'il faut, pas un retour en arrière.

2. **Ajouter un condensateur** de 220 à 470 µF entre `3V3` et `GND`, au plus
   près de la carte. Il sert de réservoir et absorbe le pic. C'est le remède de
   fond, et c'est pourquoi la nomenclature en prévoit un.

3. **Vérifier l'alimentation elle-même** : câble USB court et épais, branché
   directement sur l'ordinateur, sans hub. Et surtout, **rien d'autre relié à
   `VIN`** — un module de charge encore câblé suffit à perturber.

### Un piège matériel à écarter d'abord

`POWERON_RESET` est aussi ce qu'on obtient en appuyant sur **EN**. Une carte
posée sur du tissu, un couvre-lit, une nappe : le bouton peut être enfoncé, et
les broches nues dessous peuvent se toucher dans un pli.

Posez la carte sur une surface **dure et plate** avant de conclure quoi que ce
soit.

### Remettre la radio

Une fois le remède appliqué, **décommentez les deux lignes** — sans quoi la
sonde mesure très bien mais ne parlera jamais à personne :

```cpp
  demarrerAnnonce();
  tenirFenetre(fenetre);
```

Téléversez. La trace attendue, à chaque cycle :

```
rst:0x5 (DEEPSLEEP_RESET),boot:0x17 (SPI_FAST_FLASH_BOOT)
reveil: minuterie
T=+7,25 C (725 centi), pile=100% (4900 mV), attente=3, manuel=0
annonce HACCP-C456
veille 1 s (tics 180)
```

Trois choses à y vérifier, dans cet ordre :

| À vérifier | Pourquoi |
| --- | --- |
| `DEEPSLEEP_RESET`, et non `POWERON_RESET` | l'alimentation tient pendant l'émission |
| pas de `demarrage a froid` après le premier | la mémoire de sauvegarde survit, donc le 3,3 V n'est pas tombé |
| la ligne `annonce HACCP-XXXX` | la radio est réellement partie |

`veille 1 s` est normal en mode banc et n'est pas un défaut : la fenêtre
d'annonce dure 60 s et le cycle une minute, la radio occupe donc presque tout
le temps. En service (§ 11), le cycle passe à 30 minutes et la fenêtre à 15 s.

Notez le nom `HACCP-XXXX` de la trace : c'est sous ce nom que la sonde
apparaîtra au scan, et c'est lui qu'il faudra chercher depuis l'application.

## 10. Essayer l'alerte Wi-Fi

Facultatif, et indépendant du Bluetooth. Cette option fait allumer le Wi-Fi à
la sonde **uniquement pour signaler un défaut** : température hors seuils sur
deux relevés consécutifs, ou pile faible. Elle est la seule façon d'être
prévenu la nuit sans qu'aucun appareil ne soit à portée.

### 10.1 S'abonner aux notifications

**ntfy.sh** est gratuit et sans compte.

1. Installez l'application **ntfy** (App Store ou Play Store).
2. *Ajouter un abonnement* → saisissez un nom de sujet **long et non
   devinable**, par exemple `ibis-sisteron-froid-7f3a91c2`.

> **Le nom du sujet est le seul mot de passe.** Qui le connaît lit vos alertes,
> et peut en publier de fausses. Inventez une suite qu'on ne devine pas — pas
> `ibis-froid`.

Sans téléphone sous la main, ouvrez simplement `https://ntfy.sh/VOTRE-SUJET`
dans un navigateur : les messages y arrivent en direct.

### 10.2 Configurer la sonde

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

### 10.3 Déclencher l'alerte pour de vrai

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

### 10.4 Pour recommencer l'essai

Après une alerte, la sonde se tait **2 heures** (`ALERTE_REPOS_MINUTES`) : sans
ce repos, une enceinte en panne enverrait une notification par relevé.

Pour relancer un essai tout de suite, appuyez sur **EN**. La remise à zéro
efface le compteur de repos, et deux relevés plus tard une nouvelle
notification part.

### 10.5 Ce que coûte l'option

Rien, tant que les enceintes sont conformes : le Wi-Fi n'est jamais allumé.

Une enceinte réellement en panne envoie une alerte toutes les 2 heures, soit
environ **0,4 mAh par alerte** — 5 mAh par jour de panne. Sans effet sur
l'autonomie, d'autant qu'une panne se règle en quelques heures.

## 11. Passer en service

Une fois l'essai concluant, dans `config.h` :

- **`MODE_BANC` à 0** — sans quoi l'autonomie tombe de deux ans à quelques
  semaines ;
- `EMPLACEMENT` — `"Chambre froide"`, `"Congel coffre"`…
- `SEUIL_MIN_CENTI` / `SEUIL_MAX_CENTI` — `100`/`400` en positif,
  `-2300`/`-1800` en négatif ;
- `REVEIL_MANUEL_ACTIF` à 1 seulement quand l'ILS est réellement soudé ;
- les bornes de batterie (§ « Pile ») selon piles AA ou accu rechargeable.

Attention : `MODE_BANC` à 0 rend aussi sa valeur normale à `PUISSANCE_BLE`,
`ESP_PWR_LVL_N0` — une dizaine de mètres de portée, et un pic de courant plus
fort qu'au banc. C'est le moment où une alimentation juste se fait remarquer
(§ 9). Sur le montage définitif, avec le condensateur de la nomenclature en
place, elle n'a plus de raison de faiblir ; si c'est le cas, redescendez d'un
cran plutôt que de renoncer au condensateur.

Puis le montage définitif : voir `README.md`, § 4 (câblage complet) et § 8
(mise en service sur l'enceinte).
