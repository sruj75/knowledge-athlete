import os
import random
import re
import uuid
import logging
from datetime import timezone, timedelta, datetime
from typing import Any, Callable, Dict, List, Optional, Set, Tuple, Union, cast

from fastapi import HTTPException

from database import redis_db
from database.auth import get_user_name
import database.conversations as conversations_db
import database.notifications as notification_db
import database.users as users_db
import database.tasks as tasks_db
import database.folders as folders_db
import database.calendar_meetings as calendar_db
from database.vector_db import upsert_vector2, update_vector_metadata, upsert_transcript_chunk_vectors
from utils.conversations.transcript_chunks import build_transcript_chunks
from models.calendar_context import CalendarMeetingContext
from models.conversation import Conversation, CreateConversation
from models.conversation_enums import ConversationSource, ConversationStatus
from utils.conversations.factory import deserialize_conversation
from utils.conversations import lifecycle as lifecycle_service
from utils.subscription import is_trial_paywalled, should_defer_desktop_processing
from models.other import Person
from models.structured import Structured  # type: ignore[reportAttributeAccessIssue]  # SDK/fallback export is runtime-complete.
from utils.notifications import send_important_conversation_message
from models.task import Task, TaskStatus, TaskAction, TaskActionProvider
from models.notification_message import NotificationMessage
from utils.executors import postprocess_executor, submit_with_context
from utils.llm.conversation_processing import (
    get_transcript_structure,
    should_discard_conversation,
    get_reprocess_transcript_structure,
)
from utils.llm.conversation_folder import assign_conversation_to_folder
from utils.analytics import record_usage
from utils.llm.usage_tracker import track_usage, Features
from utils.llm.temporal import date_in_tz
from utils.llm.chat import (
    retrieve_metadata_fields_from_transcript,
    obtain_emotional_message,
)
from utils.llm.clients import generate_embedding
from utils.notifications import send_notification
from utils.other.hume import (
    get_hume,
    HumeJobCallbackModel,
    HumeJobModelPredictionResponseModel,
    HumePredictionEmotionResponseModel,
)
from utils.retrieval.rag import retrieve_rag_conversation_context
from utils.cloud_tasks import is_audio_merge_dispatch_enabled
from utils.other.storage import (
    compute_audio_files_fingerprint,
    enqueue_conversation_artifact_build,
    precache_conversation_audio,
)

logger = logging.getLogger(__name__)


def _get_structured(
    uid: str,
    language_code: str,
    conversation: Union[Conversation, CreateConversation],
    force_process: bool = False,
    people: Optional[List[Person]] = None,
) -> Tuple[Structured, bool]:
    try:
        tz: Optional[str] = notification_db.get_user_time_zone(uid)
        tz_str: str = tz or ''
        user_language = users_db.get_user_language_preference(uid) or language_code

        # Extract calendar context from external_data
        calendar_context: Optional[CalendarMeetingContext] = None
        if hasattr(conversation, 'external_data'):
            external_data_value = cast(Optional[Dict[str, Any]], getattr(conversation, 'external_data', None))
            if external_data_value:
                calendar_data = external_data_value.get('calendar_meeting_context')
                if calendar_data:
                    calendar_context = CalendarMeetingContext(**calendar_data)

        main_conv = cast(Union[Conversation, CreateConversation], conversation)
        user_name = get_user_name(uid, use_default=False)
        transcript_text = main_conv.get_transcript(False, people=people, user_name=user_name)  # type: ignore[reportArgumentType]  # conversation.py reverted to main; people/user_name may be Optional

        # For re-processing, we don't discard, just re-structure.
        if force_process:
            conv_started_at = cast(datetime, main_conv.started_at)
            # reprocess endpoint
            with track_usage(uid, Features.CONVERSATION_STRUCTURE):
                structured = get_reprocess_transcript_structure(
                    transcript_text,
                    conv_started_at,
                    language_code,
                    tz_str,
                    output_language_code=user_language,
                )
            return structured, False

        # Compute conversation duration for discard heuristics
        duration_seconds: Optional[float] = None
        if main_conv.started_at and main_conv.finished_at:
            duration_seconds = max(0, (main_conv.finished_at - main_conv.started_at).total_seconds())

        # Determine whether to discard the conversation based on its transcript.
        with track_usage(uid, Features.CONVERSATION_DISCARD):
            discarded = should_discard_conversation(transcript_text, duration_seconds)
        if discarded:
            return Structured(emoji=random.choice(['🧠', '🎉'])), True

        # If not discarded, proceed to generate the structured summary from the transcript.
        conv_started_at = cast(datetime, main_conv.started_at)
        with track_usage(uid, Features.CONVERSATION_STRUCTURE):
            structured = get_transcript_structure(
                transcript_text,
                conv_started_at,
                language_code,
                tz_str,
                uid,
                calendar_meeting_context=calendar_context,
                output_language_code=user_language,
            )
        return structured, False
    except Exception as e:
        logger.error(e)
        raise HTTPException(status_code=500, detail="Error processing conversation, please try again later")


