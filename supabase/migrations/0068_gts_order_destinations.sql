-- GTS: persist destination terminal and Incoterm named place for order simulations
begin;

alter table public.gts_order_simulations
  add column if not exists destination_port text,
  add column if not exists named_place text;

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
      destination_port, named_place, delivery_deadline, ship_date,
      exchange_rate, transport_mode, declared_fob_usd, allocation_method,
      has_destination_broker, applies_drawback, cost_inputs,
      cost_classification, selected_incoterm, recommended_incoterm,
      recommendation, blended_margin_pct
    )
    values (
      coalesce(p_simulation->>'client_name', ''),
      nullif(p_simulation->>'order_reference', ''),
      coalesce(nullif(p_simulation->>'destination_country', ''), 'Estados Unidos'),
      nullif(p_simulation->>'destination_city', ''),
      nullif(p_simulation->>'destination_port', ''),
      nullif(p_simulation->>'named_place', ''),
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
        destination_port = nullif(p_simulation->>'destination_port', ''),
        named_place = nullif(p_simulation->>'named_place', ''),
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

grant execute on function public.gts_save_order_simulation(jsonb, jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
