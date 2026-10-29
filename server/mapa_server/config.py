from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Supabase project (Settings -> API)
    supabase_url: str = ""
    supabase_anon_key: str = ""
    # Direct Postgres connection string (Settings -> Database). Uses the owner
    # role, so it bypasses RLS: only this service ever holds it.
    database_url: str = ""

    # Reminder chat. "rules" is an offline parser for development and tests;
    # "gemini" calls the model with forced tool use.
    chat_provider: str = "sarvam"   # "sarvam" (with offline fallback), "gemini", or "rules"
    gemini_api_key: str = ""
    gemini_model: str = "gemini-3.5-flash-lite"
    # Which model runs the phone call: "sarvam" (fast, native Telugu, same key as the voices) or "gemini".
    # Measured: Sarvam answers in ~0.3 s; Gemini on a free key took 3 to 50 s and often errored.
    llm_provider: str = "sarvam"
    sarvam_model: str = "sarvam-105b-conversations"
    # Model for typed reminders. The plain 105B reasons for ~5 s and can run out of tokens; this one answers in ~0.4 s.
    sarvam_chat_model: str = "sarvam-105b-conversations"
    # How hard Gemini thinks before answering: minimal, low, medium, high, or empty for the model default.
    # A phone call needs minimal; the default thinks for seconds.
    gemini_thinking: str = "minimal"

    # Pairing
    pairing_code_ttl_minutes: int = 15
    pairing_attempts_per_10min: int = 5

    # LiveKit Cloud (calls). Free tier is plenty for a family.
    livekit_url: str = ""
    livekit_api_key: str = ""
    livekit_api_secret: str = ""
    agent_name: str = "mapa-caller"

    # Push (Firebase Cloud Messaging) rings a locked or closed Android phone.
    # Path to the service-account JSON from Firebase: Project settings -> Service accounts.
    fcm_service_account_file: str = ""

    # Voice (Sarvam covers English and Telugu, in and out)
    sarvam_api_key: str = ""
    voice_en: str = "priya"
    voice_te: str = "kavya"

    # Calls
    ring_timeout_s: int = 45        # how long a phone rings before it counts as unanswered
    max_call_minutes: int = 4       # hard cap on one call
    emergency_number: str = "112"   # said to the parent if they describe an emergency

    # Scheduling
    schedule_horizon_hours: int = 48
    retry_after_minutes: int = 10
    max_attempts: int = 2


@lru_cache
def get_settings() -> Settings:
    return Settings()
