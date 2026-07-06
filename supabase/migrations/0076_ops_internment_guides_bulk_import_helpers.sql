-- OPS: helpers for bulk importing internment guides
begin;

create or replace function public.ops_resolve_user_profiles_by_email(p_emails text[])
returns table (
  email text,
  user_id uuid,
  display_name text
)
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  return query
  select
    lower(u.email)::text as email,
    u.id as user_id,
    p.display_name
  from auth.users u
  join public.ops_user_profiles p on p.user_id = u.id
  where p.active = true
    and nullif(btrim(p.display_name), '') is not null
    and lower(u.email) = any (
      select lower(nullif(btrim(input_email), ''))
      from unnest(coalesce(p_emails, array[]::text[])) as input(input_email)
      where nullif(btrim(input_email), '') is not null
    );
end;
$$;

create or replace function public.ops_sync_internment_guide_number_seq()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max_number integer;
begin
  if to_regclass('public.ops_internment_guide_number_seq') is null then
    return null;
  end if;

  select max(guide_number)
    into v_max_number
  from public.ops_internment_guides;

  if v_max_number is not null then
    perform setval('public.ops_internment_guide_number_seq'::regclass, v_max_number, true);
  end if;

  return null;
end;
$$;

do $$
begin
  if to_regclass('public.ops_internment_guides') is not null then
    drop trigger if exists trg_ops_internment_guides_sync_number_seq
      on public.ops_internment_guides;
    create trigger trg_ops_internment_guides_sync_number_seq
    after insert or update of guide_number on public.ops_internment_guides
    for each statement execute procedure public.ops_sync_internment_guide_number_seq();
  end if;
end $$;

grant execute on function public.ops_resolve_user_profiles_by_email(text[]) to authenticated;
grant execute on function public.ops_sync_internment_guide_number_seq() to authenticated;

notify pgrst, 'reload schema';

commit;
