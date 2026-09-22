# Application iOS — SwiftUI

Lecture des sondes HACCP depuis un iPhone ou un iPad, avec CoreBluetooth.

---

## 1. Pourquoi une application native était nécessaire

Ce n'est pas une préférence de style : **Safari ne gère pas le Bluetooth web**,
et sur iOS tous les navigateurs sont bâtis sur Safari — Chrome et Firefox pour
iPhone compris.

Conséquence directe : la fiche web relève parfaitement les sondes sur la
tablette Android de la cuisine, mais **ne peut pas les relever depuis un
iPhone**. Aucun réglage n'y change rien.

Une application SwiftUI avec CoreBluetooth n'a pas cette limite. Elle parle aux
sondes avec exactement le même protocole que la fiche : c'est la même sonde, le
même service GATT, les mêmes trames.

> **Dépannage immédiat, sans rien développer :** le navigateur **Bluefy**
> (App Store, gratuit) embarque sa propre pile Bluetooth web. En ouvrant
> l'adresse de la fiche dedans, la section Sondes fonctionne sur iPhone. C'est
> une béquille utile le temps de finir l'application, pas une solution durable.

## 2. Ce que contient le dossier

| Fichier | Rôle |
| --- | --- |
| `SondesHACCP/ProtocoleSonde.swift` | UUID, drapeaux, décodage des trames, commandes |
| `SondesHACCP/ModeleSonde.swift` | Sonde, relevés, recalage d'horloge, bilans, conservation |
| `SondesHACCP/GestionnaireSondes.swift` | Dialogue CoreBluetooth : scan, connexion, déversement |
| `SondesHACCP/VuesSondes.swift` | Écrans SwiftUI : liste, carte, courbe, détail, appairage |

Les noms sont en français, comme le reste du dépôt.

## 3. Créer le projet dans Xcode

1. **Xcode → File → New → Project → iOS → App.**
   - *Product Name* : `Sondes HACCP`
   - *Interface* : **SwiftUI**
   - *Language* : **Swift**
2. Dans le navigateur de projet, glissez les **quatre fichiers `.swift`** du
   dossier `SondesHACCP/`. Cochez *Copy items if needed*.
3. **Cible → General → Minimum Deployments : iOS 17.0.**
   (`ContentUnavailableView` et `MainActor.assumeIsolated` le demandent.)
4. **Cible → Info → ajouter une clé :**
   - `Privacy - Bluetooth Always Usage Description`
     (`NSBluetoothAlwaysUsageDescription`)
   - Valeur : *« Pour relever les températures des enceintes froides. »*

   Sans cette clé, l'application est **fermée par le système** à la première
   utilisation du Bluetooth. C'est l'oubli le plus courant.
5. Dans le fichier `…App.swift` créé par Xcode, remplacez la vue racine :

   ```swift
   @main
   struct SondesHACCPApp: App {
       var body: some Scene {
           WindowGroup { VueSondes() }
       }
   }
   ```
6. **Branchez un iPhone et lancez dessus.** Le simulateur n'a pas de Bluetooth :
   il compilera, mais ne trouvera jamais aucune sonde.

## 4. Utilisation

- **Appairer** : passez l'aimant sur le boîtier de la sonde — elle ouvre une
  fenêtre de deux minutes — puis touchez *Appairer*.
- **Relever** : le bouton en haut à droite, ou un tiré-vers-le-bas sur la liste.
- **Emplacement et type d'enceinte** : dans le détail d'une sonde. Les seuils se
  règlent tout seuls sur les normes de la fiche, et sont écrits dans la sonde.
- **Étalonnage** : bain d'eau glacée, saisir l'écart lu, la correction part dans
  la sonde (commande `0x05`).

## 5. Particularités iOS à connaître

**iOS met en cache la liste des services GATT.** Si vous modifiez la structure
du service dans le firmware, l'iPhone continuera d'afficher l'ancienne : coupez
et rallumez le Bluetooth, ou oubliez l'appareil. C'est une source classique de
« ça marchait hier ».

**Le simulateur n'a pas de Bluetooth.** Tout essai se fait sur un appareil réel.

**Relever en arrière-plan est possible**, et c'est intéressant ici : ajoutez la
capacité *Background Modes → Uses Bluetooth LE accessories*, et un
`connect()` laissé en attente réveille l'application quand la sonde se remet à
émettre. Avec une fenêtre de 15 s toutes les 30 minutes, cela donne plusieurs
synchronisations par jour sans ouvrir l'application. iOS reste maître de son
budget d'exécution : c'est un bonus, pas une garantie.

**Les notifications d'écart** partent en local dès qu'une synchronisation
détecte une température non conforme, y compris en arrière-plan. Pour être
réveillé la nuit, téléphone rangé et sonde hors de portée, il faut l'option
Wi-Fi de la sonde (`../README.md`, § 7) : c'est la sonde elle-même qui pousse
alors l'alerte, sans dépendre d'un téléphone à proximité.

## 6. Ce qui n'est pas encore fait

Le nécessaire est là — appairer, relever, afficher, alerter, étalonner. Restent
à écrire, si vous voulez que l'application remplace la fiche et non la
compléter :

- l'export CSV et le récapitulatif transmis à la direction ;
- la check-list elle-même (les 25 tâches, l'émargement, la clôture) ;
- le partage des relevés entre la tablette Android et les iPhone — aujourd'hui
  chaque appareil garde les siens, comme la fiche web.

## 7. État de vérification

À dire clairement, pour que vous sachiez sur quoi vous vous appuyez.

**Ce code n'a jamais été compilé.** Le compilateur Swift n'était pas
installable dans l'environnement où il a été écrit (`download.swift.org` est
bloqué par la politique réseau). Attendez-vous à quelques corrections au
premier passage dans Xcode.

**Ce qui a été vérifié malgré tout** : les décalages d'octets du décodeur Swift
ont été confrontés aux trames réellement produites par le firmware C++ compilé
et exécuté — état complet sur 20 octets, paquets d'historique, paquet de fin,
températures négatives, drapeaux. Tout concorde. C'était le point le plus
susceptible d'être faux sans qu'on s'en aperçoive.

**Ce qui a été relu ligne à ligne** : l'ordre des rappels CoreBluetooth
(`MainActor.assumeIsolated` plutôt qu'un saut asynchrone, sans quoi les paquets
d'historique pourraient être traités dans le désordre), l'attente de la
confirmation d'écriture avant de couper la connexion (sans quoi l'acquittement
serait annulé et la sonde redéverserait le même historique sans fin), et le
chien de garde sur une connexion qui n'aboutit pas — CoreBluetooth n'expire
jamais de lui-même.
