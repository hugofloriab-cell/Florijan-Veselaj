-- Melodix — tests du modèle de sécurité et de la comptabilité des crédits
--
-- Ces tests vérifient les invariants dont dépend la viabilité économique du
-- produit. Ils tournent en CI sur une base vierge :
--     ./supabase/tests/run.sh
--
-- Ils n'utilisent aucune extension : chaque cas lève une exception explicite en
-- cas d'échec, donc `psql -v ON_ERROR_STOP=1` suffit à faire échouer la CI.

\set QUIET on
\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- Mise en place : deux utilisateurs, un projet chacun
-- ---------------------------------------------------------------------------

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'alice@example.test'),
  ('22222222-2222-2222-2222-222222222222', 'bob@example.test');

do $$
begin
  if (select count(*) from public.profiles) <> 2 then
    raise exception 'ECHEC : le trigger de création de profil ne s''est pas déclenché';
  end if;
  raise notice 'OK  profil créé automatiquement à l''inscription';
end $$;

-- Alice reçoit 10 crédits (offre de bienvenue)
select public.grant_credits(
  '11111111-1111-1111-1111-111111111111', 10, 'welcome', 'evt_welcome_alice');

insert into public.projects (id, user_id, title)
values ('aaaaaaaa-0000-0000-0000-000000000001',
        '11111111-1111-1111-1111-111111111111', 'Projet Alice');

-- ---------------------------------------------------------------------------
-- 1. Le solde suit le ledger
-- ---------------------------------------------------------------------------

do $$
declare v integer;
begin
  select credits_balance into v from public.profiles
   where id = '11111111-1111-1111-1111-111111111111';
  if v <> 10 then
    raise exception 'ECHEC : solde attendu 10, obtenu %', v;
  end if;
  raise notice 'OK  le solde reflète le ledger (10)';
end $$;

-- ---------------------------------------------------------------------------
-- 2. Rejeu d'un webhook RevenueCat : ne crédite qu'une fois
-- ---------------------------------------------------------------------------

select public.grant_credits(
  '11111111-1111-1111-1111-111111111111', 10, 'welcome', 'evt_welcome_alice');

do $$
declare v integer;
begin
  select credits_balance into v from public.profiles
   where id = '11111111-1111-1111-1111-111111111111';
  if v <> 10 then
    raise exception 'ECHEC : webhook rejoué crédité deux fois (solde %)', v;
  end if;
  raise notice 'OK  webhook rejoué : idempotent';
end $$;

-- ---------------------------------------------------------------------------
-- 3. Création d'un job payant : débit dans la même transaction
-- ---------------------------------------------------------------------------

set local role authenticated;
set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';

select public.create_paid_job(
  'aaaaaaaa-0000-0000-0000-000000000001', 'generate', 4,
  '{"prompt":"synthwave mélancolique"}'::jsonb) as job_id \gset

reset role;

do $$
declare v integer;
begin
  select credits_balance into v from public.profiles
   where id = '11111111-1111-1111-1111-111111111111';
  if v <> 6 then
    raise exception 'ECHEC : solde attendu 6 après un job à 4 crédits, obtenu %', v;
  end if;
  raise notice 'OK  job créé et débité atomiquement (solde 6)';
end $$;

-- ---------------------------------------------------------------------------
-- 4. Solde insuffisant : le job ne doit pas exister
-- ---------------------------------------------------------------------------
--
-- L'invariant qui compte : pas de génération non payée. Si le débit échoue, la
-- transaction entière est annulée, job compris.

do $$
declare
  v_rejected boolean := false;
  v_jobs     integer;
  v_balance  integer;
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
    perform public.create_paid_job(
      'aaaaaaaa-0000-0000-0000-000000000001', 'generate', 999, '{}'::jsonb);
  exception when others then
    v_rejected := true;
  end;
  reset role;

  if not v_rejected then
    raise exception 'ECHEC : génération autorisée sans crédits suffisants';
  end if;

  select count(*) into v_jobs from public.jobs where credits_cost = 999;
  if v_jobs <> 0 then
    raise exception 'ECHEC : job orphelin conservé après échec du débit (% ligne(s))', v_jobs;
  end if;

  select credits_balance into v_balance from public.profiles
   where id = '11111111-1111-1111-1111-111111111111';
  if v_balance <> 6 then
    raise exception 'ECHEC : solde altéré par une tentative échouée (%)', v_balance;
  end if;

  raise notice 'OK  solde insuffisant : job refusé et transaction annulée';
end $$;

-- ---------------------------------------------------------------------------
-- 5. Isolation entre utilisateurs (RLS)
-- ---------------------------------------------------------------------------

