-- MES: add royalty rate for garment commercial pricing
begin;

alter table public.mes_garments
  add column if not exists royalty_rate numeric default 0.15;

update public.mes_garments
set royalty_rate = 0.15
where royalty_rate is null;

alter table public.mes_garments
  alter column royalty_rate set default 0.15,
  alter column royalty_rate set not null;

alter table public.mes_garments
  drop constraint if exists mes_garments_royalty_rate_check;

alter table public.mes_garments
  add constraint mes_garments_royalty_rate_check
  check (royalty_rate >= 0);

notify pgrst, 'reload schema';

commit;
