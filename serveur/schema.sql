-- ==================================================================
-- Restaurant Les Tilleuls — base des avis privés
-- ------------------------------------------------------------------
-- À coller dans Supabase : menu de gauche → SQL Editor → New query →
-- coller → Run. À exécuter une seule fois.
--
-- Principe de sécurité : le public peut DÉPOSER un avis, jamais en LIRE
-- un. La lecture, la modification et la suppression exigent une
-- connexion. La clé « anon » présente dans la page ne donne donc accès
-- à rien, même si quelqu'un la récupère.
-- ==================================================================

create table if not exists public.avis (
  id          uuid primary key default gen_random_uuid(),
  cree_le     timestamptz not null default now(),
  note        smallint    not null check (note between 1 and 5),
  commentaire text        check (char_length(commentaire) <= 2000),
  photo       text,                       -- image en base64, facultative
  canal       text        not null check (canal in ('prive', 'public')),
  plateforme  text,
  table_no    text        check (char_length(table_no) <= 20),
  contact     text        check (char_length(contact) <= 200),
  lu          boolean     not null default false
);

comment on table public.avis is
  'Avis clients. Les avis « prive » ne sont jamais publiés ; les « public » '
  'gardent la trace d''une redirection vers une plateforme.';

create index if not exists avis_cree_le_idx on public.avis (cree_le desc);
create index if not exists avis_canal_idx   on public.avis (canal);

-- ------------------------------------------------------------------
-- Règles d'accès (Row Level Security)
-- ------------------------------------------------------------------
alter table public.avis enable row level security;

-- Le public dépose, et c'est tout. Aucune lecture, aucune modification.
drop policy if exists "depot public" on public.avis;
create policy "depot public"
  on public.avis for insert
  to anon
  with check (true);

-- Le gérant connecté lit, met à jour et supprime.
drop policy if exists "lecture gerant" on public.avis;
create policy "lecture gerant"
  on public.avis for select
  to authenticated
  using (true);

drop policy if exists "maj gerant" on public.avis;
create policy "maj gerant"
  on public.avis for update
  to authenticated
  using (true) with check (true);

drop policy if exists "suppression gerant" on public.avis;
create policy "suppression gerant"
  on public.avis for delete
  to authenticated
  using (true);

-- ------------------------------------------------------------------
-- Garde-fou anti-abus
-- ------------------------------------------------------------------
-- L'insertion étant ouverte, on limite la taille d'un avis pour qu'on ne
-- puisse pas remplir la base avec une image démesurée.
alter table public.avis drop constraint if exists avis_photo_taille;
alter table public.avis add constraint avis_photo_taille
  check (photo is null or char_length(photo) <= 700000);   -- ~500 Ko

-- ==================================================================
-- La carte publiée depuis le panneau gérant
-- ------------------------------------------------------------------
-- Une seule ligne, « carte », qui porte les réglages du restaurant :
-- identité, liens d'avis, délais, et la carte elle-même si elle a été
-- importée depuis le panneau.
--
-- Sens inverse des avis : ici le public LIT (il faut bien afficher la
-- carte) et seul le gérant connecté ÉCRIT.
-- ==================================================================

create table if not exists public.contenu (
  id      text primary key,
  donnees jsonb       not null,
  maj_le  timestamptz not null default now()
);

alter table public.contenu enable row level security;

drop policy if exists "lecture publique" on public.contenu;
create policy "lecture publique"
  on public.contenu for select
  to anon, authenticated
  using (true);

drop policy if exists "depot gerant" on public.contenu;
create policy "depot gerant"
  on public.contenu for insert
  to authenticated
  with check (true);

drop policy if exists "maj gerant contenu" on public.contenu;
create policy "maj gerant contenu"
  on public.contenu for update
  to authenticated
  using (true) with check (true);

-- Garde-fou : chaque client télécharge cette ligne à l'ouverture de la
-- carte. Au-delà de quelques mégaoctets, l'application deviendrait lente
-- sur un téléphone en 4G.
alter table public.contenu drop constraint if exists contenu_taille;
alter table public.contenu add constraint contenu_taille
  check (length(donnees::text) <= 6000000);   -- ~6 Mo

-- ------------------------------------------------------------------
-- Conservation limitée (RGPD)
-- ------------------------------------------------------------------
-- Supprime les avis de plus de 12 mois. À appeler manuellement, ou à
-- planifier si l'extension pg_cron est activée sur le projet.
create or replace function public.purge_avis_anciens()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare supprimes integer;
begin
  delete from public.avis where cree_le < now() - interval '12 months';
  get diagnostics supprimes = row_count;
  return supprimes;
end;
$$;

-- Planification mensuelle (ignorée si pg_cron n'est pas disponible) :
-- select cron.schedule('purge-avis', '0 3 1 * *', 'select public.purge_avis_anciens()');
