"""GAP 1: subject_entity_id / predicate / arguments persist through canonical extraction."""

from __future__ import annotations

import os
import importlib
from datetime import datetime, timezone
from unittest.mock import patch

import pytest

os.environ.setdefault(
    "ENCRYPTION_SECRET",
    "omi_ZwB2ZNqB2HHpMK6wStk7sTpavJiPTFg7gXUHnc4tFABPU6pZ2c2DKgehtfgi4RZv",
)

from models.memories import Memory, MemoryCategory, MemoryDB, SubjectAttribution
from models.memory_apply import MemoryControlState
from models.product_memory import MemoryItemStatus, MemoryTier
from utils.memory.canonical_memory_adapter import (
    extraction_memory_id,
    read_canonical_memories,
    write_canonical_extraction_memory,
)
from utils.memory.canonical_activation import CanonicalWriteDecision
from utils.memory.memory_service import MemoryService
from utils.memory.memory_system import MemorySystem
from utils.memory.required_promotion import required_processing_payload
from tests.unit.test_ws_i_write_convergence import _FakeDb, _trusted_account_generation

USER_ENTITY_ID = "user"


def _refresh_canonical_runtime() -> None:
    canonical_adapter = importlib.import_module("utils.memory.canonical_memory_adapter")
    globals().update(
        {
            "read_canonical_memories": canonical_adapter.read_canonical_memories,
            "write_canonical_extraction_memory": canonical_adapter.write_canonical_extraction_memory,
        }
    )


@pytest.fixture(autouse=True)
def _refresh_canonical_runtime_fixture():
    _refresh_canonical_runtime()


def _control_seed(uid: str) -> dict:
    return {
        f"users/{uid}/memory_state/apply_control": MemoryControlState(
            uid=uid,
            head_commit_id="head0",
            account_generation=1,
            source_generation=1,
        ).model_dump(mode="json"),
    }


def _rollout_control_doc(uid: str) -> dict:
    return {
        "uid": uid,
        "schema_version": 1,
        "mode": "write",
        "mode_epoch": 1,
        "cutover_epoch": 0,
        "account_generation": 1,
        "fallback_projection_ready": False,
        "persistent_memory_writes_started": True,
        "decommission_reconciled": False,
        "writes_blocked": False,
        "stage_gates": {"shadow": "passed", "write": "passed", "read": "blocked"},
        "grants": {"omi_chat": {"default_memory": False, "archive": False}},
        "vector_repair_outbox_enabled": False,
    }


@pytest.fixture
def monkeypatch_trusted_account(monkeypatch):
    monkeypatch.setattr(
        "utils.memory.canonical_memory_adapter.read_memory_v3_trusted_account_generation",
        lambda **_: _trusted_account_generation(),
    )


def test_memory_service_write_persists_subject_and_predicate(monkeypatch_trusted_account):
    uid = "uid-subject-wire"
    conversation_id = "conv-subject"
    content = "User lives in San Francisco"
    now = datetime(2026, 6, 1, tzinfo=timezone.utc)
    memory = Memory(content=content, category=MemoryCategory.interesting)
    memory_db = MemoryDB.from_memory(
        memory,
        uid,
        conversation_id,
        False,
        subject_entity_id=USER_ENTITY_ID,
        subject_attribution=SubjectAttribution.user,
    )
    memory_db.id = "mem_subject_test"
    memory_db.memory_tier = MemoryTier.short_term
    memory_db.created_at = now
    memory_db.updated_at = now

    payload = memory_db.model_dump(mode="json")
    assert payload.get("subject_entity_id") == USER_ENTITY_ID

    db = _FakeDb(_control_seed(uid))
    service = MemoryService(db_client=db)
    with patch(
        "utils.memory.memory_service.canonical_write_decision",
        return_value=CanonicalWriteDecision(enabled=True, memory_system=MemorySystem.CANONICAL),
    ):
        service.write(uid, payload)

    items = read_canonical_memories(uid, db_client=db)
    assert len(items) == 1
    stored = db.docs[f"users/{uid}/memory_items/{items[0].id}"]
    assert stored["subject_entity_id"] == USER_ENTITY_ID
    assert stored["predicate"] == "resides_in"
    assert stored["arguments"] == {"location": "San Francisco"}


def test_extraction_memory_id_is_deterministic_and_partitions_non_user_subjects():
    identity = {
        "uid": "uid-subject-id",
        "source_id": "conv-subject-id",
        "content": "Prefers tea",
    }

    alice_id = extraction_memory_id(**identity, subject_entity_id="person:alice")
    bob_id = extraction_memory_id(**identity, subject_entity_id="person:bob")

    assert alice_id == extraction_memory_id(**identity, subject_entity_id="person:alice")
    assert alice_id != bob_id
    assert extraction_memory_id(**identity, subject_entity_id=USER_ENTITY_ID) == extraction_memory_id(**identity)


def test_write_mode_rollout_doc_does_not_collide_with_apply_control_state(monkeypatch_trusted_account):
    uid = "uid-rollout-doc-present"
    payload = {
        "id": "mem_rollout_collision",
        "uid": uid,
        "content": "Canonical write works with rollout state present",
        "conversation_id": "conv-rollout-collision",
        "memory_tier": MemoryTier.short_term.value,
        "created_at": datetime(2026, 6, 1, tzinfo=timezone.utc),
        "updated_at": datetime(2026, 6, 1, tzinfo=timezone.utc),
    }
    db = _FakeDb({f"users/{uid}/memory_control/state": _rollout_control_doc(uid)})
    service = MemoryService(db_client=db)

    with patch(
        "utils.memory.memory_service.canonical_write_decision",
        return_value=CanonicalWriteDecision(enabled=True, memory_system=MemorySystem.CANONICAL),
    ):
        service.write(uid, payload)

    apply_control = db.docs[f"users/{uid}/memory_state/apply_control"]
    rollout_control = db.docs[f"users/{uid}/memory_control/state"]
    assert apply_control["head_commit_id"] != "head0"
    assert apply_control["source_generation"] == 1
    assert rollout_control["mode"] == "write"
    assert rollout_control["stage_gates"]["read"] == "blocked"
    assert f"users/{uid}/memory_items/mem_rollout_collision" in db.docs


def test_write_canonical_extraction_memory_threads_explicit_triple_fields(monkeypatch_trusted_account):
    uid = "uid-explicit"
    conversation_id = "conv-explicit"
    content = "Prefers dark mode"
    now = datetime(2026, 6, 1, tzinfo=timezone.utc)
    db = _FakeDb(_control_seed(uid))
    payload = {
        "id": "mem_explicit",
        "uid": uid,
        "content": content,
        "conversation_id": conversation_id,
        "subject_entity_id": USER_ENTITY_ID,
        "predicate": "prefers",
        "arguments": {"thing": "dark mode"},
        "memory_tier": MemoryTier.short_term.value,
        "created_at": now,
        "updated_at": now,
        "evidence": [
            {
                "evidence_id": "ev1",
                "source_id": conversation_id,
                "source_type": "conversation",
                "source_signal": "transcription",
                "extractor_id": "test",
                "extractor_version": "v1",
                "artifact_ref": {},
                "capture_confidence": 0.5,
                "independence_group": conversation_id,
                "redaction_status": "active",
                "created_at": now,
            }
        ],
    }
    write_canonical_extraction_memory(uid, payload, db_client=db)
    stored = db.docs[f"users/{uid}/memory_items/mem_explicit"]
    assert stored["subject_entity_id"] == USER_ENTITY_ID
    assert stored["predicate"] == "prefers"
    assert stored["arguments"] == {"thing": "dark mode"}
