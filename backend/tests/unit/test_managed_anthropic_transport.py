from types import SimpleNamespace

import httpx
import pytest

from utils.llm.anthropic_transport import (
    ANTHROPIC_STREAM_HEARTBEAT,
    ManagedAnthropicPolicy,
    create_managed_anthropic_message,
    stream_managed_anthropic_events,
)


def _policy(**overrides) -> ManagedAnthropicPolicy:
    values = {
        'first_event_timeout_seconds': 25.0,
        'progress_heartbeat_seconds': 20.0,
        'max_duration_seconds': 150.0,
        'cancel_grace_seconds': 2.0,
        'provider_max_attempts': 3,
        'provider_retry_backoff_seconds': 1.0,
        'provider_min_retry_headroom_seconds': 45.0,
    }
    values.update(overrides)
    return ManagedAnthropicPolicy(**values)


async def _no_sleep(_seconds: float) -> None:
    return None


class _Stream:
    def __init__(self, events):
        self.events = iter(events)
        self.exits = []

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        self.exits.append(args)

    def __aiter__(self):
        return self

    async def __anext__(self):
        value = next(self.events, StopAsyncIteration)
        if isinstance(value, BaseException):
            raise value
        if value is StopAsyncIteration:
            raise StopAsyncIteration
        return value


class _Messages:
    def __init__(self, *, streams=(), creates=()):
        self.streams = iter(streams)
        self.creates = iter(creates)
        self.stream_calls = 0
        self.create_calls = 0

    def stream(self, **_payload):
        self.stream_calls += 1
        return next(self.streams)

    async def create(self, **_payload):
        self.create_calls += 1
        value = next(self.creates)
        if isinstance(value, BaseException):
            raise value
        return value


@pytest.mark.asyncio
async def test_create_retries_transport_failure_before_returning_provider_result():
    result = object()
    messages = _Messages(creates=[httpx.ConnectError('offline'), result])

    assert await create_managed_anthropic_message(messages, {}, policy=_policy(), _sleep=_no_sleep) is result
    assert messages.create_calls == 2


@pytest.mark.asyncio
async def test_stream_retries_transport_failure_before_first_event():
    event = SimpleNamespace(type='message_start')
    first = _Stream([httpx.ConnectError('offline')])
    second = _Stream([event])
    messages = _Messages(streams=[first, second])

    observed = [
        item async for item in stream_managed_anthropic_events(messages, {}, policy=_policy(), _sleep=_no_sleep)
    ]

    assert observed == [event]
    assert messages.stream_calls == 2
    assert len(first.exits) == 1
    assert len(second.exits) == 1


@pytest.mark.asyncio
async def test_stream_never_retries_after_provider_output_begins():
    event = SimpleNamespace(type='message_start')
    stream = _Stream([event, httpx.ConnectError('disconnected')])
    messages = _Messages(streams=[stream])

    with pytest.raises(httpx.ConnectError):
        _ = [item async for item in stream_managed_anthropic_events(messages, {}, policy=_policy(), _sleep=_no_sleep)]

    assert messages.stream_calls == 1
    assert len(stream.exits) == 1


@pytest.mark.asyncio
async def test_stream_emits_progress_heartbeat_without_cancelling_pending_event():
    clock = [0.0]
    steps = iter(('ready', 'timeout'))

    async def wait(tasks, *, timeout):
        task = next(iter(tasks))
        if next(steps) == 'timeout':
            clock[0] += timeout
            return set(), set(tasks)
        try:
            await task
        except BaseException:
            pass
        return set(tasks), set()

    stream = _Stream([SimpleNamespace(type='message_start')])
    events = stream_managed_anthropic_events(
        _Messages(streams=[stream]),
        {},
        policy=_policy(),
        _monotonic=lambda: clock[0],
        _wait=wait,
    )

    assert (await anext(events)).type == 'message_start'
    assert await anext(events) is ANTHROPIC_STREAM_HEARTBEAT
    await events.aclose()
    assert len(stream.exits) == 1


def test_policy_rejects_nonpositive_environment_values(monkeypatch):
    monkeypatch.setenv('AGENT_STREAM_FIRST_EVENT_TIMEOUT_SECONDS', '0')
    monkeypatch.setenv('AGENT_STREAM_PROVIDER_MAX_ATTEMPTS', 'invalid')

    policy = ManagedAnthropicPolicy.from_environment()

    assert policy.first_event_timeout_seconds == 25.0
    assert policy.provider_max_attempts == 3
