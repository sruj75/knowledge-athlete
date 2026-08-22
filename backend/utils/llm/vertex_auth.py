"""Cached Google ADC token supplier for direct Vertex workloads."""

import asyncio
import time
from collections.abc import Callable
from typing import Any

import google.auth
from google.auth.transport.requests import Request as GoogleAuthRequest

from utils.executors import llm_executor, run_blocking

GOOGLE_CLOUD_PLATFORM_SCOPE = 'https://www.googleapis.com/auth/cloud-platform'


class VertexAccessTokenSupplier:
    """Cache ADC access tokens while refreshing blocking Google auth off-loop."""

    def __init__(
        self,
        *,
        credentials_factory: Callable[..., tuple[Any, str | None]] = google.auth.default,
        auth_request_factory: Callable[[], Any] = GoogleAuthRequest,
        now: Callable[[], float] = time.time,
    ) -> None:
        self._credentials_factory = credentials_factory
        self._auth_request_factory = auth_request_factory
        self._now = now
        self._credentials: Any | None = None
        self._access_token: str | None = None
        self._expires_at = 0.0
        self._refresh_lock = asyncio.Lock()

    async def get_access_token(self) -> str:
        if self._access_token and self._now() < self._expires_at - 60:
            return self._access_token
        async with self._refresh_lock:
            if self._access_token and self._now() < self._expires_at - 60:
                return self._access_token
            token, expires_at = await run_blocking(llm_executor, self._refresh)
            if not token:
                raise RuntimeError('Vertex credentials did not provide an access token')
            self._access_token = token
            self._expires_at = expires_at
            return token

    def _refresh(self) -> tuple[str, float]:
        credentials = self._credentials
        if credentials is None:
            credentials, _ = self._credentials_factory(scopes=[GOOGLE_CLOUD_PLATFORM_SCOPE])
            self._credentials = credentials
        credentials.refresh(self._auth_request_factory())
        token = str(getattr(credentials, 'token', '') or '')
        expiry = getattr(credentials, 'expiry', None)
        expires_at = expiry.timestamp() if expiry is not None else self._now() + 300
        return token, expires_at
