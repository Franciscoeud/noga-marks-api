-- GTS: export simulations linked to MES garment costing
begin;

create extension if not exists "uuid-ossp";

create table if not exists public.gts_export_simulations (
  id uuid primary key default uuid_generate_v4(),
  design_id uuid not null references public.mes_garments(id) on delete cascade,
  country_destination text not null default 'Estados Unidos',
  city_destination text not null default 'New York',
  destination_port text not null default 'New York, USA',
  incoterm text not null default 'DDP',
  named_place text not null default 'New York, USA',
  transport_mode text not null default 'courier',
  currency text not null default 'USD',
  exchange_rate numeric(12,4) not null default 3.7000,
  production_cost_usd numeric(14,4) not null default 0,
  production_cost_pen numeric(14,4) not null default 0,
  packaging_cost_usd numeric(14,4) not null default 0,
  labels_cost_usd numeric(14,4) not null default 0,
  certificate_origin_cost_usd numeric(14,4) not null default 0,
  peru_customs_agent_usd numeric(14,4) not null default 0,
  peru_internal_transport_usd numeric(14,4) not null default 0,
  origin_handling_usd numeric(14,4) not null default 0,
  export_documentation_usd numeric(14,4) not null default 0,
  origin_port_costs_usd numeric(14,4) not null default 0,
  other_origin_costs_usd numeric(14,4) not null default 0,
  international_freight_usd numeric(14,4) not null default 0,
  international_insurance_usd numeric(14,4) not null default 0,
  destination_handling_usd numeric(14,4) not null default 0,
  usa_broker_fee_usd numeric(14,4) not null default 0,
  usa_mpf_fee_usd numeric(14,4) not null default 0,
  usa_internal_transport_usd numeric(14,4) not null default 0,
  final_delivery_usd numeric(14,4) not null default 0,
  unloading_destination_usd numeric(14,4) not null default 0,
  other_destination_costs_usd numeric(14,4) not null default 0,
  ad_valorem_pct numeric(8,4) not null default 6,
  preferential_tariff_pct numeric(8,4) not null default 0,
  trade_agreement_applicable boolean not null default false,
  trade_agreement_name text not null default 'Peru - USA',
  ad_valorem_base_usd numeric(14,4),
  ad_valorem_amount_usd numeric(14,4) not null default 0,
  tlc_savings_usd numeric(14,4) not null default 0,
  exw_usd numeric(14,4) not null default 0,
  fca_usd numeric(14,4) not null default 0,
  fas_usd numeric(14,4) not null default 0,
  fob_usd numeric(14,4) not null default 0,
  cfr_usd numeric(14,4) not null default 0,
  cif_usd numeric(14,4) not null default 0,
  cpt_usd numeric(14,4) not null default 0,
  cip_usd numeric(14,4) not null default 0,
  dap_usd numeric(14,4) not null default 0,
  dpu_usd numeric(14,4) not null default 0,
  ddp_usd numeric(14,4) not null default 0,
  landed_cost_usd numeric(14,4) not null default 0,
  notes text,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint gts_export_simulations_incoterm_check
    check (incoterm in ('EXW', 'FCA', 'FAS', 'FOB', 'CFR', 'CIF', 'CPT', 'CIP', 'DAP', 'DPU', 'DDP')),
  constraint gts_export_simulations_transport_mode_check
    check (transport_mode in ('courier', 'aereo', 'maritimo', 'terrestre')),
  constraint gts_export_simulations_currency_check check (currency = 'USD'),
  constraint gts_export_simulations_nonnegative_check check (
    exchange_rate >= 0
    and production_cost_usd >= 0
    and production_cost_pen >= 0
    and packaging_cost_usd >= 0
    and labels_cost_usd >= 0
    and certificate_origin_cost_usd >= 0
    and peru_customs_agent_usd >= 0
    and peru_internal_transport_usd >= 0
    and origin_handling_usd >= 0
    and export_documentation_usd >= 0
    and origin_port_costs_usd >= 0
    and other_origin_costs_usd >= 0
    and international_freight_usd >= 0
    and international_insurance_usd >= 0
    and destination_handling_usd >= 0
    and usa_broker_fee_usd >= 0
    and usa_mpf_fee_usd >= 0
    and usa_internal_transport_usd >= 0
    and final_delivery_usd >= 0
    and unloading_destination_usd >= 0
    and other_destination_costs_usd >= 0
    and ad_valorem_pct >= 0
    and preferential_tariff_pct >= 0
    and (ad_valorem_base_usd is null or ad_valorem_base_usd >= 0)
    and ad_valorem_amount_usd >= 0
    and exw_usd >= 0
    and fca_usd >= 0
    and fas_usd >= 0
    and fob_usd >= 0
    and cfr_usd >= 0
    and cif_usd >= 0
    and cpt_usd >= 0
    and cip_usd >= 0
    and dap_usd >= 0
    and dpu_usd >= 0
    and ddp_usd >= 0
    and landed_cost_usd >= 0
  )
);

create index if not exists idx_gts_export_simulations_design
  on public.gts_export_simulations(design_id);
create index if not exists idx_gts_export_simulations_created
  on public.gts_export_simulations(created_at desc);

drop trigger if exists trg_gts_export_simulations_updated_at
  on public.gts_export_simulations;
create trigger trg_gts_export_simulations_updated_at
before update on public.gts_export_simulations
for each row execute procedure public.set_updated_at();

alter table public.gts_export_simulations enable row level security;

drop policy if exists "gts_export_simulations_read" on public.gts_export_simulations;
create policy "gts_export_simulations_read" on public.gts_export_simulations
  for select to authenticated
  using (true);

drop policy if exists "gts_export_simulations_insert" on public.gts_export_simulations;
create policy "gts_export_simulations_insert" on public.gts_export_simulations
  for insert to authenticated
  with check (true);

drop policy if exists "gts_export_simulations_update" on public.gts_export_simulations;
create policy "gts_export_simulations_update" on public.gts_export_simulations
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "gts_export_simulations_delete" on public.gts_export_simulations;
create policy "gts_export_simulations_delete" on public.gts_export_simulations
  for delete to authenticated
  using (true);

notify pgrst, 'reload schema';

commit;
