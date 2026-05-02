-- MES: master data for design colors, materials and techniques
begin;

create table if not exists public.mes_design_attributes (
  id uuid primary key default uuid_generate_v4(),
  dispatch text not null default 'FW26-27',
  kind text not null,
  name text not null,
  active boolean not null default true,
  order_index int not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint mes_design_attributes_dispatch_check
    check (dispatch in ('FW26-27', 'SS27')),
  constraint mes_design_attributes_kind_check
    check (kind in ('color', 'material', 'technique')),
  constraint mes_design_attributes_name_not_blank
    check (btrim(name) <> '')
);

create unique index if not exists uq_mes_design_attributes_dispatch_kind_name
  on public.mes_design_attributes(dispatch, kind, lower(btrim(name)));

create index if not exists idx_mes_design_attributes_dispatch_kind
  on public.mes_design_attributes(dispatch, kind);

drop trigger if exists trg_mes_design_attributes_updated_at on public.mes_design_attributes;
create trigger trg_mes_design_attributes_updated_at
before update on public.mes_design_attributes
for each row execute procedure public.set_updated_at();

insert into public.mes_design_attributes(dispatch, kind, name, active, order_index)
select distinct
  case
    when dispatch = 'SS27-COM' then 'SS27'
    when dispatch in ('FW26-27', 'SS27') then dispatch
    else 'FW26-27'
  end as dispatch,
  kind,
  value as name,
  true as active,
  0 as order_index
from (
  select dispatch, 'technique'::text as kind, nullif(btrim(technique), '') as value
  from public.mes_garments
  union all
  select dispatch, 'material'::text as kind, nullif(btrim(material), '') as value
  from public.mes_garments
  union all
  select dispatch, 'color'::text as kind, nullif(btrim(design_color), '') as value
  from public.mes_garments
) source
where value is not null
on conflict do nothing;

alter table public.mes_design_attributes enable row level security;

drop policy if exists "mes_design_attributes_read" on public.mes_design_attributes;
create policy "mes_design_attributes_read" on public.mes_design_attributes
  for select to authenticated
  using (true);

drop policy if exists "mes_design_attributes_write" on public.mes_design_attributes;
create policy "mes_design_attributes_write" on public.mes_design_attributes
  for insert to authenticated
  with check (true);

drop policy if exists "mes_design_attributes_update" on public.mes_design_attributes;
create policy "mes_design_attributes_update" on public.mes_design_attributes
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "mes_design_attributes_delete" on public.mes_design_attributes;
create policy "mes_design_attributes_delete" on public.mes_design_attributes
  for delete to authenticated
  using (true);

notify pgrst, 'reload schema';

commit;
