-- OPS: include order type in daily WhatsApp summary critical orders
begin;

create or replace function public.ops_build_daily_order_summary(
  p_today date default null,
  p_limit int default 10
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
with params as (
  select
    coalesce(p_today, timezone('America/Lima', now())::date) as today,
    greatest(coalesce(p_limit, 10), 1) as safe_limit,
    timezone('America/Lima', now()) as now_local
),
window_bounds as (
  select
    today,
    safe_limit,
    now_local,
    today::timestamp as day_start,
    (today + 1)::timestamp as day_end
  from params
),
active_orders as (
  select
    o.id,
    o.cod,
    o.subject,
    o.status,
    o.delivery_date,
    o.delivery_time,
    coalesce(nullif(o.client_text, ''), c.name, '-') as client_name,
    nullif(ot.name, '') as order_type_name,
    case
      when o.delivery_date is null then null
      else o.delivery_date::timestamp + coalesce(o.delivery_time, time '00:00')
    end as delivery_at
  from public.ops_orders o
  left join public.ops_clients c on c.id = o.client_id
  left join public.ops_order_types ot on ot.id = o.order_type_id
  where o.status in ('Pendiente', 'Procesando')
),
task_flow as (
  select
    t.*,
    (
      t.completed_at is not null
      or coalesce(t.status, 'Pendiente') = 'Completado'
    ) as is_completed,
    exists (
      select 1
      from public.ops_order_tasks previous_task
      where previous_task.order_id = t.order_id
        and coalesce(previous_task.is_gate, false)
        and not (
          previous_task.completed_at is not null
          or coalesce(previous_task.status, 'Pendiente') = 'Completado'
        )
        and (
          coalesce(previous_task.order_index, 0),
          coalesce(previous_task.step_code, ''),
          previous_task.id::text
        ) < (
          coalesce(t.order_index, 0),
          coalesce(t.step_code, ''),
          t.id::text
        )
    ) as computed_is_blocked
  from public.ops_order_tasks t
  join active_orders o on o.id = t.order_id
),
top_orders as (
  select
    o.*,
    current_stage.step_code as current_stage_code,
    current_stage.title as current_stage_title
  from active_orders o
  left join lateral (
    select tf.step_code, tf.title
    from task_flow tf
    where tf.order_id = o.id
      and not tf.is_completed
      and not tf.computed_is_blocked
    order by
      case when coalesce(tf.is_required, true) then 0 else 1 end,
      coalesce(tf.order_index, 0),
      coalesce(tf.step_code, '')
    limit 1
  ) current_stage on true
  order by
    (o.delivery_at is not null and o.delivery_at < (select now_local from window_bounds)) desc,
    (
      o.delivery_at is not null
      and o.delivery_at >= (select now_local from window_bounds)
      and o.delivery_at < (select day_end from window_bounds)
    ) desc,
    o.delivery_at asc nulls last,
    o.cod desc nulls last
  limit (select safe_limit from window_bounds)
),
top_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', id,
        'cod', cod,
        'subject', subject,
        'client', client_name,
        'order_type_name', order_type_name,
        'status', status,
        'current_stage_code', current_stage_code,
        'current_stage_title', current_stage_title,
        'delivery_at', delivery_at,
        'is_overdue', delivery_at is not null and delivery_at < (select now_local from window_bounds),
        'is_due_today',
          delivery_at is not null
          and delivery_at >= (select now_local from window_bounds)
          and delivery_at < (select day_end from window_bounds)
      )
      order by
        (delivery_at is not null and delivery_at < (select now_local from window_bounds)) desc,
        delivery_at asc nulls last,
        cod desc nulls last
    ),
    '[]'::jsonb
  ) as items
  from top_orders
)
select jsonb_build_object(
  'date', (select today from window_bounds),
  'timezone', 'America/Lima',
  'generated_at', timezone('America/Lima', now()),
  'total_pending_orders', (select count(*) from active_orders),
  'overdue_orders', (
    select count(*)
    from active_orders
    where delivery_at is not null
      and delivery_at < (select now_local from window_bounds)
  ),
  'due_today_orders', (
    select count(*)
    from active_orders
    where delivery_at is not null
      and delivery_at >= (select now_local from window_bounds)
      and delivery_at < (select day_end from window_bounds)
  ),
  'pending_status_orders', (
    select count(*)
    from active_orders
    where status = 'Pendiente'
  ),
  'processing_status_orders', (
    select count(*)
    from active_orders
    where status = 'Procesando'
  ),
  'critical_orders', (select items from top_json)
);
$$;

revoke all on function public.ops_build_daily_order_summary(date, int) from public;

notify pgrst, 'reload schema';

commit;
