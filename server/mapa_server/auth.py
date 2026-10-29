"""Sign-in checking.

The apps sign in with Supabase Auth (anonymous sign-in) and send the access token
with every request. We check it two ways:

1. Locally, against Supabase's published signing key (JWKS). No network call per
   request, so answering a call never depends on a round trip to Supabase.
2. If the key can't be used (not published yet, or temporarily unreachable), by
   asking Supabase who the token belongs to, with retries.
"""
import asyncio
import logging
import time
from dataclasses import dataclass
from uuid import UUID

import httpx
import jwt
from fastapi import Depends, Header, HTTPException, status

from .config import Settings, get_settings

log = logging.getLogger("mapa.auth")

_cache: dict[str, tuple[float, UUID]] = {}
_TTL_S = 60.0
_JWKS_TTL_S = 3600.0
_jwks: dict = {"at": 0.0, "keys": {}}


@dataclass(frozen=True)
class AuthUser:
    id: UUID
    token: str


async def _refresh_jwks(s: Settings) -> bool:
    try:
        async with httpx.AsyncClient(timeout=8) as c:
            r = await c.get(f"{s.supabase_url}/auth/v1/.well-known/jwks.json", headers={"apikey": s.supabase_anon_key})
        r.raise_for_status()
        _jwks["keys"] = {k["kid"]: k for k in r.json().get("keys", []) if "kid" in k}
        _jwks["at"] = time.monotonic()
        return bool(_jwks["keys"])
    except Exception as e:
        log.warning("could not fetch Supabase signing keys: %s", type(e).__name__)
        return False


async def verify_locally(token: str, s: Settings) -> UUID | None:
    """The user a token belongs to, or None if it can't be checked here.
    Raises 401 for a token that is definitely bad (expired, forged, wrong audience)."""
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid_token") from None
    alg, kid = header.get("alg"), header.get("kid")
    if alg not in ("ES256", "RS256") or not kid:
        return None   # legacy shared-secret tokens can't be checked without the secret

    if kid not in _jwks["keys"] or time.monotonic() - _jwks["at"] > _JWKS_TTL_S:
        if not await _refresh_jwks(s) and kid not in _jwks["keys"]:
            return None
    jwk = _jwks["keys"].get(kid)
    if jwk is None:
        return None
    try:
        claims = jwt.decode(token, jwt.PyJWK(jwk).key, algorithms=[alg], audience="authenticated",
                            issuer=f"{s.supabase_url}/auth/v1", options={"require": ["exp", "sub"]})
        return UUID(claims["sub"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid_token") from None
    except (jwt.PyJWTError, ValueError):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid_token") from None


async def verify_remotely(token: str, s: Settings) -> UUID:
    """Ask Supabase. Retried, because one dropped connection must not fail an answered call."""
    last = "unreachable"
    for attempt in range(3):
        try:
            async with httpx.AsyncClient(timeout=8) as c:
                r = await c.get(f"{s.supabase_url}/auth/v1/user",
                                headers={"Authorization": f"Bearer {token}", "apikey": s.supabase_anon_key})
            if r.status_code in (401, 403):
                raise HTTPException(status.HTTP_401_UNAUTHORIZED, "invalid_token")
            if r.status_code == 200:
                return UUID(r.json()["id"])
            last = f"status {r.status_code}"
        except httpx.HTTPError as e:
            last = type(e).__name__
        await asyncio.sleep(0.4 * (attempt + 1))
    log.error("could not check a login with Supabase after 3 tries (%s)", last)
    raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "auth_unreachable")


async def current_user(
    authorization: str | None = Header(default=None),
    settings: Settings = Depends(get_settings),
) -> AuthUser:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing_token")
    token = authorization.split(" ", 1)[1].strip()

    hit = _cache.get(token)
    if hit and hit[0] > time.monotonic():
        return AuthUser(hit[1], token)

    if not settings.supabase_url:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, "auth_not_configured")

    uid = await verify_locally(token, settings) or await verify_remotely(token, settings)
    if len(_cache) > 2000:
        _cache.clear()
    _cache[token] = (time.monotonic() + _TTL_S, uid)
    return AuthUser(uid, token)
