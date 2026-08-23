# Éléments de marque

## Icône de l'application

Deux variantes prêtes à l'emploi, 1024 × 1024 px, opaques et sans coins
arrondis — iOS applique lui-même le masque.

| Fichier | Rendu |
|---|---|
| `AppIcon-1024-blanc.png` | Tracé bleu sur fond blanc. Sobre, lisible, registre médical / professionnel. |
| `AppIcon-1024-bleu.png` | Tracé blanc sur fond bleu `#17507F`. Ressort davantage sur un écran d'accueil chargé. |

### Installation dans Xcode

1. Dans le navigateur, ouvre **`Assets.xcassets`**
2. Sélectionne **`AppIcon`**
3. Glisse le PNG choisi dans l'emplacement **1024 pt**
4. `⌘R` — l'icône apparaît sur l'écran d'accueil du simulateur

⚠️ Ce dossier `Branding/` est **hors du dossier de l'application** : ces images
ne doivent pas être embarquées dans le bundle, seule celle déposée dans
`Assets.xcassets` compte.

## Logo dans l'application

`HACCPPocket/Resources/BrandLogo.png` est embarqué automatiquement et affiché
par la vue `BrandLogo`. C'est un PNG niveaux de gris + alpha : seul son tracé
compte, la couleur est appliquée à l'affichage, ce qui le rend lisible en mode
clair comme en mode sombre.

## Couleur de marque

`#17507F` — échantillonnée sur le tracé d'origine. Déclarée dans
`BrandAssets.color`, accessible partout via `Color.brand`.
