"""HTTP API used by the Flutter apps."""
from contextlib import asynccontextmanager
from datetime import date, datetime, timedelta, timezone
from typing import Literal
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import psycopg
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from . import calls, db, scheduler
from .auth import AuthUser, current_user
from .config import Settings, get_settings
from .gemini_provider import GeminiProvider
from .intent import ChatReply, IntentProvider, Message, ReminderDraft
from .pairing import AttemptLimiter, generate_code
from .push import get_pusher
from .rules_provider import RulesProvider
from .sarvam_provider import FallbackProvider, SarvamProvider


@asynccontextmanager
async def lifespan(app: FastAPI):
    if get_settings().database_url:
        await db.open_pool()
    yield
    await db.close_pool()


app = FastAPI(title="Mapa", version="0.1.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

_limiter = AttemptLimiter(get_settings().pairing_attempts_per_10min)


def provider(s: Settings = Depends(get_settings)) -> IntentProvider:
    if s.chat_provider == "gemini" and s.gemini_api_key:
        return FallbackProvider(GeminiProvider(), RulesProvider())
    if s.chat_provider == "sarvam" and s.sarvam_api_key:
        return FallbackProvider(SarvamProvider(), RulesProvider())
    return RulesProvider()


@app.get("/health")
async def health() -> dict:
    return {"ok": True}


# ------------------------------------------------------------------ profile

class ProfileIn(BaseModel):
    role: Literal["caretaker", "recipient"]
    display_name: str = Field(default="", max_length=40)
    language: Literal["en", "te"] = "en"
    timezone: str = "Asia/Kolkata"
    fcm_token: str | None = None


@app.put("/me/profile")
async def put_profile(body: ProfileIn, user: AuthUser = Depends(current_user)) -> dict:
    try:
        ZoneInfo(body.timezone)
    except (ZoneInfoNotFoundError, ValueError):
        raise HTTPException(422, "unknown_timezone") from None
    async with db.connection() as conn:
        await conn.execute(
            """insert into profiles (id, role, display_name, language, timezone, fcm_token)
               values (%s, %s, %s, %s, %s, %s)
               on conflict (id) do update set role = excluded.role, display_name = excluded.display_name,
                 language = excluded.language, timezone = excluded.timezone,
                 fcm_token = coalesce(excluded.fcm_token, profiles.fcm_token)""",
            (user.id, body.role, body.display_name, body.language, body.timezone, body.fcm_token))
    return {"id": str(user.id)}


class PushTokenIn(BaseModel):
    token: str = Field(min_length=20, max_length=4096)


@app.put("/me/push-token", status_code=204)
async def put_push_token(body: PushTokenIn, user: AuthUser = Depends(current_user)) -> None:
    """The phone's Firebase token, so Mapa can wake it for a call. One phone, one person:
    if someone else was signed in on this phone before, they stop receiving its calls."""
    async with db.connection() as conn:
        await conn.execute("update profiles set fcm_token = null where fcm_token = %s and id <> %s", (body.token, user.id))
        cur = await conn.execute("update profiles set fcm_token = %s where id = %s", (body.token, user.id))
        if cur.rowcount == 0:
            raise HTTPException(status.HTTP_409_CONFLICT, "no_profile")


async def _require_role(conn, user: AuthUser, role: str) -> None:
    row = await (await conn.execute("select role from profiles where id = %s", (user.id,))).fetchone()
    if row is None or row["role"] != role:
        raise HTTPException(status.HTTP_403_FORBIDDEN, f"{role}_only")


# ------------------------------------------------------------------ pairing

class CodeIn(BaseModel):
    recipient_label: str = Field(min_length=1, max_length=40)


@app.post("/pairing/codes")
async def create_code(body: CodeIn, user: AuthUser = Depends(current_user),
                      s: Settings = Depends(get_settings)) -> dict:
    async with db.connection() as conn:
        await _require_role(conn, user, "caretaker")
        await conn.execute("delete from pairing_codes where expires_at < now() - interval '1 day'")
        for _ in range(8):
            code = generate_code()
            try:
                row = await (await conn.execute(
                    """insert into pairing_codes (code, caretaker_id, recipient_label, expires_at)
                       values (%s, %s, %s, now() + make_interval(mins => %s)) returning expires_at""",
                    (code, user.id, body.recipient_label.strip(), s.pairing_code_ttl_minutes))).fetchone()
                return {"code": code, "expires_at": row["expires_at"], "qr_payload": f"mapa://pair/{code}"}
            except psycopg.errors.UniqueViolation:
                await conn.rollback()
    raise HTTPException(503, "no_code_available")


class RedeemIn(BaseModel):
    code: str = Field(pattern=r"^[0-9]{6}$")


_REDEEM_ERRORS = {"invalid_code": 404, "code_used": 409, "code_expired": 410, "self_pair": 422}


@app.post("/pairing/redeem")
async def redeem(body: RedeemIn, user: AuthUser = Depends(current_user)) -> dict:
    key = str(user.id)
    if _limiter.blocked(key):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "too_many_attempts")
    async with db.connection() as conn:
        await _require_role(conn, user, "recipient")
        try:
            row = await (await conn.execute("select * from redeem_pairing_code(%s, %s)", (body.code, user.id))).fetchone()
        except psycopg.errors.RaiseException as e:
            reason = (e.diag.message_primary or "").strip()
            if reason in ("invalid_code", "code_expired"):
                _limiter.fail(key)
            raise HTTPException(_REDEEM_ERRORS.get(reason, 400), reason) from None
    _limiter.reset(key)
    return {"link_id": str(row["id"]), "caretaker_id": str(row["caretaker_id"]), "tone": row["tone"]}


