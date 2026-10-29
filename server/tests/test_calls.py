"""Call endpoints, tokens, and clean-up, against the embedded Postgres."""
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
import psycopg
import pytest
from fastapi.testclient import TestClient
from helpers import link, reminder, user
from psycopg.rows import dict_row

from mapa_server import api, calls, db, scheduler
from mapa_server.auth import AuthUser, current_user
from mapa_server.config import Settings, get_settings

UTC = timezone.utc
S = Settings(livekit_url="wss://test.livekit.cloud", livekit_api_key="devkey", livekit_api_secret="s" * 40,
             ring_timeout_s=45, max_call_minutes=4)


@pytest.fixture
async def conn(pg_uri):
    async with await psycopg.AsyncConnection.connect(pg_uri, row_factory=dict_row, autocommit=True) as c:
        yield c


@pytest.fixture
def http(pg_uri, monkeypatch):
    """The real API on the real database; each request gets its own connection."""
    @asynccontextmanager
    async def connection():
        async with await psycopg.AsyncConnection.connect(pg_uri, row_factory=dict_row) as c:
            yield c

    monkeypatch.setattr(db, "connection", connection)
    api.app.dependency_overrides[get_settings] = lambda: S
    yield lambda uid: (api.app.dependency_overrides.__setitem__(current_user, lambda: AuthUser(uid, "t")), TestClient(api.app))[1]
    api.app.dependency_overrides.clear()


async def ringing_call(conn, *, started_ago_s=5, status="ringing"):
    caretaker, parent = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    rid = await reminder(conn, (await link(conn, caretaker, parent))["id"], medicine="BP tablet")
    occ = (await (await conn.execute(
        """insert into call_occurrences (reminder_id, scheduled_at, status, started_at)
           values (%s, now(), %s, now() - make_interval(secs => %s)) returning id""",
        (rid, status, started_ago_s))).fetchone())["id"]
    return caretaker, parent, occ


# ---- tokens

def test_token_lets_one_person_into_one_room_and_nothing_else():
    tok = calls.make_join_token(S, room="mapa-1", identity="recipient-x", name="Amma")
    claims = jwt.decode(tok, S.livekit_api_secret, algorithms=["HS256"], options={"verify_aud": False})
    assert claims["sub"] == "recipient-x" and claims["iss"] == "devkey"
    assert claims["video"]["room"] == "mapa-1" and claims["video"]["roomJoin"] is True
    assert not claims["video"].get("roomAdmin") and not claims["video"].get("roomCreate")
    assert claims["exp"] - claims["nbf"] <= 900 + 5


# ---- join / decline / call-now

async def test_the_parent_can_join_a_ringing_call_once(conn, http):
    _, parent, occ = await ringing_call(conn)
    r = http(parent).post(f"/calls/{occ}/join")
    assert r.status_code == 200
    body = r.json()
    assert body["url"] == S.livekit_url and body["room"] == f"mapa-{occ}"
    assert jwt.decode(body["token"], S.livekit_api_secret, algorithms=["HS256"], options={"verify_aud": False})["video"]["room"] == body["room"]
    assert (await (await conn.execute("select status from call_occurrences where id = %s", (occ,))).fetchone())["status"] == "in_call"
    assert http(parent).post(f"/calls/{occ}/join").status_code == 409   # already answered


async def test_strangers_and_the_caretaker_cannot_join(conn, http):
    caretaker, _, occ = await ringing_call(conn)
    stranger = await user(conn, "recipient", "Nosy")
    assert http(stranger).post(f"/calls/{occ}/join").status_code == 404
    assert http(caretaker).post(f"/calls/{occ}/join").status_code == 404
    assert http(stranger).post(f"/calls/{uuid4()}/join").status_code == 404


async def test_a_call_that_rang_too_long_is_gone(conn, http):
    _, parent, occ = await ringing_call(conn, started_ago_s=120)
    assert http(parent).post(f"/calls/{occ}/join").status_code == 410


