-- OPS Google Calendar: one order per occurrence, manual execution, fenced sync.
-- This migration deliberately does not register another scheduler. The backend
-- repeat_every worker is the only synchronizer; enable it after OAuth setup.
begin;

alter table public.ops_order_types add column if not exists code text;
create unique index if not exists uq_ops_order_types_code
  on public.ops_order_types(code) where code is not null;
insert into public.ops_order_types (id, name, code)
values (gen_random_uuid(), 'Google Calendar', 'google_calendar')
on conflict (code) where code is not null do nothing;

create table if not exists public.ops_calendar_connections (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id),
  user_id uuid not null references auth.users(id),
  google_email text not null,
  google_subject text,
  encrypted_refresh_token text not null,
  scopes text[] not null default '{}',
  active boolean not null default true,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id, business_unit_id)
);
alter table public.ops_calendar_connections add column if not exists google_subject text;
create unique index if not exists uq_ops_calendar_connections_google_subject
  on public.ops_calendar_connections(business_unit_id, google_subject)
  where google_subject is not null;

create table if not exists public.ops_calendar_oauth_states (
  state_hash text primary key,
  user_id uuid not null references auth.users(id),
  business_unit_id uuid not null references public.crm_business_units(id),
  encrypted_code_verifier text not null,
  redirect_uri text not null,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.ops_calendar_calendars (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id),
  connection_id uuid not null,
  calendar_id text not null check (length(btrim(calendar_id)) > 0),
  calendar_name text not null,
  assignee_id uuid not null references public.ops_assignees(id),
  enabled boolean not null default true,
  horizon_past_days integer not null default 30 check (horizon_past_days between 0 and 365),
  horizon_future_days integer not null default 90 check (horizon_future_days between 1 and 366),
  sync_token text,
  last_synced_at timestamptz,
  last_error text,
  lease_token uuid,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(business_unit_id, calendar_id),
  unique(id, business_unit_id),
  foreign key (connection_id, business_unit_id)
    references public.ops_calendar_connections(id, business_unit_id)
);

create table if not exists public.ops_calendar_event_cache (
  calendar_mapping_id uuid not null references public.ops_calendar_calendars(id) on delete cascade,
  event_id text not null,
  payload jsonb not null default '{}',
  is_master boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key(calendar_mapping_id, event_id)
);

alter table public.ops_orders
  add column if not exists origin text not null default 'traditional',
  add column if not exists calendar_mapping_id uuid,
  add column if not exists calendar_event_id text,
  add column if not exists calendar_recurring_event_id text,
  add column if not exists calendar_original_start_key text,
  add column if not exists calendar_ical_uid text,
  add column if not exists calendar_transferred_from_order_id uuid references public.ops_orders(id),
  add column if not exists calendar_external_status text,
  add column if not exists calendar_event_etag text,
  add column if not exists calendar_event_url text,
  add column if not exists scheduled_start timestamptz,
  add column if not exists scheduled_end timestamptz,
  add column if not exists calendar_all_day boolean not null default false,
  add column if not exists calendar_start_date date,
  add column if not exists calendar_end_date date,
  add column if not exists execution_started_at timestamptz,
  add column if not exists execution_started_by uuid references auth.users(id),
  add column if not exists execution_completed_at timestamptz,
  add column if not exists execution_completed_by uuid references auth.users(id),
  add column if not exists execution_note text,
  add column if not exists publish_pending boolean not null default false,
  add column if not exists publish_revision bigint not null default 0,
  add column if not exists last_publish_error text;

alter table public.ops_orders drop constraint if exists ops_orders_calendar_mapping_company_fkey;
alter table public.ops_orders add constraint ops_orders_calendar_mapping_company_fkey
  foreign key (calendar_mapping_id, business_unit_id)
  references public.ops_calendar_calendars(id, business_unit_id);
alter table public.ops_orders drop constraint if exists ops_orders_origin_check;
alter table public.ops_orders add constraint ops_orders_origin_check
  check (origin in ('traditional', 'google_calendar'));
