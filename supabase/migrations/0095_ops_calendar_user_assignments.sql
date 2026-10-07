-- OPS-only company/worker access. Do not grant CRM membership to fix Calendar.
-- Apply after 0094 and before deploying the matching Calendar backend.
begin;

create table if not exists public.ops_calendar_user_assignments (
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assignee_id uuid not null references public.ops_assignees(id) on delete restrict,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (business_unit_id, user_id)
);
create index if not exists idx_ops_calendar_user_assignments_user
  on public.ops_calendar_user_assignments(user_id) where active;
comment on table public.ops_calendar_user_assignments is
  'Server-managed Calendar-only company and execution identity; never grants Sales access or changes inbox visibility.';
alter table public.ops_calendar_user_assignments enable row level security;
revoke all on public.ops_calendar_user_assignments from public, anon, authenticated;
grant all on public.ops_calendar_user_assignments to service_role;

-- The inbox read scope and the personal execution identity are independent.
-- An explicit Calendar assignment takes precedence over the legacy inbox
-- assignee, but NEVER bypasses an inactive/missing inbox permission or module.
create or replace function public.ops_calendar_user_access(
  p_user_id uuid, p_business_unit_id uuid, p_assignee_id uuid default null,
  p_manage boolean default false, p_act boolean default false
) returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select p_user_id is not null and exists (
    select 1
    from public.crm_business_units b
    left join public.crm_business_unit_memberships m
      on m.business_unit_id = b.id and m.user_id = p_user_id and m.active
    left join public.ops_calendar_user_assignments a
      on a.business_unit_id = b.id and a.user_id = p_user_id and a.active
    where b.id = p_business_unit_id and b.active
      and (m.user_id is not null or a.user_id is not null)
      and (not exists (select 1 from public.app_user_modules u where u.user_id = p_user_id)
           or exists (select 1 from public.app_user_modules u where u.user_id = p_user_id
                      and lower(btrim(u.module_key)) = 'ops'))
      and (
        m.role in ('admin', 'manager')
        or (not p_manage and exists (
          select 1 from public.ops_inbox_user_permissions p
          where p.user_id = p_user_id and p.active and (
            coalesce(a.assignee_id,
              case when p.access_level = 'assignee' then p.assignee_id end) = p_assignee_id
            or (p.access_level = 'all' and not p_act)
          )
        ))
      )
  );
$$;
revoke all on function public.ops_calendar_user_access(uuid, uuid, uuid, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.ops_calendar_user_access(uuid, uuid, uuid, boolean, boolean)
  to service_role;

-- Approved repair: LRJ may still read all OPS activities in CDM but execute
-- only his own. Resolve the already-verified calendar/worker, not a title
-- heuristic. Missing/different identities stop the repair rather than guessing.
-- A rerun must not reactivate or overwrite a later administrative change.
do $$
declare
  target_user uuid;
  target_company uuid;
  target_assignee uuid;
begin
  select id into target_user from auth.users
    where id = '0ead3bd7-fa97-481c-950d-9944b60b9a40'
      and lower(email) = 'lrj@cdmservi.com';
  if target_user is null then
    raise notice 'LRJ Calendar repair not applied: verified user is absent.';
    return;
  end if;
  select c.business_unit_id, c.assignee_id into target_company, target_assignee
    from public.ops_calendar_calendars c
    join public.crm_business_units b on b.id = c.business_unit_id and b.active
    join public.ops_assignees a on a.id = c.assignee_id and a.active
    where c.id = '537882dd-736c-4271-acce-f0fa1a62477e'
      and c.business_unit_id = 'ca19e953-7efc-40c6-89b9-60b69e7ad8a3'
      and c.assignee_id = '5ae05a6c-abc5-4fb2-a5aa-a674114415c6'
      and b.code = 'cdm';
  if target_company is null then
    raise exception 'LRJ Calendar repair stopped: verify the CDM calendar and assignee identities.';
  end if;
  if not exists (select 1 from public.ops_inbox_user_permissions
                 where user_id = target_user and active and access_level = 'all') then
    raise exception 'LRJ Calendar repair stopped: existing full inbox read permission changed.';
  end if;
  insert into public.ops_calendar_user_assignments(business_unit_id, user_id, assignee_id)
    values (target_company, target_user, target_assignee)
    on conflict (business_unit_id, user_id) do nothing;
end;
$$;

notify pgrst, 'reload schema';
commit;
