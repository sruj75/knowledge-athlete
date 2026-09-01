from __future__ import annotations

import asyncio
import json
import os
import re
from collections.abc import AsyncIterator, Mapping
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from fastapi.responses import StreamingResponse
from fastapi.routing import APIRoute

from database import llm_usage as llm_usage_db
from database import redis_db
from utils.executors import critical_executor, db_executor, llm_executor, run_blocking
from utils.http_client import get_gemini_client, get_gemini_semaphore
from utils.llm.desktop_llm_stub import llm_stub_enabled, stub_gemini_stream
from utils.llm.managed_stream_transport import (
    MANAGED_STREAM_HEARTBEAT,
    stream_managed_response_bytes,
)
from utils.llm.model_config import get_model
from utils.llm.provider_errors import handle_llm_error
from utils.observability.langfuse import ChatGeneration, normalize_session_id, start_chat_generation
from utils.observability.langfuse_prompts import (
    ResolvedRuntimePrompt,
    compose_system_prompt,
    fallback_runtime_prompt,
    get_runtime_prompt,
)
from utils.other import endpoints as auth
from utils.subscription import enforce_chat_quota

_MAX_BODY_BYTES = 16 * 1024 * 1024
_RATE_LIMIT_PER_MINUTE = 120
_MODEL = get_model('chat_agent')
_MAX_OUTPUT_TOKENS = 16_384
_CHAT_CONTRACT_VERSION = '2'
_GEMINI_BASE_URL = 'https://generativelanguage.googleapis.com/v1beta'
_BACKEND_ROUTE = f'/v2/models/{_MODEL}:streamGenerateContent'
_SSE_BOUNDARY = re.compile(br'\r?\n\r?\n')
_ALLOWED_REQUEST_FIELDS = frozenset({'contents', 'generationConfig', 'systemInstruction', 'toolConfig', 'tools'})
_ALLOWED_GENERATION_CONFIG_FIELDS = frozenset({'maxOutputTokens', 'temperature', 'thinkingConfig'})
_ALLOWED_THINKING_CONFIG_FIELDS = frozenset({'includeThoughts', 'thinkingLevel'})


class _BoundedChatRoute(APIRoute):
    def get_route_handler(self):
        route_handler = super().get_route_handler()

        async def bounded_route_handler(request: Request):
            content_length = request.headers.get('content-length')
            if content_length is not None:
                try:
                    if int(content_length) > _MAX_BODY_BYTES:
                        raise HTTPException(status_code=413, detail='Request body is too large')
                except ValueError as exc:
                    raise HTTPException(status_code=400, detail='Invalid Content-Length') from exc
            received = 0
            receive = request.receive

            async def bounded_receive():
                nonlocal received
                message = await receive()
                if message.get('type') == 'http.request':
                    body = message.get('body', b'')
                    if isinstance(body, bytes):
                        received += len(body)
                        if received > _MAX_BODY_BYTES:
                            raise HTTPException(status_code=413, detail='Request body is too large')
                return message

            return await route_handler(Request(request.scope, receive=bounded_receive))

        return bounded_route_handler


router = APIRouter(route_class=_BoundedChatRoute)


