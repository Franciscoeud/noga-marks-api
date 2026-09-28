-- Sales CRM: idempotent reconciliation queue for OPS quotations.
-- OPS remains the source of commercial documents. This migration deliberately
-- does not create one opportunity per quotation or infer commercial outcomes.
begin;

create table if not exists public.crm_ops_reconciliation_runs (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  dry_run boolean not null default true,
  status text not null default 'running',
  started_at timestamptz not null default timezone('utc', now()),
  finished_at timestamptz,
  total_quotes integer not null default 0,
  linked_count integer not null default 0,
  unlinked_count integer not null default 0,
  ambiguous_count integer not null default 0,
  resolved_count integer not null default 0,
  error_count integer not null default 0,
  error_detail text,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_ops_reconciliation_runs_status_check
    check (status in ('running', 'completed', 'failed')),
  constraint crm_ops_reconciliation_runs_counts_check
    check (
      total_quotes >= 0 and linked_count >= 0 and unlinked_count >= 0
      and ambiguous_count >= 0 and resolved_count >= 0 and error_count >= 0
    )
);

create index if not exists idx_crm_ops_reconciliation_runs_unit
  on public.crm_ops_reconciliation_runs (business_unit_id, started_at desc);

create table if not exists public.crm_ops_reconciliation_cases (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  run_id uuid references public.crm_ops_reconciliation_runs(id) on delete set null,
  quotation_id uuid not null references public.ops_quotations(id) on delete cascade,
  status text not null default 'unlinked',
  recommended_action text,
  recommended_account_id uuid references public.crm_accounts(id) on delete set null,
  recommended_opportunity_id uuid references public.crm_opportunities(id) on delete set null,
  confidence numeric(5,4) not null default 0,
  evidence jsonb not null default '[]'::jsonb,
  suggested_quotation_ids jsonb not null default '[]'::jsonb,
  snapshot jsonb not null default '{}'::jsonb,
  resolution jsonb,
  resolved_by uuid,
  resolved_at timestamptz,
  first_seen_at timestamptz not null default timezone('utc', now()),
  last_seen_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_ops_reconciliation_cases_status_check
    check (status in ('linked', 'unlinked', 'ambiguous', 'resolved', 'ignored', 'error')),
  constraint crm_ops_reconciliation_cases_confidence_check
    check (confidence between 0 and 1),
  constraint crm_ops_reconciliation_cases_json_check
    check (jsonb_typeof(evidence) = 'array' and jsonb_typeof(suggested_quotation_ids) = 'array'),
  constraint uq_crm_ops_reconciliation_case unique (business_unit_id, quotation_id)
);

create index if not exists idx_crm_ops_reconciliation_cases_review
  on public.crm_ops_reconciliation_cases (business_unit_id, status, last_seen_at desc);
create index if not exists idx_crm_ops_reconciliation_cases_run
  on public.crm_ops_reconciliation_cases (run_id);

-- ``crm_ops_reconciliation_cases`` is the mutable work queue.  Keep a
-- separate append-only snapshot for every execution so a later rerun,
-- relink or human decision cannot rewrite what that execution found.
create table if not exists public.crm_ops_reconciliation_run_cases (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null,
  case_id uuid not null,
  business_unit_id uuid not null,
  quotation_id uuid not null,
  status text not null,
  recommended_action text,
  recommended_account_id uuid,
  recommended_opportunity_id uuid,
  confidence numeric(5,4) not null default 0,
  evidence jsonb not null default '[]'::jsonb,
  suggested_quotation_ids jsonb not null default '[]'::jsonb,
  quotation_snapshot jsonb not null default '{}'::jsonb,
  case_payload jsonb not null default '{}'::jsonb,
  captured_at timestamptz not null default timezone('utc', now()),
  constraint crm_ops_reconciliation_run_cases_status_check
    check (status in ('linked', 'unlinked', 'ambiguous', 'resolved', 'ignored', 'error')),
  constraint crm_ops_reconciliation_run_cases_confidence_check
    check (confidence between 0 and 1),
  constraint crm_ops_reconciliation_run_cases_json_check
    check (
      jsonb_typeof(evidence) = 'array'
      and jsonb_typeof(suggested_quotation_ids) = 'array'
      and jsonb_typeof(quotation_snapshot) = 'object'
      and jsonb_typeof(case_payload) = 'object'
    ),
  constraint uq_crm_ops_reconciliation_run_case unique (run_id, quotation_id)
);

-- Audit snapshots must outlive mutable queue records.  RESTRICT makes the
-- append-only contract explicit instead of relying on a DELETE trigger to
-- interrupt an ON DELETE CASCADE halfway through a parent operation.
alter table public.crm_ops_reconciliation_run_cases
  drop constraint if exists crm_ops_reconciliation_run_cases_run_id_fkey;
alter table public.crm_ops_reconciliation_run_cases
  add constraint crm_ops_reconciliation_run_cases_run_id_fkey
  foreign key (run_id) references public.crm_ops_reconciliation_runs(id) on delete restrict;
alter table public.crm_ops_reconciliation_run_cases
  drop constraint if exists crm_ops_reconciliation_run_cases_business_unit_id_fkey;
alter table public.crm_ops_reconciliation_run_cases
  add constraint crm_ops_reconciliation_run_cases_business_unit_id_fkey
  foreign key (business_unit_id) references public.crm_business_units(id) on delete restrict;

create index if not exists idx_crm_ops_reconciliation_run_cases_unit
  on public.crm_ops_reconciliation_run_cases (business_unit_id, run_id, captured_at);

alter table public.crm_ops_reconciliation_cases
  add column if not exists review_revision integer not null default 1,
  add column if not exists last_reopened_at timestamptz,
  add column if not exists last_reopen_reason text;

