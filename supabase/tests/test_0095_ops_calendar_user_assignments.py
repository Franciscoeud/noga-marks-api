"""Calendar-only access against disposable PostgreSQL; every fixture rolls back."""
from pathlib import Path
import re
import unittest

import test_0094_ops_google_calendar as calendar


def migration(name):
    source = (Path(__file__).resolve().parents[1] / "migrations" / name).read_text(encoding="utf-8")
    source = re.sub(r"(?m)^--[^\n]*\n", "", source).strip()
    if not source.startswith("begin;") or not source.endswith("commit;"):
        raise AssertionError("Migration must be transactional")
    return source.removeprefix("begin;").removesuffix("commit;")


CDM, OTHER, READER = calendar.CDM, calendar.OTHER, calendar.READER
ASSIGNEE, OTHER_ASSIGNEE = calendar.ASSIGNEE, calendar.OTHER_ASSIGNEE
SEED_USER = "0ead3bd7-fa97-481c-950d-9944b60b9a40"
SEED_COMPANY = "ca19e953-7efc-40c6-89b9-60b69e7ad8a3"
SEED_ASSIGNEE = "5ae05a6c-abc5-4fb2-a5aa-a674114415c6"
SEED_MAPPING = "537882dd-736c-4271-acce-f0fa1a62477e"
SEED_CONNECTION = "90000000-0000-0000-0000-000000000001"


class CalendarPersonalAccessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        calendar.GoogleCalendarMigrationTests.setUpClass.__func__(cls)
        cls.assignment_migration = migration("0095_ops_calendar_user_assignments.sql")
        cls.crm_migration = migration("0093_crm_unrestricted_module_access.sql")

    def run_sql(self, body, before=""):
        # Reuse 0094's real schema and transaction harness, without importing or
        # inheriting its TestCase (which would run the old suite a second time).
        preparation = """
alter table auth.users add column email text;
alter table public.crm_business_units add column code text;
"""
        calendar.GoogleCalendarMigrationTests.run_sql(
            self, preparation + self.crm_migration + before + self.assignment_migration + body,
        )

    @staticmethod
    def personal():
        return f"""
delete from public.crm_business_unit_memberships where user_id = '{READER}';
insert into public.ops_calendar_user_assignments(business_unit_id,user_id,assignee_id)
values ('{CDM}', '{READER}', '{ASSIGNEE}');
"""

    def test_personal_execution_does_not_change_inbox_modules_or_crm(self):
        self.run_sql(self.personal()
            + calendar.assert_sql(f"public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}',false,true)", "Own execution denied")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{OTHER_ASSIGNEE}',false,true)", "Other worker execution granted")
            + calendar.assert_sql(f"public.ops_calendar_user_access('{READER}','{CDM}','{OTHER_ASSIGNEE}')", "Full inbox read lost")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}',null,true)", "Management granted")
            + calendar.assert_sql(f"not exists(select 1 from public.crm_business_unit_memberships where user_id='{READER}')", "CRM membership created")
            + calendar.assert_sql(f"not exists(select 1 from public.app_user_modules where user_id='{READER}')", "Module permissions changed")
            + calendar.assert_sql(f"(select access_level='all' and assignee_id is null from public.ops_inbox_user_permissions where user_id='{READER}')", "Inbox changed")
            + calendar.authenticated(READER)
            + calendar.assert_sql(f"not public.crm_has_business_unit_access('{CDM}')", "Sales read access granted")
            + calendar.assert_sql(f"not public.crm_can_edit_business_record('{CDM}',null)", "Sales write access granted"))

    def test_real_start_complete_and_idempotency_without_crm_membership(self):
        self.run_sql(self.personal() + calendar.sync()
            + calendar.act("start", user=READER)
            + calendar.act("complete", user=READER, note="'Test closure'")
            + calendar.act("complete", user=READER, note="'Do not overwrite'")
            + calendar.assert_sql("(select status='Completado' and execution_started_at is not null and execution_completed_at is not null and execution_note='Test closure' from public.ops_orders where calendar_event_id='event-one')", "Closure not preserved"))

    def test_other_worker_action_rejected_but_both_rows_readable(self):
        self.run_sql(self.personal() + calendar.sync()
            + f"insert into public.ops_calendar_calendars(id,business_unit_id,connection_id,calendar_id,calendar_name,assignee_id) values ('{calendar.SECOND_MAPPING}','{CDM}','{calendar.CONNECTION}','other','Other','{OTHER_ASSIGNEE}');"
            + f"select public.ops_calendar_acquire_lease('{calendar.SECOND_MAPPING}');"
            + calendar.sync(mapping=calendar.SECOND_MAPPING)
            + calendar.rejects(f"select public.ops_calendar_act((select id from public.ops_orders where calendar_mapping_id='{calendar.SECOND_MAPPING}'),'{READER}','complete',null)", "42501")
            + calendar.authenticated(READER)
            + calendar.assert_sql("(select count(*) from public.ops_orders)=2", "Read-all scope changed"))

    def test_company_header_and_foreign_company_are_enforced(self):
        self.run_sql(self.personal() + calendar.sync()
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{OTHER}','{ASSIGNEE}',false,true)", "Foreign execution granted")
            + calendar.authenticated(READER, company=OTHER)
            + calendar.assert_sql("(select count(*) from public.ops_orders)=0", "Company header bypassed")
            + calendar.authenticated(READER)
            + calendar.assert_sql("(select count(*) from public.ops_orders)=1", "Own company unavailable"))

    def test_disabled_assignment_company_or_inbox_denies_execution(self):
        check = calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}',false,true)", "Inactive permission granted")
        self.run_sql(self.personal()
            + f"update public.ops_calendar_user_assignments set active=false where user_id='{READER}';" + check
            + f"update public.ops_calendar_user_assignments set active=true where user_id='{READER}';"
            + f"update public.crm_business_units set active=false where id='{CDM}';" + check
            + f"update public.crm_business_units set active=true where id='{CDM}';"
            + f"update public.ops_inbox_user_permissions set active=false where user_id='{READER}';" + check
            + f"delete from public.ops_inbox_user_permissions where user_id='{READER}';" + check)

    def test_explicit_module_list_cannot_be_bypassed(self):
        self.run_sql(self.personal()
            + f"insert into public.app_user_modules values ('{READER}','Sales');"
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}',false,true)", "Module restriction bypassed")
            + f"insert into public.app_user_modules values ('{READER}','Ops');"
            + calendar.assert_sql(f"public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}',false,true)", "Explicit OPS denied"))

    def test_private_assignment_and_service_rpc_cannot_be_self_granted(self):
        self.run_sql(self.personal() + calendar.sync() + calendar.authenticated(READER)
            + calendar.rejects("select * from public.ops_calendar_user_assignments", "42501")
            + calendar.rejects(f"insert into public.ops_calendar_user_assignments(business_unit_id,user_id,assignee_id) values ('{OTHER}','{READER}','{OTHER_ASSIGNEE}')", "42501")
            + calendar.rejects("update public.ops_calendar_user_assignments set active=true", "42501")
            + calendar.rejects(calendar.act("complete", user=READER), "42501")
            + calendar.rejects(f"select public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}',false,true)", "42501"))

    def test_legacy_permissions_and_explicit_identity_precedence(self):
        self.run_sql(
            calendar.assert_sql(f"public.ops_calendar_user_access('{calendar.ADMIN}','{CDM}',null,true,true)", "Legacy admin denied")
            + calendar.assert_sql(f"public.ops_calendar_user_access('{calendar.WORKER}','{CDM}','{ASSIGNEE}',false,true)", "Legacy worker denied")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}',false,true)", "Read-all gained execution")
            + f"insert into public.ops_calendar_user_assignments(business_unit_id,user_id,assignee_id) values ('{CDM}','{calendar.WORKER}','{OTHER_ASSIGNEE}');"
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{calendar.WORKER}','{CDM}','{ASSIGNEE}',false,true)", "Legacy identity overrides explicit identity")
            + calendar.assert_sql(f"public.ops_calendar_user_access('{calendar.WORKER}','{CDM}','{OTHER_ASSIGNEE}',false,true)", "Explicit identity denied"))

    def test_repeated_migration_does_not_reset_disabled_assignment(self):
        self.run_sql(self.personal()
            + f"update public.ops_calendar_user_assignments set active=false where user_id='{READER}';"
            + self.assignment_migration
            + calendar.assert_sql(f"(select count(*) from public.ops_calendar_user_assignments where user_id='{READER}')=1", "Assignment duplicated")
            + calendar.assert_sql(f"(select not active from public.ops_calendar_user_assignments where user_id='{READER}')", "Assignment reactivated"))

    @staticmethod
    def seed_fixture():
        # Isolated authorization fixture with verified IDs, no production events.
        return f"""
insert into auth.users(id,email) values ('{SEED_USER}','lrj@cdmservi.com');
insert into public.crm_business_units(id,active,code) values ('{SEED_COMPANY}',true,'cdm');
insert into public.ops_assignees(id,name) values ('{SEED_ASSIGNEE}','Test LRJ');
insert into public.ops_inbox_user_permissions values ('{SEED_USER}','all',null,true);
insert into public.ops_calendar_connections(id,business_unit_id,user_id,google_email,encrypted_refresh_token)
  values ('{SEED_CONNECTION}','{SEED_COMPANY}','{calendar.ADMIN}','test@example.invalid','not-a-real-token');
insert into public.ops_calendar_calendars(id,business_unit_id,connection_id,calendar_id,calendar_name,assignee_id)
  values ('{SEED_MAPPING}','{SEED_COMPANY}','{SEED_CONNECTION}','test-lrj-calendar','Test LRJ','{SEED_ASSIGNEE}');
"""

    def test_verified_lrj_seed_is_precise_repeatable_and_preserves_scopes(self):
        self.run_sql(self.assignment_migration
            + calendar.assert_sql(f"(select count(*) from public.ops_calendar_user_assignments where user_id='{SEED_USER}' and business_unit_id='{SEED_COMPANY}' and assignee_id='{SEED_ASSIGNEE}' and active)=1", "Seed absent or duplicated")
            + calendar.assert_sql(f"not exists(select 1 from public.crm_business_unit_memberships where user_id='{SEED_USER}')", "Seed granted CRM access")
            + calendar.assert_sql(f"not exists(select 1 from public.app_user_modules where user_id='{SEED_USER}')", "Seed changed modules")
            + calendar.assert_sql(f"(select access_level='all' and assignee_id is null from public.ops_inbox_user_permissions where user_id='{SEED_USER}')", "Seed reduced inbox visibility")
            + f"update public.ops_calendar_user_assignments set active=false where user_id='{SEED_USER}';"
            + self.assignment_migration
            + calendar.assert_sql(f"(select not active from public.ops_calendar_user_assignments where user_id='{SEED_USER}')", "Seed reactivated a revoked permission"),
            before=self.seed_fixture())

    def test_changed_verified_mapping_stops_repair(self):
        # Catch only the guard's explicit error, not the assertion sentinel.
        block = self.assignment_migration.split("do $$", 1)[1].split("notify pgrst", 1)[0]
        self.run_sql(f"update public.ops_calendar_calendars set assignee_id='{OTHER_ASSIGNEE}' where id='{SEED_MAPPING}';"
            + calendar.rejects("do $$" + block, "P0001"), before=self.seed_fixture())
