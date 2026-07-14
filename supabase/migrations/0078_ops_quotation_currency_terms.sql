-- OPS: quotation currency and per-proforma commercial terms
begin;

update public.ops_quotations
set currency = 'PEN'
where currency is null
   or nullif(btrim(currency), '') is null;

update public.ops_quotations
set currency = upper(btrim(currency))
where currency is not null;

update public.ops_quotations
set currency = 'PEN'
where currency not in ('PEN', 'USD');

alter table public.ops_quotations
  alter column currency set default 'PEN',
  alter column currency set not null;

alter table public.ops_quotations
  drop constraint if exists ops_quotations_currency_check;

alter table public.ops_quotations
  add constraint ops_quotations_currency_check
  check (currency in ('PEN', 'USD'));

notify pgrst, 'reload schema';

commit;
