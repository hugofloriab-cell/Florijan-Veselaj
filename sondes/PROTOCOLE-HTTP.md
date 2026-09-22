# Protocole HTTP des sondes HACCP

La sonde sert ses relevés en HTTP, sur son propre réseau Wi-Fi ou sur celui de
l'hôtel. Le principe est celui d'une petite caméra d'inspection : on se
connecte à l'appareil, on lit, on repart. Rien ne sort de l'hôtel, rien n'est
stocké ailleurs que dans la sonde et dans l'appareil qui vient lire.

C'est la voie recommandée pour une application iOS. [`PROTOCOLE-BLE.md`](PROTOCOLE-BLE.md)
décrit l'autre voie, qui garde un avantage propre (§ 8).

---

## 1. Pourquoi cette voie plutôt que le Bluetooth

| | HTTP | Bluetooth |
| --- | --- | --- |
| Côté application | `URLSession` + `Codable` — quelques lignes | `CoreBluetooth`, délégués, files d'attente |
| Safari sur iPhone / iPad | **fonctionne** | impossible, jamais implémenté par WebKit |
| Lire 4 sondes en une passe | mode station seulement | oui |
| Voir les températures sans se connecter | non | oui, dans l'annonce |
| Énergie par consultation | ~100 mA pendant la consultation | ~11 mA pendant la fenêtre |

Les deux peuvent tourner sur la même sonde : le portail se ferme avant que le
Bluetooth ne s'ouvre, et si le portail a été acquitté, la fenêtre Bluetooth est
sautée — le travail est déjà fait.

## 2. Les deux modes

Le JSON servi est **identique**. Seule l'adresse de base change : votre
application n'a pas une ligne de différence.

### `PORTAIL_AP` — la sonde crée son réseau

```
réseau  SONDE-C456        (mot de passe : PORTAIL_MDP)
base    http://192.168.4.1
```

Aucun mot de passe d'hôtel dans le programme, aucune dépendance au réseau
existant, fonctionne dans une cave où le Wi-Fi ne passe pas. En échange, le
téléphone quitte son réseau et ne lit **qu'une sonde à la fois**.

### `PORTAIL_STATION` — la sonde rejoint le réseau de l'hôtel

```
base    http://sonde-c456.local
```

Le téléphone ne change pas de réseau, et l'application interroge les quatre
sondes dans la même tournée. En échange, il faut que le Wi-Fi porte jusqu'à
l'enceinte — **à vérifier sur place**, les cuisines et les réserves sont
souvent des zones mortes — et que les identifiants du réseau soient dans
`config.h`, donc hors du dépôt public.

## 3. Quand la sonde répond

**Presque jamais**, et c'est voulu : le portail est fermé 99,9 % du temps.

```
  aimant / bouton
        │
        ▼
  ┌───────────────┐   ┌──────────────────┐   ┌──────────────┐
  │ réveil        │──►│ portail ouvert   │──►│ veille       │
  │ mesure        │   │ 180 s au plus    │   │ profonde     │
  └───────────────┘   │ ou jusqu'à       │   └──────────────┘
                      │ /acquitter       │
                      └──────────────────┘
```

Le plafond est `PORTAIL_DUREE_S`. Mais `/acquitter` ferme le portail
immédiatement : **une consultation de vingt secondes coûte vingt secondes de
radio, pas trois minutes.** C'est ce qui rend l'option compatible avec des mois
d'autonomie, et c'est pourquoi votre application doit acquitter dès qu'elle a
écrit — pas seulement pour libérer la mémoire de la sonde.

`POST /prolonger` rouvre pour cinq minutes, le temps d'un étalonnage.

## 4. Requêtes

### `GET /etat`

```json
{
  "version": 1,
  "sonde": "HACCP-C456",
  "emplacement": "Chambre froide",
  "centi": 655,
  "capteur_ok": true,
  "pile": 19,
  "tension_mv": 3820,
  "tics": 86400,
  "unix_ref": 1757600000,
  "intervalle_min": 30,
  "attente": 3,
  "offset_centi": -40,
  "seuil_min_centi": 100,
  "seuil_max_centi": 400,
  "drapeaux": 39,
  "alerte": true,
  "pile_faible": true,
  "tampon_plein": false,
  "reveil_manuel": true
}
```

`centi` vaut **`null`** quand la lecture a échoué. `drapeaux` reprend les bits
du § 3 de `PROTOCOLE-BLE.md` ; les quatre booléens qui suivent les décodent,
inutile de manipuler les bits.

