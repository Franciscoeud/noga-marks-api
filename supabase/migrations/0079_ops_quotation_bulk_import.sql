-- OPS: transactional bulk import for quotations
begin;

create or replace function public.ops_bulk_import_quotations(
  p_quotations jsonb,
  p_created_by uuid default auth.uid(),
  p_created_by_email text default null
)
returns table (
  id uuid,
  quotation_year integer,
  quotation_number integer
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  q jsonb;
  item_row jsonb;
  lead_payload jsonb;
  v_quote_id uuid;
  v_lead_id uuid;
  v_year integer;
  v_number integer;
  v_recipient_type text;
  v_items jsonb;
  v_total numeric(14, 2);
  v_created_leads jsonb := '{}'::jsonb;
  v_lead_key text;
begin
  if p_quotations is null or jsonb_typeof(p_quotations) <> 'array' then
    raise exception 'p_quotations debe ser un arreglo JSON';
  end if;

  for q in
    select value from jsonb_array_elements(p_quotations)
  loop
    v_year := (q->>'quotation_year')::integer;
    v_number := (q->>'quotation_number')::integer;
    v_recipient_type := q->>'recipient_type';
    v_items := coalesce(q->'items', '[]'::jsonb);
    v_lead_id := null;

    if v_year is null or v_year < 2000 then
      raise exception 'Anio de cotizacion invalido: %', q->>'quotation_year';
    end if;
    if v_number is null or v_number <= 0 then
      raise exception 'Numero de cotizacion invalido: %', q->>'quotation_number';
    end if;
    if jsonb_array_length(v_items) = 0 then
      raise exception 'La cotizacion CDM-%/% no tiene items', lpad(v_number::text, 4, '0'), v_year;
    end if;

    if nullif(q->>'crm_lead_id', '') is not null then
      v_lead_id := (q->>'crm_lead_id')::uuid;
    end if;

    if v_recipient_type = 'lead' and v_lead_id is null then
      v_lead_key := nullif(q->>'lead_import_key', '');
      if v_lead_key is not null and v_created_leads ? v_lead_key then
        v_lead_id := (v_created_leads->>v_lead_key)::uuid;
      end if;
    end if;

    if v_recipient_type = 'lead' and v_lead_id is null then
      lead_payload := q->'lead_payload';
      if lead_payload is null or jsonb_typeof(lead_payload) <> 'object' then
        raise exception 'La cotizacion CDM-%/% requiere lead_payload', lpad(v_number::text, 4, '0'), v_year;
      end if;

      insert into public.crm_leads (
        full_name,
        first_name,
        last_name,
        phone,
        phone_normalized,
        whatsapp_number,
        email,
        company_name,
        source_channel,
        source_platform,
        source_detail,
        product_interest_raw,
        requested_info_type,
        message_context,
        inbound_message,
        language,
        lead_status,
        status,
        pipeline_stage,
        temperature,
        priority_score,
        intent_score,
        consent_whatsapp,
        whatsapp_opt_in,
        consent_email,
        consent_sms,
        raw_payload,
        owner_user_id,
        assigned_user_id,
        assigned_user_label,
        created_at,
        updated_at
      )
      values (
        nullif(lead_payload->>'full_name', ''),
        nullif(lead_payload->>'first_name', ''),
        nullif(lead_payload->>'last_name', ''),
        nullif(lead_payload->>'phone', ''),
        nullif(lead_payload->>'phone_normalized', ''),
        nullif(lead_payload->>'whatsapp_number', ''),
        nullif(lead_payload->>'email', ''),
        nullif(lead_payload->>'company_name', ''),
        coalesce(nullif(lead_payload->>'source_channel', ''), 'ops_quotation'),
        coalesce(nullif(lead_payload->>'source_platform', ''), 'ops'),
        coalesce(nullif(lead_payload->>'source_detail', ''), 'OPS Cotizaciones'),
        nullif(lead_payload->>'product_interest_raw', ''),
        coalesce(nullif(lead_payload->>'requested_info_type', ''), 'cotizacion'),
        nullif(lead_payload->>'message_context', ''),
        nullif(lead_payload->>'inbound_message', ''),
        coalesce(nullif(lead_payload->>'language', ''), 'es'),
        coalesce(nullif(lead_payload->>'lead_status', ''), 'qualified'),
        coalesce(nullif(lead_payload->>'status', ''), 'calificado'),
        coalesce(nullif(lead_payload->>'pipeline_stage', ''), 'Cotizado'),
        coalesce(nullif(lead_payload->>'temperature', ''), 'frio'),
        coalesce(nullif(lead_payload->>'priority_score', ''), '0')::integer,
        coalesce(nullif(lead_payload->>'intent_score', ''), '0')::integer,
        coalesce((lead_payload->>'consent_whatsapp')::boolean, false),
        coalesce((lead_payload->>'whatsapp_opt_in')::boolean, false),
        coalesce((lead_payload->>'consent_email')::boolean, false),
        coalesce((lead_payload->>'consent_sms')::boolean, false),
        coalesce(lead_payload->'raw_payload', '{}'::jsonb),
        nullif(lead_payload->>'owner_user_id', '')::uuid,
        nullif(lead_payload->>'assigned_user_id', '')::uuid,
        coalesce(nullif(lead_payload->>'assigned_user_label', ''), p_created_by_email),
        timezone('utc', now()),
        timezone('utc', now())
      )
      returning public.crm_leads.id into v_lead_id;

      insert into public.crm_lead_events (
        lead_id,
        event_type,
        event_source,
        payload,
        payload_json,
        created_by,
        created_at
      )
      values (
        v_lead_id,
        'created',
        'ops_quotations',
        jsonb_build_object(
          'event_type', 'ops_quotation_bulk_import_lead',
          'created_by_email', p_created_by_email
        ),
        jsonb_build_object(
          'event_type', 'ops_quotation_bulk_import_lead',
          'created_by_email', p_created_by_email
        ),
        p_created_by,
        timezone('utc', now())
      );

      if v_lead_key is not null then
        v_created_leads := v_created_leads || jsonb_build_object(v_lead_key, v_lead_id::text);
      end if;
    end if;

    insert into public.ops_quotations (
      quotation_year,
      quotation_number,
      quotation_date,
      recipient_type,
      client_id,
      crm_lead_id,
      client_name,
      recipient_name_snapshot,
      recipient_doc_snapshot,
      recipient_email_snapshot,
      recipient_phone_snapshot,
      currency,
      terms_validity,
      terms_payment,
      terms_taxes,
      terms_delivery,
      signed_by_name,
      signed_by_title,
      status,
      created_at,
      updated_at
    )
    values (
      v_year,
      v_number,
      (q->>'quotation_date')::date,
      v_recipient_type,
      nullif(q->>'client_id', '')::uuid,
      v_lead_id,
      nullif(q->>'client_name', ''),
      nullif(q->>'recipient_name_snapshot', ''),
      nullif(q->>'recipient_doc_snapshot', ''),
      nullif(q->>'recipient_email_snapshot', ''),
      nullif(q->>'recipient_phone_snapshot', ''),
      coalesce(nullif(q->>'currency', ''), 'PEN'),
      nullif(q->>'terms_validity', ''),
      nullif(q->>'terms_payment', ''),
      nullif(q->>'terms_taxes', ''),
      nullif(q->>'terms_delivery', ''),
      coalesce(nullif(q->>'signed_by_name', ''), 'Luis E. Revoredo Johnson'),
      coalesce(nullif(q->>'signed_by_title', ''), 'Gerente de Ventas'),
      coalesce(nullif(q->>'status', ''), 'issued'),
      timezone('utc', now()),
      timezone('utc', now())
    )
    returning public.ops_quotations.id into v_quote_id;

    for item_row in
      select value from jsonb_array_elements(v_items)
    loop
      insert into public.ops_quotation_items (
        quotation_id,
        position,
        code,
        description,
        quantity,
        unit_price,
        created_at,
        updated_at
      )
      values (
        v_quote_id,
        (item_row->>'position')::integer,
        nullif(item_row->>'code', ''),
        nullif(item_row->>'description', ''),
        (item_row->>'quantity')::numeric,
        (item_row->>'unit_price')::numeric,
        timezone('utc', now()),
        timezone('utc', now())
      );
    end loop;

    if v_recipient_type = 'lead' and v_lead_id is not null then
      select coalesce(sum((value->>'quantity')::numeric * (value->>'unit_price')::numeric), 0)::numeric(14, 2)
        into v_total
      from jsonb_array_elements(v_items) as item_value(value);

      insert into public.crm_lead_events (
        lead_id,
        event_type,
        event_source,
        payload,
        payload_json,
        created_by,
        created_at
      )
      values (
        v_lead_id,
        'quotation_created',
        'ops_quotations',
        jsonb_build_object(
          'quotation_id', v_quote_id,
          'quotation_code', 'CDM-' || lpad(v_number::text, 4, '0') || '/' || v_year::text,
          'total_amount', v_total,
          'currency', coalesce(nullif(q->>'currency', ''), 'PEN')
        ),
        jsonb_build_object(
          'quotation_id', v_quote_id,
          'quotation_code', 'CDM-' || lpad(v_number::text, 4, '0') || '/' || v_year::text,
          'total_amount', v_total,
          'currency', coalesce(nullif(q->>'currency', ''), 'PEN')
        ),
        p_created_by,
        timezone('utc', now())
      );
    end if;

    insert into public.ops_quotation_year_counters (quotation_year, next_number)
    values (v_year, v_number + 1)
    on conflict (quotation_year) do update set
      next_number = greatest(public.ops_quotation_year_counters.next_number, excluded.next_number),
      updated_at = timezone('utc', now());

    id := v_quote_id;
    quotation_year := v_year;
    quotation_number := v_number;
    return next;
  end loop;
end;
$$;

grant execute on function public.ops_bulk_import_quotations(jsonb, uuid, text) to authenticated;

notify pgrst, 'reload schema';

commit;