def _get_conversation_obj(
    uid: str,
    structured: Structured,
    conversation: Union[Conversation, CreateConversation],
) -> Conversation:
    discarded = structured.title == ''
    if isinstance(conversation, CreateConversation):
        conversation_dict = conversation.dict()
        # Store calendar context in external_data if available
        calendar_context = conversation_dict.pop('calendar_meeting_context', None)

        # Use started_at as created_at for imported conversations to preserve original timestamp
        created_at = conversation.started_at if conversation.started_at else datetime.now(timezone.utc)
        result: Conversation = Conversation(
            id=str(uuid.uuid4()),
            uid=uid,
            structured=structured,
            created_at=created_at,
            discarded=discarded,
            **conversation_dict,
        )

        # Add calendar metadata to external_data
        if calendar_context:
            if not result.external_data:
                result.external_data = {}
            result.external_data['calendar_meeting_context'] = calendar_context

        return result
    else:
        main_conv = conversation
        main_conv.structured = structured
        main_conv.discarded = discarded
        return main_conv


# Verbatim transcript-chunk indexing (ns_tchunks). Off by default: enables semantic
# retrieval over raw transcript text, which the summary-only conversation vectors miss.
TRANSCRIPT_CHUNK_INDEXING_ENABLED = os.getenv('TRANSCRIPT_CHUNK_INDEXING_ENABLED', 'false').lower() == 'true'


def save_transcript_chunk_vectors(uid: str, conversation: Conversation):
    segments: List[Any] = [s.dict() if hasattr(s, 'dict') else s for s in (conversation.transcript_segments or [])]
    chunks = build_transcript_chunks(
        cast(List[Dict[str, Any]], segments), conversation.started_at or conversation.created_at
    )
    if chunks:
        upsert_transcript_chunk_vectors(uid, conversation.id, chunks)


def save_structured_vector(uid: str, conversation: Conversation, update_only: bool = False) -> None:
    vector = generate_embedding(str(conversation.structured)) if not update_only else None
    tz = notification_db.get_user_time_zone(uid) or ''

    metadata: Dict[str, Any] = {}

    segments: List[Dict[str, Any]] = [t.dict() for t in conversation.transcript_segments]
    metadata = retrieve_metadata_fields_from_transcript(uid, conversation.created_at, segments, tz)

    metadata['created_at'] = int(conversation.created_at.timestamp())

    if not update_only:
        logger.info('save_structured_vector creating vector')
        upsert_vector2(uid, conversation.id, cast(List[float], vector), metadata)
    else:
        logger.info('save_structured_vector updating metadata')
        update_vector_metadata(uid, conversation.id, metadata)


def _build_deferred_structured(
    conversation: Union[Conversation, CreateConversation],
) -> Structured:
    """A cheap, no-LLM placeholder Structured for a lazily-deferred conversation. The title is
    the first few words of the transcript so the conversation list stays usable until the user
    opens it (which triggers the real enrichment). A non-empty title is required — an empty one
    marks the conversation discarded in `_get_conversation_obj`."""
    text = ''
    for seg in list(getattr(conversation, 'transcript_segments', None) or []):
        seg_text = (getattr(seg, 'text', '') or '').strip()
        if seg_text:
            text = seg_text
            break
    words = text.split()
    title = ' '.join(words[:8]).strip() if words else ''
    return Structured(title=title or 'Recording')


