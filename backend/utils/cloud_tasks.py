"""Shared Cloud Tasks dispatch and OIDC verification primitives."""

import json
import logging
import hashlib
import os
import uuid
from typing import Any, Dict, Literal, NamedTuple, Optional
from urllib.parse import urlparse

from fastapi import HTTPException, Request
from google.api_core.exceptions import AlreadyExists
from google.auth.transport import requests as google_auth_requests
from google.cloud import tasks_v2
from google.oauth2 import id_token
from google.protobuf import duration_pb2

logger = logging.getLogger(__name__)

# Must remain below the account-deletion run-lock TTL so a lock cannot expire under a live task.
DISPATCH_DEADLINE_SECONDS = 1500

_tasks_client: Optional[tasks_v2.CloudTasksClient] = None
_google_auth_request: Optional[google_auth_requests.Request] = None


class AccountDeletionTaskAuthentication(NamedTuple):
    """Verified Cloud Tasks identity plus its narrowly scoped audience lane."""

    retry_count: int
    audience: Literal['account_deletion', 'legacy']


def _get_tasks_client() -> tasks_v2.CloudTasksClient:
    global _tasks_client
    if _tasks_client is None:
        _tasks_client = tasks_v2.CloudTasksClient()
    return _tasks_client


def _get_auth_request() -> google_auth_requests.Request:
    global _google_auth_request
    if _google_auth_request is None:
        _google_auth_request = google_auth_requests.Request()
    return _google_auth_request


def _account_deletion_oidc_audience() -> str:
    return os.getenv('ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE', '')


def _account_deletion_invoker_sa() -> str:
    return os.getenv('ACCOUNT_DELETION_TASKS_INVOKER_SA', '')


def _legacy_account_deletion_oidc_audience() -> str:
    return os.getenv('ACCOUNT_DELETION_LEGACY_TASKS_OIDC_AUDIENCE', '')


def _legacy_account_deletion_invoker_sa() -> str:
    return os.getenv('ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA', '')


def is_account_deletion_dispatch_enabled() -> bool:
    return os.getenv('ACCOUNT_DELETION_DISPATCH_MODE', 'inline') == 'cloud_tasks'


def validate_account_deletion_dispatch_configuration() -> None:
    """Reject a production process that could execute deletion wipes inline.

    Account deletion is intentionally different from sync's staged rollout: an
    accepted deletion request must have one durable, OIDC-protected execution
    owner. Keeping this check at process startup prevents a missing deploy
    binding from silently falling back to the in-process dispatcher.
    """
    stage = os.getenv('OMI_ENV_STAGE', '').strip().lower()
    if stage != 'prod' and not is_account_deletion_dispatch_enabled():
        return

    if not is_account_deletion_dispatch_enabled():
        raise RuntimeError('production requires ACCOUNT_DELETION_DISPATCH_MODE=cloud_tasks')

    required_env = (
        'ACCOUNT_DELETION_TASKS_PROJECT',
        'ACCOUNT_DELETION_TASKS_LOCATION',
        'ACCOUNT_DELETION_TASKS_INVOKER_SA',
        'ACCOUNT_DELETION_TASKS_QUEUE',
        'ACCOUNT_DELETION_HANDLER_URL',
        'ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE',
        'ACCOUNT_DELETION_LEGACY_TASKS_OIDC_AUDIENCE',
        'ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA',
    )
    missing = [name for name in required_env if not os.getenv(name, '').strip()]
    if missing:
        raise RuntimeError(f'account-deletion Cloud Tasks config is incomplete: {", ".join(missing)}')

    handler_url = os.environ['ACCOUNT_DELETION_HANDLER_URL']
    audience = os.environ['ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE']
    if urlparse(handler_url).scheme != 'https' or urlparse(audience).scheme != 'https':
        raise RuntimeError('account-deletion handler URL and OIDC audience must use HTTPS')
    if audience != handler_url:
        raise RuntimeError('account-deletion OIDC audience must exactly match the canonical handler URL')


def get_account_deletion_tasks_max_attempts() -> int:
    return int(os.getenv('ACCOUNT_DELETION_TASKS_MAX_ATTEMPTS', '5'))


