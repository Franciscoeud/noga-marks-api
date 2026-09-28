-- Sales CRM: internal follow-up alerts and currency-safe reporting primitives.
begin;

create table if not exists public.crm_alert_settings (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  inactivity_days integer not null default 7,
  active boolean not null default true,
  updated_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint uq_crm_alert_settings_unit unique (business_unit_id),
  constraint crm_alert_settings_inactivity_check check (inactivity_days between 1 and 365)
);

insert into public.crm_alert_settings (business_unit_id, inactivity_days)
select id, 7 from public.crm_business_units
on conflict (business_unit_id) do nothing;

create table if not exists public.crm_opportunity_alerts (
  id uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.crm_business_units(id) on delete cascade,
  opportunity_id uuid not null references public.crm_opportunities(id) on delete cascade,
  alert_type text not null,
  owner_user_id uuid,
  due_at timestamptz,
  severity text not null default 'warning',
  message text not null,
  metadata jsonb not null default '{}'::jsonb,
  generated_at timestamptz not null default timezone('utc', now()),
  resolved_at timestamptz,
  resolved_by uuid,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint crm_opportunity_alerts_type_check check (
    alert_type in (
      'follow_up_overdue', 'missing_next_action', 'reactivation_overdue',
      'estimated_close_overdue', 'inactive_opportunity'
    )
  ),
  constraint crm_opportunity_alerts_severity_check
    check (severity in ('info', 'warning', 'critical')),
  constraint crm_opportunity_alerts_message_check
    check (nullif(btrim(message), '') is not null)
);

create unique index if not exists uq_crm_opportunity_active_alert
  on public.crm_opportunity_alerts (opportunity_id, alert_type)
  where resolved_at is null;
create index if not exists idx_crm_opportunity_alerts_queue
  on public.crm_opportunity_alerts (business_unit_id, resolved_at, due_at, alert_type);
create index if not exists idx_crm_opportunity_alerts_owner
  on public.crm_opportunity_alerts (business_unit_id, owner_user_id, resolved_at, due_at);

alter table public.crm_campaigns
  add column if not exists cost_amount numeric(14,2),
  add column if not exists cost_currency text,
  add column if not exists attribution_model text not null default 'primary';

alter table public.crm_campaigns
  drop constraint if exists crm_campaigns_cost_check;
alter table public.crm_campaigns
  add constraint crm_campaigns_cost_check check (
    (cost_amount is null or cost_amount >= 0)
    and (cost_currency is null or cost_currency ~ '^[A-Z]{3}$')
    and attribution_model in ('primary')
  );

