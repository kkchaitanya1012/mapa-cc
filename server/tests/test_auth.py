import time
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from jwt.algorithms import ECAlgorithm

from mapa_server import auth
from mapa_server.config import Settings

S = Settings(_env_file=None, supabase_url="https://x.supabase.co", supabase_anon_key="anon")
KEY = ec.generate_private_key(ec.SECP256R1())
OTHER = ec.generate_private_key(ec.SECP256R1())
UID = uuid4()


def jwk(key, kid="k1"):
    d = ECAlgorithm.to_jwk(key.public_key(), as_dict=True)
    return {**d, "kid": kid, "alg": "ES256", "use": "sig"}


def token(key=KEY, kid="k1", sub=None, aud="authenticated", iss="https://x.supabase.co/auth/v1", exp_in=300, alg="ES256"):
    now = int(time.time())
    return jwt.encode({"sub": str(sub or UID), "aud": aud, "iss": iss, "iat": now, "exp": now + exp_in},
                      key, algorithm=alg, headers={"kid": kid})


@pytest.fixture(autouse=True)
def _keys(monkeypatch):
    auth._jwks.update(at=time.monotonic(), keys={"k1": jwk(KEY)})
    auth._cache.clear()

    async def no_fetch(s):
        return False
    monkeypatch.setattr(auth, "_refresh_jwks", no_fetch)


async def test_a_good_login_is_recognised_without_any_network():
    assert await auth.verify_locally(token(), S) == UID


@pytest.mark.parametrize("bad", [
    lambda: token(exp_in=-10),                              # expired
    lambda: token(aud="someone-else"),                      # wrong audience
    lambda: token(iss="https://evil.example/auth/v1"),      # wrong issuer
    lambda: token(key=OTHER),                               # signed by a stranger's key
    lambda: token()[:-4] + "AAAA",                          # tampered
    lambda: "not.a.token",
])
async def test_bad_logins_are_refused(bad):
    with pytest.raises(HTTPException) as e:
        await auth.verify_locally(bad(), S)
    assert e.value.status_code == 401


async def test_tokens_that_cannot_be_checked_locally_fall_through():
    legacy = jwt.encode({"sub": str(UID), "aud": "authenticated"}, "secret" * 8, algorithm="HS256", headers={"kid": "k1"})
    assert await auth.verify_locally(legacy, S) is None                   # shared-secret token
    assert await auth.verify_locally(token(kid="unknown"), S) is None     # key we can't fetch


async def test_an_unknown_key_triggers_one_refresh(monkeypatch):
    calls = []

    async def fetch(s):
        calls.append(1)
        auth._jwks.update(at=time.monotonic(), keys={"k1": jwk(KEY), "k2": jwk(OTHER, "k2")})
        return True
    monkeypatch.setattr(auth, "_refresh_jwks", fetch)
    assert await auth.verify_locally(token(key=OTHER, kid="k2"), S) == UID
    assert len(calls) == 1


def patch_client(monkeypatch, handler):
    real = httpx.AsyncClient
    monkeypatch.setattr(auth.httpx, "AsyncClient", lambda **kw: real(transport=httpx.MockTransport(handler), **kw))
    async def nap(_): pass
    monkeypatch.setattr(auth.asyncio, "sleep", nap)


async def test_one_dropped_connection_does_not_fail_the_login(monkeypatch):
    seen = []

    def handler(req):
        seen.append(1)
        if len(seen) < 3:
            raise httpx.ConnectError("blip")
        return httpx.Response(200, json={"id": str(UID)})
    patch_client(monkeypatch, handler)
    assert await auth.verify_remotely("t", S) == UID and len(seen) == 3


async def test_a_dead_connection_gives_a_clear_503_after_three_tries(monkeypatch):
    seen = []

    def handler(req):
        seen.append(1)
        raise httpx.ConnectError("down")
    patch_client(monkeypatch, handler)
    with pytest.raises(HTTPException) as e:
        await auth.verify_remotely("t", S)
    assert e.value.status_code == 503 and len(seen) == 3


async def test_a_rejected_token_is_a_401_and_not_retried(monkeypatch):
    seen = []

    def handler(req):
        seen.append(1)
        return httpx.Response(401, json={})
    patch_client(monkeypatch, handler)
    with pytest.raises(HTTPException) as e:
        await auth.verify_remotely("t", S)
    assert e.value.status_code == 401 and len(seen) == 1


async def test_current_user_caches_a_checked_login():
    t = token()
    first = await auth.current_user(authorization=f"Bearer {t}", settings=S)
    auth._jwks["keys"].clear()                       # even with no keys, the cached login still works for its short life
    again = await auth.current_user(authorization=f"Bearer {t}", settings=S)
    assert first.id == again.id == UID
