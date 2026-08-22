from typing import List, Optional, Tuple
from pathlib import Path

import database.users as user_db
from config.stt_provider_policy import supports_live_multilingual_mode
from models.transcript_segment import TranscriptSegment
from utils.stt.pre_recorded import (
    postprocess_words,
    prerecorded_from_bytes,
    get_prerecorded_service,
)
from utils.stt.outcomes import (
    TranscriptionFailure,
    TranscriptionOutcome,
    empty_unexpected_failure,
    failure_from_exception,
)
from utils.stt.vad import VADAudioDecodeError, VADProcessingError, linear16_pcm_is_silent, vad_is_empty_strict
import logging

logger = logging.getLogger(__name__)


def resolve_voice_message_language(uid: str, request_language: Optional[str]) -> str:
    """
    Determine language selection for voice message transcription.

    Returns a single language string: either a specific language code (e.g., 'en', 'es')
    or 'multi' for auto-detection mode.
    """
    if request_language:
        normalized = request_language.strip()
        if normalized:
            request_lower = normalized.lower()
            if request_lower == 'auto' or request_lower == 'multi':
                return 'multi'
            return normalized

    user_language = user_db.get_user_language_preference(uid)
    if user_language:
        return 'multi' if supports_live_multilingual_mode(user_language) else user_language

    return 'multi'


_MAX_VOICE_MESSAGE_BYTES = 200 * 1024 * 1024


def _validated_wav_is_silent(path: str, *, provider: str) -> bool:
    """Return strict VAD silence without converting decode failures to silence."""

    try:
        return vad_is_empty_strict(path)
    except VADAudioDecodeError as error:
        raise TranscriptionFailure(
            TranscriptionOutcome.INVALID_INPUT,
            provider=provider,
            retryable=False,
        ) from error
    except Exception as error:
        raise TranscriptionFailure(TranscriptionOutcome.UPSTREAM_ERROR, provider=provider) from error


def _prerecorded_voice_message_from_bytes(
    audio_bytes: bytes,
    *,
    stt_language: str,
    return_language: bool,
):
    """Preserve the five-attempt budget of the retired signed-URL adapter."""
    kwargs = {
        'diarize': False,
        'language': stt_language,
        'return_language': return_language,
    }
    try:
        return prerecorded_from_bytes(audio_bytes, **kwargs)
    except RuntimeError:
        # The byte adapter has exhausted attempts 1-3. The old URL adapter then
        # resumed it at attempt index 1, providing two final provider attempts.
        return prerecorded_from_bytes(audio_bytes, **kwargs, attempts=1)


def transcribe_voice_message_bytes(
    audio_bytes: bytes,
    language: str,
    detect_language: bool = True,
) -> Tuple[Optional[str], Optional[str]]:
    """Run the synchronous prerecorded-STT pipeline on request-local WAV bytes."""
    provider, stt_language, _ = get_prerecorded_service(language)
    is_multi = stt_language == 'multi'
    try:
        if is_multi and detect_language:
            words, detected_language = _prerecorded_voice_message_from_bytes(
                audio_bytes,
                stt_language=stt_language,
                return_language=True,
            )
        else:
            words = _prerecorded_voice_message_from_bytes(
                audio_bytes,
                stt_language=stt_language,
                return_language=False,
            )
            detected_language = stt_language
    except Exception as error:
        failure = failure_from_exception(error, provider=provider)
        logger.warning(
            'Voice message transcription failed: outcome=%s provider=%s retryable=%s',
            failure.outcome.value,
            failure.provider,
            failure.retryable,
        )
        raise failure from error

    if not words:
        raise empty_unexpected_failure(provider)
    try:
        transcript_segments: List[TranscriptSegment] = postprocess_words(words, 0)
    except Exception as error:
        raise TranscriptionFailure(TranscriptionOutcome.UPSTREAM_ERROR, provider=provider) from error
    del words
    if not transcript_segments:
        raise empty_unexpected_failure(provider)

    text = " ".join([segment.text for segment in transcript_segments]).strip()
    transcript_segments.clear()
    if len(text) == 0:
        raise empty_unexpected_failure(provider)

    return text, detected_language


def load_voice_message_segment_bytes(
    path: str,
    uid: str,
    language: str = 'multi',
) -> Tuple[Optional[bytes], str, Optional[str]]:
    """Validate and load one request-local WAV on the storage lane.

    The third tuple item carries the detected-language response for the silence
    outcome, where no provider call is needed.
    """
    if not language:
        language = resolve_voice_message_language(uid, None)
    provider, provider_language, _ = get_prerecorded_service(language)
    if _validated_wav_is_silent(path, provider=provider):
        detected_language = provider_language if provider_language != 'multi' else None
        return None, language, detected_language

    audio_path = Path(path)
    if audio_path.stat().st_size > _MAX_VOICE_MESSAGE_BYTES:
        raise TranscriptionFailure(
            TranscriptionOutcome.INVALID_INPUT,
            provider=provider,
            retryable=False,
        )
    return audio_path.read_bytes(), language, None


def transcribe_pcm_bytes(
    audio_bytes: bytes,
    uid: str,
    language: str = 'multi',
    encoding: str = 'linear16',
    sample_rate: int = 16000,
    channels: int = 1,
    keywords: Optional[List[str]] = None,
) -> Tuple[Optional[str], Optional[str]]:
    """Transcribe raw PCM audio bytes through managed pre-recorded STT.

    Skips GCS upload and WAV conversion for maximum speed.
    Used by desktop PTT batch mode.
    """
    if not language:
        language = resolve_voice_message_language(uid, None)

    provider, stt_language, _ = get_prerecorded_service(language)
    is_multi = stt_language == 'multi'

    if encoding == 'linear16':
        try:
            if linear16_pcm_is_silent(audio_bytes, sample_rate=sample_rate, channels=channels):
                return None, stt_language if not is_multi else None
        except VADAudioDecodeError as error:
            raise TranscriptionFailure(
                TranscriptionOutcome.INVALID_INPUT,
                provider=provider,
                retryable=False,
            ) from error
        except VADProcessingError as error:
            raise TranscriptionFailure(TranscriptionOutcome.UPSTREAM_ERROR, provider=provider) from error

    try:
        if is_multi:
            result = prerecorded_from_bytes(
                audio_bytes,
                sample_rate=sample_rate,
                diarize=False,
                encoding=encoding,
                channels=channels,
                language=stt_language,
                return_language=True,
                keywords=keywords,
            )
            words, detected_language = result
        else:
            words = prerecorded_from_bytes(
                audio_bytes,
                sample_rate=sample_rate,
                diarize=False,
                encoding=encoding,
                channels=channels,
                language=stt_language,
                keywords=keywords,
            )
            detected_language = stt_language
    except Exception as error:
        raise failure_from_exception(error, provider=provider) from error

    if not words:
        raise empty_unexpected_failure(provider)

    try:
        transcript_segments: List[TranscriptSegment] = postprocess_words(words, 0)
    except Exception as error:
        raise TranscriptionFailure(TranscriptionOutcome.UPSTREAM_ERROR, provider=provider) from error
    del words
    if not transcript_segments:
        raise empty_unexpected_failure(provider)

    text = " ".join([segment.text for segment in transcript_segments]).strip()
    transcript_segments.clear()
    if len(text) == 0:
        raise empty_unexpected_failure(provider)

    return text, detected_language
