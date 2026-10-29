**Story**
Mapa is for the ones you care about. Mapa is made for you to care for your parents, guardians, or partners or anyone. It would be great if you call your loved ones and take a check on their medicines or their current status. But in this busy life, maybe you can’t do that all the time especially if you’re the primary provider for the family. But I feel AI can help. What if AI calls your parents to take a check on whether they have taken their medicines, are they feeling okay. Maybe it sounds materialistic but it would definitely help a care taker to keep track of their loved ones.

**What does mapa do ?**
Mapa is a reminder which calls the parent, guardian, partner or patient to tremind them of their medicine and take a status check on them.

How does mapa work ?
Mapa got two personas. One - A parent/partner/patient/guardian. Two - Adult child/Guardian/Caretaker. 

Both of them get paired by a paring code or a QR code. The care taker would produce a pairing code and the parent would be entering the pairing code.

After the pairing has been done, the care taker can just the reminders out in the chat and the llm assistant would convert them as  schedulers as described by the caretaker .If the reminder is vague the AI assistant would ask follow up questions.At the patient side , they would be receiving calls from the schedulers.

Journey - User opens the app. They would be seeing the landing page/ home page with the logo and name and with a CTA button. - After pressing the CTA button, the user will be going through the onboarding screens to know about the app.(There would three onboarding screens)	
- The onboarding screens must only be seen by the user if he’s a new user.
- For the Caretaker  - There would be a unique code + QR generation screen.
- For Parent/Patient
    - The Caretaker’s QR should be scanned or the pairing code has to be entered.
- The Care taker’s Screen will be activated as soon as they’re paired with the patient.
    - The screen would be having two buttons in the middle if they’re no reminders added.
    - Add a Reminder , Add Another person
    - Add a reminder would take the care taker to a chat screen where the caretaker types out the reminder item with time and number of days or the kind of days (MTWTFSS).
    - After a reminder is added the + button go to the bottom right side of the screen with same options - add a reminder, add a person.
    - The backend scheduler triggers the call through WebRTC. The voice agent will get a check on the medicine status and captures the response 
- The Parent 
    - The parent would receive a call to the phone, they give the status

**Design**

- The design should be minimalistic, friendly
- Both dark and white modes should be included.
- The colour palettes should be in between bright and pale side so it looks pleasant and friendly
- Inspiration should be more from Duolingo and Waterllama App as they are good at gamifications and reminders.
- Give a good burry look wherever you feel it might give some aesthetic sense.
- Font should be Inter 
- The calling animation should be a bit cute 
- The calling animation should mimic the iOs slider effect with good blur


**Tech**
- Flutter for the front-end
- Python for the backend(Ask me if something else is better)
- Voice Pipeline
    - Any fast and cheaper model for LLM
    - Live kit for orchestration and handling the pipeline
    - STT/ASR - would be Eleven Labs/ Cartesia 
    - TTS would be Sarvam, Deepgram or Fish Audio


**Rules**
- The AI assistant should only able to take the input and create a scheduler, it should not generate texts or answer to some random questions.
- It can pop some options to get some clarity from the user to get specific of reminder.
- Even the voice agent shouldn’t entertain any other things other than parent’s status of medicine or their well being 

**Skills**
- Impeccable for design
- Taste-skill
- Emily Kowalski’s Design skill 
- Graphify for memory retention of the project.

**Output**
- A cross platform app which runs on both iOS and android.


**Conditions**
- I don't have a apple developer account so I just wanna run it on my own apple device with developer profile installed.
- I don't have much of a budget for this. If we can wrap it up with something cheaper and more cost effective why not. 
- We are not compromising on design and expereince, it should never feel materialistic even when using the app or while talking to the agent.

---

# Architecture & Build Plan (finalised)

