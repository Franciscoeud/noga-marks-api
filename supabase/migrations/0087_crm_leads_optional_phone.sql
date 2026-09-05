-- CRM leads: allow OPS quick leads to be created before a phone is known.
begin;

alter table public.crm_leads
  alter column phone_normalized drop not null;

notify pgrst, 'reload schema';

commit;
