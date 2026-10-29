"""Static checks on the migration. It can't run Postgres here, so these catch
the mistakes that matter most: a table left open, or a privileged function
callable by clients."""
import re
from pathlib import Path

import sqlglot

SQL = (Path(__file__).parents[2] / "supabase/migrations/0001_init.sql").read_text()


def tables() -> list[str]:
    return re.findall(r"create table public\.(\w+)", SQL)


def test_every_table_has_row_level_security():
    assert len(tables()) == 7
    for t in tables():
        assert re.search(rf"alter table public\.{t}\s+enable row level security", SQL), t


def test_every_table_can_be_read_by_someone():
    for t in tables():
        assert re.search(rf"create policy \w+ on public\.{t}\s+for select", SQL), t


def test_clients_cannot_write_server_owned_tables():
    for t in ("call_occurrences", "call_results", "pairing_codes"):
        assert not re.search(rf"create policy \w+ on public\.{t}\s+for (insert|update|delete)", SQL), t
    assert not re.search(r"create policy \w+ on public\.alerts\s+for (insert|delete)", SQL)
    assert not re.search(r"create policy \w+ on public\.care_links\s+for insert", SQL)


def test_privileged_functions_are_not_callable_by_clients():
    for fn in ("redeem_pairing_code(text, uuid)", "claim_due_occurrences(integer)"):
        assert re.search(rf"revoke all on function public\.{re.escape(fn)} from public, anon, authenticated", SQL), fn


def test_security_definer_functions_pin_search_path():
    for body in re.findall(r"security definer(.*?)as \$\$", SQL, re.S):
        assert "set search_path" in body


def test_plain_statements_parse_as_postgres():
    # Function bodies use dollar quoting; check everything else.
    without_functions = re.sub(r"create function.*?\$\$;|create function.*?end \$\$;", "", SQL, flags=re.S)
    stmts = [s for s in sqlglot.parse(without_functions, read="postgres") if s is not None]
    assert len(stmts) > 30