def _validate_native_request(model: str, body: object, alt: str | None) -> dict[str, object]:
    if model != _MODEL:
        raise ValueError('unsupported model')
    if alt not in {None, 'sse'}:
        raise ValueError('alt must be sse')
    if not isinstance(body, dict):
        raise ValueError('request body must be an object')
    unknown_fields = set(body) - _ALLOWED_REQUEST_FIELDS
    if unknown_fields:
        raise ValueError(f'unsupported request field: {sorted(unknown_fields)[0]}')
    contents = body.get('contents')
    if not isinstance(contents, list):
        raise ValueError('contents must be an array')
    generation_config = body.get('generationConfig')
    if generation_config is None:
        generation_config = {}
        body['generationConfig'] = generation_config
    if not isinstance(generation_config, dict):
        raise ValueError('generationConfig must be an object')
    unknown_generation_fields = set(generation_config) - _ALLOWED_GENERATION_CONFIG_FIELDS
    if unknown_generation_fields:
        raise ValueError(f'unsupported generationConfig field: {sorted(unknown_generation_fields)[0]}')
    requested_maximum = generation_config.get('maxOutputTokens', _MAX_OUTPUT_TOKENS)
    if not isinstance(requested_maximum, int) or isinstance(requested_maximum, bool) or requested_maximum < 1:
        raise ValueError('maxOutputTokens must be a positive integer')
    generation_config['maxOutputTokens'] = min(requested_maximum, _MAX_OUTPUT_TOKENS)
    thinking_config = generation_config.get('thinkingConfig')
    if thinking_config is not None:
        if not isinstance(thinking_config, Mapping):
            raise ValueError('thinkingConfig must be an object')
        unknown_thinking_fields = set(thinking_config) - _ALLOWED_THINKING_CONFIG_FIELDS
        if unknown_thinking_fields:
            raise ValueError(f'unsupported thinkingConfig field: {sorted(unknown_thinking_fields)[0]}')
        level = thinking_config.get('thinkingLevel')
        if level is not None and level not in {'LOW', 'MEDIUM', 'HIGH'}:
            raise ValueError('unsupported thinkingLevel')
    return body


def _system_instruction_text(value: object) -> str | None:
    if isinstance(value, str):
        return value
    if not isinstance(value, Mapping):
        return None
    parts = value.get('parts')
    if not isinstance(parts, list):
        return None
    text = ''.join(
        str(part['text']) for part in parts if isinstance(part, Mapping) and isinstance(part.get('text'), str)
    )
    return text or None


async def _resolve_runtime_system_prompt(payload: dict[str, object]) -> ResolvedRuntimePrompt:
    try:
        prompt = await run_blocking(llm_executor, get_runtime_prompt)
    except Exception:
        prompt = fallback_runtime_prompt(reason='other')
    combined = compose_system_prompt(prompt, _system_instruction_text(payload.get('systemInstruction')))
    if combined:
        payload['systemInstruction'] = {'parts': [{'text': combined}]}
    else:
        payload.pop('systemInstruction', None)
    return prompt


def _usage_values(usage: Mapping[str, object] | None) -> tuple[int, int, int, int]:
    if usage is None:
        return 0, 0, 0, 0
    prompt_tokens = int(usage.get('promptTokenCount') or 0)
    cached_tokens = int(usage.get('cachedContentTokenCount') or 0)
    candidate_tokens = int(usage.get('candidatesTokenCount') or 0)
    thought_tokens = int(usage.get('thoughtsTokenCount') or 0)
    return max(0, prompt_tokens - cached_tokens), candidate_tokens + thought_tokens, cached_tokens, 0


async def _record_usage(uid: str, usage: Mapping[str, object]) -> None:
    input_tokens, output_tokens, cache_read_tokens, cache_write_tokens = _usage_values(usage)
    await run_blocking(
        db_executor,
        llm_usage_db.record_llm_usage_bucket,
        uid,
        input_tokens,
        output_tokens,
        cache_read_tokens,
        cache_write_tokens,
        input_tokens + output_tokens + cache_read_tokens + cache_write_tokens,
        0.0,
    )


def _langfuse_usage_details(usage: Mapping[str, object] | None) -> dict[str, int] | None:
    if usage is None:
        return None
    input_tokens, output_tokens, cache_read_tokens, cache_write_tokens = _usage_values(usage)
    return {
        'input': input_tokens,
        'output': output_tokens,
        'cache_read_input_tokens': cache_read_tokens,
        'cache_creation_input_tokens': cache_write_tokens,
    }


