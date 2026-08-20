"""Managed streaming speech-to-text through the fixed Modulate adapter."""

from __future__ import annotations

import asyncio
import inspect
import io
import json
import logging
import os
import threading
import urllib.parse
import uuid
import wave as _wave
from typing import Any, Callable, Dict, List, Optional, cast

import websockets

from config.stt_provider_policy import (
    MODULATE_PROVIDER,
    STTServingSurface,
    modulate_supports_language,
    normalized_stt_language,
    supports_live_multilingual_mode,
)
from utils.log_sanitizer import sanitize
from utils.metrics import OMI_LIVE_STT_MISALIGNED_FRAMES_TOTAL
from utils.stt.socket import STTSocket

logger = logging.getLogger(__name__)


async def drain_stt_socket(socket: STTSocket) -> None:
    """Await a managed socket's tail drain, with a synchronous close fallback."""
    drain_and_close = getattr(socket, 'drain_and_close', None)
    if not callable(drain_and_close):
        socket.finish()
        return
    drain_result = drain_and_close()
    if inspect.isawaitable(drain_result):
        await drain_result
        return
    logger.warning('Managed STT adapter lacks async tail drain')
    socket.finish()


def _requested_stt_language(
    language: Optional[str], base_lang: str, *, multi_lang_enabled: bool, surface: STTServingSurface
) -> str:
    """Resolve the managed language while retaining PTT's explicit input."""
    if base_lang == 'multi' or (
        surface == STTServingSurface.STREAMING
        and multi_lang_enabled
        and language
        and supports_live_multilingual_mode(language)
    ):
        return 'multi'
    return base_lang


def get_managed_stt_language(
    language: Optional[str],
    multi_lang_enabled: bool = True,
    *,
    surface: STTServingSurface = STTServingSurface.STREAMING,
) -> Optional[str]:
    """Return the language accepted by the fixed managed adapter."""
    base_lang = normalized_stt_language(language) or 'en'
    requested_language = _requested_stt_language(
        language,
        base_lang,
        multi_lang_enabled=multi_lang_enabled,
        surface=surface,
    )
    return requested_language if modulate_supports_language(requested_language) else None


