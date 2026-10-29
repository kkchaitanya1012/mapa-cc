"""Reminder chat understood by Sarvam's model, through three strict tools.

The model can only answer by calling create_reminder, ask_clarification or
reject_off_topic, so it can never chat. Every argument is validated here before
it becomes a reminder, and a message that can't be understood falls back to the
offline parser (see FallbackProvider).
"""
import json
import logging
from datetime import date, datetime, time, timedelta

import httpx
from pydantic import ValidationError

from .config import get_settings
from .intent import ChatReply, Clarify, IntentProvider, Message, ReminderDraft
from .schedule import EVERY_DAY, mask_for_days

log = logging.getLogger("mapa.chat")

BASE_V1 = "https://api.sarvam.ai/v1"
BASE_V2 = "https://api.sarvam.ai/v2"
PASSED_GRACE = timedelta(minutes=2)

SYSTEM = """You turn a caretaker's chat messages into a medicine reminder for {nickname}. Today is {weekday} {today}. The local time now is {now}.

Answer ONLY by calling exactly one tool. Never write a normal reply.

Use create_reminder when you know: the medicine, at least one time, and how long it lasts. Otherwise use ask_clarification with 2 to 5 short options (none for a medicine name). If the message is not about a medicine reminder, use reject_off_topic.

Understanding the message:
- Medicine: use the name exactly as the caretaker typed it, without the dose. Do not "correct" spellings. A dose such as 75mg, 500 mg or 1 tablet goes in dose, never in the medicine name.
- Times: understand "10.50 pm", "10:50pm", "10 50 pm", "8", "half past nine", "quarter to 7". Output 24-hour HH:MM. If am or pm is not stated and you cannot tell from context (morning, evening, night, bedtime, after dinner), ask.
- "tonight", "today", "this evening", "just once", "only today" = start today, lasts 1 day.
- "tomorrow" = start tomorrow (start_in_days 1). Alone, it lasts 1 day.
- "every day", "daily", "each morning" = repeats. If they do not say how long, ask how long unless they said it continues ("always", "ongoing", "forever", "keep going").
- "for a week" = 7 days, "for a month" = 30 days, "for 2 weeks" = 14.
- Weekdays: Monday=0 ... Sunday=6. Leave weekdays empty for every day.
- Messages may be in English or Telugu; understand both.
- Time options in a question must include am or pm, for example "8:00 am". Never offer options for a medicine name.
- Never invent a medicine, time, or duration the caretaker did not give."""

TOOLS = [
    {"type": "function", "function": {
        "name": "create_reminder",
        "description": "A complete reminder, ready for the caretaker to confirm.",
        "parameters": {"type": "object", "properties": {
            "medicine": {"type": "string"},
            "dose": {"type": "string", "description": "for example 75 mg or 1 tablet; omit if not given"},
            "times": {"type": "array", "items": {"type": "string"}, "description": "24-hour HH:MM"},
            "weekdays": {"type": "array", "items": {"type": "integer"}, "description": "0=Monday ... 6=Sunday; omit for every day"},
            "start_in_days": {"type": "integer", "description": "0 = today, 1 = tomorrow"},
            "duration_days": {"type": "integer", "description": "how many days it lasts: 1 for tonight or today"},
            "ongoing": {"type": "boolean", "description": "true only if they said it continues with no end"},
        }, "required": ["medicine", "times"]}}},
    {"type": "function", "function": {
        "name": "ask_clarification",
        "description": "Ask one short question with tappable options.",
        "parameters": {"type": "object", "properties": {
            "field": {"type": "string", "enum": ["medicine", "time", "days", "duration"]},
            "question": {"type": "string"},
            "options": {"type": "array", "items": {"type": "string"}},
        }, "required": ["field", "question"]}}},
    {"type": "function", "function": {
        "name": "reject_off_topic",
        "description": "The message is not about a medicine reminder.",
        "parameters": {"type": "object", "properties": {}}}},
]


class NoUsableAnswer(Exception):
    """The model did not answer with a tool, or with arguments we can trust."""


def _fmt(t: time) -> str:
    h = t.hour % 12 or 12
    return f"{h}:{t.minute:02d} {'am' if t.hour < 12 else 'pm'}"


