"""Audio builders retained only for the S-25 Cloud Tasks backlog drain."""

from __future__ import annotations

import io
import logging
import wave

from pydub import AudioSegment

from utils.other.storage import download_audio_chunks_and_merge

logger = logging.getLogger(__name__)
AUDIO_SAMPLE_RATE = 16000


def pcm_to_wav(pcm_data: bytes, sample_rate: int = 16000, channels: int = 1, sample_width: int = 2) -> bytes:
    """Shared transient voice-message PCM conversion."""
    wav_buffer = io.BytesIO()
    with wave.open(wav_buffer, 'wb') as wav_file:
        wav_file.setnchannels(channels)
        wav_file.setsampwidth(sample_width)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(pcm_data)
    return wav_buffer.getvalue()


def build_playback_artifact(uid: str, conversation_id: str, timestamps: list[float]) -> bytes:
    """Build one artifact for an already-queued legacy audio-merge task."""
    pcm_data = download_audio_chunks_and_merge(
        uid,
        conversation_id,
        timestamps,
        fill_gaps=True,
        sample_rate=AUDIO_SAMPLE_RATE,
    )
    if not pcm_data:
        return b''
    segment = AudioSegment(data=pcm_data, sample_width=2, frame_rate=AUDIO_SAMPLE_RATE, channels=1)
    buffer = io.BytesIO()
    segment.export(buffer, format='mp3', bitrate='48k')  # type: ignore[reportUnknownMemberType]
    return buffer.getvalue()


_PCM_BYTES_PER_SECOND = AUDIO_SAMPLE_RATE * 2


def build_conversation_playback_artifact(
    uid: str,
    conversation_id: str,
    audio_files: list[dict],
    started_at_ts: float,
) -> tuple[bytes, list[dict]]:
    """Drain an already-queued conversation artifact task with bounded memory."""
    parts = sorted(
        [audio_file for audio_file in audio_files if audio_file.get('id') and audio_file.get('chunk_timestamps')],
        key=lambda audio_file: min(audio_file['chunk_timestamps']),
    )
    pcm_buffer = bytearray()
    spans: list[dict] = []
    for audio_file in parts:
        timestamps = sorted(audio_file['chunk_timestamps'])
        try:
            pcm = download_audio_chunks_and_merge(
                uid,
                conversation_id,
                timestamps,
                fill_gaps=True,
                sample_rate=AUDIO_SAMPLE_RATE,
            )
        except FileNotFoundError:
            logger.warning('Conversation artifact part missing from backlog drain')
            continue
        if not pcm:
            continue
        spans.append(
            {
                'file_id': audio_file['id'],
                'wall_offset': round(timestamps[0] - started_at_ts, 3),
                'artifact_offset': round(len(pcm_buffer) / _PCM_BYTES_PER_SECOND, 3),
                'len': round(len(pcm) / _PCM_BYTES_PER_SECOND, 3),
            }
        )
        pcm_buffer.extend(pcm)
    if not pcm_buffer:
        raise FileNotFoundError('No chunks found for conversation backlog drain')
    segment = AudioSegment(data=bytes(pcm_buffer), sample_width=2, frame_rate=AUDIO_SAMPLE_RATE, channels=1)
    buffer = io.BytesIO()
    segment.export(buffer, format='mp3', bitrate='48k')  # type: ignore[reportUnknownMemberType]
    return buffer.getvalue(), spans
