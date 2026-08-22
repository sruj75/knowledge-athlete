"""S-23 boundary for the S-25-owned historical audio-reader handoff."""

import struct

import pytest

from utils.other import storage


@pytest.mark.parametrize(
    ('payload', 'message'),
    [
        (b'', 'too short'),
        (b'\x00' * 4, 'too short'),
        (struct.pack('<II', 1, 100), 'Truncated'),
        (struct.pack('<IIH', 1, 640, 100) + b'\x00' * 5, 'Truncated'),
    ],
)
def test_retained_drain_decoder_rejects_malformed_historical_chunks(payload, message):
    with pytest.raises(ValueError, match=message):
        storage.decode_opus_to_pcm(payload)


def test_new_product_audio_writers_are_absent():
    assert not hasattr(storage, 'upload_audio_chunk')
    assert not hasattr(storage, 'delete_audio_chunks')
    assert not hasattr(storage, 'upload_audio_chunks_batch')
    assert callable(storage.download_audio_chunks_and_merge)
