-- Sales CRM: business-unit ownership, tenant isolation and secret hardening.
--
-- This migration is intentionally additive.  The legacy CRM used crm_accounts
-- both for customers and as a tenant selector (Brave / ISF).  We retain those
-- two rows as archived migration references, move their scope to explicit
-- business units and stop using them as customer accounts.
begin;

create extension if not exists "pgcrypto";

-- Several legacy CRM tables were created with UUID primary keys but without a
-- server-side generator.  The old API happened to provide some identifiers,
-- while the tenant-aware Sales service correctly relies on the database to
-- generate them.  Restore only missing defaults so installations that already
-- use another UUID expression keep their existing behaviour.
do $$
declare
  v_table_name text;
begin
  foreach v_table_name in array array[
    'crm_accounts',
    'crm_contacts',
    'crm_opportunities',
    'crm_opportunity_contacts',
    'crm_activities',
    'crm_activity_tasks',
    'crm_activity_log',
    'crm_campaigns',
    'crm_campaign_members',
    'crm_leads',
    'crm_lead_events',
    'crm_conversations',
    'crm_conversation_messages',
    'crm_email_settings',
    'crm_email_messages',
    'crm_message_templates',
    'crm_assignment_rules',
    'crm_source_routes',
    'crm_source_field_mappings',
    'crm_messaging_providers',
    'crm_product_interests',
    'crm_programs',
    'crm_whatsapp_templates',
    'crm_webhook_inbox'
  ]
  loop
    if exists (
      select 1
      from pg_catalog.pg_class relation
      join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
      join pg_catalog.pg_attribute attribute on attribute.attrelid = relation.oid
      left join pg_catalog.pg_attrdef default_value
        on default_value.adrelid = relation.oid
       and default_value.adnum = attribute.attnum
      where namespace.nspname = 'public'
        and relation.relname = v_table_name
        and relation.relkind in ('r', 'p')
        and attribute.attname = 'id'
        and attribute.atttypid = 'uuid'::regtype
        and not attribute.attisdropped
        and default_value.oid is null
    ) then
      execute format(
        'alter table public.%I alter column id set default gen_random_uuid()',
        v_table_name
      );
    end if;
  end loop;
end;
$$;

-- Keep historical NULL timestamps untouched (their original business date is
-- unknown), but make every newly created CRM row auditable from this point on.
do $$
declare
  v_table_name text;
  v_column_name text;
begin
  foreach v_table_name in array array[
    'crm_accounts', 'crm_contacts', 'crm_opportunities',
    'crm_opportunity_contacts', 'crm_activities', 'crm_activity_tasks',
    'crm_activity_log', 'crm_campaigns', 'crm_campaign_members', 'crm_leads',
    'crm_lead_events', 'crm_conversations', 'crm_conversation_messages',
    'crm_email_settings', 'crm_email_messages', 'crm_message_templates',
    'crm_assignment_rules', 'crm_source_routes', 'crm_source_field_mappings',
    'crm_messaging_providers', 'crm_product_interests', 'crm_programs',
    'crm_whatsapp_templates', 'crm_webhook_inbox'
  ]
  loop
    foreach v_column_name in array array['created_at', 'updated_at']
    loop
      if exists (
        select 1
        from pg_catalog.pg_class relation
        join pg_catalog.pg_namespace namespace on namespace.oid = relation.relnamespace
        join pg_catalog.pg_attribute attribute on attribute.attrelid = relation.oid
        left join pg_catalog.pg_attrdef default_value
          on default_value.adrelid = relation.oid
         and default_value.adnum = attribute.attnum
        where namespace.nspname = 'public'
          and relation.relname = v_table_name
          and relation.relkind in ('r', 'p')
          and attribute.attname = v_column_name
          and attribute.atttypid in ('timestamp with time zone'::regtype, 'timestamp without time zone'::regtype)
          and not attribute.attisdropped
          and default_value.oid is null
      ) then
        execute format(
          'alter table public.%I alter column %I set default timezone(''utc'', now())',
          v_table_name,
          v_column_name
        );
      end if;
    end loop;
  end loop;
end;
$$;

create table if not exists public.crm_business_units (
  id uuid primary key default gen_random_uuid(),
  code text not null,
  slug text not null,
  name text not null,
  active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_business_units_slug_check
    check (slug = lower(slug) and slug ~ '^[a-z0-9][a-z0-9_-]*$'),
  constraint crm_business_units_code_check
    check (code = slug),
  constraint crm_business_units_name_check check (nullif(btrim(name), '') is not null)
);

create unique index if not exists uq_crm_business_units_slug
  on public.crm_business_units (lower(slug));
create unique index if not exists uq_crm_business_units_code
  on public.crm_business_units (lower(code));

insert into public.crm_business_units (code, slug, name)
values
  ('cdm', 'cdm', 'CDM'),
  ('brave-destinations', 'brave-destinations', 'Brave Destinations'),
  ('instituto-san-fernando', 'instituto-san-fernando', 'Instituto San Fernando')
on conflict ((lower(slug))) do update
set code = excluded.code,
    name = excluded.name,
    active = true;

create table if not exists public.crm_business_unit_memberships (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null,
  is_default boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_business_unit_memberships_role_check
    check (role in ('admin', 'manager', 'sales_rep', 'marketing', 'viewer')),
  constraint uq_crm_business_unit_membership unique (business_unit_id, user_id)
);

create unique index if not exists uq_crm_business_unit_default_membership
  on public.crm_business_unit_memberships (user_id)
  where active and is_default;
create index if not exists idx_crm_business_unit_memberships_user
  on public.crm_business_unit_memberships (user_id, active);

-- Existing Sales users previously had global CRM access.  Preserve that access
-- explicitly during the migration; new users must receive deliberate memberships.
insert into public.crm_business_unit_memberships (
  business_unit_id,
  user_id,
  role,
  is_default,
  active
)
select
  unit.id,
  module_access.user_id,
  'admin',
  unit.slug = 'cdm'
    and not exists (
      select 1
      from public.crm_business_unit_memberships existing
      where existing.user_id = module_access.user_id
        and existing.active
        and existing.is_default
    ),
  true
from public.app_user_modules as module_access
cross join public.crm_business_units as unit
where lower(module_access.module_key) = 'sales'
on conflict (business_unit_id, user_id) do nothing;

-- OPS users need to retain access to CDM quotations.  Sales module validation is
-- still enforced separately by the API, so this does not grant access to Sales UI.
insert into public.crm_business_unit_memberships (
  business_unit_id,
  user_id,
  role,
  is_default,
  active
)
select
  unit.id,
  module_access.user_id,
  'manager',
  not exists (
    select 1
    from public.crm_business_unit_memberships existing
    where existing.user_id = module_access.user_id
      and existing.active
      and existing.is_default
  ),
  true
