"""
Level 1 live test: fair-use API endpoints via FastAPI TestClient.

Tests the protected fair-use support endpoints with fixture-scoped policy state.
"""

import os
import sys
import time
import types
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

import pytest
import fakeredis

# In-memory fair_use DB. The autouse ``cleanup`` fixture installs fakes that read
# and write here, replacing the former module-scope ``sys.modules`` stubs.
_state_store = {}
_events = []

# Stand-in for ``database._client.db`` consumed by the admin router's case-lookup
# endpoints. The autouse fixture patches ``routers.fair_use_admin.db`` to this mock
# so individual tests can drive ``collection_group`` via ``patch.object``.
_fake_db = MagicMock()

from fastapi import FastAPI
from fastapi.testclient import TestClient

import database.fair_use as _fair_use_db_module
import routers.fair_use_admin as _admin_module
import utils.fair_use as fair_use

# Import the router
from routers.fair_use_admin import router as admin_router

app = FastAPI()
app.include_router(admin_router)
client = TestClient(app)

TEST_UID = f'api_test_{int(time.time())}'
ADMIN_HEADERS = {'X-Admin-Key': 'test-admin-key-12345'}


def _cleanup():
    _state_store.clear()
    _events.clear()
    try:
        fair_use.redis_client.delete(
            fair_use._redis_key(TEST_UID),
            f'fair_use:bucket:{TEST_UID}',
            f'fair_use:stage:{TEST_UID}',
            f'fair_use:vad_delta:{TEST_UID}',
        )
    except Exception:
        pass


@pytest.fixture(autouse=True)
def cleanup(monkeypatch):
    """Install in-memory fakes for ``database.fair_use`` and patch the admin router's ``db``.

    Replaces the former module-scope ``sys.modules`` stubs with fixture-scoped
    ``monkeypatch.setattr`` (the sanctioned Tier-2 seam). Test bodies and assertions
    are unchanged.
    """
    monkeypatch.setattr(fair_use, 'redis_client', fakeredis.FakeRedis())
    monkeypatch.setattr(fair_use, 'FAIR_USE_ENABLED', True)
    monkeypatch.setattr(_admin_module, 'ADMIN_KEY', 'test-admin-key-12345')
    monkeypatch.setattr(_admin_module, 'FAIR_USE_ENABLED', True)
    monkeypatch.setattr(_fair_use_db_module, 'get_fair_use_state', lambda uid: _state_store.get(uid, {}))
    monkeypatch.setattr(
        _fair_use_db_module, 'update_fair_use_state', lambda uid, u: _state_store.setdefault(uid, {}).update(u)
    )
    monkeypatch.setattr(
        _fair_use_db_module,
        'create_fair_use_event',
        lambda uid, d: (_events.append({**d, 'uid': uid}), f'evt-{len(_events)}')[1],
    )
    monkeypatch.setattr(
        _fair_use_db_module,
        'get_fair_use_events',
        lambda uid, limit=50: [e for e in _events if e.get('uid') == uid][:limit],
    )
    monkeypatch.setattr(
        _fair_use_db_module, 'get_violation_counts', lambda uid: {'violation_count_7d': 0, 'violation_count_30d': 0}
    )
    monkeypatch.setattr(_fair_use_db_module, 'resolve_fair_use_event', lambda uid, eid, admin_uid='', notes='': None)
    monkeypatch.setattr(
        _fair_use_db_module, 'reset_fair_use_state', lambda uid, admin_uid='': _state_store.pop(uid, None)
    )
    monkeypatch.setattr(_fair_use_db_module, 'get_flagged_users', lambda stage_filter=None, limit=50: [])
    monkeypatch.setattr(_admin_module, 'db', _fake_db)

    _cleanup()
    yield
    _cleanup()


