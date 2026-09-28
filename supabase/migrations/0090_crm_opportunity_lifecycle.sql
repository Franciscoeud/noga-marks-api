-- Sales CRM: explicit opportunity lifecycle, document links and immutable history.
begin;

-- A transaction-local marker allows this migration to normalize legacy rows
-- even when it is rerun after the lifecycle guard already exists.
select set_config('app.crm_lifecycle_transition', 'true', true);

create extension if not exists "pgcrypto";

create table if not exists public.crm_opportunity_stages (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  code text not null,
  label text not null,
  sort_order integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_stages_code_check
    check (code in ('qualification', 'proposal', 'customer_evaluation', 'negotiation', 'pending_approval')),
  constraint crm_opportunity_stages_label_check check (nullif(btrim(label), '') is not null),
  constraint uq_crm_opportunity_stage unique (business_unit_id, code)
);

create table if not exists public.crm_opportunity_reasons (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  reason_type text not null,
  code text not null,
  label text not null,
  requires_comment boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_reasons_type_check
    check (reason_type in ('win', 'loss', 'pause', 'reopen', 'correction')),
  constraint crm_opportunity_reasons_text_check
    check (nullif(btrim(code), '') is not null and nullif(btrim(label), '') is not null),
  constraint uq_crm_opportunity_reason unique (business_unit_id, reason_type, code)
);

create table if not exists public.crm_commercial_sources (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  code text not null,
  label text not null,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_commercial_sources_text_check
    check (nullif(btrim(code), '') is not null and nullif(btrim(label), '') is not null),
  constraint uq_crm_commercial_source unique (business_unit_id, code)
);

-- These columns also make the migration safe to rerun over an earlier draft
-- of the catalog tables without losing the actor recorded by the API.
alter table public.crm_opportunity_stages
  add column if not exists created_by uuid;
alter table public.crm_opportunity_reasons
  add column if not exists created_by uuid;
alter table public.crm_commercial_sources
  add column if not exists created_by uuid;

insert into public.crm_opportunity_stages (business_unit_id, code, label, sort_order)
select unit.id, seed.code, seed.label, seed.sort_order
from public.crm_business_units unit
cross join (values
  ('qualification', 'Necesidad calificada', 10),
  ('proposal', 'Cotización enviada', 20),
  ('customer_evaluation', 'En evaluación del cliente', 30),
  ('negotiation', 'En negociación', 40),
  ('pending_approval', 'Pendiente de aprobación / OC', 50)
) seed(code, label, sort_order)
on conflict (business_unit_id, code) do update
set label = excluded.label, sort_order = excluded.sort_order;

insert into public.crm_opportunity_reasons (
  business_unit_id, reason_type, code, label, requires_comment, sort_order
)
select unit.id, seed.reason_type, seed.code, seed.label, seed.requires_comment, seed.sort_order
from public.crm_business_units unit
cross join (values
  ('loss', 'price', 'Precio', false, 10),
  ('loss', 'stock', 'Stock', false, 20),
  ('loss', 'delivery_time', 'Plazo de entrega', false, 30),
  ('loss', 'specifications', 'Especificaciones', false, 40),
  ('loss', 'payment_terms', 'Condiciones de pago', false, 50),
  ('loss', 'competition', 'Competencia', false, 60),
  ('loss', 'budget', 'Presupuesto', false, 70),
  ('loss', 'project_cancelled', 'Proyecto postergado o cancelado', false, 80),
  ('loss', 'service', 'Atención', false, 90),
  ('loss', 'reason_unconfirmed', 'Motivo no confirmado', true, 100),
  ('loss', 'other', 'Otro', true, 110),
  ('win', 'price', 'Precio', false, 10),
  ('win', 'availability', 'Stock / disponibilidad', false, 20),
  ('win', 'delivery_time', 'Plazo de entrega', false, 30),
  ('win', 'specifications', 'Especificaciones', false, 40),
  ('win', 'payment_terms', 'Condiciones de pago', false, 50),
  ('win', 'service', 'Atención', false, 60),
  ('win', 'relationship', 'Confianza o relación previa', false, 70),
  ('win', 'other', 'Otro', true, 80),
  ('pause', 'customer_request', 'Solicitud del cliente', false, 10),
  ('pause', 'budget_pending', 'Presupuesto pendiente', false, 20),
  ('pause', 'project_postponed', 'Proyecto postergado', false, 30),
  ('pause', 'internal_approval', 'Aprobación interna', false, 40),
  ('pause', 'other', 'Otro', true, 50),
  ('reopen', 'customer_reactivated', 'Cliente reactivó la negociación', false, 10),
  ('reopen', 'data_correction', 'Corrección de resultado', true, 20),
  ('reopen', 'other', 'Otro', true, 30),
  ('correction', 'data_correction', 'Corrección de datos', true, 10),
  ('correction', 'other', 'Otro', true, 20)
) seed(reason_type, code, label, requires_comment, sort_order)
on conflict (business_unit_id, reason_type, code) do update
set label = excluded.label,
    requires_comment = excluded.requires_comment,
    sort_order = excluded.sort_order;

insert into public.crm_commercial_sources (business_unit_id, code, label, sort_order)
select unit.id, seed.code, seed.label, seed.sort_order
from public.crm_business_units unit
cross join (values
  ('unidentified', 'No identificado', 10),
  ('referral', 'Referido', 20),
  ('prospecting', 'Prospección', 30),
  ('paid_ad', 'Anuncio', 40),
  ('organic_search', 'Búsqueda orgánica', 50),
  ('existing_customer', 'Cliente existente', 60),
  ('event', 'Evento', 70),
  ('other', 'Otro', 80)
) seed(code, label, sort_order)
on conflict (business_unit_id, code) do update
set label = excluded.label, sort_order = excluded.sort_order;

alter table public.crm_accounts
  add column if not exists conversion_key text;
alter table public.crm_contacts
  add column if not exists conversion_key text;

alter table public.crm_opportunities
  add column if not exists commercial_status text not null default 'verification',
  add column if not exists opportunity_type text,
  add column if not exists need_summary text,
  add column if not exists product_categories jsonb not null default '[]'::jsonb,
  add column if not exists budget_amount numeric(14,2),
  add column if not exists budget_currency text,
  add column if not exists budget_status text not null default 'pending',
  add column if not exists expected_purchase_date date,
  add column if not exists estimated_close_date date,
  add column if not exists business_created_at date,
  add column if not exists imported_at timestamptz,
  add column if not exists stage_entered_at timestamptz,
  add column if not exists next_action text,
  add column if not exists next_action_at timestamptz,
  add column if not exists last_effective_contact_at timestamptz,
  add column if not exists last_customer_response_at timestamptz,
  add column if not exists current_proposed_net_amount numeric(14,2),
  add column if not exists current_currency text,
  add column if not exists current_cost_net numeric(14,2),
  add column if not exists current_discount_percent numeric(7,4),
  add column if not exists tax_basis_status text not null default 'unknown',
  add column if not exists technical_origin text,
  add column if not exists commercial_source_id uuid references public.crm_commercial_sources(id) on delete set null,
  add column if not exists channel text,
  add column if not exists primary_campaign_id uuid references public.crm_campaigns(id) on delete set null,
  add column if not exists parent_opportunity_id uuid references public.crm_opportunities(id) on delete set null,
  add column if not exists paused_stage text,
  add column if not exists pause_reason_id uuid references public.crm_opportunity_reasons(id) on delete set null,
  add column if not exists pause_reason_snapshot text,
  add column if not exists pause_comment text,
  add column if not exists reactivation_at timestamptz,
  add column if not exists closed_at timestamptz,
  add column if not exists win_reason_id uuid references public.crm_opportunity_reasons(id) on delete set null,
  add column if not exists loss_reason_id uuid references public.crm_opportunity_reasons(id) on delete set null,
  add column if not exists close_reason_snapshot text,
  add column if not exists closure_comment text,
  add column if not exists competitor_name text,
  add column if not exists accepted_net_amount numeric(14,2),
  add column if not exists accepted_currency text,
  add column if not exists acceptance_evidence_type text,
  add column if not exists acceptance_evidence_reference jsonb,
  add column if not exists evidence_document_id uuid,
  add column if not exists legacy_stage_snapshot text,
  add column if not exists version integer not null default 1,
  add column if not exists updated_by uuid;

