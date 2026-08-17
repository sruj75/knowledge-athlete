"""Tests for the desktop trial paywall reconnect gate (#7318).

Validates:
- Admission phase rejects paywalled desktop before session start
- No paywall close block inside the session body (removed, handled in admission)
- Cache invalidation on payment changes
- is_trial_paywalled handles platform filtering (only desktop/macos affected)
- Behavioral tests for is_trial_paywalled and clear_trial_paywall_cache
"""

from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from routers.listen.contracts import ListenRequest
from routers.listen.runtime import ListenSessionRuntime

BACKEND_DIR = Path(__file__).resolve().parents[2]
RUNTIME_SRC_PATH = BACKEND_DIR / 'routers' / 'listen' / 'runtime.py'
USERS_SRC_PATH = BACKEND_DIR / 'routers' / 'users.py'
SUBSCRIPTION_SRC_PATH = BACKEND_DIR / 'utils' / 'subscription.py'


def _read_source(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


class FakeWebSocket:
    def __init__(self):
        self.headers = {}
        self.events = []
        self.closed = []

    async def send_json(self, event):
        self.events.append(event)

    async def close(self, *, code, reason):
        self.closed.append((code, reason))


def _runtime(uid='test-user', source='desktop'):
    websocket = FakeWebSocket()
    return ListenSessionRuntime(ListenRequest(websocket=websocket, uid=uid, source=source)), websocket


class TestAdmissionPhase:
    """Exercise admission through the extracted runtime instead of source ordering."""

    @pytest.mark.asyncio
    async def test_paywall_rejects_before_session_start(self, monkeypatch):
        runtime, websocket = _runtime()

        async def fake_run_blocking(_executor, function, *args):
            assert function.__name__ == 'is_trial_paywalled'
            assert args == ('test-user', 'desktop')
            return True

        monkeypatch.setattr('routers.listen.runtime.run_blocking', fake_run_blocking)
        assert await runtime._admit() is False
        assert websocket.events[0]['type'] == 'freemium_threshold_reached'
        assert websocket.closed == [(1008, 'trial_expired')]
        assert runtime.task_supervisor._session_started is False

    @pytest.mark.asyncio
    async def test_bad_uid_and_audio_format_are_rejected_without_starting_session(self, monkeypatch):
        missing_uid, missing_uid_socket = _runtime(uid='')
        assert await missing_uid._admit() is False
        assert missing_uid_socket.closed == [(1008, 'Bad uid')]

        invalid_audio, invalid_audio_socket = _runtime()
        monkeypatch.setattr('routers.listen.runtime.validate_audio_format', lambda *_args: 'bad_audio')
        assert await invalid_audio._admit() is False
        assert invalid_audio_socket.closed == [(1003, 'bad_audio')]
        assert invalid_audio.task_supervisor._session_started is False


class TestNoPaywallBlockInSession:
    def test_runtime_has_no_legacy_cooldown_logic(self):
        source = _read_source(RUNTIME_SRC_PATH)
        assert 'check_trial_paywall_ws_cooldown' not in source
        assert 'set_trial_paywall_ws_cooldown' not in source


class TestCacheInvalidation:
    """Verify trial paywall cache is cleared on subscription changes."""

    def test_clear_trial_paywall_cache_clears_expired_key(self):
        src = _read_source(SUBSCRIPTION_SRC_PATH)
        assert 'trial_paywall:expired:' in src, "clear function must delete expired cache"
        fn_start = src.find('def clear_trial_paywall_cache')
        assert fn_start != -1
        fn_body = src[fn_start : src.find('\ndef ', fn_start + 1)]
        assert 'delete_generic_cache' in fn_body


class TestCacheInvalidationBehavioral:
    """Verify clear_trial_paywall_cache implementation."""

    def test_clear_cache_deletes_expired_key(self):
        src = _read_source(SUBSCRIPTION_SRC_PATH)
        fn_start = src.find('def clear_trial_paywall_cache')
        assert fn_start != -1
        fn_end = src.find('\ndef ', fn_start + 1)
        fn_body = src[fn_start:fn_end] if fn_end != -1 else src[fn_start:]
        assert 'delete_generic_cache' in fn_body
        assert 'trial_paywall:expired:' in fn_body
        delete_count = fn_body.count('delete_generic_cache')
        assert (
            delete_count == 1
        ), f"clear_trial_paywall_cache should call delete_generic_cache exactly once, got {delete_count}"


class TestPlatformFiltering:
    """Verify is_trial_paywalled handles platform scoping correctly via source inspection."""

    def test_is_trial_paywalled_checks_desktop_tokens(self):
        src = _read_source(SUBSCRIPTION_SRC_PATH)
        assert '_TRIAL_PAYWALL_DESKTOP_TOKENS' in src, "must use desktop token set for platform filtering"
        assert 'macos' in src, "desktop tokens must include 'macos'"
        assert 'desktop' in src, "desktop tokens must include 'desktop'"

    def test_is_trial_paywalled_filters_before_expiry_lookup(self):
        src = _read_source(SUBSCRIPTION_SRC_PATH)
        fn_start = src.find('def is_trial_paywalled(')
        assert fn_start != -1
        fn_body = src[fn_start : src.find('\ndef ', fn_start + 1)]
        filter_pos = fn_body.find('platform.lower() not in _TRIAL_PAYWALL_DESKTOP_TOKENS')
        expiry_pos = fn_body.find('_is_trial_expired_cached(uid)')
        assert filter_pos != -1, "is_trial_paywalled must filter non-desktop platforms"
        assert expiry_pos != -1, "is_trial_paywalled must call the cached expiry lookup"
        assert filter_pos < expiry_pos, "platform filtering must happen before the expiry lookup"

    def test_is_trial_paywalled_delegates_to_cached_expiry(self):
        src = _read_source(SUBSCRIPTION_SRC_PATH)
        fn_start = src.find('def is_trial_paywalled(')
        assert fn_start != -1
        fn_body = src[fn_start : src.find('\ndef ', fn_start + 1)]
        assert (
            'return _is_trial_expired_cached(uid)' in fn_body
        ), "desktop paywall decisions must use the cached expiry lookup"

    def test_is_trial_paywalled_uses_lower_for_case_insensitivity(self):
        src = _read_source(SUBSCRIPTION_SRC_PATH)
        fn_start = src.find('def is_trial_paywalled(')
        assert fn_start != -1
        fn_body = src[fn_start : src.find('\ndef ', fn_start + 1)]
        assert '.lower()' in fn_body, "is_trial_paywalled must use .lower() for case-insensitive matching"

    def test_admission_calls_is_trial_paywalled_with_source(self):
        src = _read_source(RUNTIME_SRC_PATH)
        admission_start = src.find('async def _admit(')
        admission_end = src.find('    async def _bootstrap', admission_start)
        admission_body = src[admission_start:admission_end]
        assert (
            'run_blocking(db_executor, is_trial_paywalled, self.request.uid, self.request.source)' in admission_body
        ), "admission phase must offload is_trial_paywalled with uid and source"


class TestIsTrialPaywalledBehavioral:
    """Behavioral tests for is_trial_paywalled() — mock internals, test logic directly.

    Uses sys.modules stubs to avoid triggering Firestore/Firebase init on import.
    """

    @pytest.fixture(autouse=True)
    def _setup_subscription(self):
        import sys
        import types

        def _stub(name):
            if name not in sys.modules:
                sys.modules[name] = types.ModuleType(name)
            return sys.modules[name]

        saved = {}
        stubs = [
            'google.cloud',
            'google.cloud.firestore',
            'google.cloud.firestore_v1',
            'firebase_admin',
            'firebase_admin.auth',
            'firebase_admin.firestore',
            'database._client',
            'database.redis_db',
            'database.users',
            'database.user_usage',
            'database.announcements',
        ]
        for name in stubs:
            saved[name] = sys.modules.get(name)
            mod = _stub(name)
            if name == 'database._client':
                mod.db = MagicMock()
            elif name == 'database.redis_db':
                mod.get_generic_cache = MagicMock(return_value=None)
                mod.set_generic_cache = MagicMock()
                mod.delete_generic_cache = MagicMock()
            elif name == 'database.users':
                mod.get_user_valid_subscription = MagicMock(return_value=None)
            elif name == 'database.user_usage':
                pass
            elif name == 'database.announcements':
                mod.compare_versions = MagicMock()
            elif name == 'firebase_admin.auth':
                mock_user = MagicMock()
                mock_user.user_metadata.creation_timestamp = 0
                mod.get_user = MagicMock(return_value=mock_user)

        if 'utils.subscription' in sys.modules:
            del sys.modules['utils.subscription']

        import utils.subscription as sub

        # The trial paywall is OFF by default (freemium). Force it on so the delegation
        # logic under test is reachable.
        sub.TRIAL_PAYWALL_ENABLED = True

        self._sub = sub
        self._mock_expired = MagicMock(return_value=True)
        self._orig_expired = sub._is_trial_expired_cached
        sub._is_trial_expired_cached = self._mock_expired

        yield

        sub._is_trial_expired_cached = self._orig_expired
        for name in stubs:
            if saved[name] is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = saved[name]

    def test_desktop_expired_returns_true(self):
        assert self._sub.is_trial_paywalled('uid1', 'desktop') is True

    def test_macos_expired_returns_true(self):
        assert self._sub.is_trial_paywalled('uid1', 'macos') is True

    def test_windows_expired_returns_true(self):
        # Windows is a desktop platform: it must be subject to the desktop trial
        # paywall exactly like macOS (regression for the platform defect where
        # only 'macos'/'desktop' were recognized as desktop tokens).
        assert self._sub.is_trial_paywalled('uid1', 'windows') is True
        assert self._sub.is_trial_paywalled('uid1', 'WINDOWS') is True

    def test_ios_returns_false(self):
        assert self._sub.is_trial_paywalled('uid1', 'ios') is False
        self._mock_expired.assert_not_called()

    def test_android_returns_false(self):
        assert self._sub.is_trial_paywalled('uid1', 'android') is False
        self._mock_expired.assert_not_called()

    def test_none_platform_returns_false(self):
        assert self._sub.is_trial_paywalled('uid1', None) is False
        self._mock_expired.assert_not_called()

    def test_unknown_platform_returns_false(self):
        assert self._sub.is_trial_paywalled('uid1', 'phone_call') is False
        self._mock_expired.assert_not_called()

    def test_mixed_case_desktop(self):
        assert self._sub.is_trial_paywalled('uid1', 'Desktop') is True
        assert self._sub.is_trial_paywalled('uid1', 'MACOS') is True

    def test_desktop_cache_false_returns_false(self):
        self._mock_expired.return_value = False
        assert self._sub.is_trial_paywalled('uid1', 'desktop') is False

    def test_desktop_uid_delegates_to_expiry_cache(self):
        assert self._sub.is_trial_paywalled('uid1', 'desktop') is True
        self._mock_expired.assert_called_with('uid1')

    def test_different_desktop_uid_uses_same_expiry_path(self):
        assert self._sub.is_trial_paywalled('uid99', 'desktop') is True
        self._mock_expired.assert_called_with('uid99')

    def test_not_expired_returns_false(self):
        self._mock_expired.return_value = False
        assert self._sub.is_trial_paywalled('uid1', 'desktop') is False

    def test_clear_cache_calls_redis_delete(self):
        self._sub.clear_trial_paywall_cache('test-uid-123')
        self._sub.redis_db.delete_generic_cache.assert_called_with('trial_paywall:expired:test-uid-123')
