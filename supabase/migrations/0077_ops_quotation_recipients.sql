-- OPS: quotation recipients linked to Sales leads
begin;

alter table public.ops_quotations
  alter column client_id drop not null;

alter table public.ops_quotations
  add column if not exists recipient_type text not null default 'client',
  add column if not exists crm_lead_id uuid references public.crm_leads(id) on delete set null,
  add column if not exists recipient_name_snapshot text,
  add column if not exists recipient_doc_snapshot text,
  add column if not exists recipient_email_snapshot text,
  add column if not exists recipient_phone_snapshot text;

update public.ops_quotations
set
  recipient_type = coalesce(nullif(btrim(recipient_type), ''), 'client'),
  recipient_name_snapshot = coalesce(nullif(btrim(recipient_name_snapshot), ''), client_name)
where recipient_name_snapshot is null
   or nullif(btrim(recipient_name_snapshot), '') is null
   or nullif(btrim(recipient_type), '') is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'ops_quotations_recipient_type_check'
      and conrelid = 'public.ops_quotations'::regclass
  ) then
    alter table public.ops_quotations
      add constraint ops_quotations_recipient_type_check
      check (recipient_type in ('client', 'lead', 'manual'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'ops_quotations_recipient_required_check'
      and conrelid = 'public.ops_quotations'::regclass
  ) then
    alter table public.ops_quotations
      add constraint ops_quotations_recipient_required_check
      check (
        nullif(btrim(recipient_name_snapshot), '') is not null
        and (
          (recipient_type = 'client' and client_id is not null and crm_lead_id is null)
          or (recipient_type = 'lead' and client_id is null and crm_lead_id is not null)
          or (recipient_type = 'manual' and client_id is null and crm_lead_id is null and status = 'draft')
        )
      );
  end if;
end $$;

create index if not exists idx_ops_quotations_recipient_type
  on public.ops_quotations(recipient_type);
create index if not exists idx_ops_quotations_crm_lead
  on public.ops_quotations(crm_lead_id)
  where crm_lead_id is not null;

notify pgrst, 'reload schema';

commit;
