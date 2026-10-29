"""A stand-in parent. Rings through the real stack and talks to Mapa with real audio.

Needs the API, scheduler and voice worker running (see CALLING.md). Run from server/ with the venv on:

    python tools/rehearse_call.py en|te
    BOTSAY="I have a pain in my chest." python tools/rehearse_call.py en   # custom lines, separated by |

Uses 2 anonymous sign-ins per run (Supabase allows 30 an hour)
Creates two throwaway anonymous users and deletes exactly those two at the end.
"""
import asyncio, base64, io, json, sys, time, wave
import httpx, psycopg
from livekit import rtc
from mapa_server.config import get_settings

LANG = sys.argv[1] if len(sys.argv) > 1 else "en"
S = get_settings()
API = "http://127.0.0.1:8000"
SAY = {
    "en": ["Yes, I took it after breakfast.", "I am feeling good, thank you."],
    "te": ["అవును, ఉదయం ఇడ్లీ తిన్నాక వేసుకున్నాను.", "నేను బాగానే ఉన్నాను, ధన్యవాదాలు."],
}[LANG]
import os
if os.environ.get('BOTSAY'): SAY = os.environ['BOTSAY'].split('|')
TTS_LANG = {"en": ("en-IN", "rahul"), "te": ("te-IN", "rahul")}[LANG]
SR = 16000


def log(*a):
    print(f"[{time.strftime('%H:%M:%S')}]", *a, flush=True)


async def signup(c):
    r = await c.post(f"{S.supabase_url}/auth/v1/signup", headers={"apikey": S.supabase_anon_key}, json={})
    r.raise_for_status()
    j = r.json()
    return j["user"]["id"], {"authorization": f"Bearer {j['access_token']}"}


async def speech_pcm(c, text):
    r = await c.post("https://api.sarvam.ai/text-to-speech",
                     headers={"api-subscription-key": S.sarvam_api_key},
                     json={"text": text, "target_language_code": TTS_LANG[0], "speaker": TTS_LANG[1],
                           "model": "bulbul:v3", "speech_sample_rate": SR})
    r.raise_for_status()
    w = wave.open(io.BytesIO(base64.b64decode(r.json()["audios"][0])))
    assert w.getframerate() == SR and w.getnchannels() == 1, (w.getframerate(), w.getnchannels())
    return w.readframes(w.getnframes())