create or replace function public.crm_capture_ops_reconciliation_run_case()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.run_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.crm_ops_reconciliation_runs run
    where run.id = new.run_id
      and run.business_unit_id = new.business_unit_id
  ) then
    raise exception 'Reconciliation run does not belong to the case business unit'
      using errcode = '23514';
  end if;

  insert into public.crm_ops_reconciliation_run_cases (
    run_id,
    case_id,
    business_unit_id,
    quotation_id,
    status,
    recommended_action,
    recommended_account_id,
    recommended_opportunity_id,
    confidence,
    evidence,
    suggested_quotation_ids,
    quotation_snapshot,
    case_payload
  ) values (
    new.run_id,
    new.id,
    new.business_unit_id,
    new.quotation_id,
    new.status,
    new.recommended_action,
    new.recommended_account_id,
    new.recommended_opportunity_id,
    new.confidence,
    new.evidence,
    new.suggested_quotation_ids,
    new.snapshot,
    to_jsonb(new)
  )
  on conflict (run_id, quotation_id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_crm_ops_reconciliation_capture_run_case
  on public.crm_ops_reconciliation_cases;
create trigger trg_crm_ops_reconciliation_capture_run_case
after insert or update on public.crm_ops_reconciliation_cases
for each row execute procedure public.crm_capture_ops_reconciliation_run_case();

-- Capture the latest surviving case for historical runs created before this
-- table existed.  Older snapshots that were never persisted cannot be
-- reconstructed and are deliberately not invented.
insert into public.crm_ops_reconciliation_run_cases (
  run_id, case_id, business_unit_id, quotation_id, status,
  recommended_action, recommended_account_id, recommended_opportunity_id,
  confidence, evidence, suggested_quotation_ids, quotation_snapshot,
  case_payload, captured_at
)
select
  reconciliation_case.run_id,
  reconciliation_case.id,
  reconciliation_case.business_unit_id,
  reconciliation_case.quotation_id,
  reconciliation_case.status,
  reconciliation_case.recommended_action,
  reconciliation_case.recommended_account_id,
  reconciliation_case.recommended_opportunity_id,
  reconciliation_case.confidence,
  reconciliation_case.evidence,
  reconciliation_case.suggested_quotation_ids,
  reconciliation_case.snapshot,
  to_jsonb(reconciliation_case),
  reconciliation_case.last_seen_at
from public.crm_ops_reconciliation_cases reconciliation_case
join public.crm_ops_reconciliation_runs run
  on run.id = reconciliation_case.run_id
 and run.business_unit_id = reconciliation_case.business_unit_id
where reconciliation_case.run_id is not null
on conflict (run_id, quotation_id) do nothing;

create or replace function public.crm_guard_ops_reconciliation_run_case()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'Reconciliation run case history is append-only'
    using errcode = '55000';
end;
$$;

drop trigger if exists trg_crm_ops_reconciliation_run_cases_immutable
  on public.crm_ops_reconciliation_run_cases;
create trigger trg_crm_ops_reconciliation_run_cases_immutable
before update or delete on public.crm_ops_reconciliation_run_cases
for each row execute procedure public.crm_guard_ops_reconciliation_run_case();

-- Stable OPS identifiers are the only automatic account match. Names are not
-- unique because two businesses may legitimately share a trading name.
create unique index if not exists uq_crm_accounts_unit_ops_client
  on public.crm_accounts (business_unit_id, ops_client_id)
  where ops_client_id is not null;

create index if not exists idx_crm_accounts_unit_tax_id
  on public.crm_accounts (business_unit_id, regexp_replace(tax_id, '[^0-9]', '', 'g'))
  where nullif(regexp_replace(tax_id, '[^0-9]', '', 'g'), '') is not null;

create or replace function public.crm_queue_ops_quotation_reconciliation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_linked boolean;
  v_link_opportunity_id uuid;
  v_material_changed boolean := true;
  v_relationship_changed boolean := true;
begin
  if new.business_unit_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_relationship_changed :=
      old.business_unit_id is distinct from new.business_unit_id
      or old.recipient_name_snapshot is distinct from new.recipient_name_snapshot
      or old.recipient_doc_snapshot is distinct from new.recipient_doc_snapshot
      or old.client_id is distinct from new.client_id
      or old.crm_lead_id is distinct from new.crm_lead_id;
    v_material_changed :=
      v_relationship_changed
      or old.currency is distinct from new.currency
      or old.terms_taxes is distinct from new.terms_taxes
      or old.quotation_date is distinct from new.quotation_date
      or old.status is distinct from new.status;

    if old.business_unit_id is distinct from new.business_unit_id
       and old.business_unit_id is not null then
      delete from public.crm_ops_reconciliation_cases reconciliation_case
      where reconciliation_case.business_unit_id = old.business_unit_id
        and reconciliation_case.quotation_id = old.id;
    end if;
  end if;

  select link.opportunity_id
  into v_link_opportunity_id
  from public.crm_opportunity_quotations link
  where link.quotation_id = new.id
    and link.business_unit_id = new.business_unit_id
  limit 1;
  v_linked := v_link_opportunity_id is not null;

  insert into public.crm_ops_reconciliation_cases (
    business_unit_id,
    quotation_id,
    status,
    recommended_action,
    recommended_opportunity_id,
    confidence,
    evidence,
    snapshot,
    last_seen_at
  ) values (
    new.business_unit_id,
    new.id,
    case when v_linked then 'linked' else 'unlinked' end,
    case when v_linked then 'already_linked' else 'review' end,
    v_link_opportunity_id,
    case when v_linked then 1 else 0 end,
    case when v_linked then '["La proforma ya tiene una relación explícita."]'::jsonb else '[]'::jsonb end,
    jsonb_build_object(
      'code', 'CDM-' || lpad(coalesce(new.quotation_number, 0)::text, 4, '0') || '/' || coalesce(new.quotation_year, 0)::text,
      'recipient', new.recipient_name_snapshot,
      'recipient_doc', new.recipient_doc_snapshot,
      'client_id', new.client_id,
      'lead_id', new.crm_lead_id,
      'currency', new.currency,
      'terms_taxes', new.terms_taxes,
      'quotation_date', new.quotation_date,
      'status', new.status
    ),
    timezone('utc', now())
  )
  on conflict (business_unit_id, quotation_id) do update
  set snapshot = excluded.snapshot,
      last_seen_at = excluded.last_seen_at,
      updated_at = timezone('utc', now()),
      status = case
        when v_material_changed
          and (
            crm_ops_reconciliation_cases.status in ('resolved', 'ignored')
            or (v_relationship_changed and v_linked)
          ) then 'ambiguous'
        when v_material_changed then excluded.status
        else crm_ops_reconciliation_cases.status
      end,
      recommended_action = case
        when v_material_changed
          and (
            crm_ops_reconciliation_cases.status in ('resolved', 'ignored')
            or (v_relationship_changed and v_linked)
          ) then 'review_changed_quotation'
        when v_material_changed then excluded.recommended_action
        else crm_ops_reconciliation_cases.recommended_action
      end,
      recommended_account_id = case
        when v_material_changed then null
        else crm_ops_reconciliation_cases.recommended_account_id
      end,
      recommended_opportunity_id = case
        when v_material_changed then v_link_opportunity_id
        else crm_ops_reconciliation_cases.recommended_opportunity_id
      end,
      confidence = case
        when v_material_changed then excluded.confidence
        else crm_ops_reconciliation_cases.confidence
      end,
      evidence = case
        when v_material_changed
          and (
            crm_ops_reconciliation_cases.status in ('resolved', 'ignored')
            or (v_relationship_changed and v_linked)
          ) then excluded.evidence || jsonb_build_array(
            'La proforma cambió después de su revisión y requiere validar nuevamente la relación comercial.'
          )
        when v_material_changed then excluded.evidence
        else crm_ops_reconciliation_cases.evidence
      end,
      suggested_quotation_ids = case
        when v_material_changed then '[]'::jsonb
        else crm_ops_reconciliation_cases.suggested_quotation_ids
      end,
      resolution = case
        when v_material_changed then null
        else crm_ops_reconciliation_cases.resolution
      end,
      resolved_by = case
        when v_material_changed then null
        else crm_ops_reconciliation_cases.resolved_by
      end,
      resolved_at = case
        when v_material_changed then null
        else crm_ops_reconciliation_cases.resolved_at
      end,
      review_revision = case
        when v_material_changed then crm_ops_reconciliation_cases.review_revision + 1
        else crm_ops_reconciliation_cases.review_revision
      end,
      last_reopened_at = case
        when v_material_changed
          and (
            crm_ops_reconciliation_cases.status in ('resolved', 'ignored')
            or (v_relationship_changed and v_linked)
          )
          then timezone('utc', now())
        else crm_ops_reconciliation_cases.last_reopened_at
      end,
      last_reopen_reason = case
        when v_material_changed
          and (
            crm_ops_reconciliation_cases.status in ('resolved', 'ignored')
            or (v_relationship_changed and v_linked)
          )
          then 'quotation_material_change'
        else crm_ops_reconciliation_cases.last_reopen_reason
      end;
  return new;
end;
$$;

drop trigger if exists trg_ops_quotations_queue_crm_reconciliation
  on public.ops_quotations;
create trigger trg_ops_quotations_queue_crm_reconciliation
after insert or update of business_unit_id, recipient_name_snapshot,
  recipient_doc_snapshot, client_id, crm_lead_id, currency, terms_taxes,
  quotation_date, status
on public.ops_quotations
for each row execute procedure public.crm_queue_ops_quotation_reconciliation();

create or replace function public.crm_refresh_reconciliation_link_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quotation_id uuid := coalesce(new.quotation_id, old.quotation_id);
  v_business_unit_id uuid := coalesce(new.business_unit_id, old.business_unit_id);
  v_linked boolean;
  v_link_opportunity_id uuid;
begin
  select link.opportunity_id
  into v_link_opportunity_id
  from public.crm_opportunity_quotations link
  where link.quotation_id = v_quotation_id
    and link.business_unit_id = v_business_unit_id
  limit 1;
  v_linked := v_link_opportunity_id is not null;

  update public.crm_ops_reconciliation_cases
  set status = case
        when tg_op = 'UPDATE'
          and v_linked
          and status = 'resolved'
          and resolution->>'opportunity_id' = v_link_opportunity_id::text
          then 'resolved'
        when v_linked then 'linked'
        else 'unlinked'
      end,
      recommended_action = case
        when tg_op = 'UPDATE'
          and v_linked
          and status = 'resolved'
          and resolution->>'opportunity_id' = v_link_opportunity_id::text
          then recommended_action
        when v_linked then 'already_linked'
        else 'review'
      end,
      recommended_opportunity_id = case
        when v_linked then v_link_opportunity_id
        else null
      end,
      confidence = case
        when tg_op = 'UPDATE'
          and v_linked
          and status = 'resolved'
          and resolution->>'opportunity_id' = v_link_opportunity_id::text
          then confidence
        when v_linked then 1
        else 0
      end,
      evidence = case
        when tg_op = 'UPDATE'
          and v_linked
          and status = 'resolved'
          and resolution->>'opportunity_id' = v_link_opportunity_id::text
          then evidence
        when v_linked then jsonb_build_array('La proforma ya tiene una relación explícita.')
        else jsonb_build_array('El vínculo comercial fue eliminado; la proforma requiere una nueva revisión.')
      end,
      resolution = case
        when tg_op = 'UPDATE'
          and v_linked
          and status = 'resolved'
          and resolution->>'opportunity_id' = v_link_opportunity_id::text
          then resolution
        else null
      end,
      resolved_by = case
        when tg_op = 'UPDATE'
          and v_linked
          and status = 'resolved'
          and resolution->>'opportunity_id' = v_link_opportunity_id::text
          then resolved_by
        else null
      end,
      resolved_at = case
        when tg_op = 'UPDATE'
          and v_linked
          and status = 'resolved'
          and resolution->>'opportunity_id' = v_link_opportunity_id::text
          then resolved_at
        else null
      end,
      review_revision = case
        when not v_linked or status = 'ignored' then review_revision + 1
        else review_revision
      end,
      last_reopened_at = case
        when not v_linked or status = 'ignored' then timezone('utc', now())
        else last_reopened_at
      end,
      last_reopen_reason = case
        when not v_linked then 'quotation_link_removed'
        when status = 'ignored' and v_linked then 'quotation_link_created'
        else last_reopen_reason
      end,
      last_seen_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where business_unit_id = v_business_unit_id
    and quotation_id = v_quotation_id;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_crm_opportunity_quotations_reconciliation
  on public.crm_opportunity_quotations;
create trigger trg_crm_opportunity_quotations_reconciliation
after insert or update or delete on public.crm_opportunity_quotations
for each row execute procedure public.crm_refresh_reconciliation_link_status();

-- Backfill every real quotation dynamically. No opportunity or outcome is
-- inferred here, regardless of quotation count or age.
insert into public.crm_ops_reconciliation_cases (
  business_unit_id, quotation_id, status, recommended_action,
  recommended_opportunity_id, confidence, evidence, snapshot,
  first_seen_at, last_seen_at
)
select
  quotation.business_unit_id,
  quotation.id,
  case when link.opportunity_id is null then 'unlinked' else 'linked' end,
  case when link.opportunity_id is null then 'review' else 'already_linked' end,
  link.opportunity_id,
  case when link.opportunity_id is null then 0 else 1 end,
  case
    when link.opportunity_id is null then '[]'::jsonb
    else '["La proforma ya tiene una relación explícita."]'::jsonb
  end,
  jsonb_build_object(
    'code', 'CDM-' || lpad(coalesce(quotation.quotation_number, 0)::text, 4, '0') || '/' || coalesce(quotation.quotation_year, 0)::text,
    'recipient', quotation.recipient_name_snapshot,
    'client_id', quotation.client_id,
    'lead_id', quotation.crm_lead_id,
    'currency', quotation.currency,
    'terms_taxes', quotation.terms_taxes,
    'quotation_date', quotation.quotation_date
  ),
  coalesce(quotation.created_at, timezone('utc', now())),
  timezone('utc', now())
from public.ops_quotations quotation
left join public.crm_opportunity_quotations link on link.quotation_id = quotation.id
where quotation.business_unit_id is not null
on conflict (business_unit_id, quotation_id) do update
set snapshot = excluded.snapshot,
    status = case
      when excluded.status = 'linked'
        and crm_ops_reconciliation_cases.status = 'resolved'
        and crm_ops_reconciliation_cases.resolution->>'opportunity_id'
          = excluded.recommended_opportunity_id::text
        then crm_ops_reconciliation_cases.status
      when excluded.status = 'unlinked'
        and crm_ops_reconciliation_cases.status = 'ignored'
        then crm_ops_reconciliation_cases.status
      else excluded.status
    end,
    recommended_action = case
      when excluded.status = 'linked'
        and crm_ops_reconciliation_cases.status = 'resolved'
        and crm_ops_reconciliation_cases.resolution->>'opportunity_id'
          = excluded.recommended_opportunity_id::text
        then crm_ops_reconciliation_cases.recommended_action
      when excluded.status = 'unlinked'
        and crm_ops_reconciliation_cases.status = 'ignored'
        then crm_ops_reconciliation_cases.recommended_action
      else excluded.recommended_action
    end,
    recommended_opportunity_id = excluded.recommended_opportunity_id,
    confidence = excluded.confidence,
    evidence = excluded.evidence,
    resolution = case
      when excluded.status = 'linked'
        and crm_ops_reconciliation_cases.status = 'resolved'
        and crm_ops_reconciliation_cases.resolution->>'opportunity_id'
          = excluded.recommended_opportunity_id::text
        then crm_ops_reconciliation_cases.resolution
      when excluded.status = 'unlinked'
        and crm_ops_reconciliation_cases.status = 'ignored'
        then crm_ops_reconciliation_cases.resolution
      else null
    end,
    resolved_by = case
      when (
        excluded.status = 'linked'
        and crm_ops_reconciliation_cases.status = 'resolved'
        and crm_ops_reconciliation_cases.resolution->>'opportunity_id'
          = excluded.recommended_opportunity_id::text
      ) or (
        excluded.status = 'unlinked'
        and crm_ops_reconciliation_cases.status = 'ignored'
      ) then crm_ops_reconciliation_cases.resolved_by
      else null
    end,
    resolved_at = case
      when (
        excluded.status = 'linked'
        and crm_ops_reconciliation_cases.status = 'resolved'
        and crm_ops_reconciliation_cases.resolution->>'opportunity_id'
          = excluded.recommended_opportunity_id::text
      ) or (
        excluded.status = 'unlinked'
        and crm_ops_reconciliation_cases.status = 'ignored'
      ) then crm_ops_reconciliation_cases.resolved_at
      else null
    end,
    review_revision = case
      when crm_ops_reconciliation_cases.status = 'resolved'
        and excluded.status = 'unlinked'
        then crm_ops_reconciliation_cases.review_revision + 1
      when crm_ops_reconciliation_cases.status = 'ignored'
        and excluded.status = 'linked'
        then crm_ops_reconciliation_cases.review_revision + 1
      else crm_ops_reconciliation_cases.review_revision
    end,
    last_reopened_at = case
      when crm_ops_reconciliation_cases.status = 'resolved'
        and excluded.status = 'unlinked'
        then timezone('utc', now())
      when crm_ops_reconciliation_cases.status = 'ignored'
        and excluded.status = 'linked'
        then timezone('utc', now())
      else crm_ops_reconciliation_cases.last_reopened_at
    end,
    last_reopen_reason = case
      when crm_ops_reconciliation_cases.status = 'resolved'
        and excluded.status = 'unlinked'
        then 'quotation_link_missing'
      when crm_ops_reconciliation_cases.status = 'ignored'
        and excluded.status = 'linked'
        then 'quotation_link_created'
      else crm_ops_reconciliation_cases.last_reopen_reason
    end,
    last_seen_at = excluded.last_seen_at,
    updated_at = timezone('utc', now());

-- Recover only explicit lead conversion events whose referenced opportunity
-- still belongs to the same company. This does not infer a relation from a
-- quotation event and is safe to repeat.
with conversion_events as (
  select
    event.business_unit_id,
    event.lead_id,
    coalesce(event.payload_json, event.payload, '{}'::jsonb) as event_payload,
    event.created_at,
    row_number() over (partition by event.lead_id order by event.created_at desc, event.id desc) as lead_rank
  from public.crm_lead_events event
  where event.event_type = 'converted'
    and event.business_unit_id is not null
    and coalesce(event.payload_json, event.payload, '{}'::jsonb)->>'opportunity_id'
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
), valid_relations as (
  select
    event.business_unit_id,
    event.lead_id,
    (event.event_payload->>'opportunity_id')::uuid as opportunity_id,
    case
      when event.event_payload->>'contact_id' ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (event.event_payload->>'contact_id')::uuid
      else null
    end as contact_id,
    event.lead_rank
  from conversion_events event
  join public.crm_opportunities opportunity
    on opportunity.id = (event.event_payload->>'opportunity_id')::uuid
   and opportunity.business_unit_id = event.business_unit_id
)
insert into public.crm_lead_opportunities (
  business_unit_id, lead_id, opportunity_id, contact_id,
  relationship_type, is_primary, idempotency_key
)
select
  relation.business_unit_id,
  relation.lead_id,
  relation.opportunity_id,
  contact.id,
  'converted',
  relation.lead_rank = 1 and not exists (
    select 1 from public.crm_lead_opportunities existing
    where existing.lead_id = relation.lead_id and existing.is_primary
  ),
  'legacy-conversion:' || relation.lead_id::text || ':' || relation.opportunity_id::text
from valid_relations relation
left join public.crm_contacts contact
  on contact.id = relation.contact_id
 and contact.business_unit_id = relation.business_unit_id
on conflict (lead_id, opportunity_id) do nothing;

-- Commit one reconciliation analysis as a single database transaction.  The
-- fuzzy comparison remains in the application, but no account, case or run is
-- visible unless the whole batch validates and commits.
create or replace function public.crm_commit_ops_reconciliation_run(
  p_business_unit_id uuid,
  p_dry_run boolean,
  p_cases jsonb,
  p_account_actions jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_is_service_role boolean :=
    coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_now timestamptz := timezone('utc', now());
  v_run public.crm_ops_reconciliation_runs%rowtype;
  v_case public.crm_ops_reconciliation_cases%rowtype;
  v_account public.crm_accounts%rowtype;
  v_client public.ops_clients%rowtype;
  v_quotation public.ops_quotations%rowtype;
  v_item jsonb;
  v_suggested jsonb;
  v_quotation_id uuid;
  v_client_id uuid;
  v_account_id uuid;
  v_opportunity_id uuid;
  v_actual_link_opportunity_id uuid;
  v_status text;
  v_action text;
  v_confidence numeric;
  v_tax_id text;
  v_candidate_count integer;
  v_payload_count integer;
  v_distinct_count integer;
  v_database_count integer;
  v_recommended_account_id uuid;
  v_account_map jsonb := '{}'::jsonb;
  v_account_results jsonb := '[]'::jsonb;
  v_cases_result jsonb := '[]'::jsonb;
  v_counts jsonb;
begin
  if not v_is_service_role
     and not public.crm_has_business_unit_access(
       p_business_unit_id,
       array['admin','manager']::text[]
     ) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.crm_business_units unit
    where unit.id = p_business_unit_id and unit.active
  ) then
    raise exception 'Business unit is not active' using errcode = '23503';
  end if;
  if jsonb_typeof(coalesce(p_cases, 'null'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_account_actions, 'null'::jsonb)) <> 'array' then
    raise exception 'Cases and account actions must be arrays' using errcode = '22023';
  end if;
  if jsonb_array_length(p_cases) > 5000
     or jsonb_array_length(p_account_actions) > 5000 then
    raise exception 'Reconciliation batch is too large' using errcode = '54000';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('crm-reconciliation:' || p_business_unit_id::text, 0)
  );

  select count(*), count(distinct value->>'quotation_id')
  into v_payload_count, v_distinct_count
  from jsonb_array_elements(p_cases);
  select count(*) into v_database_count
  from public.ops_quotations quotation
  where quotation.business_unit_id = p_business_unit_id;
  if v_payload_count <> v_distinct_count or v_payload_count <> v_database_count then
    raise exception 'Quotation set changed while reconciliation was being prepared'
      using errcode = '40001';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_cases) item
    left join public.ops_quotations quotation
      on quotation.id = (item->>'quotation_id')::uuid
     and quotation.business_unit_id = p_business_unit_id
    where quotation.id is null
  ) then
    raise exception 'A reconciliation quotation is outside the business unit'
      using errcode = '23503';
  end if;
  if (
    select count(*) from jsonb_array_elements(p_account_actions)
  ) <> (
    select count(distinct value->>'ops_client_id')
    from jsonb_array_elements(p_account_actions)
  ) then
    raise exception 'Duplicate account action for OPS client' using errcode = '22023';
  end if;

  insert into public.crm_ops_reconciliation_runs (
    business_unit_id, dry_run, status, started_at, created_by
  ) values (
    p_business_unit_id, coalesce(p_dry_run, true), 'running', v_now, v_actor
  ) returning * into v_run;

  for v_item in select value from jsonb_array_elements(p_account_actions)
  loop
    v_client_id := nullif(v_item->>'ops_client_id', '')::uuid;
    v_action := nullif(btrim(v_item->>'action'), '');
    if v_client_id is null or v_action not in ('attach', 'create') then
      raise exception 'Invalid account reconciliation action' using errcode = '22023';
    end if;
    select client.* into v_client
    from public.ops_clients client
    where client.id = v_client_id
      and exists (
        select 1 from public.ops_quotations quotation
        where quotation.business_unit_id = p_business_unit_id
          and quotation.client_id = client.id
      )
    for update;
    if not found then
      raise exception 'OPS client is not part of this reconciliation'
        using errcode = '23503';
    end if;

    if coalesce(p_dry_run, true) then
      v_account_results := v_account_results || jsonb_build_array(
        jsonb_build_object(
          'ops_client_id', v_client_id,
          'account_id', null,
          'result', 'dry_run'
        )
      );
      continue;
    end if;

    v_tax_id := nullif(regexp_replace(coalesce(v_client.ruc, ''), '[^0-9]', '', 'g'), '');
    v_account_id := nullif(v_item->>'account_id', '')::uuid;
    if v_action = 'attach' then
      if v_account_id is null or v_tax_id is null then
        raise exception 'Exact RUC and account are required to attach an OPS client'
          using errcode = '22023';
      end if;
      select account.* into v_account
      from public.crm_accounts account
      where account.id = v_account_id
        and account.business_unit_id = p_business_unit_id
      for update;
      if not found
         or v_account.ops_client_id is distinct from null
            and v_account.ops_client_id <> v_client_id
         or nullif(regexp_replace(coalesce(v_account.tax_id, ''), '[^0-9]', '', 'g'), '')
            is distinct from v_tax_id then
        raise exception 'Account is not an exact reusable match for OPS client'
          using errcode = '23514';
      end if;
      update public.crm_accounts
      set ops_client_id = v_client_id,
          updated_at = v_now
      where id = v_account.id
      returning * into v_account;
      v_action := 'attached';
    else
      select account.* into v_account
      from public.crm_accounts account
      where account.business_unit_id = p_business_unit_id
        and account.ops_client_id = v_client_id
      limit 1
      for update;
      if found then
        v_action := 'reused';
      else
        v_candidate_count := 0;
        if v_tax_id is not null then
          select count(*) into v_candidate_count
          from public.crm_accounts account
          where account.business_unit_id = p_business_unit_id
            and nullif(regexp_replace(coalesce(account.tax_id, ''), '[^0-9]', '', 'g'), '') = v_tax_id;
        end if;
        if v_candidate_count > 1 then
          raise exception 'RUC has more than one CRM account candidate'
            using errcode = '21000';
        elsif v_candidate_count = 1 then
          select account.* into v_account
          from public.crm_accounts account
          where account.business_unit_id = p_business_unit_id
            and nullif(regexp_replace(coalesce(account.tax_id, ''), '[^0-9]', '', 'g'), '') = v_tax_id
          for update;
          if v_account.ops_client_id is not null
             and v_account.ops_client_id <> v_client_id then
            raise exception 'RUC account is already linked to another OPS client'
              using errcode = '23505';
          end if;
          update public.crm_accounts
          set ops_client_id = v_client_id,
              updated_at = v_now
          where id = v_account.id
          returning * into v_account;
          v_action := 'attached';
        else
          insert into public.crm_accounts (
            business_unit_id, ops_client_id, name, tax_id, email, phone,
            billing_address, account_kind, created_by, created_at, updated_at
          ) values (
            p_business_unit_id,
            v_client_id,
            coalesce(nullif(btrim(v_client.name), ''), 'Cliente OPS sin nombre'),
            v_tax_id,
            v_client.email,
            v_client.phone,
            case when nullif(btrim(v_client.address), '') is not null
              then jsonb_build_object('address', v_client.address)
              else null end,
            'customer',
            v_actor,
            v_now,
            v_now
          ) returning * into v_account;
          v_action := 'created';
        end if;
      end if;
    end if;
    v_account_map := v_account_map || jsonb_build_object(
      v_client_id::text, v_account.id::text
    );
    v_account_results := v_account_results || jsonb_build_array(
      jsonb_build_object(
        'ops_client_id', v_client_id,
        'account_id', v_account.id,
        'result', v_action
      )
    );
  end loop;

  for v_item in select value from jsonb_array_elements(p_cases)
  loop
    v_quotation_id := nullif(v_item->>'quotation_id', '')::uuid;
    v_status := nullif(btrim(v_item->>'status'), '');
    v_confidence := coalesce((v_item->>'confidence')::numeric, 0);
    if v_status not in ('linked','unlinked','ambiguous','resolved','ignored','error')
       or v_confidence < 0 or v_confidence > 1
       or jsonb_typeof(coalesce(v_item->'evidence', 'null'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(v_item->'suggested_quotation_ids', 'null'::jsonb)) <> 'array'
       or jsonb_typeof(coalesce(v_item->'snapshot', 'null'::jsonb)) <> 'object' then
      raise exception 'Invalid reconciliation case payload' using errcode = '22023';
    end if;
    select quotation.* into v_quotation
    from public.ops_quotations quotation
    where quotation.id = v_quotation_id
      and quotation.business_unit_id = p_business_unit_id
    for share;
    if not found then
      raise exception 'Quotation set changed while reconciliation was being prepared'
        using errcode = '40001';
    end if;
    if coalesce(v_item->'snapshot'->>'recipient', '')
         <> coalesce(v_quotation.recipient_name_snapshot, '')
       or coalesce(v_item->'snapshot'->>'recipient_doc', '')
         <> coalesce(v_quotation.recipient_doc_snapshot, '')
       or coalesce(v_item->'snapshot'->>'recipient_type', '')
         <> coalesce(v_quotation.recipient_type, '')
       or coalesce(v_item->'snapshot'->>'client_id', '')
         <> coalesce(v_quotation.client_id::text, '')
       or coalesce(v_item->'snapshot'->>'lead_id', '')
         <> coalesce(v_quotation.crm_lead_id::text, '')
       or coalesce(v_item->'snapshot'->>'currency', '')
         <> coalesce(v_quotation.currency, '')
       or coalesce(v_item->'snapshot'->>'terms_taxes', '')
         <> coalesce(v_quotation.terms_taxes, '')
       or coalesce(v_item->'snapshot'->>'quotation_date', '')
         <> coalesce(v_quotation.quotation_date::text, '')
       or coalesce(v_item->'snapshot'->>'quotation_status', '')
         <> coalesce(v_quotation.status, '') then
      raise exception 'Quotation changed while reconciliation was being prepared'
        using errcode = '40001';
    end if;
    v_account_id := nullif(v_item->>'recommended_account_id', '')::uuid;
    v_client_id := nullif(v_item->'snapshot'->>'client_id', '')::uuid;
    if v_account_id is null and v_client_id is not null
       and v_account_map ? v_client_id::text then
      v_account_id := (v_account_map->>v_client_id::text)::uuid;
    end if;
    if v_account_id is not null and not exists (
      select 1 from public.crm_accounts account
      where account.id = v_account_id
        and account.business_unit_id = p_business_unit_id
    ) then
      raise exception 'Recommended account is outside the business unit'
        using errcode = '23503';
    end if;
    v_opportunity_id := nullif(v_item->>'recommended_opportunity_id', '')::uuid;
    if v_opportunity_id is not null and not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = v_opportunity_id
        and opportunity.business_unit_id = p_business_unit_id
    ) then
      raise exception 'Recommended opportunity is outside the business unit'
        using errcode = '23503';
    end if;
    v_actual_link_opportunity_id := null;
    select link.opportunity_id into v_actual_link_opportunity_id
    from public.crm_opportunity_quotations link
    where link.business_unit_id = p_business_unit_id
      and link.quotation_id = v_quotation_id
    limit 1;
    if (
      v_actual_link_opportunity_id is not null
      and (
        v_status not in ('linked', 'resolved')
        or v_opportunity_id is distinct from v_actual_link_opportunity_id
      )
    ) or (
      v_actual_link_opportunity_id is null
      and v_status in ('linked', 'resolved')
    ) then
      raise exception 'Quotation link changed while reconciliation was being prepared'
        using errcode = '40001';
    end if;
    for v_suggested in select value from jsonb_array_elements(v_item->'suggested_quotation_ids')
    loop
      if not exists (
        select 1 from public.ops_quotations quotation
        where quotation.id = (trim(both '"' from v_suggested::text))::uuid
          and quotation.business_unit_id = p_business_unit_id
      ) then
        raise exception 'Suggested quotation is outside the business unit'
          using errcode = '23503';
      end if;
    end loop;

    insert into public.crm_ops_reconciliation_cases (
      business_unit_id, run_id, quotation_id, status, recommended_action,
      recommended_account_id, recommended_opportunity_id, confidence,
      evidence, suggested_quotation_ids, snapshot, last_seen_at
    ) values (
      p_business_unit_id,
      v_run.id,
      v_quotation_id,
      v_status,
      nullif(btrim(v_item->>'recommended_action'), ''),
      v_account_id,
      v_opportunity_id,
      v_confidence,
      v_item->'evidence',
      v_item->'suggested_quotation_ids',
      v_item->'snapshot',
      v_now
    )
    on conflict (business_unit_id, quotation_id) do update
    set run_id = excluded.run_id,
        status = case
          when crm_ops_reconciliation_cases.status in ('resolved','ignored')
            then crm_ops_reconciliation_cases.status
          else excluded.status end,
        recommended_action = case
          when crm_ops_reconciliation_cases.status in ('resolved','ignored')
            then crm_ops_reconciliation_cases.recommended_action
          else excluded.recommended_action end,
        recommended_account_id = case
          when crm_ops_reconciliation_cases.status in ('resolved','ignored')
            then crm_ops_reconciliation_cases.recommended_account_id
          else excluded.recommended_account_id end,
        recommended_opportunity_id = case
          when crm_ops_reconciliation_cases.status in ('resolved','ignored')
            then crm_ops_reconciliation_cases.recommended_opportunity_id
          else excluded.recommended_opportunity_id end,
        confidence = case
          when crm_ops_reconciliation_cases.status in ('resolved','ignored')
            then crm_ops_reconciliation_cases.confidence
          else excluded.confidence end,
        evidence = case
          when crm_ops_reconciliation_cases.status in ('resolved','ignored')
            then crm_ops_reconciliation_cases.evidence
          else excluded.evidence end,
        suggested_quotation_ids = case
          when crm_ops_reconciliation_cases.status in ('resolved','ignored')
            then crm_ops_reconciliation_cases.suggested_quotation_ids
          else excluded.suggested_quotation_ids end,
        snapshot = excluded.snapshot,
        last_seen_at = excluded.last_seen_at,
        updated_at = v_now
    returning * into v_case;
    v_cases_result := v_cases_result || jsonb_build_array(to_jsonb(v_case));
  end loop;

  select jsonb_build_object(
    'linked_count', count(*) filter (where status = 'linked'),
    'unlinked_count', count(*) filter (where status in ('unlinked','ignored')),
    'ambiguous_count', count(*) filter (where status = 'ambiguous'),
    'resolved_count', count(*) filter (where status = 'resolved'),
    'error_count', count(*) filter (where status = 'error')
  ) into v_counts
  from jsonb_to_recordset(v_cases_result) as rows(status text);

  update public.crm_ops_reconciliation_runs
  set status = 'completed',
      finished_at = v_now,
      total_quotes = v_payload_count,
      linked_count = coalesce((v_counts->>'linked_count')::integer, 0),
      unlinked_count = coalesce((v_counts->>'unlinked_count')::integer, 0),
      ambiguous_count = coalesce((v_counts->>'ambiguous_count')::integer, 0),
      resolved_count = coalesce((v_counts->>'resolved_count')::integer, 0),
      error_count = coalesce((v_counts->>'error_count')::integer, 0)
  where id = v_run.id
  returning * into v_run;

  return jsonb_build_object(
    'run', to_jsonb(v_run),
    'cases', v_cases_result,
    'accounts', v_account_results
  );
