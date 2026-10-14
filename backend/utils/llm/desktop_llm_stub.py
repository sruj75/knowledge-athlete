"""Deterministic conversational and retained desktop-proxy fixtures."""

from __future__ import annotations

import json
import os
import re
from collections.abc import Mapping

DEFAULT_ASSISTANT_TEXT = 'Hermetic LLM stub response.'
_MARKER_RE = re.compile(r'\[\[MARKER:([^\]]+)\]\]')


def llm_stub_flag_is_truthy(value: str) -> bool:
    return value.strip().lower() in {'1', 'true', 'yes', 'on'}


def llm_stub_enabled(environ: Mapping[str, str] | None = None) -> bool:
    env = os.environ if environ is None else environ
    return llm_stub_flag_is_truthy(env.get('OMI_LLM_STUB', ''))


def exact_reply_token(user_text: str) -> str | None:
    lowercase = user_text.lower()
    marker = 'reply with exactly'
    start = lowercase.find(marker)
    if start < 0:
        return None
    suffix = user_text[start + len(marker) :].lstrip(': \t')
    token = suffix.split(None, 1)[0] if suffix.strip() else ''
    while token and not (token[0].isalnum() or token[0] == '_'):
        token = token[1:]
    while token and not (token[-1].isalnum() or token[-1] == '_'):
        token = token[:-1]
    return token or None


def extract_markers(text: str) -> list[str]:
    markers: list[str] = []
    for match in _MARKER_RE.finditer(text):
        marker = match.group(1)
        if marker not in markers:
            markers.append(marker)
    return markers


def stub_assistant_text(body: str) -> str:
    markers = extract_markers(body)
    if not markers:
        return DEFAULT_ASSISTANT_TEXT
    return ' '.join(f'Stub saw marker: {marker}' for marker in markers)


def extract_latest_gemini_user_text(body_text: str) -> str:
    try:
        value = json.loads(body_text)
    except ValueError:
        return ''
    contents = value.get('contents') if isinstance(value, Mapping) else None
    if not isinstance(contents, list):
        return ''
    for content in reversed(contents):
        if not isinstance(content, Mapping) or content.get('role') == 'model':
            continue
        parts = content.get('parts')
        if not isinstance(parts, list):
            continue
        texts = [part['text'] for part in parts if isinstance(part, Mapping) and isinstance(part.get('text'), str)]
        if texts:
            return '\n'.join(texts)
    return ''


def gemini_json_payload(text: str) -> dict[str, object]:
    return {
        'candidates': [
            {
                'content': {'parts': [{'text': text}], 'role': 'model'},
                'finishReason': 'STOP',
            }
        ]
    }


def stub_gemini_proxy_json(body_text: str) -> dict[str, object]:
    try:
        body = json.loads(body_text)
    except ValueError:
        body = {}
    if isinstance(body, Mapping):
        generation_config = body.get('generationConfig') or body.get('generation_config')
        if isinstance(generation_config, Mapping):
            response_schema = generation_config.get('responseSchema') or generation_config.get('response_schema')
            properties = response_schema.get('properties') if isinstance(response_schema, Mapping) else None
            if isinstance(properties, Mapping) and 'questions' in properties:
                return gemini_json_payload(json.dumps({'questions': []}, separators=(',', ':')))
    return gemini_json_payload(stub_assistant_text(extract_latest_gemini_user_text(body_text)))
