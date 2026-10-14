"""Authenticated, transient conversation compute for typed and spoken A."""

import asyncio
from collections.abc import AsyncIterator
from contextlib import aclosing
from datetime import datetime, timezone
import json
import logging
import os
import re

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from models.desktop_ai import PromptReference
from models.desktop_conversation import (
    ConversationRespondRequest,
    ConversationSessionRequest,
    ConversationSessionResponse,
)
from services.desktop_inference import authorized_desktop_user, enforce_conversation_quota, record_conversation_usage
from utils.bounded_ai_route import BoundedAIRoute
from utils.executors import db_executor, llm_executor, run_blocking
from utils.http_client import get_gemini_client, get_gemini_semaphore
from utils.llm.desktop_llm_stub import exact_reply_token, llm_stub_enabled, stub_assistant_text
from utils.llm.gemini_usage import GeminiUsage
from utils.llm.managed_stream_transport import MANAGED_STREAM_HEARTBEAT, stream_managed_response_bytes
from utils.llm.model_config import get_model
from utils.observability.chat_evaluation import remember_chat_prompt
from utils.observability.conversation_prompts import (
    bootstrap_conversation_prompt,
    resolve_conversation_prompt,
    ConversationPromptMismatchError,
    ConversationPromptUnavailableError,
)
from utils.observability.langfuse import start_chat_generation
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt

router = APIRouter(route_class=BoundedAIRoute)
logger = logging.getLogger(__name__)
_MODEL = get_model('conversation')
_SSE_BOUNDARY = re.compile(rb'\r?\n\r?\n')


class _FunctionCall(BaseModel):
    name: str
    args: dict[str, object] = Field(default_factory=dict)


class _Part(BaseModel):
    text: str = ''
    thought: bool = False
    functionCall: _FunctionCall | None = None


class _Content(BaseModel):
    parts: list[_Part] = Field(default_factory=list[_Part])


class _Candidate(BaseModel):
    content: _Content = Field(default_factory=_Content)
    finishReason: str | None = None


class _ProviderEvent(BaseModel):
    candidates: list[_Candidate] = Field(default_factory=list[_Candidate], max_length=1)
    usageMetadata: GeminiUsage | None = None
    modelVersion: str | None = Field(default=None, max_length=128)


def _sse(event: str, data: dict[str, object]) -> bytes:
    return f'event: {event}\ndata: {json.dumps(data, separators=(",", ":"))}\n\n'.encode()


def _payload(request: ConversationRespondRequest, prompt: ResolvedRuntimePrompt) -> dict[str, object]:
    # Stable context precedes changing history to permit provider prefix reuse.
    # This is evidence in a user content part, never a caller-supplied system policy.
    contents: list[dict[str, object]] = []
    if request.context:
        contents.append({'role': 'user', 'parts': [{'text': json.dumps({'context': request.context})}]})
    contents.extend(
        {'role': 'user' if item.role == 'user' else 'model', 'parts': [{'text': item.text}]} for item in request.history
    )
    parts: list[dict[str, object]] = []
    if request.guidance:
        parts.append({'text': json.dumps({'private_supervisor_guidance': request.guidance})})
    parts.append({'text': request.message})
    if request.image:
        parts.append({'inlineData': {'mimeType': 'image/jpeg', 'data': request.image.jpeg_base64}})
    contents.append({'role': 'user', 'parts': parts})
    return {
        'systemInstruction': {'parts': [{'text': prompt.text}]},
        'contents': contents,
        'generationConfig': {'maxOutputTokens': 4096, 'thinkingConfig': {'thinkingLevel': 'low'}},
        'tools': [
            {
                'functionDeclarations': [
                    {
                        'name': 'end_conversation',
                        'description': 'Signal that this conversation has ended. This cannot execute any other action.',
                        'parameters': {'type': 'OBJECT', 'properties': {}, 'additionalProperties': False},
                    }
                ]
            }
        ],
        'toolConfig': {'functionCallingConfig': {'mode': 'AUTO'}},
    }