create or replace function public.crm_refresh_opportunity_alerts(p_business_unit_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_generation text := gen_random_uuid()::text;
  v_inactivity_days integer;
  v_count integer;
  v_last_activity timestamptz;
  opportunity record;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and not public.crm_has_business_unit_access(p_business_unit_id) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;

  select coalesce(setting.inactivity_days, 7)
  into v_inactivity_days
  from public.crm_alert_settings setting
  where setting.business_unit_id = p_business_unit_id
    and setting.active
  limit 1;
  v_inactivity_days := coalesce(v_inactivity_days, 7);

  for opportunity in
    select item.*
    from public.crm_opportunities item
    where item.business_unit_id = p_business_unit_id
      and item.commercial_status in ('open', 'paused')
  loop
    if opportunity.commercial_status = 'open'
       and (nullif(btrim(opportunity.next_action), '') is null or opportunity.next_action_at is null) then
      insert into public.crm_opportunity_alerts (
        business_unit_id, opportunity_id, alert_type, owner_user_id,
        due_at, severity, message, metadata, generated_at
      ) values (
        p_business_unit_id, opportunity.id, 'missing_next_action', opportunity.owner_user_id,
        timezone('utc', now()), 'warning', 'La oportunidad no tiene una próxima acción completa.',
        jsonb_build_object('generation', v_generation), timezone('utc', now())
      )
      on conflict (opportunity_id, alert_type) where resolved_at is null do update
      set owner_user_id = excluded.owner_user_id, due_at = excluded.due_at,
          severity = excluded.severity, message = excluded.message,
          metadata = excluded.metadata, generated_at = excluded.generated_at,
          updated_at = timezone('utc', now());
    end if;

    if opportunity.commercial_status = 'open'
       and opportunity.next_action_at is not null
       and opportunity.next_action_at < timezone('utc', now()) then
      insert into public.crm_opportunity_alerts (
        business_unit_id, opportunity_id, alert_type, owner_user_id,
        due_at, severity, message, metadata, generated_at
      ) values (
        p_business_unit_id, opportunity.id, 'follow_up_overdue', opportunity.owner_user_id,
        opportunity.next_action_at, 'critical', 'El seguimiento comercial está vencido.',
        jsonb_build_object('generation', v_generation, 'next_action', opportunity.next_action), timezone('utc', now())
      )
      on conflict (opportunity_id, alert_type) where resolved_at is null do update
      set owner_user_id = excluded.owner_user_id, due_at = excluded.due_at,
          severity = excluded.severity, message = excluded.message,
          metadata = excluded.metadata, generated_at = excluded.generated_at,
          updated_at = timezone('utc', now());
    end if;

    if opportunity.commercial_status = 'paused'
       and opportunity.reactivation_at is not null
       and opportunity.reactivation_at < timezone('utc', now()) then
      insert into public.crm_opportunity_alerts (
        business_unit_id, opportunity_id, alert_type, owner_user_id,
        due_at, severity, message, metadata, generated_at
      ) values (
        p_business_unit_id, opportunity.id, 'reactivation_overdue', opportunity.owner_user_id,
        opportunity.reactivation_at, 'critical', 'La fecha de reactivación de la oportunidad ya venció.',
        jsonb_build_object('generation', v_generation), timezone('utc', now())
      )
      on conflict (opportunity_id, alert_type) where resolved_at is null do update
      set owner_user_id = excluded.owner_user_id, due_at = excluded.due_at,
          severity = excluded.severity, message = excluded.message,
          metadata = excluded.metadata, generated_at = excluded.generated_at,
          updated_at = timezone('utc', now());
    end if;

    if opportunity.commercial_status = 'open'
       and opportunity.estimated_close_date is not null
       and opportunity.estimated_close_date < current_date then
      insert into public.crm_opportunity_alerts (
        business_unit_id, opportunity_id, alert_type, owner_user_id,
        due_at, severity, message, metadata, generated_at
      ) values (
        p_business_unit_id, opportunity.id, 'estimated_close_overdue', opportunity.owner_user_id,
        opportunity.estimated_close_date::timestamptz, 'warning', 'La fecha estimada de cierre ya venció.',
        jsonb_build_object('generation', v_generation), timezone('utc', now())
      )
      on conflict (opportunity_id, alert_type) where resolved_at is null do update
      set owner_user_id = excluded.owner_user_id, due_at = excluded.due_at,
          severity = excluded.severity, message = excluded.message,
          metadata = excluded.metadata, generated_at = excluded.generated_at,
          updated_at = timezone('utc', now());
    end if;

    select greatest(
      coalesce(max(coalesce(activity.occurred_at, activity.created_at)), '-infinity'::timestamptz),
      coalesce(opportunity.last_effective_contact_at, '-infinity'::timestamptz),
      coalesce(opportunity.last_customer_response_at, '-infinity'::timestamptz),
      coalesce(opportunity.business_created_at::timestamptz, opportunity.created_at)
    )
    into v_last_activity
    from public.crm_activities activity
    where activity.opportunity_id = opportunity.id;

    if v_last_activity is not null
       and v_last_activity + make_interval(days => v_inactivity_days) < timezone('utc', now()) then
      insert into public.crm_opportunity_alerts (
        business_unit_id, opportunity_id, alert_type, owner_user_id,
        due_at, severity, message, metadata, generated_at
      ) values (
        p_business_unit_id, opportunity.id, 'inactive_opportunity', opportunity.owner_user_id,
        v_last_activity + make_interval(days => v_inactivity_days), 'warning',
        'La oportunidad superó el umbral de inactividad configurado.',
        jsonb_build_object(
          'generation', v_generation,
          'last_activity_at', v_last_activity,
          'threshold_days', v_inactivity_days
        ),
        timezone('utc', now())
      )
      on conflict (opportunity_id, alert_type) where resolved_at is null do update
      set owner_user_id = excluded.owner_user_id, due_at = excluded.due_at,
          severity = excluded.severity, message = excluded.message,
          metadata = excluded.metadata, generated_at = excluded.generated_at,
          updated_at = timezone('utc', now());
    end if;
  end loop;

  update public.crm_opportunity_alerts alert
  set resolved_at = timezone('utc', now()),
      resolved_by = null,
      updated_at = timezone('utc', now()),
      metadata = alert.metadata || jsonb_build_object('auto_resolved', true)
  where alert.business_unit_id = p_business_unit_id
    and alert.resolved_at is null
    and alert.metadata->>'generation' is distinct from v_generation;

  select count(*) into v_count
  from public.crm_opportunity_alerts alert
  where alert.business_unit_id = p_business_unit_id
    and alert.resolved_at is null;
  return v_count;
end;
$$;

-- A compact SQL reporting primitive is useful for audits and exports. The API
-- enriches it with drill-downs, but this function enforces the same key rules:
-- unique opportunities, close-date cohorts, confirmed net pipeline and no
-- arithmetic across currencies.
create or replace function public.crm_commercial_reporting_snapshot(
  p_business_unit_id uuid,
  p_date_from date default null,
  p_date_to date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
stable
as $$
declare
  v_result jsonb;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role'
     and not public.crm_has_business_unit_access(p_business_unit_id) then
    raise exception 'Business unit access denied' using errcode = '42501';
  end if;

  with status_counts as (
    select commercial_status, count(*)::integer as count
    from public.crm_opportunities
    where business_unit_id = p_business_unit_id
    group by commercial_status
  ), currency_metrics as (
    select
      coalesce(
        case when commercial_status = 'won' then accepted_currency else current_currency end,
        'UNKNOWN'
      ) as currency,
      coalesce(sum(current_proposed_net_amount) filter (
        where commercial_status = 'open' and tax_basis_status = 'confirmed_net'
      ), 0)::numeric(14,2) as pipeline_open,
      coalesce(sum(current_proposed_net_amount) filter (
        where commercial_status = 'paused' and tax_basis_status = 'confirmed_net'
      ), 0)::numeric(14,2) as pipeline_paused,
      coalesce(sum(current_proposed_net_amount) filter (
        where commercial_status = 'verification' and tax_basis_status = 'confirmed_net'
      ), 0)::numeric(14,2) as pending_verification,
      coalesce(sum(accepted_net_amount) filter (
        where commercial_status = 'won'
          and closed_at::date >= coalesce(p_date_from, '-infinity'::date)
          and closed_at::date <= coalesce(p_date_to, 'infinity'::date)
      ), 0)::numeric(14,2) as won_amount,
      count(*) filter (
        where commercial_status = 'won'
          and closed_at::date >= coalesce(p_date_from, '-infinity'::date)
          and closed_at::date <= coalesce(p_date_to, 'infinity'::date)
      )::integer as won_count,
      count(*) filter (
        where commercial_status = 'lost'
          and closed_at::date >= coalesce(p_date_from, '-infinity'::date)
          and closed_at::date <= coalesce(p_date_to, 'infinity'::date)
      )::integer as lost_count
    from public.crm_opportunities
    where business_unit_id = p_business_unit_id
    group by coalesce(
      case when commercial_status = 'won' then accepted_currency else current_currency end,
      'UNKNOWN'
    )
  ), serialized_currency as (
    select jsonb_agg(
      jsonb_build_object(
        'currency', currency,
        'pipeline_open', pipeline_open,
        'pipeline_paused', pipeline_paused,
        'pending_verification', pending_verification,
        'won_amount', won_amount,
        'won_count', won_count,
        'lost_count', lost_count,
        'close_rate', case
          when won_count + lost_count = 0 then null
          else round(won_count::numeric * 100 / (won_count + lost_count), 2)
        end
      ) order by currency
    ) as value
    from currency_metrics
  )
  select jsonb_build_object(
    'counts_by_status', coalesce((
      select jsonb_object_agg(commercial_status, count) from status_counts
    ), '{}'::jsonb),
    'by_currency', coalesce((select value from serialized_currency), '[]'::jsonb),
    'period', jsonb_build_object('date_from', p_date_from, 'date_to', p_date_to),
    'generated_at', timezone('utc', now())
  ) into v_result;
  return v_result;
end;
$$;

-- Apply a complete lifecycle command in one database transaction. The API
-- performs friendly validation first; this function is the final concurrency,
-- tenant and atomicity boundary for status, outcome, accepted items, remainder
-- and quotation-delivery evidence.
create or replace function public.crm_apply_opportunity_transition(
  p_business_unit_id uuid,
  p_opportunity_id uuid,
  p_expected_version integer,
  p_action text,
  p_update jsonb,
  p_outcome jsonb default null,
  p_accepted_items jsonb default '[]'::jsonb,
  p_remainder jsonb default null,
  p_quotation_delivery jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_before public.crm_opportunities%rowtype;
  v_after public.crm_opportunities%rowtype;
  v_outcome public.crm_opportunity_outcomes%rowtype;
  v_child public.crm_opportunities%rowtype;
  v_item jsonb;
  v_unknown_key text;
  v_allowed_update_keys text[];
  v_items_total numeric(14,2);
  v_proposed_reference numeric(14,2);
  v_quoted_quantity numeric(12,2);
begin
  if p_action not in (
    'open', 'set_stage', 'change_stage', 'quotation_sent', 'pause',
    'reactivate', 'win', 'lose', 'reopen', 'correct'
  ) then
    raise exception 'Unsupported opportunity transition' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_update, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_accepted_items, '[]'::jsonb)) <> 'array'
     or (p_outcome is not null and jsonb_typeof(p_outcome) <> 'object')
     or (p_remainder is not null and jsonb_typeof(p_remainder) <> 'object')
     or (p_quotation_delivery is not null and jsonb_typeof(p_quotation_delivery) <> 'object') then
    raise exception 'Invalid transition payload' using errcode = '22023';
  end if;
  if not public.crm_can_edit_opportunity_child(p_business_unit_id, p_opportunity_id) then
    raise exception 'Opportunity access denied' using errcode = '42501';
  end if;

  -- Consumed by the opportunity guard trigger.  It is transaction-local and
  -- cannot be supplied through a PostgREST table update.
  perform set_config('app.crm_lifecycle_transition', 'true', true);

  select * into v_before
  from public.crm_opportunities opportunity
  where opportunity.id = p_opportunity_id
    and opportunity.business_unit_id = p_business_unit_id
  for update;
  if not found then
    raise exception 'Opportunity not found' using errcode = 'P0002';
  end if;
  if p_expected_version is not null and v_before.version <> p_expected_version then
    raise exception 'Opportunity was modified by another user' using errcode = '40001';
  end if;

  v_proposed_reference := case
    when v_before.tax_basis_status = 'confirmed_net'
      then v_before.current_proposed_net_amount
    else null
  end;
  if v_proposed_reference is null
     and v_before.current_proposed_net_amount is null then
    select sum(item.line_total)
    into v_proposed_reference
    from public.crm_opportunity_quotations link
    join public.ops_quotations quotation
      on quotation.id = link.quotation_id
    join public.ops_quotation_items item
      on item.quotation_id = link.quotation_id
    where link.business_unit_id = p_business_unit_id
      and link.opportunity_id = p_opportunity_id
      and link.is_current
      and (
        v_before.tax_basis_status = 'confirmed_net'
        or (
          v_before.tax_basis_status = 'unknown'
          and coalesce(quotation.terms_taxes, '')
            ~* 'no[[:space:]]+incluy(e|en)[[:space:]]+(el[[:space:]]+)?igv'
        )
      );
  end if;

  -- Authenticated clients can call this RPC directly, so bind each command to
  -- its permitted source/target states and append-only outcome here as well as
  -- in the API.
  if p_action = 'open' then
    if v_before.commercial_status <> 'verification'
       or (p_update->>'commercial_status') is distinct from 'open'
       or p_outcome is not null then
      raise exception 'Only a verification opportunity can be opened' using errcode = '23514';
    end if;
    v_allowed_update_keys := array[
      'commercial_status','stage','owner_user_id','next_action','next_action_at',
      'closed_at','updated_at','updated_by'
    ];
  elsif p_action in ('set_stage', 'change_stage') then
    if v_before.commercial_status <> 'open'
       or not (p_update ? 'stage')
       or (p_update->>'stage') = 'proposal'
       or p_update ? 'commercial_status'
       or p_outcome is not null then
      raise exception 'Invalid stage transition' using errcode = '23514';
    end if;
    v_allowed_update_keys := array['stage','updated_at','updated_by'];
  elsif p_action = 'quotation_sent' then
    if v_before.commercial_status <> 'open'
       or (p_update->>'stage') is distinct from 'proposal'
       or p_quotation_delivery is null
       or p_outcome is not null then
      raise exception 'Invalid quotation delivery transition' using errcode = '23514';
    end if;
    v_allowed_update_keys := array['stage','updated_at','updated_by'];
  elsif p_action = 'pause' then
    if v_before.commercial_status <> 'open'
       or (p_update->>'commercial_status') is distinct from 'paused'
       or p_outcome is not null then
      raise exception 'Invalid pause transition' using errcode = '23514';
    end if;
    v_allowed_update_keys := array[
      'commercial_status','owner_user_id','paused_stage','pause_reason_id',
      'pause_reason_snapshot','pause_comment','reactivation_at','updated_at','updated_by'
    ];
  elsif p_action = 'reactivate' then
    if v_before.commercial_status <> 'paused'
       or (p_update->>'commercial_status') is distinct from 'open'
       or p_outcome is not null then
      raise exception 'Invalid reactivation transition' using errcode = '23514';
    end if;
    v_allowed_update_keys := array[
      'commercial_status','stage','owner_user_id','next_action','next_action_at',
      'pause_reason_id','pause_reason_snapshot','pause_comment','reactivation_at',
      'updated_at','updated_by'
    ];
  elsif p_action = 'win' then
    if v_before.commercial_status not in ('verification', 'open', 'paused')
       or (p_update->>'commercial_status') is distinct from 'won'
       or (p_outcome->>'status') is distinct from 'won' then
      raise exception 'Invalid won transition' using errcode = '23514';
    end if;
    v_allowed_update_keys := array[
      'commercial_status','closed_at','accepted_net_amount','accepted_currency',
      'win_reason_id','acceptance_evidence_type','evidence_document_id',
      'acceptance_evidence_reference','close_reason_snapshot','closure_comment',
      'next_action','next_action_at','updated_at','updated_by'
    ];
  elsif p_action = 'lose' then
    if v_before.commercial_status not in ('verification', 'open', 'paused')
       or (p_update->>'commercial_status') is distinct from 'lost'
       or (p_outcome->>'status') is distinct from 'lost' then
      raise exception 'Invalid lost transition' using errcode = '23514';
    end if;
    v_allowed_update_keys := array[
      'commercial_status','closed_at','loss_reason_id','close_reason_snapshot',
      'closure_comment','competitor_name','next_action','next_action_at',
      'updated_at','updated_by'
    ];
  elsif p_action = 'reopen' then
    if v_before.commercial_status not in ('won', 'lost')
       or (p_update->>'commercial_status') is distinct from 'open'
       or (p_outcome->>'status') is distinct from 'reopened' then
      raise exception 'Invalid reopen transition' using errcode = '23514';
    end if;
    v_allowed_update_keys := array[
      'commercial_status','stage','owner_user_id','next_action','next_action_at',
      'closed_at','accepted_net_amount','accepted_currency','win_reason_id',
      'loss_reason_id','close_reason_snapshot','closure_comment','competitor_name',
      'acceptance_evidence_type','acceptance_evidence_reference',
      'evidence_document_id','updated_at','updated_by'
    ];
  elsif p_action = 'correct' then
    if v_before.commercial_status not in ('won', 'lost')
       or p_update ? 'commercial_status'
       or (p_outcome->>'status') is distinct from (v_before.commercial_status || '_correction') then
      raise exception 'Invalid close correction' using errcode = '23514';
    end if;
    v_allowed_update_keys := array[
      'closed_at','accepted_net_amount','accepted_currency','win_reason_id',
      'loss_reason_id','acceptance_evidence_type','evidence_document_id',
      'acceptance_evidence_reference','close_reason_snapshot','closure_comment',
      'competitor_name','updated_at','updated_by'
    ];
  end if;

  if p_action <> 'win'
     and (p_remainder is not null or jsonb_array_length(coalesce(p_accepted_items, '[]'::jsonb)) > 0) then
    raise exception 'Only a won transition can contain accepted items or a remainder' using errcode = '23514';
  end if;
  if p_action <> 'quotation_sent' and p_quotation_delivery is not null then
    raise exception 'Quotation delivery is only valid for quotation_sent' using errcode = '23514';
  end if;

  select key into v_unknown_key
  from jsonb_object_keys(coalesce(p_update, '{}'::jsonb)) key
  where not (key = any(v_allowed_update_keys))
  limit 1;
  if v_unknown_key is not null then
    raise exception 'Unsupported opportunity field: %', v_unknown_key using errcode = '22023';
  end if;

  if p_outcome is not null then
    select key into v_unknown_key
    from jsonb_object_keys(p_outcome) key
    where not (key = any(array[
      'status','closed_at','reason_id','reason_snapshot','comment',
      'competitor_name','accepted_net_amount','currency','evidence_document_id',
      'evidence_type','evidence_reference','is_partial','remainder_disposition',
      'created_by'
    ]::text[]))
    limit 1;
    if v_unknown_key is not null then
      raise exception 'Unsupported outcome field: %', v_unknown_key using errcode = '22023';
    end if;
  end if;

  if p_remainder is not null then
    select key into v_unknown_key
    from jsonb_object_keys(p_remainder) key
    where not (key = any(array[
      'name','commercial_status','stage','owner_user_id','next_action',
      'next_action_at','amount','currency','pause_reason_id','reactivation_at'
    ]::text[]))
    limit 1;
    if v_unknown_key is not null then
      raise exception 'Unsupported remainder field: %', v_unknown_key using errcode = '22023';
    end if;
  end if;

  if p_quotation_delivery is not null then
    select key into v_unknown_key
    from jsonb_object_keys(p_quotation_delivery) key
    where not (key = any(array['quotation_id','sent_at','sent_channel']::text[]))
    limit 1;
    if v_unknown_key is not null then
      raise exception 'Unsupported quotation-delivery field: %', v_unknown_key using errcode = '22023';
    end if;
  end if;

  if p_action = 'win' then
    if coalesce((p_outcome->>'is_partial')::boolean, false) then
      if jsonb_array_length(coalesce(p_accepted_items, '[]'::jsonb)) = 0 then
        raise exception 'A partial acceptance requires accepted items' using errcode = '23514';
      end if;
      if p_outcome->>'remainder_disposition' in ('open', 'paused') and p_remainder is null then
        raise exception 'An open or paused remainder requires a child opportunity' using errcode = '23514';
      end if;
      if p_outcome->>'remainder_disposition' in ('closed', 'lost') and p_remainder is not null then
        raise exception 'A closed or lost remainder cannot create a child opportunity' using errcode = '23514';
      end if;
    elsif jsonb_array_length(coalesce(p_accepted_items, '[]'::jsonb)) > 0
       or p_remainder is not null
       or (
         v_proposed_reference is not null
         and nullif(p_update->>'accepted_net_amount', '')::numeric
             < v_proposed_reference
       ) then
      raise exception 'A partial acceptance must be declared explicitly' using errcode = '23514';
    end if;
    if p_remainder is not null and (
      p_outcome->>'remainder_disposition' not in ('open', 'paused')
      or p_remainder->>'commercial_status' is distinct from p_outcome->>'remainder_disposition'
      or coalesce(nullif(p_remainder->>'amount', '')::numeric, 0) <= 0
      or nullif(p_remainder->>'currency', '') is distinct from nullif(p_outcome->>'currency', '')
    ) then
      raise exception 'Remainder details are inconsistent with the partial acceptance' using errcode = '23514';
    end if;
    if p_remainder is not null
       and v_proposed_reference is not null
       and abs(
         nullif(p_update->>'accepted_net_amount', '')::numeric
         + nullif(p_remainder->>'amount', '')::numeric
         - v_proposed_reference
       ) > 0.01 then
      raise exception 'Accepted and remainder amounts must match the current valuation'
        using errcode = '23514';
    end if;
  end if;

  if p_quotation_delivery is not null then
    update public.crm_opportunity_quotations link
    set sent_at = nullif(p_quotation_delivery->>'sent_at', '')::timestamptz,
        sent_channel = nullif(btrim(p_quotation_delivery->>'sent_channel'), ''),
        sent_by = auth.uid(),
        updated_at = timezone('utc', now())
    where link.business_unit_id = p_business_unit_id
      and link.opportunity_id = p_opportunity_id
      and link.quotation_id = nullif(p_quotation_delivery->>'quotation_id', '')::uuid
      and link.is_current;
    if not found then
      raise exception 'Quotation is not linked to this opportunity' using errcode = '23503';
    end if;
  end if;

  update public.crm_opportunities opportunity
  set commercial_status = case when p_update ? 'commercial_status' then p_update->>'commercial_status' else opportunity.commercial_status end,
      stage = case when p_update ? 'stage' then p_update->>'stage' else opportunity.stage end,
      owner_user_id = case when p_update ? 'owner_user_id' then nullif(p_update->>'owner_user_id', '')::uuid else opportunity.owner_user_id end,
      next_action = case when p_update ? 'next_action' then nullif(btrim(p_update->>'next_action'), '') else opportunity.next_action end,
      next_action_at = case when p_update ? 'next_action_at' then nullif(p_update->>'next_action_at', '')::timestamptz else opportunity.next_action_at end,
      closed_at = case when p_update ? 'closed_at' then nullif(p_update->>'closed_at', '')::timestamptz else opportunity.closed_at end,
      paused_stage = case when p_update ? 'paused_stage' then nullif(p_update->>'paused_stage', '') else opportunity.paused_stage end,
      pause_reason_id = case when p_update ? 'pause_reason_id' then nullif(p_update->>'pause_reason_id', '')::uuid else opportunity.pause_reason_id end,
      pause_reason_snapshot = case when p_update ? 'pause_reason_snapshot' then nullif(btrim(p_update->>'pause_reason_snapshot'), '') else opportunity.pause_reason_snapshot end,
      pause_comment = case when p_update ? 'pause_comment' then nullif(btrim(p_update->>'pause_comment'), '') else opportunity.pause_comment end,
      reactivation_at = case when p_update ? 'reactivation_at' then nullif(p_update->>'reactivation_at', '')::timestamptz else opportunity.reactivation_at end,
      accepted_net_amount = case when p_update ? 'accepted_net_amount' then nullif(p_update->>'accepted_net_amount', '')::numeric else opportunity.accepted_net_amount end,
      accepted_currency = case when p_update ? 'accepted_currency' then nullif(p_update->>'accepted_currency', '') else opportunity.accepted_currency end,
      win_reason_id = case when p_update ? 'win_reason_id' then nullif(p_update->>'win_reason_id', '')::uuid else opportunity.win_reason_id end,
      loss_reason_id = case when p_update ? 'loss_reason_id' then nullif(p_update->>'loss_reason_id', '')::uuid else opportunity.loss_reason_id end,
      acceptance_evidence_type = case when p_update ? 'acceptance_evidence_type' then nullif(p_update->>'acceptance_evidence_type', '') else opportunity.acceptance_evidence_type end,
      evidence_document_id = case when p_update ? 'evidence_document_id' then nullif(p_update->>'evidence_document_id', '')::uuid else opportunity.evidence_document_id end,
      acceptance_evidence_reference = case
        when p_update ? 'acceptance_evidence_reference'
          then nullif(p_update->'acceptance_evidence_reference', 'null'::jsonb)
        else opportunity.acceptance_evidence_reference
      end,
      close_reason_snapshot = case when p_update ? 'close_reason_snapshot' then nullif(btrim(p_update->>'close_reason_snapshot'), '') else opportunity.close_reason_snapshot end,
      closure_comment = case when p_update ? 'closure_comment' then nullif(btrim(p_update->>'closure_comment'), '') else opportunity.closure_comment end,
      competitor_name = case when p_update ? 'competitor_name' then nullif(btrim(p_update->>'competitor_name'), '') else opportunity.competitor_name end,
      updated_by = auth.uid(),
      updated_at = timezone('utc', now())
  where opportunity.id = p_opportunity_id
    and opportunity.business_unit_id = p_business_unit_id
  returning * into v_after;

  -- The immutable outcome must be the exact historical snapshot of the state
  -- just applied.  This prevents direct RPC callers from recording conflicting
  -- amounts, dates, reasons or evidence.
  if p_outcome is not null and p_outcome->>'status' in ('won', 'won_correction') then
    if nullif(p_outcome->>'closed_at', '')::timestamptz is distinct from v_after.closed_at
       or nullif(p_outcome->>'reason_id', '')::uuid is distinct from v_after.win_reason_id
       or nullif(p_outcome->>'accepted_net_amount', '')::numeric is distinct from v_after.accepted_net_amount
       or nullif(p_outcome->>'currency', '') is distinct from v_after.accepted_currency
       or nullif(p_outcome->>'evidence_document_id', '')::uuid is distinct from v_after.evidence_document_id
       or nullif(p_outcome->>'evidence_type', '') is distinct from v_after.acceptance_evidence_type
       or nullif(p_outcome->'evidence_reference', 'null'::jsonb)
            is distinct from v_after.acceptance_evidence_reference
       or nullif(btrim(p_outcome->>'reason_snapshot'), '') is distinct from v_after.close_reason_snapshot
       or nullif(btrim(p_outcome->>'comment'), '') is distinct from v_after.closure_comment then
      raise exception 'Won outcome does not match the opportunity state' using errcode = '23514';
    end if;
  elsif p_outcome is not null and p_outcome->>'status' in ('lost', 'lost_correction') then
    if nullif(p_outcome->>'closed_at', '')::timestamptz is distinct from v_after.closed_at
       or nullif(p_outcome->>'reason_id', '')::uuid is distinct from v_after.loss_reason_id
       or nullif(btrim(p_outcome->>'reason_snapshot'), '') is distinct from v_after.close_reason_snapshot
       or nullif(btrim(p_outcome->>'comment'), '') is distinct from v_after.closure_comment
       or nullif(btrim(p_outcome->>'competitor_name'), '') is distinct from v_after.competitor_name then
      raise exception 'Lost outcome does not match the opportunity state' using errcode = '23514';
    end if;
  end if;

  if p_remainder is not null then
    insert into public.crm_opportunities (
      id, business_unit_id, parent_opportunity_id, account_id, name,
      commercial_status, stage, owner_user_id, next_action, next_action_at,
      current_proposed_net_amount, current_currency, tax_basis_status,
      technical_origin, paused_stage, pause_reason_id, pause_reason_snapshot,
      reactivation_at, created_by, updated_by
    ) values (
      gen_random_uuid(),
      p_business_unit_id,
      p_opportunity_id,
      v_before.account_id,
      coalesce(nullif(btrim(p_remainder->>'name'), ''), v_before.name || ' · Alcance remanente'),
      coalesce(nullif(p_remainder->>'commercial_status', ''), 'open'),
      coalesce(nullif(p_remainder->>'stage', ''), v_before.stage, 'qualification'),
      coalesce(nullif(p_remainder->>'owner_user_id', '')::uuid, v_before.owner_user_id, auth.uid()),
      nullif(btrim(p_remainder->>'next_action'), ''),
      nullif(p_remainder->>'next_action_at', '')::timestamptz,
      nullif(p_remainder->>'amount', '')::numeric,
      nullif(p_remainder->>'currency', ''),
      v_before.tax_basis_status,
      'partial_acceptance_remainder',
      case when p_remainder->>'commercial_status' = 'paused' then coalesce(nullif(p_remainder->>'stage', ''), v_before.stage) else null end,
      nullif(p_remainder->>'pause_reason_id', '')::uuid,
      case when p_remainder->>'commercial_status' = 'paused' then 'Remanente de aceptación parcial' else null end,
      nullif(p_remainder->>'reactivation_at', '')::timestamptz,
      auth.uid(),
      auth.uid()
    ) returning * into v_child;
  end if;

  if p_outcome is not null then
    insert into public.crm_opportunity_outcomes (
      business_unit_id, opportunity_id, status, closed_at, reason_id,
      reason_snapshot, comment, competitor_name, accepted_net_amount,
      currency, evidence_document_id, evidence_type, evidence_reference,
      is_partial, remainder_disposition, remainder_child_opportunity_id,
      created_by
    ) values (
      p_business_unit_id,
      p_opportunity_id,
      p_outcome->>'status',
      nullif(p_outcome->>'closed_at', '')::timestamptz,
      nullif(p_outcome->>'reason_id', '')::uuid,
      nullif(btrim(p_outcome->>'reason_snapshot'), ''),
      nullif(btrim(p_outcome->>'comment'), ''),
      nullif(btrim(p_outcome->>'competitor_name'), ''),
      nullif(p_outcome->>'accepted_net_amount', '')::numeric,
      nullif(p_outcome->>'currency', ''),
      nullif(p_outcome->>'evidence_document_id', '')::uuid,
      nullif(p_outcome->>'evidence_type', ''),
      nullif(p_outcome->'evidence_reference', 'null'::jsonb),
      coalesce((p_outcome->>'is_partial')::boolean, false),
      nullif(p_outcome->>'remainder_disposition', ''),
      v_child.id,
      auth.uid()
    ) returning * into v_outcome;
  end if;

  if jsonb_array_length(coalesce(p_accepted_items, '[]'::jsonb)) > 0 and v_outcome.id is null then
    raise exception 'Accepted items require an outcome' using errcode = '23514';
  end if;
  for v_item in select * from jsonb_array_elements(coalesce(p_accepted_items, '[]'::jsonb))
  loop
    select key into v_unknown_key
    from jsonb_object_keys(v_item) key
    where not (key = any(array[
      'quotation_item_id','code','description','quantity',
      'accepted_unit_net','accepted_total_net'
    ]::text[]))
    limit 1;
    if v_unknown_key is not null then
      raise exception 'Unsupported accepted-item field: %', v_unknown_key using errcode = '22023';
    end if;
    if abs(
      (v_item->>'quantity')::numeric * (v_item->>'accepted_unit_net')::numeric
      - (v_item->>'accepted_total_net')::numeric
    ) > 0.01 then
      raise exception 'Accepted item total must equal quantity times accepted unit net'
        using errcode = '23514';
    end if;
    if nullif(v_item->>'quotation_item_id', '') is not null then
      select quotation_item.quantity
      into v_quoted_quantity
      from public.ops_quotation_items quotation_item
      join public.crm_opportunity_quotations link
        on link.quotation_id = quotation_item.quotation_id
      where quotation_item.id = (v_item->>'quotation_item_id')::uuid
        and link.opportunity_id = p_opportunity_id
        and link.business_unit_id = p_business_unit_id;
      if not found then
        raise exception 'Accepted quotation item is not linked to this opportunity' using errcode = '23503';
      end if;
      if (v_item->>'quantity')::numeric > v_quoted_quantity then
        raise exception 'Accepted quantity cannot exceed quoted quantity' using errcode = '23514';
      end if;
    end if;
    insert into public.crm_opportunity_accepted_items (
      business_unit_id, opportunity_id, outcome_id, quotation_item_id,
      code, description, quantity, accepted_unit_net, accepted_total_net
    ) values (
      p_business_unit_id,
      p_opportunity_id,
      v_outcome.id,
      nullif(v_item->>'quotation_item_id', '')::uuid,
      nullif(v_item->>'code', ''),
      v_item->>'description',
      (v_item->>'quantity')::numeric,
      (v_item->>'accepted_unit_net')::numeric,
      (v_item->>'accepted_total_net')::numeric
    );
  end loop;

  if v_outcome.id is not null and v_outcome.is_partial then
    select coalesce(sum(item.accepted_total_net), 0)
    into v_items_total
    from public.crm_opportunity_accepted_items item
    where item.outcome_id = v_outcome.id;
    if abs(v_items_total - v_outcome.accepted_net_amount) > 0.01 then
      raise exception 'Accepted item total must equal accepted net amount' using errcode = '23514';
    end if;
  end if;

  insert into public.crm_opportunity_events (
    business_unit_id, opportunity_id, event_type, payload,
    old_values, new_values, source, occurred_at, created_by
  ) values (
    p_business_unit_id,
    p_opportunity_id,
    'transition_' || p_action,
    jsonb_build_object(
      'outcome_id', v_outcome.id,
      'remainder_opportunity_id', v_child.id
    ),
    to_jsonb(v_before),
    to_jsonb(v_after),
    'sales',
    timezone('utc', now()),
    auth.uid()
  );

  return jsonb_build_object(
    'opportunity', to_jsonb(v_after),
    'outcome', case when v_outcome.id is null then null else to_jsonb(v_outcome) end,
    'remainder_opportunity', case when v_child.id is null then null else to_jsonb(v_child) end
  );
end;
$$;

drop trigger if exists trg_crm_alert_settings_updated_at on public.crm_alert_settings;
create trigger trg_crm_alert_settings_updated_at
before update on public.crm_alert_settings
for each row execute procedure public.crm_set_updated_at();
drop trigger if exists trg_crm_opportunity_alerts_updated_at on public.crm_opportunity_alerts;
create trigger trg_crm_opportunity_alerts_updated_at
before update on public.crm_opportunity_alerts
for each row execute procedure public.crm_set_updated_at();

alter table public.crm_alert_settings enable row level security;
alter table public.crm_opportunity_alerts enable row level security;

drop policy if exists crm_alert_settings_select on public.crm_alert_settings;
create policy crm_alert_settings_select on public.crm_alert_settings
for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_alert_settings_write on public.crm_alert_settings;
create policy crm_alert_settings_write on public.crm_alert_settings
for all to authenticated
using (public.crm_has_business_unit_access(business_unit_id, array['admin','manager']::text[]))
with check (public.crm_has_business_unit_access(business_unit_id, array['admin','manager']::text[]));

drop policy if exists crm_opportunity_alerts_select on public.crm_opportunity_alerts;
create policy crm_opportunity_alerts_select on public.crm_opportunity_alerts
for select to authenticated
using (public.crm_has_business_unit_access(business_unit_id));
drop policy if exists crm_opportunity_alerts_update on public.crm_opportunity_alerts;
create policy crm_opportunity_alerts_update on public.crm_opportunity_alerts
for update to authenticated
using (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id))
with check (public.crm_can_edit_opportunity_child(business_unit_id, opportunity_id));

grant select, insert, update, delete on public.crm_alert_settings to authenticated;
grant select, update on public.crm_opportunity_alerts to authenticated;
revoke all on function public.crm_refresh_opportunity_alerts(uuid) from public;
revoke all on function public.crm_commercial_reporting_snapshot(uuid, date, date) from public;
revoke all on function public.crm_apply_opportunity_transition(
  uuid, uuid, integer, text, jsonb, jsonb, jsonb, jsonb, jsonb
) from public;
grant execute on function public.crm_refresh_opportunity_alerts(uuid) to authenticated, service_role;
grant execute on function public.crm_commercial_reporting_snapshot(uuid, date, date) to authenticated, service_role;
grant execute on function public.crm_apply_opportunity_transition(
  uuid, uuid, integer, text, jsonb, jsonb, jsonb, jsonb, jsonb
) to authenticated, service_role;

notify pgrst, 'reload schema';

commit;
