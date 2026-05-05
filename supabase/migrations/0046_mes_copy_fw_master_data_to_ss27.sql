-- MES: copy FW26-27 master data into SS27 after accidental season load
begin;

alter table public.mes_style_pieces
  alter column style_type_id drop not null;

insert into public.mes_style_types(dispatch, name, active, order_index)
select
  'SS27',
  source.name,
  source.active,
  source.order_index
from public.mes_style_types source
where source.dispatch = 'FW26-27'
  and not exists (
    select 1
    from public.mes_style_types target
    where target.dispatch = 'SS27'
      and lower(btrim(target.name)) = lower(btrim(source.name))
  );

insert into public.mes_style_pieces(dispatch, style_type_id, name, active, order_index)
select
  'SS27',
  null,
  source.name,
  source.active,
  source.order_index
from (
  select distinct on (lower(btrim(name)))
    name,
    active,
    order_index
  from public.mes_style_pieces
  where dispatch = 'FW26-27'
  order by lower(btrim(name)), order_index, name
) source
where not exists (
  select 1
  from public.mes_style_pieces target
  where target.dispatch = 'SS27'
    and lower(btrim(target.name)) = lower(btrim(source.name))
);

update public.mes_style_pieces
set style_type_id = null
where dispatch = 'SS27'
  and style_type_id is not null;

delete from public.mes_style_pieces duplicate
using public.mes_style_pieces keeper
where duplicate.dispatch = 'SS27'
  and keeper.dispatch = 'SS27'
  and duplicate.id > keeper.id
  and lower(btrim(duplicate.name)) = lower(btrim(keeper.name));

create unique index if not exists uq_mes_style_pieces_ss27_name
  on public.mes_style_pieces(lower(btrim(name)))
  where dispatch = 'SS27';

insert into public.mes_design_attributes(dispatch, kind, name, active, order_index)
select
  'SS27',
  source.kind,
  source.name,
  source.active,
  source.order_index
from public.mes_design_attributes source
where source.dispatch = 'FW26-27'
on conflict do nothing;

insert into public.mes_supply_items(
  dispatch,
  name,
  category,
  unit,
  waste_percent,
  currency,
  unit_cost,
  active
)
select
  'SS27',
  source.name,
  source.category,
  source.unit,
  source.waste_percent,
  source.currency,
  source.unit_cost,
  source.active
from public.mes_supply_items source
where source.dispatch = 'FW26-27'
  and not exists (
    select 1
    from public.mes_supply_items target
    where target.dispatch = 'SS27'
      and target.category = source.category
      and lower(btrim(target.name)) = lower(btrim(source.name))
      and lower(btrim(target.unit)) = lower(btrim(source.unit))
  );

insert into public.mes_exchange_rates(
  dispatch,
  currency_from,
  currency_to,
  rate,
  valid_from,
  valid_to,
  active,
  notes
)
select
  'SS27',
  source.currency_from,
  source.currency_to,
  source.rate,
  source.valid_from,
  source.valid_to,
  source.active,
  source.notes
from public.mes_exchange_rates source
where source.dispatch = 'FW26-27'
  and not exists (
    select 1
    from public.mes_exchange_rates target
    where target.dispatch = 'SS27'
      and target.currency_from = source.currency_from
      and target.currency_to = source.currency_to
      and target.valid_from = source.valid_from
      and target.valid_to is not distinct from source.valid_to
  );

insert into public.mes_service_rates(
  dispatch,
  service,
  criteria,
  min_incl,
  max_excl,
  rate_pen,
  unit,
  valid_from,
  valid_to,
  active,
  notes
)
select
  'SS27',
  source.service,
  source.criteria,
  source.min_incl,
  source.max_excl,
  source.rate_pen,
  source.unit,
  source.valid_from,
  source.valid_to,
  source.active,
  source.notes
from public.mes_service_rates source
where source.dispatch = 'FW26-27'
  and not exists (
    select 1
    from public.mes_service_rates target
    where target.dispatch = 'SS27'
      and lower(btrim(target.service)) = lower(btrim(source.service))
      and lower(btrim(target.criteria)) = lower(btrim(source.criteria))
      and target.min_incl = source.min_incl
      and target.max_excl is not distinct from source.max_excl
      and lower(btrim(target.unit)) = lower(btrim(source.unit))
      and target.valid_from = source.valid_from
  );

insert into public.mes_labor_rates(
  dispatch,
  role,
  resource_id,
  monthly_salary,
  currency,
  days_month,
  cost_day,
  cost_hour,
  cost_type,
  valid_from,
  valid_to,
  active,
  responsible,
  notes,
  location
)
select
  'SS27',
  source.role,
  source.resource_id,
  source.monthly_salary,
  source.currency,
  source.days_month,
  source.cost_day,
  source.cost_hour,
  source.cost_type,
  source.valid_from,
  source.valid_to,
  source.active,
  source.responsible,
  source.notes,
  source.location
from public.mes_labor_rates source
where source.dispatch = 'FW26-27'
  and not exists (
    select 1
    from public.mes_labor_rates target
    where target.dispatch = 'SS27'
      and lower(btrim(target.role)) = lower(btrim(source.role))
      and target.resource_id is not distinct from source.resource_id
      and target.valid_from = source.valid_from
      and target.location is not distinct from source.location
  );

notify pgrst, 'reload schema';

commit;