def _store_deferred_conversation(uid: str, conversation: Union[Conversation, CreateConversation]) -> Conversation:
    """Persist a desktop conversation with a cheap (no-LLM) title and `deferred=True`, skipping
    all enrichment. Mirrors the tail of process_conversation's persistence (cheap structured →
    `_get_conversation_obj` → upsert) without any LLM / Pinecone / app work. The enrichment runs
    later via the lazy trigger in `get_conversation_by_id`."""
    is_initial_creation = isinstance(conversation, CreateConversation)
    structured = _build_deferred_structured(conversation)
    conversation = _get_conversation_obj(uid, structured, conversation)
    conversation.deferred = True
    # `processing` (not completed) is the user-facing "awaiting enrichment" state. Unlike the
    # `deferred` flag it survives the desktop's local conversation cache, so the client shows a
    # processing indicator and re-fetches on open to trigger enrichment. The lazy enrich sets it
    # back to `completed`.
    conversation.status = ConversationStatus.processing
    if is_initial_creation:
        persisted = lifecycle_service.create_processing_conversation(uid, conversation.dict(), idempotent=True)
    else:
        persisted = lifecycle_service.persist_processed_conversation(uid, conversation.dict())
    if not persisted:
        logger.info('lazy: deferred conversation creation fenced uid=%s conv=%s', uid, conversation.id)
        return conversation
    logger.info("lazy: stored deferred desktop conversation uid=%s conv=%s", uid, conversation.id)
    return conversation


