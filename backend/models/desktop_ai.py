"""Bounded wire contracts for the private supervisor and AI evaluation receipts."""

import base64
from typing import Annotated, Literal, Self

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, StrictBool, field_validator, model_validator

OpaqueID = Annotated[str, Field(min_length=1, max_length=128, pattern=r'^[A-Za-z0-9_.:-]+$')]
ShortText = Annotated[str, Field(max_length=2000)]
TerminalOutcome = Literal['completed', 'interrupted', 'cancelled', 'failed', 'suppressed']
SupervisorAction = Literal['wait', 'guide_next_turn', 'intervene']


class WireModel(BaseModel):
    model_config = ConfigDict(extra='forbid')


class PromptReceipt(WireModel):
    text: str = Field(max_length=32000)
    name: str = Field(min_length=1, max_length=128)
    version: str = Field(min_length=1, max_length=64)
    source: Literal['langfuse', 'fallback']


class PromptReference(WireModel):
    name: str = Field(min_length=1, max_length=128)
    version: str = Field(min_length=1, max_length=64)
    source: Literal['langfuse', 'fallback']


class JPEGImage(WireModel):
    jpeg_base64: str = Field(min_length=1, max_length=2_800_000)

    @field_validator('jpeg_base64')
    @classmethod
    def validate_jpeg(cls, value: str) -> str:
        try:
            data = base64.b64decode(value, validate=True)
        except ValueError as exc:
            raise ValueError('image must contain base64 JPEG') from exc
        if len(data) > 2_000_000 or not data.startswith(b'\xff\xd8\xff'):
            raise ValueError('image must be a JPEG no larger than 2 MB')
        return value


class SupervisorScreen(JPEGImage):
    app_name: str = Field(default='', max_length=256)
    window_title: str = Field(default='', max_length=512)
    captured_at: AwareDatetime


class SupervisorWebcam(JPEGImage):
    jpeg_base64: str = Field(min_length=1, max_length=341_336)
    captured_at: AwareDatetime

    @field_validator('jpeg_base64')
    @classmethod
    def validate_webcam_size(cls, value: str) -> str:
        if len(base64.b64decode(value, validate=True)) > 256_000:
            raise ValueError('webcam JPEG exceeds 256 KB')
        return value


class SupervisorInputAvailability(WireModel):
    status: Literal['available', 'disabled', 'denied', 'unavailable', 'stale', 'suspended']
    captured_at: AwareDatetime | None = None
    age_ms: int | None = Field(default=None, ge=0, le=86_400_000, strict=True)


class SupervisorInputStatus(WireModel):
    screen: SupervisorInputAvailability
    webcam: SupervisorInputAvailability
    microphone: SupervisorInputAvailability
    system: SupervisorInputAvailability


class SupervisorActiveConversation(WireModel):
    id: OpaqueID
    state: Literal['closed', 'connecting', 'open', 'reconnecting', 'ending']


class TranscriptObservation(WireModel):
    id: OpaqueID
    text: ShortText
    source: Literal['microphone', 'system', 'mixed', 'user', 'assistant']
    revision: int = Field(default=0, ge=0, strict=True)
    final: StrictBool = True


class ConversationObservation(WireModel):
    turn_id: OpaqueID
    role: Literal['user', 'assistant']
    text: ShortText
    outcome: TerminalOutcome | None = None
    revision: int = Field(default=0, ge=0, strict=True)
    final: StrictBool = True


class SupervisorRequest(WireModel):
    observation_id: OpaqueID
    session_id: OpaqueID
    context_epoch: int = Field(ge=0, le=18_446_744_073_709_551_615, strict=True)
    screen: SupervisorScreen | None = None
    webcam: SupervisorWebcam | None = None
    observed_at: AwareDatetime | None = None
    content_revision: int = Field(default=0, ge=0, strict=True)
    input_status: SupervisorInputStatus | None = None
    active_conversation: SupervisorActiveConversation | None = None
    transcripts: list[TranscriptObservation] = Field(default_factory=list[TranscriptObservation], max_length=32)
    conversation: list[ConversationObservation] = Field(default_factory=list[ConversationObservation], max_length=16)
    memories: list[ShortText] = Field(default_factory=list, max_length=30)
    profile: str = Field(default='', max_length=12000)
    evaluation_sharing: StrictBool = False


class SupervisorDecision(WireModel):
    action: SupervisorAction
    note: ShortText | None = None

    @model_validator(mode='after')
    def validate_note(self) -> Self:
        if self.action != 'wait' and not (self.note and self.note.strip()):
            raise ValueError('guidance requires a nonempty note')
        if self.action == 'wait':
            self.note = None
        return self


class SupervisorResponse(SupervisorDecision):
    decision_id: OpaqueID
    observation_id: OpaqueID
    session_id: OpaqueID
    context_epoch: int
    prompt: PromptReceipt
    outcome: Literal['completed', 'degraded']


class TerminalTurnObservation(WireModel):
    kind: Literal['terminal_turn']
    session_id: OpaqueID
    turn_id: OpaqueID
    decision_id: OpaqueID | None = None
    prompt: PromptReference
    outcome: TerminalOutcome
    duration_ms: int = Field(ge=0, le=3_600_000, strict=True)
    evaluation_sharing: StrictBool = False
    conversation: list[ConversationObservation] = Field(default_factory=list[ConversationObservation], max_length=16)


class ChatTerminalObservation(WireModel):
    kind: Literal['chat_terminal']
    session_id: OpaqueID
    turn_id: OpaqueID
    request_id: OpaqueID
    outcome: TerminalOutcome
    duration_ms: int = Field(ge=0, le=3_600_000, strict=True)
    evaluation_sharing: StrictBool = False
    conversation: list[ConversationObservation] = Field(default_factory=list[ConversationObservation], max_length=16)


class ScoreObservation(WireModel):
    kind: Literal['score']
    request_id: OpaqueID | None = None
    session_id: OpaqueID
    turn_id: OpaqueID
    decision_id: OpaqueID | None = None
    value: int = Field(ge=0, le=1, strict=True)
    evaluation_sharing: StrictBool = False


class SupervisorDecisionObservation(WireModel):
    kind: Literal['supervisor_decision']
    session_id: OpaqueID
    decision_id: OpaqueID
    observation_id: OpaqueID
    prompt: PromptReference
    evaluation_sharing: StrictBool = False
    transcripts: list[TranscriptObservation] = Field(default_factory=list[TranscriptObservation], max_length=32)
    conversation: list[ConversationObservation] = Field(default_factory=list[ConversationObservation], max_length=16)


AIObservation = Annotated[
    TerminalTurnObservation | ChatTerminalObservation | ScoreObservation | SupervisorDecisionObservation,
    Field(discriminator='kind'),
]
