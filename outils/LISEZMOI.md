# Rendre une nouvelle carte

`rendre-carte.py` transforme le PDF du restaurant en pages affichables par
l'application. **Rien n'est recomposé** : chaque page est rendue telle
quelle, à 1800 px de large, en WebP. La mise en page, les photos, les
couleurs et les polices du document d'origine sont conservées.

```bash
python3 rendre-carte.py fr    # produit assets/menu/carte-fr-1.webp …
python3 rendre-carte.py en    # produit assets/menu/carte-en-1.webp …
```

Le script attend les chemins des PDF en haut du fichier ; adaptez-les, puis
reportez la liste des pages dans `assets/js/config.js` (`menu.images` et
`menu.imagesEn`) et dans `sw.js` (`PRECACHE`), sans oublier d'y changer le
numéro de version du cache.

Dépendances : `pymupdf` et `opencv-python`.

## Le cadrage du bouton « Agrandir »

Une page A4 fait 595 points de large, l'écran d'un téléphone 390 : le texte
y perd un tiers de sa taille et les prix tombent à 7 pixels. Aucun découpage
n'y change rien — l'échelle ne dépend que de la largeur montrée, jamais de
la hauteur : couper une page en deux dans le sens de la hauteur donne
exactement le même corps de texte. Seul le zoom agit.

`bandes.py` calcule donc, page par page, quelle bande de la largeur le
bouton « Agrandir » doit cadrer, à partir des boîtes de texte du PDF :

```bash
python3 bandes.py    # affiche les tableaux à coller dans config.js
```

Le résultat va dans `menu.lecture.pages` de `assets/js/config.js`. La
maquette alterne les colonnes — photos à gauche page 2, à droite page 3,
deux colonnes page 4 — et un cadrage unique couperait un nom de plat sur
deux. `menu.lecture.defaut` sert aux cartes déposées depuis le panneau
gérant, dont on ne connaît pas la maquette.

Pour que les prix soient lisibles **sans que le client ait à agrandir**, il
faudrait que le PDF lui-même soit dessiné au format d'un téléphone (page
étroite, texte plus gros). L'application afficherait ce PDF-là tel quel, lui
aussi.

## Pourquoi pas le PDF affiché directement ?

L'application sait le faire (`menu.type: "pdf"`), et le rendu serait
vectoriel, donc net à tout niveau de zoom. Mais cela suppose de charger
PDF.js depuis un CDN à chaque ouverture : une dépendance extérieure, et un
écran vide si ce CDN est lent ou bloqué. Des images rendues à l'avance ne
dépendent de personne et s'affichent instantanément.