async def main():
    uids = []
    async with httpx.AsyncClient(timeout=30) as c:
        try:
            care_id, A = await signup(c); par_id, B = await signup(c); uids = [care_id, par_id]
            put = lambda h, **kw: c.put(f"{API}/me/profile", headers=h, json=kw)
            assert (await put(A, role="caretaker", display_name="Priya")).status_code == 200
            assert (await put(B, role="recipient", display_name="", language=LANG)).status_code == 200
            code = (await c.post(f"{API}/pairing/codes", headers=A, json={"recipient_label": "Amma"})).json()["code"]
            assert (await c.post(f"{API}/pairing/redeem", headers=B, json={"code": code})).status_code == 200
            link = (await c.get(f"{S.supabase_url}/rest/v1/care_links?select=id", headers={**A, "apikey": S.supabase_anon_key})).json()[0]["id"]
            today = time.strftime("%Y-%m-%d")
            draft = {"medicine": "BP tablet", "dose": None, "times": ["09:00:00"], "days_mask": 127, "start_date": today}
            assert (await c.post(f"{API}/reminders", headers=A, json={"link_id": link, "draft": draft})).status_code == 201
            with psycopg.connect(S.database_url) as db:
                occ = db.execute("select o.id from call_occurrences o join reminders r on r.id=o.reminder_id where r.link_id=%s order by o.scheduled_at limit 1", (link,)).fetchone()[0]
            log("set up: caretaker + parent paired, reminder created, call", str(occ)[:8])

            assert (await c.post(f"{API}/calls/{occ}/call-now", headers=A)).status_code == 202
            log("caretaker tapped Call now; waiting for the scheduler to ring...")
            t0 = time.time()
            while True:
                with psycopg.connect(S.database_url) as db:
                    st = db.execute("select status from call_occurrences where id=%s", (occ,)).fetchone()[0]
                if st == "ringing": break
                if time.time() - t0 > 40: raise SystemExit(f"never rang (status {st})")
                await asyncio.sleep(1)
            log(f"phone is ringing ({time.time()-t0:.0f}s after Call now)")

            j = (await c.post(f"{API}/calls/{occ}/join", headers=B))
            log("parent slid to answer: join ->", j.status_code)
            j = j.json()

            room = rtc.Room()
            agent_audio = {"last_voice": 0.0, "first_voice": 0.0, "voiced_s": 0.0}
            closed = asyncio.Event()

            @room.on("disconnected")
            def _(*_a): closed.set()

            async def listen(track):
                async for ev in rtc.AudioStream(track):
                    f = ev.frame
                    import array
                    pcm = array.array("h", bytes(f.data))
                    peak = max((abs(x) for x in pcm[::8]), default=0)
                    if peak > 900:
                        now = time.time()
                        agent_audio["first_voice"] = agent_audio["first_voice"] or now
                        agent_audio["last_voice"] = now
                        agent_audio["voiced_s"] += f.samples_per_channel / f.sample_rate

            @room.on("track_subscribed")
            def _(track, pub, participant):
                if track.kind == rtc.TrackKind.KIND_AUDIO:
                    asyncio.create_task(listen(track))

            await room.connect(j["url"], j["token"])
            src = rtc.AudioSource(SR, 1)
            mic = rtc.LocalAudioTrack.create_audio_track("mic", src)
            await room.local_participant.publish_track(mic, rtc.TrackPublishOptions(source=rtc.TrackSource.SOURCE_MICROPHONE))
            log("parent is in the call room")

            async def agent_finished_speaking(timeout=45):
                t = time.time()
                while time.time() - t < timeout:
                    la = agent_audio["last_voice"]
                    if la and time.time() - la > 1.4 and not closed.is_set():
                        return True
                    if closed.is_set(): return False
                    await asyncio.sleep(0.2)
                return False

            async def speak(pcm):
                n = SR // 100  # 10 ms
                for i in range(0, len(pcm), n * 2):
                    chunk = pcm[i:i + n * 2]
                    if len(chunk) < n * 2: chunk += b"\x00" * (n * 2 - len(chunk))
                    fr = rtc.AudioFrame.create(SR, 1, n); memoryview(fr.data).cast("B")[:] = chunk
                    await src.capture_frame(fr)
                await src.wait_for_playout()

            for i, line in enumerate(SAY):
                if not await agent_finished_speaking():
                    log("Mapa never finished / call closed early"); break
                agent_audio["last_voice"] = 0.0
                log(f"Mapa spoke ({agent_audio['voiced_s']:.1f}s so far). parent says: {line}")
                await speak(await speech_pcm(c, line))
            try:
                await asyncio.wait_for(closed.wait(), 50)
                log("Mapa hung up the call")
            except asyncio.TimeoutError:
                log("call still open after 50s; hanging up from the parent side")
                await room.disconnect()
            await asyncio.sleep(4)

            with psycopg.connect(S.database_url) as db:
                occ_row = db.execute("select status, started_at, ended_at from call_occurrences where id=%s", (occ,)).fetchone()
                res = db.execute("select medicine_status, wellbeing, note, duration_s, transcript from call_results where occurrence_id=%s", (occ,)).fetchone()
                alerts = db.execute("select kind, message from alerts where caretaker_id=%s", (care_id,)).fetchall()
            log("call status:", occ_row[0])
            if res:
                log(f"RESULT medicine={res[0]} wellbeing={res[1]} duration={res[3]}s")
                log("note for the caretaker:", res[2])
                for t in res[4]: print(f"      {t['who']:>6}: {t['text']}")
            else:
                log("NO RESULT RECORDED")
            log("alerts raised:", alerts or "none")
        finally:
            if uids:
                with psycopg.connect(S.database_url) as db:
                    db.execute("delete from auth.users where id = any(%s::uuid[])", (uids,)); db.commit()
                log("cleaned up the 2 test users")

asyncio.run(main())