### `GET /releves`

Tous les relevés non encore acquittés, du plus ancien au plus récent.

```json
{
  "version": 1,
  "sonde": "HACCP-C456",
  "tics": 86400,
  "nombre": 3,
  "releves": [
    {"index": 0, "tics": 82800, "centi": 655,   "capteur_ok": true,  "pile": 19, "drapeaux": 1},
    {"index": 1, "tics": 84600, "centi": null,  "capteur_ok": false, "pile": 19, "drapeaux": 17},
    {"index": 2, "tics": 86400, "centi": -2055, "capteur_ok": true,  "pile": 19, "drapeaux": 3}
  ]
}
```

Envoyé en morceaux (`Transfer-Encoding: chunked`) : 512 relevés font une
quarantaine de milliers d'octets, que la sonde n'a pas la mémoire de fabriquer
d'un bloc. `URLSession` ne voit pas la différence.

`index` part toujours de 0 et suit la file d'attente, pas une position absolue
dans la mémoire de la sonde. C'est cet index que `/acquitter` attend.

### `POST /acquitter?jusqua=<index>`

Libère les relevés jusqu'à cet index **inclus**.

```json
{"acquitte": true, "attente": 1}
```

`409` si l'index dépasse ce qui est en attente — c'est le cas si votre
application rejoue un vieil acquittement.

> **À n'envoyer qu'après avoir écrit les relevés sur l'appareil.** C'est la
> seule requête qui fait perdre des données à la sonde. Si la synchronisation
> casse avant, la sonde garde tout et on recommence : rien n'est perdu. Si vous
> acquittez avant d'écrire, les relevés disparaissent des deux côtés.

### `POST /heure?unix=<horodatage>`

Règle l'heure de référence et lève `HORLOGE_OK`. **À envoyer à chaque
connexion** : c'est ce qui permet de recaler la dérive (§ 6).

### `POST /etalonner?centi=<offset>`

Offset ajouté à chaque mesure, en centièmes de degré, entre −5000 et +5000.
Déterminé dans un bain de glace — voir `PREMIER-ESSAI.md` § 8, et n'y touchez
pas sans.

### `POST /prolonger`

Garde le portail ouvert cinq minutes de plus.

### `GET /`

Une page lisible dans n'importe quel navigateur : température, pile, seuils.
Elle n'est pas là pour faire joli — elle permet de vérifier une sonde depuis
n'importe quel téléphone, **sans aucune application**, y compris depuis Safari.
C'est le filet de sécurité quand votre application est en cours de
développement, ou quand c'est un collègue qui doit aller voir.

## 5. Séquence complète

```
téléphone                                     sonde
   │  (aimant passé sur le boîtier)            │
   │  rejoindre SONDE-C456 / ou déjà sur le Wi-Fi
   │─────────────────────────────────────────► │
   │  GET /etat                                │
   │◄───────────────────────────────────────── │
   │  POST /heure?unix=1757600123              │
   │─────────────────────────────────────────► │
   │  GET /releves                             │
   │◄───────────────────────────────────────── │
   │  ── écriture dans l'appareil ──           │
   │  POST /acquitter?jusqua=2                 │
   │─────────────────────────────────────────► │
   │                       (le portail se ferme, la sonde dort)
```

## 6. Dérive d'horloge

Identique au Bluetooth, et la raison est la même : sans quartz, l'oscillateur
RC de la veille dérive de quelques pour cent, soit jusqu'à 30 minutes sur
24 heures. La sonde n'essaie donc pas de tenir l'heure — elle horodate en
**tics** (ses propres secondes depuis la mise sous tension) et c'est
l'application qui recale.

Avec deux points de repère, la synchronisation précédente (`T₀`, `R₀`) et celle
en cours (`T₁`, `R₁`) :

```
heure_réelle(t) = R₀ + (t − T₀) × (R₁ − R₀) / (T₁ − T₀)
```

À la première synchronisation, faute de repère antérieur :
`heure_réelle(t) = R₁ − (T₁ − t)`.

Conservez donc `(tics, heure du téléphone)` à chaque synchronisation. Le détail
est au § 6 de `PROTOCOLE-BLE.md`.

## 7. Températures

