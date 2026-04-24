-- OPS: monthly contracts and contract-period billing
begin;

create extension if not exists "uuid-ossp";

create table if not exists public.ops_contracts (
  id uuid primary key default uuid_generate_v4(),
  client_id uuid not null references public.ops_clients(id) on delete restrict,
  name text not null,
  billing_email text,
  condicion_pago text check (condicion_pago in ('contado', '15_dias', '30_dias', '45_dias')),
  currency text not null default 'USD',
  start_date date,
  end_date date,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create unique index if not exists uq_ops_contracts_active_client
  on public.ops_contracts(client_id)
  where active = true;

create index if not exists idx_ops_contracts_client_id
  on public.ops_contracts(client_id);

create index if not exists idx_ops_contracts_active
  on public.ops_contracts(active);

create table if not exists public.ops_contract_monthly_periods (
  id uuid primary key default uuid_generate_v4(),
  contract_id uuid not null references public.ops_contracts(id) on delete cascade,
  period_month date not null,
  status text not null default 'open' check (status in ('open', 'invoiced')),
  billing_invoice_id uuid,
  closed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (contract_id, period_month)
);

create index if not exists idx_ops_contract_monthly_periods_contract_id
  on public.ops_contract_monthly_periods(contract_id);

create index if not exists idx_ops_contract_monthly_periods_status
  on public.ops_contract_monthly_periods(status);

alter table public.ops_orders
  add column if not exists contract_id uuid,
  add column if not exists contract_period_id uuid,
  add column if not exists billing_status text not null default 'pending',
  add column if not exists billing_amount numeric(12,2),
  add column if not exists billing_currency text not null default 'USD',
  add column if not exists billing_invoice_id uuid,
  add column if not exists billing_anchor_month date;

alter table public.ops_orders
  drop constraint if exists ops_orders_billing_status_check;

alter table public.ops_orders
  add constraint ops_orders_billing_status_check
  check (billing_status in ('pending', 'pending_monthly_invoice', 'staged_for_period', 'invoiced'));

create index if not exists idx_ops_orders_contract_id
  on public.ops_orders(contract_id);

create index if not exists idx_ops_orders_contract_period_id
  on public.ops_orders(contract_period_id);

create index if not exists idx_ops_orders_billing_status
  on public.ops_orders(billing_status);

create index if not exists idx_ops_orders_billing_anchor_month
  on public.ops_orders(billing_anchor_month);

create index if not exists idx_ops_orders_billing_invoice_id
  on public.ops_orders(billing_invoice_id);

alter table public.billing_invoices
  add column if not exists contract_period_id uuid,
  add column if not exists invoice_scope text not null default 'order';

alter table public.billing_invoices
  drop constraint if exists billing_invoices_invoice_scope_check;

alter table public.billing_invoices
  add constraint billing_invoices_invoice_scope_check
  check (invoice_scope in ('order', 'contract_period'));

create unique index if not exists uq_billing_invoices_contract_period_id
  on public.billing_invoices(contract_period_id)
  where contract_period_id is not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ops_orders_contract_id_fkey'
  ) then
    alter table public.ops_orders
      add constraint ops_orders_contract_id_fkey
      foreign key (contract_id) references public.ops_contracts(id) on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'ops_orders_contract_period_id_fkey'
  ) then
    alter table public.ops_orders
      add constraint ops_orders_contract_period_id_fkey
      foreign key (contract_period_id) references public.ops_contract_monthly_periods(id) on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'ops_orders_billing_invoice_id_fkey'
  ) then
    alter table public.ops_orders
      add constraint ops_orders_billing_invoice_id_fkey
      foreign key (billing_invoice_id) references public.billing_invoices(id) on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'billing_invoices_contract_period_id_fkey'
  ) then
    alter table public.billing_invoices
      add constraint billing_invoices_contract_period_id_fkey
      foreign key (contract_period_id) references public.ops_contract_monthly_periods(id) on delete set null;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'ops_contract_monthly_periods_billing_invoice_id_fkey'
  ) then
    alter table public.ops_contract_monthly_periods
      add constraint ops_contract_monthly_periods_billing_invoice_id_fkey
      foreign key (billing_invoice_id) references public.billing_invoices(id) on delete set null;
  end if;
end $$;

