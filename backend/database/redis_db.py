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


def _serialize_cache_value(value: Any) -> str:
    return json.dumps(value, default=str)


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


def cache_user_geolocation(uid: str, geolocation: Dict[str, Any]) -> None:
    # Unset optional fields are dropped rather than serialized as JSON ``null``.
    # This key is written by the API tier and read by pusher, which deploys on its
    # own cadence; a reader still on the pre-JSON ``eval()`` reader raises
    # ``NameError: name 'null' is not defined`` and discards the conversation it
    # was finalizing. Every reader rebuilds ``Geolocation`` from this dict, whose
    # optional fields already default to ``None`` when absent.
    present_fields = {key: value for key, value in geolocation.items() if value is not None}
    r.set(f'users:{uid}:geolocation', _serialize_cache_value(present_fields))
    r.expire(f'users:{uid}:geolocation', 60 * 30)  # FIXME: too much?


def get_cached_user_geolocation(uid: str) -> Optional[Dict[str, Any]]:
    raw = r.get(f'users:{uid}:geolocation')
    if not raw:
        return None
    loaded = _deserialize_cache_value(raw)
    return cast(Dict[str, Any], loaded) if isinstance(loaded, dict) else None


def delete_cached_user_geolocation(uid: str) -> None:
    r.delete(f'users:{uid}:geolocation')


def set_in_progress_conversation_id(uid: str, conversation_id: str, ttl: int = 300) -> None:
    r.set(f'users:{uid}:in_progress_memory_id', conversation_id)
    r.expire(f'users:{uid}:in_progress_memory_id', ttl)


def remove_in_progress_conversation_id(uid: str) -> None:
    r.delete(f'users:{uid}:in_progress_memory_id')


def get_in_progress_conversation_id(uid: str) -> str:
    conversation_id = r.get(f'users:{uid}:in_progress_memory_id')
    if not conversation_id:
        return ''
    return conversation_id.decode()


def set_conversation_meeting_id(conversation_id: str, meeting_id: str, ttl: int = 86400) -> None:
    """Store the meeting_id for a conversation. TTL defaults to 24 hours."""
    r.set(f'conversation:{conversation_id}:meeting_id', meeting_id)
    r.expire(f'conversation:{conversation_id}:meeting_id', ttl)


def get_conversation_meeting_id(conversation_id: str) -> Optional[str]:
    """Retrieve the meeting_id associated with a conversation."""
    meeting_id = r.get(f'conversation:{conversation_id}:meeting_id')
    if not meeting_id:
        return None
    return meeting_id.decode()


def get_filter_category_items(uid: str, category: str, limit: Optional[int] = None) -> List[str]:
    key = f'users:{uid}:filters:{category}'
    if limit:
        # Get random sample if limit specified
        val = r.srandmember(key, limit)
    else:
        # Get all items (existing behavior)
        val = r.smembers(key)

    if not val:
        return []
    return [x.decode() for x in val]


def add_filter_category_item(uid: str, category: str, item: str) -> None:
    r.sadd(f'users:{uid}:filters:{category}', item)


def save_migrated_retrieval_conversation_id(conversation_id: str) -> None:
    r.sadd('migrated_retrieval_memory_ids', conversation_id)
    r.expire('migrated_retrieval_memory_ids', 60 * 60 * 24 * 7)


@try_catch_decorator
def incr_daily_notification_count(uid: str) -> int:
    """Atomically increment the daily proactive-notification count for a user."""
    from datetime import datetime, timezone

    key = f'{uid}:daily_noti_count:{datetime.now(timezone.utc).strftime("%Y-%m-%d")}'
    count = r.incr(key)
    r.expire(key, 90000)  # 25 hours TTL
    return count


@try_catch_decorator
def get_daily_notification_count(uid: str) -> int:
    """Get the current daily proactive-notification count for a user."""
    from datetime import datetime, timezone

    key = f'{uid}:daily_noti_count:{datetime.now(timezone.utc).strftime("%Y-%m-%d")}'
    val = r.get(key)
    if not val:
        return 0
    return int(val)


@try_catch_decorator
def set_user_data_protection_level(uid: str, level: str) -> None:
    """Caches the user's data protection level."""
    key = f'user:{uid}:data_protection_level'
    r.set(key, level)


@try_catch_decorator
def get_user_data_protection_level(uid: str) -> Optional[str]:
    """Retrieves the user's cached data protection level."""
    key = f'user:{uid}:data_protection_level'
    level = r.get(key)
    return level.decode() if level else None


