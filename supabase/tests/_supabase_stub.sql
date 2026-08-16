-- Reproduction minimale de l'environnement Supabase (rôles, schéma auth,
-- schéma storage) permettant de faire tourner les migrations et les tests sur un
-- Postgres nu, sans démarrer la stack Supabase complète.
--
-- Uniquement destiné aux tests. Sur un vrai projet Supabase, tout ceci existe déjà.

create extension if not exists pgcrypto;

-- Les rôles sont globaux au cluster : création idempotente pour que le script de
-- test puisse être relancé sans repartir d'un cluster neuf.
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end $$;

create schema if not exists auth;
create schema if not exists storage;

create table auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text,
  raw_user_meta_data jsonb default '{}'::jsonb
);

-- Même résolution que Supabase : claim `sub` du JWT porté par la requête.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
  )::uuid;
$$;

create table storage.buckets (
  id     text primary key,
  name   text not null,
  public boolean not null default false
);

create table storage.objects (
  id        uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets (id),
  name      text,
  owner     uuid
);
alter table storage.objects enable row level security;

create or replace function storage.foldername(name text)
returns text[]
language sql
immutable
as $$
  select string_to_array(name, '/');
$$;

grant usage on schema public, auth, storage to anon, authenticated, service_role;

-- Supabase accorde ALL par défaut sur les nouvelles tables de `public` : on
-- reproduit ce comportement pour que la migration RLS ait quelque chose à
-- resserrer, exactement comme en production.
alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
