"""Behavioral coverage for the retained generic Redis cache surface."""

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


def test_generic_cache_json_round_trip(fake_redis: _FakeRedis) -> None:
    value = {"segments": [{"start": 1.0, "end": 2.0}]}

    redis_db.set_generic_cache("vad/example", value, ttl=60)

    assert redis_db.get_generic_cache("vad/example") == value


def test_retired_geolocation_cache_is_not_part_of_the_redis_surface() -> None:
    # Static public-surface tripwire: S-23 removed the only production owner of
    # this legacy namespace, so S-26 must not retain an unowned reader.
    assert not hasattr(redis_db, "get_cached_user_geolocation")