alter table public.ops_orders drop constraint if exists ops_orders_billing_status_check;
alter table public.ops_orders add constraint ops_orders_billing_status_check
  check (billing_status in ('pending', 'pending_monthly_invoice', 'staged_for_period', 'invoiced', 'not_applicable'));
alter table public.ops_orders drop constraint if exists ops_orders_calendar_schedule_check;
alter table public.ops_orders add constraint ops_orders_calendar_schedule_check check (
  origin <> 'google_calendar' or (
    business_unit_id is not null and calendar_mapping_id is not null
    and calendar_event_id is not null and assignee_id is not null
    and billing_status = 'not_applicable' and billing_invoice_id is null
    and contract_id is null and contract_period_id is null
    and not is_custom_task_order
    and (
      (calendar_all_day and scheduled_start is null and scheduled_end is null
       and calendar_start_date is not null and calendar_end_date is not null and calendar_end_date > calendar_start_date
       and order_time is null and delivery_time is null)
      or (not calendar_all_day and scheduled_start is not null and scheduled_end is not null and scheduled_end > scheduled_start
          and calendar_start_date is null and calendar_end_date is null)
    )
  )
);
create unique index if not exists uq_ops_orders_calendar_event
  on public.ops_orders(business_unit_id, calendar_mapping_id, calendar_event_id)
  where origin = 'google_calendar';
create unique index if not exists uq_ops_orders_calendar_occurrence
  on public.ops_orders(business_unit_id, calendar_mapping_id, calendar_recurring_event_id, calendar_original_start_key)
  where origin = 'google_calendar' and calendar_recurring_event_id is not null
    and calendar_original_start_key is not null;
create index if not exists idx_ops_orders_calendar_agenda
  on public.ops_orders(business_unit_id, order_date, assignee_id)
  where origin = 'google_calendar';
create index if not exists idx_ops_orders_calendar_publish
  on public.ops_orders(calendar_mapping_id) where publish_pending;

create table if not exists public.ops_calendar_history (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id),
  order_id uuid not null references public.ops_orders(id) on delete restrict,
  event_type text not null,
  user_id uuid references auth.users(id),
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

-- auth.uid() is never substituted from a client-supplied body. The explicit user
-- argument is only used by service-only action RPCs after API authentication.
create or replace function public.ops_calendar_user_access(
  p_user_id uuid, p_business_unit_id uuid, p_assignee_id uuid default null,
  p_manage boolean default false, p_act boolean default false
) returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select p_user_id is not null and exists (
    select 1 from public.crm_business_unit_memberships m
    join public.crm_business_units b on b.id = m.business_unit_id
    where m.user_id = p_user_id and m.business_unit_id = p_business_unit_id
      and m.active and b.active
      and (not exists (select 1 from public.app_user_modules a where a.user_id = p_user_id)
           or exists (select 1 from public.app_user_modules a where a.user_id = p_user_id
                      and lower(btrim(a.module_key)) = 'ops'))
      and (
        m.role in ('admin', 'manager')
        or (not p_manage and exists (
          select 1 from public.ops_inbox_user_permissions p
          where p.user_id = p_user_id and p.active and (
            (p.access_level = 'assignee' and p.assignee_id = p_assignee_id)
            or (p.access_level = 'all' and not p_act)
          )
        ))
      )
  );
$$;

