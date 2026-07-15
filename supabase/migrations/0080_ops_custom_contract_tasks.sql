-- OPS: custom one-step tasks for contract clients
begin;

create extension if not exists "uuid-ossp";

alter table public.ops_orders
  add column if not exists is_custom_task_order boolean not null default false;

create index if not exists idx_ops_orders_custom_task
  on public.ops_orders(is_custom_task_order)
  where is_custom_task_order = true;

insert into public.ops_order_types (id, name, sharepoint_id)
select uuid_generate_v4(), 'Tarea personalizada', null
where not exists (
  select 1
  from public.ops_order_types
  where lower(btrim(name)) = lower('Tarea personalizada')
);

notify pgrst, 'reload schema';

commit;
