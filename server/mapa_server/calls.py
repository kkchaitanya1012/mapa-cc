"""Calls: LiveKit tokens, dispatching the voice agent, and tidying up calls
that nobody answered or that got stuck."""
import json
import logging
from datetime import datetime, timedelta
from uuid import UUID

from livekit import api
from psycopg import AsyncConnection

from . import db
from .config import Settings, get_settings
from .push import Pusher, get_pusher

log = logging.getLogger("mapa.calls")


def room_name(occurrence_id: UUID | str) -> str:
    return f"mapa-{occurrence_id}"


def make_join_token(s: Settings, *, room: str, identity: str, name: str, ttl_s: int = 900) -> str:
    """A short-lived token letting one person join one room, audio only."""
    grants = api.VideoGrants(room_join=True, room=room, can_publish=True, can_subscribe=True,
                             can_publish_data=True)
    return (api.AccessToken(s.livekit_api_key, s.livekit_api_secret)
            .with_identity(identity).with_name(name).with_grants(grants)
            .with_ttl(timedelta(seconds=ttl_s)).to_jwt())


async def call_context(conn: AsyncConnection, occurrence_id: UUID) -> dict:
    """Everything the voice agent and the join check need to know about a call."""
    cur = await conn.execute(
        """select o.id, o.status, o.attempt, o.started_at, o.scheduled_at,
                  r.id as reminder_id, r.medicine, r.dose,
                  l.id as link_id, l.nickname, l.caretaker_id, l.recipient_id,
                  rp.language, rp.display_name as recipient_name, rp.fcm_token as recipient_fcm,
                  cp.display_name as caretaker_name
             from call_occurrences o
             join reminders r on r.id = o.reminder_id
             join care_links l on l.id = r.link_id
             join profiles rp on rp.id = l.recipient_id
             join profiles cp on cp.id = l.caretaker_id
            where o.id = %s""", (occurrence_id,))
    row = await cur.fetchone()
    if row is None:
        raise LookupError(f"occurrence {occurrence_id} not found")
    return row


def agent_metadata(ctx: dict) -> str:
    """What the agent is told when it joins the room. No secrets, no ids it doesn't need."""
    return json.dumps({
        "occurrence_id": str(ctx["id"]), "name": ctx["nickname"], "medicine": ctx["medicine"],
        "dose": ctx["dose"], "language": ctx["language"], "caretaker": ctx["caretaker_name"] or "your family",
        "attempt": ctx["attempt"],
    })


class LiveKitDispatcher:
    """Starts a call: create the room and send the voice agent into it. The phone
    learns about the call from the database (realtime), and joins when answered."""

    def __init__(self, s: Settings | None = None, pusher: Pusher | None = None) -> None:
        self.s = s or get_settings()
        self.pusher = pusher or get_pusher(self.s)

    async def dispatch(self, occurrence: dict) -> None:
        s = self.s
        if not (s.livekit_url and s.livekit_api_key and s.livekit_api_secret):
            raise RuntimeError("LiveKit is not configured")
        room = room_name(occurrence["id"])
        async with db.connection() as conn:
            ctx = await call_context(conn, occurrence["id"])
            await conn.execute("update call_occurrences set room_name = %s where id = %s", (room, occurrence["id"]))
        meta = agent_metadata(ctx)
        lk = api.LiveKitAPI(s.livekit_url, s.livekit_api_key, s.livekit_api_secret)
        try:
            await lk.room.create_room(api.CreateRoomRequest(
                name=room, empty_timeout=120, departure_timeout=20, max_participants=3, metadata=meta))
            await lk.agent_dispatch.create_dispatch(
                api.CreateAgentDispatchRequest(agent_name=s.agent_name, room=room, metadata=meta))
        finally:
            await lk.aclose()
        log.info("ringing %s for occurrence %s", ctx["nickname"], occurrence["id"])
        await ring_phone(self.pusher, ctx)


async def delete_room(s: Settings, room: str) -> None:
    """Best effort: closing the room hangs up anyone still in it."""
    if not (s.livekit_url and s.livekit_api_key):
        return
    lk = api.LiveKitAPI(s.livekit_url, s.livekit_api_key, s.livekit_api_secret)
    try:
        await lk.room.delete_room(api.DeleteRoomRequest(room=room))
    except Exception:
        log.debug("room %s already gone", room)
    finally:
        await lk.aclose()


async def find_unanswered(conn: AsyncConnection, *, now: datetime, ring_ttl_s: int, call_cap_min: int) -> list[dict]:
    """Calls that rang too long, or that have been 'in call' longer than any call should be."""
    cur = await conn.execute(
        """select id, status, room_name from call_occurrences
            where (status = 'ringing' and started_at < %(ring)s)
               or (status = 'in_call'  and started_at < %(cap)s)""",
        {"ring": now - timedelta(seconds=ring_ttl_s), "cap": now - timedelta(minutes=call_cap_min + 3)})
    return await cur.fetchall()


async def _forget_dead_token(token: str) -> None:
    async with db.connection() as conn:
        await conn.execute("update profiles set fcm_token = null where fcm_token = %s", (token,))


async def ring_phone(pusher: Pusher, ctx: dict) -> None:
    """Wake the parent's phone so it can show the call even when locked or closed.
    Best effort: if it fails, the call still rings inside the open app."""
    token = ctx.get("recipient_fcm")
    if not token:
        log.info("push skipped: %s's phone has not registered for calls yet", ctx["nickname"])
        return
    try:
        result = await pusher.ring(token, ctx)
    except Exception:
        log.exception("push failed for occurrence %s", ctx["id"])
        return
    if result.status == "ok":
        log.info("push sent to %s's phone for occurrence %s", ctx["nickname"], ctx["id"])
    elif result.status == "dead_token":
        log.warning("push: %s's phone token is stale, forgetting it", ctx["nickname"])
        await _forget_dead_token(token)
    else:
        log.warning("push not sent for occurrence %s: %s", ctx["id"], result.detail)


async def cancel_ring(pusher: Pusher, occurrence_id: UUID | str) -> None:
    """Take the call screen down on the phone (timed out, declined, answered elsewhere)."""
    try:
        async with db.connection() as conn:
            ctx = await call_context(conn, UUID(str(occurrence_id)))
        if ctx.get("recipient_fcm"):
            await pusher.cancel(ctx["recipient_fcm"], str(occurrence_id))
    except Exception:
        log.debug("cancel push skipped for %s", occurrence_id, exc_info=True)
