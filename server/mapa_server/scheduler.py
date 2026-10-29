"""Scheduler: materialise upcoming calls, claim due ones, handle outcomes.

Run as its own process: `python -m mapa_server.scheduler`. Every step is safe
to repeat or run from two processes at once.
"""
import asyncio
import logging
import time
from datetime import datetime, timedelta, timezone
from typing import Protocol
from uuid import UUID
from zoneinfo import ZoneInfo

from psycopg import AsyncConnection
from psycopg.types.json import Jsonb

from . import calls, db
from .config import Settings, get_settings
from .schedule import after_no_answer, alerts_for, occurrences_between

log = logging.getLogger("mapa.scheduler")

# A reminder created a minute after its time still rings; older than this is skipped.
GRACE = timedelta(minutes=2)


class Dispatcher(Protocol):
    async def dispatch(self, occurrence: dict) -> None:
        """Start the call: create the room, dispatch the agent, push to the phone."""


class LoggingDispatcher:
    """Used before LiveKit is configured. Still wakes the parent's phone (if Firebase is set up),
    so the ringing and the lock-screen call can be tried before any voice accounts exist."""

    def __init__(self, pusher: calls.Pusher | None = None) -> None:
        self.pusher = pusher or calls.get_pusher(get_settings())

    async def dispatch(self, occurrence: dict) -> None:
        log.info("would dial occurrence %s (attempt %s)", occurrence["id"], occurrence["attempt"])
        async with db.connection() as conn:
            ctx = await calls.call_context(conn, occurrence["id"])
        await calls.ring_phone(self.pusher, ctx)


async def materialize(
    conn: AsyncConnection, *, now: datetime, horizon: timedelta, reminder_ids: list[UUID] | None = None
) -> int:
    """Create pending call rows for active reminders over the next `horizon`."""
    window_start, window_end = now - GRACE, now + horizon
    rows = await (await conn.execute(
        """select r.id, r.time_of_day, r.days_mask, r.start_date, r.end_date, p.timezone
             from reminders r
             join care_links l on l.id = r.link_id
             join profiles p on p.id = l.recipient_id
            where r.active
              and r.start_date <= %(last_day)s
              and (r.end_date is null or r.end_date >= %(first_day)s)
              and (%(ids)s::uuid[] is null or r.id = any(%(ids)s::uuid[]))""",
        {"last_day": window_end.date() + timedelta(days=1),
         "first_day": window_start.date() - timedelta(days=1), "ids": reminder_ids},
    )).fetchall()

    pairs: list[tuple[UUID, datetime]] = []
    for r in rows:
        for at in occurrences_between(
            time_of_day=r["time_of_day"], days_mask=r["days_mask"], start_date=r["start_date"],
            end_date=r["end_date"], tz=ZoneInfo(r["timezone"]),
            window_start=window_start, window_end=window_end,
        ):
            pairs.append((r["id"], at))
    if not pairs:
        return 0
    # One round trip however many calls: this runs against a remote database.
    cur = await conn.execute(
        """insert into call_occurrences (reminder_id, scheduled_at)
           select * from unnest(%s::uuid[], %s::timestamptz[])
           on conflict (reminder_id, scheduled_at, attempt) do nothing""",
        ([p[0] for p in pairs], [p[1] for p in pairs]))
    return cur.rowcount


async def claim_due(conn: AsyncConnection, limit: int = 20) -> list[dict]:
    cur = await conn.execute("select * from claim_due_occurrences(%s)", (limit,))
    return await cur.fetchall()


async def _context(conn: AsyncConnection, occurrence_id: UUID) -> dict:
    cur = await conn.execute(
        """select o.id, o.attempt, o.scheduled_at, r.id as reminder_id, r.medicine, r.time_of_day,
                  l.id as link_id, l.caretaker_id, l.nickname
             from call_occurrences o
             join reminders r on r.id = o.reminder_id
             join care_links l on l.id = r.link_id
            where o.id = %s""", (occurrence_id,))
    row = await cur.fetchone()
    if row is None:
        raise LookupError(f"occurrence {occurrence_id} not found")
    return row


