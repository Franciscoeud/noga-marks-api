"""Regression for the real message-template migration block in 0089.

Run against an isolated PostgreSQL test database (never production):
    CRM_MIGRATION_TEST_DSN=<test DSN> python -m unittest discover -s supabase/tests -v

Set CRM_MIGRATION_TEST_PSQL to the psql executable if it is not on PATH.
Each test uses an independently named schema inside a transaction and rolls back
all fixture data and DDL. No Supabase services or application data are needed.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest
from uuid import uuid4


MIGRATIONS = Path(__file__).resolve().parents[1] / "migrations"
BEGIN_MARKER = "-- BEGIN CRM MESSAGE TEMPLATE SCOPE MIGRATION"
END_MARKER = "-- END CRM MESSAGE TEMPLATE SCOPE MIGRATION"
UNIT_A = "10000000-0000-0000-0000-000000000001"
UNIT_B = "10000000-0000-0000-0000-000000000002"
ACCOUNT_A = "20000000-0000-0000-0000-000000000001"
ACCOUNT_B = "20000000-0000-0000-0000-000000000002"
CUSTOMER_A = "20000000-0000-0000-0000-000000000003"
CUSTOMER_B = "20000000-0000-0000-0000-000000000004"


def migration_block():
    source = (MIGRATIONS / "0089_crm_business_units_security.sql").read_text(
        encoding="utf-8"
    )
    if source.count(BEGIN_MARKER) != 1 or source.count(END_MARKER) != 1:
        raise AssertionError("0089 must contain exactly one template-scope block")
    return source.split(BEGIN_MARKER, 1)[1].split(END_MARKER, 1)[0]


def old_index():
    source = (
        MIGRATIONS / "0029_crm_account_scoping_and_brave_templates.sql"
    ).read_text(encoding="utf-8")
    match = re.search(
        r"create unique index if not exists uq_crm_message_templates_scope\b.*?;",
        source,
        re.DOTALL | re.IGNORECASE,
    )
    if not match:
        raise AssertionError("Could not find the original 0029 scope index")
    return match.group(0)


def check(condition, message):
    return (
        "do $assert$ begin if ("
        + condition
        + ") is not true then raise exception '"
        + message.replace("'", "''")
        + "'; end if; end $assert$;"
    )


def expect_unique_violation(sql):
    # An exception block is a PostgreSQL subtransaction: the failed migration
    # must restore both records and the index it replaced.
    return f"""
do $expected_error$
begin
  begin
    execute $migration_under_test${sql}$migration_under_test$;
    raise exception 'Expected a unique_violation, but the operation succeeded';
  exception when unique_violation then
    null;
  end;
end $expected_error$;
"""


class MessageTemplateScopeMigrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dsn = os.environ.get("CRM_MIGRATION_TEST_DSN")
        if not cls.dsn:
            raise unittest.SkipTest("CRM_MIGRATION_TEST_DSN is not configured")
        cls.psql = os.environ.get("CRM_MIGRATION_TEST_PSQL") or shutil.which("psql")
        if not cls.psql:
            raise RuntimeError("Install psql or set CRM_MIGRATION_TEST_PSQL")
        cls.block = migration_block()
        cls.original_index = old_index()

    def run_sql(self, body):
        schema = "crm_0089_test_" + uuid4().hex
        fixture = f"""
begin;
set local statement_timeout = '15s';
create schema {schema};
set local search_path = {schema}, pg_catalog;
create table public.crm_legacy_account_business_units (
  account_id uuid primary key,
  business_unit_id uuid not null
);
create table public.crm_message_templates (
  id integer primary key,
  business_unit_id uuid,
  account_id uuid,
  channel text not null default 'whatsapp',
  language text not null default 'es',
  product_interest_id uuid,
  source_channel text,
  requested_info_type text,
  template_key text not null default 'default_whatsapp',
  body text not null
);
{self.original_index}
insert into public.crm_legacy_account_business_units values
  ('{ACCOUNT_A}', '{UNIT_A}'), ('{ACCOUNT_B}', '{UNIT_B}');
insert into public.crm_message_templates (id, account_id, body) values
  (1, null, 'TEST global'),
  (2, '{ACCOUNT_A}', 'TEST empresa A'),
  (3, '{ACCOUNT_B}', 'TEST empresa B');
create table original_rows as select * from public.crm_message_templates;
"""
        script = (fixture + body + "\nrollback;\n").replace("public.", schema + ".")
        result = subprocess.run(
            [
                self.psql, "-X", "--no-password", "--set=ON_ERROR_STOP=1",
                "--quiet", "--dbname", self.dsn,
            ],
            input=script,
            text=True,
            encoding="utf-8",
            capture_output=True,
            timeout=30,
            env={**os.environ, "PGCLIENTENCODING": "UTF8"},
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)

    def test_original_index_reproduces_reported_collision_without_data_loss(self):
        update = """
