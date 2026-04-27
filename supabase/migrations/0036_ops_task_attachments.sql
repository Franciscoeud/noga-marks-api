-- OPS: task attachments for images and PDFs
begin;

create table if not exists public.ops_order_task_attachments (
  id uuid primary key default uuid_generate_v4(),
  order_id uuid not null references public.ops_orders(id) on delete cascade,
  task_id uuid not null references public.ops_order_tasks(id) on delete cascade,
  url text not null,
  path text,
  filename text,
  mime_type text,
  file_kind text not null check (file_kind in ('image', 'pdf')),
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_ops_order_task_attachments_order
  on public.ops_order_task_attachments(order_id);

create index if not exists idx_ops_order_task_attachments_task
  on public.ops_order_task_attachments(task_id, created_at);

alter table public.ops_order_task_attachments enable row level security;

drop policy if exists "ops_order_task_attachments_read" on public.ops_order_task_attachments;
create policy "ops_order_task_attachments_read" on public.ops_order_task_attachments
  for select to authenticated
  using (true);

drop policy if exists "ops_order_task_attachments_write" on public.ops_order_task_attachments;
create policy "ops_order_task_attachments_write" on public.ops_order_task_attachments
  for insert to authenticated
  with check (true);

drop policy if exists "ops_order_task_attachments_update" on public.ops_order_task_attachments;
create policy "ops_order_task_attachments_update" on public.ops_order_task_attachments
  for update to authenticated
  using (true)
  with check (true);

drop policy if exists "ops_order_task_attachments_delete" on public.ops_order_task_attachments;
create policy "ops_order_task_attachments_delete" on public.ops_order_task_attachments
  for delete to authenticated
  using (true);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'ops-photos',
  'ops-photos',
  true,
  10485760,
  array[
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/heic',
    'image/heif',
    'application/pdf'
  ]
)
on conflict (id)
do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

commit;
