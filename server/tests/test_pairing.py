import re

from mapa_server.pairing import AttemptLimiter, generate_code


def test_code_is_six_digits_and_varies():
    codes = {generate_code() for _ in range(200)}
    assert all(re.fullmatch(r"\d{6}", c) for c in codes)
    assert len(codes) > 150


def test_limiter_blocks_after_the_limit_and_recovers():
    lim = AttemptLimiter(3, window_s=600)
    for i in range(3):
        assert not lim.blocked("u", now=i)
        lim.fail("u", now=i)
    assert lim.blocked("u", now=10)
    assert not lim.blocked("someone-else", now=10)
    assert not lim.blocked("u", now=700)  # window passed


def test_success_clears_the_count():
    lim = AttemptLimiter(2)
    lim.fail("u", now=0)
    lim.reset("u")
    lim.fail("u", now=1)
    assert not lim.blocked("u", now=2)
