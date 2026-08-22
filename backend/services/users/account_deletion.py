from __future__ import annotations

import logging

import time
from typing import Any, Callable, Literal, TypedDict, cast

from database import users as users_db
from database.vector_db import purge_user_vectors
from utils.billing.service import cancel_subscription_for_account_deletion
from utils.cloud_tasks import enqueue_account_deletion_wipe, is_account_deletion_dispatch_enabled
from utils.executors import cleanup_executor, submit_with_context
from utils.log_sanitizer import sanitize
from utils.other import endpoints as auth
from utils.posthog_telemetry import emit_posthog_event

logger = logging.getLogger(__name__)


class PurgeFailure(TypedDict):
    operation: str
    error: str


class PurgeResult(TypedDict):
    required_failures: list[PurgeFailure]
    pinecone_namespaces_purged: int


ACCOUNT_DELETION_WIPE_COMPLETED = 'Account Deletion Wipe Completed'
ACCOUNT_DELETION_WIPE_FAILED = 'Account Deletion Wipe Failed'


def purge_pinecone_user_data(uid: str) -> PurgeResult:
    """Run the exact S-24-owned Pinecone purge before Firestore deletion."""
    result: PurgeResult = {
        'required_failures': [],
        'pinecone_namespaces_purged': 0,
    }
    try:
        result['pinecone_namespaces_purged'] = purge_user_vectors(uid)
    except Exception as e:
        result['required_failures'].append({'operation': 'pinecone_user_vectors', 'error': sanitize(str(e))})
        logger.error(f'delete_account Pinecone purge failed for {uid}: {sanitize(str(e))}')

    return result


def _required_failures_from_purge_result(purge_result: object) -> list[PurgeFailure]:
    if not isinstance(purge_result, dict):
        return []
    purge_result_dict = cast(dict[str, object], purge_result)
    required_failures_value = purge_result_dict.get('required_failures', [])
    if not isinstance(required_failures_value, list):
        return []
    required_failure_items = cast(list[object], required_failures_value)
    failures: list[PurgeFailure] = []
    for failure in required_failure_items:
        if not isinstance(failure, dict):
            continue
        failure_dict = cast(dict[str, object], failure)
        failures.append(
            {'operation': str(failure_dict.get('operation', 'unknown')), 'error': str(failure_dict.get('error', ''))}
        )
    return failures


# Service-level PostHog distinct_id only. Never re-identify a deleted Firebase UID
# as a person profile (success path runs after Auth + Firestore wipe).
_ACCOUNT_DELETION_TELEMETRY_DISTINCT_ID = 'omi-service:account-deletion'


def _emit_deletion_telemetry(uid: str, event: str, properties: dict[str, object]) -> None:
    logger.info(
        'account_deletion_telemetry event=%s duration_seconds=%s pinecone_namespaces_purged=%s '
        'required_failure_count=%s failed_operations=%s retry_count=%s terminal=%s',
        event,
        properties.get('duration_seconds'),
        properties.get('pinecone_namespaces_purged'),
        properties.get('required_failure_count'),
        properties.get('failed_operations'),
        properties.get('retry_count'),
        properties.get('terminal'),
    )
    # Drop any accidental uid-bearing keys; person processing is disabled so
    # completion/failure cannot recreate a profile for the deleted account.
    safe_properties = {key: value for key, value in properties.items() if key not in {'uid', 'user_id', 'distinct_id'}}
    safe_properties['$process_person_profile'] = False
    emit_posthog_event(_ACCOUNT_DELETION_TELEMETRY_DISTINCT_ID, event, safe_properties)


class AccountCleanupFailure(RuntimeError):
    """A provider or retained Firestore cleanup failed before completion."""

    def __init__(self, operation: str, purge_result: PurgeResult, cause: Exception):
        super().__init__(str(cause))
        self.operation = operation
        self.purge_result = purge_result


def _empty_purge_result() -> PurgeResult:
    return {
        'required_failures': [],
        'pinecone_namespaces_purged': 0,
    }


