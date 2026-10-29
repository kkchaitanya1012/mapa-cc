# Mapa server

FastAPI service, call scheduler, and the LiveKit voice agent.

```
cd server
/opt/anaconda3/bin/python3.12 -m venv .venv && source .venv/bin/activate   # Python 3.12+
pip install -e ".[dev]"
python -m pytest                                  # ~130 tests, runs a real embedded Postgres, no setup
cp .env.example .env                              # then fill in your Supabase values
uvicorn mapa_server.api:app --reload              # API on :8000, docs at /docs
python -m mapa_server.scheduler                   # scheduler (separate process)
python -m mapa_server.voice.worker dev            # Mapa's voice (separate process; needs LiveKit + Sarvam keys)
```

## What's here
- `../supabase/migrations/`: `0001_init.sql` (tables, row-level security, `redeem_pairing_code`, `claim_due_occurrences`) and `0002_*` (Call now once per slot, reminders in realtime). Apply in order.
- `mapa_server/api.py`: `/me/profile`, `/me/push-token`, `/pairing/*`, `/chat`, `/reminders`, `/calls/{id}/join|decline|call-now`.
- `mapa_server/rules_provider.py`: offline reminder parser. `gemini_provider.py`: model-backed one (untested without a key).
- `mapa_server/schedule.py`: pure call-time, retry and alert rules.
- `mapa_server/scheduler.py`: materialise upcoming calls, claim due ones, record no-answer and call results.

- `mapa_server/calls.py`, `push.py`, `voice/`: LiveKit rooms and tokens, FCM ring, the voice agent.

## Not verified against real services
The Gemini provider and the live push to a real phone. See `../CALLING.md` for setup.
