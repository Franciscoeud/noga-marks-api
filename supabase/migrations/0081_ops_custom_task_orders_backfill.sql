-- OPS: backfill custom task order flag for existing technical type orders
begin;

update public.ops_orders o
set
  is_custom_task_order = true,
  updated_at = timezone('utc', now())
from public.ops_order_types t
where o.order_type_id = t.id
  and lower(btrim(t.name)) = lower('Tarea personalizada')
  and coalesce(o.is_custom_task_order, false) = false;

notify pgrst, 'reload schema';

commit;
