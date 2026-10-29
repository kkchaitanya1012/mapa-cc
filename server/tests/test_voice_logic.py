from mapa_server.voice import prompts
from mapa_server.voice.state import CallState, MAX_NOTE

META = {"name": "Amma", "medicine": "BP tablet", "dose": "1 tablet", "language": "en", "caretaker": "Priya"}


# ---- what Mapa says and won't say

def test_instructions_name_the_person_medicine_and_caretaker():
    text = prompts.instructions(META)
    assert "Amma" in text and "BP tablet (1 tablet)" in text and "Priya" in text


def test_instructions_hold_the_hard_limits():
    text = prompts.instructions(META, emergency_number="112")
    for must in ("nothing else", "never give medical advice", "second off-topic remark", "call 112",
                 "Never pretend to be a person", "record_medicine_status", "record_wellbeing", "end_call"):
        assert must in text, must


def test_telugu_calls_ask_for_telugu_script():
    text = prompts.instructions({**META, "language": "te"})
    assert "Telugu" in text and "తెలుగు" in text


def test_greetings_are_short_and_on_topic():
    en = prompts.greeting(META)
    assert "Amma" in en and "BP tablet" in en and en.endswith("Have you taken it?") and len(en) < 140
    te = prompts.greeting({**META, "language": "te"})
    assert "Amma" in te and "BP tablet" in te and "వేసుకున్నారా" in te


def test_greeting_without_a_caretaker_name_still_reads_well():
    assert "Your family asked me" in prompts.greeting({**META, "caretaker": ""})


def test_language_codes_cover_both_voices():
    assert prompts.LANG_CODES == {"en": "en-IN", "te": "te-IN"}


# ---- what a call turns into

def test_a_normal_call_becomes_a_result_with_the_parents_words():
    s = CallState()
    s.add_turn("mapa", "Have you taken it?")
    s.add_turn("parent", "Yes, with my idli")
    s.set_medicine("taken", '"Took it with idli, feeling good!"')
    s.set_wellbeing("good", "feeling fine")
    o = s.outcome()
    assert (o.kind, o.medicine_status, o.wellbeing, o.note) == ("result", "taken", "good", "Took it with idli, feeling good!")
    assert s.user_turns == 1


def test_an_unwell_parent_leads_with_how_they_feel():
    s = CallState()
    s.set_medicine("taken", "I took it")
    s.set_wellbeing("unwell", "A little dizzy since morning")
    assert s.outcome().note == "A little dizzy since morning"


def test_note_falls_back_to_wellbeing_and_is_capped():
    s = CallState()
    s.set_wellbeing("okay", "x" * 500)
    o = s.outcome()
    assert o.medicine_status == "unclear" and len(o.note) == MAX_NOTE


def test_an_instant_hangup_with_no_words_counts_as_unanswered():
    assert CallState().outcome().kind == "no_answer"


def test_a_silent_call_that_went_on_is_unclear_not_unanswered():
    s = CallState()
    s.started -= 60
    o = s.outcome()
    assert o.kind == "result" and o.medicine_status == "unclear"


def test_the_agent_cannot_record_nonsense():
    s = CallState()
    for bad in (lambda: s.set_medicine("maybe", ""), lambda: s.set_wellbeing("great", "")):
        try:
            bad()
        except ValueError:
            continue
        raise AssertionError("accepted an invalid value")


def test_empty_turns_are_ignored():
    s = CallState()
    s.add_turn("parent", "   ")
    assert s.user_turns == 0 and s.transcript == []
