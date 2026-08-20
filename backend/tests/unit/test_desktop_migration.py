"""Tests for the desktop Python backend CRUD migration (PR #6175).

Covers:
1. Pydantic request validation (boundary tests for all desktop models)
2. Wire-compatibility (notification settings field mapping, assistant settings
   deep-merge, message field expectations)
3. Score computation (weekly uses created_at, default_tab logic)
4. LLM usage (dual-write, cost-only sums desktop_chat bucket)
5. Batch limit (commit triggers at BATCH_LIMIT=500)
"""

import os
import sys
import types
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
BACKEND_DIR = Path(__file__).resolve().parent.parent.parent

os.environ.setdefault(
    "ENCRYPTION_SECRET",
    "omi_ZwB2ZNqB2HHpMK6wStk7sTpavJiPTFg7gXUHnc4tFABPU6pZ2c2DKgehtfgi4RZv",
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _stub_module(name):
    mod = types.ModuleType(name)
    sys.modules[name] = mod
    return mod


def _stub_package(name):
    mod = types.ModuleType(name)
    mod.__path__ = []
    sys.modules[name] = mod
    return mod


def _remove_module_tree(prefix):
    for name in list(sys.modules):
        if name == prefix or name.startswith(prefix + "."):
            sys.modules.pop(name, None)


def _ensure_package_path(name, path):
    mod = sys.modules.get(name)
    if not isinstance(mod, types.ModuleType):
        mod = types.ModuleType(name)
        sys.modules[name] = mod
    mod.__path__ = [str(path)]
    return mod


# ---------------------------------------------------------------------------
# Stub heavy dependencies before any production imports
# ---------------------------------------------------------------------------
for module_prefix in [
    "database",
    "models",
    "utils",
    "routers.chat_sessions",
    "routers.focus_sessions",
    "routers.advice",
]:
    _remove_module_tree(module_prefix)

for mod_name in [
    "firebase_admin",
    "firebase_admin.firestore",
    "firebase_admin.auth",
    "firebase_admin.messaging",
    "firebase_admin.credentials",
    "google.cloud.firestore",
    "google.cloud.firestore_v1",
    "google.cloud.firestore_v1.base_query",
    "google.auth",
    "google.auth.transport",
    "google.auth.transport.requests",
    "google.cloud.storage",
    "opuslib",
    "sentry_sdk",
    "database.redis_db",
    "database.auth",
    "utils.llm",
    "utils.llm.clients",
]:
    if mod_name not in sys.modules:
        _stub_module(mod_name)

sys.modules["utils.llm.clients"].get_llm = MagicMock()
usage_tracker_stub = _stub_module("utils.llm.usage_tracker")


class _Features:
    CHAT = "chat"


usage_tracker_stub.Features = _Features
usage_tracker_stub.track_usage = MagicMock()

# Stub google.cloud.firestore sentinels
firestore_stub = sys.modules["google.cloud.firestore"]
firestore_stub.Increment = lambda x: f"__increment_{x}__"
firestore_stub.ArrayRemove = lambda values: ("__array_remove__", tuple(values))
firestore_stub.Query = MagicMock()
firestore_stub.Query.ASCENDING = "ASCENDING"
firestore_stub.Query.DESCENDING = "DESCENDING"
firestore_stub.Client = MagicMock

# Stub FieldFilter
field_filter_stub = sys.modules["google.cloud.firestore_v1.base_query"]
field_filter_stub.FieldFilter = MagicMock()
sys.modules["google.cloud.firestore_v1"].FieldFilter = field_filter_stub.FieldFilter
sys.modules["google.cloud.firestore_v1"].transactional = lambda f: f

redis_stub = sys.modules["database.redis_db"]
redis_stub.r = MagicMock()
setattr(redis_stub, 'try_acquire_client_device_write_lock', MagicMock(return_value=True))
redis_stub.try_acquire_user_platform_write_lock = MagicMock(return_value=True)

# Add backend dir to sys.path
sys.path.insert(0, str(BACKEND_DIR))

# Stub database package and _client
_ensure_package_path("database", BACKEND_DIR / "database")

client_stub = _stub_module("database._client")
mock_db = MagicMock()
client_stub.db = mock_db
client_stub.delete_collection_recursive = MagicMock()
client_stub.document_id_from_seed = MagicMock(return_value="seed-id")
client_stub.get_firestore_client = MagicMock(return_value=mock_db)

# Stub database.helpers (used by chat.py)
helpers_stub = _stub_module("database.helpers")
helpers_stub.set_data_protection_level = lambda **kw: (lambda f: f)
helpers_stub.prepare_for_write = lambda **kw: (lambda f: f)
helpers_stub.prepare_for_read = lambda **kw: (lambda f: f)

# Stub models and utils needed by database.users and database.chat
_ensure_package_path("models", BACKEND_DIR / "models")
models_users_stub = _stub_module("models.users")
models_users_stub.Subscription = MagicMock()
models_users_stub.PlanLimits = MagicMock()
models_users_stub.PlanType = MagicMock()
models_users_stub.SubscriptionStatus = MagicMock()

_stub_package("utils")
_stub_package("utils.other")
utils_sub_stub = _stub_module("utils.subscription")
utils_sub_stub.get_default_free_subscription = MagicMock()
utils_enc_stub = _stub_module("utils.encryption")
utils_enc_stub.encrypt = MagicMock(return_value="encrypted")
utils_enc_stub.decrypt = MagicMock(return_value="decrypted")
endpoints_stub = _stub_module("utils.other.endpoints")
endpoints_stub.get_current_user_uid = MagicMock()
endpoints_stub.with_rate_limit = lambda dep, policy: dep
endpoints_stub.timeit = lambda f: f
_stub_module("utils.observability")
fallback_stub = _stub_module("utils.observability.fallback")
fallback_stub.record_fallback = MagicMock()
request_validation_stub = _stub_module("utils.request_validation")
request_validation_stub.validate_calendar_date = lambda value, field_name='date': value
redis_stub = _stub_module("database.redis_db")
redis_stub.r = MagicMock()
setattr(redis_stub, 'try_acquire_client_device_write_lock', MagicMock(return_value=True))
redis_stub.try_acquire_user_platform_write_lock = MagicMock(return_value=True)

# ---------------------------------------------------------------------------
# Import domain-specific database modules
# ---------------------------------------------------------------------------
import database.users as users_db  # noqa: E402
import database.chat as chat_db  # noqa: E402
import database.llm_usage as llm_usage_db  # noqa: E402

# ---------------------------------------------------------------------------
# Import Pydantic models from lightweight router files
# ---------------------------------------------------------------------------
from pydantic import BaseModel, Field, ValidationError  # noqa: E402

from routers.focus_sessions import CreateFocusSessionRequest  # noqa: E402
from routers.advice import CreateAdviceRequest  # noqa: E402

_ensure_package_path("models", BACKEND_DIR / "models")
_ensure_package_path("utils", BACKEND_DIR / "utils")
_ensure_package_path("utils.other", BACKEND_DIR / "utils" / "other")

# Cannot import routers.users directly — it pulls in database.conversations → utils.other.hume
# which has heavy deps. Mirror the models here and verify parity via AST test below.


class UpdateNotificationSettingsRequest(BaseModel):
    enabled: bool | None = None
    frequency: int | None = Field(None, ge=0, le=5)


class RecordLlmUsageBucketRequest(BaseModel):
    input_tokens: int = Field(0, ge=0)
    output_tokens: int = Field(0, ge=0)
    cache_read_tokens: int = Field(0, ge=0)
    cache_write_tokens: int = Field(0, ge=0)
    total_tokens: int = Field(0, ge=0)
    cost_usd: float = Field(0.0, ge=0.0)
    account: str = Field('omi', max_length=100)


# ===========================================================================
# 1. PYDANTIC REQUEST VALIDATION (boundary tests)
# ===========================================================================


class TestUpdateNotificationSettingsValidation:
    def test_frequency_6_fails(self):
        """UpdateNotificationSettingsRequest with frequency=6 (max is 5) should fail."""
        with pytest.raises(ValidationError) as exc_info:
            UpdateNotificationSettingsRequest(frequency=6)
        assert 'frequency' in str(exc_info.value)

    def test_frequency_5_passes(self):
        r = UpdateNotificationSettingsRequest(frequency=5)
        assert r.frequency == 5

    def test_frequency_0_passes(self):
        r = UpdateNotificationSettingsRequest(frequency=0)
        assert r.frequency == 0


class TestRecordDesktopLlmUsageValidation:
    def test_negative_tokens_fails(self):
        """RecordLlmUsageBucketRequest with negative tokens should fail."""
        with pytest.raises(ValidationError) as exc_info:
            RecordLlmUsageBucketRequest(input_tokens=-1)
        assert 'input_tokens' in str(exc_info.value)

    def test_negative_output_tokens_fails(self):
        with pytest.raises(ValidationError) as exc_info:
            RecordLlmUsageBucketRequest(output_tokens=-5)
        assert 'output_tokens' in str(exc_info.value)

    def test_default_account_is_omi(self):
        """RecordLlmUsageBucketRequest default account is 'omi'."""
        r = RecordLlmUsageBucketRequest()
        assert r.account == 'omi'

    def test_all_defaults_zero(self):
        """All token fields default to 0."""
        r = RecordLlmUsageBucketRequest()
        assert r.input_tokens == 0
        assert r.output_tokens == 0
        assert r.cache_read_tokens == 0
        assert r.total_tokens == 0
        assert r.cost_usd == 0.0


class TestCreateFocusSessionValidation:
    def test_invalid_status_fails(self):
        """CreateFocusSessionRequest with status not focused/distracted should fail."""
        with pytest.raises(ValidationError) as exc_info:
            CreateFocusSessionRequest(status='idle', app_or_site='Chrome', description='browsing')
        assert 'status' in str(exc_info.value)

    def test_valid_focused(self):
        r = CreateFocusSessionRequest(status='focused', app_or_site='VSCode', description='coding')
        assert r.status == 'focused'

    def test_valid_distracted(self):
        r = CreateFocusSessionRequest(status='distracted', app_or_site='Twitter', description='scrolling')
        assert r.status == 'distracted'


class TestCreateAdviceValidation:
    def test_confidence_above_1_fails(self):
        """CreateAdviceRequest with confidence > 1.0 should fail."""
        with pytest.raises(ValidationError) as exc_info:
            CreateAdviceRequest(content='take a break', confidence=1.5)
        assert 'confidence' in str(exc_info.value)

    def test_confidence_below_0_fails(self):
        with pytest.raises(ValidationError) as exc_info:
            CreateAdviceRequest(content='take a break', confidence=-0.1)
        assert 'confidence' in str(exc_info.value)

    def test_confidence_1_passes(self):
        r = CreateAdviceRequest(content='take a break', confidence=1.0)
        assert r.confidence == 1.0

    def test_confidence_default_is_half(self):
        r = CreateAdviceRequest(content='take a break')
        assert r.confidence == 0.5


# ===========================================================================
# 2. WIRE-COMPATIBILITY TESTS (mock Firestore)
# ===========================================================================


class TestNotificationSettingsWireCompat:
    """Verify notification settings return Swift-compatible field names."""

    def _mock_user_doc(self, data, exists=True):
        """Create a mock user doc snapshot."""
        snap = MagicMock()
        snap.exists = exists
        snap.to_dict.return_value = data
        return snap

    def test_returns_enabled_and_frequency_keys(self):
        """get_notification_settings returns 'enabled'/'frequency' not 'notifications_enabled'."""
        snap = self._mock_user_doc({'notifications_enabled': False, 'notification_frequency': 2})
        mock_db.collection.return_value.document.return_value.get.return_value = snap
        result = users_db.get_notification_settings('test-uid')

        assert 'enabled' in result
        assert 'frequency' in result
        assert 'notifications_enabled' not in result
        assert 'notification_frequency' not in result
        assert result['enabled'] is False
        assert result['frequency'] == 2

    def test_defaults_frequency_to_off_when_unset(self):
        """Frequency defaults to 0 (Off) when the user doc has no notification_frequency."""
        snap = self._mock_user_doc({})
        mock_db.collection.return_value.document.return_value.get.return_value = snap
        result = users_db.get_notification_settings('test-uid')

        assert result['frequency'] == 0
        assert result['enabled'] is True

    def test_defaults_when_doc_missing(self):
        """Returns defaults when user doc doesn't exist."""
        snap = self._mock_user_doc({}, exists=False)
        mock_db.collection.return_value.document.return_value.get.return_value = snap
        result = users_db.get_notification_settings('test-uid')

        assert result == {'enabled': True, 'frequency': 0}


class TestAssistantSettingsWireCompat:
    """Verify assistant settings deep-merge and update_channel handling."""

    def _mock_user_doc(self, data, exists=True):
        snap = MagicMock()
        snap.exists = exists
        snap.to_dict.return_value = data
        return snap

    def test_get_includes_update_channel(self):
        """get_assistant_settings includes top-level update_channel from user doc."""
        snap = self._mock_user_doc(
            {
                'assistant_settings': {'focus': {'enabled': True}},
                'update_channel': 'beta',
            }
        )
        mock_db.collection.return_value.document.return_value.get.return_value = snap
        result = users_db.get_assistant_settings('test-uid')

        assert result['update_channel'] == 'beta'
        assert result['focus'] == {'enabled': True}

    def test_deep_merge_preserves_sibling_sections(self):
        """update_assistant_settings deep-merges without destroying sibling sections."""
        existing_data = {
            'assistant_settings': {
                'focus': {'enabled': True, 'cooldown_interval': 30},
                'task': {'enabled': False},
            },
        }
        snap = self._mock_user_doc(existing_data)
        mock_db.collection.return_value.document.return_value.get.return_value = snap
        result = users_db.update_assistant_settings('test-uid', {'focus': {'enabled': False}})

        # focus.enabled should be updated, but focus.cooldown_interval preserved
        assert result['focus']['enabled'] is False
        assert result['focus']['cooldown_interval'] == 30
        # task section should be untouched
        assert result['task'] == {'enabled': False}

    def test_update_channel_written_to_top_level(self):
        """update_assistant_settings writes update_channel to top-level, not inside assistant_settings."""
        snap = self._mock_user_doc({'assistant_settings': {}})
        captured_updates = {}

        def capture_update(data):
            import copy

            captured_updates.update(copy.deepcopy(data))

        mock_ref = mock_db.collection.return_value.document.return_value
        mock_ref.get.return_value = snap
        mock_ref.update.side_effect = capture_update
        users_db.update_assistant_settings('test-uid', {'update_channel': 'beta'})

        assert 'update_channel' in captured_updates
        assert captured_updates['update_channel'] == 'beta'
        assert 'update_channel' not in captured_updates.get('assistant_settings', {})

    def test_raw_assistant_settings_excludes_update_channel(self):
        """_get_raw_assistant_settings does NOT include update_channel."""
        snap = self._mock_user_doc(
            {
                'assistant_settings': {'focus': {'enabled': True}},
                'update_channel': 'beta',
            }
        )
        mock_db.collection.return_value.document.return_value.get.return_value = snap
        result = users_db._get_raw_assistant_settings('test-uid')

        assert 'update_channel' not in result
        assert result == {'focus': {'enabled': True}}


class TestLlmUsageBucketParam:
    """Verify configurable bucket parameter in LLM usage functions."""

    def test_custom_bucket_dual_writes(self):
        """record_llm_usage_bucket with custom bucket writes to both bucket and bucket_account."""
        mock_ref = MagicMock()

        with patch.object(llm_usage_db, 'db') as patched_db:
            patched_db.collection.return_value.document.return_value.collection.return_value.document.return_value = (
                mock_ref
            )
            llm_usage_db.record_llm_usage_bucket(
                'uid',
                input_tokens=10,
                output_tokens=20,
                bucket='custom_feature',
                account='openai',
            )

        set_call = mock_ref.set.call_args
        update_data = set_call[0][0]
        # Primary bucket
        assert 'custom_feature.input_tokens' in update_data
        assert 'custom_feature.output_tokens' in update_data
        assert 'custom_feature.call_count' in update_data
        # Per-account bucket
        assert 'custom_feature_openai.input_tokens' in update_data
        assert 'custom_feature_openai.output_tokens' in update_data

    def test_get_total_llm_cost_custom_bucket(self):
        """get_total_llm_cost with custom bucket reads from the specified bucket only."""
        mock_doc1 = MagicMock()
        mock_doc1.to_dict.return_value = {
            'custom_feature': {'cost_usd': 0.5},
            'custom_feature_openai': {'cost_usd': 0.5},  # Should NOT be double-counted
            'desktop_chat': {'cost_usd': 1.0},  # Different bucket, should be excluded
        }
        mock_col = MagicMock()
        mock_col.stream.return_value = [mock_doc1]

        with patch.object(llm_usage_db, 'db') as patched_db:
            patched_db.collection.return_value.document.return_value.collection.return_value = mock_col
            result = llm_usage_db.get_total_llm_cost('uid', bucket='custom_feature')

        assert result == 0.5  # Only custom_feature, not custom_feature_openai or desktop_chat


# 4. LLM USAGE TESTS (mock Firestore)
# ===========================================================================


class TestLlmUsage:
    """Verify LLM usage dual-write and cost summation."""

    def test_record_dual_writes_desktop_chat_and_account(self):
        """record_llm_usage_bucket dual-writes both 'desktop_chat' and 'desktop_chat_{account}'."""
        mock_ref = MagicMock()
        with patch.object(llm_usage_db, 'db') as patched_db:
            patched_db.collection.return_value.document.return_value.collection.return_value.document.return_value = (
                mock_ref
            )
            llm_usage_db.record_llm_usage_bucket(
                'test-uid',
                input_tokens=100,
                output_tokens=50,
                account='anthropic',
            )

        # Verify set(merge=True) was called
        mock_ref.set.assert_called_once()
        update_data = mock_ref.set.call_args[0][0]
        assert mock_ref.set.call_args[1] == {'merge': True}

        # Must have both desktop_chat and desktop_chat_anthropic keys
        desktop_chat_keys = [k for k in update_data if k.startswith('desktop_chat.')]
        desktop_chat_acct_keys = [k for k in update_data if k.startswith('desktop_chat_anthropic.')]
        assert len(desktop_chat_keys) > 0, "Missing desktop_chat.* keys"
        assert len(desktop_chat_acct_keys) > 0, "Missing desktop_chat_anthropic.* keys"

        # Verify input_tokens increment is present for both buckets
        assert 'desktop_chat.input_tokens' in update_data
        assert 'desktop_chat_anthropic.input_tokens' in update_data

    def test_record_default_account_omi(self):
        """Default account produces desktop_chat_omi keys."""
        mock_ref = MagicMock()
        with patch.object(llm_usage_db, 'db') as patched_db:
            patched_db.collection.return_value.document.return_value.collection.return_value.document.return_value = (
                mock_ref
            )
            llm_usage_db.record_llm_usage_bucket('test-uid', input_tokens=10, output_tokens=5)

        update_data = mock_ref.set.call_args[0][0]
        assert 'desktop_chat_omi.input_tokens' in update_data

    def test_get_total_cost_only_sums_desktop_chat_bucket(self):
        """get_total_llm_cost only sums the desktop_chat bucket, not desktop_chat_{account}."""
        doc1 = MagicMock()
        doc1.to_dict.return_value = {
            'desktop_chat': {'cost_usd': 0.05, 'call_count': 10},
            'desktop_chat_anthropic': {'cost_usd': 0.05, 'call_count': 10},
        }
        doc2 = MagicMock()
        doc2.to_dict.return_value = {
            'desktop_chat': {'cost_usd': 0.03, 'call_count': 5},
            'desktop_chat_omi': {'cost_usd': 0.03, 'call_count': 5},
        }

        mock_col = MagicMock()
        mock_col.stream.return_value = [doc1, doc2]

        with patch.object(llm_usage_db, 'db') as patched_db:
            patched_db.collection.return_value.document.return_value.collection.return_value = mock_col
            total = llm_usage_db.get_total_llm_cost('test-uid')

        # Should only sum desktop_chat: 0.05 + 0.03 = 0.08
        assert total == round(0.08, 6)

    def test_get_total_cost_ignores_non_dict_desktop_chat(self):
        """get_total_llm_cost handles docs where desktop_chat is not a dict."""
        doc1 = MagicMock()
        doc1.to_dict.return_value = {'desktop_chat': 'corrupted', 'other_key': 123}
        doc2 = MagicMock()
        doc2.to_dict.return_value = {'desktop_chat': {'cost_usd': 0.01}}

        mock_col = MagicMock()
        mock_col.stream.return_value = [doc1, doc2]

        with patch.object(llm_usage_db, 'db') as patched_db:
            patched_db.collection.return_value.document.return_value.collection.return_value = mock_col
            total = llm_usage_db.get_total_llm_cost('test-uid')

        assert total == 0.01


import database.focus_sessions as focus_sessions_db


class TestFocusStatsWireCompat:
    """Verify focus stats returns FocusStatsResponse shape expected by Swift client."""

    def test_focus_stats_has_all_required_fields(self):
        """get_focus_stats returns date, focused_minutes, distracted_minutes, session_count, etc."""
        with patch.object(focus_sessions_db, 'get_focus_sessions', return_value=[]):
            result = focus_sessions_db.get_focus_stats('test-uid', date='2025-01-15')

        required_keys = {
            'date',
            'focused_minutes',
            'distracted_minutes',
            'session_count',
            'focused_count',
            'distracted_count',
            'top_distractions',
        }
        assert required_keys.issubset(result.keys()), f"Missing keys: {required_keys - result.keys()}"

    def test_focus_stats_computes_minutes(self):
        """Focused/distracted times are reported in minutes."""
        sessions = [
            {'status': 'focused', 'duration_seconds': 300},
            {'status': 'focused', 'duration_seconds': 180},
            {'status': 'distracted', 'duration_seconds': 120, 'app_or_site': 'Twitter'},
        ]
        with patch.object(focus_sessions_db, 'get_focus_sessions', return_value=sessions):
            result = focus_sessions_db.get_focus_stats('test-uid', date='2025-01-15')

        assert result['focused_minutes'] == 8  # (300+180)//60
        assert result['distracted_minutes'] == 2  # 120//60
        assert result['session_count'] == 3
        assert result['focused_count'] == 2
        assert result['distracted_count'] == 1
        assert result['date'] == '2025-01-15'

    def test_top_distractions_is_list_of_dicts(self):
        """top_distractions must be list of {app_or_site, total_seconds, count} dicts, not tuples."""
        sessions = [
            {'status': 'distracted', 'duration_seconds': 120, 'app_or_site': 'Twitter'},
            {'status': 'distracted', 'duration_seconds': 60, 'app_or_site': 'Twitter'},
            {'status': 'distracted', 'duration_seconds': 300, 'app_or_site': 'Reddit'},
        ]
        with patch.object(focus_sessions_db, 'get_focus_sessions', return_value=sessions):
            result = focus_sessions_db.get_focus_stats('test-uid', date='2025-01-15')

        distractions = result['top_distractions']
        assert isinstance(distractions, list)
        assert len(distractions) == 2

        # Sorted by total_seconds descending: Reddit (300) > Twitter (180)
        assert distractions[0]['app_or_site'] == 'Reddit'
        assert distractions[0]['total_seconds'] == 300
        assert distractions[0]['count'] == 1
        assert distractions[1]['app_or_site'] == 'Twitter'
        assert distractions[1]['total_seconds'] == 180
        assert distractions[1]['count'] == 2


# ===========================================================================
# 8. MODEL PARITY (inline models match routers/users.py source)
# ===========================================================================


class TestModelParity:
    """Verify inline test models match the real router models via AST."""

    def test_notification_settings_fields_match_source(self):
        """Inline UpdateNotificationSettingsRequest matches routers/users.py definition."""
        import ast

        source = (BACKEND_DIR / 'routers' / 'users.py').read_text(encoding='utf-8')
        tree = ast.parse(source)
        for node in ast.walk(tree):
            if isinstance(node, ast.ClassDef) and node.name == 'UpdateNotificationSettingsRequest':
                field_names = [
                    stmt.target.id
                    for stmt in node.body
                    if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name)
                ]
                break
        else:
            pytest.fail("UpdateNotificationSettingsRequest not found in routers/users.py")
        expected = [f.alias or name for name, f in UpdateNotificationSettingsRequest.model_fields.items()]
        assert set(field_names) == set(expected), f"Field mismatch: source={field_names} test={expected}"


