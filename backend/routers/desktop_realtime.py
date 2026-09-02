import json
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
from fastapi import APIRouter, Depends, Response
from fastapi.responses import JSONResponse
from google.cloud import firestore
from pydantic import BaseModel, ConfigDict, StrictInt

from database._client import get_firestore_client
from utils.executors import db_executor, run_blocking
from utils.other.endpoints import get_current_user_uid
from utils.subscription import is_trial_paywalled

router = APIRouter()
logger = logging.getLogger(__name__)

_GEMINI_AUTH_TOKENS_URL = "https://generativelanguage.googleapis.com/v1alpha/auth_tokens"
_GEMINI_LIVE_MODEL = "models/gemini-3.1-flash-live-preview"
_SESSION_START_WINDOW_MIN = 2
_SESSION_MAX_MIN = 30
_TRIAL_EXPIRED_MESSAGE = "Desktop trial expired. Upgrade to continue managed voice."


class MintRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")


class UsageReport(BaseModel):
    model_config = ConfigDict(extra="forbid")

    input_text_tokens: StrictInt = 0
    input_audio_tokens: StrictInt = 0
    input_cached_tokens: StrictInt = 0
    output_text_tokens: StrictInt = 0
    output_audio_tokens: StrictInt = 0


def _error(
    status_code: int,
    reason: str,
    message: str,
    provider: str | None = None,
    code: str | None = None,
    upstream_status_code: int | None = None,
    retryable: bool = False,
) -> JSONResponse:
    body: dict[str, Any] = {
        "error": message,
        "reason": reason,
        "backend_route": "/v2/realtime/session",
        "retryable": retryable,
    }
    if provider is not None:
        body["provider"] = provider
    if code is not None:
        body["code"] = code
    if upstream_status_code is not None:
        body["upstream_status_code"] = upstream_status_code
    return JSONResponse(status_code=status_code, content=body)


def _upstream_error(provider: str, status_code: int, body: str) -> JSONResponse:
    try:
        parsed = json.loads(body)
    except json.JSONDecodeError:
        parsed = {}
    error = parsed.get("error") if isinstance(parsed, dict) else None
    error = error if isinstance(error, dict) else {}
    code_value = error.get("code") or error.get("status") or (parsed.get("code") if isinstance(parsed, dict) else None)
    code = str(code_value) if isinstance(code_value, (str, int, float)) and str(code_value) else None
    message_value = error.get("message") or (parsed.get("message") if isinstance(parsed, dict) else None)
    message = message_value if isinstance(message_value, str) else body[:500]
    lower = f"{code or ''} {message}".lower()
    if status_code == 429 or "quota" in lower:
        reason = "provider_quota_exceeded"
    elif status_code in (401, 403) or any(
        value in lower for value in ("invalid api key", "api key not valid", "authentication", "permission denied")
    ):
        reason = "provider_auth_failed"
    elif status_code >= 500:
        reason = "provider_mint_unavailable"
    else:
        reason = "provider_mint_rejected"
    return _error(status_code, reason, message, provider, code, status_code, status_code == 429 or status_code >= 500)


async def _post_json(
    url: str, provider: str, headers: dict[str, str], body: dict[str, Any], params: dict[str, str] | None = None
) -> tuple[dict[str, Any] | None, JSONResponse | None]:
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(15.0, connect=10.0)) as client:
            response = await client.post(url, headers=headers, json=body, params=params)
    except httpx.HTTPError as error:
        return None, _error(502, "provider_mint_transport_error", str(error), retryable=True)
    if not response.is_success:
        return None, _upstream_error(provider, response.status_code, response.text)
    try:
        data = response.json()
    except json.JSONDecodeError as error:
        return None, _error(502, "provider_mint_transport_error", str(error), retryable=True)
    if not isinstance(data, dict):
        return None, _error(
            502, "provider_mint_transport_error", "provider mint response was not an object", retryable=True
        )
    return data, None


