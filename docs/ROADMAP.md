# Melodix — Feuille de route produit & technique

> Application mobile de création musicale IA **éditable après génération**.
> Document de référence : toute décision structurante est tranchée ici avant d'écrire du code.

---

## 0. Le pari technique

Les concurrents (Suno, Udio, Soniva) produisent un **fichier**. Melodix produit un **projet** :
une structure de données versionnée dont l'audio n'est qu'un rendu parmi d'autres.

C'est la seule différence qui compte, et elle se joue dans le modèle de données, pas dans l'UI :

```
Project ──┬── LyricsDocument (JSON structuré, sections typées)
          ├── Version #1 ──┬── Stem (vocals)     ─┐
          │                ├── Stem (drums)       │ WAV + waveform peaks
          │                ├── Stem (bass)        │ + gain / mute / solo
          │                └── Stem (other)      ─┘
          │                └── Section[] (intro / verse / chorus …, bornées en ms)
          ├── Version #2 (issue de #1 : « refais le refrain », « change le genre »)
          └── Render[] (mixdowns MP3/WAV exportés)
```

Un morceau n'est jamais écrasé : chaque édition crée une **Version** enfant.
L'utilisateur peut toujours revenir en arrière — c'est ce qui supprime la peur de « perdre son morceau ».

---

## 1. Architecture cible

| Couche | Choix | Justification |
|---|---|---|
| Mobile | **Swift / SwiftUI — iOS d'abord** | Décision actée ([ADR 000](./adr/000-stack-mobile.md)) : l'audio multipiste est le produit, et `AVAudioEngine` n'a pas d'équivalent cross-platform. Android = portage ultérieur, hors périmètre v1 |
| Audio device | **AVAudioEngine**, un `AVAudioPlayerNode` par stem | Synchronisation à l'échantillon près sur horloge commune, gain/mute temps réel, et mixdown offline **sur l'appareil** pour l'export — donc à coût cloud nul |
| Backend | **Supabase** (Postgres + Auth + Storage + Edge Functions + Realtime) | Le modèle projet/version/stem/section est **relationnel** ; Firestore (NoSQL) serait un contresens ici. RLS = isolation multi-tenant gratuite |
| Assistant paroles | **Claude API** (`claude-sonnet-5`) | Co-écriture, structuration, comptage de syllabes, adaptation à la métrique. Appelée **uniquement** côté serveur |
| Génération musicale | **À trancher en Phase 1** (cf. § Risque n°1) | Détermine la légalité commerciale du produit entier |
| Séparation de pistes | **Demucs / htdemucs** via Replicate ou fal.ai | Licence MIT, standard de facto, ~10-20 s par morceau |
| Voix utilisateur | Pipeline DSP custom (alignement + time-stretch + pitch correction) sur worker GPU | Aucune API clé-en-main ne fait ça correctement (cf. Phase 4) |
| Paiement | **RevenueCat** + ledger de crédits côté serveur | La génération a un coût marginal réel : l'abonnement seul est une machine à perdre de l'argent |

### Le pattern central : les jobs asynchrones

Une génération prend 30 s à 3 min. **Rien ne doit jamais bloquer le mobile.**

```
App ──POST /jobs──► Edge Function ──► INSERT jobs (status=queued)
                                  └─► Replicate/fal (avec webhook_url)
                                                    │
                                             (30s–3min)
                                                    ▼
App ◄──Realtime──── UPDATE jobs (done) ◄── Edge Function /webhooks/provider
                                            (signature HMAC vérifiée)
```

L'app ne fait **jamais** de polling et ne connaît **jamais** une clé d'API fournisseur.
Si l'app est tuée pendant la génération, le job aboutit quand même : l'état vit en base.

---

## 2. Les 5 phases

### Phase 1 — Architecture & choix des API · ~2 semaines
**Objectif : ne plus avoir aucune inconnue bloquante.** Zéro feature livrée, et c'est normal.
Détail complet dans [`PHASE-1.md`](./PHASE-1.md).

Sorties : moteur musical choisi et contractualisé · schéma Postgres + RLS migré · contrat des 8 Edge Functions typé · monorepo + CI · modèle de coût unitaire validé · spike lecture 4 stems sur device physique.

---

### Phase 2 — La boucle de génération · ~3-4 semaines
Le chemin le plus court entre une idée et un morceau écoutable.

