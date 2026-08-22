"""Behavioral tests for the callerless S-25 conversation-audio drain builder."""

from unittest.mock import MagicMock

import pytest

from utils.sync import playback


class _FakeAudioSegment:
    def __init__(self, **_kwargs):
        pass

    def export(self, buffer, **_kwargs):
        buffer.write(b'MP3')


def _parts(monkeypatch, available):
    monkeypatch.setattr(playback, 'AudioSegment', _FakeAudioSegment)

    def download(_uid, _conversation_id, timestamps, **_kwargs):
        first = sorted(timestamps)[0]
        if first not in available:
            raise FileNotFoundError(first)
        return available[first]

    monkeypatch.setattr(playback, 'download_audio_chunks_and_merge', download)


def test_dense_artifact_collapses_inter_part_gaps(monkeypatch):
    _parts(monkeypatch, {1000.0: b'\x01' * 320_000, 1200.0: b'\x02' * 160_000})
    audio_files = [
        {'id': 'B', 'chunk_timestamps': [1200.0]},
        {'id': 'A', 'chunk_timestamps': [1000.0]},
    ]

    mp3, spans = playback.build_conversation_playback_artifact('uid', 'conversation', audio_files, 990.0)

    assert mp3 == b'MP3'
    assert spans == [
        {'file_id': 'A', 'wall_offset': 10.0, 'artifact_offset': 0.0, 'len': 10.0},
        {'file_id': 'B', 'wall_offset': 210.0, 'artifact_offset': 10.0, 'len': 5.0},
    ]


def test_missing_part_is_skipped_without_leaving_an_artifact_gap(monkeypatch):
    _parts(monkeypatch, {1200.0: b'\x02' * 160_000})

    _, spans = playback.build_conversation_playback_artifact(
        'uid',
        'conversation',
        [
            {'id': 'missing', 'chunk_timestamps': [1000.0]},
            {'id': 'present', 'chunk_timestamps': [1200.0]},
        ],
        990.0,
    )

    assert spans == [{'file_id': 'present', 'wall_offset': 210.0, 'artifact_offset': 0.0, 'len': 5.0}]


def test_all_missing_parts_fail_the_existing_task(monkeypatch):
    _parts(monkeypatch, {})

    with pytest.raises(FileNotFoundError):
        playback.build_conversation_playback_artifact(
            'uid', 'conversation', [{'id': 'missing', 'chunk_timestamps': [1.0]}], 0.0
        )


def test_single_part_builder_keeps_fixed_mp3_encoding(monkeypatch):
    segment = MagicMock()
    segment.export.side_effect = lambda buffer, **_kwargs: buffer.write(b'MP3')
    monkeypatch.setattr(playback, 'AudioSegment', MagicMock(return_value=segment))
    monkeypatch.setattr(playback, 'download_audio_chunks_and_merge', lambda *_args, **_kwargs: b'pcm')

    assert playback.build_playback_artifact('uid', 'conversation', [1.0]) == b'MP3'
    segment.export.assert_called_once()
    assert segment.export.call_args.kwargs == {'format': 'mp3', 'bitrate': '48k'}