async def test_declining_counts_as_unanswered_and_schedules_a_retry(conn, http):
    caretaker, parent, occ = await ringing_call(conn)
    assert http(parent).post(f"/calls/{occ}/decline").status_code == 204
    assert (await (await conn.execute("select status from call_occurrences where id = %s", (occ,))).fetchone())["status"] == "no_answer"
    retry = await (await conn.execute(
        "select attempt, status from call_occurrences where reminder_id = (select reminder_id from call_occurrences where id = %s) and attempt = 2",
        (occ,))).fetchone()
    assert retry == {"attempt": 2, "status": "pending"}


async def test_call_now_moves_a_pending_call_to_now(conn, http):
    caretaker, parent, occ = await ringing_call(conn, status="pending")
    await conn.execute("update call_occurrences set scheduled_at = now() + interval '5 hours', started_at = null where id = %s", (occ,))
    assert http(parent).post(f"/calls/{occ}/call-now").status_code == 404      # only the caretaker
    assert http(caretaker).post(f"/calls/{occ}/call-now").status_code == 202
    due = (await (await conn.execute("select scheduled_at <= now() as due from call_occurrences where id = %s", (occ,))).fetchone())["due"]
    assert due
    assert http(caretaker).post(f"/calls/{occ}/call-now").status_code == 202    # still pending: harmless
    await conn.execute("update call_occurrences set status = 'in_call' where id = %s", (occ,))
    r = http(caretaker).post(f"/calls/{occ}/call-now")          # already on the call: told, not errored
    assert r.status_code == 202 and r.json() == {"status": "already_calling"}
    await conn.execute("update call_occurrences set status = 'completed' where id = %s", (occ,))
    assert http(caretaker).post(f"/calls/{occ}/call-now").status_code == 409   # that call is over


async def test_calls_need_livekit_configured(conn, http):
    _, parent, occ = await ringing_call(conn)
    api.app.dependency_overrides[get_settings] = lambda: Settings(_env_file=None)  # ignore the real .env
    assert http(parent).post(f"/calls/{occ}/join").status_code == 503


# ---- clean-up of calls nobody answered

async def test_sweep_hangs_up_on_long_rings_and_stuck_calls_but_not_fresh_ones(conn, monkeypatch):
    deleted = []

    async def fake_delete(s, room):
        deleted.append(room)

    monkeypatch.setattr(calls, "delete_room", fake_delete)
    monkeypatch.setattr(db, "connection", _owner_connection(conn))
    _, _, fresh = await ringing_call(conn, started_ago_s=10)
    _, _, long_ring = await ringing_call(conn, started_ago_s=90)
    _, _, stuck = await ringing_call(conn, started_ago_s=60 * 10, status="in_call")
    _, _, chatting = await ringing_call(conn, started_ago_s=60, status="in_call")
    await conn.execute("update call_occurrences set room_name = 'mapa-' || id::text")

    await scheduler.sweep_unanswered(S, datetime.now(UTC))

    status = lambda i: conn.execute("select status from call_occurrences where id = %s", (i,))
    assert [(await (await status(i)).fetchone())["status"] for i in (fresh, long_ring, stuck, chatting)] == [
        "ringing", "no_answer", "no_answer", "in_call"]
    assert {f"mapa-{long_ring}", f"mapa-{stuck}"} <= set(deleted)          # other tests share this database,
    assert f"mapa-{fresh}" not in deleted and f"mapa-{chatting}" not in deleted  # so check ours, not the total


def _owner_connection(shared):
    @asynccontextmanager
    async def connection():
        yield shared
    return connection


async def test_call_now_works_once_per_slot(conn, http):
    caretaker, _, occ = await ringing_call(conn, status="pending")
    await conn.execute("update call_occurrences set scheduled_at = now() + interval '5 hours', started_at = null where id = %s", (occ,))
    row = await (await conn.execute("select reminder_id, scheduled_at from call_occurrences where id = %s", (occ,))).fetchone()
    assert http(caretaker).post(f"/calls/{occ}/call-now").json() == {"status": "calling"}
    # the scheduler re-creates the original slot; Call now on it is refused
    again = await (await conn.execute(
        "insert into call_occurrences (reminder_id, scheduled_at) values (%s, %s) returning id",
        (row["reminder_id"], row["scheduled_at"]))).fetchone()
    r = http(caretaker).post(f"/calls/{again['id']}/call-now")
    assert r.status_code == 409 and r.json()["detail"] == "already_called"