def _build_wav_header(sample_rate: int, bits_per_sample: int = 16, channels: int = 1) -> bytes:  # type: ignore[reportUnusedFunction]  # exported, exercised by tests/unit/test_modulate_stt.py
    buf = io.BytesIO()
    with _wave.open(buf, 'wb') as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(bits_per_sample // 8)
        wf.setframerate(sample_rate)
        wf.writeframes(b'')
    return buf.getvalue()


class SafeModulateSocket(STTSocket):
    def __init__(
        self,
        ws: Any,
        stream_transcript: Callable[[List[Dict[str, Any]]], None],
        loop: asyncio.AbstractEventLoop,
        preseconds: int = 0,
        canonical_segments: bool = False,
    ) -> None:
        self._ws: Any = ws
        self._stream_transcript: Callable[[List[Dict[str, Any]]], None] = stream_transcript
        self._loop: asyncio.AbstractEventLoop = loop
        self._preseconds = preseconds
        self._canonical_segments = canonical_segments
        self._dead = False
        self._closed = False
        self._death_reason: Optional[str] = None
        self._lock = threading.Lock()
        self._header_sent = False
        self._wav_header: Optional[bytes] = None
        self._send_queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=2000)
        self._done_event = asyncio.Event()
        self._prev_partial_text: str = ''
        self._prev_partial_start_ms: int = 0
        self._prev_partial_word_count: int = 0
        # Velma rejects any s16le frame that is not a whole number of samples with
        # {"type":"error","error":"Invalid input audio"} and then closes the socket, so a
        # single odd-length frame ends the session even after valid audio. Nothing upstream
        # guarantees even-length buffers, so carry a trailing odd byte to the next frame.
        self._pending_odd_byte: bytes = b''
        self._recv_task: asyncio.Task[None] = asyncio.ensure_future(self._recv_loop(), loop=loop)
        self._send_task: asyncio.Task[None] = asyncio.ensure_future(self._send_loop(), loop=loop)

    def set_wav_header(self, header: bytes) -> None:
        self._wav_header = header

    @property
    def is_connection_dead(self) -> bool:
        return self._dead

    @property
    def death_reason(self) -> Optional[str]:
        return self._death_reason

    def _mark_dead(self, reason: str) -> None:
        with self._lock:
            if not self._dead:
                self._dead = True
                self._death_reason = reason

    def send(self, data: bytes) -> bool:
        """Synchronously accept audio only when it reaches the provider queue.

        The listen handler runs on ``self._loop``.  A producer on a different
        event loop cannot safely wait for a queue callback without blocking that
        loop, so it is treated as a terminal ownership error rather than
        optimistically dropping audio.
        """
        with self._lock:
            if self._dead or self._closed:
                return False
            if not data:
                # b'' is this socket's shutdown sentinel: _send_loop breaks on it and finish()
                # uses it to stop the loop. Enqueuing an empty audio frame would therefore end
                # the send loop mid-session while the socket still reports itself alive, so every
                # later frame would be queued and never sent. The header stays pending because
                # _header_sent is only set once it is queued.
                return True
            aligned = self._pending_odd_byte + data
            self._pending_odd_byte = aligned[-1:] if len(aligned) % 2 else b''
            if self._pending_odd_byte:
                aligned = aligned[:-1]
                misaligned = True
            else:
                misaligned = False
            if misaligned:
                OMI_LIVE_STT_MISALIGNED_FRAMES_TOTAL.labels(provider=MODULATE_PROVIDER, stage='provider_send').inc()
            if not aligned:
                # One carried byte and nothing else yet: it is buffered, not dropped.
                return True
            prepend_header = not self._header_sent and self._wav_header is not None
            queued_data = (self._wav_header or b'') + aligned if prepend_header else aligned

        try:
            current_loop = asyncio.get_running_loop()
        except RuntimeError:
            current_loop = None

        if current_loop is not self._loop:
            # This only occurs in synchronous tests / shutdown code where the
            # provider loop is stopped, so no concurrent queue consumer exists.
            # It remains a truthful immediate enqueue rather than a deferred
            # cross-loop callback. A live foreign loop is a terminal misuse.
            if current_loop is not None or self._loop.is_running():
                self._mark_dead('send called outside provider event loop')
                return False

        try:
            self._send_queue.put_nowait(queued_data)
        except asyncio.QueueFull:
            self._mark_dead('send queue full')
            return False

        if prepend_header:
            with self._lock:
                self._header_sent = True
        return True

    def finalize(self) -> None:
        pass

    def finish(self) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
        try:
            self._loop.call_soon_threadsafe(lambda: self._send_queue.put_nowait(b''))
        except (RuntimeError, Exception):
            pass

    async def drain_and_close(self) -> None:
        try:
            await asyncio.sleep(0)
            _EOS_SENTINEL = b'__EOS__'
            try:
                self._send_queue.put_nowait(_EOS_SENTINEL)
            except asyncio.QueueFull:
                pass
            try:
                await asyncio.wait_for(self._send_task, timeout=10)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                pass
            try:
                await asyncio.wait_for(self._done_event.wait(), timeout=60)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                logger.warning('Modulate drain timed out waiting for done message')
                if self._prev_partial_text:
                    self._flush_partial()
        except Exception:
            pass
        if self._prev_partial_text:
            self._flush_partial()
        self._recv_task.cancel()
        try:
            await self._ws.close()
        except Exception:
            pass

    async def _send_loop(self) -> None:
        _EOS_SENTINEL = b'__EOS__'
        try:
            while not self._closed and not self._dead:
                data = await self._send_queue.get()
                if data == b'':
                    break
                if data == _EOS_SENTINEL:
                    # Docs: send empty text frame ("") to signal end of audio stream
                    await self._ws.send('')
                    break
                await self._ws.send(data)
        except websockets.exceptions.ConnectionClosed as e:
            self._mark_dead(f'ws send closed: {e}')
        except Exception as e:
            self._mark_dead(f'ws send error: {e}')

    async def _recv_loop(self) -> None:
        try:
            async for raw_msg in self._ws:
                if self._closed:
                    break
                try:
                    loaded: object = json.loads(raw_msg)
                except (json.JSONDecodeError, TypeError):
                    continue
                if not isinstance(loaded, dict):
                    continue
                msg: Dict[str, Any] = cast(Dict[str, Any], loaded)

                msg_type = msg.get('type', '')
                if msg_type == 'error':
                    err = msg.get('error', msg.get('message', 'unknown error'))
                    logger.error('Modulate streaming error: %s', sanitize(err))
                    if self._prev_partial_text:
                        self._flush_partial()
                    self._done_event.set()
                    self._mark_dead('modulate provider error')
                    break
                elif msg_type == 'done':
                    logger.info('Modulate streaming done: duration_ms=%s', msg.get('duration_ms'))
                    if self._prev_partial_text:
                        self._flush_partial()
                    self._done_event.set()
                    break
                elif msg_type == 'partial_utterance':
                    pu = msg.get('partial_utterance', msg)
                    self._handle_partial_utterance(pu)
                elif msg_type == 'utterance':
                    utt = msg.get('utterance', msg)
                    self._handle_utterance(utt)
            # A clean async-for exhaustion means the provider closed the upstream
            # WebSocket without raising. A local drain (self._closed) or an
            # explicit provider 'done' (self._done_event) is expected
            # finalization; any other clean close is unexpected provider death and
            # must latch terminal so the listen loop propagates it without waiting
            # for another client audio frame (#10028).
            if not self._closed and not self._done_event.is_set():
                self._mark_dead('modulate ws closed cleanly without terminal frame')
        except websockets.exceptions.ConnectionClosed as e:
            self._mark_dead(f'ws recv closed: {e}')
        except Exception as e:
            self._mark_dead(f'ws recv error: {e}')

    def _handle_partial_utterance(self, msg: Dict[str, Any]) -> None:
        if self._canonical_segments:
            return
        # Modulate sends cumulative partial_utterance messages during streaming
        # (e.g., "He", "He could", "He could hardly"...) but these are preview-only.
        # We buffer them here and only forward the final `utterance` via _handle_utterance.
        #
        # Limitation: the user sees no live text until the utterance finalizes
        # (after the speech segment completes). For continuous speech, this can be
        # the entire clip duration. Modulate has no endpointing config to control this.
        # The retired adapter used endpointing to deliver finalized chunks mid-stream.
        #
        # To add live preview from partials, implement delta extraction (Option C-lite):
        # track committed words, emit only new stable words as incremental segments.
        # This would require careful handling of Modulate's occasional mid-partial
        # text revisions and start_ms shifts.
        text = msg.get('text', '').strip()
        if not text:
            return
        start_ms = msg.get('start_ms', 0)
        self._prev_partial_text = text
        self._prev_partial_start_ms = start_ms
        self._prev_partial_word_count = len(text.split())

    def _flush_partial(self) -> None:
        if self._canonical_segments:
            self._prev_partial_text = ''
            self._prev_partial_word_count = 0
            return
        text = self._prev_partial_text
        start_ms = self._prev_partial_start_ms
        self._prev_partial_text = ''
        self._prev_partial_word_count = 0
        if not text:
            return
        start = start_ms / 1000.0
        if self._preseconds and start < self._preseconds:
            return
        segments = [
            {
                'speaker': 'SPEAKER_00',
                'start': start,
                'end': start,
                'text': text,
                'is_user': False,
                'person_id': None,
            }
        ]
        self._stream_transcript(segments)

    def _handle_utterance(self, msg: Dict[str, Any]) -> None:
        if self._canonical_segments:
            self._stream_transcript([canonical_segment_from_modulate(msg)])
            self._prev_partial_text = ''
            self._prev_partial_word_count = 0
            return

        text = msg.get('text', '').strip()
        if not text:
            return

        self._prev_partial_text = ''
        self._prev_partial_word_count = 0

        start_ms = msg.get('start_ms', 0)
        duration_ms = msg.get('duration_ms', 0)
        start = start_ms / 1000.0
        end = (start_ms + duration_ms) / 1000.0

        if self._preseconds and start < self._preseconds:
            return

        raw_speaker = msg.get('speaker')
        if isinstance(raw_speaker, int) and raw_speaker >= 1:
            speaker_idx = raw_speaker - 1
        else:
            speaker_idx = 0
        speaker = f'SPEAKER_{speaker_idx:02d}'

        segments = [
            {
                'speaker': speaker,
                'start': start,
                'end': end,
                'text': text,
                'is_user': False,
                'person_id': None,
            }
        ]
        self._stream_transcript(segments)


