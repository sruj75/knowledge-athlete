import hmac
import json
import os
import time
from typing import Any, Callable, Dict, Optional, TypeVar, cast

from fastapi import Depends, Header, HTTPException, WebSocketException
from fastapi import Request
from starlette.websockets import WebSocket
from firebase_admin import auth
from firebase_admin.auth import CertificateFetchError, ExpiredIdTokenError, InvalidIdTokenError, RevokedIdTokenError
import logging
import redis as redis_pkg

from config.participant_admission import (
    ParticipantAdmissionConfigurationError,
    ParticipantNotAdmittedError,
    require_hosted_participant,
)
from database.redis_db import check_rate_limit, try_acquire_listen_lock
from database.users import record_client_device, record_user_platform
from utils.client_device import resolve_client_device
from utils.executors import critical_executor, run_blocking
from utils.rate_limit_config import RATE_POLICIES, RATE_LIMIT_SHADOW, get_effective_limit

logger = logging.getLogger(__name__)

WS_AUTH_CODE_TOKEN_REFRESH = 4001
WS_AUTH_CODE_RELOGIN_REQUIRED = 4004


def get_user(uid: str) -> Any:
    return auth.get_user(uid)  # type: ignore[reportUnknownVariableType,reportUnknownMemberType]  # firebase_admin auth untyped


def verify_token(token: str) -> str:
    """
    Verify a Firebase token or ADMIN_KEY and return the uid.

    Args:
        token: The token to verify (Firebase ID token or ADMIN_KEY format)

    Returns:
        The user's uid

    Raises:
        InvalidIdTokenError: If the token is invalid
    """
    # ADMIN_KEY impersonation: token format is "<ADMIN_KEY><uid>" (kept as-is —
    # this exact concatenation is depended on by this repo's own integration
    # tests, the listen/sync test stacks, and the production
    # memory-continuity-gauntlet smoke test, so changing the format would
    # break first-party tooling, not just close a hole). What actually
    # changes: the prefix compare is constant-time instead of `startswith`
    # (closes a timing side-channel on ADMIN_KEY itself), every successful
    # use is logged so impersonation is auditable instead of silent, and
    # ADMIN_KEY_AUTH_ENABLED lets an operator who doesn't need this feature
    # turn it off entirely — default stays "true" so existing deployments
    # and CI that already rely on it keep working unchanged.
    admin_key = os.getenv('ADMIN_KEY')
    if admin_key and os.getenv('ADMIN_KEY_AUTH_ENABLED', 'true').lower() == 'true':
        if len(admin_key) < 16:
            logger.warning('ADMIN_KEY is under 16 chars — trivially guessable if this deployment is internet-facing')
        candidate = token[: len(admin_key)].encode()
        if hmac.compare_digest(candidate, admin_key.encode()) and len(token) > len(admin_key):
            impersonated_uid = token[len(admin_key) :]
            logger.warning('event=admin_key_auth outcome=impersonation_accepted')
            return impersonated_uid

    # Verify Firebase token
    try:
        decoded_token = cast(Any, auth.verify_id_token(token))  # type: ignore[reportUnknownMemberType]  # firebase_admin auth untyped
        return decoded_token['uid']
    except InvalidIdTokenError:
        # Only honored when no real Firebase credential is configured — every
        # legitimate LOCAL_DEVELOPMENT=true path (hermetic e2e harness, the
        # auth-emulator dev harness) already unsets or never sets these, and
        # every real deployment sets one to talk to the real project (see
        # main.py's firebase_admin.initialize_app branches). This keeps the
        # bypass inert the moment real credentials are present, without
        # requiring test paths to change what they already do.
        no_real_credential = not (os.getenv('SERVICE_ACCOUNT_JSON') or os.getenv('GOOGLE_APPLICATION_CREDENTIALS'))
        if os.getenv('LOCAL_DEVELOPMENT') == 'true' and no_real_credential:
            return '123'
        raise


def _authenticated_http_uid(authorization: str) -> str:
    if not authorization:
        raise HTTPException(status_code=401, detail="Authorization header not found")
    elif len(str(authorization).split(' ')) != 2:
        raise HTTPException(status_code=401, detail="Invalid authorization token")

    token = authorization.split(' ')[1]
    try:
        uid = verify_token(token)
    except InvalidIdTokenError as e:
        logger.error(e)
        raise HTTPException(status_code=401, detail="Invalid authorization token")

    return uid


