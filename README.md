# Melodix

Application mobile de création musicale IA — avec une différence : le morceau reste **éditable après sa génération**.

Là où les outils actuels produisent un fichier figé, Melodix produit un projet versionné : pistes séparées,
sections repérées, paroles structurées. On corrige un refrain, on change de genre, on retire un instrument —
sans tout régénérer et sans perdre son morceau.

## Documentation

- [`docs/ROADMAP.md`](docs/ROADMAP.md) — vision technique, architecture, 5 phases, risques
- [`docs/PHASE-1.md`](docs/PHASE-1.md) — plan opérationnel de la phase en cours

## Stack cible

Expo (React Native) · Supabase (Postgres, Auth, Storage, Edge Functions, Realtime) ·
Claude API pour l'assistant paroles · APIs serverless GPU pour la génération et la séparation de pistes ·
RevenueCat pour les abonnements et les crédits.

État : **Phase 1 — architecture et choix des API.**
