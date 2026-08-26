"""
Fake Redis using fakeredis.

Provides a hermetic in-memory Redis replacement that supports
the same API surface as redis.Redis — get, set, delete, expire,
JSON operations, etc.
"""

from typing import Optional

import fakeredis

# Module-level singleton
_fake_redis: Optional[fakeredis.FakeRedis] = None


def get_fake_redis() -> fakeredis.FakeRedis:
    """Return the shared FakeRedis instance."""
    if _fake_redis is None:
        raise RuntimeError("FakeRedis not initialized — call setup_fake_redis() first")
    return _fake_redis


def setup_fake_redis() -> fakeredis.FakeRedis:
    """Create and register the global FakeRedis singleton."""
    global _fake_redis
    _fake_redis = fakeredis.FakeRedis()
    return _fake_redis


def teardown_fake_redis():
    """Clear the singleton."""
    global _fake_redis
    _fake_redis = None


def patch_redis_client():
    """Inject the shared fake through the production Redis boundary."""
    from database.redis_connection import set_redis_client_for_testing

    set_redis_client_for_testing(get_fake_redis())
