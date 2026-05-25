-- GTS: store final garment price snapshots for export simulations
begin;

alter table public.gts_export_simulations
  add column if not exists final_price_usd numeric(14,4) not null default 0,
  add column if not exists final_price_pen numeric(14,4) not null default 0;

alter table public.gts_export_simulations
  drop constraint if exists gts_export_simulations_final_price_nonnegative_check;

alter table public.gts_export_simulations
  add constraint gts_export_simulations_final_price_nonnegative_check
  check (final_price_usd >= 0 and final_price_pen >= 0);

notify pgrst, 'reload schema';

commit;