@router.post("/v2/realtime/session")
async def mint_session(request: MintRequest, uid: str = Depends(get_current_user_uid)) -> JSONResponse:
    if await run_blocking(db_executor, is_trial_paywalled, uid, "desktop"):
        return JSONResponse(
            status_code=402,
            content={"error": "trial_expired", "message": _TRIAL_EXPIRED_MESSAGE},
        )
    key = os.getenv("GEMINI_API_KEY", "").strip()
    if not key:
        return _error(503, "provider_not_configured", "Gemini realtime is not configured", "Gemini", retryable=True)
    now = datetime.now(timezone.utc)
    start = (now + timedelta(minutes=_SESSION_START_WINDOW_MIN)).strftime("%Y-%m-%dT%H:%M:%SZ")
    expires_at = (now + timedelta(minutes=_SESSION_MAX_MIN)).strftime("%Y-%m-%dT%H:%M:%SZ")
    data, error = await _post_json(
        _GEMINI_AUTH_TOKENS_URL,
        "gemini",
        {},
        {"uses": 1, "expireTime": expires_at, "newSessionExpireTime": start},
        {"key": key},
    )
    if error:
        return error
    token = data.get("name") if data else None
    if not isinstance(token, str):
        return _error(502, "provider_mint_transport_error", "gemini mint: no token name in response", retryable=True)
    return JSONResponse({"provider": "gemini", "token": token, "expires_at": expires_at})


def _record_usage(
    uid: str,
    input_tokens: int,
    output_tokens: int,
    cached_tokens: int,
    total_tokens: int,
    cost: float,
) -> None:
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    account = "desktop_chat_realtime"
    updates: dict[str, Any] = {"date": date, "last_updated": datetime.now(timezone.utc)}
    for prefix in ("desktop_chat", account):
        updates.update(
            {
                f"{prefix}.input_tokens": firestore.Increment(input_tokens),
                f"{prefix}.output_tokens": firestore.Increment(output_tokens),
                f"{prefix}.cache_read_tokens": firestore.Increment(cached_tokens),
                f"{prefix}.cache_write_tokens": firestore.Increment(0),
                f"{prefix}.total_tokens": firestore.Increment(total_tokens),
                f"{prefix}.cost_usd": firestore.Increment(cost),
                f"{prefix}.call_count": firestore.Increment(1),
            }
        )
    updates["desktop_chat.quota_questions"] = firestore.Increment(1)
    updates[f"{account}.quota_questions"] = firestore.Increment(1)
    get_firestore_client().collection("users").document(uid).collection("llm_usage").document(date).set(
        updates, merge=True
    )


def _usage_cost(report: UsageReport) -> float:
    rates = (0.75, 3.0, 0.075, 4.5, 12.0)
    return (
        sum(
            value * rate
            for value, rate in zip(
                (
                    max(report.input_text_tokens, 0),
                    max(report.input_audio_tokens, 0),
                    max(report.input_cached_tokens, 0),
                    max(report.output_text_tokens, 0),
                    max(report.output_audio_tokens, 0),
                ),
                rates,
            )
        )
        / 1_000_000
    )


@router.post("/v2/realtime/usage", status_code=204)
async def report_usage(report: UsageReport, uid: str = Depends(get_current_user_uid)) -> Response:
    if await run_blocking(db_executor, is_trial_paywalled, uid, "desktop"):
        return JSONResponse(
            status_code=402,
            content={"error": "trial_expired", "message": _TRIAL_EXPIRED_MESSAGE},
        )
    input_tokens = max(report.input_text_tokens, 0) + max(report.input_audio_tokens, 0)
    output_tokens = max(report.output_text_tokens, 0) + max(report.output_audio_tokens, 0)
    cached_tokens = max(report.input_cached_tokens, 0)
    total_tokens = input_tokens + output_tokens + cached_tokens
    if total_tokens <= 0:
        return Response(status_code=204)
    try:
        await run_blocking(
            db_executor,
            _record_usage,
            uid,
            input_tokens,
            output_tokens,
            cached_tokens,
            total_tokens,
            _usage_cost(report),
        )
    except Exception:
        logger.error("realtime usage record failed for uid=%s", uid)
        return Response(status_code=502)
    return Response(status_code=204)
