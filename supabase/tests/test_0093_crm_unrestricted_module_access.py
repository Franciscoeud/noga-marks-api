"""Execute 0089 policies and 0093 helpers against isolated PostgreSQL fixtures.

Run only against a disposable test database with a role allowed to CREATE ROLE:
    CRM_MIGRATION_TEST_DSN=<test DSN> python -m unittest discover -s supabase/tests -v

Set CRM_MIGRATION_TEST_PSQL when psql is not on PATH. Every fixture uses a unique
schema and a non-owner, non-superuser RLS role; all DDL and data roll back.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest
from uuid import uuid4


MIGRATIONS = Path(__file__).resolve().parents[1] / "migrations"
CDM = "10000000-0000-0000-0000-000000000001"
FOREIGN = "10000000-0000-0000-0000-000000000002"
USERS = {
    name: f"20000000-0000-0000-0000-{number:012d}"
    for number, name in enumerate(
        ("viewer", "admin", "no_membership", "inactive", "foreign", "ops",
         "mes", "sales", "sales_rep", "marketing", "manager"),
        start=1,
    )
}
FUNCTIONS = (
    "crm_request_business_unit_id",
    "crm_has_business_unit_access",
    "crm_has_ops_business_unit_access",
    "crm_is_any_business_admin",
    "crm_can_edit_business_record",
)
TABLES = (
    "app_user_modules", "crm_business_units", "crm_business_unit_memberships",
    "crm_accounts", "crm_campaigns", "crm_business_unit_assignment_queue",
)


def check(condition, message):
    return (
        "do $assert$ begin if (" + condition
        + ") is not true then raise exception '" + message.replace("'", "''")
        + "'; end if; end $assert$;\n"
    )


def expect_denied(sql):
    return f"""
do $expected_denial$
begin
  begin
    {sql}
    raise exception 'Expected an RLS denial, but the write succeeded';
  exception when insufficient_privilege then
    null;
  end;
end $expected_denial$;
"""


def check_affected(sql, count, message):
    escaped_message = message.replace("'", "''")
    return f"""
do $assert_write$
declare affected integer;
begin
  {sql};
  get diagnostics affected = row_count;
  if affected <> {count} then
    raise exception '{escaped_message}: expected {count}, got %', affected;
  end if;
end $assert_write$;
"""


def as_user(user, company=CDM):
    uid = USERS[user] if user else ""
    headers = '{"x-company-id":"' + company + '"}' if company else "{}"
    return f"""
reset role;
select set_config('request.jwt.claim.sub', '{uid}', true);
select set_config('request.headers', '{headers}', true);
set local role authenticated;
"""


def row_snapshot():
    return " union all ".join(
        f"select '{table}' as relation, to_jsonb(record) as row "
        f"from public.{table} record" for table in TABLES
    )


def same_rows(left, right):
    return (
        f"not exists (select * from {left} except all select * from {right}) "
        f"and not exists (select * from {right} except all select * from {left})"
    )


class UnrestrictedModuleAccessMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dsn = os.environ.get("CRM_MIGRATION_TEST_DSN")
        if not cls.dsn:
            raise unittest.SkipTest("CRM_MIGRATION_TEST_DSN is not configured")
        cls.psql = os.environ.get("CRM_MIGRATION_TEST_PSQL") or shutil.which("psql")
        if not cls.psql:
            raise RuntimeError("Install psql or set CRM_MIGRATION_TEST_PSQL")
        original = (MIGRATIONS / "0089_crm_business_units_security.sql").read_text(
            encoding="utf-8"
        )
        cls.original_functions = "\n".join(
            re.search(
                rf"create or replace function public\.{name}\(.*?\n\$\$;",
                original, re.DOTALL,
            ).group(0)
            for name in FUNCTIONS
        )
        policy_names = (
            "crm_business_units_select", "crm_business_units_manage",
            "crm_accounts_select", "crm_accounts_write",
            "crm_campaigns_select", "crm_campaigns_write",
            "crm_business_unit_assignment_queue_select",
        )
        cls.policies = "\n".join(
            re.search(
                rf"create policy {name}\b.*?;", original, re.DOTALL,
            ).group(0)
            for name in policy_names
        )
        source = (
            MIGRATIONS / "0093_crm_unrestricted_module_access.sql"
        ).read_text(encoding="utf-8")
        source = re.sub(r"(?m)^--[^\n]*\n", "", source).strip()
        if not source.startswith("begin;") or not source.endswith("commit;"):
            raise AssertionError("0093 must have an explicit transaction wrapper")
        # Retain the real migration body inside the fixture's outer rollback.
        cls.migration = source.removeprefix("begin;").removesuffix("commit;")

    def run_sql(self, body, *, migrate=True):
        suffix = uuid4().hex
        schema = "crm_0093_test_" + suffix
        role = "crm_0093_role_" + suffix
        grants = "\n".join(
            f"revoke all on function public.{signature} from public; "
            f"grant execute on function public.{signature} to authenticated;"
            for signature in (
                "crm_request_business_unit_id()",
                "crm_has_business_unit_access(uuid, text[])",
                "crm_has_ops_business_unit_access(uuid, text[])",
                "crm_is_any_business_admin()",
                "crm_can_edit_business_record(uuid, uuid, boolean)",
            )
        )
        memberships = ",\n".join(
            f"('{USERS[user]}', '{unit}', '{member_role}', {str(active).lower()})"
            for user, unit, member_role, active in (
                ("viewer", CDM, "viewer", True),
                ("admin", CDM, "admin", True),
                ("inactive", CDM, "admin", False),
                ("foreign", FOREIGN, "viewer", True),
                ("ops", CDM, "admin", True),
                ("mes", CDM, "admin", True),
                ("sales", CDM, "admin", True),
                ("sales_rep", CDM, "sales_rep", True),
                ("marketing", CDM, "marketing", True),
                ("manager", CDM, "manager", True),
            )
        )
        fixture = f"""
