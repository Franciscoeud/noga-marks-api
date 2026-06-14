-- GTS: origin profiles, customs lanes, NMF duty rates and order-line results
begin;

create table if not exists public.gts_customs_blocs (
  code text primary key,
  label text not null,
  origin_rule text not null,
  tolerance_pct numeric(7,4) not null default 10,
  preferential_rate numeric(8,6) not null default 0,
  vat_recoverable boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint gts_customs_blocs_code_check check (code in ('EU', 'US')),
  constraint gts_customs_blocs_rate_check
    check (
      tolerance_pct >= 0 and tolerance_pct <= 100
      and preferential_rate >= 0 and preferential_rate <= 1
    )
);

create table if not exists public.gts_lanes (
  code text primary key,
  customs_bloc_code text not null references public.gts_customs_blocs(code) on delete restrict,
  country_name text not null,
  vat_rate numeric(8,6) not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint gts_lanes_code_check check (code in ('IT', 'FR', 'US')),
  constraint gts_lanes_vat_rate_check check (vat_rate >= 0 and vat_rate <= 1)
);

create table if not exists public.gts_duty_rates (
  id uuid primary key default uuid_generate_v4(),
  customs_bloc_code text not null references public.gts_customs_blocs(code) on delete cascade,
  hs_code text not null,
  nmf_rate numeric(8,6) not null,
  valid_from date not null,
  valid_to date,
  source text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint gts_duty_rates_hs_check
    check (hs_code ~ '^[0-9]+$' and length(hs_code) in (4, 6, 8, 10)),
  constraint gts_duty_rates_rate_check check (nmf_rate >= 0 and nmf_rate <= 1),
  constraint gts_duty_rates_dates_check check (valid_to is null or valid_to >= valid_from),
  constraint uq_gts_duty_rates_bloc_hs_from unique (customs_bloc_code, hs_code, valid_from)
);

create table if not exists public.gts_origin_profiles (
  garment_id uuid primary key references public.mes_garments(id) on delete cascade,
  construction text not null,
  hs_code text not null,
  fabric_country_code text,
  fabric_is_eu_originating boolean not null default false,
  yarn_country_code text,
  making_up_country_code text not null default 'PE',
  fiber_composition jsonb not null default '[]'::jsonb,
  non_originating_textile_weight_pct numeric(7,4) not null default 0,
  contains_elastomeric_yarn boolean not null default false,
  has_sensitive_components boolean not null default false,
  sensitive_components_note text,
  non_originating_trims_note text,
  short_supply_override boolean not null default false,
  override_note text,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint gts_origin_profiles_construction_check
    check (construction in ('knit', 'woven', 'sweater', 'other')),
  constraint gts_origin_profiles_hs_check
    check (hs_code ~ '^[0-9]+$' and length(hs_code) in (4, 6, 8, 10)),
  constraint gts_origin_profiles_country_codes_check
    check (
      (fabric_country_code is null or fabric_country_code ~ '^[A-Z]{2}$')
      and (yarn_country_code is null or yarn_country_code ~ '^[A-Z]{2}$')
      and making_up_country_code ~ '^[A-Z]{2}$'
    ),
  constraint gts_origin_profiles_non_originating_check
    check (non_originating_textile_weight_pct >= 0 and non_originating_textile_weight_pct <= 100),
  constraint gts_origin_profiles_override_note_check
    check (not short_supply_override or nullif(btrim(override_note), '') is not null)
);

alter table public.gts_order_simulation_items
  add column if not exists origin_results jsonb not null default '{}'::jsonb;

create index if not exists idx_gts_duty_rates_lookup
  on public.gts_duty_rates(customs_bloc_code, hs_code, valid_from desc);
create index if not exists idx_gts_origin_profiles_hs
  on public.gts_origin_profiles(hs_code);

drop trigger if exists trg_gts_customs_blocs_updated_at on public.gts_customs_blocs;
create trigger trg_gts_customs_blocs_updated_at
before update on public.gts_customs_blocs
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_gts_lanes_updated_at on public.gts_lanes;
create trigger trg_gts_lanes_updated_at
before update on public.gts_lanes
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_gts_duty_rates_updated_at on public.gts_duty_rates;
create trigger trg_gts_duty_rates_updated_at
before update on public.gts_duty_rates
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_gts_origin_profiles_updated_at on public.gts_origin_profiles;
create trigger trg_gts_origin_profiles_updated_at
before update on public.gts_origin_profiles
for each row execute procedure public.set_updated_at();