def canonical_segment_from_modulate(utterance: Dict[str, Any]) -> Dict[str, Any]:
    """Validate and project a finalized Velma utterance into the public listen DTO."""
    raw_segment_id = utterance.get('utterance_uuid')
    if not isinstance(raw_segment_id, str):
        raise ValueError('Modulate utterance is missing utterance_uuid')
    try:
        segment_id = str(uuid.UUID(raw_segment_id))
    except ValueError as error:
        raise ValueError('Modulate utterance_uuid is not a UUID') from error

    text = utterance.get('text')
    if not isinstance(text, str) or not text.strip():
        raise ValueError('Modulate utterance is missing text')
    start_ms = utterance.get('start_ms')
    duration_ms = utterance.get('duration_ms')
    if not isinstance(start_ms, (int, float)) or start_ms < 0:
        raise ValueError('Modulate utterance start_ms is invalid')
    if not isinstance(duration_ms, (int, float)) or duration_ms < 0:
        raise ValueError('Modulate utterance duration_ms is invalid')
    raw_speaker = utterance.get('speaker')
    if not isinstance(raw_speaker, int) or isinstance(raw_speaker, bool) or raw_speaker < 1:
        raise ValueError('Modulate utterance speaker is invalid')

    return {
        'segmentId': segment_id,
        'speakerId': raw_speaker - 1,
        'text': text.strip(),
        'start': start_ms / 1000.0,
        'end': (start_ms + duration_ms) / 1000.0,
    }


