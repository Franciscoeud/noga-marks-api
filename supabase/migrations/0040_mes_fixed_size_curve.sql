-- MES: standardize garment size curve to fixed XXS-XXL range
begin;

alter table public.mes_garments
  alter column sizes set default array['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL']::text[],
  alter column size_curve set default '{"XXS": 0, "XS": 0, "S": 0, "M": 0, "L": 0, "XL": 0, "XXL": 0}'::jsonb;

update public.mes_garments
set
  sizes = array['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL']::text[],
  size_curve = jsonb_build_object(
    'XXS', coalesce((coalesce(size_curve, '{}'::jsonb)->>'XXS')::numeric, 0),
    'XS', coalesce((coalesce(size_curve, '{}'::jsonb)->>'XS')::numeric, 0),
    'S', coalesce((coalesce(size_curve, '{}'::jsonb)->>'S')::numeric, 0),
    'M', coalesce((coalesce(size_curve, '{}'::jsonb)->>'M')::numeric, 0),
    'L', coalesce((coalesce(size_curve, '{}'::jsonb)->>'L')::numeric, 0),
    'XL', coalesce((coalesce(size_curve, '{}'::jsonb)->>'XL')::numeric, 0),
    'XXL', coalesce((coalesce(size_curve, '{}'::jsonb)->>'XXL')::numeric, 0)
  )
where sizes is distinct from array['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL']::text[]
  or size_curve is null
  or not (
    size_curve ? 'XXS'
    and size_curve ? 'XS'
    and size_curve ? 'S'
    and size_curve ? 'M'
    and size_curve ? 'L'
    and size_curve ? 'XL'
    and size_curve ? 'XXL'
  );

notify pgrst, 'reload schema';

commit;
