-- GTS: identify the Manufacturing price source stored in each simulation
begin;

alter table public.gts_export_simulations
  add column if not exists price_source text;

update public.gts_export_simulations
set price_source = 'legacy_precio_wholesale'
where price_source is null;

alter table public.gts_export_simulations
  alter column price_source set default 'wholesale_simulado',
  alter column price_source set not null;

alter table public.gts_export_simulations
  drop constraint if exists gts_export_simulations_price_source_check;

alter table public.gts_export_simulations
  add constraint gts_export_simulations_price_source_check
  check (price_source in ('legacy_precio_wholesale', 'wholesale_simulado'));

notify pgrst, 'reload schema';

commit;
