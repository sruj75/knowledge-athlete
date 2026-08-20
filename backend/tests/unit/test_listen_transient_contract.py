"""Behavioral contract for the transient-only ``/v4/listen`` surface.

Modulate's documented streaming contract is the external source for the first
configuration frame and finalized utterance fields:
https://docs.modulate.ai/api-reference/stt/streaming
"""

from __future__ import annotations

import asyncio
import json
import uuid
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
import routers.transcribe as transcribe
from starlette.websockets import WebSocketDisconnect, WebSocketState
from utils.other import endpoints as auth


def _listen_app(monkeypatch: pytest.MonkeyPatch) -> tuple[TestClient, AsyncMock]:
    captured = AsyncMock()

    async def run_transient(request):
        await captured(request)
        await request.websocket.send_json({"type": "service_status", "status": "ready"})
        await request.websocket.close(code=1000)

    monkeypatch.setattr(transcribe, "run_listen_session", run_transient)
    app = FastAPI()
    app.include_router(transcribe.router)
    app.dependency_overrides[auth.get_current_user_uid_ws_listen] = lambda: "uid-transient"
    return TestClient(app), captured


def test_route_accepts_only_immutable_session_snapshot(monkeypatch: pytest.MonkeyPatch):
    client, captured = _listen_app(monkeypatch)

    with client.websocket_connect(
        "/v4/listen?language=auto&translation_target=es&vocabulary=Omi&vocabulary=Knowledge%20Athlete",
        headers={"Authorization": "Bearer test", "X-App-Platform": "macos"},
    ) as websocket:
        assert websocket.receive_json() == {"type": "service_status", "status": "ready"}

    request = captured.await_args.args[0]
    assert request.uid == "uid-transient"
    assert request.config.language == "auto"
    assert request.config.translation_target == "es"
    assert request.config.vocabulary == ("Omi", "Knowledge Athlete")
    assert request.platform == "macos"
    assert request.audio.sample_rate == 16_000
    assert request.audio.channels == 1
    assert request.audio.codec == "s16le"


@pytest.mark.asyncio
async def test_peer_close_stops_delivery_without_skipping_final_usage_flush():
    """Drive the real supervisor loop: peer loss must not skip final accounting."""
    from routers.listen.contracts import ListenRequest, ListenSessionConfig
    from routers.listen.runtime import ListenSessionRuntime

    class PeerSocket:
        client_state = WebSocketState.CONNECTED

        def __init__(self):
            self.events = []

        async def send_json(self, payload):
            if payload.get("type") == "segments":
                raise RuntimeError("Cannot call send once a close message has been sent")
            self.events.append(payload)

        async def send_text(self, _payload):
            return None

        async def close(self, **_kwargs):
            self.client_state = WebSocketState.DISCONNECTED

    peer = PeerSocket()
    runtime = ListenSessionRuntime(
        ListenRequest(
            websocket=peer,
            uid="uid-transient",
            config=ListenSessionConfig(language="en"),
            platform="macos",
        )
    )
    runtime._admit = AsyncMock(return_value=True)
    runtime.receiver.initialize_stt = AsyncMock(return_value=True)
    runtime.receiver.finish = lambda: None
    runtime._flush_usage = AsyncMock(return_value=0)

    async def receive_one_segment():
        runtime.transcripts.enqueue(
            [
                {
                    "segmentId": "00000000-0000-4000-8000-000000000001",
                    "speakerId": 0,
                    "text": "owed work",
                    "start": 0.0,
                    "end": 1.0,
                }
            ]
        )
        await runtime.state.shutdown_event.wait()

    runtime.receiver.receive_data = receive_one_segment

    await asyncio.wait_for(runtime.run(), timeout=2)

    assert peer.events == [{"type": "service_status", "status": "ready"}]
    assert runtime.state.active is False
    runtime._flush_usage.assert_awaited_once_with(final=True)


@pytest.mark.parametrize(
    "query",
    [
        "transient_only=true",
        "sample_rate=8000",
        "codec=pcm8",
        "channels=2",
        "source=desktop",
        "custom_stt=enabled",
        "onboarding=enabled",
        "speaker_auto_assign=enabled",
        "create_speakers=true",
        "vad_gate=disabled",
        "call_id=call-1",
        "client_conversation_id=00000000-0000-0000-0000-000000000000",
        "provider=deepgram",
        "unknown=value",
    ],
)
def test_retired_or_unknown_query_fails_closed(monkeypatch: pytest.MonkeyPatch, query: str):
    client, captured = _listen_app(monkeypatch)

    with pytest.raises(WebSocketDisconnect) as closed:
        with client.websocket_connect(
            f"/v4/listen?language=en&{query}",
            headers={"Authorization": "Bearer test", "X-App-Platform": "macos"},
        ):
            pass

    assert closed.value.code == 1008
    captured.assert_not_awaited()


