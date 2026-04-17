-- OPS: make close-order invoice issuance idempotent when an invoice already exists
begin;

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
begin
  select *
  into v_order
  from public.ops_orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Pedido no encontrado';
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
          condicion_pago = p_condicion_pago,
          fecha_vencimiento = v_fecha_vencimiento,
          notas = nullif(btrim(coalesce(p_notas_cierre, '')), '')
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
      notas
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
      nullif(btrim(coalesce(p_notas_cierre, '')), '')
    )
    returning id into v_invoice_id;
  end if;

  update public.ops_orders
  set status = 'Cerrado',
      cerrado_at = coalesce(v_order.cerrado_at, v_fecha_emision),
      garantia_dias = greatest(coalesce(p_garantia_dias, 0), 0),
      notas_cierre = nullif(btrim(coalesce(p_notas_cierre, '')), '')
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

grant execute on function public.ops_close_order_with_invoice(uuid, text, numeric, text, int, text) to authenticated;

notify pgrst, 'reload schema';

commit;
