import json
from datetime import datetime, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock

from services.users import data_export


def test_server_export_contains_only_retained_metadata_and_never_reads_product_content(monkeypatch):
    now = datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc)
    monkeypatch.setattr(
        data_export,
        'get_user_profile',
        MagicMock(
            return_value={
                'email': 'owner@example.com',
                'created_at': now,
                'language': 'en',
                'store_recording_permission': True,
                'private_cloud_sync_enabled': True,
                'training_data_opt_in': True,
                'conversations': ['must-not-export'],
            }
        ),
    )
    monkeypatch.setattr(
        data_export,
        'get_existing_user_subscription',
        MagicMock(return_value=SimpleNamespace(model_dump=lambda **_: {'plan': 'basic'})),
    )
    monkeypatch.setattr(
        data_export,
        'get_monthly_usage_for_subscription',
        MagicMock(return_value={'transcription_seconds': 12, 'words_transcribed': 34, 'insights_gained': 5}),
    )
    monkeypatch.setattr(data_export.llm_usage_db, 'get_total_llm_cost', MagicMock(return_value=1.25))

    payload = json.loads(''.join(data_export.iter_user_data_export('owner-a')))

    assert payload == {
        'schema_version': 1,
        'account': {
            'uid': 'owner-a',
            'email': 'owner@example.com',
            'created_at': '2026-01-02T03:04:05+00:00',
            'language': 'en',
        },
        'subscription': {'plan': 'basic'},
        'usage': {
            'transcription_seconds': 12,
            'words_transcribed': 34,
            'insights_gained': 5,
            'managed_ai_total_cost_usd': 1.25,
        },
    }
    assert 'conversations' not in payload
    assert 'people' not in payload
    assert 'chat_messages' not in payload


def test_server_export_handles_absent_optional_account_state(monkeypatch):
    monkeypatch.setattr(data_export, 'get_user_profile', MagicMock(return_value=None))
    monkeypatch.setattr(data_export, 'get_existing_user_subscription', MagicMock(return_value=None))
    monkeypatch.setattr(data_export, 'get_monthly_usage_for_subscription', MagicMock(return_value={}))
    monkeypatch.setattr(data_export.llm_usage_db, 'get_total_llm_cost', MagicMock(return_value=0))

    payload = json.loads(''.join(data_export.iter_user_data_export('owner-a')))

    assert payload['account'] == {'uid': 'owner-a'}
    assert payload['subscription'] is None
    assert payload['usage']['managed_ai_total_cost_usd'] == 0