class _GeminiStreamObservation:
    def __init__(self) -> None:
        self._buffer = b''
        self.text: list[str] = []
        self.tool_calls: list[dict[str, object]] = []
        self.finish_reason: str | None = None
        self.usage: Mapping[str, object] | None = None
        self.completion_started = False

    def feed(self, chunk: bytes) -> None:
        self._buffer += chunk
        while True:
            boundary = _SSE_BOUNDARY.search(self._buffer)
            if boundary is None:
                return
            event = self._buffer[: boundary.start()]
            self._buffer = self._buffer[boundary.end() :]
            data = b'\n'.join(
                line.split(b':', 1)[1].lstrip() for line in event.splitlines() if line.startswith(b'data:')
            )
            if not data:
                continue
            try:
                value = json.loads(data)
            except (UnicodeDecodeError, ValueError):
                continue
            self._observe_value(value)

    def _observe_value(self, value: object) -> None:
        if not isinstance(value, Mapping):
            return
        usage = value.get('usageMetadata')
        if isinstance(usage, Mapping):
            self.usage = usage
        candidates = value.get('candidates')
        if not isinstance(candidates, list):
            return
        for candidate in candidates:
            if not isinstance(candidate, Mapping):
                continue
            finish_reason = candidate.get('finishReason')
            if isinstance(finish_reason, str):
                self.finish_reason = finish_reason
            content = candidate.get('content')
            parts = content.get('parts') if isinstance(content, Mapping) else None
            if not isinstance(parts, list):
                continue
            for part in parts:
                if not isinstance(part, Mapping):
                    continue
                text = part.get('text')
                if isinstance(text, str) and text:
                    self.completion_started = True
                    if part.get('thought') is not True:
                        self.text.append(text)
                function_call = part.get('functionCall')
                if isinstance(function_call, Mapping):
                    self.completion_started = True
                    self.tool_calls.append(dict(function_call))

    def output(self) -> dict[str, object]:
        result: dict[str, object] = {'text': ''.join(self.text), 'stop_reason': self.finish_reason}
        if self.tool_calls:
            result['tool_calls'] = self.tool_calls
        return result


async def _stream_native_gemini(
    payload: dict[str, object],
    uid: str,
    *,
    api_key: str,
    request_id: str,
    session_id: str | None,
    platform: str | None,
    prompt: ResolvedRuntimePrompt,
) -> AsyncIterator[bytes]:
    observation = _GeminiStreamObservation()
    generation: ChatGeneration = start_chat_generation(
        uid=uid,
        request_id=request_id,
        session_id=session_id,
        platform=platform,
        model=_MODEL,
        provider_input=payload,
        prompt_version=prompt.version,
        prompt_source=prompt.source,
        prompt_client=prompt.prompt_client,
        streaming=True,
    )
    level: str | None = None
    status_message: str | None = None
    marked_completion = False
    client = get_gemini_client()
    url = f'{_GEMINI_BASE_URL}/models/{_MODEL}:streamGenerateContent?alt=sse'

    try:
        async with get_gemini_semaphore():
            async for chunk in stream_managed_response_bytes(
                lambda: client.stream(
                    'POST',
                    url,
                    headers={'content-type': 'application/json', 'x-goog-api-key': api_key},
                    json=payload,
                )
            ):
                if chunk is MANAGED_STREAM_HEARTBEAT:
                    yield b': keep-alive\n\n'
                    continue
                if not isinstance(chunk, bytes):
                    continue
                observation.feed(chunk)
                if observation.completion_started and not marked_completion:
                    marked_completion = True
                    generation.mark_completion_started(datetime.now(timezone.utc))
                yield chunk
        if observation.usage is not None:
            await _record_usage(uid, observation.usage)
    except (asyncio.CancelledError, GeneratorExit):
        level = 'WARNING'
        status_message = 'cancelled'
        raise
    except Exception as exc:
        level = 'ERROR'
        status_message = type(exc).__name__
        handle_llm_error(exc, 'gemini', feature='chat_agent', model=_MODEL)
        yield b'data: ' + json.dumps(_sanitized_stream_error(exc), separators=(',', ':')).encode() + b'\n\n'
    finally:
        generation.finish(
            output=observation.output(),
            usage_details=_langfuse_usage_details(observation.usage),
            level=level,
            status_message=status_message,
        )


