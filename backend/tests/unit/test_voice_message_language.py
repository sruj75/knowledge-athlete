"""
Unit tests for voice message language resolution.
"""

import os
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import MagicMock, call

import pytest

from testing.import_isolation import load_module_fresh, stub_modules

_BACKEND = Path(__file__).resolve().parents[2]


def _build_google_stubs() -> dict[str, ModuleType]:
    """Build the google.cloud.* stub subpackages (NotFound / FieldFilter / transactional)."""
    google_pkg = ModuleType("google")
    google_pkg.__path__ = []  # type: ignore[attr-defined]
    google_cloud_pkg = ModuleType("google.cloud")
    google_cloud_pkg.__path__ = []  # type: ignore[attr-defined]

    class NotFound(Exception):
        pass

    google_exceptions = ModuleType("google.cloud.exceptions")
    google_exceptions.NotFound = NotFound  # type: ignore[attr-defined]
    google_firestore = ModuleType("google.cloud.firestore")
    google_firestore_v1 = ModuleType("google.cloud.firestore_v1")
    google_firestore_v1.FieldFilter = MagicMock()  # type: ignore[attr-defined]
    google_firestore_v1.transactional = lambda func: func  # type: ignore[attr-defined]

    google_pkg.cloud = google_cloud_pkg  # type: ignore[attr-defined]
    google_cloud_pkg.exceptions = google_exceptions  # type: ignore[attr-defined]
    google_cloud_pkg.firestore = google_firestore  # type: ignore[attr-defined]

    return {
        "google": google_pkg,
        "google.cloud": google_cloud_pkg,
        "google.cloud.exceptions": google_exceptions,
        "google.cloud.firestore": google_firestore,
        "google.cloud.firestore_v1": google_firestore_v1,
    }


@pytest.fixture(scope="module")
def chat():
    """Load utils.chat fresh against a stubbed db/llm/models chain.

    utils.chat pulls a heavy import chain at import time (database and LLM
    clients) that cannot run in a hermetic unit process. The fakes below
    short-circuit that chain so only the pure ``resolve_voice_message_language``
    logic is exercised. The fake must precede the import — see
    ``backend/docs/test_isolation.md`` and ``testing/import_isolation``.
    """
    redis_db = MagicMock()
    redis_db.try_acquire_user_platform_write_lock = MagicMock()
    subscription = MagicMock()
    subscription.get_default_free_subscription = MagicMock()
    usage_tracker = MagicMock()
    usage_tracker.track_usage = MagicMock()
    usage_tracker.set_usage_context = MagicMock()
    usage_tracker.reset_usage_context = MagicMock()

    fakes: dict[str, object] = {
        "database._client": MagicMock(),
        "database.notifications": MagicMock(),
        "database.auth": MagicMock(),
        "database.users": MagicMock(),
        "database.redis_db": redis_db,
        "models.chat": MagicMock(),
        "models.conversation": MagicMock(),
        "models.notification_message": MagicMock(),
        "models.transcript_segment": MagicMock(),
        "utils.subscription": subscription,
        "utils.llm.usage_tracker": usage_tracker,
        "utils.notifications": MagicMock(),
        "utils.other.storage": MagicMock(),
        "utils.retrieval.graph": MagicMock(),
        "utils.stt.pre_recorded": MagicMock(),
    }
    fakes.update(_build_google_stubs())

    with stub_modules(fakes):  # type: ignore[arg-type]
        module = load_module_fresh("utils.chat", os.path.join(str(_BACKEND), "utils", "chat.py"))
        yield module


def test_request_language_auto_overrides_account_language(chat, monkeypatch):
    monkeypatch.setattr(chat.user_db, "get_user_language_preference", lambda uid: "es")

    language = chat.resolve_voice_message_language("uid", " auto ")
    assert language == "multi"


def test_request_language_multi(chat, monkeypatch):
    monkeypatch.setattr(chat.user_db, "get_user_language_preference", lambda uid: "ru")

    language = chat.resolve_voice_message_language("uid", "multi")
    assert language == "multi"


def test_request_language_specific(chat, monkeypatch):
    monkeypatch.setattr(chat.user_db, "get_user_language_preference", lambda uid: "en")

    language = chat.resolve_voice_message_language("uid", "ru")
    assert language == "ru"


def test_request_language_blank_uses_account_language_capability(chat, monkeypatch):
    monkeypatch.setattr(chat.user_db, "get_user_language_preference", lambda uid: "my")

    language = chat.resolve_voice_message_language("uid", "   ")
    assert language == "my"


def test_account_language_without_auto_detection_uses_explicit_language(chat, monkeypatch):
    monkeypatch.setattr(chat.user_db, "get_user_language_preference", lambda uid: "my")

    language = chat.resolve_voice_message_language("uid", None)
    assert language == "my"


def test_supported_account_language_uses_auto_detection(chat, monkeypatch):
    monkeypatch.setattr(chat.user_db, "get_user_language_preference", lambda uid: "fr")

    language = chat.resolve_voice_message_language("uid", None)
    assert language == "multi"


def test_no_preference_detect_language(chat, monkeypatch):
    monkeypatch.setattr(chat.user_db, "get_user_language_preference", lambda uid: "")

    language = chat.resolve_voice_message_language("uid", None)
    assert language == "multi"


def test_voice_message_uses_request_local_bytes_without_storage(chat, monkeypatch, tmp_path):
    audio = tmp_path / "audio.wav"
    payload = b"synthetic-wav-bytes"
    audio.write_bytes(payload)
    assert not hasattr(chat, "get_syncing_file_temporal_signed_url")
    assert not hasattr(chat, "schedule_syncing_temporal_file_deletion")
    monkeypatch.setattr(chat, "get_prerecorded_service", lambda language: ("modulate", "en", "modulate-velma-2"))
    monkeypatch.setattr(chat, "_validated_wav_is_silent", lambda path, provider: True)

    assert chat.load_voice_message_segment_bytes(str(audio), "uid", "en") == (None, "en", "en")

    monkeypatch.setattr(chat, "_validated_wav_is_silent", lambda path, provider: False)
    transcribe = MagicMock(return_value=[object()])
    monkeypatch.setattr(chat, "prerecorded_from_bytes", transcribe)
    monkeypatch.setattr(chat, "postprocess_words", lambda words, offset: [SimpleNamespace(text="hello")])

    audio_bytes, language, silence_language = chat.load_voice_message_segment_bytes(str(audio), "uid", "en")
    assert (audio_bytes, language, silence_language) == (payload, "en", None)
    assert chat.transcribe_voice_message_bytes(audio_bytes, language) == ("hello", "en")
    transcribe.assert_called_once_with(payload, diarize=False, language="en", return_language=False)


def test_voice_message_preserves_legacy_provider_retry_budget(chat, monkeypatch):
    """Continue with attempts 4-5 after the byte adapter exhausts attempts 1-3."""
    monkeypatch.setattr(chat, "get_prerecorded_service", lambda language: ("modulate", "en", "modulate-velma-2"))
    transcribe = MagicMock(side_effect=[RuntimeError("first three attempts failed"), [object()]])
    monkeypatch.setattr(chat, "prerecorded_from_bytes", transcribe)
    monkeypatch.setattr(chat, "postprocess_words", lambda words, offset: [SimpleNamespace(text="recovered")])

    assert chat.transcribe_voice_message_bytes(b"wav", "en") == ("recovered", "en")
    assert transcribe.call_args_list == [
        call(b"wav", diarize=False, language="en", return_language=False),
        call(b"wav", diarize=False, language="en", return_language=False, attempts=1),
    ]
