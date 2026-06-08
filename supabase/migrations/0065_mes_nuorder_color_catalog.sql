-- MES: separate NuOrder color catalog from Manufacturing color mappings
begin;

create table if not exists public.mes_nuorder_colors (
  id uuid primary key default uuid_generate_v4(),
  dispatch text not null,
  nuorder_color_code text not null,
  nuorder_color_name text not null,
  swatch_url text,
  swatch_path text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint mes_nuorder_colors_dispatch_check
    check (dispatch in ('FW26-27', 'SS27')),
  constraint mes_nuorder_colors_code_not_blank
    check (btrim(nuorder_color_code) <> ''),
  constraint mes_nuorder_colors_name_not_blank
    check (btrim(nuorder_color_name) <> '')
);

create unique index if not exists uq_mes_nuorder_colors_dispatch_code
  on public.mes_nuorder_colors(dispatch, nuorder_color_code);

create index if not exists idx_mes_nuorder_colors_dispatch
  on public.mes_nuorder_colors(dispatch);

drop trigger if exists trg_mes_nuorder_colors_updated_at
  on public.mes_nuorder_colors;
create trigger trg_mes_nuorder_colors_updated_at
before update on public.mes_nuorder_colors
for each row execute procedure public.set_updated_at();

alter table public.mes_nuorder_colors enable row level security;

drop policy if exists "mes_nuorder_colors_read"
  on public.mes_nuorder_colors;
create policy "mes_nuorder_colors_read"
  on public.mes_nuorder_colors
  for select to authenticated
  using (true);

drop policy if exists "mes_nuorder_colors_insert"
  on public.mes_nuorder_colors;
create policy "mes_nuorder_colors_insert"
  on public.mes_nuorder_colors
  for insert to authenticated
  with check (true);

drop policy if exists "mes_nuorder_colors_update"
  on public.mes_nuorder_colors;
create policy "mes_nuorder_colors_update"
  on public.mes_nuorder_colors
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "mes_nuorder_colors_delete"
  on public.mes_nuorder_colors;
create policy "mes_nuorder_colors_delete"
  on public.mes_nuorder_colors
  for delete to authenticated
  using (true);

insert into public.mes_nuorder_colors (
  dispatch,
  nuorder_color_code,
  nuorder_color_name,
  swatch_url,
  swatch_path
)
select distinct on (mapping.dispatch, btrim(mapping.nuorder_color_code))
  mapping.dispatch,
  btrim(mapping.nuorder_color_code),
  btrim(mapping.nuorder_color_name),
  mapping.swatch_url,
  mapping.swatch_path
from public.mes_nuorder_color_mappings mapping
where mapping.nuorder_color_code is not null
  and btrim(mapping.nuorder_color_code) <> ''
  and mapping.nuorder_color_name is not null
  and btrim(mapping.nuorder_color_name) <> ''
order by
  mapping.dispatch,
  btrim(mapping.nuorder_color_code),
  mapping.updated_at desc,
  mapping.created_at desc
on conflict (dispatch, nuorder_color_code) do nothing;

alter table public.mes_nuorder_color_mappings
  add column if not exists nuorder_color_id uuid
  references public.mes_nuorder_colors(id) on delete restrict;

update public.mes_nuorder_color_mappings mapping
set nuorder_color_id = color.id
from public.mes_nuorder_colors color
where mapping.nuorder_color_id is null
  and color.dispatch = mapping.dispatch
  and btrim(color.nuorder_color_code) = btrim(mapping.nuorder_color_code);

alter table public.mes_nuorder_color_mappings
  alter column nuorder_color_id set not null;

create index if not exists idx_mes_nuorder_color_mappings_color
  on public.mes_nuorder_color_mappings(nuorder_color_id);

alter table public.mes_nuorder_color_mappings
  drop constraint if exists mes_nuorder_color_mappings_code_not_blank;

alter table public.mes_nuorder_color_mappings
  drop constraint if exists mes_nuorder_color_mappings_name_not_blank;

alter table public.mes_nuorder_color_mappings
  drop column if exists nuorder_color_code,
  drop column if exists nuorder_color_name,
  drop column if exists swatch_url,
  drop column if exists swatch_path;

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
    and exists (
      select 1
      from public.mes_nuorder_colors color
      where color.id = mes_nuorder_color_mappings.nuorder_color_id
        and color.dispatch = mes_nuorder_color_mappings.dispatch
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
    and exists (
      select 1
      from public.mes_nuorder_colors color
      where color.id = mes_nuorder_color_mappings.nuorder_color_id
        and color.dispatch = mes_nuorder_color_mappings.dispatch
    )
  );

grant select, insert, update, delete on public.mes_nuorder_colors to authenticated;

notify pgrst, 'reload schema';

commit;
