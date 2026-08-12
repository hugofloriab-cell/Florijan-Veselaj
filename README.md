# Menu & Avis — Web App restaurant

Application web responsive pensée pour être ouverte au **scan d'un QR code**
sur la table. Elle fait trois choses :

1. présenter la carte sous forme de **livret feuilletable** (flipbook) ;
2. proposer au client un **rappel différé** pour laisser un avis ;
3. **router les avis** : les bons vont vers Google / Tripadvisor / Booking,
   les mauvais restent en privé pour le gérant.

Aucun framework, aucune étape de build : du HTML, du CSS et du JavaScript.
Il suffit de déposer les fichiers sur un hébergement statique.

---

## Démarrage rapide

```bash
# depuis le dossier du projet
npx http-server -p 8080 -c-1
# puis ouvrir http://localhost:8080
```

Un simple `open index.html` fonctionne aussi, mais en `file://` le Service
Worker et les notifications sont désactivés par le navigateur. Pour tester
l'expérience complète, passez par un serveur HTTP (et par **HTTPS** en
production : les notifications l'exigent).

### Panneau gérant

`/admin.html` — mot de passe par défaut : **`gerant2024`**
(à changer, voir « Sécurité » plus bas).

---

## Tout se configure dans un seul fichier

`assets/js/config.js` regroupe l'intégralité des réglages : nom du
restaurant, source du menu, délais de rappel, liens d'avis publics, mot de
passe du panneau gérant.

### 1. Le menu

**Option A — des images** (par défaut) :

```js
menu: {
  type: "images",
  images: [
    "assets/menu/page-1.jpg",
    "assets/menu/page-2.jpg"
  ]
}
```

Formats acceptés : `jpg`, `png`, `webp`, `svg`. Conseil : des pages au même
format (A4 portrait, soit un ratio 1:1,414) et environ 1200 px de large.
Les six pages livrées en exemple sont des SVG, remplaçables directement.

**Option B — un fichier PDF** :

```js
menu: {
  type: "pdf",
  pdfUrl: "assets/menu/menu.pdf"
}
```

