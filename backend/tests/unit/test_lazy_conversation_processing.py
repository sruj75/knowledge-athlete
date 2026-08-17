"""Unit tests for lazy desktop conversation processing (freemium cost cut).

Validates `should_defer_desktop_processing`: free desktop users are deferred
(raw transcript on capture, enriched on first open); normalized paid users are
processed normally; lookups fail safe to "process".

Uses sys.modules stubs so importing utils.subscription doesn't trigger Firestore/Firebase init.
"""

import sys
import types

import pytest
from unittest.mock import MagicMock


class TestShouldDeferDesktopProcessing:
    @pytest.fixture(autouse=True)
    def _setup_subscription(self):
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
            elif name == 'database.announcements':
                mod.compare_versions = MagicMock()
            elif name == 'firebase_admin.auth':
                mod.get_user = MagicMock()

        if 'utils.subscription' in sys.modules:
            del sys.modules['utils.subscription']
        import utils.subscription as sub

        self._sub = sub
        self._users = sys.modules['database.users']
        yield
        for name in stubs:
            if saved[name] is None:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = saved[name]
        sys.modules.pop('utils.subscription', None)

    def _sub_with_plan(self, plan):
        s = MagicMock()
        s.plan = plan
        return s

    def test_free_plan_is_deferred(self):
        from models.users import PlanType

        self._users.get_user_valid_subscription.return_value = None
        assert self._sub.should_defer_desktop_processing('uid') is True

    def test_bounded_is_not_deferred(self):
        from models.users import PlanType

        self._users.get_user_valid_subscription.return_value = self._sub_with_plan(PlanType.bounded)
        assert self._sub.should_defer_desktop_processing('uid') is False

    def test_unlimited_is_not_deferred(self):
        from models.users import PlanType

        self._users.get_user_valid_subscription.return_value = self._sub_with_plan(PlanType.unlimited)
        assert self._sub.should_defer_desktop_processing('uid') is False

    def test_lookup_error_fails_safe_to_not_deferred(self):
        self._users.get_user_valid_subscription.side_effect = RuntimeError("firestore down")
        assert self._sub.should_defer_desktop_processing('uid') is False


class TestDeferredNotRequeuedBySweeper:
    """Deferred conversations sit in status=processing until opened — they must NOT be returned by
    get_processing_conversations (the listen-session sweeper re-sends those to pusher, which would
    background-process deferred rows and defeat the cost saving)."""

    @pytest.fixture(scope='class')
    def conversations_db(self):
        import database.conversations as cdb

        return cdb

    def test_get_processing_conversations_excludes_deferred(self, conversations_db):
        cdb = conversations_db

        def _doc(d):
            m = MagicMock()
            m.to_dict.return_value = d
            return m

        docs = [
            _doc({'id': 'a', 'deferred': True}),  # deferred -> excluded
            _doc({'id': 'b', 'deferred': False}),  # not deferred -> kept
            _doc({'id': 'c'}),  # no deferred field (normal processing) -> kept
        ]
        chain = MagicMock()
        chain.stream.return_value = docs
        mock_db = MagicMock()
        mock_db.collection.return_value.document.return_value.collection.return_value.where.return_value = chain
        with __import__('unittest.mock', fromlist=['patch']).patch.object(cdb, 'db', mock_db):
            result = cdb.get_processing_conversations('uid-x')
        assert [c['id'] for c in result] == ['b', 'c']
