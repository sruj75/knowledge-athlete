"""Authenticated, stateless candidate computation for local conversations."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Annotated
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import regex
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, StringConstraints, ValidationError, field_validator

from models.conversation_enums import CategoryEnum
from utils.llm import conversation_processing
from utils.llm.usage_tracker import Features, track_usage
from utils.other.endpoints import get_current_user_uid

logger = logging.getLogger(__name__)
router = APIRouter()

BoundedTranscript = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1_000_000)]
LanguageCode = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=32)]
TimezoneName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128)]


class ConversationDiscardRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')

    generation_id: UUID
    transcript: BoundedTranscript
    duration_seconds: float = Field(ge=0, allow_inf_nan=False)


class ConversationDiscardResponse(BaseModel):
    generation_id: UUID
    discard: bool


class ConversationCandidateRequest(BaseModel):
    model_config = ConfigDict(extra='forbid')

    generation_id: UUID
    transcript: BoundedTranscript
    started_at: datetime
    language: LanguageCode
    output_language: LanguageCode
    timezone: TimezoneName

    @field_validator('timezone')
    @classmethod
    def validate_timezone(cls, value: str) -> str:
        try:
            ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError) as error:
            raise ValueError('timezone must be an IANA timezone') from error
        return value


class ConversationCommitmentCandidate(BaseModel):
    model_config = ConfigDict(extra='forbid')

    title: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=256)]
    description: Annotated[str, StringConstraints(strip_whitespace=True, max_length=50_000)] = ''
    start: datetime
    duration_minutes: int = Field(gt=0, le=180)
    created: bool = False


class ConversationStructureResponse(BaseModel):
    model_config = ConfigDict(extra='forbid')

    generation_id: UUID
    title: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=256)]
    overview: Annotated[str, StringConstraints(strip_whitespace=True, max_length=50_000)]
    emoji: str
    category: CategoryEnum
    commitments: list[ConversationCommitmentCandidate] = Field(max_length=100)

    @field_validator('title')
    @classmethod
    def validate_title_word_count(cls, value: str) -> str:
        if len(value.split()) > 10:
            raise ValueError('title must contain at most ten words')
        return value

    @field_validator('emoji')
    @classmethod
    def validate_single_grapheme(cls, value: str) -> str:
        if regex.fullmatch(r'\X', value) is None:
            raise ValueError('emoji must be exactly one extended grapheme cluster')
        return value


def classify_discard(transcript: str, duration_seconds: float) -> bool:
    """Narrow injectable seam around the retained classifier."""
    return conversation_processing.should_discard_conversation(transcript, duration_seconds, raise_on_error=True)


def compute_structure_candidate(request: ConversationCandidateRequest, uid: str):
    return conversation_processing.get_transcript_structure(
        transcript=request.transcript,
        started_at=request.started_at,
        language_code=request.language,
        tz=request.timezone,
        uid=uid,
        output_language_code=request.output_language,
    )


@router.post('/v1/conversation-compute/discard', response_model=ConversationDiscardResponse)
def compute_discard(
    request: ConversationDiscardRequest,
    uid: str = Depends(get_current_user_uid),
) -> ConversationDiscardResponse:
    try:
        with track_usage(uid, Features.CONVERSATION_DISCARD):
            discard = classify_discard(request.transcript, request.duration_seconds)
    except Exception:
        # The Mac owns fail-open persistence. A transport error is required so it can record
        # failed-keep work and fallback telemetry instead of misclassifying it as success.
        logger.warning('Conversation discard compute failed', exc_info=False)
        raise HTTPException(status_code=502, detail='compute_failed') from None
    return ConversationDiscardResponse(generation_id=request.generation_id, discard=discard)


@router.post('/v1/conversation-compute/structure', response_model=ConversationStructureResponse)
def compute_structure(
    request: ConversationCandidateRequest,
    uid: str = Depends(get_current_user_uid),
) -> ConversationStructureResponse:
    try:
        with track_usage(uid, Features.CONVERSATION_STRUCTURE):
            result = compute_structure_candidate(request, uid)
        return ConversationStructureResponse(
            generation_id=request.generation_id,
            title=result.title,
            overview=result.overview,
            emoji=result.emoji,
            category=result.category,
            commitments=[
                ConversationCommitmentCandidate(
                    title=event.title,
                    description=event.description,
                    start=event.start,
                    duration_minutes=event.duration,
                    created=False,
                )
                for event in (result.events or [])
            ],
        )
    except ValidationError as error:
        logger.warning('Conversation structure returned an invalid candidate shape')
        raise HTTPException(status_code=502, detail='invalid_candidate_response') from error