Le PDF est rendu page par page avec [PDF.js](https://mozilla.github.io/pdf.js/),
chargé depuis un CDN. Si la connexion du restaurant est mauvaise, déposez
`pdf.min.js` et `pdf.worker.min.js` sur votre serveur et indiquez-les :

```js
menu: {
  type: "pdf",
  pdfUrl: "assets/menu/menu.pdf",
  pdfjs: { lib: "assets/vendor/pdf.min.js", worker: "assets/vendor/pdf.worker.min.js" }
}
```

Si PDF.js reste injoignable, le livret affiche un message d'erreur lisible et
le reste de l'application (avis, rappel) continue de fonctionner.

### 2. Les liens d'avis publics

Remplacez les URL d'exemple par les vôtres :

```js
review: {
  threshold: 4,                       // note à partir de laquelle on redirige
  publicLinks: [
    { id: "google", label: "Google", url: "https://search.google.com/local/writereview?placeid=VOTRE_PLACE_ID", color: "#4285F4" },
    …
  ]
}
```

* **Google** — récupérez votre Place ID sur
  [ce vérificateur](https://developers.google.com/maps/documentation/places/web-service/place-id),
  puis utilisez `https://search.google.com/local/writereview?placeid=…`
* **Tripadvisor** — page de l'établissement → « Écrire un avis », copiez l'URL
* **Booking** — lien « Donnez votre avis » reçu après un séjour

Supprimez simplement les entrées inutiles du tableau.

### 3. Les délais de rappel

```js
reminder: {
  delays: [5, 10, 15, 20, 30, 40],   // en minutes
  defaultDelay: 15,
  askOnOpen: true,                   // pop-up dès l'ouverture
  snoozeHours: 4                     // ne pas re-proposer avant X heures
}
```

---

## Comment ça marche

### Le livret (`assets/js/flipbook.js`)

Composant autonome, sans dépendance. La page qui tourne est un élément 3D
(`rotateY`) dont la face avant porte la page courante et la face arrière la
page de destination — la même que celle rendue dessous, ce qui rend la
transition sans raccord.

* **le geste suit le doigt** : la rotation est pilotée par la position du
  pointeur, pas par une animation lancée à l'aveugle ; un relâchement avant
  un tiers de course fait revenir la page en arrière ;
* **zones tactiles** gauche/droite pour tourner au tap, flèches du clavier,
  curseur de navigation ;
* **double-tap** pour zoomer, glissé pour se déplacer dans la page zoomée ;
* **simple page sur mobile, double page au-delà de 820 px** de large ;
* pages voisines préchargées.

### Le rappel (`assets/js/reminder.js`)

À l'ouverture, une fenêtre propose au client un délai. S'il accepte :

* l'échéance est enregistrée dans `localStorage`, ce qui la rend **résistante
  au rechargement de la page et à la mise en veille** — au retour sur
  l'onglet, l'échéance est revérifiée plutôt que de faire confiance au seul
  `setTimeout`, que les navigateurs brident en arrière-plan ;
* une **notification Web** est envoyée si le client l'a autorisée (via le
  Service Worker, pour qu'un clic rouvre l'application sur le formulaire) ;
* un **minuteur visuel** reste affiché en bas de l'écran dans tous les cas :
  même sans autorisation de notification, le rappel fonctionne.

L'autorisation est demandée au moment où le client choisit un délai, jamais
au chargement — c'est ce que réclament les navigateurs, et c'est plus poli.

### Le routage des avis (`assets/js/review.js`)

| Note | Ce qui se passe |
|---|---|
| **≥ 4 étoiles** | Écran de remerciement + boutons vers Google, Tripadvisor et Booking. Le commentaire saisi peut être copié en un tap pour être collé sur la plateforme. |
| **1 à 3 étoiles** | L'avis est enregistré **en local uniquement** et n'apparaît que dans le panneau gérant. Rien n'est publié, rien n'est envoyé nulle part. |

Le client sait toujours ce qui va arriver : dès qu'une note est choisie, un
encart annonce clairement la destination de son message. Un formulaire qui
oriente en silence se retourne contre le restaurant le jour où un client s'en
aperçoit.

La photo (appareil photo ou galerie) est redimensionnée et compressée dans le
navigateur avant stockage. Note : pour un avis public, la photo **n'est pas**
transférée vers Google ou Tripadvisor — le client doit la joindre lui-même,
et l'application le lui rappelle.

### Le stockage (`assets/js/db.js`)

IndexedDB, avec repli automatique sur `localStorage` (navigation privée) et,
en dernier recours, conservation de l'avis sans la photo plutôt que de tout
perdre si le quota est atteint.

Pour centraliser les avis sur un serveur, renseignez :

```js
sync: { endpoint: "https://exemple.fr/api/avis", token: "…" }
```

Chaque avis **privé** est alors aussi envoyé en `POST` JSON. L'échec réseau
n'est jamais bloquant : l'avis reste dans le navigateur.

---

## Sécurité — à lire avant la mise en production

Le mot de passe du panneau gérant est vérifié **dans le navigateur** (SHA-256
comparé à une empreinte présente dans `config.js`). Cela empêche un client
curieux d'entrer ; cela n'arrête pas quelqu'un de motivé, qui peut lire
l'empreinte dans le code source.

C'est acceptable tant que les avis restent stockés dans le navigateur du
gérant, sur son appareil. Dès que vous branchez `sync.endpoint`, la vraie
protection doit être **côté serveur** (authentification, HTTPS, contrôle
d'accès), le panneau ne devenant qu'une façade.

Pour changer le mot de passe : ouvrez `admin.html`, puis dans la console du
navigateur :

```js
await hashPassword("mon-nouveau-mot-de-passe")
```

Copiez l'empreinte obtenue dans `config.js` → `admin.passwordSha256`.

Autres points :

* **Sauvegardez** régulièrement via le bouton « Exporter » (CSV + JSON) :
  vider les données du navigateur efface les avis.
* Ajoutez une mention d'information si vous collectez un e-mail ou un
  téléphone (RGPD) — le champ contact est facultatif et vide par défaut.
* `admin.html` porte un `noindex`, mais placez-le derrière une
  authentification serveur (`.htpasswd` par exemple) si c'est possible chez
  votre hébergeur. **GitHub Pages ne le permet pas** : l'adresse du panneau y
  est publique et le mot de passe reste la seule barrière. Changez-le avant
  la mise en ligne.

---

## Structure

```
index.html               écran client (menu + avis)
.github/workflows/       déploiement automatique sur GitHub Pages
.nojekyll                sert les fichiers tels quels, sans traitement Jekyll
admin.html               panneau gérant, protégé par mot de passe
manifest.webmanifest     installation sur l'écran d'accueil (PWA)
sw.js                    cache hors ligne + notifications
assets/
  css/styles.css         thème principal (mobile-first)
  css/admin.css          panneau gérant
  js/config.js           ← tous les réglages
  js/flipbook.js         livret 3D
  js/reminder.js         rappel différé + notifications
  js/review.js           formulaire et routage des avis
  js/db.js               stockage IndexedDB
  js/app.js              assemblage
  js/admin.js            tableau de bord
  menu/page-1…6.svg      pages de menu d'exemple
  img/                   icônes de l'application
```

---

## Mise en ligne avec GitHub Pages

Le dépôt contient déjà tout le nécessaire : `.github/workflows/pages.yml`
publie le site à chaque `push` sur `main`, sans étape de build. Une seule
manipulation reste à faire, une fois :

1. **Activer Pages** — dans le dépôt : `Settings` → `Pages` → *Build and
   deployment* → **Source : GitHub Actions**. (Pas « Deploy from a branch ».)
2. **Lancer le premier déploiement** — poussez sur `main`, ou allez dans
   l'onglet `Actions` → *Déployer sur GitHub Pages* → `Run workflow`.
3. L'adresse s'affiche à la fin du job, et ensuite dans `Settings` → `Pages` :
   `https://<votre-compte>.github.io/<nom-du-dépôt>/`

Tous les chemins de l'application sont relatifs : le site fonctionne
directement dans un sous-dossier, sans réglage supplémentaire. HTTPS est
fourni par GitHub, donc les notifications et l'appareil photo fonctionnent.

### Puis, avant d'ouvrir aux clients

1. Remplacez les pages de menu et complétez `config.js` (nom, liens d'avis).
2. **Changez le mot de passe du panneau gérant** — sur GitHub Pages,
   `admin.html` est accessible à qui connaît l'adresse.
3. Générez un QR code pointant vers l'URL (n'importe quel générateur gratuit
   fait l'affaire) et posez-le sur les tables.
4. Sur votre téléphone, ouvrez `/admin.html` et ajoutez-le à l'écran
   d'accueil : vous avez les retours privés à portée de main.

### Autres hébergeurs

Le site étant statique et sans build, il se dépose tel quel sur Netlify,
Vercel, o2switch, OVH… Sur un hébergeur classique, profitez-en pour protéger
`admin.html` par un `.htpasswd`. Exigence commune à tous : **HTTPS**, sans
quoi ni les notifications ni l'appareil photo ne sont autorisés.

---

## Compatibilité

Testé sur Chromium (mobile et bureau). L'application fonctionne sur Safari
iOS et Chrome Android ; deux réserves propres à iOS :

* les notifications Web exigent que le site soit **ajouté à l'écran
  d'accueil** (iOS 16.4+). Sans cela le minuteur visuel prend le relais, le
  rappel n'est jamais perdu ;
* `capture="environment"` ouvre l'appareil photo sur Android ; iOS propose un
  choix entre appareil photo et galerie — les deux boutons restent utiles.

Le mode PDF a été validé avec un PDF.js simulé (le CDN était inaccessible
depuis l'environnement de développement) : la chaîne de rendu, la pagination
et l'affichage sont vérifiés, mais faites un essai avec votre PDF réel avant
la mise en service.