# ******************************************************
# **************** DATA MIGRATION STATUS ***************
# ******************************************************


def set_migration_status(
    uid: str,
    status: str,
    processed: Optional[int] = None,
    total: Optional[int] = None,
    error: Optional[str] = None,
) -> None:
    key = f"migration_status:{uid}"
    data: Dict[str, Any] = {"status": status}
    if processed is not None:
        data["processed"] = processed
    if total is not None:
        data["total"] = total
    if error is not None:
        data["error"] = error

    r.set(key, json.dumps(data), ex=3600)  # Expire after 1 hour


# ******************************************************
# ******************* AUTH SESSION *********************
# ******************************************************


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


# ******************************************************
# ************** CREDIT LIMIT NOTIFICATIONS ************
# ******************************************************


def set_credit_limit_notification_sent(uid: str, ttl: int = 60 * 60 * 24) -> None:
    """Cache that credit limit notification was sent to user (24 hours TTL by default)"""
    r.set(f'users:{uid}:credit_limit_notification_sent', '1', ex=ttl)


def has_credit_limit_notification_been_sent(uid: str) -> bool:
    """Check if credit limit notification was already sent to user recently"""
    return r.exists(f'users:{uid}:credit_limit_notification_sent')


def set_silent_user_notification_sent(uid: str, ttl: int = 60 * 60 * 24) -> None:
    """Cache that silent user notification was sent to user (24 hours TTL by default)"""
    r.set(f'users:{uid}:silent_notification_sent', '1', ex=ttl)


def has_silent_user_notification_been_sent(uid: str) -> bool:
    """Check if silent user notification was already sent to user recently"""
    return r.exists(f'users:{uid}:silent_notification_sent')


# ******************************************************
# ******* IMPORTANT CONVERSATION NOTIFICATIONS *********
# ******************************************************


def set_important_conversation_notification_sent(uid: str, conversation_id: str) -> None:
    """Mark that important conversation notification was sent for this conversation (no expiry - one-time per conversation)"""
    r.set(f'users:{uid}:important_conv_notif:{conversation_id}', '1')


def has_important_conversation_notification_been_sent(uid: str, conversation_id: str) -> bool:
    """Check if important conversation notification was already sent for this conversation"""
    return r.exists(f'users:{uid}:important_conv_notif:{conversation_id}')


# ******************************************************
# *************** RATE LIMITING ************************
# ******************************************************

# Lua script: atomic increment + TTL in a single round-trip.
# Returns [current_count, ttl_remaining].  Sets TTL on first hit
# and self-heals any key that lost its TTL (prevents permanent buckets).
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


# ******************************************************
# *************** SPEECH PROFILE CACHE *****************
# ******************************************************


@try_catch_decorator
def set_speech_profile_duration(uid: str, duration: float) -> None:
    """Cache speech profile duration (write-ahead on upload)"""
    r.set(f'users:{uid}:speech_profile_duration', str(duration))


# ******************************************************
# ************ DAILY SUMMARY NOTIFICATIONS *************
# ******************************************************


def try_acquire_daily_summary_lock(uid: str, date: str, ttl: int = 60 * 60 * 2) -> bool:
    """Atomically acquire lock BEFORE expensive LLM work. Returns True if acquired, False if another job instance already holds it."""
    result = r.set(f'users:{uid}:daily_summary_lock:{date}', '1', ex=ttl, nx=True)
    return result is not None


@try_catch_decorator
def set_credits_invalidation_signal(uid: str, ttl: int = 120) -> None:
    """Signal active WebSocket sessions to refresh credits immediately.

    Called when subscription changes (Stripe webhook, upgrade, etc.).
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


def try_acquire_goal_extraction_lock(uid: str, ttl: int = 300) -> bool:
    """Per-user rate limit for goal extraction. Returns True if acquired (not rate limited)."""
    result = r.set(f'users:{uid}:goal_extraction_lock', '1', ex=ttl, nx=True)
    return result is not None


def try_acquire_conversation_goal_lock(uid: str, conversation_id: str, ttl: int = 3600) -> bool:
    """Idempotency lock: one goal extraction per conversation. Returns True if acquired."""
    result = r.set(f'users:{uid}:conv_goal_lock:{conversation_id}', '1', ex=ttl, nx=True)
    return result is not None
