/* -- OPS: control documents - internment guides
begin;

create extension if not exists "uuid-ossp";

create sequence if not exists public.ops_internment_guide_number_seq
  as integer
  start with 7293
  increment by 1
  no minvalue
  no maxvalue
  cache 1;

create table if not exists public.ops_user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint ops_user_profiles_display_name_check
    check (nullif(btrim(display_name), '') is not null)
);

create table if not exists public.ops_internment_guides (
  id uuid primary key default uuid_generate_v4(),
  guide_number integer not null default nextval('public.ops_internment_guide_number_seq'),
  order_id uuid references public.ops_orders(id) on delete set null,
  client_id uuid references public.ops_clients(id) on delete set null,
  client_name text not null,
  address text,
  phone text,
  representative text,
  email text,
  warranty text,
  guide_date date not null default timezone('America/Lima', now())::date,
  guide_time time not null default timezone('America/Lima', now())::time,
  equipment_description text not null,
  serial_number text,
  reported_problem text not null,
  observations text,
  received_by_user_id uuid references auth.users(id) on delete set null,
  received_by_name text not null,
  received_by_email text,
  status text not null default 'issued',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint uq_ops_internment_guides_number unique (guide_number),
  constraint ops_internment_guides_status_check
    check (status in ('draft', 'issued', 'cancelled')),
  constraint ops_internment_guides_required_text_check
    check (
      nullif(btrim(client_name), '') is not null
      and nullif(btrim(equipment_description), '') is not null
      and nullif(btrim(reported_problem), '') is not null
      and nullif(btrim(received_by_name), '') is not null
    ),
  constraint ops_internment_guides_number_check check (guide_number > 0)
);

create table if not exists public.ops_internment_guide_photos (
  id uuid primary key default uuid_generate_v4(),
  guide_id uuid not null references public.ops_internment_guides(id) on delete cascade,
  storage_path text,
  public_url text not null,
  filename text,
  mime_type text,
  position smallint not null,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint ops_internment_guide_photos_position_check
    check (position >= 1 and position <= 6),
  constraint ops_internment_guide_photos_url_check
    check (nullif(btrim(public_url), '') is not null),
  constraint ops_internment_guide_photos_mime_check
    check (mime_type is null or mime_type like 'image/%'),
  constraint uq_ops_internment_guide_photos_position unique (guide_id, position)
);

create index if not exists idx_ops_internment_guides_created_at
  on public.ops_internment_guides(created_at desc);
create index if not exists idx_ops_internment_guides_order
  on public.ops_internment_guides(order_id)
  where order_id is not null;
create index if not exists idx_ops_internment_guides_client
  on public.ops_internment_guides(client_id)
  where client_id is not null;
create index if not exists idx_ops_internment_guide_photos_guide
  on public.ops_internment_guide_photos(guide_id, position);

drop trigger if exists trg_ops_user_profiles_updated_at
  on public.ops_user_profiles;
create trigger trg_ops_user_profiles_updated_at
before update on public.ops_user_profiles
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_ops_internment_guides_updated_at
  on public.ops_internment_guides;
create trigger trg_ops_internment_guides_updated_at
before update on public.ops_internment_guides
for each row execute procedure public.set_updated_at();

alter table public.ops_user_profiles enable row level security;
alter table public.ops_internment_guides enable row level security;
alter table public.ops_internment_guide_photos enable row level security;

drop policy if exists "ops_user_profiles_read_own" on public.ops_user_profiles;
create policy "ops_user_profiles_read_own" on public.ops_user_profiles
  for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "ops_internment_guides_read" on public.ops_internment_guides;
create policy "ops_internment_guides_read" on public.ops_internment_guides
  for select to authenticated using (true);
drop policy if exists "ops_internment_guides_insert" on public.ops_internment_guides;
create policy "ops_internment_guides_insert" on public.ops_internment_guides
  for insert to authenticated with check (true);
drop policy if exists "ops_internment_guides_update" on public.ops_internment_guides;
create policy "ops_internment_guides_update" on public.ops_internment_guides
  for update to authenticated using (true) with check (true);
drop policy if exists "ops_internment_guides_delete" on public.ops_internment_guides;
create policy "ops_internment_guides_delete" on public.ops_internment_guides
  for delete to authenticated using (true);

drop policy if exists "ops_internment_guide_photos_read" on public.ops_internment_guide_photos;
create policy "ops_internment_guide_photos_read" on public.ops_internment_guide_photos
  for select to authenticated using (true);
drop policy if exists "ops_internment_guide_photos_insert" on public.ops_internment_guide_photos;
create policy "ops_internment_guide_photos_insert" on public.ops_internment_guide_photos
  for insert to authenticated with check (true);
drop policy if exists "ops_internment_guide_photos_update" on public.ops_internment_guide_photos;
create policy "ops_internment_guide_photos_update" on public.ops_internment_guide_photos
  for update to authenticated using (true) with check (true);
drop policy if exists "ops_internment_guide_photos_delete" on public.ops_internment_guide_photos;
create policy "ops_internment_guide_photos_delete" on public.ops_internment_guide_photos
  for delete to authenticated using (true);

drop policy if exists "ops_photos_read_authenticated" on storage.objects;
create policy "ops_photos_read_authenticated" on storage.objects
  for select to authenticated
  using (bucket_id = 'ops-photos');
drop policy if exists "ops_photos_insert_authenticated" on storage.objects;
create policy "ops_photos_insert_authenticated" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'ops-photos');
drop policy if exists "ops_photos_update_authenticated" on storage.objects;
create policy "ops_photos_update_authenticated" on storage.objects
  for update to authenticated
  using (bucket_id = 'ops-photos')
  with check (bucket_id = 'ops-photos');
drop policy if exists "ops_photos_delete_authenticated" on storage.objects;
create policy "ops_photos_delete_authenticated" on storage.objects
  for delete to authenticated
  using (bucket_id = 'ops-photos');

grant select on public.ops_user_profiles to authenticated;
grant select, insert, update, delete on public.ops_internment_guides to authenticated;
grant select, insert, update, delete on public.ops_internment_guide_photos to authenticated;
grant usage on sequence public.ops_internment_guide_number_seq to authenticated;

notify pgrst, 'reload schema';

commit;
 */