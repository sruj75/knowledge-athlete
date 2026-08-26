"""Neutral Redis run locks for idempotent background jobs.

The key prefix and TTL deliberately match the retired wearable-sync owner so
rolling revisions serialize durable account-deletion delivery against exactly
the same Redis keys as before S-02.
"""

import logging
import uuid
from typing import Optional

from database.redis_connection import get_redis_client

logger = logging.getLogger(__name__)

RUN_LOCK_KEY_PREFIX = "sync_job_lock:"
RUN_LOCK_TTL_SECONDS = 1800

_RELEASE_LOCK_SCRIPT = """
if redis.call('get', KEYS[1]) == ARGV[1] then
    return redis.call('del', KEYS[1])
end
return 0
"""


def try_acquire_job_run_lock(job_id: str) -> Optional[str]:
    """Acquire a compare-delete run lock, or return ``None`` if held."""
    token = str(uuid.uuid4())
    acquired = get_redis_client().set(f"{RUN_LOCK_KEY_PREFIX}{job_id}", token, nx=True, ex=RUN_LOCK_TTL_SECONDS)
    return token if acquired else None


def release_job_run_lock(job_id: str, token: str) -> None:
    """Release the run lock only when ``token`` still owns it."""
    try:
        get_redis_client().eval(_RELEASE_LOCK_SCRIPT, 1, f"{RUN_LOCK_KEY_PREFIX}{job_id}", token)
    except Exception as error:
        # Best effort: Redis expiry prevents a stuck lock, while propagating the
        # failure could turn an otherwise successful idempotent job into a retry.
        logger.warning("release_job_run_lock failed for %s: %s", job_id, error)
