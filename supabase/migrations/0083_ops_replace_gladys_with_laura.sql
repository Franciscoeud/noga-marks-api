-- OPS: Laura replaces Gladys effective 2026-08-26.
-- Preserve completed task history under Gladys and transfer all open work to Laura.
begin;

do $$
declare
  v_gladys_id uuid;
  v_laura_id uuid;
  v_match_count integer;
begin
  select count(*), (array_agg(id))[1]
  into v_match_count, v_gladys_id
  from public.ops_assignees
  where lower(btrim(name)) = lower('Gladys');

  if v_match_count <> 1 then
    raise exception 'Expected exactly one OPS assignee named Gladys, found %', v_match_count;
  end if;

  select count(*), (array_agg(id))[1]
  into v_match_count, v_laura_id
  from public.ops_assignees
  where lower(btrim(name)) = lower('Laura');

  if v_match_count > 1 then
    raise exception 'Expected at most one OPS assignee named Laura, found %', v_match_count;
  end if;

  if v_laura_id is null then
    insert into public.ops_assignees (name, active)
    values ('Laura', true)
    returning id into v_laura_id;
  else
    update public.ops_assignees
    set
      name = 'Laura',
      active = true,
      updated_at = timezone('utc', now())
    where id = v_laura_id;
  end if;

  update public.ops_order_tasks
  set
    assignee_id = v_laura_id,
    assignee_text = 'Laura',
    updated_at = timezone('utc', now())
  where assignee_id = v_gladys_id
    and not (
      completed_at is not null
      or lower(btrim(coalesce(status, ''))) = lower('Completado')
    );

  update public.ops_task_templates
  set
    default_assignee_id = v_laura_id,
    updated_at = timezone('utc', now())
  where default_assignee_id = v_gladys_id;

  update public.ops_inbox_user_permissions
  set
    assignee_id = v_laura_id,
    notes = case
      when notes is null then 'Bandeja OPS Laura - reemplaza a Gladys desde 2026-08-26'
      else replace(notes, 'Gladys', 'Laura')
    end,
    updated_at = timezone('utc', now())
  where assignee_id = v_gladys_id;

  update public.ops_notification_recipients
  set
    assignee_id = v_laura_id,
    name = case
      when lower(btrim(name)) = lower('Gladys') then 'Laura'
      else name
    end,
    updated_at = timezone('utc', now())
  where assignee_id = v_gladys_id;

  update public.ops_assignees
  set
    active = false,
    updated_at = timezone('utc', now())
  where id = v_gladys_id;

  if exists (
    select 1
    from public.ops_order_tasks
    where assignee_id = v_gladys_id
      and not (
        completed_at is not null
        or lower(btrim(coalesce(status, ''))) = lower('Completado')
      )
  ) then
    raise exception 'Open OPS tasks remain assigned to Gladys';
  end if;

  if exists (
    select 1
    from public.ops_task_templates
    where default_assignee_id = v_gladys_id
  ) then
    raise exception 'OPS task templates remain assigned to Gladys';
  end if;

  if exists (
    select 1
    from public.ops_inbox_user_permissions
    where assignee_id = v_gladys_id
  ) then
    raise exception 'OPS inbox permissions remain assigned to Gladys';
  end if;

  if exists (
    select 1
    from public.ops_notification_recipients
    where assignee_id = v_gladys_id
  ) then
    raise exception 'OPS notification recipients remain assigned to Gladys';
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;
