from datetime import datetime, timezone, timedelta

import pytest
from pydantic import ValidationError

from models.conversation_metadata import ConversationMetadata, ConversationMetadataKeys, metadata_list
from models.daily_summary_payload import DailySummaryPayload
from utils.conversations.datetime_utils import coerce_utc_datetime
from utils.log_sanitizer import sanitize_validation_error


def test_conversation_metadata_uses_single_vector_schema_and_entities_field():
    metadata = ConversationMetadata(
        people=['alice'],
        topics=['vector search'],
        entities=['pinecone'],
        dates=['2026-06-25'],
    ).to_vector_metadata()

    assert metadata == {
        ConversationMetadataKeys.PEOPLE: ['alice'],
        ConversationMetadataKeys.TOPICS: ['vector search'],
        ConversationMetadataKeys.ENTITIES: ['pinecone'],
        ConversationMetadataKeys.DATES: ['2026-06-25'],
    }
    assert 'people_mentioned' not in metadata
    assert metadata[ConversationMetadataKeys.ENTITIES] != metadata[ConversationMetadataKeys.TOPICS]


@pytest.mark.parametrize(
    ('raw', 'expected'),
    [
        (['alice'], ['alice']),
        (('alice', 'bob'), ['alice', 'bob']),
        ('alice', []),
        (None, []),
    ],
)
def test_metadata_list_only_returns_list_like_values(raw, expected):
    assert metadata_list({'people': raw}, ConversationMetadataKeys.PEOPLE) == expected


@pytest.mark.parametrize(
    ('value', 'expected'),
    [
        ('2026-06-25T12:00:00Z', datetime(2026, 6, 25, 12, 0, tzinfo=timezone.utc)),
        (
            '2026-06-25T08:00:00-04:00',
            datetime(2026, 6, 25, 12, 0, tzinfo=timezone.utc),
        ),
        (
            datetime(2026, 6, 25, 8, 0, tzinfo=timezone(timedelta(hours=-4))),
            datetime(2026, 6, 25, 12, 0, tzinfo=timezone.utc),
        ),
        (datetime(2026, 6, 25, 12, 0), datetime(2026, 6, 25, 12, 0, tzinfo=timezone.utc)),
    ],
)
def test_coerce_utc_datetime_normalizes_supported_timestamps(value, expected):
    assert coerce_utc_datetime(value) == expected


@pytest.mark.parametrize('value', [None, 'not-a-date', object()])
def test_coerce_utc_datetime_returns_none_for_missing_or_malformed_values(value):
    assert coerce_utc_datetime(value) is None


def test_daily_summary_payload_rejects_malformed_section_shape():
    with pytest.raises(ValidationError):
        DailySummaryPayload.model_validate({'headline': 'Today', 'highlights': ['not an object']})
    with pytest.raises(ValidationError):
        DailySummaryPayload.model_validate(
            {'headline': 'Today', 'highlights': [{'topic_name': 'wrong key', 'summary': 'Summary'}]}
        )


def test_daily_summary_payload_allows_omitted_optional_sections():
    payload = DailySummaryPayload.model_validate({'headline': 'Today'})

    assert payload.headline == 'Today'
    assert payload.highlights == []
    assert payload.unresolved_questions == []


def test_daily_summary_validation_log_summary_omits_private_input_value():
    private_summary_text = "Private therapy conversation about Alice and Bob"
    try:
        DailySummaryPayload.model_validate(
            {
                "headline": "Today",
                "highlights": [
                    {
                        "topic": "Personal",
                        "summary": private_summary_text,
                        "conversation_numbers": "not-a-list",
                    }
                ],
            }
        )
    except ValidationError as exc:
        safe_summary = sanitize_validation_error(exc)
    else:
        raise AssertionError("expected malformed daily summary payload to fail validation")

    assert private_summary_text not in safe_summary
    assert "input_value" not in safe_summary
    assert "conversation_numbers" in safe_summary
