"""Provider-neutral deadlines and pre-first-byte retry for managed SSE relays."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import suppress
from dataclasses import dataclass
import os
import time
from typing import Any, Protocol

import httpx

from utils.retrieval.safety import should_retry_provider_error

MANAGED_STREAM_HEARTBEAT = object()


class _ResponseStream(Protocol):
    async def __aenter__(self) -> httpx.Response: ...

    async def __aexit__(self, exc_type: object, exc: object, traceback: object) -> object: ...


@dataclass(frozen=True)
class ManagedStreamPolicy:
    first_event_timeout_seconds: float
    progress_heartbeat_seconds: float
    max_duration_seconds: float
    cancel_grace_seconds: float
    provider_max_attempts: int
    provider_retry_backoff_seconds: float
    provider_min_retry_headroom_seconds: float

    @classmethod
    def from_environment(cls) -> 'ManagedStreamPolicy':
        return cls(
            first_event_timeout_seconds=_positive_float('AGENT_STREAM_FIRST_EVENT_TIMEOUT_SECONDS', 25.0),
            progress_heartbeat_seconds=_positive_float('AGENT_STREAM_PROGRESS_HEARTBEAT_SECONDS', 20.0),
            max_duration_seconds=_positive_float('AGENT_STREAM_MAX_DURATION_SECONDS', 150.0),
            cancel_grace_seconds=_positive_float('AGENT_STREAM_CANCEL_GRACE_SECONDS', 2.0),
            provider_max_attempts=_positive_int('AGENT_STREAM_PROVIDER_MAX_ATTEMPTS', 3),
            provider_retry_backoff_seconds=_positive_float('AGENT_STREAM_PROVIDER_RETRY_BACKOFF_SECONDS', 1.0),
            provider_min_retry_headroom_seconds=_positive_float(
                'AGENT_STREAM_PROVIDER_MIN_RETRY_HEADROOM_SECONDS', 45.0
            ),
        )


async def stream_managed_response_bytes(
    open_stream: Callable[[], _ResponseStream],
    *,
    policy: ManagedStreamPolicy | None = None,
    _monotonic: Callable[[], float] = time.monotonic,
    _sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    _wait: Callable[..., Awaitable[tuple[set[asyncio.Task[Any]], set[asyncio.Task[Any]]]]] = asyncio.wait,
) -> AsyncIterator[bytes | object]:
    """Yield raw response bytes; retry transport failures only before any byte."""

    active_policy = policy or ManagedStreamPolicy.from_environment()
    turn_deadline = _monotonic() + active_policy.max_duration_seconds
    attempt = 0

    while True:
        attempt += 1
        first_event_deadline = min(turn_deadline, _monotonic() + active_policy.first_event_timeout_seconds)
        manager: _ResponseStream | None = None
        opened = False
        pending: asyncio.Task[Any] | None = None
        saw_bytes = False
        try:
            remaining = turn_deadline - _monotonic()
            if remaining <= 0:
                raise TimeoutError('managed provider stream exceeded its turn deadline')
            manager = open_stream()
            response = await asyncio.wait_for(manager.__aenter__(), timeout=first_event_deadline - _monotonic())
            opened = True
            response.raise_for_status()
            iterator = response.aiter_raw()

            while True:
                remaining = turn_deadline - _monotonic()
                if remaining <= 0:
                    raise TimeoutError('managed provider stream exceeded its turn deadline')
                if pending is None:
                    pending = asyncio.create_task(iterator.__anext__())
                silent_limit = active_policy.progress_heartbeat_seconds if saw_bytes else first_event_deadline - _monotonic()
                if silent_limit <= 0:
                    raise TimeoutError('managed provider stream produced no first byte before its deadline')
                done, _ = await _wait({pending}, timeout=min(silent_limit, remaining))
                if not done:
                    if not saw_bytes:
                        raise TimeoutError('managed provider stream produced no first byte before its deadline')
                    if _monotonic() >= turn_deadline:
                        raise TimeoutError('managed provider stream exceeded its turn deadline')
                    yield MANAGED_STREAM_HEARTBEAT
                    continue

                try:
                    chunk = pending.result()
                except StopAsyncIteration:
                    pending = None
                    if not saw_bytes:
                        raise httpx.RemoteProtocolError('managed provider stream ended before its first byte')
                    opened = False
                    await _close_stream(manager, None, active_policy.cancel_grace_seconds)
                    return
                pending = None
                if not chunk:
                    continue
                saw_bytes = True
                yield chunk
        except BaseException as exc:
            await _cancel_pending(pending)
            if opened and manager is not None:
                opened = False
                await _close_stream(manager, exc, active_policy.cancel_grace_seconds)
            if isinstance(exc, Exception) and not saw_bytes and _can_retry(
                exc, attempt, turn_deadline, active_policy, _monotonic
            ):
                has_retry_headroom = await _sleep_before_retry(
                    active_policy.provider_retry_backoff_seconds,
                    turn_deadline,
                    _monotonic,
                    _sleep,
                    active_policy.provider_min_retry_headroom_seconds,
                )
                if not has_retry_headroom:
                    raise
                continue
            raise


def _can_retry(
    exc: BaseException,
    attempt: int,
    turn_deadline: float,
    policy: ManagedStreamPolicy,
    monotonic: Callable[[], float],
) -> bool:
    remaining_after_backoff = turn_deadline - monotonic() - policy.provider_retry_backoff_seconds
    retry_error = httpx.ReadTimeout(str(exc)) if isinstance(exc, TimeoutError) else exc
    return should_retry_provider_error(
        retry_error,
        attempts_made=attempt,
        max_attempts=policy.provider_max_attempts,
        text_already_streamed=False,
        seconds_remaining=remaining_after_backoff,
        min_headroom_seconds=policy.provider_min_retry_headroom_seconds,
    )


async def _sleep_before_retry(
    delay_seconds: float,
    turn_deadline: float,
    monotonic: Callable[[], float],
    sleep: Callable[[float], Awaitable[None]],
    minimum_headroom_seconds: float,
) -> bool:
    remaining = turn_deadline - monotonic()
    if remaining <= 0:
        raise TimeoutError('managed provider stream exceeded its turn deadline')
    try:
        await asyncio.wait_for(sleep(delay_seconds), timeout=remaining)
    except TimeoutError as exc:
        raise TimeoutError('managed provider stream exceeded its turn deadline') from exc
    return turn_deadline - monotonic() >= minimum_headroom_seconds


async def _cancel_pending(pending: asyncio.Task[Any] | None) -> None:
    if pending is None or pending.done():
        return
    pending.cancel()
    with suppress(BaseException):
        await pending


async def _close_stream(manager: _ResponseStream, error: BaseException | None, grace_seconds: float) -> None:
    async def close() -> None:
        if error is None:
            await manager.__aexit__(None, None, None)
        else:
            await manager.__aexit__(type(error), error, error.__traceback__)

    close_task = asyncio.create_task(close())
    try:
        await asyncio.wait_for(asyncio.shield(close_task), timeout=grace_seconds)
    except TimeoutError:
        close_task.cancel()
        with suppress(BaseException):
            await close_task


def _positive_float(name: str, default: float) -> float:
    raw = os.getenv(name, '').strip()
    try:
        value = float(raw) if raw else default
    except ValueError:
        return default
    return value if value > 0 else default


def _positive_int(name: str, default: int) -> int:
    raw = os.getenv(name, '').strip()
    try:
        value = int(raw) if raw else default
    except ValueError:
        return default
    return value if value > 0 else default
