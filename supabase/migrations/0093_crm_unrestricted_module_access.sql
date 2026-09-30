-- Match the application module contract: no rows means unrestricted modules;
-- an explicit module list must include Sales. Business-unit membership and
-- its existing role, owner and request-company checks still govern CRM access.
-- CREATE OR REPLACE preserves function ownership and existing EXECUTE grants.
begin;

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
      and (
        not exists (
          select 1 from public.app_user_modules module_access
          where module_access.user_id = auth.uid()
        )
        or exists (
          select 1 from public.app_user_modules module_access
          where module_access.user_id = auth.uid()
            and lower(module_access.module_key) = 'sales'
        )
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
      and (
        not exists (
          select 1 from public.app_user_modules module_access
          where module_access.user_id = auth.uid()
        )
        or exists (
          select 1 from public.app_user_modules module_access
          where module_access.user_id = auth.uid()
            and lower(module_access.module_key) = 'sales'
        )
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
      and (
        not exists (
          select 1 from public.app_user_modules module_access
          where module_access.user_id = auth.uid()
        )
        or exists (
          select 1 from public.app_user_modules module_access
          where module_access.user_id = auth.uid()
            and lower(module_access.module_key) = 'sales'
        )
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

commit;
