"""Retained on-device transcript upload contract after developer API removal."""

import os
from contextlib import nullcontext
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from starlette.requests import Request

os.environ.setdefault('OPENAI_API_KEY', 'sk-test-not-real')
os.environ.setdefault(
    'ENCRYPTION_SECRET',
    'omi_ZwB2ZNqB2HHpMK6wStk7sTpavJiPTFg7gXUHnc4tFABPU6pZ2c2DKgehtfgi4RZv',
)

import routers.conversations as conversations  # noqa: E402
from models.conversation_enums import ConversationStatus  # noqa: E402


NOW = datetime(2026, 1, 1, tzinfo=timezone.utc)


def _request(**overrides):
    payload = {
        'transcript_segments': [
            {
                'text': 'hello world',
                'speaker': 'SPEAKER_00',
                'is_user': True,
                'start': 0.0,
                'end': 1.5,
            }
        ],
        'source': 'desktop',
        'started_at': NOW,
        'finished_at': NOW.replace(second=2),
        'language': 'en',
    }
    payload.update(overrides)
    return conversations.CreateConversationFromTranscriptRequest.model_validate(payload)


def test_client_session_id_is_idempotent_and_persists_capture_provenance(monkeypatch):
    monkeypatch.setattr(conversations.conversations_db, 'get_conversation', MagicMock(return_value=None))
    claim = MagicMock(return_value=True)
    monkeypatch.setattr(conversations.lifecycle_service, 'create_processing_conversation', claim)
    monkeypatch.setattr(
        conversations.lifecycle_service, 'processing_admission_guard', lambda *_args, **_kwargs: nullcontext()
    )
    persisted = MagicMock()
    monkeypatch.setattr(conversations.lifecycle_service, 'persist_processed_conversation', persisted)

    def _process(_uid, _language, conversation):
        conversation.status = ConversationStatus.completed
        return conversation

    monkeypatch.setattr(conversations, 'process_conversation', _process)
    response = conversations._create_conversation_from_segments(
        'uid1',
        _request(client_conversation_id='local-session-1'),
        client_device_id='macos_a1b2c3d4',
        client_platform='macos',
    )

    expected_id = conversations._from_segments_conversation_id('uid1', 'local-session-1')
    assert response.id == expected_id
    claimed = claim.call_args.args[1]
    assert claimed['id'] == expected_id
    assert claimed['client_device_id'] == 'macos_a1b2c3d4'
    assert claimed['client_platform'] == 'macos'
    persisted.assert_called_once()


def test_retry_returns_existing_conversation_without_processing(monkeypatch):
    expected_id = conversations._from_segments_conversation_id('uid1', 'local-session-1')
    monkeypatch.setattr(
        conversations.conversations_db,
        'get_conversation',
        MagicMock(return_value={'id': expected_id, 'status': 'processing', 'discarded': False}),
    )
    process = MagicMock()
    monkeypatch.setattr(conversations, 'process_conversation', process)

    response = conversations._create_conversation_from_segments(
        'uid1',
        _request(client_session_id='local-session-1'),
    )

    assert response.id == expected_id
    assert response.status == 'processing'
    process.assert_not_called()


def test_invalid_segment_is_rejected_before_processing(monkeypatch):
    process = MagicMock()
    monkeypatch.setattr(conversations, 'process_conversation', process)

    with pytest.raises(HTTPException) as exc:
        conversations._create_conversation_from_segments(
            'uid1',
            _request(transcript_segments=[{'text': 'bad', 'start': 2.0, 'end': 1.0}]),
        )

    assert exc.value.status_code == 422
    process.assert_not_called()


def test_firebase_route_resolves_capture_provenance_from_headers(monkeypatch):
    captured = {}

    def _create(uid, request, **kwargs):
        captured.update(uid=uid, request=request, **kwargs)
        return conversations.ConversationCreateResponse(id='c1', status='completed', discarded=False)

    monkeypatch.setattr(conversations, '_create_conversation_from_segments', _create)
    request = Request(
        {
            'type': 'http',
            'method': 'POST',
            'path': '/v1/conversations/from-segments',
            'headers': [(b'x-app-platform', b'macos'), (b'x-device-id-hash', b'a1b2c3d4')],
        }
    )

    response = conversations.create_conversation_from_segments_user(_request(), request, uid='uid1')

    assert response.id == 'c1'
    assert captured['client_device_id'] == 'macos_a1b2c3d4'
    assert captured['client_platform'] == 'macos'
    assert isinstance(captured['request'], conversations.CreateConversationFromTranscriptRequest)
