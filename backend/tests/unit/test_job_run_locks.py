from unittest.mock import MagicMock, patch

from database import job_run_locks


def test_generic_run_lock_keeps_existing_redis_key_and_ttl_contract() -> None:
    redis = MagicMock()
    redis.set.return_value = True

    with patch.object(job_run_locks, "get_redis_client", return_value=redis), patch.object(
        job_run_locks.uuid, "uuid4", return_value="token"
    ):
        assert job_run_locks.try_acquire_job_run_lock("account:u-1") == "token"

    redis.set.assert_called_once_with(
        "sync_job_lock:account:u-1",
        "token",
        nx=True,
        ex=job_run_locks.RUN_LOCK_TTL_SECONDS,
    )


def test_generic_run_lock_returns_none_when_already_held() -> None:
    redis = MagicMock()
    redis.set.return_value = False

    with patch.object(job_run_locks, "get_redis_client", return_value=redis):
        assert job_run_locks.try_acquire_job_run_lock("account-deletion:u-1") is None


def test_generic_run_lock_release_is_compare_and_delete() -> None:
    redis = MagicMock()

    with patch.object(job_run_locks, "get_redis_client", return_value=redis):
        job_run_locks.release_job_run_lock("account-deletion:u-1", "token")

    redis.eval.assert_called_once_with(
        job_run_locks._RELEASE_LOCK_SCRIPT,
        1,
        "sync_job_lock:account-deletion:u-1",
        "token",
    )
