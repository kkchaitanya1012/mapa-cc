"""What happened on a call, and what to do about it. No network, fully testable."""
import time
from dataclasses import dataclass, field

MEDICINE = ("taken", "not_taken", "will_take_later", "unclear")
WELLBEING = ("good", "okay", "unwell")
QUICK_HANGUP_S = 15       # a call that ends this fast with no words was not really answered
MAX_NOTE = 140


@dataclass
class Outcome:
    kind: str                     # "result" | "no_answer"
    medicine_status: str = "unclear"
    wellbeing: str | None = None
    note: str | None = None


def _clean(text: str | None) -> str | None:
    if not text:
        return None
    t = " ".join(text.split()).strip(' "“”')
    return t[:MAX_NOTE] if t else None


@dataclass
class CallState:
    started: float = field(default_factory=time.monotonic)
    medicine_status: str | None = None
    medicine_quote: str | None = None
    wellbeing: str | None = None
    wellbeing_note: str | None = None
    transcript: list[dict] = field(default_factory=list)
    user_turns: int = 0
    wrapping_up: bool = False   # how they feel is recorded: the next thing said is the goodbye

    def set_medicine(self, status: str, quote: str | None) -> None:
        if status not in MEDICINE:
            raise ValueError(f"unknown medicine status {status!r}")
        self.medicine_status, self.medicine_quote = status, _clean(quote)

    def set_wellbeing(self, wellbeing: str, note: str | None) -> None:
        if wellbeing not in WELLBEING:
            raise ValueError(f"unknown wellbeing {wellbeing!r}")
        self.wellbeing, self.wellbeing_note = wellbeing, _clean(note)

    def add_turn(self, who: str, text: str) -> None:
        if not text.strip():
            return
        self.transcript.append({"who": who, "text": text.strip()})
        if who == "parent":
            self.user_turns += 1

    def duration_s(self) -> int:
        return int(time.monotonic() - self.started)

    def outcome(self) -> Outcome:
        """Turn the call into a result, or into 'nobody really answered'."""
        if self.medicine_status is None and self.wellbeing is None:
            if self.user_turns == 0 and self.duration_s() < QUICK_HANGUP_S:
                return Outcome("no_answer")
        # The caretaker reads one line: lead with what they said about the medicine,
        # fall back to how they feel.
        note = self.medicine_quote or self.wellbeing_note
        if self.medicine_quote and self.wellbeing == "unwell" and self.wellbeing_note:
            note = self.wellbeing_note
        return Outcome("result", self.medicine_status or "unclear", self.wellbeing, note)