from public.app_user_modules as module_access
join public.crm_business_units as unit on unit.slug = 'cdm'
where lower(module_access.module_key) = 'ops'
on conflict (business_unit_id, user_id) do nothing;

create or replace function public.crm_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_crm_business_units_updated_at on public.crm_business_units;
create trigger trg_crm_business_units_updated_at
before update on public.crm_business_units
for each row execute procedure public.crm_set_updated_at();

drop trigger if exists trg_crm_business_unit_memberships_updated_at
  on public.crm_business_unit_memberships;
create trigger trg_crm_business_unit_memberships_updated_at
before update on public.crm_business_unit_memberships
for each row execute procedure public.crm_set_updated_at();

create or replace function public.crm_request_business_unit_id()
returns uuid
language plpgsql
stable
set search_path = public, pg_temp
as $$
declare
  v_headers jsonb;
begin
  begin
    v_headers := nullif(current_setting('request.headers', true), '')::jsonb;
  exception when others then
    return null;
  end;
  return nullif(v_headers->>'x-company-id', '')::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

create or replace function public.crm_has_business_unit_access(
  p_business_unit_id uuid,
  p_roles text[] default null
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.crm_business_unit_memberships membership
    where membership.business_unit_id = p_business_unit_id
      and membership.user_id = auth.uid()
      and membership.active
      and (p_roles is null or membership.role = any(p_roles))
      and (
        public.crm_request_business_unit_id() is null
        or membership.business_unit_id = public.crm_request_business_unit_id()
      )
      and exists (
        select 1
        from public.app_user_modules module_access
        where module_access.user_id = auth.uid()
          and lower(module_access.module_key) = 'sales'
      )
  );
$$;

create or replace function public.crm_has_ops_business_unit_access(
  p_business_unit_id uuid,
  p_roles text[] default null
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.crm_business_unit_memberships membership
    where membership.business_unit_id = p_business_unit_id
      and membership.user_id = auth.uid()
      and membership.active
      and (p_roles is null or membership.role = any(p_roles))
      and (
        public.crm_request_business_unit_id() is null
        or membership.business_unit_id = public.crm_request_business_unit_id()
      )
      and exists (
        select 1
        from public.app_user_modules module_access
        where module_access.user_id = auth.uid()
          and lower(module_access.module_key) = 'ops'
      )
  );
$$;

create or replace function public.crm_is_any_business_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.crm_business_unit_memberships membership
    where membership.user_id = auth.uid()
      and membership.active
      and membership.role = 'admin'
      and exists (
        select 1 from public.app_user_modules module_access
        where module_access.user_id = auth.uid()
          and lower(module_access.module_key) = 'sales'
      )
  );
$$;

create or replace function public.crm_can_edit_business_record(
  p_business_unit_id uuid,
  p_owner_user_id uuid default null,
  p_allow_marketing boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.crm_business_unit_memberships membership
    where membership.business_unit_id = p_business_unit_id
      and membership.user_id = auth.uid()
      and membership.active
      and (
        public.crm_request_business_unit_id() is null
        or membership.business_unit_id = public.crm_request_business_unit_id()
      )
      and exists (
        select 1 from public.app_user_modules module_access
        where module_access.user_id = auth.uid()
          and lower(module_access.module_key) = 'sales'
      )
      and (
        membership.role in ('admin', 'manager')
        or (membership.role = 'marketing' and p_allow_marketing)
        or (
          membership.role = 'sales_rep'
          and (p_owner_user_id is null or p_owner_user_id = auth.uid())
        )
      )
  );
$$;

-- PostgreSQL validates SQL-language function bodies when they are created.
-- Add the minimal tenant/owner columns before compiling the child-policy
-- helpers below; the complete additive column set is applied later.
alter table public.crm_opportunities
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid;
alter table public.crm_leads
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid;
alter table public.crm_campaigns
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid;

create or replace function public.crm_can_edit_opportunity_child(
  p_business_unit_id uuid,
  p_opportunity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.crm_opportunities opportunity
    where opportunity.id = p_opportunity_id
      and opportunity.business_unit_id = p_business_unit_id
      and public.crm_can_edit_business_record(
        p_business_unit_id,
        opportunity.owner_user_id
      )
  );
$$;

create or replace function public.crm_can_edit_lead_child(
  p_business_unit_id uuid,
  p_lead_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.crm_leads lead
    where lead.id = p_lead_id
      and lead.business_unit_id = p_business_unit_id
      and public.crm_can_edit_business_record(
        p_business_unit_id,
        coalesce(lead.owner_user_id, lead.assigned_user_id),
        true
      )
  );
$$;

create or replace function public.crm_can_edit_campaign_child(
  p_business_unit_id uuid,
  p_campaign_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.crm_campaigns campaign
    where campaign.id = p_campaign_id
      and campaign.business_unit_id = p_business_unit_id
      and public.crm_can_edit_business_record(
        p_business_unit_id,
        campaign.owner_user_id,
        true
      )
  );
$$;

create or replace function public.crm_try_uuid(p_value text)
returns uuid
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
begin
  return p_value::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

-- Persist the old account-to-tenant interpretation before clearing those links.
create table if not exists public.crm_legacy_account_business_units (
  account_id uuid primary key references public.crm_accounts(id) on delete cascade,
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  migrated_at timestamptz not null default timezone('utc', now())
);

insert into public.crm_legacy_account_business_units (account_id, business_unit_id)
select account.id, unit.id
from public.crm_accounts account
join public.crm_business_units unit
  on (lower(account.name) = 'brave destinations' and unit.slug = 'brave-destinations')
  or (lower(account.name) = 'instituto san fernando' and unit.slug = 'instituto-san-fernando')
where lower(coalesce(account.type, '')) = 'lead_source'
on conflict (account_id) do update
set business_unit_id = excluded.business_unit_id;

-- Add tenant ownership while retaining every legacy column and response shape.
alter table public.crm_accounts
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid,
  add column if not exists created_by uuid,
  add column if not exists account_kind text not null default 'customer',
  add column if not exists ops_client_id uuid references public.ops_clients(id) on delete set null,
  add column if not exists tax_id text,
  add column if not exists is_archived boolean not null default false,
  add column if not exists imported_at timestamptz,
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

alter table public.crm_leads
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists technical_origin text,
  add column if not exists commercial_source_id uuid,
  add column if not exists contact_channel text,
  add column if not exists primary_campaign_id uuid,
  add column if not exists imported_at timestamptz;

alter table public.crm_contacts
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid,
  add column if not exists created_by uuid,
  add column if not exists ops_contact_id uuid references public.ops_contacts(id) on delete set null,
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

