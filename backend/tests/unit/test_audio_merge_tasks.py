"""Behavioral boundary tests for the callerless S-25 audio-merge worker."""

from unittest.mock import MagicMock

import pytest

from routers import sync
from utils import cloud_tasks


class _Request:
    def __init__(self, payload=None, error=None):
        self.payload = payload
        self.error = error

    async def json(self):
        if self.error:
            raise self.error
        return self.payload


async def _inline_run_blocking(_executor, function, *args):
    return function(*args)


def test_queue_names_are_deterministic_for_existing_drain_artifacts(monkeypatch):
    enqueued = []
    monkeypatch.setattr(
        cloud_tasks, '_enqueue_named_task', lambda queue, url, task_id, payload: enqueued.append(task_id)
    )

    cloud_tasks.enqueue_audio_merge_job(
        {'uid': 'uid', 'conversation_id': 'conversation', 'audio_file_id': 'part', 'timestamps': [1.0]}
    )
    cloud_tasks.enqueue_audio_merge_job(
        {'schema_version': 2, 'uid': 'uid', 'conversation_id': 'conversation', 'fingerprint': 'fingerprint'}
    )

    assert enqueued == ['am-conversation-part', 'amc-conversation-fingerprint']


@pytest.mark.asyncio
async def test_invalid_payload_is_acknowledged_without_product_state(monkeypatch):
    response = await sync.run_audio_merge_job(_Request(error=ValueError('invalid')), task_retry_count=0)

    assert response.status_code == 200
    assert b'invalid_payload' in response.body


@pytest.mark.asyncio
async def test_missing_legacy_chunks_mark_the_existing_task_terminal(monkeypatch):
    marker = MagicMock()
    monkeypatch.setattr(sync, 'run_blocking', _inline_run_blocking)
    monkeypatch.setattr(sync, 'try_acquire_job_run_lock', lambda _key: 'token')
    monkeypatch.setattr(sync, 'release_job_run_lock', lambda *_args: None)
    monkeypatch.setattr(sync, 'get_playback_artifact_signed_url', lambda *_args: None)
    monkeypatch.setattr(sync.sync_playback, 'build_playback_artifact', MagicMock(side_effect=FileNotFoundError()))
    monkeypatch.setattr(sync, 'mark_playback_unavailable', marker)

    response = await sync.run_audio_merge_job(
        _Request(
            {
                'uid': 'uid',
                'conversation_id': 'conversation',
                'audio_file_id': 'part',
                'timestamps': [1.0],
            }
        ),
        task_retry_count=0,
    )

    assert response.status_code == 200
    assert b'chunks_missing' in response.body
    marker.assert_called_once_with('uid', 'conversation', 'part', 'chunks_missing')


def test_worker_route_stays_internal_and_has_no_product_producer():
    routes = {(method, route.path) for route in sync.router.routes for method in getattr(route, 'methods', set())}

    assert routes == {('POST', '/v2/audio-merge-jobs/run')}
    assert all(not getattr(route, 'include_in_schema', True) for route in sync.router.routes)
