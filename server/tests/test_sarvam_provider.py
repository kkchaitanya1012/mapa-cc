from datetime import date, datetime, time
from zoneinfo import ZoneInfo

import httpx
import pytest

from mapa_server.intent import Message
from mapa_server.rules_provider import RulesProvider
from mapa_server.sarvam_provider import FallbackProvider, NoUsableAnswer, SarvamProvider, to_reply

TODAY = date(2026, 10, 27)
NOW = datetime(2026, 10, 27, 21, 30, tzinfo=ZoneInfo("Asia/Kolkata"))


def reply(name, **args):
    return to_reply(name, args, today=TODAY, now=NOW)


# ---- turning the model's tool calls into reminders, with every value checked

def test_tonight_at_ten_fifty_is_a_one_off_at_22_50():
    r = reply("create_reminder", medicine="Pegbalin tablet", times=["22:50"], duration_days=1, start_in_days=0)
    d = r.draft
    assert r.type == "create" and d.times == [time(22, 50)]
    assert d.start_date == TODAY and d.end_date == TODAY and d.days_mask == 127


def test_tomorrow_starts_tomorrow_and_a_week_lasts_seven_days():
    d = reply("create_reminder", medicine="Vit D", times=["09:00"], start_in_days=1, duration_days=7).draft
    assert (d.start_date, d.end_date) == (date(2026, 10, 28), date(2026, 11, 3))


def test_weekdays_become_a_mask_and_ongoing_has_no_end():
    d = reply("create_reminder", medicine="Insulin", times=["07:00", "19:00"], weekdays=[0, 2, 4], ongoing=True).draft
    assert d.days_mask == 0b10101 and d.end_date is None and d.times == [time(7), time(19)]


def test_a_missing_duration_is_asked_not_guessed():
    r = reply("create_reminder", medicine="Thyroxine", times=["07:00"])
    assert r.type == "clarify" and r.clarify.field == "duration"


def test_a_time_that_has_already_passed_today_is_not_silently_saved():
    r = reply("create_reminder", medicine="Calcium", times=["20:00"], duration_days=1)
    assert r.type == "clarify" and "already passed" in r.clarify.question and "Yes, tomorrow" in r.clarify.options


def test_a_recurring_reminder_for_an_earlier_time_is_fine():
    assert reply("create_reminder", medicine="BP", times=["08:00"], duration_days=30).type == "create"


def test_mapa_never_suggests_a_medicine():
    r = reply("ask_clarification", field="medicine", question="Which medicine?", options=["BP tablet", "Painkiller"])
    assert r.clarify.options == []


@pytest.mark.parametrize("args", [
    {"medicine": "X", "times": ["25:99"], "duration_days": 1},
    {"medicine": "X", "times": [], "duration_days": 1},
    {"medicine": "", "times": ["09:00"], "duration_days": 1},
    {"medicine": "X", "times": ["09:00"], "duration_days": 9999},
    {"medicine": "X", "times": ["09:00"], "duration_days": 1, "start_in_days": 90},
    {"medicine": "X", "times": ["09:00"], "duration_days": 1, "weekdays": [9]},
    {"times": ["09:00"], "duration_days": 1},
])
def test_untrustworthy_arguments_are_refused(args):
    with pytest.raises(NoUsableAnswer):
        reply("create_reminder", **args)


def test_off_topic_and_unknown_tools():
    assert reply("reject_off_topic").type == "reject"
    with pytest.raises(NoUsableAnswer):
        reply("send_email", to="x")


# ---- the HTTP side

def provider(handler, model="sarvam-105b-conversations"):
    return SarvamProvider(model, client=httpx.AsyncClient(transport=httpx.MockTransport(handler)))


def tool_response(name, args):
    import json
    return httpx.Response(200, json={"choices": [{"finish_reason": "tool_calls", "message": {"tool_calls": [
        {"function": {"name": name, "arguments": json.dumps(args)}}]}}]})


async def test_the_model_is_asked_with_strict_tools_and_todays_date():
    seen = {}

    def handler(req):
        import json
        seen.update(json.loads(req.content), url=str(req.url), key=req.headers["api-subscription-key"])
        return tool_response("create_reminder", {"medicine": "BP", "times": ["09:00"], "duration_days": 1, "start_in_days": 1})
    r = await provider(handler).respond([Message(role="user", text="BP at 9 tomorrow")], "Amma", TODAY, NOW)
    assert r.type == "create"
    assert seen["url"].startswith("https://api.sarvam.ai/v1/") and seen["tool_choice"] == "required"
    assert {t["function"]["name"] for t in seen["tools"]} == {"create_reminder", "ask_clarification", "reject_off_topic"}
    assert "Tuesday 2026-10-27" in seen["messages"][0]["content"] and "21:30" in seen["messages"][0]["content"]
    assert seen["messages"][1] == {"role": "user", "content": "BP at 9 tomorrow"}


async def test_a_plain_text_answer_is_not_trusted():
    def handler(req):
        return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": "Sure! What time?"}}]})
    with pytest.raises(NoUsableAnswer):
        await provider(handler).respond([Message(role="user", text="x")], "Amma", TODAY, NOW)


async def test_the_offline_parser_takes_over_when_the_model_fails():
    def down(req):
        raise httpx.ConnectError("no network")
    p = FallbackProvider(provider(down), RulesProvider())
    r = await p.respond([Message(role="user", text="Pegbalin tablet at 10.50 pm tonight")], "Amma", TODAY, NOW)
    assert r.type == "create" and r.draft.times == [time(22, 50)] and r.draft.end_date == TODAY


# ---- the offline parser, now that it is only the safety net

@pytest.mark.parametrize("text,times", [
    ("Pegbalin tablet at 10.50 pm tonight", [time(22, 50)]),
    ("Pegbalin tablet at 10:50pm tonight", [time(22, 50)]),
    ("BP tablet 9.15 am tomorrow", [time(9, 15)]),
])
async def test_offline_parser_reads_dotted_times_and_one_offs(text, times):
    r = await RulesProvider().respond([Message(role="user", text=text)], "Amma", TODAY)
    assert r.type == "create" and r.draft.times == times
    assert r.draft.end_date == r.draft.start_date          # one night only


async def test_offline_parser_starts_tomorrow_when_asked():
    r = await RulesProvider().respond([Message(role="user", text="BP tablet 9 am tomorrow")], "Amma", TODAY)
    assert r.draft.start_date == date(2026, 10, 28)
