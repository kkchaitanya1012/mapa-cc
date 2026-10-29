from datetime import date, time

import pytest

from mapa_server.intent import Message
from mapa_server.rules_provider import RulesProvider
from mapa_server.schedule import EVERY_DAY, WEEKDAYS

TODAY = date(2026, 10, 27)


async def ask(*texts: str, name: str = "Amma"):
    msgs = [Message(role="user", text=t) for t in texts]
    return await RulesProvider().respond(msgs, name, TODAY)


async def test_complete_reminder_creates():
    r = await ask("Amma BP tablet at 9 am every day for 30 days")
    assert r.type == "create"
    d = r.draft
    assert d.medicine.lower() == "bp tablet" and d.times == [time(9, 0)]
    assert d.days_mask == EVERY_DAY
    assert d.start_date == TODAY and d.end_date == date(2026, 11, 25)


async def test_breakfast_asks_for_a_time_with_options():
    r = await ask("BP tablet every morning after breakfast for a month")
    assert r.type == "clarify" and r.clarify.field == "time"
    assert "breakfast" in r.clarify.question and "8:30 am" in r.clarify.options


async def test_tapping_an_option_completes_the_reminder():
    r = await ask("BP tablet every morning after breakfast for a month", "8:30 am")
    assert r.type == "create" and r.draft.times == [time(8, 30)]
    assert r.draft.end_date == date(2026, 11, 25)


async def test_bare_time_after_breakfast_means_morning():
    r = await ask("BP tablet after breakfast for a month", "8:30")
    assert r.type == "create" and r.draft.times == [time(8, 30)]


async def test_missing_duration_is_asked():
    r = await ask("Metformin 500 mg with lunch at 1:30 pm")
    assert r.type == "clarify" and r.clarify.field == "duration"
    assert "Keep going" in r.clarify.options


async def test_answering_the_duration_question():
    r = await ask("Metformin 500 mg with lunch at 1:30 pm", "30 days")
    assert r.type == "create" and r.draft.dose == "500 mg" and r.draft.times == [time(13, 30)]
    assert r.draft.medicine == "Metformin"


async def test_ongoing_has_no_end_date():
    r = await ask("Vitamin D at 8 pm daily", "Keep going")
    assert r.type == "create" and r.draft.end_date is None and r.draft.times == [time(20, 0)]


async def test_once_a_day_is_not_a_one_day_duration():
    r = await ask("Thyroid tablet once a day at 7 am")
    assert r.type == "clarify" and r.clarify.field == "duration"


async def test_weekdays_and_named_days():
    r = await ask("Vitamin D at 8 pm on weekdays for 2 weeks")
    assert r.draft.days_mask == WEEKDAYS
    r = await ask("Insulin at 7 am on Mon Wed Fri for 1 month")
    assert r.draft.days_mask == 0b10101


async def test_two_times():
    r = await ask("Antibiotic tablet at 8 am and 8 pm for 7 days")
    assert r.type == "create" and r.draft.times == [time(8, 0), time(20, 0)]


async def test_dose_number_is_not_mistaken_for_a_time():
    r = await ask("Metformin 500 mg every morning for a month")
    assert r.type == "clarify" and r.clarify.field == "time"


async def test_unknown_medicine_is_asked_not_guessed():
    r = await ask("remind her at 9 am for 10 days to take her medicine")
    assert r.type == "clarify" and r.clarify.field == "medicine" and r.clarify.options == []


@pytest.mark.parametrize("text", [
    "what's the weather today?", "tell me a joke", "who won the match", "hello", "what is the capital of France",
])
async def test_off_topic_is_rejected(text):
    assert (await ask(text)).type == "reject"


async def test_empty_is_rejected():
    assert (await ask("   ")).type == "reject"
