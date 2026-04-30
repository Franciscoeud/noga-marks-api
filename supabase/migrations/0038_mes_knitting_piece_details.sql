-- MES: add full piece detail fields for the white Colecciones flow
begin;

alter table public.mes_knitting_production
  add column if not exists piece_type text default 'Principal',
  add column if not exists piece_description text,
  add column if not exists piece_status text default 'En proceso',
  add column if not exists thread_color text,
  add column if not exists thread_type text,
  add column if not exists thread_thickness text,
  add column if not exists piece_weight_g numeric(12,3),
  add column if not exists thread_weight_used_g numeric(12,3),
  add column if not exists stitch_used text,
  add column if not exists thread_quantity numeric(12,4),
  add column if not exists color_code text;

alter table public.mes_knitting_production
  drop constraint if exists mes_knitting_production_piece_status_check;

alter table public.mes_knitting_production
  add constraint mes_knitting_production_piece_status_check
  check (
    piece_status is null
    or piece_status in ('En proceso', 'Terminado', 'Pausado', 'Cancelado')
  );

create index if not exists idx_mes_knitting_production_piece_status
  on public.mes_knitting_production(piece_status);

notify pgrst, 'reload schema';

commit;
