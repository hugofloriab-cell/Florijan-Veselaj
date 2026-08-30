# Protocole BLE des sondes HACCP

Contrat entre le firmware de la sonde (`firmware/sonde-haccp/`) et la fiche
(`checklist-petit-dejeuner.html`, section « Sondes de température »).

Toute modification doit être reportée **des deux côtés**.

---

## 1. Principe

La sonde est un **enregistreur**, pas un émetteur permanent : elle mesure toutes
les 30 minutes, garde les relevés en mémoire, et ne parle que par courtes
fenêtres. La tablette vient chercher l'historique une fois par jour.

C'est ce qui permet de tenir des années sur des piles : la radio est allumée
moins de 1 % du temps.

```
  toutes les 30 min          fenêtre d'annonce            aimant / bouton
  ┌──────────────┐           ┌──────────────┐             ┌──────────────┐
  │ réveil       │           │ annonce BLE  │             │ annonce BLE  │
  │ mesure T°    │──────────►│ 15 s         │             │ 120 s        │
  │ mesure pile  │           │ puis veille  │             │ (synchro     │
  │ rangement    │           └──────────────┘             │  immédiate)  │
  └──────────────┘                                        └──────────────┘
         │                            ▲
         └── veille profonde ─────────┘
             5 à 44 µA
```

## 2. Annonce (advertising)

| Champ | Contenu |
| --- | --- |
| Nom local | `HACCP-XXXX` — `XXXX` = 4 derniers chiffres hexadécimaux de l'adresse MAC |
| Service annoncé | `e9ea0001-6d2c-4f8b-9a35-0b7c1d4e5f60` |
| Données constructeur | identifiant `0xFFFF` (usage privé) puis la charge utile ci-dessous |

Charge utile constructeur, 7 octets — permet de lire la température **sans se
connecter**, dans le résultat de scan :

| Offset | Type | Contenu |
| --- | --- | --- |
| 0 | `uint8` | version du protocole (`1`) |
| 1 | `int16` LE | dernière température, en centièmes de °C (`0x8000` = invalide) |
| 3 | `uint8` | niveau de pile, 0–100 % |
| 4 | `uint16` LE | nombre de relevés en attente de synchronisation |
| 6 | `uint8` | drapeaux (voir § 3) |

## 3. Drapeaux

Bit à 1 = condition active.

| Bit | Nom | Signification |
| --- | --- | --- |
| 0 | `HORLOGE_OK` | l'horloge interne a été réglée par une tablette depuis le dernier démarrage |
| 1 | `ALERTE_T` | la dernière mesure est hors des seuils configurés |
| 2 | `PILE_FAIBLE` | tension sous le seuil d'alerte (par défaut 20 %) |
| 3 | `TAMPON_PLEIN` | le tampon a débordé : les relevés les plus anciens ont été perdus |
| 4 | `CAPTEUR_HS` | la dernière lecture du capteur a échoué |
| 5 | `REVEIL_MANUEL` | la fenêtre en cours a été déclenchée par l'aimant ou le bouton |

## 4. Service GATT

Service `e9ea0001-6d2c-4f8b-9a35-0b7c1d4e5f60`.

### 4.1 Caractéristique « État » — `e9ea0002-6d2c-4f8b-9a35-0b7c1d4e5f60`

Propriétés : `read`, `notify`. Longueur 20 octets.

| Offset | Type | Contenu |
| --- | --- | --- |
| 0 | `uint8` | version du protocole (`1`) |
| 1 | `uint8` | drapeaux (§ 3) |
| 2 | `uint16` LE | tension d'alimentation, en mV |
| 4 | `uint8` | niveau de pile, 0–100 % |
| 5 | `uint8` | intervalle d'échantillonnage, en minutes |
| 6 | `int16` LE | dernière température, centièmes de °C |
| 8 | `uint16` LE | relevés en attente |
| 10 | `uint32` LE | **tics** : secondes écoulées depuis la mise sous tension |
| 14 | `uint32` LE | horodatage Unix de référence, tel que réglé par la commande `0x01` (`0` si jamais réglé) |
| 18 | `int16` LE | offset d'étalonnage appliqué, centièmes de °C |

Les **tics** sont l'horloge propre de la sonde. Ils ne dérivent pas de la même
façon que l'heure réelle (voir § 6).

### 4.2 Caractéristique « Historique » — `e9ea0003-6d2c-4f8b-9a35-0b7c1d4e5f60`

Propriétés : `notify`. Émise en rafale après la commande `0x02`.

Chaque notification : en-tête de 4 octets puis N relevés de 8 octets.

En-tête :

| Offset | Type | Contenu |
| --- | --- | --- |
| 0 | `uint16` LE | index du premier relevé du paquet |
| 2 | `uint16` LE | nombre de relevés dans ce paquet (`0` = fin du déversement) |

Relevé (8 octets) :

| Offset | Type | Contenu |
| --- | --- | --- |
| 0 | `uint32` LE | tics au moment de la mesure |
| 4 | `int16` LE | température, centièmes de °C (`0x8000` = mesure ratée) |
| 6 | `uint8` | niveau de pile à cet instant, 0–100 % |
| 7 | `uint8` | drapeaux à cet instant (§ 3) |

