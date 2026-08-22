import pytest

from utils.executors import llm_executor
from utils.llm import vertex_auth
from utils.llm.vertex_auth import VertexAccessTokenSupplier


@pytest.mark.asyncio
async def test_vertex_access_token_refresh_uses_llm_executor(monkeypatch):
    calls = []

    class Credentials:
        token = ''
        expiry = None

        def refresh(self, _request) -> None:
            self.token = 'adc-token'

    async def fake_run_blocking(executor, function):
        calls.append(executor)
        return function()

    monkeypatch.setattr(vertex_auth, 'run_blocking', fake_run_blocking)
    supplier = VertexAccessTokenSupplier(
        credentials_factory=lambda **_kwargs: (Credentials(), 'test-project'),
        auth_request_factory=object,
    )

    assert await supplier.get_access_token() == 'adc-token'
    assert calls == [llm_executor]
