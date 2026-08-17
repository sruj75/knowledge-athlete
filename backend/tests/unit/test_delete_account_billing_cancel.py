"""Regression test for issue #6750 — delete-account must cancel an active billing subscription.

Before the fix, DELETE /v1/users/delete-account revoked Firebase auth and wiped Firestore but never
canceled the user's provider subscription, so a paying user kept getting billed with no way to log back
in and cancel. The handler now cancels the subscription before Firebase auth deletion and blocks the
deletion if billing cancellation cannot be confirmed.

``services.users.account_deletion`` binds its collaborators at import (``from database import users as
users_db`` and the billing service, and those packages pull heavy chains with
import-time side effects, so the fake ``database``/``utils`` namespaces must be active before the
module is exec'd. This is the sanctioned Tier-2 "fake must precede import" case: see
``backend/docs/test_isolation.md`` and ``testing.import_isolation.load_module_fresh``.
"""

import os
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from testing.import_isolation import AutoMockModule, load_module_fresh, stub_modules

_BACKEND = Path(__file__).resolve().parents[2]


def _pkg(name):
    m = AutoMockModule(name)
    m.__path__ = []
    return m


@pytest.fixture(scope="module")
def users_service():
    """Load a fresh services.users.account_deletion against stubbed database/utils namespaces."""
    fakes = {
        "database": _pkg("database"),
        "database.users": AutoMockModule("database.users"),
        "database.action_items": AutoMockModule("database.action_items"),
        "database.conversations": AutoMockModule("database.conversations"),
        "database.memories": AutoMockModule("database.memories"),
        "database.screen_activity": AutoMockModule("database.screen_activity"),
        "database.vector_db": AutoMockModule("database.vector_db"),
        "utils": _pkg("utils"),
        "utils.cloud_tasks": AutoMockModule("utils.cloud_tasks"),
        "utils.billing": _pkg("utils.billing"),
        "utils.billing.service": AutoMockModule("utils.billing.service"),
        "utils.executors": AutoMockModule("utils.executors"),
        "utils.log_sanitizer": AutoMockModule("utils.log_sanitizer"),
        "utils.posthog_telemetry": AutoMockModule("utils.posthog_telemetry"),
        "utils.other": _pkg("utils.other"),
        "utils.other.endpoints": AutoMockModule("utils.other.endpoints"),
        "utils.memory": _pkg("utils.memory"),
        "utils.memory.canonical_memory_adapter": AutoMockModule("utils.memory.canonical_memory_adapter"),
        "utils.other.storage": AutoMockModule("utils.other.storage"),
        "utils.twilio_service": AutoMockModule("utils.twilio_service"),
    }
    with stub_modules(fakes):
        service = load_module_fresh(
            "services.users.account_deletion",
            os.path.join(str(_BACKEND), "services", "users", "account_deletion.py"),
        )
        service.users_db.mark_user_deletion_wipe_intent.return_value = {
            'wipe_job_id': 'job-1',
            'dispatch_claimed': True,
        }
        service.users_db.mark_user_deletion_wipe_started.return_value = True
        yield service


def _sub(billing_subscription_id):
    s = MagicMock()
    s.billing_subscription_id = billing_subscription_id
    return s


def test_paid_user_subscription_is_left_for_the_claimed_wipe_worker(users_service):
    with patch.object(
        users_service.users_db, 'get_user_subscription', return_value=_sub('sub_123')
    ) as get_sub, patch.object(
        users_service, 'cancel_subscription_for_account_deletion', return_value=True
    ) as cancel, patch.object(
        users_service.auth, 'delete_account'
    ) as fb_delete, patch.object(
        users_service, 'submit_with_context'
    ) as submit:
        resp = users_service.start_account_deletion(uid='uid1')
    get_sub.assert_not_called()
    cancel.assert_not_called()
    fb_delete.assert_not_called()
    submit.assert_called_once_with(users_service.cleanup_executor, users_service.background_wipe_user_data, 'uid1')
    assert resp['status'] == 'ok'


def test_free_user_does_not_call_billing_provider(users_service):
    with patch.object(users_service.users_db, 'get_user_subscription', return_value=_sub(None)), patch.object(
        users_service, 'cancel_subscription_for_account_deletion'
    ) as cancel, patch.object(users_service.auth, 'delete_account'), patch.object(
        users_service, 'submit_with_context'
    ) as submit:
        resp = users_service.start_account_deletion(uid='uid1')
    cancel.assert_not_called()
    submit.assert_called_once_with(users_service.cleanup_executor, users_service.background_wipe_user_data, 'uid1')
    assert resp['status'] == 'ok'


def test_request_does_not_observe_billing_errors_before_claimed_wipe(users_service):
    with patch.object(users_service.users_db, 'get_user_subscription', return_value=_sub('sub_123')), patch.object(
        users_service, 'cancel_subscription_for_account_deletion', side_effect=Exception('billing down')
    ), patch.object(users_service.users_db, 'mark_user_deletion_billing_failed') as mark_billing_failed, patch.object(
        users_service.auth, 'delete_account'
    ) as fb_delete, patch.object(
        users_service, 'submit_with_context'
    ) as submit:
        resp = users_service.start_account_deletion(uid='uid1')
    mark_billing_failed.assert_not_called()
    fb_delete.assert_not_called()
    submit.assert_called_once_with(users_service.cleanup_executor, users_service.background_wipe_user_data, 'uid1')
    assert resp['status'] == 'ok'