Le nombre de relevés par paquet s'adapte au MTU négocié :
`N = min(20, (MTU - 3 - 4) / 8)`. Chrome négocie 517 octets, donc 20 en pratique.
Un paquet final avec `nombre = 0` clôt le déversement.

### 4.3 Caractéristique « Commande » — `e9ea0004-6d2c-4f8b-9a35-0b7c1d4e5f60`

Propriétés : `write`. Premier octet = code de commande.

| Code | Charge utile | Effet |
| --- | --- | --- |
| `0x01` | `uint32` LE horodatage Unix | Règle l'horloge de référence et lève `HORLOGE_OK`. À envoyer à chaque connexion. |
| `0x02` | `uint16` LE index de départ | Démarre le déversement de l'historique. `0xFFFF` = tout ce qui est en attente. |
| `0x03` | `uint16` LE index | Acquitte jusqu'à cet index inclus : les relevés plus anciens sont libérés. |
| `0x04` | `uint8` minutes (1–240) | Change l'intervalle d'échantillonnage. |
| `0x05` | `int16` LE centi-°C | Règle l'offset d'étalonnage (ajouté à chaque mesure). |
| `0x06` | `int16` LE min, `int16` LE max | Règle les seuils d'alerte, en centièmes de °C. |
| `0x07` | — | Maintient la sonde éveillée 5 minutes (maintenance, étalonnage). |
| `0x08` | jusqu'à 16 octets UTF-8 | Enregistre le libellé d'emplacement dans la sonde. |

Toute commande inconnue est ignorée.

## 5. Séquence de synchronisation

```
tablette                                        sonde
   │  requestDevice (filtre sur le service)      │
   │───────────────────────────────────────────► │
   │  connect + négociation MTU                  │
   │◄──────────────────────────────────────────► │
   │  lecture « État »                           │
   │───────────────────────────────────────────► │
   │  0x01 <heure Unix de la tablette>           │
   │───────────────────────────────────────────► │
   │  souscription « Historique »                │
   │───────────────────────────────────────────► │
   │  0x02 0xFFFF                                │
   │───────────────────────────────────────────► │
   │             paquets de relevés              │
   │◄─────────────────────────────────────────── │
   │             … paquet vide (fin)             │
   │◄─────────────────────────────────────────── │
   │  0x03 <dernier index reçu>                  │
   │───────────────────────────────────────────► │
   │  déconnexion                                │
   │───────────────────────────────────────────► │
```

L'acquittement (`0x03`) n'est envoyé qu'**après** écriture des relevés dans le
stockage de la tablette. Si la synchronisation échoue en cours de route, la
sonde garde tout et on recommence : aucun relevé n'est perdu.

## 6. Correction de la dérive d'horloge

Sans quartz, l'ESP32-C3 compte le temps de veille avec un oscillateur RC dont
la dérive atteint quelques pour cent. Sur 24 heures cela fait jusqu'à 30 minutes
d'erreur — inacceptable pour un relevé horodaté.

La sonde n'essaie donc pas de tenir l'heure : elle horodate en **tics** (ses
propres secondes), et la tablette recale après coup.

À chaque synchronisation, la tablette connaît deux points de repère :

- la synchronisation précédente : tics `T₀`, heure réelle `R₀` ;
- la synchronisation en cours : tics `T₁`, heure réelle `R₁`.

Un relevé pris à `t` tics est daté par interpolation linéaire :

```
heure_réelle(t) = R₀ + (t − T₀) × (R₁ − R₀) / (T₁ − T₀)
```

À la première synchronisation, faute de repère antérieur, on retient
`heure_réelle(t) = R₁ − (T₁ − t)` (cadence nominale).

Cette correction est faite par l'application, dans `sondeDater()`. Elle ramène
l'erreur d'horodatage à quelques secondes, quelle que soit la dérive du RC.

Un quartz 32,768 kHz sur la version série (§ nomenclature du `README.md`) ramène
la dérive brute à 20 ppm — la correction reste alors sans effet visible, mais
elle ne gêne pas.

## 7. Choix qui expliquent le format

- **Centièmes de degré en `int16`** : couvre −327 à +327 °C au centième, sur
  2 octets. Le flottant coûterait le double sans rien apporter : aucun capteur
  de la nomenclature ne descend sous le centième.
- **8 octets par relevé** : 48 relevés/jour = 384 octets/jour. Les 5 Ko de
  mémoire RTC gardent donc 13 jours — largement de quoi encaisser un week-end
  prolongé sans tablette.
- **Le niveau de pile est stocké à chaque relevé**, pas seulement en direct :
  c'est ce qui permet à l'application de tracer la pente de décharge et d'en
  déduire une autonomie restante plutôt qu'un pourcentage instantané, très
  bruité par la température.
- **L'acquittement est explicite** : la sonde ne jette rien tant que la tablette
  n'a pas confirmé l'écriture.