alter table public.crm_opportunities
  add column if not exists conversion_key text;

create unique index if not exists uq_crm_accounts_conversion_key
  on public.crm_accounts (business_unit_id, conversion_key)
  where conversion_key is not null;
create unique index if not exists uq_crm_contacts_conversion_key
  on public.crm_contacts (business_unit_id, conversion_key)
  where conversion_key is not null;
create unique index if not exists uq_crm_opportunities_conversion_key
  on public.crm_opportunities (business_unit_id, conversion_key)
  where conversion_key is not null;

-- Keep legacy UI fields available while moving them into unambiguous fields.
update public.crm_opportunities
set opportunity_type = coalesce(opportunity_type, type),
    estimated_close_date = coalesce(estimated_close_date, close_date),
    current_proposed_net_amount = coalesce(current_proposed_net_amount, amount)
where (opportunity_type is null and type is not null)
   or (estimated_close_date is null and close_date is not null)
   or (current_proposed_net_amount is null and amount is not null);

update public.crm_opportunities
set legacy_stage_snapshot = stage
where legacy_stage_snapshot is null;

alter table public.crm_opportunities drop constraint if exists crm_opportunities_stage_check;
update public.crm_opportunities
set stage = case
  when stage in ('needs_analysis', 'prospecting', 'closed', 'closed_won', 'closed_lost') then 'qualification'
  when stage in ('qualification', 'proposal', 'customer_evaluation', 'negotiation', 'pending_approval') then stage
  else 'qualification'
end
where stage is null
   or stage not in ('qualification', 'proposal', 'customer_evaluation', 'negotiation', 'pending_approval');
alter table public.crm_opportunities alter column stage set default 'qualification';
alter table public.crm_opportunities alter column stage_entered_at set default timezone('utc', now());
alter table public.crm_opportunities
  add constraint crm_opportunities_stage_check
  check (stage in ('qualification', 'proposal', 'customer_evaluation', 'negotiation', 'pending_approval'));

alter table public.crm_opportunities drop constraint if exists crm_opportunities_commercial_status_check;
alter table public.crm_opportunities
  add constraint crm_opportunities_commercial_status_check
  check (commercial_status in ('verification', 'open', 'paused', 'won', 'lost'));
alter table public.crm_opportunities drop constraint if exists crm_opportunities_currency_check;
alter table public.crm_opportunities
  add constraint crm_opportunities_currency_check
  check (
    (budget_currency is null or budget_currency ~ '^[A-Z]{3}$')
    and (current_currency is null or current_currency ~ '^[A-Z]{3}$')
    and (accepted_currency is null or accepted_currency ~ '^[A-Z]{3}$')
  );
alter table public.crm_opportunities drop constraint if exists crm_opportunities_amounts_check;
alter table public.crm_opportunities
  add constraint crm_opportunities_amounts_check
  check (
    (budget_amount is null or budget_amount >= 0)
    and (current_proposed_net_amount is null or current_proposed_net_amount >= 0)
    and (current_cost_net is null or current_cost_net >= 0)
    and (accepted_net_amount is null or accepted_net_amount >= 0)
    and (current_discount_percent is null or current_discount_percent between 0 and 100)
  );
alter table public.crm_opportunities drop constraint if exists crm_opportunities_budget_status_check;
alter table public.crm_opportunities
  add constraint crm_opportunities_budget_status_check
  check (budget_status in ('pending', 'known', 'not_applicable'));
alter table public.crm_opportunities drop constraint if exists crm_opportunities_tax_basis_check;
alter table public.crm_opportunities
  add constraint crm_opportunities_tax_basis_check
  check (tax_basis_status in ('confirmed_net', 'needs_review', 'unknown'));
alter table public.crm_opportunities drop constraint if exists crm_opportunities_evidence_type_check;
alter table public.crm_opportunities
  add constraint crm_opportunities_evidence_type_check
  check (
    acceptance_evidence_type is null
    or acceptance_evidence_type in ('customer_po', 'signed_quotation', 'acceptance_file', 'inbound_interaction')
  );

alter table public.crm_leads
  drop constraint if exists crm_leads_commercial_source_fkey;
alter table public.crm_leads
  add constraint crm_leads_commercial_source_fkey
  foreign key (commercial_source_id) references public.crm_commercial_sources(id) on delete set null;
alter table public.crm_leads
  drop constraint if exists crm_leads_primary_campaign_fkey;
alter table public.crm_leads
  add constraint crm_leads_primary_campaign_fkey
  foreign key (primary_campaign_id) references public.crm_campaigns(id) on delete set null;

-- OPS creates the commercial document, not the acquisition channel.  Preserve
-- its technical origin while leaving the commercial source explicitly
-- unidentified and avoiding an invented contact channel.  Historical lead
-- qualification is deliberately not rewritten here.
update public.crm_leads lead
set technical_origin = 'ops_quotation',
    commercial_source_id = coalesce(
      lead.commercial_source_id,
      (
        select source.id
        from public.crm_commercial_sources source
        where source.business_unit_id = lead.business_unit_id
          and source.code = 'unidentified'
        limit 1
      )
    ),
    contact_channel = case
      when lower(coalesce(lead.contact_channel, ''))
        in ('ops quotation', 'ops_quotation', 'ops quotations') then null
      else lead.contact_channel
    end
where lower(coalesce(lead.source_channel, ''))
        in ('ops quotation', 'ops_quotation', 'ops quotations')
   or lead.technical_origin = 'ops_quotation';

create or replace function public.crm_normalize_ops_lead_context()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if lower(coalesce(new.source_channel, ''))
       in ('ops quotation', 'ops_quotation', 'ops quotations')
     or new.technical_origin = 'ops_quotation' then
    new.technical_origin := 'ops_quotation';
    -- A proforma is documentary evidence of interest, not evidence that the
    -- lead was qualified or that the proposal was sent.  Protect every insert,
    -- including service-role imports, from inheriting the legacy defaults.
    if tg_op = 'INSERT' then
      new.lead_status := 'new';
      new.status := 'nuevo';
      new.pipeline_stage := 'Nuevo';
      new.temperature := 'frio';
    end if;
    if lower(coalesce(new.contact_channel, ''))
         in ('ops quotation', 'ops_quotation', 'ops quotations') then
      new.contact_channel := null;
    end if;
    if new.commercial_source_id is null and new.business_unit_id is not null then
      select source.id
      into new.commercial_source_id
      from public.crm_commercial_sources source
      where source.business_unit_id = new.business_unit_id
        and source.code = 'unidentified'
      limit 1;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_crm_leads_normalize_ops_origin on public.crm_leads;
create trigger trg_crm_leads_normalize_ops_origin
before insert or update of source_channel, technical_origin, business_unit_id
on public.crm_leads
for each row execute procedure public.crm_normalize_ops_lead_context();

-- Activity endpoints keep the legacy columns while adding precise actor and
-- occurrence timestamps.  The check is widened to the vocabulary exposed by
-- the Sales API.
alter table public.crm_activities
  add column if not exists created_by_user_id uuid,
  add column if not exists occurred_at timestamptz;
alter table public.crm_activities
  drop constraint if exists crm_activities_activity_type_check;
alter table public.crm_activities
  add constraint crm_activities_activity_type_check
  check (activity_type in ('email', 'event', 'call', 'task', 'meeting', 'note'));

alter table public.crm_activity_tasks
  add column if not exists assigned_to_user_id uuid,
  add column if not exists created_by uuid;

