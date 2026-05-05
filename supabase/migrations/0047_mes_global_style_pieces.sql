-- MES: allow master piece names without style-specific association
begin;

alter table public.mes_style_pieces
  alter column style_type_id drop not null;

update public.mes_style_pieces
set style_type_id = null
where dispatch = 'SS27';

delete from public.mes_style_pieces duplicate
using public.mes_style_pieces keeper
where duplicate.dispatch = 'SS27'
  and keeper.dispatch = 'SS27'
  and duplicate.id > keeper.id
  and lower(btrim(duplicate.name)) = lower(btrim(keeper.name));

create unique index if not exists uq_mes_style_pieces_ss27_name
  on public.mes_style_pieces(lower(btrim(name)))
  where dispatch = 'SS27';

notify pgrst, 'reload schema';

commit;
