"""Minimal persisted shape used only by the temporary S-25 finalizer drain.

Durable product conversations are Mac-local. This model intentionally omits
the retired hosted recording, identity, protection, provenance, mutation, and
compatibility envelopes. Unknown historical fields are ignored while an
already-queued finalization job drains.
"""

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field

from models.conversation_enums import ConversationStatus
from models.geolocation import Geolocation
from models.structured import Structured
from models.transcript_segment import TranscriptSegment


class Conversation(BaseModel):
    model_config = ConfigDict(extra='ignore')

    id: str
    created_at: datetime
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    language: Optional[str] = None
    structured: Structured = Field(default_factory=Structured)
    transcript_segments: List[TranscriptSegment] = Field(default_factory=list)
    geolocation: Optional[Geolocation] = None
    discarded: bool = False
    status: ConversationStatus = ConversationStatus.completed

    def get_transcript(self, include_timestamps: bool = False, user_name: Optional[str] = None) -> str:
        return TranscriptSegment.segments_as_string(
            self.transcript_segments,
            include_timestamps=include_timestamps,
            user_name=user_name,
        )


class ConversationFinalizationStatusResponse(BaseModel):
    """Temporary customer projection for an S-25-owned durable drain job."""

    job_id: str
    status: str
    terminal: bool
    retryable: bool
    attempt_count: int
    task_retry_count: int