def _perform_account_cleanup(uid: str) -> PurgeResult:
    """Compose every required external cleanup behind the durable worker."""
    current_operation = 'billing_subscription'
    purge_result = _empty_purge_result()
    try:
        _cancel_subscription_for_account_deletion(uid)
        current_operation = 'firebase_auth'
        try:
            auth.delete_account(uid)
        except Exception as e:
            err = str(e).upper()
            if 'USER_NOT_FOUND' in err or 'NO USER RECORD' in err:
                logger.info('delete_account worker observed Firebase Auth user already absent')
            else:
                raise
        current_operation = 'pinecone_user_vectors'
        purge_result = purge_pinecone_user_data(uid)
        required_failures = _required_failures_from_purge_result(purge_result)
        if required_failures:
            failed_operations = ', '.join(failure['operation'] for failure in required_failures)
            raise RuntimeError(f'required derived purge failed: {failed_operations}')
        current_operation = 'firestore_user_data'
        wipe_result = users_db.delete_user_data(uid)
        if wipe_result.get('status') != 'ok':
            raise RuntimeError('authoritative Firestore user-data wipe did not complete')
    except Exception as e:
        raise AccountCleanupFailure(current_operation, purge_result, e) from e
    return purge_result


def background_wipe_user_data(uid: str, retry_count: int = 0, terminal: bool = False) -> bool:
    started_at = time.monotonic()
    current_operation = 'wipe_running_marker'
    purge_result = _empty_purge_result()
    try:
        # Transition to ``running`` so the reconciler can distinguish a
        # genuinely orphaned ``pending`` marker (queued but never started)
        # from a wipe that is actively executing. Without this, a slow wipe
        # could be duplicate-claimed after the short ``pending`` stale window.
        users_db.mark_user_deletion_wipe_running(uid)
        # The durable marker and queue claim are the authority for every
        # irreversible step below. In particular, do not cancel billing or
        # remove Firebase Auth from the request thread: a queue NotFound must
        # leave an account usable and recoverable.
        purge_result = _perform_account_cleanup(uid)
        logger.info('delete_account background wipe complete')
    except Exception as e:
        if isinstance(e, AccountCleanupFailure):
            current_operation = e.operation
            purge_result = e.purge_result
        logger.error(f'delete_account background wipe failed for {uid}: {sanitize(str(e))}')
        # Mark the wipe as failed so a reconciliation worker can retry. Do NOT mark
        # completed — that would hide a partial wipe from the recovery path.
        try:
            users_db.mark_user_deletion_wipe_failed(uid)
        except Exception as persist_err:
            logger.error(f'delete_account wipe status persist failed for {uid}: {sanitize(str(persist_err))}')
        required_failures = _required_failures_from_purge_result(purge_result)
        failed_operations = [failure['operation'] for failure in required_failures] or [current_operation]
        _emit_deletion_telemetry(
            uid,
            ACCOUNT_DELETION_WIPE_FAILED,
            {
                'failed_operations': failed_operations,
                'retry_count': max(0, retry_count),
                'terminal': terminal,
            },
        )
        return False
    else:
        try:
            users_db.mark_user_deletion_wipe_completed(uid)
        except Exception as e:
            logger.error(f'delete_account wipe status persist failed for {uid}: {sanitize(str(e))}')
            try:
                users_db.mark_user_deletion_wipe_failed(uid)
            except Exception as persist_err:
                logger.error(f'delete_account wipe status persist failed for {uid}: {sanitize(str(persist_err))}')
            _emit_deletion_telemetry(
                uid,
                ACCOUNT_DELETION_WIPE_FAILED,
                {
                    'failed_operations': ['wipe_completed_marker'],
                    'retry_count': max(0, retry_count),
                    'terminal': terminal,
                },
            )
            return False
        required_failures = _required_failures_from_purge_result(purge_result)
        _emit_deletion_telemetry(
            uid,
            ACCOUNT_DELETION_WIPE_COMPLETED,
            {
                'duration_seconds': round(time.monotonic() - started_at, 3),
                'pinecone_namespaces_purged': purge_result.get('pinecone_namespaces_purged', 0),
                'required_failure_count': len(required_failures),
                'failed_operations': [failure['operation'] for failure in required_failures],
            },
        )
        return True


def enqueue_deletion_wipe(uid: str, wipe_job_id: str):
    """Dispatch the account-deletion wipe using the configured durable mechanism."""
    if is_account_deletion_dispatch_enabled() is True:
        enqueue_account_deletion_wipe(wipe_job_id)
        return
    # Inline dispatch is retained solely for deterministic local/dev/test
    # execution. Production startup rejects this mode before serving traffic.
    submit_with_context(cleanup_executor, background_wipe_user_data, uid)


def _mark_wipe_failed_after_enqueue_error(uid: str, error: Exception):
    try:
        users_db.mark_user_deletion_wipe_failed(uid)
    except Exception as persist_err:
        logger.error(
            f'delete_account enqueue failure status persist failed for {uid}: {sanitize(str(persist_err))}; '
            f'original enqueue error: {sanitize(str(error))}'
        )


