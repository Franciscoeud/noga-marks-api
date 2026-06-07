-- MES: NuOrder color mappings and manual EUR export prices
begin;

alter table public.mes_garments
  add column if not exists nuorder_wholesale_eur numeric(14,4),
  add column if not exists nuorder_retail_eur numeric(14,4);

alter table public.mes_garments
  drop constraint if exists mes_garments_nuorder_wholesale_eur_nonnegative;
alter table public.mes_garments
  add constraint mes_garments_nuorder_wholesale_eur_nonnegative
  check (nuorder_wholesale_eur is null or nuorder_wholesale_eur >= 0);

alter table public.mes_garments
  drop constraint if exists mes_garments_nuorder_retail_eur_nonnegative;
alter table public.mes_garments
  add constraint mes_garments_nuorder_retail_eur_nonnegative
  check (nuorder_retail_eur is null or nuorder_retail_eur >= 0);

create table if not exists public.mes_nuorder_color_mappings (
  id uuid primary key default uuid_generate_v4(),
  dispatch text not null,
  design_attribute_id uuid not null references public.mes_design_attributes(id) on delete cascade,
  nuorder_color_code text not null,
  nuorder_color_name text not null,
  swatch_url text,
  swatch_path text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint mes_nuorder_color_mappings_dispatch_check
    check (dispatch in ('FW26-27', 'SS27')),
  constraint mes_nuorder_color_mappings_code_not_blank
    check (btrim(nuorder_color_code) <> ''),
  constraint mes_nuorder_color_mappings_name_not_blank
    check (btrim(nuorder_color_name) <> '')
);

create unique index if not exists uq_mes_nuorder_color_mappings_attribute
  on public.mes_nuorder_color_mappings(design_attribute_id);

create index if not exists idx_mes_nuorder_color_mappings_dispatch
  on public.mes_nuorder_color_mappings(dispatch);

drop trigger if exists trg_mes_nuorder_color_mappings_updated_at
  on public.mes_nuorder_color_mappings;
create trigger trg_mes_nuorder_color_mappings_updated_at
before update on public.mes_nuorder_color_mappings
for each row execute procedure public.set_updated_at();

alter table public.mes_nuorder_color_mappings enable row level security;

drop policy if exists "mes_nuorder_color_mappings_read"
  on public.mes_nuorder_color_mappings;
create policy "mes_nuorder_color_mappings_read"
  on public.mes_nuorder_color_mappings
  for select to authenticated
  using (true);

drop policy if exists "mes_nuorder_color_mappings_insert"
  on public.mes_nuorder_color_mappings;
create policy "mes_nuorder_color_mappings_insert"
  on public.mes_nuorder_color_mappings
  for insert to authenticated
  with check (
    exists (
      select 1
      from public.mes_design_attributes attribute
      where attribute.id = mes_nuorder_color_mappings.design_attribute_id
        and attribute.kind = 'color'
        and attribute.dispatch = mes_nuorder_color_mappings.dispatch
    )
  );

drop policy if exists "mes_nuorder_color_mappings_update"
  on public.mes_nuorder_color_mappings;
create policy "mes_nuorder_color_mappings_update"
  on public.mes_nuorder_color_mappings
  for update to authenticated
  using (true)
  with check (
    exists (
      select 1
      from public.mes_design_attributes attribute
      where attribute.id = mes_nuorder_color_mappings.design_attribute_id
        and attribute.kind = 'color'
        and attribute.dispatch = mes_nuorder_color_mappings.dispatch
    )
  );

drop policy if exists "mes_nuorder_color_mappings_delete"
  on public.mes_nuorder_color_mappings;
create policy "mes_nuorder_color_mappings_delete"
  on public.mes_nuorder_color_mappings
  for delete to authenticated
  using (true);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'mes-nuorder-swatches',
  'mes-nuorder-swatches',
  true,
  5242880,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id)
do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "mes_nuorder_swatches_read" on storage.objects;
create policy "mes_nuorder_swatches_read" on storage.objects
  for select
  using (bucket_id = 'mes-nuorder-swatches');

drop policy if exists "mes_nuorder_swatches_insert" on storage.objects;
create policy "mes_nuorder_swatches_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'mes-nuorder-swatches');

drop policy if exists "mes_nuorder_swatches_update" on storage.objects;
create policy "mes_nuorder_swatches_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'mes-nuorder-swatches' and owner = auth.uid())
  with check (bucket_id = 'mes-nuorder-swatches' and owner = auth.uid());

drop policy if exists "mes_nuorder_swatches_delete" on storage.objects;
create policy "mes_nuorder_swatches_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'mes-nuorder-swatches' and owner = auth.uid());

grant select, insert, update, delete on public.mes_nuorder_color_mappings to authenticated;

notify pgrst, 'reload schema';

commit;
