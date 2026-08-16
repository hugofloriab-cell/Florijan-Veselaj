-- Melodix — Row Level Security
--
-- Modèle : l'isolation entre utilisateurs est appliquée par la base, pas par le
-- code applicatif. Même une Edge Function boguée ne peut pas faire fuiter le
-- projet d'un tiers. Les tables enfants n'ont pas de user_id : elles héritent de
-- la propriété via leur projet parent.
--
-- Le rôle `service_role` (webhooks, tâches système) contourne la RLS par
-- construction et n'a donc pas de politique ici.

-- ---------------------------------------------------------------------------
-- Privilèges de table
-- ---------------------------------------------------------------------------
--
-- Supabase accorde par défaut ALL sur les nouvelles tables de `public` à anon et
-- authenticated. On repart de zéro pour n'accorder que ce que les politiques
-- ci-dessous autorisent : les deux couches disent alors la même chose. Sans ce
-- resserrage, une politique oubliée sur une table ouvrirait un accès complet.

revoke all on all tables in schema public from anon, authenticated;

grant select, update            on public.profiles         to authenticated;
grant select, insert, update, delete on public.projects    to authenticated;
grant select, insert, update, delete on public.lyrics_documents to authenticated;
grant select, update, delete    on public.versions         to authenticated;
grant select, update            on public.stems            to authenticated;
grant select                    on public.sections         to authenticated;
grant select                    on public.renders          to authenticated;
grant select                    on public.jobs             to authenticated;
grant select                    on public.credit_ledger    to authenticated;

alter table public.profiles         enable row level security;
alter table public.projects         enable row level security;
alter table public.lyrics_documents enable row level security;
alter table public.versions         enable row level security;
alter table public.stems            enable row level security;
alter table public.sections         enable row level security;
alter table public.renders          enable row level security;
alter table public.jobs             enable row level security;
alter table public.credit_ledger    enable row level security;

-- ---------------------------------------------------------------------------
-- Helper : la version appartient-elle à l'utilisateur courant ?
-- ---------------------------------------------------------------------------
--
-- STABLE + inlinable : le planificateur la remonte dans le plan de requête au
-- lieu de l'exécuter ligne à ligne.

create or replace function public.owns_version(p_version_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.versions v
      join public.projects p on p.id = v.project_id
     where v.id = p_version_id
       and p.user_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = auth.uid());

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- La RLS autorise la mise à jour de la ligne, mais surtout pas de n'importe
-- quelle colonne : sans ce garde-fou, un utilisateur s'octroierait des crédits
-- illimités par un simple PATCH.
create or replace function public.guard_profile_columns()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon')
     and (new.credits_balance is distinct from old.credits_balance
          or new.tier is distinct from old.tier
          or new.id is distinct from old.id) then
    raise exception 'Colonne protégée : credits_balance et tier sont gérés côté serveur'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

create trigger trg_guard_profile_columns
  before update on public.profiles
  for each row execute function public.guard_profile_columns();

-- ---------------------------------------------------------------------------
-- projects
-- ---------------------------------------------------------------------------

create policy projects_all_own on public.projects
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- lyrics_documents
-- ---------------------------------------------------------------------------

create policy lyrics_documents_all_own on public.lyrics_documents
  for all to authenticated
  using (
    exists (select 1 from public.projects p
             where p.id = lyrics_documents.project_id and p.user_id = auth.uid())
  )
  with check (
    exists (select 1 from public.projects p
             where p.id = lyrics_documents.project_id and p.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- versions
-- ---------------------------------------------------------------------------
--
-- Lecture et renommage côté client ; la création passe par les Edge Functions
-- (une version n'a de sens qu'attachée à un job payé).

create policy versions_select_own on public.versions
  for select to authenticated
  using (
    exists (select 1 from public.projects p
             where p.id = versions.project_id and p.user_id = auth.uid())
  );

create policy versions_update_own on public.versions
  for update to authenticated
  using (
    exists (select 1 from public.projects p
             where p.id = versions.project_id and p.user_id = auth.uid())
  )
  with check (
    exists (select 1 from public.projects p
             where p.id = versions.project_id and p.user_id = auth.uid())
  );

create policy versions_delete_own on public.versions
  for delete to authenticated
  using (
    exists (select 1 from public.projects p
             where p.id = versions.project_id and p.user_id = auth.uid())
  );

-- ---------------------------------------------------------------------------
-- stems — lecture, plus mise à jour du mixage (gain / mute)
-- ---------------------------------------------------------------------------

create policy stems_select_own on public.stems
  for select to authenticated
  using (public.owns_version(version_id));

create policy stems_update_own on public.stems
  for update to authenticated
  using (public.owns_version(version_id))
  with check (public.owns_version(version_id));

-- ---------------------------------------------------------------------------
-- sections / renders — lecture seule côté client, écrites par le backend
-- ---------------------------------------------------------------------------

create policy sections_select_own on public.sections
  for select to authenticated
  using (public.owns_version(version_id));

create policy renders_select_own on public.renders
  for select to authenticated
  using (public.owns_version(version_id));

-- ---------------------------------------------------------------------------
-- jobs — lecture seule
-- ---------------------------------------------------------------------------
--
-- Aucune politique d'insertion, volontairement : la seule voie de création est
-- create_paid_job(), qui débite dans la même transaction. Un INSERT direct
-- permettrait de générer gratuitement.

create policy jobs_select_own on public.jobs
  for select to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- credit_ledger — lecture seule (historique de consommation dans l'app)
-- ---------------------------------------------------------------------------

create policy credit_ledger_select_own on public.credit_ledger
  for select to authenticated
  using (user_id = auth.uid());