begin;
set local statement_timeout = '15s';
create schema {schema};
set local search_path = {schema}, pg_catalog;
create role authenticated nologin nosuperuser noinherit nobypassrls;
grant authenticated to current_user;
grant usage on schema {schema} to authenticated;
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
create table public.app_user_modules (user_id uuid, module_key text);
create table public.crm_business_units (id uuid primary key, name text);
create table public.crm_business_unit_memberships (
  user_id uuid, business_unit_id uuid, role text, active boolean,
  primary key (user_id, business_unit_id)
);
create table public.crm_accounts (
  id integer primary key, business_unit_id uuid, owner_user_id uuid, name text
);
create table public.crm_campaigns (
  id integer primary key, business_unit_id uuid, owner_user_id uuid, name text
);
create table public.crm_business_unit_assignment_queue (
  id integer primary key, description text
);
insert into public.app_user_modules values
  ('{USERS['ops']}', 'OPS'), ('{USERS['mes']}', 'MES'),
  ('{USERS['sales']}', 'SaLeS'), ('{USERS['sales']}', 'OPS');
insert into public.crm_business_units values
  ('{CDM}', 'CDM'), ('{FOREIGN}', 'Other company');
insert into public.crm_business_unit_memberships values {memberships};
insert into public.crm_accounts values
  (1, '{CDM}', '{USERS['sales_rep']}', 'Owned by rep'),
  (2, '{CDM}', '{USERS['sales']}', 'Owned by someone else'),
  (3, '{CDM}', null, 'Unassigned'),
  (4, '{FOREIGN}', '{USERS['foreign']}', 'Foreign account');
insert into public.crm_campaigns values
  (1, '{CDM}', null, 'CDM campaign'), (2, '{FOREIGN}', null, 'Foreign campaign');
insert into public.crm_business_unit_assignment_queue values (1, 'Global queue');
{self.original_functions}
{grants}
alter table public.crm_business_units enable row level security;
alter table public.crm_accounts enable row level security;
alter table public.crm_campaigns enable row level security;
alter table public.crm_business_unit_assignment_queue enable row level security;
{self.policies}
grant select, insert, update, delete on public.crm_accounts,
  public.crm_campaigns, public.crm_business_units,
  public.crm_business_unit_assignment_queue to authenticated;
