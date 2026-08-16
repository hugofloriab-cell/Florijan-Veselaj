-- Melodix — schéma initial
--
-- Principe directeur : un morceau n'est jamais écrasé. Chaque édition crée une
-- ligne `versions` enfant de la précédente (`parent_version_id`), ce qui forme un
-- arbre d'édition parcourable dans les deux sens. C'est cette colonne qui porte la
-- promesse produit « tu ne perds jamais ton morceau ».

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Types énumérés
-- ---------------------------------------------------------------------------

create type version_status as enum ('pending', 'generating', 'ready', 'failed');

create type stem_kind as enum ('vocals', 'drums', 'bass', 'other');

create type section_kind as enum (
  'intro', 'verse', 'pre_chorus', 'chorus', 'bridge', 'solo', 'outro'
);

create type job_kind as enum (
  'generate',             -- texte -> morceau complet
  'separate_stems',       -- Demucs, enchaîné automatiquement après 'generate'
  'regenerate_section',   -- re-génération d'un segment, même seed
  'restyle',              -- changement de genre, paroles et structure conservées
  'vocal_align',          -- voix utilisateur -> alignement + correction de pitch
  'export'
);

create type job_status as enum ('queued', 'running', 'succeeded', 'failed', 'cancelled');

create type render_format as enum ('mp3', 'wav_zip');

-- ---------------------------------------------------------------------------
-- Utilitaire : maintien de updated_at
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- profiles — miroir applicatif de auth.users
-- ---------------------------------------------------------------------------

create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  display_name    text,
  tier            text        not null default 'free',
  -- Cache dénormalisé : la source de vérité reste la somme de credit_ledger.
  -- Maintenu exclusivement par le trigger apply_credit_ledger (migration 0002).
  credits_balance integer     not null default 0,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create trigger trg_profiles_touch
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Création automatique du profil à l'inscription : sans ça, le premier appel
-- authentifié échouerait sur une ligne manquante.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'display_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- projects
-- ---------------------------------------------------------------------------