class TestAdminEndpoints:
    """Test admin fair-use endpoints."""

    def test_exactly_six_protected_support_operations_remain(self):
        operations = {
            (method, route.path)
            for route in admin_router.routes
            for method in route.methods
            if route.path.startswith('/v1/admin/fair-use')
        }
        assert operations == {
            ('GET', '/v1/admin/fair-use/flagged'),
            ('GET', '/v1/admin/fair-use/user/{uid}'),
            ('POST', '/v1/admin/fair-use/user/{uid}/resolve-event/{event_id}'),
            ('POST', '/v1/admin/fair-use/user/{uid}/reset'),
            ('POST', '/v1/admin/fair-use/user/{uid}/set-stage'),
            ('GET', '/v1/admin/fair-use/case/{case_ref}'),
        }

    @pytest.mark.parametrize(
        ('method', 'path'),
        [
            ('GET', '/v1/admin/fair-use/flagged'),
            ('GET', f'/v1/admin/fair-use/user/{TEST_UID}'),
            ('POST', f'/v1/admin/fair-use/user/{TEST_UID}/resolve-event/event-1'),
            ('POST', f'/v1/admin/fair-use/user/{TEST_UID}/reset'),
            ('POST', f'/v1/admin/fair-use/user/{TEST_UID}/set-stage?stage=warning'),
            ('GET', '/v1/admin/fair-use/case/FU-AABBCCDDEEFF'),
        ],
    )
    def test_every_support_operation_requires_the_admin_key(self, method, path):
        assert client.request(method, path).status_code == 422
        assert client.request(method, path, headers={'X-Admin-Key': 'wrong'}).status_code == 403

    def test_get_flagged_users(self):
        """GET /v1/admin/fair-use/flagged returns users list."""
        resp = client.get('/v1/admin/fair-use/flagged', headers=ADMIN_HEADERS)
        assert resp.status_code == 200
        data = resp.json()
        assert 'users' in data
        assert 'fair_use_enabled' in data
        assert data['fair_use_enabled'] is True

    def test_flagged_users_requires_admin_key(self):
        """GET without admin key should 422 (missing header)."""
        resp = client.get('/v1/admin/fair-use/flagged')
        assert resp.status_code == 422

    def test_flagged_users_rejects_bad_key(self):
        """GET with wrong admin key should 403."""
        resp = client.get('/v1/admin/fair-use/flagged', headers={'X-Admin-Key': 'wrong'})
        assert resp.status_code == 403

    def test_get_user_detail(self):
        """GET /v1/admin/fair-use/user/{uid} returns state + speech."""
        fair_use.record_speech_ms(TEST_UID, 5000)

        resp = client.get(f'/v1/admin/fair-use/user/{TEST_UID}', headers=ADMIN_HEADERS)
        assert resp.status_code == 200
        data = resp.json()
        assert data['uid'] == TEST_UID
        assert 'current_speech_ms' in data
        assert data['current_speech_ms']['daily_ms'] == 5000

    def test_support_detail_strips_content_bearing_legacy_event_fields(self):
        _events.append(
            {
                'uid': TEST_UID,
                'review_id': 'review-1',
                'classifier_score': 0.91,
                'title': 'must not leave durable support boundary',
                'overview': 'must not leave durable support boundary',
                'reasoning': 'must not leave durable support boundary',
                'classifier': {'evidence': [{'conversation_id': 'local-id'}]},
            }
        )

        response = client.get(f'/v1/admin/fair-use/user/{TEST_UID}', headers=ADMIN_HEADERS)

        assert response.status_code == 200
        event = response.json()['events'][0]
        assert event['review_id'] == 'review-1'
        assert event['classifier_score'] == 0.91
        assert not {'title', 'overview', 'reasoning', 'classifier'} & event.keys()

    def test_set_stage(self):
        """POST /v1/admin/fair-use/user/{uid}/set-stage updates stage."""
        resp = client.post(
            f'/v1/admin/fair-use/user/{TEST_UID}/set-stage?stage=warning',
            headers=ADMIN_HEADERS,
        )
        assert resp.status_code == 200
        assert resp.json()['stage'] == 'warning'
        assert _state_store[TEST_UID]['stage'] == 'warning'

    def test_set_invalid_stage(self):
        """POST with invalid stage should 400."""
        resp = client.post(
            f'/v1/admin/fair-use/user/{TEST_UID}/set-stage?stage=ban',
            headers=ADMIN_HEADERS,
        )
        assert resp.status_code == 400

    def test_reset_user(self):
        """POST /v1/admin/fair-use/user/{uid}/reset clears state."""
        _state_store[TEST_UID] = {'stage': 'warning'}

        resp = client.post(f'/v1/admin/fair-use/user/{TEST_UID}/reset', headers=ADMIN_HEADERS)
        assert resp.status_code == 200
        assert TEST_UID not in _state_store

    def test_set_stage_none_clears_enforcement(self):
        """Setting stage to 'none' should reset durations."""
        _state_store[TEST_UID] = {
            'stage': 'throttle',
            'throttle_until': datetime.utcnow() + timedelta(days=7),
        }

        resp = client.post(
            f'/v1/admin/fair-use/user/{TEST_UID}/set-stage?stage=none',
            headers=ADMIN_HEADERS,
        )
        assert resp.status_code == 200
        state = _state_store[TEST_UID]
        assert state['throttle_until'] is None
        assert state['restrict_until'] is None


class TestRemovedCustomerEndpoints:
    def test_signed_in_status_route_is_absent(self):
        assert client.get('/v1/fair-use/status').status_code == 404

    def test_public_case_status_route_is_absent(self):
        assert client.get('/v1/fair-use/case/FU-AABBCCDDEEFF/status').status_code == 404


