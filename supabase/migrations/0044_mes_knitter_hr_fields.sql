-- MES: add RRHH profile fields for knitters
begin;

alter table public.mes_knitters
  add column if not exists city text,
  add column if not exists hr_status text not null default 'Activa',
  add column if not exists primary_technique text not null default 'Tejido a mano',
  add column if not exists specialties text[] not null default '{}'::text[],
  add column if not exists years_experience numeric(5,2) not null default 0;

update public.mes_knitters
set
  hr_status = case
    when btrim(coalesce(hr_status, '')) in ('Activa', 'En proyecto', 'Disponible', 'Inactiva')
      then btrim(hr_status)
    when active is false then 'Inactiva'
    else 'Activa'
  end,
  primary_technique = case
    when btrim(coalesce(primary_technique, '')) in ('Tejido a mano', 'Crochet')
      then btrim(primary_technique)
    else 'Tejido a mano'
  end,
  specialties = coalesce(specialties, '{}'::text[]),
  years_experience = coalesce(years_experience, 0);

alter table public.mes_knitters
  alter column hr_status set default 'Activa',
  alter column hr_status set not null,
  alter column primary_technique set default 'Tejido a mano',
  alter column primary_technique set not null,
  alter column specialties set default '{}'::text[],
  alter column specialties set not null,
  alter column years_experience set default 0,
  alter column years_experience set not null;

alter table public.mes_knitters
  drop constraint if exists mes_knitters_hr_status_check;

alter table public.mes_knitters
  add constraint mes_knitters_hr_status_check
  check (hr_status in ('Activa', 'En proyecto', 'Disponible', 'Inactiva'));

alter table public.mes_knitters
  drop constraint if exists mes_knitters_primary_technique_check;

alter table public.mes_knitters
  add constraint mes_knitters_primary_technique_check
  check (primary_technique in ('Tejido a mano', 'Crochet'));

alter table public.mes_knitters
  drop constraint if exists mes_knitters_years_experience_nonnegative;

alter table public.mes_knitters
  add constraint mes_knitters_years_experience_nonnegative
  check (years_experience >= 0);

with ranked_dni as (
  select
    id,
    row_number() over (
      partition by lower(btrim(dni))
      order by created_at, id
    ) as duplicate_rank
  from public.mes_knitters
  where dni is not null
    and btrim(dni) <> ''
)
update public.mes_knitters k
set dni = null
from ranked_dni d
where k.id = d.id
  and d.duplicate_rank > 1;

create unique index if not exists uq_mes_knitters_dni
  on public.mes_knitters(lower(btrim(dni)))
  where dni is not null and btrim(dni) <> '';

create index if not exists idx_mes_knitters_hr_status
  on public.mes_knitters(hr_status);

create index if not exists idx_mes_knitters_primary_technique
  on public.mes_knitters(primary_technique);

notify pgrst, 'reload schema';

commit;