alter table public.crm_opportunities
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid,
  add column if not exists created_by uuid,
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

alter table public.crm_opportunity_contacts
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;

alter table public.crm_campaigns
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid,
  add column if not exists created_by uuid,
  add column if not exists currency text,
  add column if not exists is_archived boolean not null default false,
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

alter table public.crm_activities
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid,
  add column if not exists completed_at timestamptz,
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

alter table public.crm_activity_tasks
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists owner_user_id uuid,
  add column if not exists due_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

alter table public.crm_activity_log
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists opportunity_id uuid references public.crm_opportunities(id) on delete cascade,
  add column if not exists created_by uuid;

alter table public.crm_email_settings
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade,
  add column if not exists password_encrypted text,
  add column if not exists password_key_version integer,
  add column if not exists secret_migrated_at timestamptz;

alter table public.crm_email_messages
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict,
  add column if not exists opportunity_id uuid references public.crm_opportunities(id) on delete set null,
  add column if not exists lead_id uuid references public.crm_leads(id) on delete set null,
  add column if not exists created_by uuid;

alter table public.crm_message_templates
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;
alter table public.crm_assignment_rules
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;
alter table public.crm_source_routes
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;
alter table public.crm_source_field_mappings
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;
alter table public.crm_messaging_providers
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;
alter table public.crm_product_interests
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;
alter table public.crm_programs
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;
alter table public.crm_whatsapp_templates
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;
alter table public.crm_webhook_inbox
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict;
alter table public.crm_conversations
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict;
alter table public.crm_conversation_messages
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict;
alter table public.crm_lead_events
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict;
alter table public.crm_campaign_members
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete cascade;

alter table public.ops_quotations
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict;
alter table public.ops_orders
  add column if not exists business_unit_id uuid references public.crm_business_units(id) on delete restrict;

create unique index if not exists uq_crm_accounts_unit_ops_client
  on public.crm_accounts (business_unit_id, ops_client_id)
  where ops_client_id is not null;
create unique index if not exists uq_crm_contacts_unit_ops_contact
  on public.crm_contacts (business_unit_id, ops_contact_id)
  where ops_contact_id is not null;
create index if not exists idx_crm_accounts_business_unit
  on public.crm_accounts (business_unit_id, is_archived, name);
create index if not exists idx_crm_leads_business_unit
  on public.crm_leads (business_unit_id, created_at desc);
create index if not exists idx_crm_opportunities_business_unit
  on public.crm_opportunities (business_unit_id, created_at desc);
create index if not exists idx_ops_quotations_business_unit
  on public.ops_quotations (business_unit_id, quotation_date desc);

-- Translate legacy owner-account scoping before account_id becomes a customer link.
update public.crm_leads lead
set business_unit_id = mapping.business_unit_id,
    account_id = null
from public.crm_legacy_account_business_units mapping
where lead.account_id = mapping.account_id;

-- BEGIN CRM MESSAGE TEMPLATE SCOPE MIGRATION
-- The legacy index used account_id to distinguish the owning company.  Once
-- that scope moves to business_unit_id, clearing account_id would collide with
-- a global template or another company's template.  Replace the index BEFORE
-- updating those rows.  Keep account_id as a separate customer-specific scope,
-- and keep NULL ownership as an explicit scope rather than bypassing uniqueness.
-- Rebuilding inside this transaction is repeatable and retains all templates;
-- genuine duplicates within one company still reject the transaction.
drop index if exists public.uq_crm_message_templates_scope;
create unique index uq_crm_message_templates_scope
  on public.crm_message_templates (
    coalesce(business_unit_id::text, '*'),
    channel,
    language,
    coalesce(account_id::text, '*'),
    coalesce(product_interest_id::text, '*'),
    coalesce(lower(source_channel), '*'),
    coalesce(lower(requested_info_type), '*'),
    lower(template_key)
  );

update public.crm_message_templates record
set business_unit_id = mapping.business_unit_id,
    account_id = null
from public.crm_legacy_account_business_units mapping
where record.account_id = mapping.account_id;
-- END CRM MESSAGE TEMPLATE SCOPE MIGRATION

update public.crm_assignment_rules record
set business_unit_id = mapping.business_unit_id,
    account_id = null
from public.crm_legacy_account_business_units mapping
where record.account_id = mapping.account_id;

update public.crm_source_routes record
set business_unit_id = mapping.business_unit_id,
    account_id = null
from public.crm_legacy_account_business_units mapping
where record.account_id = mapping.account_id;

-- Some installations used the older campaign DDL with account_id while the
-- current production schema does not.  Migrate it only when that column exists.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'crm_campaigns'
      and column_name = 'account_id'
  ) then
    execute $sql$
      update public.crm_campaigns campaign
      set business_unit_id = mapping.business_unit_id,
          account_id = null
      from public.crm_legacy_account_business_units mapping
      where campaign.account_id = mapping.account_id
    $sql$;
  end if;
end $$;

update public.crm_accounts account
set business_unit_id = mapping.business_unit_id,
    account_kind = 'legacy_scope',
    is_archived = true,
    updated_at = timezone('utc', now())
from public.crm_legacy_account_business_units mapping
where account.id = mapping.account_id;

-- CDM is the only existing OPS owner.  Infer only records for which this is safe.
update public.ops_quotations
set business_unit_id = (select id from public.crm_business_units where slug = 'cdm')
where business_unit_id is null;

update public.ops_orders
set business_unit_id = (select id from public.crm_business_units where slug = 'cdm')
where business_unit_id is null;

create or replace function public.crm_default_ops_business_unit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.business_unit_id is null then
    select id into new.business_unit_id
    from public.crm_business_units
    where code = 'cdm' and active
    limit 1;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_ops_quotations_default_business_unit on public.ops_quotations;
create trigger trg_ops_quotations_default_business_unit
before insert on public.ops_quotations
for each row execute procedure public.crm_default_ops_business_unit();

drop trigger if exists trg_ops_orders_default_business_unit on public.ops_orders;
create trigger trg_ops_orders_default_business_unit
before insert on public.ops_orders
for each row execute procedure public.crm_default_ops_business_unit();

update public.crm_leads
set business_unit_id = (select id from public.crm_business_units where slug = 'cdm'),
    technical_origin = coalesce(technical_origin, 'ops_quotation'),
    contact_channel = coalesce(contact_channel, nullif(source_channel, '')),
    account_id = null
where business_unit_id is null
  and (
    lower(coalesce(source_channel, '')) in ('ops quotation', 'ops_quotation', 'ops quotations')
    or lower(coalesce(source_detail, '')) like '%ops%quotation%'
  );