alter table public.gts_customs_blocs enable row level security;
alter table public.gts_lanes enable row level security;
alter table public.gts_duty_rates enable row level security;
alter table public.gts_origin_profiles enable row level security;

drop policy if exists "gts_customs_blocs_read" on public.gts_customs_blocs;
create policy "gts_customs_blocs_read" on public.gts_customs_blocs
  for select to authenticated using (true);
drop policy if exists "gts_customs_blocs_insert" on public.gts_customs_blocs;
create policy "gts_customs_blocs_insert" on public.gts_customs_blocs
  for insert to authenticated with check (true);
drop policy if exists "gts_customs_blocs_update" on public.gts_customs_blocs;
create policy "gts_customs_blocs_update" on public.gts_customs_blocs
  for update to authenticated using (true) with check (true);
drop policy if exists "gts_customs_blocs_delete" on public.gts_customs_blocs;
create policy "gts_customs_blocs_delete" on public.gts_customs_blocs
  for delete to authenticated using (true);

drop policy if exists "gts_lanes_read" on public.gts_lanes;
create policy "gts_lanes_read" on public.gts_lanes
  for select to authenticated using (true);
drop policy if exists "gts_lanes_insert" on public.gts_lanes;
create policy "gts_lanes_insert" on public.gts_lanes
  for insert to authenticated with check (true);
drop policy if exists "gts_lanes_update" on public.gts_lanes;
create policy "gts_lanes_update" on public.gts_lanes
  for update to authenticated using (true) with check (true);
drop policy if exists "gts_lanes_delete" on public.gts_lanes;
create policy "gts_lanes_delete" on public.gts_lanes
  for delete to authenticated using (true);

drop policy if exists "gts_duty_rates_read" on public.gts_duty_rates;
create policy "gts_duty_rates_read" on public.gts_duty_rates
  for select to authenticated using (true);
drop policy if exists "gts_duty_rates_insert" on public.gts_duty_rates;
create policy "gts_duty_rates_insert" on public.gts_duty_rates
  for insert to authenticated with check (true);
drop policy if exists "gts_duty_rates_update" on public.gts_duty_rates;
create policy "gts_duty_rates_update" on public.gts_duty_rates
  for update to authenticated using (true) with check (true);
drop policy if exists "gts_duty_rates_delete" on public.gts_duty_rates;
create policy "gts_duty_rates_delete" on public.gts_duty_rates
  for delete to authenticated using (true);

drop policy if exists "gts_origin_profiles_read" on public.gts_origin_profiles;
create policy "gts_origin_profiles_read" on public.gts_origin_profiles
  for select to authenticated using (true);
drop policy if exists "gts_origin_profiles_insert" on public.gts_origin_profiles;
create policy "gts_origin_profiles_insert" on public.gts_origin_profiles
  for insert to authenticated with check (true);
drop policy if exists "gts_origin_profiles_update" on public.gts_origin_profiles;
create policy "gts_origin_profiles_update" on public.gts_origin_profiles
  for update to authenticated using (true) with check (true);
drop policy if exists "gts_origin_profiles_delete" on public.gts_origin_profiles;
create policy "gts_origin_profiles_delete" on public.gts_origin_profiles
  for delete to authenticated using (true);

insert into public.gts_customs_blocs (
  code, label, origin_rule, tolerance_pct, preferential_rate, vat_recoverable
)
values
  ('EU', 'Union Europea', 'from_yarn', 10, 0, true),
  ('US', 'Estados Unidos', 'yarn_forward', 10, 0, false)
on conflict (code) do update set
  label = excluded.label,
  origin_rule = excluded.origin_rule,
  tolerance_pct = excluded.tolerance_pct,
  preferential_rate = excluded.preferential_rate,
  vat_recoverable = excluded.vat_recoverable;

insert into public.gts_lanes (code, customs_bloc_code, country_name, vat_rate)
values
  ('IT', 'EU', 'Italia', 0.22),
  ('FR', 'EU', 'Francia', 0.20),
  ('US', 'US', 'Estados Unidos', 0)
