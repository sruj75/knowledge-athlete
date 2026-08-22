import json
import struct
from unittest.mock import AsyncMock, Mock

import pytest

from utils.listen_pusher_session import (
    FINALIZATION_REQUEST_HEADER,
    ListenPusherSession,
    ListenPusherSessionConfig,
    ListenPusherSessionDeps,
)


def _session(*, max_pending_requests=2):
    socket = AsyncMock()
    callback = Mock()
    connect = AsyncMock(return_value=socket)
    session = ListenPusherSession(
        ListenPusherSessionConfig('uid', 'session', 16_000, 'en', max_pending_requests),
        ListenPusherSessionDeps(callback, connect),
    )
    return session, socket, callback, connect


def _decode(frame: bytes):
    return struct.unpack('<I', frame[:4])[0], json.loads(frame[4:])


@pytest.mark.asyncio
async def test_only_durable_finalization_control_frame_is_sent():
    session, socket, _, _ = _session()
    await session.connect()

    assert await session.request_conversation_processing(
        'conversation', finalization_job_id='job', dispatch_generation=3
    )

    header, payload = _decode(socket.send.await_args.args[0])
    assert header == FINALIZATION_REQUEST_HEADER
    assert payload == {
        'conversation_id': 'conversation',
        'language': 'en',
        'finalization_job_id': 'job',
        'dispatch_generation': 3,
    }


@pytest.mark.asyncio
async def test_disconnected_request_is_replayed_after_connect():
    session, socket, _, _ = _session()
    assert not await session.request_conversation_processing(
        'conversation', finalization_job_id='job', dispatch_generation=1
    )

    assert await session.connect()
    assert _decode(socket.send.await_args.args[0])[1]['conversation_id'] == 'conversation'


@pytest.mark.asyncio
async def test_success_acknowledges_pending_request_once():
    session, socket, callback, _ = _session()
    await session.connect()
    await session.request_conversation_processing('conversation', finalization_job_id='job', dispatch_generation=1)
    socket.recv.return_value = struct.pack('<I', 201) + json.dumps({'conversation_id': 'conversation'}).encode()

    await session.receive_once()

    assert session.pending_conversation_requests == {}
    callback.assert_called_once_with('conversation')


@pytest.mark.asyncio
async def test_retryable_error_keeps_request_buffered():
    session, socket, callback, _ = _session()
    await session.connect()
    await session.request_conversation_processing('conversation', finalization_job_id='job', dispatch_generation=1)
    socket.recv.return_value = (
        struct.pack('<I', 201)
        + json.dumps({'conversation_id': 'conversation', 'error': 'retry', 'terminal': False}).encode()
    )

    await session.receive_once()

    assert 'conversation' in session.pending_conversation_requests
    callback.assert_not_called()


@pytest.mark.asyncio
async def test_pending_buffer_is_bounded_and_records_eviction_fallback(monkeypatch):
    recorded = []
    monkeypatch.setattr('utils.listen_pusher_session.record_fallback', lambda **fields: recorded.append(fields))
    session, _, _, _ = _session(max_pending_requests=1)
    await session.request_conversation_processing('old', finalization_job_id='job-old', dispatch_generation=1)
    await session.request_conversation_processing('new', finalization_job_id='job-new', dispatch_generation=1)
    assert list(session.pending_conversation_requests) == ['new']
    assert recorded == [
        {
            'component': 'pusher',
            'from_mode': 'durable_pending_buffer',
            'to_mode': 'evicted_oldest_request',
            'reason': 'capacity_full',
            'outcome': 'degraded',
            'log': __import__('utils.listen_pusher_session', fromlist=['logger']).logger,
        }
    ]
