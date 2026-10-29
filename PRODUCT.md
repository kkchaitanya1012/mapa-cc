# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

One branded Mapa design language on both OSes, not per-OS controls. In practice, the caretaker side runs on iPhone and the recipient side runs on Android, so each side honours its OS guarantees: on iOS, safe areas, edge-swipe back and Reduce Motion; on Android, system Back, edge-to-edge insets and the remove-animations setting.

## Stack

Flutter (iOS + Android) front end. Python backend (FastAPI + LiveKit Agents), Supabase (Postgres/Auth/Realtime), LiveKit Cloud for WebRTC calls, FCM to ring the Android recipient. The full architecture is in `plan.md`.

## Users

- **Caretaker:** an adult child, guardian or partner who is the busy primary provider for the family. They can't call every day to check on medicines. They use an iPhone. Their job is to set reminders quickly in plain language and glance at whether their person is okay.
- **Recipient:** a parent, partner, guardian or patient, often elderly (60+) but comfortable with a smartphone. They use Android. Their job is almost passive: pair once, then answer Mapa's call and say whether they took their medicine and how they feel. Speaks English or Telugu.

## Product Purpose

Mapa phones the people you care about, so you don't have to remember to. At each scheduled time, an AI voice agent calls the recipient, checks on the specific medicine and their wellbeing, and reports back to the caretaker. Success means the caretaker trusts that someone checked in, and the recipient feels cared for rather than monitored.

## Positioning

Not a pill-box alarm: Mapa actually talks to your parent, in their own language (Telugu or English), and closes the loop back to you. Reminders are set by chatting naturally ("Amma, BP tablet, 9 am, every day for a month"), not by filling in forms.

## Operating Context

- **Pairing.** The caretaker generates a pairing code + QR. The recipient scans it or types it. One caretaker can care for several people ("Add another person").
- **Reminder chat.** The caretaker types reminders in a chat. The assistant only turns them into schedules and asks clarifying questions as tappable options. It never chats about anything else.
- **The call.** The call arrives on the recipient's Android phone as an in-app VoIP call with a full-screen incoming-call UI. The voice agent stays strictly on medicine status and wellbeing.
- **Alerts.** A missed dose, an unwell answer or an unanswered call raises an alert for the caretaker, shown in-app only. There's no iOS background push, because there's no paid Apple developer account.

## Capabilities and Constraints

- The caretaker iOS build is sideloaded with a free personal provisioning profile: no push notifications, and it must be reinstalled every 7 days.
- Low budget: free tiers wherever possible.
- Onboarding (3 screens) shows only on first launch.
- Caretaker home has two states: an empty state with two centred actions ("Add a reminder", "Add another person"), then, once a reminder exists, a bottom-right + button with the same two actions.
- Languages: English and Telugu (voice). The recipient UI language is undecided; English for now.

## Brand Commitments

- Name: **Mapa**.
- Voice: **playful buddy**. Duolingo-style cheeky warmth, streak celebrations, fun nudges. It must never feel clinical, transactional or "materialistic", either in the app or on the call.
- Font: **Inter** (binding, from the brief).
- Light and dark modes are both required.
- Palette sits "between bright and pale": pleasant and friendly, neither neon nor washed out.
- References the user named: Duolingo and Waterllama (gamification, reminders).
- Tasteful blur where it adds aesthetic value.
- The incoming-call animation should be cute, and it should mimic the iOS slide-to-answer with a good blur.

## Evidence on Hand

No logo, mascot, illustrations, testimonials or user data exist yet. Any mascot or illustration has to be authored, and no usage statistics or claims may be fabricated.

## Product Principles

1. Care, not surveillance: every screen and call should feel like love from the caretaker, never like monitoring.
2. Effortless on both ends: the caretaker sets reminders in one sentence, and the recipient only has to answer a call.
3. Stay on task: the chat assistant and the voice agent do one job and gently refuse everything else.
4. Delight earns habit: streaks and small celebrations make showing up feel good for both people.

## Accessibility & Inclusion

The recipient may be 60+: large text, high contrast, big touch targets, and as few taps and as little reading as possible on recipient screens. Respect system font scaling, and the Reduce Motion / remove-animations settings on both OSes.
