-- Melodix — comptabilité des crédits
--
-- Règle non négociable : le client ne débite jamais. Il appelle une fonction qui
-- crée le job et écrit le débit dans la MÊME transaction. Si le solde est
-- insuffisant, l'insertion du débit lève une exception et le job n'existe pas.
-- Il est structurellement impossible de lancer une génération non payée.

-- ---------------------------------------------------------------------------
-- Report du ledger sur le solde caché, avec garde anti-découvert
-- ---------------------------------------------------------------------------

create or replace function public.apply_credit_ledger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance integer;
begin
  -- Le UPDATE verrouille la ligne de profil : deux générations lancées
  -- simultanément sont sérialisées, ce qui interdit de dépenser deux fois le
  -- même crédit.
  update public.profiles
     set credits_balance = credits_balance + new.delta
   where id = new.user_id
  returning credits_balance into v_balance;

  if v_balance is null then
    raise exception 'Profil introuvable pour l''utilisateur %', new.user_id
      using errcode = 'foreign_key_violation';
  end if;

  if v_balance < 0 then
    raise exception 'Crédits insuffisants (solde résultant : %)', v_balance
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger trg_apply_credit_ledger
  after insert on public.credit_ledger
  for each row execute function public.apply_credit_ledger();

-- Le ledger est append-only : toute correction se fait par une écriture inverse,
-- jamais par une modification. C'est ce qui garde le solde auditable.
--
-- La garde ne vise que les rôles clients. Le service_role doit conserver le droit
-- d'effacer, sans quoi la suppression de compte deviendrait impossible — or elle
-- est exigée par l'App Store et par le RGPD. La vraie barrière côté client reste
-- l'absence de privilège UPDATE/DELETE sur la table (migration 0003) ; ce trigger
-- est une seconde ligne de défense.
create or replace function public.forbid_ledger_mutation()
returns trigger
language plpgsql
as $$
begin
  if current_user in ('authenticated', 'anon') then
    raise exception 'credit_ledger est append-only : écrire une ligne inverse'
      using errcode = 'insufficient_privilege';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger trg_credit_ledger_immutable
  before update or delete on public.credit_ledger
  for each row execute function public.forbid_ledger_mutation();

-- ---------------------------------------------------------------------------
-- Création d'un job payant (appelée par les Edge Functions)
-- ---------------------------------------------------------------------------

create or replace function public.create_paid_job(
  p_project_id   uuid,
  p_kind         job_kind,
  p_credits_cost integer,
  p_payload      jsonb default '{}'::jsonb,
  p_version_id   uuid  default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_job_id  uuid;
begin
  if v_user_id is null then
    raise exception 'Authentification requise' using errcode = 'insufficient_privilege';
  end if;

  if p_credits_cost < 0 then
    raise exception 'Coût en crédits négatif' using errcode = 'check_violation';
  end if;

  -- Vérification d'appartenance explicite : SECURITY DEFINER contourne la RLS,
  -- donc le contrôle doit être fait ici, à la main.
  if not exists (
    select 1 from public.projects
     where id = p_project_id and user_id = v_user_id
  ) then
    raise exception 'Projet introuvable ou non autorisé' using errcode = 'insufficient_privilege';
  end if;

  if p_version_id is not null and not exists (
    select 1 from public.versions
     where id = p_version_id and project_id = p_project_id
  ) then
    raise exception 'Version étrangère au projet' using errcode = 'check_violation';
  end if;

  insert into public.jobs (user_id, project_id, version_id, kind, credits_cost, payload)
  values (v_user_id, p_project_id, p_version_id, p_kind, p_credits_cost, p_payload)
  returning id into v_job_id;

  -- Lève si le solde devient négatif -> rollback complet, job compris.
  if p_credits_cost > 0 then
    insert into public.credit_ledger (user_id, delta, reason, job_id)
    values (v_user_id, -p_credits_cost, 'job:' || p_kind::text, v_job_id);
  end if;

  return v_job_id;
end;
$$;

revoke all on function public.create_paid_job(uuid, job_kind, integer, jsonb, uuid) from public, anon;
grant execute on function public.create_paid_job(uuid, job_kind, integer, jsonb, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Échec d'un job -> remboursement automatique
-- ---------------------------------------------------------------------------
--
-- Un utilisateur qui perd des crédits à cause d'une panne fournisseur demande un
-- remboursement, laisse un avis à une étoile, ou les deux. Automatisé dès le
-- départ, appelé par le webhook fournisseur.

create or replace function public.fail_job_and_refund(
  p_job_id uuid,
  p_error  text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.jobs%rowtype;
begin
  select * into v_job from public.jobs where id = p_job_id for update;

  if not found then
    raise exception 'Job introuvable : %', p_job_id using errcode = 'no_data_found';
  end if;

  -- Idempotent : un webhook rejoué ne rembourse pas deux fois.
  if v_job.status in ('failed', 'cancelled') then
    return;
  end if;

  update public.jobs
     set status = 'failed',
         error = p_error,
         completed_at = now(),
         credits_refunded = (v_job.credits_cost > 0)
   where id = p_job_id;

  if v_job.credits_cost > 0 and not v_job.credits_refunded then
    insert into public.credit_ledger (user_id, delta, reason, job_id)
    values (v_job.user_id, v_job.credits_cost, 'refund:' || v_job.kind::text, p_job_id);
  end if;
end;
$$;

-- Réservée au service_role (webhooks) : jamais appelable depuis l'app, sinon
-- n'importe qui pourrait se rembourser en boucle.
revoke all on function public.fail_job_and_refund(uuid, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Crédit d'un achat RevenueCat (webhook)
-- ---------------------------------------------------------------------------

create or replace function public.grant_credits(
  p_user_id           uuid,
  p_amount            integer,
  p_reason            text,
  p_external_event_id text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_amount <= 0 then
    raise exception 'Montant de crédit invalide : %', p_amount using errcode = 'check_violation';
  end if;

  insert into public.credit_ledger (user_id, delta, reason, external_event_id)
  values (p_user_id, p_amount, p_reason, p_external_event_id)
  -- L'index unique sur external_event_id absorbe les rejeux de webhook.
  on conflict (external_event_id) where external_event_id is not null
  do nothing;
end;
$$;

revoke all on function public.grant_credits(uuid, integer, text, text) from public, anon, authenticated;
