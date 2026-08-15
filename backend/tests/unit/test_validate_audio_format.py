"""Regression: an unsupported codec/sample_rate must be rejected before the decoder is built.

The native Opus decoder accepts only a fixed set of sample rates. Validation is checked at
connect so unsupported rates and retired wearable-only LC3 codecs close cleanly (1003) instead
of escaping the ASGI handler as an unclean 1006 drop.
"""

from utils.transcribe_decisions import OPUS_SUPPORTED_SAMPLE_RATES, validate_audio_format


def test_supported_formats_pass():
    assert validate_audio_format('opus', 16000) is None
    assert validate_audio_format('opus_fs320', 48000) is None
    assert validate_audio_format('pcm8', 8000) is None
    assert validate_audio_format('pcm16', 16000) is None
    assert validate_audio_format('aac', 16000) is None


def test_opus_rejects_a_rate_opuslib_cannot_decode():
    # 44100 is not one of opus's supported rates; opuslib.Decoder(44100, 1) would raise OpusError.
    reason = validate_audio_format('opus', 44100)
    assert reason is not None
    assert '44100' in reason
    assert validate_audio_format('opus_fs320', 44100) is not None
    # Every advertised opus rate is accepted.
    for rate in OPUS_SUPPORTED_SAMPLE_RATES:
        assert validate_audio_format('opus', rate) is None


def test_retired_lc3_codecs_are_rejected():
    assert validate_audio_format('lc3', 16000) == 'lc3 streaming is no longer supported'
    assert validate_audio_format('lc3_fs1030', 16000) == 'lc3 streaming is no longer supported'
