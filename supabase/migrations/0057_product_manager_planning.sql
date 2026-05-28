-- Planning: Product Manager costing view and configurable GM semaphore rules
begin;

create table if not exists public.semaforo_reglas (
  id bigint generated always as identity primary key,
  indicador text not null check (
    indicador in ('gm_venta', 'gm_retail', 'gm_wholesale', 'gm_msrp')
  ),
  banda_id text not null check (
    banda_id in ('celeste', 'verde', 'amarillo', 'ambar', 'rojo')
  ),
  label text not null,
  color_hex text not null,
  color_soft text not null,
  min_pct numeric,
  orden int not null,
  unique (indicador, banda_id)
);

alter table public.semaforo_reglas enable row level security;

drop policy if exists "semaforo_reglas_read" on public.semaforo_reglas;
create policy "semaforo_reglas_read" on public.semaforo_reglas
  for select to authenticated
  using (true);

drop policy if exists "semaforo_reglas_insert" on public.semaforo_reglas;
create policy "semaforo_reglas_insert" on public.semaforo_reglas
  for insert to authenticated
  with check (true);

drop policy if exists "semaforo_reglas_update" on public.semaforo_reglas;
create policy "semaforo_reglas_update" on public.semaforo_reglas
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "semaforo_reglas_delete" on public.semaforo_reglas;
create policy "semaforo_reglas_delete" on public.semaforo_reglas
  for delete to authenticated
  using (true);

insert into public.semaforo_reglas (
  indicador,
  banda_id,
  label,
  color_hex,
  color_soft,
  min_pct,
  orden
)
values
  ('gm_venta', 'celeste', 'Excede', '#0e7490', '#ecfeff', 50, 1),
  ('gm_venta', 'verde', 'Optimo', '#15803d', '#f0fdf4', 40, 2),
  ('gm_venta', 'amarillo', 'Bajo minimo', '#ca8a04', '#fefce8', 20, 3),
  ('gm_venta', 'ambar', 'Riesgo', '#ea580c', '#fff7ed', 10, 4),
  ('gm_venta', 'rojo', 'Critico', '#dc2626', '#fef2f2', null, 5),
  ('gm_retail', 'celeste', 'Excede', '#0e7490', '#ecfeff', 65, 1),
  ('gm_retail', 'verde', 'Optimo', '#15803d', '#f0fdf4', 55, 2),
  ('gm_retail', 'amarillo', 'Bajo minimo', '#ca8a04', '#fefce8', 45, 3),
  ('gm_retail', 'ambar', 'Riesgo', '#ea580c', '#fff7ed', 35, 4),
  ('gm_retail', 'rojo', 'Critico', '#dc2626', '#fef2f2', null, 5),
  ('gm_wholesale', 'celeste', 'Excede', '#0e7490', '#ecfeff', 58, 1),
  ('gm_wholesale', 'verde', 'Optimo', '#15803d', '#f0fdf4', 50, 2),
  ('gm_wholesale', 'amarillo', 'Bajo minimo', '#ca8a04', '#fefce8', 40, 3),
  ('gm_wholesale', 'ambar', 'Riesgo', '#ea580c', '#fff7ed', 30, 4),
  ('gm_wholesale', 'rojo', 'Critico', '#dc2626', '#fef2f2', null, 5),
  ('gm_msrp', 'celeste', 'Excede', '#0e7490', '#ecfeff', 65, 1),
  ('gm_msrp', 'verde', 'Optimo', '#15803d', '#f0fdf4', 58, 2),
  ('gm_msrp', 'amarillo', 'Bajo minimo', '#ca8a04', '#fefce8', 50, 3),
  ('gm_msrp', 'ambar', 'Riesgo', '#ea580c', '#fff7ed', 40, 4),
  ('gm_msrp', 'rojo', 'Critico', '#dc2626', '#fef2f2', null, 5)
on conflict (indicador, banda_id)
do update set
  label = excluded.label,
  color_hex = excluded.color_hex,
  color_soft = excluded.color_soft,
  min_pct = excluded.min_pct,
  orden = excluded.orden;

drop view if exists public.v_costeo_prendas;