update public.crm_leads lead
set business_unit_id = account.business_unit_id
from public.crm_accounts account
where lead.business_unit_id is null
  and lead.account_id = account.id
  and account.business_unit_id is not null
  and account.account_kind <> 'legacy_scope';

update public.crm_contacts contact
set business_unit_id = account.business_unit_id
from public.crm_accounts account
where contact.business_unit_id is null
  and contact.account_id = account.id
  and account.business_unit_id is not null;

update public.crm_opportunities opportunity
set business_unit_id = account.business_unit_id
from public.crm_accounts account
where opportunity.business_unit_id is null
  and opportunity.account_id = account.id
  and account.business_unit_id is not null;

-- All pre-migration non-scope accounts belonged to the only operational CRM
-- tenant (CDM).  Brave and ISF were explicitly identified above, so this does
-- not infer ownership merely from an account name.
update public.crm_accounts account
set business_unit_id = (select id from public.crm_business_units where slug = 'cdm'),
    account_kind = case when account.account_kind = 'legacy_scope' then account.account_kind else 'customer' end,
    updated_at = timezone('utc', now())
where account.business_unit_id is null
  and account.account_kind <> 'legacy_scope';

-- Re-run dependent inference after assigning the legacy CDM customer accounts.
update public.crm_contacts contact
set business_unit_id = account.business_unit_id
from public.crm_accounts account
where contact.business_unit_id is null
  and contact.account_id = account.id
  and account.business_unit_id is not null;

update public.crm_opportunities opportunity
set business_unit_id = account.business_unit_id
from public.crm_accounts account
where opportunity.business_unit_id is null
  and opportunity.account_id = account.id
  and account.business_unit_id is not null;

update public.crm_opportunity_contacts link
set business_unit_id = opportunity.business_unit_id
from public.crm_opportunities opportunity
where link.opportunity_id = opportunity.id
  and link.business_unit_id is null;

update public.crm_activities activity
set business_unit_id = opportunity.business_unit_id
from public.crm_opportunities opportunity
where activity.opportunity_id = opportunity.id
  and activity.business_unit_id is null;

update public.crm_activity_tasks task
set business_unit_id = activity.business_unit_id,
    owner_user_id = coalesce(task.owner_user_id, public.crm_try_uuid(task.assigned_to)),
    due_at = coalesce(task.due_at, task.due_date::timestamptz)
from public.crm_activities activity
where task.activity_id = activity.id
  and task.business_unit_id is null;

update public.crm_lead_events event
set business_unit_id = lead.business_unit_id
from public.crm_leads lead
where event.lead_id = lead.id
  and event.business_unit_id is null;

update public.crm_conversations conversation
set business_unit_id = lead.business_unit_id
from public.crm_leads lead
where conversation.lead_id = lead.id
  and conversation.business_unit_id is null;

update public.crm_conversation_messages message
set business_unit_id = conversation.business_unit_id
from public.crm_conversations conversation
where message.conversation_id = conversation.id
  and message.business_unit_id is null;

update public.crm_campaign_members member
set business_unit_id = campaign.business_unit_id
from public.crm_campaigns campaign
where member.campaign_id = campaign.id
  and member.business_unit_id is null;

update public.crm_email_messages message
set business_unit_id = account.business_unit_id
from public.crm_accounts account
where message.business_unit_id is null
  and message.account_id = account.id;

update public.crm_email_messages message
set business_unit_id = contact.business_unit_id
from public.crm_contacts contact
where message.business_unit_id is null
  and message.contact_id = contact.id;

-- User-owned email settings follow the user's default unit (CDM for migrated users).
update public.crm_email_settings setting
set business_unit_id = membership.business_unit_id
from public.crm_business_unit_memberships membership
where setting.business_unit_id is null
  and membership.user_id = setting.user_id
  and membership.active
  and membership.is_default;

-- Track ambiguous historical records without assigning invented ownership.
create table if not exists public.crm_business_unit_assignment_queue (
  id uuid primary key default gen_random_uuid(),
  source_table text not null,
  source_id uuid not null,
  reason text not null,
  snapshot jsonb not null default '{}'::jsonb,
  resolved_business_unit_id uuid references public.crm_business_units(id) on delete set null,
  resolved_by uuid,
  resolved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  constraint uq_crm_business_unit_assignment_queue unique (source_table, source_id)
);

insert into public.crm_business_unit_assignment_queue (source_table, source_id, reason, snapshot)
select 'crm_leads', id, 'No identificado', jsonb_build_object('name', full_name, 'source_channel', source_channel)
from public.crm_leads where business_unit_id is null
on conflict (source_table, source_id) do nothing;

insert into public.crm_business_unit_assignment_queue (source_table, source_id, reason, snapshot)
select 'crm_accounts', id, 'No identificado', jsonb_build_object('name', name, 'type', type)
from public.crm_accounts where business_unit_id is null
on conflict (source_table, source_id) do nothing;

insert into public.crm_business_unit_assignment_queue (source_table, source_id, reason, snapshot)
select 'crm_opportunities', id, 'No identificado', jsonb_build_object('name', name, 'stage', stage)
from public.crm_opportunities where business_unit_id is null
on conflict (source_table, source_id) do nothing;

insert into public.crm_business_unit_assignment_queue (source_table, source_id, reason, snapshot)
select 'crm_campaigns', id, 'No identificado', jsonb_build_object('name', name, 'status', status)
from public.crm_campaigns where business_unit_id is null
on conflict (source_table, source_id) do nothing;

-- Queue every remaining ambiguous tenant-bearing record.  Configuration
-- snapshots are intentionally empty so provider credentials and message
-- contents never get copied into the administrative queue.
do $$
declare table_name text;
begin
  foreach table_name in array array[
    'crm_contacts','crm_activities','crm_activity_tasks','crm_activity_log',
    'crm_email_settings','crm_email_messages','crm_message_templates',
    'crm_assignment_rules','crm_source_routes','crm_source_field_mappings',
    'crm_messaging_providers','crm_product_interests','crm_programs',
    'crm_whatsapp_templates','crm_webhook_inbox','crm_conversations',
    'crm_conversation_messages','crm_lead_events','crm_campaign_members'
  ] loop
    execute format(
      'insert into public.crm_business_unit_assignment_queue (source_table, source_id, reason, snapshot) select %L, id, ''No identificado'', ''{}''::jsonb from public.%I where business_unit_id is null on conflict (source_table, source_id) do nothing',
      table_name, table_name
    );
  end loop;
end $$;

