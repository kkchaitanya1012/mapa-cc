# Turning calling on

Calls are built and have been rehearsed end to end (English, Telugu, and an emergency) with a stand-in parent: `python tools/rehearse_call.py en|te` from `server/`.
Put the values in `server/.env` (copy `server/.env.example` if you haven't).

| What | Where to get it | `.env` keys |
|---|---|---|
| **LiveKit Cloud** (carries the call) | cloud.livekit.io: new project, then Settings, Keys | `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` |
| **Sarvam** (hears, speaks and thinks, in English and Telugu) | dashboard.sarvam.ai: API keys | `SARVAM_API_KEY` |
| Gemini (optional alternative brain) | aistudio.google.com: Get API key | `GEMINI_API_KEY`, and `LLM_PROVIDER=gemini` |

**Why Sarvam is the default brain:** measured on Mapa's own task, `sarvam-105b-conversations` answered in about 0.3 s with correct tool calls and natural Telugu. Gemini on a free key took 3 to 50 s and often returned server errors, which makes a phone call unusable. Re-test Gemini on a paid key before switching.

## Run it (three processes, from `server/`, with the venv active)

```
uvicorn mapa_server.api:app --host 0.0.0.0 --port 8000   # the API
python -m mapa_server.scheduler                           # rings calls at their time
python -m mapa_server.voice.worker dev                    # Mapa's voice (the agent)
```

## Try a call

1. Caretaker phone: Today, then **Call now** on the next-call card.
2. Within about 10 seconds the parent's phone shows **Mapa is calling** (the app must be open).
3. Slide to answer. Mapa asks about the medicine, then how they feel, then says goodbye.
4. The caretaker sees the answer under Call log, and an alert if the medicine wasn't taken or they said they feel unwell.

## What is and isn't there

- Works: ringing, answering, declining, no-answer redial (once, after 10 minutes) then an alert, the call cap (4 minutes), hanging up when Mapa finishes, captions on the parent's screen.
- Built, needs Firebase to switch on: **ringing a locked or closed Android phone** with a full-screen call, ringtone, Answer and Not now (see below).
- **Check by ear:** the voices (`VOICE_EN`, `VOICE_TE` in `.env`) and the Telugu lines in `server/mapa_server/voice/prompts.py`. A Telugu speaker should read those before real use.
- Emergencies: if a parent describes one, Mapa tells them to call 112 (set `EMERGENCY_NUMBER` for another country), alerts the caretaker as "unwell", and ends the call. It never gives medical advice.

## Ringing a locked or closed phone (Firebase push)

Without this, the parent's phone only rings while Mapa is open. With it, the phone rings like a normal call: over the lock screen, with the ringtone, even if Mapa was closed. Firebase is free for this.

1. **Create a Firebase project** at console.firebase.google.com (Google Analytics can stay off).
2. **Add an Android app** to it with the package name `app.mapa.mapa`. Download `google-services.json` when it offers.
3. **Run** `python3 app/tools/firebase_config.py ~/Downloads/google-services.json`. It copies the four values the app needs into `app/config.android.json` (not committed).
4. **Server key:** Project settings, Service accounts, Generate new private key. Save the JSON outside the repo (say `~/mapa-firebase.json`) and set `FCM_SERVICE_ACCOUNT_FILE=/Users/you/mapa-firebase.json` in `server/.env`. Restart the API and the scheduler.
5. **Rebuild the app:** `flutter build apk --release --dart-define-from-file=config.android.json`, and install it on the parent's Android phone.

On the parent's phone, after pairing, Mapa shows **Let Mapa ring you** and asks for three things: notifications, showing calls on the lock screen (Android 14 asks you to switch this on in Settings), and the microphone.

**Test it:** lock the parent's phone, then on the caretaker's phone tap **Call now**. Within about 10 seconds the parent's phone should ring full-screen. Answer joins the call; Not now sends it to redial later; ignoring it hangs up after 45 seconds and the caretaker gets an alert after the second try.

**Watch for:**
- Some brands (Xiaomi, Oppo, Vivo, Huawei, and Samsung's "sleeping apps") stop apps in the background and delay push. On those phones set Mapa to "Unrestricted" or "No restrictions" under battery settings. A fix we can build later is a first-run guide for each brand.
- Calls only ring phones registered after the app was last opened as the parent, so open Mapa once on their phone after installing.
- The first answer from a cold lock screen can take a couple of seconds longer while the app starts.
