-- FI module: finance tables, P&L view, RLS, seeds
begin;

create extension if not exists "uuid-ossp";

create table if not exists public.fi_properties (
  id uuid primary key default uuid_generate_v4(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.fi_categories (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  type text not null check (type in ('income', 'expense', 'noncash')),
  pnl_group text not null,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (name, type)
);

create table if not exists public.fi_transactions (
  id uuid primary key default uuid_generate_v4(),
  date date not null,
  property_id uuid not null references public.fi_properties(id) on delete restrict,
  category_id uuid not null references public.fi_categories(id) on delete restrict,
  amount numeric(14,2) not null check (amount >= 0),
  channel text,
  vendor text,
  payment_method text,
  notes text,
  receipt_url text,
  is_recurring boolean not null default false,
  recurrence_freq text,
  recurrence_day int,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_fi_transactions_date on public.fi_transactions(date);
create index if not exists idx_fi_transactions_property on public.fi_transactions(property_id);
create index if not exists idx_fi_transactions_category on public.fi_transactions(category_id);

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_fi_properties_updated_at on public.fi_properties;
create trigger trg_fi_properties_updated_at
before update on public.fi_properties
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_fi_categories_updated_at on public.fi_categories;
create trigger trg_fi_categories_updated_at
before update on public.fi_categories
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_fi_transactions_updated_at on public.fi_transactions;
create trigger trg_fi_transactions_updated_at
before update on public.fi_transactions
for each row execute procedure public.set_updated_at();

create or replace view public.fi_monthly_pnl as
select
  t.property_id,
  date_part('year', t.date)::int as year,
  date_part('month', t.date)::int as month,
  c.id as category_id,
  c.name as category_name,
  c.type as category_type,
  c.pnl_group,
  c.sort_order,
  sum(t.amount)::numeric(14,2) as total_amount
from public.fi_transactions t
join public.fi_categories c on c.id = t.category_id
group by
  t.property_id,
  date_part('year', t.date),
  date_part('month', t.date),
  c.id,
  c.name,
  c.type,
  c.pnl_group,
  c.sort_order;

alter table public.fi_properties enable row level security;
alter table public.fi_categories enable row level security;
alter table public.fi_transactions enable row level security;

create policy "fi_properties_read" on public.fi_properties
  for select to authenticated
  using (true);

create policy "fi_properties_write" on public.fi_properties
  for insert to authenticated
  with check (true);

create policy "fi_properties_update" on public.fi_properties
  for update to authenticated
  using (true)
  with check (true);

create policy "fi_properties_delete" on public.fi_properties
  for delete to authenticated
  using (true);

create policy "fi_categories_read" on public.fi_categories
  for select to authenticated
  using (true);

create policy "fi_categories_write" on public.fi_categories
  for insert to authenticated
  with check (true);

create policy "fi_categories_update" on public.fi_categories
  for update to authenticated
  using (true)
  with check (true);

create policy "fi_categories_delete" on public.fi_categories
  for delete to authenticated
  using (true);

create policy "fi_transactions_read" on public.fi_transactions
  for select to authenticated
  using (true);

create policy "fi_transactions_insert" on public.fi_transactions
  for insert to authenticated
  with check (auth.uid() is not null);

create policy "fi_transactions_update" on public.fi_transactions
  for update to authenticated
  using (true)
  with check (true);

create policy "fi_transactions_delete" on public.fi_transactions
  for delete to authenticated
  using (true);

insert into public.fi_properties (name)
values
  ('Miraflores Suites'),
  ('Barranco Loft')
on conflict (name) do nothing;

insert into public.fi_categories (name, type, pnl_group, sort_order)
values
  ('Room Revenue', 'income', 'Revenue', 10),
  ('Other Revenue', 'income', 'Revenue', 20),
  ('OTA Fees', 'expense', 'COGS', 30),
  ('Cleaning / Laundry', 'expense', 'COGS', 40),
  ('Amenities / Supplies', 'expense', 'COGS', 50),
  ('Payroll', 'expense', 'Opex', 60),
  ('Utilities', 'expense', 'Opex', 70),
  ('Maintenance / Repairs', 'expense', 'Opex', 80),
  ('Marketing / Advertising', 'expense', 'Opex', 90),
  ('Software / Subscriptions', 'expense', 'Opex', 100),
  ('Taxes / Licenses', 'expense', 'Opex', 110),
  ('Other Expenses', 'expense', 'Opex', 120),
  ('Depreciation', 'noncash', 'Depreciation', 130)
on conflict (name, type) do nothing;

commit;