-- Resolve ambiguous historical ownership only after an administrator reviews
-- the snapshot.  The source table is selected from a strict allow-list and
-- both the source row and queue decision are changed in one transaction.
create or replace function public.crm_resolve_business_unit_assignment(
  p_queue_id uuid,
  p_business_unit_id uuid
)
returns public.crm_business_unit_assignment_queue
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_assignment public.crm_business_unit_assignment_queue%rowtype;
  v_actual_business_unit_id uuid;
  v_source_exists boolean;
  v_allowed_tables constant text[] := array[
    'crm_accounts','crm_leads','crm_contacts','crm_opportunities','crm_campaigns',
    'crm_activities','crm_activity_tasks','crm_activity_log','crm_email_settings',
    'crm_email_messages','crm_message_templates','crm_assignment_rules',
    'crm_source_routes','crm_source_field_mappings','crm_messaging_providers',
    'crm_product_interests','crm_programs','crm_whatsapp_templates',
    'crm_webhook_inbox','crm_conversations','crm_conversation_messages',
    'crm_lead_events','crm_campaign_members'
  ];
begin
  if not exists (
    select 1
    from public.crm_business_units unit
    where unit.id = p_business_unit_id
      and unit.active
  ) then
    raise exception 'Business unit not found or inactive';
  end if;

  if coalesce(auth.role(), '') <> 'service_role'
     and not exists (
       select 1
       from public.crm_business_unit_memberships membership
       where membership.business_unit_id = p_business_unit_id
         and membership.user_id = auth.uid()
         and membership.role = 'admin'
         and membership.active
     ) then
    raise exception 'Administrator membership is required';
  end if;

  select *
  into v_assignment
  from public.crm_business_unit_assignment_queue
  where id = p_queue_id
  for update;

  if not found then
    raise exception 'Assignment queue item not found';
  end if;
  if not (v_assignment.source_table = any(v_allowed_tables)) then
    raise exception 'Unsupported assignment source table';
  end if;
  if v_assignment.resolved_at is not null then
    if v_assignment.resolved_business_unit_id is distinct from p_business_unit_id then
      raise exception 'Assignment queue item was already resolved for another business unit';
    end if;
    return v_assignment;
  end if;

  execute format(
    'select business_unit_id, true from public.%I where id = $1 for update',
    v_assignment.source_table
  )
  into v_actual_business_unit_id, v_source_exists
  using v_assignment.source_id;

  if not coalesce(v_source_exists, false) then
    raise exception 'Assignment source row not found';
  end if;
  if v_actual_business_unit_id is not null
     and v_actual_business_unit_id <> p_business_unit_id then
    raise exception 'Assignment source row already belongs to another business unit';
  end if;

  if v_actual_business_unit_id is null then
    execute format(
      'update public.%I set business_unit_id = $1 where id = $2 and business_unit_id is null',
      v_assignment.source_table
    )
    using p_business_unit_id, v_assignment.source_id;
  end if;

  update public.crm_business_unit_assignment_queue
  set resolved_business_unit_id = p_business_unit_id,
      resolved_by = auth.uid(),
      resolved_at = timezone('utc', now())
  where id = p_queue_id
  returning * into v_assignment;

  return v_assignment;
end;
$$;

revoke all on function public.crm_resolve_business_unit_assignment(uuid, uuid) from public;
grant execute on function public.crm_resolve_business_unit_assignment(uuid, uuid)
  to authenticated, service_role;

-- Keep cross-table tenant keys synchronized for records inserted by legacy code.
create or replace function public.crm_inherit_business_unit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.business_unit_id is not null then
    return new;
  end if;

  if tg_table_name = 'crm_lead_events' then
    select business_unit_id into new.business_unit_id from public.crm_leads where id = new.lead_id;
  elsif tg_table_name = 'crm_conversations' then
    select business_unit_id into new.business_unit_id from public.crm_leads where id = new.lead_id;
  elsif tg_table_name = 'crm_conversation_messages' then
    select business_unit_id into new.business_unit_id from public.crm_conversations where id = new.conversation_id;
  elsif tg_table_name = 'crm_opportunity_contacts' then
    select business_unit_id into new.business_unit_id from public.crm_opportunities where id = new.opportunity_id;
  elsif tg_table_name = 'crm_activities' then
    select business_unit_id into new.business_unit_id from public.crm_opportunities where id = new.opportunity_id;
  elsif tg_table_name = 'crm_activity_tasks' then
    select business_unit_id into new.business_unit_id from public.crm_activities where id = new.activity_id;
  elsif tg_table_name = 'crm_campaign_members' then
    select business_unit_id into new.business_unit_id from public.crm_campaigns where id = new.campaign_id;
  end if;
  return new;
end;
$$;

do $$
declare
  table_name text;
  parent_column text;
begin
  for table_name, parent_column in
    select * from (values
      ('crm_lead_events', 'lead_id'),
      ('crm_conversations', 'lead_id'),
      ('crm_conversation_messages', 'conversation_id'),
      ('crm_opportunity_contacts', 'opportunity_id'),
      ('crm_activities', 'opportunity_id'),
      ('crm_activity_tasks', 'activity_id'),
      ('crm_campaign_members', 'campaign_id')
    ) values_list(table_name, parent_column)
  loop
    execute format('drop trigger if exists trg_%I_inherit_business_unit on public.%I', table_name, table_name);
    execute format(
      'create trigger trg_%I_inherit_business_unit before insert or update of %I, business_unit_id on public.%I for each row execute procedure public.crm_inherit_business_unit()',
      table_name, parent_column, table_name
    );
  end loop;
end $$;

-- Legacy internal endpoints predate explicit tenant fields.  Populate the
-- selected request company on inserts so those compatible routes remain safe
-- while the backend migrates them incrementally.  Service/webhook writes must
-- provide a company explicitly because they have no user membership.
create or replace function public.crm_assign_request_business_unit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.business_unit_id is not null then
    return new;
  end if;

  new.business_unit_id := public.crm_request_business_unit_id();
  if new.business_unit_id is null
     and tg_table_name = 'crm_leads'
     and lower(coalesce(to_jsonb(new)->>'source_channel', ''))
       in ('ops quotation', 'ops_quotation', 'ops quotations') then
    select unit.id
    into new.business_unit_id
    from public.crm_business_units unit
    where unit.slug = 'cdm'
      and unit.active
    limit 1;
  end if;
  if new.business_unit_id is null and auth.uid() is not null then
    select membership.business_unit_id
    into new.business_unit_id
    from public.crm_business_unit_memberships membership
    where membership.user_id = auth.uid()
      and membership.active
    order by membership.is_default desc, membership.created_at
    limit 1;
  end if;
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array[
    'crm_accounts','crm_leads','crm_contacts','crm_opportunities','crm_campaigns',
    'crm_email_settings','crm_message_templates','crm_assignment_rules',
    'crm_source_routes','crm_source_field_mappings','crm_messaging_providers',
    'crm_product_interests','crm_programs','crm_whatsapp_templates',
    'crm_webhook_inbox'
  ] loop
    execute format(
      'drop trigger if exists trg_%I_assign_request_business_unit on public.%I',
      table_name, table_name
    );
    execute format(
      'create trigger trg_%I_assign_request_business_unit before insert on public.%I for each row execute procedure public.crm_assign_request_business_unit()',
      table_name, table_name
    );
  end loop;