do $$
declare
  v_projects integer;
  v_jobs     integer;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';

  select count(*) into v_projects from public.projects;
  select count(*) into v_jobs     from public.jobs;

  reset role;

  if v_projects <> 0 then
    raise exception 'ECHEC : Bob voit % projet(s) d''Alice', v_projects;
  end if;
  if v_jobs <> 0 then
    raise exception 'ECHEC : Bob voit % job(s) d''Alice', v_jobs;
  end if;
  raise notice 'OK  RLS : Bob ne voit ni les projets ni les jobs d''Alice';
end $$;

-- ---------------------------------------------------------------------------
-- 6. Bob ne peut pas lancer de job sur le projet d'Alice
-- ---------------------------------------------------------------------------

do $$
declare v_rejected boolean := false;
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222"}';
    perform public.create_paid_job(
      'aaaaaaaa-0000-0000-0000-000000000001', 'generate', 1, '{}'::jsonb);
  exception when others then
    v_rejected := true;
  end;
  reset role;

  if not v_rejected then
    raise exception 'ECHEC : Bob a pu lancer un job sur le projet d''Alice';
  end if;
  raise notice 'OK  create_paid_job vérifie l''appartenance du projet';
end $$;

-- ---------------------------------------------------------------------------
-- 7. Pas d'insertion directe dans `jobs` (contournement du paiement)
-- ---------------------------------------------------------------------------

do $$
declare v_rejected boolean := false;
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
    insert into public.jobs (user_id, project_id, kind)
    values ('11111111-1111-1111-1111-111111111111',
            'aaaaaaaa-0000-0000-0000-000000000001', 'generate');
  exception when others then
    v_rejected := true;
  end;
  reset role;

  if not v_rejected then
    raise exception 'ECHEC : INSERT direct dans jobs autorisé — génération gratuite possible';
  end if;
  raise notice 'OK  INSERT direct dans jobs refusé';
end $$;

-- ---------------------------------------------------------------------------
-- 8. L'utilisateur ne peut pas s'octroyer des crédits
-- ---------------------------------------------------------------------------

do $$
declare v_rejected boolean := false;
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
    update public.profiles set credits_balance = 9999
     where id = '11111111-1111-1111-1111-111111111111';
  exception when others then
    v_rejected := true;
  end;
  reset role;

  if not v_rejected then
    raise exception 'ECHEC : credits_balance modifiable depuis le client';
  end if;
  raise notice 'OK  credits_balance et tier protégés côté client';
end $$;

-- ---------------------------------------------------------------------------
-- 9. Pas d'écriture directe dans le ledger
-- ---------------------------------------------------------------------------

do $$
declare v_rejected boolean := false;
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
    insert into public.credit_ledger (user_id, delta, reason)
    values ('11111111-1111-1111-1111-111111111111', 500, 'triche');
  exception when others then
    v_rejected := true;
  end;
  reset role;

  if not v_rejected then
    raise exception 'ECHEC : écriture directe dans credit_ledger autorisée';
  end if;
  raise notice 'OK  credit_ledger en écriture refusée côté client';
end $$;

-- ---------------------------------------------------------------------------
-- 10. Le ledger est append-only pour le client (UPDATE et DELETE)
-- ---------------------------------------------------------------------------

do $$
declare
  v_update_rejected boolean := false;
  v_delete_rejected boolean := false;
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
    update public.credit_ledger set delta = 500
     where user_id = '11111111-1111-1111-1111-111111111111';
  exception when others then
    v_update_rejected := true;
  end;
  reset role;

  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
    delete from public.credit_ledger
     where user_id = '11111111-1111-1111-1111-111111111111';
  exception when others then
    v_delete_rejected := true;
  end;
  reset role;

  if not v_update_rejected then
    raise exception 'ECHEC : lignes de ledger modifiables — solde non auditable';
  end if;
  if not v_delete_rejected then
    raise exception 'ECHEC : lignes de ledger supprimables — solde non auditable';
  end if;
  raise notice 'OK  credit_ledger append-only côté client (UPDATE et DELETE bloqués)';
end $$;

-- ---------------------------------------------------------------------------
-- 11. Job échoué : remboursement automatique, et une seule fois
-- ---------------------------------------------------------------------------

select public.fail_job_and_refund(:'job_id', 'timeout fournisseur');

do $$
declare v integer;
begin
  select credits_balance into v from public.profiles
   where id = '11111111-1111-1111-1111-111111111111';
  if v <> 10 then
    raise exception 'ECHEC : remboursement attendu (solde 10), obtenu %', v;
  end if;
  raise notice 'OK  job échoué : crédits remboursés';
end $$;

-- Rejeu du webhook d'échec
select public.fail_job_and_refund(:'job_id', 'timeout fournisseur');

