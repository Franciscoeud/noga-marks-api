-- OPS: classify clients and standardize business sectors
begin;

create extension if not exists "uuid-ossp";

alter table public.ops_clients
  add column if not exists client_type text not null default 'Empresa';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ops_clients_client_type_check'
      and conrelid = 'public.ops_clients'::regclass
  ) then
    alter table public.ops_clients
      add constraint ops_clients_client_type_check
      check (client_type in ('Empresa', 'Persona Natural'));
  end if;
end $$;

create table if not exists public.ops_client_sectors (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  active boolean not null default true,
  sort_order integer not null default 1000,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint ops_client_sectors_name_check
    check (nullif(btrim(name), '') is not null),
  constraint uq_ops_client_sectors_name unique (name)
);

create index if not exists idx_ops_client_sectors_active_sort
  on public.ops_client_sectors(active, sort_order, name);

drop trigger if exists trg_ops_client_sectors_updated_at
  on public.ops_client_sectors;
create trigger trg_ops_client_sectors_updated_at
before update on public.ops_client_sectors
for each row execute procedure public.set_updated_at();

insert into public.ops_client_sectors (name, sort_order)
values
  ('Tecnología', 10),
  ('Telecomunicaciones', 20),
  ('Retail / Comercio', 30),
  ('Servicios', 40),
  ('Salud', 50),
  ('Educación', 60),
  ('Construcción / Inmobiliaria', 70),
  ('Industria / Manufactura', 80),
  ('Finanzas / Seguros', 90),
  ('Logística / Transporte', 100),
  ('Gobierno', 110),
  ('Hotelería / Turismo', 120),
  ('Otro', 130)
on conflict (name) do update set
  active = true,
  sort_order = excluded.sort_order,
  updated_at = timezone('utc', now());

insert into public.ops_client_sectors (name, sort_order)
select distinct btrim(sector), 900
from public.ops_clients
where nullif(btrim(sector), '') is not null
on conflict (name) do update set
  active = true,
  updated_at = timezone('utc', now());

alter table public.ops_client_sectors enable row level security;

drop policy if exists "ops_client_sectors_read" on public.ops_client_sectors;
create policy "ops_client_sectors_read" on public.ops_client_sectors
  for select to authenticated using (true);

grant select on public.ops_client_sectors to authenticated;

notify pgrst, 'reload schema';

commit;