on conflict (code) do update set
  customs_bloc_code = excluded.customs_bloc_code,
  country_name = excluded.country_name,
  vat_rate = excluded.vat_rate;

create or replace function public.gts_save_order_simulation(
  p_simulation jsonb,
  p_items jsonb,
  p_profiles jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_id uuid := nullif(p_simulation->>'id', '')::uuid;
  v_item jsonb;
  v_profile jsonb;
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

  for v_profile in select * from jsonb_array_elements(coalesce(p_profiles, '[]'::jsonb))
  loop
    insert into public.gts_origin_profiles (
      garment_id, construction, hs_code, fabric_country_code,
      fabric_is_eu_originating, yarn_country_code, making_up_country_code,
      fiber_composition, non_originating_textile_weight_pct,
      contains_elastomeric_yarn, has_sensitive_components,
      sensitive_components_note, non_originating_trims_note,
      short_supply_override, override_note, notes
    )
    values (
      (v_profile->>'garment_id')::uuid,
      v_profile->>'construction',
      v_profile->>'hs_code',
      nullif(v_profile->>'fabric_country_code', ''),
      coalesce((v_profile->>'fabric_is_eu_originating')::boolean, false),
      nullif(v_profile->>'yarn_country_code', ''),
      coalesce(nullif(v_profile->>'making_up_country_code', ''), 'PE'),
      coalesce(v_profile->'fiber_composition', '[]'::jsonb),
      coalesce((v_profile->>'non_originating_textile_weight_pct')::numeric, 0),
      coalesce((v_profile->>'contains_elastomeric_yarn')::boolean, false),
      coalesce((v_profile->>'has_sensitive_components')::boolean, false),
      nullif(v_profile->>'sensitive_components_note', ''),
      nullif(v_profile->>'non_originating_trims_note', ''),
      coalesce((v_profile->>'short_supply_override')::boolean, false),
      nullif(v_profile->>'override_note', ''),
      nullif(v_profile->>'notes', '')
    )
    on conflict (garment_id) do update set
      construction = excluded.construction,
      hs_code = excluded.hs_code,
      fabric_country_code = excluded.fabric_country_code,
      fabric_is_eu_originating = excluded.fabric_is_eu_originating,
      yarn_country_code = excluded.yarn_country_code,
      making_up_country_code = excluded.making_up_country_code,
      fiber_composition = excluded.fiber_composition,
      non_originating_textile_weight_pct = excluded.non_originating_textile_weight_pct,
      contains_elastomeric_yarn = excluded.contains_elastomeric_yarn,
      has_sensitive_components = excluded.has_sensitive_components,
      sensitive_components_note = excluded.sensitive_components_note,
      non_originating_trims_note = excluded.non_originating_trims_note,
      short_supply_override = excluded.short_supply_override,
      override_note = excluded.override_note,
      notes = excluded.notes;
  end loop;

  delete from public.gts_order_simulation_items where simulation_id = v_id;
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    insert into public.gts_order_simulation_items (
      simulation_id, garment_id, garment_label, quantity, unit_cost_usd,
      wholesale_price_usd, unit_weight_kg, origin_results
    )
    values (
      v_id,
      (v_item->>'garment_id')::uuid,
      v_item->>'garment_label',
      (v_item->>'quantity')::integer,
      (v_item->>'unit_cost_usd')::numeric,
      (v_item->>'wholesale_price_usd')::numeric,
      (v_item->>'unit_weight_kg')::numeric,
      coalesce(v_item->'origin_results', '{}'::jsonb)
    );
  end loop;

  return v_id;
end;
$$;

create or replace function public.gts_save_order_simulation(
  p_simulation jsonb,
  p_items jsonb
)
returns uuid
language sql
security invoker
set search_path = public
as $$
  select public.gts_save_order_simulation(p_simulation, p_items, '[]'::jsonb);
$$;

grant select, insert, update, delete on public.gts_customs_blocs to authenticated;
grant select, insert, update, delete on public.gts_lanes to authenticated;
grant select, insert, update, delete on public.gts_duty_rates to authenticated;
grant select, insert, update, delete on public.gts_origin_profiles to authenticated;
grant execute on function public.gts_save_order_simulation(jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.gts_save_order_simulation(jsonb, jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
