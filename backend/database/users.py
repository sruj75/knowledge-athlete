import uuid
from datetime import datetime, timedelta, timezone
from typing import Literal, Optional, TypedDict

from google.cloud import firestore
from google.cloud.firestore_v1 import transactional
from ._client import db, delete_collection_recursive
from database.firestore_cache import CachePolicy, get_or_fetch, invalidate
from database.read_boundary import parse_snapshot_strict
from database.redis_db import try_acquire_client_device_write_lock, try_acquire_user_platform_write_lock
from config.free_plan import get_default_free_subscription
from models.users import (
    Subscription,
    PlanLimits,
    PlanType,
    SubscriptionStatus,
)
import logging

logger = logging.getLogger(__name__)
DELETION_WIPE_RUNNING_STALE_AFTER = timedelta(hours=6)
_DELETION_WIPE_TERMINAL_STATUSES = frozenset({'completed', 'cancelled'})
_DELETION_WIPE_LEGACY_ACTIONABLE_STATUSES = frozenset({'pending', 'retrying', 'running', 'failed'})


class DeletionWipeTaskResolution(TypedDict):
    outcome: Literal['resolved', 'missing', 'ambiguous', 'completed', 'not_actionable']
    uid: str | None


class DeletionWipeIntent(TypedDict):
    """Result of creating or joining an account-deletion wipe authority."""

    wipe_job_id: str
    dispatch_claimed: bool


# Conservative low-risk user projections. Do NOT use these policies for
# entitlement, data-protection, privacy-consent, or full user-doc caching.
_USER_LANGUAGE_CACHE = CachePolicy(namespace='user_language', version=1, ttl_seconds=300)


# Industry-standard two-field pattern (Mixpanel / Amplitude / PostHog):
#   signup_platform       — set once at account creation, immutable
#   last_active_platform  — overwritten on every authenticated request
#   platforms_used        — array union of every platform the user has ever
#                           authenticated from (for cross-platform segmentation)
#
# We normalize the raw header into a coarse `desktop | mobile` bucket, matching
# the profitability dashboard splits, and preserve the granular value
# (`ios`/`android`/`macos`/`windows`) in `last_active_os` for finer drill-down.
_PLATFORM_ALIASES = {
    'macos': 'desktop',
    'mac': 'desktop',
    'mac os x': 'desktop',
    'windows': 'desktop',
    'win32': 'desktop',
    'desktop': 'desktop',
    'ios': 'mobile',
    'iphone os': 'mobile',
    'android': 'mobile',
    'mobile': 'mobile',
    'web': 'web',
    'browser': 'web',
}


def _normalize_platform(raw: Optional[str]) -> tuple[Optional[str], Optional[str]]:
    """Return (coarse_platform, os_value) for a raw `X-App-Platform` header.

    `coarse_platform` is one of 'desktop' / 'mobile' (None if unrecognized).
    `os_value` is the normalized OS string preserved for drill-down.
    """
    if not raw or not isinstance(raw, str):
        return None, None
    os_value = raw.strip().lower()
    if not os_value:
        return None, None
    coarse = _PLATFORM_ALIASES.get(os_value)
    return coarse, os_value


def record_client_device(
    uid: str,
    *,
    client_device_id: Optional[str],
    platform: Optional[str],
    app_version: Optional[str] = None,
    label: Optional[str] = None,
) -> None:
    """Upsert users/{uid}/client_devices/{client_device_id} from request headers.

    Throttled via Redis (same 10-minute window as record_user_platform). Fail-open telemetry.
    """
    if not client_device_id or not platform:
        return

    try:
        if not try_acquire_client_device_write_lock(uid, client_device_id):
            return

        now = datetime.now(timezone.utc)
        coarse, _os_value = _normalize_platform(platform)
        doc_ref = db.collection('users').document(uid).collection('client_devices').document(client_device_id)
        updates = {
            'platform': platform,
            'device_class': coarse,
            'last_seen_at': now,
        }
        if app_version:
            updates['app_version'] = app_version
        if label:
            updates['label'] = label

        snapshot = doc_ref.get()
        if not snapshot.exists:
            updates['first_seen_at'] = now

        doc_ref.set(updates, merge=True)
    except Exception as e:  # noqa: BLE001
        logger.warning("record_client_device failed for uid=%s: %s", uid, e)


