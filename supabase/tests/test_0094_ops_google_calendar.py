"""Real PostgreSQL tests for 0094 (all fixtures roll back, never production).

OPS_CALENDAR_TEST_DSN=<disposable database> python -m unittest discover -s supabase/tests -v
OPS_CALENDAR_TEST_PSQL may point to psql.exe. The fixture user needs CREATE ROLE.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest
from uuid import uuid4


CDM = "10000000-0000-0000-0000-000000000001"
OTHER = "10000000-0000-0000-0000-000000000002"
ADMIN = "20000000-0000-0000-0000-000000000001"
WORKER = "20000000-0000-0000-0000-000000000002"
OTHER_WORKER = "20000000-0000-0000-0000-000000000003"
FOREIGN = "20000000-0000-0000-0000-000000000004"
READER = "20000000-0000-0000-0000-000000000005"
ASSIGNEE = "30000000-0000-0000-0000-000000000001"
OTHER_ASSIGNEE = "30000000-0000-0000-0000-000000000002"
CONNECTION = "40000000-0000-0000-0000-000000000001"
MAPPING = "50000000-0000-0000-0000-000000000001"
SECOND_MAPPING = "50000000-0000-0000-0000-000000000002"
TRADITIONAL_TYPE = "60000000-0000-0000-0000-000000000001"


def assert_sql(condition, message):
    return f"do $assert$ begin if ({condition}) is not true then raise exception '{message}'; end if; end $assert$;\n"


def rejects(sql, sqlstate=None):
    clause = f"sqlstate '{sqlstate}'" if sqlstate else "others"
    sql = re.sub(r"^select\b", "perform", sql.strip().rstrip(";"), flags=re.IGNORECASE)
    # The sentinel lies outside the inner exception handler, so an unexpectedly
    # successful call cannot be mistaken for the expected database rejection.
    return f"""
do $denial$ declare denied boolean := false;
begin
  begin {sql}; exception when {clause} then denied := true; end;
  if not denied then raise exception 'Expected database rejection'; end if;
end $denial$;
"""


def event(event_id="event-one", **overrides):
    result = {
        "event_id": event_id, "is_master": False,
        "raw_event": {"id": event_id, "status": "confirmed", "iCalUID": "stable-ical-" + event_id},
        "subject": "Revisar Laptop de Rey", "comments": "Descripción original",
        "google_status": "confirmed", "event_etag": '"etag-one"',
        "event_url": "https://calendar.google.com/calendar/event?eid=test",
        "scheduled_start": "2026-09-30T14:00:00-05:00",
        "scheduled_end": "2026-09-30T15:00:00-05:00",
        "all_day": False, "start_date": None, "end_date": None,
    }
    result.update(overrides)
    return result


def sync(events=None, token="token-one", *, full=False, window_start=None, window_end=None, mapping=MAPPING):
    events = [event()] if events is None else events
    start = "null" if window_start is None else f"'{window_start}'::date"
    end = "null" if window_end is None else f"'{window_end}'::date"
    return (
        f"select public.ops_calendar_commit_sync('{mapping}', "
        f"(select lease_token from public.ops_calendar_calendars where id = '{mapping}'), "
        f"$events${json.dumps(events, ensure_ascii=False)}$events$::jsonb, '{token}', true, "
        f"{str(full).lower()}, {start}, {end});\n"
    )


def act(action, user=WORKER, event_id="event-one", note="null"):
    return (
        f"select public.ops_calendar_act((select id from public.ops_orders where calendar_event_id = '{event_id}' "
        f"and calendar_mapping_id = '{MAPPING}'), '{user}', '{action}', {note});\n"
    )


def authenticated(user, company=CDM):
    return (
        "reset role;\n"
        f"select set_config('request.jwt.claim.sub', '{user}', true);\n"
        f"select set_config('request.headers', '{{\"x-company-id\":\"{company}\"}}', true);\n"
        "set local role authenticated;\n"
    )


class GoogleCalendarMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dsn = os.environ.get("OPS_CALENDAR_TEST_DSN")
        if not cls.dsn:
            raise unittest.SkipTest("OPS_CALENDAR_TEST_DSN is not configured (disposable PostgreSQL only)")
        cls.psql = os.environ.get("OPS_CALENDAR_TEST_PSQL") or shutil.which("psql")
        if not cls.psql:
            raise RuntimeError("Set OPS_CALENDAR_TEST_PSQL to the psql executable")
        source = (Path(__file__).resolve().parents[1] / "migrations" / "0094_ops_google_calendar.sql").read_text(encoding="utf-8")
        source = re.sub(r"(?m)^--[^\n]*\n", "", source).strip()
        if not source.startswith("begin;") or not source.endswith("commit;"):
            raise AssertionError("0094 must be transactional")
        cls.migration = source.removeprefix("begin;").removesuffix("commit;")

    def run_sql(self, body):
        suffix = uuid4().hex
        schema = "ops_0094_" + suffix
        fixture = f"""
