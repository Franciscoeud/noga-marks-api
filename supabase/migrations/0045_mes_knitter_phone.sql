-- MES: add phone number for knitter profiles
begin;

alter table public.mes_knitters
  add column if not exists phone text;

notify pgrst, 'reload schema';

commit;