end;
$$;

-- Make selection of the current proposal atomic.  The quotation itself is
-- globally unique in the relation, so retries return the same link and a
-- conflicting opportunity is rejected before the previous current link is
-- changed.
create or replace function public.crm_link_opportunity_quotation(
  p_business_unit_id uuid,
  p_opportunity_id uuid,
  p_quotation_id uuid,
  p_link_type text default 'proposal',
  p_is_current boolean default false,
  p_sent_at timestamptz default null,
  p_sent_channel text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_is_service_role boolean :=
    coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_owner uuid;
  v_existing public.crm_opportunity_quotations%rowtype;
  v_link public.crm_opportunity_quotations%rowtype;
begin
  if p_link_type not in ('proposal', 'revision', 'alternative', 'replaced') then
    raise exception 'Invalid quotation link type';
  end if;
  if (p_sent_at is null) <> (nullif(btrim(p_sent_channel), '') is null) then
    raise exception 'Quotation sent date and channel must be provided together';
  end if;

  select opportunity.owner_user_id into v_owner
  from public.crm_opportunities opportunity
  where opportunity.id = p_opportunity_id
    and opportunity.business_unit_id = p_business_unit_id;
  if not found then
    raise exception 'Opportunity not found in business unit';
  end if;
  if not v_is_service_role
     and not public.crm_can_edit_business_record(p_business_unit_id, v_owner, true) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.ops_quotations quotation
    where quotation.id = p_quotation_id
      and quotation.business_unit_id = p_business_unit_id
  ) then
    raise exception 'Quotation not found in business unit';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_opportunity_id::text, 0));
  select * into v_existing
  from public.crm_opportunity_quotations link
  where link.quotation_id = p_quotation_id
  for update;
  if found and v_existing.opportunity_id <> p_opportunity_id then
    raise exception 'Quotation is already linked to another opportunity'
      using errcode = '23505';
  end if;

  insert into public.crm_opportunity_quotations (
    business_unit_id, opportunity_id, quotation_id, link_type, is_current,
    sent_at, sent_channel, sent_by, created_by, updated_at
  ) values (
    p_business_unit_id, p_opportunity_id, p_quotation_id, p_link_type, false,
    p_sent_at, nullif(btrim(p_sent_channel), ''),
    case when p_sent_at is not null then v_actor else null end,
    v_actor, timezone('utc', now())
  )
  on conflict (quotation_id) do update
  set link_type = excluded.link_type,
      sent_at = excluded.sent_at,
      sent_channel = excluded.sent_channel,
      sent_by = case
        when excluded.sent_at is not null then coalesce(excluded.sent_by, crm_opportunity_quotations.sent_by)
        else null
      end,
      updated_at = timezone('utc', now())
  returning * into v_link;

  if p_is_current then
    update public.crm_opportunity_quotations
    set is_current = false, updated_at = timezone('utc', now())
    where opportunity_id = p_opportunity_id
      and id <> v_link.id
      and is_current;
    update public.crm_opportunity_quotations
    set is_current = true, updated_at = timezone('utc', now())
    where id = v_link.id
    returning * into v_link;
  elsif v_link.is_current then
    update public.crm_opportunity_quotations
    set is_current = false, updated_at = timezone('utc', now())
    where id = v_link.id
    returning * into v_link;
  end if;

  return to_jsonb(v_link);
