"""Runs the real migration on an embedded Postgres and exercises RLS, pairing and the scheduler."""
from datetime import date, datetime, time, timedelta, timezone
from uuid import uuid4

import psycopg
import pytest
from psycopg.rows import dict_row

from mapa_server import scheduler
from mapa_server.config import Settings
from mapa_server.schedule import EVERY_DAY

UTC = timezone.utc


@pytest.fixture
async def conn(pg_uri):
    async with await psycopg.AsyncConnection.connect(pg_uri, row_factory=dict_row, autocommit=True) as c:
        yield c


from helpers import as_user, code_for, link, reminder, user  # noqa: E402


# ---------------------------------------------------------------- pairing

async def test_redeem_creates_a_link_and_burns_the_code(conn):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    code = await code_for(conn, a, "Amma")
    row = await (await conn.execute("select * from redeem_pairing_code(%s, %s)", (code, b))).fetchone()
    assert row["caretaker_id"] == a and row["recipient_id"] == b and row["nickname"] == "Amma"
    with pytest.raises(psycopg.errors.RaiseException, match="code_used"):
        await conn.execute("select * from redeem_pairing_code(%s, %s)", (code, await user(conn, "recipient", "X")))


async def test_unknown_expired_and_self_codes_fail(conn):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    with pytest.raises(psycopg.errors.RaiseException, match="invalid_code"):
        await conn.execute("select * from redeem_pairing_code('000000', %s)", (b,))
    old = await code_for(conn, a, expires="now() - interval '1 minute'")
    with pytest.raises(psycopg.errors.RaiseException, match="code_expired"):
        await conn.execute("select * from redeem_pairing_code(%s, %s)", (old, b))
    mine = await code_for(conn, a)
    with pytest.raises(psycopg.errors.RaiseException, match="self_pair"):
        await conn.execute("select * from redeem_pairing_code(%s, %s)", (mine, a))


async def test_each_new_person_gets_the_next_phone_colour(conn):
    a = await user(conn, "caretaker", "Priya")
    tones = [(await link(conn, a, await user(conn, "recipient", f"R{i}")))["tone"] for i in range(5)]
    assert tones == ["peach", "mint", "butter", "lilac", "peach"]


async def test_clients_cannot_call_privileged_functions(conn):
    a = await user(conn, "caretaker", "Priya")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        await as_user(conn, a, "select * from redeem_pairing_code('123456', %s)", (a,))
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        await as_user(conn, a, "select * from claim_due_occurrences(5)")


# ---------------------------------------------------------------- RLS

async def test_people_only_see_their_own_links_reminders_and_alerts(conn):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    stranger = await user(conn, "caretaker", "Stranger")
    lk = await link(conn, a, b)
    rid = await reminder(conn, lk["id"])
    await conn.execute("insert into alerts (caretaker_id, link_id, kind, message) values (%s, %s, 'unwell', 'x')",
                       (a, lk["id"]))

    for uid, sees in ((a, 1), (b, 1), (stranger, 0)):
        assert len(await as_user(conn, uid, "select id from care_links where id = %s", (lk["id"],))) == sees
        assert len(await as_user(conn, uid, "select id from reminders where id = %s", (rid,))) == sees
    assert len(await as_user(conn, a, "select id from alerts")) >= 1
    assert await as_user(conn, b, "select id from alerts where link_id = %s", (lk["id"],)) == []
    assert await as_user(conn, stranger, "select id from alerts where link_id = %s", (lk["id"],)) == []


async def test_only_the_caretaker_can_write_reminders(conn):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    lk = await link(conn, a, b)
    insert = ("insert into reminders (link_id, medicine, time_of_day, start_date) values (%s, 'x', '09:00', '2026-10-27')",
              (lk["id"],))
    await as_user(conn, a, *insert)
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        await as_user(conn, b, *insert)
    stranger = await user(conn, "caretaker", "S")
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        await as_user(conn, stranger, *insert)


async def test_recipient_cannot_delete_the_link_or_forge_alerts(conn):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    lk = await link(conn, a, b)
    await as_user(conn, b, "delete from care_links where id = %s", (lk["id"],))
    assert (await (await conn.execute("select count(*) n from care_links where id = %s", (lk["id"],))).fetchone())["n"] == 1
    with pytest.raises(psycopg.errors.InsufficientPrivilege):
        await as_user(conn, b, "insert into alerts (caretaker_id, link_id, kind, message) values (%s, %s, 'unwell', 'x')",
                      (a, lk["id"]))


async def test_you_can_read_the_person_you_are_linked_to_but_not_strangers(conn):
    a, b, s = (await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma"),
               await user(conn, "recipient", "Stranger"))
    await link(conn, a, b)
    names = {r["display_name"] for r in await as_user(conn, a, "select display_name from profiles")}
    assert {"Priya", "Amma"} <= names and "Stranger" not in names


# ---------------------------------------------------------------- scheduler

async def test_materialize_creates_calls_once(conn):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    lk = await link(conn, a, b)
    rid = await reminder(conn, lk["id"], at=time(9, 0))
    now = datetime(2026, 10, 27, 0, 0, tzinfo=UTC)
    n1 = await scheduler.materialize(conn, now=now, horizon=timedelta(hours=48), reminder_ids=[rid])
    n2 = await scheduler.materialize(conn, now=now, horizon=timedelta(hours=48), reminder_ids=[rid])
    assert n1 == 2 and n2 == 0
    times = [r["scheduled_at"] for r in await (await conn.execute(
        "select scheduled_at from call_occurrences where reminder_id = %s order by 1", (rid,))).fetchall()]
    assert times == [datetime(2026, 10, 27, 3, 30, tzinfo=UTC), datetime(2026, 10, 28, 3, 30, tzinfo=UTC)]