async def _stream_response(
    request: ConversationRespondRequest, uid: str, prompt: ResolvedRuntimePrompt, api_key: str
) -> AsyncIterator[bytes]:
    payload = _payload(request, prompt)
    generation = start_chat_generation(
        uid=uid,
        request_id=request.turn_id,
        session_id=request.conversation_id,
        platform='desktop',
        model=_MODEL,
        provider_input=payload,
        prompt_version=prompt.version,
        prompt_source=prompt.source,
        prompt_client=prompt.prompt_client,
        streaming=True,
    )
    buffer = b''
    text_length = 0
    end_conversation = False
    finish_reason: str | None = None
    usage: GeminiUsage | None = None
    model_version: str | None = None
    marked_completion = False
    level: str | None = None
    status: str | None = None
    try:
        async with get_gemini_semaphore():
            async with aclosing(
                stream_managed_response_bytes(
                    lambda: get_gemini_client().stream(
                        'POST',
                        f'https://generativelanguage.googleapis.com/v1beta/models/{_MODEL}:streamGenerateContent?alt=sse',
                        headers={'x-goog-api-key': api_key},
                        json=payload,
                    )
                )
            ) as stream:
                async for chunk in stream:
                    if chunk is MANAGED_STREAM_HEARTBEAT:
                        yield b': keep-alive\n\n'
                        continue
                    if not isinstance(chunk, bytes):
                        continue
                    buffer += chunk
                    if len(buffer) > 1_000_000:
                        raise ValueError('Provider event exceeds its bound')
                    while (boundary := _SSE_BOUNDARY.search(buffer)) is not None:
                        event, buffer = buffer[: boundary.start()], buffer[boundary.end() :]
                        data = b'\n'.join(line[5:].lstrip() for line in event.splitlines() if line.startswith(b'data:'))
                        if not data:
                            continue
                        result = _ProviderEvent.model_validate_json(data)
                        usage = result.usageMetadata or usage
                        model_version = result.modelVersion or model_version
                        for candidate in result.candidates:
                            finish_reason = candidate.finishReason or finish_reason
                            for part in candidate.content.parts:
                                if part.thought:
                                    continue
                                if (part.text or part.functionCall) and not marked_completion:
                                    marked_completion = True
                                    generation.mark_completion_started(datetime.now(timezone.utc))
                                if part.text:
                                    text_length += len(part.text)
                                    if text_length > 32000:
                                        raise ValueError('Provider output exceeds its bound')
                                    yield _sse('text_delta', {'text': part.text})
                                if part.functionCall:
                                    if part.functionCall.name != 'end_conversation' or part.functionCall.args:
                                        raise ValueError('Provider returned an unsupported lifecycle signal')
                                    end_conversation = True
        if buffer.strip() or finish_reason != 'STOP' or not (text_length or end_conversation):
            raise ValueError('Provider stream did not complete a response')
        done: dict[str, object] = {
            'end_conversation': end_conversation,
            'prompt_ref': request.prompt_ref.model_dump(),
        }
        if model_version:
            done['model_version'] = model_version
        if usage is not None:
            done['usage'] = usage.wire()
        yield _sse('done', done)
    except (asyncio.CancelledError, GeneratorExit):
        level, status = 'WARNING', 'cancelled'
        raise
    except Exception as error:
        level, status = 'ERROR', type(error).__name__
        logger.warning('Conversation response failed error_type=%s', type(error).__name__)
        yield _sse('error', {'code': 'provider_unavailable', 'retryable': True})
    finally:
        # The generation already has metadata-only input; do not retain response content.
        generation.finish(
            output={'text': ' ' * text_length, 'stop_reason': finish_reason},
            usage_details=usage.langfuse() if usage else None,
            level=level,
            status_message=status,
        )
        if usage is not None:
            try:
                await record_conversation_usage(uid, usage)
            except Exception as error:
                logger.warning('Conversation usage recording failed error_type=%s', type(error).__name__)


@router.post('/v1/conversation/session', response_model=ConversationSessionResponse)
async def bootstrap_session(
    request: ConversationSessionRequest, uid: str = Depends(authorized_desktop_user)
) -> ConversationSessionResponse:
    prompt = await run_blocking(llm_executor, bootstrap_conversation_prompt)
    return ConversationSessionResponse(conversation_id=request.conversation_id, prompt=prompt)


@router.post('/v1/conversation/respond', response_class=StreamingResponse)
async def respond(
    request: ConversationRespondRequest, uid: str = Depends(authorized_desktop_user)
) -> StreamingResponse:
    try:
        prompt = await run_blocking(llm_executor, resolve_conversation_prompt, request.prompt_ref)
    except ConversationPromptMismatchError as error:
        raise HTTPException(status_code=409, detail='prompt_reference_mismatch') from error
    except ConversationPromptUnavailableError as error:
        raise HTTPException(status_code=503, detail='prompt_unavailable') from error
    if llm_stub_enabled():

        async def stub() -> AsyncIterator[bytes]:
            yield _sse(
                'text_delta', {'text': exact_reply_token(request.message) or stub_assistant_text(request.message)}
            )
            yield _sse('done', {'end_conversation': False, 'prompt_ref': request.prompt_ref.model_dump()})

        return StreamingResponse(stub(), media_type='text/event-stream')
    api_key = os.environ.get('GEMINI_API_KEY', '').strip()
    if not api_key:
        raise HTTPException(status_code=503, detail='Managed Gemini is not configured')
    await enforce_conversation_quota(uid, request.turn_id)
    await run_blocking(
        db_executor,
        remember_chat_prompt,
        uid,
        request.turn_id,
        PromptReference(name=prompt.name, version=prompt.version, source=request.prompt_ref.source),
    )
    return StreamingResponse(
        _stream_response(request, uid, prompt, api_key),
        media_type='text/event-stream',
        headers={'Cache-Control': 'no-cache', 'X-Request-Id': request.turn_id},
    )
