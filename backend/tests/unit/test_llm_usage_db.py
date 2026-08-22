"""
Unit tests for LLM usage database operations.
"""

import os
from pathlib import Path
from types import ModuleType
from unittest.mock import MagicMock, patch

import pytest

from testing.import_isolation import AutoMockModule, load_module_fresh, stub_modules

_BACKEND = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module", autouse=True)
def _llm_usage_module():
    google_pkg = ModuleType("google")
    google_pkg.__path__ = []  # type: ignore[attr-defined]
    google_cloud_pkg = ModuleType("google.cloud")
    google_cloud_pkg.__path__ = []  # type: ignore[attr-defined]
    firestore_stub = ModuleType("google.cloud.firestore")
    firestore_stub.Increment = lambda value: value
    firestore_stub.transactional = lambda fn: fn
    client_stub = AutoMockModule("database._client")
    client_stub.db = MagicMock()

    with stub_modules(
        {
            "google": google_pkg,
            "google.cloud": google_cloud_pkg,
            "google.cloud.firestore": firestore_stub,
            "database._client": client_stub,
        }
    ):
        module = load_module_fresh(
            "database.llm_usage",
            os.path.join(str(_BACKEND), "database", "llm_usage.py"),
        )
        globals()["llm_usage"] = module
        yield module


class _FakeDocSnapshot:
    def __init__(self, data, exists=True):
        self._data = data
        self.exists = exists

    def to_dict(self):
        return self._data


class _FakeDocRef:
    def __init__(self):
        self.set_calls = []

    def set(self, data, merge=False):
        self.set_calls.append({"data": data, "merge": merge})

    def get(self):
        return _FakeDocSnapshot({}, exists=False)


class _FakeCollection:
    def __init__(self, doc_ref=None):
        self._doc_ref = doc_ref or _FakeDocRef()

    def document(self, doc_id):
        return self._doc_ref

    def where(self, *args, **kwargs):
        return self


class _FakeUserRef:
    def __init__(self, collection):
        self._collection = collection

    def collection(self, name):
        return self._collection


def test_record_llm_usage_sanitizes_model_with_dots():
    """Test that model names with dots are sanitized."""
    doc_ref = _FakeDocRef()
    collection = _FakeCollection(doc_ref)
    user_ref = _FakeUserRef(collection)

    # Patch the db used by llm_usage module
    with patch.object(llm_usage, 'db') as patched_db:
        patched_db.collection.return_value.document.return_value = user_ref

        llm_usage.record_llm_usage(
            uid="test-user",
            feature="chat",
            model="gpt-4.1-mini",
            input_tokens=100,
            output_tokens=50,
        )

    assert len(doc_ref.set_calls) == 1
    call = doc_ref.set_calls[0]
    assert call["merge"] is True
    # Check that '.' is replaced with '_'
    assert "chat.gpt-4_1-mini.input_tokens" in call["data"]
    assert "chat.gpt-4_1-mini.output_tokens" in call["data"]


def test_record_llm_usage_sanitizes_model_with_slash():
    """Test that model names with slashes are sanitized (e.g., google/gemini-flash-1.5-8b)."""
    doc_ref = _FakeDocRef()
    collection = _FakeCollection(doc_ref)
    user_ref = _FakeUserRef(collection)

    with patch.object(llm_usage, 'db') as patched_db:
        patched_db.collection.return_value.document.return_value = user_ref

        llm_usage.record_llm_usage(
            uid="test-user",
            feature="chat",
            model="google/gemini-flash-1.5-8b",
            input_tokens=200,
            output_tokens=100,
        )

    assert len(doc_ref.set_calls) == 1
    call = doc_ref.set_calls[0]
    assert call["merge"] is True
    # Check that both '/' and '.' are replaced with '_'
    assert "chat.google_gemini-flash-1_5-8b.input_tokens" in call["data"]
    assert "chat.google_gemini-flash-1_5-8b.output_tokens" in call["data"]


def test_record_llm_usage_skips_zero_tokens():
    """Test that zero token usage is not recorded."""
    doc_ref = _FakeDocRef()

    with patch.object(llm_usage, 'db') as patched_db:
        llm_usage.record_llm_usage(
            uid="test-user",
            feature="chat",
            model="gpt-4.1-mini",
            input_tokens=0,
            output_tokens=0,
        )

    assert len(doc_ref.set_calls) == 0


def test_get_daily_usage_returns_empty_when_not_exists():
    """Test that get_daily_usage returns empty dict when no data exists."""
    mock_doc = _FakeDocSnapshot({}, exists=False)
    doc_ref = MagicMock()
    doc_ref.get.return_value = mock_doc

    with patch.object(llm_usage, 'db') as patched_db:
        patched_db.collection.return_value.document.return_value.collection.return_value.document.return_value = doc_ref

        result = llm_usage.get_daily_usage("test-user")

    assert result == {}


def test_get_daily_usage_returns_data_when_exists():
    """Test that get_daily_usage returns data when it exists."""
    expected_data = {
        "chat": {"gpt-4_1-mini": {"input_tokens": 100, "output_tokens": 50}},
        "last_updated": "2026-01-27T00:00:00Z",
    }
    mock_doc = _FakeDocSnapshot(expected_data, exists=True)
    doc_ref = MagicMock()
    doc_ref.get.return_value = mock_doc

    with patch.object(llm_usage, 'db') as patched_db:
        patched_db.collection.return_value.document.return_value.collection.return_value.document.return_value = doc_ref

        result = llm_usage.get_daily_usage("test-user")

    assert result == expected_data


def test_record_llm_usage_sanitizes_all_special_chars():
    """Test that all Firestore-disallowed characters are sanitized: . / ~ * [ ] `."""
    doc_ref = _FakeDocRef()
    collection = _FakeCollection(doc_ref)
    user_ref = _FakeUserRef(collection)

    with patch.object(llm_usage, 'db') as patched_db:
        patched_db.collection.return_value.document.return_value = user_ref

        llm_usage.record_llm_usage(
            uid="test-user",
            feature="chat",
            model="foo/bar~baz*qux[quux]corge`grault.garply",
            input_tokens=10,
            output_tokens=5,
        )

    assert len(doc_ref.set_calls) == 1
    call = doc_ref.set_calls[0]
    # All special chars should be replaced with '_'
    assert "chat.foo_bar_baz_qux_quux_corge_grault_garply.input_tokens" in call["data"]


def test_record_llm_usage_nonzero_input_only():
    """Test that usage is recorded when only input tokens are non-zero."""
    doc_ref = _FakeDocRef()
    collection = _FakeCollection(doc_ref)
    user_ref = _FakeUserRef(collection)

    with patch.object(llm_usage, 'db') as patched_db:
        patched_db.collection.return_value.document.return_value = user_ref

        llm_usage.record_llm_usage(
            uid="test-user",
            feature="rag",
            model="gpt-4",
            input_tokens=100,
            output_tokens=0,
        )

    assert len(doc_ref.set_calls) == 1


def test_record_llm_usage_nonzero_output_only():
    """Test that usage is recorded when only output tokens are non-zero."""
    doc_ref = _FakeDocRef()
    collection = _FakeCollection(doc_ref)
    user_ref = _FakeUserRef(collection)

    with patch.object(llm_usage, 'db') as patched_db:
        patched_db.collection.return_value.document.return_value = user_ref

        llm_usage.record_llm_usage(
            uid="test-user",
            feature="rag",
            model="gpt-4",
            input_tokens=0,
            output_tokens=50,
        )

    assert len(doc_ref.set_calls) == 1
