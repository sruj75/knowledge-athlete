"""One lazy Redis connection boundary for retained coordination and caches."""

from __future__ import annotations

import os
from threading import Lock
from typing import Any

import redis


class RedisConfigurationError(RuntimeError):
    """The selected runtime profile cannot establish its required Redis transport."""


_client: Any | None = None
_client_lock = Lock()


def get_redis_client() -> Any:
    """Return the process-scoped client, constructing it only on first use."""
    global _client
    if _client is None:
        with _client_lock:
            if _client is None:
                _client = _create_redis_client()
    return _client


def _create_redis_client() -> Any:
    stage = os.getenv('OMI_ENV_STAGE', '').strip().lower()
    hosted = stage in {'dev', 'prod'}
    host = os.getenv('REDIS_DB_HOST', '').strip()
    if not host:
        raise RedisConfigurationError('REDIS_DB_HOST is required')
    port_raw = os.getenv('REDIS_DB_PORT', '6379').strip()
    try:
        port = int(port_raw)
    except ValueError as error:
        raise RedisConfigurationError('REDIS_DB_PORT must be an integer') from error
    if port <= 0 or port > 65535:
        raise RedisConfigurationError('REDIS_DB_PORT must be between 1 and 65535')

    password = os.getenv('REDIS_DB_PASSWORD')
    kwargs: dict[str, Any] = {
        'host': host,
        'port': port,
        'username': 'default',
        'password': password or None,
        'health_check_interval': 30,
    }
    if hosted:
        if not password:
            raise RedisConfigurationError('REDIS_DB_PASSWORD is required for hosted Redis')
        ca_pem = os.getenv('REDIS_DB_CA_CERT_PEM', '').strip()
        if not ca_pem:
            raise RedisConfigurationError('REDIS_DB_CA_CERT_PEM is required for hosted Redis')
        kwargs.update(
            ssl=True,
            ssl_cert_reqs='required',
            ssl_check_hostname=True,
            ssl_ca_data=ca_pem,
        )
    return redis.Redis(**kwargs)


def set_redis_client_for_testing(client: Any) -> None:
    """Inject the hermetic adapter used by tests and the offline harness."""
    global _client
    with _client_lock:
        _client = client


def reset_redis_client_for_testing() -> None:
    global _client
    with _client_lock:
        _client = None
