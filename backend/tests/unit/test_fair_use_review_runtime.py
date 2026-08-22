import asyncio
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest

from models.fair_use import SoftCapTrigger
from models.users import PlanType
from routers.listen.contracts import ListenRequest, ListenSessionConfig
from routers.listen.receiver import ListenReceiver
from routers.listen.runtime import ListenSessionRuntime


class ReviewSocket:
    def __init__(self):
        self.events = []

    async def send_json(self, payload):
        self.events.append(payload)


class GatedFirstSendReviewSocket(ReviewSocket):
    def __init__(self):
        super().__init__()
        self.first_send_entered = asyncio.Event()
        self.release_first_send = asyncio.Event()
        self.send_attempts = 0

    async def send_json(self, payload):
        self.send_attempts += 1
        if self.send_attempts == 1:
            self.first_send_entered.set()
            await self.release_first_send.wait()
        self.events.append(payload)


@pytest.mark.asyncio
async def test_cap_crossing_emits_one_content_free_owner_review_event(monkeypatch):
    socket = ReviewSocket()
    runtime = ListenSessionRuntime(
        ListenRequest(
            websocket=socket,
            uid='owner-a',
            config=ListenSessionConfig(language='en'),
            platform='macos',
        )
    )
    totals = {'daily_ms': 7_200_001, 'three_day_ms': 7_200_001, 'weekly_ms': 7_200_001}
    caps = [{'trigger': SoftCapTrigger.DAILY, 'speech_ms': 7_200_001, 'threshold_ms': 7_200_000}]
    review = {
        'review_id': 'review-1',
        'trigger': 'daily',
        'window_speech_ms': totals,
        'thresholds_ms': {'daily_ms': 7_200_000, 'three_day_ms': 28_800_000, 'weekly_ms': 36_000_000},
        'classifier_contract': 'openai/gpt-5.1:prompt-v2',
        'requested_at': '2026-08-21T08:00:00+00:00',
        'expires_at': '2026-08-21T20:00:00+00:00',
        'session_id': runtime.session_id,
    }

    async def call(function, *args, **_kwargs):
        name = function.__name__
        if name == 'get_user_valid_subscription':
            return SimpleNamespace(entitlement_policy=PlanType.bounded)
        if name == 'get_rolling_speech_ms':
            return totals
        if name == 'check_soft_caps':
            return caps
        if name == 'is_free_credits_exhausted':
            return False
        if name == 'create_pending_fair_use_review':
            assert args == ('owner-a', caps, totals, PlanType.bounded, runtime.session_id)
            return review
        if name == 'get_enforcement_stage':
            return 'warning'
        raise AssertionError(f'unexpected persistence call: {name}')

    runtime.persistence.call = call
    monkeypatch.setattr('routers.listen.runtime.FAIR_USE_ENABLED', True)
    monkeypatch.setattr('routers.listen.runtime.FAIR_USE_CHECK_INTERVAL_SECONDS', 0)
    monkeypatch.setattr('routers.listen.runtime.is_daily_audio_ceiling_exceeded', lambda *_args, **_kwargs: False)

    await runtime._refresh_fair_use()
    runtime.state.fair_use_last_check_ts = 0
    await runtime._refresh_fair_use()

    assert socket.events == [
        {
            'review_id': 'review-1',
            'trigger': 'daily',
            'window_speech_ms': totals,
            'thresholds_ms': {
                'daily_ms': 7_200_000,
                'three_day_ms': 28_800_000,
                'weekly_ms': 36_000_000,
            },
            'classifier_contract': 'openai/gpt-5.1:prompt-v2',
            'requested_at': '2026-08-21T08:00:00+00:00',
            'expires_at': '2026-08-21T20:00:00+00:00',
            'type': 'fair_use_review_requested',
        }
    ]
    assert 'uid' not in socket.events[0]
    assert 'title' not in socket.events[0]
    assert 'score' not in socket.events[0]


@pytest.mark.asyncio
async def test_restricted_budget_exhaustion_emits_once_keeps_socket_and_discards_audio(monkeypatch):
    socket = ReviewSocket()
    runtime = ListenSessionRuntime(
        ListenRequest(
            websocket=socket,
            uid='owner-a',
            config=ListenSessionConfig(language='en'),
            platform='macos',
        )
    )
    runtime.state.fair_use_track_managed_stt_usage = True
    runtime.state.fair_use_managed_stt_budget_exhausted = True
    runtime.state.fair_use_allowance_handoff_required = True

    async def call(function, *args, **_kwargs):
        if function.__name__ == 'get_managed_stt_budget_status':
            assert args == ('owner-a',)
            return {
                'daily_limit_ms': 1_800_000,
                'used_ms': 1_800_000,
                'remaining_ms': 0,
                'exhausted': True,
                'resets_at': '2026-08-22T00:00:00Z',
            }
        if function.__name__ == 'get_fair_use_state':
            assert args == ('owner-a',)
            return {'stage': 'restrict', 'last_case_ref': 'FU-ABC123DEF456'}
        raise AssertionError(f'unexpected persistence call: {function.__name__}')

    runtime.persistence.call = call
    runtime.receiver.stt_socket = SimpleNamespace(is_connection_dead=False)
    monkeypatch.setattr('routers.listen.receiver.stt_buffer_flush_size', lambda _sample_rate: 2)
    provider_send = AsyncMock()
    monkeypatch.setattr('routers.listen.receiver.flush_live_stt_buffer', provider_send)

    first = bytearray(b'1234')
    second = bytearray(b'5678')
    await runtime.receiver._flush_stt_buffer(first)
    await runtime.receiver._flush_stt_buffer(second)

    provider_send.assert_not_awaited()
    assert first == bytearray()
    assert second == bytearray()
    assert runtime.state.active is True
    assert socket.events == [
        {
            'resets_at': '2026-08-22T00:00:00Z',
            'case_ref': 'FU-ABC123DEF456',
            'support_email': 'support@heyintentive.com',
            'type': 'fair_use_managed_cloud_exhausted',
        }
    ]