def process_conversation(
    uid: str,
    language_code: str,
    conversation: Union[Conversation, CreateConversation],
    force_process: bool = False,
    is_reprocess: bool = False,
    persistence_observer: Callable[[bool], None] | None = None,
    defer_derived_effects: bool = False,
    derived_effects_observer: Callable[[Callable[[], None]], None] | None = None,
) -> Conversation:
    def report_persistence(current: bool) -> None:
        if persistence_observer is not None:
            persistence_observer(current)

    is_initial_creation = isinstance(conversation, CreateConversation)
    # Trial paywall: skip all post-processing (summaries, action
    # items, and embeddings) for paywalled desktop users.
    # Without this, any segments that did get through before the trial gate
    # (e.g. buffered transcripts, retroactive `/v1/conversations` create) still
    # trigger expensive LLM + Pinecone work.
    #
    # `conversation.source` carries the originating client (desktop / omi / etc).
    # Non-desktop sources flow through untouched — paywall is desktop-only.
    if (
        hasattr(conversation, 'source')
        and conversation.source == ConversationSource.desktop
        and is_trial_paywalled(uid, 'macos')
    ):
        logger.info(
            "trial paywall: skipping post-processing for uid=%s conv=%s source=desktop",
            uid,
            getattr(conversation, 'id', '?'),
        )
        # Return the conversation as-is with no LLM work performed. If it has
        # a status field, mark it processed so the client doesn't show a stuck
        # "processing" state forever.
        if isinstance(conversation, Conversation):
            try:
                conversation.status = ConversationStatus.completed
            except Exception:
                pass
        report_persistence(False)
        return cast(Conversation, conversation)

    # Lazy desktop processing (freemium cost cut): desktop users without a desktop-entitled
    # paid plan (basic / Neo) get ONLY the raw transcript on capture. The expensive LLM
    # enrichment (summary, action items, embeddings, app results) is deferred until
    # they first OPEN the conversation (get_conversation_by_id reprocesses it with
    # force_process=True). Paid desktop plans (Operator / Architect) and all
    # non-desktop sources are processed normally here. force_process / is_reprocess — the lazy
    # trigger and manual reprocess — bypass this so the enrichment actually runs.
    if (
        not force_process
        and not is_reprocess
        and hasattr(conversation, 'source')
        and conversation.source == ConversationSource.desktop
        and should_defer_desktop_processing(uid)
    ):
        deferred = _store_deferred_conversation(uid, conversation)
        report_persistence(False)
        return deferred

    # Fetch meeting context from Firestore if meeting_id is associated with this conversation
    if isinstance(conversation, Conversation) and conversation.id:
        meeting_id = redis_db.get_conversation_meeting_id(conversation.id)
        if meeting_id:
            try:
                meeting_data = calendar_db.get_meeting(uid, meeting_id)
                if meeting_data:
                    # Add meeting context to conversation's external_data
                    if not conversation.external_data:
                        conversation.external_data = {}
                    conversation.external_data['calendar_meeting_context'] = meeting_data
                    logger.info(
                        f"Retrieved meeting context for conversation {conversation.id}: {meeting_data.get('title')}"
                    )
            except Exception as e:
                logger.error(f"Error retrieving meeting context for conversation {conversation.id}: {e}")

    person_ids = conversation.get_person_ids()
    people: List[Person] = []
    if person_ids:
        people_data = users_db.get_people_by_ids(uid, list(set(person_ids)))
        people = [Person(**p) for p in people_data]

    structured, discarded = _get_structured(uid, language_code, conversation, force_process, people=people)
    conversation = _get_conversation_obj(uid, structured, conversation)

    # Persist the completed generation before it can trigger any derived work.
    # A discard or replacement that wins this transaction must not create
    # vectors, action items, audio artifacts, folders,
    # downstream usage or derived work from a stale in-memory snapshot.
    conversation.status = ConversationStatus.completed
    if is_initial_creation:
        persisted = lifecycle_service.create_completed_conversation(uid, conversation.dict(), idempotent=True)
    else:
        persisted = lifecycle_service.persist_processed_conversation(uid, conversation.dict())
    report_persistence(persisted)
    if not persisted:
        logger.info(
            'processing result fenced before completion side effects uid=%s conversation=%s', uid, conversation.id
        )
        return conversation

    # Wrap every post-persistence derived effect so the durable finalizer can
    # defer the bundle until it transactionally claims ownership (#10468 r5).
    def _emit_derived_effects() -> None:
        # AI-based folder assignment
        assigned_folder_id = None
        if not discarded and not is_reprocess and not conversation.folder_id:
            try:
                # Get user's folders
                user_folders = folders_db.get_folders(uid)
                if not user_folders:
                    user_folders = folders_db.initialize_system_folders(uid)

                if user_folders and conversation.structured:
                    cat = conversation.structured.category.value if conversation.structured.category else 'other'
                    with track_usage(uid, Features.CONVERSATION_FOLDER):
                        folder_id, confidence, reasoning = assign_conversation_to_folder(
                            title=conversation.structured.title or '',
                            overview=conversation.structured.overview or '',
                            category=cat,
                            user_folders=user_folders,
                            category_folder_id=folders_db.resolve_category_folder_id(cat, user_folders),
                        )
                    if folder_id:
                        conversation.folder_id = folder_id
                        assigned_folder_id = folder_id
                        conversations_db.update_conversation(uid, conversation.id, {'folder_id': folder_id})
                        logger.info(
                            f"AI assigned conversation {conversation.id} to folder {folder_id} (confidence: {confidence:.2f}): {reasoning}"
                        )
            except Exception as e:
                logger.error(f"Error during folder assignment for conversation {conversation.id}: {e}")

        if not discarded:
            # Analytics tracking
            insights_gained = 0
            if conversation.structured:
                # Count sentences with more than 5 words from title and overview
                for text in [conversation.structured.title, conversation.structured.overview]:
                    if text:
                        sentences = re.split(r'[.!?]+', text)
                        for sentence in sentences:
                            if len(sentence.split()) > 5:
                                insights_gained += 1

                # Count extracted calendar events.
                insights_gained += len(conversation.structured.events)

            if insights_gained > 0:
                record_usage(uid, insights_gained=insights_gained)
            if not is_reprocess:
                submit_with_context(postprocess_executor, save_structured_vector, uid, conversation)
                if TRANSCRIPT_CHUNK_INDEXING_ENABLED:
                    submit_with_context(postprocess_executor, save_transcript_chunk_vectors, uid, conversation)
        # Create audio files from chunks if private cloud sync was enabled
        if not is_reprocess and conversation.private_cloud_sync_enabled:
            try:
                audio_files = conversations_db.create_audio_files_from_chunks(uid, conversation.id)
                if audio_files:
                    conversation.audio_files = audio_files
                    files_payload = [af.dict() for af in audio_files]
                    conversations_db.update_conversation(uid, conversation.id, {'audio_files': files_payload})
                    # Pre-cache audio files in background
                    precache_conversation_audio(uid, conversation.id, files_payload)
                    # Build the conversation-level playback artifact (dense MP3 + spans)
                    if is_audio_merge_dispatch_enabled():
                        enqueue_conversation_artifact_build(
                            uid,
                            conversation.id,
                            compute_audio_files_fingerprint(files_payload),
                            caller='process_conversation',
                        )
            except Exception as e:
                logger.error(f"Error creating audio files: {e}")

        # Update folder conversation count after conversation is saved
        if assigned_folder_id:
            folders_db.update_folder_conversation_count(uid, assigned_folder_id)

    if defer_derived_effects:
        if derived_effects_observer is not None:
            derived_effects_observer(_emit_derived_effects)
        return conversation
    _emit_derived_effects()
    logger.info(f'process_conversation completed conversation.id= {conversation.id}')
    return conversation


