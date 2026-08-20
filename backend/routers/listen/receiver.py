"""Fixed mono 16 kHz s16le receiver for transient listen sessions."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, cast

from fastapi.websockets import WebSocketDisconnect

from config.stt_provider_policy import MODULATE_PROVIDER
from utils.observability.fallback import record_fallback
from utils.stt.live_failure import (
    flush_live_stt_buffer,
    live_stt_initialization_failure,
    live_stt_socket_is_dead,
    live_stt_upstream_failure,
    terminate_live_stt_session,
)
from utils.stt.streaming import make_stream_callback, process_audio_modulate
from utils.stt.vad_gate import GatedSTTSocket, VADStreamingGate, VAD_GATE_MODE, is_gate_enabled
from utils.transcribe_decisions import decide_stt_buffer_flush, stt_buffer_flush_size

logger = logging.getLogger(__name__)

STT_DEATH_POLL_INTERVAL_SECONDS = 1.0


class ListenReceiver:
    def __init__(self, host: Any):
        self.host = host
        self.stt_socket: Any = None
        self.vad_gate: VADStreamingGate | None = None

    async def _create_stt_socket(self, callback: Any) -> Any:
        config = self.host.request.config
        return await process_audio_modulate(
            callback,
            self.host.request.audio.sample_rate,
            config.modulate_language,
            vocabulary=config.vocabulary,
            canonical_segments=True,
        )

    async def initialize_stt(self) -> bool:
        request = self.host.request
        try:
            if is_gate_enabled():
                try:
                    self.vad_gate = VADStreamingGate(
                        sample_rate=request.audio.sample_rate,
                        channels=request.audio.channels,
                        mode=VAD_GATE_MODE,
                        uid=request.uid,
                        session_id=self.host.session_id,
                    )
                except Exception:
                    logger.exception("VAD gate initialization failed; continuing without it")
                    record_fallback(
                        component="vad",
                        from_mode="gated",
                        to_mode="direct",
                        reason="other",
                        outcome="degraded",
                    )
                    self.vad_gate = None

            managed_callback = make_stream_callback(self.host.transcripts.enqueue, self.vad_gate, True)
            raw_socket = await self._create_stt_socket(managed_callback)
            if raw_socket is None:
                await terminate_live_stt_session(
                    request.websocket,
                    self.host.state,
                    failure=live_stt_upstream_failure(MODULATE_PROVIDER),
                    reason="initialization_failed",
                    platform=request.platform,
                )
                return False
            self.stt_socket = GatedSTTSocket(raw_socket, gate=self.vad_gate) if self.vad_gate else raw_socket
            self.host.spawn(self._monitor_stt_death(), name="stt_death_monitor")
            return True
        except Exception as error:
            await terminate_live_stt_session(
                request.websocket,
                self.host.state,
                failure=live_stt_initialization_failure(error, MODULATE_PROVIDER),
                reason="initialization_failed",
                platform=request.platform,
            )
            return False

    async def _monitor_stt_death(self) -> None:
        while self.host.state.active and not self.host.state.stt_terminal_failure:
            if self.stt_socket is not None and live_stt_socket_is_dead(self.stt_socket):
                await terminate_live_stt_session(
                    self.host.request.websocket,
                    self.host.state,
                    failure=live_stt_upstream_failure(MODULATE_PROVIDER),
                    reason="connection_lost",
                    platform=self.host.request.platform,
                )
                return
            if await self.host.wait(STT_DEATH_POLL_INTERVAL_SECONDS):
                return

    async def _flush_stt_buffer(self, buffer: bytearray, *, force: bool = False) -> None:
        request = self.host.request
        socket_dead = self.stt_socket is not None and live_stt_socket_is_dead(self.stt_socket)
        decision = decide_stt_buffer_flush(
            buffer_len=len(buffer),
            flush_size=stt_buffer_flush_size(request.audio.sample_rate),
            force=force,
            socket_dead=socket_dead,
            socket_available=self.stt_socket is not None,
            fair_use_managed_stt_budget_exhausted=self.host.state.fair_use_managed_stt_budget_exhausted,
            fair_use_track_managed_stt_usage=self.host.state.fair_use_track_managed_stt_usage,
            sample_rate=request.audio.sample_rate,
        )
        if not decision.should_flush:
            return
        if self.host.state.fair_use_managed_stt_budget_exhausted:
            buffer.clear()
            return
        sent = await flush_live_stt_buffer(
            request.websocket,
            self.host.state,
            stt_socket=self.stt_socket,
            buffer=buffer,
            provider=MODULATE_PROVIDER,
            platform=request.platform,
        )
        if sent:
            self.host.state.managed_stt_usage_ms_pending += decision.managed_stt_usage_ms

    async def receive_data(self) -> None:
        request = self.host.request
        buffer = bytearray()
        now = self.host.now()
        self.host.state.last_audio_received_time = now
        self.host.state.last_activity_time = now
        try:
            while self.host.state.active:
                try:
                    message = await asyncio.wait_for(
                        request.websocket.receive(), timeout=self.host.limits.ws_receive_timeout
                    )
                except asyncio.TimeoutError:
                    break
                self.host.state.last_activity_time = self.host.now()
                if message.get("type") == "websocket.disconnect":
                    self.host.state.close_code = message.get("code", 1000)
                    break
                data = message.get("bytes")
                if data is not None:
                    if not data:
                        continue
                    now = self.host.now()
                    self.host.state.last_audio_received_time = now
                    if self.host.state.first_audio_byte_timestamp is None:
                        self.host.state.first_audio_byte_timestamp = now
                        self.host.state.last_usage_record_timestamp = now
                        self.host.start_live_transcription()
                    buffer.extend(cast(bytes, data))
                    await self._flush_stt_buffer(buffer)
                    continue
                if message.get("text") is not None:
                    self.host.state.close_code = 1008
                    self.host.state.active = False
                    await request.websocket.close(code=1008, reason="listen accepts binary PCM frames only")
                    break
        except WebSocketDisconnect:
            pass
        except Exception as error:
            logger.error("Listen receive failure type=%s", type(error).__name__)
            self.host.state.close_code = 1011
        finally:
            if self.vad_gate is not None:
                logger.info(json.dumps(self.vad_gate.to_json_log()))
            if not self.host.state.stt_terminal_failure:
                await self._flush_stt_buffer(buffer, force=True)
            await self._drain_stt_socket()
            self.host.state.active = False

    async def _drain_stt_socket(self) -> None:
        socket = self.stt_socket
        target = socket._conn if isinstance(socket, GatedSTTSocket) else socket  # type: ignore[reportPrivateUsage]
        if target is None:
            return
        try:
            drain = getattr(target, "drain_and_close", None)
            if callable(drain):
                await cast(Any, drain)()
            else:
                target.finish()
        except Exception as error:
            logger.warning("Listen STT drain failed type=%s", type(error).__name__)
        finally:
            self.stt_socket = None

    def finish(self) -> None:
        if self.stt_socket:
            self.stt_socket.finish()
