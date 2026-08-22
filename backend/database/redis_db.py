import ast
import base64
import json
import os
from typing import Any, Callable, Dict, List, Optional, TypeVar, Union, cast
from datetime import datetime, timedelta, timezone

import redis
import logging

logger = logging.getLogger(__name__)

# redis.Redis is untyped under strict Pyright; treat the client as Any at this
# SDK boundary. Downstream callers narrow results via the adapter pattern.
_redis_host: Optional[str] = os.getenv('REDIS_DB_HOST')
_redis_port_env: Optional[str] = os.getenv('REDIS_DB_PORT')
r: Any = redis.Redis(
    host=cast(str, _redis_host),
    port=int(_redis_port_env) if _redis_port_env is not None else 6379,
    username='default',
    password=os.getenv('REDIS_DB_PASSWORD'),
    health_check_interval=30,
)


T = TypeVar("T")


def _decode_redis_value(raw: Union[bytes, str]) -> str:
    return raw.decode('utf-8') if isinstance(raw, bytes) else raw


def _deserialize_cache_value(raw: Union[bytes, str, None]) -> Any:
    """Deserialize a Redis cache value using JSON, with legacy literal_eval fallback."""
    if raw is None:
        return None
    text = _decode_redis_value(raw)
    try:
        return json.loads(text)
    except (TypeError, ValueError, json.JSONDecodeError):
        try:
            return ast.literal_eval(text)
        except (ValueError, SyntaxError):
            return text


def try_catch_decorator(func: Callable[..., T]) -> Callable[..., Optional[T]]:
    """Wrap func so any exception is logged and returns None (fail-open).

    The wrapped callable returns Optional[T] because a failure yields None even
    when the underlying function's declared return type is T. Callers must narrow
    away None before treating the result as T.
    """

    def wrapper(*args: Any, **kwargs: Any) -> Optional[T]:
        try:
            return func(*args, **kwargs)
        except Exception as e:
            logger.error(f'Error calling {func.__name__} {e}')
            return None

    return wrapper


@try_catch_decorator
def get_generic_cache(path: str) -> Any:
    key = base64.b64encode(f'{path}'.encode('utf-8'))
    key = key.decode('utf-8')

    data = r.get(f'cache:{key}')
    return json.loads(data) if data else None


@try_catch_decorator
def set_generic_cache(path: str, data: object, ttl: Optional[int] = None) -> None:
    key = base64.b64encode(f'{path}'.encode('utf-8'))
    key = key.decode('utf-8')

    r.set(f'cache:{key}', json.dumps(data, default=str))
    if ttl:
        r.expire(f'cache:{key}', ttl)


@try_catch_decorator
def delete_generic_cache(path: str) -> None:
    key = base64.b64encode(f'{path}'.encode('utf-8'))
    key = key.decode('utf-8')
    r.delete(f'cache:{key}')


def cache_user_name(uid: str, name: str, ttl: int = 60 * 60 * 24 * 7) -> None:
    r.set(f'users:{uid}:name', name)
    r.expire(f'users:{uid}:name', ttl)


def cache_signed_url(blob_path: str, signed_url: str, ttl: int = 60 * 60) -> None:
    r.set(f'urls:{blob_path}', signed_url)
    r.expire(f'urls:{blob_path}', ttl - 1)


def get_cached_signed_url(blob_path: str) -> str:
    signed_url = r.get(f'urls:{blob_path}')
    if not signed_url:
        return ''
    return signed_url.decode()


def get_cached_user_geolocation(uid: str) -> Optional[Dict[str, Any]]:
    """Read legacy hosted-listen location residue until S-23 removes finalization storage."""
    raw = r.get(f'users:{uid}:geolocation')
    if not raw:
        return None
    loaded = _deserialize_cache_value(raw)
    return cast(Dict[str, Any], loaded) if isinstance(loaded, dict) else None