end;
$$;

create or replace function public.crm_unlink_opportunity_quotation(
  p_business_unit_id uuid,
  p_opportunity_id uuid,
  p_quotation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_is_service_role boolean :=
    coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_owner uuid;
  v_link public.crm_opportunity_quotations%rowtype;
begin
  select opportunity.owner_user_id into v_owner
  from public.crm_opportunities opportunity
  where opportunity.id = p_opportunity_id
    and opportunity.business_unit_id = p_business_unit_id;
  if not found then
    raise exception 'Opportunity not found in business unit';
  end if;
  if not v_is_service_role
     and not public.crm_can_edit_business_record(p_business_unit_id, v_owner, true) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;

  select * into v_link
  from public.crm_opportunity_quotations link
  where link.business_unit_id = p_business_unit_id
    and link.opportunity_id = p_opportunity_id
    and link.quotation_id = p_quotation_id
  for update;
  if not found then
    raise exception 'Quotation link not found';
  end if;
  if v_link.is_current then
    raise exception 'Current quotation cannot be unlinked';
  end if;

  delete from public.crm_opportunity_quotations where id = v_link.id;
  return true;
end;
$$;

create or replace function public.crm_link_lead_opportunity(
  p_business_unit_id uuid,
  p_lead_id uuid,
  p_opportunity_id uuid,
  p_contact_id uuid default null,
  p_relationship_type text default 'converted',
  p_is_primary boolean default true,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_is_service_role boolean :=
    coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_opportunity_account_id uuid;
  v_contact_account_id uuid;
  v_prior public.crm_lead_opportunities%rowtype;
  v_link public.crm_lead_opportunities%rowtype;
begin
  if p_relationship_type not in ('originated', 'converted', 'influenced', 'related') then
    raise exception 'Invalid lead opportunity relationship type';
  end if;
  if not v_is_service_role and (
    not public.crm_can_edit_lead_child(p_business_unit_id, p_lead_id)
    or not public.crm_can_edit_opportunity_child(p_business_unit_id, p_opportunity_id)
  ) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;

  select opportunity.account_id into v_opportunity_account_id
  from public.crm_opportunities opportunity
  where opportunity.id = p_opportunity_id
    and opportunity.business_unit_id = p_business_unit_id;
  if not found then
    raise exception 'Opportunity not found in business unit';
  end if;
  if not exists (
    select 1 from public.crm_leads lead
    where lead.id = p_lead_id
      and lead.business_unit_id = p_business_unit_id
  ) then
    raise exception 'Lead not found in business unit';
  end if;
  if p_contact_id is not null then
    select contact.account_id into v_contact_account_id
    from public.crm_contacts contact
    where contact.id = p_contact_id
      and contact.business_unit_id = p_business_unit_id;
    if not found then
      raise exception 'Contact not found in business unit';
    end if;
    if v_opportunity_account_id is not null
       and v_contact_account_id is not null
       and v_contact_account_id <> v_opportunity_account_id then
      raise exception 'Contact belongs to another opportunity account';
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_lead_id::text, 0));
  if nullif(btrim(p_idempotency_key), '') is not null then
    select * into v_prior
    from public.crm_lead_opportunities relation
    where relation.business_unit_id = p_business_unit_id
      and relation.lead_id = p_lead_id
      and relation.idempotency_key = nullif(btrim(p_idempotency_key), '')
    for update;
    if found and v_prior.opportunity_id <> p_opportunity_id then
      raise exception 'Idempotency key is already linked to another opportunity'
        using errcode = '23505';
    end if;
  end if;

  insert into public.crm_lead_opportunities (
    business_unit_id, lead_id, opportunity_id, contact_id,
    relationship_type, is_primary, idempotency_key, created_by
  ) values (
    p_business_unit_id, p_lead_id, p_opportunity_id, p_contact_id,
    p_relationship_type, false, nullif(btrim(p_idempotency_key), ''), v_actor
  )
  on conflict (lead_id, opportunity_id) do update
  set contact_id = coalesce(excluded.contact_id, crm_lead_opportunities.contact_id),
      relationship_type = excluded.relationship_type,
      idempotency_key = coalesce(excluded.idempotency_key, crm_lead_opportunities.idempotency_key)
  returning * into v_link;

  if p_is_primary then
    update public.crm_lead_opportunities
    set is_primary = false
    where lead_id = p_lead_id
      and id <> v_link.id
      and is_primary;
    update public.crm_lead_opportunities
    set is_primary = true
    where id = v_link.id
    returning * into v_link;
  elsif v_link.is_primary then
    update public.crm_lead_opportunities
    set is_primary = false
    where id = v_link.id
    returning * into v_link;
  end if;

  return to_jsonb(v_link);
