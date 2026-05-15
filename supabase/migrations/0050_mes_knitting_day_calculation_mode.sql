-- MES: add day calculation mode for knitting production work days
begin;

alter table public.mes_knitting_production
  add column if not exists day_calculation_mode text not null default 'simple';

update public.mes_knitting_production
set day_calculation_mode = 'simple'
where day_calculation_mode is null
   or day_calculation_mode not in ('simple', 'full_day', 'half_day');

alter table public.mes_knitting_production
  alter column day_calculation_mode set default 'simple',
  alter column day_calculation_mode set not null;

alter table public.mes_knitting_production
  drop constraint if exists mes_knitting_production_day_calculation_mode_check;

alter table public.mes_knitting_production
  add constraint mes_knitting_production_day_calculation_mode_check
  check (day_calculation_mode in ('simple', 'full_day', 'half_day'));

notify pgrst, 'reload schema';

commit;