"""
        script = fixture + (self.migration if migrate else "") + body
        script += "\nreset role;\nrollback;\n"
        script = (
            script.replace("public.", schema + ".")
            .replace("auth.", schema + ".")
            .replace("search_path = public, pg_temp", f"search_path = {schema}, pg_temp")
            .replace("authenticated", role)
        )
        result = subprocess.run(
            [self.psql, "-X", "--no-password", "--set=ON_ERROR_STOP=1", "--quiet",
             "--dbname", self.dsn],
            input=script, text=True, encoding="utf-8", capture_output=True,
            timeout=30, env={**os.environ, "PGCLIENTENCODING": "UTF8"},
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def denied_company_access(self):
        return (
            check(f"not public.crm_has_business_unit_access('{CDM}')", "Read helper allowed CDM")
            + check(f"not public.crm_can_edit_business_record('{CDM}')", "Edit helper allowed CDM")
            + check("(select count(*) from public.crm_accounts) = 0", "RLS exposed accounts")
            + check("(select count(*) from public.crm_business_units) = 0", "RLS exposed companies")
            + check_affected(
                "update public.crm_accounts set name = 'Denied'", 0, "RLS allowed update",
            )
            + expect_denied(
                "insert into public.crm_accounts values "
                f"(99, '{CDM}', null, 'Denied insert');"
            )
        )

    def test_original_helpers_reproduce_unrestricted_access_failure(self):
        self.run_sql(
            as_user("admin") + self.denied_company_access()
            + check("not public.crm_is_any_business_admin()", "Original admin gate did not deny")
            + "reset role;\n" + self.migration + as_user("admin")
            + check("(select count(*) from public.crm_accounts) = 3", "0093 did not restore CDM read")
            + check("public.crm_is_any_business_admin()", "0093 did not restore existing admin"),
            migrate=False,
        )

    def test_unrestricted_viewer_reads_without_writes_or_admin_privileges(self):
        self.run_sql(
            as_user("viewer")
            + check(f"public.crm_has_business_unit_access('{CDM}')", "Viewer lost membership read")
            + check(f"not public.crm_has_business_unit_access('{CDM}', array['admin'])", "Viewer gained admin role")
            + check(f"not public.crm_can_edit_business_record('{CDM}')", "Viewer gained edit access")
            + check("not public.crm_is_any_business_admin()", "Viewer gained global admin")
            + check("(select count(*) from public.crm_accounts) = 3", "Viewer cannot read CDM accounts")
            + check("(select count(*) from public.crm_business_unit_assignment_queue) = 0", "Viewer can read admin queue")
            + check_affected(
                "update public.crm_accounts set name = 'Denied'", 0, "Viewer updated accounts",
            )
            + check_affected(
                "delete from public.crm_accounts", 0, "Viewer deleted accounts",
            )
            + check_affected(
                "update public.crm_business_units set name = 'Denied'", 0, "Viewer changed a company",
            )
            + expect_denied(f"insert into public.crm_accounts values (99, '{CDM}', null, 'Denied');")
        )

    def test_unrestricted_admin_can_manage_only_the_member_company(self):
        self.run_sql(
            as_user("admin")
            + check(f"public.crm_has_business_unit_access('{CDM}', array['admin'])", "Admin lost role")
            + check(f"not public.crm_has_business_unit_access('{FOREIGN}')", "Admin gained foreign access")
            + check("public.crm_is_any_business_admin()", "Existing admin cannot use admin helper")
            + check("(select count(*) from public.crm_accounts) = 3", "Admin sees wrong accounts")
            + check("(select count(*) from public.crm_business_unit_assignment_queue) = 1", "Admin lost queue access")
            + f"insert into public.crm_accounts values (99, '{CDM}', null, 'Created');\n"
            + check_affected(
                "update public.crm_accounts set name = 'Changed' where id = 99",
                1, "Admin cannot update CDM account",
            )
            + check_affected(
                "delete from public.crm_accounts where id = 99", 1, "Admin cannot delete CDM account",
            )
            + check_affected(
                "update public.crm_business_units set name = 'Changed'", 1, "Admin company update escaped membership",
            )
            + expect_denied(f"insert into public.crm_accounts values (99, '{FOREIGN}', null, 'Denied');")
            + expect_denied(f"update public.crm_accounts set business_unit_id = '{FOREIGN}' where id = 1;")
        )

    def test_missing_inactive_and_foreign_memberships_are_denied(self):
        for user in ("no_membership", "inactive", "foreign"):
            with self.subTest(user=user):
                self.run_sql(
                    as_user(user) + self.denied_company_access()
                    + check("not public.crm_is_any_business_admin()", "Invalid membership gained admin")
                    + check("(select count(*) from public.crm_business_unit_assignment_queue) = 0", "Invalid membership sees queue")
                )

    def test_explicit_ops_and_mes_lists_do_not_grant_sales(self):
        for user in ("ops", "mes"):
            with self.subTest(user=user):
                self.run_sql(
                    as_user(user) + self.denied_company_access()
                    + check("not public.crm_is_any_business_admin()", "Non-Sales module gained Sales admin")
                    + check("(select count(*) from public.crm_business_unit_assignment_queue) = 0", "Non-Sales module sees queue")
                )

    def test_explicit_mixed_case_sales_still_allows_member_access(self):
        self.run_sql(
            as_user("sales")
            + check(f"public.crm_has_business_unit_access('{CDM}', array['admin'])", "Explicit Sales read denied")
            + check(f"public.crm_can_edit_business_record('{CDM}')", "Explicit Sales edit denied")
            + check("public.crm_is_any_business_admin()", "Explicit Sales admin denied")
            + check("(select count(*) from public.crm_accounts) = 3", "Explicit Sales RLS denied")
            + check_affected(
                "update public.crm_accounts set name = 'Updated'", 3, "Explicit Sales cannot update member accounts",
            )
        )

    def test_foreign_request_header_denies_scoped_access_but_keeps_global_queue_semantics(self):
        self.run_sql(
            as_user("admin", FOREIGN) + self.denied_company_access()
            + check("public.crm_is_any_business_admin()", "Global admin predicate changed header semantics")
            + check("(select count(*) from public.crm_business_unit_assignment_queue) = 1", "Global queue changed header semantics")
        )

    def test_null_auth_uid_cannot_read_write_or_be_admin(self):
        self.run_sql(
            as_user(None) + self.denied_company_access()
            + check("not public.crm_is_any_business_admin()", "NULL user gained admin")
            + check("(select count(*) from public.crm_business_unit_assignment_queue) = 0", "NULL user sees queue")
        )

    def test_sales_rep_owner_and_marketing_opt_in_constraints_remain(self):
        self.run_sql(
            as_user("sales_rep")
            + check(f"public.crm_can_edit_business_record('{CDM}', '{USERS['sales_rep']}')", "Rep cannot edit owned row")
            + check(f"public.crm_can_edit_business_record('{CDM}')", "Rep cannot edit unassigned row")
            + check(f"not public.crm_can_edit_business_record('{CDM}', '{USERS['sales']}')", "Rep can edit another owner")
            + check_affected(
                "update public.crm_accounts set name = 'Rep update'", 2, "Rep owner RLS changed",
            )
            + expect_denied(f"update public.crm_accounts set owner_user_id = '{USERS['sales']}' where id = 1;")
            + as_user("marketing")
            + check(f"not public.crm_can_edit_business_record('{CDM}')", "Marketing bypassed opt-in")
            + check(f"public.crm_can_edit_business_record('{CDM}', null, true)", "Marketing opt-in denied")
            + check_affected(
                "update public.crm_accounts set name = 'Denied'", 0, "Marketing changed core accounts",
            )
            + check_affected(
                "update public.crm_campaigns set name = 'Marketing update'", 1, "Marketing campaign RLS changed",
            )
            + as_user("manager")
            + check(f"public.crm_can_edit_business_record('{CDM}', '{USERS['sales']}')", "Manager cannot edit")
            + check("not public.crm_is_any_business_admin()", "Manager gained admin")
        )

    def test_ops_helper_keeps_its_explicit_module_requirement(self):
        self.run_sql(
            as_user("admin")
            + check(f"not public.crm_has_ops_business_unit_access('{CDM}')", "Unrestricted user gained OPS helper access")
            + as_user("ops")
            + check(f"public.crm_has_ops_business_unit_access('{CDM}')", "Explicit OPS lost helper access")
        )

    def test_rerun_preserves_data_function_ownership_security_and_acls(self):
        metadata = """
