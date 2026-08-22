import importlib
import importlib.util
import sys
import types
from unittest.mock import MagicMock

import pytest

MISSING_OPUS_MESSAGE = "native libopus"
_MISSING = object()


def _capture_module(name: str):
    parent_name, _, attr = name.rpartition(".")
    parent = sys.modules.get(parent_name)
    parent_attr = getattr(parent, attr, _MISSING) if parent is not None else _MISSING
    return sys.modules.get(name, _MISSING), parent_attr


def _restore_module(name: str, captured):
    module, parent_attr = captured
    parent_name, _, attr = name.rpartition(".")
    parent = sys.modules.get(parent_name)

    if module is _MISSING:
        sys.modules.pop(name, None)
    else:
        sys.modules[name] = module

    if parent is None:
        return
    if parent_attr is _MISSING:
        if hasattr(parent, attr):
            delattr(parent, attr)
    else:
        setattr(parent, attr, parent_attr)


def _drop_module(name: str):
    sys.modules.pop(name, None)
    parent_name, _, attr = name.rpartition(".")
    parent = sys.modules.get(parent_name)
    if parent is not None and not hasattr(parent, "__path__"):
        sys.modules.pop(parent_name, None)
        return
    if parent is not None and hasattr(parent, attr):
        delattr(parent, attr)


def _module(name: str, **attrs):
    module = types.ModuleType(name)
    for attr, value in attrs.items():
        setattr(module, attr, value)
    return module


def _install_python_multipart_stub(monkeypatch):
    if "python_multipart" in sys.modules:
        return
    if importlib.util.find_spec("python_multipart") is not None:
        return

    monkeypatch.setitem(sys.modules, "python_multipart", _module("python_multipart", __version__="0.0.20"))


def _install_sync_import_stubs(monkeypatch):
    _install_python_multipart_stub(monkeypatch)

    for name in [
        "database._client",
        "database.redis_db",
        "database.fair_use",
        "database.users",
        "database.user_usage",
        "database.conversations",
        "database.cache",
        "firebase_admin",
        "firebase_admin.messaging",
        "models.conversation",
        "models.conversation_enums",
        "models.transcript_segment",
        "utils.conversations.process_conversation",
        "utils.conversations.factory",
        "utils.other.endpoints",
        "utils.other.storage",
        "utils.encryption",
        "utils.analytics",
        "utils.cloud_tasks",
        "utils.http_client",
        "utils.stt.pre_recorded",
        "utils.stt.vad",
        "utils.speaker_assignment",
        "utils.speaker_identification",
        "utils.stt.speaker_embedding",
        "utils.fair_use",
        "utils.subscription",
        "utils.log_sanitizer",
        "utils.executors",
        "pydub",
        "numpy",
        "httpx",
    ]:
        monkeypatch.setitem(sys.modules, name, MagicMock())

    sys.modules["database.redis_db"].r = MagicMock()
    sys.modules["database._client"].db = MagicMock()
    sys.modules["utils.log_sanitizer"].sanitize = lambda value: value


def test_sync_import_defers_missing_native_opus(monkeypatch, tmp_path):
    captured_sync_files = _capture_module("utils.sync.files")
    _install_sync_import_stubs(monkeypatch)
    monkeypatch.setitem(sys.modules, "opuslib", None)
    try:
        _drop_module("utils.sync.files")

        sync_files = importlib.import_module("utils.sync.files")
        opus_path = tmp_path / "audio.opus"
        opus_path.write_bytes(b"\x00\x00\x00\x00")

        assert sync_files.Decoder is None
        with pytest.raises(RuntimeError, match=MISSING_OPUS_MESSAGE):
            sync_files.decode_opus_file_to_wav(str(opus_path), str(tmp_path / "audio.wav"))
    finally:
        _restore_module("utils.sync.files", captured_sync_files)
