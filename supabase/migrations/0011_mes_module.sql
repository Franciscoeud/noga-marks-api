-- MES module: garment costing tables, policies, and storage
begin;

create extension if not exists "uuid-ossp";

create table if not exists public.mes_garments (
  id uuid primary key default uuid_generate_v4(),
  style_number text not null,
  client text,
  dispatch text,
  reference_code text,
  cost_date date,
  status text not null default 'En proceso' check (status in ('En proceso', 'Terminado')),
  currency text not null default 'USD' check (currency in ('USD', 'PEN')),
  exchange_rate numeric(12,4) not null default 3.5,
  margin_rate numeric(6,4) not null default 0.40,
  admin_rate numeric(6,4) not null default 0,
  finance_rate numeric(6,4) not null default 0,
  tax_rate numeric(6,4) not null default 0.18,
  cutting_days numeric(8,2),
  sewing_days numeric(8,2),
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.mes_cost_items (
  id uuid primary key default uuid_generate_v4(),
  garment_id uuid not null references public.mes_garments(id) on delete cascade,
  section text not null,
  item_name text not null,
  unit text,
  quantity numeric(12,4),
  waste_percent numeric(6,3),
  unit_cost numeric(12,4),
  currency text not null default 'USD' check (currency in ('USD', 'PEN')),
  kind text not null default 'material' check (kind in ('material', 'labor', 'service', 'overhead')),
  order_index int,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.mes_garment_photos (
  id uuid primary key default uuid_generate_v4(),
  garment_id uuid not null references public.mes_garments(id) on delete cascade,
  url text not null,
  path text,
  caption text,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_mes_garments_style on public.mes_garments(lower(style_number));
create index if not exists idx_mes_cost_items_garment on public.mes_cost_items(garment_id);
create index if not exists idx_mes_cost_items_section on public.mes_cost_items(section);
create index if not exists idx_mes_photos_garment on public.mes_garment_photos(garment_id);

drop trigger if exists trg_mes_garments_updated_at on public.mes_garments;
create trigger trg_mes_garments_updated_at
before update on public.mes_garments
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_mes_cost_items_updated_at on public.mes_cost_items;
create trigger trg_mes_cost_items_updated_at
before update on public.mes_cost_items
for each row execute procedure public.set_updated_at();

alter table public.mes_garments enable row level security;
alter table public.mes_cost_items enable row level security;
alter table public.mes_garment_photos enable row level security;

drop policy if exists "mes_garments_read" on public.mes_garments;
create policy "mes_garments_read" on public.mes_garments
  for select to authenticated
  using (true);

drop policy if exists "mes_garments_write" on public.mes_garments;
create policy "mes_garments_write" on public.mes_garments
  for insert to authenticated
  with check (true);

drop policy if exists "mes_garments_update" on public.mes_garments;
create policy "mes_garments_update" on public.mes_garments
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "mes_garments_delete" on public.mes_garments;
create policy "mes_garments_delete" on public.mes_garments
  for delete to authenticated
  using (true);

drop policy if exists "mes_cost_items_read" on public.mes_cost_items;
create policy "mes_cost_items_read" on public.mes_cost_items
  for select to authenticated
  using (true);

drop policy if exists "mes_cost_items_write" on public.mes_cost_items;
create policy "mes_cost_items_write" on public.mes_cost_items
  for insert to authenticated
  with check (true);

drop policy if exists "mes_cost_items_update" on public.mes_cost_items;
create policy "mes_cost_items_update" on public.mes_cost_items
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "mes_cost_items_delete" on public.mes_cost_items;
create policy "mes_cost_items_delete" on public.mes_cost_items
  for delete to authenticated
  using (true);

drop policy if exists "mes_photos_read" on public.mes_garment_photos;
create policy "mes_photos_read" on public.mes_garment_photos
  for select to authenticated
  using (true);

drop policy if exists "mes_photos_write" on public.mes_garment_photos;
create policy "mes_photos_write" on public.mes_garment_photos
  for insert to authenticated
  with check (true);

drop policy if exists "mes_photos_update" on public.mes_garment_photos;
create policy "mes_photos_update" on public.mes_garment_photos
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "mes_photos_delete" on public.mes_garment_photos;
create policy "mes_photos_delete" on public.mes_garment_photos
  for delete to authenticated
  using (true);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'mes-photos',
  'mes-photos',
  true,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id)
do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "mes_photos_bucket_read" on storage.objects;
create policy "mes_photos_bucket_read" on storage.objects
  for select
  using (bucket_id = 'mes-photos');

drop policy if exists "mes_photos_bucket_insert" on storage.objects;
create policy "mes_photos_bucket_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'mes-photos');

drop policy if exists "mes_photos_bucket_update" on storage.objects;
create policy "mes_photos_bucket_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'mes-photos' and owner = auth.uid())
  with check (bucket_id = 'mes-photos' and owner = auth.uid());

drop policy if exists "mes_photos_bucket_delete" on storage.objects;
create policy "mes_photos_bucket_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'mes-photos' and owner = auth.uid());

commit;
