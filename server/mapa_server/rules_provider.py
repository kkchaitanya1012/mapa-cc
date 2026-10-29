"""Offline intent parser: deterministic, no API key.

Used for development and tests, and as the fallback when no model is
configured. It understands the common phrasings; anything it can't place becomes
a clarifying question rather than a guess.
"""
import re
from datetime import date, time, timedelta

from .intent import ChatReply, Clarify, Message, ReminderDraft
from .schedule import EVERY_DAY, WEEKDAYS, WEEKENDS, mask_for_days

_FORMS = r"tablets?|pills?|capsules?|syrup|injection|drops|inhaler|ointment|cream|patch"
_MEDICINE_HINT = re.compile(rf"\b({_FORMS}|medicine|medication|meds?|insulin|vitamin|dose|\d+\s?(?:mg|mcg|ml))\b", re.I)
_DOSE = re.compile(r"\b(\d+(?:\.\d+)?\s?(?:mg|mcg|ml|g))\b", re.I)
_DOSE_COUNT = re.compile(r"\b(\d+|one|two|half)\s+(tablets?|pills?|capsules?|drops)\b", re.I)
_NAME_BEFORE_FORM = re.compile(rf"([A-Za-z][A-Za-z0-9\-]*(?:\s+[A-Za-z0-9\-]+)?)\s+(?:{_FORMS})\b", re.I)
_NAME_BEFORE_DOSE = re.compile(r"\b([A-Za-z][A-Za-z\-]{2,})\s+\d+(?:\.\d+)?\s?(?:mg|mcg|ml|g)\b", re.I)
_VITAMIN = re.compile(r"\b(vitamin\s+[a-z]\d*|insulin)\b", re.I)
_FILLER = {"take", "give", "remind", "reminder", "her", "him", "them", "to", "the", "a", "an", "every", "each",
           "daily", "morning", "evening", "night", "afternoon", "after", "before", "with", "at", "for", "and",
           "amma", "nanna", "mom", "dad", "mum", "papa", "ammamma", "thatha", "please", "set"}

_TIME_AMPM = re.compile(r"\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)", re.I)
_TIME_COLON = re.compile(r"\b(\d{1,2})[:.](\d{2})\b(?!\s*(?:am|pm))", re.I)
_TIME_AT = re.compile(r"\bat\s+(\d{1,2})(?:[:.](\d{2}))?\b(?!\s*(?:mg|mcg|ml|days?|weeks?|months?))", re.I)

_MEALS = {
    "breakfast": ("breakfast", ["7:00 am", "7:30 am", "8:00 am", "8:30 am", "9:00 am"], "am"),
    "lunch": ("lunch", ["12:30 pm", "1:00 pm", "1:30 pm", "2:00 pm"], "pm"),
    "dinner": ("dinner", ["7:30 pm", "8:00 pm", "8:30 pm", "9:00 pm"], "pm"),
    "bedtime": ("bedtime", ["9:00 pm", "9:30 pm", "10:00 pm"], "pm"),
}
_PARTS = {
    "morning": ["7:00 am", "8:00 am", "9:00 am"],
    "afternoon": ["1:00 pm", "2:00 pm", "3:00 pm"],
    "evening": ["6:00 pm", "7:00 pm", "8:00 pm"],
    "night": ["9:00 pm", "10:00 pm"],
}
_GENERIC_TIMES = ["8:00 am", "1:00 pm", "8:00 pm"]

_DAYNAMES = {"mon": 0, "tue": 1, "tues": 1, "wed": 2, "thu": 3, "thur": 3, "thurs": 3, "fri": 4, "sat": 5, "sun": 6}
_DURATION = re.compile(r"\b(\d+|a|one|two|three)\s*(day|week|month)s?\b", re.I)
_NUMWORDS = {"a": 1, "one": 1, "two": 2, "three": 3}
_ONGOING = re.compile(r"\b(ongoing|forever|indefinitely|always|keep going|no end|until further notice)\b", re.I)


def _hour24(h: int, ampm: str | None, hint: str | None) -> int:
    if ampm:
        a = ampm.lower()[0]
        return (h % 12) + (12 if a == "p" else 0)
    if hint == "pm" and h < 12:
        return h + 12
    if hint == "am":
        return h % 12
    # no cue: 6-11 reads as morning, 12 as noon, 1-5 as afternoon
    return h if 6 <= h <= 11 or h == 12 else (h + 12 if 1 <= h <= 5 else h)


def _find_times(text: str, hint: str | None) -> list[time]:
    found: set[time] = set()
    spans: list[tuple[int, int]] = []
    for pat in (_TIME_AMPM, _TIME_COLON, _TIME_AT):
        for m in pat.finditer(text):
            if any(m.start() < e and m.end() > s for s, e in spans):  # overlaps an earlier match
                continue
            h = int(m.group(1))
            mnt = int(m.group(2) or 0)
            ampm = m.group(3) if pat is _TIME_AMPM else None
            if h > 23 or mnt > 59 or (ampm and h > 12):
                continue
            found.add(time(_hour24(h, ampm, hint), mnt))
            spans.append(m.span())
    return sorted(found)


