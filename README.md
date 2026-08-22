# HACCP Pocket

Application iOS / iPadOS / macOS de traçabilité sanitaire (HACCP) pour la
restauration indépendante. 100 % local : aucune donnée ne quitte l'appareil,
aucun serveur, aucun compte.

## Périmètre fonctionnel

- Relevés de température des enceintes froides et du maintien au chaud
- Traçabilité des produits entamés (DLC secondaire, lot, photo d'étiquette)
- Contrôle des marchandises à réception
- Plan de nettoyage et de désinfection avec preuve d'exécution
- Export PDF mensuel « prêt pour le contrôle »

## Stack

- SwiftUI (iOS 17+), architecture MVVM
- SwiftData pour la persistance locale
- Vision pour l'OCR des DLC et la lecture des codes-barres
- PDFKit pour les exports, Swift Charts pour les courbes
- RevenueCat pour l'abonnement

## Arborescence

```
HACCPPocket/
├── App/         Point d'entrée, schéma SwiftData, amorçage, réglages, formatage
├── Models/      Entités @Model
├── Services/    Notifications locales, OCR Vision
├── ViewModels/  Logique métier et état des formulaires
└── Views/       Écrans SwiftUI
```

## Avancement

- [x] Step A — Modèles de données SwiftData
- [x] Step B — ViewModels, services de notification et OCR
- [x] Step C1 — Navigation, tableau de bord, registre des températures
- [x] Step C2 — Produits, nettoyage, réception, réglages
- [ ] Step D — Paywall RevenueCat