def _sanitized_stream_error(exc: Exception) -> dict[str, object]:
    upstream_status = exc.response.status_code if isinstance(exc, httpx.HTTPStatusError) else None
    if upstream_status in (401, 403):
        reason, status, retryable = 'provider_auth_failed', 'UNAUTHENTICATED', False
    elif upstream_status == 429:
        reason, status, retryable = 'provider_quota_exceeded', 'RESOURCE_EXHAUSTED', True
    else:
        reason = 'provider_unavailable'
        status = 'UNAVAILABLE'
        retryable = upstream_status is None or upstream_status in (408, 409, 425) or upstream_status >= 500
    return {
        'error': {
            'code': upstream_status or 502,
            'message': 'Upstream provider error',
            'status': status,
        },
        'reason': reason,
        'provider': 'gemini',
        'backend_route': _BACKEND_ROUTE,
        'upstream_status_code': upstream_status,
        'retryable': retryable,
    }


async def _meter_server_request(uid: str) -> None:
    try:
        allowed, _, retry_after = await run_blocking(
            critical_executor, redis_db.check_rate_limit, uid, 'desktop_chat', _RATE_LIMIT_PER_MINUTE, 60
        )
    except Exception as exc:
        raise HTTPException(status_code=503, detail='Chat metering is temporarily unavailable') from exc
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail={'error': {'message': 'Rate limit exceeded', 'type': 'rate_limit_error', 'code': 429}},
            headers={'Retry-After': str(retry_after)},
        )


@router.post('/v2/models/{model}:streamGenerateContent', response_model=None)
async def stream_generate_content(
    model: str,
    body: dict[str, object],
    alt: str | None = Query(None),
    uid: str = Depends(auth.get_current_user_uid),
    x_app_platform: str | None = Header(None, alias='X-App-Platform'),
    x_omi_chat_contract_version: str | None = Header(None, alias='X-Omi-Chat-Contract-Version'),
    x_omi_request_id: str | None = Header(None, alias='X-Omi-Request-Id'),
    x_omi_session_id: str | None = Header(None, alias='X-Omi-Session-Id'),
    x_goog_api_key: str | None = Header(None, alias='X-Goog-Api-Key'),
) -> StreamingResponse:
    if isinstance(x_goog_api_key, str):
        raise HTTPException(status_code=400, detail='Client provider keys are not accepted')
    if x_omi_chat_contract_version not in {None, _CHAT_CONTRACT_VERSION}:
        raise HTTPException(status_code=426, detail='Unsupported chat contract version')
    try:
        payload = _validate_native_request(model, body, alt)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    request_id = x_omi_request_id or str(uuid4())
    response_headers = {
        'Cache-Control': 'no-cache',
        'X-Omi-Chat-Contract-Version': _CHAT_CONTRACT_VERSION,
        'X-Request-Id': request_id,
    }
    if llm_stub_enabled():
        return StreamingResponse(
            stub_gemini_stream(payload),
            media_type='text/event-stream',
            headers=response_headers,
        )

    api_key = os.environ.get('GEMINI_API_KEY', '').strip()
    if not api_key:
        raise HTTPException(status_code=503, detail='Managed Gemini is not configured')
    enforce_chat_quota(uid, platform=x_app_platform)
    await _meter_server_request(uid)
    prompt = await _resolve_runtime_system_prompt(payload)
    session_id = normalize_session_id(x_omi_session_id)
    await run_blocking(
        db_executor,
        llm_usage_db.record_chat_quota_question,
        uid,
        f'desktop_chat:{request_id}',
        'desktop_chat',
        platform=x_app_platform,
    )
    return StreamingResponse(
        _stream_native_gemini(
            payload,
            uid,
            api_key=api_key,
            request_id=request_id,
            session_id=session_id,
            platform=x_app_platform,
            prompt=prompt,
        ),
        media_type='text/event-stream',
        headers=response_headers,
    )
