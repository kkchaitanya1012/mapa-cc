"""The voice agent: joins a call room, talks to the parent, writes down the result.

Run it next to the scheduler:
    python -m mapa_server.voice.worker dev      # local, auto-reload
    python -m mapa_server.voice.worker start    # production
"""
import asyncio
import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Annotated, Literal
from uuid import UUID

from google.genai import types
from livekit import rtc
from livekit.agents import Agent, AgentServer, AgentSession, JobContext, JobProcess, RunContext, cli, function_tool
from livekit.plugins import google, sarvam, silero

from .. import db, scheduler
from ..config import Settings, get_settings
from .prompts import LANG_CODES, goodbye_cap, greeting, instructions
from .state import CallState

log = logging.getLogger("mapa.voice")

# The LiveKit agents runtime reads its connection details from the environment, not from our
# settings file, so hand them over (before it starts, and so inherited by its job processes).
_s = get_settings()
for _k, _v in (("LIVEKIT_URL", _s.livekit_url), ("LIVEKIT_API_KEY", _s.livekit_api_key),
               ("LIVEKIT_API_SECRET", _s.livekit_api_secret)):
    if _v:
        os.environ.setdefault(_k, _v)

MAX_PARENT_TURNS = 14   # a short check-in never needs more; this stops a call that has wandered


class MapaAgent(Agent):
    """Mapa on the phone. The only things it can *do* are the three tools below."""

    def __init__(self, meta: dict, state: CallState, done: asyncio.Event, s: Settings) -> None:
        super().__init__(instructions=instructions(meta, emergency_number=s.emergency_number))
        self.meta, self.state, self.done = meta, state, done

    @function_tool
    async def record_medicine_status(
        self, context: RunContext,
        status: Annotated[Literal["taken", "not_taken", "will_take_later", "unclear"], "what they told you"],
        quote: Annotated[str, "a very short quote of their words, in English"],
    ) -> str:
        """Write down whether they took their medicine. Call this as soon as they answer."""
        self.state.set_medicine(status, quote)
        log.info("tool record_medicine_status(%s)", status)
        return "Recorded. Now ask how they are feeling today."

    @function_tool
    async def record_wellbeing(
        self, context: RunContext,
        wellbeing: Annotated[Literal["good", "okay", "unwell"], "how they say they feel"],
        note: Annotated[str, "a short note in their words, in English"],
    ) -> str:
        """Write down how they are feeling. Call this once they have told you."""
        self.state.set_wellbeing(wellbeing, note)
        self.state.wrapping_up = True      # the server hangs up after the goodbye, whether or not the model does
        log.info("tool record_wellbeing(%s)", wellbeing)
        return "Recorded. Say one warm goodbye sentence, then call end_call."

    @function_tool
    async def end_call(self, context: RunContext) -> str:
        """Hang up. Call this only after you have said goodbye."""
        log.info("tool end_call")
        # Don't hang up yet: the goodbye may still be coming. The call ends when it has been said
        # (see the state handler below), or after a short grace period if there is nothing to say.
        self.state.wrapping_up = True
        asyncio.get_running_loop().call_later(15, self.done.set)
        return "Call ended."


def prewarm(proc: JobProcess) -> None:
    proc.userdata["vad"] = silero.VAD.load()


server = AgentServer()
server.setup_fnc = prewarm


def build_session(meta: dict, vad, s: Settings) -> AgentSession:
    lang = meta.get("language", "en")
    code = LANG_CODES.get(lang, "en-IN")
    if s.llm_provider == "gemini":
        thinking = ({"thinking_config": types.ThinkingConfig(thinking_level=types.ThinkingLevel[s.gemini_thinking.upper()])}
                    if s.gemini_thinking else {})
        brain = google.LLM(model=s.gemini_model, api_key=s.gemini_api_key, temperature=0.3, **thinking)
    else:
        brain = sarvam.LLM(model=s.sarvam_model, api_key=s.sarvam_api_key, temperature=0.3)
    return AgentSession(
        vad=vad,
        stt=sarvam.STT(language=code, api_key=s.sarvam_api_key),
        llm=brain,
        tts=sarvam.TTS(target_language_code=code, speaker=s.voice_te if lang == "te" else s.voice_en,
                       api_key=s.sarvam_api_key),
    )


async def finish(meta: dict, state: CallState, s: Settings, *, joined: bool) -> None:
    """Write the outcome. Safe to call once, whatever way the call ended."""
    occ = UUID(meta["occurrence_id"])
    now = datetime.now(timezone.utc)
    await db.ensure_pool()
    out = state.outcome() if joined else None
    async with db.connection() as conn:
        if out is None or out.kind == "no_answer":
            await scheduler.mark_no_answer(conn, occ, now=now, s=s)
        else:
            kinds = await scheduler.record_result(
                conn, occ, medicine_status=out.medicine_status, wellbeing=out.wellbeing, note=out.note,
                transcript=state.transcript, duration_s=state.duration_s(), now=now)
            log.info("call %s done: %s / %s, alerts=%s", occ, out.medicine_status, out.wellbeing, kinds)


@server.rtc_session(agent_name=get_settings().agent_name)
async def entrypoint(ctx: JobContext) -> None:
    s = get_settings()
    meta = json.loads(ctx.job.metadata or "{}")
    state, done = CallState(), asyncio.Event()
    await ctx.connect()
    log.info("waiting for %s to pick up (%s)", meta.get("name"), meta.get("occurrence_id"))

    # Nobody picks up before the room closes: the scheduler handles the redial.
    try:
        await asyncio.wait_for(ctx.wait_for_participant(), timeout=s.ring_timeout_s + 15)
    except asyncio.TimeoutError:
        log.info("nobody answered")
        return

    state = CallState()  # the clock starts when they answer
    ctx.room.on("participant_disconnected", lambda p: done.set())
    session = build_session(meta, ctx.proc.userdata["vad"], s)

    @session.on("conversation_item_added")
    def _on_item(ev) -> None:
        role = getattr(ev.item, "role", None)   # tool calls and handoffs are items too; only messages have a role
        text = getattr(ev.item, "text_content", None) or ""
        who = "mapa" if role == "assistant" else "parent" if role == "user" else None
        if who and text:
            state.add_turn(who, text)
            if state.user_turns >= MAX_PARENT_TURNS:
                done.set()

    spoke_goodbye = {"started": False}
    t_last = {"t": time.monotonic()}

    @session.on("agent_state_changed")
    def _on_state(ev) -> None:
        now = time.monotonic()
        log.info("mapa %s -> %s (+%.1fs)", ev.old_state, ev.new_state, now - t_last["t"])
        t_last["t"] = now
        if not state.wrapping_up:
            return
        if ev.new_state == "speaking":
            spoke_goodbye["started"] = True
        elif ev.new_state == "listening" and spoke_goodbye["started"]:
            # The goodbye has been said. Give the audio a moment to drain, then hang up.
            asyncio.get_running_loop().call_later(1.5, done.set)

    @session.on("close")
    def _on_close(ev) -> None:
        done.set()

    await session.start(MapaAgent(meta, state, done, s), room=ctx.room)
    await session.say(greeting(meta), allow_interruptions=True)

    try:
        await asyncio.wait_for(done.wait(), timeout=s.max_call_minutes * 60)
    except asyncio.TimeoutError:
        await session.say(goodbye_cap(meta), allow_interruptions=False)
    finally:
        try:
            await finish(meta, state, s, joined=True)
        finally:
            try:
                await session.aclose()    # stop cleanly before the room goes away
            except Exception:
                pass
            await ctx.delete_room()   # hang up the parent's phone


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    cli.run_app(server)
