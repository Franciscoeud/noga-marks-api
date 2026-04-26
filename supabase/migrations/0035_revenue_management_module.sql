-- Revenue Management v1: operational supervision, inspections, issues, rooms, and configurable checklist templates
begin;

create extension if not exists "uuid-ossp";

alter table public.app_user_modules
  drop constraint if exists app_user_modules_module_key_check;

alter table public.app_user_modules
  add constraint app_user_modules_module_key_check
  check (module_key in ('SCM', 'Planificacion', 'MES', 'Sales', 'FI', 'Ops', 'Revenue'));

create table if not exists public.rm_property_members (
  user_id uuid not null references auth.users(id) on delete cascade,
  property_id uuid not null references public.fi_properties(id) on delete cascade,
  role text not null check (role in ('admin', 'supervisor', 'housekeeping', 'maintenance', 'viewer', 'manager')),
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, property_id)
);

create table if not exists public.rm_rooms (
  id uuid primary key default uuid_generate_v4(),
  property_id uuid not null references public.fi_properties(id) on delete cascade,
  code text not null,
  name text not null,
  floor text,
  has_private_bathroom boolean not null default false,
  key_color text,
  lock_type text check (lock_type in ('physical_key', 'smart_lock', 'mixed')),
  refrigerator_assignment text,
  wifi_quality text check (wifi_quality in ('good', 'regular', 'weak')),
  room_notes text,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (property_id, code)
);

