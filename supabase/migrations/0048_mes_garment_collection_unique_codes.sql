-- MES: enforce garment code uniqueness within each collection
begin;

do $$
declare
  duplicate_summary text;
begin
  select string_agg(
    format('dispatch=%s, style_number=%s, count=%s', dispatch, style_number_key, duplicate_count),
    '; '
  )
  into duplicate_summary
  from (
    select
      dispatch,
      lower(btrim(style_number)) as style_number_key,
      count(*) as duplicate_count
    from public.mes_garments
    where dispatch is not null
      and btrim(style_number) <> ''
    group by dispatch, lower(btrim(style_number))
    having count(*) > 1
  ) duplicates;

  if duplicate_summary is not null then
    raise exception 'Duplicate MES style numbers exist within the same collection: %', duplicate_summary;
  end if;
end $$;

do $$
declare
  duplicate_summary text;
begin
  select string_agg(
    format('dispatch=%s, reference_code=%s, count=%s', dispatch, reference_code_key, duplicate_count),
    '; '
  )
  into duplicate_summary
  from (
    select
      dispatch,
      lower(btrim(reference_code)) as reference_code_key,
      count(*) as duplicate_count
    from public.mes_garments
    where dispatch is not null
      and reference_code is not null
      and btrim(reference_code) <> ''
    group by dispatch, lower(btrim(reference_code))
    having count(*) > 1
  ) duplicates;

  if duplicate_summary is not null then
    raise exception 'Duplicate MES reference codes exist within the same collection: %', duplicate_summary;
  end if;
end $$;

alter table public.mes_garments
  drop constraint if exists mes_garments_style_number_unique;

alter table public.mes_garments
  drop constraint if exists mes_garments_reference_code_unique;

drop index if exists public.uq_mes_garments_style_number;
drop index if exists public.uq_mes_garments_reference_code;

create unique index if not exists uq_mes_garments_dispatch_style_number
  on public.mes_garments(dispatch, lower(btrim(style_number)))
  where dispatch is not null
    and btrim(style_number) <> '';

create unique index if not exists uq_mes_garments_dispatch_reference_code
  on public.mes_garments(dispatch, lower(btrim(reference_code)))
  where dispatch is not null
    and reference_code is not null
    and btrim(reference_code) <> '';

notify pgrst, 'reload schema';

commit;
