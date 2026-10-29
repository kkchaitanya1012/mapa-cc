"""Shared helpers for tests that use the embedded Postgres."""
from datetime import date, time
from uuid import uuid4

from mapa_server.schedule import EVERY_DAY


async def user(conn, role: str, name: str, tz: str = "Asia/Kolkata"):
    uid = uuid4()
    await conn.execute("insert into auth.users (id) values (%s)", (uid,))
    await conn.execute("insert into profiles (id, role, display_name, timezone) values (%s, %s, %s, %s)",
                       (uid, role, name, tz))
    return uid


async def code_for(conn, caretaker, label="Amma", code=None, expires="now() + interval '15 minutes'"):
    code = code or f"{uuid4().int % 1_000_000:06d}"
    await conn.execute(
        f"insert into pairing_codes (code, caretaker_id, recipient_label, expires_at) values (%s, %s, %s, {expires})",
        (code, caretaker, label))
    return code


async def link(conn, caretaker, recipient, label="Amma"):
    code = await code_for(conn, caretaker, label)
    return await (await conn.execute("select * from redeem_pairing_code(%s, %s)", (code, recipient))).fetchone()


async def as_user(conn, uid, sql, params=None):
    """Run a query as a signed-in client (RLS applies)."""
    async with conn.transaction():
        await conn.execute("set local role authenticated")
        await conn.execute("select set_config('request.jwt.claim.sub', %s, true)", (str(uid),))
        cur = await conn.execute(sql, params)
        return await cur.fetchall() if cur.description else []


async def reminder(conn, link_id, *, at=time(9, 0), start=None, end=None, medicine="BP tablet"):
    return (await (await conn.execute(
        """insert into reminders (link_id, medicine, time_of_day, days_mask, start_date, end_date)
           values (%s, %s, %s, %s, %s, %s) returning id""",
        (link_id, medicine, at, EVERY_DAY, start or date(2026, 10, 1), end))).fetchone())["id"]
