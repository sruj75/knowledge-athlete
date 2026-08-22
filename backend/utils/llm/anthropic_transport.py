"""Bounded retry and streaming deadlines for direct managed Anthropic Chat."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator, Awaitable, Callable, Mapping
from contextlib import suppress
from dataclasses import dataclass
import os
import time
from typing import Any

import httpx

from utils.retrieval.safety import should_retry_provider_error

ANTHROPIC_STREAM_HEARTBEAT = object()


@dataclass(frozen=True)
class ManagedAnthropicPolicy:
    first_event_timeout_seconds: float
    progress_heartbeat_seconds: float
    max_duration_seconds: float
    cancel_grace_seconds: float
    provider_max_attempts: int
    provider_retry_backoff_seconds: float
    provider_min_retry_headroom_seconds: float

    @classmethod
    def from_environment(cls) -> 'ManagedAnthropicPolicy':
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


async def create_managed_anthropic_message(
    messages: Any,
    payload: Mapping[str, object],
    *,
    policy: ManagedAnthropicPolicy | None = None,
    _monotonic: Callable[[], float] = time.monotonic,
    _sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
) -> Any:
    active_policy = policy or ManagedAnthropicPolicy.from_environment()
    started_at = _monotonic()
    attempt = 0
    while True:
        attempt += 1
        remaining = active_policy.max_duration_seconds - (_monotonic() - started_at)
        if remaining <= 0:
            raise TimeoutError('managed Anthropic request exceeded its turn deadline')
        try:
            return await asyncio.wait_for(messages.create(**dict(payload)), timeout=remaining)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            if not _can_retry(exc, attempt, started_at, active_policy, _monotonic):
                raise
            await _sleep(active_policy.provider_retry_backoff_seconds)


async def stream_managed_anthropic_events(
    messages: Any,
    payload: Mapping[str, object],
    *,
    policy: ManagedAnthropicPolicy | None = None,
    _monotonic: Callable[[], float] = time.monotonic,
    _sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    _wait: Callable[..., Awaitable[tuple[set[asyncio.Task[Any]], set[asyncio.Task[Any]]]]] = asyncio.wait,
) -> AsyncIterator[object]:
    """Yield provider events, retrying transport failures only before the first event."""

    active_policy = policy or ManagedAnthropicPolicy.from_environment()
    started_at = _monotonic()
    attempt = 0

    while True:
        attempt += 1
        manager: Any | None = None
        opened = False
        pending: asyncio.Task[Any] | None = None
        saw_event = False
        try:
            remaining = active_policy.max_duration_seconds - (_monotonic() - started_at)
            if remaining <= 0:
                raise TimeoutError('managed Anthropic stream exceeded its turn deadline')
            manager = messages.stream(**dict(payload))
            active = await asyncio.wait_for(
                manager.__aenter__(), timeout=min(active_policy.first_event_timeout_seconds, remaining)
            )
            opened = True
            iterator = active.__aiter__()

            while True:
                remaining = active_policy.max_duration_seconds - (_monotonic() - started_at)
                if remaining <= 0:
                    raise TimeoutError('managed Anthropic stream exceeded its turn deadline')
                if pending is None:
                    pending = asyncio.create_task(iterator.__anext__())
                silent_limit = (
                    active_policy.progress_heartbeat_seconds if saw_event else active_policy.first_event_timeout_seconds
                )
                done, _ = await _wait({pending}, timeout=min(silent_limit, remaining))
                if not done:
                    if not saw_event:
                        raise TimeoutError('managed Anthropic stream produced no first event before its deadline')
                    if _monotonic() - started_at >= active_policy.max_duration_seconds:
                        raise TimeoutError('managed Anthropic stream exceeded its turn deadline')
                    yield ANTHROPIC_STREAM_HEARTBEAT
                    continue

                try:
                    event = pending.result()
                except StopAsyncIteration:
                    pending = None
                    opened = False
                    await _close_stream(manager, None, active_policy.cancel_grace_seconds)
                    return
                pending = None
                saw_event = True
                yield event
        except BaseException as exc:
            await _cancel_pending(pending)
            if opened:
                opened = False
                await _close_stream(manager, exc, active_policy.cancel_grace_seconds)
            if (
                isinstance(exc, Exception)
                and not saw_event
                and _can_retry(exc, attempt, started_at, active_policy, _monotonic)
            ):
                await _sleep(active_policy.provider_retry_backoff_seconds)
                continue
            raise


def _can_retry(
    exc: BaseException,
    attempt: int,
    started_at: float,
    policy: ManagedAnthropicPolicy,
    monotonic: Callable[[], float],
) -> bool:
    remaining = policy.max_duration_seconds - (monotonic() - started_at)
    retry_error = httpx.ReadTimeout(str(exc)) if isinstance(exc, TimeoutError) else exc
    return should_retry_provider_error(
        retry_error,
        attempts_made=attempt,
        max_attempts=policy.provider_max_attempts,
        text_already_streamed=False,
        seconds_remaining=remaining,
        min_headroom_seconds=policy.provider_min_retry_headroom_seconds,
    )


async def _cancel_pending(pending: asyncio.Task[Any] | None) -> None:
    if pending is None or pending.done():
        return
    pending.cancel()
    with suppress(BaseException):
        await pending


async def _close_stream(manager: Any, error: BaseException | None, grace_seconds: float) -> None:
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
