-- MES: season-scope master data so FW26-27 remains historical and SS27 can be loaded independently
begin;

alter table public.mes_style_types
  add column if not exists dispatch text;

update public.mes_style_types
set dispatch = 'FW26-27'
where dispatch is null or btrim(dispatch) = '';

alter table public.mes_style_types
  alter column dispatch set default 'FW26-27';

alter table public.mes_style_types
  alter column dispatch set not null;

alter table public.mes_style_types
  drop constraint if exists mes_style_types_dispatch_check;

alter table public.mes_style_types
  add constraint mes_style_types_dispatch_check
  check (dispatch in ('FW26-27', 'SS27'));

create index if not exists idx_mes_style_types_dispatch
  on public.mes_style_types(dispatch);

alter table public.mes_style_pieces
  add column if not exists dispatch text;

update public.mes_style_pieces p
set dispatch = coalesce(t.dispatch, 'FW26-27')
from public.mes_style_types t
where p.style_type_id = t.id
  and (p.dispatch is null or btrim(p.dispatch) = '');

update public.mes_style_pieces
set dispatch = 'FW26-27'
where dispatch is null or btrim(dispatch) = '';

alter table public.mes_style_pieces
  alter column dispatch set default 'FW26-27';

alter table public.mes_style_pieces
  alter column dispatch set not null;

alter table public.mes_style_pieces
  drop constraint if exists mes_style_pieces_dispatch_check;

alter table public.mes_style_pieces
  add constraint mes_style_pieces_dispatch_check
  check (dispatch in ('FW26-27', 'SS27'));

create index if not exists idx_mes_style_pieces_dispatch
  on public.mes_style_pieces(dispatch);

alter table public.mes_supply_items
  add column if not exists dispatch text;

update public.mes_supply_items
set dispatch = 'FW26-27'
where dispatch is null or btrim(dispatch) = '';

alter table public.mes_supply_items
  alter column dispatch set default 'FW26-27';

alter table public.mes_supply_items
  alter column dispatch set not null;

alter table public.mes_supply_items
  drop constraint if exists mes_supply_items_dispatch_check;

alter table public.mes_supply_items
  add constraint mes_supply_items_dispatch_check
  check (dispatch in ('FW26-27', 'SS27'));

create index if not exists idx_mes_supply_items_dispatch
  on public.mes_supply_items(dispatch);

alter table public.mes_exchange_rates
  add column if not exists dispatch text;

update public.mes_exchange_rates
set dispatch = 'FW26-27'
where dispatch is null or btrim(dispatch) = '';

alter table public.mes_exchange_rates
  alter column dispatch set default 'FW26-27';

alter table public.mes_exchange_rates
  alter column dispatch set not null;

alter table public.mes_exchange_rates
  drop constraint if exists mes_exchange_rates_dispatch_check;

alter table public.mes_exchange_rates
  add constraint mes_exchange_rates_dispatch_check
  check (dispatch in ('FW26-27', 'SS27'));

create index if not exists idx_mes_exchange_rates_dispatch
  on public.mes_exchange_rates(dispatch);

alter table public.mes_service_rates
  add column if not exists dispatch text;

update public.mes_service_rates
set dispatch = 'FW26-27'
where dispatch is null or btrim(dispatch) = '';

alter table public.mes_service_rates
  alter column dispatch set default 'FW26-27';

alter table public.mes_service_rates
  alter column dispatch set not null;

alter table public.mes_service_rates
  drop constraint if exists mes_service_rates_dispatch_check;

alter table public.mes_service_rates
  add constraint mes_service_rates_dispatch_check
  check (dispatch in ('FW26-27', 'SS27'));

create index if not exists idx_mes_service_rates_dispatch
  on public.mes_service_rates(dispatch);

alter table public.mes_labor_rates
  add column if not exists dispatch text;

update public.mes_labor_rates
set dispatch = 'FW26-27'
where dispatch is null or btrim(dispatch) = '';

alter table public.mes_labor_rates
  alter column dispatch set default 'FW26-27';

alter table public.mes_labor_rates
  alter column dispatch set not null;

alter table public.mes_labor_rates
  drop constraint if exists mes_labor_rates_dispatch_check;

alter table public.mes_labor_rates
  add constraint mes_labor_rates_dispatch_check
  check (dispatch in ('FW26-27', 'SS27'));

create index if not exists idx_mes_labor_rates_dispatch
  on public.mes_labor_rates(dispatch);

notify pgrst, 'reload schema';

commit;
