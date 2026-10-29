# Mapa

*A call from you, even when you can't call.*

Mapa phones the people you care about so you don't have to remember to. At each scheduled time an AI voice agent calls your parent or patient (English or Telugu), asks about the specific medicine and how they feel, and reports back to you. Reminders are set by chatting ("Amma, BP tablet, 9 am, every day for a month"), not by filling in forms.

- **Caretaker** uses an iPhone: sets reminders, sees today's calls, call log and alerts.
- **Recipient** uses an Android phone: pairs once, then answers Mapa's call (full screen, over the lock screen when push is on).

This is a trial project. It currently runs from a development machine; there is no hosted deployment.

## Layout

| Path | What |
|---|---|
| `app/` | Flutter app (both roles). See `app/README.md`. |
| `server/` | FastAPI API, call scheduler and LiveKit voice agent. See `server/README.md`. |
| `supabase/migrations/` | Database schema, row-level security, realtime. Apply in order. |
| `design/mockups/index.html` | Static design mockups, open in a browser. |
| `PRODUCT.md`, `plan.md` | Product intent and architecture. |
| `CALLING.md` | Keys needed for calls and push, and how to try a call. |
| `.impeccable/` | Design-direction notes (`surfaces/app.md` is the visual contract). |

## Stack

Flutter, FastAPI (Python 3.12), Supabase (Postgres, Auth, Realtime), LiveKit Cloud (calls), Sarvam (voice and brain), Firebase Cloud Messaging (rings a locked Android phone).

## Run it

1. Create a Supabase project and apply `supabase/migrations/*.sql` in order.
2. Server: follow `server/README.md`, then `CALLING.md` for the LiveKit, Sarvam and Firebase values. Three processes: the API, the scheduler, the voice worker.
3. App: follow `app/README.md`. Phones must reach the API, so on a dev machine both must be on the same Wi-Fi.

## Secrets

Never committed: `server/.env`, `app/config.local.json`, `app/config.android.json`, the Firebase service-account JSON, `dist/`. Copy the `*.example` files and fill them in.
