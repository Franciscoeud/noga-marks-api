-- MES: add external workshop cost for garment costing
begin;

alter table public.mes_garments
  add column if not exists external_workshop_cost numeric,
  add column if not exists external_workshop_currency text default 'PEN';

update public.mes_garments
set external_workshop_currency = 'PEN'
where external_workshop_currency is null;

alter table public.mes_garments
  alter column external_workshop_currency set default 'PEN',
  alter column external_workshop_currency set not null;

alter table public.mes_garments
  drop constraint if exists mes_garments_external_workshop_cost_check;

alter table public.mes_garments
  add constraint mes_garments_external_workshop_cost_check
  check (external_workshop_cost is null or external_workshop_cost >= 0);

alter table public.mes_garments
  drop constraint if exists mes_garments_external_workshop_currency_check;

alter table public.mes_garments
  add constraint mes_garments_external_workshop_currency_check
  check (external_workshop_currency in ('PEN', 'USD'));

notify pgrst, 'reload schema';

commit;