select oid, proname, proowner, proacl, prosecdef, provolatile, proconfig,
       pg_get_function_arguments(oid) as arguments,
       pg_get_function_result(oid) as result
from pg_proc where pronamespace = current_schema()::regnamespace
"""
        definitions = """
select proname, pg_get_functiondef(oid) as definition from pg_proc
where pronamespace = current_schema()::regnamespace
"""
        self.run_sql(
            "create table original_rows as " + row_snapshot() + ";\n"
            + "create table original_metadata as " + metadata + ";\n"
            + "create table original_definitions as " + definitions + ";\n"
            + self.migration
            + "create table first_definitions as " + definitions + ";\n"
            + self.migration
            + "create table final_rows as " + row_snapshot() + ";\n"
            + "create table final_metadata as " + metadata + ";\n"
            + "create table final_definitions as " + definitions + ";\n"
            + check(same_rows("original_rows", "final_rows"), "Migration mutated business data or memberships")
            + check(same_rows("original_metadata", "final_metadata"), "Migration changed function ownership, security or ACLs")
            + check(same_rows("first_definitions", "final_definitions"), "Rerun changed function definitions")
            + check(
                "(select array_agg(original.proname::text order by original.proname) "
                "from original_definitions original join final_definitions final using (proname) "
                "where original.definition <> final.definition) = "
                "array['crm_can_edit_business_record', 'crm_has_business_unit_access', 'crm_is_any_business_admin']",
                "Migration changed functions outside the three Sales helpers",
            )
            + as_user("admin")
            + check(f"public.crm_can_edit_business_record('{CDM}')", "Rerun lost unrestricted edit access"),
            migrate=False,
        )


if __name__ == "__main__":
    unittest.main()