# ===========================================================================
# 9. RATING=0 BOUNDARY (route rejects 0 despite model allowing it)
# ===========================================================================


# TESTER-REQUESTED: Focus-stats duration_seconds=0 boundary
# ============================================================================


class TestFocusStatsDurationBoundary:
    """Verify duration_seconds=0 and missing duration behavior."""

    def test_distracted_zero_duration_treated_as_default(self):
        """duration_seconds=0 is treated as 60 via `or 60` in get_focus_stats."""
        sessions = [{'status': 'distracted', 'app_or_site': 'Twitter', 'duration_seconds': 0}]
        with patch.object(focus_sessions_db, 'get_focus_sessions', return_value=sessions):
            result = focus_sessions_db.get_focus_stats('uid', '2026-04-06')
        # duration_seconds=0 is falsy, so `or 60` defaults to 60
        assert result['distracted_minutes'] == 1  # 60 seconds = 1 minute

    def test_distracted_missing_duration_treated_as_default(self):
        """Missing duration_seconds defaults to 60 via `or 60`."""
        sessions = [{'status': 'distracted', 'app_or_site': 'Reddit'}]
        with patch.object(focus_sessions_db, 'get_focus_sessions', return_value=sessions):
            result = focus_sessions_db.get_focus_stats('uid', '2026-04-06')
        assert result['distracted_minutes'] == 1

    def test_focused_zero_duration_is_zero(self):
        """Focused sessions with duration_seconds=0 contribute 0 minutes."""
        sessions = [{'status': 'focused', 'duration_seconds': 0}]
        with patch.object(focus_sessions_db, 'get_focus_sessions', return_value=sessions):
            result = focus_sessions_db.get_focus_stats('uid', '2026-04-06')
        assert result['focused_minutes'] == 0


