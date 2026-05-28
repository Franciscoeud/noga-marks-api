-- MES: normalize current SS27 USD/PEN master exchange rate
begin;

update public.mes_exchange_rates
set
  rate = 3.7000,
  updated_at = now(),
  notes = coalesce(nullif(notes, ''), 'TC maestro SS27 vigente')
where dispatch = 'SS27'
  and currency_from = 'USD'
  and currency_to = 'PEN'
  and active
  and rate = 3.5000;

notify pgrst, 'reload schema';

commit;
