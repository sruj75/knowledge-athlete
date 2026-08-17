"""Round-trip tests for Redis cache serialization helpers in database/redis_db.py."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

import pytest

import database.redis_db as redis_db


class _FakeRedis:
    def __init__(self) -> None:
        self._store: Dict[str, Any] = {}

    def set(self, key: str, value: Any, ex: Optional[int] = None) -> None:
        self._store[key] = value

    def get(self, key: str) -> Optional[Any]:
        return self._store.get(key)

    def expire(self, key: str, ttl: int) -> None:
        return None

    def mget(self, keys: List[str]) -> List[Optional[Any]]:
        return [self._store.get(key) for key in keys]


@pytest.fixture
def fake_redis(monkeypatch: pytest.MonkeyPatch) -> _FakeRedis:
    client = _FakeRedis()
    monkeypatch.setattr(redis_db, "r", client)
    return client


def test_geolocation_legacy_literal_round_trip(fake_redis: _FakeRedis) -> None:
    fake_redis._store["users:uid-legacy:geolocation"] = b"{'lat': 1.0, 'lng': 2.0}"
    assert redis_db.get_cached_user_geolocation("uid-legacy") == {"lat": 1.0, "lng": 2.0}