end $$;

-- Safe email-settings projection.  The application writes Fernet ciphertext
-- using CRM_SECRET_ENCRYPTION_KEY; plaintext remains readable only by service role
-- until the rotated credential is saved once through the new endpoint.
create or replace view public.crm_email_settings_safe
with (security_barrier = true)
as
select
  id,
  user_id,
  business_unit_id,
  provider,
  from_name,
  from_address,
  smtp_host,
  smtp_port,
  use_tls,
  username,
  auto_bcc,
  (password_encrypted is not null or password is not null) as has_password,
  password_key_version,
  secret_migrated_at,
  created_at,
  updated_at
from public.crm_email_settings setting
where setting.user_id = auth.uid()
   or public.crm_has_business_unit_access(
        setting.business_unit_id,
        array['admin', 'manager']::text[]
      );

revoke all on public.crm_email_settings from anon, authenticated;
grant select, insert, update, delete on public.crm_email_settings to service_role;
grant select on public.crm_email_settings_safe to authenticated, service_role;

-- Private opportunity documents.  Object names must start with the business-unit UUID.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'crm-opportunity-documents',
  'crm-opportunity-documents',
  false,
  20971520,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.crm_storage_business_unit_id(p_object_name text)
returns uuid
language sql
immutable
set search_path = public, storage, pg_temp
as $$
  select public.crm_try_uuid((storage.foldername(p_object_name))[1]);
$$;

create or replace function public.crm_storage_opportunity_id(p_object_name text)
returns uuid
language sql
immutable
set search_path = public, storage, pg_temp
as $$
  select case
    when (storage.foldername(p_object_name))[2] = 'opportunities'
      then public.crm_try_uuid((storage.foldername(p_object_name))[3])
    else null
  end;
$$;

drop policy if exists "crm_opportunity_documents_select" on storage.objects;
create policy "crm_opportunity_documents_select" on storage.objects
for select to authenticated
using (
  bucket_id = 'crm-opportunity-documents'
  and public.crm_has_business_unit_access(public.crm_storage_business_unit_id(name))
);

drop policy if exists "crm_opportunity_documents_insert" on storage.objects;
create policy "crm_opportunity_documents_insert" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'crm-opportunity-documents'
  and public.crm_can_edit_opportunity_child(
    public.crm_storage_business_unit_id(name),
    public.crm_storage_opportunity_id(name)
  )
);

drop policy if exists "crm_opportunity_documents_update" on storage.objects;
create policy "crm_opportunity_documents_update" on storage.objects
for update to authenticated
using (
  bucket_id = 'crm-opportunity-documents'
  and public.crm_can_edit_opportunity_child(
    public.crm_storage_business_unit_id(name),
    public.crm_storage_opportunity_id(name)
  )
)
with check (
  bucket_id = 'crm-opportunity-documents'
  and public.crm_can_edit_opportunity_child(
    public.crm_storage_business_unit_id(name),
    public.crm_storage_opportunity_id(name)
  )
);

drop policy if exists "crm_opportunity_documents_delete" on storage.objects;
create policy "crm_opportunity_documents_delete" on storage.objects
for delete to authenticated
using (
  bucket_id = 'crm-opportunity-documents'
  and public.crm_can_edit_opportunity_child(
    public.crm_storage_business_unit_id(name),
    public.crm_storage_opportunity_id(name)
  )
);

-- Remove all legacy CRM policies before installing tenant-aware policies.  This
-- deliberately excludes non-CRM/OPS tables and storage policies defined above.
do $$
declare
  policy_record record;
begin
  for policy_record in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = any(array[
        'crm_accounts','crm_contacts','crm_opportunities','crm_opportunity_contacts',
        'crm_activities','crm_activity_tasks','crm_activity_log','crm_campaigns',
        'crm_campaign_members','crm_leads','crm_lead_events','crm_conversations',
        'crm_conversation_messages','crm_email_messages','crm_message_templates',
        'crm_assignment_rules','crm_source_routes','crm_source_field_mappings',
        'crm_messaging_providers','crm_product_interests','crm_programs',
        'crm_whatsapp_templates','crm_webhook_inbox','ops_quotations','ops_quotation_items',
        'ops_orders'
      ])
  loop
    execute format('drop policy %I on %I.%I', policy_record.policyname, policy_record.schemaname, policy_record.tablename);
  end loop;
end $$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'crm_business_units','crm_business_unit_memberships','crm_business_unit_assignment_queue',
    'crm_legacy_account_business_units',
    'crm_accounts','crm_contacts','crm_opportunities','crm_opportunity_contacts',
    'crm_activities','crm_activity_tasks','crm_activity_log','crm_campaigns',
    'crm_campaign_members','crm_leads','crm_lead_events','crm_conversations',
    'crm_conversation_messages','crm_email_settings','crm_email_messages',
    'crm_message_templates','crm_assignment_rules','crm_source_routes',
    'crm_source_field_mappings','crm_messaging_providers','crm_product_interests',
    'crm_programs','crm_whatsapp_templates','crm_webhook_inbox','ops_quotations',
    'ops_quotation_items','ops_orders'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
  end loop;
end $$;

drop policy if exists crm_business_units_select on public.crm_business_units;
create policy crm_business_units_select on public.crm_business_units
for select to authenticated
using (public.crm_has_business_unit_access(id));

drop policy if exists crm_business_units_manage on public.crm_business_units;
create policy crm_business_units_manage on public.crm_business_units
for update to authenticated
using (public.crm_has_business_unit_access(id, array['admin']::text[]))
with check (public.crm_has_business_unit_access(id, array['admin']::text[]));

drop policy if exists crm_business_unit_memberships_select on public.crm_business_unit_memberships;
create policy crm_business_unit_memberships_select on public.crm_business_unit_memberships
for select to authenticated
using (
  user_id = auth.uid()
  or public.crm_has_business_unit_access(business_unit_id, array['admin', 'manager']::text[])
);

drop policy if exists crm_business_unit_memberships_manage on public.crm_business_unit_memberships;
create policy crm_business_unit_memberships_manage on public.crm_business_unit_memberships
for all to authenticated
using (public.crm_has_business_unit_access(business_unit_id, array['admin']::text[]))
with check (public.crm_has_business_unit_access(business_unit_id, array['admin']::text[]));

