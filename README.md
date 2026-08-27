# Check-list & Hygiène Petit Déjeuner — Hôtel Ibis Sisteron

Version dématérialisée de la fiche papier « Check-list & Hygiène Petit Déjeuner »,
conçue pour la tablette de la cuisine.

## Fichiers

| Fichier | Usage |
| --- | --- |
| `checklist-petit-dejeuner.html` | **La source.** Page autonome, copiable telle quelle sur une tablette. |
| `docs/` | **Version installable publiée sur le web** (voir ci-dessous). Générée. |
| `.artifact/checklist-petit-dejeuner.html` | Version publication en ligne. Générée. |
| `build.py` | Régénère `docs/` et `.artifact/` depuis la source. |

Ne modifiez que `checklist-petit-dejeuner.html`, puis lancez `python3 build.py`.

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

1. **Enregistrer** `checklist-petit-dejeuner.html` sur la tablette — et non « ouvrir ».
   Le fichier arrive dans les Téléchargements.
2. Ouvrir **Chrome**, puis saisir cette adresse dans la barre du haut :
   `file:///sdcard/Download/`
3. Dans la liste, taper sur `checklist-petit-dejeuner.html`.
4. Menu **⋮ → Ajouter à l'écran d'accueil** : la fiche se lance comme une application.

L'étape 2 est la plus fiable : elle évite la boîte « Ouvrir avec », qui renvoie
souvent la fiche vers un aperçu incapable d'exécuter le script.

Aucune connexion Internet n'est nécessaire au quotidien.

> **Ouvrez bien le fichier avec Chrome, pas depuis un aperçu.**
> Dans une fenêtre d'aperçu (pièce jointe consultée directement dans une
> application de messagerie, page intégrée), le navigateur bloque l'impression,
> l'ouverture de la messagerie et l'enregistrement de fichiers. La fiche le
> détecte et affiche un bandeau d'avertissement. Le pointage des tâches et la
> signature, eux, fonctionnent partout.

## Installation recommandée : par adresse web

Copier le fichier sur chaque tablette est fastidieux, et les aperçus de pièces
jointes n'exécutent pas le script — la fiche s'affiche alors sans pouvoir être
signée ni enregistrée. La publication web supprime ce problème.

### Mise en ligne (une seule fois)

Dans le dépôt GitHub : **Settings → Pages → Build and deployment**

- *Source* : **Deploy from a branch**
- *Branch* : la branche contenant ce dossier, et **`/docs`** comme répertoire
- **Save**

Au bout d'une minute, la page affiche l'adresse publique, de la forme
`https://<compte>.github.io/<dépôt>/`.

### Installation sur chaque tablette

1. Ouvrir **Chrome**, saisir cette adresse.
2. Menu **⋮ → Ajouter à l'écran d'accueil**.

La fiche se lance alors en plein écran, avec sa propre icône, **sans barre
d'adresse et sans connexion Internet** : le service worker (`docs/sw.js`) la
conserve sur l'appareil. Seule la première ouverture demande du réseau.

### Mettre à jour la fiche

Modifier `checklist-petit-dejeuner.html`, lancer `python3 build.py`, incrémenter
`CACHE` dans `docs/sw.js` (`checklist-pdj-v1` vers `v2`...), puis pousser. Les
tablettes récupèrent la nouvelle version à leur prochaine ouverture avec réseau.
Sans changement de `CACHE`, elles gardent l'ancienne.

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

Après modification, régénérer les versions dérivées avec `python3 build.py`.
