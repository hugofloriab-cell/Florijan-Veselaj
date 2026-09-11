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

1. **Arduino IDE 2.x** → *Outils → Gestionnaire de cartes* → installer
   **esp32 by Espressif Systems** (version 3.x).
2. *Outils → Gérer les bibliothèques* → **OneWire** (Paul Stoffregen) et
   **DallasTemperature** (Miles Burton).
3. *Outils → Type de carte* : **ESP32 Dev Module** pour une DevKit,
   **XIAO_ESP32C3** pour une XIAO.
4. Ouvrir `firmware/sonde-haccp/sonde-haccp.ino`. Vérifier en bas de `config.h`
   que **`MODE_BANC` vaut 1**.
5. Téléverser. Si la carte n'est pas détectée : maintenir **BOOT**, appuyer
   brièvement sur **EN**/**RESET**, relâcher BOOT.

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

## 9. Passer en service

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
