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

## Transmission à la direction

Bouton **Transmettre**. À la clôture d'une fiche, la tablette propose l'envoi directement.

Les destinataires se saisissent une fois et sont mémorisés. Trois contenus possibles :

| Contenu | Ce que reçoit le destinataire |
| --- | --- |
| Récapitulatif du jour | Un texte lisible dans le corps de l'e-mail : avancement, **liste des tâches non validées**, anomalies, émargement. |
| Historique complet (CSV) | Le tableau de toutes les fiches, ouvrable dans Excel. |
| Sauvegarde complète (JSON) | Toutes les données, pour archivage ou changement de tablette. |

Deux voies d'envoi, selon ce que propose la tablette :

- **Partager…** — ouvre le partage Android : Gmail, Outlook, Drive, WhatsApp.
  Pour le CSV et le JSON, le fichier part directement en pièce jointe.
- **Envoyer par e-mail** — ouvre l'application de messagerie avec destinataires,
  objet et message déjà remplis. Il ne reste qu'à appuyer sur Envoyer.

Aucun serveur, aucun compte à créer : la tablette utilise la messagerie déjà
installée dessus.

## Installation sur la tablette

1. Copier `checklist-petit-dejeuner.html` sur la tablette (câble USB, clé USB ou e-mail).
2. Ouvrir le fichier avec Chrome.
3. Menu de Chrome → **Ajouter à l'écran d'accueil** : la fiche s'ouvre comme une application.

Aucune connexion Internet n'est nécessaire au quotidien.

> **Ouvrez bien le fichier avec Chrome, pas depuis un aperçu.**
> Dans une fenêtre d'aperçu (pièce jointe consultée directement dans une
> application de messagerie, page intégrée), le navigateur bloque l'impression,
> l'ouverture de la messagerie et l'enregistrement de fichiers. La fiche le
> détecte et affiche un bandeau d'avertissement. Le pointage des tâches et la
> signature, eux, fonctionnent partout.

## Où sont stockées les données

Dans le stockage local du navigateur de la tablette (`localStorage`), sur cet appareil
uniquement. Les fiches ne sont donc **pas** synchronisées entre plusieurs tablettes.

> Effacer les données de navigation de Chrome supprime les fiches enregistrées.
> Exporter le CSV ou le JSON en fin de semaine ou de mois pour conserver l'historique.

## Modifier le contenu de la fiche

Les lignes de la check-list sont écrites **en dur** dans le corps de la page
(`<div class="slots">` et `<div class="tasklist" id="extra-tasks">`), afin que la
fiche reste complète, lisible et imprimable même si le script ne s'exécute pas.

Le bloc `<script>` contient les mêmes libellés dans les tableaux `SLOTS` et `EXTRA`,
utilisés pour les compteurs de validation et pour l'export. **Toute modification doit
être reportée aux deux endroits**, en conservant les identifiants `t<créneau>-<ligne>`
et `x<n>` des cases à cocher.

Après modification, régénérer la version publication :

```sh
python3 - <<'PY'
s = open('checklist-petit-dejeuner.html', encoding='utf-8').read()
frag = s.split('<!--ARTIFACT-START-->')[1].split('<!--ARTIFACT-END-->')[0]
frag = '\n'.join(l for l in frag.split('\n') if l.strip() not in ('</head>', '<body>'))
open('.artifact/checklist-petit-dejeuner.html', 'w', encoding='utf-8').write(frag.strip() + '\n')
PY
```