## Decisions
- **Caretaker = iPhone** (free personal provisioning, no paid Apple account). **Recipient = Android.**
- The call is an **in-app VoIP call** (LiveKit/WebRTC) that rings the Android phone through an FCM high-priority push with a full-screen incoming-call UI. No phone-network calls, so the per-call telecom cost is zero.
- Voice languages: **English + Telugu**.
- Backend: **Supabase (Postgres/Auth/Realtime) + Python** service.
- Escalation: **alert the caretaker**, delivered **in-app only** (Supabase Realtime feed/banner). Native iOS push isn't available on free provisioning.

## System overview
```
Flutter app (one app, role picked at onboarding)
   │  supabase_flutter (auth, CRUD, realtime)        │ livekit_client (call)
   ▼                                                 ▼
Supabase ◄──────── Python service (Fly.io/Railway) ──► LiveKit Cloud (free tier)
 Postgres+RLS        ├─ FastAPI: /chat, /pairing, /calls/token     ▲
 Realtime            ├─ Scheduler loop (due occurrences → dispatch)│
                     ├─ FCM sender (wake Android, ring)            │
                     └─ LiveKit Agents worker (voice agent) ───────┘
                          STT/TTS: Sarvam (Telugu+English) · LLM: Gemini Flash
```

## Repo layout
- `app/`: Flutter (iOS + Android)
- `server/`: Python 3.12, `uv`-managed. `api/` (FastAPI), `scheduler/`, `agent/` (LiveKit worker), `shared/` (db, models, prompts)
- `supabase/migrations/`: SQL schema + RLS policies

## Data model (Supabase Postgres, RLS on every table)
- `profiles`: id (= auth uid), role (`caretaker`|`recipient`), display_name, language (`en`|`te`), timezone, fcm_token, onboarding_done
- `pairing_codes`: code (6 chars, unambiguous alphabet), caretaker_id, recipient_label, expires_at (15 min), used_at
- `care_links`: caretaker_id, recipient_id, nickname ("Amma"), created_at. One caretaker can have many recipients ("Add another person").
- `reminders`: id, link_id, medicine, dose, instructions, time_of_day, days_mask (MTWTFSS bitmask), start_date, end_date (nullable), active, created_from_chat (jsonb of the parsed intent)
- `call_occurrences`: id, reminder_id, scheduled_at (UTC), status (`pending|ringing|in_call|completed|no_answer|failed`), attempt, room_name
- `call_results`: occurrence_id, medicine_status (`taken|not_taken|will_take_later|unclear`), wellbeing (`good|okay|unwell`), note, transcript (jsonb), duration_s
- `alerts`: id, caretaker_id, link_id, kind (`missed_dose|no_answer|unwell`), occurrence_id, seen_at

Auth: **Supabase anonymous sign-in** (free, no SMS OTP cost). It can later be upgraded to Apple/Google linking so the account can be recovered.

## Flows
**Pairing.** The caretaker app calls `POST /pairing/codes` and shows the code + QR (`qr_flutter`). The recipient scans it (`mobile_scanner`) or types the code, then calls `POST /pairing/redeem`. The server creates the `care_links` row atomically. The caretaker screen listens on Realtime for the new link and switches to the paired home.

**Chat → reminder (strict).** `POST /chat` takes {link_id, messages}. The LLM runs with **forced tool calling only** and can never return free text. Tools:
- `create_reminder(medicine, dose?, times[], days_mask, start_date, duration_days|end_date)`
- `ask_clarification(question, options[])`: rendered as tappable chips in the chat
- `reject_off_topic()`: the client shows a fixed, friendly canned line

The server validates the tool args with Pydantic, shows a confirmation card in chat, and inserts `reminders` when the user confirms. Off-topic input never reaches a generative reply.

**Scheduling.**
- A loop runs every 30 s in the service. It materialises the next 48 h of `call_occurrences` from `reminders`, using the recipient's timezone and `days_mask`.
- It claims due rows with `SELECT … FOR UPDATE SKIP LOCKED`, which makes it safe to restart or run a second instance.

