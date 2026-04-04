-- CRM: account scoping and seeded WhatsApp templates for Brave and ISF
begin;

alter table public.crm_leads
  add column if not exists account_id uuid references public.crm_accounts(id) on delete set null;

alter table public.crm_message_templates
  add column if not exists account_id uuid references public.crm_accounts(id) on delete set null;

alter table public.crm_assignment_rules
  add column if not exists account_id uuid references public.crm_accounts(id) on delete set null;

create index if not exists idx_crm_leads_account_id
  on public.crm_leads(account_id);

create index if not exists idx_crm_message_templates_account_id
  on public.crm_message_templates(account_id);

create index if not exists idx_crm_assignment_rules_account_id
  on public.crm_assignment_rules(account_id);

drop index if exists public.uq_crm_message_templates_scope;

create unique index if not exists uq_crm_message_templates_scope
  on public.crm_message_templates(
    channel,
    language,
    coalesce(account_id::text, '*'),
    coalesce(product_interest_id::text, '*'),
    coalesce(lower(source_channel), '*'),
    coalesce(lower(requested_info_type), '*'),
    lower(template_key)
  );

insert into public.crm_accounts (name, type)
select seed.name, 'lead_source'
from (
  values
    ('Brave Destinations'),
    ('Instituto San Fernando')
) as seed(name)
where not exists (
  select 1
  from public.crm_accounts existing
  where lower(existing.name) = lower(seed.name)
);

with brave_account as (
  select id
  from public.crm_accounts
  where lower(name) = 'brave destinations'
  limit 1
),
isf_account as (
  select id
  from public.crm_accounts
  where lower(name) = 'instituto san fernando'
  limit 1
),
isf_interests as (
  select id
  from public.crm_product_interests
  where lower(slug) in ('optometria', 'enfermeria', 'terapia-fisica')
)
update public.crm_leads lead
set account_id = brave_account.id
from brave_account
where lead.account_id is null
  and (
    lower(coalesce(lead.landing_page, '')) like '%bravedestinations.com%'
    or lower(coalesce(lead.landing_page, '')) like '%brave%'
    or lower(coalesce(lead.campaign_name, '')) like '%brave%'
    or lower(coalesce(lead.form_name, '')) like '%brave%'
    or lower(coalesce(lead.source_detail, '')) like '%brave%'
    or lower(coalesce(lead.raw_payload->>'site', '')) like '%bravedestinations%'
    or lower(coalesce(lead.raw_payload->>'referrer', '')) like '%bravedestinations%'
  );

with isf_account as (
  select id
  from public.crm_accounts
  where lower(name) = 'instituto san fernando'
  limit 1
),
isf_interests as (
  select id
  from public.crm_product_interests
  where lower(slug) in ('optometria', 'enfermeria', 'terapia-fisica')
)
update public.crm_leads lead
set account_id = isf_account.id
from isf_account
where lead.account_id is null
  and lead.product_interest_id in (select id from isf_interests);

update public.crm_leads
set dedupe_key = case
      when coalesce(trim(external_source_id), '') <> '' and account_id is not null
        then 'external::' || lower(account_id::text) || '::' || lower(trim(external_source_id))
      when account_id is not null
        then lower(
          concat_ws(
            '|',
            account_id::text,
            coalesce(phone_normalized, ''),
            coalesce(email, ''),
            coalesce(product_interest_id::text, '')
          )
        )
      else dedupe_key
    end
where account_id is not null;

with isf_account as (
  select id
  from public.crm_accounts
  where lower(name) = 'instituto san fernando'
  limit 1
),
isf_interests as (
  select id
  from public.crm_product_interests
  where lower(slug) in ('optometria', 'enfermeria', 'terapia-fisica')
)
update public.crm_message_templates template
set account_id = isf_account.id
from isf_account
where template.account_id is null
  and template.product_interest_id in (select id from isf_interests);

insert into public.crm_message_templates (
  active,
  channel,
  template_key,
  template_name,
  language,
  account_id,
  source_channel,
  product_interest_id,
  requested_info_type,
  body,
  variables_schema,
  approval_status
)
select
  true,
  'whatsapp',
  'initial_whatsapp',
  seed.template_name,
  'en',
  brave.id,
  'web',
  null,
  seed.requested_info_type,
  seed.body,
  jsonb_build_object(
    'lead_name', 'string',
    'account_name', 'string',
    'requested_info_type', 'string',
    'advisor_name', 'string'
  ),
  'approved'
from (
  values
    ('comments_on_past_tour', 'Brave · Comments on Past Tour', 'Hi {{lead_name}}, thanks for contacting {{account_name}} about your past tour. We have received your message and one of our travel advisors will review it and reply here shortly.'),
    ('existing_reservation', 'Brave · Existing Reservation', 'Hi {{lead_name}}, thanks for contacting {{account_name}} about an existing reservation. We have received your request and one of our travel advisors will get back to you on WhatsApp shortly.'),
    ('ordering_a_brochure', 'Brave · Ordering a Brochure', 'Hi {{lead_name}}, thanks for requesting a brochure from {{account_name}}. We have received your request and a travel advisor will send the next details shortly.'),
    ('preparing_to_go', 'Brave · Preparing to Go', 'Hi {{lead_name}}, thanks for contacting {{account_name}} about preparing for your trip. We have received your request and a travel advisor will follow up here shortly.'),
    ('solo_travel', 'Brave · Solo Travel', 'Hi {{lead_name}}, thanks for your interest in solo travel with {{account_name}}. We have received your request and a travel advisor will reach out on WhatsApp shortly.'),
    ('tour_availability', 'Brave · Tour Availability', 'Hi {{lead_name}}, thanks for contacting {{account_name}} about tour availability. We have received your request and a travel advisor will confirm the next details shortly.'),
    ('tour_destinations', 'Brave · Tour Destinations', 'Hi {{lead_name}}, thanks for contacting {{account_name}} about tour destinations. We have received your request and one of our travel advisors will reply here shortly.'),
    ('using_our_website', 'Brave · Using our Website', 'Hi {{lead_name}}, thanks for contacting {{account_name}} about using our website. We have received your message and a travel advisor will assist you shortly.'),
    (null, 'Brave · Generic WhatsApp', 'Hi {{lead_name}}, thanks for contacting {{account_name}}. We have received your request and one of our travel advisors will reply here shortly.')
) as seed(requested_info_type, template_name, body)
cross join (
  select id
  from public.crm_accounts
  where lower(name) = 'brave destinations'
  limit 1
) as brave
where not exists (
  select 1
  from public.crm_message_templates existing
  where existing.channel = 'whatsapp'
    and lower(coalesce(existing.language, '')) = 'en'
    and coalesce(existing.account_id::text, '') = brave.id::text
    and coalesce(lower(existing.source_channel), '') = 'web'
    and coalesce(lower(existing.template_key), '') = 'initial_whatsapp'
    and coalesce(lower(existing.requested_info_type), '') = coalesce(lower(seed.requested_info_type), '')
);

notify pgrst, 'reload schema';

commit;
