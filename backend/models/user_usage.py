from datetime import datetime, timezone
from pydantic import BaseModel, Field


def _utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class UsageStats(BaseModel):
    """Represents a set of usage metrics for a period."""

    transcription_seconds: int = 0
    words_transcribed: int = 0
    insights_gained: int = 0
    memories_created: int = 0
    speech_seconds: int = 0


class HourlyUsage(UsageStats):
    """Represents the hourly usage data stored in the database."""

    uid: str
    year: int
    month: int
    day: int
    hour: int
    last_updated: datetime = Field(default_factory=_utc_now)
