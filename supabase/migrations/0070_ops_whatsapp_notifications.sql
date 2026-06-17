-- OPS: WhatsApp daily notification recipients, logs and summary RPCs
begin;

create extension if not exists "uuid-ossp";

create table if not exists public.ops_notification_recipients (
  id uuid primary key default uuid_generate_v4(),
  name text not null,
  whatsapp_to text not null,
  recipient_type text not null,
  assignee_id uuid references public.ops_assignees(id) on delete set null,
  active boolean not null default true,
  timezone text not null default 'America/Lima',
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint ops_notification_recipients_type_check
    check (recipient_type in ('general', 'assignee')),
  constraint ops_notification_recipients_whatsapp_check
    check (whatsapp_to ~ '^whatsapp:\+[0-9]{8,15}$'),
  constraint ops_notification_recipients_assignee_check
    check (
      (recipient_type = 'assignee' and assignee_id is not null)
      or (recipient_type = 'general')
    )
);

create table if not exists public.ops_notification_logs (
  id uuid primary key default uuid_generate_v4(),
  notification_date date not null,
  notification_type text not null,
  recipient_id uuid references public.ops_notification_recipients(id) on delete set null,
  assignee_id uuid references public.ops_assignees(id) on delete set null,
  whatsapp_to text,
  status text not null,
  dry_run boolean not null default false,
  twilio_message_sid text,
  payload jsonb not null default '{}'::jsonb,
  error_message text,
  sent_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  constraint ops_notification_logs_type_check
    check (notification_type in ('daily_summary', 'assignee_summary')),
  constraint ops_notification_logs_status_check
    check (status in ('success', 'error', 'skipped'))
);

create index if not exists idx_ops_notification_recipients_active_type
  on public.ops_notification_recipients(active, recipient_type);
create index if not exists idx_ops_notification_recipients_assignee
  on public.ops_notification_recipients(assignee_id)
  where assignee_id is not null;
create index if not exists idx_ops_notification_logs_sent_at
  on public.ops_notification_logs(sent_at desc);
create index if not exists idx_ops_notification_logs_recipient_date
  on public.ops_notification_logs(notification_date, notification_type, recipient_id);
create unique index if not exists uq_ops_notification_logs_success_once
  on public.ops_notification_logs(notification_date, notification_type, recipient_id)
  where dry_run = false and status = 'success' and recipient_id is not null;

drop trigger if exists trg_ops_notification_recipients_updated_at
  on public.ops_notification_recipients;
create trigger trg_ops_notification_recipients_updated_at
before update on public.ops_notification_recipients
for each row execute procedure public.set_updated_at();

alter table public.ops_notification_recipients enable row level security;
alter table public.ops_notification_logs enable row level security;

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
    case
      when o.delivery_date is null then null
      else o.delivery_date::timestamp + coalesce(o.delivery_time, time '00:00')
    end as delivery_at
  from public.ops_orders o
  left join public.ops_clients c on c.id = o.client_id
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

create or replace function public.ops_build_assignee_task_summary(
  p_assignee_id uuid,
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
assignee as (
  select id, name
  from public.ops_assignees
  where id = p_assignee_id
),
active_orders as (
  select
    o.id,
    o.cod,
    o.subject,
    o.status,
    coalesce(nullif(o.client_text, ''), c.name, '-') as client_name
  from public.ops_orders o
  left join public.ops_clients c on c.id = o.client_id
  where o.status in ('Pendiente', 'Procesando')
),
task_flow as (
  select
    t.*,
    ao.cod,
    ao.subject,
    ao.client_name,
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
    ) as computed_is_blocked,
    case
      when t.due_at is null then null
      else t.due_at at time zone 'America/Lima'
    end as due_at_local
  from public.ops_order_tasks t
  join active_orders ao on ao.id = t.order_id
  where t.assignee_id = p_assignee_id
),
visible_tasks as (
  select *
  from task_flow
  where not is_completed
    and (
      not computed_is_blocked
      or coalesce(is_conditional, false)
    )
),
top_tasks as (
  select *
  from visible_tasks
  order by
    (due_at_local is not null and due_at_local < (select now_local from window_bounds)) desc,
    (
      due_at_local is not null
      and due_at_local >= (select now_local from window_bounds)
      and due_at_local < (select day_end from window_bounds)
    ) desc,
    due_at_local asc nulls last,
    cod desc nulls last,
    coalesce(order_index, 0),
    coalesce(step_code, '')
  limit (select safe_limit from window_bounds)
),
top_json as (
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'task_id', id,
        'order_id', order_id,
        'order_cod', cod,
        'order_subject', subject,
        'client', client_name,
        'step_code', step_code,
        'title', title,
        'due_at', due_at,
        'due_at_local', due_at_local,
        'is_overdue', due_at_local is not null and due_at_local < (select now_local from window_bounds),
        'is_due_today',
          due_at_local is not null
          and due_at_local >= (select now_local from window_bounds)
          and due_at_local < (select day_end from window_bounds)
      )
      order by
        (due_at_local is not null and due_at_local < (select now_local from window_bounds)) desc,
        due_at_local asc nulls last,
        cod desc nulls last,
        coalesce(order_index, 0),
        coalesce(step_code, '')
    ),
    '[]'::jsonb
  ) as items
  from top_tasks
)
select jsonb_build_object(
  'date', (select today from window_bounds),
  'timezone', 'America/Lima',
  'generated_at', timezone('America/Lima', now()),
  'assignee_id', coalesce((select id::text from assignee), p_assignee_id::text),
  'assignee_name', coalesce((select name from assignee), 'Responsable'),
  'total_pending_tasks', (select count(*) from visible_tasks),
  'overdue_tasks', (
    select count(*)
    from visible_tasks
    where due_at_local is not null
      and due_at_local < (select now_local from window_bounds)
  ),
  'due_today_tasks', (
    select count(*)
    from visible_tasks
    where due_at_local is not null
      and due_at_local >= (select now_local from window_bounds)
      and due_at_local < (select day_end from window_bounds)
  ),
  'priority_tasks', (select items from top_json)
);
$$;

revoke all on function public.ops_build_daily_order_summary(date, int) from public;
revoke all on function public.ops_build_assignee_task_summary(uuid, date, int) from public;

notify pgrst, 'reload schema';

commit;
