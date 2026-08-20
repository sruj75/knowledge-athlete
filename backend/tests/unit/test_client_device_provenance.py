"""Unit tests for client device identity contract and registry."""

from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

from models.memories import Evidence
from utils.client_device import (
    build_client_device_id,
    resolve_client_device,
    resolve_client_device_from_websocket_auth_message,
)


def test_build_client_device_id_matches_fcm_shape():
    assert build_client_device_id("ios", "abc12345") == "ios_abc12345"
    assert build_client_device_id("macos", "deadbeef") == "macos_deadbeef"


def test_build_client_device_id_null_when_missing():
    assert build_client_device_id(None, "abc") is None
    assert build_client_device_id("ios", None) is None
    assert build_client_device_id("ios", "default") is None
    assert build_client_device_id("ios", "nothex!!") is None
    assert build_client_device_id("unknown", "a1b2c3d4") is None


def test_resolve_client_device_from_headers():
    ctx = resolve_client_device(x_app_platform="macos", x_device_id_hash="a1b2c3d4", x_app_version="1.2.3")
    assert ctx.client_device_id == "macos_a1b2c3d4"
    assert ctx.platform == "macos"
    assert ctx.app_version == "1.2.3"


def test_resolve_client_device_from_websocket_auth_message_uses_web_platform():
    context = resolve_client_device_from_websocket_auth_message(
        {"text": '{"type":"auth","token":"firebase","device_id_hash":"a1b2c3d4"}'}
    )

    assert context.client_device_id == "web_a1b2c3d4"
    assert context.platform == "web"


@patch("database.redis_db.try_acquire_client_device_write_lock", return_value=True)
def test_record_client_device_upserts_and_throttles(mock_lock):
    import importlib
    import os
    from pathlib import Path

    from tests.unit.memory_import_isolation import drop_stale_module

    backend_dir = Path(__file__).resolve().parents[2]
    users_file = os.path.join(backend_dir, "database", "users.py")
    drop_stale_module("database.users", users_file)
    import database.users as users_db

    importlib.reload(users_db)

    mock_doc = MagicMock()
    mock_doc.get.return_value.exists = False
    mock_collection = MagicMock()
    mock_collection.document.return_value = mock_doc
    mock_user = MagicMock()
    mock_user.collection.return_value = mock_collection

    mock_db = MagicMock()
    original_db = users_db.__dict__.get("db")
    users_db.db = mock_db
    try:
        mock_db.collection.return_value.document.return_value = mock_user
        users_db.record_client_device(
            "uid-1",
            client_device_id="macos_a1b2c3d4",
            platform="macos",
            app_version="1.0.0",
        )
    finally:
        users_db.db = original_db

    mock_lock.assert_called_once_with("uid-1", "macos_a1b2c3d4")
    mock_doc.set.assert_called_once()
    payload = mock_doc.set.call_args[0][0]
    assert payload["platform"] == "macos"
    assert payload["device_class"] == "desktop"
    assert "first_seen_at" in payload
    assert users_db._normalize_platform("windows") == ("desktop", "windows")


def test_evidence_id_unchanged_when_client_device_absent():
    artifact = {"kind": "transcript_segments", "conversation_id": "conv-1"}
    without_device = Evidence.from_source(
        source_id="conv-1",
        source_type="conversation",
        source_signal="transcription",
        extractor_id="new_memories_extractor",
        extractor_version="v1",
        artifact_ref=artifact,
    )
    with_device = Evidence.from_source(
        source_id="conv-1",
        source_type="conversation",
        source_signal="transcription",
        extractor_id="new_memories_extractor",
        extractor_version="v1",
        artifact_ref=artifact,
        client_device_id="macos_abc",
    )
    assert without_device.evidence_id == with_device.evidence_id
    assert with_device.client_device_id == "macos_abc"


def test_transcript_artifact_ref_omits_device_from_hash_inputs():
    from models.conversation import Conversation
    from models.structured import Structured

    def _artifact_ref(conversation: Conversation) -> dict:
        segments = conversation.transcript_segments or []
        return {
            "kind": "transcript_segments",
            "conversation_id": conversation.id,
            "segment_ids": [segment.id for segment in segments if segment.id],
            "start": min((segment.start for segment in segments), default=None),
            "end": max((segment.end for segment in segments), default=None),
        }

    base = Conversation(
        id="c1",
        created_at=datetime.now(timezone.utc),
        started_at=datetime.now(timezone.utc),
        finished_at=datetime.now(timezone.utc),
        structured=Structured(),
    )
    with_device = base.model_copy(update={"client_device_id": "macos_abc12345"})

    assert _artifact_ref(base) == _artifact_ref(with_device)


def test_transient_listen_has_no_durable_device_provenance_owner():
    runtime = (Path(__file__).resolve().parents[2] / "routers" / "listen" / "runtime.py").read_text(encoding="utf-8")
    conversations = Path(__file__).resolve().parents[2] / "routers" / "listen" / "conversations.py"

    assert not conversations.exists()
    assert "resolve_client_device_from_headers(" not in runtime
    assert "client_device_id" not in runtime


def test_retired_web_listen_device_provenance_handshake_is_absent():
    source = (Path(__file__).resolve().parents[2] / "routers" / "transcribe.py").read_text(encoding="utf-8")

    assert 'websocket("/v4/web/listen")' not in source
    assert "resolve_client_device_from_websocket_auth_message(first_message)" not in source
    assert "client_device_context=client_device_context" not in source