# ------------------------------------------------------------------ reminder chat

class ChatIn(BaseModel):
    link_id: UUID
    messages: list[Message] = Field(min_length=1, max_length=30)


async def _caretaker_link(conn, user: AuthUser, link_id: UUID) -> dict:
    row = await (await conn.execute(
        """select l.id, l.nickname, p.timezone from care_links l join profiles p on p.id = l.recipient_id
            where l.id = %s and l.caretaker_id = %s""", (link_id, user.id))).fetchone()
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "link_not_found")
    return row


@app.post("/chat", response_model=ChatReply)
async def chat(body: ChatIn, user: AuthUser = Depends(current_user),
               prov: IntentProvider = Depends(provider)) -> ChatReply:
    async with db.connection() as conn:
        link = await _caretaker_link(conn, user, body.link_id)
    now = datetime.now(ZoneInfo(link["timezone"]))
    try:
        return await prov.respond(body.messages, link["nickname"], now.date(), now)
    except Exception:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, "assistant_unavailable") from None


# ------------------------------------------------------------------ reminders

class ReminderIn(BaseModel):
    link_id: UUID
    draft: ReminderDraft


@app.post("/reminders", status_code=201)
async def create_reminders(body: ReminderIn, user: AuthUser = Depends(current_user),
                           s: Settings = Depends(get_settings)) -> dict:
    d = body.draft
    ids: list[UUID] = []
    async with db.connection() as conn:
        await _caretaker_link(conn, user, body.link_id)
        for t in d.times:
            row = await (await conn.execute(
                """insert into reminders (link_id, medicine, dose, instructions, time_of_day, days_mask,
                                          start_date, end_date, source)
                   values (%s, %s, %s, %s, %s, %s, %s, %s, '{"via":"chat"}'::jsonb) returning id""",
                (body.link_id, d.medicine, d.dose, d.instructions, t, d.days_mask, d.start_date, d.end_date))).fetchone()
            ids.append(row["id"])
        await scheduler.materialize(conn, now=datetime.now(timezone.utc),
                                    horizon=timedelta(hours=s.schedule_horizon_hours), reminder_ids=ids)
    return {"reminder_ids": [str(i) for i in ids]}


@app.delete("/reminders/{reminder_id}", status_code=204)
async def delete_reminder(reminder_id: UUID, user: AuthUser = Depends(current_user)) -> None:
    async with db.connection() as conn:
        cur = await conn.execute(
            """delete from reminders r using care_links l
                where r.id = %s and l.id = r.link_id and l.caretaker_id = %s""", (reminder_id, user.id))
        if cur.rowcount == 0:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "reminder_not_found")