def _retry_firestore_write(
    fn: Callable[[], Any],
    *,
    uid: str,
    fail_msg: str,
    on_failure: Literal['raise', 'log'],
    max_attempts: int = 3,
    retry_delay: float = 0.5,
) -> Any:
    """Retry a transient Firestore write, then raise or log on persistent failure."""
    last_err: Exception | None = None
    for attempt in range(max_attempts):
        try:
            return fn()
        except Exception as e:
            last_err = e
            if attempt < max_attempts - 1:
                time.sleep(retry_delay * (attempt + 1))
    assert last_err is not None
    msg = f'{fail_msg} after {max_attempts} attempts for {uid}: {sanitize(str(last_err))}'
    if on_failure == 'raise':
        raise Exception(msg)
    logger.critical(msg)


def _cancel_subscription_for_account_deletion(uid: str) -> None:
    subscription_id = None
    try:
        sub = users_db.get_user_subscription(uid)
        subscription_id = getattr(sub, 'billing_subscription_id', None) if sub else None
        if not subscription_id:
            return
        canceled = cancel_subscription_for_account_deletion(subscription_id)
        if not canceled:
            raise RuntimeError('billing provider did not confirm cancellation')
    except Exception as e:
        raw_error = str(e)
        sanitized_error = sanitize(raw_error)
        if not isinstance(
            sanitized_error, str
        ):  # pyright: ignore[reportUnnecessaryIsInstance]  # tests stub sanitize with MagicMock
            sanitized_error = raw_error
        _retry_firestore_write(
            lambda: users_db.mark_user_deletion_billing_failed(uid, subscription_id, sanitized_error),
            uid=uid,
            fail_msg='delete_account billing failure status persist failed',
            on_failure='log',
        )
        logger.error(f'delete_account billing cancellation failed for {uid}: {sanitize(str(e))}')
        raise


def start_account_deletion(uid: str) -> dict[str, str]:
    # Persist the authoritative, actionable intent before dispatch. This state
    # is enough for reconciliation to recover a failed queue handoff, while the
    # Cloud Tasks handler claim fences all destructive work. If either write or
    # dispatch fails, no Firebase Auth or billing mutation has happened.
    wipe_intent = _retry_firestore_write(
        lambda: users_db.mark_user_deletion_wipe_intent(uid),
        uid=uid,
        fail_msg='Failed to persist deletion-wipe intent',
        on_failure='raise',
    )
    wipe_job_id = wipe_intent.get('wipe_job_id') if isinstance(wipe_intent, dict) else None
    if not isinstance(wipe_job_id, str) or not wipe_job_id:
        raise RuntimeError('deletion-wipe intent did not persist a wipe_job_id')
    dispatch_claimed = wipe_intent.get('dispatch_claimed') is True if isinstance(wipe_intent, dict) else False
    if not dispatch_claimed:
        logger.info('delete_account joined existing durable deletion intent')
        return {'status': 'ok', 'message': 'Account deletion started'}

    # The pending marker is persisted before enqueue. A failed enqueue is
    # recorded as failed and is therefore independently recoverable by the
    # reconciler; queue delivery accelerates the wipe but is not its only
    # durability boundary.
    pending_transitioned = _retry_firestore_write(
        lambda: users_db.mark_user_deletion_wipe_started(uid, wipe_job_id),
        uid=uid,
        fail_msg='delete_account marker transition to pending failed',
        on_failure='raise',
    )
    if pending_transitioned is not True:
        # Another execution owns the durable authority. Do not move its marker
        # backwards or dispatch a duplicate task.
        logger.info('delete_account queue transition already owned by another request')
        return {'status': 'ok', 'message': 'Account deletion started'}

    try:
        enqueue_deletion_wipe(uid, wipe_job_id)
    except Exception as e:
        _mark_wipe_failed_after_enqueue_error(uid, e)
        logger.warning('delete_account queue acceleration failed; durable reconciliation will retry')
        # The actionable marker is committed. Queue dispatch is only an
        # acceleration path; reconciliation owns eventual completion.
        return {'status': 'ok', 'message': 'Account deletion started'}

    logger.info('delete_account accepted durable deletion intent and queue acceleration')
    return {'status': 'ok', 'message': 'Account deletion started'}


