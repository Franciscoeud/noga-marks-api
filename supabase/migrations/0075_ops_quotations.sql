-- OPS: quotations / CDM proformas
begin;

create extension if not exists "uuid-ossp";

create table if not exists public.ops_quotation_year_counters (
  quotation_year integer primary key,
  next_number integer not null default 1,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint ops_quotation_year_counters_year_check
    check (quotation_year >= 2000),
  constraint ops_quotation_year_counters_next_number_check
    check (next_number > 0)
);

insert into public.ops_quotation_year_counters (quotation_year, next_number)
values (2026, 500)
on conflict (quotation_year) do nothing;

create or replace function public.next_ops_quotation_number(p_year integer)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_number integer;
begin
  if p_year is null or p_year < 2000 then
    raise exception 'Invalid quotation year: %', p_year;
  end if;

  insert into public.ops_quotation_year_counters (quotation_year, next_number)
  values (p_year, 1)
  on conflict (quotation_year) do nothing;

  update public.ops_quotation_year_counters
  set next_number = next_number + 1,
      updated_at = timezone('utc', now())
  where quotation_year = p_year
  returning next_number - 1 into v_number;

  return v_number;
end;
$$;

create table if not exists public.ops_quotations (
  id uuid primary key default uuid_generate_v4(),
  quotation_number integer not null,
  quotation_year integer not null default extract(year from timezone('America/Lima', now()))::integer,
  client_id uuid not null references public.ops_clients(id) on delete restrict,
  client_name text not null,
  quotation_date date not null default timezone('America/Lima', now())::date,
  currency text not null default 'PEN',
  terms_validity text not null default '04 dias utiles',
  terms_payment text not null default 'Contado contra Entrega',
  terms_taxes text not null default 'Los precios incluyen IGV',
  terms_delivery text not null default '48 horas despues de emitida la OC',
  signed_by_name text not null default 'Luis E. Revoredo Johnson',
  signed_by_title text not null default 'Gerente de Ventas',
  status text not null default 'issued',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint uq_ops_quotations_number unique (quotation_year, quotation_number),
  constraint ops_quotations_year_check check (quotation_year >= 2000),
  constraint ops_quotations_number_check check (quotation_number > 0),
  constraint ops_quotations_currency_check check (currency = 'PEN'),
  constraint ops_quotations_status_check
    check (status in ('draft', 'issued', 'cancelled')),
  constraint ops_quotations_required_text_check
    check (
      nullif(btrim(client_name), '') is not null
      and nullif(btrim(terms_validity), '') is not null
      and nullif(btrim(terms_payment), '') is not null
      and nullif(btrim(terms_taxes), '') is not null
      and nullif(btrim(terms_delivery), '') is not null
      and nullif(btrim(signed_by_name), '') is not null
      and nullif(btrim(signed_by_title), '') is not null
    )
);

create or replace function public.ops_set_quotation_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.quotation_year is null then
    new.quotation_year := extract(year from timezone('America/Lima', now()))::integer;
  end if;

  if new.quotation_number is null then
    new.quotation_number := public.next_ops_quotation_number(new.quotation_year);
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ops_quotations_set_number
  on public.ops_quotations;
create trigger trg_ops_quotations_set_number
before insert on public.ops_quotations
for each row execute procedure public.ops_set_quotation_number();

create table if not exists public.ops_quotation_items (
  id uuid primary key default uuid_generate_v4(),
  quotation_id uuid not null references public.ops_quotations(id) on delete cascade,
  position integer not null,
  code text not null,
  description text not null,
  quantity numeric(12, 2) not null,
  unit_price numeric(12, 2) not null,
  line_total numeric(14, 2) generated always as (round(quantity * unit_price, 2)) stored,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint ops_quotation_items_position_check check (position >= 1),
  constraint ops_quotation_items_quantity_check check (quantity > 0),
  constraint ops_quotation_items_unit_price_check check (unit_price >= 0),
  constraint ops_quotation_items_required_text_check
    check (
      nullif(btrim(code), '') is not null
      and nullif(btrim(description), '') is not null
    ),
  constraint uq_ops_quotation_items_position unique (quotation_id, position)
);

create index if not exists idx_ops_quotations_created_at
  on public.ops_quotations(created_at desc);
create index if not exists idx_ops_quotations_number
  on public.ops_quotations(quotation_year desc, quotation_number desc);
create index if not exists idx_ops_quotations_client
  on public.ops_quotations(client_id);
create index if not exists idx_ops_quotations_status
  on public.ops_quotations(status);
create index if not exists idx_ops_quotation_items_quote
  on public.ops_quotation_items(quotation_id, position);

drop trigger if exists trg_ops_quotation_year_counters_updated_at
  on public.ops_quotation_year_counters;
create trigger trg_ops_quotation_year_counters_updated_at
before update on public.ops_quotation_year_counters
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_ops_quotations_updated_at
  on public.ops_quotations;
create trigger trg_ops_quotations_updated_at
before update on public.ops_quotations
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_ops_quotation_items_updated_at
  on public.ops_quotation_items;
create trigger trg_ops_quotation_items_updated_at
before update on public.ops_quotation_items
for each row execute procedure public.set_updated_at();

alter table public.ops_quotation_year_counters enable row level security;
alter table public.ops_quotations enable row level security;
alter table public.ops_quotation_items enable row level security;

drop policy if exists "ops_quotations_read" on public.ops_quotations;
create policy "ops_quotations_read" on public.ops_quotations
  for select to authenticated using (true);
drop policy if exists "ops_quotations_insert" on public.ops_quotations;
create policy "ops_quotations_insert" on public.ops_quotations
  for insert to authenticated with check (true);
drop policy if exists "ops_quotations_update" on public.ops_quotations;
create policy "ops_quotations_update" on public.ops_quotations
  for update to authenticated using (true) with check (true);
drop policy if exists "ops_quotations_delete" on public.ops_quotations;
create policy "ops_quotations_delete" on public.ops_quotations
  for delete to authenticated using (true);

drop policy if exists "ops_quotation_items_read" on public.ops_quotation_items;
create policy "ops_quotation_items_read" on public.ops_quotation_items
  for select to authenticated using (true);
drop policy if exists "ops_quotation_items_insert" on public.ops_quotation_items;
create policy "ops_quotation_items_insert" on public.ops_quotation_items
  for insert to authenticated with check (true);
drop policy if exists "ops_quotation_items_update" on public.ops_quotation_items;
create policy "ops_quotation_items_update" on public.ops_quotation_items
  for update to authenticated using (true) with check (true);
drop policy if exists "ops_quotation_items_delete" on public.ops_quotation_items;
create policy "ops_quotation_items_delete" on public.ops_quotation_items
  for delete to authenticated using (true);

grant select, insert, update, delete on public.ops_quotations to authenticated;
grant select, insert, update, delete on public.ops_quotation_items to authenticated;
grant execute on function public.next_ops_quotation_number(integer) to authenticated;
grant execute on function public.ops_set_quotation_number() to authenticated;

notify pgrst, 'reload schema';

commit;