@try_catch_decorator
def set_auth_session(session_id: str, session_data: Dict[str, Any], ttl: int = 600) -> None:
    """Store auth session data with expiration (default 10 minutes)"""
    r.set(f'auth_session:{session_id}', json.dumps(session_data), ex=ttl)


@try_catch_decorator
def get_auth_session(session_id: str) -> Optional[Dict[str, Any]]:
    """Retrieve auth session data"""
    data = r.get(f'auth_session:{session_id}')
    if not data:
        return None
    loaded: object = json.loads(data.decode('utf-8'))
    return cast(Dict[str, Any], loaded) if isinstance(loaded, dict) else None


@try_catch_decorator
def set_auth_code(auth_code: str, firebase_token: str, ttl: int = 300) -> None:
    """Store auth code with Firebase token (default 5 minutes)"""
    r.set(f'auth_code:{auth_code}', firebase_token, ex=ttl)


@try_catch_decorator
def get_auth_code(auth_code: str) -> Optional[str]:
    """Retrieve Firebase token by auth code"""
    token = r.get(f'auth_code:{auth_code}')
    return token.decode('utf-8') if token else None


@try_catch_decorator
def delete_auth_code(auth_code: str) -> None:
    """Delete used auth code"""
    r.delete(f'auth_code:{auth_code}')


# Atomic increment + TTL in one round-trip. The TTL repair prevents a Redis
# key that lost expiry metadata from becoming a permanent rate-limit bucket.
_RATE_LIMIT_LUA = r.register_script(
    """
local key = KEYS[1]
local window = tonumber(ARGV[1])
local current = redis.call('INCR', key)
if current == 1 then
    redis.call('EXPIRE', key, window)
end
local ttl = redis.call('TTL', key)
if ttl < 0 then
    redis.call('EXPIRE', key, window)
    ttl = window
end
return {current, ttl}
"""
)


def check_rate_limit(key: str, policy: str, max_requests: int, window: int) -> tuple[bool, int, int]:
    """Check per-key rate limit using a single atomic Lua call.

    Args:
        key: Rate limit subject (for example, a uid or IP address).
        policy: Policy name (used in Redis key namespace).
        max_requests: Maximum requests allowed in the window (after boost).
        window: Window size in seconds.

    Returns:
        (allowed, remaining, retry_after_seconds)
    """
    redis_key = f'rl:{policy}:{key}'
    current, ttl = _RATE_LIMIT_LUA(keys=[redis_key], args=[window])
    remaining = max(0, max_requests - current)
    allowed = current <= max_requests
    retry_after = max(0, ttl) if not allowed else 0
    return allowed, remaining, retry_after


# Atomic TTS rate-limit: burst (sliding-window ZSET) + daily char counter.
# Returns [status, retry_after_seconds]:
#   0 = allow, 1 = burst exceeded, 2 = daily char limit exceeded.
# Burst uses a sorted set keyed by timestamp-ms for sliding-window accuracy,
# trimmed on every call (O(log n)). Daily char counter auto-expires at midnight
# UTC (caller passes seconds_until_midnight_utc as the TTL).
_TTS_RATE_LIMIT_LUA = r.register_script(
    """
local burst_key = KEYS[1]
local daily_key = KEYS[2]
local now_ms = tonumber(ARGV[1])
local window_ms = tonumber(ARGV[2])
local burst_limit = tonumber(ARGV[3])
local char_count = tonumber(ARGV[4])
local daily_limit = tonumber(ARGV[5])
local daily_ttl = tonumber(ARGV[6])

redis.call('ZREMRANGEBYSCORE', burst_key, 0, now_ms - window_ms)
local burst_current = redis.call('ZCARD', burst_key)
if burst_current >= burst_limit then
    return {1, math.floor(window_ms / 1000)}
end

local daily_current = tonumber(redis.call('GET', daily_key) or '0')
if daily_current + char_count > daily_limit then
    return {2, daily_ttl}
end

redis.call('ZADD', burst_key, now_ms, now_ms .. ':' .. math.random())
redis.call('PEXPIRE', burst_key, window_ms)
local new_daily = redis.call('INCRBY', daily_key, char_count)
if new_daily == char_count then
    redis.call('EXPIRE', daily_key, daily_ttl)
end
return {0, 0}
"""
)