create or replace function public.ops_calendar_can_read(p_business_unit_id uuid, p_assignee_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select (public.crm_request_business_unit_id() is null
          or public.crm_request_business_unit_id() = p_business_unit_id)
    and public.ops_calendar_user_access(auth.uid(), p_business_unit_id, p_assignee_id);
$$;
create or replace function public.ops_calendar_is_admin(p_business_unit_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select (public.crm_request_business_unit_id() is null
          or public.crm_request_business_unit_id() = p_business_unit_id)
    and public.ops_calendar_user_access(auth.uid(), p_business_unit_id, null, true);
$$;

-- Restrictive policies prevent existing permissive OPS/Sales policies from
-- exposing Calendar assignments or bypassing the explicit start/complete API.
drop policy if exists ops_calendar_orders_read_scope on public.ops_orders;
create policy ops_calendar_orders_read_scope on public.ops_orders as restrictive
for select to authenticated using (
  origin <> 'google_calendar' or public.ops_calendar_can_read(business_unit_id, assignee_id)
);
drop policy if exists ops_calendar_orders_select on public.ops_orders;
create policy ops_calendar_orders_select on public.ops_orders for select to authenticated
using (origin = 'google_calendar' and public.ops_calendar_can_read(business_unit_id, assignee_id));
drop policy if exists ops_calendar_orders_insert_guard on public.ops_orders;
create policy ops_calendar_orders_insert_guard on public.ops_orders as restrictive
for insert to authenticated with check (origin <> 'google_calendar');
drop policy if exists ops_calendar_orders_update_guard on public.ops_orders;
create policy ops_calendar_orders_update_guard on public.ops_orders as restrictive
for update to authenticated using (origin <> 'google_calendar') with check (origin <> 'google_calendar');
drop policy if exists ops_calendar_orders_delete_guard on public.ops_orders;
create policy ops_calendar_orders_delete_guard on public.ops_orders as restrictive
for delete to authenticated using (origin <> 'google_calendar');

alter table public.ops_calendar_connections enable row level security;
alter table public.ops_calendar_oauth_states enable row level security;
alter table public.ops_calendar_calendars enable row level security;
alter table public.ops_calendar_event_cache enable row level security;
alter table public.ops_calendar_history enable row level security;
drop policy if exists ops_calendar_connections_select on public.ops_calendar_connections;
create policy ops_calendar_connections_select on public.ops_calendar_connections for select to authenticated
using (public.ops_calendar_is_admin(business_unit_id));
drop policy if exists ops_calendar_calendars_select on public.ops_calendar_calendars;
create policy ops_calendar_calendars_select on public.ops_calendar_calendars for select to authenticated
using (public.ops_calendar_can_read(business_unit_id, assignee_id));
drop policy if exists ops_calendar_history_select on public.ops_calendar_history;
create policy ops_calendar_history_select on public.ops_calendar_history for select to authenticated
using (exists (select 1 from public.ops_orders o where o.id = order_id
               and public.ops_calendar_can_read(o.business_unit_id, o.assignee_id)));
revoke all on public.ops_calendar_connections, public.ops_calendar_oauth_states,
  public.ops_calendar_calendars, public.ops_calendar_event_cache, public.ops_calendar_history
  from anon, authenticated;
grant select (id, business_unit_id, user_id, google_email, google_subject, scopes, active, last_error, created_at, updated_at)
  on public.ops_calendar_connections to authenticated;
grant select on public.ops_calendar_calendars, public.ops_calendar_history to authenticated;
grant all on public.ops_calendar_connections, public.ops_calendar_oauth_states,
  public.ops_calendar_calendars, public.ops_calendar_event_cache, public.ops_calendar_history to service_role;

create or replace function public.ops_calendar_guard_order()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op <> 'INSERT' and old.origin = 'google_calendar' then
    if tg_op = 'DELETE' then raise exception 'Calendar orders retain execution history; cancel externally instead'; end if;
    if current_setting('ops.calendar_write', true) is distinct from 'on' then
      raise exception 'Calendar orders may only be changed through Calendar RPCs';
    end if;
    if new.origin <> old.origin or new.business_unit_id <> old.business_unit_id
       or new.calendar_mapping_id <> old.calendar_mapping_id then
      raise exception 'Calendar order identity is immutable';
    end if;
    if new.calendar_event_id is distinct from old.calendar_event_id and not (
      old.calendar_recurring_event_id is not null and old.calendar_original_start_key is not null
      and new.calendar_recurring_event_id = old.calendar_recurring_event_id
      and new.calendar_original_start_key = old.calendar_original_start_key
    ) then raise exception 'Only the same recurring occurrence may change Google event ID'; end if;
  end if;
  if tg_op <> 'DELETE' and (
    new.origin = 'google_calendar' or exists (
      select 1 from public.ops_order_types t where t.id = new.order_type_id and t.code = 'google_calendar'
    )
  ) then
    if current_setting('ops.calendar_write', true) is distinct from 'on'
       or new.origin <> 'google_calendar' or new.calendar_mapping_id is null then
      raise exception 'Google Calendar orders must be imported by the Calendar synchronizer';
    end if;
    if not exists (select 1 from public.ops_order_types t where t.id = new.order_type_id and t.code = 'google_calendar') then
      raise exception 'Invalid Google Calendar order type';
    end if;
    if exists (select 1 from public.ops_order_tasks t where t.order_id = new.id) then
      raise exception 'Google Calendar orders cannot contain checklist tasks';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists trg_ops_calendar_guard_order on public.ops_orders;
create trigger trg_ops_calendar_guard_order before insert or update or delete on public.ops_orders
for each row execute function public.ops_calendar_guard_order();

create or replace function public.ops_calendar_guard_checklist()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_table_name = 'ops_order_tasks' then
    if exists (select 1 from public.ops_orders o where o.id = new.order_id and o.origin = 'google_calendar') then
      raise exception 'Google Calendar activities have no checklist';
    end if;
  elsif exists (select 1 from public.ops_order_types t where t.id = new.order_type_id and t.code = 'google_calendar') then
    raise exception 'Google Calendar order type has no templates';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_ops_calendar_guard_tasks on public.ops_order_tasks;
create trigger trg_ops_calendar_guard_tasks before insert or update on public.ops_order_tasks
for each row execute function public.ops_calendar_guard_checklist();
drop trigger if exists trg_ops_calendar_guard_templates on public.ops_task_templates;
create trigger trg_ops_calendar_guard_templates before insert or update on public.ops_task_templates
for each row execute function public.ops_calendar_guard_checklist();

create or replace function public.ops_calendar_guard_type()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if old.code = 'google_calendar' then
    if tg_op = 'DELETE' then raise exception 'Google Calendar is a system order type'; end if;
    if new.code is distinct from old.code or new.name is distinct from old.name then
      raise exception 'Google Calendar is a system order type';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists trg_ops_calendar_guard_type on public.ops_order_types;
create trigger trg_ops_calendar_guard_type before update or delete on public.ops_order_types
for each row execute function public.ops_calendar_guard_type();

create or replace function public.ops_calendar_history_immutable()
returns trigger language plpgsql as $$
begin raise exception 'Calendar history is append-only'; end;
$$;
drop trigger if exists trg_ops_calendar_history_immutable on public.ops_calendar_history;
create trigger trg_ops_calendar_history_immutable before update or delete on public.ops_calendar_history
for each row execute function public.ops_calendar_history_immutable();

-- Lease generation is the fencing token. A stale worker cannot renew, import,
-- acknowledge publications or release a newer worker's lease.
create or replace function public.ops_calendar_acquire_lease(p_mapping_id uuid, p_lease_seconds integer default 120)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare result uuid;
begin
  update public.ops_calendar_calendars c
  set lease_token = gen_random_uuid(), lease_until = clock_timestamp() + make_interval(secs => least(600, greatest(30, p_lease_seconds)))
  where c.id = p_mapping_id and c.enabled
    and (c.lease_until is null or c.lease_until < clock_timestamp())
    and exists (select 1 from public.ops_calendar_connections k
                join public.crm_business_units b on b.id = k.business_unit_id
                where k.id = c.connection_id and k.active and b.active)
  returning lease_token into result;
  return result;
end;
$$;
create or replace function public.ops_calendar_renew_lease(p_mapping_id uuid, p_lease_token uuid, p_lease_seconds integer default 120)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.ops_calendar_calendars set lease_until = clock_timestamp() + make_interval(secs => least(600, greatest(30, p_lease_seconds)))
  where id = p_mapping_id and lease_token = p_lease_token and lease_until > clock_timestamp() and enabled;
  return found;
end;
$$;
create or replace function public.ops_calendar_release_lease(p_mapping_id uuid, p_lease_token uuid, p_error text default null)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.ops_calendar_calendars set lease_token = null, lease_until = null,
    last_error = left(p_error, 2000), updated_at = now()
  where id = p_mapping_id and lease_token = p_lease_token;
  return found;
end;
$$;

create or replace function public.ops_calendar_commit_sync(
  p_mapping_id uuid, p_lease_token uuid, p_events jsonb, p_sync_token text,
  p_sync_complete boolean default true, p_full_sync boolean default false,
  p_window_start date default null, p_window_end date default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  mapping public.ops_calendar_calendars%rowtype;
  old_order public.ops_orders%rowtype;
  new_order public.ops_orders%rowtype;
  item jsonb;
  type_id uuid;
  assignee_name text;
  prior_gate text := current_setting('ops.calendar_write', true);
  count_created integer := 0;
  count_updated integer := 0;
  external_status text;
  is_all_day boolean;
  starts timestamptz;
  ends timestamptz;
  date_start date;
  date_end date;
  transferred_from uuid;
  needs_publication boolean;
begin
  select * into mapping from public.ops_calendar_calendars where id = p_mapping_id for update;
  if not found or mapping.lease_token is distinct from p_lease_token
     or mapping.lease_until <= clock_timestamp() or not mapping.enabled then
    raise exception 'Calendar sync lease expired or superseded';
  end if;
  if jsonb_typeof(p_events) <> 'array' then raise exception 'Events must be an array'; end if;
  select id into strict type_id from public.ops_order_types where code = 'google_calendar';
  select name into strict assignee_name from public.ops_assignees where id = mapping.assignee_id and active;
  perform set_config('ops.calendar_write', 'on', true);

  for item in select value from jsonb_array_elements(p_events) loop
    if nullif(item->>'event_id', '') is null then raise exception 'Missing Google event ID'; end if;
    external_status := coalesce(item->>'google_status', item->'raw_event'->>'status', 'confirmed');
    if external_status not in ('confirmed', 'tentative', 'cancelled') then raise exception 'Invalid Google event status'; end if;
    insert into public.ops_calendar_event_cache (calendar_mapping_id, event_id, payload, is_master)
    values (mapping.id, item->>'event_id', coalesce(item->'raw_event', '{}'), coalesce((item->>'is_master')::boolean, false))
    on conflict (calendar_mapping_id, event_id) do update set payload = excluded.payload,
      is_master = excluded.is_master, updated_at = now();

    if coalesce((item->>'is_master')::boolean, false) then
      if external_status = 'cancelled' then
        for old_order in select * from public.ops_orders where calendar_mapping_id = mapping.id
          and calendar_recurring_event_id = item->>'event_id' and calendar_external_status <> 'cancelled' for update loop
          update public.ops_orders set calendar_external_status = 'cancelled', updated_at = now()
            where id = old_order.id returning * into new_order;
          insert into public.ops_calendar_history(business_unit_id, order_id, event_type, before_data, after_data)
          values (mapping.business_unit_id, old_order.id, 'series_cancelled', to_jsonb(old_order), to_jsonb(new_order));
          count_updated := count_updated + 1;
        end loop;
      end if;
      continue;
    end if;

    select * into old_order from public.ops_orders
      where business_unit_id = mapping.business_unit_id and calendar_mapping_id = mapping.id
        and (calendar_event_id = item->>'event_id' or (
          nullif(item->>'recurring_event_id', '') is not null
          and nullif(item->>'original_start_key', '') is not null
          and calendar_recurring_event_id = item->>'recurring_event_id'
          and calendar_original_start_key = item->>'original_start_key'
        )) for update;
    if external_status = 'cancelled' then
      if found and old_order.calendar_external_status is distinct from 'cancelled' then
        update public.ops_orders set calendar_external_status = 'cancelled',
          calendar_event_etag = coalesce(item->>'event_etag', calendar_event_etag), updated_at = now()
          where id = old_order.id returning * into new_order;
        insert into public.ops_calendar_history(business_unit_id, order_id, event_type, before_data, after_data)
        values (mapping.business_unit_id, old_order.id, 'event_cancelled', to_jsonb(old_order), to_jsonb(new_order));
        count_updated := count_updated + 1;
      end if;
      -- A cancellation tombstone is not a new activity and may lack dates.
      continue;
    end if;
    is_all_day := coalesce((item->>'all_day')::boolean, false);
    starts := nullif(item->>'scheduled_start', '')::timestamptz;
    ends := nullif(item->>'scheduled_end', '')::timestamptz;
    date_start := nullif(item->>'start_date', '')::date;
    date_end := nullif(item->>'end_date', '')::date;
    if (is_all_day and (date_start is null or date_end is null or date_end <= date_start or starts is not null or ends is not null))
       or (not is_all_day and (starts is null or ends is null or ends <= starts)) then
      raise exception 'Invalid or missing Calendar event schedule';
    end if;
    if old_order.id is null then
      transferred_from := null;
      -- Do not merge copied events or match by subject/company name. A move is
      -- only linked after its source cancellation and exact Google identity
      -- (including occurrence) are known; the original audit record survives.
      select min(id::text)::uuid into transferred_from from public.ops_orders o
      where o.business_unit_id = mapping.business_unit_id and o.origin = 'google_calendar'
        and o.calendar_mapping_id <> mapping.id and o.calendar_external_status = 'cancelled'
        and o.calendar_event_id = item->>'event_id'
        and o.calendar_ical_uid = item->'raw_event'->>'iCalUID'
        and o.calendar_original_start_key is not distinct from item->>'original_start_key'
      having count(*) = 1;
      insert into public.ops_orders (
        order_type_id, origin, business_unit_id, calendar_mapping_id, calendar_event_id,
        calendar_recurring_event_id, calendar_original_start_key, calendar_ical_uid,
        calendar_external_status, calendar_event_etag, calendar_event_url,
        subject, comments, assignee_id, assignee, scheduled_start, scheduled_end,
        calendar_all_day, calendar_start_date, calendar_end_date,
        order_date, order_time, delivery_date, delivery_time,
        status, billing_status, publish_pending, publish_revision, calendar_transferred_from_order_id
      ) values (
        type_id, 'google_calendar', mapping.business_unit_id, mapping.id, item->>'event_id',
        item->>'recurring_event_id', item->>'original_start_key', item->'raw_event'->>'iCalUID',
        external_status, item->>'event_etag', item->>'event_url',
        coalesce(nullif(item->>'subject', ''), '(Sin título)'), item->>'comments', mapping.assignee_id, assignee_name,
        case when is_all_day then null else starts end, case when is_all_day then null else ends end,
        is_all_day, case when is_all_day then date_start end, case when is_all_day then date_end end,
        case when is_all_day then date_start else (starts at time zone 'America/Lima')::date end,
        case when not is_all_day then (starts at time zone 'America/Lima')::time end,
        case when is_all_day then date_end else (ends at time zone 'America/Lima')::date end,
        case when not is_all_day then (ends at time zone 'America/Lima')::time end,
        'Pendiente', 'not_applicable', true, 1, transferred_from
      ) returning * into new_order;
      insert into public.ops_calendar_history(business_unit_id, order_id, event_type, after_data)
      values (mapping.business_unit_id, new_order.id, 'imported', to_jsonb(new_order));
      if transferred_from is not null then
        insert into public.ops_calendar_history(business_unit_id, order_id, event_type, after_data)
        values (mapping.business_unit_id, new_order.id, 'transferred_from_calendar',
                jsonb_build_object('source_order_id', transferred_from));
      end if;
      count_created := count_created + 1;
    else
      needs_publication :=
        old_order.subject is distinct from coalesce(nullif(item->>'subject', ''), '(Sin título)')
        or old_order.comments is distinct from item->>'comments'
        or (not old_order.publish_pending and (
          position('/ops/google-calendar/activities/' || old_order.id::text
                   in coalesce(item->'raw_event'->>'description', '')) = 0
          or item->'raw_event'->'extendedProperties'->'private'->>'nogamarksOrderId'
             is distinct from old_order.id::text
          or (old_order.execution_completed_at is not null and (
            coalesce(item->'raw_event'->>'summary', '') !~ '^✔[[:space:]]'
            or item->'raw_event'->'extendedProperties'->'private'->>'nogamarksCompleted'
               is distinct from 'true'
          ))
        ));
      update public.ops_orders set
        subject = coalesce(nullif(item->>'subject', ''), '(Sin título)'), comments = item->>'comments',
        assignee_id = case when execution_started_at is null and execution_completed_at is null then mapping.assignee_id else assignee_id end,
        assignee = case when execution_started_at is null and execution_completed_at is null then assignee_name else assignee end,
        scheduled_start = case when is_all_day then null else starts end,
        scheduled_end = case when is_all_day then null else ends end,
        calendar_all_day = is_all_day, calendar_start_date = case when is_all_day then date_start end,
        calendar_end_date = case when is_all_day then date_end end,
        order_date = case when is_all_day then date_start else (starts at time zone 'America/Lima')::date end,
        order_time = case when not is_all_day then (starts at time zone 'America/Lima')::time end,
        delivery_date = case when is_all_day then date_end else (ends at time zone 'America/Lima')::date end,
        delivery_time = case when not is_all_day then (ends at time zone 'America/Lima')::time end,
        calendar_event_id = item->>'event_id',
        calendar_external_status = external_status, calendar_event_etag = item->>'event_etag',
        calendar_event_url = item->>'event_url', calendar_recurring_event_id = item->>'recurring_event_id',
        calendar_original_start_key = item->>'original_start_key',
        calendar_ical_uid = coalesce(item->'raw_event'->>'iCalUID', calendar_ical_uid),
        publish_pending = publish_pending or needs_publication,
        publish_revision = publish_revision + case when needs_publication then 1 else 0 end,
        updated_at = now()
      where id = old_order.id returning * into new_order;
      -- ETags and audit timestamps alone do not constitute a business change.
      if (to_jsonb(old_order) - array['updated_at','calendar_event_etag'])
         is distinct from (to_jsonb(new_order) - array['updated_at','calendar_event_etag']) then
        insert into public.ops_calendar_history(business_unit_id, order_id, event_type, before_data, after_data)
        values (mapping.business_unit_id, new_order.id, 'event_updated', to_jsonb(old_order), to_jsonb(new_order));
        count_updated := count_updated + 1;
      end if;
    end if;
  end loop;

  -- Each successful run expands ALL cached series in a bounded window. Missing
  -- occurrences in that window have been removed/excluded from their series.
  -- Full resync additionally reconciles removed non-recurring events and masters.
  for old_order in select o.* from public.ops_orders o
    where p_sync_complete and o.calendar_mapping_id = mapping.id and o.calendar_external_status <> 'cancelled'
      and (
        (o.calendar_recurring_event_id is not null and p_window_start is not null and p_window_end is not null
         and o.order_date >= p_window_start and o.order_date < p_window_end)
        or (p_full_sync and o.calendar_recurring_event_id is null)
        or (p_full_sync and o.calendar_recurring_event_id is not null and not exists (
          select 1 from jsonb_array_elements(p_events) e
          where e->>'event_id' = o.calendar_recurring_event_id and coalesce((e->>'is_master')::boolean, false)
        ))
      )
      and not exists (select 1 from jsonb_array_elements(p_events) e where e->>'event_id' = o.calendar_event_id)
      for update loop
    update public.ops_orders set calendar_external_status = 'cancelled', updated_at = now()
      where id = old_order.id returning * into new_order;
    insert into public.ops_calendar_history(business_unit_id, order_id, event_type, before_data, after_data)
    values (mapping.business_unit_id, old_order.id, 'event_absent_in_resync', to_jsonb(old_order), to_jsonb(new_order));
    count_updated := count_updated + 1;
  end loop;
  if p_full_sync then
    delete from public.ops_calendar_event_cache c where c.calendar_mapping_id = mapping.id
      and not exists (select 1 from jsonb_array_elements(p_events) e where e->>'event_id' = c.event_id);
  end if;
  if p_sync_complete then
    update public.ops_calendar_calendars set sync_token = p_sync_token,
      last_synced_at = now(), last_error = null, updated_at = now() where id = mapping.id;
  end if;
  perform set_config('ops.calendar_write', coalesce(prior_gate, ''), true);
  return jsonb_build_object('created', count_created, 'updated', count_updated);
end;
$$;

create or replace function public.ops_calendar_act(
  p_order_id uuid, p_user_id uuid, p_action text, p_note text default null
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  old_order public.ops_orders%rowtype;
  new_order public.ops_orders%rowtype;
  prior_gate text := current_setting('ops.calendar_write', true);
begin
  select * into old_order from public.ops_orders where id = p_order_id and origin = 'google_calendar' for update;
  if not found or not public.ops_calendar_user_access(p_user_id, old_order.business_unit_id, old_order.assignee_id, false, true) then
    raise insufficient_privilege using message = 'No tienes permiso para actuar sobre esta actividad';
  end if;
  if p_action not in ('start', 'complete') then raise exception 'Acción no válida'; end if;
  if length(coalesce(p_note, '')) > 5000 then raise exception 'La nota excede 5000 caracteres'; end if;
  if old_order.execution_completed_at is not null
    or (p_action = 'start' and old_order.execution_started_at is not null) then
    return to_jsonb(old_order);
  end if;
  if old_order.calendar_external_status = 'cancelled' then raise exception 'El evento está cancelado en Google Calendar'; end if;
  perform set_config('ops.calendar_write', 'on', true);
  if p_action = 'start' then
    update public.ops_orders set execution_started_at = clock_timestamp(), execution_started_by = p_user_id,
      status = 'Procesando', updated_at = now() where id = old_order.id returning * into new_order;
  else
    update public.ops_orders set execution_completed_at = clock_timestamp(), execution_completed_by = p_user_id,
      execution_note = nullif(btrim(p_note), ''), status = 'Completado',
      publish_pending = true, publish_revision = publish_revision + 1,
      last_publish_error = null, updated_at = now()
      where id = old_order.id returning * into new_order;
  end if;
  insert into public.ops_calendar_history(business_unit_id, order_id, event_type, user_id, before_data, after_data)
  values (old_order.business_unit_id, old_order.id, p_action, p_user_id, to_jsonb(old_order), to_jsonb(new_order));
  perform set_config('ops.calendar_write', coalesce(prior_gate, ''), true);
  return to_jsonb(new_order);
end;
$$;

create or replace function public.ops_calendar_publish_ack(
  p_order_id uuid, p_lease_token uuid, p_expected_revision bigint, p_event_etag text
) returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare prior_gate text := current_setting('ops.calendar_write', true); result boolean;
begin
  -- Same lock order as import: mapping then order.
  perform 1 from public.ops_calendar_calendars c join public.ops_orders o on o.calendar_mapping_id = c.id
  where o.id = p_order_id and c.lease_token = p_lease_token and c.lease_until > clock_timestamp() and c.enabled for update of c;
  if not found then raise exception 'Calendar publish lease expired or superseded'; end if;
  perform set_config('ops.calendar_write', 'on', true);
  update public.ops_orders set publish_pending = false, last_publish_error = null,
    calendar_event_etag = coalesce(p_event_etag, calendar_event_etag)
  where id = p_order_id and origin = 'google_calendar' and publish_revision = p_expected_revision;
  result := found;
  perform set_config('ops.calendar_write', coalesce(prior_gate, ''), true);
  return result;
end;
$$;
create or replace function public.ops_calendar_publish_error(p_order_id uuid, p_lease_token uuid, p_error text)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare prior_gate text := current_setting('ops.calendar_write', true); result boolean;
begin
  perform 1 from public.ops_calendar_calendars c join public.ops_orders o on o.calendar_mapping_id = c.id
  where o.id = p_order_id and c.lease_token = p_lease_token and c.lease_until > clock_timestamp() and c.enabled for update of c;
  if not found then raise exception 'Calendar publish lease expired or superseded'; end if;
  perform set_config('ops.calendar_write', 'on', true);
  update public.ops_orders set last_publish_error = left(p_error, 2000), publish_pending = true
  where id = p_order_id and origin = 'google_calendar';
  result := found;
  perform set_config('ops.calendar_write', coalesce(prior_gate, ''), true);
  return result;
end;
$$;

-- Deny PUBLIC's default function execute privilege (including service RPCs).
do $$
declare fn record;
begin
  for fn in select oid::regprocedure as signature from pg_proc
    where pronamespace = 'public'::regnamespace and proname like 'ops_calendar_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', fn.signature);
    execute format('grant execute on function %s to service_role', fn.signature);
  end loop;
end;
$$;
grant execute on function public.ops_calendar_can_read(uuid, uuid),
  public.ops_calendar_is_admin(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