end;
$$;

-- Contact assignment also needs to be atomic.  Some historical installations
-- never received the old `(opportunity_id, contact_id)` unique index, and a
-- contact may legitimately play more than one role in the same negotiation.
-- Serialize changes per opportunity and make the natural key explicit as
-- opportunity + contact + role without relying on deployment-specific indexes.
create or replace function public.crm_link_opportunity_contact(
  p_business_unit_id uuid,
  p_opportunity_id uuid,
  p_contact_id uuid,
  p_contact_role text default 'other',
  p_is_primary boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_is_service_role boolean :=
    coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_opportunity_account_id uuid;
  v_contact_account_id uuid;
  v_role text := coalesce(nullif(btrim(lower(p_contact_role)), ''), 'other');
  v_link public.crm_opportunity_contacts%rowtype;
begin
  if v_role not in ('requester', 'buyer', 'approver', 'other') then
    raise exception 'Invalid opportunity contact role';
  end if;
  if not v_is_service_role
     and not public.crm_can_edit_opportunity_child(p_business_unit_id, p_opportunity_id) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;

  select opportunity.account_id into v_opportunity_account_id
  from public.crm_opportunities opportunity
  where opportunity.id = p_opportunity_id
    and opportunity.business_unit_id = p_business_unit_id;
  if not found then
    raise exception 'Opportunity not found in business unit';
  end if;

  select contact.account_id into v_contact_account_id
  from public.crm_contacts contact
  where contact.id = p_contact_id
    and contact.business_unit_id = p_business_unit_id;
  if not found then
    raise exception 'Contact not found in business unit';
  end if;
  if v_opportunity_account_id is not null
     and v_contact_account_id is not null
     and v_opportunity_account_id <> v_contact_account_id then
    raise exception 'Contact belongs to another opportunity account';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_opportunity_id::text, 0));
  select * into v_link
  from public.crm_opportunity_contacts relation
  where relation.opportunity_id = p_opportunity_id
    and relation.contact_id = p_contact_id
    and coalesce(nullif(btrim(lower(relation.contact_role)), ''), 'other') = v_role
  order by relation.created_at nulls last, relation.id
  limit 1
  for update;

  if not found then
    insert into public.crm_opportunity_contacts (
      id, business_unit_id, opportunity_id, contact_id, contact_role, is_primary, created_at
    ) values (
      gen_random_uuid(), p_business_unit_id, p_opportunity_id, p_contact_id, v_role, false,
      timezone('utc', now())
    )
    returning * into v_link;
  end if;

  if p_is_primary then
    update public.crm_opportunity_contacts
    set is_primary = false
    where opportunity_id = p_opportunity_id
      and id <> v_link.id
      and is_primary;
    update public.crm_opportunity_contacts
    set is_primary = true
    where id = v_link.id
    returning * into v_link;
  elsif v_link.is_primary then
    update public.crm_opportunity_contacts
    set is_primary = false
    where id = v_link.id
    returning * into v_link;
  end if;

  return to_jsonb(v_link);
