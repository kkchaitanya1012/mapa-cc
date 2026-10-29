import json
from contextlib import asynccontextmanager
from uuid import uuid4

import httpx
import psycopg
import pytest
from fastapi.testclient import TestClient
from helpers import link, reminder, user
from psycopg.rows import dict_row

from mapa_server import api, calls, db, push
from mapa_server.auth import AuthUser, current_user

CTX = {"id": uuid4(), "nickname": "Amma", "medicine": "BP tablet", "caretaker_name": "Priya", "language": "te"}


def fake_fcm(handler):
    sa = {"project_id": "mapa-test"}
    import tempfile
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(sa, f)
    f.close()

    async def token():
        return "oauth-token"

    return push.FcmPusher(f.name, client=httpx.AsyncClient(transport=httpx.MockTransport(handler)), token_provider=token)


# ---- what goes over the wire

def test_ring_payload_is_all_strings_and_carries_only_what_the_call_screen_needs():
    p = push.ring_payload(CTX)
    assert set(p) == {"type", "occurrence_id", "name", "medicine", "caretaker", "language"}
    assert all(isinstance(v, str) for v in p.values())
    assert p["type"] == "incoming_call" and p["name"] == "Amma" and p["language"] == "te"


async def test_the_ring_is_a_high_priority_data_only_message_with_a_short_life():
    seen = {}

    def handler(req: httpx.Request) -> httpx.Response:
        seen["url"], seen["auth"], seen["body"] = str(req.url), req.headers["authorization"], json.loads(req.content)
        return httpx.Response(200, json={"name": "projects/mapa-test/messages/1"})

    r = await fake_fcm(handler).ring("device-token-123", CTX)
    assert r.status == "ok"
    assert seen["url"] == "https://fcm.googleapis.com/v1/projects/mapa-test/messages:send"
    assert seen["auth"] == "Bearer oauth-token"
    msg = seen["body"]["message"]
    assert msg["token"] == "device-token-123"
    assert "notification" not in msg            # data-only, so the app decides how to show it
    assert msg["android"] == {"priority": "HIGH", "ttl": "60s"}
    assert msg["data"]["occurrence_id"] == str(CTX["id"])


async def test_cancel_names_the_call_to_take_down():
    body = {}

    def handler(req):
        body.update(json.loads(req.content))
        return httpx.Response(200, json={})

    await fake_fcm(handler).cancel("tok", "abc")
    assert body["message"]["data"] == {"type": "call_cancelled", "occurrence_id": "abc"}


@pytest.mark.parametrize("status,payload,expected", [
    (404, {"error": {"status": "NOT_FOUND", "details": [{"errorCode": "UNREGISTERED"}]}}, "dead_token"),
    (400, {"error": {"status": "INVALID_ARGUMENT"}}, "dead_token"),
    (500, {"error": {"status": "INTERNAL"}}, "error"),
    (403, {"error": {"status": "PERMISSION_DENIED"}}, "error"),
])
async def test_failures_are_classified(status, payload, expected):
    r = await fake_fcm(lambda req: httpx.Response(status, json=payload)).ring("t", CTX)
    assert r.status == expected


async def test_a_network_failure_is_an_error_not_a_crash():
    def boom(req):
        raise httpx.ConnectError("down")

    assert (await fake_fcm(boom).ring("t", CTX)).status == "error"


async def test_without_firebase_the_null_pusher_does_nothing_and_says_so():
    assert (await push.NullPusher().ring("t", CTX)).status == "error"


# ---- the database side

@pytest.fixture
async def conn(pg_uri):
    async with await psycopg.AsyncConnection.connect(pg_uri, row_factory=dict_row, autocommit=True) as c:
        yield c


@pytest.fixture
def http(pg_uri, monkeypatch):
    @asynccontextmanager
    async def connection():
        async with await psycopg.AsyncConnection.connect(pg_uri, row_factory=dict_row) as c:
            yield c

    monkeypatch.setattr(db, "connection", connection)
    yield lambda uid: (api.app.dependency_overrides.__setitem__(current_user, lambda: AuthUser(uid, "t")), TestClient(api.app))[1]
    api.app.dependency_overrides.clear()


