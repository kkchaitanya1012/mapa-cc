"""Model-backed intent parser using Gemini with forced tool calling.

The model can only answer by calling one of three tools, so it can never
produce free text. Every argument is re-validated by pydantic before use.

NOTE: written against the public REST shape but not yet exercised with a real
key; run `pytest tests/test_gemini_live.py` with GEMINI_API_KEY set to check it.
"""
from datetime import date

import httpx
from pydantic import ValidationError

from .config import get_settings
from .intent import ChatReply, Clarify, Message, ReminderDraft

SYSTEM = """You are the reminder parser inside Mapa, an app that phones elderly people about their medicine.
You do exactly one job: turn the caretaker's messages into a medicine reminder for {nickname}.
Rules:
- Always answer by calling exactly one tool. Never write a normal reply.
- If the messages describe a complete reminder (medicine, at least one time, and how long), call create_reminder.
- If the medicine, the time, or the duration is missing or vague, call ask_clarification with 2-5 short tappable options (or none for the medicine name).
- If the message is not about a medicine reminder (questions, chat, anything else), call reject_off_topic.
- Times are 24-hour HH:MM. days: 0=Monday ... 6=Sunday; omit for every day.
- Today is {today}. Never invent a medicine or a time the caretaker did not give."""

TOOLS = [{"functionDeclarations": [
    {"name": "create_reminder",
     "description": "A complete reminder ready to confirm.",
     "parameters": {"type": "object", "properties": {
         "medicine": {"type": "string"}, "dose": {"type": "string"},
         "times": {"type": "array", "items": {"type": "string", "description": "HH:MM, 24-hour"}},
         "days": {"type": "array", "items": {"type": "integer"}},
         "duration_days": {"type": "integer", "description": "omit for ongoing"}},
         "required": ["medicine", "times"]}},
    {"name": "ask_clarification",
     "description": "Ask one short question with tappable options.",
     "parameters": {"type": "object", "properties": {
         "field": {"type": "string", "enum": ["medicine", "time", "days", "duration"]},
         "question": {"type": "string"},
         "options": {"type": "array", "items": {"type": "string"}}},
         "required": ["field", "question"]}},
    {"name": "reject_off_topic",
     "description": "The message is not about a medicine reminder.",
     "parameters": {"type": "object", "properties": {}}},
]}]


class GeminiProvider:
    async def respond(self, messages: list[Message], nickname: str, today: date, now=None) -> ChatReply:
        from datetime import time, timedelta

        from .schedule import EVERY_DAY, mask_for_days

        s = get_settings()
        body = {
            "systemInstruction": {"parts": [{"text": SYSTEM.format(nickname=nickname, today=today.isoformat())}]},
            "contents": [{"role": "user" if m.role == "user" else "model", "parts": [{"text": m.text}]}
                         for m in messages],
            "tools": TOOLS,
            "toolConfig": {"functionCallingConfig": {"mode": "ANY"}},
            "generationConfig": {"temperature": 0},
        }
        async with httpx.AsyncClient(timeout=15) as client:
            r = await client.post(
                f"https://generativelanguage.googleapis.com/v1beta/models/{s.gemini_model}:generateContent",
                headers={"x-goog-api-key": s.gemini_api_key}, json=body)
        r.raise_for_status()
        try:
            call = r.json()["candidates"][0]["content"]["parts"][0]["functionCall"]
            name, args = call["name"], call.get("args", {})
        except (KeyError, IndexError):
            return ChatReply(type="reject")

        try:
            if name == "create_reminder":
                days = args.get("days")
                dur = args.get("duration_days")
                return ChatReply(type="create", draft=ReminderDraft(
                    medicine=args["medicine"], dose=args.get("dose"),
                    times=[time.fromisoformat(t) for t in args["times"]],
                    days_mask=mask_for_days(days) if days else EVERY_DAY,
                    start_date=today,
                    end_date=today + timedelta(days=int(dur) - 1) if dur else None))
            if name == "ask_clarification":
                return ChatReply(type="clarify", clarify=Clarify(
                    field=args["field"], question=args["question"], options=args.get("options", [])[:6]))
        except (ValidationError, KeyError, ValueError):
            return ChatReply(type="reject")
        return ChatReply(type="reject")