def record_user_platform(uid: str, raw_platform: Optional[str]) -> None:
    """Write the user-platform fields from an `X-App-Platform` header value.

    Called on every authenticated request. Throttled to one Firestore write
    per (uid, coarse_platform) every 10 minutes via Redis so chatty endpoints
    don't hot-spot the user doc. Fail-open: any error is logged and swallowed
    because this is a telemetry side-effect, not a request-correctness path.

    - `signup_platform` is set once via `Firestore.ArrayUnion` semantics:
      we read the doc and only write it if it's not already present.
    - `last_active_platform` / `last_active_os` / `last_active_at` are
      overwritten every throttle-window.
    - `platforms_used` accumulates via `firestore.ArrayUnion`.
    """
    coarse, os_value = _normalize_platform(raw_platform)
    if not coarse:
        return

    try:
        if not try_acquire_user_platform_write_lock(uid, coarse):
            return

        now = datetime.now(timezone.utc)
        user_ref = db.collection('users').document(uid)

        updates = {
            'last_active_platform': coarse,
            'last_active_os': os_value,
            'last_active_at': now,
            f'last_active_at_{coarse}': now,
            'platforms_used': firestore.ArrayUnion([coarse]),
        }

        # `signup_platform` is set_once. Read the doc (single read) and only
        # include the field in the write if it's not already present. Cheaper
        # than a transaction for a field that almost never changes.
        snapshot = user_ref.get()
        if snapshot.exists:
            data = snapshot.to_dict() or {}
            if not data.get('signup_platform'):
                updates['signup_platform'] = coarse
                updates['signup_os'] = os_value
                updates['signup_platform_at'] = data.get('created_at') or now
        else:
            # First-ever auth'd request for this uid — treat as sign-up.
            updates['signup_platform'] = coarse
            updates['signup_os'] = os_value
            updates['signup_platform_at'] = now

        user_ref.set(updates, merge=True)
    except Exception as e:  # noqa: BLE001
        logger.warning("record_user_platform failed for uid=%s: %s", uid, e)


def is_exists_user(uid: str):
    user_ref = db.collection('users').document(uid)
    if not user_ref.get().exists:
        return False
    return True


def get_user_profile(uid: str) -> dict:
    """Gets the full user profile document."""
    user_ref = db.collection('users').document(uid)
    user_doc = user_ref.get()
    if user_doc.exists:
        return user_doc.to_dict()
    return {}


def get_user_time_zone(uid: str) -> Optional[str]:
    """Return retained account timezone metadata without importing FCM storage."""
    user_ref = db.collection('users').document(uid)
    user_data = user_ref.get().to_dict() or {}
    value = user_data.get('time_zone')
    return value if isinstance(value, str) and value else None


def set_user_cancellation_feedback(uid: str, reason: str, reason_details: Optional[str] = None):
    user_ref = db.collection('users').document(uid)
    user_ref.set(
        {
            'cancellation_feedback': {
                'reason': reason,
                'reason_details': reason_details or '',
                'timestamp': datetime.now(timezone.utc),
            }
        },
        merge=True,
    )


def mark_user_deletion_wipe_running(uid: str):
    """Transition a queued wipe marker to ``running`` once the worker starts.

    Called by ``background_wipe_user_data`` at the top of the wipe worker.
    This lets the reconciler distinguish a genuinely orphaned ``pending`` wipe
    (queued but never picked up — safe to re-enqueue)
    from a ``running`` wipe (actively executing — only recovered if the claim
    is stale, i.e. the worker probably crashed).

    Without this, a slow but live wipe could be reclaimed as orphaned after
    ``stale_after`` (default 10 min) and re-enqueued concurrently, leading to
    duplicate work where a later failure overwrites a successful completion.
    """
    db.collection('account_deletions').document(uid).set(
        {'wipe_status': 'running', 'wipe_running_at': datetime.now(timezone.utc)},
        merge=True,
    )