def _record_authenticated_client(
    uid: str,
    *,
    x_app_platform: str | None,
    x_device_id_hash: str | None,
    x_app_version: str | None,
) -> None:
    try:
        record_user_platform(uid, x_app_platform)
    except Exception as e:  # noqa: BLE001 — telemetry must never fail the request
        logger.debug("event=client_metadata_failed operation=record_user_platform exception_type=%s", type(e).__name__)

    try:
        device_ctx = resolve_client_device(
            x_app_platform=x_app_platform,
            x_device_id_hash=x_device_id_hash,
            x_app_version=x_app_version,
        )
        record_client_device(
            uid,
            client_device_id=device_ctx.client_device_id,
            platform=device_ctx.platform,
            app_version=device_ctx.app_version,
        )
    except Exception as e:  # noqa: BLE001 — telemetry must never fail the request
        logger.debug("event=client_metadata_failed operation=record_client_device exception_type=%s", type(e).__name__)


def _require_http_participant(uid: str) -> None:
    try:
        require_hosted_participant(uid)
    except ParticipantNotAdmittedError as exc:
        raise HTTPException(status_code=403, detail=str(exc)) from exc
    except ParticipantAdmissionConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


def get_current_user_uid(
    authorization: str = Header(None),
    x_app_platform: str = Header(None, alias='X-App-Platform'),
    x_device_id_hash: str = Header(None, alias='X-Device-Id-Hash'),
    x_app_version: str = Header(None, alias='X-App-Version'),
) -> str:
    """Authenticate an HTTP request and record best-effort client metadata."""

    uid = _authenticated_http_uid(authorization)
    _record_authenticated_client(
        uid,
        x_app_platform=x_app_platform,
        x_device_id_hash=x_device_id_hash,
        x_app_version=x_app_version,
    )

    return uid


def get_current_participant_uid(
    authorization: str = Header(None),
    x_app_platform: str = Header(None, alias='X-App-Platform'),
    x_device_id_hash: str = Header(None, alias='X-Device-Id-Hash'),
    x_app_version: str = Header(None, alias='X-App-Version'),
) -> str:
    """Authenticate and admit a hosted-compute participant before metadata writes."""

    uid = _authenticated_http_uid(authorization)
    _require_http_participant(uid)
    _record_authenticated_client(
        uid,
        x_app_platform=x_app_platform,
        x_device_id_hash=x_device_id_hash,
        x_app_version=x_app_version,
    )

    return uid


def _verify_ws_auth(authorization: str) -> str:
    """Common WebSocket auth — verifies token, returns uid.

    Raises WebSocketException instead of HTTPException(401) so the ASGI server
    sends a proper WebSocket close frame (not a handshake crash). Auth failures
    use 1008 by default, 4001 when the client should refresh its token, and
    4004 when it should force re-login.
    """
    if not authorization:
        raise WebSocketException(code=1008, reason="Authorization header not found")
    elif len(str(authorization).split(' ')) != 2:
        raise WebSocketException(code=1008, reason="Invalid authorization token")

    try:
        token = authorization.split(' ')[1]
        return verify_token(token)
    except (InvalidIdTokenError, CertificateFetchError) as e:
        close_code, reason = _get_ws_auth_close(e)
        logger.error("WebSocket auth failed: code=%s error=%s", close_code, e)
        raise WebSocketException(code=close_code, reason=reason)
    except Exception as e:
        logger.error(f"WebSocket auth error: {e}")
        raise WebSocketException(code=1008, reason="Auth error")


def _get_ws_auth_close(error: Exception) -> 'tuple[int, str]':
    if isinstance(error, RevokedIdTokenError):
        return WS_AUTH_CODE_RELOGIN_REQUIRED, "Token revoked; re-login required"
    if isinstance(error, CertificateFetchError):
        return WS_AUTH_CODE_TOKEN_REFRESH, "Token refresh required"
    if isinstance(error, ExpiredIdTokenError):
        return WS_AUTH_CODE_TOKEN_REFRESH, "Token refresh required"

    message = str(error).lower()
    if 'revoked' in message:
        return WS_AUTH_CODE_RELOGIN_REQUIRED, "Token revoked; re-login required"
    if 'expired' in message or 'certificate' in message:
        return WS_AUTH_CODE_TOKEN_REFRESH, "Token refresh required"
    return 1008, "Invalid authorization token"


