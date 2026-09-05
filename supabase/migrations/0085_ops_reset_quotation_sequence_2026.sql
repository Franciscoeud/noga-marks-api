-- OPS quotations: remove the initial test quotations and continue 2026 at 680.
begin;

-- Quotation items are removed by the existing ON DELETE CASCADE relationship.
-- Linked clients, CRM leads and their events remain untouched.
delete from public.ops_quotations
where quotation_year = 2026
  and quotation_number in (500, 501);

-- Keep 680 as a floor so reapplying this migration can never move an
-- already-advanced production counter backwards.
insert into public.ops_quotation_year_counters as counters (quotation_year, next_number)
values (2026, 680)
on conflict (quotation_year) do update
set next_number = excluded.next_number
where counters.next_number < excluded.next_number;

do $$
begin
  if exists (
    select 1
    from public.ops_quotations
    where quotation_year = 2026
      and quotation_number in (500, 501)
  ) then
    raise exception 'OPS quotations 500 and 501 for 2026 were not removed';
  end if;

  if not exists (
    select 1
    from public.ops_quotation_year_counters
    where quotation_year = 2026
      and next_number >= 680
  ) then
    raise exception 'OPS quotation counter for 2026 was not advanced to at least 680';
  end if;
end $$;

commit;
