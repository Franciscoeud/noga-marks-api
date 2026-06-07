-- MES: calculate NuOrder EUR prices from dated master exchange rates
begin;

alter table public.mes_garments
  drop constraint if exists mes_garments_nuorder_wholesale_eur_nonnegative;
alter table public.mes_garments
  drop constraint if exists mes_garments_nuorder_retail_eur_nonnegative;

alter table public.mes_garments
  drop column if exists nuorder_wholesale_eur,
  drop column if exists nuorder_retail_eur;

alter table public.mes_exchange_rates
  drop constraint if exists mes_exchange_rates_currency_from_check;
alter table public.mes_exchange_rates
  drop constraint if exists mes_exchange_rates_currency_to_check;

alter table public.mes_exchange_rates
  add constraint mes_exchange_rates_currency_from_check
  check (currency_from in ('USD', 'PEN', 'EUR'));

alter table public.mes_exchange_rates
  add constraint mes_exchange_rates_currency_to_check
  check (currency_to in ('USD', 'PEN', 'EUR'));

notify pgrst, 'reload schema';

commit;