# ------------------------------------------------------------------ calls

async def _call_for(conn, user: AuthUser, occurrence_id: UUID, *, as_role: str) -> dict:
    """The call, if this person is the right side of it. Anyone else gets a plain 404."""
    try:
        ctx = await calls.call_context(conn, occurrence_id)
    except LookupError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "call_not_found") from None
    owner = ctx["recipient_id"] if as_role == "recipient" else ctx["caretaker_id"]
    if owner != user.id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "call_not_found")
    return ctx


@app.post("/calls/{occurrence_id}/join")
async def join_call(occurrence_id: UUID, user: AuthUser = Depends(current_user),
                    s: Settings = Depends(get_settings)) -> dict:
    """The parent answered: give their phone a token for the room Mapa is waiting in."""
    if not (s.livekit_url and s.livekit_api_key and s.livekit_api_secret):
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "calls_not_configured")
    async with db.connection() as conn:
        ctx = await _call_for(conn, user, occurrence_id, as_role="recipient")
        if ctx["status"] != "ringing":
            raise HTTPException(status.HTTP_409_CONFLICT, "not_ringing")
        age = (datetime.now(timezone.utc) - ctx["started_at"]).total_seconds()
        if age > s.ring_timeout_s + 10:
            raise HTTPException(status.HTTP_410_GONE, "call_expired")
        await conn.execute(
            "update call_occurrences set status = 'in_call', started_at = now() where id = %s and status = 'ringing'",
            (occurrence_id,))
    room = calls.room_name(occurrence_id)
    token = calls.make_join_token(s, room=room, identity=f"recipient-{user.id}", name=ctx["nickname"])
    return {"url": s.livekit_url, "token": token, "room": room}


@app.post("/calls/{occurrence_id}/decline", status_code=204)
async def decline_call(occurrence_id: UUID, user: AuthUser = Depends(current_user),
                       s: Settings = Depends(get_settings)) -> None:
    """The parent tapped "Not now": counts as unanswered, so Mapa tries once more later."""
    async with db.connection() as conn:
        ctx = await _call_for(conn, user, occurrence_id, as_role="recipient")
        if ctx["status"] != "ringing":
            return
        await scheduler.mark_no_answer(conn, occurrence_id, now=datetime.now(timezone.utc), s=s)
    await calls.delete_room(s, calls.room_name(occurrence_id))
    await calls.cancel_ring(get_pusher(s), occurrence_id)


@app.post("/calls/{occurrence_id}/call-now", status_code=202)
async def call_now(occurrence_id: UUID, user: AuthUser = Depends(current_user)) -> dict:
    """Caretaker: ring them now instead of at the scheduled time. The scheduler picks it up within seconds.
    Once per scheduled slot: the slot is then marked as called, so the button stays off."""
    async with db.connection() as conn:
        ctx = await _call_for(conn, user, occurrence_id, as_role="caretaker")
        if ctx["status"] in ("ringing", "in_call"):
            return {"status": "already_calling"}      # a second tap while it rings is not an error
        if ctx["status"] != "pending":
            raise HTTPException(status.HTTP_409_CONFLICT, "call_finished")   # a stale card: that call is over
        row = await (await conn.execute(
            "select called_early_for is not null as moved from call_occurrences where id = %s", (occurrence_id,))).fetchone()
        if row["moved"]:
            return {"status": "already_calling"}      # this is the call already moved to now
        already = await (await conn.execute(
            "select 1 from call_occurrences where reminder_id = %s and called_early_for = %s",
            (ctx["reminder_id"], ctx["scheduled_at"]))).fetchone()
        if already:
            raise HTTPException(status.HTTP_409_CONFLICT, "already_called")   # this slot was called with Call now
        await conn.execute(
            """update call_occurrences set called_early_for = scheduled_at, scheduled_at = now()
                where id = %s and status = 'pending'""", (occurrence_id,))
    return {"status": "calling"}
