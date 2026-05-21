-- MES: extend garment and knitting piece status options
begin;

update public.mes_knitting_production
set piece_status = 'En proceso'
where piece_status = 'Pausado';

alter table public.mes_garments
  drop constraint if exists mes_garments_status_check;

alter table public.mes_garments
  add constraint mes_garments_status_check
  check (status in ('En proceso', 'Terminado', 'Cancelado', 'Descartado'));

alter table public.mes_knitting_production
  alter column piece_status set default 'En proceso';

alter table public.mes_knitting_production
  drop constraint if exists mes_knitting_production_piece_status_check;

alter table public.mes_knitting_production
  add constraint mes_knitting_production_piece_status_check
  check (
    piece_status is null
    or piece_status in ('En proceso', 'Terminado', 'Cancelado', 'Descartado')
  );

notify pgrst, 'reload schema';

commit;
