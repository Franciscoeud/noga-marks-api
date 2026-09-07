-- CRM/OPS: allow quotation timeline events and recover events missed after save.
begin;

-- Keep the database constraint aligned with CRM_LEAD_EVENT_TYPES in the API.
-- Recreating it is idempotent and deliberately retains a closed allow-list.
alter table public.crm_lead_events
  drop constraint if exists crm_lead_events_event_type_check;

alter table public.crm_lead_events
  add constraint crm_lead_events_event_type_check
  check (
    event_type in (
      'created',
      'updated',
      'webhook_received',
      'landing_submitted',
      'auto_reply_sent',
      'auto_reply_failed',
      'message_sent',
      'message_failed',
      'message_skipped',
      'whatsapp_inbound',
      'whatsapp_outbound',
      'replied',
      'assigned',
      'qualified',
      'converted',
      'discarded',
      'quotation_created'
    )
  );

-- The quotation header and items are persisted before the API records the CRM
-- event. Recover only missing events for complete lead quotations. This keeps
-- CDM-0681/2026 (and any other valid quotation) intact and never changes the
-- annual quotation counter.
insert into public.crm_lead_events (
  lead_id,
  event_type,
  event_source,
  payload,
  payload_json,
  created_by,
  created_at
)
select
  quotation.crm_lead_id,
  'quotation_created',
  'ops_quotations',
  jsonb_build_object(
    'quotation_id', quotation.id,
    'quotation_code',
      'CDM-' || lpad(quotation.quotation_number::text, 4, '0') || '/' || quotation.quotation_year::text,
    'total_amount', coalesce(item_totals.total_amount, 0::numeric),
    'currency', quotation.currency
  ),
  jsonb_build_object(
    'quotation_id', quotation.id,
    'quotation_code',
      'CDM-' || lpad(quotation.quotation_number::text, 4, '0') || '/' || quotation.quotation_year::text,
    'total_amount', coalesce(item_totals.total_amount, 0::numeric),
    'currency', quotation.currency
  ),
  null,
  quotation.created_at
from public.ops_quotations as quotation
cross join lateral (
  select sum(item.line_total)::numeric(14, 2) as total_amount
  from public.ops_quotation_items as item
  where item.quotation_id = quotation.id
) as item_totals
where quotation.recipient_type = 'lead'
  and quotation.crm_lead_id is not null
  and exists (
    select 1
    from public.ops_quotation_items as item
    where item.quotation_id = quotation.id
  )
  and not exists (
    select 1
    from public.crm_lead_events as event
    where event.lead_id = quotation.crm_lead_id
      and event.event_type = 'quotation_created'
      and (
        event.payload_json->>'quotation_id' = quotation.id::text
        or event.payload->>'quotation_id' = quotation.id::text
      )
  );

notify pgrst, 'reload schema';

commit;