@transactional
def _mark_user_deletion_wipe_intent_txn(transaction, doc_ref, wipe_job_id: str) -> DeletionWipeIntent:
    snapshot = doc_ref.get(transaction=transaction)
    if snapshot.exists:
        data = snapshot.to_dict() or {}
        existing_job_id = data.get('wipe_job_id')
        # A repeat request must join the existing durable deletion authority,
        # never reset a claimed/running/completed job backwards.
        if isinstance(existing_job_id, str) and existing_job_id:
            status = data.get('wipe_status')
            # A retry can recover a request that crashed after intent was
            # committed but before it promoted that exact job to pending. The
            # promotion below is itself job-id-fenced and transactional, so
            # concurrent retries can race safely: exactly one gets ``True``
            # and dispatches.
            if status == 'deleting_auth':
                return {'wipe_job_id': existing_job_id, 'dispatch_claimed': True}
            if status in {'pending', 'retrying', 'running', 'failed', 'completed'}:
                return {'wipe_job_id': existing_job_id, 'dispatch_claimed': False}
    transaction.set(
        doc_ref,
        {
            'wipe_status': 'deleting_auth',
            'wipe_intent_at': datetime.now(timezone.utc),
            'wipe_job_id': wipe_job_id,
        },
        merge=True,
    )
    return {'wipe_job_id': wipe_job_id, 'dispatch_claimed': True}


def mark_user_deletion_wipe_intent(uid: str) -> DeletionWipeIntent:
    """Create or join the durable account-deletion authority.

    Repeated requests reuse an existing active job id rather than moving a
    claimed, running, failed, or completed wipe backwards. An existing
    ``deleting_auth`` intent remains eligible for the job-id-fenced promotion
    so a retry can recover a crash before queue acceleration; exactly one
    concurrent request can win that promotion. The claimed worker is the only
    path that deletes Firebase Auth or user data.

    ``deleting_auth`` remains a legacy recovery state for records written by
    older workers; new request handling promotes it immediately.
    """
    wipe_job_id = uuid.uuid4().hex
    doc_ref = db.collection('account_deletions').document(uid)
    transaction = db.transaction()
    return _mark_user_deletion_wipe_intent_txn(transaction, doc_ref, wipe_job_id)


@transactional
def _mark_user_deletion_wipe_started_txn(transaction, doc_ref, wipe_job_id: str) -> bool:
    """Promote a newly-created intent to pending exactly once.

    The status and opaque job id are checked in the same transaction as the
    write. This fences a retry/repeated request from moving an already claimed,
    running, failed, or completed wipe backwards before it can enqueue again.
    """
    snapshot = doc_ref.get(transaction=transaction)
    if not snapshot.exists:
        return False
    data = snapshot.to_dict() or {}
    if data.get('wipe_status') != 'deleting_auth' or data.get('wipe_job_id') != wipe_job_id:
        return False
    transaction.update(
        doc_ref,
        {'wipe_status': 'pending', 'wipe_queued_at': datetime.now(timezone.utc)},
    )
    return True


def mark_user_deletion_wipe_started(uid: str, wipe_job_id: str) -> bool:
    """Atomically promote one newly-created wipe intent to queue-pending."""
    doc_ref = db.collection('account_deletions').document(uid)
    transaction = db.transaction()
    return _mark_user_deletion_wipe_started_txn(transaction, doc_ref, wipe_job_id)


def mark_user_deletion_wipe_completed(uid: str):
    """Mark the background data wipe as finished."""
    db.collection('account_deletions').document(uid).set(
        {'wipe_status': 'completed', 'wipe_completed_at': datetime.now(timezone.utc)},
        merge=True,
    )


