"""S-23/S-25 contract: hosted conversation schemas remain absent."""

from pathlib import Path

from models.transcript_segment import TranscriptSegment


def test_hosted_conversation_drain_schema_is_absent():
    backend_root = Path(__file__).resolve().parents[2]

    assert not (backend_root / 'models/conversation.py').exists()


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