drop policy if exists crm_business_unit_assignment_queue_select on public.crm_business_unit_assignment_queue;
create policy crm_business_unit_assignment_queue_select on public.crm_business_unit_assignment_queue
for select to authenticated using (public.crm_is_any_business_admin());
drop policy if exists crm_business_unit_assignment_queue_update on public.crm_business_unit_assignment_queue;
-- Queue decisions must go through crm_resolve_business_unit_assignment(),
-- which changes the source record and audit row atomically. No authenticated
-- role may update the queue table directly.

-- Core records: company-wide read; admin/manager or the owning sales rep may write.
drop policy if exists crm_accounts_select on public.crm_accounts;
create policy crm_accounts_select on public.crm_accounts for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_accounts_write on public.crm_accounts;
create policy crm_accounts_write on public.crm_accounts for all to authenticated
using (public.crm_can_edit_business_record(business_unit_id, owner_user_id))
with check (public.crm_can_edit_business_record(business_unit_id, owner_user_id));

drop policy if exists crm_contacts_select on public.crm_contacts;
create policy crm_contacts_select on public.crm_contacts for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_contacts_write on public.crm_contacts;
create policy crm_contacts_write on public.crm_contacts for all to authenticated
using (public.crm_can_edit_business_record(business_unit_id, owner_user_id))
with check (public.crm_can_edit_business_record(business_unit_id, owner_user_id));

drop policy if exists crm_opportunities_select on public.crm_opportunities;
create policy crm_opportunities_select on public.crm_opportunities for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_opportunities_write on public.crm_opportunities;
create policy crm_opportunities_write on public.crm_opportunities for all to authenticated
using (public.crm_can_edit_business_record(business_unit_id, owner_user_id))
with check (public.crm_can_edit_business_record(business_unit_id, owner_user_id));

drop policy if exists crm_leads_select on public.crm_leads;
create policy crm_leads_select on public.crm_leads for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_leads_write on public.crm_leads;
create policy crm_leads_write on public.crm_leads for all to authenticated
using (public.crm_can_edit_business_record(business_unit_id, coalesce(owner_user_id, assigned_user_id), true))
with check (public.crm_can_edit_business_record(business_unit_id, coalesce(owner_user_id, assigned_user_id), true));

drop policy if exists crm_campaigns_select on public.crm_campaigns;
create policy crm_campaigns_select on public.crm_campaigns for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_campaigns_write on public.crm_campaigns;
create policy crm_campaigns_write on public.crm_campaigns for all to authenticated
using (public.crm_can_edit_business_record(business_unit_id, owner_user_id, true))
with check (public.crm_can_edit_business_record(business_unit_id, owner_user_id, true));

-- Opportunity children honour the opportunity owner, not merely tenant membership.
drop policy if exists crm_opportunity_contacts_select on public.crm_opportunity_contacts;
create policy crm_opportunity_contacts_select on public.crm_opportunity_contacts
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_opportunity_contacts_write on public.crm_opportunity_contacts;
create policy crm_opportunity_contacts_write on public.crm_opportunity_contacts
for all to authenticated
using (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id))
with check (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id));

drop policy if exists crm_activities_select on public.crm_activities;
create policy crm_activities_select on public.crm_activities
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_activities_write on public.crm_activities;
create policy crm_activities_write on public.crm_activities
for all to authenticated
using (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id))
with check (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id));

drop policy if exists crm_activity_tasks_select on public.crm_activity_tasks;
create policy crm_activity_tasks_select on public.crm_activity_tasks
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_activity_tasks_write on public.crm_activity_tasks;
create policy crm_activity_tasks_write on public.crm_activity_tasks
for all to authenticated
using (
  exists (
    select 1 from public.crm_activities activity
    where activity.id = activity_id
      and public.crm_can_edit_opportunity_child(business_unit_id, activity.opportunity_id)
  )
)
with check (
  exists (
    select 1 from public.crm_activities activity
    where activity.id = activity_id
      and public.crm_can_edit_opportunity_child(business_unit_id, activity.opportunity_id)
  )
);

drop policy if exists crm_activity_log_select on public.crm_activity_log;
create policy crm_activity_log_select on public.crm_activity_log
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_activity_log_write on public.crm_activity_log;
create policy crm_activity_log_write on public.crm_activity_log
for all to authenticated
using (
  case when opportunity_id is not null
    then public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id)
    else public.crm_can_edit_business_record(business_unit_id, created_by)
  end
)
with check (
  case when opportunity_id is not null
    then public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id)
    else public.crm_can_edit_business_record(business_unit_id, created_by)
  end
);

-- Lead children remain editable by Marketing and by the owning/unassigned rep.
drop policy if exists crm_lead_events_select on public.crm_lead_events;
create policy crm_lead_events_select on public.crm_lead_events
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_lead_events_write on public.crm_lead_events;
create policy crm_lead_events_write on public.crm_lead_events
for all to authenticated
using (public.crm_can_edit_lead_child(business_unit_id, lead_id))
with check (public.crm_can_edit_lead_child(business_unit_id, lead_id));

drop policy if exists crm_conversations_select on public.crm_conversations;
create policy crm_conversations_select on public.crm_conversations
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_conversations_write on public.crm_conversations;
create policy crm_conversations_write on public.crm_conversations
for all to authenticated
using (public.crm_can_edit_lead_child(business_unit_id, lead_id))
with check (public.crm_can_edit_lead_child(business_unit_id, lead_id));

drop policy if exists crm_conversation_messages_select on public.crm_conversation_messages;
create policy crm_conversation_messages_select on public.crm_conversation_messages
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_conversation_messages_write on public.crm_conversation_messages;
create policy crm_conversation_messages_write on public.crm_conversation_messages
for all to authenticated
using (
  exists (
    select 1 from public.crm_conversations conversation
    where conversation.id = conversation_id
      and public.crm_can_edit_lead_child(business_unit_id, conversation.lead_id)
  )
)
with check (
  exists (
    select 1 from public.crm_conversations conversation
    where conversation.id = conversation_id
      and public.crm_can_edit_lead_child(business_unit_id, conversation.lead_id)
  )
);

drop policy if exists crm_campaign_members_select on public.crm_campaign_members;
create policy crm_campaign_members_select on public.crm_campaign_members
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_campaign_members_write on public.crm_campaign_members;
create policy crm_campaign_members_write on public.crm_campaign_members
for all to authenticated
using (public.crm_can_edit_campaign_child(business_unit_id, campaign_id))
with check (public.crm_can_edit_campaign_child(business_unit_id, campaign_id));