async def get_current_user_uid_ws_listen(
    websocket: WebSocket = None,  # pyright: ignore[reportArgumentType]  # FastAPI needs bare WebSocket type for WS injection
    authorization: str = Header(None),
):
    """WebSocket auth for /v4/listen — NO rate limiting.

    Mobile apps reconnect legitimately on network switch / backgrounding,
    so the per-UID rate limiter must not block them.

    This remains async so Firebase verification does not block the event loop.
    Customer credential headers are intentionally ignored; listen always uses
    the product-managed provider policy and account quota.
    """
    uid = await run_blocking(critical_executor, _verify_ws_auth, authorization)

    return uid


async def get_current_participant_uid_ws_listen(
    websocket: WebSocket = None,  # pyright: ignore[reportArgumentType]  # FastAPI needs bare WebSocket type for WS injection
    authorization: str = Header(None),
) -> str:
    """Authenticate and admit a hosted-compute WebSocket before its handler runs."""

    uid = await run_blocking(critical_executor, _verify_ws_auth, authorization)
    try:
        require_hosted_participant(uid)
    except (ParticipantNotAdmittedError, ParticipantAdmissionConfigurationError) as exc:
        raise WebSocketException(code=1008, reason=str(exc)) from exc

    return uid


def get_current_user_uid_ws(authorization: str = Header(None)):
    """WebSocket auth WITH per-UID rate limiting (7s window).

    Use for WebSocket endpoints that need retry-storm protection.
    """
    uid = _verify_ws_auth(authorization)

    # Fail-open on Redis errors to avoid reintroducing handshake crashes
    try:
        if not try_acquire_listen_lock(uid):
            logger.warning(f"WebSocket rate limited uid={uid}")
            raise WebSocketException(code=1008, reason="Rate limited, retry later")
    except WebSocketException:
        raise
    except Exception as e:
        logger.error(f"Rate limit check failed (allowing connection): {e}")

    return uid


def get_current_user_uid_from_ws_message(message: Dict[str, Any]) -> str:
    """
    Get user uid from WebSocket first-message auth.

    Expected message format: {"type": "auth", "token": "<token>"}

    Returns:
        The user's uid

    Raises:
        ValueError: If message format is invalid
        InvalidIdTokenError: If token is invalid
    """
    if message.get("type") == "websocket.disconnect":
        raise ValueError("Client disconnected")

    text = message.get("text")
    if text is None:
        raise ValueError("Expected JSON auth message")

    try:
        loaded = json.loads(text)
    except json.JSONDecodeError:
        raise ValueError("Invalid JSON")

    auth_data: Dict[str, Any] = cast(Dict[str, Any], loaded) if isinstance(loaded, dict) else {}

    if auth_data.get("type") != "auth":
        raise ValueError("First message must be auth")

    token = auth_data.get("token")
    if not token:
        raise ValueError("Missing token")

    return verify_token(token)


cached: Dict[str, Any] = {}

# This in-process rate-limit cache is keyed by "{endpoint}:{ip}", so a stream of distinct client IPs
# would otherwise grow it without bound. Bound the map.
_MAX_RATE_LIMIT_ENTRIES = 100000


def _store_rate_limit(key: str, value: str) -> None:
    cached[key] = value
    if len(cached) > _MAX_RATE_LIMIT_ENTRIES:
        for stale in list(cached)[: len(cached) - _MAX_RATE_LIMIT_ENTRIES]:
            del cached[stale]


