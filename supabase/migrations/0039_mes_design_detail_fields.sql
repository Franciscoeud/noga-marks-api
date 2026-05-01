-- MES: design detail metadata and optional knitter photos for Colecciones
begin;

alter table public.mes_garments
  add column if not exists commercial_name text,
  add column if not exists technique text,
  add column if not exists material text,
  add column if not exists design_color text,
  add column if not exists sizes text[] default array['S', 'M', 'L'],
  add column if not exists size_curve jsonb default '{"S": 0, "M": 0, "L": 0}'::jsonb;

update public.mes_garments
set sizes = array['S', 'M', 'L']
where sizes is null or cardinality(sizes) = 0;

update public.mes_garments
set size_curve = '{"S": 0, "M": 0, "L": 0}'::jsonb
where size_curve is null;

alter table public.mes_knitters
  add column if not exists photo_url text,
  add column if not exists photo_path text;

notify pgrst, 'reload schema';

commit;
