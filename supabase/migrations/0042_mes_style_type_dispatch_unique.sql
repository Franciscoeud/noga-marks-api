-- MES: allow the same style names in different seasons
begin;

alter table public.mes_style_types
  drop constraint if exists mes_style_types_name_unique;

drop index if exists public.mes_style_types_name_unique;

create unique index if not exists uq_mes_style_types_dispatch_name
  on public.mes_style_types(dispatch, lower(btrim(name)));

notify pgrst, 'reload schema';

commit;
