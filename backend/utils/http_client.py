"""Shared httpx.AsyncClient instances for outbound HTTP.

Implements Lane 1 of the 3-lane async architecture (issue #6369):
- Connection pooling per service
- Bounded concurrency via asyncio.Semaphore

Lifecycle: clients are lazily created on first use and should be closed
at application shutdown via ``close_all_clients()``.
"""

import asyncio
import logging
from collections.abc import Callable

import httpx

logger = logging.getLogger(__name__)
# ---------------------------------------------------------------------------
# Semaphores for bounded concurrency per client type
# ---------------------------------------------------------------------------
# Semaphores are event-loop-bound in Python's asyncio. Since sync FastAPI
# endpoints use asyncio.run() which creates a new event loop each call,
# we key semaphores by event loop ID so each loop gets its own instance.
# The main FastAPI event loop (used by async endpoints) shares one set.

_semaphores: dict[tuple[int, str], asyncio.Semaphore] = {}
_SEMAPHORE_CACHE_MAX = 100  # Prune when cache exceeds this size


def _get_semaphore(name: str, limit: int) -> asyncio.Semaphore:
    """Get or create a semaphore for the current event loop.

    Keyed by (loop_id, name) so each event loop gets its own set. This is
    necessary because asyncio.run() in sync FastAPI endpoints creates a
    fresh event loop per call, and semaphores are loop-bound.

    The main FastAPI event loop (used by async endpoints) reuses the same
    loop_id for the lifetime of the process, so its semaphores are stable.
    Entries from short-lived asyncio.run() loops are pruned when the cache
    grows beyond _SEMAPHORE_CACHE_MAX to prevent unbounded growth.
    """
    try:
        loop = asyncio.get_running_loop()
        key = (id(loop), name)
    except RuntimeError:
        # No running loop — create unbound semaphore (will bind on first acquire)
        return asyncio.Semaphore(limit)
    if key not in _semaphores:
        # Prune stale entries from destroyed loops when cache grows large
        if len(_semaphores) > _SEMAPHORE_CACHE_MAX:
            _evict_foreign_loop_semaphores(id(loop))
        _semaphores[key] = asyncio.Semaphore(limit)
    return _semaphores[key]


def _evict_foreign_loop_semaphores(live_loop_id: int) -> None:
    """Drop semaphores belonging to loops other than the one running now.

    Remove only foreign-loop state. A blanket clear() also dropped the running loop's own entry, so the next caller
    got a fresh Semaphore while in-flight tasks still held permits on the old one — briefly
    allowing twice the concurrency the limit exists to cap.
    """
    for key in [k for k in _semaphores if k[0] != live_loop_id]:
        del _semaphores[key]


def get_maps_semaphore() -> asyncio.Semaphore:
    return _get_semaphore('maps', 8)


def get_auth_semaphore() -> asyncio.Semaphore:
    return _get_semaphore('auth', 20)


def get_stt_semaphore() -> asyncio.Semaphore:
    return _get_semaphore('stt', 8)


# ---------------------------------------------------------------------------
# Shared httpx.AsyncClient instances
# ---------------------------------------------------------------------------

_clients: dict[int, tuple[asyncio.AbstractEventLoop, dict[str, httpx.AsyncClient]]] = {}
_loopless_clients: dict[str, httpx.AsyncClient] = {}


