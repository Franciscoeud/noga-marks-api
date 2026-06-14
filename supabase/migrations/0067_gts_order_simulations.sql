-- GTS: multi-style purchase order simulations
begin;

alter table public.gts_export_simulations
  drop constraint if exists gts_export_simulations_transport_mode_check;
alter table public.gts_export_simulations
  add constraint gts_export_simulations_transport_mode_check
  check (transport_mode in ('exporta_facil', 'courier', 'aereo', 'maritimo', 'terrestre'));

alter table public.semaforo_reglas
  drop constraint if exists semaforo_reglas_indicador_check;
alter table public.semaforo_reglas
  add constraint semaforo_reglas_indicador_check
  check (indicador in ('gm_venta', 'gm_retail', 'gm_wholesale', 'gm_msrp', 'gts_margen_blended'));

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
  ('gts_margen_blended', 'verde', 'Saludable', '#15803d', '#f0fdf4', 40, 1),
  ('gts_margen_blended', 'ambar', 'Ajustado', '#d97706', '#fffbeb', 25, 2),
  ('gts_margen_blended', 'rojo', 'Critico', '#dc2626', '#fef2f2', null, 3)
on conflict (indicador, banda_id)
do update set
  label = excluded.label,
  color_hex = excluded.color_hex,
  color_soft = excluded.color_soft,
  min_pct = excluded.min_pct,
  orden = excluded.orden;

create table if not exists public.gts_order_simulations (
  id uuid primary key default uuid_generate_v4(),
  client_name text not null default '',
  order_reference text,
  destination_country text not null default 'Estados Unidos',
  destination_city text,
  delivery_deadline date,
  ship_date date,
  exchange_rate numeric(12,4) not null default 3.7000,
  transport_mode text not null default 'courier',
  declared_fob_usd numeric(14,4) not null default 0,
  allocation_method text not null default 'by_units',
  has_destination_broker boolean not null default false,
  applies_drawback boolean not null default false,
  cost_inputs jsonb not null default '{}'::jsonb,
  cost_classification jsonb not null default '{}'::jsonb,
  selected_incoterm text,
  recommended_incoterm text,
  recommendation jsonb,
  blended_margin_pct numeric(12,4),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint gts_order_simulations_transport_mode_check
    check (transport_mode in ('exporta_facil', 'courier', 'aereo', 'maritimo')),
  constraint gts_order_simulations_allocation_method_check
    check (allocation_method in ('by_units', 'by_value')),
  constraint gts_order_simulations_incoterm_check
    check (
      selected_incoterm is null
      or selected_incoterm in ('EXW', 'FCA', 'FAS', 'FOB', 'CFR', 'CIF', 'CPT', 'CIP', 'DAP', 'DPU', 'DDP')
    ),
  constraint gts_order_simulations_recommended_incoterm_check
    check (
      recommended_incoterm is null
      or recommended_incoterm in ('EXW', 'FCA', 'FAS', 'FOB', 'CFR', 'CIF', 'CPT', 'CIP', 'DAP', 'DPU', 'DDP')
    ),
  constraint gts_order_simulations_nonnegative_check
    check (exchange_rate >= 0 and declared_fob_usd >= 0)
);

create table if not exists public.gts_order_simulation_items (
  id uuid primary key default uuid_generate_v4(),
  simulation_id uuid not null references public.gts_order_simulations(id) on delete cascade,
  garment_id uuid not null references public.mes_garments(id) on delete restrict,
  garment_label text not null,
  quantity integer not null check (quantity > 0),
  unit_cost_usd numeric(14,4) not null check (unit_cost_usd >= 0),
  wholesale_price_usd numeric(14,4) not null check (wholesale_price_usd >= 0),
  unit_weight_kg numeric(10,3) not null default 0.500 check (unit_weight_kg > 0),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint uq_gts_order_simulation_items_garment
    unique (simulation_id, garment_id)
);

create index if not exists idx_gts_order_simulations_updated
  on public.gts_order_simulations(updated_at desc);
create index if not exists idx_gts_order_simulation_items_simulation
  on public.gts_order_simulation_items(simulation_id);
create index if not exists idx_gts_order_simulation_items_garment
  on public.gts_order_simulation_items(garment_id);

drop trigger if exists trg_gts_order_simulations_updated_at on public.gts_order_simulations;
create trigger trg_gts_order_simulations_updated_at
before update on public.gts_order_simulations
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_gts_order_simulation_items_updated_at on public.gts_order_simulation_items;
create trigger trg_gts_order_simulation_items_updated_at
before update on public.gts_order_simulation_items
for each row execute procedure public.set_updated_at();

alter table public.gts_order_simulations enable row level security;
alter table public.gts_order_simulation_items enable row level security;

drop policy if exists "gts_order_simulations_read" on public.gts_order_simulations;
create policy "gts_order_simulations_read" on public.gts_order_simulations
  for select to authenticated using (true);
drop policy if exists "gts_order_simulations_insert" on public.gts_order_simulations;
create policy "gts_order_simulations_insert" on public.gts_order_simulations
  for insert to authenticated with check (true);
drop policy if exists "gts_order_simulations_update" on public.gts_order_simulations;
create policy "gts_order_simulations_update" on public.gts_order_simulations
  for update to authenticated using (true) with check (true);
drop policy if exists "gts_order_simulations_delete" on public.gts_order_simulations;
create policy "gts_order_simulations_delete" on public.gts_order_simulations
  for delete to authenticated using (true);