create table if not exists public.crm_lead_opportunities (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  lead_id uuid not null references public.crm_leads(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  contact_id uuid references public.crm_contacts(id) on delete set null,
  relationship_type text not null default 'related',
  is_primary boolean not null default false,
  idempotency_key text,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_lead_opportunities_type_check
    check (relationship_type in ('originated', 'converted', 'related', 'influenced')),
  constraint uq_crm_lead_opportunity unique (lead_id, opportunity_id)
);
create unique index if not exists uq_crm_lead_opportunity_primary
  on public.crm_lead_opportunities (lead_id)
  where is_primary;
create unique index if not exists uq_crm_lead_opportunity_idempotency
  on public.crm_lead_opportunities (business_unit_id, lead_id, idempotency_key)
  where idempotency_key is not null;

alter table public.crm_opportunity_contacts
  add column if not exists is_primary boolean not null default false;
create unique index if not exists uq_crm_opportunity_primary_contact
  on public.crm_opportunity_contacts (opportunity_id)
  where is_primary;

create table if not exists public.crm_opportunity_quotations (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  quotation_id uuid not null references public.ops_quotations(id) on delete restrict,
  link_type text not null default 'proposal',
  is_current boolean not null default false,
  sent_at timestamptz,
  sent_channel text,
  sent_by uuid,
  notes text,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_quotations_type_check
    check (link_type in ('proposal', 'revision', 'alternative', 'replaced')),
  constraint crm_opportunity_quotations_sent_check
    check ((sent_at is null and sent_channel is null) or (sent_at is not null and nullif(btrim(sent_channel), '') is not null)),
  constraint uq_crm_opportunity_quotation unique (quotation_id),
  constraint uq_crm_opportunity_quotation_pair unique (opportunity_id, quotation_id)
);
create unique index if not exists uq_crm_opportunity_current_quotation
  on public.crm_opportunity_quotations (opportunity_id)
  where is_current;

create table if not exists public.crm_opportunity_orders (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  order_id uuid not null references public.ops_orders(id) on delete restrict,
  relationship_type text not null default 'customer_fulfilment',
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_orders_type_check
    check (relationship_type = 'customer_fulfilment'),
  constraint uq_crm_opportunity_order unique (order_id),
  constraint uq_crm_opportunity_order_pair unique (opportunity_id, order_id)
);

create table if not exists public.crm_opportunity_campaigns (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  campaign_id uuid not null references public.crm_campaigns(id) on delete cascade,
  attribution_type text not null default 'influenced',
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_campaigns_attribution_check
    check (attribution_type in ('primary', 'influenced')),
  constraint uq_crm_opportunity_campaign unique (opportunity_id, campaign_id)
);
create unique index if not exists uq_crm_opportunity_primary_campaign
  on public.crm_opportunity_campaigns (opportunity_id)
  where attribution_type = 'primary';

-- The opportunity is the source of truth for primary attribution.  Keeping
-- this work in an AFTER trigger makes the opportunity update and its campaign
-- link one transaction, while writes to the child table do not recurse into
-- the opportunity.
create or replace function public.crm_sync_opportunity_primary_campaign()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.primary_campaign_id is not null and not exists (
    select 1
    from public.crm_campaigns campaign
    where campaign.id = new.primary_campaign_id
      and campaign.business_unit_id = new.business_unit_id
  ) then
    raise exception 'Opportunity campaign belongs to another business unit'
      using errcode = '23514';
  end if;

  delete from public.crm_opportunity_campaigns link
  where link.opportunity_id = new.id
    and link.attribution_type = 'primary'
    and (
      new.primary_campaign_id is null
      or link.campaign_id <> new.primary_campaign_id
      or link.business_unit_id <> new.business_unit_id
    );

  if new.primary_campaign_id is not null then
    insert into public.crm_opportunity_campaigns (
      business_unit_id,
      opportunity_id,
      campaign_id,
      attribution_type,
      created_by
    ) values (
      new.business_unit_id,
      new.id,
      new.primary_campaign_id,
      'primary',
      coalesce(new.updated_by, new.created_by)
    )
    on conflict (opportunity_id, campaign_id) do update
    set business_unit_id = excluded.business_unit_id,
        attribution_type = 'primary',
        created_by = coalesce(crm_opportunity_campaigns.created_by, excluded.created_by);
  end if;

  return new;
end;
$$;

-- A replay also repairs links created before this trigger existed.  Invalid
-- cross-company references are rejected instead of being silently copied.
do $$
begin
  if exists (
    select 1
    from public.crm_opportunities opportunity
    left join public.crm_campaigns campaign
      on campaign.id = opportunity.primary_campaign_id
    where opportunity.primary_campaign_id is not null
      and (
        campaign.id is null
        or campaign.business_unit_id <> opportunity.business_unit_id
      )
  ) then
    raise exception 'Existing opportunity campaign belongs to another business unit'
      using errcode = '23514';
  end if;
end $$;

delete from public.crm_opportunity_campaigns link
using public.crm_opportunities opportunity
where link.opportunity_id = opportunity.id
  and link.attribution_type = 'primary'
  and (
    opportunity.primary_campaign_id is null
    or link.campaign_id <> opportunity.primary_campaign_id
    or link.business_unit_id <> opportunity.business_unit_id
  );

insert into public.crm_opportunity_campaigns (
  business_unit_id,
  opportunity_id,
  campaign_id,
  attribution_type,
  created_by
)
select
  opportunity.business_unit_id,
  opportunity.id,
  opportunity.primary_campaign_id,
  'primary',
  coalesce(opportunity.updated_by, opportunity.created_by)
from public.crm_opportunities opportunity
where opportunity.primary_campaign_id is not null
on conflict (opportunity_id, campaign_id) do update
set business_unit_id = excluded.business_unit_id,
    attribution_type = 'primary',
    created_by = coalesce(crm_opportunity_campaigns.created_by, excluded.created_by);

drop trigger if exists trg_crm_opportunities_sync_primary_campaign
  on public.crm_opportunities;
create trigger trg_crm_opportunities_sync_primary_campaign
after insert or update of primary_campaign_id, business_unit_id
on public.crm_opportunities
for each row
execute procedure public.crm_sync_opportunity_primary_campaign();

revoke all on function public.crm_sync_opportunity_primary_campaign() from public;

-- Child writes may add influenced campaigns, but the primary row can only
-- mirror crm_opportunities.primary_campaign_id.  This also protects direct
-- PostgREST access from creating a divergent primary attribution.
create or replace function public.crm_guard_primary_campaign_link()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_opportunity public.crm_opportunities%rowtype;
begin
  if tg_op = 'DELETE' then
    if old.attribution_type <> 'primary' then
      return old;
    end if;
    select * into v_opportunity
    from public.crm_opportunities opportunity
    where opportunity.id = old.opportunity_id;
    if found and v_opportunity.primary_campaign_id = old.campaign_id then
      raise exception 'Primary campaign must be changed through the opportunity'
        using errcode = '23514';
    end if;
    return old;
  end if;

  if new.attribution_type = 'primary' then
    select * into v_opportunity
    from public.crm_opportunities opportunity
    where opportunity.id = new.opportunity_id
      and opportunity.business_unit_id = new.business_unit_id;
    if not found or v_opportunity.primary_campaign_id is distinct from new.campaign_id then
      raise exception 'Primary campaign link does not match the opportunity'
        using errcode = '23514';
    end if;
  end if;

  if tg_op = 'UPDATE'
     and old.attribution_type = 'primary'
     and new.attribution_type <> 'primary' then
    select * into v_opportunity
    from public.crm_opportunities opportunity
    where opportunity.id = old.opportunity_id;
    if found and v_opportunity.primary_campaign_id = old.campaign_id then
      raise exception 'Primary campaign must be changed through the opportunity'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_crm_opportunity_campaigns_guard_primary
  on public.crm_opportunity_campaigns;
create trigger trg_crm_opportunity_campaigns_guard_primary
before insert or update or delete
on public.crm_opportunity_campaigns
for each row
execute procedure public.crm_guard_primary_campaign_link();

revoke all on function public.crm_guard_primary_campaign_link() from public;

create table if not exists public.crm_opportunity_events (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  event_type text not null,
  payload jsonb not null default '{}'::jsonb,
  old_values jsonb not null default '{}'::jsonb,
  new_values jsonb not null default '{}'::jsonb,
  reason text,
  source text not null default 'sales',
  original_occurred_at timestamptz,
  occurred_at timestamptz not null default timezone('utc', now()),
  imported_at timestamptz,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_events_type_check
    check (nullif(btrim(event_type), '') is not null)
);
create index if not exists idx_crm_opportunity_events_timeline
  on public.crm_opportunity_events (opportunity_id, coalesce(original_occurred_at, occurred_at, created_at) desc);

create table if not exists public.crm_opportunity_documents (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  document_type text not null,
  storage_path text not null,
  filename text not null,
  mime_type text not null,
  size_bytes bigint,
  acceptance_eligible boolean not null default false,
  notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_documents_type_check
    check (document_type in (
      'customer_purchase_order','signed_quotation','acceptance_file',
      'inbound_acceptance','other'
    )),
  constraint crm_opportunity_documents_mime_check
    check (mime_type in ('application/pdf','image/jpeg','image/png','image/webp')),
  constraint crm_opportunity_documents_size_check
    check (size_bytes is null or size_bytes between 1 and 20971520),
  constraint crm_opportunity_documents_path_check
    check (nullif(btrim(storage_path), '') is not null and nullif(btrim(filename), '') is not null),
  constraint uq_crm_opportunity_document_path unique (storage_path)
);

alter table public.crm_opportunities
  drop constraint if exists crm_opportunities_evidence_document_fkey;
alter table public.crm_opportunities
  add constraint crm_opportunities_evidence_document_fkey
  foreign key (evidence_document_id) references public.crm_opportunity_documents(id) on delete set null;

create table if not exists public.crm_opportunity_outcomes (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  outcome_version integer not null default 1,
  status text not null,
  closed_at timestamptz,
  reason_id uuid references public.crm_opportunity_reasons(id) on delete restrict,
  reason_snapshot text,
  comment text,
  competitor_name text,
  accepted_net_amount numeric(14,2),
  currency text,
  evidence_document_id uuid references public.crm_opportunity_documents(id) on delete restrict,
  evidence_type text,
  evidence_reference jsonb,
  is_partial boolean not null default false,
  remainder_disposition text,
  remainder_child_opportunity_id uuid references public.crm_opportunities(id) on delete set null,
  supersedes_outcome_id uuid references public.crm_opportunity_outcomes(id) on delete set null,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_outcomes_status_check
    check (status in ('won', 'lost', 'reopened', 'won_correction', 'lost_correction')),
  constraint crm_opportunity_outcomes_version_check check (outcome_version > 0),
  constraint crm_opportunity_outcomes_currency_check check (currency is null or currency ~ '^[A-Z]{3}$'),
  constraint crm_opportunity_outcomes_amount_check check (accepted_net_amount is null or accepted_net_amount >= 0),
  constraint crm_opportunity_outcomes_evidence_type_check check (
    evidence_type is null
    or evidence_type in ('customer_po', 'signed_quotation', 'acceptance_file', 'inbound_interaction')
  ),
  constraint crm_opportunity_outcomes_required_fields_check check (
    (status not in ('won', 'won_correction') or (
      closed_at is not null
      and reason_id is not null
      and accepted_net_amount > 0
      and currency is not null
      and (
        (evidence_type = 'inbound_interaction' and evidence_reference is not null and evidence_reference <> '{}'::jsonb)
        or (evidence_type <> 'inbound_interaction' and evidence_document_id is not null)
      )
    ))
    and (status not in ('lost', 'lost_correction') or (
      closed_at is not null and reason_id is not null and nullif(btrim(comment), '') is not null
    ))
    and (status <> 'reopened' or nullif(btrim(comment), '') is not null)
  ),
  constraint crm_opportunity_outcomes_partial_check check (
    not is_partial
    or remainder_disposition in ('closed', 'lost', 'open', 'paused')
  ),
  constraint uq_crm_opportunity_outcome_version unique (opportunity_id, outcome_version)
);

create table if not exists public.crm_opportunity_accepted_items (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  outcome_id uuid not null references public.crm_opportunity_outcomes(id) on delete cascade,
  quotation_item_id uuid references public.ops_quotation_items(id) on delete restrict,
  code text,
  description text not null,
  quantity numeric(12,2) not null,
  accepted_unit_net numeric(14,2) not null,
  accepted_total_net numeric(14,2) not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_accepted_items_values_check check (
    nullif(btrim(description), '') is not null
    and quantity > 0
    and accepted_unit_net >= 0
    and accepted_total_net >= 0
  ),
  constraint uq_crm_opportunity_accepted_quote_item unique (outcome_id, quotation_item_id)
);

create or replace function public.crm_prepare_opportunity_outcome()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_previous_id uuid;
  v_next_version integer;
begin
  -- Serialize outcome versions per opportunity so corrections/reopens remain
  -- append-only even when two requests arrive at nearly the same time.
  perform pg_advisory_xact_lock(hashtextextended(new.opportunity_id::text, 0));
  select id, outcome_version
  into v_previous_id, v_next_version
  from public.crm_opportunity_outcomes
  where opportunity_id = new.opportunity_id
  order by outcome_version desc
  limit 1;

  new.outcome_version := coalesce(v_next_version, 0) + 1;
  if new.supersedes_outcome_id is null then
    new.supersedes_outcome_id := v_previous_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_crm_opportunity_outcomes_prepare
  on public.crm_opportunity_outcomes;
create trigger trg_crm_opportunity_outcomes_prepare
before insert on public.crm_opportunity_outcomes
for each row execute procedure public.crm_prepare_opportunity_outcome();

create table if not exists public.crm_opportunity_financial_events (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  event_type text not null,
  event_date date not null,
  amount numeric(14,2),
  currency text,
  reference text,
  document_id uuid references public.crm_opportunity_documents(id) on delete set null,
  notes text,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_financial_events_type_check
    check (event_type in ('invoiced', 'partially_invoiced', 'paid', 'partially_paid', 'cancelled')),
  constraint crm_opportunity_financial_events_value_check
    check ((amount is null or amount >= 0) and (currency is null or currency ~ '^[A-Z]{3}$'))
);

create table if not exists public.crm_saved_views (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  entity_type text not null,
  code text not null,
  name text not null,
  filters_json jsonb not null default '{}'::jsonb,
  columns_json jsonb not null default '[]'::jsonb,
  visibility text not null default 'private',
  is_default boolean not null default false,
  created_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_saved_views_entity_check
    check (entity_type in ('opportunities', 'leads', 'reconciliation', 'follow_ups', 'reporting')),
  constraint crm_saved_views_visibility_check check (visibility in ('private', 'company')),
  constraint crm_saved_views_code_check check (nullif(btrim(code), '') is not null)
);
create unique index if not exists uq_crm_saved_views_owner_name
  on public.crm_saved_views (business_unit_id, coalesce(user_id::text, '*'), entity_type, lower(name));
create unique index if not exists uq_crm_saved_views_owner_code
  on public.crm_saved_views (business_unit_id, coalesce(user_id::text, '*'), entity_type, lower(code));

insert into public.crm_saved_views (
  business_unit_id, user_id, entity_type, code, name, filters_json, columns_json,
  visibility, is_default, created_by
)
select
  unit.id,
  membership.user_id,
  'opportunities',
  'cdm_ops_quotations',
  'CDM · Cotizaciones OPS',
  '{"technical_origin":"ops_quotation"}'::jsonb,
  '["name","account","commercial_status","stage","current_proposed_net_amount","current_currency","owner","next_action_at"]'::jsonb,
  'private',
  false,
  membership.user_id
from public.crm_business_units unit
join public.crm_business_unit_memberships membership
  on membership.business_unit_id = unit.id and membership.active
where unit.code = 'cdm'
  and exists (
    select 1 from public.app_user_modules module_access
    where module_access.user_id = membership.user_id
      and lower(module_access.module_key) = 'sales'
  )
on conflict do nothing;

-- Validate that explicit relation keys never cross companies.
create or replace function public.crm_valid_inbound_acceptance(
  p_business_unit_id uuid,
  p_opportunity_id uuid,
  p_reference jsonb
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p_reference is not null
    and p_reference->>'source' = 'inbound'
    and public.crm_try_uuid(p_reference->>'event_id') is not null
    and case coalesce(nullif(p_reference->>'type', ''), 'lead_event')
      when 'conversation_message' then exists (
        select 1
        from public.crm_conversation_messages message
        join public.crm_lead_opportunities lead_link
          on lead_link.lead_id = message.lead_id
         and lead_link.opportunity_id = p_opportunity_id
         and lead_link.business_unit_id = p_business_unit_id
        where message.id = public.crm_try_uuid(p_reference->>'event_id')
          and message.business_unit_id = p_business_unit_id
          and message.direction = 'inbound'
      )
      when 'lead_event' then exists (
        select 1
        from public.crm_lead_events event
        join public.crm_lead_opportunities lead_link
          on lead_link.lead_id = event.lead_id
         and lead_link.opportunity_id = p_opportunity_id
         and lead_link.business_unit_id = p_business_unit_id
        where event.id = public.crm_try_uuid(p_reference->>'event_id')
          and event.business_unit_id = p_business_unit_id
      )
      else false
    end;
$$;

create or replace function public.crm_validate_business_unit_relationship()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Keep field access inside the matching table branch.  A trigger RECORD does
  -- not expose another table's fields even inside a false boolean expression.
  if tg_table_name = 'crm_accounts' then
    if new.parent_account_id is not null and not exists (
      select 1 from public.crm_accounts parent
      where parent.id = new.parent_account_id
        and parent.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Parent account belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_leads' then
    if new.account_id is not null and not exists (
      select 1 from public.crm_accounts account
      where account.id = new.account_id
        and account.business_unit_id = new.business_unit_id
        and not account.is_archived
    ) then
      raise exception 'Lead account belongs to another business unit';
    end if;
    if new.commercial_source_id is not null and not exists (
      select 1 from public.crm_commercial_sources source
      where source.id = new.commercial_source_id
        and source.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Lead commercial source belongs to another business unit';
    end if;
    if new.primary_campaign_id is not null and not exists (
      select 1 from public.crm_campaigns campaign
      where campaign.id = new.primary_campaign_id
        and campaign.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Lead campaign belongs to another business unit';
    end if;
    if new.product_interest_id is not null and not exists (
      select 1 from public.crm_product_interests interest
      where interest.id = new.product_interest_id
        and interest.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Lead product interest belongs to another business unit';
    end if;
    if new.program_id is not null and not exists (
      select 1 from public.crm_programs program
      where program.id = new.program_id
        and program.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Lead program belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_campaigns' then
    if new.parent_campaign_id is not null and not exists (
      select 1 from public.crm_campaigns parent
      where parent.id = new.parent_campaign_id
        and parent.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Parent campaign belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_contacts' then
    if new.account_id is not null and not exists (
      select 1 from public.crm_accounts account
      where account.id = new.account_id
        and account.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Account belongs to another business unit';
    end if;
    if tg_op = 'UPDATE'
       and new.account_id is distinct from old.account_id
       and exists (
         select 1
         from public.crm_opportunity_contacts relation
         join public.crm_opportunities opportunity on opportunity.id = relation.opportunity_id
         where relation.contact_id = new.id
           and opportunity.account_id is not null
           and new.account_id is distinct from opportunity.account_id
       ) then
      raise exception 'Contact account conflicts with a linked opportunity';
    end if;
  elsif tg_table_name = 'crm_opportunities' then
    if new.account_id is not null and not exists (
      select 1 from public.crm_accounts account
      where account.id = new.account_id
        and account.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Account belongs to another business unit';
    end if;
    if new.parent_opportunity_id is not null and not exists (
      select 1 from public.crm_opportunities parent
      where parent.id = new.parent_opportunity_id
        and parent.business_unit_id = new.business_unit_id
        and parent.account_id is not distinct from new.account_id
    ) then
      raise exception 'Parent opportunity belongs to another account or business unit';
    end if;
    if new.commercial_source_id is not null and not exists (
      select 1 from public.crm_commercial_sources source
      where source.id = new.commercial_source_id
        and source.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity source belongs to another business unit';
    end if;
    if new.primary_campaign_id is not null and not exists (
      select 1 from public.crm_campaigns campaign
      where campaign.id = new.primary_campaign_id
        and campaign.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity campaign belongs to another business unit';
    end if;
    if tg_op = 'UPDATE'
       and new.account_id is distinct from old.account_id
       and exists (
         select 1
         from public.crm_opportunity_contacts relation
         join public.crm_contacts contact on contact.id = relation.contact_id
         where relation.opportunity_id = new.id
           and contact.account_id is not null
           and new.account_id is distinct from contact.account_id
       ) then
      raise exception 'Opportunity account conflicts with a linked contact';
    end if;
  elsif tg_table_name = 'crm_lead_opportunities' then
    if not exists (
      select 1 from public.crm_leads lead
      where lead.id = new.lead_id and lead.business_unit_id = new.business_unit_id
    ) or not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Lead or opportunity belongs to another business unit';
    end if;
    if new.contact_id is not null and not exists (
      select 1 from public.crm_contacts contact
      where contact.id = new.contact_id
        and contact.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Converted contact belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_opportunity_contacts' then
    if not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) or not exists (
      select 1 from public.crm_contacts contact
      where contact.id = new.contact_id and contact.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity or contact belongs to another business unit';
    end if;
    if exists (
      select 1
      from public.crm_opportunities opportunity
      join public.crm_contacts contact on contact.id = new.contact_id
      where opportunity.id = new.opportunity_id
        and opportunity.account_id is not null
        and contact.account_id is not null
        and opportunity.account_id <> contact.account_id
    ) then
      raise exception 'Opportunity and contact belong to different accounts';
    end if;
  elsif tg_table_name = 'crm_opportunity_quotations' then
    if not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) or not exists (
      select 1 from public.ops_quotations quotation
      where quotation.id = new.quotation_id
        and quotation.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity or quotation belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_opportunity_orders' then
    if not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) or not exists (
      select 1 from public.ops_orders customer_order
      where customer_order.id = new.order_id
        and customer_order.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity or customer order belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_opportunity_campaigns' then
    if not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) or not exists (
      select 1 from public.crm_campaigns campaign
      where campaign.id = new.campaign_id
        and campaign.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity or campaign belongs to another business unit';
    end if;
  elsif tg_table_name in ('crm_opportunity_events', 'crm_opportunity_documents') then
    if not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_opportunity_outcomes' then
    if not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity belongs to another business unit';
    end if;
    if new.reason_id is not null and not exists (
      select 1 from public.crm_opportunity_reasons reason
      where reason.id = new.reason_id
        and reason.business_unit_id = new.business_unit_id
        and reason.active
        and reason.reason_type = case
          when new.status in ('won', 'won_correction') then 'win'
          when new.status in ('lost', 'lost_correction') then 'loss'
          else reason.reason_type
        end
    ) then
      raise exception 'Outcome reason belongs to another business unit or type';
    end if;
    if new.evidence_document_id is not null and not exists (
      select 1 from public.crm_opportunity_documents document
      where document.id = new.evidence_document_id
        and document.business_unit_id = new.business_unit_id
        and document.opportunity_id = new.opportunity_id
        and document.acceptance_eligible
    ) then
      raise exception 'Outcome evidence does not belong to this opportunity';
    end if;
    if new.evidence_type = 'inbound_interaction'
       and not public.crm_valid_inbound_acceptance(
         new.business_unit_id, new.opportunity_id, new.evidence_reference
       ) then
      raise exception 'Inbound acceptance is not linked to this opportunity';
    end if;
    if new.remainder_child_opportunity_id is not null and not exists (
      select 1 from public.crm_opportunities child
      where child.id = new.remainder_child_opportunity_id
        and child.business_unit_id = new.business_unit_id
        and child.parent_opportunity_id = new.opportunity_id
    ) then
      raise exception 'Remainder opportunity is not a child of this opportunity';
    end if;
  elsif tg_table_name = 'crm_opportunity_accepted_items' then
    if not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) or not exists (
      select 1 from public.crm_opportunity_outcomes outcome
      where outcome.id = new.outcome_id
        and outcome.business_unit_id = new.business_unit_id
        and outcome.opportunity_id = new.opportunity_id
    ) then
      raise exception 'Accepted item outcome belongs to another opportunity';
    end if;
    if new.quotation_item_id is not null and not exists (
      select 1
      from public.ops_quotation_items quotation_item
      join public.crm_opportunity_quotations quotation_link
        on quotation_link.quotation_id = quotation_item.quotation_id
       and quotation_link.opportunity_id = new.opportunity_id
       and quotation_link.business_unit_id = new.business_unit_id
      where quotation_item.id = new.quotation_item_id
    ) then
      raise exception 'Accepted item is not from a linked quotation';
    end if;
  elsif tg_table_name = 'crm_opportunity_financial_events' then
    if not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Opportunity belongs to another business unit';
    end if;
    if new.document_id is not null and not exists (
          select 1 from public.crm_opportunity_documents document
          where document.id = new.document_id
            and document.business_unit_id = new.business_unit_id
            and document.opportunity_id = new.opportunity_id
        ) then
      raise exception 'Financial document does not belong to this opportunity';
    end if;
  elsif tg_table_name = 'crm_activities' then
    if new.opportunity_id is not null and not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Activity opportunity belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_activity_log' then
    if new.account_id is not null and not exists (
      select 1 from public.crm_accounts account
      where account.id = new.account_id
        and account.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Activity account belongs to another business unit';
    end if;
    if new.contact_id is not null and not exists (
      select 1 from public.crm_contacts contact
      where contact.id = new.contact_id
        and contact.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Activity contact belongs to another business unit';
    end if;
    if new.opportunity_id is not null and not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Activity opportunity belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_campaign_members' then
    if new.campaign_id is not null and not exists (
      select 1 from public.crm_campaigns campaign
      where campaign.id = new.campaign_id
        and campaign.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Campaign belongs to another business unit';
    end if;
    if new.contact_id is not null and not exists (
      select 1 from public.crm_contacts contact
      where contact.id = new.contact_id
        and contact.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Campaign contact belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_conversations' then
    if new.lead_id is not null and not exists (
      select 1 from public.crm_leads lead
      where lead.id = new.lead_id
        and lead.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Conversation lead belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_conversation_messages' then
    if new.conversation_id is not null and not exists (
      select 1 from public.crm_conversations conversation
      where conversation.id = new.conversation_id
        and conversation.business_unit_id = new.business_unit_id
        and (new.lead_id is null or conversation.lead_id = new.lead_id)
    ) then
      raise exception 'Message conversation belongs to another business unit or lead';
    end if;
    if new.lead_id is not null and not exists (
      select 1 from public.crm_leads lead
      where lead.id = new.lead_id
        and lead.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Message lead belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_email_messages' then
    if new.account_id is not null and not exists (
      select 1 from public.crm_accounts account
      where account.id = new.account_id
        and account.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Email account belongs to another business unit';
    end if;
    if new.contact_id is not null and not exists (
      select 1 from public.crm_contacts contact
      where contact.id = new.contact_id
        and contact.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Email contact belongs to another business unit';
    end if;
    if new.opportunity_id is not null and not exists (
      select 1 from public.crm_opportunities opportunity
      where opportunity.id = new.opportunity_id
        and opportunity.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Email opportunity belongs to another business unit';
    end if;
    if new.lead_id is not null and not exists (
      select 1 from public.crm_leads lead
      where lead.id = new.lead_id
        and lead.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Email lead belongs to another business unit';
    end if;
  elsif tg_table_name in ('crm_message_templates', 'crm_assignment_rules', 'crm_source_routes') then
    if new.account_id is not null and not exists (
      select 1 from public.crm_accounts account
      where account.id = new.account_id
        and account.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Configuration account belongs to another business unit';
    end if;
    if new.product_interest_id is not null and not exists (
      select 1 from public.crm_product_interests interest
      where interest.id = new.product_interest_id
        and interest.business_unit_id = new.business_unit_id
    ) then
      raise exception 'Configuration product interest belongs to another business unit';
    end if;
  elsif tg_table_name = 'crm_whatsapp_templates' then
    if new.program_id is not null and not exists (
      select 1 from public.crm_programs program
      where program.id = new.program_id
        and program.business_unit_id = new.business_unit_id
    ) then
      raise exception 'WhatsApp template program belongs to another business unit';
    end if;
  end if;
  return new;
end;
$$;

do $$
declare
  table_name text;
  watched_columns text;
begin
  for table_name, watched_columns in
    select * from (values
      ('crm_accounts', 'parent_account_id, business_unit_id'),
      ('crm_leads', 'account_id, commercial_source_id, primary_campaign_id, product_interest_id, program_id, business_unit_id'),
      ('crm_campaigns', 'parent_campaign_id, business_unit_id'),
      ('crm_contacts', 'account_id, business_unit_id'),
      ('crm_opportunities', 'account_id, parent_opportunity_id, commercial_source_id, primary_campaign_id, business_unit_id'),
      ('crm_lead_opportunities', 'lead_id, opportunity_id, contact_id, business_unit_id'),
      ('crm_opportunity_contacts', 'opportunity_id, contact_id, business_unit_id'),
      ('crm_opportunity_quotations', 'opportunity_id, quotation_id, business_unit_id'),
      ('crm_opportunity_orders', 'opportunity_id, order_id, business_unit_id'),
      ('crm_opportunity_campaigns', 'opportunity_id, campaign_id, business_unit_id'),
      ('crm_opportunity_events', 'opportunity_id, business_unit_id'),
      ('crm_opportunity_documents', 'opportunity_id, business_unit_id'),
      ('crm_opportunity_outcomes', 'opportunity_id, reason_id, evidence_document_id, evidence_type, evidence_reference, remainder_child_opportunity_id, status, business_unit_id'),
      ('crm_opportunity_accepted_items', 'opportunity_id, outcome_id, quotation_item_id, business_unit_id'),
      ('crm_opportunity_financial_events', 'opportunity_id, document_id, business_unit_id'),
      ('crm_activities', 'opportunity_id, business_unit_id'),
      ('crm_activity_log', 'account_id, contact_id, opportunity_id, business_unit_id'),
      ('crm_campaign_members', 'campaign_id, contact_id, business_unit_id'),
      ('crm_conversations', 'lead_id, business_unit_id'),
      ('crm_conversation_messages', 'conversation_id, lead_id, business_unit_id'),
      ('crm_email_messages', 'account_id, contact_id, opportunity_id, lead_id, business_unit_id'),
      ('crm_message_templates', 'account_id, product_interest_id, business_unit_id'),
      ('crm_assignment_rules', 'account_id, product_interest_id, business_unit_id'),
      ('crm_source_routes', 'account_id, product_interest_id, business_unit_id'),
      ('crm_whatsapp_templates', 'program_id, business_unit_id')
    ) trigger_tables(table_name, watched_columns)
  loop
    execute format('drop trigger if exists trg_%I_validate_tenant on public.%I', table_name, table_name);
    execute format(
      'create trigger trg_%I_validate_tenant before insert or update of %s on public.%I for each row execute procedure public.crm_validate_business_unit_relationship()',
      table_name, watched_columns, table_name
    );
  end loop;
end $$;

create or replace function public.crm_validate_opportunity_state()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_reason_type text;
  v_reason_requires_comment boolean;
  v_lifecycle_command boolean :=
    coalesce(current_setting('app.crm_lifecycle_transition', true), 'false') = 'true';
begin
  if tg_op = 'INSERT' then
    if not v_lifecycle_command and new.commercial_status not in ('verification', 'open') then
      raise exception 'New opportunities must start as verification or open';
    end if;
    if not v_lifecycle_command
       and new.commercial_status in ('verification', 'open')
       and (
         new.paused_stage is not null or new.pause_reason_id is not null
         or new.reactivation_at is not null or new.closed_at is not null
         or new.win_reason_id is not null or new.loss_reason_id is not null
         or new.accepted_net_amount is not null or new.accepted_currency is not null
         or new.acceptance_evidence_type is not null or new.evidence_document_id is not null
         or new.acceptance_evidence_reference is not null
       ) then
      raise exception 'A new active opportunity cannot contain pause or close data';
    end if;
  elsif not v_lifecycle_command and row(
    new.commercial_status, new.stage, new.paused_stage, new.pause_reason_id,
    new.pause_reason_snapshot, new.pause_comment, new.reactivation_at,
    new.closed_at, new.win_reason_id, new.loss_reason_id,
    new.close_reason_snapshot, new.closure_comment, new.competitor_name,
    new.accepted_net_amount, new.accepted_currency,
    new.acceptance_evidence_type, new.acceptance_evidence_reference,
    new.evidence_document_id
  ) is distinct from row(
    old.commercial_status, old.stage, old.paused_stage, old.pause_reason_id,
    old.pause_reason_snapshot, old.pause_comment, old.reactivation_at,
    old.closed_at, old.win_reason_id, old.loss_reason_id,
    old.close_reason_snapshot, old.closure_comment, old.competitor_name,
    old.accepted_net_amount, old.accepted_currency,
    old.acceptance_evidence_type, old.acceptance_evidence_reference,
    old.evidence_document_id
  ) then
    raise exception 'Lifecycle fields must be changed through a transition';
  end if;

  if tg_op = 'INSERT' and new.stage_entered_at is null then
    new.stage_entered_at := timezone('utc', now());
  elsif tg_op = 'UPDATE' and new.stage is distinct from old.stage then
    new.stage_entered_at := timezone('utc', now());
  end if;

  if new.owner_user_id is not null
     and (
       tg_op = 'INSERT'
       or new.commercial_status in ('open', 'paused')
       or (tg_op = 'UPDATE' and new.owner_user_id is distinct from old.owner_user_id)
     )
     and not exists (
       select 1
       from public.crm_business_unit_memberships membership
       where membership.business_unit_id = new.business_unit_id
         and membership.user_id = new.owner_user_id
         and membership.active
         and membership.role in ('admin', 'manager', 'sales_rep')
     ) then
    raise exception 'Opportunity owner must be an active commercial member of the business unit';
  end if;

  if new.commercial_status = 'open' then
    if new.owner_user_id is null or nullif(btrim(new.next_action), '') is null or new.next_action_at is null then
      raise exception 'An open opportunity requires owner, next action and next-action date';
    end if;
    if new.stage = 'proposal' and not exists (
      select 1 from public.crm_opportunity_quotations link
      where link.opportunity_id = new.id and link.is_current
        and link.sent_at is not null and nullif(btrim(link.sent_channel), '') is not null
    ) then
      raise exception 'Quotation sent stage requires a current quotation with sent date and channel';
    end if;
  elsif new.commercial_status = 'paused' then
    if new.owner_user_id is null or new.pause_reason_id is null or new.reactivation_at is null or new.paused_stage is null then
      raise exception 'A paused opportunity requires owner, reason, reactivation date and preserved stage';
    end if;
    select reason_type, requires_comment into v_reason_type, v_reason_requires_comment
    from public.crm_opportunity_reasons
    where id = new.pause_reason_id
      and business_unit_id = new.business_unit_id
      and active;
    if v_reason_type is distinct from 'pause' then raise exception 'Invalid pause reason'; end if;
    if v_reason_requires_comment and nullif(btrim(new.pause_comment), '') is null then
      raise exception 'The selected pause reason requires a comment';
    end if;
  elsif new.commercial_status = 'won' then
    if new.closed_at is null or new.win_reason_id is null or new.accepted_net_amount is null
       or new.accepted_currency is null or new.acceptance_evidence_type is null then
      raise exception 'A won opportunity requires close date, reason, accepted net amount, currency and evidence';
    end if;
    if new.acceptance_evidence_type <> 'inbound_interaction' and new.evidence_document_id is null then
      raise exception 'Documentary acceptance evidence is required';
    end if;
    if new.acceptance_evidence_type = 'inbound_interaction'
       and (new.acceptance_evidence_reference is null or new.acceptance_evidence_reference = '{}'::jsonb) then
      raise exception 'Inbound acceptance evidence requires a reference';
    end if;
    if new.evidence_document_id is not null and not exists (
      select 1 from public.crm_opportunity_documents document
      where document.id = new.evidence_document_id
        and document.business_unit_id = new.business_unit_id
        and document.opportunity_id = new.id
        and document.acceptance_eligible
    ) then
      raise exception 'Acceptance document does not belong to this opportunity';
    end if;
    if new.acceptance_evidence_type = 'inbound_interaction'
       and not public.crm_valid_inbound_acceptance(
         new.business_unit_id, new.id, new.acceptance_evidence_reference
       ) then
      raise exception 'Inbound acceptance is not linked to this opportunity';
    end if;
    select reason_type, requires_comment into v_reason_type, v_reason_requires_comment
    from public.crm_opportunity_reasons
    where id = new.win_reason_id
      and business_unit_id = new.business_unit_id
      and active;
    if v_reason_type is distinct from 'win' then raise exception 'Invalid win reason'; end if;
    if v_reason_requires_comment and nullif(btrim(new.closure_comment), '') is null then
      raise exception 'The selected win reason requires a comment';
    end if;
  elsif new.commercial_status = 'lost' then
    if new.closed_at is null or new.loss_reason_id is null or nullif(btrim(new.closure_comment), '') is null then
      raise exception 'A lost opportunity requires close date, reason and comment';
    end if;
    select reason_type, requires_comment into v_reason_type, v_reason_requires_comment
    from public.crm_opportunity_reasons
    where id = new.loss_reason_id
      and business_unit_id = new.business_unit_id
      and active;
    if v_reason_type is distinct from 'loss' then raise exception 'Invalid loss reason'; end if;
    if v_reason_requires_comment and nullif(btrim(new.closure_comment), '') is null then
      raise exception 'The selected loss reason requires a comment';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    new.version := old.version + 1;
  end if;
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_crm_opportunities_validate_state on public.crm_opportunities;
create trigger trg_crm_opportunities_validate_state
before insert or update on public.crm_opportunities
for each row execute procedure public.crm_validate_opportunity_state();

create or replace function public.crm_capture_opportunity_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event_type text;
begin
  if new.commercial_status is distinct from old.commercial_status then
    v_event_type := case new.commercial_status
      when 'paused' then 'paused'
      when 'open' then case when old.commercial_status in ('won','lost','paused') then 'reopened' else 'status_changed' end
      when 'won' then 'won'
      when 'lost' then 'lost'
      else 'status_changed'
    end;
  elsif new.stage is distinct from old.stage then v_event_type := 'stage_changed';
  elsif new.owner_user_id is distinct from old.owner_user_id then v_event_type := 'owner_changed';
  elsif new.current_proposed_net_amount is distinct from old.current_proposed_net_amount
     or new.current_currency is distinct from old.current_currency then v_event_type := 'amount_changed';
  elsif new.estimated_close_date is distinct from old.estimated_close_date then v_event_type := 'estimated_close_changed';
  elsif new.next_action is distinct from old.next_action
     or new.next_action_at is distinct from old.next_action_at then v_event_type := 'next_action_changed';
  else return new;
  end if;

  insert into public.crm_opportunity_events (
    business_unit_id, opportunity_id, event_type, old_values, new_values, created_by
  ) values (
    new.business_unit_id,
    new.id,
    v_event_type,
    jsonb_build_object(
      'commercial_status', old.commercial_status, 'stage', old.stage,
      'owner_user_id', old.owner_user_id, 'current_proposed_net_amount', old.current_proposed_net_amount,
      'current_currency', old.current_currency, 'estimated_close_date', old.estimated_close_date,
      'next_action', old.next_action, 'next_action_at', old.next_action_at
    ),
    jsonb_build_object(
      'commercial_status', new.commercial_status, 'stage', new.stage,
      'owner_user_id', new.owner_user_id, 'current_proposed_net_amount', new.current_proposed_net_amount,
      'current_currency', new.current_currency, 'estimated_close_date', new.estimated_close_date,
      'next_action', new.next_action, 'next_action_at', new.next_action_at
    ),
    coalesce(new.updated_by, auth.uid())
  );
  return new;
end;
$$;

drop trigger if exists trg_crm_opportunities_capture_change on public.crm_opportunities;
create trigger trg_crm_opportunities_capture_change
after update on public.crm_opportunities
for each row execute procedure public.crm_capture_opportunity_change();

create or replace function public.crm_refresh_opportunity_valuation(p_opportunity_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_amount numeric(14,2);
  v_currency text;
  v_tax_status text;
begin
  select
    coalesce(sum(item.line_total), 0)::numeric(14,2),
    quotation.currency,
    case
      when lower(quotation.terms_taxes) like '%no incluyen%' then 'confirmed_net'
      when lower(quotation.terms_taxes) like '%incluyen%' then 'needs_review'
      else 'unknown'
    end
  into v_amount, v_currency, v_tax_status
  from public.crm_opportunity_quotations link
  join public.ops_quotations quotation on quotation.id = link.quotation_id
  left join public.ops_quotation_items item on item.quotation_id = quotation.id
  where link.opportunity_id = p_opportunity_id and link.is_current
  group by quotation.currency, quotation.terms_taxes;

  update public.crm_opportunities
  set current_proposed_net_amount = v_amount,
      current_currency = v_currency,
      tax_basis_status = coalesce(v_tax_status, 'unknown'),
      amount = v_amount
  where id = p_opportunity_id;
end;
$$;

create or replace function public.crm_refresh_valuation_from_quotation_link()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.crm_refresh_opportunity_valuation(old.opportunity_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    perform public.crm_refresh_opportunity_valuation(new.opportunity_id);
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_crm_opportunity_quotations_refresh_valuation
  on public.crm_opportunity_quotations;
create trigger trg_crm_opportunity_quotations_refresh_valuation
after insert or update or delete on public.crm_opportunity_quotations
for each row execute procedure public.crm_refresh_valuation_from_quotation_link();

-- Record the pre-migration stage and then leave every historical result unasserted.
insert into public.crm_opportunity_events (
  business_unit_id, opportunity_id, event_type, old_values, new_values, source, imported_at
)
select
  opportunity.business_unit_id,
  opportunity.id,
  'legacy_stage_migrated',
  jsonb_build_object('legacy_stage', opportunity.legacy_stage_snapshot, 'legacy_close_date', opportunity.close_date),
  jsonb_build_object('commercial_status', 'verification', 'stage', opportunity.stage),
  'migration_0090',
  timezone('utc', now())
from public.crm_opportunities opportunity
where opportunity.business_unit_id is not null
  and not exists (
    select 1 from public.crm_opportunity_events event
    where event.opportunity_id = opportunity.id and event.source = 'migration_0090'
  );

-- Shared updated-at triggers for editable catalogs/views.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'crm_opportunity_stages','crm_opportunity_reasons','crm_commercial_sources','crm_saved_views'
  ] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', table_name, table_name);
    execute format(
      'create trigger trg_%I_updated_at before update on public.%I for each row execute procedure public.crm_set_updated_at()',
      table_name, table_name
    );
  end loop;
end $$;

-- RLS: every relationship has its own tenant key and validates the owning record.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'crm_opportunity_stages','crm_opportunity_reasons','crm_commercial_sources',
    'crm_lead_opportunities','crm_opportunity_quotations','crm_opportunity_orders',
    'crm_opportunity_campaigns','crm_opportunity_events','crm_opportunity_documents',
    'crm_opportunity_outcomes','crm_opportunity_accepted_items',
    'crm_opportunity_financial_events','crm_saved_views'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
  end loop;
end $$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'crm_opportunity_stages','crm_opportunity_reasons','crm_commercial_sources'
  ] loop
    execute format('drop policy if exists %I on public.%I', table_name || '_select', table_name);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.crm_has_business_unit_access(business_unit_id))',
      table_name || '_select', table_name
    );
    execute format('drop policy if exists %I on public.%I', table_name || '_write', table_name);
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.crm_has_business_unit_access(business_unit_id, array[''admin'',''manager'']::text[])) with check (public.crm_has_business_unit_access(business_unit_id, array[''admin'',''manager'']::text[]))',
      table_name || '_write', table_name
    );
  end loop;
end $$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'crm_lead_opportunities','crm_opportunity_quotations','crm_opportunity_orders',
    'crm_opportunity_campaigns','crm_opportunity_documents','crm_opportunity_outcomes',
    'crm_opportunity_accepted_items','crm_opportunity_financial_events'
  ] loop
    execute format('drop policy if exists %I on public.%I', table_name || '_select', table_name);
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.crm_has_business_unit_access(business_unit_id))',
      table_name || '_select', table_name
    );
    execute format('drop policy if exists %I on public.%I', table_name || '_write', table_name);
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id)) with check (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id))',
      table_name || '_write', table_name
    );
  end loop;
end $$;

-- Outcomes and their accepted-item snapshots are append-only to authenticated
-- clients. They are written only through the atomic lifecycle RPC; corrections
-- and reopenings create a new version instead of mutating the previous result.
drop policy if exists crm_opportunity_outcomes_write on public.crm_opportunity_outcomes;
drop policy if exists crm_opportunity_outcomes_insert on public.crm_opportunity_outcomes;

drop policy if exists crm_opportunity_accepted_items_write on public.crm_opportunity_accepted_items;
drop policy if exists crm_opportunity_accepted_items_insert on public.crm_opportunity_accepted_items;

drop policy if exists crm_opportunity_events_select on public.crm_opportunity_events;
create policy crm_opportunity_events_select on public.crm_opportunity_events
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_opportunity_events_insert on public.crm_opportunity_events;
create policy crm_opportunity_events_insert on public.crm_opportunity_events
for insert to authenticated
with check (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id));

drop policy if exists crm_saved_views_select on public.crm_saved_views;
create policy crm_saved_views_select on public.crm_saved_views for select to authenticated
using (
  public.crm_has_business_unit_access(business_unit_id)
  and (visibility = 'company' or user_id = auth.uid() or user_id is null)
);
drop policy if exists crm_saved_views_write on public.crm_saved_views;
create policy crm_saved_views_write on public.crm_saved_views for all to authenticated
using (
  public.crm_has_business_unit_access(business_unit_id)
  and (user_id = auth.uid() or public.crm_has_business_unit_access(business_unit_id, array['admin','manager']::text[]))
)
with check (
  public.crm_has_business_unit_access(business_unit_id)
  and (user_id = auth.uid() or public.crm_has_business_unit_access(business_unit_id, array['admin','manager']::text[]))
);

grant select, insert, update, delete on
  public.crm_opportunity_stages, public.crm_opportunity_reasons,
  public.crm_commercial_sources, public.crm_lead_opportunities,
  public.crm_opportunity_quotations, public.crm_opportunity_orders,
  public.crm_opportunity_campaigns, public.crm_opportunity_documents,
  public.crm_opportunity_financial_events, public.crm_saved_views
to authenticated;
grant select on public.crm_opportunity_outcomes,
  public.crm_opportunity_accepted_items to authenticated;
revoke insert, update, delete on public.crm_opportunity_outcomes,
  public.crm_opportunity_accepted_items from authenticated;
grant select, insert on public.crm_opportunity_events to authenticated;
revoke update, delete on public.crm_opportunities from authenticated;
grant update (
  account_id, name, owner_user_id, opportunity_type, need_summary,
  product_categories, budget_amount, budget_currency, budget_status,
  expected_purchase_date, estimated_close_date, next_action, next_action_at,
  last_effective_contact_at, last_customer_response_at,
  current_proposed_net_amount, current_currency, current_cost_net,
  current_discount_percent, tax_basis_status, commercial_source_id, channel,
  primary_campaign_id, description, amount, close_date, owner, type,
  updated_at, updated_by
) on public.crm_opportunities to authenticated;
revoke all on function public.crm_valid_inbound_acceptance(uuid, uuid, jsonb) from public;
grant execute on function public.crm_valid_inbound_acceptance(uuid, uuid, jsonb) to service_role;
revoke all on function public.crm_refresh_opportunity_valuation(uuid) from public;
grant execute on function public.crm_refresh_opportunity_valuation(uuid) to service_role;

-- Trigger functions execute through their triggers; they are not public RPCs.
revoke all on function public.crm_normalize_ops_lead_context() from public;
revoke all on function public.crm_sync_opportunity_primary_campaign() from public;
revoke all on function public.crm_guard_primary_campaign_link() from public;
revoke all on function public.crm_prepare_opportunity_outcome() from public;
revoke all on function public.crm_validate_business_unit_relationship() from public;
revoke all on function public.crm_validate_opportunity_state() from public;
revoke all on function public.crm_capture_opportunity_change() from public;
revoke all on function public.crm_refresh_valuation_from_quotation_link() from public;

notify pgrst, 'reload schema';

commit;
