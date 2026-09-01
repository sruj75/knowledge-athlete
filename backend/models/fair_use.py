from datetime import datetime, timezone
from enum import Enum
from typing import Annotated, Optional

from pydantic import BaseModel, ConfigDict, Field, StringConstraints


def _utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class FairUseStage(str, Enum):
    """Graduated enforcement stages."""

    NONE = "none"
    WARNING = "warning"
    THROTTLE = "throttle"
    RESTRICT = "restrict"


class UsageType(str, Enum):
    """Types of detected non-personal usage."""

    NONE = "none"
    AUDIOBOOK = "audiobook"
    PODCAST = "podcast"
    PRERECORDED = "prerecorded"
    TV_MOVIE = "tv_movie"
    COMMERCIAL = "commercial"
    UNKNOWN = "unknown"
    FREE_EXHAUSTED = "free_exhausted"


def normalize_usage_type(value: object) -> UsageType:
    """Project an untrusted classifier value onto the durable closed enum."""
    if value is None or value == '':
        return UsageType.NONE
    if isinstance(value, UsageType):
        return value
    try:
        return UsageType(value)
    except (TypeError, ValueError):
        return UsageType.UNKNOWN


class SoftCapTrigger(str, Enum):
    """Which rolling window triggered the soft cap."""

    DAILY = "daily"
    THREE_DAY = "3day"
    WEEKLY = "weekly"


class FairUseConversationEvidence(BaseModel):
    """The complete, bounded transient evidence shape accepted from an owner Mac."""

    model_config = ConfigDict(extra='forbid')

    conversation_id: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=64)]
    title: Annotated[str, StringConstraints(max_length=512)] = ''
    overview: Annotated[str, StringConstraints(max_length=200)] = ''
    category: Annotated[str, StringConstraints(max_length=64)] = ''
    duration_minutes: float = Field(ge=0, le=10_080, allow_inf_nan=False)
    source: Annotated[str, StringConstraints(max_length=64)] = ''
    created_at: datetime


class FairUseClassificationRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')

    conversations: list[FairUseConversationEvidence] = Field(max_length=30)


class FairUseClassificationResponse(BaseModel):
    model_config = ConfigDict(extra='forbid')

    review_id: str
    accepted: bool
    idempotent: bool
    action: str
    stage: FairUseStage
    case_ref: str = ''


class FairUseState(BaseModel):
    """Per-user fair use enforcement state. Stored at users/{uid}/fair_use_state/current."""

    stage: FairUseStage = FairUseStage.NONE
    violation_count_7d: int = 0
    violation_count_30d: int = 0
    last_violation_at: Optional[datetime] = None
    throttle_until: Optional[datetime] = None
    restrict_until: Optional[datetime] = None
    last_classifier_score: float = 0.0
    last_classifier_type: UsageType = UsageType.NONE
    updated_at: datetime = Field(default_factory=_utc_now)


class FairUseEvent(BaseModel):
    """A single fair-use violation event. Stored at users/{uid}/fair_use_events/{event_id}."""

    model_config = ConfigDict(extra='forbid')

    created_at: datetime = Field(default_factory=_utc_now)
    session_id: str = ""
    trigger: SoftCapTrigger = SoftCapTrigger.DAILY
    window_speech_ms: dict[str, int] = Field(default_factory=dict[str, int])  # {daily, three_day, weekly}
    thresholds_ms: dict[str, int] = Field(default_factory=dict[str, int])  # snapshot of active thresholds
    review_id: str = ''
    classifier_score: float = 0.0
    classifier_type: UsageType = UsageType.NONE
    classifier_confidence: float = 0.0
    classifier_model: str = 'gemini/gemini-3.7-flash'
    classifier_prompt_version: str = 'v2'
    enforcement_action: str = ""  # warning, throttle, restrict, none
    previous_stage: FairUseStage = FairUseStage.NONE
    new_stage: FairUseStage = FairUseStage.NONE
    case_ref: str = ''
    admin_notes: str = ""
    resolved: bool = False
    resolved_at: Optional[datetime] = None
    resolved_by: str = ""


class FairUseUserSummary(BaseModel):
    """Summary for protected support operations."""

    uid: str
    stage: FairUseStage = FairUseStage.NONE
    violation_count_7d: int = 0
    violation_count_30d: int = 0
    last_violation_at: Optional[datetime] = None
    last_classifier_score: float = 0.0
    last_classifier_type: UsageType = UsageType.NONE
    speech_hours_today: float = 0.0
    speech_hours_7d: float = 0.0