do $$
declare v integer;
begin
  select credits_balance into v from public.profiles
   where id = '11111111-1111-1111-1111-111111111111';
  if v <> 10 then
    raise exception 'ECHEC : double remboursement sur webhook rejoué (solde %)', v;
  end if;
  raise notice 'OK  remboursement idempotent';
end $$;

-- ---------------------------------------------------------------------------
-- 12. fail_job_and_refund est hors de portée du client
-- ---------------------------------------------------------------------------

do $$
declare v_rejected boolean := false;
begin
  begin
    set local role authenticated;
    set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
    perform public.fail_job_and_refund(
      'aaaaaaaa-0000-0000-0000-000000000001', 'auto-remboursement');
  exception when others then
    v_rejected := true;
  end;
  reset role;

  if not v_rejected then
    raise exception 'ECHEC : fail_job_and_refund appelable par le client';
  end if;
  raise notice 'OK  fonctions de webhook réservées au service_role';
end $$;

-- ---------------------------------------------------------------------------
-- 13. L'arbre de versions tient (parent_version_id)
-- ---------------------------------------------------------------------------

insert into public.versions (id, project_id, status, seed)
values ('bbbbbbbb-0000-0000-0000-000000000001',
        'aaaaaaaa-0000-0000-0000-000000000001', 'ready', 42);

insert into public.versions (id, project_id, parent_version_id, label, status)
values ('bbbbbbbb-0000-0000-0000-000000000002',
        'aaaaaaaa-0000-0000-0000-000000000001',
        'bbbbbbbb-0000-0000-0000-000000000001', 'refrain retravaillé', 'ready');

do $$
declare v integer;
begin
  with recursive tree as (
    select id, parent_version_id from public.versions
     where id = 'bbbbbbbb-0000-0000-0000-000000000002'
    union all
    select v.id, v.parent_version_id
      from public.versions v join tree t on v.id = t.parent_version_id
  )
  select count(*) into v from tree;

  if v <> 2 then
    raise exception 'ECHEC : arbre de versions non remontable (% nœud(s))', v;
  end if;
  raise notice 'OK  arbre de versions remontable jusqu''à la racine';
end $$;

-- ---------------------------------------------------------------------------
-- 14. Suppression d'un projet par son propriétaire
-- ---------------------------------------------------------------------------
--
-- Régression : tant que jobs.project_id était en CASCADE, cette suppression
-- échouait. La cascade atteignait `jobs`, dont la disparition forçait un
-- UPDATE ... SET job_id = NULL sur le ledger append-only, bloqué par le trigger.
-- L'utilisateur se retrouvait avec des projets indélébiles.

do $$
declare v_versions integer;
begin
  set local role authenticated;
  set local request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111"}';
  delete from public.projects where id = 'aaaaaaaa-0000-0000-0000-000000000001';
  reset role;

  select count(*) into v_versions from public.versions;
  if v_versions <> 0 then
    raise exception 'ECHEC : % version(s) orpheline(s) après suppression du projet', v_versions;
  end if;
  raise notice 'OK  projet supprimable par son propriétaire, versions en cascade';
end $$;

-- Le contenu disparaît, la comptabilité reste.
do $$
declare
  v_ledger integer;
  v_jobs   integer;
begin
  select count(*) into v_ledger from public.credit_ledger
   where user_id = '11111111-1111-1111-1111-111111111111';
  if v_ledger = 0 then
    raise exception 'ECHEC : historique comptable effacé avec le projet';
  end if;

  select count(*) into v_jobs from public.jobs where project_id is null;
  if v_jobs = 0 then
    raise exception 'ECHEC : jobs supprimés avec le projet — dépenses non traçables';
  end if;
  raise notice 'OK  ledger et jobs conservés après suppression du contenu';
end $$;

-- ---------------------------------------------------------------------------
-- 15. Suppression de compte (exigence App Store / RGPD)
-- ---------------------------------------------------------------------------

do $$
declare v_left integer;
begin
  delete from auth.users where id = '11111111-1111-1111-1111-111111111111';

  select count(*) into v_left from public.credit_ledger
   where user_id = '11111111-1111-1111-1111-111111111111';
  if v_left <> 0 then
    raise exception 'ECHEC : % ligne(s) de ledger survivent à la suppression du compte', v_left;
  end if;

  select count(*) into v_left from public.profiles
   where id = '11111111-1111-1111-1111-111111111111';
  if v_left <> 0 then
    raise exception 'ECHEC : profil orphelin après suppression du compte';
  end if;
  raise notice 'OK  suppression de compte : effacement complet possible';
end $$;

rollback;

\echo '--- Tous les tests de sécurité sont passés ---'
