-- Access: grant Keily access to Planning and GTS modules
begin;

alter table public.app_user_modules
  drop constraint if exists app_user_modules_module_key_check;

alter table public.app_user_modules
  add constraint app_user_modules_module_key_check
  check (module_key in ('SCM', 'Planificacion', 'MES', 'Sales', 'FI', 'Ops', 'Revenue', 'GTS'));

insert into public.app_user_modules (user_id, module_key)
select u.id, module.module_key
from auth.users u
cross join (
  values
    ('Planificacion'),
    ('GTS')
) as module(module_key)
where lower(u.email) = 'keily.arenas@nogamarks.com'
on conflict (user_id, module_key) do nothing;

notify pgrst, 'reload schema';

commit;