async def mark_no_answer(conn: AsyncConnection, occurrence_id: UUID, *, now: datetime, s: Settings) -> None:
    """Nobody picked up: redial once after a pause, then tell the caretaker."""
    ctx = await _context(conn, occurrence_id)
    await conn.execute(
        "update call_occurrences set status = 'no_answer', ended_at = %s where id = %s", (now, occurrence_id))
    decision = after_no_answer(ctx["attempt"], s.max_attempts, now, s.retry_after_minutes)
    if decision.retry_at:
        await conn.execute(
            """insert into call_occurrences (reminder_id, scheduled_at, attempt) values (%s, %s, %s)
               on conflict do nothing""", (ctx["reminder_id"], decision.retry_at, ctx["attempt"] + 1))
    if decision.alert:
        await conn.execute(
            """insert into alerts (caretaker_id, link_id, occurrence_id, kind, message)
               values (%s, %s, %s, 'no_answer', %s)""",
            (ctx["caretaker_id"], ctx["link_id"], occurrence_id, f"{ctx['nickname']} didn't pick up"))


async def record_result(
    conn: AsyncConnection, occurrence_id: UUID, *, medicine_status: str, wellbeing: str | None,
    note: str | None, transcript: list[dict], duration_s: int | None, now: datetime,
) -> list[str]:
    """Store what was said on the call, close it, and raise any alerts. Returns alert kinds."""
    ctx = await _context(conn, occurrence_id)
    await conn.execute(
        """insert into call_results (occurrence_id, medicine_status, wellbeing, note, transcript, duration_s)
           values (%s, %s, %s, %s, %s, %s)
           on conflict (occurrence_id) do update set medicine_status = excluded.medicine_status,
             wellbeing = excluded.wellbeing, note = excluded.note,
             transcript = excluded.transcript, duration_s = excluded.duration_s""",
        (occurrence_id, medicine_status, wellbeing, note, Jsonb(transcript), duration_s))
    await conn.execute(
        "update call_occurrences set status = 'completed', ended_at = %s where id = %s", (now, occurrence_id))
    kinds: list[str] = []
    for kind, message in alerts_for(medicine_status, wellbeing, who=ctx["nickname"], medicine=ctx["medicine"]):
        await conn.execute(
            """insert into alerts (caretaker_id, link_id, occurrence_id, kind, message)
               values (%s, %s, %s, %s, %s)""",
            (ctx["caretaker_id"], ctx["link_id"], occurrence_id, kind, message))
        kinds.append(kind)
    return kinds


async def sweep_unanswered(s: Settings, now: datetime, pusher: calls.Pusher | None = None) -> int:
    """Hang up on phones that rang too long (or calls that never ended), then redial or alert."""
    async with db.connection() as conn:
        stale = await calls.find_unanswered(conn, now=now, ring_ttl_s=s.ring_timeout_s, call_cap_min=s.max_call_minutes)
        for row in stale:
            await mark_no_answer(conn, row["id"], now=now, s=s)
    for row in stale:
        if row["room_name"]:
            await calls.delete_room(s, row["room_name"])
        if pusher is not None and row["status"] == "ringing":
            await calls.cancel_ring(pusher, row["id"])   # take the call screen down on their phone
    return len(stale)


_last_materialized = 0.0
MATERIALIZE_EVERY_S = 60


async def tick(dispatcher: Dispatcher, s: Settings) -> None:
    """One pass. Ringing a due call comes first: it is the only step a person is waiting on."""
    global _last_materialized
    now = datetime.now(timezone.utc)
    async with db.connection() as conn:
        due = await claim_due(conn)
    for occ in due:
        try:
            await dispatcher.dispatch(occ)
        except Exception:
            log.exception("dispatch failed for %s", occ["id"])
            async with db.connection() as conn:
                await conn.execute("update call_occurrences set status = 'failed' where id = %s", (occ["id"],))

    swept = await sweep_unanswered(s, now, getattr(dispatcher, "pusher", None))
    if swept:
        log.info("%d call(s) went unanswered or stuck", swept)

    if time.monotonic() - _last_materialized >= MATERIALIZE_EVERY_S:
        async with db.connection() as conn:
            made = await materialize(conn, now=now, horizon=timedelta(hours=s.schedule_horizon_hours))
        _last_materialized = time.monotonic()
        if made:
            log.info("scheduled %d upcoming calls", made)


async def run_forever(dispatcher: Dispatcher | None = None, every_s: float = 4) -> None:
    s = get_settings()
    if dispatcher is None:
        live = s.livekit_url and s.livekit_api_key and s.livekit_api_secret
        dispatcher = calls.LiveKitDispatcher(s) if live else LoggingDispatcher()
        log.info("calls: %s", "LiveKit" if live else "LiveKit not configured, logging only")
    await db.open_pool()
    try:
        while True:
            try:
                await tick(dispatcher, s)
            except Exception:
                log.exception("scheduler tick failed")
            await asyncio.sleep(every_s)
    finally:
        await db.close_pool()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    asyncio.run(run_forever())
