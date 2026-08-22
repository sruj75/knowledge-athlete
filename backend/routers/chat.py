import asyncio
import base64
import json
import tempfile
import uuid
import re
from datetime import datetime, timezone
from typing import List, Optional
from pathlib import Path

from utils.executors import critical_executor, db_executor, storage_executor, sync_executor, run_blocking

from fastapi import (
    APIRouter,
    Depends,
    Header,
    HTTPException,
    Request,
    UploadFile,
    File,
    Form,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.responses import StreamingResponse
from multipart.multipart import shutil
from pydantic import BaseModel

import database.chat as chat_db
from models.chat import (
    Message,
    FileChat,
)
from utils.chat import (
    resolve_voice_message_language,
    transcribe_voice_message_segment,
    transcribe_pcm_bytes,
)
from utils.sync.files import retrieve_file_paths, decode_files_to_wav
from utils.stt.streaming import drain_stt_socket, get_managed_stt_language, process_audio_modulate
from utils.stt.pre_recorded import get_prerecorded_service
from config.prerecorded_stt import TranscriptionOutcome
from config.stt_provider_policy import MODULATE_MODEL, MODULATE_PROVIDER, STTServingSurface
from utils.stt.outcomes import TranscriptionFailure, failure_from_exception
from utils.observability.transcription import TranscriptionAttempt
from database.redis_db import check_rate_limit
from utils.rate_limit_config import get_effective_limit, RATE_LIMIT_SHADOW
from utils.subscription import is_trial_paywalled
from utils.other import endpoints as auth, storage
from utils.other.chat_file import FileChatTool
from utils.multipart import (
    CHAT_FILE_MAX_PART_SIZE,
    MultipartMaxPartSizeRoute,
    VOICE_MESSAGE_MAX_PART_SIZE,
    max_part_size,
    parse_multipart_form,
)
from utils.voice_duration_limiter import (
    compute_pcm_duration_ms,
    read_wav_duration_ms,
    try_consume_budget,
    check_budget,
    record_actual_duration,
)
from testing.parity_pack_v0.live_capture import SurfaceParityCapture
import logging

logger = logging.getLogger(__name__)

router = APIRouter(route_class=MultipartMaxPartSizeRoute)

# WS idle timeout: close if no audio bytes received for this long
_WS_IDLE_TIMEOUT_S = 60

# Hard body-size cap for octet-stream uploads (200 MB).
# Prevents memory exhaustion from oversized payloads regardless of budget.
_MAX_PCM_BODY_BYTES = 200_000_000


class VoiceMessageTranscriptionResponse(BaseModel):
    transcript: str
    language: Optional[str] = None
    stt_provider: Optional[str] = None
    stt_model: Optional[str] = None
    outcome: Optional[TranscriptionOutcome] = None


class TranscriptionErrorDetail(BaseModel):
    error: str
    outcome: TranscriptionOutcome
    provider: str
    retryable: bool
    message: str


class TranscriptionErrorResponse(BaseModel):
    detail: TranscriptionErrorDetail


def _transcription_http_error(failure: TranscriptionFailure) -> HTTPException:
    logger.warning(
        'Transcription request failed: outcome=%s provider=%s retryable=%s',
        failure.outcome.value,
        failure.provider,
        failure.retryable,
    )
    return HTTPException(status_code=failure.status_code, detail=failure.as_detail())


def _cleanup_temp_voice_wavs(paths: List[str], uid: str) -> None:
    for path in paths:
        if path.startswith(f'/tmp/{uid}_'):
            try:
                Path(path).unlink()
            except OSError:
                pass


def _parse_context_keywords(raw: Optional[str]) -> List[str]:
    if not raw:
        return []

    keywords = []
    seen = set()
    for item in raw.split(','):
        keyword = item.strip()
        if len(keyword) < 2 or len(keyword) > 80:
            continue
        key = keyword.lower()
        if key in seen:
            continue
        seen.add(key)
        keywords.append(keyword)
        if len(keywords) >= 100:
            break
    return keywords


@router.post(
    "/v2/voice-messages",
    response_class=StreamingResponse,
    responses={
        200: {
            "description": "Server-sent stream containing the transient voice-message transcript.",
            "content": {"text/event-stream": {"schema": {"type": "string"}}},
        }
    },
)
@max_part_size(VOICE_MESSAGE_MAX_PART_SIZE)
def create_voice_message_stream(
    files: List[UploadFile] = File(...),
    language: Optional[str] = Form(None),
    uid: str = Depends(auth.with_rate_limit(auth.get_current_user_uid, "voice:message")),
    x_app_platform: Optional[str] = Header(None, alias='X-App-Platform'),
):
    """Transcribe a legacy voice-message upload without hosted Chat persistence or persona inference."""
    resolved_language = resolve_voice_message_language(uid, language)
    stt_provider, _, _stt_model = get_prerecorded_service(resolved_language)
    paths: List[str] = []
    wav_paths: List[str] = []

    def record_preparation_failure(failure: TranscriptionFailure) -> None:
        attempt = TranscriptionAttempt(
            route='voice_chat_sse',
            provider=stt_provider,
            platform=x_app_platform,
        )
        attempt.finish(failure.outcome)

    try:
        paths = retrieve_file_paths(files, uid)
        if not paths:
            raise TranscriptionFailure(
                TranscriptionOutcome.INVALID_INPUT,
                provider=stt_provider,
                retryable=False,
            )
        wav_paths = decode_files_to_wav(paths)
        if not wav_paths:
            raise TranscriptionFailure(
                TranscriptionOutcome.INVALID_INPUT,
                provider=stt_provider,
                retryable=False,
            )
        first_wav = wav_paths[0]
        duration_ms = read_wav_duration_ms(first_wav)
        if duration_ms is not None:
            allowed, _used_ms, _remaining_ms = try_consume_budget(uid, duration_ms)
            if not allowed:
                raise HTTPException(status_code=429, detail='Daily transcription budget exhausted')
    except TranscriptionFailure as failure:
        record_preparation_failure(failure)
        _cleanup_temp_voice_wavs(paths + wav_paths, uid)
        raise _transcription_http_error(failure) from failure
    except HTTPException:
        _cleanup_temp_voice_wavs(paths + wav_paths, uid)
        raise
    except Exception as error:
        failure = failure_from_exception(error, provider=stt_provider)
        record_preparation_failure(failure)
        _cleanup_temp_voice_wavs(paths + wav_paths, uid)
        raise _transcription_http_error(failure) from error

    async def generate_stream():
        attempt = TranscriptionAttempt(
            route='voice_chat_sse',
            provider=stt_provider,
            platform=x_app_platform,
        )
        try:
            text, _detected_language = await run_blocking(
                sync_executor,
                transcribe_voice_message_segment,
                first_wav,
                uid,
                language=resolved_language,
            )
            if text:
                # Preserve the legacy `message:` SSE frame shape for retained
                # callers, but do not write the transient transcript to hosted
                # Chat or invoke the deleted persona/RAG answer path.
                message = Message(
                    id=str(uuid.uuid4()),
                    text=text,
                    created_at=datetime.now(timezone.utc),
                    sender='human',
                    type='text',
                )
                encoded = base64.b64encode(message.model_dump_json().encode('utf-8')).decode('utf-8')
                attempt.finish(TranscriptionOutcome.SUCCESS)
                yield f"message: {encoded}\n\n"
            else:
                attempt.finish(TranscriptionOutcome.EXPECTED_SILENCE)
        except Exception as error:
            if attempt.finished:
                raise
            failure = failure_from_exception(error, provider=stt_provider)
            attempt.finish(failure.outcome)
            yield f"error: {json.dumps(failure.as_detail(), separators=(',', ':'))}\n\n"
        finally:
            if not attempt.finished:
                attempt.finish(TranscriptionOutcome.UPSTREAM_ERROR)
            await run_blocking(storage_executor, _cleanup_temp_voice_wavs, paths + wav_paths, uid)
            paths.clear()
            wav_paths.clear()

    return StreamingResponse(generate_stream(), media_type="text/event-stream")


@router.post(
    "/v2/voice-message/transcribe",
    response_model=VoiceMessageTranscriptionResponse,
    responses={
        400: {"model": TranscriptionErrorResponse, "description": "Invalid audio input"},
        502: {"model": TranscriptionErrorResponse, "description": "Upstream or unexpected-empty result"},
        503: {"model": TranscriptionErrorResponse, "description": "Provider configuration unavailable"},
        504: {"model": TranscriptionErrorResponse, "description": "Provider timeout"},
    },
)
async def transcribe_voice_message(
    request: Request,
    uid: str = Depends(auth.with_rate_limit(auth.get_current_user_uid, "voice:transcribe")),
    x_app_platform: Optional[str] = Header(None, alias='X-App-Platform'),
):
    """Transcribe audio and return the transcript text.

    Accepts two content types:
    - multipart/form-data: file upload with optional 'language' form field (mobile)
    - application/octet-stream: raw PCM bytes with query params (desktop PTT)

    Returns {"transcript": "...", "language": "..."}.
    """
    # Trial paywall: reject paywalled desktop PTT before opening managed STT.
    # Narrow to trial-only on purpose — full enforce_chat_quota here would
    # change mobile behavior for users past their existing 30/mo chat cap.
    if await run_blocking(db_executor, is_trial_paywalled, uid, x_app_platform):
        raise HTTPException(status_code=402, detail={'error': 'quota_exceeded', 'plan_type': 'basic'})

    content_type = request.headers.get("content-type", "")

    if "application/octet-stream" in content_type:
        # Check Content-Length before buffering to reject oversized payloads early
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                parsed_content_length = int(content_length)
            except ValueError as error:
                failure = TranscriptionFailure(
                    TranscriptionOutcome.INVALID_INPUT,
                    provider=None,
                    retryable=False,
                )
                raise _transcription_http_error(failure) from error
            if parsed_content_length > _MAX_PCM_BODY_BYTES:
                raise HTTPException(status_code=413, detail=f'Body too large (max {_MAX_PCM_BODY_BYTES} bytes)')

        audio_bytes = await request.body()
        if not audio_bytes or len(audio_bytes) == 0:
            raise HTTPException(status_code=400, detail='No audio data provided')

        if len(audio_bytes) > _MAX_PCM_BODY_BYTES:
            del audio_bytes
            raise HTTPException(status_code=413, detail=f'Body too large (max {_MAX_PCM_BODY_BYTES} bytes)')

        language = request.query_params.get("language")
        resolved_language = await run_blocking(db_executor, resolve_voice_message_language, uid, language)
        stt_provider, _, stt_model = get_prerecorded_service(resolved_language)
        context_keywords = _parse_context_keywords(request.query_params.get("keywords"))
        encoding = request.query_params.get("encoding", "linear16")
        try:
            sample_rate = int(request.query_params.get("sample_rate", "16000"))
            channels = int(request.query_params.get("channels", "1"))
        except ValueError:
            del audio_bytes
            raise _transcription_http_error(
                TranscriptionFailure(
                    TranscriptionOutcome.INVALID_INPUT,
                    provider=stt_provider,
                    retryable=False,
                )
            )

        if sample_rate < 8000 or sample_rate > 48000:
            del audio_bytes
            raise _transcription_http_error(
                TranscriptionFailure(
                    TranscriptionOutcome.INVALID_INPUT,
                    provider=stt_provider,
                    retryable=False,
                )
            )
        if channels < 1 or channels > 2:
            del audio_bytes
            raise _transcription_http_error(
                TranscriptionFailure(
                    TranscriptionOutcome.INVALID_INPUT,
                    provider=stt_provider,
                    retryable=False,
                )
            )

        parity_capture = SurfaceParityCapture.from_environ(
            principal_id=uid,
            session_id=str(uuid.uuid4()),
            surface="ptt",
            source="desktop_ptt_http",
            provider_lane="stt",
            route_or_model=stt_model or stt_provider or "prerecorded",
            request={
                "encoding": encoding,
                "sample_rate": sample_rate,
                "channels": channels,
                "language": resolved_language,
                "keyword_count": len(context_keywords),
            },
        )
        parity_capture.observe_audio("client", audio_bytes)

        # Daily budget check
        duration_ms = compute_pcm_duration_ms(len(audio_bytes), sample_rate, channels)
        allowed, used_ms, remaining_ms = try_consume_budget(uid, duration_ms)
        if not allowed:
            del audio_bytes
            raise HTTPException(status_code=429, detail='Daily transcription budget exhausted')

        attempt = TranscriptionAttempt(
            route='voice_rest_pcm',
            provider=stt_provider,
            platform=x_app_platform,
        )
        try:
            transcript, detected_language = await run_blocking(
                sync_executor,
                transcribe_pcm_bytes,
                audio_bytes,
                uid,
                language=resolved_language,
                encoding=encoding,
                sample_rate=sample_rate,
                channels=channels,
                keywords=context_keywords,
            )
            outcome = TranscriptionOutcome.SUCCESS if transcript else TranscriptionOutcome.EXPECTED_SILENCE
            parity_capture.observe(
                "inbound",
                {
                    "type": "transcript",
                    "text": transcript or "",
                    "detected_language": detected_language,
                    "outcome": outcome.value,
                },
            )
            attempt.finish(outcome)
        except Exception as error:
            failure = failure_from_exception(error, provider=stt_provider)
            attempt.finish(failure.outcome)
            raise _transcription_http_error(failure) from error
        finally:
            if not attempt.finished:
                attempt.finish(TranscriptionOutcome.UPSTREAM_ERROR)
            parity_capture.persist()
            del audio_bytes

        response = {
            "transcript": transcript or "",
            "stt_provider": stt_provider,
            "stt_model": stt_model,
            "outcome": outcome.value,
        }
        if detected_language:
            response["language"] = detected_language
        return response

    # Multipart file upload mode (original behavior)
    form = await parse_multipart_form(request, max_part_size=VOICE_MESSAGE_MAX_PART_SIZE)
    files = form.getlist("files")
    language = form.get("language")
    upload_files = [f for f in files if hasattr(f, 'file')]
    if not upload_files:
        raise HTTPException(status_code=400, detail='No files provided')
    if any(not file.filename for file in upload_files):
        raise HTTPException(status_code=400, detail='Each uploaded file must have a filename')

    wav_paths = []
    other_file_paths = []
    resolved_language = await run_blocking(db_executor, resolve_voice_message_language, uid, language)
    stt_provider, _, stt_model = get_prerecorded_service(resolved_language)
    transcripts = []
    detected_languages = []
    attempt: TranscriptionAttempt | None = None

    def _record_multipart_preparation_failure(failure: TranscriptionFailure) -> None:
        """Emit a typed terminal result for rejected multipart audio."""
        preparation_attempt = TranscriptionAttempt(
            route='voice_rest_multipart',
            provider=stt_provider,
            platform=x_app_platform,
        )
        preparation_attempt.finish(failure.outcome)

    # Process all files in a single loop
    def _save_wav(path, file_obj):
        with open(path, "wb") as buffer:
            shutil.copyfileobj(file_obj, buffer)

    try:
        # Preprocessing belongs inside the same customer-visible failure
        # boundary as provider work. In particular, decode_files_to_wav can
        # reject corrupt input with HTTPException before a provider call.
        for file in upload_files:
            filename = file.filename
            assert filename is not None
            if (suffix := Path(filename).suffix.lower()) in ('.wav', '.webm', '.mp4'):
                temp_path = f"/tmp/{uid}_{uuid.uuid4()}{suffix}"
                await run_blocking(storage_executor, _save_wav, temp_path, file.file)
                wav_paths.append(temp_path)
            else:
                path = await run_blocking(storage_executor, retrieve_file_paths, [file], uid)
                if path:
                    other_file_paths.extend(path)

        if other_file_paths:
            converted_wav_paths = await run_blocking(storage_executor, decode_files_to_wav, other_file_paths)
            if converted_wav_paths:
                wav_paths.extend(converted_wav_paths)

        if not wav_paths:
            raise TranscriptionFailure(
                TranscriptionOutcome.INVALID_INPUT,
                provider=stt_provider,
                retryable=False,
            )

        # Daily budget check (sum all files). This is not a provider outcome,
        # so do it before recording an accepted transcription attempt.
        total_duration_ms = 0
        for wav_path in wav_paths:
            duration_ms = await run_blocking(storage_executor, read_wav_duration_ms, wav_path)
            if duration_ms is not None:
                total_duration_ms += duration_ms
        if total_duration_ms > 0:
            allowed, used_ms, remaining_ms = try_consume_budget(uid, total_duration_ms)
            if not allowed:
                raise HTTPException(status_code=429, detail='Daily transcription budget exhausted')

        is_multi = resolved_language == 'multi'
        attempt = TranscriptionAttempt(
            route='voice_rest_multipart',
            provider=stt_provider,
            platform=x_app_platform,
        )
        for wav_path in wav_paths:
            transcript, detected_language = await run_blocking(
                sync_executor, transcribe_voice_message_segment, wav_path, uid, language=resolved_language
            )
            if transcript:
                transcripts.append(transcript)
            if is_multi and detected_language:
                detected_languages.append(detected_language)

        if is_multi:
            unique_languages = {lang for lang in detected_languages if lang}
            detected_language = None
            if len(unique_languages) == 1:
                detected_language = unique_languages.pop()
            elif len(unique_languages) > 1:
                detected_language = "multi"
        else:
            detected_language = None

        combined_transcript = " ".join(transcripts)
        outcome = TranscriptionOutcome.SUCCESS if combined_transcript else TranscriptionOutcome.EXPECTED_SILENCE
        attempt.finish(outcome)
        response = {
            "transcript": combined_transcript,
            "stt_provider": stt_provider,
            "stt_model": stt_model,
            "outcome": outcome.value,
        }
        if detected_language:
            response["language"] = detected_language
        return response
    except TranscriptionFailure as failure:
        if attempt is None:
            _record_multipart_preparation_failure(failure)
        else:
            attempt.finish(failure.outcome)
        raise _transcription_http_error(failure) from failure
    except HTTPException as error:
        if error.status_code == 429:
            raise
        failure = TranscriptionFailure(
            TranscriptionOutcome.INVALID_INPUT,
            provider=stt_provider,
            retryable=False,
        )
        if attempt is None:
            _record_multipart_preparation_failure(failure)
        else:
            attempt.finish(failure.outcome)
        raise _transcription_http_error(failure) from error
    except Exception as error:
        failure = failure_from_exception(error, provider=stt_provider)
        if attempt is None:
            _record_multipart_preparation_failure(failure)
        else:
            attempt.finish(failure.outcome)
        raise _transcription_http_error(failure) from error
    finally:
        if attempt is not None and not attempt.finished:
            attempt.finish(TranscriptionOutcome.UPSTREAM_ERROR)
        # retrieve_file_paths and conversion can both allocate uid-scoped
        # inputs. Clean every path even when preprocessing fails before the
        # previous provider-only try/finally boundary.
        await run_blocking(storage_executor, _cleanup_temp_voice_wavs, wav_paths + other_file_paths, uid)
        transcripts.clear()
        detected_languages.clear()
        wav_paths.clear()
        other_file_paths.clear()


@router.websocket("/v2/voice-message/transcribe-stream")
async def transcribe_voice_message_stream(
    websocket: WebSocket,
    uid: str = Depends(auth.get_current_user_uid_ws_listen),
    language: str = 'en',
    sample_rate: int = 16000,
    codec: str = 'linear16',
    channels: int = 1,
    keywords: Optional[str] = None,
    x_app_platform: Optional[str] = Header(None, alias='X-App-Platform'),
):
    """WebSocket endpoint for PTT live mode transcription-only streaming.

    Receives binary PCM audio chunks, streams them to managed STT, and returns
    transcript segments in real-time. No conversation lifecycle, no memory
    extraction, no pusher — just audio in, transcript out.

    Query params:
        language: Language code (default 'en')
        sample_rate: Audio sample rate in Hz (default 16000)
        codec: Audio codec, must be 'linear16' (default 'linear16')
        channels: Number of audio channels (default 1)
        keywords: Comma-separated context terms to boost recognition

    Client sends:
        - binary frames: audio data (PCM 16-bit)
        - text "finalize": flush remaining audio + trigger provider finalization
    Server sends: JSON arrays of transcript segments
        [{"speaker": "SPEAKER_00", "start": 0.0, "end": 1.5, "text": "Hello world",
          "is_user": false}]
    """
    await websocket.accept()

    # Paywalled desktop users — close before opening a provider connection for
    # a PTT stream that would not be allowed to chat anyway.
    if await run_blocking(db_executor, is_trial_paywalled, uid, x_app_platform):
        await websocket.close(code=1008, reason='trial_expired')
        return

    if codec != 'linear16':
        await websocket.close(code=1008, reason='Unsupported codec; only linear16 is supported')
        return

    if sample_rate < 8000 or sample_rate > 48000:
        await websocket.close(code=1008, reason='sample_rate must be between 8000 and 48000')
        return

    if channels < 1 or channels > 2:
        await websocket.close(code=1008, reason='channels must be 1 or 2')
        return

    # The managed adapter wires a mono PCM path: sending
    # interleaved stereo here would be billed as two channels while being
    # transcribed as mono, corrupting timing and quality. Reject channels > 1
    # explicitly instead of silently downmixing or double-billing.
    if channels != 1:
        await websocket.close(code=1008, reason='Only mono (channels=1) is supported by this transcription provider')
        return

    # Inline rate limiting for WebSocket (can't use Depends(with_rate_limit))
    try:
        max_requests, window = get_effective_limit('voice:transcribe_stream')
        allowed, remaining, retry_after = await run_blocking(
            critical_executor, check_rate_limit, uid, 'voice:transcribe_stream', max_requests, window
        )
        if not allowed:
            if not RATE_LIMIT_SHADOW:
                await websocket.close(code=1008, reason=f'Rate limit exceeded. Retry in {retry_after}s.')
                return
            logger.warning(f'[shadow] rate_limit_exceeded policy=voice:transcribe_stream uid={uid}')
    except Exception:
        pass  # Fail-open, consistent with Redis rate limiting elsewhere

    # Daily budget check — reject if already exhausted before opening a provider connection.
    budget_remaining_ms = None  # None = fail-open (no enforcement)
    try:
        has_budget, used_ms, remaining_ms = check_budget(uid)
        if not has_budget:
            await websocket.close(code=1008, reason='Daily transcription budget exhausted')
            return
        budget_remaining_ms = remaining_ms
    except Exception:
        pass  # Fail-open

    websocket_active = True
    stt_socket = None
    sender_task = None
    stt_audio_buffer = bytearray()
    received_audio_bytes = 0  # Includes buffered bytes for admission/budget enforcement.
    accepted_audio_bytes = 0  # Only bytes the provider explicitly accepted.
    # A terminal provider failure after either audio handoff or finalization.
    stt_send_failed = False
    stt_drained = False
    usage_recorded = False
    # 30ms flush threshold for the live-STT transport (16-bit PCM = 2 bytes per sample per channel).
    bytes_per_second = sample_rate * channels * 2
    stt_buffer_flush_size = int(bytes_per_second * 0.03)

    stt_language = get_managed_stt_language(language, surface=STTServingSurface.PTT)
    if stt_language is None:
        await websocket.close(code=1011, reason='Transcription service unavailable')
        return
    context_keywords = _parse_context_keywords(keywords)
    parity_capture = SurfaceParityCapture.from_environ(
        principal_id=uid,
        session_id=str(uuid.uuid4()),
        surface="ptt",
        source="desktop_ptt_stream",
        provider_lane="stt",
        route_or_model=MODULATE_MODEL,
        request={
            "codec": codec,
            "sample_rate": sample_rate,
            "channels": channels,
            "language": stt_language,
            "keyword_count": len(context_keywords),
        },
    )

    loop = asyncio.get_running_loop()

    # Provider callbacks can run off-loop — bridge to async via
    # loop.call_soon_threadsafe so asyncio.Queue wakeups are reliable.
    _SENTINEL = object()
    segment_queue = asyncio.Queue()

    def stream_transcript(segments):
        parity_capture.observe("inbound", {"type": "transcript", "segments": segments})
        loop.call_soon_threadsafe(segment_queue.put_nowait, segments)

    async def segment_sender():
        """Forward segments from the thread-safe queue to the WebSocket."""
        nonlocal websocket_active
        while websocket_active:
            try:
                segments = await asyncio.wait_for(segment_queue.get(), timeout=0.5)
                if segments is _SENTINEL:
                    break
                await websocket.send_json(segments)
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.warning(f'transcribe-stream: segment_sender error uid={uid}: {e}')
                websocket_active = False
                break

    async def close_stt_failure() -> None:
        """Expose an unusable live-STT session before the caller drops audio."""
        nonlocal websocket_active, stt_send_failed
        if stt_send_failed:
            return
        stt_send_failed = True
        websocket_active = False
        logger.error('event=ptt_transcription_stream outcome=provider_terminal_failure')
        try:
            await websocket.close(code=1011, reason='Transcription service unavailable')
        except Exception:
            pass

    async def send_stt_audio_or_close(audio: bytes) -> bool:
        """Require the provider to accept audio before its caller discards it."""
        if stt_send_failed:
            return False
        try:
            accepted = stt_socket is not None and not stt_socket.is_connection_dead and stt_socket.send(audio) is True
        except Exception:
            accepted = False
        if accepted:
            return True

        await close_stt_failure()
        return False

    def record_stt_usage_once() -> None:
        """Record accepted provider audio only after a terminal provider drain."""
        nonlocal usage_recorded
        if usage_recorded or accepted_audio_bytes <= 0 or bytes_per_second <= 0:
            return
        actual_duration_ms = compute_pcm_duration_ms(accepted_audio_bytes, sample_rate, channels)
        record_actual_duration(uid, actual_duration_ms)
        usage_recorded = True

    async def drain_stt_or_close() -> bool:
        """Finalize and await the selected provider's tail before sender teardown."""
        nonlocal stt_drained
        if stt_send_failed:
            return False
        if stt_drained:
            return True
        try:
            if stt_socket is None:
                raise RuntimeError('missing STT socket')
            stt_socket.finalize()
            await drain_stt_socket(stt_socket)
        except Exception:
            await close_stt_failure()
            return False
        stt_drained = True
        return True

    try:
        stt_socket = await process_audio_modulate(stream_transcript, sample_rate, stt_language)

        if stt_socket is None:
            logger.error(
                'transcribe-stream: failed to connect to managed STT uid=%s provider=%s', uid, MODULATE_PROVIDER
            )
            await websocket.close(code=1011, reason='Transcription service unavailable')
            return

        # Start segment sender task
        sender_task = asyncio.create_task(segment_sender())

        # Audio receive loop with audio-idle timeout.
        # Timeout is based on last *audio* frame, not last message — text-only
        # frames (e.g. "finalize") don't reset the idle clock.
        last_audio_time = asyncio.get_event_loop().time()
        while websocket_active:
            # Compute remaining idle budget based on last audio receipt
            now = asyncio.get_event_loop().time()
            remaining_idle = _WS_IDLE_TIMEOUT_S - (now - last_audio_time)
            if remaining_idle <= 0:
                logger.info(f'transcribe-stream: audio-idle timeout ({_WS_IDLE_TIMEOUT_S}s) uid={uid}')
                await websocket.close(code=1008, reason=f'Idle timeout: no audio for {_WS_IDLE_TIMEOUT_S}s')
                break

            try:
                message = await asyncio.wait_for(websocket.receive(), timeout=remaining_idle)
            except asyncio.TimeoutError:
                logger.info(f'transcribe-stream: audio-idle timeout ({_WS_IDLE_TIMEOUT_S}s) uid={uid}')
                await websocket.close(code=1008, reason=f'Idle timeout: no audio for {_WS_IDLE_TIMEOUT_S}s')
                break
            except WebSocketDisconnect:
                break

            if message.get("type") == "websocket.disconnect":
                break

            # Handle text "finalize" message: flush remaining audio and await the provider's
            # final transcript. Finalization is terminal; clients close once they have received it.
            # Note: text frames do NOT reset the audio-idle timer.
            text_data = message.get("text")
            if text_data and text_data.strip() == "finalize":
                if stt_socket and not stt_send_failed:
                    if len(stt_audio_buffer) > 0:
                        if not await send_stt_audio_or_close(bytes(stt_audio_buffer)):
                            break
                        accepted_audio_bytes += len(stt_audio_buffer)
                        stt_audio_buffer.clear()
                    if await drain_stt_or_close():
                        record_stt_usage_once()
                    else:
                        break
                continue

            data = message.get("bytes")
            if data is None:
                continue

            if stt_drained:
                await websocket.close(code=1008, reason='Transcription already finalized')
                break

            last_audio_time = asyncio.get_event_loop().time()

            # Guard against oversized frames (5 MB matches REST endpoint limit)
            if len(data) > 5 * 1024 * 1024:
                logger.warning(f'transcribe-stream: oversized frame uid={uid} size={len(data)}')
                continue

            # In-session budget enforcement: check BEFORE incrementing received_audio_bytes
            # so that the triggering frame is not counted as consumed (it won't be sent upstream).
            if budget_remaining_ms is not None and bytes_per_second > 0:
                prospective_ms = compute_pcm_duration_ms(received_audio_bytes + len(data), sample_rate, channels)
                if prospective_ms > budget_remaining_ms:
                    logger.info(
                        f'transcribe-stream: budget exhausted mid-session uid={uid} elapsed={prospective_ms}ms remaining={budget_remaining_ms}ms'
                    )
                    await websocket.close(code=1008, reason='Daily transcription budget exhausted')
                    break

            received_audio_bytes += len(data)
            parity_capture.observe_audio("client", data)
            stt_audio_buffer.extend(data)

            # Flush to the selected provider in 30ms chunks.
            while len(stt_audio_buffer) >= stt_buffer_flush_size:
                chunk = bytes(stt_audio_buffer[:stt_buffer_flush_size])
                if not await send_stt_audio_or_close(chunk):
                    break
                del stt_audio_buffer[:stt_buffer_flush_size]
                accepted_audio_bytes += len(chunk)

    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.error(f'transcribe-stream: error uid={uid}: {e}')
        await close_stt_failure()
    finally:
        websocket_active = False

        # Flush remaining audio buffer
        if stt_socket and not stt_send_failed and not stt_drained and len(stt_audio_buffer) > 0:
            if await send_stt_audio_or_close(bytes(stt_audio_buffer)):
                accepted_audio_bytes += len(stt_audio_buffer)
                stt_audio_buffer.clear()

        # Await a healthy provider's final tail before stopping the segment sender.
        # A rejected send still gets a best-effort close but no final transcript or usage charge.
        if stt_socket and not stt_send_failed and await drain_stt_or_close():
            record_stt_usage_once()

        if stt_socket and not stt_drained:
            try:
                await drain_stt_socket(stt_socket)
            except Exception:
                try:
                    stt_socket.finish()
                except Exception:
                    pass

        # Signal sender task to drain and stop, then wait for it
        loop.call_soon_threadsafe(segment_queue.put_nowait, _SENTINEL)
        if sender_task is not None:
            try:
                await asyncio.wait_for(sender_task, timeout=2.0)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                sender_task.cancel()
                try:
                    await sender_task
                except asyncio.CancelledError:
                    pass

        del stt_audio_buffer
        parity_capture.persist()


@router.post('/v1/files', response_model=List[FileChat], tags=['chat'])
@max_part_size(CHAT_FILE_MAX_PART_SIZE)
def upload_file_chat(
    files: List[UploadFile] = File(...),
    uid: str = Depends(auth.with_rate_limit(auth.get_current_user_uid, "file:upload")),
):
    thumbs_name = []
    files_chat = []
    for file in files:
        # Use a UUID-based temp file name to prevent path traversal via user-controlled filename
        safe_suffix = Path(file.filename).name if file.filename else "upload"
        temp_file = Path(tempfile.gettempdir()) / f"{uuid.uuid4().hex}_{safe_suffix}"
        try:
            with temp_file.open("wb") as buffer:
                shutil.copyfileobj(file.file, buffer)

            result = FileChatTool.upload(temp_file)

            thumb_name = result.get("thumbnail_name", "")
            if thumb_name != "":
                thumbs_name.append(thumb_name)

            filechat = FileChat(
                id=str(uuid.uuid4()),
                name=result.get("file_name", ""),
                mime_type=result.get("mime_type", ""),
                openai_file_id=result.get("file_id", ""),
                created_at=datetime.now(timezone.utc),
                thumb_name=thumb_name,
            )
            files_chat.append(filechat)
        finally:
            if temp_file.exists():
                temp_file.unlink()

    if len(thumbs_name) > 0:
        thumbs_path = storage.upload_multi_chat_files(thumbs_name, uid)
        for fc in files_chat:
            if not fc.is_image():
                continue
            thumb_path = thumbs_path.get(fc.thumb_name, "")
            fc.thumbnail = thumb_path
            # cleanup file thumb
            thumb_file = Path(fc.thumb_name)
            thumb_file.unlink()

    # save db
    files_chat_dict = [fc.model_dump() for fc in files_chat]

    chat_db.add_multi_files(uid, files_chat_dict)

    response = [fc.model_dump() for fc in files_chat]

    return response
