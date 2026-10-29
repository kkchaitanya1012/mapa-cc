import secrets
import time
from collections import defaultdict, deque


def generate_code() -> str:
    """Six digits, so a parent can type it on a big phone keypad. 10^6 codes
    with a 15-minute life and a per-user attempt limit make guessing impractical."""
    return f"{secrets.randbelow(1_000_000):06d}"


class AttemptLimiter:
    """Allow at most `limit` failed redeem attempts per user per window."""

    def __init__(self, limit: int, window_s: float = 600.0) -> None:
        self.limit, self.window = limit, window_s
        self._fails: dict[str, deque[float]] = defaultdict(deque)

    def _trim(self, key: str, now: float) -> deque[float]:
        q = self._fails[key]
        while q and q[0] <= now - self.window:
            q.popleft()
        return q

    def blocked(self, key: str, now: float | None = None) -> bool:
        now = time.monotonic() if now is None else now
        return len(self._trim(key, now)) >= self.limit

    def fail(self, key: str, now: float | None = None) -> None:
        now = time.monotonic() if now is None else now
        self._trim(key, now).append(now)

    def reset(self, key: str) -> None:
        self._fails.pop(key, None)