def _get_client(name: str, factory: Callable[[], httpx.AsyncClient]) -> httpx.AsyncClient:
    """Get or create a shared client owned by the current event loop.

    Clients are per-loop for the same reason as `_get_semaphore`: a pooled
    keep-alive connection belongs to the event loop that opened it. Sync
    FastAPI endpoints run `asyncio.run()`, which closes its loop on return, so
    a process-wide client ends up holding connections whose loop is gone. The
    next request on a live loop makes the pool discard one, and closing it
    calls `write_eof()` on a freed uvloop handle — `RuntimeError: unable to
    perform operation on <TCPTransport closed=True ...>; the handler is
    closed`, which httpcore re-raises at the caller. In prod that surfaced as
    intermittent HTTP 500s in external HTTP consumers.

    A finished loop's entry is dropped when the next loop appears — its
    clients cannot be closed (that is the same dead-handle error) and its
    sockets went down with the loop. Each entry keeps the loop itself, both to
    recognise that moment and so no two live entries can share an id.

    The main FastAPI event loop keeps one stable entry, so async callers — the
    hot paths — reuse their pool exactly as before.
    """
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        # No running loop: configuration inspection, not requests.
        by_name = _loopless_clients
    else:
        entry = _clients.get(id(loop))
        if entry is None or entry[0] is not loop:
            for cached_id, (cached_loop, _) in list(_clients.items()):
                if cached_loop.is_closed():
                    del _clients[cached_id]
            entry = (loop, {})
            _clients[id(loop)] = entry
        by_name = entry[1]
    client = by_name.get(name)
    if client is None:
        client = factory()
        by_name[name] = client
    return client


def get_external_client() -> httpx.AsyncClient:
    """Return a shared async HTTP client for retained external HTTP calls.

    Uses aggressive connect timeout (2s) and 30s read timeout to match
    the previous per-call timeout used by these consumers.
    """
    return _get_client(
        'external',
        lambda: httpx.AsyncClient(
            timeout=httpx.Timeout(30.0, connect=2.0),
            limits=httpx.Limits(max_connections=64, max_keepalive_connections=16),
        ),
    )


def get_maps_client() -> httpx.AsyncClient:
    """Return a shared async HTTP client for Google Maps geocoding."""
    return _get_client(
        'maps',
        lambda: httpx.AsyncClient(
            timeout=httpx.Timeout(10.0, connect=2.0),
            limits=httpx.Limits(max_connections=8, max_keepalive_connections=4),
        ),
    )


def get_auth_client() -> httpx.AsyncClient:
    """Return a shared async HTTP client for OAuth/auth token exchanges.

    Keep-alive is disabled (`max_keepalive_connections=0`) because Cloud Run
    reused stale sockets after the remote (Google/Apple/Firebase token
    endpoints) or an intermediate NAT silently dropped them, raising asyncio's
    "handler is closed" RuntimeError mid-request. That surfaced as intermittent HTTP 500s
    on `/v1/auth/callback/{google,apple}` and `/v1/auth/token`, breaking both
    Sign in with Google and Sign in with Apple (both providers share this
    client). Auth token-exchange volume is low, so paying a TLS handshake per
    request is a fine trade for eliminating the stale-socket failures.
    """
    return _get_client(
        'auth',
        lambda: httpx.AsyncClient(
            timeout=httpx.Timeout(10.0, connect=2.0),
            limits=httpx.Limits(max_connections=20, max_keepalive_connections=0),
        ),
    )


def get_stt_client() -> httpx.AsyncClient:
    """Return a shared async HTTP client for STT/ML services (long timeout)."""
    return _get_client(
        'stt',
        lambda: httpx.AsyncClient(
            timeout=httpx.Timeout(300.0, connect=5.0),
            limits=httpx.Limits(max_connections=8, max_keepalive_connections=4),
        ),
    )


def get_web_fetch_client() -> httpx.AsyncClient:
    """Return a shared async HTTP client for user-initiated URL fetches.

    Isolated from the general external pool so slow/stalled pages don't
    compete with other outbound requests.
    """
    return _get_client(
        'web_fetch',
        lambda: httpx.AsyncClient(
            timeout=httpx.Timeout(15.0, connect=5.0),
            limits=httpx.Limits(max_connections=16, max_keepalive_connections=4),
        ),
    )


async def close_all_clients():
    """Close all shared HTTP clients. Call at app shutdown.

    Only this loop's clients can be closed: another loop's connections are
    already gone with it, and awaiting aclose() on them raises the dead-handle
    RuntimeError described in `_get_client`.
    """
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        loop = None
    _, own_clients = _clients.pop(id(loop), (None, {})) if loop is not None else (None, {})
    for client in own_clients.values():
        try:
            await client.aclose()
        except Exception as e:
            logger.warning(f"Error closing HTTP client: {e}")
    _clients.clear()
    _loopless_clients.clear()
    # Reset stateful registries
    _semaphores.clear()