end;
$$;

create or replace function public.crm_unlink_opportunity_contact(
  p_business_unit_id uuid,
  p_opportunity_id uuid,
  p_relation_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_is_service_role boolean :=
    coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_link public.crm_opportunity_contacts%rowtype;
begin
  if not v_is_service_role
     and not public.crm_can_edit_opportunity_child(p_business_unit_id, p_opportunity_id) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_opportunity_id::text, 0));
  select * into v_link
  from public.crm_opportunity_contacts relation
  where relation.id = p_relation_id
    and relation.business_unit_id = p_business_unit_id
    and relation.opportunity_id = p_opportunity_id
  for update;
  if not found then
    raise exception 'Opportunity contact link not found';
  end if;

  delete from public.crm_opportunity_contacts where id = v_link.id;
  return true;
end;
$$;

-- Finalize all relationships and lead state in one transaction.  Account,
-- contact and opportunity rows are created beforehand with conversion_key so
-- a retry can reuse them; this function prevents a partially linked conversion.
create or replace function public.crm_finalize_lead_conversion(
  p_business_unit_id uuid,
  p_lead_id uuid,
  p_opportunity_id uuid,
  p_contact_id uuid default null,
  p_account_id uuid default null,
  p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_is_service_role boolean :=
    coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_opportunity_account_id uuid;
  v_contact_account_id uuid;
  v_lead_link jsonb;
  v_contact_link jsonb;
begin
  if not v_is_service_role and (
    not public.crm_can_edit_lead_child(p_business_unit_id, p_lead_id)
    or not public.crm_can_edit_opportunity_child(p_business_unit_id, p_opportunity_id)
  ) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_lead_id::text, 0));

  select opportunity.account_id into v_opportunity_account_id
  from public.crm_opportunities opportunity
  where opportunity.id = p_opportunity_id
    and opportunity.business_unit_id = p_business_unit_id;
  if not found then
    raise exception 'Opportunity not found in business unit';
  end if;
  if not exists (
    select 1 from public.crm_leads lead
    where lead.id = p_lead_id
      and lead.business_unit_id = p_business_unit_id
  ) then
    raise exception 'Lead not found in business unit';
  end if;
  if p_account_id is not null and not exists (
    select 1 from public.crm_accounts account
    where account.id = p_account_id
      and account.business_unit_id = p_business_unit_id
      and not account.is_archived
  ) then
    raise exception 'Account not found in business unit';
  end if;
  if p_account_id is not null
     and v_opportunity_account_id is not null
     and p_account_id <> v_opportunity_account_id then
    raise exception 'Opportunity belongs to another account';
  end if;
  if p_account_id is not null and v_opportunity_account_id is null then
    update public.crm_opportunities
    set account_id = p_account_id,
        updated_at = timezone('utc', now()),
        updated_by = auth.uid()
    where id = p_opportunity_id
      and business_unit_id = p_business_unit_id;
    v_opportunity_account_id := p_account_id;
  end if;

  if p_contact_id is not null then
    select contact.account_id into v_contact_account_id
    from public.crm_contacts contact
    where contact.id = p_contact_id
      and contact.business_unit_id = p_business_unit_id;
    if not found then
      raise exception 'Contact not found in business unit';
    end if;
    if p_account_id is not null and v_contact_account_id is null then
      update public.crm_contacts
      set account_id = p_account_id,
          updated_at = timezone('utc', now())
      where id = p_contact_id
        and business_unit_id = p_business_unit_id;
      v_contact_account_id := p_account_id;
    end if;
    if v_opportunity_account_id is not null
       and v_contact_account_id is not null
       and v_opportunity_account_id <> v_contact_account_id then
      raise exception 'Contact belongs to another opportunity account';
    end if;
  end if;

  v_lead_link := public.crm_link_lead_opportunity(
    p_business_unit_id,
    p_lead_id,
    p_opportunity_id,
    p_contact_id,
    'converted',
    true,
    p_idempotency_key
  );

  if p_contact_id is not null then
    v_contact_link := public.crm_link_opportunity_contact(
      p_business_unit_id,
      p_opportunity_id,
      p_contact_id,
      'requester',
      true
    );
  end if;

  update public.crm_leads
  set account_id = coalesce(p_account_id, account_id),
      lead_status = 'converted',
      status = 'convertido',
      updated_at = timezone('utc', now())
  where id = p_lead_id
    and business_unit_id = p_business_unit_id;

  return jsonb_build_object(
    'relation', v_lead_link,
    'contact_relation', v_contact_link
  );
