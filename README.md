# Check-list & Hygiène Petit Déjeuner — Hôtel Ibis Sisteron

Version dématérialisée de la fiche papier « Check-list & Hygiène Petit Déjeuner »,
conçue pour la tablette de la cuisine.

## Fichiers

| Fichier | Usage |
| --- | --- |
| `checklist-petit-dejeuner.html` | **Fichier à installer sur la tablette.** Page autonome, fonctionne hors connexion. |
| `.artifact/checklist-petit-dejeuner.html` | Même page, format publication en ligne (générée depuis le fichier ci-dessus). |

## Ce que fait la fiche

- Les 25 tâches de la fiche papier, dans le même ordre et avec les mêmes rappels HACCP.
- Une case à cocher par tâche ; la pastille **VAL.** de chaque créneau horaire passe au vert
  automatiquement quand toutes ses tâches sont validées.
- Bloc de fin de service : nom de l'agent, heure de fin de cleaning, conformité OUI/NON,
  signature tactile au doigt.
- Champ « Observations & anomalies » (rupture de stock, T° non conforme, produit jeté…).
- Sauvegarde automatique à chaque clic, dans la tablette. Une fiche par date.
- Historique des fiches enregistrées, consultables et rouvrables.
- Export **CSV** (ouvrable dans Excel) et **JSON** (sauvegarde complète), plus impression / PDF.
- Mode clair et mode sombre (le service commence à 6h00).

## Installation sur la tablette

1. Copier `checklist-petit-dejeuner.html` sur la tablette (câble USB, clé USB ou e-mail).
2. Ouvrir le fichier avec Chrome.
3. Menu de Chrome → **Ajouter à l'écran d'accueil** : la fiche s'ouvre comme une application.

Aucune connexion Internet n'est nécessaire au quotidien.

## Où sont stockées les données

Dans le stockage local du navigateur de la tablette (`localStorage`), sur cet appareil
uniquement. Les fiches ne sont donc **pas** synchronisées entre plusieurs tablettes.

> Effacer les données de navigation de Chrome supprime les fiches enregistrées.
> Exporter le CSV ou le JSON en fin de semaine ou de mois pour conserver l'historique.

## Modifier le contenu de la fiche

Les tâches sont décrites en haut du bloc `<script>` de `checklist-petit-dejeuner.html`,
dans les tableaux `SLOTS` (déroulé horaire) et `EXTRA` (tâches supplémentaires).
Ajouter, retirer ou reformuler une ligne suffit : cases, compteurs et export suivent.

Après modification, régénérer la version publication :

```sh
python3 - <<'PY'
s = open('checklist-petit-dejeuner.html', encoding='utf-8').read()
frag = s.split('<!--ARTIFACT-START-->')[1].split('<!--ARTIFACT-END-->')[0]
frag = '\n'.join(l for l in frag.split('\n') if l.strip() not in ('</head>', '<body>'))
open('.artifact/checklist-petit-dejeuner.html', 'w', encoding='utf-8').write(frag.strip() + '\n')
PY
```