def _enqueue_named_task(
    queue: str,
    url: str,
    task_id: str,
    payload: Dict[str, Any],
) -> None:
    """Enqueue one named HTTP task. Duplicate names are treated as success —
    Cloud Tasks deduplicates named tasks. Any other failure raises."""
    project = os.getenv('ACCOUNT_DELETION_TASKS_PROJECT', '')
    location = os.getenv('ACCOUNT_DELETION_TASKS_LOCATION', '')
    invoker_sa = _account_deletion_invoker_sa()
    audience = _account_deletion_oidc_audience()
    if not all([project, location, queue, url, invoker_sa, audience]):
        raise RuntimeError('account-deletion Cloud Tasks config is incomplete')
    if urlparse(url).scheme != 'https' or audience != url:
        raise RuntimeError('account-deletion task target must use one exact HTTPS handler URL and audience')

    client = _get_tasks_client()
    parent = client.queue_path(project, location, queue)
    task = tasks_v2.Task(
        name=client.task_path(project, location, queue, task_id),
        http_request=tasks_v2.HttpRequest(
            http_method=tasks_v2.HttpMethod.POST,
            url=url,
            headers={'Content-Type': 'application/json'},
            body=json.dumps(payload).encode(),
            oidc_token=tasks_v2.OidcToken(
                service_account_email=invoker_sa,
                audience=audience,
            ),
        ),
        dispatch_deadline=duration_pb2.Duration(seconds=DISPATCH_DEADLINE_SECONDS),
    )
    try:
        client.create_task(parent=parent, task=task)  # type: ignore[reportUnknownMemberType]  # google.cloud.tasks_v2 partially untyped
    except AlreadyExists:
        logger.info('task %s already enqueued, skipping duplicate', task_id)


def enqueue_account_deletion_wipe(wipe_job_id: str) -> None:
    """Wake one durable deletion job without exposing a user identifier.

    The Firestore job is canonical. Cloud Tasks diagnostics must not contain a
    Firebase uid; the OIDC handler resolves the uid only after looking up this
    opaque job identifier.
    """
    if not wipe_job_id:
        raise ValueError('wipe_job_id must be non-empty')
    job_hash = hashlib.sha256(wipe_job_id.encode('utf-8')).hexdigest()[:32]
    task_id = f"account-delete-{job_hash}-{uuid.uuid4().hex}"
    _enqueue_named_task(
        os.getenv('ACCOUNT_DELETION_TASKS_QUEUE', ''),
        os.getenv('ACCOUNT_DELETION_HANDLER_URL', ''),
        task_id,
        {'job_id': wipe_job_id},
    )


def _verify_cloud_tasks_oidc(request: Request, *, audience: str, invoker_sa: str, log_failure: bool = True) -> int:
    """Verify a configured task audience and issuer; returns task retry count.

    Sync function on purpose — verify_oauth2_token fetches Google certs over
    HTTP, and FastAPI runs sync dependencies in the threadpool.
    """
    if not audience or not invoker_sa:
        # Env unset: this service is not a task target (e.g. main backend
        # running the shared image) — never accept task traffic.
        raise HTTPException(status_code=403, detail='Task dispatch not configured on this service')

    auth_header = request.headers.get('authorization', '')
    if not auth_header.startswith('Bearer '):
        raise HTTPException(status_code=403, detail='Missing bearer token')

    try:
        claims: Any = id_token.verify_oauth2_token(auth_header[len('Bearer ') :], _get_auth_request(), audience=audience)  # type: ignore[reportUnknownMemberType]  # google.oauth2.id_token partially untyped
    except Exception as e:
        # Distinguishes bad tokens from transient JWKS-fetch failures in logs
        if log_failure:
            logger.warning('OIDC token verification failed: %s', e)
        raise HTTPException(status_code=403, detail='Invalid OIDC token')

    if claims.get('email') != invoker_sa or not claims.get('email_verified'):
        raise HTTPException(status_code=403, detail='Unexpected token identity')

    try:
        return int(request.headers.get('x-cloudtasks-taskretrycount', '0'))
    except ValueError:
        return 0


def verify_account_deletion_cloud_tasks_oidc(request: Request) -> AccountDeletionTaskAuthentication:
    """Verify deletion tasks, with a bounded compatibility path for queued legacy UID tasks.

    Before opaque job IDs, account-deletion tasks inherited sync's OIDC
    audience. Verify that former audience only during the queue drain window;
    the route rejects it for new job-ID payloads before any lookup or mutation.
    """
    deletion_audience = _account_deletion_oidc_audience()
    try:
        retry_count = _verify_cloud_tasks_oidc(
            request,
            audience=deletion_audience,
            invoker_sa=_account_deletion_invoker_sa(),
            log_failure=False,
        )
        return AccountDeletionTaskAuthentication(retry_count=retry_count, audience='account_deletion')
    except HTTPException as deletion_error:
        legacy_audience = _legacy_account_deletion_oidc_audience()
        legacy_invoker_sa = _legacy_account_deletion_invoker_sa()
        if not deletion_audience or not legacy_audience or legacy_audience == deletion_audience:
            raise deletion_error

        retry_count = _verify_cloud_tasks_oidc(
            request,
            audience=legacy_audience,
            invoker_sa=legacy_invoker_sa,
        )
        return AccountDeletionTaskAuthentication(retry_count=retry_count, audience='legacy')
