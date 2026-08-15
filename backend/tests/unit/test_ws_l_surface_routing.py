"""WS-L surface routing: cohort pinning, shared canonical filter, memory≠cohort guard."""

from __future__ import annotations

import os
import importlib
from datetime import datetime, timedelta, timezone

import pytest

os.environ.setdefault(
    "ENCRYPTION_SECRET",
    "omi_ZwB2ZNqB2HHpMK6wStk7sTpavJiPTFg7gXUHnc4tFABPU6pZ2c2DKgehtfgi4RZv",
)

from models.memory_evidence import ArtifactPreservationState, MemoryEvidence, SourceState
from models.product_memory import (
    MemoryAccessPolicy,
    MemoryItemStatus,
    MemoryTier,
    ProcessingState,
    MemoryItem,
)

from tests.unit.memory_import_isolation import ensure_utils_memory_packages_importable

ensure_utils_memory_packages_importable()
from utils.memory.canonical_visibility_filter import filter_canonical_default_visible_items


def _refresh_memory_system_bindings():
    memory_system_mod = importlib.import_module("utils.memory.memory_system")
    globals()["MemorySystem"] = memory_system_mod.MemorySystem
    globals()["resolve_memory_system"] = memory_system_mod.resolve_memory_system
    return memory_system_mod


_refresh_memory_system_bindings()


class _Snapshot:
    def __init__(self, data=None, *, exists=True):
        self._data = data
        self.exists = exists

    def to_dict(self):
        if self._data is None:
            return None
        return dict(self._data)


class _DocumentRef:
    def __init__(self, db_client, path):
        self._db_client = db_client
        self.path = path

    def get(self, timeout=None):
        if self.path not in self._db_client.docs:
            return _Snapshot(None, exists=False)
        return _Snapshot(self._db_client.docs[self.path], exists=True)


class _FirestoreFake:
    def __init__(self, docs=None):
        self.docs = docs or {}

    def document(self, path):
        return _DocumentRef(self, path)


@pytest.fixture(autouse=True)
def _clear_canonical_cohort(monkeypatch):
    from tests.unit.canonical_cohort_test_helpers import clear_canonical_cohort

    _refresh_memory_system_bindings()
    clear_canonical_cohort(monkeypatch)
    monkeypatch.delenv("MEMORY_MODE", raising=False)
    monkeypatch.delenv("MEMORY_ENABLED_USERS", raising=False)


def _processed_short_term_item(*, memory_id: str = "mem-st") -> MemoryItem:
    now = datetime(2026, 6, 1, tzinfo=timezone.utc)
    evidence = MemoryEvidence(
        evidence_id="ev1",
        source_type="conversation",
        source_id="conv-1",
        source_version="v1",
        conversation_id="conv-1",
        artifact_preservation=ArtifactPreservationState.preserved,
    )
    return MemoryItem(
        memory_id=memory_id,
        uid="uid-canonical",
        version=1,
        tier=MemoryTier.short_term,
        status=MemoryItemStatus.active,
        processing_state=ProcessingState.processed,
        content="Fresh short-term extraction",
        evidence=[evidence],
        source_state=SourceState.active,
        sensitivity_labels=[],
        user_asserted=False,
        captured_at=now,
        updated_at=now,
        expires_at=now + timedelta(days=30),
        ledger_commit_id="commit_1",
        ledger_sequence=1,
        source_commit_id="commit_1",
        source_commit_sequence=1,
        content_hash="hash1",
    )


class TestSharedCanonicalVisibilityFilter:
    def test_processed_short_term_stays_default_visible(self):
        item = _processed_short_term_item()
        policy = MemoryAccessPolicy.for_omi_chat(archive_capability=False)
        now = datetime(2026, 6, 15, tzinfo=timezone.utc)

        visible = filter_canonical_default_visible_items([item], policy=policy, now=now)

        assert len(visible) == 1
        assert visible[0].memory_id == "mem-st"


class TestResolveMemorySystemIgnoresMemoryFlags:
    def test_memory_read_dogfood_stays_legacy_cohort(self, monkeypatch):
        monkeypatch.setenv("MEMORY_MODE", "read")
        monkeypatch.setenv("MEMORY_ENABLED_USERS", "uid-memory")
        db = _FirestoreFake(
            {
                "users/uid-memory/memory_control/state": {
                    "mode": "read",
                    "fallback_projection_ready": True,
                }
            }
        )
        assert resolve_memory_system("uid-memory", db_client=db) == MemorySystem.LEGACY

    def test_canonical_cohort_pins_without_memory_flags(self, monkeypatch):
        from tests.unit.canonical_cohort_test_helpers import set_canonical_cohort

        set_canonical_cohort(monkeypatch, "uid-canonical")
        assert resolve_memory_system("uid-canonical", db_client=_FirestoreFake()) == MemorySystem.CANONICAL
        assert resolve_memory_system("uid-legacy", db_client=_FirestoreFake()) == MemorySystem.LEGACY


class TestMemorySystemRequestPinning:
    def test_pin_stable_when_underlying_resolver_would_flip(self, monkeypatch):
        from utils.memory.memory_system_pin import (
            clear_memory_system_pin,
            pin_memory_system,
            resolve_pinned_memory_system,
        )
        import utils.memory.memory_system_pin as memory_system_pin

        uid = "uid-pin-flip"
        calls = {"count": 0}

        def flipping_resolve(_uid, *, db_client=None):
            calls["count"] += 1
            return MemorySystem.CANONICAL if calls["count"] == 1 else MemorySystem.LEGACY

        monkeypatch.setattr(memory_system_pin, "resolve_memory_system", flipping_resolve)

        assert pin_memory_system(uid) == MemorySystem.CANONICAL
        assert resolve_pinned_memory_system(uid) == MemorySystem.CANONICAL
        assert resolve_pinned_memory_system(uid) == MemorySystem.CANONICAL
        assert calls["count"] == 1

        clear_memory_system_pin()
        assert resolve_pinned_memory_system(uid) == MemorySystem.LEGACY
        assert calls["count"] == 2

    def test_request_scope_resets_pin_after_block(self, monkeypatch):
        from utils.memory.memory_system_pin import (
            get_pinned_memory_system,
            memory_system_request_scope,
            resolve_pinned_memory_system,
        )

        from tests.unit.canonical_cohort_test_helpers import set_canonical_cohort

        set_canonical_cohort(monkeypatch, "uid-scope")
        with memory_system_request_scope("uid-scope") as pinned:
            assert pinned == MemorySystem.CANONICAL
            assert get_pinned_memory_system(uid="uid-scope") == MemorySystem.CANONICAL
        assert get_pinned_memory_system(uid="uid-scope") is None
        assert resolve_pinned_memory_system("uid-scope") == MemorySystem.CANONICAL

    def test_unpinned_resolve_matches_static_legacy_and_canonical(self, monkeypatch):
        from utils.memory.memory_system_pin import clear_memory_system_pin, resolve_pinned_memory_system

        from tests.unit.canonical_cohort_test_helpers import clear_canonical_cohort, set_canonical_cohort

        clear_memory_system_pin()
        clear_canonical_cohort(monkeypatch)
        assert resolve_pinned_memory_system("uid-legacy") == MemorySystem.LEGACY

        set_canonical_cohort(monkeypatch, "uid-canonical")
        assert resolve_pinned_memory_system("uid-canonical") == MemorySystem.CANONICAL
        assert resolve_pinned_memory_system("uid-other") == MemorySystem.LEGACY