def _find_days(text: str) -> int:
    t = text.lower()
    if re.search(r"\bweekdays?\b", t):
        return WEEKDAYS
    if re.search(r"\bweekends?\b", t):
        return WEEKENDS
    picked = {n for w, n in _DAYNAMES.items() if re.search(rf"\b{w}(?:day|sday|nesday|rsday|urday)?s?\b", t)}
    # "sat" and "sun" etc. only count when no "every day" phrasing overrides them
    if picked and not re.search(r"\b(every ?day|daily|each day)\b", t):
        return mask_for_days(picked)
    return EVERY_DAY


def _find_duration_days(text: str) -> int | None | str:
    """Number of days, None for ongoing, or 'ask' if unspecified."""
    if _ONGOING.search(text):
        return None
    if re.search(r"\b(tonight|today|this evening|just once|only once|only today|tomorrow)\b", text, re.I) \
            and not re.search(r"\b(every ?day|daily|each|weekdays?|weekends?)\b", text, re.I):
        return 1                       # a one-off
    # "once a day" describes frequency, not how long
    text = re.sub(r"\b(once|twice|\d+\s*times|thrice)\s+(a|per|every)\s+(day|week)\b", " ", text, flags=re.I)
    m = _DURATION.search(text)
    if not m:
        return "ask"
    raw = m.group(1).lower()
    n = int(raw) if raw.isdigit() else _NUMWORDS[raw]
    unit = m.group(2).lower()
    return n * {"day": 1, "week": 7, "month": 30}[unit]


def _find_medicine(text: str) -> tuple[str | None, str | None]:
    """(medicine name, dose) from the first message that mentions one."""
    dose_m = _DOSE.search(text) or _DOSE_COUNT.search(text)
    dose = dose_m.group(0) if dose_m else None
    if v := _VITAMIN.search(text):
        return v.group(1).title(), dose
    if m := _NAME_BEFORE_DOSE.search(text):
        return m.group(1).title(), dose
    if m := _NAME_BEFORE_FORM.search(text):
        words = [w for w in m.group(1).split() if w.lower() not in _FILLER]
        if words:
            name = " ".join(words)
            form = re.search(rf"{re.escape(m.group(1))}\s+({_FORMS})", text, re.I)
            label = f"{name} {form.group(1).lower()}" if form else name
            return (label if name.isupper() else label[0].upper() + label[1:]), dose
    return None, dose


def _meal_hint(text: str) -> tuple[str | None, str | None]:
    t = text.lower()
    for key, (name, _opts, ampm) in _MEALS.items():
        if key in t or (key == "bedtime" and re.search(r"\b(bed ?time|before sleep)\b", t)):
            return name, ampm
    for part, _opts in _PARTS.items():
        if re.search(rf"\b{part}\b", t):
            return part, "am" if part == "morning" else "pm"
    return None, None


class RulesProvider:
    async def respond(self, messages: list[Message], nickname: str, today: date, now=None) -> ChatReply:
        user_text = " . ".join(m.text for m in messages if m.role == "user")
        if not user_text.strip():
            return ChatReply(type="reject")

        medicine, dose = _find_medicine(user_text)
        meal, hint = _meal_hint(user_text)
        times = _find_times(user_text, hint)

        # Nothing that looks like a medicine reminder at all.
        if medicine is None and not times and not _MEDICINE_HINT.search(user_text):
            return ChatReply(type="reject")

        if medicine is None:
            return ChatReply(type="clarify", clarify=Clarify(
                field="medicine", question=f"Which medicine should Mapa remind {nickname} about?"))

        if not times:
            opts = (_MEALS[meal][1] if meal in _MEALS else _PARTS.get(meal or "", _GENERIC_TIMES))
            q = (f"What time does {nickname} have {meal}?" if meal in _MEALS
                 else f"What time should Mapa call {nickname}?")
            return ChatReply(type="clarify", clarify=Clarify(field="time", question=q, options=list(opts)))

        duration = _find_duration_days(user_text)
        if duration == "ask":
            return ChatReply(type="clarify", clarify=Clarify(
                field="duration", question="For how long?",
                options=["7 days", "30 days", "3 months", "Keep going"]))

        start = today + timedelta(days=1) if re.search(r"\btomorrow\b", user_text, re.I) else today
        end = None if duration is None else start + timedelta(days=int(duration) - 1)
        return ChatReply(type="create", draft=ReminderDraft(
            medicine=medicine, dose=dose, times=times, days_mask=_find_days(user_text),
            start_date=start, end_date=end))
