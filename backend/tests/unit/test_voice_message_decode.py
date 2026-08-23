from __future__ import annotations

import struct
import wave

import pytest
from fastapi import HTTPException

from utils.voice_messages import decode_files_to_wav


def _write_pcm_voice_message(path, frames: list[bytes]) -> None:
    with path.open('wb') as handle:
        for frame in frames:
            handle.write(struct.pack('<I', len(frame)))
            handle.write(frame)


def test_pcm_voice_message_is_decoded_for_the_retained_chat_route(tmp_path) -> None:
    source = tmp_path / 'audio_phonemic_pcm16_16000_1_fs160_1760000000.bin'
    _write_pcm_voice_message(source, [bytes([42]) * 320])

    decoded = decode_files_to_wav([str(source)])

    assert decoded == [str(source).replace('.bin', '.wav')]
    assert not source.exists()
    with wave.open(decoded[0], 'rb') as wav_file:
        assert wav_file.getframerate() == 16000
        assert wav_file.getnchannels() == 1
        assert wav_file.getsampwidth() == 2
        assert wav_file.getnframes() == 160


def test_unreadable_voice_message_does_not_discard_a_valid_sibling(tmp_path) -> None:
    unreadable = tmp_path / 'audio_phonemic_pcm16_16000_1_fs160_1760000000.bin'
    valid = tmp_path / 'audio_phonemic_pcm16_16000_1_fs160_1760000001.bin'
    unreadable.write_bytes(b'')
    _write_pcm_voice_message(valid, [bytes([21]) * 320])

    decoded = decode_files_to_wav([str(unreadable), str(valid)])

    assert decoded == [str(valid).replace('.bin', '.wav')]
    assert not unreadable.exists()
    assert not valid.exists()


def test_voice_message_batch_fails_only_when_nothing_decodes(tmp_path) -> None:
    unreadable = tmp_path / 'audio_phonemic_pcm16_16000_1_fs160_1760000000.bin'
    unreadable.write_bytes(b'')

    with pytest.raises(HTTPException) as error:
        decode_files_to_wav([str(unreadable)])

    assert error.value.status_code == 400
    assert error.value.detail == 'Audio decode failed'