create table public.projects (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid        not null references auth.users (id) on delete cascade,
  title              text        not null default 'Sans titre',
  genre_prompt       text,
  bpm                integer     check (bpm is null or bpm between 40 and 240),
  key_signature      text,
  current_version_id uuid,  -- FK ajoutée après la création de `versions` (cycle)
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index projects_user_id_created_at_idx
  on public.projects (user_id, created_at desc);

create trigger trg_projects_touch
  before update on public.projects
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- lyrics_documents — paroles structurées, jamais un bloc de texte
-- ---------------------------------------------------------------------------
--
-- content = [
--   { "type": "verse", "index": 1,
--     "lines": [ { "text": "...", "syllables": 8 } ] }
-- ]
--
-- C'est cette structure typée qui rend possibles le comptage de syllabes, le
-- mapping paroles <-> sections audio, et la correction ciblée d'un seul couplet.

create table public.lyrics_documents (
  id         uuid primary key default gen_random_uuid(),
  project_id uuid        not null unique references public.projects (id) on delete cascade,
  content    jsonb       not null default '[]'::jsonb,
  model_used text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_lyrics_documents_touch
  before update on public.lyrics_documents
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- versions — l'arbre d'édition
-- ---------------------------------------------------------------------------

create table public.versions (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid           not null references public.projects (id) on delete cascade,
  parent_version_id uuid           references public.versions (id) on delete set null,
  label             text,
  status            version_status not null default 'pending',
  -- Instantanés : une version doit rester rejouable même si le projet a changé depuis.
  prompt_snapshot   jsonb          not null default '{}'::jsonb,
  lyrics_snapshot   jsonb,
  -- Indispensable à la régénération de section : sans seed reproductible, le
  -- segment re-généré ne se raccorde pas au reste du morceau.
  seed              bigint,
  duration_ms       integer,
  master_audio_path text,
  created_at        timestamptz    not null default now()
);

create index versions_project_id_created_at_idx
  on public.versions (project_id, created_at desc);

create index versions_parent_version_id_idx
  on public.versions (parent_version_id);

alter table public.projects
  add constraint projects_current_version_id_fkey
  foreign key (current_version_id) references public.versions (id) on delete set null;

-- ---------------------------------------------------------------------------
-- stems — pistes séparées (Demucs)
-- ---------------------------------------------------------------------------

create table public.stems (
  id           uuid primary key default gen_random_uuid(),
  version_id   uuid        not null references public.versions (id) on delete cascade,
  kind         stem_kind   not null,
  storage_path text        not null,
  peaks_path   text,        -- waveform pré-calculée, pour ne pas décoder l'audio à l'affichage
  gain_db      real        not null default 0 check (gain_db between -60 and 12),
  muted        boolean     not null default false,
  created_at   timestamptz not null default now(),
  unique (version_id, kind)
);

create index stems_version_id_idx on public.stems (version_id);

-- ---------------------------------------------------------------------------
-- sections — découpage temporel, borné aussi en mesures
-- ---------------------------------------------------------------------------
--
-- bar_start / bar_end sont ce qui permet de recoller une régénération sur un
-- passage à la mesure plutôt qu'au milieu d'un temps : c'est la différence
-- audible entre une couture propre et un raccord bancal.

create table public.sections (
  id         uuid primary key default gen_random_uuid(),
  version_id uuid         not null references public.versions (id) on delete cascade,
  kind       section_kind not null,
  position   integer      not null,
  start_ms   integer      not null check (start_ms >= 0),
  end_ms     integer      not null,
  bar_start  integer,
  bar_end    integer,
  created_at timestamptz  not null default now(),
  check (end_ms > start_ms),
  unique (version_id, position)
);

create index sections_version_id_idx on public.sections (version_id);

-- ---------------------------------------------------------------------------
-- renders — mixdowns exportés
-- ---------------------------------------------------------------------------

create table public.renders (
  id           uuid primary key default gen_random_uuid(),
  version_id   uuid          not null references public.versions (id) on delete cascade,
  format       render_format not null,
  storage_path text          not null,
  size_bytes   bigint,
  -- Les exports sont purgeables : ils sont toujours reconstructibles depuis les stems.
  expires_at   timestamptz,
  created_at   timestamptz   not null default now()
);

create index renders_version_id_idx on public.renders (version_id);

-- ---------------------------------------------------------------------------
-- jobs — tout traitement asynchrone passe par ici
-- ---------------------------------------------------------------------------

create table public.jobs (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid        not null references auth.users (id) on delete cascade,
  -- SET NULL et non CASCADE, délibérément : un job est une écriture comptable
  -- (des crédits ont été dépensés) et doit survivre à la suppression du contenu
  -- auquel il se rapportait. En CASCADE, supprimer un projet effacerait des jobs
  -- encore référencés par le ledger append-only — et la suppression échouerait.
  project_id      uuid        references public.projects (id) on delete set null,
  version_id      uuid        references public.versions (id) on delete set null,
  kind            job_kind    not null,
  status          job_status  not null default 'queued',
  provider        text,
  provider_job_id text,
  credits_cost    integer     not null default 0 check (credits_cost >= 0),
  credits_refunded boolean    not null default false,
  payload         jsonb       not null default '{}'::jsonb,
  error           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  completed_at    timestamptz
);

create index jobs_user_id_status_idx on public.jobs (user_id, status);
create index jobs_project_id_idx on public.jobs (project_id);

-- Idempotence des webhooks : un fournisseur qui rejoue un callback ne doit pas
-- pouvoir créer un second job ni un second remboursement.
create unique index jobs_provider_job_id_key
  on public.jobs (provider, provider_job_id)
  where provider_job_id is not null;

create trigger trg_jobs_touch
  before update on public.jobs
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- credit_ledger — source de vérité du solde
-- ---------------------------------------------------------------------------
--
-- Append-only. delta < 0 = consommation, delta > 0 = achat, offre de bienvenue
-- ou remboursement d'un job échoué.

create table public.credit_ledger (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid        not null references auth.users (id) on delete cascade,
  delta             integer     not null check (delta <> 0),
  reason            text        not null,
  job_id            uuid        references public.jobs (id) on delete set null,
  -- ID d'événement RevenueCat : garantit qu'un webhook rejoué ne crédite qu'une fois.
  external_event_id text,
  created_at        timestamptz not null default now()
);

create index credit_ledger_user_id_created_at_idx
  on public.credit_ledger (user_id, created_at desc);

create unique index credit_ledger_external_event_id_key
  on public.credit_ledger (external_event_id)
  where external_event_id is not null;

-- Un job ne peut être débité qu'une fois et remboursé qu'une fois.
create unique index credit_ledger_job_debit_key
  on public.credit_ledger (job_id)
  where job_id is not null and delta < 0;

create unique index credit_ledger_job_refund_key
  on public.credit_ledger (job_id)
  where job_id is not null and delta > 0;