def _seconds_until_midnight_utc() -> int:
    now = datetime.now(timezone.utc)
    tomorrow = (now + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    return max(1, int((tomorrow - now).total_seconds()))


def check_tts_rate_limit(
    uid: str,
    char_count: int,
    burst_limit: int = 50,
    burst_window_secs: int = 60,
    daily_char_limit: int = 10_000,
) -> tuple[int, int]:
    """Atomic per-user TTS rate limit check.

    Returns (status, retry_after_seconds) where status is:
        0  — allow
        1  — burst window exceeded
        2  — daily character limit exceeded
       -1  — Redis error (fail-open: caller should allow the request)
    """
    try:
        burst_key = f'tts:burst:{uid}'
        today_utc = datetime.now(timezone.utc).strftime('%Y%m%d')
        daily_key = f'tts:chars:{uid}:{today_utc}'
        now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
        window_ms = burst_window_secs * 1000
        daily_ttl = _seconds_until_midnight_utc()
        result = _TTS_RATE_LIMIT_LUA(
            keys=[burst_key, daily_key],
            args=[now_ms, window_ms, burst_limit, char_count, daily_char_limit, daily_ttl],
        )
        return int(result[0]), int(result[1])
    except Exception as e:
        logger.error(f'check_tts_rate_limit: redis error uid={uid}: {e}')
        return -1, 0


def try_acquire_listen_lock(uid: str, ttl: int = 7) -> bool:
    """Atomically try to acquire listen rate limit lock. Returns True if acquired (not rate limited), False if already rate limited."""
    result = r.set(f'users:{uid}:listen_rate_limit', '1', ex=ttl, nx=True)
    return result is not None


def try_acquire_client_device_write_lock(uid: str, client_device_id: str, ttl: int = 600) -> bool:
    """Throttle client_devices registry upserts to once per (uid, device) every `ttl` seconds."""
    try:
        result = r.set(f'users:{uid}:client_device_write:{client_device_id}', '1', ex=ttl, nx=True)
        return result is not None
    except Exception:
        return True


def try_acquire_user_platform_write_lock(uid: str, platform: str, ttl: int = 600) -> bool:
    """Return True once every `ttl` seconds per (uid, platform) to throttle
    `last_active_platform` writes on chatty endpoints. The platform is part of
    the key so switching platforms bypasses the throttle and records the
    change immediately.
    """
    try:
        result = r.set(f'users:{uid}:platform_write:{platform}', '1', ex=ttl, nx=True)
        return result is not None
    except Exception:
        # Fail-open: if Redis is down, let the caller write through. Firestore
        # merge is idempotent, so worst case we write more often than intended.
        return True


@try_catch_decorator
def set_credits_invalidation_signal(uid: str, ttl: int = 120) -> None:
    """Signal active WebSocket sessions to refresh credits immediately.

    Called when a verified billing projection changes.
    Active transcribe loops check this on each 60s tick and force a Firestore refresh.
    TTL is 2 min — long enough for all streams to see it on their next 60s tick.
    Uses GET (not GETDEL) so multiple concurrent streams all see the signal.
    """
    r.set(f'credits_invalidated:{uid}', '1', ex=ttl)


@try_catch_decorator
def check_credits_invalidation(uid: str) -> bool:
    """Check if credits need immediate refresh.

    Returns True if invalidation signal is present (caller should refresh).
    Uses GET (not GETDEL) so all concurrent streams for the same user see the signal.
    The signal auto-expires via its TTL.
    """
    result = r.get(f'credits_invalidated:{uid}')
    return result is not None


# ******************************************************
# *************** GOAL RATE LIMITING *******************
# ******************************************************