def _is_auth_user_gone(uid: str) -> bool:
    """Check whether the Firebase auth user for ``uid`` no longer exists.

    Returns ``True`` if the user was already deleted (``USER_NOT_FOUND`` or
    equivalent). Returns ``False`` on any other error — fail safe so a transient
    Firebase outage does not trigger a data wipe for a user whose auth account
    may still exist.
    """
    try:
        auth.get_user(uid)
        return False
    except Exception as e:
        err = str(e).upper()
        if 'USER_NOT_FOUND' in err or 'NO USER RECORD' in err:
            return True
        # Indeterminate — do NOT treat as gone.
        logger.warning(f'delete_account auth-user-gone check indeterminate for {uid}: {sanitize(str(e))}')
        return False


def reconcile_pending_deletion_wipes(limit: int = 100) -> dict[str, int]:
    """Re-enqueue account-deletion wipes that were cancelled or failed.

    Called by a periodic worker (cron, Cloud Scheduler, or startup hook) to drain
    the ``wipe_status in ('pending', 'failed', 'retrying')`` backlog left behind
    when a durable task enqueue or worker execution failed.

    Also recovers stale ``'deleting_auth'`` records — markers where the deletion
    intent was written but never transitioned to ``'pending'`` (usually a crash
    or deploy after ``auth.delete_account()`` succeeded). For these records, the
    Firebase auth user is verified gone *before* claiming and re-enqueueing, so a
    transient Firebase outage or a record left by an in-progress deletion cannot
    trigger a premature data wipe for a user whose auth account still exists.

    Each wipe is atomically claimed via a Firestore transaction before
    re-enqueueing, so concurrent workers or overlapping scheduler runs cannot
    double-enqueue the same wipe.

    Returns a summary dict with counts of re-enqueued and skipped wipes.
    """
    requeued = 0
    skipped = 0
    try:
        pending = users_db.get_pending_deletion_wipes(limit=limit)
    except Exception as e:
        logger.error(f'delete_account reconciliation query failed: {sanitize(str(e))}')
        return {'requeued': 0, 'skipped': 0, 'error': 1}

    for record in pending:
        uid = record.get('uid')
        if uid is not None and not isinstance(uid, str):
            skipped += 1
            continue
        if not uid:
            skipped += 1
            continue
        # P1 recovery: a 'deleting_auth' record means the intent was written but
        # the marker was never transitioned to 'pending'. Verify the Firebase
        # auth user is actually gone before claiming it, so we never wipe data
        # for a user whose auth account may still exist.
        if record.get('wipe_status') == 'deleting_auth':
            if not _is_auth_user_gone(uid):
                skipped += 1
                logger.info(
                    f'delete_account reconciliation skipping deleting_auth record for {uid} — auth user still exists'
                )
                continue
        # Atomically claim the wipe to prevent concurrent re-enqueueing by
        # multiple workers. If the claim fails, another worker owns it.
        try:
            claimed_uid = users_db.claim_deletion_wipe(uid)
        except Exception as e:
            logger.error(f'delete_account reconciliation claim failed for {uid}: {sanitize(str(e))}')
            skipped += 1
            continue
        if claimed_uid is None:
            skipped += 1
            continue
        if record.get('wipe_status') == 'running':
            _emit_deletion_telemetry(
                uid,
                ACCOUNT_DELETION_WIPE_FAILED,
                {'failed_operations': ['stale_running_wipe'], 'retry_count': 0, 'terminal': False},
            )
        wipe_job_id = record.get('wipe_job_id')
        if not isinstance(wipe_job_id, str) or not wipe_job_id:
            try:
                wipe_job_id = users_db.ensure_deletion_wipe_job_id(uid)
            except Exception as e:
                logger.error(f'delete_account reconciliation job-id recovery failed for {uid}: {sanitize(str(e))}')
                _mark_wipe_failed_after_enqueue_error(uid, e)
                skipped += 1
                continue
        if not isinstance(wipe_job_id, str) or not wipe_job_id:
            error = RuntimeError('deletion-wipe job id missing after recovery')
            logger.error(f'delete_account reconciliation cannot dispatch {uid}: {error}')
            _mark_wipe_failed_after_enqueue_error(uid, error)
            skipped += 1
            continue
        try:
            enqueue_deletion_wipe(uid, wipe_job_id)
        except Exception as e:
            logger.error(f'delete_account reconciliation enqueue failed for {uid}: {sanitize(str(e))}')
            _mark_wipe_failed_after_enqueue_error(uid, e)
            skipped += 1
            continue
        requeued += 1
        logger.info(f'delete_account reconciliation re-enqueued wipe for {uid}')

    if requeued:
        logger.info(f'delete_account reconciliation: re-enqueued {requeued}, skipped {skipped}')
    return {'requeued': requeued, 'skipped': skipped}