begin;
set local statement_timeout = '20s';
create schema {schema};
set local search_path = {schema}, pg_catalog;
create role authenticated nologin nosuperuser noinherit nobypassrls;
create role anon nologin nosuperuser noinherit nobypassrls;
create role service_role nologin nosuperuser noinherit bypassrls;
grant authenticated, anon, service_role to current_user;
grant usage on schema {schema} to authenticated, anon, service_role;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create function public.crm_request_business_unit_id() returns uuid language sql stable as $$
  select nullif(nullif(current_setting('request.headers', true), '')::jsonb->>'x-company-id', '')::uuid;
$$;
create table public.crm_business_units(id uuid primary key, active boolean default true);
create table public.crm_business_unit_memberships(user_id uuid, business_unit_id uuid, role text, active boolean default true);
create table public.app_user_modules(user_id uuid, module_key text);
create table public.ops_assignees(id uuid primary key, name text not null, active boolean default true);
create table public.ops_inbox_user_permissions(user_id uuid primary key, access_level text, assignee_id uuid, active boolean default true);
create table public.ops_order_types(id uuid primary key default gen_random_uuid(), name text not null);
create table public.ops_orders(
  id uuid primary key default gen_random_uuid(), cod bigint generated by default as identity unique,
  order_type_id uuid not null references public.ops_order_types(id), business_unit_id uuid references public.crm_business_units(id),
  subject text, comments text, client_id uuid, client_text text, contact_id uuid, contact_text text,
  assignee_id uuid references public.ops_assignees(id), assignee text,
  order_date date not null, order_time time, delivery_date date, delivery_time time,
  status text not null default 'Pendiente', billing_status text not null default 'pending',
  billing_invoice_id uuid, contract_id uuid, contract_period_id uuid,
  is_custom_task_order boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.ops_order_tasks(id uuid primary key default gen_random_uuid(), order_id uuid references public.ops_orders(id), title text);
create table public.ops_task_templates(id uuid primary key default gen_random_uuid(), order_type_id uuid references public.ops_order_types(id), title text);
alter table public.ops_orders enable row level security;
-- Deliberately maximally permissive legacy policy: restrictive Calendar policies
-- must still prevent cross-user and cross-company access and all direct writes.
create policy legacy_ops_allow_all on public.ops_orders for all to authenticated using(true) with check(true);
grant select, insert, update, delete on public.ops_orders to authenticated;
grant all on public.ops_orders, public.ops_order_tasks, public.ops_task_templates, public.ops_order_types to service_role;
grant usage on all sequences in schema {schema} to service_role, authenticated;
insert into auth.users values ('{ADMIN}'), ('{WORKER}'), ('{OTHER_WORKER}'), ('{FOREIGN}'), ('{READER}');
insert into public.crm_business_units values ('{CDM}', true), ('{OTHER}', true);
insert into public.crm_business_unit_memberships values
  ('{ADMIN}', '{CDM}', 'admin', true), ('{WORKER}', '{CDM}', 'viewer', true),
  ('{OTHER_WORKER}', '{CDM}', 'sales_rep', true), ('{FOREIGN}', '{OTHER}', 'admin', true),
  ('{READER}', '{CDM}', 'viewer', true);
insert into public.ops_assignees values ('{ASSIGNEE}', 'Carlos Alberto', true), ('{OTHER_ASSIGNEE}', 'Other worker', true);
insert into public.ops_inbox_user_permissions values ('{WORKER}', 'assignee', '{ASSIGNEE}', true),
  ('{OTHER_WORKER}', 'assignee', '{OTHER_ASSIGNEE}', true), ('{READER}', 'all', null, true);
insert into public.ops_order_types values ('{TRADITIONAL_TYPE}', 'Traditional');
{self.migration}
insert into public.ops_calendar_connections(id,business_unit_id,user_id,google_email,encrypted_refresh_token)
values ('{CONNECTION}', '{CDM}', '{ADMIN}', 'test@example.invalid', 'encrypted-not-a-real-token');
insert into public.ops_calendar_calendars(id,business_unit_id,connection_id,calendar_id,calendar_name,assignee_id)
values ('{MAPPING}', '{CDM}', '{CONNECTION}', 'pilot-calendar', 'OPS - Carlos Alberto', '{ASSIGNEE}');
select public.ops_calendar_acquire_lease('{MAPPING}');
"""
        script = fixture + body + "\nreset role;\nrollback;\n"
        script = (script.replace("public.", schema + ".").replace("auth.", schema + ".")
                  .replace("search_path = public, pg_temp", f"search_path = {schema}, pg_temp")
                  .replace("'public'::regnamespace", f"'{schema}'::regnamespace")
                  .replace("authenticated", "auth_" + suffix)
                  .replace("service_role", "service_" + suffix)
                  .replace("anon", "anon_" + suffix))
        result = subprocess.run(
            [self.psql, "-X", "--no-password", "--set=ON_ERROR_STOP=1", "--quiet", "--dbname", self.dsn],
            input=script, text=True, encoding="utf-8", capture_output=True, timeout=35,
            env={**os.environ, "PGCLIENTENCODING": "UTF8"},
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def test_exact_schedule_without_templates_or_customer(self):
        self.run_sql(sync() + assert_sql("""(select subject = 'Revisar Laptop de Rey' and assignee_id = '""" + ASSIGNEE + """'
          and order_date = '2026-09-30' and order_time = '14:00' and delivery_time = '15:00'
          and scheduled_start = '2026-09-30T19:00:00Z' and scheduled_end = '2026-09-30T20:00:00Z'
          and status = 'Pendiente' and billing_status = 'not_applicable'
          and client_id is null and contact_id is null and contract_id is null
          and execution_started_at is null and execution_completed_at is null
          and created_at = now() from public.ops_orders)""", "Incorrect imported order")
          + assert_sql("(select count(*) from public.ops_order_tasks) = 0", "Created checklist tasks"))

    def test_hidden_calendar_parent_cannot_bypass_task_guard(self):
        self.run_sql(sync()
          + "select set_config('test.calendar_order', (select id::text from public.ops_orders), true);\n"
          + "grant insert on public.ops_order_tasks to authenticated;\n"
          + authenticated(OTHER_WORKER)
          + assert_sql("(select count(*) from public.ops_orders) = 0", "Foreign worker sees activity")
          + rejects("insert into public.ops_order_tasks(order_id,title) values (current_setting('test.calendar_order')::uuid, 'Not permitted')")
          + "reset role;\n"
          + assert_sql("(select count(*) from public.ops_order_tasks) = 0", "RLS-hidden parent bypassed task guard"))

    def test_night_weekend_midnight_and_all_day_are_preserved(self):
        self.run_sql(sync([
            event("night", scheduled_start="2026-10-03T23:45:12-05:00", scheduled_end="2026-10-04T01:30:45-05:00"),
            event("all-day", all_day=True, scheduled_start=None, scheduled_end=None, start_date="2026-10-03", end_date="2026-10-05"),
        ]) + assert_sql("(select order_time = '23:45:12' and delivery_time = '01:30:45' and order_date = '2026-10-03' and delivery_date = '2026-10-04' from public.ops_orders where calendar_event_id = 'night')", "Business hours altered event")
        + assert_sql("(select order_time is null and delivery_time is null and scheduled_start is null and scheduled_end is null and calendar_end_date = '2026-10-05' from public.ops_orders where calendar_event_id = 'all-day')", "All day event invented hours"))

    def test_repeat_sync_and_reprogramming_are_idempotent(self):
        self.run_sql(sync() + sync() + assert_sql("(select count(*) from public.ops_orders) = 1", "Duplicate order")
        + assert_sql("(select count(*) from public.ops_calendar_history) = 1", "Identical sync grew history")
        + sync([event(subject="Reprogramada", scheduled_start="2026-10-02T22:00:00-05:00", scheduled_end="2026-10-02T23:00:00-05:00")], token="token-two")
        + assert_sql("(select count(*) from public.ops_orders) = 1", "Reprogramming created order")
        + assert_sql("(select subject = 'Reprogramada' and order_time = '22:00' and publish_revision = 2 from public.ops_orders)", "Reprogramming was lost")
        + assert_sql("(select sync_token = 'token-two' from public.ops_calendar_calendars)", "Missing checkpoint"))

    def test_completion_without_start_does_not_invent_execution(self):
        self.run_sql(sync() + act("complete", note="'Entregado'") + act("complete", note="'Must not overwrite'") + act("start")
        + assert_sql("(select status = 'Completado' and execution_started_at is null and execution_started_by is null and execution_completed_by = '" + WORKER + "' and execution_note = 'Entregado' and publish_revision = 2 from public.ops_orders)", "Completion not idempotent")
        + assert_sql("(select count(*) from public.ops_calendar_history where event_type = 'complete') = 1", "Duplicate completion history")
        + sync([event(subject="Changed remotely")], token="resync-token", full=True)
        + assert_sql("(select status = 'Completado' and execution_completed_at is not null and execution_started_at is null from public.ops_orders)", "Resync reset execution"))

    def test_start_complete_and_repeated_occurrence_are_isolated(self):
        self.run_sql(sync([
            event("first", recurring_event_id="series", original_start_key="2026-09-30T19:00:00Z"),
            event("second", recurring_event_id="series", original_start_key="2026-10-01T19:00:00Z"),
        ]) + act("start", event_id="first") + act("start", event_id="first") + act("complete", event_id="first")
        + assert_sql("(select execution_started_at is not null and execution_completed_at >= execution_started_at and status = 'Completado' from public.ops_orders where calendar_event_id = 'first')", "Execution timestamps missing")
        + assert_sql("(select status = 'Pendiente' and execution_started_at is null and execution_completed_at is null from public.ops_orders where calendar_event_id = 'second')", "Another occurrence modified")
        + assert_sql("(select count(*) from public.ops_calendar_history where event_type = 'start') = 1", "Repeated start not idempotent"))

    def test_cancellation_preserves_execution_and_sparse_tombstone_is_not_order(self):
        cancelled = {"event_id": "event-one", "google_status": "cancelled", "raw_event": {"status": "cancelled"}}
        self.run_sql(sync() + act("start") + sync([cancelled, {**cancelled, "event_id": "unknown"}])
        + assert_sql("(select count(*) from public.ops_orders) = 1", "Sparse cancellation created activity")
        + assert_sql("(select status = 'Procesando' and execution_started_at is not null and calendar_external_status = 'cancelled' and subject = 'Revisar Laptop de Rey' from public.ops_orders)", "Cancellation overwrote work")
        + rejects(act("complete")))

    def test_full_resync_preserves_completed_missing_activity(self):
        self.run_sql(sync() + act("complete") + sync([], token="after-410", full=True)
        + assert_sql("(select status = 'Completado' and calendar_external_status = 'cancelled' and execution_completed_at is not null from public.ops_orders)", "Full reset deleted execution")
        + assert_sql("(select sync_token = 'after-410' from public.ops_calendar_calendars)", "Resync checkpoint missing"))

    def test_recurrence_window_exclusion_keeps_outside_history(self):
        master = {"event_id": "series", "is_master": True, "raw_event": {"status": "confirmed", "recurrence": ["RRULE:FREQ=DAILY"]}}
        first = event("first", recurring_event_id="series", original_start_key="first")
        older = event("older", recurring_event_id="series", original_start_key="older", scheduled_start="2026-01-01T14:00:00-05:00", scheduled_end="2026-01-01T15:00:00-05:00")
        self.run_sql(sync([master, first, older]) + sync([master], window_start="2026-09-01", window_end="2026-11-01")
        + assert_sql("(select count(*) from public.ops_orders) = 2", "Master became an activity")
        + assert_sql("(select calendar_external_status = 'cancelled' from public.ops_orders where calendar_event_id = 'first')", "Excluded occurrence remains live")
        + assert_sql("(select calendar_external_status = 'confirmed' from public.ops_orders where calendar_event_id = 'older')", "Window erased historical occurrence"))

    def test_lease_fences_stale_workers_and_atomic_checkpoint(self):
        self.run_sql(assert_sql(f"public.ops_calendar_acquire_lease('{MAPPING}') is null", "Concurrent worker acquired lease")
        + rejects(f"select public.ops_calendar_commit_sync('{MAPPING}', gen_random_uuid(), '[]', 'bad')")
        + assert_sql(f"not public.ops_calendar_renew_lease('{MAPPING}', gen_random_uuid())", "Renew accepted stale token")
        + rejects(sync([event(), event("invalid", scheduled_end="2026-09-29T14:00:00-05:00")]))
        + assert_sql("(select count(*) from public.ops_orders) = 0", "Failed batch partially persisted")
        + assert_sql("(select sync_token is null from public.ops_calendar_calendars)", "Failed batch advanced checkpoint")
        + assert_sql("(select count(*) from public.ops_calendar_event_cache) = 0", "Failed batch persisted cache"))

    def test_stale_publication_ack_does_not_lose_completion(self):
        ack = f"select public.ops_calendar_publish_ack((select id from public.ops_orders), (select lease_token from public.ops_calendar_calendars), 1, '\"old-etag\"');"
        self.run_sql(sync() + act("complete") + ack
        + assert_sql("(select publish_pending and publish_revision = 2 from public.ops_orders)", "Stale ACK lost completion")
        + "select public.ops_calendar_publish_error((select id from public.ops_orders), (select lease_token from public.ops_calendar_calendars), 'Temporary failure');"
        + assert_sql("(select status = 'Completado' and publish_pending and last_publish_error = 'Temporary failure' from public.ops_orders)", "Publication failure lost closure")
        + "select public.ops_calendar_publish_ack((select id from public.ops_orders), (select lease_token from public.ops_calendar_calendars), 2, '\"new-etag\"');"
        + assert_sql("(select not publish_pending and last_publish_error is null from public.ops_orders)", "Publication not acknowledged"))

    def test_direct_legacy_writes_and_tasks_are_denied(self):
        self.run_sql(sync() + "set local role service_role;"
        + rejects("update public.ops_orders set status = 'Pendiente'")
        + rejects("delete from public.ops_orders")
        + rejects("insert into public.ops_order_tasks(order_id,title) select id,'Forbidden checklist' from public.ops_orders")
        + rejects("insert into public.ops_task_templates(order_type_id,title) select id,'Forbidden template' from public.ops_order_types where code='google_calendar'")
        + rejects("insert into public.ops_orders(order_type_id,order_date) select id,current_date from public.ops_order_types where code='google_calendar'")
        + f"insert into public.ops_orders(order_type_id,order_date) values ('{TRADITIONAL_TYPE}',current_date);"
        + "update public.ops_orders set status='Procesando' where origin='traditional';"
        + "insert into public.ops_order_tasks(order_id,title) select id,'Traditional checklist' from public.ops_orders where origin='traditional';"
        + assert_sql("(select count(*) from public.ops_order_tasks)=1", "Traditional checklist regressed"))

    def test_rls_assignee_company_and_explicit_module_restrictions(self):
        self.run_sql(sync() + authenticated(WORKER)
        + assert_sql("(select count(*) from public.ops_orders)=1", "Assigned worker cannot read activity")
        + assert_sql("(select count(*) from public.ops_calendar_connections)=0", "Worker sees connections")
        + authenticated(OTHER_WORKER) + assert_sql("(select count(*) from public.ops_orders)=0", "Other worker sees activity")
        + authenticated(FOREIGN, OTHER) + assert_sql("(select count(*) from public.ops_orders)=0", "Cross-company leak")
        + authenticated(ADMIN, OTHER) + assert_sql("(select count(*) from public.ops_orders)=0", "Company header bypass")
        + "reset role;" + f"insert into public.app_user_modules values ('{ADMIN}','Sales');"
        + authenticated(ADMIN) + assert_sql("(select count(*) from public.ops_orders)=0", "Explicit non-OPS module gained access"))

    def test_service_action_revalidates_user_company_and_assignee(self):
        self.run_sql(sync() + rejects(act("start", user=OTHER_WORKER), "42501")
        + rejects(act("start", user=FOREIGN), "42501") + rejects(act("start", user=READER), "42501")
        + f"update public.crm_business_unit_memberships set active=false where user_id='{WORKER}';"
        + rejects(act("start"), "42501") + act("start", user=ADMIN)
        + assert_sql("(select execution_started_by='" + ADMIN + "' from public.ops_orders)", "Admin cannot act"))

    def test_no_client_rpc_or_secret_access_and_no_direct_updates(self):
        self.run_sql(sync() + authenticated(ADMIN)
        + assert_sql("(select count(id) from public.ops_calendar_connections)=1", "Admin lacks safe connection metadata")
        + rejects("select encrypted_refresh_token from public.ops_calendar_connections", "42501")
        + rejects("select * from public.ops_calendar_oauth_states", "42501")
        + rejects(f"select public.ops_calendar_acquire_lease('{MAPPING}')", "42501")
        + rejects(act("complete", user=ADMIN), "42501")
        + "update public.ops_orders set status='Completado';"
        + assert_sql("(select status='Pendiente' from public.ops_orders)", "Direct update bypassed explicit action")
        + rejects(f"select public.ops_calendar_user_access('{ADMIN}','{CDM}',null,true)", "42501"))

    def test_configuration_cannot_cross_company_and_history_is_immutable(self):
        self.run_sql(sync()
        + rejects(f"insert into public.ops_calendar_calendars(business_unit_id,connection_id,calendar_id,calendar_name,assignee_id) values ('{OTHER}','{CONNECTION}','foreign','Foreign','{ASSIGNEE}')", "23503")
        + rejects("update public.ops_calendar_history set event_type='rewritten'")
        + rejects("delete from public.ops_calendar_history"))

    def test_migration_is_repeatable_and_does_not_duplicate_or_reset(self):
        self.run_sql(sync() + act("complete") + self.migration
        + assert_sql("(select count(*) from public.ops_order_types where code='google_calendar')=1", "Duplicate system type")
        + assert_sql("(select count(*) from public.ops_orders)=1", "Migration changed orders")
        + assert_sql("(select status='Completado' and execution_completed_at is not null from public.ops_orders)", "Migration reset execution"))

    def test_occurrence_stable_identity_survives_changed_event_id(self):
        self.run_sql(sync([event("first-id", recurring_event_id="series", original_start_key="2026-09-30T19:00:00Z")])
        + act("complete", event_id="first-id")
        + sync([event("replacement-id", recurring_event_id="series", original_start_key="2026-09-30T19:00:00Z")])
        + assert_sql("(select count(*) from public.ops_orders)=1", "Stable occurrence duplicated")
        + assert_sql("(select calendar_event_id='replacement-id' and status='Completado' from public.ops_orders)", "Stable occurrence lost identity or execution"))

    def test_missing_managed_link_or_completion_is_republished_without_echo_loop(self):
        # The canonical subject/comments remain identical if someone removes only
        # our appended link/checkmark. Raw provider fields must still enqueue repair.
        self.run_sql(sync() + act("complete")
        + "select public.ops_calendar_publish_ack((select id from public.ops_orders),(select lease_token from public.ops_calendar_calendars),2,'etag');"
        + sync()
        + assert_sql("(select publish_pending and publish_revision=3 from public.ops_orders)", "Removed managed content not repaired")
        + sync() + assert_sql("(select publish_revision=3 from public.ops_orders)", "Same pending repair endlessly increments revision")
        + "select public.ops_calendar_publish_ack((select id from public.ops_orders),(select lease_token from public.ops_calendar_calendars),3,'etag');"
        + """select public.ops_calendar_commit_sync('""" + MAPPING + """',
          (select lease_token from public.ops_calendar_calendars),
          jsonb_build_array(jsonb_build_object('event_id','event-one','subject','Revisar Laptop de Rey',
            'comments','Descripción original','scheduled_start','2026-09-30T14:00:00-05:00',
            'scheduled_end','2026-09-30T15:00:00-05:00','event_url','https://calendar.google.com/calendar/event?eid=test',
            'raw_event',jsonb_build_object('summary','✔ Revisar Laptop de Rey',
              'description','Descripción original [Nogamarks OPS] /ops/google-calendar/activities/'||(select id::text from public.ops_orders),
              'extendedProperties',jsonb_build_object('private',jsonb_build_object('nogamarksCompleted','true',
                'nogamarksOrderId',(select id::text from public.ops_orders)))))),'echo');"""
        + assert_sql("(select not publish_pending and publish_revision=3 from public.ops_orders)", "Provider echo caused a publication loop"))

    def test_calendar_move_links_only_exact_cancelled_identity_preserving_source_work(self):
        self.run_sql(sync() + act("start")
        + sync([{"event_id": "event-one", "google_status": "cancelled"}])
        + f"insert into public.ops_calendar_calendars(id,business_unit_id,connection_id,calendar_id,calendar_name,assignee_id) values ('{SECOND_MAPPING}','{CDM}','{CONNECTION}','second-calendar','OPS - Other worker','{OTHER_ASSIGNEE}');"
        + f"select public.ops_calendar_acquire_lease('{SECOND_MAPPING}');"
        + sync(mapping=SECOND_MAPPING)
        + assert_sql("(select count(*) from public.ops_orders)=2", "Move lost historical order")
        + assert_sql(f"(select status='Procesando' and calendar_external_status='cancelled' and execution_started_at is not null from public.ops_orders where calendar_mapping_id='{MAPPING}')", "Move lost original work")
        + assert_sql(f"(select status='Pendiente' and execution_started_at is null and calendar_transferred_from_order_id=(select id from public.ops_orders where calendar_mapping_id='{MAPPING}') from public.ops_orders where calendar_mapping_id='{SECOND_MAPPING}')", "Move did not preserve explicit source linkage"))


if __name__ == "__main__":
    unittest.main()
