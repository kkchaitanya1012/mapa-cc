from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest

from mapa_server.schedule import (EVERY_DAY, WEEKDAYS, after_no_answer, alerts_for, days_in_mask,
                                  mask_for_days, occurrences_between)

IST = ZoneInfo("Asia/Kolkata")
UTC = timezone.utc


def utc(*a) -> datetime:
    return datetime(*a, tzinfo=UTC)


def test_mask_round_trip():
    assert mask_for_days([0, 2, 4]) == 0b10101
    assert days_in_mask(0b10101) == [0, 2, 4]
    assert days_in_mask(EVERY_DAY) == list(range(7))
    with pytest.raises(ValueError):
        mask_for_days([7])


def test_daily_nine_am_ist_is_0330_utc():
    out = occurrences_between(
        time_of_day=time(9, 0), days_mask=EVERY_DAY, start_date=date(2026, 10, 1), end_date=None, tz=IST,
        window_start=utc(2026, 10, 27, 0, 0), window_end=utc(2026, 10, 29, 0, 0))
    assert out == [utc(2026, 10, 27, 3, 30), utc(2026, 10, 28, 3, 30)]


def test_weekdays_only_skips_the_weekend():
    # 2026-10-31 is a Saturday, 2026-11-01 a Sunday
    out = occurrences_between(
        time_of_day=time(9, 0), days_mask=WEEKDAYS, start_date=date(2026, 10, 1), end_date=None, tz=IST,
        window_start=utc(2026, 10, 30, 0, 0), window_end=utc(2026, 11, 3, 0, 0))
    assert [d.astimezone(IST).date() for d in out] == [date(2026, 10, 30), date(2026, 11, 2)]


def test_start_and_end_dates_bound_the_calls():
    out = occurrences_between(
        time_of_day=time(20, 0), days_mask=EVERY_DAY, start_date=date(2026, 10, 28), end_date=date(2026, 10, 29),
        tz=IST, window_start=utc(2026, 10, 26, 0, 0), window_end=utc(2026, 11, 5, 0, 0))
    assert [d.astimezone(IST).date() for d in out] == [date(2026, 10, 28), date(2026, 10, 29)]


def test_window_is_half_open():
    at = utc(2026, 10, 27, 3, 30)
    kw = dict(time_of_day=time(9, 0), days_mask=EVERY_DAY, start_date=date(2026, 10, 1), end_date=None, tz=IST)
    assert occurrences_between(**kw, window_start=at, window_end=at + timedelta(hours=1)) == [at]
    assert occurrences_between(**kw, window_start=at - timedelta(hours=1), window_end=at) == []


def test_late_evening_ist_uses_the_local_calendar_day():
    # 23:30 IST on the 27th is 18:00 UTC the same day; a UTC-date loop would mislabel edge cases
    out = occurrences_between(
        time_of_day=time(23, 30), days_mask=mask_for_days([1]), start_date=date(2026, 10, 1), end_date=None,
        tz=IST, window_start=utc(2026, 10, 27, 0, 0), window_end=utc(2026, 10, 28, 0, 0))
    assert out == [utc(2026, 10, 27, 18, 0)]  # 27 Oct 2026 is a Tuesday


def test_stays_at_local_time_across_daylight_saving():
    ny = ZoneInfo("America/New_York")  # clocks go back on 2026-11-01
    out = occurrences_between(
        time_of_day=time(9, 0), days_mask=EVERY_DAY, start_date=date(2026, 10, 1), end_date=None, tz=ny,
        window_start=utc(2026, 10, 31, 0, 0), window_end=utc(2026, 11, 3, 0, 0))
    local = [d.astimezone(ny).time() for d in out]
    assert local == [time(9, 0)] * 3
    assert out[0].hour == 13 and out[-1].hour == 14  # UTC offset shifted by an hour


def test_naive_window_is_rejected():
    with pytest.raises(ValueError):
        occurrences_between(time_of_day=time(9), days_mask=1, start_date=date(2026, 1, 1), end_date=None, tz=IST,
                            window_start=datetime(2026, 1, 1), window_end=datetime(2026, 1, 2))


def test_retry_then_alert():
    now = utc(2026, 10, 27, 4, 0)
    first = after_no_answer(1, 2, now, 10)
    assert first.retry_at == now + timedelta(minutes=10) and not first.alert
    last = after_no_answer(2, 2, now, 10)
    assert last.retry_at is None and last.alert


def test_alert_rules():
    assert alerts_for("taken", "good", who="Amma", medicine="BP tablet") == []
    assert alerts_for("will_take_later", "okay", who="Amma", medicine="BP tablet") == []
    assert alerts_for("not_taken", "good", who="Amma", medicine="BP tablet") == [
        ("missed_dose", "Amma hasn't taken BP tablet")]
    kinds = [k for k, _ in alerts_for("not_taken", "unwell", who="Amma", medicine="BP tablet")]
    assert kinds == ["unwell", "missed_dose"]
    assert [k for k, _ in alerts_for("taken", "unwell", who="Amma", medicine="x")] == ["unwell"]