**Dispatch & ring.**
1. Create a LiveKit room (`mapa-<occurrence_id>`) and dispatch the agent to it with metadata (recipient name, language, medicine, dose).
2. Send an FCM **data-only high-priority** message to the recipient containing the room and a short-lived token.
3. Android shows a full-screen incoming call via `flutter_callkit_incoming`, with Mapa's own custom slide-to-answer UI when the app is in the foreground.
4. Answering joins the room through `livekit_client`.
5. No join within 45 s → `no_answer`. Retry once after 10 min, then raise a `no_answer` alert.

**Voice agent (LiveKit Agents, Python).**
- Pipeline: Silero VAD + LiveKit turn detector → **Sarvam STT (saarika)** → **Gemini 2.5 Flash** (cheap, good Telugu; Claude Haiku 5.5 as an alternative) → **Sarvam TTS (bulbul)**, with a warm voice per language. Sarvam covers both English and Telugu, so one vendor handles both directions. Deepgram and Cartesia are weak at Telugu.
- Script: greet by name → ask about the specific medicine → ask how they feel → close warmly. Target length is 60–90 s.
- Tools: `record_medicine_status`, `record_wellbeing(note)`, `end_call`. The system prompt hard-scopes the agent: anything off-topic gets a gentle redirect, and after 2 redirects the agent ends the call politely.
- After the call: write `call_results` and the transcript. `not_taken` / `unwell` → insert an `alerts` row.

**Caretaker alerts (in-app).**
- The app subscribes to `alerts` and `call_results` through Realtime and shows a blurred top banner plus an alert feed.
- An unseen-count badge appears on the person's card.
- Because there's no background push on iOS, the home screen always opens on "Today", showing each scheduled call's status.

## Flutter app
- Packages: `flutter_riverpod`, `go_router`, `supabase_flutter`, `livekit_client`, `firebase_messaging` (Android only), `flutter_callkit_incoming`, `mobile_scanner`, `qr_flutter`, `google_fonts` (Inter), `shared_preferences` (onboarding-seen flag), `flutter_animate`/`rive` (call animation, mascot).
- Screens:
  - Splash/landing (logo + CTA)
  - 3 onboarding screens (first launch only)
  - Role select
  - Caretaker: code/QR, home (empty state = two centred buttons "Add a reminder" / "Add another person"; after the first reminder, a bottom-right FAB with the same two options), chat, person detail (reminders + call history + streaks), alerts
  - Recipient: scan/enter code, calm idle screen ("Mapa will call you at 9:00"), incoming-call screen, in-call screen
- Design system: Inter; light + dark tokens; a soft "between bright and pale" palette (mint, peach, butter, lavender); `BackdropFilter` blur on banners, sheets, FAB menu and call screen; Duolingo/Waterllama-style streaks and rings on person cards; a cute pulsing-avatar incoming call with an iOS-style frosted slide-to-answer. During UI work, use the **impeccable**, **taste-skill** and **emil-design-eng** skills.

## Cost (approximate, monthly, small personal use)
- Supabase free
- LiveKit Cloud free tier
- Fly.io/Railway ≈ $0–5
- FCM free
- Sarvam: roughly ₹0.5–1 per call-minute for STT+TTS
- Gemini Flash: pennies

Caveats:
- A Supabase free project pauses after 7 days of inactivity. The scheduler's own traffic keeps it awake.
- The iOS app installed with free provisioning must be re-run from Xcode/`flutter run` every 7 days.

## Build phases
1. **Foundations.** Supabase project + migrations + RLS. Python service skeleton (FastAPI, config, Supabase service-role client). Flutter project with theme tokens, Inter, light/dark, routing.
2. **Onboarding & pairing.** Landing, onboarding (first launch), role select, anonymous auth, code/QR generation + scan/enter, the Realtime switch to the paired home.
3. **Chat → reminders.** `/chat` with forced tools + clarification chips + confirmation card. Reminders list. Empty-state → FAB transition.
4. **Calling.** Scheduler + occurrences, FCM + full-screen incoming call on Android, the LiveKit join, the voice agent worker (EN + TE), results capture.
5. **Caretaker insight.** Today view, call history, transcript summary, alerts feed/banner, streaks.
6. **Polish.** Animations (call slider, blur, mascot), copy tone, edge cases (no answer, retries, timezone/DST, unpair), graphify graph of the repo.