create table if not exists public.rm_zones (
  id uuid primary key default uuid_generate_v4(),
  property_id uuid references public.fi_properties(id) on delete cascade,
  name text not null,
  zone_type text not null check (
    zone_type in (
      'room',
      'common_area',
      'kitchen',
      'external_patio',
      'terrace',
      'terrace_furniture',
      'balcony',
      'storage',
      'entrance'
    )
  ),
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_checklist_templates (
  id uuid primary key default uuid_generate_v4(),
  property_id uuid references public.fi_properties(id) on delete cascade,
  base_template_id uuid references public.rm_checklist_templates(id) on delete set null,
  name text not null,
  description text,
  frequency text not null default 'weekly',
  version int not null default 1,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_checklist_sections (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references public.rm_checklist_templates(id) on delete cascade,
  name text not null,
  description text,
  scope text not null check (
    scope in (
      'room_common',
      'room_private_bathroom',
      'room_shared_bathroom',
      'common_area',
      'kitchen',
      'external_patio',
      'terrace',
      'terrace_furniture',
      'balcony',
      'storage',
      'entrance'
    )
  ),
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_priority_levels (
  code text primary key check (code in ('low', 'medium', 'high', 'critical')),
  label text not null,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_issue_types (
  code text primary key,
  label text not null,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_checklist_items (
  id uuid primary key default uuid_generate_v4(),
  template_id uuid not null references public.rm_checklist_templates(id) on delete cascade,
  section_id uuid not null references public.rm_checklist_sections(id) on delete cascade,
  scope text not null check (
    scope in (
      'room_common',
      'room_private_bathroom',
      'room_shared_bathroom',
      'common_area',
      'kitchen',
      'external_patio',
      'terrace',
      'terrace_furniture',
      'balcony',
      'storage',
      'entrance'
    )
  ),
  item_code text not null,
  title text not null,
  description text,
  expected_standard text,
  default_priority text not null references public.rm_priority_levels(code) on delete restrict,
  requires_photo_on_issue boolean not null default true,
  requires_photo_always boolean not null default false,
  can_create_issue boolean not null default true,
  revenue_impact_category text check (
    revenue_impact_category in ('none', 'review_risk', 'room_blocked', 'guest_compensation', 'repair_cost')
  ),
  is_required boolean not null default true,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (template_id, item_code)
);

create table if not exists public.rm_room_checklist_overrides (
  id uuid primary key default uuid_generate_v4(),
  room_id uuid not null references public.rm_rooms(id) on delete cascade,
  checklist_item_id uuid not null references public.rm_checklist_items(id) on delete cascade,
  override_type text not null check (
    override_type in (
      'add_custom_item',
      'disable_base_item',
      'change_priority',
      'change_expected_standard',
      'make_required',
      'make_not_required'
    )
  ),
  custom_title text,
  custom_description text,
  custom_expected_standard text,
  custom_priority text references public.rm_priority_levels(code) on delete restrict,
  custom_section_name text,
  sort_order int,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_room_specific_checklist_items (
  id uuid primary key default uuid_generate_v4(),
  room_id uuid not null references public.rm_rooms(id) on delete cascade,
  template_id uuid references public.rm_checklist_templates(id) on delete set null,
  section_name text not null,
  title text not null,
  description text,
  expected_standard text,
  default_priority text not null references public.rm_priority_levels(code) on delete restrict,
  requires_photo_on_issue boolean not null default true,
  requires_photo_always boolean not null default false,
  can_create_issue boolean not null default true,
  revenue_impact_category text check (
    revenue_impact_category in ('none', 'review_risk', 'room_blocked', 'guest_compensation', 'repair_cost')
  ),
  is_required boolean not null default true,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_inspections (
  id uuid primary key default uuid_generate_v4(),
  property_id uuid not null references public.fi_properties(id) on delete cascade,
  template_id uuid not null references public.rm_checklist_templates(id) on delete restrict,
  inspection_date date not null,
  started_at timestamptz not null default timezone('utc', now()),
  submitted_at timestamptz,
  inspected_by uuid references auth.users(id) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'in_progress', 'submitted', 'reviewed', 'closed', 'cancelled')),
  general_notes text,
  cancel_reason text,
  overall_score numeric(5,2),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_inspection_targets (
  id uuid primary key default uuid_generate_v4(),
  inspection_id uuid not null references public.rm_inspections(id) on delete cascade,
  target_type text not null check (target_type in ('room', 'zone')),
  room_id uuid references public.rm_rooms(id) on delete set null,
  zone_id uuid references public.rm_zones(id) on delete set null,
  target_name_snapshot text not null,
  status text not null default 'pending' check (status in ('pending', 'in_progress', 'completed')),
  score numeric(5,2),
  notes text,
  sort_order int not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  check (
    (target_type = 'room' and room_id is not null and zone_id is null)
    or (target_type = 'zone' and zone_id is not null and room_id is null)
  )
);

create table if not exists public.rm_issues (
  id uuid primary key default uuid_generate_v4(),
  property_id uuid not null references public.fi_properties(id) on delete cascade,
  room_id uuid references public.rm_rooms(id) on delete set null,
  zone_id uuid references public.rm_zones(id) on delete set null,
  inspection_id uuid references public.rm_inspections(id) on delete set null,
  inspection_target_id uuid references public.rm_inspection_targets(id) on delete set null,
  checklist_item_id uuid references public.rm_checklist_items(id) on delete set null,
  room_specific_item_id uuid references public.rm_room_specific_checklist_items(id) on delete set null,
  title text not null,
  description text,
  priority text not null references public.rm_priority_levels(code) on delete restrict,
  issue_type text not null references public.rm_issue_types(code) on delete restrict,
  status text not null default 'open' check (status in ('open', 'assigned', 'in_progress', 'resolved', 'closed', 'cancelled')),
  assigned_to uuid references auth.users(id) on delete set null,
  due_date date,
  revenue_impact_category text check (
    revenue_impact_category in ('none', 'review_risk', 'room_blocked', 'guest_compensation', 'repair_cost')
  ),
  estimated_cost numeric(12,2),
  estimated_lost_revenue numeric(12,2),
  blocks_room boolean not null default false,
  guest_review_risk boolean not null default false,
  recurrence_key text,
  opened_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz,
  closed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_inspection_responses (
  id uuid primary key default uuid_generate_v4(),
  inspection_id uuid not null references public.rm_inspections(id) on delete cascade,
  inspection_target_id uuid not null references public.rm_inspection_targets(id) on delete cascade,
  checklist_item_id uuid references public.rm_checklist_items(id) on delete set null,
  room_specific_item_id uuid references public.rm_room_specific_checklist_items(id) on delete set null,
  status text not null default 'pending' check (status in ('pending', 'ok', 'observed', 'critical', 'na')),
  priority text references public.rm_priority_levels(code) on delete restrict,
  comment text,
  photo_urls text[] not null default '{}',
  creates_issue boolean not null default false,
  issue_id uuid references public.rm_issues(id) on delete set null,
  score numeric(5,2),
  answered_by uuid references auth.users(id) on delete set null,
  answered_at timestamptz,
  item_title_snapshot text not null,
  item_description_snapshot text,
  expected_standard_snapshot text,
  priority_snapshot text,
  section_name_snapshot text,
  item_scope_snapshot text,
  revenue_impact_category_snapshot text,
  can_create_issue_snapshot boolean not null default true,
  requires_photo_on_issue_snapshot boolean not null default true,
  requires_photo_always_snapshot boolean not null default false,
  is_room_specific boolean not null default false,
  item_source text not null default 'base' check (item_source in ('base', 'room_specific')),
  sort_order_snapshot int not null default 0,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_issue_comments (
  id uuid primary key default uuid_generate_v4(),
  issue_id uuid not null references public.rm_issues(id) on delete cascade,
  author_id uuid references auth.users(id) on delete set null,
  comment text not null,
  photo_urls text[] not null default '{}',
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.rm_room_status_history (
  id uuid primary key default uuid_generate_v4(),
  room_id uuid not null references public.rm_rooms(id) on delete cascade,
  property_id uuid not null references public.fi_properties(id) on delete cascade,
  status text not null check (status in ('available', 'needs_attention', 'blocked', 'maintenance', 'out_of_service')),
  reason text,
  issue_id uuid references public.rm_issues(id) on delete set null,
  started_at timestamptz not null default timezone('utc', now()),
  ended_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_rm_property_members_property on public.rm_property_members(property_id);
create index if not exists idx_rm_property_members_user on public.rm_property_members(user_id);
create index if not exists idx_rm_rooms_property on public.rm_rooms(property_id);
create index if not exists idx_rm_rooms_active on public.rm_rooms(active);
create index if not exists idx_rm_zones_property on public.rm_zones(property_id);
create index if not exists idx_rm_zones_zone_type on public.rm_zones(zone_type);
create index if not exists idx_rm_templates_property on public.rm_checklist_templates(property_id);
create index if not exists idx_rm_templates_active on public.rm_checklist_templates(is_active);
create index if not exists idx_rm_sections_template on public.rm_checklist_sections(template_id);
create index if not exists idx_rm_items_template on public.rm_checklist_items(template_id);
create index if not exists idx_rm_items_section on public.rm_checklist_items(section_id);
create index if not exists idx_rm_room_overrides_room on public.rm_room_checklist_overrides(room_id);
create index if not exists idx_rm_room_specific_items_room on public.rm_room_specific_checklist_items(room_id);
create index if not exists idx_rm_inspections_property on public.rm_inspections(property_id);
create index if not exists idx_rm_inspections_status on public.rm_inspections(status);
create index if not exists idx_rm_targets_inspection on public.rm_inspection_targets(inspection_id);
create index if not exists idx_rm_responses_inspection on public.rm_inspection_responses(inspection_id);
create index if not exists idx_rm_responses_target on public.rm_inspection_responses(inspection_target_id);
create index if not exists idx_rm_responses_issue on public.rm_inspection_responses(issue_id);
create index if not exists idx_rm_issues_property on public.rm_issues(property_id);
create index if not exists idx_rm_issues_status on public.rm_issues(status);
create index if not exists idx_rm_issues_assigned_to on public.rm_issues(assigned_to);
create index if not exists idx_rm_issues_due_date on public.rm_issues(due_date);
create index if not exists idx_rm_issue_comments_issue on public.rm_issue_comments(issue_id);
create index if not exists idx_rm_room_status_history_room on public.rm_room_status_history(room_id);
create index if not exists idx_rm_room_status_history_property on public.rm_room_status_history(property_id);

create or replace function public.rm_is_admin()
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from public.fi_user_roles
    where user_id = auth.uid()
      and role = 'admin'
  );
$$;

create or replace function public.rm_has_property_access(p_property_id uuid)
returns boolean
language sql
stable
as $$
  select case
    when auth.uid() is null then false
    when public.rm_is_admin() then true
    when p_property_id is null then false
    else exists (
      select 1
      from public.rm_property_members
      where user_id = auth.uid()
        and property_id = p_property_id
        and active = true
    )
  end;
$$;

create or replace function public.rm_can_manage_property(p_property_id uuid)
returns boolean
language sql
stable
as $$
  select case
    when auth.uid() is null then false
    when public.rm_is_admin() then true
    else exists (
      select 1
      from public.rm_property_members
      where user_id = auth.uid()
        and property_id = p_property_id
        and active = true
        and role in ('admin', 'manager')
    )
  end;
$$;

create or replace function public.rm_can_run_inspections(p_property_id uuid)
returns boolean
language sql
stable
as $$
  select case
    when auth.uid() is null then false
    when public.rm_is_admin() then true
    else exists (
      select 1
      from public.rm_property_members
      where user_id = auth.uid()
        and property_id = p_property_id
        and active = true
        and role in ('admin', 'manager', 'supervisor')
    )
  end;
$$;

create or replace function public.rm_can_edit_templates(p_property_id uuid)
returns boolean
language sql
stable
as $$
  select case
    when auth.uid() is null then false
    when public.rm_is_admin() then true
    when p_property_id is null then public.rm_is_admin()
    else public.rm_can_manage_property(p_property_id)
  end;
$$;

create or replace function public.rm_can_update_assigned_issues(p_property_id uuid, p_assigned_to uuid)
returns boolean
language sql
stable
as $$
  select case
    when auth.uid() is null then false
    when public.rm_is_admin() then true
    when exists (
      select 1
      from public.rm_property_members
      where user_id = auth.uid()
        and property_id = p_property_id
        and active = true
        and role in ('admin', 'manager', 'supervisor')
    ) then true
    when p_assigned_to is not null and p_assigned_to = auth.uid() then true
    else false
  end;
$$;

create or replace function public.rm_room_property_id(p_room_id uuid)
returns uuid
language sql
stable
as $$
  select property_id
  from public.rm_rooms
  where id = p_room_id;
$$;

create or replace function public.rm_template_property_id(p_template_id uuid)
returns uuid
language sql
stable
as $$
  select property_id
  from public.rm_checklist_templates
  where id = p_template_id;
$$;

create or replace function public.rm_section_property_id(p_section_id uuid)
returns uuid
language sql
stable
as $$
  select t.property_id
  from public.rm_checklist_sections s
  join public.rm_checklist_templates t on t.id = s.template_id
  where s.id = p_section_id;
$$;

create or replace function public.rm_item_property_id(p_item_id uuid)
returns uuid
language sql
stable
as $$
  select t.property_id
  from public.rm_checklist_items i
  join public.rm_checklist_templates t on t.id = i.template_id
  where i.id = p_item_id;
$$;

create or replace function public.rm_inspection_property_id(p_inspection_id uuid)
returns uuid
language sql
stable
as $$
  select property_id
  from public.rm_inspections
  where id = p_inspection_id;
$$;

create or replace function public.rm_target_property_id(p_target_id uuid)
returns uuid
language sql
stable
as $$
  select i.property_id
  from public.rm_inspection_targets t
  join public.rm_inspections i on i.id = t.inspection_id
  where t.id = p_target_id;
$$;

create or replace function public.rm_issue_property_id(p_issue_id uuid)
returns uuid
language sql
stable
as $$
  select property_id
  from public.rm_issues
  where id = p_issue_id;
$$;

drop trigger if exists trg_rm_property_members_updated_at on public.rm_property_members;
create trigger trg_rm_property_members_updated_at
before update on public.rm_property_members
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_rooms_updated_at on public.rm_rooms;
create trigger trg_rm_rooms_updated_at
before update on public.rm_rooms
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_zones_updated_at on public.rm_zones;
create trigger trg_rm_zones_updated_at
before update on public.rm_zones
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_checklist_templates_updated_at on public.rm_checklist_templates;
create trigger trg_rm_checklist_templates_updated_at
before update on public.rm_checklist_templates
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_checklist_sections_updated_at on public.rm_checklist_sections;
create trigger trg_rm_checklist_sections_updated_at
before update on public.rm_checklist_sections
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_priority_levels_updated_at on public.rm_priority_levels;
create trigger trg_rm_priority_levels_updated_at
before update on public.rm_priority_levels
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_issue_types_updated_at on public.rm_issue_types;
create trigger trg_rm_issue_types_updated_at
before update on public.rm_issue_types
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_checklist_items_updated_at on public.rm_checklist_items;
create trigger trg_rm_checklist_items_updated_at
before update on public.rm_checklist_items
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_room_checklist_overrides_updated_at on public.rm_room_checklist_overrides;
create trigger trg_rm_room_checklist_overrides_updated_at
before update on public.rm_room_checklist_overrides
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_room_specific_items_updated_at on public.rm_room_specific_checklist_items;
create trigger trg_rm_room_specific_items_updated_at
before update on public.rm_room_specific_checklist_items
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_inspections_updated_at on public.rm_inspections;
create trigger trg_rm_inspections_updated_at
before update on public.rm_inspections
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_targets_updated_at on public.rm_inspection_targets;
create trigger trg_rm_targets_updated_at
before update on public.rm_inspection_targets
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_issues_updated_at on public.rm_issues;
create trigger trg_rm_issues_updated_at
before update on public.rm_issues
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_rm_responses_updated_at on public.rm_inspection_responses;
create trigger trg_rm_responses_updated_at
before update on public.rm_inspection_responses
for each row execute procedure public.set_updated_at();

alter table public.rm_property_members enable row level security;
alter table public.rm_rooms enable row level security;
alter table public.rm_zones enable row level security;
alter table public.rm_checklist_templates enable row level security;
alter table public.rm_checklist_sections enable row level security;
alter table public.rm_priority_levels enable row level security;
alter table public.rm_issue_types enable row level security;
alter table public.rm_checklist_items enable row level security;
alter table public.rm_room_checklist_overrides enable row level security;
alter table public.rm_room_specific_checklist_items enable row level security;
alter table public.rm_inspections enable row level security;
alter table public.rm_inspection_targets enable row level security;
alter table public.rm_issues enable row level security;
alter table public.rm_inspection_responses enable row level security;
alter table public.rm_issue_comments enable row level security;
alter table public.rm_room_status_history enable row level security;

drop policy if exists "rm_property_members_read" on public.rm_property_members;
create policy "rm_property_members_read" on public.rm_property_members
  for select to authenticated
  using (public.rm_is_admin() or auth.uid() = user_id or public.rm_has_property_access(property_id));

drop policy if exists "rm_property_members_write" on public.rm_property_members;
create policy "rm_property_members_write" on public.rm_property_members
  for all to authenticated
  using (public.rm_is_admin() or public.rm_can_manage_property(property_id))
  with check (public.rm_is_admin() or public.rm_can_manage_property(property_id));

drop policy if exists "rm_rooms_read" on public.rm_rooms;
create policy "rm_rooms_read" on public.rm_rooms
  for select to authenticated
  using (public.rm_has_property_access(property_id));

drop policy if exists "rm_rooms_write" on public.rm_rooms;
create policy "rm_rooms_write" on public.rm_rooms
  for all to authenticated
  using (public.rm_can_manage_property(property_id))
  with check (public.rm_can_manage_property(property_id));

drop policy if exists "rm_zones_read" on public.rm_zones;
create policy "rm_zones_read" on public.rm_zones
  for select to authenticated
  using (property_id is null or public.rm_has_property_access(property_id));

drop policy if exists "rm_zones_write" on public.rm_zones;
create policy "rm_zones_write" on public.rm_zones
  for all to authenticated
  using ((property_id is null and public.rm_is_admin()) or public.rm_can_manage_property(property_id))
  with check ((property_id is null and public.rm_is_admin()) or public.rm_can_manage_property(property_id));

drop policy if exists "rm_templates_read" on public.rm_checklist_templates;
create policy "rm_templates_read" on public.rm_checklist_templates
  for select to authenticated
  using (property_id is null or public.rm_has_property_access(property_id));

drop policy if exists "rm_templates_write" on public.rm_checklist_templates;
create policy "rm_templates_write" on public.rm_checklist_templates
  for all to authenticated
  using ((property_id is null and public.rm_is_admin()) or public.rm_can_edit_templates(property_id))
  with check ((property_id is null and public.rm_is_admin()) or public.rm_can_edit_templates(property_id));

drop policy if exists "rm_sections_read" on public.rm_checklist_sections;
create policy "rm_sections_read" on public.rm_checklist_sections
  for select to authenticated
  using (
    public.rm_template_property_id(template_id) is null
    or public.rm_has_property_access(public.rm_template_property_id(template_id))
  );

drop policy if exists "rm_sections_write" on public.rm_checklist_sections;
create policy "rm_sections_write" on public.rm_checklist_sections
  for all to authenticated
  using (
    (public.rm_template_property_id(template_id) is null and public.rm_is_admin())
    or public.rm_can_edit_templates(public.rm_template_property_id(template_id))
  )
  with check (
    (public.rm_template_property_id(template_id) is null and public.rm_is_admin())
    or public.rm_can_edit_templates(public.rm_template_property_id(template_id))
  );

drop policy if exists "rm_priority_levels_read" on public.rm_priority_levels;
create policy "rm_priority_levels_read" on public.rm_priority_levels
  for select to authenticated
  using (true);

drop policy if exists "rm_priority_levels_write" on public.rm_priority_levels;
create policy "rm_priority_levels_write" on public.rm_priority_levels
  for all to authenticated
  using (public.rm_is_admin())
  with check (public.rm_is_admin());

drop policy if exists "rm_issue_types_read" on public.rm_issue_types;
create policy "rm_issue_types_read" on public.rm_issue_types
  for select to authenticated
  using (true);

drop policy if exists "rm_issue_types_write" on public.rm_issue_types;
create policy "rm_issue_types_write" on public.rm_issue_types
  for all to authenticated
  using (public.rm_is_admin())
  with check (public.rm_is_admin());

drop policy if exists "rm_items_read" on public.rm_checklist_items;
create policy "rm_items_read" on public.rm_checklist_items
  for select to authenticated
  using (
    public.rm_template_property_id(template_id) is null
    or public.rm_has_property_access(public.rm_template_property_id(template_id))
  );

drop policy if exists "rm_items_write" on public.rm_checklist_items;
create policy "rm_items_write" on public.rm_checklist_items
  for all to authenticated
  using (
    (public.rm_template_property_id(template_id) is null and public.rm_is_admin())
    or public.rm_can_edit_templates(public.rm_template_property_id(template_id))
  )
  with check (
    (public.rm_template_property_id(template_id) is null and public.rm_is_admin())
    or public.rm_can_edit_templates(public.rm_template_property_id(template_id))
  );

drop policy if exists "rm_room_overrides_read" on public.rm_room_checklist_overrides;
create policy "rm_room_overrides_read" on public.rm_room_checklist_overrides
  for select to authenticated
  using (public.rm_has_property_access(public.rm_room_property_id(room_id)));

drop policy if exists "rm_room_overrides_write" on public.rm_room_checklist_overrides;
create policy "rm_room_overrides_write" on public.rm_room_checklist_overrides
  for all to authenticated
  using (public.rm_can_manage_property(public.rm_room_property_id(room_id)))
  with check (public.rm_can_manage_property(public.rm_room_property_id(room_id)));

drop policy if exists "rm_room_specific_items_read" on public.rm_room_specific_checklist_items;
create policy "rm_room_specific_items_read" on public.rm_room_specific_checklist_items
  for select to authenticated
  using (public.rm_has_property_access(public.rm_room_property_id(room_id)));

drop policy if exists "rm_room_specific_items_write" on public.rm_room_specific_checklist_items;
create policy "rm_room_specific_items_write" on public.rm_room_specific_checklist_items
  for all to authenticated
  using (public.rm_can_manage_property(public.rm_room_property_id(room_id)))
  with check (public.rm_can_manage_property(public.rm_room_property_id(room_id)));

drop policy if exists "rm_inspections_read" on public.rm_inspections;
create policy "rm_inspections_read" on public.rm_inspections
  for select to authenticated
  using (public.rm_has_property_access(property_id));

drop policy if exists "rm_inspections_write" on public.rm_inspections;
create policy "rm_inspections_write" on public.rm_inspections
  for all to authenticated
  using (public.rm_can_run_inspections(property_id))
  with check (public.rm_can_run_inspections(property_id));

drop policy if exists "rm_targets_read" on public.rm_inspection_targets;
create policy "rm_targets_read" on public.rm_inspection_targets
  for select to authenticated
  using (public.rm_has_property_access(public.rm_inspection_property_id(inspection_id)));

drop policy if exists "rm_targets_write" on public.rm_inspection_targets;
create policy "rm_targets_write" on public.rm_inspection_targets
  for all to authenticated
  using (public.rm_can_run_inspections(public.rm_inspection_property_id(inspection_id)))
  with check (public.rm_can_run_inspections(public.rm_inspection_property_id(inspection_id)));

drop policy if exists "rm_issues_read" on public.rm_issues;
create policy "rm_issues_read" on public.rm_issues
  for select to authenticated
  using (public.rm_has_property_access(property_id));

drop policy if exists "rm_issues_write" on public.rm_issues;
create policy "rm_issues_write" on public.rm_issues
  for all to authenticated
  using (public.rm_can_update_assigned_issues(property_id, assigned_to))
  with check (public.rm_can_update_assigned_issues(property_id, assigned_to));

drop policy if exists "rm_responses_read" on public.rm_inspection_responses;
create policy "rm_responses_read" on public.rm_inspection_responses
  for select to authenticated
  using (public.rm_has_property_access(public.rm_inspection_property_id(inspection_id)));

drop policy if exists "rm_responses_write" on public.rm_inspection_responses;
create policy "rm_responses_write" on public.rm_inspection_responses
  for all to authenticated
  using (public.rm_can_run_inspections(public.rm_inspection_property_id(inspection_id)))
  with check (public.rm_can_run_inspections(public.rm_inspection_property_id(inspection_id)));

drop policy if exists "rm_issue_comments_read" on public.rm_issue_comments;
create policy "rm_issue_comments_read" on public.rm_issue_comments
  for select to authenticated
  using (public.rm_has_property_access(public.rm_issue_property_id(issue_id)));

drop policy if exists "rm_issue_comments_write" on public.rm_issue_comments;
create policy "rm_issue_comments_write" on public.rm_issue_comments
  for all to authenticated
  using (public.rm_can_update_assigned_issues(public.rm_issue_property_id(issue_id), null))
  with check (public.rm_can_update_assigned_issues(public.rm_issue_property_id(issue_id), null));

drop policy if exists "rm_room_status_history_read" on public.rm_room_status_history;
create policy "rm_room_status_history_read" on public.rm_room_status_history
  for select to authenticated
  using (public.rm_has_property_access(property_id));

drop policy if exists "rm_room_status_history_write" on public.rm_room_status_history;
create policy "rm_room_status_history_write" on public.rm_room_status_history
  for all to authenticated
  using (public.rm_can_manage_property(property_id))
  with check (public.rm_can_manage_property(property_id));

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'rm-inspection-photos',
  'rm-inspection-photos',
  true,
  10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id)
do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "rm_inspection_photos_read" on storage.objects;
create policy "rm_inspection_photos_read" on storage.objects
  for select
  using (bucket_id = 'rm-inspection-photos');

drop policy if exists "rm_inspection_photos_insert" on storage.objects;
create policy "rm_inspection_photos_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'rm-inspection-photos');

drop policy if exists "rm_inspection_photos_update" on storage.objects;
create policy "rm_inspection_photos_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'rm-inspection-photos' and owner = auth.uid())
  with check (bucket_id = 'rm-inspection-photos' and owner = auth.uid());

drop policy if exists "rm_inspection_photos_delete" on storage.objects;
create policy "rm_inspection_photos_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'rm-inspection-photos' and owner = auth.uid());

insert into public.app_user_modules (user_id, module_key)
select id, 'Revenue'
from auth.users
where email in ('francisco@duomoholding.com', 'hola@nogamarks.com', 'keily.arenas@nogamarks.com')
on conflict (user_id, module_key) do nothing;

insert into public.rm_priority_levels (code, label, sort_order, active)
values
  ('low', 'Baja', 10, true),
  ('medium', 'Media', 20, true),
  ('high', 'Alta', 30, true),
  ('critical', 'Critica', 40, true)
on conflict (code) do update
set label = excluded.label,
    sort_order = excluded.sort_order,
    active = excluded.active;

insert into public.rm_issue_types (code, label, sort_order, active)
values
  ('cleaning', 'Limpieza', 10, true),
  ('maintenance', 'Mantenimiento', 20, true),
  ('safety', 'Seguridad', 30, true),
  ('guest_experience', 'Experiencia del huesped', 40, true),
  ('inventory', 'Inventario', 50, true),
  ('wifi', 'WiFi', 60, true),
  ('access', 'Acceso', 70, true),
  ('bathroom', 'Bano', 80, true),
  ('electricity', 'Electricidad', 90, true),
  ('humidity', 'Humedad', 100, true),
  ('other', 'Otro', 110, true)
on conflict (code) do update
set label = excluded.label,
    sort_order = excluded.sort_order,
    active = excluded.active;

insert into public.rm_zones (property_id, name, zone_type, active, sort_order)
select null, seed.name, seed.zone_type, true, seed.sort_order
from (
  values
    ('Entrada principal / fachada / puerta de calle', 'entrance', 10),
    ('Pasillos, escaleras y circulacion interna', 'common_area', 20),
    ('Area de llaves / baul / punto de entrega', 'common_area', 30),
    ('Almacen / luggage storage', 'storage', 40),
    ('Cocina compartida', 'kitchen', 50),
    ('Patio externo', 'external_patio', 60),
    ('Terraza', 'terrace', 70),
    ('Muebles de descanso de terraza', 'terrace_furniture', 80),
    ('Balcon', 'balcony', 90)
) as seed(name, zone_type, sort_order)
where not exists (
  select 1
  from public.rm_zones z
  where z.property_id is null
    and z.name = seed.name
);

do $$
declare
  v_template_id uuid;
begin
  select id
  into v_template_id
  from public.rm_checklist_templates
  where property_id is null
    and name = 'Checklist semanal hospedaje - v1'
    and version = 1
  limit 1;

  if v_template_id is null then
    insert into public.rm_checklist_templates (
      property_id,
      name,
      description,
      frequency,
      version,
      is_active
    )
    values (
      null,
      'Checklist semanal hospedaje - v1',
      'Template base para supervision operativa semanal y revenue management en hospedajes.',
      'weekly',
      1,
      true
    )
    returning id into v_template_id;
  end if;

  insert into public.rm_checklist_sections (template_id, name, description, scope, sort_order, active)
  select v_template_id, seed.name, seed.description, seed.scope, seed.sort_order, true
  from (
    values
      ('Acceso, puerta, cerradura y llaves', null, 'room_common', 10),
      ('Cama, colchon y ropa de cama', null, 'room_common', 20),
      ('Piso, paredes, techo y humedad', null, 'room_common', 30),
      ('Ventanas, cortinas e iluminacion natural', null, 'room_common', 40),
      ('Iluminacion y electricidad', null, 'room_common', 50),
      ('Internet / WiFi', null, 'room_common', 60),
      ('Muebles y equipamiento', null, 'room_common', 70),
      ('Bano privado', null, 'room_private_bathroom', 80),
      ('Limpieza profunda y experiencia del huesped', null, 'room_common', 90),
      ('Seguridad y riesgos', null, 'room_common', 100),
      ('Entrada principal / fachada / puerta de calle', null, 'entrance', 110),
      ('Pasillos, escaleras y circulacion interna', null, 'common_area', 120),
      ('Area de llaves / baul / punto de entrega', null, 'common_area', 130),
      ('Almacen / luggage storage', null, 'storage', 140),
      ('Refrigeradora', null, 'kitchen', 150),
      ('Cocina, lavadero y superficies', null, 'kitchen', 160),
      ('Orden y convivencia', null, 'kitchen', 170),
      ('Patio externo', null, 'external_patio', 180),
      ('Terraza', null, 'terrace', 190),
      ('Muebles de descanso de terraza', null, 'terrace_furniture', 200),
      ('Balcon', null, 'balcony', 210)
  ) as seed(name, description, scope, sort_order)
  where not exists (
    select 1
    from public.rm_checklist_sections s
    where s.template_id = v_template_id
      and s.name = seed.name
  );

  insert into public.rm_checklist_items (
    template_id,
    section_id,
    scope,
    item_code,
    title,
    description,
    expected_standard,
    default_priority,
    requires_photo_on_issue,
    requires_photo_always,
    can_create_issue,
    revenue_impact_category,
    is_required,
    sort_order,
    active
  )
  select
    v_template_id,
    (
      select s.id
      from public.rm_checklist_sections s
      where s.template_id = v_template_id
        and s.name = seed.section_name
      limit 1
    ),
    seed.scope,
    seed.item_code,
    seed.title,
    seed.description,
    seed.expected_standard,
    seed.default_priority,
    seed.requires_photo_on_issue,
    seed.requires_photo_always,
    seed.can_create_issue,
    seed.revenue_impact_category,
    true,
    seed.sort_order,
    true
  from (
    values
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_DOOR','Puerta de habitacion',null,'Abre y cierra correctamente, sin friccion ni ruido excesivo','high',true,false,true,'review_risk',10),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_LOCK','Cerradura',null,'Funciona sin trabarse','critical',true,false,true,'room_blocked',20),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_KEY','Llave fisica',null,'Existe, esta identificada y funciona correctamente','critical',true,false,true,'room_blocked',30),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_DUPLICATE_KEY','Duplicado de llave',null,'Disponible y controlado por administracion','high',true,false,true,'room_blocked',40),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_HANDLE','Manija',null,'Firme, limpia y sin juego excesivo','medium',true,false,true,'none',50),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_FRAME','Marco de puerta',null,'Sin rajaduras, golpes fuertes o humedad','medium',true,false,true,'repair_cost',60),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_LABEL','Numero o identificacion de habitacion',null,'Visible y en buen estado','low',false,false,true,'review_risk',70),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_INSIDE_SECURITY','Seguridad interior',null,'Pestillo o cierre interior funcional si aplica','critical',true,false,true,'room_blocked',80),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_SMART_LOCK','Smart lock / acceso remoto',null,'Funciona correctamente si aplica','critical',true,false,true,'room_blocked',90),
      ('Acceso, puerta, cerradura y llaves','room_common','ROOM_ACCESS_INSTRUCTIONS','Instrucciones de acceso',null,'Claras y actualizadas para esa habitacion','high',true,false,true,'review_risk',100),

      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_MATTRESS','Colchon',null,'Sin hundimientos, manchas fuertes, olores o danos','high',true,false,true,'review_risk',110),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_PROTECTOR','Protector de colchon',null,'Limpio, seco y en buen estado','high',true,false,true,'review_risk',120),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_SHEETS','Sabanas',null,'Limpias, sin manchas, roturas ni desgaste excesivo','critical',true,false,true,'review_risk',130),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_BLANKETS','Frazadas / edredon',null,'Limpio, sin olores ni manchas','high',true,false,true,'review_risk',140),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_PILLOWS','Almohadas',null,'Limpias, firmes, sin mal olor ni deformacion','high',true,false,true,'review_risk',150),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_PILLOW_CASES','Fundas',null,'Limpias, sin manchas ni roturas','high',true,false,true,'review_risk',160),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_HEADBOARD','Cabecera',null,'Limpia, firme y sin polvo acumulado','medium',true,false,true,'none',170),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_BASE','Base de cama',null,'Firme, sin ruido ni inestabilidad','high',true,false,true,'repair_cost',180),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_PRESENTATION','Presentacion general',null,'Cama tendida correctamente y visualmente ordenada','high',true,false,true,'review_risk',190),
      ('Cama, colchon y ropa de cama','room_common','ROOM_BED_EXTRA_LINEN','Ropa de cama extra',null,'Disponible solo si corresponde y bien almacenada','medium',true,false,true,'none',200),

      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_FLOOR','Piso',null,'Limpio, sin manchas, polvo, basura ni dano visible','high',true,false,true,'review_risk',210),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_BASEBOARDS','Zocalos',null,'Sin polvo acumulado ni humedad','medium',true,false,true,'none',220),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_WALLS','Paredes',null,'Sin manchas, hongos, rayones o descascaramiento relevante','high',true,false,true,'repair_cost',230),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_CEILING','Techo',null,'Sin humedad, goteras o grietas visibles','high',true,false,true,'repair_cost',240),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_CORNERS','Esquinas',null,'Sin telaranas, polvo o senales de humedad','medium',true,false,true,'review_risk',250),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_SMELL','Olor de habitacion',null,'Sin olor a humedad, encierro, comida o drenaje','high',true,false,true,'review_risk',260),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_VENTILATION','Ventilacion natural',null,'La habitacion puede ventilarse correctamente','high',true,false,true,'review_risk',270),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_NOISE','Ruido estructural',null,'Puertas, piso o ventanas no generan molestias excesivas','medium',true,false,true,'review_risk',280),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_LEAKS','Senales de filtracion',null,'No hay manchas nuevas o activas','critical',true,false,true,'room_blocked',290),
      ('Piso, paredes, techo y humedad','room_common','ROOM_STRUCTURE_PAINT','Pintura',null,'Estado aceptable para recibir huespedes','medium',true,false,true,'none',300),

      ('Ventanas, cortinas e iluminacion natural','room_common','ROOM_WINDOWS_OPERATION','Ventanas',null,'Abren y cierran correctamente','high',true,false,true,'review_risk',310),
      ('Ventanas, cortinas e iluminacion natural','room_common','ROOM_WINDOWS_GLASS','Vidrios',null,'Limpios, sin rajaduras peligrosas','high',true,false,true,'safety',320),
      ('Ventanas, cortinas e iluminacion natural','room_common','ROOM_WINDOWS_LOCKS','Seguros de ventana',null,'Funcionan correctamente','critical',true,false,true,'room_blocked',330),
      ('Ventanas, cortinas e iluminacion natural','room_common','ROOM_WINDOWS_CURTAINS','Cortinas',null,'Limpias, completas y funcionales','high',true,false,true,'review_risk',340),
      ('Ventanas, cortinas e iluminacion natural','room_common','ROOM_WINDOWS_BARS','Barras de cortina',null,'Firmes y bien colocadas','medium',true,false,true,'repair_cost',350),
      ('Ventanas, cortinas e iluminacion natural','room_common','ROOM_WINDOWS_PRIVACY','Privacidad',null,'La habitacion mantiene privacidad adecuada','high',true,false,true,'review_risk',360),
      ('Ventanas, cortinas e iluminacion natural','room_common','ROOM_WINDOWS_LIGHT','Entrada de luz',null,'Sin bloqueo innecesario salvo diseno propio','low',false,false,true,'none',370),
      ('Ventanas, cortinas e iluminacion natural','room_common','ROOM_WINDOWS_MOSQUITO_NET','Mosquitero',null,'En buen estado si aplica','medium',true,false,true,'none',380),

      ('Iluminacion y electricidad','room_common','ROOM_POWER_MAIN_LIGHT','Luz principal',null,'Funciona correctamente','high',true,false,true,'review_risk',390),
      ('Iluminacion y electricidad','room_common','ROOM_POWER_SECONDARY_LIGHTS','Lamparas secundarias',null,'Funcionan y tienen foco operativo','medium',true,false,true,'none',400),
      ('Iluminacion y electricidad','room_common','ROOM_POWER_SWITCHES','Interruptores',null,'Funcionan sin falso contacto','high',true,false,true,'electricity',410),
      ('Iluminacion y electricidad','room_common','ROOM_POWER_OUTLETS','Tomacorrientes',null,'Funcionan y estan firmes','critical',true,false,true,'room_blocked',420),
      ('Iluminacion y electricidad','room_common','ROOM_POWER_WIRING','Cables visibles',null,'No hay cables expuestos o peligrosos','critical',true,false,true,'room_blocked',430),
      ('Iluminacion y electricidad','room_common','ROOM_POWER_EXTENSIONS','Adaptadores/extensiones',null,'Solo si son seguros y necesarios','high',true,false,true,'electricity',440),
      ('Iluminacion y electricidad','room_common','ROOM_POWER_EXTRA_PLUGS','Cargadores o enchufes extras',null,'Buen estado si aplica','medium',true,false,true,'none',450),
      ('Iluminacion y electricidad','room_common','ROOM_POWER_NIGHT_LIGHT','Iluminacion nocturna',null,'Suficiente para circulacion segura','high',true,false,true,'review_risk',460),
      ('Iluminacion y electricidad','room_common','ROOM_POWER_ABNORMAL_USE','Consumo anomalo',null,'No hay equipos conectados innecesariamente','medium',true,false,true,'repair_cost',470),

      ('Internet / WiFi','room_common','ROOM_WIFI_SIGNAL','Senal WiFi',null,'Senal suficiente dentro de la habitacion','high',true,false,true,'review_risk',480),
      ('Internet / WiFi','room_common','ROOM_WIFI_SPEED','Velocidad percibida',null,'Adecuada para navegacion, WhatsApp y uso basico','high',true,false,true,'review_risk',490),
      ('Internet / WiFi','room_common','ROOM_WIFI_WORKSPACE','Zona de trabajo',null,'Mesa/silla con conectividad aceptable si aplica','medium',true,false,true,'review_risk',500),
      ('Internet / WiFi','room_common','ROOM_WIFI_DISCLOSURE','Comunicacion al huesped',null,'Si la senal es limitada, debe estar informado antes','high',true,false,true,'review_risk',510),
      ('Internet / WiFi','room_common','ROOM_WIFI_ROUTER','Router/repetidor cercano',null,'Encendido y funcionando si aplica','high',true,false,true,'wifi',520),
      ('Internet / WiFi','room_common','ROOM_WIFI_PASSWORD','Contrasena visible o enviada',null,'Correcta y actualizada','medium',true,false,true,'review_risk',530),

      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_DESK','Mesa o escritorio',null,'Limpio, firme y sin dano grave','medium',true,false,true,'none',540),
      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_CHAIR','Silla',null,'Firme, limpia y segura','medium',true,false,true,'safety',550),
      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_NIGHTSTAND','Velador',null,'Limpio y estable','medium',true,false,true,'none',560),
      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_CLOSET','Closet / perchero',null,'Limpio, funcional y sin olor','medium',true,false,true,'review_risk',570),
      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_MIRROR','Espejo',null,'Limpio, sin rajaduras peligrosas','high',true,false,true,'safety',580),
      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_SHELVES','Repisas',null,'Limpias y firmes','medium',true,false,true,'none',590),
      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_TRASH','Basurero',null,'Limpio, con bolsa y sin olor','high',true,false,true,'review_risk',600),
      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_DECOR','Decoracion',null,'En buen estado, sin piezas sueltas','low',false,false,true,'none',610),
      ('Muebles y equipamiento','room_common','ROOM_FURNITURE_INVENTORY','Inventario de habitacion',null,'Coincide con lo esperado para esa habitacion','high',true,false,true,'guest_compensation',620),

      ('Bano privado','room_private_bathroom','ROOM_BATH_TOILET','Inodoro',null,'Limpio, sin fugas y con descarga correcta','critical',true,false,true,'room_blocked',630),
      ('Bano privado','room_private_bathroom','ROOM_BATH_SINK','Lavamanos',null,'Limpio, sin obstruccion ni fuga','high',true,false,true,'repair_cost',640),
      ('Bano privado','room_private_bathroom','ROOM_BATH_SHOWER','Ducha',null,'Limpia, presion adecuada y sin fuga','critical',true,false,true,'room_blocked',650),
      ('Bano privado','room_private_bathroom','ROOM_BATH_HOT_WATER','Agua caliente',null,'Funciona correctamente','critical',true,false,true,'room_blocked',660),
      ('Bano privado','room_private_bathroom','ROOM_BATH_SCREEN','Cortina / mampara',null,'Limpia, sin hongos ni mal olor','high',true,false,true,'review_risk',670),
      ('Bano privado','room_private_bathroom','ROOM_BATH_FLOOR','Piso de bano',null,'Limpio, seco y sin riesgo de resbalon','high',true,false,true,'safety',680),
      ('Bano privado','room_private_bathroom','ROOM_BATH_MIRROR','Espejo de bano',null,'Limpio, sin manchas fuertes','medium',true,false,true,'none',690),
      ('Bano privado','room_private_bathroom','ROOM_BATH_FAUCETS','Griferia',null,'Limpia, sin sarro excesivo ni fuga','high',true,false,true,'repair_cost',700),
      ('Bano privado','room_private_bathroom','ROOM_BATH_DRAIN','Desague',null,'Sin mal olor ni obstruccion','critical',true,false,true,'room_blocked',710),
      ('Bano privado','room_private_bathroom','ROOM_BATH_TOILET_PAPER','Papel higienico',null,'Disponible segun estandar','high',true,false,true,'review_risk',720),
      ('Bano privado','room_private_bathroom','ROOM_BATH_AMENITIES','Jabon / amenities',null,'Disponible y presentable si aplica','medium',true,false,true,'guest_compensation',730),
      ('Bano privado','room_private_bathroom','ROOM_BATH_TOWELS','Toallas',null,'Limpias, secas, sin manchas ni olor','critical',true,false,true,'review_risk',740),
      ('Bano privado','room_private_bathroom','ROOM_BATH_VENTILATION','Ventilacion del bano',null,'Funciona o permite evitar humedad','high',true,false,true,'repair_cost',750),
      ('Bano privado','room_private_bathroom','ROOM_BATH_DOOR','Puerta del bano',null,'Cierra correctamente','high',true,false,true,'review_risk',760),

      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_HIGH_DUST','Polvo en superficies altas',null,'Sin acumulacion visible','medium',true,false,true,'review_risk',770),
      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_UNDER_BED','Polvo debajo de cama',null,'Sin suciedad acumulada','high',true,false,true,'review_risk',780),
      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_GENERAL_SMELL','Olor general',null,'Fresco, limpio y neutro','high',true,false,true,'review_risk',790),
      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_HAIR','Cabellos visibles',null,'No debe haber cabellos en cama, bano o piso','critical',true,false,true,'review_risk',800),
      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_STAINS','Manchas visibles',null,'No debe haber manchas en textiles o superficies principales','high',true,false,true,'review_risk',810),
      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_FORGOTTEN_ITEMS','Objetos olvidados',null,'No hay pertenencias de huespedes anteriores','critical',true,false,true,'guest_compensation',820),
      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_CHECKIN_READY','Presentacion al ingreso',null,'Habitacion lista para check-in','critical',true,false,true,'room_blocked',830),
      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_LISTING_MATCH','Coherencia con fotos online',null,'El estado real coincide con lo ofrecido','high',true,false,true,'review_risk',840),
      ('Limpieza profunda y experiencia del huesped','room_common','ROOM_EXPERIENCE_COMFORT','Ruido / confort',null,'No hay ruidos evitables dentro de la habitacion','medium',true,false,true,'review_risk',850),

      ('Seguridad y riesgos','room_common','ROOM_SAFETY_ELECTRICAL','Riesgo electrico',null,'Sin cables expuestos, enchufes flojos o sobrecarga','critical',true,false,true,'room_blocked',860),
      ('Seguridad y riesgos','room_common','ROOM_SAFETY_FALLS','Riesgo de caida',null,'Piso, alfombra o escalon sin peligro visible','critical',true,false,true,'room_blocked',870),
      ('Seguridad y riesgos','room_common','ROOM_SAFETY_GLASS','Vidrios o espejos',null,'Sin rajaduras peligrosas','critical',true,false,true,'safety',880),
      ('Seguridad y riesgos','room_common','ROOM_SAFETY_FURNITURE','Muebles inestables',null,'Ningun mueble debe tambalearse peligrosamente','high',true,false,true,'safety',890),
      ('Seguridad y riesgos','room_common','ROOM_SAFETY_HUMIDITY','Humedad activa',null,'No debe haber humedad que afecte salud o estructura','critical',true,false,true,'room_blocked',900),
      ('Seguridad y riesgos','room_common','ROOM_SAFETY_THIRD_PARTY_ACCESS','Acceso de terceros',null,'Puertas y ventanas seguras','critical',true,false,true,'room_blocked',910),
      ('Seguridad y riesgos','room_common','ROOM_SAFETY_SIGNAGE','Senalizacion necesaria',null,'Si hay una particularidad, debe estar comunicada','medium',true,false,true,'none',920),

      ('Entrada principal / fachada / puerta de calle','entrance','ENTRANCE_MAIN_DOOR','Puerta de calle',null,'Abre y cierra correctamente','critical',true,false,true,'room_blocked',930),
      ('Entrada principal / fachada / puerta de calle','entrance','ENTRANCE_KEY_BOX','Llave temporal / caja externa',null,'Disponible, limpia y funcional si aplica','critical',true,false,true,'room_blocked',940),
      ('Entrada principal / fachada / puerta de calle','entrance','ENTRANCE_KEY_SAFE','Caja gris/azul de llave',null,'Codigo o mecanismo funcionando','critical',true,false,true,'room_blocked',950),
      ('Entrada principal / fachada / puerta de calle','entrance','ENTRANCE_LIGHTING','Iluminacion de entrada',null,'Suficiente para llegada nocturna','high',true,false,true,'review_risk',960),
      ('Entrada principal / fachada / puerta de calle','entrance','ENTRANCE_SIGNAGE','Senalizacion',null,'Clara, discreta y util para huespedes','medium',true,false,true,'review_risk',970),
      ('Entrada principal / fachada / puerta de calle','entrance','ENTRANCE_CLEANLINESS','Limpieza exterior',null,'Sin basura o elementos que den mala impresion','high',true,false,true,'review_risk',980),
      ('Entrada principal / fachada / puerta de calle','entrance','ENTRANCE_SAFETY','Seguridad entrada',null,'No hay objetos peligrosos o sueltos','critical',true,false,true,'safety',990),
      ('Entrada principal / fachada / puerta de calle','entrance','ENTRANCE_BELL','Timbre/intercomunicador',null,'Funciona correctamente si aplica','medium',true,false,true,'review_risk',1000),

      ('Pasillos, escaleras y circulacion interna','common_area','COMMON_HALL_FLOOR','Piso de pasillos',null,'Limpio y sin obstaculos','high',true,false,true,'review_risk',1010),
      ('Pasillos, escaleras y circulacion interna','common_area','COMMON_STAIRS','Escaleras',null,'Limpias, seguras y sin objetos sueltos','critical',true,false,true,'safety',1020),
      ('Pasillos, escaleras y circulacion interna','common_area','COMMON_HANDRAILS','Barandas',null,'Firmes y limpias','critical',true,false,true,'safety',1030),
      ('Pasillos, escaleras y circulacion interna','common_area','COMMON_LIGHTING','Iluminacion de circulacion',null,'Funciona correctamente','high',true,false,true,'review_risk',1040),
      ('Pasillos, escaleras y circulacion interna','common_area','COMMON_WALLS','Paredes',null,'Sin manchas graves o humedad visible','medium',true,false,true,'repair_cost',1050),
      ('Pasillos, escaleras y circulacion interna','common_area','COMMON_SMELL','Olor',null,'Sin humedad, comida o basura','high',true,false,true,'review_risk',1060),
      ('Pasillos, escaleras y circulacion interna','common_area','COMMON_NOISE','Ruido',null,'Sin elementos que generen ruido innecesario','medium',true,false,true,'review_risk',1070),
      ('Pasillos, escaleras y circulacion interna','common_area','COMMON_PERSONAL_ITEMS','Objetos personales',null,'No deben invadir zonas comunes','medium',true,false,true,'none',1080),

      ('Area de llaves / baul / punto de entrega','common_area','COMMON_KEYS_CHEST','Baul o punto de entrega',null,'Limpio, visible y ordenado','high',true,false,true,'review_risk',1090),
      ('Area de llaves / baul / punto de entrega','common_area','COMMON_KEYS_TEMPORARY','Llave temporal Inca/Tumi',null,'Debe estar donde corresponde despues del uso','critical',true,false,true,'room_blocked',1100),
      ('Area de llaves / baul / punto de entrega','common_area','COMMON_KEYS_SETS','Juegos de llaves',null,'Identificados por habitacion','critical',true,false,true,'room_blocked',1110),
      ('Area de llaves / baul / punto de entrega','common_area','COMMON_KEYS_DUPLICATES','Duplicados',null,'Controlados y no accesibles a huespedes','critical',true,false,true,'room_blocked',1120),
      ('Area de llaves / baul / punto de entrega','common_area','COMMON_KEYS_INTERNAL_INSTRUCTIONS','Instrucciones internas',null,'Actualizadas para housekeeping/supervisora','high',true,false,true,'review_risk',1130),
      ('Area de llaves / baul / punto de entrega','common_area','COMMON_KEYS_RETURN_EVIDENCE','Evidencia de devolucion',null,'Foto o confirmacion cuando aplique','medium',true,false,true,'none',1140),

      ('Almacen / luggage storage','storage','STORAGE_ORDER','Orden general',null,'Maletas y objetos correctamente ubicados','high',true,false,true,'review_risk',1150),
      ('Almacen / luggage storage','storage','STORAGE_SECURITY','Seguridad',null,'Objetos de huespedes protegidos','critical',true,false,true,'guest_compensation',1160),
      ('Almacen / luggage storage','storage','STORAGE_IDENTIFICATION','Identificacion',null,'Maletas identificadas por huesped/habitacion','high',true,false,true,'guest_compensation',1170),
      ('Almacen / luggage storage','storage','STORAGE_CLEANLINESS','Limpieza',null,'Sin polvo, humedad ni malos olores','high',true,false,true,'review_risk',1180),
      ('Almacen / luggage storage','storage','STORAGE_ACCESSIBILITY','Accesibilidad',null,'Housekeeping puede acceder sin bloquear circulacion','medium',true,false,true,'none',1190),
      ('Almacen / luggage storage','storage','STORAGE_LOG','Registro',null,'Existe control de ingreso/salida de equipaje','high',true,false,true,'guest_compensation',1200),

      ('Refrigeradora','kitchen','KITCHEN_FRIDGE_CLEANLINESS','Limpieza general',null,'Interior limpio, sin derrames ni olores','high',true,false,true,'review_risk',1210),
      ('Refrigeradora','kitchen','KITCHEN_FRIDGE_ASSIGNMENTS','Bandejas asignadas',null,'Cada habitacion usa su piso/bandeja asignada','high',true,false,true,'review_risk',1220),
      ('Refrigeradora','kitchen','KITCHEN_FRIDGE_EXPIRED','Alimentos vencidos',null,'No debe haber alimentos abandonados o en mal estado','high',true,false,true,'review_risk',1230),
      ('Refrigeradora','kitchen','KITCHEN_FRIDGE_SPACE','Espacio disponible',null,'La habitacion entrante tiene espacio libre','high',true,false,true,'guest_compensation',1240),
      ('Refrigeradora','kitchen','KITCHEN_FRIDGE_TEMPERATURE','Temperatura',null,'Enfria correctamente','critical',true,false,true,'repair_cost',1250),
      ('Refrigeradora','kitchen','KITCHEN_FRIDGE_FREEZER','Congelador',null,'Sin exceso de hielo o derrames si aplica','medium',true,false,true,'repair_cost',1260),
      ('Refrigeradora','kitchen','KITCHEN_FRIDGE_LABELS','Etiquetado',null,'Alimentos identificados por habitacion si aplica','medium',true,false,true,'none',1270),
      ('Refrigeradora','kitchen','KITCHEN_FRIDGE_EXTERIOR','Exterior',null,'Limpio, sin manchas visibles','medium',true,false,true,'none',1280),

      ('Cocina, lavadero y superficies','kitchen','KITCHEN_SINK','Lavadero',null,'Limpio, sin obstruccion ni mal olor','high',true,false,true,'review_risk',1290),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_FAUCET','Grifo',null,'Sin fuga y con presion normal','high',true,false,true,'repair_cost',1300),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_COUNTER','Mesa / meson',null,'Limpio y seco','high',true,false,true,'review_risk',1310),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_STOVE','Cocina / hornilla',null,'Limpia y segura','high',true,false,true,'safety',1320),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_GAS_POWER','Gas/electricidad',null,'Sin senales de riesgo','critical',true,false,true,'safety',1330),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_DISHWARE','Vajilla',null,'Limpia, completa y ordenada','medium',true,false,true,'guest_compensation',1340),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_UTENSILS','Utensilios',null,'Limpios y en lugar correcto','medium',true,false,true,'none',1350),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_SPONGES','Esponjas/secadores',null,'En buen estado, sin olor fuerte','medium',true,false,true,'review_risk',1360),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_TRASH','Basurero',null,'Limpio, con bolsa y sin desborde','high',true,false,true,'review_risk',1370),
      ('Cocina, lavadero y superficies','kitchen','KITCHEN_FLOOR','Piso de cocina',null,'Limpio, seco y sin grasa o restos','high',true,false,true,'review_risk',1380),

      ('Orden y convivencia','kitchen','KITCHEN_RULES','Reglas visibles',null,'Uso de cocina y refrigeradora claro para huespedes','medium',true,false,true,'review_risk',1390),
      ('Orden y convivencia','kitchen','KITCHEN_ODORS','Olores',null,'Sin olor fuerte a comida acumulada','high',true,false,true,'review_risk',1400),
      ('Orden y convivencia','kitchen','KITCHEN_PENDING_DISHES','Platos pendientes',null,'No debe haber acumulacion excesiva','medium',true,false,true,'none',1410),
      ('Orden y convivencia','kitchen','KITCHEN_OWNERLESS_FOOD','Alimentos sin dueno',null,'Deben moverse o descartarse segun politica','medium',true,false,true,'none',1420),
      ('Orden y convivencia','kitchen','KITCHEN_PESTS','Control de plagas',null,'Sin senales de insectos o roedores','critical',true,false,true,'room_blocked',1430),
      ('Orden y convivencia','kitchen','KITCHEN_VENTILATION','Ventilacion',null,'Cocina puede ventilarse correctamente','high',true,false,true,'review_risk',1440),

      ('Patio externo','external_patio','PATIO_FLOOR','Piso',null,'Limpio, sin basura, charcos o elementos peligrosos','high',true,false,true,'review_risk',1450),
      ('Patio externo','external_patio','PATIO_DRAINAGE','Drenaje',null,'Sin acumulacion de agua','high',true,false,true,'repair_cost',1460),
      ('Patio externo','external_patio','PATIO_WALLS','Paredes exteriores',null,'Sin humedad critica, manchas fuertes o desprendimientos','medium',true,false,true,'repair_cost',1470),
      ('Patio externo','external_patio','PATIO_PLANTS','Plantas/macetas',null,'Ordenadas, sin tierra derramada','low',false,false,true,'none',1480),
      ('Patio externo','external_patio','PATIO_LIGHTING','Iluminacion',null,'Funciona correctamente en la noche','high',true,false,true,'review_risk',1490),
      ('Patio externo','external_patio','PATIO_SAFETY','Seguridad',null,'Sin objetos cortantes, cables o muebles inestables','critical',true,false,true,'safety',1500),
      ('Patio externo','external_patio','PATIO_SMELL','Olor',null,'Sin olor a humedad, basura o drenaje','high',true,false,true,'review_risk',1510),
      ('Patio externo','external_patio','PATIO_ACCESS','Acceso',null,'Libre de obstaculos','high',true,false,true,'review_risk',1520),
      ('Patio externo','external_patio','PATIO_PRESENTATION','Presentacion visual',null,'Agradable para huespedes','medium',true,false,true,'review_risk',1530),

      ('Terraza','terrace','TERRACE_FLOOR','Piso de terraza',null,'Limpio, seco y sin zonas peligrosas','high',true,false,true,'review_risk',1540),
      ('Terraza','terrace','TERRACE_RAILINGS','Barandas',null,'Firmes y seguras','critical',true,false,true,'safety',1550),
      ('Terraza','terrace','TERRACE_LIGHTING','Iluminacion',null,'Funciona correctamente','high',true,false,true,'review_risk',1560),
      ('Terraza','terrace','TERRACE_FURNITURE','Muebles',null,'Limpios, firmes y bien ubicados','high',true,false,true,'guest_compensation',1570),
      ('Terraza','terrace','TERRACE_CUSHIONS','Cojines',null,'Limpios, secos y sin mal olor','high',true,false,true,'review_risk',1580),
      ('Terraza','terrace','TERRACE_TABLES','Mesas auxiliares',null,'Limpias y estables','medium',true,false,true,'none',1590),
      ('Terraza','terrace','TERRACE_DECOR','Plantas/decoracion',null,'Ordenadas y sin deterioro grave','low',false,false,true,'none',1600),
      ('Terraza','terrace','TERRACE_DRAINAGE','Drenaje',null,'Sin acumulacion de agua','high',true,false,true,'repair_cost',1610),
      ('Terraza','terrace','TERRACE_PRESENTATION','Vista/presentacion',null,'Zona agradable para descanso','medium',true,false,true,'review_risk',1620),
      ('Terraza','terrace','TERRACE_NOISE','Ruido',null,'No hay elementos que generen molestias','medium',true,false,true,'review_risk',1630),
      ('Terraza','terrace','TERRACE_WEATHER_PROTECTION','Seguridad climatica',null,'Muebles protegidos de lluvia o humedad cuando aplique','medium',true,false,true,'repair_cost',1640),

      ('Muebles de descanso de terraza','terrace_furniture','TERRACE_FURN_SOFA','Sofas/sillas',null,'Firmes, estables y seguros','high',true,false,true,'guest_compensation',1650),
      ('Muebles de descanso de terraza','terrace_furniture','TERRACE_FURN_CUSHIONS','Cojines de descanso',null,'Limpios, secos, sin manchas ni olor','high',true,false,true,'review_risk',1660),
      ('Muebles de descanso de terraza','terrace_furniture','TERRACE_FURN_UPHOLSTERY','Tapizados',null,'Sin roturas graves o suciedad visible','medium',true,false,true,'review_risk',1670),
      ('Muebles de descanso de terraza','terrace_furniture','TERRACE_FURN_STRUCTURE','Estructura de madera/metal',null,'Sin oxido, astillas o piezas flojas','high',true,false,true,'safety',1680),
      ('Muebles de descanso de terraza','terrace_furniture','TERRACE_FURN_TABLES','Mesas',null,'Estables y limpias','medium',true,false,true,'none',1690),
      ('Muebles de descanso de terraza','terrace_furniture','TERRACE_FURN_LAYOUT','Distribucion',null,'Permite circulacion comoda','medium',true,false,true,'none',1700),
      ('Muebles de descanso de terraza','terrace_furniture','TERRACE_FURN_PROTECTION','Proteccion climatica',null,'Guardados o protegidos si hay lluvia/humedad','medium',true,false,true,'repair_cost',1710),
      ('Muebles de descanso de terraza','terrace_furniture','TERRACE_FURN_PRESENTATION','Presentacion',null,'Zona lista para uso de huespedes','high',true,false,true,'review_risk',1720),

      ('Balcon','balcony','BALCONY_RAILING','Baranda',null,'Firme, segura y sin piezas sueltas','critical',true,false,true,'safety',1730),
      ('Balcon','balcony','BALCONY_FLOOR','Piso',null,'Limpio, seco y sin riesgo de caida','high',true,false,true,'review_risk',1740),
      ('Balcon','balcony','BALCONY_DOOR','Puerta/ventana al balcon',null,'Abre, cierra y asegura correctamente','critical',true,false,true,'room_blocked',1750),
      ('Balcon','balcony','BALCONY_DRAINAGE','Drenaje',null,'Sin acumulacion de agua','high',true,false,true,'repair_cost',1760),
      ('Balcon','balcony','BALCONY_FURNITURE','Muebles',null,'Firmes y seguros si aplica','high',true,false,true,'guest_compensation',1770),
      ('Balcon','balcony','BALCONY_GLASS','Vidrios',null,'Limpios y sin rajaduras peligrosas','high',true,false,true,'safety',1780),
      ('Balcon','balcony','BALCONY_LOOSE_OBJECTS','Objetos sueltos',null,'No hay elementos que puedan caer','critical',true,false,true,'safety',1790),
      ('Balcon','balcony','BALCONY_LIGHTING','Iluminacion',null,'Suficiente si aplica','medium',true,false,true,'review_risk',1800),
      ('Balcon','balcony','BALCONY_PRESENTATION','Presentacion',null,'Ordenado y agradable','medium',true,false,true,'review_risk',1810)
  ) as seed(section_name, scope, item_code, title, description, expected_standard, default_priority, requires_photo_on_issue, requires_photo_always, can_create_issue, revenue_impact_category, sort_order)
  where not exists (
    select 1
    from public.rm_checklist_items i
    where i.template_id = v_template_id
      and i.item_code = seed.item_code
  );
end $$;

notify pgrst, 'reload schema';

commit;