def mark_user_deletion_wipe_failed(uid: str):
    """Mark the background data wipe as failed so a reconciliation worker can retry."""
    db.collection('account_deletions').document(uid).set(
        {'wipe_status': 'failed', 'wipe_failed_at': datetime.now(timezone.utc)},
        merge=True,
    )


@transactional
def _ensure_deletion_wipe_job_id_txn(transaction, doc_ref, generated_job_id: str) -> str | None:
    snapshot = doc_ref.get(transaction=transaction)
    if not snapshot.exists:
        return None
    existing_job_id = (snapshot.to_dict() or {}).get('wipe_job_id')
    if isinstance(existing_job_id, str) and existing_job_id:
        return existing_job_id
    transaction.update(doc_ref, {'wipe_job_id': generated_job_id})
    return generated_job_id


def ensure_deletion_wipe_job_id(uid: str) -> str | None:
    """Backfill an opaque job id for a pre-job-id deletion record.

    Records created before the job-scoped payload migration remain recoverable:
    the reconciler claims the state first, then atomically assigns an opaque id
    before it re-enqueues the task.
    """
    doc_ref = db.collection('account_deletions').document(uid)
    transaction = db.transaction()
    return _ensure_deletion_wipe_job_id_txn(transaction, doc_ref, uuid.uuid4().hex)


def resolve_deletion_wipe_job_id(wipe_job_id: str) -> DeletionWipeTaskResolution:
    """Resolve an opaque task id to one canonical deletion job document."""
    docs = list(db.collection('account_deletions').where('wipe_job_id', '==', wipe_job_id).limit(2).stream())
    if not docs:
        return {'outcome': 'missing', 'uid': None}
    if len(docs) != 1:
        return {'outcome': 'ambiguous', 'uid': None}

    doc = docs[0]
    status = (doc.to_dict() or {}).get('wipe_status')
    if status == 'completed':
        return {'outcome': 'completed', 'uid': None}
    if status in _DELETION_WIPE_TERMINAL_STATUSES:
        return {'outcome': 'not_actionable', 'uid': None}
    return {'outcome': 'resolved', 'uid': doc.id}


def resolve_legacy_deletion_wipe_uid(legacy_uid: str) -> DeletionWipeTaskResolution:
    """Resolve a bounded legacy payload through the persisted deletion record.

    This compatibility path is deliberately narrower than the historical
    handler: a UID from a queued legacy task is never executable on its own.
    It must name a still-actionable canonical deletion record, and the handler
    uses the document id returned here rather than the payload value.
    """
    doc = db.collection('account_deletions').document(legacy_uid).get()
    if not doc.exists:
        return {'outcome': 'missing', 'uid': None}
    status = (doc.to_dict() or {}).get('wipe_status')
    if status == 'completed':
        return {'outcome': 'completed', 'uid': None}
    if status not in _DELETION_WIPE_LEGACY_ACTIONABLE_STATUSES:
        return {'outcome': 'not_actionable', 'uid': None}
    return {'outcome': 'resolved', 'uid': doc.id}


@transactional
def _mark_user_deletion_billing_failed_txn(transaction, doc_ref, uid: str, subscription_id: str | None, error: str):
    snapshot = doc_ref.get(transaction=transaction)
    if snapshot.exists:
        status = (snapshot.to_dict() or {}).get('wipe_status')
        if status in ('pending', 'retrying', 'running', 'failed', 'completed'):
            return False

    transaction.set(
        doc_ref,
        {
            'wipe_status': 'billing_failed',
            'billing_failed_at': datetime.now(timezone.utc),
            'billing_subscription_id': subscription_id or '',
            'billing_error': error,
        },
        merge=True,
    )
    return True


def mark_user_deletion_billing_failed(uid: str, subscription_id: str | None, error: str) -> bool:
    """Record that account deletion is blocked on provider cancellation.

    Never clobbers an actionable or terminal wipe state. A billing failure can
    only block deletion before a destructive wipe has been queued or started.
    """
    doc_ref = db.collection('account_deletions').document(uid)
    transaction = db.transaction()
    return _mark_user_deletion_billing_failed_txn(transaction, doc_ref, uid, subscription_id, error)


