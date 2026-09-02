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

## Deux façons de configurer

**Depuis le panneau gérant** (`admin.html` → onglet *Réglages*) : carte,
identité, liens d'avis, délais de rappel et mot de passe se modifient sans
toucher au code. Voir « Modifier le contenu sans code » plus bas.

**Dans le fichier `config.js`** : ce sont les valeurs d'usine, celles qui
s'appliquent quand rien n'a été publié depuis le panneau.

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

### L'affichage plein écran

Un site ne peut pas masquer la barre d'adresse du navigateur : c'est une
protection, un site ne doit pas pouvoir se faire passer pour un autre. Ce que
l'application fait à la place :

* elle **passe en plein écran au premier geste sur la carte** (réglable par
  `ui.autoFullscreen`), ce qui masque effectivement les barres sur Android ;
* un bouton ⤢ dans l'en-tête permet d'entrer et de sortir à tout moment ;
* sur iPhone, Safari n'autorise pas le plein écran : le bouton est alors
  masqué plutôt que d'être inerte. La seule voie y est « Ajouter à l'écran
  d'accueil », qui ouvre l'application sans aucune barre.

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
* une **notification Web** est envoyée si le client l'a autorisée. Elle passe
  obligatoirement par le Service Worker : Chrome Android refuse le
  constructeur `new Notification()` et lève une exception ;
* un **minuteur visuel** reste affiché en bas de l'écran dans tous les cas :
  même sans autorisation de notification, le rappel fonctionne.

L'autorisation est demandée au moment où le client choisit un délai, jamais
au chargement — c'est ce que réclament les navigateurs, et c'est plus poli.

### Ce que le rappel ne peut pas faire (à lire)

**Si le client ferme l'onglet, aucune notification ne partira.** Un site
statique n'a aucun moyen d'exécuter du code à une heure donnée : le rappel
repose sur la page, et quand la page meurt, le minuteur meurt avec elle.
Android est le plus strict — il gèle puis supprime les onglets en arrière-plan
au bout de quelques minutes.

Trois conséquences pratiques :

1. dès que le client choisit un délai, une **notification de confirmation**
   est postée immédiatement (« Rappel prévu vers 21 h 15 »). C'est la seule
   entrée dont on soit certain dans le volet de notifications ; elle porte le
   même `tag`, donc le vrai rappel la remplacera s'il peut partir ;
2. l'application demande explicitement de **garder la page ouverte** ;
3. le **minuteur visuel** reste la voie fiable : il retrouve son échéance au
   retour sur la page, même après un rechargement.

Pour un rappel qui fonctionne onglet fermé, il faut la **Web Push API**, donc
un serveur qui garde les abonnements et déclenche l'envoi à l'heure dite
(clés VAPID + une tâche planifiée). C'est un vrai composant serveur, pas une
option à cocher : le `sync.endpoint` de `config.js` est le point de départ
naturel si vous voulez aller jusque-là.

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

## Recevoir les avis chez vous (Supabase)

**Sans serveur, les avis privés ne vous parviennent pas.** Ils sont écrits
dans le navigateur du client, sur son téléphone à lui ; le panneau gérant lit
la base de l'appareil sur lequel il est ouvert. Le filtrage fonctionne — rien
n'est publié — mais la partie « pour que le gérant puisse s'améliorer » reste
lettre morte.

Brancher Supabase corrige cela, gratuitement, et apporte au passage une vraie
authentification pour le panneau.

### Mise en place — trois étapes

**1. Créer le projet.** Sur [supabase.com](https://supabase.com), nouveau
projet, région **Europe (Paris)**. La région ne peut pas être changée ensuite.

**2. Créer la table.** Menu de gauche → *SQL Editor* → *New query* → coller le
contenu de `serveur/schema.sql` → *Run*. Une seule fois.

**3. Créer votre compte gérant.** *Authentication* → *Users* → *Add user* →
votre e-mail et un mot de passe solide. Cochez *Auto Confirm User*.

Puis dans `assets/js/config.js` (ou depuis le panneau, onglet Réglages) :

```js
serveur: {
  url: "https://xxxxxxxx.supabase.co",   // Settings → API → Project URL
  cleAnon: "sb_publishable_..."          // Settings → API → clé publique
}
```

Le panneau gérant demande alors un e-mail en plus du mot de passe : c'est
Supabase qui vérifie, plus la page.

### Pourquoi la clé dans la page n'est pas une faille

La clé publique (`sb_publishable_…`, ou `anon public` dans l'ancien format)
l'est par conception — elle est dans le code de la page, visible de tous. Ce qui protège les données, ce sont les règles RLS de
`schema.sql` : le public peut **déposer** un avis, jamais en **lire** un. Une
lecture avec la seule clé publique renvoie une erreur 401. Lire, modifier ou
supprimer exige une session ouverte avec votre compte.

### Rien ne se perd

L'avis est d'abord écrit sur le téléphone du client, puis envoyé. Si le réseau
manque, il reste sur place et repart tout seul au prochain passage sur la page.
Le panneau signale les avis en attente plutôt que de faire comme s'ils
n'existaient pas.

### Vos obligations

Les avis quittent le téléphone du client : vous en devenez responsable.
`schema.sql` fournit une fonction `purge_avis_anciens()` qui efface les avis
de plus de douze mois, à planifier ou à lancer à la main. Le champ contact
reste facultatif et vide par défaut.

---

## Modifier le contenu sans code

Le panneau gérant contient un éditeur (onglet **Réglages**) qui permet de
changer la carte, l'identité, les liens d'avis, les délais et le mot de passe.

### Comment ça marche

Le site est **statique** : le navigateur du gérant ne peut rien écrire sur
l'hébergement. L'éditeur produit donc un fichier, `contenu.json`, que le
gérant dépose dans `assets/`. Trois couches se superposent :

| Couche | Fichier | Vue par |
|---|---|---|
| Valeurs d'usine | `assets/js/config.js` | tout le monde |
| Version publiée | `assets/contenu.json` | tout le monde |
| Aperçu local | `localStorage` | le gérant seul, sur son appareil |

### Le geste, du début à la fin

1. **Réglages** → déposez un PDF ou des images. Un PDF est découpé page par
   page dans le navigateur ; les images sont redimensionnées à 1400 px.
   Réordonnez ou supprimez des pages avec les flèches et la croix.
2. **Prévisualiser sur cet appareil** — la carte s'ouvre avec vos
   modifications, mais seulement chez vous. Un bandeau doré le rappelle en
   haut de l'application, avec un bouton pour revenir en arrière.
3. **Télécharger contenu.json**, puis déposer ce fichier dans le dossier
   `assets/` de votre site. Sur GitHub : `assets/` → *Add file* → *Upload
   files*. Les clients voient le changement au rechargement suivant.

Le poids du fichier est affiché en permanence. Tant que la carte reste celle
déjà en ligne, il ne pèse que quelques kilo-octets : ce ne sont que des
chemins. Dès que vous importez une nouvelle carte, les images voyagent dans
le fichier — comptez environ 150 Ko par page.

### Ce que l'éditeur ne fait pas

Il ne publie pas à votre place : le dépôt du fichier reste manuel. C'est le
prix d'un site sans serveur — en échange, il n'y a ni base de données, ni
abonnement, ni panne possible côté serveur.

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
  contenu.json           contenu publié depuis le panneau gérant
  js/config.js           ← valeurs d'usine
  js/contenu.js          superposition config.js / contenu.json / aperçu
  js/serveur.js          liaison Supabase (facultative)
serveur/schema.sql       table des avis, règles d'accès, purge RGPD
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