drop trigger if exists trg_ops_contracts_updated_at on public.ops_contracts;
create trigger trg_ops_contracts_updated_at
before update on public.ops_contracts
for each row execute procedure public.set_updated_at();

drop trigger if exists trg_ops_contract_monthly_periods_updated_at on public.ops_contract_monthly_periods;
create trigger trg_ops_contract_monthly_periods_updated_at
before update on public.ops_contract_monthly_periods
for each row execute procedure public.set_updated_at();

alter table public.ops_contracts enable row level security;
alter table public.ops_contract_monthly_periods enable row level security;

drop policy if exists "ops_contracts_auth" on public.ops_contracts;
create policy "ops_contracts_auth" on public.ops_contracts
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

drop policy if exists "ops_contract_monthly_periods_auth" on public.ops_contract_monthly_periods;
create policy "ops_contract_monthly_periods_auth" on public.ops_contract_monthly_periods
  for all
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

update public.billing_invoices
set invoice_scope = 'order'
where coalesce(invoice_scope, '') = '';

update public.ops_orders o
set billing_status = 'invoiced',
    billing_amount = bi.monto,
    billing_currency = coalesce(bi.moneda, 'USD'),
    billing_invoice_id = bi.id,
    billing_anchor_month = coalesce(
      date_trunc('month', timezone('America/Lima', o.cerrado_at))::date,
      date_trunc('month', timezone('America/Lima', bi.fecha_emision))::date
    )
from public.billing_invoices bi
where bi.order_id = o.id;

update public.ops_orders
set billing_status = coalesce(nullif(billing_status, ''), 'pending'),
    billing_currency = coalesce(nullif(billing_currency, ''), 'USD')
where billing_status is null
   or billing_currency is null
   or billing_currency = '';

