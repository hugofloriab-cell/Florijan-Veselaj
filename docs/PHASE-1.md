# Phase 1 — Architecture & choix des API

**Durée visée : 2 semaines. Aucune feature utilisateur livrée.**
Objectif unique : qu'il ne reste **aucune inconnue capable de faire réécrire le socle** en Phase 3.

---

## Lot 1 — Trancher le moteur musical (priorité absolue, 2-3 jours)

C'est la décision dont dépendent toutes les autres. Elle est d'abord **juridique**, ensuite technique.

Grille d'évaluation, 3 candidats testés sur le **même prompt de référence** :

| Critère | Poids |
|---|---|
| Licence commerciale explicite pour un produit payant | **Éliminatoire** |
| Génère paroles **et** voix chantée (pas seulement instrumental) | **Éliminatoire** |
| Coût par génération (durée 2-3 min) | Fort |
| Latence p50 / p95 | Fort |
| Support d'une **seed** reproductible → indispensable à la régénération de section | Fort |
| Webhook de complétion natif | Moyen |
| Contrôle de structure (couplet/refrain) dans le prompt | Moyen |

**Livrable : un ADR** (`docs/adr/001-moteur-musical.md`) figeant le choix, le coût réel mesuré, et le plan de repli si le fournisseur change ses conditions. On isole le fournisseur derrière une interface `MusicEngine` pour rendre le remplacement possible sans toucher au reste.

⚠️ Écarter d'emblée tout modèle en licence **CC-BY-NC** (dont MusicGen) : incompatible avec une app monétisée.

---

## Lot 2 — Schéma de base de données (3-4 jours)

Le schéma est le produit. S'il est juste, l'éditeur de Phase 3 est simple à écrire ; s'il est faux, il est impossible.

```sql
profiles        (id → auth.users, display_name, credits_balance, tier)
projects        (id, user_id, title, bpm, key_signature, genre_prompt,
                 current_version_id, created_at)
lyrics_documents(id, project_id, content jsonb, model_used, updated_at)
   -- content = [{ type:'verse'|'chorus'|'bridge'|'intro'|'outro',
   --              index:int, lines:[{text, syllables}] }]
versions        (id, project_id, parent_version_id,   -- ← arbre de versions
                 label, prompt_snapshot jsonb, seed, duration_ms,
                 status, master_audio_path)
stems           (id, version_id, kind 'vocals'|'drums'|'bass'|'other',
                 storage_path, peaks_path, gain_db, muted)
sections        (id, version_id, kind, start_ms, end_ms, bar_start, bar_end)
renders         (id, version_id, format 'mp3'|'wav_zip', storage_path,
                 expires_at)
jobs            (id, user_id, project_id, version_id, kind, status,
                 provider, provider_job_id, credits_cost, error, payload jsonb)
credit_ledger   (id, user_id, delta, reason, job_id, revenuecat_event_id)
```

Points non négociables :
- **RLS activée sur chaque table**, politiques `user_id = auth.uid()` ; les Edge Functions utilisent la `service_role` pour les écritures système (webhooks).
- `credits_balance` n'est **jamais** la source de vérité : c'est la somme de `credit_ledger`. Débit et création du job dans **une seule transaction**.
- `parent_version_id` auto-référencé = l'arbre d'édition. C'est cette colonne qui incarne la promesse « tu ne perds jamais ton morceau ».
- Storage : buckets privés, accès par **URL signées à durée courte** uniquement.

**Livrable** : migrations Supabase versionnées + types TypeScript générés + jeu de données de test.

---

## Lot 3 — Contrat d'API (2 jours)

Huit Edge Functions, typées de bout en bout et figées avant tout code mobile :

| Fonction | Rôle |
|---|---|
| `POST /lyrics/assist` | Proxy Claude en streaming → co-écriture et structuration des paroles |
| `POST /projects` | Création d'un projet + document de paroles initial |
| `POST /generate` | Débit crédits + création job + appel moteur musical |
| `POST /versions/:id/regenerate-section` | Régénération d'un segment (même seed, prompt modifié) |
| `POST /versions/:id/restyle` | Changement de genre, paroles et structure conservées |
| `POST /versions/:id/export` | Mixdown MP3 ou zip de stems WAV |
| `POST /webhooks/:provider` | Callback fournisseur — **signature HMAC vérifiée** |
| `POST /webhooks/revenuecat` | Achat/renouvellement → crédit du ledger |

Règle absolue : **aucune clé d'API tierce n'existe côté mobile.** Un binaire mobile est décompilable ; toute clé qui y figure est publique.

---

## Lot 4 — Socle projet & CI (2 jours)

```
melodix/
├── apps/mobile/          Expo (dev client) — TypeScript
├── supabase/
│   ├── migrations/
│   └── functions/        Edge Functions Deno
├── packages/shared/      Types + schémas Zod partagés mobile ⇄ backend
└── docs/                 ROADMAP, PHASE-1, ADRs
```

CI GitHub Actions : typecheck, lint, tests, vérification que les migrations s'appliquent sur une base vierge. Environnements `dev` / `prod` séparés dès le premier jour.

---

## Lot 5 — Modèle économique unitaire (1 jour)

Tableur à remplir avec les **coûts réels mesurés au Lot 1** :

```
coût_morceau = génération + séparation stems + stockage + bande passante
prix_crédit  = coût_morceau × marge_cible (≥ 3×, avant commission store de 15-30 %)
```

À décider ici, pas en Phase 4 : combien de morceaux gratuits à l'inscription (acquisition), combien de crédits par palier d'abonnement, et le prix des packs à l'unité.

---

## Lot 6 — Spikes techniques de dérisquage (2-3 jours)

Trois prototypes jetables, à faire tourner sur **téléphone physique**, pas sur simulateur :

1. **Lecture 4 stems synchronisés** avec `react-native-audio-api` : mute/gain temps réel, mesure de la dérive de synchro et de la consommation mémoire. *Si ce spike échoue, toute l'UX de l'éditeur doit être repensée — d'où sa place en Phase 1.*
2. **Chaîne job complète** : Edge Function → Replicate → webhook → Supabase Realtime → UI. Mesurer la latence bout-en-bout et vérifier le comportement quand l'app est en arrière-plan.
3. **Régénération de section** : générer un morceau, en régénérer 8 mesures avec la même seed, recoller avec crossfade, et **écouter**. Juger de la qualité de la couture avant de construire l'éditeur autour.

---

## Critères de sortie de la Phase 1

- [ ] ADR moteur musical signé, licence commerciale vérifiée par écrit
- [ ] Migrations appliquées, RLS testée (un utilisateur ne peut pas lire le projet d'un autre)
- [ ] Contrat des 8 endpoints figé et typé
- [ ] CI verte sur le monorepo
- [ ] Coût par morceau mesuré, grille tarifaire arrêtée
- [ ] Les 3 spikes exécutés, résultats consignés

Tant qu'une case n'est pas cochée, on n'entre pas en Phase 2.
