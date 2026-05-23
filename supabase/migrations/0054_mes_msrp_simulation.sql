-- MES: add MSRP commercial simulation fields
begin;

alter table public.mes_garments
  add column if not exists msrp_simulado numeric,
  add column if not exists gm_msrp numeric default 0.60,
  add column if not exists gm_wholesale numeric default 0.40;

update public.mes_garments
set gm_msrp = 0.60
where gm_msrp is null;

update public.mes_garments
set gm_wholesale = 0.40
where gm_wholesale is null;

alter table public.mes_garments
  alter column gm_msrp set default 0.60,
  alter column gm_msrp set not null,
  alter column gm_wholesale set default 0.40,
  alter column gm_wholesale set not null;

alter table public.mes_garments
  drop constraint if exists mes_garments_msrp_simulado_check;

alter table public.mes_garments
  add constraint mes_garments_msrp_simulado_check
  check (msrp_simulado is null or msrp_simulado >= 0);

alter table public.mes_garments
  drop constraint if exists mes_garments_gm_msrp_check;

alter table public.mes_garments
  add constraint mes_garments_gm_msrp_check
  check (gm_msrp >= 0 and gm_msrp < 1);

alter table public.mes_garments
  drop constraint if exists mes_garments_gm_wholesale_check;

alter table public.mes_garments
  add constraint mes_garments_gm_wholesale_check
  check (gm_wholesale >= 0 and gm_wholesale < 1);

notify pgrst, 'reload schema';

commit;
