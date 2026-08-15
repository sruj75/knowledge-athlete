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


def test_geolocation_json_round_trip(fake_redis: _FakeRedis) -> None:
    geo = {"lat": 37.77, "lng": -122.42, "city": "San Francisco"}
    redis_db.cache_user_geolocation("uid-1", geo)
    assert redis_db.get_cached_user_geolocation("uid-1") == geo


def test_geolocation_omits_unset_optional_fields(fake_redis: _FakeRedis) -> None:
    """A cached geolocation must stay parseable by a reader still using ``eval()``.

    ``Geolocation.model_dump()`` carries ``None`` for google_place_id/address/
    location_type. Serialized as JSON ``null`` those crashed pusher's legacy
    reader with ``NameError: name 'null' is not defined``, and the failing
    conversation was then marked discarded.
    """
    redis_db.cache_user_geolocation(
        "uid-1",
        {
            "google_place_id": None,
            "latitude": 37.77,
            "longitude": -122.42,
            "address": None,
            "location_type": None,
        },
    )

    raw = fake_redis._store["users:uid-1:geolocation"]
    assert "null" not in raw
    assert eval(raw) == {"latitude": 37.77, "longitude": -122.42}  # noqa: S307 — legacy reader
    assert redis_db.get_cached_user_geolocation("uid-1") == {"latitude": 37.77, "longitude": -122.42}


def test_geolocation_legacy_literal_round_trip(fake_redis: _FakeRedis) -> None:
    fake_redis._store["users:uid-legacy:geolocation"] = b"{'lat': 1.0, 'lng': 2.0}"
    assert redis_db.get_cached_user_geolocation("uid-legacy") == {"lat": 1.0, "lng": 2.0}
