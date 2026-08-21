"""Authenticated, stateless candidate computation for local conversations."""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Annotated
from uuid import UUID
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import regex
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field, StringConstraints, ValidationError, field_validator, model_validator

from models.conversation_enums import CategoryEnum
from utils.llm import conversation_processing
from utils.llm.usage_tracker import Features, track_usage
from utils.other.endpoints import get_current_user_uid

logger = logging.getLogger(__name__)
router = APIRouter()

BoundedTranscript = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=1_000_000)]
LanguageCode = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=32)]
TimezoneName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=128)]
BoundedDescription = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4_096)]


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


class RelatedTaskCandidate(BaseModel):
    model_config = ConfigDict(extra='forbid')

    token: Annotated[str, StringConstraints(pattern=r'^t[0-9]$')]
    description: BoundedDescription
    due_at: datetime | None = None
    completed: bool = False


class ConversationActionItemsRequest(ConversationCandidateRequest):
    related_tasks: list[RelatedTaskCandidate] = Field(default_factory=list, max_length=10)


class ConversationActionCandidate(BaseModel):
    model_config = ConfigDict(extra='forbid')

    action: Annotated[str, StringConstraints(pattern=r'^(create|update|complete)$')]
    description: BoundedDescription
    target_task_token: Annotated[str, StringConstraints(pattern=r'^t[0-9]$')] | None = None
    due_at: datetime | None = None

    @model_validator(mode='after')
    def validate_target_shape(self) -> 'ConversationActionCandidate':
        if self.action in {'update', 'complete'} and self.target_task_token is None:
            raise ValueError('update and complete candidates require a target')
        if self.action == 'create' and self.target_task_token is not None:
            raise ValueError('create candidates must not contain a target')
        return self


class ConversationActionItemsResponse(BaseModel):
    model_config = ConfigDict(extra='forbid')

    generation_id: UUID
    candidates: list[ConversationActionCandidate] = Field(max_length=100)


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
        calendar_meeting_context=None,
        output_language_code=request.output_language,
    )


def compute_action_item_candidates(request: ConversationActionItemsRequest, uid: str):
    del uid  # Usage is scoped by the route; the retained helper does not persist user state.
    existing = [
        {
            'id': task.token,
            'description': task.description,
            'due_at': task.due_at,
            'completed': task.completed,
        }
        for task in request.related_tasks
    ]
    return conversation_processing.extract_action_items(
        transcript=request.transcript,
        started_at=request.started_at,
        language_code=request.language,
        tz=request.timezone,
        existing_action_items=existing,
        calendar_meeting_context=None,
        output_language_code=request.output_language,
        raise_on_error=True,
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


@router.post('/v1/conversation-compute/action-items', response_model=ConversationActionItemsResponse)
def compute_action_items(
    request: ConversationActionItemsRequest,
    uid: str = Depends(get_current_user_uid),
) -> ConversationActionItemsResponse:
    open_request = request.model_copy(
        update={'related_tasks': [task for task in request.related_tasks if not task.completed]}
    )
    allowed_targets = {task.token for task in open_request.related_tasks}
    try:
        with track_usage(uid, Features.CONVERSATION_ACTION_ITEMS):
            result = compute_action_item_candidates(open_request, uid)
        candidates = []
        for item in result:
            action = item.candidate_action or 'create'
            target = item.target_task_id
            if action in {'update', 'complete'} and target not in allowed_targets:
                raise ValueError('candidate target was not supplied by the caller')
            candidates.append(
                ConversationActionCandidate(
                    action=action,
                    description=item.description,
                    target_task_token=target,
                    due_at=item.due_at,
                )
            )
        return ConversationActionItemsResponse(generation_id=request.generation_id, candidates=candidates)
    except (ValidationError, ValueError) as error:
        logger.warning('Conversation action items returned an invalid candidate shape')
        raise HTTPException(status_code=502, detail='invalid_candidate_response') from error
    except Exception as error:
        logger.warning('Conversation action items compute failed')
        raise HTTPException(status_code=502, detail='compute_failed') from error
