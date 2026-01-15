-- FI access control: restrict income visibility for selected users
begin;

create table if not exists public.fi_user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'user',
  can_view_income boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

alter table public.fi_user_roles enable row level security;

drop policy if exists "fi_user_roles_read_own" on public.fi_user_roles;
create policy "fi_user_roles_read_own" on public.fi_user_roles
  for select to authenticated
  using (auth.uid() = user_id);

create or replace function public.fi_restrict_income()
returns boolean
language sql
stable
as $$
  select coalesce(
    (select not can_view_income from public.fi_user_roles where user_id = auth.uid()),
    false
  );
$$;

drop policy if exists "fi_categories_read" on public.fi_categories;
drop policy if exists "fi_categories_write" on public.fi_categories;
drop policy if exists "fi_categories_update" on public.fi_categories;
drop policy if exists "fi_categories_delete" on public.fi_categories;

create policy "fi_categories_read" on public.fi_categories
  for select to authenticated
  using (
    fi_restrict_income() = false
    or pnl_group in ('COGS', 'Opex')
  );

create policy "fi_categories_write" on public.fi_categories
  for insert to authenticated
  with check (
    fi_restrict_income() = false
    or pnl_group in ('COGS', 'Opex')
  );

create policy "fi_categories_update" on public.fi_categories
  for update to authenticated
  using (
    fi_restrict_income() = false
    or pnl_group in ('COGS', 'Opex')
  )
  with check (
    fi_restrict_income() = false
    or pnl_group in ('COGS', 'Opex')
  );

create policy "fi_categories_delete" on public.fi_categories
  for delete to authenticated
  using (
    fi_restrict_income() = false
    or pnl_group in ('COGS', 'Opex')
  );

drop policy if exists "fi_transactions_read" on public.fi_transactions;
drop policy if exists "fi_transactions_insert" on public.fi_transactions;
drop policy if exists "fi_transactions_update" on public.fi_transactions;
drop policy if exists "fi_transactions_delete" on public.fi_transactions;

create policy "fi_transactions_read" on public.fi_transactions
  for select to authenticated
  using (
    fi_restrict_income() = false
    or exists (
      select 1
      from public.fi_categories c
      where c.id = category_id
        and c.pnl_group in ('COGS', 'Opex')
    )
  );

create policy "fi_transactions_insert" on public.fi_transactions
  for insert to authenticated
  with check (
    auth.uid() is not null
    and (
      fi_restrict_income() = false
      or exists (
        select 1
        from public.fi_categories c
        where c.id = category_id
          and c.pnl_group in ('COGS', 'Opex')
      )
    )
  );

create policy "fi_transactions_update" on public.fi_transactions
  for update to authenticated
  using (
    fi_restrict_income() = false
    or exists (
      select 1
      from public.fi_categories c
      where c.id = category_id
        and c.pnl_group in ('COGS', 'Opex')
    )
  )
  with check (
    fi_restrict_income() = false
    or exists (
      select 1
      from public.fi_categories c
      where c.id = category_id
        and c.pnl_group in ('COGS', 'Opex')
    )
  );

create policy "fi_transactions_delete" on public.fi_transactions
  for delete to authenticated
  using (
    fi_restrict_income() = false
    or exists (
      select 1
      from public.fi_categories c
      where c.id = category_id
        and c.pnl_group in ('COGS', 'Opex')
    )
  );

insert into public.fi_user_roles (user_id, role, can_view_income)
select id, 'admin', true
from auth.users
where email = 'francisco@duomoholding.com'
on conflict (user_id) do update
set role = excluded.role,
    can_view_income = excluded.can_view_income;

insert into public.fi_user_roles (user_id, role, can_view_income)
select id, 'cashier', false
from auth.users
where email = 'shuaman@duomoholding.com'
on conflict (user_id) do update
set role = excluded.role,
    can_view_income = excluded.can_view_income;

commit;
