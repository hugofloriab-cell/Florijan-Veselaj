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

## 2. Câblage — trois fils et une résistance

Le DS18B20 sort trois fils : **rouge** (alimentation), **jaune** ou blanc
(données), **noir** (masse). La résistance de 4,7 kΩ se monte entre le rouge et
le jaune : sans elle, la ligne de données reste à zéro et le capteur reste muet.

```
   DS18B20                     ESP32 (DevKit / WROOM-32)

   rouge  ───────────────────► GPIO19      (alimentation commutée)
            │
          4,7 kΩ
            │
   jaune  ──┴────────────────► GPIO21      (données 1-Wire)

   noir   ───────────────────► GND
```

Sur une carte **ESP32-C3** (XIAO, SuperMini), c'est GPIO21 pour l'alimentation
et GPIO5 pour les données — le programme s'adapte tout seul, seules les broches
physiques changent. Le détail est dans `config.h`.

> **Le rouge ne va pas sur 3V3.** Il va sur une broche ordinaire, que le
> programme allume le temps de la mesure et éteint ensuite. C'est ce qui
> supprime la consommation du capteur au repos. Branché sur 3V3 permanent, tout
> fonctionne aussi — mais l'autonomie en souffre.

## 3. Où écrire et téléverser le programme

Trois possibilités, par ordre de commodité :

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

## 4. Programmation

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

## 5. Lire la trace

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

**Si `T` vaut −32768** : le capteur n'est pas lu. Dans l'ordre — la résistance
de 4,7 kΩ est-elle bien entre le rouge et le jaune (et non entre le jaune et la
masse) ? Le rouge est-il sur GPIO19 et le jaune sur GPIO21 ? Les trois fils
font-ils bien contact ?

## 6. Relever depuis la fiche

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

## 7. Vérifier l'étalonnage

Un verre de glace pilée, un peu d'eau, on remue : le bain est à 0,0 °C tant
qu'il reste de la glace.

Plongez-y la pointe inox **et** votre thermomètre de référence. Après cinq
minutes, relevez depuis la fiche. Un DS18B20 sorti d'usine tombe en général
entre −0,5 et +0,5 °C. L'écart lu se corrige avec le bouton **Étalonner**, ou
dans `OFFSET_ETALONNAGE_CENTI`.

## 8. Passer en service

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
