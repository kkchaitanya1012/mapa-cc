import pathlib
import shutil
import tempfile

import psycopg
import pytest

MIGRATIONS = sorted((pathlib.Path(__file__).parents[2] / "supabase/migrations").glob("*.sql"))

# The pieces of Supabase the migration expects to already exist.
SUPABASE_STUB = """
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create role anon nologin; create role authenticated nologin; create role service_role nologin;
create publication supabase_realtime;
grant usage on schema auth, public to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated;
"""
CLIENT_GRANTS = """
grant select, insert, update, delete on all tables in schema public to authenticated;
"""


@pytest.fixture(scope="session")
def pg_uri():
    pgserver = pytest.importorskip("pgserver")
    root = tempfile.mkdtemp(prefix="mapa-pg-")
    srv = pgserver.get_server(root, cleanup_mode="delete")
    uri = srv.get_uri()
    with psycopg.connect(uri, autocommit=True) as c:
        c.execute(SUPABASE_STUB)
        for m in MIGRATIONS:
            c.execute(m.read_text())
        c.execute(CLIENT_GRANTS)
    yield uri
    srv.cleanup()
    shutil.rmtree(root, ignore_errors=True)
