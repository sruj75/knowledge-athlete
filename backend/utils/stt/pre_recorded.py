"""Managed pre-recorded speech-to-text through the fixed Modulate adapter."""

from __future__ import annotations

import logging
import os
import wave as _wave
from abc import ABC, abstractmethod
from collections import defaultdict
from io import BytesIO
from typing import Any, Dict, List, Optional, Sequence, Tuple, Union

import httpx

from config.prerecorded_stt import (
    PrerecordedSTTConfigurationError as _PrerecordedSTTConfigurationError,
    require_managed_stt_environment,
)
from config.stt_provider_policy import MODULATE_MODEL, MODULATE_PROVIDER, normalized_stt_language
from models.transcript_segment import TranscriptSegment
from utils.other.endpoints import timeit

_MODULATE_TIMEOUT = httpx.Timeout(connect=10.0, read=300.0, write=30.0, pool=10.0)

logger = logging.getLogger(__name__)

# Public export used by router failure mapping.
PrerecordedSTTConfigurationError = _PrerecordedSTTConfigurationError


class PrerecordedSTTProvider(ABC):
    @abstractmethod
    def transcribe_url(
        self,
        audio_url: str,
        speakers_count: Optional[int] = None,
        attempts: int = 0,
        return_language: bool = False,
        diarize: bool = True,
        language: Optional[str] = None,
        keywords: Optional[Sequence[str]] = None,
    ) -> Union[List[Dict[str, Any]], Tuple[List[Dict[str, Any]], str]]: ...

    @abstractmethod
    def transcribe_bytes(
        self,
        audio_bytes: bytes,
        sample_rate: int = 16000,
        diarize: bool = True,
        attempts: int = 0,
        encoding: Optional[str] = None,
        channels: int = 1,
        language: Optional[str] = None,
        return_language: bool = False,
        keywords: Optional[Sequence[str]] = None,
    ) -> Union[List[Dict[str, Any]], Tuple[List[Dict[str, Any]], str]]: ...


def get_prerecorded_service(language: Optional[str] = 'en') -> Tuple[str, Optional[str], str]:
    """Return the fixed managed adapter and its normalized language request."""
    base_lang = normalized_stt_language(language) or 'en'
    return MODULATE_PROVIDER, base_lang, MODULATE_MODEL


