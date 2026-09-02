"""Unit tests for the hermetic desktop LLM stub (OMI_LLM_STUB)."""

from __future__ import annotations

import json

import pytest

from utils.llm import desktop_llm_stub as stub


def _user_body(text: str, *, tools: list[str] | None = None, stream: bool = False) -> dict:
    body: dict = {
        'model': 'gemini-3.7-flash',
        'messages': [{'role': 'user', 'content': text}],
        'stream': stream,
    }
    if tools:
        body['tools'] = [
            {'type': 'function', 'function': {'name': name, 'parameters': {'type': 'object'}}} for name in tools
        ]
    return body


def test_llm_stub_flag_truthy_values():
    assert stub.llm_stub_flag_is_truthy('1')
    assert stub.llm_stub_flag_is_truthy('true')
    assert stub.llm_stub_flag_is_truthy('YES')
    assert not stub.llm_stub_flag_is_truthy('0')
    assert not stub.llm_stub_flag_is_truthy('false')
    assert stub.llm_stub_enabled({'OMI_LLM_STUB': '1'})
    assert not stub.llm_stub_enabled({})


def test_chat_hermetic_exact_reply_token():
    body = _user_body('Reply with exactly [[MARKER:chat-hermetic]]')
    directive = stub.stub_directive(body)
    assert isinstance(directive, stub._TextDirective)
    assert directive.text == 'MARKER:chat-hermetic'


def test_floating_bar_marker_echo():
    body = _user_body('Hermetic floating bar [[MARKER:floating-bar]]')
    directive = stub.stub_directive(body)
    assert isinstance(directive, stub._TextDirective)
    assert directive.text == 'Stub saw marker: floating-bar'


def test_kernel_user_message_boundary_ignores_history_markers():
    wrapped = 'Prior context with [[MARKER:old]]\n\n# User Message\n' 'Reply with exactly [[MARKER:chat-hermetic]]'
    body = _user_body(wrapped)
    directive = stub.stub_directive(body)
    assert isinstance(directive, stub._TextDirective)
    assert directive.text == 'MARKER:chat-hermetic'


def test_gauntlet_spawn_emits_tool_call():
    body = _user_body(
        'Use spawn_agent now to start a visible background agent titled "Recall Page". '
        'Objective: track marker GAUNTLET-SPAWN-ABC and wait silently.',
        tools=['spawn_agent'],
    )
    directive = stub.stub_directive(body)
    assert isinstance(directive, stub._ToolCallDirective)
    assert directive.name == 'spawn_agent'
    assert directive.arguments['title'] == 'Recall Page'
    assert 'GAUNTLET-SPAWN-ABC' in directive.arguments['objective']


@pytest.mark.asyncio
async def test_stream_emits_native_gemini_sse_for_exact_reply():
    body = {'contents': [{'role': 'user', 'parts': [{'text': 'Reply with exactly [[MARKER:chat-hermetic]]'}]}]}
    chunks = [chunk async for chunk in stub.stub_gemini_stream(body)]
    assert len(chunks) == 1
    payload = json.loads(chunks[0][6:])
    assert payload['candidates'][0]['content']['parts'][0]['text'] == 'MARKER:chat-hermetic'
    assert payload['usageMetadata']['totalTokenCount'] == 2


@pytest.mark.asyncio
async def test_native_gemini_stub_tool_call_and_follow_up_response():
    first_body = {
        'contents': [{'role': 'user', 'parts': [{'text': 'Use spawn_agent now for GAUNTLET-SPAWN-ABC'}]}],
        'tools': [{'functionDeclarations': [{'name': 'spawn_agent', 'parametersJsonSchema': {'type': 'object'}}]}],
    }
    first = json.loads((await anext(stub.stub_gemini_stream(first_body)))[6:])
    call_part = first['candidates'][0]['content']['parts'][0]
    assert call_part['functionCall']['name'] == 'spawn_agent'
    assert call_part['thoughtSignature'] == 'c3R1Yi10aG91Z2h0LXNpZ25hdHVyZQ=='

    follow_up_body = {
        **first_body,
        'contents': [
            *first_body['contents'],
            first['candidates'][0]['content'],
            {
                'role': 'user',
                'parts': [
                    {
                        'functionResponse': {
                            'name': 'spawn_agent',
                            'response': {'output': 'started GAUNTLET-SPAWN-ABC'},
                        }
                    }
                ],
            },
        ],
    }
    follow_up = json.loads((await anext(stub.stub_gemini_stream(follow_up_body)))[6:])
    assert follow_up['candidates'][0]['content']['parts'][0]['text'] == (
        'Started the background agent for GAUNTLET-SPAWN-ABC.'
    )


def test_gemini_proxy_stub_echoes_marker():
    body = json.dumps(
        {
            'contents': [
                {'role': 'user', 'parts': [{'text': 'hello [[MARKER:gemini-stub]]'}]},
            ]
        }
    )
    payload = stub.stub_gemini_proxy_json(body)
    assert payload['candidates'][0]['content']['parts'][0]['text'] == 'Stub saw marker: gemini-stub'


def test_gemini_proxy_stub_honors_home_suggestion_response_schema():
    body = json.dumps(
        {
            'contents': [{'role': 'user', 'parts': [{'text': 'Write personalized questions'}]}],
            'generationConfig': {
                'responseMimeType': 'application/json',
                'responseSchema': {
                    'type': 'object',
                    'properties': {'questions': {'type': 'array', 'items': {'type': 'string'}}},
                    'required': ['questions'],
                },
            },
        }
    )

    payload = stub.stub_gemini_proxy_json(body)

    assert payload['candidates'][0]['content']['parts'][0]['text'] == '{"questions":[]}'
