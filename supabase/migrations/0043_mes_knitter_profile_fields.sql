-- MES: add knitter profile and fixed daily rate fields
begin;

alter table public.mes_knitters
  add column if not exists dni text,
  add column if not exists province text,
  add column if not exists performance_label text not null default 'Promedio',
  add column if not exists daily_rate_pen numeric(12,2) not null default 0,
  add column if not exists notes text;

update public.mes_knitters
set
  performance_label = case
    when btrim(coalesce(performance_label, '')) in ('Lenta', 'Rapida', 'Promedio')
      then btrim(performance_label)
    else 'Promedio'
  end,
  daily_rate_pen = coalesce(daily_rate_pen, 0);

alter table public.mes_knitters
  alter column performance_label set default 'Promedio',
  alter column performance_label set not null,
  alter column daily_rate_pen set default 0,
  alter column daily_rate_pen set not null;

alter table public.mes_knitters
  drop constraint if exists mes_knitters_performance_label_check;

alter table public.mes_knitters
  add constraint mes_knitters_performance_label_check
  check (performance_label in ('Lenta', 'Rapida', 'Promedio'));

alter table public.mes_knitters
  drop constraint if exists mes_knitters_daily_rate_pen_nonnegative;

alter table public.mes_knitters
  add constraint mes_knitters_daily_rate_pen_nonnegative
  check (daily_rate_pen >= 0);

with latest_rates as (
  select distinct on (knitter_id)
    knitter_id,
    daily_rate_pen
  from public.mes_knitting_production
  where daily_rate_pen is not null
    and daily_rate_pen > 0
  order by knitter_id, created_at desc
)
update public.mes_knitters k
set daily_rate_pen = latest_rates.daily_rate_pen
from latest_rates
where k.id = latest_rates.knitter_id
  and k.daily_rate_pen = 0;

create index if not exists idx_mes_knitters_performance_label
  on public.mes_knitters(performance_label);

create table if not exists public.mes_knitter_mobility_payments (
  id uuid primary key default uuid_generate_v4(),
  knitter_id uuid not null references public.mes_knitters(id) on delete cascade,
  payment_date date not null default current_date,
  amount_pen numeric(12,2) not null default 0,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint mes_knitter_mobility_payments_amount_nonnegative
    check (amount_pen >= 0)
);

create index if not exists idx_mes_knitter_mobility_payments_knitter
  on public.mes_knitter_mobility_payments(knitter_id);

create index if not exists idx_mes_knitter_mobility_payments_date
  on public.mes_knitter_mobility_payments(payment_date);

drop trigger if exists trg_mes_knitter_mobility_payments_updated_at
  on public.mes_knitter_mobility_payments;
create trigger trg_mes_knitter_mobility_payments_updated_at
before update on public.mes_knitter_mobility_payments
for each row execute procedure public.set_updated_at();

alter table public.mes_knitter_mobility_payments enable row level security;

drop policy if exists "mes_knitter_mobility_payments_read"
  on public.mes_knitter_mobility_payments;
create policy "mes_knitter_mobility_payments_read"
  on public.mes_knitter_mobility_payments
  for select to authenticated
  using (true);

drop policy if exists "mes_knitter_mobility_payments_write"
  on public.mes_knitter_mobility_payments;
create policy "mes_knitter_mobility_payments_write"
  on public.mes_knitter_mobility_payments
  for insert to authenticated
  with check (true);

drop policy if exists "mes_knitter_mobility_payments_update"
  on public.mes_knitter_mobility_payments;
create policy "mes_knitter_mobility_payments_update"
  on public.mes_knitter_mobility_payments
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "mes_knitter_mobility_payments_delete"
  on public.mes_knitter_mobility_payments;
create policy "mes_knitter_mobility_payments_delete"
  on public.mes_knitter_mobility_payments
  for delete to authenticated
  using (true);

notify pgrst, 'reload schema';

commit;