create or replace function public.ops_close_order_with_invoice(
  p_order_id uuid,
  p_cliente_email text,
  p_monto numeric,
  p_condicion_pago text,
  p_garantia_dias int default 0,
  p_notas_cierre text default null
)
returns table (
  invoice_id uuid,
  order_id uuid,
  numero_factura text,
  fecha_emision timestamptz,
  fecha_vencimiento timestamptz,
  cliente text,
  cliente_email text,
  asunto_pedido text,
  monto numeric,
  moneda text,
  condicion_pago text,
  invoice_status text,
  garantia_dias int,
  cerrado_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.ops_orders%rowtype;
  v_existing_invoice public.billing_invoices%rowtype;
  v_total_tasks int;
  v_pending_tasks int;
  v_fecha_emision timestamptz := timezone('utc', now());
  v_fecha_vencimiento timestamptz;
  v_numero_factura text;
  v_payment_days int;
  v_invoice_id uuid;
  v_cliente text;
  v_billing_anchor_month date;
begin
  select *
  into v_order
  from public.ops_orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_order.contract_id is not null then
    raise exception 'El pedido pertenece a un contrato mensual';
  end if;

  if v_order.status = 'Cancelado' then
    raise exception 'No se puede cerrar un pedido cancelado';
  end if;

  if v_order.status = 'Cerrado' then
    raise exception 'El pedido ya esta cerrado';
  end if;

  select count(*)
  into v_total_tasks
  from public.ops_order_tasks task_count
  where task_count.order_id = p_order_id;

  if coalesce(v_total_tasks, 0) = 0 then
    raise exception 'El pedido no tiene tareas para cerrar';
  end if;

  select count(*)
  into v_pending_tasks
  from public.ops_order_tasks pending_task
  where pending_task.order_id = p_order_id
    and not (
      pending_task.completed_at is not null
      or coalesce(pending_task.status, 'Pendiente') = 'Completado'
    );

  if coalesce(v_pending_tasks, 0) > 0 then
    raise exception 'El checklist del pedido aun no esta completo';
  end if;

  if p_cliente_email is null or btrim(p_cliente_email) = '' then
    raise exception 'El email del cliente es obligatorio';
  end if;

  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto de la factura debe ser mayor a cero';
  end if;

  v_payment_days := case p_condicion_pago
    when 'contado' then 0
    when '15_dias' then 15
    when '30_dias' then 30
    when '45_dias' then 45
    else null
  end;

  if v_payment_days is null then
    raise exception 'La condicion de pago no es valida';
  end if;

  select *
  into v_existing_invoice
  from public.billing_invoices existing_invoice
  where existing_invoice.order_id = p_order_id
  limit 1
  for update;

  if found then
    v_invoice_id := v_existing_invoice.id;
    v_fecha_emision := coalesce(v_existing_invoice.fecha_emision, v_fecha_emision);
    v_fecha_vencimiento := coalesce(
      v_existing_invoice.fecha_emision,
      v_fecha_emision
    ) + make_interval(days => v_payment_days);

    if coalesce(v_existing_invoice.status, 'pendiente') = 'pendiente' then
      update public.billing_invoices
      set cliente = coalesce(nullif(v_existing_invoice.cliente, ''), coalesce(v_order.client_text, '')),
          cliente_email = btrim(p_cliente_email),
          monto = p_monto,
          moneda = coalesce(nullif(v_existing_invoice.moneda, ''), 'USD'),
          condicion_pago = p_condicion_pago,
          fecha_vencimiento = v_fecha_vencimiento,
          notas = nullif(btrim(coalesce(p_notas_cierre, '')), ''),
          invoice_scope = 'order'
      where id = v_existing_invoice.id;
    else
      v_fecha_vencimiento := coalesce(
        v_existing_invoice.fecha_vencimiento,
        v_fecha_emision + make_interval(days => v_payment_days)
      );
    end if;
  else
    v_fecha_vencimiento := v_fecha_emision + make_interval(days => v_payment_days);
    v_numero_factura := public.next_billing_invoice_number(extract(year from v_fecha_emision)::int);
    v_cliente := coalesce(v_order.client_text, '');

    insert into public.billing_invoices (
      order_id,
      cliente,
      cliente_email,
      numero_factura,
      monto,
      moneda,
      condicion_pago,
      fecha_emision,
      fecha_vencimiento,
      status,
      notas,
      invoice_scope
    )
    values (
      p_order_id,
      v_cliente,
      btrim(p_cliente_email),
      v_numero_factura,
      p_monto,
      'USD',
      p_condicion_pago,
      v_fecha_emision,
      v_fecha_vencimiento,
      'pendiente',
      nullif(btrim(coalesce(p_notas_cierre, '')), ''),
      'order'
    )
    returning id into v_invoice_id;
  end if;

  v_billing_anchor_month := date_trunc(
    'month',
    timezone('America/Lima', coalesce(v_order.cerrado_at, v_fecha_emision))
  )::date;

  update public.ops_orders
  set status = 'Cerrado',
      cerrado_at = coalesce(v_order.cerrado_at, v_fecha_emision),
      garantia_dias = greatest(coalesce(p_garantia_dias, 0), 0),
      notas_cierre = nullif(btrim(coalesce(p_notas_cierre, '')), ''),
      billing_status = 'invoiced',
      billing_amount = p_monto,
      billing_currency = 'USD',
      billing_invoice_id = v_invoice_id,
      billing_anchor_month = v_billing_anchor_month,
      contract_period_id = null
  where id = p_order_id;

  return query
  select
    bi.id,
    bi.order_id,
    bi.numero_factura,
    bi.fecha_emision,
    bi.fecha_vencimiento,
    bi.cliente,
    bi.cliente_email,
    coalesce(v_order.subject, ''),
    bi.monto,
    bi.moneda,
    bi.condicion_pago,
    bi.status,
    greatest(coalesce(p_garantia_dias, 0), 0),
    coalesce(v_order.cerrado_at, v_fecha_emision)
  from public.billing_invoices bi
  where bi.id = v_invoice_id;
end;
$$;

create or replace function public.ops_close_contract_order(
  p_order_id uuid,
  p_monto numeric,
  p_garantia_dias int default 0,
  p_notas_cierre text default null
)
returns table (
  order_id uuid,
  contract_id uuid,
  contract_period_id uuid,
  billing_status text,
  billing_amount numeric,
  billing_currency text,
  billing_anchor_month date,
  cerrado_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.ops_orders%rowtype;
  v_contract public.ops_contracts%rowtype;
  v_period public.ops_contract_monthly_periods%rowtype;
  v_total_tasks int;
  v_pending_tasks int;
  v_cerrado_at timestamptz := timezone('utc', now());
  v_billing_anchor_month date;
  v_billing_status text := 'pending_monthly_invoice';
  v_contract_period_id uuid;
  v_billing_currency text;
begin
  select *
  into v_order
  from public.ops_orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pedido no encontrado';
  end if;

  if v_order.contract_id is null then
    raise exception 'El pedido no pertenece a un contrato mensual';
  end if;

  select *
  into v_contract
  from public.ops_contracts
  where id = v_order.contract_id
  for update;

  if not found then
    raise exception 'Contrato no encontrado';
  end if;

  if v_order.status = 'Cancelado' then
    raise exception 'No se puede cerrar un pedido cancelado';
  end if;

  if v_order.status = 'Cerrado' then
    raise exception 'El pedido ya esta cerrado';
  end if;

  select count(*)
  into v_total_tasks
  from public.ops_order_tasks task_count
  where task_count.order_id = p_order_id;

  if coalesce(v_total_tasks, 0) = 0 then
    raise exception 'El pedido no tiene tareas para cerrar';
  end if;

  select count(*)
  into v_pending_tasks
  from public.ops_order_tasks pending_task
  where pending_task.order_id = p_order_id
    and not (
      pending_task.completed_at is not null
      or coalesce(pending_task.status, 'Pendiente') = 'Completado'
    );

  if coalesce(v_pending_tasks, 0) > 0 then
    raise exception 'El checklist del pedido aun no esta completo';
  end if;

  if p_monto is null or p_monto <= 0 then
    raise exception 'El monto facturable del pedido debe ser mayor a cero';
  end if;

  v_billing_anchor_month := date_trunc(
    'month',
    timezone('America/Lima', coalesce(v_order.cerrado_at, v_cerrado_at))
  )::date;
  v_billing_currency := coalesce(nullif(v_contract.currency, ''), 'USD');

  select *
  into v_period
  from public.ops_contract_monthly_periods existing_period
  where existing_period.contract_id = v_order.contract_id
    and existing_period.period_month = v_billing_anchor_month
  limit 1
  for update;

  if not found then
    insert into public.ops_contract_monthly_periods (
      contract_id,
      period_month,
      status
    )
    values (
      v_order.contract_id,
      v_billing_anchor_month,
      'open'
    )
    returning * into v_period;
  end if;

  if v_period.status = 'open' then
    v_billing_status := 'staged_for_period';
    v_contract_period_id := v_period.id;
  else
    v_billing_status := 'pending_monthly_invoice';
    v_contract_period_id := null;
  end if;

  update public.ops_orders
  set status = 'Cerrado',
      cerrado_at = coalesce(v_order.cerrado_at, v_cerrado_at),
      garantia_dias = greatest(coalesce(p_garantia_dias, 0), 0),
      notas_cierre = nullif(btrim(coalesce(p_notas_cierre, '')), ''),
      billing_status = v_billing_status,
      billing_amount = p_monto,
      billing_currency = v_billing_currency,
      billing_invoice_id = null,
      billing_anchor_month = v_billing_anchor_month,
      contract_period_id = v_contract_period_id
  where id = p_order_id;

  return query
  select
    p_order_id,
    v_order.contract_id,
    v_contract_period_id,
    v_billing_status,
    p_monto,
    v_billing_currency,
    v_billing_anchor_month,
    coalesce(v_order.cerrado_at, v_cerrado_at);
end;
$$;

create or replace function public.ops_close_contract_period_with_invoice(
  p_period_id uuid,
  p_cliente_email text default null,
  p_condicion_pago text default null,
  p_notas text default null
)
returns table (
  invoice_id uuid,
  contract_period_id uuid,
  contract_id uuid,
  numero_factura text,
  fecha_emision timestamptz,
  fecha_vencimiento timestamptz,
  cliente text,
  cliente_email text,
  monto numeric,
  moneda text,
  condicion_pago text,
  invoice_status text,
  period_month date,
  orders_count int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_period public.ops_contract_monthly_periods%rowtype;
  v_contract public.ops_contracts%rowtype;
  v_client public.ops_clients%rowtype;
  v_invoice_id uuid;
  v_numero_factura text;
  v_fecha_emision timestamptz := timezone('utc', now());
  v_fecha_vencimiento timestamptz;
  v_payment_days int;
  v_condicion_pago text;
  v_cliente_email text;
  v_moneda text;
  v_total_amount numeric;
  v_orders_count int;
begin
  select *
  into v_period
  from public.ops_contract_monthly_periods
  where id = p_period_id
  for update;

  if not found then
    raise exception 'Periodo de contrato no encontrado';
  end if;

  select *
  into v_contract
  from public.ops_contracts
  where id = v_period.contract_id
  for update;

  if not found then
    raise exception 'Contrato no encontrado';
  end if;

  select *
  into v_client
  from public.ops_clients
  where id = v_contract.client_id;

  if v_period.status = 'invoiced' then
    raise exception 'El periodo ya fue facturado';
  end if;

  v_cliente_email := nullif(btrim(coalesce(p_cliente_email, v_contract.billing_email, '')), '');
  if v_cliente_email is null then
    raise exception 'El email de facturacion es obligatorio';
  end if;

  v_condicion_pago := coalesce(nullif(btrim(coalesce(p_condicion_pago, '')), ''), v_contract.condicion_pago);
  v_payment_days := case v_condicion_pago
    when 'contado' then 0
    when '15_dias' then 15
    when '30_dias' then 30
    when '45_dias' then 45
    else null
  end;

  if v_payment_days is null then
    raise exception 'La condicion de pago no es valida';
  end if;

  perform 1
  from public.ops_orders staged_order
  where staged_order.contract_period_id = p_period_id
    and staged_order.billing_status = 'staged_for_period'
  for update;

  select
    count(*),
    coalesce(sum(staged_order.billing_amount), 0)
  into v_orders_count, v_total_amount
  from public.ops_orders staged_order
  where staged_order.contract_period_id = p_period_id
    and staged_order.billing_status = 'staged_for_period';

  if coalesce(v_orders_count, 0) = 0 then
    raise exception 'El periodo no tiene pedidos incluidos para facturar';
  end if;

  if coalesce(v_total_amount, 0) <= 0 then
    raise exception 'El total facturable del periodo debe ser mayor a cero';
  end if;

  v_fecha_vencimiento := v_fecha_emision + make_interval(days => v_payment_days);
  v_numero_factura := public.next_billing_invoice_number(extract(year from v_fecha_emision)::int);
  v_moneda := coalesce(nullif(v_contract.currency, ''), 'USD');

  insert into public.billing_invoices (
    order_id,
    contract_period_id,
    cliente,
    cliente_email,
    numero_factura,
    monto,
    moneda,
    condicion_pago,
    fecha_emision,
    fecha_vencimiento,
    status,
    notas,
    invoice_scope
  )
  values (
    null,
    p_period_id,
    coalesce(nullif(v_client.name, ''), v_contract.name),
    v_cliente_email,
    v_numero_factura,
    v_total_amount,
    v_moneda,
    v_condicion_pago,
    v_fecha_emision,
    v_fecha_vencimiento,
    'pendiente',
    nullif(btrim(coalesce(p_notas, '')), ''),
    'contract_period'
  )
  returning id into v_invoice_id;

  update public.ops_orders
  set billing_status = 'invoiced',
      billing_invoice_id = v_invoice_id,
      billing_currency = v_moneda
  where contract_period_id = p_period_id
    and billing_status = 'staged_for_period';

  update public.ops_contract_monthly_periods
  set status = 'invoiced',
      billing_invoice_id = v_invoice_id,
      closed_at = v_fecha_emision
  where id = p_period_id;

  return query
  select
    v_invoice_id,
    p_period_id,
    v_period.contract_id,
    v_numero_factura,
    v_fecha_emision,
    v_fecha_vencimiento,
    coalesce(nullif(v_client.name, ''), v_contract.name),
    v_cliente_email,
    v_total_amount,
    v_moneda,
    v_condicion_pago,
    'pendiente',
    v_period.period_month,
    v_orders_count;
end;
$$;

grant execute on function public.ops_close_order_with_invoice(uuid, text, numeric, text, int, text) to authenticated;
grant execute on function public.ops_close_contract_order(uuid, numeric, int, text) to authenticated;
grant execute on function public.ops_close_contract_period_with_invoice(uuid, text, text, text) to authenticated;

notify pgrst, 'reload schema';

commit;