@pytest.mark.asyncio
async def test_concurrent_exhaustion_notifiers_claim_exactly_one_event_send():
    socket = GatedFirstSendReviewSocket()
    runtime = ListenSessionRuntime(
        ListenRequest(
            websocket=socket,
            uid='owner-a',
            config=ListenSessionConfig(language='en'),
            platform='macos',
        )
    )

    async def call(function, *_args, **_kwargs):
        if function.__name__ == 'get_managed_stt_budget_status':
            return {'resets_at': '2026-08-22T00:00:00Z'}
        if function.__name__ == 'get_fair_use_state':
            return {'last_case_ref': 'FU-ABC123DEF456'}
        raise AssertionError(f'unexpected persistence call: {function.__name__}')

    runtime.persistence.call = call
    first = asyncio.create_task(runtime.notify_managed_cloud_exhausted())
    await socket.first_send_entered.wait()

    await runtime.notify_managed_cloud_exhausted()
    assert socket.send_attempts == 1

    socket.release_first_send.set()
    await first
    assert len(socket.events) == 1


@pytest.mark.asyncio
async def test_thirty_hour_ceiling_does_not_emit_the_restricted_thirty_minute_copy(monkeypatch):
    socket = ReviewSocket()
    runtime = ListenSessionRuntime(
        ListenRequest(
            websocket=socket,
            uid='owner-a',
            config=ListenSessionConfig(language='en'),
            platform='macos',
        )
    )
    runtime.state.fair_use_managed_stt_budget_exhausted = True
    runtime.state.fair_use_allowance_handoff_required = False
    runtime.receiver.stt_socket = SimpleNamespace(is_connection_dead=False)
    monkeypatch.setattr('routers.listen.receiver.stt_buffer_flush_size', lambda _sample_rate: 2)
    provider_send = AsyncMock()
    monkeypatch.setattr('routers.listen.receiver.flush_live_stt_buffer', provider_send)

    buffer = bytearray(b'1234')
    await runtime.receiver._flush_stt_buffer(buffer)

    provider_send.assert_not_awaited()
    assert buffer == bytearray()
    assert runtime.state.active is True
    assert socket.events == []


@pytest.mark.asyncio
async def test_active_restriction_does_not_request_another_semantic_review(monkeypatch):
    socket = ReviewSocket()
    runtime = ListenSessionRuntime(
        ListenRequest(
            websocket=socket,
            uid='owner-a',
            config=ListenSessionConfig(language='en'),
            platform='macos',
        )
    )
    created = False

    async def call(function, *_args, **_kwargs):
        nonlocal created
        if function.__name__ == 'get_user_valid_subscription':
            return SimpleNamespace(entitlement_policy=PlanType.bounded)
        if function.__name__ == 'get_rolling_speech_ms':
            return {'daily_ms': 7_200_001, 'three_day_ms': 0, 'weekly_ms': 0}
        if function.__name__ == 'check_soft_caps':
            return [{'trigger': SoftCapTrigger.DAILY, 'speech_ms': 7_200_001, 'threshold_ms': 7_200_000}]
        if function.__name__ == 'is_free_credits_exhausted':
            return False
        if function.__name__ == 'get_enforcement_stage':
            return 'restrict'
        if function.__name__ == 'is_managed_stt_budget_exhausted':
            return False
        if function.__name__ == 'create_pending_fair_use_review':
            created = True
            return None
        raise AssertionError(f'unexpected persistence call: {function.__name__}')

    runtime.persistence.call = call
    monkeypatch.setattr('routers.listen.runtime.FAIR_USE_ENABLED', True)
    monkeypatch.setattr('routers.listen.runtime.FAIR_USE_CHECK_INTERVAL_SECONDS', 0)
    monkeypatch.setattr('routers.listen.runtime.is_daily_audio_ceiling_exceeded', lambda *_args, **_kwargs: False)

    await runtime._refresh_fair_use()

    assert created is False
    assert socket.events == []