def _wrap_pcm_as_wav(pcm_bytes: bytes, sample_rate: int, channels: int, bits_per_sample: int = 16) -> bytes:
    buf = BytesIO()
    with _wave.open(buf, 'wb') as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(bits_per_sample // 8)
        wf.setframerate(sample_rate)
        wf.writeframes(pcm_bytes)
    return buf.getvalue()


@timeit
def modulate_prerecorded_from_bytes(
    audio_bytes: bytes,
    sample_rate: int = 16000,
    diarize: bool = True,
    attempts: int = 0,
    return_language: bool = False,
) -> Union[List[Dict[str, Any]], Tuple[List[Dict[str, Any]], str]]:
    logger.info(f'modulate_prerecorded_from_bytes bytes_len={len(audio_bytes)} {sample_rate} {diarize} {attempts}')

    require_managed_stt_environment()
    api_key = os.environ['MODULATE_API_KEY']

    try:
        url = 'https://modulate-developer-apis.com/api/velma-2-stt-batch'
        headers = {'X-API-Key': api_key}
        files = {'upload_file': ('audio.wav', BytesIO(audio_bytes), 'audio/wav')}
        data = {'speaker_diarization': str(diarize).lower()}

        with httpx.Client(timeout=300) as client:
            response = client.post(url, headers=headers, files=files, data=data)
        response.raise_for_status()
        result = response.json()

        utterances = result.get('utterances', [])
        if not utterances:
            if return_language:
                return [], 'en'
            return []

        words: List[Dict[str, Any]] = []
        detected_language = 'en'
        for utt in utterances:
            text = utt.get('text', '').strip()
            if not text:
                continue

            start_ms = utt.get('start_ms', 0)
            duration_ms = utt.get('duration_ms', 0)
            start = start_ms / 1000.0
            end = (start_ms + duration_ms) / 1000.0

            raw_speaker = utt.get('speaker')
            if isinstance(raw_speaker, int) and raw_speaker >= 1:
                speaker_idx = raw_speaker - 1
            else:
                speaker_idx = 0
            speaker = f'SPEAKER_{speaker_idx:02d}'

            words.append({'timestamp': [start, end], 'speaker': speaker, 'text': text})

            lang = utt.get('language')
            if lang:
                detected_language = lang

        if return_language:
            return words, detected_language

        return words

    except Exception as e:
        logger.error('Modulate prerecorded error exception_type=%s attempt=%s', type(e).__name__, attempts + 1)
        if attempts < 2:
            return modulate_prerecorded_from_bytes(audio_bytes, sample_rate, diarize, attempts + 1, return_language)
        raise RuntimeError(f'Modulate transcription failed after {attempts + 1} attempts') from e


@timeit
def modulate_prerecorded(
    audio_url: str,
    speakers_count: Optional[int] = None,
    attempts: int = 0,
    return_language: bool = False,
    diarize: bool = True,
    language: Optional[str] = None,
) -> Union[List[Dict[str, Any]], Tuple[List[Dict[str, Any]], str]]:
    logger.info(
        'modulate_prerecorded url_len=%s speakers_count=%s attempt=%s', len(audio_url), speakers_count, attempts
    )
    try:
        with httpx.Client(timeout=_MODULATE_TIMEOUT) as client:
            resp = client.get(audio_url)
            resp.raise_for_status()
            audio_bytes = resp.content
        return modulate_prerecorded_from_bytes(
            audio_bytes, diarize=diarize, attempts=attempts, return_language=return_language
        )
    except Exception as e:
        logger.error(
            'Modulate prerecorded (url) error exception_type=%s attempt=%s',
            type(e).__name__,
            attempts + 1,
        )
        if attempts < 1:
            return modulate_prerecorded(audio_url, speakers_count, attempts + 1, return_language, diarize, language)
        raise RuntimeError(f'Modulate transcription (url) failed after {attempts + 1} attempts') from e


# ---------------------------------------------------------------------------


class ModulatePrerecordedProvider(PrerecordedSTTProvider):
    def _normalize_lang(self, language: Optional[str]) -> str:
        if not language:
            return 'en'
        return language.split('-')[0].split('_')[0].lower()

    def transcribe_url(
        self,
        audio_url: str,
        speakers_count: Optional[int] = None,
        attempts: int = 0,
        return_language: bool = False,
        diarize: bool = True,
        language: Optional[str] = None,
        keywords: Optional[Sequence[str]] = None,
    ) -> Union[List[Dict[str, Any]], Tuple[List[Dict[str, Any]], str]]:
        return modulate_prerecorded(
            audio_url,
            speakers_count=speakers_count,
            attempts=attempts,
            return_language=return_language,
            diarize=diarize,
            language=self._normalize_lang(language),
        )

    def transcribe_bytes(
        self,
        audio_bytes: bytes,
        sample_rate: int = 16000,
        diarize: bool = True,
        attempts: int = 0,
        encoding: Optional[str] = None,
        channels: int = 1,
        language: Optional[str] = None,
        return_language: bool = False,
        keywords: Optional[Sequence[str]] = None,
    ) -> Union[List[Dict[str, Any]], Tuple[List[Dict[str, Any]], str]]:
        if encoding:
            audio_bytes = _wrap_pcm_as_wav(audio_bytes, sample_rate, channels)
        return modulate_prerecorded_from_bytes(
            audio_bytes,
            sample_rate=sample_rate,
            diarize=diarize,
            attempts=attempts,
            return_language=return_language,
        )


def get_prerecorded_provider(language: Optional[str] = 'en') -> PrerecordedSTTProvider:
    """Construct the fixed managed pre-recorded adapter."""
    return ModulatePrerecordedProvider()


# ---------------------------------------------------------------------------
# Convenience wrappers — delegate to the active provider
# ---------------------------------------------------------------------------


def prerecorded(
    audio_url: str,
    speakers_count: Optional[int] = None,
    attempts: int = 0,
    return_language: bool = False,
    diarize: bool = True,
    language: Optional[str] = None,
    keywords: Optional[Sequence[str]] = None,
) -> Union[List[Dict[str, Any]], Tuple[List[Dict[str, Any]], str]]:
    """Transcribe a URL through the fixed managed adapter."""
    provider = get_prerecorded_provider(language)
    return provider.transcribe_url(
        audio_url,
        speakers_count=speakers_count,
        attempts=attempts,
        return_language=return_language,
        diarize=diarize,
        language=language,
        keywords=keywords,
    )


def prerecorded_from_bytes(
    audio_bytes: bytes,
    sample_rate: int = 16000,
    diarize: bool = True,
    attempts: int = 0,
    encoding: Optional[str] = None,
    channels: int = 1,
    language: Optional[str] = None,
    return_language: bool = False,
    keywords: Optional[Sequence[str]] = None,
) -> Union[List[Dict[str, Any]], Tuple[List[Dict[str, Any]], str]]:
    """Transcribe bytes through the fixed managed adapter."""
    provider = get_prerecorded_provider(language)
    return provider.transcribe_bytes(
        audio_bytes,
        sample_rate=sample_rate,
        diarize=diarize,
        attempts=attempts,
        encoding=encoding,
        channels=channels,
        language=language,
        return_language=return_language,
        keywords=keywords,
    )


def _words_cleaning(words: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    words_cleaned: List[Dict[str, Any]] = []
    for i, w in enumerate(words):
        # if w['timestamp'][0] == w['timestamp'][1]:
        #     continue
        words_cleaned.append(
            {
                'start': round(w['timestamp'][0], 2),
                'end': round(w['timestamp'][1] or w['timestamp'][0] + 1, 2),
                'speaker': w['speaker'],
                'text': str(w['text']).strip(),
                'is_user': False,
            }
        )

    for i, word in enumerate(words_cleaned):
        speaker = word['speaker']
        if not speaker:
            prev_chunk = words_cleaned[i - 1] if i > 0 else None
            next_chunk = words_cleaned[i + 1] if i < len(words_cleaned) - 1 else None
            prev_speaker = prev_chunk['speaker'] if prev_chunk else None
            next_speaker = next_chunk['speaker'] if next_chunk else None

            if prev_speaker and next_speaker:
                if prev_speaker == next_speaker:
                    speaker = prev_speaker
                else:
                    secs_from_prev = word['start'] - prev_chunk['end'] if prev_chunk else 0
                    secs_to_next = next_chunk['start'] - word['end'] if next_chunk else 0
                    speaker = prev_speaker if secs_from_prev < secs_to_next else next_speaker
            elif prev_speaker:
                speaker = prev_speaker
            elif next_speaker:
                speaker = next_speaker
            else:
                speaker = 'SPEAKER_00'

            words_cleaned[i]['speaker'] = speaker

    # for chunk in words_cleaned:
    #     print(chunk)
    return words_cleaned


def _retrieve_user_speaker_id(words: List[Dict[str, Any]], skip_n_seconds: int) -> Optional[str]:
    if not skip_n_seconds:
        return None

    user_speaker_id: defaultdict[str, int] = defaultdict(int)
    for word in words:
        if word['start'] >= skip_n_seconds:
            break
        if not word['speaker']:
            continue
        user_speaker_id[word['speaker']] += 1

    if not user_speaker_id:
        return None
    return max(user_speaker_id, key=user_speaker_id.get)  # type: ignore[reportUnknownVariableType,reportUnknownArgumentType]  # pyright can't infer defaultdict key type


def _merge_segments(
    words: List[Dict[str, Any]], skip_n_seconds: int, user_speaker_id: Optional[str]
) -> List[Dict[str, Any]]:
    segments: List[Dict[str, Any]] = []
    for word in words:
        if word['start'] < skip_n_seconds:
            continue
        word['is_user'] = word['speaker'] == user_speaker_id if word['speaker'] else False

        same_prev_speaker = word['speaker'] == segments[-1]['speaker'] if segments else False
        seconds_from_prev = word['start'] - segments[-1]['end'] if segments else 0

        # TODO: consider having a max segment size too
        if segments and same_prev_speaker and seconds_from_prev < 30:
            segments[-1]['end'] = word['end']
            segments[-1]['text'] += ' ' + word['text']
        else:
            segments.append(word)
    return segments


def _segments_as_objects(segments: List[Dict[str, Any]]) -> List[TranscriptSegment]:
    if not segments:
        return []
    starts_at = segments[0]['start']
    return [
        TranscriptSegment(
            text=str(segment['text']).strip().capitalize(),
            speaker=segment['speaker'],
            is_user=segment['is_user'],
            start=round(segment['start'] - starts_at, 2),
            end=round(segment['end'] - starts_at, 2),
        )
        for segment in segments
    ]


def postprocess_words(
    words: List[Dict[str, Any]], duration: int, skip_n_seconds: int = 0  # , merge_segments: bool = True
) -> List[TranscriptSegment]:
    cleaned_words = _words_cleaning(words)
    user_speaker_id = _retrieve_user_speaker_id(cleaned_words, skip_n_seconds)
    segments = _merge_segments(cleaned_words, skip_n_seconds, user_speaker_id)
    segments_objs = _segments_as_objects(segments)
    return segments_objs
