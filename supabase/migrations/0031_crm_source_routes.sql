begin;

create table if not exists public.crm_source_routes (
  id uuid primary key default uuid_generate_v4(),
  active boolean not null default true,
  provider text not null,
  source_channel text not null,
  campaign_name text,
  form_name text,
  adset_name text,
  ad_name text,
  account_id uuid references public.crm_accounts(id) on delete set null,
  product_interest_id uuid references public.crm_product_interests(id) on delete set null,
  requested_info_type text,
  priority int not null default 100,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_crm_source_routes_provider_channel
  on public.crm_source_routes(provider, source_channel, active);

create index if not exists idx_crm_source_routes_priority
  on public.crm_source_routes(priority, created_at);

commit;
