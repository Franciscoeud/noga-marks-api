-- OPS: dashboard monthly targets and supporting indexes
begin;

create table if not exists public.ops_dashboard_monthly_targets (
  id uuid primary key default uuid_generate_v4(),
  period_month date not null,
  closed_orders_target int not null default 0
    check (closed_orders_target >= 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (period_month)
);

create index if not exists idx_ops_dashboard_monthly_targets_period_month
  on public.ops_dashboard_monthly_targets(period_month);

create index if not exists idx_ops_orders_cerrado_at
  on public.ops_orders(cerrado_at);

create index if not exists idx_ops_order_tasks_completed_at
  on public.ops_order_tasks(completed_at);

drop trigger if exists trg_ops_dashboard_monthly_targets_updated_at on public.ops_dashboard_monthly_targets;
create trigger trg_ops_dashboard_monthly_targets_updated_at
before update on public.ops_dashboard_monthly_targets
for each row execute procedure public.set_updated_at();

alter table public.ops_dashboard_monthly_targets enable row level security;

drop policy if exists "ops_dashboard_monthly_targets_read" on public.ops_dashboard_monthly_targets;
create policy "ops_dashboard_monthly_targets_read" on public.ops_dashboard_monthly_targets
  for select to authenticated
  using (true);

drop policy if exists "ops_dashboard_monthly_targets_write" on public.ops_dashboard_monthly_targets;
create policy "ops_dashboard_monthly_targets_write" on public.ops_dashboard_monthly_targets
  for insert to authenticated
  with check (true);

drop policy if exists "ops_dashboard_monthly_targets_update" on public.ops_dashboard_monthly_targets;
create policy "ops_dashboard_monthly_targets_update" on public.ops_dashboard_monthly_targets
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "ops_dashboard_monthly_targets_delete" on public.ops_dashboard_monthly_targets;
create policy "ops_dashboard_monthly_targets_delete" on public.ops_dashboard_monthly_targets
  for delete to authenticated
  using (true);

notify pgrst, 'reload schema';

commit;
