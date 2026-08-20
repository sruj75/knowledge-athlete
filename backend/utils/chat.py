from typing import List, Optional, Tuple

import database.users as user_db
from config.stt_provider_policy import supports_live_multilingual_mode
from models.transcript_segment import TranscriptSegment
from utils.other.storage import get_syncing_file_temporal_signed_url, schedule_syncing_temporal_file_deletion
from utils.stt.pre_recorded import (
    postprocess_words,
    prerecorded,
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


def _prepare_voice_message_url(path: str) -> str:
    """Create the signed input URL and schedule its cleanup on the storage lane."""
    url = get_syncing_file_temporal_signed_url(path)
    schedule_syncing_temporal_file_deletion(path)
    return url


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


def _transcribe_voice_message_url(
    url: str,
    path: str,
    language: str,
    detect_language: bool = True,
) -> Tuple[Optional[str], Optional[str]]:
    """Run the synchronous prerecorded-STT pipeline for one signed URL."""
    provider, stt_language, _ = get_prerecorded_service(language)
    is_multi = stt_language == 'multi'
    try:
        if is_multi and detect_language:
            words, detected_language = prerecorded(url, diarize=False, language=stt_language, return_language=True)
        else:
            words = prerecorded(url, diarize=False, language=stt_language, return_language=False)
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


def transcribe_voice_message_segment(
    path: str,
    uid: str,
    language: str = 'multi',
) -> Tuple[Optional[str], Optional[str]]:
    if not language:
        language = resolve_voice_message_language(uid, None)
    provider, provider_language, _ = get_prerecorded_service(language)
    # Schedule deletion before the VAD gate as well: silence is a valid
    # terminal outcome, not a reason to retain temporary customer audio.
    url = _prepare_voice_message_url(path)
    if _validated_wav_is_silent(path, provider=provider):
        detected_language = provider_language if provider_language != 'multi' else None
        return None, detected_language

    return _transcribe_voice_message_url(url, path, language)


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
