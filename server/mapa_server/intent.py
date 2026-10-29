"""Turn the caretaker's chat into a reminder, and nothing else.

The assistant has three possible outputs and no free-text one:
  create   - a complete reminder draft to confirm
  clarify  - one question with tappable options
  reject   - the message wasn't about a medicine reminder (the app shows a fixed line)
"""
from datetime import date, datetime, time
from typing import Literal, Protocol

from pydantic import BaseModel, Field, field_validator

from .schedule import EVERY_DAY


class Message(BaseModel):
    role: Literal["user", "assistant"]
    text: str = Field(max_length=500)


class ReminderDraft(BaseModel):
    medicine: str = Field(min_length=1, max_length=80)
    dose: str | None = Field(default=None, max_length=80)
    instructions: str | None = Field(default=None, max_length=200)
    times: list[time] = Field(min_length=1, max_length=6)
    days_mask: int = Field(default=EVERY_DAY, ge=1, le=127)
    start_date: date
    end_date: date | None = None

    @field_validator("times")
    @classmethod
    def _unique_sorted(cls, v: list[time]) -> list[time]:
        return sorted(set(v))


class Clarify(BaseModel):
    field: Literal["medicine", "time", "days", "duration"]
    question: str
    options: list[str] = Field(default_factory=list, max_length=6)  # empty = free text


class ChatReply(BaseModel):
    type: Literal["create", "clarify", "reject"]
    draft: ReminderDraft | None = None
    clarify: Clarify | None = None


class IntentProvider(Protocol):
    async def respond(self, messages: list[Message], nickname: str, today: date, now: datetime | None = None) -> ChatReply: ...