def to_reply(name: str, args: dict, *, today: date, now: datetime | None) -> ChatReply:
    """Validate a tool call into a reply. Raises NoUsableAnswer for anything we shouldn't trust."""
    if name == "reject_off_topic":
        return ChatReply(type="reject")
    try:
        if name == "ask_clarification":
            opts = [str(o)[:40] for o in (args.get("options") or [])][:6]
            if args.get("field") == "medicine":
                opts = []        # Mapa never suggests a medicine; the caretaker names it
            return ChatReply(type="clarify", clarify=Clarify(
                field=args["field"], question=str(args["question"])[:200], options=opts))
        if name != "create_reminder":
            raise NoUsableAnswer(f"unknown tool {name!r}")

        times = [time.fromisoformat(str(t).strip()[:5]) for t in args["times"]]
        start_in = int(args.get("start_in_days") or 0)
        if not 0 <= start_in <= 14:
            raise NoUsableAnswer("start out of range")
        start = today + timedelta(days=start_in)
        days = args.get("duration_days")
        if days is None and not args.get("ongoing"):
            return ChatReply(type="clarify", clarify=Clarify(
                field="duration", question="For how long?", options=["Just today", "7 days", "30 days", "Keep going"]))
        if days is not None and not 1 <= int(days) <= 365:
            raise NoUsableAnswer("duration out of range")
        end = None if args.get("ongoing") and days is None else start + timedelta(days=int(days) - 1)
        wk = args.get("weekdays") or []
        draft = ReminderDraft(
            medicine=str(args["medicine"]).strip(), dose=(str(args["dose"]).strip() or None) if args.get("dose") else None,
            times=times, days_mask=mask_for_days(int(d) for d in wk) if wk else EVERY_DAY,
            start_date=start, end_date=end)
    except (KeyError, ValueError, TypeError, ValidationError) as e:
        raise NoUsableAnswer(f"bad arguments: {e}") from None

    # A one-off for a time that has already gone would never ring. Say so instead of saving it.
    if now and start == now.date() and draft.end_date == start and not draft.times[-1:] == []:
        if all(datetime.combine(start, t, tzinfo=now.tzinfo) < now - PASSED_GRACE for t in draft.times):
            t = draft.times[0]
            return ChatReply(type="clarify", clarify=Clarify(
                field="time", question=f"{_fmt(t)} has already passed today. Set it for tomorrow instead?",
                options=["Yes, tomorrow", "No, change the time"]))
    return ChatReply(type="create", draft=draft)


class SarvamProvider:
    def __init__(self, model: str | None = None, *, client: httpx.AsyncClient | None = None) -> None:
        s = get_settings()
        self.model = model or s.sarvam_chat_model
        self.key = s.sarvam_api_key
        self._client = client

    async def respond(self, messages: list[Message], nickname: str, today: date, now: datetime | None = None) -> ChatReply:
        now = now or datetime.now()
        system = SYSTEM.format(nickname=nickname, weekday=today.strftime("%A"), today=today.isoformat(), now=now.strftime("%H:%M"))
        body = {"model": self.model, "temperature": 0, "max_tokens": 1500, "tools": TOOLS,
                "messages": [{"role": "system", "content": system}] + [{"role": m.role, "content": m.text} for m in messages]}
        base = BASE_V1 if self.model == "sarvam-105b-conversations" else BASE_V2
        client = self._client or httpx.AsyncClient(timeout=15)
        try:
            for choice in ("required", "auto"):          # some models only accept "auto"
                r = await client.post(f"{base}/chat/completions", headers={"api-subscription-key": self.key},
                                      json={**body, "tool_choice": choice})
                if r.status_code == 200:
                    break
                if choice == "auto" or r.status_code not in (400, 422):
                    r.raise_for_status()
        finally:
            if self._client is None:
                await client.aclose()
        try:
            call = r.json()["choices"][0]["message"]["tool_calls"][0]["function"]
            args = json.loads(call.get("arguments") or "{}")
            return to_reply(call["name"], args, today=today, now=now)
        except NoUsableAnswer:
            raise
        except (KeyError, IndexError, TypeError, json.JSONDecodeError) as e:
            raise NoUsableAnswer(f"no tool call: {e!r}") from None


class FallbackProvider:
    """Ask the model first; if it fails or says something we can't trust, use the offline parser."""

    def __init__(self, primary: IntentProvider, fallback: IntentProvider) -> None:
        self.primary, self.fallback = primary, fallback

    async def respond(self, messages, nickname, today, now=None) -> ChatReply:
        try:
            return await self.primary.respond(messages, nickname, today, now)
        except Exception as e:
            log.warning("chat model unavailable (%s); using the offline parser", type(e).__name__)
            return await self.fallback.respond(messages, nickname, today)