TOKEN = "t" * 40


async def test_registering_a_phone_stores_its_token(conn, http):
    parent = await user(conn, "recipient", "Amma")
    assert http(parent).put("/me/push-token", json={"token": TOKEN}).status_code == 204
    assert (await (await conn.execute("select fcm_token from profiles where id = %s", (parent,))).fetchone())["fcm_token"] == TOKEN


async def test_a_phone_belongs_to_one_person_at_a_time(conn, http):
    first, second = await user(conn, "recipient", "Old"), await user(conn, "recipient", "New")
    tok = "shared-" + "x" * 40
    http(first).put("/me/push-token", json={"token": tok})
    http(second).put("/me/push-token", json={"token": tok})   # same phone, new person signed in
    rows = {r["id"]: r["fcm_token"] for r in await (await conn.execute("select id, fcm_token from profiles where id = any(%s)", ([first, second],))).fetchall()}
    assert rows == {first: None, second: tok}


async def test_push_token_needs_a_real_token_and_a_profile(conn, http):
    parent = await user(conn, "recipient", "Amma")
    assert http(parent).put("/me/push-token", json={"token": "short"}).status_code == 422
    assert http(uuid4()).put("/me/push-token", json={"token": TOKEN}).status_code == 409


class Recorder:
    def __init__(self, result="ok"):
        self.sent, self.result = [], result

    async def ring(self, token, ctx):
        self.sent.append(("ring", token, str(ctx["id"])))
        return push.SendResult(self.result)

    async def cancel(self, token, occ):
        self.sent.append(("cancel", token, occ))
        return push.SendResult("ok")


async def call_for(conn, token):
    caretaker, parent = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    if token:
        await conn.execute("update profiles set fcm_token = %s where id = %s", (token, parent))
    rid = await reminder(conn, (await link(conn, caretaker, parent))["id"])
    occ = (await (await conn.execute(
        "insert into call_occurrences (reminder_id, scheduled_at, status, started_at) values (%s, now(), 'ringing', now()) returning id", (rid,))).fetchone())["id"]
    return parent, occ


async def test_ringing_wakes_the_parents_phone(conn, monkeypatch):
    monkeypatch.setattr(db, "connection", lambda: _shared(conn))
    _, occ = await call_for(conn, "phone-" + "a" * 40)
    rec = Recorder()
    ctx = await calls.call_context(conn, occ)
    await calls.ring_phone(rec, ctx)
    assert rec.sent == [("ring", "phone-" + "a" * 40, str(occ))]
    await calls.cancel_ring(rec, occ)
    assert rec.sent[-1][0] == "cancel"


async def test_a_parent_without_a_registered_phone_is_simply_not_pushed(conn, monkeypatch):
    monkeypatch.setattr(db, "connection", lambda: _shared(conn))
    _, occ = await call_for(conn, None)
    rec = Recorder()
    await calls.ring_phone(rec, await calls.call_context(conn, occ))
    assert rec.sent == []


async def test_a_dead_token_is_forgotten(conn, monkeypatch):
    monkeypatch.setattr(db, "connection", lambda: _shared(conn))
    parent, occ = await call_for(conn, "dead-" + "b" * 40)
    await calls.ring_phone(Recorder("dead_token"), await calls.call_context(conn, occ))
    assert (await (await conn.execute("select fcm_token from profiles where id = %s", (parent,))).fetchone())["fcm_token"] is None


def _shared(conn):
    @asynccontextmanager
    async def cm():
        yield conn
    return cm()


async def test_before_livekit_is_set_up_the_phone_still_rings(conn, monkeypatch):
    from mapa_server.scheduler import LoggingDispatcher
    monkeypatch.setattr(db, "connection", lambda: _shared(conn))
    _, occ = await call_for(conn, "phone-" + "c" * 40)
    rec = Recorder()
    await LoggingDispatcher(pusher=rec).dispatch({"id": occ, "attempt": 1})
    assert rec.sent == [("ring", "phone-" + "c" * 40, str(occ))]
