# TV Kosova — lecteur de playlist M3U

Application web qui lit une playlist M3U (chaînes en direct HLS `.m3u8`) sur un
ordinateur, un téléphone ou une Smart TV. Publiée avec le reste de `docs/` sur
GitHub Pages, à l'adresse `…/tv/`.

| Fichier | Rôle |
| --- | --- |
| `index.html` | L'application (liste des chaînes + lecteur). |
| `chaines.m3u` | Playlist chargée par défaut. **C'est elle qu'on complète.** |
| `hls.min.js` | Lecteur HLS (hls.js 1.5.13, licence Apache-2.0), inclus pour ne dépendre d'aucun CDN. |
| `manifest.webmanifest`, `icone.svg` | Installation sur l'écran d'accueil. |

## Ajouter une chaîne

Dans `chaines.m3u`, deux lignes par chaîne :

    #EXTINF:-1 tvg-logo="https://…/logo.png" group-title="Kosovë",RTK 1
    https://…/live.m3u8

On peut aussi charger une autre playlist depuis l'application (fichier, adresse
web ou copier-coller) : elle reste enregistrée sur l'appareil.

## Télécommande / clavier

Flèches haut/bas : parcourir la liste (ou zapper quand la liste est masquée) ·
OK/Entrée : regarder · CH+/CH− ou Page préc./suiv. : zapper · chiffres : aller à
la chaîne n° · L : liste · F : plein écran · Retour/Échap : afficher/masquer la liste.

## Limites à connaître

- Page en `https` : les flux en `http` ne peuvent pas être lus.
- Un flux qui n'autorise pas la lecture depuis un autre site (CORS) échouera
  dans Chrome ; Safari et beaucoup de télés le liront quand même.
- N'utilisez que des flux diffusés officiellement par les chaînes.

## Si une chaîne affiche une erreur (ex. RTK 1)

Les adresses changent. Pour retrouver la bonne, sur un ordinateur avec Chrome :

1. Ouvrez la page du direct sur le site officiel (pour RTK : rtklive.com, rubrique « Live »).
2. Clic droit > Inspecter > onglet **Réseau** (Network), tapez `m3u8` dans le filtre.
3. Lancez la vidéo : copiez l'adresse qui apparaît (clic droit > Copy > Copy URL).
4. Remplacez l'ancienne adresse dans `chaines.m3u`.

## L'appli Android TV (sans curseur)

Le dossier `android/` contient une petite appli « TV Kosova » qui ouvre cette page
en plein écran, pilotée directement à la télécommande, et qui apparaît dans la liste
d'applications de la télé. Elle lit aussi les flux en `http` (TV Dielli, TV Opoja).

Elle est construite automatiquement par le workflow Pages et publiée à l'adresse
`…/tv/tv-kosova.apk`.

Installation sur une télé Google TV / Android TV :

1. Play Store de la télé : installer **Downloader** (de AFTVnews).
2. Paramètres > Système > À propos > appuyer 7 fois sur « Build Android TV OS »
   pour activer les options développeur, puis Paramètres > Applications >
   Sécurité et restrictions > **Sources inconnues** : autoriser Downloader.
3. Dans Downloader, taper l'adresse de l'APK, télécharger, puis **Installer**.

Les chaînes et l'appli web se mettent à jour toutes seules : l'APK n'est à
réinstaller que si le dossier `android/` change. Dans ce cas, désinstaller
d'abord l'ancienne version (l'APK est signé avec une clé de débogage
différente à chaque construction, pour ne garder aucune clé dans le dépôt).