def cancel_user_deletion_wipe(uid: str):
    """Cancel a pending deletion-wipe marker.

    Called when the Firebase auth deletion fails after the marker was already
    persisted. Without this, the reconciliation worker would later wipe the
    user's data even though their Firebase account still exists.
    """
    db.collection('account_deletions').document(uid).set(
        {'wipe_status': 'cancelled', 'wipe_cancelled_at': datetime.now(timezone.utc)},
        merge=True,
    )


def get_pending_deletion_wipes(
    limit: int = 100,
    stale_after: timedelta = timedelta(minutes=10),
    running_stale_after: timedelta = DELETION_WIPE_RUNNING_STALE_AFTER,
) -> list[dict]:
    """Return account_deletions documents whose wipe needs retry.

    Queries ``failed`` records (always actionable), stale ``pending`` records
    (queued more than ``stale_after`` ago), stale ``deleting_auth`` records
    (intent written but never transitioned to ``pending`` — usually a crash
    after ``auth.delete_account()`` succeeded), stale ``running`` records (worker
    started but hasn't finished within ``running_stale_after`` — probably
    crashed), and stale ``retrying`` claims (worker probably crashed). Fresh
    ``pending``, ``deleting_auth``, and ``running`` markers from in-progress
    deletions are excluded so the reconciler doesn't double-enqueue a wipe that
    is still running.

    The caller is responsible for verifying the Firebase auth user is actually
    gone before recovering a ``deleting_auth`` record — this function returns
    candidates, and ``claim_deletion_wipe`` also age-guards inside a transaction.

    All queries are single-field equality filters on ``wipe_status`` to avoid
    requiring Firestore composite indexes. Age filtering is done in Python.
    """
    stale_cutoff = datetime.now(timezone.utc) - stale_after
    running_cutoff = datetime.now(timezone.utc) - running_stale_after
    budget = limit

    failed_docs = db.collection('account_deletions').where('wipe_status', '==', 'failed').limit(budget).stream()
    result = [doc.to_dict() | {'uid': doc.id} for doc in failed_docs]

    if len(result) < limit:
        # Over-fetch *all* pending docs and age-filter in Python. A tight
        # ``.limit(budget)`` would cap the query before stale records beyond the
        # first page of fresh pending docs, leaving them permanently unqueued.
        # The ``account_deletions`` collection only holds deletion events so
        # the full scan is bounded.
        pending_docs = db.collection('account_deletions').where('wipe_status', '==', 'pending').stream()
        for doc in pending_docs:
            if len(result) >= limit:
                break
            data = doc.to_dict()
            queued_at = data.get('wipe_queued_at')
            if queued_at and queued_at < stale_cutoff:
                result.append(data | {'uid': doc.id})

    if len(result) < limit:
        # Recover stale ``running`` markers — the worker started but hasn't
        # finished within ``running_stale_after``. This is much longer than the
        # ``pending`` stale window because a legitimately slow wipe (queued
        # behind other cleanup jobs) can take several minutes; we only want to
        # reclaim a ``running`` marker when the worker has almost certainly
        # crashed or the pod was killed mid-execution.
        running_docs = db.collection('account_deletions').where('wipe_status', '==', 'running').stream()
        for doc in running_docs:
            if len(result) >= limit:
                break
            data = doc.to_dict()
            running_at = data.get('wipe_running_at')
            if running_at and running_at < running_cutoff:
                result.append(data | {'uid': doc.id})

    if len(result) < limit:
        # Over-fetch all 'deleting_auth' docs and age-filter in Python. A stale
        # 'deleting_auth' record (intent written but never transitioned to
        # 'pending') usually means a crash/deploy after auth.delete_account()
        # succeeded. The reconciler verifies the Firebase user is gone before
        # recovering these — see reconcile_pending_deletion_wipes.
        deleting_auth_docs = db.collection('account_deletions').where('wipe_status', '==', 'deleting_auth').stream()
        for doc in deleting_auth_docs:
            if len(result) >= limit:
                break
            data = doc.to_dict()
            intent_at = data.get('wipe_intent_at')
            if intent_at and intent_at < stale_cutoff:
                result.append(data | {'uid': doc.id})

    if len(result) < limit:
        retrying_docs = db.collection('account_deletions').where('wipe_status', '==', 'retrying').stream()
        for doc in retrying_docs:
            if len(result) >= limit:
                break
            data = doc.to_dict()
            claimed_at = data.get('wipe_claimed_at')
            # Use the longer ``running_stale_after`` window so a queued-but-
            # not-yet-running retrying claim is not returned as a candidate
            # before the worker has had a chance to start.
            if claimed_at and claimed_at < running_cutoff:
                result.append(data | {'uid': doc.id})

    return result


