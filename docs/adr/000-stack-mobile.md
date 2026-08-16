# ADR 000 — Stack mobile : Swift natif, iOS d'abord

**Statut :** accepté · **Date :** 2026-08-16

## Contexte

Melodix se distingue par l'édition post-génération : lecture simultanée de 4 stems
synchronisés, gain et mute par piste en temps réel, waveforms, régénération de section,
enregistrement de la voix de l'utilisateur puis correction de pitch. L'audio multipiste
n'est pas une fonctionnalité périphérique du produit — c'est le produit.

Trois options ont été évaluées : React Native + Expo, Flutter, et Swift natif.

## Décision

**Swift / SwiftUI, iOS d'abord.** Android est un portage ultérieur, explicitement hors
périmètre v1.

## Conséquences

**Ce qu'on gagne**

- `AVAudioEngine` : graphe audio temps réel, un `AVAudioPlayerNode` par stem sur une
  horloge commune → synchronisation à l'échantillon près, sans la dérive qu'imposent les
  ponts cross-platform. Aucun équivalent en React Native ou Flutter.
- `AVAudioEngine.enableManualRenderingMode` : mixdown offline plus rapide que le temps réel
  pour l'export, **sur l'appareil** — donc sans coût cloud. Point non négligeable avec un
  budget serré.
- `AVAudioSession`, enregistrement micro, gestion des interruptions et du Bluetooth :
  intégration système native pour la fonctionnalité voix de la Phase 4.
- Pas de couche d'abstraction à déboguer quand un problème audio survient.

**Ce qu'on paie**

- **Android à réécrire intégralement** le jour venu (SwiftUI et AVAudioEngine n'ont pas
  d'équivalent portable). C'est le coût assumé de cette décision : il est réel et il
  arrivera. La parade est de garder toute la logique métier côté serveur, où elle est
  réutilisable telle quelle.
- Un Mac avec Xcode est requis pour builder et publier.
- **Deux langages** : Swift côté app, TypeScript côté Edge Functions. Le package de types
  partagés prévu initialement disparaît ; à la place, les types `Codable` Swift sont
  générés depuis le schéma Postgres, avec un test de contrat en CI qui échoue si le schéma
  et les structs divergent. Sans ce garde-fou, la dérive est garantie.

**Impacts sur le plan**

- Repo restructuré : `ios/` (app Swift) + `supabase/` (migrations et Edge Functions).
- Le spike n°1 de la Phase 1 devient : lecture de 4 stems synchronisés avec `AVAudioEngine`,
  mesure de la dérive et de l'empreinte mémoire sur iPhone physique.
- SDK : `supabase-swift` et `purchases-ios` (RevenueCat) sont tous deux officiels et matures.

## Alternatives écartées

- **React Native + Expo** — le meilleur choix de vélocité et le seul à donner Android
  gratuitement, mais aucune bibliothèque audio RN ne garantit une synchronisation
  multipiste au niveau d'`AVAudioEngine`. Écarté parce que le risque porte précisément sur
  la fonctionnalité différenciante.
- **Flutter** — même angle mort audio, sans le bénéfice d'un langage partagé avec le backend.