update public.crm_message_templates record
set business_unit_id = mapping.business_unit_id, account_id = null
from public.crm_legacy_account_business_units mapping
where record.account_id = mapping.account_id;
"""
        self.run_sql(
            expect_unique_violation(update)
            + check(
                "not exists (select * from public.crm_message_templates except "
                "select * from original_rows)",
                "Failed old migration changed template data",
            )
        )

    def test_migration_preserves_content_and_maps_each_company(self):
        self.run_sql(
            self.block
            + check(
                "(select count(*) from public.crm_message_templates) = 3 "
                "and not exists (select id, body from original_rows except "
                "select id, body from public.crm_message_templates)",
                "Template IDs or contents were lost",
            )
            + check(
                f"(select business_unit_id = '{UNIT_A}' and account_id is null "
                "from public.crm_message_templates where id = 2) "
                f"and (select business_unit_id = '{UNIT_B}' and account_id is null "
                "from public.crm_message_templates where id = 3) "
                "and (select business_unit_id is null and account_id is null "
                "from public.crm_message_templates where id = 1)",
                "Template tenant mapping is incorrect",
            )
        )

    def test_same_scope_is_allowed_in_distinct_companies(self):
        self.run_sql(
            self.block
            + f"""
insert into public.crm_message_templates (id, business_unit_id, template_key, body)
values (4, '{UNIT_A}', 'TEST new', 'A'), (5, '{UNIT_B}', 'TEST new', 'B');
"""
            + check(
                "(select count(*) from public.crm_message_templates) = 5",
                "Distinct companies incorrectly share a unique scope",
            )
        )

    def test_duplicate_scope_in_same_company_is_rejected(self):
        self.run_sql(
            self.block
            + expect_unique_violation(
                "insert into public.crm_message_templates "
                "(id, business_unit_id, template_key, body) "
                f"values (4, '{UNIT_A}', 'DEFAULT_WHATSAPP', 'TEST duplicate');"
            )
            + check(
                "(select count(*) from public.crm_message_templates) = 3",
                "Duplicate company template was inserted",
            )
        )

    def test_customer_specific_templates_remain_distinct(self):
        self.run_sql(
            self.block
            + f"""
insert into public.crm_message_templates (id, business_unit_id, account_id, body)
values (4, '{UNIT_A}', '{CUSTOMER_A}', 'TEST customer A'),
       (5, '{UNIT_A}', '{CUSTOMER_B}', 'TEST customer B');
"""
            + self.block
            + check(
                "(select count(*) from public.crm_message_templates "
                "where id in (4, 5) and account_id is not null) = 2",
                "Customer account scopes were collapsed",
            )
        )

    def test_null_company_scope_still_rejects_duplicates(self):
        self.run_sql(
            self.block
            + expect_unique_violation(
                "insert into public.crm_message_templates (id, body) "
                "values (4, 'TEST duplicate global');"
            )
            + check(
                "(select count(*) from public.crm_message_templates) = 3",
                "NULL-company scopes bypassed uniqueness",
            )
        )

    def test_rerun_does_not_change_records(self):
        self.run_sql(
            self.block
            + "create table first_run as select * from public.crm_message_templates;"
            + self.block
            + check(
                "not exists (select * from first_run except select * from "
                "public.crm_message_templates) and not exists (select * from "
                "public.crm_message_templates except select * from first_run)",
                "Rerunning the migration changed template records",
            )
        )

    def test_real_collision_rolls_back_without_deleting_templates_or_index(self):
        self.run_sql(
            f"""
insert into public.crm_legacy_account_business_units
values ('{CUSTOMER_A}', '{UNIT_A}');
insert into public.crm_message_templates (id, account_id, body)
values (4, '{CUSTOMER_A}', 'TEST second legacy account for company A');
create table before_collision as select * from public.crm_message_templates;
create table before_index as
select pg_get_indexdef('uq_crm_message_templates_scope'::regclass) as definition;
"""
            + expect_unique_violation(self.block)
            + check(
                "not exists (select * from before_collision except select * from "
                "public.crm_message_templates) and not exists (select * from "
                "public.crm_message_templates except select * from before_collision)",
                "Real collision deleted or modified an existing template",
            )
            + check(
                "(select definition from before_index) = "
                "pg_get_indexdef('uq_crm_message_templates_scope'::regclass)",
                "Real collision failed to restore the original unique index",
            )
        )


if __name__ == "__main__":
    unittest.main()
