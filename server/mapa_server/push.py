"""Push notifications: how a locked or closed phone finds out it is being called.

Firebase Cloud Messaging, HTTP v1. Messages are data-only and high priority so
Android wakes the app, which then shows the full-screen incoming call. Nothing
sensitive goes in the payload: a name, a medicine, and which call.
"""
import asyncio
import json
import logging
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Protocol

import httpx

from .config import Settings

log = logging.getLogger("mapa.push")

SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
RING_TTL_S = 60   # a ring that can't be delivered within a minute is worthless


@dataclass(frozen=True)
class SendResult:
    status: str     # "ok" | "dead_token" | "error"
    detail: str = ""


class Pusher(Protocol):
    async def ring(self, token: str, ctx: dict) -> SendResult: ...
    async def cancel(self, token: str, occurrence_id: str) -> SendResult: ...


def ring_payload(ctx: dict) -> dict[str, str]:
    """FCM data values must all be strings."""
    return {
        "type": "incoming_call",
        "occurrence_id": str(ctx["id"]),
        "name": str(ctx["nickname"]),
        "medicine": str(ctx["medicine"]),
        "caretaker": str(ctx.get("caretaker_name") or ""),
        "language": str(ctx.get("language") or "en"),
    }


def cancel_payload(occurrence_id: str) -> dict[str, str]:
    return {"type": "call_cancelled", "occurrence_id": str(occurrence_id)}


class NullPusher:
    """Used until Firebase is configured. Calls still ring inside the open app."""

    async def ring(self, token: str, ctx: dict) -> SendResult:
        return SendResult("error", "push not configured")

    async def cancel(self, token: str, occurrence_id: str) -> SendResult:
        return SendResult("error", "push not configured")


class FcmPusher:
    def __init__(self, service_account_file: str, *, client: httpx.AsyncClient | None = None,
                 token_provider: Callable[[], Awaitable[str]] | None = None) -> None:
        with open(service_account_file) as f:
            self.project_id = json.load(f)["project_id"]
        self._file = service_account_file
        self._client = client or httpx.AsyncClient(timeout=10)
        self._token_provider = token_provider or self._google_token
        self._creds = None

    async def _google_token(self) -> str:
        """An OAuth token for the service account; google-auth caches and refreshes it."""
        from google.auth.transport.requests import Request
        from google.oauth2 import service_account

        if self._creds is None:
            self._creds = service_account.Credentials.from_service_account_file(self._file, scopes=[SCOPE])
        if not self._creds.valid:
            await asyncio.to_thread(self._creds.refresh, Request())
        return self._creds.token

    async def _send(self, token: str, data: dict[str, str]) -> SendResult:
        body = {"message": {
            "token": token,
            "data": data,
            "android": {"priority": "HIGH", "ttl": f"{RING_TTL_S}s"},
        }}
        try:
            r = await self._client.post(
                f"https://fcm.googleapis.com/v1/projects/{self.project_id}/messages:send",
                headers={"authorization": f"Bearer {await self._token_provider()}"}, json=body)
        except httpx.HTTPError as e:
            return SendResult("error", type(e).__name__)
        if r.status_code == 200:
            return SendResult("ok")
        code = ""
        try:
            for d in r.json().get("error", {}).get("details", []):
                code = d.get("errorCode") or code
            code = code or r.json().get("error", {}).get("status", "")
        except ValueError:
            pass
        if r.status_code == 404 or code in ("UNREGISTERED", "INVALID_ARGUMENT"):
            return SendResult("dead_token", code)   # the app was uninstalled or the token is stale
        return SendResult("error", f"{r.status_code} {code}")

    async def ring(self, token: str, ctx: dict) -> SendResult:
        return await self._send(token, ring_payload(ctx))

    async def cancel(self, token: str, occurrence_id: str) -> SendResult:
        return await self._send(token, cancel_payload(occurrence_id))


_cache: dict[str, Pusher] = {}


def get_pusher(s: Settings) -> Pusher:
    """One sender per service-account file, so its OAuth token is reused between calls."""
    path = s.fcm_service_account_file
    if not path:
        return NullPusher()
    if path not in _cache:
        try:
            _cache[path] = FcmPusher(path)
        except (OSError, KeyError, ValueError):
            log.exception("could not load the Firebase service account; push is off")
            return NullPusher()
    return _cache[path]