async def test_materialize_respects_the_recipients_timezone_and_end_date(conn):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma", tz="America/New_York")
    lk = await link(conn, a, b)
    rid = await reminder(conn, lk["id"], at=time(9, 0), end=date(2026, 10, 27))
    await scheduler.materialize(conn, now=datetime(2026, 10, 27, 0, 0, tzinfo=UTC), horizon=timedelta(hours=72),
                                reminder_ids=[rid])
    rows = await (await conn.execute("select scheduled_at from call_occurrences where reminder_id = %s", (rid,))).fetchall()
    assert [r["scheduled_at"] for r in rows] == [datetime(2026, 10, 27, 13, 0, tzinfo=UTC)]  # 9am EDT


async def test_claim_hands_each_due_call_out_once(conn):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    rid = await reminder(conn, (await link(conn, a, b))["id"])
    await conn.execute("insert into call_occurrences (reminder_id, scheduled_at) values (%s, now() - interval '1 minute')", (rid,))
    await conn.execute("insert into call_occurrences (reminder_id, scheduled_at) values (%s, now() + interval '1 hour')", (rid,))
    mine = lambda rows: [o for o in rows if o["reminder_id"] == rid]  # other tests share this database
    first = mine(await scheduler.claim_due(conn, limit=1000))
    assert len(first) == 1 and first[0]["status"] == "ringing"  # the future call is left alone
    assert mine(await scheduler.claim_due(conn, limit=1000)) == []  # and nothing is handed out twice


async def _ringing(conn, medicine="BP tablet", attempt=1):
    a, b = await user(conn, "caretaker", "Priya"), await user(conn, "recipient", "Amma")
    rid = await reminder(conn, (await link(conn, a, b))["id"], medicine=medicine)
    occ = (await (await conn.execute(
        "insert into call_occurrences (reminder_id, scheduled_at, status, attempt) values (%s, now(), 'ringing', %s) returning id",
        (rid, attempt))).fetchone())["id"]
    return a, rid, occ


async def test_no_answer_redials_once_then_alerts(conn):
    s, now = Settings(), datetime(2026, 10, 27, 4, 0, tzinfo=UTC)
    a, rid, occ = await _ringing(conn, attempt=1)
    await scheduler.mark_no_answer(conn, occ, now=now, s=s)
    retry = await (await conn.execute("select * from call_occurrences where reminder_id = %s and attempt = 2", (rid,))).fetchone()
    assert retry["status"] == "pending" and retry["scheduled_at"] == now + timedelta(minutes=10)
    assert (await (await conn.execute("select count(*) n from alerts where caretaker_id = %s", (a,))).fetchone())["n"] == 0

    await scheduler.mark_no_answer(conn, retry["id"], now=now + timedelta(minutes=10), s=s)
    alerts = await (await conn.execute("select kind, message from alerts where caretaker_id = %s", (a,))).fetchall()
    assert alerts == [{"kind": "no_answer", "message": "Amma didn't pick up"}]


async def test_result_closes_the_call_and_raises_the_right_alerts(conn):
    a, rid, occ = await _ringing(conn, medicine="Metformin")
    kinds = await scheduler.record_result(
        conn, occ, medicine_status="not_taken", wellbeing="unwell", note="dizzy",
        transcript=[{"who": "mapa", "text": "Did you take it?"}], duration_s=42, now=datetime.now(UTC))
    assert kinds == ["unwell", "missed_dose"]
    assert (await (await conn.execute("select status from call_occurrences where id = %s", (occ,))).fetchone())["status"] == "completed"
    msgs = {r["message"] for r in await (await conn.execute("select message from alerts where caretaker_id = %s", (a,))).fetchall()}
    assert msgs == {"Amma said they aren't feeling well", "Amma hasn't taken Metformin"}


async def test_a_good_call_raises_no_alerts(conn):
    a, _rid, occ = await _ringing(conn)
    assert await scheduler.record_result(conn, occ, medicine_status="taken", wellbeing="good", note=None,
                                         transcript=[], duration_s=30, now=datetime.now(UTC)) == []


async def test_two_schedulers_never_claim_the_same_call(pg_uri):
    async with await psycopg.AsyncConnection.connect(pg_uri, row_factory=dict_row, autocommit=True) as setup:
        a, b = await user(setup, "caretaker", "Priya"), await user(setup, "recipient", "Amma")
        rid = await reminder(setup, (await link(setup, a, b))["id"])
        for i in range(6):
            await setup.execute(
                "insert into call_occurrences (reminder_id, scheduled_at) values (%s, now() - make_interval(mins => %s))",
                (rid, i + 1))
    async with (await psycopg.AsyncConnection.connect(pg_uri, row_factory=dict_row) as c1,
                await psycopg.AsyncConnection.connect(pg_uri, row_factory=dict_row) as c2):
        # Both transactions are open at once; each takes a few and must not overlap.
        got1 = {o["id"] for o in await scheduler.claim_due(c1, limit=1000) if o["reminder_id"] == rid}
        got2 = {o["id"] for o in await scheduler.claim_due(c2, limit=1000) if o["reminder_id"] == rid}
        await c1.rollback()
        await c2.rollback()
    assert len(got1) == 6 and got2 == set()
