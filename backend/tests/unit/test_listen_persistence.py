"""Tests for the executor-backed listen persistence boundary."""

import pytest

from routers.listen.persistence import ListenPersistence


@pytest.fixture
def anyio_backend():
    return 'asyncio'


@pytest.mark.anyio
async def test_listen_persistence_offloads_and_preserves_call_arguments(monkeypatch):
    captured = {}

    def write(uid, *, value):
        return f'{uid}:{value}'

    async def fake_run_blocking(executor, function, *args, **kwargs):
        captured.update(executor=executor, function=function, args=args, kwargs=kwargs)
        return function(*args, **kwargs)

    monkeypatch.setattr('routers.listen.persistence.run_blocking', fake_run_blocking)

    result = await ListenPersistence().call(write, 'user-1', value='stored')

    assert result == 'user-1:stored'
    assert captured['function'] is write
    assert captured['args'] == ('user-1',)
    assert captured['kwargs'] == {'value': 'stored'}