end;
$$;

-- Resolve one review case without exposing the intermediate opportunity or
-- quotation link.  Retries reuse both the conversion key and the existing
-- link, and the audit event is de-duplicated by case id.
create or replace function public.crm_resolve_ops_reconciliation_case(
  p_business_unit_id uuid,
  p_case_id uuid,
  p_action text,
  p_account_id uuid default null,
  p_opportunity_id uuid default null,
  p_opportunity_name text default null,
  p_link_type text default 'proposal',
  p_is_current boolean default true,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_is_service_role boolean :=
    coalesce(current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v_now timestamptz := timezone('utc', now());
  v_case public.crm_ops_reconciliation_cases%rowtype;
  v_opportunity public.crm_opportunities%rowtype;
  v_existing_link public.crm_opportunity_quotations%rowtype;
  v_link jsonb;
  v_lead_link jsonb;
  v_lead_id uuid;
  v_conversion_key text;
  v_snapshot jsonb;
begin
  if not v_is_service_role
     and not public.crm_has_business_unit_access(
       p_business_unit_id,
       array['admin','manager']::text[]
     ) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;
  if p_action not in ('leave_pending', 'link_opportunity', 'create_opportunity') then
    raise exception 'Invalid reconciliation action' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('crm-reconciliation-case:' || p_case_id::text, 0));
  select reconciliation_case.* into v_case
  from public.crm_ops_reconciliation_cases reconciliation_case
  where reconciliation_case.id = p_case_id
    and reconciliation_case.business_unit_id = p_business_unit_id
  for update;
  if not found then
    raise exception 'Reconciliation case not found in business unit'
      using errcode = 'P0002';
  end if;

  select link.* into v_existing_link
  from public.crm_opportunity_quotations link
  where link.business_unit_id = p_business_unit_id
    and link.quotation_id = v_case.quotation_id
  limit 1
  for update;

  if p_action = 'leave_pending' then
    if found then
      raise exception 'Linked quotation cannot be left pending'
        using errcode = '23505';
    end if;
    update public.crm_ops_reconciliation_cases
    set status = 'ignored',
        resolution = jsonb_build_object(
          'action', 'leave_pending',
          'comment', nullif(btrim(p_comment), ''),
          'review_revision', review_revision
        ),
        resolved_by = v_actor,
        resolved_at = v_now,
        last_seen_at = v_now,
        updated_at = v_now
    where id = p_case_id
    returning * into v_case;
    return jsonb_build_object(
      'case', to_jsonb(v_case),
      'opportunity', null,
      'result', 'requiere_informacion'
    );
  end if;

  if p_account_id is not null and not exists (
    select 1 from public.crm_accounts account
    where account.id = p_account_id
      and account.business_unit_id = p_business_unit_id
  ) then
    raise exception 'Account not found in business unit' using errcode = '23503';
  end if;

  if p_action = 'link_opportunity' then
    if p_opportunity_id is null then
      raise exception 'Opportunity is required' using errcode = '22023';
    end if;
    select opportunity.* into v_opportunity
    from public.crm_opportunities opportunity
    where opportunity.id = p_opportunity_id
      and opportunity.business_unit_id = p_business_unit_id
    for update;
    if not found then
      raise exception 'Opportunity not found in business unit' using errcode = '23503';
    end if;
    if v_existing_link.id is not null
       and v_existing_link.opportunity_id <> v_opportunity.id then
      raise exception 'Quotation is already linked to another opportunity'
        using errcode = '23505';
    end if;
  else
    if v_existing_link.id is not null then
      select opportunity.* into v_opportunity
      from public.crm_opportunities opportunity
      where opportunity.id = v_existing_link.opportunity_id
        and opportunity.business_unit_id = p_business_unit_id
      for update;
    else
      v_conversion_key := 'ops-reconciliation:' || p_case_id::text;
      select opportunity.* into v_opportunity
      from public.crm_opportunities opportunity
      where opportunity.business_unit_id = p_business_unit_id
        and opportunity.conversion_key = v_conversion_key
      limit 1
      for update;
      if not found then
        v_snapshot := coalesce(v_case.snapshot, '{}'::jsonb);
        insert into public.crm_opportunities (
          business_unit_id, account_id, name, commercial_status, stage,
          technical_origin, conversion_key, created_by, updated_by,
          created_at, updated_at, imported_at
        ) values (
          p_business_unit_id,
          p_account_id,
          coalesce(
            nullif(btrim(p_opportunity_name), ''),
            coalesce(nullif(v_snapshot->>'recipient', ''), 'Cliente')
              || ' - '
              || coalesce(nullif(v_snapshot->>'code', ''), 'Cotización')
          ),
          'verification',
          'qualification',
          'ops_quotation',
          v_conversion_key,
          v_actor,
          v_actor,
          v_now,
          v_now,
          v_now
        ) returning * into v_opportunity;
      end if;
    end if;
  end if;

  if v_opportunity.id is null then
    raise exception 'Could not resolve reconciliation opportunity';
  end if;
  if p_account_id is not null then
    if v_opportunity.account_id is not null
       and v_opportunity.account_id <> p_account_id then
      raise exception 'Opportunity belongs to a different account'
        using errcode = '23514';
    elsif v_opportunity.account_id is null then
      update public.crm_opportunities
      set account_id = p_account_id,
          updated_by = v_actor,
          updated_at = v_now
      where id = v_opportunity.id
      returning * into v_opportunity;
    end if;
  end if;
  v_link := public.crm_link_opportunity_quotation(
    p_business_unit_id,
    v_opportunity.id,
    v_case.quotation_id,
    coalesce(nullif(btrim(p_link_type), ''), 'proposal'),
    coalesce(p_is_current, true),
    null,
    null
  );
  select quotation.crm_lead_id into v_lead_id
  from public.ops_quotations quotation
  where quotation.id = v_case.quotation_id
    and quotation.business_unit_id = p_business_unit_id;
  if v_lead_id is not null then
    v_lead_link := public.crm_link_lead_opportunity(
      p_business_unit_id,
      v_lead_id,
      v_opportunity.id,
      null,
      'related',
      false,
      'ops-reconciliation:' || p_case_id::text
    );
  end if;

  if not exists (
    select 1 from public.crm_opportunity_events event
    where event.business_unit_id = p_business_unit_id
      and event.opportunity_id = v_opportunity.id
      and event.event_type = 'quotation_linked'
      and event.source = 'ops_reconciliation'
      and event.payload->>'reconciliation_case_id' = p_case_id::text
  ) then
    insert into public.crm_opportunity_events (
      business_unit_id, opportunity_id, event_type, payload, source,
      occurred_at, created_by
    ) values (
      p_business_unit_id,
      v_opportunity.id,
      'quotation_linked',
      jsonb_build_object(
        'reconciliation_case_id', p_case_id,
        'quotation_id', v_case.quotation_id,
        'link_type', coalesce(nullif(btrim(p_link_type), ''), 'proposal'),
        'is_current', coalesce(p_is_current, true),
        'lead_relation', v_lead_link
      ),
      'ops_reconciliation',
      v_now,
      v_actor
    );
  end if;

  update public.crm_ops_reconciliation_cases
  set status = 'resolved',
      recommended_action = p_action,
      recommended_account_id = coalesce(p_account_id, recommended_account_id),
      recommended_opportunity_id = v_opportunity.id,
      confidence = 1,
      resolution = jsonb_build_object(
        'action', p_action,
        'opportunity_id', v_opportunity.id,
        'quotation_id', v_case.quotation_id,
        'comment', nullif(btrim(p_comment), ''),
        'link', v_link,
        'review_revision', review_revision
      ),
      resolved_by = v_actor,
      resolved_at = v_now,
      last_seen_at = v_now,
      updated_at = v_now
  where id = p_case_id
  returning * into v_case;

  return jsonb_build_object(
    'case', to_jsonb(v_case),
    'opportunity', to_jsonb(v_opportunity),
    'result', 'aplicada'
  );
end;
$$;

drop trigger if exists trg_crm_ops_reconciliation_cases_updated_at
  on public.crm_ops_reconciliation_cases;
create trigger trg_crm_ops_reconciliation_cases_updated_at
before update on public.crm_ops_reconciliation_cases
for each row execute procedure public.crm_set_updated_at();

alter table public.crm_ops_reconciliation_runs enable row level security;
alter table public.crm_ops_reconciliation_cases enable row level security;
alter table public.crm_ops_reconciliation_run_cases enable row level security;

drop policy if exists crm_ops_reconciliation_runs_select on public.crm_ops_reconciliation_runs;
create policy crm_ops_reconciliation_runs_select on public.crm_ops_reconciliation_runs
for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_ops_reconciliation_runs_write on public.crm_ops_reconciliation_runs;
create policy crm_ops_reconciliation_runs_write on public.crm_ops_reconciliation_runs
for all to authenticated
using (public.crm_has_business_unit_access(business_unit_id, array['admin','manager']::text[]))
with check (public.crm_has_business_unit_access(business_unit_id, array['admin','manager']::text[]));

drop policy if exists crm_ops_reconciliation_cases_select on public.crm_ops_reconciliation_cases;
create policy crm_ops_reconciliation_cases_select on public.crm_ops_reconciliation_cases
for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_ops_reconciliation_cases_write on public.crm_ops_reconciliation_cases;
create policy crm_ops_reconciliation_cases_write on public.crm_ops_reconciliation_cases
for all to authenticated
using (public.crm_has_business_unit_access(business_unit_id, array['admin','manager']::text[]))
with check (public.crm_has_business_unit_access(business_unit_id, array['admin','manager']::text[]));

drop policy if exists crm_ops_reconciliation_run_cases_select
  on public.crm_ops_reconciliation_run_cases;
create policy crm_ops_reconciliation_run_cases_select
on public.crm_ops_reconciliation_run_cases
for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));