# TESTER-REQUESTED: LLM dual-write full payload parity
# ============================================================================


class TestLlmDualWritePayloadParity:
    """Verify all fields are written to both primary and per-account buckets."""

    def test_all_fields_written_to_both_buckets(self):
        """record_llm_usage_bucket writes all fields to both desktop_chat and desktop_chat_omi in single set()."""
        mock_ref = MagicMock()
        with patch.object(llm_usage_db, 'db') as patched_db:
            patched_db.collection.return_value.document.return_value.collection.return_value.document.return_value = (
                mock_ref
            )
            llm_usage_db.record_llm_usage_bucket(
                uid='uid',
                input_tokens=100,
                output_tokens=50,
                cache_read_tokens=20,
                cache_write_tokens=10,
                total_tokens=180,
                cost_usd=0.05,
                bucket='desktop_chat',
                account='omi',
            )

        # Single set(merge=True) call containing both bucket prefixes
        mock_ref.set.assert_called_once()
        data = mock_ref.set.call_args[0][0]

        # Check all fields for primary bucket
        expected_fields = [
            'input_tokens',
            'output_tokens',
            'cache_read_tokens',
            'cache_write_tokens',
            'total_tokens',
            'cost_usd',
            'call_count',
        ]
        for field in expected_fields:
            assert f'desktop_chat.{field}' in data, f"Missing desktop_chat.{field}"
            assert f'desktop_chat_omi.{field}' in data, f"Missing desktop_chat_omi.{field}"

        # Verify shared metadata fields
        assert 'date' in data
        assert 'last_updated' in data


# ============================================================================