async def process_audio_modulate(
    stream_transcript: Callable[[List[Dict[str, Any]]], None],
    sample_rate: int,
    language: str,
    preseconds: int = 0,
    *,
    vocabulary: tuple[str, ...] = (),
    canonical_segments: bool = False,
) -> SafeModulateSocket:
    api_key = os.getenv('MODULATE_API_KEY')
    if not api_key:
        raise ValueError('MODULATE_API_KEY environment variable is not set')

    params = {
        'api_key': api_key,
        'speaker_diarization': 'true',
        'partial_results': 'false' if canonical_segments else 'true',
        'sample_rate': str(sample_rate),
        'audio_format': 's16le',
        'num_channels': '1',
    }
    if language and language != 'multi' and not canonical_segments:
        params['language'] = language
    endpoint = (
        'wss://platform.modulate.ai/api/velma-2-stt-streaming'
        if canonical_segments
        else 'wss://modulate-developer-apis.com/api/velma-2-stt-streaming'
    )
    uri = f'{endpoint}?{urllib.parse.urlencode(params)}'

    logger.info(f'Connecting to Modulate Velma-2 streaming sample_rate={sample_rate} language={language}')
    ws = await websockets.connect(uri, ping_timeout=10, ping_interval=10)
    if canonical_segments:
        configuration: Dict[str, Any] = {}
        if language and language != 'multi':
            configuration['language'] = language
        if vocabulary:
            configuration['custom_terms'] = list(vocabulary)
        configuration['speaker_diarization'] = True
        configuration['partial_results'] = False
        await ws.send(json.dumps(configuration, separators=(',', ':')))
    loop = asyncio.get_running_loop()
    sock = SafeModulateSocket(
        ws,
        stream_transcript,
        loop,
        preseconds=preseconds,
        canonical_segments=canonical_segments,
    )
    logger.info('Modulate Velma-2 streaming connection established')
    return sock


def sort_segments_by_start(segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return sorted(segments, key=lambda s: s.get('start', 0))


def make_stream_callback(
    callback: Callable[[List[Dict[str, Any]]], None],
    vad_gate: Any,
    passthrough: bool,
) -> Callable[[List[Dict[str, Any]]], None]:
    if vad_gate is not None and not passthrough:

        def wrapped(segments: List[Dict[str, Any]]) -> None:
            vad_gate.remap_segments(segments)
            callback(segments)

        return wrapped
    return callback


def sort_transcript_segments_in_place(segments: List[Any]) -> None:
    segments.sort(key=lambda s: s.start)
