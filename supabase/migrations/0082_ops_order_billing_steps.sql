-- OPS: derive the visible billing indicator from an explicit checklist step
begin;

alter table public.ops_task_templates
  add column if not exists billing_step_mode text not null default 'none';

alter table public.ops_order_tasks
  add column if not exists billing_step_mode text not null default 'none',
  add column if not exists billing_resolution text;

alter table public.ops_task_templates
  drop constraint if exists ops_task_templates_billing_step_mode_check;
alter table public.ops_task_templates
  add constraint ops_task_templates_billing_step_mode_check
  check (billing_step_mode in ('none', 'invoice', 'invoice_or_not_applicable'));

alter table public.ops_order_tasks
  drop constraint if exists ops_order_tasks_billing_step_mode_check;
alter table public.ops_order_tasks
  add constraint ops_order_tasks_billing_step_mode_check
  check (billing_step_mode in ('none', 'invoice', 'invoice_or_not_applicable'));

alter table public.ops_order_tasks
  drop constraint if exists ops_order_tasks_billing_resolution_check;
alter table public.ops_order_tasks
  add constraint ops_order_tasks_billing_resolution_check
  check (
    billing_resolution is null
    or (
      billing_step_mode <> 'none'
      and billing_resolution in ('invoiced', 'not_applicable')
      and (
        billing_step_mode = 'invoice_or_not_applicable'
        or billing_resolution = 'invoiced'
      )
      and (
        completed_at is not null
        or lower(btrim(coalesce(status, ''))) in ('completado', 'completed')
      )
    )
  );

-- The audit deliberately uses exact order type names and exact step codes. Titles
-- are not used because supplier invoices and non-final invoice steps also exist.
with audited_steps(order_type_name, step_code, billing_step_mode) as (
  values
    ('Alquiler / Préstamo de equipos', '07', 'invoice_or_not_applicable'),
    ('Armado y configuración de PC a medida', '12', 'invoice'),
    ('Contrato de soporte IT recurrente', '12', 'invoice'),
    ('Entrega de insumos / componentes', '04', 'invoice'),
    ('Garantía / Post-venta', '12', 'invoice_or_not_applicable'),
    ('Reparación de laptop/PC con recojo y entrega', '15', 'invoice'),
    ('Servicio de impresoras (recojo, reparación, entrega)', '14', 'invoice'),
    ('Servicio técnico en sitio del cliente', '11', 'invoice'),
    ('Venta de hardware nuevo con entrega', '10', 'invoice')
)
update public.ops_task_templates template
set billing_step_mode = audited.billing_step_mode
from public.ops_order_types order_type
join audited_steps audited
  on audited.order_type_name = order_type.name
where template.order_type_id = order_type.id
  and template.step_code = audited.step_code;

with audited_steps(order_type_name, step_code, billing_step_mode) as (
  values
    ('Alquiler / Préstamo de equipos', '07', 'invoice_or_not_applicable'),
    ('Armado y configuración de PC a medida', '12', 'invoice'),
    ('Contrato de soporte IT recurrente', '12', 'invoice'),
    ('Entrega de insumos / componentes', '04', 'invoice'),
    ('Garantía / Post-venta', '12', 'invoice_or_not_applicable'),
    ('Reparación de laptop/PC con recojo y entrega', '15', 'invoice'),
    ('Servicio de impresoras (recojo, reparación, entrega)', '14', 'invoice'),
    ('Servicio técnico en sitio del cliente', '11', 'invoice'),
    ('Venta de hardware nuevo con entrega', '10', 'invoice')
)
update public.ops_order_tasks task
set billing_step_mode = audited.billing_step_mode
from public.ops_orders orders
join public.ops_order_types order_type
  on order_type.id = orders.order_type_id
join audited_steps audited
  on audited.order_type_name = order_type.name
where task.order_id = orders.id
  and task.step_code = audited.step_code;

-- Preserve historical meaning without creating accounting invoices. Conditional
-- steps only count as invoiced when the order already has a real invoice.
update public.ops_order_tasks task
set billing_resolution = case
  when task.billing_step_mode = 'invoice' then 'invoiced'
  when orders.billing_status = 'invoiced' or orders.billing_invoice_id is not null
    then 'invoiced'
  else 'not_applicable'
end
from public.ops_orders orders
where task.order_id = orders.id
  and task.billing_step_mode <> 'none'
  and (
    task.completed_at is not null
    or lower(btrim(coalesce(task.status, ''))) in ('completado', 'completed')
  );

update public.ops_order_tasks
set billing_resolution = null
where billing_step_mode = 'none'
   or not (
     completed_at is not null
     or lower(btrim(coalesce(status, ''))) in ('completado', 'completed')
   );

create unique index if not exists uq_ops_task_templates_active_billing_step
  on public.ops_task_templates(order_type_id)
  where active = true and billing_step_mode <> 'none';

create unique index if not exists uq_ops_order_tasks_billing_step
  on public.ops_order_tasks(order_id)
  where billing_step_mode <> 'none';

notify pgrst, 'reload schema';

commit;
