-- Melodix — création d'un projet
--
-- Un projet et son document de paroles naissent ensemble : sans le second,
-- l'assistant n'a nulle part où écrire et l'app doit gérer un état intermédiaire
-- qui n'a aucun sens produit. Les deux insertions vivent donc dans une fonction,
-- donc dans une transaction.
--
-- SECURITY INVOKER (le défaut) et non DEFINER : la RLS s'applique telle quelle,
-- il n'y a aucun privilège à emprunter. L'app iOS l'appelle directement en RPC —
-- une Edge Function n'ajouterait qu'un démarrage à froid.

create or replace function public.create_project(
  p_title        text default null,
  p_genre_prompt text default null
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_project_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentification requise' using errcode = 'insufficient_privilege';
  end if;

  insert into public.projects (user_id, title, genre_prompt)
  values (
    v_user_id,
    coalesce(nullif(btrim(p_title), ''), 'Sans titre'),
    nullif(btrim(p_genre_prompt), '')
  )
  returning id into v_project_id;

  insert into public.lyrics_documents (project_id)
  values (v_project_id);

  return v_project_id;
end;
$$;

revoke all on function public.create_project(text, text) from public, anon;
grant execute on function public.create_project(text, text) to authenticated;