def rate_limit_custom(endpoint: str, request: Request, requests_per_window: int, window_seconds: int) -> bool:
    ip = request.client.host if request.client else None
    key = f"rate_limit:{endpoint}:{ip}"

    # Check if the IP is already rate-limited
    current_raw = cached.get(key)
    current: Optional[Dict[str, Any]] = None
    if current_raw:
        try:
            current = cast(Dict[str, Any], json.loads(current_raw))
        except (json.JSONDecodeError, TypeError, KeyError):
            # Corrupt cache entry: fail open by starting a fresh window rather than 500ing the request.
            current = None

    timestamp = 0
    remaining = 0
    if current:
        current_time = int(time.time())
        remaining = current.get("remaining", 0)
        timestamp = current.get("timestamp", 0)

        # Check if the time window has expired
        if current_time - timestamp >= window_seconds:
            # A new window starts with the full quota; the shared decrement below charges
            # this request, matching the first-request branch. Subtracting here too spent
            # one slot twice and left every window after the first one request short.
            remaining = requests_per_window
            timestamp = current_time
        elif remaining == 0:
            raise HTTPException(status_code=429, detail="Too Many Requests")

        remaining -= 1

    else:
        # If no previous data found, start a new time window
        remaining = requests_per_window - 1
        timestamp = int(time.time())

    # Update the rate limit info in the in-process cache
    _store_rate_limit(key, json.dumps({"timestamp": timestamp, "remaining": remaining}))

    return True


# Dependency to enforce custom rate limiting for specific endpoints
def rate_limit_dependency(
    endpoint: str = "", requests_per_window: int = 60, window_seconds: int = 60
) -> Callable[[Request], bool]:
    def rate_limit(request: Request) -> bool:
        return rate_limit_custom(endpoint, request, requests_per_window, window_seconds)

    return rate_limit


def _enforce_rate_limit(key: str, policy_name: str, *, fail_closed: bool = False) -> None:
    """Shared rate limit enforcement. Raises HTTPException(429) or logs in shadow mode.

    One Redis round-trip per call (Lua script). Fail-open on Redis errors.
    """
    max_requests, window = get_effective_limit(policy_name)
    try:
        allowed, _remaining, retry_after = check_rate_limit(key, policy_name, max_requests, window)
    except redis_pkg.exceptions.RedisError as e:  # type: ignore[reportAttributeAccessIssue]  # redis pkg exposes exceptions at runtime
        logger.error("event=rate_limit outcome=redis_error policy=%s exception_type=%s", policy_name, type(e).__name__)
        if fail_closed:
            raise HTTPException(status_code=503, detail="Rate limiter unavailable")
        return

    if not allowed:
        if RATE_LIMIT_SHADOW:
            logger.warning(
                "event=rate_limit outcome=shadow_rejected policy=%s retry_after_seconds=%s", policy_name, retry_after
            )
            return
        raise HTTPException(
            status_code=429,
            detail=f"Rate limit exceeded. Try again in {retry_after}s.",
            headers={
                "X-RateLimit-Limit": str(max_requests),
                "X-RateLimit-Remaining": "0",
                "Retry-After": str(retry_after),
            },
        )


def with_rate_limit(auth_dependency: Callable[..., Any], policy_name: str) -> Callable[..., Any]:
    """Wrap an auth dependency with per-UID rate limiting.

    After auth succeeds, checks the rate limit for that UID.
    One Redis call per request. Fail-open on Redis errors for first-party user paths.

    Args:
        auth_dependency: FastAPI dependency that returns a UID string.
        policy_name: Key in RATE_POLICIES (utils/rate_limit_config.py).
    """
    if policy_name not in RATE_POLICIES:
        raise ValueError(f"Unknown rate limit policy: {policy_name}")

    async def dependency(uid: str = Depends(auth_dependency)) -> str:
        await run_blocking(critical_executor, _enforce_rate_limit, uid, policy_name)
        return uid

    return dependency


F = TypeVar("F", bound=Callable[..., Any])


def timeit(func: F) -> F:
    """
    Decorator for measuring function's running time.
    """

    def measure_time(*args: Any, **kw: Any) -> Any:
        start_time = time.time()
        result = func(*args, **kw)
        logger.info("Processing time of %s(): %.2f seconds." % (func.__qualname__, time.time() - start_time))
        return result

    return cast(F, measure_time)


def delete_account(uid: str) -> Dict[str, str]:
    auth.delete_user(uid)  # type: ignore[reportUnknownMemberType]  # firebase_admin auth untyped
    return {"message": "User deleted"}