@transactional
def _claim_deletion_wipe_txn(
    transaction, doc_ref, stale_after: timedelta, running_stale_after: timedelta
) -> str | None:
    """Atomically claim a wipe for re-enqueueing inside a Firestore transaction.

    Transitions ``wipe_status`` from ``failed``, stale ``pending``, stale
    ``deleting_auth`` (auth user verified gone by caller), stale ``running``
    (worker crashed mid-execution), or stale ``retrying`` to ``retrying`` so
    concurrent workers cannot re-enqueue the same wipe. Fresh ``pending``,
    ``deleting_auth``, and ``running`` markers (recently written by an
    in-progress deletion) are left untouched to avoid wiping data before
    Firebase auth deletion succeeds or interrupting a live worker. ``retrying``
    claims that are not yet stale are also refused (another worker owns them).
    """
    snapshot = doc_ref.get(transaction=transaction)
    if not snapshot.exists:
        return None
    data = snapshot.to_dict()
    status = data.get('wipe_status')
    now = datetime.now(timezone.utc)
    if status == 'deleting_auth':
        # Recoverable only after the caller verified the Firebase auth user is
        # gone. Re-validate the age inside the transaction so a fresh intent
        # from an in-progress deletion is never claimed prematurely.
        intent_at = data.get('wipe_intent_at')
        if intent_at and intent_at >= now - stale_after:
            return None
        transaction.update(doc_ref, {'wipe_status': 'retrying', 'wipe_claimed_at': now})
        return snapshot.id
    if status == 'pending':
        # Re-validate the pending marker age *inside* the transaction. The
        # reconciler query may have returned a stale record that was since
        # refreshed by a new delete request; claiming a fresh marker could
        # enqueue a wipe before Firebase auth deletion has succeeded.
        queued_at = data.get('wipe_queued_at')
        if queued_at and queued_at >= now - stale_after:
            return None
        transaction.update(doc_ref, {'wipe_status': 'retrying', 'wipe_claimed_at': now})
        return snapshot.id
    if status == 'running':
        # A ``running`` marker means the worker started executing. Only reclaim
        # it if it's stale beyond ``running_stale_after`` — the worker almost
        # certainly crashed or the pod was killed mid-execution. A fresh or
        # moderately recent ``running`` marker belongs to a live worker.
        running_at = data.get('wipe_running_at')
        if running_at and running_at >= now - running_stale_after:
            return None
        transaction.update(doc_ref, {'wipe_status': 'retrying', 'wipe_claimed_at': now})
        return snapshot.id
    if status == 'failed':
        transaction.update(doc_ref, {'wipe_status': 'retrying', 'wipe_claimed_at': now})
        return snapshot.id
    if status == 'retrying':
        claimed_at = data.get('wipe_claimed_at')
        # Use the longer ``running_stale_after`` window (not ``stale_after``)
        # because a retrying wipe was just claimed by the reconciler and
        # enqueued. If the worker queue is delayed, the task may sit queued
        # beyond ``stale_after`` (10 min) without transitioning to ``running``.
        # Using the short window would let the periodic reconciler enqueue
        # another copy every pass, causing duplicate wipes to race.
        if claimed_at and claimed_at < now - running_stale_after:
            # Stale claim (worker probably crashed). Re-claim it.
            transaction.update(doc_ref, {'wipe_claimed_at': now})
            return snapshot.id
    return None