create view public.v_costeo_prendas
with (security_invoker = true) as
with cost_items as (
  select
    ci.garment_id,
    sum(
      coalesce(ci.quantity, 0)
      * coalesce(ci.unit_cost, 0)
      * (1 + coalesce(ci.waste_percent, 0) / 100)
      * case
          when ci.currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
          else 1
        end
    ) as insumos
  from public.mes_cost_items ci
  join public.mes_garments g on g.id = ci.garment_id
  group by ci.garment_id
),
services as (
  select
    s.garment_id,
    sum(
      coalesce(
        s.total_pen,
        coalesce(s.quantity_m, 0) * coalesce(s.rate_pen, 0)
      ) / nullif(g.exchange_rate, 0)
    ) as plizado
  from public.mes_garment_services s
  join public.mes_garments g on g.id = s.garment_id
  group by s.garment_id
),
knitting as (
  select
    kp.garment_id,
    sum(coalesce(kp.amount_pen, 0) / nullif(g.exchange_rate, 0)) as tejido
  from public.mes_knitting_production kp
  join public.mes_garments g on g.id = kp.garment_id
  where kp.piece_status = 'Terminado'
  group by kp.garment_id
)
select
  g.id,
  g.style_number,
  coalesce(nullif(btrim(g.reference_code), ''), g.style_number) as ref,
  coalesce(st.name, nullif(btrim(g.commercial_name), ''), 'Sin tipo') as tipo,
  g.status as estado,
  case g.dispatch
    when 'FW26-27' then 'fw26-27'
    when 'SS27' then 'ss27'
    when 'SS27-COM' then 'ss27-commercial'
    else lower(replace(coalesce(g.dispatch, 'sin-coleccion'), ' ', '-'))
  end as collection,
  g.dispatch,
  photo.url as foto_url,
  coalesce(ci.insumos, 0)::numeric as insumos,
  (
    coalesce(g.cutting_days, 0)
    * coalesce(cutting_labor.cost_day, 0)
    * case
        when cutting_labor.currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
        else 1
      end
  )::numeric as corte,
  (
    coalesce(g.sewing_days, 0)
    * coalesce(sewing_labor.cost_day, 0)
    * case
        when sewing_labor.currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
        else 1
      end
  )::numeric as confeccion,
  (
    coalesce(g.external_workshop_cost, 0)
    * case
        when g.external_workshop_currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
        else 1
      end
  )::numeric as taller_externo,
  coalesce(k.tejido, 0)::numeric as tejido,
  coalesce(s.plizado, 0)::numeric as plizado,
  (
    coalesce(ci.insumos, 0)
    + (
      coalesce(g.cutting_days, 0)
      * coalesce(cutting_labor.cost_day, 0)
      * case
          when cutting_labor.currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
          else 1
        end
    )
    + (
      coalesce(g.sewing_days, 0)
      * coalesce(sewing_labor.cost_day, 0)
      * case
          when sewing_labor.currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
          else 1
        end
    )
    + (
      coalesce(g.external_workshop_cost, 0)
      * case
          when g.external_workshop_currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
          else 1
        end
    )
    + coalesce(k.tejido, 0)
    + coalesce(s.plizado, 0)
  )::numeric as costo_total,
  g.msrp_simulado,
  g.margin_rate,
  g.retail_margin_rate,
  g.royalty_rate,
  g.tax_rate,
  g.admin_rate,
  g.finance_rate,
  g.gm_wholesale,
  g.gm_msrp,
  g.exchange_rate,
  (coalesce(g.margin_rate, 0) * 100)::numeric as gm_venta_pct,
  (coalesce(g.retail_margin_rate, 0) * 100)::numeric as gm_retail_pct,
  (coalesce(g.royalty_rate, 0) * 100)::numeric as regalias_pct,
  (coalesce(g.tax_rate, 0) * 100)::numeric as igv_pct,
  (coalesce(g.gm_wholesale, 0) * 100)::numeric as ws_margin_pct,
  (coalesce(g.gm_msrp, 0) * 100)::numeric as msrp_margin_pct,
  case
    when g.msrp_simulado is null then (
      coalesce(ci.insumos, 0)
      + (
        coalesce(g.cutting_days, 0)
        * coalesce(cutting_labor.cost_day, 0)
        * case
            when cutting_labor.currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
            else 1
          end
      )
      + (
        coalesce(g.sewing_days, 0)
        * coalesce(sewing_labor.cost_day, 0)
        * case
            when sewing_labor.currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
            else 1
          end
      )
      + (
        coalesce(g.external_workshop_cost, 0)
        * case
            when g.external_workshop_currency = 'PEN' then 1 / nullif(g.exchange_rate, 0)
            else 1
          end
      )
      + coalesce(k.tejido, 0)
      + coalesce(s.plizado, 0)
    )
    else (
      (
        (
          g.msrp_simulado
          * (1 - coalesce(g.gm_msrp, 0.60))
        )
        / nullif((1 + coalesce(g.tax_rate, 0)) * (1 + coalesce(g.royalty_rate, 0.15)), 0)
        * (1 - coalesce(g.gm_wholesale, 0.40))
      )
      / nullif(1 + coalesce(g.admin_rate, 0) + coalesce(g.finance_rate, 0), 0)
    )
  end::numeric as costo_objetivo
from public.mes_garments g
left join public.mes_style_types st on st.id = g.style_type_id
left join public.mes_labor_rates cutting_labor on cutting_labor.id = g.cutting_labor_id
left join public.mes_labor_rates sewing_labor on sewing_labor.id = g.sewing_labor_id
left join cost_items ci on ci.garment_id = g.id
left join services s on s.garment_id = g.id
left join knitting k on k.garment_id = g.id
left join lateral (
  select p.url
  from public.mes_garment_photos p
  where p.garment_id = g.id
  order by (p.id = g.primary_photo_id) desc, p.created_at asc
  limit 1
) photo on true;

grant select on public.v_costeo_prendas to authenticated;
grant select, insert, update, delete on public.semaforo_reglas to authenticated;
grant usage, select on sequence public.semaforo_reglas_id_seq to authenticated;

notify pgrst, 'reload schema';

commit;
