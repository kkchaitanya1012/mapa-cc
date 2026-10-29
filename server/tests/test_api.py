from contextlib import asynccontextmanager
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from mapa_server import api, db
from mapa_server.auth import AuthUser, current_user
from mapa_server.config import Settings, get_settings

USER = AuthUser(uuid4(), "t")
LINK = uuid4()


class Cur:
    def __init__(self, row=None, rows=None):
        self.row, self.rows, self.rowcount = row, rows or [], 1

    async def fetchone(self):
        return self.row

    async def fetchall(self):
        return self.rows


class FakeConn:
    """Answers the one query /chat makes: 'is this my link?'"""

    def __init__(self, owns_link=True):
        self.owns = owns_link

    async def execute(self, sql, params=None):
        if "from care_links l join profiles" in sql:
            return Cur({"id": LINK, "nickname": "Amma", "timezone": "Asia/Kolkata"} if self.owns else None)
        raise AssertionError(f"unexpected query: {sql[:60]}")


def client(owns_link=True) -> TestClient:
    @asynccontextmanager
    async def fake_connection():
        yield FakeConn(owns_link)

    api.app.dependency_overrides[current_user] = lambda: USER
    # never touch the real .env or the network from these tests: offline parser only
    api.app.dependency_overrides[get_settings] = lambda: Settings(_env_file=None, chat_provider="rules")
    db.connection = fake_connection  # type: ignore[assignment]
    return TestClient(api.app)


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    api.app.dependency_overrides.clear()


def test_health_needs_no_login():
    assert TestClient(api.app).get("/health").json() == {"ok": True}


def test_chat_requires_a_token():
    r = TestClient(api.app).post("/chat", json={"link_id": str(LINK), "messages": [{"role": "user", "text": "hi"}]})
    assert r.status_code == 401


def test_chat_returns_a_clarifying_question():
    r = client().post("/chat", json={"link_id": str(LINK), "messages": [
        {"role": "user", "text": "BP tablet every morning after breakfast for a month"}]})
    body = r.json()
    assert r.status_code == 200 and body["type"] == "clarify"
    assert body["clarify"]["field"] == "time" and "Amma" in body["clarify"]["question"]


def test_chat_rejects_off_topic_without_generating_text():
    r = client().post("/chat", json={"link_id": str(LINK), "messages": [
        {"role": "user", "text": "tell me a joke"}]})
    assert r.json() == {"type": "reject", "draft": None, "clarify": None}


def test_chat_on_someone_elses_link_is_404():
    r = client(owns_link=False).post("/chat", json={"link_id": str(LINK), "messages": [
        {"role": "user", "text": "BP tablet at 9 am for 7 days"}]})
    assert r.status_code == 404


def test_redeem_rejects_malformed_codes():
    assert client().post("/pairing/redeem", json={"code": "12ab56"}).status_code == 422
    assert client().post("/pairing/redeem", json={"code": "12345"}).status_code == 422


def test_oversized_chat_is_rejected():
    r = client().post("/chat", json={"link_id": str(LINK), "messages": [{"role": "user", "text": "x" * 501}]})
    assert r.status_code == 422
