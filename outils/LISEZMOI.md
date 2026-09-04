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

## Pourquoi pas le PDF affiché directement ?

L'application sait le faire (`menu.type: "pdf"`), et le rendu serait
vectoriel, donc net à tout niveau de zoom. Mais cela suppose de charger
PDF.js depuis un CDN à chaque ouverture : une dépendance extérieure, et un
écran vide si ce CDN est lent ou bloqué. Des images rendues à l'avance ne
dépendent de personne et s'affichent instantanément.