drop policy if exists crm_email_messages_select on public.crm_email_messages;
create policy crm_email_messages_select on public.crm_email_messages
for select to authenticated using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_email_messages_write on public.crm_email_messages;
create policy crm_email_messages_write on public.crm_email_messages
for all to authenticated
using (
  case when opportunity_id is not null
    then public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id)
    else public.crm_can_edit_business_record(business_unit_id, created_by)
  end
)
with check (
  case when opportunity_id is not null
    then public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id)
    else public.crm_can_edit_business_record(business_unit_id, created_by)
  end
);

-- Catalog/configuration writes are limited to managers and Marketing.  Reps can
-- consume them but cannot change routing, providers or shared templates.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'crm_message_templates','crm_assignment_rules','crm_source_routes',
    'crm_source_field_mappings','crm_messaging_providers','crm_product_interests',
    'crm_programs','crm_whatsapp_templates','crm_webhook_inbox'
  ] loop
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.crm_has_business_unit_access(business_unit_id))',
      table_name || '_select', table_name
    );
    execute format(
      'create policy %I on public.%I for all to authenticated using (public.crm_has_business_unit_access(business_unit_id, array[''admin'',''manager'',''marketing'']::text[])) with check (public.crm_has_business_unit_access(business_unit_id, array[''admin'',''manager'',''marketing'']::text[]))',
      table_name || '_write', table_name
    );
  end loop;
end $$;

drop policy if exists ops_quotations_select on public.ops_quotations;
create policy ops_quotations_select on public.ops_quotations for select to authenticated
using (
  public.crm_has_business_unit_access(business_unit_id)
  or public.crm_has_ops_business_unit_access(business_unit_id)
);
drop policy if exists ops_quotations_write on public.ops_quotations;
create policy ops_quotations_write on public.ops_quotations for all to authenticated
using (public.crm_has_ops_business_unit_access(business_unit_id, array['admin','manager','sales_rep']::text[]))
with check (public.crm_has_ops_business_unit_access(business_unit_id, array['admin','manager','sales_rep']::text[]));

drop policy if exists ops_quotation_items_select on public.ops_quotation_items;
create policy ops_quotation_items_select on public.ops_quotation_items for select to authenticated
using (
  exists (
    select 1 from public.ops_quotations quotation
    where quotation.id = quotation_id
      and (
        public.crm_has_business_unit_access(quotation.business_unit_id)
        or public.crm_has_ops_business_unit_access(quotation.business_unit_id)
      )
  )
);
drop policy if exists ops_quotation_items_write on public.ops_quotation_items;
create policy ops_quotation_items_write on public.ops_quotation_items for all to authenticated
using (
  exists (
    select 1 from public.ops_quotations quotation
    where quotation.id = quotation_id
      and public.crm_has_ops_business_unit_access(
        quotation.business_unit_id,
        array['admin','manager','sales_rep']::text[]
      )
  )
)
with check (
  exists (
    select 1 from public.ops_quotations quotation
    where quotation.id = quotation_id
      and public.crm_has_ops_business_unit_access(
        quotation.business_unit_id,
        array['admin','manager','sales_rep']::text[]
      )
  )
);

drop policy if exists ops_orders_select on public.ops_orders;
create policy ops_orders_select on public.ops_orders for select to authenticated
using (
  public.crm_has_business_unit_access(business_unit_id)
  or public.crm_has_ops_business_unit_access(business_unit_id)
);
drop policy if exists ops_orders_write on public.ops_orders;
create policy ops_orders_write on public.ops_orders for all to authenticated
using (public.crm_has_ops_business_unit_access(business_unit_id, array['admin','manager','sales_rep']::text[]))
with check (public.crm_has_ops_business_unit_access(business_unit_id, array['admin','manager','sales_rep']::text[]));

grant usage on schema public to authenticated;
grant select on public.crm_business_units, public.crm_business_unit_memberships,
  public.crm_business_unit_assignment_queue to authenticated;
revoke insert, update, delete on public.crm_business_unit_assignment_queue from authenticated;
grant select, insert, update, delete on public.crm_accounts, public.crm_contacts,
  public.crm_opportunities, public.crm_opportunity_contacts, public.crm_activities,
  public.crm_activity_tasks, public.crm_activity_log, public.crm_campaigns,
  public.crm_campaign_members, public.crm_leads, public.crm_lead_events,
  public.crm_conversations, public.crm_conversation_messages,
  public.crm_email_messages, public.crm_message_templates, public.crm_assignment_rules,
  public.crm_source_routes, public.crm_source_field_mappings,
  public.crm_messaging_providers, public.crm_product_interests, public.crm_programs,
  public.crm_whatsapp_templates, public.crm_webhook_inbox,
  public.ops_quotations, public.ops_quotation_items, public.ops_orders to authenticated;

-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default.  Keep the
-- tenant predicates callable by authenticated sessions and the service role,
-- but do not expose SECURITY DEFINER helpers or trigger functions to anon.
revoke all on function public.crm_set_updated_at() from public;
revoke all on function public.crm_request_business_unit_id() from public;
revoke all on function public.crm_has_business_unit_access(uuid, text[]) from public;
revoke all on function public.crm_has_ops_business_unit_access(uuid, text[]) from public;
revoke all on function public.crm_is_any_business_admin() from public;
revoke all on function public.crm_can_edit_business_record(uuid, uuid, boolean) from public;
revoke all on function public.crm_can_edit_opportunity_child(uuid, uuid) from public;
revoke all on function public.crm_can_edit_lead_child(uuid, uuid) from public;
revoke all on function public.crm_can_edit_campaign_child(uuid, uuid) from public;
revoke all on function public.crm_try_uuid(text) from public;
revoke all on function public.crm_default_ops_business_unit() from public;
revoke all on function public.crm_inherit_business_unit() from public;
revoke all on function public.crm_assign_request_business_unit() from public;
revoke all on function public.crm_storage_business_unit_id(text) from public;
revoke all on function public.crm_storage_opportunity_id(text) from public;

grant execute on function public.crm_request_business_unit_id()
  to authenticated, service_role;
grant execute on function public.crm_has_business_unit_access(uuid, text[])
  to authenticated, service_role;
grant execute on function public.crm_has_ops_business_unit_access(uuid, text[])
  to authenticated, service_role;
grant execute on function public.crm_is_any_business_admin()
  to authenticated, service_role;
grant execute on function public.crm_can_edit_business_record(uuid, uuid, boolean)
  to authenticated, service_role;
grant execute on function public.crm_can_edit_opportunity_child(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.crm_can_edit_lead_child(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.crm_can_edit_campaign_child(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.crm_try_uuid(text)
  to authenticated, service_role;
grant execute on function public.crm_storage_business_unit_id(text)
  to authenticated, service_role;
grant execute on function public.crm_storage_opportunity_id(text)
  to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