def claim_deletion_wipe(
    uid: str,
    stale_after: timedelta = timedelta(minutes=10),
    running_stale_after: timedelta = DELETION_WIPE_RUNNING_STALE_AFTER,
) -> str | None:
    """Attempt to claim a pending/failed/stale wipe for re-enqueueing.

    Returns the uid if claimed (caller should enqueue the wipe), or ``None`` if
    another worker already owns a non-stale claim. This prevents the same wipe
    from being re-enqueued concurrently by multiple workers or scheduler runs.
    """
    doc_ref = db.collection('account_deletions').document(uid)
    transaction = db.transaction()
    return _claim_deletion_wipe_txn(transaction, doc_ref, stale_after, running_stale_after)


@transactional
def _claim_deletion_wipe_task_txn(transaction, doc_ref, running_stale_after: timedelta) -> str:
    """Claim a Cloud Tasks delivery before running an account-deletion wipe.

    The claim intentionally stays in ``retrying`` until the cleanup worker
    starts and ``background_wipe_user_data`` marks it ``running``. If the HTTP
    request is cancelled while waiting for a cleanup thread, a later delivery can
    retry without waiting for the long running-stale lease.
    """
    snapshot = doc_ref.get(transaction=transaction)
    if not snapshot.exists:
        return 'missing'

    data = snapshot.to_dict()
    status = data.get('wipe_status')
    now = datetime.now(timezone.utc)

    if status == 'completed':
        return 'completed'
    if status in ('cancelled', 'deleting_auth'):
        return 'not_actionable'
    if status == 'running':
        running_at = data.get('wipe_running_at')
        if running_at and running_at >= now - running_stale_after:
            return 'running'

    if status in ('pending', 'retrying', 'failed', 'running'):
        transaction.update(doc_ref, {'wipe_status': 'retrying', 'wipe_claimed_at': now})
        return 'claimed'

    return 'not_actionable'


def claim_deletion_wipe_for_task(uid: str, running_stale_after: timedelta = DELETION_WIPE_RUNNING_STALE_AFTER) -> str:
    """Claim an account-deletion wipe for a Cloud Tasks worker.

    Returns one of: ``claimed``, ``running``, ``completed``, ``missing``, or
    ``not_actionable``. Only ``claimed`` callers may run the destructive wipe.
    """
    doc_ref = db.collection('account_deletions').document(uid)
    transaction = db.transaction()
    return _claim_deletion_wipe_task_txn(transaction, doc_ref, running_stale_after)


def delete_user_data(uid: str):
    user_ref = db.collection('users').document(uid)
    root_exists = user_ref.get().exists

    # Enumerate subcollections live even when the root document is missing.
    # Firestore permits immediate children to survive a parent deletion; an
    # early "User not found" return would falsely mark the deletion complete.
    # This picks up
    # every retained or historical child document, including future additions.
    for sub in user_ref.collections():
        logger.info(f"Deleting subcollection {sub.id} for user {uid}")
        delete_collection_recursive(sub, client=db)

    if root_exists:
        logger.info(f"Deleting user document: {uid}")
        user_ref.delete()
    return {'status': 'ok', 'message': 'Account deleted successfully'}


# **************************************
# ************** Payments **************
# **************************************


def set_paypal_payment_details(uid: str, data: dict):
    user_ref = db.collection('users').document(uid)
    user_ref.update({'paypal_details': data})


def get_paypal_payment_details(uid: str):
    user_ref = db.collection('users').document(uid)
    user_data = user_ref.get().to_dict() or {}
    return user_data.get('paypal_details', None)


def set_default_payment_method(uid: str, payment_method_id: str):
    user_ref = db.collection('users').document(uid)
    user_ref.update({'default_payment_method': payment_method_id})


