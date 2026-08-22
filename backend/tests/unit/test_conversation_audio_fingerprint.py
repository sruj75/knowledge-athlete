"""S-25 drain fingerprint contract for already-queued conversation audio."""

from utils.other.storage import compute_audio_files_fingerprint


def test_fingerprint_is_deterministic_and_order_insensitive():
    first = [{'id': 'A', 'chunk_timestamps': [1.0, 2.0]}, {'id': 'B', 'chunk_timestamps': [9.0]}]
    reordered = [{'id': 'B', 'chunk_timestamps': [9.0]}, {'id': 'A', 'chunk_timestamps': [2.0, 1.0]}]

    assert compute_audio_files_fingerprint(first) == compute_audio_files_fingerprint(reordered)


def test_fingerprint_changes_when_the_backlog_artifact_changes():
    original = [{'id': 'A', 'chunk_timestamps': [1.0, 2.0]}]
    late_chunk = [{'id': 'A', 'chunk_timestamps': [1.0, 2.0, 3.0]}]

    assert compute_audio_files_fingerprint(original) != compute_audio_files_fingerprint(late_chunk)


def test_fingerprint_ignores_incomplete_parts():
    complete = [{'id': 'A', 'chunk_timestamps': [1.0, 2.0]}]
    with_incomplete = complete + [{'id': None}, {'chunk_timestamps': []}, {'id': 'C'}]

    assert compute_audio_files_fingerprint(complete) == compute_audio_files_fingerprint(with_incomplete)