drop policy if exists "gts_order_simulation_items_read" on public.gts_order_simulation_items;
create policy "gts_order_simulation_items_read" on public.gts_order_simulation_items
  for select to authenticated using (true);
drop policy if exists "gts_order_simulation_items_insert" on public.gts_order_simulation_items;
create policy "gts_order_simulation_items_insert" on public.gts_order_simulation_items
  for insert to authenticated with check (true);
drop policy if exists "gts_order_simulation_items_update" on public.gts_order_simulation_items;
create policy "gts_order_simulation_items_update" on public.gts_order_simulation_items
  for update to authenticated using (true) with check (true);
drop policy if exists "gts_order_simulation_items_delete" on public.gts_order_simulation_items;
create policy "gts_order_simulation_items_delete" on public.gts_order_simulation_items
  for delete to authenticated using (true);

create or replace function public.gts_save_order_simulation(
  p_simulation jsonb,
  p_items jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid := nullif(p_simulation->>'id', '')::uuid;
  v_item jsonb;
begin
  if v_id is null then
    insert into public.gts_order_simulations (
      client_name, order_reference, destination_country, destination_city,
      delivery_deadline, ship_date, exchange_rate, transport_mode,
      declared_fob_usd, allocation_method, has_destination_broker,
      applies_drawback, cost_inputs, cost_classification, selected_incoterm,
      recommended_incoterm, recommendation, blended_margin_pct
    )
    values (
      coalesce(p_simulation->>'client_name', ''),
      nullif(p_simulation->>'order_reference', ''),
      coalesce(nullif(p_simulation->>'destination_country', ''), 'Estados Unidos'),
      nullif(p_simulation->>'destination_city', ''),
      nullif(p_simulation->>'delivery_deadline', '')::date,
      nullif(p_simulation->>'ship_date', '')::date,
      coalesce((p_simulation->>'exchange_rate')::numeric, 3.7),
      coalesce(nullif(p_simulation->>'transport_mode', ''), 'courier'),
      coalesce((p_simulation->>'declared_fob_usd')::numeric, 0),
      coalesce(nullif(p_simulation->>'allocation_method', ''), 'by_units'),
      coalesce((p_simulation->>'has_destination_broker')::boolean, false),
      coalesce((p_simulation->>'applies_drawback')::boolean, false),
      coalesce(p_simulation->'cost_inputs', '{}'::jsonb),
      coalesce(p_simulation->'cost_classification', '{}'::jsonb),
      nullif(p_simulation->>'selected_incoterm', ''),
      nullif(p_simulation->>'recommended_incoterm', ''),
      p_simulation->'recommendation',
      nullif(p_simulation->>'blended_margin_pct', '')::numeric
    )
    returning id into v_id;
  else
    update public.gts_order_simulations
    set client_name = coalesce(p_simulation->>'client_name', ''),
        order_reference = nullif(p_simulation->>'order_reference', ''),
        destination_country = coalesce(nullif(p_simulation->>'destination_country', ''), 'Estados Unidos'),
        destination_city = nullif(p_simulation->>'destination_city', ''),
        delivery_deadline = nullif(p_simulation->>'delivery_deadline', '')::date,
        ship_date = nullif(p_simulation->>'ship_date', '')::date,
        exchange_rate = coalesce((p_simulation->>'exchange_rate')::numeric, 3.7),
        transport_mode = coalesce(nullif(p_simulation->>'transport_mode', ''), 'courier'),
        declared_fob_usd = coalesce((p_simulation->>'declared_fob_usd')::numeric, 0),
        allocation_method = coalesce(nullif(p_simulation->>'allocation_method', ''), 'by_units'),
        has_destination_broker = coalesce((p_simulation->>'has_destination_broker')::boolean, false),
        applies_drawback = coalesce((p_simulation->>'applies_drawback')::boolean, false),
        cost_inputs = coalesce(p_simulation->'cost_inputs', '{}'::jsonb),
        cost_classification = coalesce(p_simulation->'cost_classification', '{}'::jsonb),
        selected_incoterm = nullif(p_simulation->>'selected_incoterm', ''),
        recommended_incoterm = nullif(p_simulation->>'recommended_incoterm', ''),
        recommendation = p_simulation->'recommendation',
        blended_margin_pct = nullif(p_simulation->>'blended_margin_pct', '')::numeric
    where id = v_id;

    if not found then
      raise exception 'No existe la simulacion GTS por orden %.', v_id;
    end if;
  end if;

  delete from public.gts_order_simulation_items where simulation_id = v_id;
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    insert into public.gts_order_simulation_items (
      simulation_id, garment_id, garment_label, quantity, unit_cost_usd,
      wholesale_price_usd, unit_weight_kg
    )
    values (
      v_id,
      (v_item->>'garment_id')::uuid,
      v_item->>'garment_label',
      (v_item->>'quantity')::integer,
      (v_item->>'unit_cost_usd')::numeric,
      (v_item->>'wholesale_price_usd')::numeric,
      (v_item->>'unit_weight_kg')::numeric
    );
  end loop;

  return v_id;
end;
$$;

grant select, insert, update, delete on public.gts_order_simulations to authenticated;
grant select, insert, update, delete on public.gts_order_simulation_items to authenticated;
grant execute on function public.gts_save_order_simulation(jsonb, jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