def _send_important_conversation_notification_if_needed(uid: str, conversation: Conversation) -> None:  # type: ignore[reportUnusedFunction]  # reserved for re-enablement
    """
    Send notification for long conversations (>30 minutes) that just completed.
    Only sends once per conversation using Redis deduplication.
    """

    # Skip if conversation is discarded
    if conversation.discarded:
        return

    # Check if we have valid timestamps to compute duration
    if not conversation.started_at or not conversation.finished_at:
        logger.error(f"Cannot compute duration for conversation {conversation.id}: missing timestamps")
        return

    # Calculate duration in seconds
    duration_seconds = (conversation.finished_at - conversation.started_at).total_seconds()

    # Only notify for conversations longer than 30 minutes (1800 seconds)
    if duration_seconds < 1800:
        return

    # Check if notification was already sent for this conversation
    if redis_db.has_important_conversation_notification_been_sent(uid, conversation.id):
        logger.info(f"Important conversation notification already sent for {conversation.id}")
        return

    # Mark as sent before sending to prevent duplicates
    redis_db.set_important_conversation_notification_sent(uid, conversation.id)

    # Send the notification
    logger.info(
        f"Sending important conversation notification for {conversation.id} (duration: {duration_seconds/60:.1f} mins)"
    )
    send_important_conversation_message(uid, conversation.id)


def process_user_emotion(uid: str, language_code: str, conversation: Conversation, urls: List[str]) -> None:
    logger.info(f'process_user_emotion conversation.id= {conversation.id}')

    # save task
    now = datetime.now()
    task = Task(
        id=str(uuid.uuid4()),
        action=TaskAction.HUME_MERSURE_USER_EXPRESSION,
        user_uid=uid,
        memory_id=conversation.id,
        created_at=now,
        status=TaskStatus.PROCESSING,
    )
    tasks_db.create(task.dict())

    # emotion
    ok = get_hume().request_user_expression_mersurement(urls)
    if "error" in ok:
        err = ok["error"]
        logger.error(err)
        return
    job = ok["result"]
    request_id = job.id
    if not request_id or len(request_id) == 0:
        logger.info(f"Can not request users feeling. uid: {uid}")
        return

    # update task
    task.request_id = request_id
    task.updated_at = datetime.now()
    tasks_db.update(task.id, task.dict())

    return