- Auth Supabase (Apple / Google / email) + onboarding.
- Assistant paroles Claude : conversation → `LyricsDocument` structuré (sections typées, syllabes comptées, rimes).
- `POST /generate` → job → webhook → Realtime → lecture in-app.
- Bibliothèque de projets, lecteur simple, suppression.
- **Critère de sortie** : un testeur externe génère un morceau complet sans assistance.

---

### Phase 3 — L'éditeur · ~4-5 semaines · ⭐ le cœur du produit
C'est ici que se gagne ou se perd la différenciation. Toute la phase est consacrée à *ne pas régénérer*.

- Séparation automatique en 4 stems à chaque génération (job en cascade).
- Mixeur multipiste : mute / solo / gain, lecture synchronisée, waveforms.
- Détection de structure : découpage en sections bornées en millisecondes (alignées sur les mesures).
- **Régénération de section** : re-générer un segment avec la même seed + prompt modifié, recollé au **passage à la mesure** avec crossfade. C'est la version réaliste et livrable de « l'inpainting ».
- **Changement de genre** : mêmes paroles + même structure + nouveau prompt de style, avec option « garder la piste voix existante ».
- Ajout / retrait d'instrument : retrait = mute + remix ; ajout = génération d'un stem conditionné puis superposition.
- Arbre de versions avec retour arrière.

---

### Phase 4 — Voix, export & monétisation · ~3-4 semaines
- **Enregistrement voix utilisateur** : capture → analyse tempo/tonalité de l'instrumental → alignement → time-stretch → correction de pitch sur la gamme du morceau → (option) conversion de timbre. Worker GPU dédié, pas d'API clé-en-main.
- Export : mixdown MP3 (partage) rendu **sur l'appareil** via le rendu manuel d'`AVAudioEngine` — zéro coût cloud —, et stems WAV en zip (réservé au tier payant).
- RevenueCat : abonnement mensuel/annuel donnant un pool de crédits + packs de crédits à l'unité.
- **Ledger de crédits** : débit transactionnel côté serveur au moment de la création du job, jamais côté client. Remboursement automatique si le job échoue.
- Paywall, écran de gestion d'abonnement, restauration d'achats.

---

### Phase 5 — Durcissement & publication · ~3 semaines
- Rate limiting, quotas anti-abus, modération des prompts (l'App Store la réclamera).
- Observabilité : Sentry mobile, logs structurés, alerte sur taux d'échec des jobs.
- Conformité stores : CGU, politique de confidentialité, **clarification écrite des droits d'usage de la musique générée**, mentions IA, suppression de compte (obligatoire Apple).
- Beta TestFlight → itération → soumission App Store. *(Android hors périmètre v1, cf. ADR 000.)*

---

## 3. Risques identifiés, par ordre de gravité

**1. Licence du moteur musical — bloquant commercial.**
MusicGen (Meta) est en **CC-BY-NC** : interdit dans un produit payant. Beaucoup de démos Replicate reposent dessus. Il faut un moteur avec licence commerciale explicite (Stable Audio, ElevenLabs Music, Suno/Udio via API partenaire, Mureka…). Ce point est traité **en premier** en Phase 1 : il conditionne l'existence même du produit.

**2. L'« inpainting » 5 secondes tel qu'imaginé n'existe pas en API grand public.**
Régénérer 5 s en conservant le contexte harmonique est un sujet de recherche, pas un endpoint. La parade — régénération de section alignée sur les mesures + crossfade, sur stems séparés — donne 80 % de la valeur perçue sans dépendre d'une capacité incertaine. À concevoir ainsi dès le départ.

**3. Économie unitaire.**
Génération + séparation ≈ 0,10-0,40 $ par morceau selon le moteur. Un abonnement « illimité » à 9,99 € est une perte garantie sur les gros utilisateurs. D'où le modèle par crédits, décidé en Phase 1 et pas après.

**4. Latence perçue.**
2-3 min d'attente tue la rétention. Contre-mesures : notification push à la fin du job, écran d'attente qui propose de travailler les paroles pendant ce temps, préchargement du premier extrait dès qu'il est disponible.

---

## 4. Ce qui n'est explicitement PAS dans le périmètre v1

Collaboration temps réel · plugin VST/desktop · distribution vers Spotify/DSP · marketplace · clonage de voix d'artistes tiers (risque juridique) · MIDI.
