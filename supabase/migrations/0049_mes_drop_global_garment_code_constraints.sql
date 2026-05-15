-- MES: remove old global garment code constraints after collection-scoped uniqueness
begin;

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'mes_garments'
      and c.contype = 'u'
      and (
        c.conname in (
          'mes_garments_style_number_unique',
          'mes_garments_reference_code_unique'
        )
        or exists (
          select 1
          from unnest(c.conkey) with ordinality as key(attnum, ord)
          join pg_attribute a
            on a.attrelid = c.conrelid
           and a.attnum = key.attnum
          group by c.oid
          having array_agg(a.attname::text order by key.ord) in (
            array['style_number']::text[],
            array['reference_code']::text[]
          )
        )
      )
  loop
    execute format('alter table public.mes_garments drop constraint if exists %I', constraint_name);
  end loop;
end $$;

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