class TestCaseRefFormat:
    """Test case reference generation format using production _generate_case_ref."""

    def _load_generate_case_ref(self):
        """Load _generate_case_ref from production source file (avoids stubbed sys.modules).

        Uses spec_from_file_location with a package-qualified name and injects
        the ._client parent so the relative import succeeds.
        """
        import importlib.util

        # Create a minimal database package with _client stub
        _client_stub = types.ModuleType('database._client')
        _client_stub.db = MagicMock()
        _client_stub.get_firestore_client = MagicMock(return_value=_client_stub.db)
        saved = sys.modules.get('database._client')
        sys.modules['database._client'] = _client_stub

        src_path = os.path.join(os.path.dirname(__file__), '..', '..', 'database', 'fair_use.py')
        spec = importlib.util.spec_from_file_location(
            'database.fair_use_prod',
            src_path,
            submodule_search_locations=[],
        )
        mod = importlib.util.module_from_spec(spec)
        mod.__package__ = 'database'
        spec.loader.exec_module(mod)

        # Restore original stub
        if saved is not None:
            sys.modules['database._client'] = saved
        else:
            sys.modules.pop('database._client', None)

        return mod._generate_case_ref

    def test_case_ref_format_and_length(self):
        """Case ref should be FU- prefix + 12 uppercase hex chars."""
        import re

        _generate_case_ref = self._load_generate_case_ref()

        for _ in range(20):
            ref = _generate_case_ref()
            assert ref.startswith('FU-')
            hex_part = ref[3:]
            assert len(hex_part) == 12
            assert re.match(r'^[0-9A-F]{12}$', hex_part)

    def test_case_refs_are_unique(self):
        """Generated refs should be unique (from UUID4)."""
        _generate_case_ref = self._load_generate_case_ref()

        refs = {_generate_case_ref() for _ in range(100)}
        assert len(refs) == 100


class TestListenPathFairUseImports:
    """Structural test: extracted listen fair-use imports match expected design.

    Reads the source file directly (avoids heavy dep chain import).
    Warning/throttle are notify-only. Restrict enforces managed STT budget cap only.
    No VAD throttle, no blanket transcript blocking.
    """

    @staticmethod
    def _read_listen_sources():
        listen_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'routers', 'listen')
        return '\n'.join(
            open(os.path.join(listen_dir, module)).read() for module in ('runtime.py', 'receiver.py', 'contracts.py')
        )

    def test_listen_does_not_import_hard_restriction(self):
        """Listen must not use a blanket restriction or VAD throttle."""
        source = self._read_listen_sources()
        assert 'is_hard_restricted' not in source
        assert 'fair_use_restricted' not in source
        assert 'get_user_vad_threshold_delta' not in source

    def test_fair_use_imports_include_budget_gate(self):
        """Tracking + managed STT budget gate functions should be imported from fair_use."""
        source = self._read_listen_sources()
        # Tracking functions
        assert 'record_speech_ms' in source
        assert 'check_soft_caps' in source
        assert 'trigger_free_exhaustion_if_needed' in source
        assert 'create_pending_fair_use_review' in source
        # managed STT budget gate (restrict-only)
        assert 'get_enforcement_stage' in source
        assert 'is_managed_stt_budget_exhausted' in source
        assert 'record_managed_stt_usage_ms' in source
        assert 'FAIR_USE_RESTRICT_DAILY_MANAGED_STT_MS' in source

    def test_budget_gate_used_in_conditionals(self):
        """fair_use_managed_stt_budget_exhausted must appear in if-conditionals, not just as an import/comment."""
        import re

        source = self._read_listen_sources()
        # Must be used as a guard, either inline or passed into the STT decision helpers.
        guard_uses = re.findall(
            r'(?:if|and|not)\s+self\.(?:host\.)?state\.fair_use_managed_stt_budget_exhausted'
            r'|fair_use_managed_stt_budget_exhausted=self\.(?:host\.)?state\.fair_use_managed_stt_budget_exhausted',
            source,
        )
        # Expect at least 3 guard points: session-start, periodic check, single-channel STT,
        # multi-channel (speech-profile excluded — small chunks, not budget-gated)
        assert (
            len(guard_uses) >= 3
        ), f'Expected >=3 guard uses of fair_use_managed_stt_budget_exhausted, found {len(guard_uses)}'

    def test_budget_accounting_across_providers(self):
        """Managed STT usage must be tracked for single-channel and multi-channel paths.

        Since #5854, per-chunk calls are batched via managed_stt_usage_ms_pending accumulator.
        record_managed_stt_usage_ms is called only at periodic flush + session-end flush.
        The accumulation points (managed_stt_usage_ms_pending +=) cover all active provider paths.
        """
        receiver_source = self._read_listen_sources()
        runtime_path = os.path.join(os.path.dirname(__file__), '..', '..', 'routers', 'listen', 'runtime.py')
        runtime_source = open(runtime_path).read()
        import re

        # Verify accumulation points cover single + multi-channel managed STT (#5854 batching)
        accum_calls = re.findall(
            r'^\s+self\.host\.state\.managed_stt_usage_ms_pending\s*\+=', receiver_source, re.MULTILINE
        )
        assert len(accum_calls) >= 1, (
            'The retained fixed managed-STT receiver must meter its provider-funded audio; '
            f'found {len(accum_calls)} accumulation points'
        )

        # Periodic and final writes share one flush implementation.
        assert re.search(
            r'self\.persistence\.call\(\s*record_managed_stt_usage_ms,\s*self\.request\.uid,\s*'
            r'self\.state\.managed_stt_usage_ms_pending,',
            runtime_source,
        )
        assert '_flush_usage(final=False)' in runtime_source
        assert '_flush_usage(final=True)' in runtime_source