## Verification
- Backend: pytest for the reminder-intent parser (vague inputs → clarification; off-topic → reject), occurrence materialisation (days_mask, timezone, end_date), and claim/lock behaviour.
- Agent: `python -m agent console` (LiveKit Agents' local console mode) to talk to the agent in English and Telugu, including off-topic attempts.
- End-to-end:
  1. Caretaker on iPhone (`flutter run` with the personal team) and recipient on Android.
  2. Pair by QR.
  3. Create "Amma, BP tablet, 1 pill at 9 am every day for 30 days" plus a reminder 2 minutes from now.
  4. The Android phone rings while locked; answer it, say "not yet" → an alert appears in the caretaker app via Realtime.
  5. Decline a call → after the retry, a `no_answer` alert appears.


---

# Build status

**Done (UI phase, 2026-10-27):** Flutter app in `app/` with all 18 designed screens, light and dark, running on the iOS simulator. Design mockups are in `design/mockups/index.html`; the chosen direction is in `.impeccable/surfaces/app.md`. Everything on screen uses sample data from `app/lib/state.dart`; the flow is clickable end to end (landing, onboarding, role, pairing, Today, reminder chat, person, alerts, parent keypad, waiting, incoming call with slide-to-answer, on the call, done).

**Done (backend foundations, 2026-10-27):** `supabase/migrations/0001_init.sql` (tables, row-level security, atomic pairing and call-claiming) and `server/` (FastAPI API for profile, pairing, reminder chat and reminders; call scheduler; retry and alert rules). 59 tests pass, including the real migration run on an embedded Postgres. See `server/README.md`.

**Done (app connected to the backend, 2026-10-27):** the Flutter app now signs in anonymously, pairs for real (code + QR, realtime), chats reminders through the server, shows Today, People, person pages and alerts from live Supabase data, and the parent's phone shows its real schedule. Start the API (`server/`, see its README) and run the app with `flutter run --dart-define-from-file=config.local.json` (copy `config.example.json`). `integration_test/flow_test.dart` drives the whole caretaker flow on the simulator against the real backend; it needs the API running and uses 2 anonymous sign-ins per run (Supabase allows 30 per hour).

**Done (calling, built; live audio untested, 2026-10-27):** server dispatches a LiveKit room and the voice agent, the parent's phone rings in-app and joins, declining and no-answer redial and alerts work, the agent's script, hard limits and result recording are written and tested (82 server tests, plus app tests of pairing, chat, ringing and declining on the simulator). See `CALLING.md`.

**Done (locked-phone ringing, built, 2026-10-27):** the server sends a high-priority Firebase push when a call starts and cancels it when the call ends or times out; the Android app shows a native full-screen incoming call (ringtone, Answer, Not now) from the background or when closed, joins the call on Answer, and asks the parent for the needed permissions right after pairing. Needs Firebase to switch on: see `CALLING.md`. Untested on a real phone.

**Done (voice call rehearsed end to end, 2026-10-27):** a stand-in parent rang through the real stack and spoke to Mapa in English and Telugu; Mapa heard, replied in 0.3 to 0.5 s, recorded the result, said goodbye, hung up, and raised the unwell alert for a chest-pain call. Brain is Sarvam 105B Conversations (Gemini free tier was too slow). Not yet tried on real phones.

**Next:** (1) test real calls on an Android phone with a locked screen; (2) deploy the server so phones don't need your Mac; (3) per-brand battery-setting guide, and alerts push for the caretaker.

**Dev shortcuts (remove before release):** long-press the "mapa" wordmark on the landing screen for a jump-to-screen menu; long-press the sleeping mascot on the parent's waiting screen to simulate an incoming call.
