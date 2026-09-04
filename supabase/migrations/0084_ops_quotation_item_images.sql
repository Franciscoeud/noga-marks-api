-- OPS quotations: optional reference image per quotation item.
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

notify pgrst, 'reload schema';

commit;