def process_user_expression_measurement_callback(
    provider: str, request_id: str, callback: HumeJobCallbackModel
) -> None:
    support_providers = [TaskActionProvider.HUME]
    if provider not in support_providers:
        logger.info(f"Provider is not supported. {provider}")
        return

    # Get task
    task_action = ""
    if provider == TaskActionProvider.HUME:
        task_action = TaskAction.HUME_MERSURE_USER_EXPRESSION
    if len(task_action) == 0:
        logger.info("Task action is empty")
        return

    task_data = tasks_db.get_task_by_action_request(task_action, request_id)
    if task_data is None:
        logger.warning(f"Task not found. Action: {task_action}, Request ID: {request_id}")
        return

    task = Task(**task_data)

    # Update
    task_status = task.status
    if callback.status == "COMPLETED":
        task_status = TaskStatus.DONE
    elif callback.status == "FAILED":
        task_status = TaskStatus.ERROR
    else:
        logger.info(f"Not support status {callback.status}")
        return

    # Not changed
    if task_status == task.status:
        logger.info("Task status are synced")
        return

    task.status = task_status
    task.updated_at = datetime.now()
    tasks_db.update(task.id, task.dict())

    # done or not
    if task.status != TaskStatus.DONE:
        logger.info(f"Task is not done yet. Uid: {task.user_uid}, task_id: {task.id}, status: {task.status}")
        return

    uid = cast(str, task.user_uid)
    memory_id = cast(str, task.memory_id)

    # Save predictions
    if len(callback.predictions) > 0:
        conversations_db.store_model_emotion_predictions_result(uid, memory_id, provider, callback.predictions)

    # Conversation
    conversation_data = conversations_db.get_conversation(uid, memory_id)
    if conversation_data is None:
        logger.warning(f"Conversation is not found. Uid: {uid}. Conversation: {memory_id}")
        return

    conversation = deserialize_conversation(conversation_data)

    # Get prediction
    predictions = callback.predictions
    logger.info(predictions)
    if len(predictions) == 0 or len(predictions[0].emotions) == 0:
        logger.info(f"Can not predict user's expression. Uid: {uid}")
        return

    # Filter users emotions only
    users_frames: List[Tuple[float, float]] = []
    for seg in filter(lambda seg: seg.is_user and 0 <= seg.start < seg.end, conversation.transcript_segments):
        users_frames.append((seg.start, seg.end))
    # print(users_frames)

    if len(users_frames) == 0:
        logger.info(f"User time frames are empty. Uid: {uid}")
        return

    users_predictions: List[HumeJobModelPredictionResponseModel] = []
    for prediction in predictions:
        for uf in users_frames:
            logger.info(f"{uf} {prediction.time}")
            if uf[0] <= prediction.time[0] and prediction.time[1] <= uf[1]:
                users_predictions.append(prediction)
                break
    if len(users_predictions) == 0:
        logger.info(f"Predictions are filtered by user transcript segments. Uid: {uid}")
        return

    # Top emotions
    emotion_filters: List[str] = []
    user_emotions: List[HumePredictionEmotionResponseModel] = []
    for up in users_predictions:
        user_emotions += up.emotions
    emotions = HumeJobModelPredictionResponseModel.get_top_emotion_names(user_emotions, 1, 0.5)
    # print(emotions)
    if len(emotion_filters) > 0:
        emotions = list(filter(lambda emotion: emotion in emotion_filters, emotions))
    if len(emotions) == 0:
        logger.info(f"Can not extract users emmotion. uid: {uid}")
        return

    emotion = ','.join(emotions)
    logger.info(f"Emotion Uid: {uid} {emotion}")

    # Ask llms about notification content
    title = "omi"
    context_str, _ = retrieve_rag_conversation_context(uid, conversation)

    response: str = obtain_emotional_message(
        uid, conversation.transcript_segments, conversation.get_person_ids(), context_str, emotion
    )
    message = response

    # Send the notification
    send_notification(uid, title, message, None)

    return


def retrieve_in_progress_conversation(uid: str) -> Optional[Dict[str, Any]]:
    conversation_id = redis_db.get_in_progress_conversation_id(uid)
    existing: Optional[Dict[str, Any]] = None

    if conversation_id:
        existing = conversations_db.get_conversation(uid, conversation_id)
        if existing and existing['status'] != 'in_progress':
            existing = None

    if not existing:
        existing = conversations_db.get_in_progress_conversation(uid)
    return existing
