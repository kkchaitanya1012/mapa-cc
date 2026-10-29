"""When should Mapa call? Pure functions, no database."""
from collections.abc import Iterable
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

EVERY_DAY = 0b1111111
WEEKDAYS = 0b0011111
WEEKENDS = 0b1100000


def mask_for_days(days: Iterable[int]) -> int:
    """Days are Python weekdays: 0 = Monday ... 6 = Sunday."""
    mask = 0
    for d in days:
        if not 0 <= d <= 6:
            raise ValueError(f"weekday out of range: {d}")
        mask |= 1 << d
    return mask


def days_in_mask(mask: int) -> list[int]:
    return [d for d in range(7) if mask & (1 << d)]


def occurrences_between(
    *,
    time_of_day: time,
    days_mask: int,
    start_date: date,
    end_date: date | None,
    tz: ZoneInfo,
    window_start: datetime,
    window_end: datetime,
) -> list[datetime]:
    """Call times (UTC) for one reminder inside [window_start, window_end).

    Dates and the weekday mask are the recipient's local calendar, so a 9:00 am
    reminder stays at 9:00 am across daylight-saving changes.
    """
    if window_start.tzinfo is None or window_end.tzinfo is None:
        raise ValueError("window bounds must be timezone-aware")
    first = window_start.astimezone(tz).date() - timedelta(days=1)
    last = window_end.astimezone(tz).date() + timedelta(days=1)
    out: list[datetime] = []
    d = first
    while d <= last:
        if (
            d >= start_date
            and (end_date is None or d <= end_date)
            and days_mask & (1 << d.weekday())
        ):
            at = datetime.combine(d, time_of_day, tzinfo=tz).astimezone(timezone.utc)
            if window_start <= at < window_end:
                out.append(at)
        d += timedelta(days=1)
    return out


@dataclass(frozen=True)
class Retry:
    retry_at: datetime | None  # when to try again, or None if we're out of attempts
    alert: bool                # tell the caretaker nobody answered


def after_no_answer(attempt: int, max_attempts: int, now: datetime, retry_after_min: int) -> Retry:
    """No answer on this attempt: redial once more later, then alert the caretaker."""
    if attempt < max_attempts:
        return Retry(now + timedelta(minutes=retry_after_min), alert=False)
    return Retry(None, alert=True)


def alerts_for(
    medicine_status: str, wellbeing: str | None, *, who: str, medicine: str
) -> list[tuple[str, str]]:
    """Which alerts a finished call should raise: (kind, message) pairs."""
    out: list[tuple[str, str]] = []
    if wellbeing == "unwell":
        out.append(("unwell", f"{who} said they aren't feeling well"))
    if medicine_status == "not_taken":
        out.append(("missed_dose", f"{who} hasn't taken {medicine}"))
    return out