Des **centièmes de degré, en entier**, partout et dans les deux protocoles.
Jamais de virgule flottante : `Int` côté Swift, `/ 100` à l'affichage
seulement. Un JSON qui transporterait `6.55` inviterait chaque client à arrondir
à sa façon, et deux relevés du même instant ne seraient plus comparables.

Une mesure ratée vaut `null`, **jamais** `-32768`. La valeur sentinelle existe
dans les trames Bluetooth parce qu'un `int16` n'a pas de « rien » ; en JSON le
langage a le mot, donc on l'emploie. Un client qui oublierait de vérifier
tracerait sinon une chambre froide à −327,68 °C.

## 8. Ce que le Bluetooth garde pour lui

Une chose, et elle compte pour la tournée quotidienne : **l'annonce Bluetooth
porte la température**. La tablette voit les quatre sondes et leurs
températures d'un seul scan, sans se connecter à rien, sans changer de réseau,
sans réveiller personne. C'est deux secondes pour la tournée du matin.

Le portail HTTP, lui, demande une connexion par sonde. Il est meilleur pour
lire un historique complet, pour étalonner, et pour être lu depuis un iPhone.

D'où le partage, si vous gardez les deux : le Bluetooth pour voir, le portail
pour relever.

## 9. Sécurité — ce qui protège quoi

| | Ce qui protège | Ce que ça ne protège pas |
| --- | --- | --- |
| `PORTAIL_AP` | le mot de passe WPA2 `PORTAIL_MDP` | rien d'autre : qui a le mot de passe a tout |
| `PORTAIL_STATION` | le réseau de l'hôtel | tout appareil déjà sur ce réseau peut écrire |

Il n'y a **aucune authentification par requête**. Sur un réseau accessible,
n'importe qui peut donc appeler `/acquitter` et faire disparaître des relevés
non lus, ou déplacer l'étalonnage avec `/etalonner`.

C'est acceptable pour un réseau privé d'hôtel et un enjeu de cette taille, mais
il faut le savoir et en tirer deux conséquences :

- **mettez un mot de passe au point d'accès.** Huit caractères minimum, sinon
  l'ESP32 crée un réseau ouvert sans le dire ;
- **n'exposez jamais une sonde depuis Internet.** Pas de redirection de port,
  pas d'UPnP. Le portail n'est pas écrit pour ça.

Le trafic est en HTTP, non chiffré. Sur le lien local d'une sonde posée sur un
frigo, ce qui circule est une température : ajouter du TLS demanderait un
certificat à maintenir pendant les années de vie de la sonde, pour protéger
l'information qu'il fait +6 °C dans la chambre froide.

## 10. Côté SwiftUI

Le contrat côté application, pour mémoire — l'application est votre travail,
ceci ne sert qu'à fixer les noms de champs :

```swift
struct EtatSonde: Decodable {
    let sonde: String
    let emplacement: String
    let centi: Int?          // null quand le capteur n'a pas répondu
    let pile: Int
    let tics: UInt32
    let attente: Int
    let alerte: Bool
    let pileFaible: Bool

    enum CodingKeys: String, CodingKey {
        case sonde, emplacement, centi, pile, tics, attente, alerte
        case pileFaible = "pile_faible"
    }

    var degres: Double? { centi.map { Double($0) / 100 } }
}

let base = URL(string: "http://192.168.4.1")!
let (data, _) = try await URLSession.shared.data(from: base.appending(path: "etat"))
let etat = try JSONDecoder().decode(EtatSonde.self, from: data)
```

Deux points qui coûtent du temps si on les découvre en route :

- **`Info.plist`** — iOS bloque le HTTP en clair. Il faut
  `NSAppTransportSecurity` → `NSAllowsLocalNetworking` à `true`. Sans ça la
  requête échoue sans explication utile.
- **Autorisation réseau local** — depuis iOS 14, la première requête vers une
  adresse locale déclenche une demande d'autorisation. Refusée une fois, elle
  ne se redemande pas : il faut aller dans Réglages.

Pour rejoindre le réseau de la sonde depuis l'application plutôt qu'à la main,
`NEHotspotConfiguration` le fait — mais l'entitlement *Hotspot Configuration*
demande un compte développeur payant. Sans lui, on rejoint le réseau dans
Réglages puis on revient dans l'application ; c'est exactement ce que demande
la caméra d'inspection.

---

Toute modification de ce format doit être reportée dans le programme de la
sonde (`firmware/sonde-haccp/sonde-haccp.ino`, section « Portail Wi-Fi ») et
ici. Les deux se relisent ensemble.