def get_default_payment_method(uid: str):
    user_ref = db.collection('users').document(uid)
    user_data = user_ref.get().to_dict() or {}
    return user_data.get('default_payment_method', None)


# **************************************
# ************* Language ***************
# **************************************


def get_user_language_preference(uid: str) -> str:
    """
    Get the user's preferred language.

    Args:
        uid: User ID

    Returns:
        Language code (e.g., 'en', 'vi') or empty string if not set
    """

    def fetch_language():
        user_ref = db.collection('users').document(uid)
        user_doc = user_ref.get(['language'])

        if user_doc.exists:
            user_data = user_doc.to_dict()
            return user_data.get('language', '')

        return ''  # Return empty string if not set

    # DESIGN DECISION: cache this typed user projection, not the full users/{uid} doc.
    #
    # Rationale:
    # - Language preference is a low-risk, frequently-read setting used during
    #   listen startup.
    # - Full user-doc caching is intentionally avoided because users/{uid} also
    #   contains entitlement, privacy, and data-protection fields.
    #
    # Safety: cache is disabled by default, Redis failures fall back to Firestore,
    # and set_user_language_preference() invalidates this namespace.
    return get_or_fetch(_USER_LANGUAGE_CACHE, uid, fetch_language)


def set_user_language_preference(uid: str, language: str) -> None:
    """
    Set the user's preferred language.

    Args:
        uid: User ID
        language: Language code (e.g., 'en', 'vi')
    """
    user_ref = db.collection('users').document(uid)
    user_ref.set({'language': language}, merge=True)
    invalidate(_USER_LANGUAGE_CACHE, uid)


def get_user_subscription(uid: str) -> Subscription:
    """Gets the user's subscription, creating a default free one if it doesn't exist."""
    user_ref = db.collection('users').document(uid)
    user_doc = user_ref.get(['subscription'])
    if user_doc.exists:
        user_data = user_doc.to_dict()
        if 'subscription' in user_data:
            sub_data = user_data['subscription']

            def subscription_payload(_snapshot: object) -> dict:
                if not isinstance(sub_data, dict):
                    raise TypeError('Firestore subscription payload must be a mapping')
                return dict(sub_data)

            return parse_snapshot_strict(Subscription, user_doc, payload_from_snapshot=subscription_payload)

    # If subscription doesn't exist for the user, create and return a default free plan.
    default_subscription = get_default_free_subscription()
    sub_to_store = default_subscription.model_dump()
    user_ref.set({'subscription': sub_to_store}, merge=True)
    return default_subscription


def get_existing_user_subscription(uid: str) -> Optional[Subscription]:
    """Gets the user's stored subscription without creating a default record."""
    user_ref = db.collection('users').document(uid)
    user_doc = user_ref.get(['subscription'])
    if not user_doc.exists:
        return None

    user_data = user_doc.to_dict()
    if 'subscription' not in user_data:
        return None

    sub_data = user_data['subscription']

    def subscription_payload(_snapshot: object) -> dict:
        if not isinstance(sub_data, dict):
            raise TypeError('Firestore subscription payload must be a mapping')
        return dict(sub_data)

    return parse_snapshot_strict(Subscription, user_doc, payload_from_snapshot=subscription_payload)


def get_user_valid_subscription(uid: str) -> Optional[Subscription]:
    """
    Gets the user's subscription if it is currently valid for use.

    A subscription is considered valid if:
    - It's a basic (free) plan with 'active' status.
    - It's a paid plan with a 'current_period_end' that has not passed yet.
      This allows users to use the service until the end of the billing period
      they paid for, even after cancelling.

    Returns the Subscription object if valid, otherwise None.
    """
    subscription = get_user_subscription(uid)

    if subscription.plan is PlanType.free:
        return subscription if subscription.status == SubscriptionStatus.active else None

    if subscription.is_current_paid_entitlement():
        return subscription

    # Fallback to default basic subscription
    return get_default_free_subscription()
