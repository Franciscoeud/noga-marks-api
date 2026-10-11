"""Personal Calendar read scope in real PostgreSQL; every fixture rolls back."""
import unittest

import test_0094_ops_google_calendar as calendar
import test_0095_ops_calendar_user_assignments as assignments


CDM, OTHER, READER = calendar.CDM, calendar.OTHER, calendar.READER
ASSIGNEE, OTHER_ASSIGNEE = calendar.ASSIGNEE, calendar.OTHER_ASSIGNEE


class CalendarPersonalReadScopeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assignments.CalendarPersonalAccessTests.setUpClass.__func__(cls)
        cls.scope_migration = assignments.migration("0096_ops_calendar_personal_read_scope.sql")

    def run_sql(self, body, before=""):
        assignments.CalendarPersonalAccessTests.run_sql(
            self, self.scope_migration + body, before=before,
        )

    @staticmethod
    def two_calendars():
        return (calendar.sync()
            + f"insert into public.ops_calendar_calendars(id,business_unit_id,connection_id,calendar_id,calendar_name,assignee_id) values ('{calendar.SECOND_MAPPING}','{CDM}','{calendar.CONNECTION}','other','Other','{OTHER_ASSIGNEE}');"
            + f"select public.ops_calendar_acquire_lease('{calendar.SECOND_MAPPING}');"
            + calendar.sync([calendar.event("other-event")], mapping=calendar.SECOND_MAPPING))

    def test_active_personal_assignment_caps_read_all_and_execution(self):
        self.run_sql(assignments.CalendarPersonalAccessTests.personal()
            + calendar.assert_sql(f"public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}')", "Own read denied")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{OTHER_ASSIGNEE}')", "Inbox-all bypassed personal read scope")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}',null)", "Unscoped read granted")
            + calendar.assert_sql(f"public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}',false,true)", "Own execution denied")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{OTHER_ASSIGNEE}',false,true)", "Other execution granted")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}',null,true)", "Personal assignment granted management"))

    def test_rls_hides_other_orders_calendars_and_history_even_without_header(self):
        self.run_sql(assignments.CalendarPersonalAccessTests.personal() + self.two_calendars()
            + calendar.authenticated(READER)
            + "select set_config('request.headers', '{}', true);"
            + calendar.assert_sql(f"(select count(*) from public.ops_orders)=1 and (select bool_and(assignee_id='{ASSIGNEE}') from public.ops_orders)", "Other activity exposed")
            + calendar.assert_sql(f"(select count(*) from public.ops_orders where assignee_id='{OTHER_ASSIGNEE}')=0", "Assignee query escaped scope")
            + calendar.assert_sql(f"(select count(*) from public.ops_calendar_calendars)=1 and (select bool_and(assignee_id='{ASSIGNEE}') from public.ops_calendar_calendars)", "Other calendar exposed")
            + calendar.assert_sql("(select count(*) from public.ops_calendar_history)=1", "Other execution history exposed")
            + calendar.assert_sql("(select count(*) from public.ops_calendar_connections)=0", "Connection metadata exposed"))

    def test_own_actions_remain_available_and_other_actions_are_rejected(self):
        self.run_sql(assignments.CalendarPersonalAccessTests.personal() + self.two_calendars()
            + calendar.rejects(f"select public.ops_calendar_act((select id from public.ops_orders where calendar_mapping_id='{calendar.SECOND_MAPPING}'),'{READER}','start',null)", "42501")
            + calendar.act("start", user=READER)
            + calendar.act("complete", user=READER, note="'Personal closure'")
            + calendar.act("complete", user=READER, note="'Do not overwrite'")
            + calendar.assert_sql(f"(select status='Completado' and execution_started_by='{READER}' and execution_completed_by='{READER}' and execution_note='Personal closure' from public.ops_orders where calendar_mapping_id='{calendar.MAPPING}')", "Own closure lost")
            + calendar.assert_sql(f"(select status='Pendiente' and execution_started_at is null from public.ops_orders where calendar_mapping_id='{calendar.SECOND_MAPPING}')", "Other activity changed"))

    def test_traditional_inbox_modules_and_crm_access_are_preserved(self):
        self.run_sql(assignments.CalendarPersonalAccessTests.personal() + self.two_calendars()
            + f"insert into public.ops_orders(order_type_id,order_date,assignee_id) values ('{calendar.TRADITIONAL_TYPE}',current_date,'{OTHER_ASSIGNEE}');"
            + calendar.assert_sql(f"(select access_level='all' and assignee_id is null and active from public.ops_inbox_user_permissions where user_id='{READER}')", "Traditional inbox permissions changed")
            + calendar.assert_sql(f"not exists(select 1 from public.app_user_modules where user_id='{READER}')", "Module permissions changed")
            + calendar.assert_sql(f"not exists(select 1 from public.crm_business_unit_memberships where user_id='{READER}')", "CRM membership created")
            + calendar.authenticated(READER)
            + calendar.assert_sql("(select count(*) from public.ops_orders where origin='traditional')=1", "Traditional inbox visibility narrowed")
            + calendar.assert_sql(f"not public.crm_has_business_unit_access('{CDM}')", "Sales read access granted")
            + calendar.assert_sql(f"not public.crm_can_edit_business_record('{CDM}',null)", "Sales write access granted"))

    def test_admin_and_manager_keep_global_access_with_personal_assignment(self):
        self.run_sql(self.two_calendars()
            + f"insert into public.ops_calendar_user_assignments(business_unit_id,user_id,assignee_id) values ('{CDM}','{calendar.ADMIN}','{ASSIGNEE}');"
            + calendar.assert_sql(f"public.ops_calendar_user_access('{calendar.ADMIN}','{CDM}','{OTHER_ASSIGNEE}')", "Admin read narrowed")
            + calendar.assert_sql(f"public.ops_calendar_user_access('{calendar.ADMIN}','{CDM}','{OTHER_ASSIGNEE}',true,true)", "Admin management or execution denied")
            + calendar.authenticated(calendar.ADMIN)
            + calendar.assert_sql("(select count(*) from public.ops_orders)=2", "Admin RLS narrowed")
            + "reset role;"
            + f"update public.crm_business_unit_memberships set role='manager' where user_id='{calendar.ADMIN}';"
            + calendar.assert_sql(f"public.ops_calendar_user_access('{calendar.ADMIN}','{CDM}','{OTHER_ASSIGNEE}',true,true)", "Manager global access denied")
            + calendar.authenticated(calendar.ADMIN)
            + calendar.assert_sql("(select count(*) from public.ops_orders)=2", "Manager RLS narrowed"))

    def test_legacy_read_all_without_personal_assignment_is_preserved(self):
        self.run_sql(self.two_calendars()
            + calendar.assert_sql(f"public.ops_calendar_user_access('{READER}','{CDM}','{OTHER_ASSIGNEE}')", "Legacy global read denied")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{OTHER_ASSIGNEE}',false,true)", "Read-all gained execution")
            + calendar.authenticated(READER)
            + calendar.assert_sql("(select count(*) from public.ops_orders)=2", "Legacy RLS read narrowed"))

    def test_personal_identity_overrides_legacy_assignee_for_read_and_act(self):
        self.run_sql(f"insert into public.ops_calendar_user_assignments(business_unit_id,user_id,assignee_id) values ('{CDM}','{calendar.WORKER}','{OTHER_ASSIGNEE}');"
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{calendar.WORKER}','{CDM}','{ASSIGNEE}')", "Legacy assignee escaped personal read scope")
            + calendar.assert_sql(f"public.ops_calendar_user_access('{calendar.WORKER}','{CDM}','{OTHER_ASSIGNEE}')", "Personal read denied")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{calendar.WORKER}','{CDM}','{ASSIGNEE}',false,true)", "Legacy assignee escaped personal execution scope")
            + calendar.assert_sql(f"public.ops_calendar_user_access('{calendar.WORKER}','{CDM}','{OTHER_ASSIGNEE}',false,true)", "Personal execution denied"))

    def test_disabled_assignment_does_not_create_access_without_membership(self):
        self.run_sql(assignments.CalendarPersonalAccessTests.personal()
            + f"update public.ops_calendar_user_assignments set active=false where user_id='{READER}';"
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}')", "Disabled assignment granted own read")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{OTHER_ASSIGNEE}')", "Disabled assignment granted global read")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}',false,true)", "Disabled assignment granted execution"))

    def test_active_company_inbox_module_and_company_header_are_required(self):
        denied = calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}')", "Inactive or missing permission granted read")
        self.run_sql(assignments.CalendarPersonalAccessTests.personal() + calendar.sync()
            + f"update public.crm_business_units set active=false where id='{CDM}';" + denied
            + f"update public.crm_business_units set active=true where id='{CDM}';"
            + f"update public.ops_inbox_user_permissions set active=false where user_id='{READER}';" + denied
            + f"update public.ops_inbox_user_permissions set active=true where user_id='{READER}';"
            + f"insert into public.app_user_modules values ('{READER}','Sales');" + denied
            + f"insert into public.app_user_modules values ('{READER}','Ops');"
            + calendar.assert_sql(f"public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}')", "Explicit OPS read denied")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{READER}','{OTHER}','{ASSIGNEE}')", "Foreign company access granted")
            + calendar.authenticated(READER, company=OTHER)
            + calendar.assert_sql("(select count(*) from public.ops_orders)=0", "Company header bypassed")
            + "reset role;"
            + f"delete from public.ops_inbox_user_permissions where user_id='{READER}';" + denied)

    def test_verified_lrj_login_can_only_read_his_seeded_assignee(self):
        self.run_sql(
            calendar.assert_sql(f"public.ops_calendar_user_access('{assignments.SEED_USER}','{assignments.SEED_COMPANY}','{assignments.SEED_ASSIGNEE}')", "LRJ own read denied")
            + calendar.assert_sql(f"not public.ops_calendar_user_access('{assignments.SEED_USER}','{assignments.SEED_COMPANY}','{OTHER_ASSIGNEE}')", "LRJ login retained global Calendar read")
            + calendar.assert_sql(f"(select access_level='all' and assignee_id is null from public.ops_inbox_user_permissions where user_id='{assignments.SEED_USER}')", "LRJ inbox visibility changed")
            + calendar.authenticated(assignments.SEED_USER, company=assignments.SEED_COMPANY)
            + calendar.assert_sql(f"public.ops_calendar_can_read('{assignments.SEED_COMPANY}','{assignments.SEED_ASSIGNEE}')", "LRJ authenticated own read denied")
            + calendar.assert_sql(f"not public.ops_calendar_can_read('{assignments.SEED_COMPANY}','{OTHER_ASSIGNEE}')", "LRJ authenticated read escaped personal scope"),
            before=assignments.CalendarPersonalAccessTests.seed_fixture())

    def test_repeat_migration_preserves_disabled_assignment_and_private_grants(self):
        self.run_sql(assignments.CalendarPersonalAccessTests.personal() + calendar.sync()
            + f"update public.ops_calendar_user_assignments set active=false where user_id='{READER}';"
            + self.scope_migration
            + calendar.assert_sql(f"(select count(*)=1 and bool_and(not active and assignee_id='{ASSIGNEE}') from public.ops_calendar_user_assignments where user_id='{READER}')", "Migration reset personal identity")
            + calendar.assert_sql("(select count(*) from public.ops_orders)=1", "Migration changed events")
            + calendar.authenticated(READER)
            + calendar.rejects("select * from public.ops_calendar_user_assignments", "42501")
            + calendar.rejects(f"select public.ops_calendar_user_access('{READER}','{CDM}','{ASSIGNEE}')", "42501"))


if __name__ == "__main__":
    unittest.main()
