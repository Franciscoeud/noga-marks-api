-- OPS: user-level access control for inbox assignee visibility
begin;

create table if not exists public.ops_inbox_user_permissions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  access_level text not null,
  assignee_id uuid references public.ops_assignees(id) on delete set null,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint ops_inbox_user_permissions_access_check
    check (access_level in ('all', 'assignee')),
  constraint ops_inbox_user_permissions_assignee_check
    check (
      (access_level = 'all' and assignee_id is null)
      or (access_level = 'assignee' and assignee_id is not null)
    )
);

create index if not exists idx_ops_inbox_user_permissions_active
  on public.ops_inbox_user_permissions(active, access_level);
create index if not exists idx_ops_inbox_user_permissions_assignee
  on public.ops_inbox_user_permissions(assignee_id)
  where assignee_id is not null;

drop trigger if exists trg_ops_inbox_user_permissions_updated_at
  on public.ops_inbox_user_permissions;
create trigger trg_ops_inbox_user_permissions_updated_at
before update on public.ops_inbox_user_permissions
for each row execute procedure public.set_updated_at();

alter table public.ops_inbox_user_permissions enable row level security;

drop policy if exists "ops_inbox_user_permissions_read_own"
  on public.ops_inbox_user_permissions;
create policy "ops_inbox_user_permissions_read_own"
  on public.ops_inbox_user_permissions
  for select to authenticated
  using (auth.uid() = user_id);

grant select on public.ops_inbox_user_permissions to authenticated;

notify pgrst, 'reload schema';

commit;
