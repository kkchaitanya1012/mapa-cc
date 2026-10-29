"""Hits the real Gemini API. Skipped unless GEMINI_API_KEY is set."""
import os
from datetime import date

import pytest

from mapa_server.gemini_provider import GeminiProvider
from mapa_server.intent import Message

pytestmark = pytest.mark.skipif(not os.getenv("GEMINI_API_KEY"), reason="no GEMINI_API_KEY")


async def test_off_topic_is_rejected():
    r = await GeminiProvider().respond([Message(role="user", text="what's the capital of France?")], "Amma", date.today())
    assert r.type == "reject"


async def test_complete_reminder_creates():
    r = await GeminiProvider().respond(
        [Message(role="user", text="BP tablet at 9 am every day for 30 days")], "Amma", date.today())
    assert r.type == "create" and r.draft.medicine
