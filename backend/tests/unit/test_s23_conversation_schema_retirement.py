"""S-23 contract: the drain schema cannot restore hosted conversation products."""

from datetime import datetime, timezone

from models.conversation import Conversation
from models.transcript_segment import TranscriptSegment


RETIRED_CONVERSATION_FIELDS = {
    'audio_files',
    'call_id',
    'calendar_event_id',
    'client_device_id',
    'client_platform',
    'data_protection_level',
    'external_data',
    'folder_id',
    'is_locked',
    'processing_conversation_id',
    'processing_memory_id',
    'source',
    'transcript_segments_compressed',
    'visibility',
}


def test_minimal_drain_schema_ignores_historical_product_fields():
    historical = {field: f'retired-{field}' for field in RETIRED_CONVERSATION_FIELDS}
    conversation = Conversation(
        id='conversation',
        created_at=datetime(2026, 8, 22, tzinfo=timezone.utc),
        **historical,
    )

    assert RETIRED_CONVERSATION_FIELDS.isdisjoint(Conversation.model_fields)
    assert RETIRED_CONVERSATION_FIELDS.isdisjoint(conversation.model_dump())


def test_transcript_schema_keeps_generic_labels_without_reusable_identity():
    segment = TranscriptSegment(
        text='hello',
        speaker='SPEAKER_02',
        is_user=False,
        start=0,
        end=1,
        person_id='retired-person',
        speech_profile_processed=True,
    )

    assert segment.speaker_id == 2
    assert {'person_id', 'speech_profile_processed'}.isdisjoint(TranscriptSegment.model_fields)
    assert {'person_id', 'speech_profile_processed'}.isdisjoint(segment.model_dump())