def test_web_listen_route_is_absent(monkeypatch: pytest.MonkeyPatch):
    client, _ = _listen_app(monkeypatch)
    paths = {getattr(route, "path", None) for route in client.app.routes}
    assert "/v4/listen" in paths
    assert "/v4/web/listen" not in paths


def test_real_route_streams_segment_and_keyed_translation_without_product_state(monkeypatch: pytest.MonkeyPatch):
    from routers import transcribe
    from routers.listen import receiver, runtime
    from utils.listen_session_bootstrap import ListenAdmissionSnapshot
    from utils.other import endpoints as auth
    from utils.translation import TranslationService

    segment_id = "ea8537e0-821a-44c8-96f2-2dbbe5085240"

    class FakeSocket:
        is_connection_dead = False

        def __init__(self, callback):
            self.callback = callback
            self.delivered = False

        def send(self, _audio):
            if not self.delivered:
                self.delivered = True
                self.callback(
                    [
                        {
                            "segmentId": segment_id,
                            "speakerId": 1,
                            "text": "Hello there.",
                            "start": 0.0,
                            "end": 1.0,
                        }
                    ]
                )
            return True

        def finish(self):
            return None

        async def drain_and_close(self):
            return None

    async def fake_modulate(callback, *_args, **_kwargs):
        return FakeSocket(callback)

    async def admitted(_uid):
        return ListenAdmissionSnapshot(True, True, False, False)

    async def immediate(_executor, function, *args, **kwargs):
        return function(*args, **kwargs)

    monkeypatch.setattr(receiver, "process_audio_modulate", fake_modulate)
    monkeypatch.setattr(receiver, "is_gate_enabled", lambda: False)
    monkeypatch.setattr(runtime, "load_listen_admission", admitted)
    monkeypatch.setattr(runtime, "run_blocking", immediate)
    monkeypatch.setattr(runtime, "is_trial_paywalled", lambda *_args: False)
    monkeypatch.setattr(runtime, "record_usage", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(
        TranslationService,
        "translate_units_batch",
        lambda _self, target, units: [(units[0][0], "Hola.", "en")],
    )

    app = FastAPI()
    app.include_router(transcribe.router)
    app.dependency_overrides[auth.get_current_user_uid_ws_listen] = lambda: "uid-transient"

    with TestClient(app) as client:
        with client.websocket_connect(
            "/v4/listen?language=en&translation_target=es&vocabulary=Omi",
            headers={"Authorization": "Bearer test", "X-App-Platform": "macos"},
        ) as websocket:
            assert _receive_event(websocket, "service_status") == {"type": "service_status", "status": "ready"}
            websocket.send_bytes(b"\x00\x00" * 480)
            assert _receive_event(websocket, "segments") == {
                "type": "segments",
                "segments": [
                    {
                        "segmentId": segment_id,
                        "speakerId": 1,
                        "text": "Hello there.",
                        "start": 0.0,
                        "end": 1.0,
                    }
                ],
            }
            assert _receive_event(websocket, "translation") == {
                "type": "translation",
                "segmentId": segment_id,
                "language": "es",
                "text": "Hola.",
            }


def test_real_route_reports_provider_initialization_failure_without_ready(monkeypatch: pytest.MonkeyPatch):
    from routers.listen import receiver, runtime
    from utils.listen_session_bootstrap import ListenAdmissionSnapshot

    async def unavailable_modulate(*_args, **_kwargs):
        return None

    async def admitted(_uid):
        return ListenAdmissionSnapshot(True, True, False, False)

    async def immediate(_executor, function, *args, **kwargs):
        return function(*args, **kwargs)

    monkeypatch.setattr(receiver, "process_audio_modulate", unavailable_modulate)
    monkeypatch.setattr(receiver, "is_gate_enabled", lambda: False)
    monkeypatch.setattr(runtime, "load_listen_admission", admitted)
    monkeypatch.setattr(runtime, "run_blocking", immediate)
    monkeypatch.setattr(runtime, "is_trial_paywalled", lambda *_args: False)

    app = FastAPI()
    app.include_router(transcribe.router)
    app.dependency_overrides[auth.get_current_user_uid_ws_listen] = lambda: "uid-transient"

    with TestClient(app) as client:
        with client.websocket_connect(
            "/v4/listen?language=en",
            headers={"Authorization": "Bearer test", "X-App-Platform": "macos"},
        ) as websocket:
            failure = websocket.receive_json()
            assert failure["type"] == "service_status"
            assert failure["status"] == "stt_failed"
            assert failure["reason"] == "initialization_failed"
            with pytest.raises(WebSocketDisconnect):
                websocket.receive_json()


@pytest.mark.asyncio
async def test_listen_vad_active_path_gates_audio_and_initialization_failure_records_fallback(monkeypatch):
    from routers.listen import receiver
    from routers.listen.contracts import ListenAudioContract, ListenRequest, ListenSessionConfig

    class RawSocket:
        is_connection_dead = False
        death_reason = None

        def send(self, _audio):
            return True

        def finish(self):
            return None

    request = ListenRequest(
        websocket=SimpleNamespace(),
        uid="uid-transient",
        config=ListenSessionConfig(language="en"),
        platform="macos",
        audio=ListenAudioContract(),
    )

    def host():
        def discard(coroutine, *, name):
            coroutine.close()
            return SimpleNamespace(name=name)

        return SimpleNamespace(
            request=request,
            session_id="session-transient",
            transcripts=SimpleNamespace(enqueue=lambda _segments: None),
            state=SimpleNamespace(),
            spawn=discard,
        )

    gate = SimpleNamespace(mode="active")
    monkeypatch.setattr(receiver, "is_gate_enabled", lambda: True)
    monkeypatch.setattr(receiver, "VADStreamingGate", lambda **_kwargs: gate)
    monkeypatch.setattr(receiver, "process_audio_modulate", AsyncMock(return_value=RawSocket()))
    active = receiver.ListenReceiver(host())

    assert await active.initialize_stt() is True
    assert active.stt_socket._gate is gate
    assert active.stt_socket._passthrough_audio is False

    recorded = []
    monkeypatch.setattr(receiver, "VADStreamingGate", lambda **_kwargs: (_ for _ in ()).throw(RuntimeError("vad")))
    monkeypatch.setattr(receiver, "record_fallback", lambda **fields: recorded.append(fields))
    failed_gate = receiver.ListenReceiver(host())

    assert await failed_gate.initialize_stt() is True
    assert recorded == [
        {
            "component": "vad",
            "from_mode": "gated",
            "to_mode": "direct",
            "reason": "other",
            "outcome": "degraded",
        }
    ]


@pytest.mark.parametrize(
    "query",
    [
        [("language", "")],
        [("language", "en"), ("translation_target", "not-a-language")],
        [("language", "en"), ("vocabulary", "")],
        [("language", "en"), ("vocabulary", "x" * 257)],
        [("language", "en"), *[("vocabulary", str(index)) for index in range(101)]],
        [("language", "en"), ("vocabulary", "x" * 8_001)],
    ],
)
def test_invalid_snapshot_is_rejected_before_audio(query: list[tuple[str, str]]):
    from routers.listen.contracts import ListenContractError, ListenSessionConfig

    with pytest.raises(ListenContractError):
        ListenSessionConfig.from_query(query)


def test_rejected_query_reason_never_echoes_untrusted_field_or_value():
    from routers.listen.contracts import ListenContractError, ListenSessionConfig

    with pytest.raises(ListenContractError) as rejected:
        ListenSessionConfig.from_query([("language", "en"), ("secret-field", "secret-value")])

    assert str(rejected.value) == "unsupported listen query field"
    assert "secret" not in str(rejected.value)


def test_modulate_final_utterance_becomes_one_stable_canonical_segment():
    from utils.stt.streaming import canonical_segment_from_modulate

    provider_id = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
    utterance = {
        "utterance_uuid": provider_id,
        "text": "Hello from Modulate.",
        "start_ms": 1_250,
        "duration_ms": 2_500,
        "speaker": 2,
        "language": "en",
        "emotion": None,
    }

    first = canonical_segment_from_modulate(utterance)
    second = canonical_segment_from_modulate(dict(utterance))

    uuid.UUID(first["segmentId"])
    assert (
        first
        == second
        == {
            "segmentId": provider_id,
            "speakerId": 1,
            "text": "Hello from Modulate.",
            "start": 1.25,
            "end": 3.75,
        }
    )
    assert set(first) == {"segmentId", "speakerId", "text", "start", "end"}


def test_canonical_adapter_never_projects_provider_partials():
    from utils.stt.streaming import SafeModulateSocket

    delivered = []
    socket = object.__new__(SafeModulateSocket)
    socket._canonical_segments = True
    socket._stream_transcript = delivered.extend
    socket._prev_partial_text = "preview only"
    socket._prev_partial_start_ms = 0
    socket._prev_partial_word_count = 2

    socket._handle_partial_utterance({"text": "new preview"})
    socket._flush_partial()

    assert delivered == []
    assert socket._prev_partial_text == ""


@pytest.mark.asyncio
async def test_modulate_first_frame_contains_exact_session_configuration(monkeypatch: pytest.MonkeyPatch):
    from utils.stt import streaming

    provider_socket = AsyncMock()
    provider_socket.__aiter__.return_value = iter(())
    monkeypatch.setenv("MODULATE_API_KEY", "test-modulate-key")
    monkeypatch.setattr(streaming.websockets, "connect", AsyncMock(return_value=provider_socket))

    socket = await streaming.process_audio_modulate(
        lambda _segments: None,
        16_000,
        "en",
        vocabulary=("Omi", "Knowledge Athlete"),
        canonical_segments=True,
    )
    await asyncio.sleep(0)

    provider_uri = streaming.websockets.connect.await_args.args[0]
    assert provider_uri.startswith("wss://platform.modulate.ai/api/velma-2-stt-streaming?")
    provider_socket.send.assert_awaited_once_with(
        json.dumps(
            {
                "language": "en",
                "custom_terms": ["Omi", "Knowledge Athlete"],
                "speaker_diarization": True,
                "partial_results": False,
            },
            separators=(",", ":"),
        )
    )
    socket.finish()


class _TranslationService:
    def __init__(self, outcomes):
        self.outcomes = outcomes
        self.calls = []

    def translate_units_batch(self, target, units):
        self.calls.append((target, units))
        if isinstance(self.outcomes, Exception):
            raise self.outcomes
        return self.outcomes

    def clear_session_cache(self):
        return None


def _transcript_host(target="es"):
    events = []
    state = SimpleNamespace(
        active=True,
        last_transcript_time=None,
        words_transcribed_since_last_record=0,
    )

    async def send_json(payload):
        events.append(payload)
        return True

    return (
        SimpleNamespace(
            state=state,
            request=SimpleNamespace(config=SimpleNamespace(translation_target=target)),
            send_json=send_json,
            complete_live_transcription=lambda: None,
            now=lambda: 10.0,
            spawn=lambda coroutine, *, name: asyncio.create_task(coroutine, name=name),
        ),
        events,
    )


@pytest.mark.asyncio
async def test_transient_translation_is_keyed_by_segment_without_product_storage(monkeypatch):
    from routers.listen import transcripts

    segment_id = "6bd0410a-a65f-48ed-9315-701f01eefb3b"
    service = _TranslationService([(segment_id, "Hola", "en")])
    host, events = _transcript_host()
    processor = transcripts.TransientTranscriptProcessor(host, translation_service=service)
    monkeypatch.setattr(transcripts, "run_blocking", _immediate)

    loop = asyncio.create_task(processor.process_loop())
    processor.enqueue([{"segmentId": segment_id, "speakerId": 0, "text": "Hello", "start": 0.0, "end": 1.0}])
    await processor.flush()
    host.state.active = False
    await loop

    assert events == [
        {
            "type": "segments",
            "segments": [{"segmentId": segment_id, "speakerId": 0, "text": "Hello", "start": 0.0, "end": 1.0}],
        },
        {"type": "translation", "segmentId": segment_id, "language": "es", "text": "Hola"},
    ]
    assert service.calls == [("es", [(segment_id, "Hello")])]


@pytest.mark.asyncio
async def test_translation_failure_keeps_original_transient_segment(monkeypatch):
    from routers.listen import transcripts

    segment_id = "6bd0410a-a65f-48ed-9315-701f01eefb3b"
    host, events = _transcript_host()
    processor = transcripts.TransientTranscriptProcessor(host, translation_service=_TranslationService(RuntimeError()))
    monkeypatch.setattr(transcripts, "run_blocking", _immediate)

    loop = asyncio.create_task(processor.process_loop())
    processor.enqueue([{"segmentId": segment_id, "speakerId": 0, "text": "Hello", "start": 0.0, "end": 1.0}])
    await processor.flush()
    host.state.active = False
    await loop

    assert len(events) == 1
    assert events[0]["type"] == "segments"
    assert events[0]["segments"][0]["text"] == "Hello"


async def _immediate(_executor, function, *args, **kwargs):
    return function(*args, **kwargs)


def _receive_event(websocket, event_type):
    while True:
        message = websocket.receive()
        text = message.get("text")
        if text == "ping":
            continue
        if text:
            payload = json.loads(text)
            if payload.get("type") == event_type:
                return payload
