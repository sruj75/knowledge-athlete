import asyncio

import httpx
import pytest

from utils.llm.managed_stream_transport import (
    MANAGED_STREAM_HEARTBEAT,
    ManagedStreamPolicy,
    stream_managed_response_bytes,
)


def _policy(**overrides) -> ManagedStreamPolicy:
    values = {
        'first_event_timeout_seconds': 1.0,
        'progress_heartbeat_seconds': 1.0,
        'max_duration_seconds': 10.0,
        'cancel_grace_seconds': 0.1,
        'provider_max_attempts': 3,
        'provider_retry_backoff_seconds': 0.001,
        'provider_min_retry_headroom_seconds': 0.0,
    }
    values.update(overrides)
    return ManagedStreamPolicy(**values)


class _Response:
    def __init__(self, chunks):
        self.chunks = chunks

    def raise_for_status(self):
        return None

    def aiter_raw(self):
        async def iterator():
            for value in self.chunks:
                if isinstance(value, BaseException):
                    raise value
                yield value

        return iterator()


class _Manager:
    def __init__(self, response=None, error=None):
        self.response = response
        self.error = error

    async def __aenter__(self):
        if self.error:
            raise self.error
        return self.response

    async def __aexit__(self, *_):
        return None


@pytest.mark.asyncio
async def test_transport_retries_only_before_first_byte():
    managers = [
        _Manager(error=httpx.ReadTimeout('before bytes')),
        _Manager(response=_Response([b'data: one\n\n', httpx.ReadTimeout('after bytes')])),
    ]
    attempts = 0

    def open_stream():
        nonlocal attempts
        manager = managers[attempts]
        attempts += 1
        return manager

    stream = stream_managed_response_bytes(open_stream, policy=_policy())
    assert await anext(stream) == b'data: one\n\n'
    with pytest.raises(httpx.ReadTimeout, match='after bytes'):
        await anext(stream)
    assert attempts == 2


@pytest.mark.asyncio
async def test_transport_emits_heartbeat_without_altering_provider_bytes():
    gate = asyncio.Event()

    class DelayedResponse(_Response):
        def aiter_raw(self):
            async def iterator():
                yield b'data: first\n\n'
                await gate.wait()
                yield b'data: second\n\n'

            return iterator()

    stream = stream_managed_response_bytes(
        lambda: _Manager(response=DelayedResponse([])),
        policy=_policy(progress_heartbeat_seconds=0.01),
    )
    assert await anext(stream) == b'data: first\n\n'
    assert await anext(stream) is MANAGED_STREAM_HEARTBEAT
    gate.set()
    assert await anext(stream) == b'data: second\n\n'


def test_transport_defaults_preserve_the_existing_chat_policy(monkeypatch):
    for name in (
        'AGENT_STREAM_FIRST_EVENT_TIMEOUT_SECONDS',
        'AGENT_STREAM_PROGRESS_HEARTBEAT_SECONDS',
        'AGENT_STREAM_MAX_DURATION_SECONDS',
        'AGENT_STREAM_PROVIDER_MAX_ATTEMPTS',
    ):
        monkeypatch.delenv(name, raising=False)
    policy = ManagedStreamPolicy.from_environment()
    assert policy.first_event_timeout_seconds == 25.0
    assert policy.progress_heartbeat_seconds == 20.0
    assert policy.max_duration_seconds == 150.0
    assert policy.provider_max_attempts == 3