grant select on
  public.crm_ops_reconciliation_runs,
  public.crm_ops_reconciliation_cases,
  public.crm_ops_reconciliation_run_cases
to authenticated;
revoke insert, update, delete on
  public.crm_ops_reconciliation_runs,
  public.crm_ops_reconciliation_cases,
  public.crm_ops_reconciliation_run_cases
from authenticated;

revoke insert, update, delete on public.crm_opportunity_quotations from authenticated;
revoke insert, update, delete on public.crm_lead_opportunities from authenticated;
revoke insert, update, delete on public.crm_opportunity_contacts from authenticated;
-- Bulk import is exposed only through the authenticated OPS backend, which
-- validates module access before invoking this service-role RPC.  Direct
-- PostgREST execution would otherwise bypass table RLS because the legacy
-- function is SECURITY DEFINER.
do $$
begin
  if to_regprocedure('public.ops_bulk_import_quotations(jsonb,uuid,text)') is not null then
    revoke all on function public.ops_bulk_import_quotations(jsonb, uuid, text) from public;
    revoke all on function public.ops_bulk_import_quotations(jsonb, uuid, text) from authenticated;
    grant execute on function public.ops_bulk_import_quotations(jsonb, uuid, text) to service_role;
  end if;
end;
$$;
revoke all on function public.crm_link_opportunity_quotation(uuid, uuid, uuid, text, boolean, timestamptz, text) from public;
revoke all on function public.crm_unlink_opportunity_quotation(uuid, uuid, uuid) from public;
revoke all on function public.crm_link_lead_opportunity(uuid, uuid, uuid, uuid, text, boolean, text) from public;
revoke all on function public.crm_link_opportunity_contact(uuid, uuid, uuid, text, boolean) from public;
revoke all on function public.crm_unlink_opportunity_contact(uuid, uuid, uuid) from public;
revoke all on function public.crm_finalize_lead_conversion(uuid, uuid, uuid, uuid, uuid, text) from public;
revoke all on function public.crm_commit_ops_reconciliation_run(uuid, boolean, jsonb, jsonb) from public;
revoke all on function public.crm_resolve_ops_reconciliation_case(uuid, uuid, text, uuid, uuid, text, text, boolean, text) from public;
grant execute on function public.crm_link_opportunity_quotation(uuid, uuid, uuid, text, boolean, timestamptz, text)
  to authenticated, service_role;
grant execute on function public.crm_unlink_opportunity_quotation(uuid, uuid, uuid)
  to authenticated, service_role;
grant execute on function public.crm_link_lead_opportunity(uuid, uuid, uuid, uuid, text, boolean, text)
  to authenticated, service_role;
grant execute on function public.crm_link_opportunity_contact(uuid, uuid, uuid, text, boolean)
  to authenticated, service_role;
grant execute on function public.crm_unlink_opportunity_contact(uuid, uuid, uuid)
  to authenticated, service_role;
grant execute on function public.crm_finalize_lead_conversion(uuid, uuid, uuid, uuid, uuid, text)
  to authenticated, service_role;
grant execute on function public.crm_commit_ops_reconciliation_run(uuid, boolean, jsonb, jsonb)
  to authenticated, service_role;
grant execute on function public.crm_resolve_ops_reconciliation_case(uuid, uuid, text, uuid, uuid, text, text, boolean, text)
  to authenticated, service_role;

-- Internal trigger functions are intentionally unavailable as PostgREST RPCs.
revoke all on function public.crm_capture_ops_reconciliation_run_case() from public;
revoke all on function public.crm_guard_ops_reconciliation_run_case() from public;
revoke all on function public.crm_queue_ops_quotation_reconciliation() from public;
revoke all on function public.crm_refresh_reconciliation_link_status() from public;

notify pgrst, 'reload schema';

commit;
