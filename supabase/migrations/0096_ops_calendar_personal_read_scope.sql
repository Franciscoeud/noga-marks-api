-- Personal Calendar assignments scope both reading and execution. Legacy
-- inbox-wide access remains unchanged for the traditional OPS inbox.
begin;

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
            or (a.user_id is null and p.access_level = 'all' and not p_act)
          )
        ))
      )
  );
$$;
revoke all on function public.ops_calendar_user_access(uuid, uuid, uuid, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.ops_calendar_user_access(uuid, uuid, uuid, boolean, boolean)
  to service_role;

comment on table public.ops_calendar_user_assignments is
  'Server-managed Calendar-only company and personal read/execution identity; never grants Sales access or changes inbox visibility. Active admin/manager memberships retain global Calendar access.';

notify pgrst, 'reload schema';
commit;
