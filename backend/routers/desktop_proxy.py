import json
import os
from typing import Any

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import Response

from database import redis_db
from utils.executors import critical_executor, db_executor, run_blocking
from utils.llm.desktop_llm_stub import (
    llm_stub_enabled,
    stub_gemini_proxy_json,
)
from utils.other.endpoints import get_current_user_uid
from utils.subscription import is_trial_paywalled

router = APIRouter()

_ALLOWED_ACTIONS = frozenset({"generateContent", "embedContent", "batchEmbedContents"})
_ALLOWED_MODELS = frozenset({"gemini-2.5-flash", "gemini-2.5-flash-lite", "gemini-embedding-001"})
_MAX_BODY_BYTES = 5 * 1024 * 1024
_MAX_OUTPUT_TOKENS = 8192
_DEFAULT_THINKING_BUDGET = 1024
_BURST_LIMIT = 30
_DAILY_HARD_LIMIT = 1500


def _path_parts(path: str) -> tuple[str, str, str]:
    path = path.replace("gemini-3-flash-preview", "gemini-2.5-flash")
    prefix, separator, action = path.partition(":")
    model = prefix.removeprefix("models/") if separator and prefix.startswith("models/") else ""
    if action not in _ALLOWED_ACTIONS or model not in _ALLOWED_MODELS:
        raise HTTPException(status_code=403, detail="Gemini model or action is not allowed")
    return path, model, action


def _as_nonnegative_int(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, int) and value >= 0:
        return value
    if isinstance(value, float) and value >= 0 and value.is_integer():
        return int(value)
    if isinstance(value, str) and value.isdigit():
        return int(value)
    return None


def _sanitize(body: bytes, action: str) -> bytes:
    try:
        payload = json.loads(body)
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=400, detail="Request body must be valid JSON") from exc
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Request body must be a JSON object")
    for key in ("safety_settings", "safetySettings", "cached_content", "cachedContent"):
        payload.pop(key, None)
    contents = payload.get("contents")
    if isinstance(contents, list):
        system_parts: list[Any] = []
        remaining = []
        for content in contents:
            if not isinstance(content, dict):
                remaining.append(content)
                continue
            role = content.setdefault("role", "user")
            if role == "system":
                if isinstance(content.get("parts"), list):
                    system_parts.extend(content["parts"])
            else:
                remaining.append(content)
        payload["contents"] = remaining
        if system_parts:
            key = "system_instruction" if "system_instruction" in payload else "systemInstruction"
            instruction = payload.get(key)
            if isinstance(instruction, dict) and isinstance(instruction.get("parts"), list):
                instruction["parts"].extend(system_parts)
            else:
                payload["systemInstruction"] = {"parts": system_parts}
    if action not in {"embedContent", "batchEmbedContents"}:
        for key in ("candidate_count", "candidateCount"):
            value = _as_nonnegative_int(payload.get(key))
            if value is not None and value > 1:
                raise HTTPException(status_code=400, detail="candidate_count must be 1 or absent")
        generation_configs = [
            payload[key] for key in ("generation_config", "generationConfig") if isinstance(payload.get(key), dict)
        ]
        if not generation_configs:
            payload["generationConfig"] = {"thinkingConfig": {"thinkingBudget": _DEFAULT_THINKING_BUDGET}}
        for config in generation_configs:
            for key in ("candidate_count", "candidateCount"):
                value = _as_nonnegative_int(config.get(key))
                if value is not None and value > 1:
                    raise HTTPException(status_code=400, detail="candidate_count must be 1 or absent")
            for key in ("max_output_tokens", "maxOutputTokens"):
                value = _as_nonnegative_int(config.get(key))
                if value is not None and value > _MAX_OUTPUT_TOKENS:
                    config[key] = _MAX_OUTPUT_TOKENS
            if "thinking_config" not in config and "thinkingConfig" not in config:
                config["thinkingConfig"] = {"thinkingBudget": _DEFAULT_THINKING_BUDGET}
    return json.dumps(payload, separators=(",", ":")).encode()


def _studio_url(path: str) -> str:
    key = os.getenv("GEMINI_API_KEY")
    if not key:
        raise HTTPException(status_code=503, detail="Gemini is not configured")
    return f"https://generativelanguage.googleapis.com/v1beta/{path}"


def _upstream(path: str, query: dict[str, str]) -> tuple[str, dict[str, str], dict[str, str]]:
    key = os.getenv("GEMINI_API_KEY", "")
    return _studio_url(path), {"x-goog-api-key": key}, {name: value for name, value in query.items() if name != "key"}


async def _meter_server_request(uid: str, path: str, model: str, action: str) -> str:
    try:
        burst_allowed, _, _ = await run_blocking(
            critical_executor, redis_db.check_rate_limit, uid, "desktop_gemini_burst", _BURST_LIMIT, 60
        )
        if not burst_allowed:
            raise HTTPException(status_code=429, detail="Gemini request rate limit exceeded")
        _, current, _ = await run_blocking(
            critical_executor,
            redis_db.check_rate_limit,
            uid,
            "desktop_gemini_daily",
            _DAILY_HARD_LIMIT,
            86_400,
        )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Gemini rate limiter is unavailable") from exc
    if int(current) > _DAILY_HARD_LIMIT:
        raise HTTPException(status_code=429, detail="Gemini daily request limit exceeded")
    return path


async def _proxy(request: Request, path: str, uid: str) -> Response:
    body = await request.body()
    if len(body) > _MAX_BODY_BYTES:
        raise HTTPException(status_code=413, detail="Request body is too large")
    path, model, action = _path_parts(path)
    if llm_stub_enabled():
        body_text = body.decode("utf-8", errors="replace")
        payload = stub_gemini_proxy_json(body_text)
        return Response(
            json.dumps(payload, separators=(",", ":")).encode("utf-8"),
            media_type="application/json",
        )
    path = await _meter_server_request(uid, path, model, action)
    _, model, action = _path_parts(path)
    body = _sanitize(body, action)
    url, headers, params = _upstream(path, dict(request.query_params))
    try:
        async with httpx.AsyncClient(timeout=httpx.Timeout(240, connect=10)) as client:
            response = await client.post(
                url, params=params, content=body, headers={"Content-Type": "application/json", **headers}
            )
        return Response(
            response.content,
            status_code=response.status_code,
            media_type=response.headers.get("content-type"),
        )
    except httpx.TimeoutException as exc:
        raise HTTPException(status_code=504, detail="Gemini request timed out") from exc
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail="Gemini upstream request failed") from exc


async def _authorized_desktop_user(uid: str = Depends(get_current_user_uid)) -> str:
    if await run_blocking(db_executor, is_trial_paywalled, uid, "desktop"):
        raise HTTPException(status_code=402, detail="trial_expired")
    return uid


@router.post("/v1/proxy/gemini/{path:path}")
async def gemini_proxy(request: Request, path: str, uid: str = Depends(_authorized_desktop_user)) -> Response:
    return await _proxy(request, path, uid)
