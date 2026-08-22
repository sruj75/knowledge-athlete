"""Drain-only processing for already-admitted S-25 finalization jobs.

New durable conversations are Mac-local. This module remains temporarily so
an operational finalizer can finish work admitted before S-23 removed hosted
product ingress.
"""

import logging
import random
import re
from datetime import datetime
from typing import Callable, Optional, Tuple

from fastapi import HTTPException

import database.users as users_db
from models.conversation import Conversation
from models.conversation_enums import ConversationStatus
from models.structured import Structured
from utils.analytics import record_usage
from utils.conversations import lifecycle as lifecycle_service
from utils.llm.conversation_processing import (
    get_reprocess_transcript_structure,
    get_transcript_structure,
    should_discard_conversation,
)
from utils.llm.usage_tracker import Features, track_usage

logger = logging.getLogger(__name__)


def _get_structured(
    uid: str,
    language_code: str,
    conversation: Conversation,
    force_process: bool = False,
) -> Tuple[Structured, bool]:
    try:
        timezone_name = users_db.get_user_time_zone(uid) or ''
        output_language = users_db.get_user_language_preference(uid) or language_code
        transcript = conversation.get_transcript()
        started_at: datetime = conversation.started_at or conversation.created_at
        if force_process:
            with track_usage(uid, Features.CONVERSATION_STRUCTURE):
                structured = get_reprocess_transcript_structure(
                    transcript,
                    started_at,
                    language_code,
                    timezone_name,
                    output_language_code=output_language,
                )
            return structured, False

        duration_seconds: Optional[float] = None
        if conversation.started_at and conversation.finished_at:
            duration_seconds = max(0, (conversation.finished_at - conversation.started_at).total_seconds())
        with track_usage(uid, Features.CONVERSATION_DISCARD):
            discarded = should_discard_conversation(transcript, duration_seconds)
        if discarded:
            return Structured(emoji=random.choice(['🧠', '🎉'])), True
        with track_usage(uid, Features.CONVERSATION_STRUCTURE):
            structured = get_transcript_structure(
                transcript,
                started_at,
                language_code,
                timezone_name,
                uid,
                output_language_code=output_language,
            )
        return structured, False
    except Exception as error:
        logger.error('Drain finalization processing failed: %s', type(error).__name__)
        raise HTTPException(status_code=500, detail='Error processing conversation, please try again later') from error


def process_conversation(
    uid: str,
    language_code: str,
    conversation: Conversation,
    force_process: bool = False,
    is_reprocess: bool = False,
    persistence_observer: Callable[[bool], None] | None = None,
    defer_derived_effects: bool = False,
    derived_effects_observer: Callable[[Callable[[], None]], None] | None = None,
) -> Conversation:
    """Finish one historical row without exposing a new product write API."""
    del is_reprocess
    structured, discarded = _get_structured(uid, language_code, conversation, force_process)
    conversation.structured = structured
    conversation.discarded = discarded
    conversation.status = ConversationStatus.completed
    persisted = lifecycle_service.persist_processed_conversation(uid, conversation.model_dump())
    if persistence_observer is not None:
        persistence_observer(persisted)
    if not persisted:
        logger.info('Drain finalization fenced uid=%s conversation=%s', uid, conversation.id)
        return conversation

    def emit_retained_usage() -> None:
        if discarded:
            return
        insights_gained = sum(
            sum(1 for sentence in re.split(r'[.!?]+', text) if len(sentence.split()) > 5)
            for text in (structured.title, structured.overview)
            if text
        )
        insights_gained += len(structured.events)
        if insights_gained:
            record_usage(uid, insights_gained=insights_gained)

    if defer_derived_effects:
        if derived_effects_observer is not None:
            derived_effects_observer(emit_retained_usage)
    else:
        emit_retained_usage()
    return conversation
