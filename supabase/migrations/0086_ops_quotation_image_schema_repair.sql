-- OPS quotations: repair image metadata columns and recover a failed 680 save.
begin;

alter table public.ops_quotation_items
  add column if not exists image_url text,
  add column if not exists image_storage_path text,
  add column if not exists image_filename text,
  add column if not exists image_mime_type text;

alter table public.ops_quotation_items
  drop constraint if exists ops_quotation_items_image_mime_check;

alter table public.ops_quotation_items
  add constraint ops_quotation_items_image_mime_check
  check (
    image_mime_type is null
    or image_mime_type in ('image/jpeg', 'image/png', 'image/webp')
  );

do $$
declare
  v_deleted_count integer := 0;
begin
  -- Delete only the header left by the failed save. A quotation that acquired
  -- items in the meantime is preserved.
  delete from public.ops_quotations as quotation
  where quotation.quotation_year = 2026
    and quotation.quotation_number = 680
    and not exists (
      select 1
      from public.ops_quotation_items as item
      where item.quotation_id = quotation.id
    );

  get diagnostics v_deleted_count = row_count;

  -- Restore 680 only for the exact failed-save state. Concurrent or later
  -- quotations prevent the counter from moving backwards.
  if v_deleted_count = 1 then
    update public.ops_quotation_year_counters as counters
    set next_number = 680
    where counters.quotation_year = 2026
      and counters.next_number = 681
      and not exists (
        select 1
        from public.ops_quotations as quotation
        where quotation.quotation_year = 2026
          and quotation.quotation_number >= 680
      );
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
