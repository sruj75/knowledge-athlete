"""Legacy gateway payload helper owned by the callerless S-25 handoff."""

from __future__ import annotations

from copy import deepcopy
from typing import Any, cast

from pydantic import BaseModel

JsonDict = dict[str, Any]
JsonList = list[Any]


def build_structured_gateway_payload(prompt: str, output_model: type[BaseModel], *, feature: str) -> JsonDict:
    return {
        'model': 'omi:auto:chat-structured',
        'messages': [{'role': 'user', 'content': prompt}],
        'response_format': {
            'type': 'json_schema',
            'json_schema': {
                'name': output_model.__name__,
                'strict': True,
                'schema': _strict_model_json_schema(output_model),
            },
        },
        'metadata': {
            'omi_feature': feature,
            'prompt_version': f'{feature}.v1',
            'parser_version': f'{output_model.__name__}.v1',
        },
    }


def _strict_model_json_schema(output_model: type[BaseModel]) -> JsonDict:
    schema = output_model.model_json_schema()
    _normalize_strict_schema(schema)
    _inline_ref_siblings(schema)
    return schema


def _as_json_dict(value: object) -> JsonDict | None:
    return cast(JsonDict, value) if isinstance(value, dict) else None


def _as_json_list(value: object) -> JsonList | None:
    return cast(JsonList, value) if isinstance(value, list) else None


def _normalize_strict_schema(schema: JsonDict) -> None:
    schema.pop('default', None)
    if schema.get('type') == 'object':
        schema['additionalProperties'] = False
    properties = _as_json_dict(schema.get('properties'))
    if properties is not None:
        schema['required'] = list(properties.keys())
        for prop_schema in properties.values():
            prop_schema_dict = _as_json_dict(prop_schema)
            if prop_schema_dict is not None:
                _normalize_strict_schema(prop_schema_dict)
    for key in ('$defs', 'definitions'):
        definitions = _as_json_dict(schema.get(key))
        if definitions is not None:
            for definition in definitions.values():
                definition_dict = _as_json_dict(definition)
                if definition_dict is not None:
                    _normalize_strict_schema(definition_dict)
    items = _as_json_dict(schema.get('items'))
    if items is not None:
        _normalize_strict_schema(items)
    for key in ('anyOf', 'oneOf', 'allOf'):
        alternatives = _as_json_list(schema.get(key))
        if alternatives is not None:
            for alternative in alternatives:
                alternative_dict = _as_json_dict(alternative)
                if alternative_dict is not None:
                    _normalize_strict_schema(alternative_dict)


def _inline_ref_siblings(schema: JsonDict) -> None:
    definitions = _as_json_dict(schema.get('$defs')) or _as_json_dict(schema.get('definitions')) or {}

    def resolve_ref(ref: str) -> JsonDict | None:
        prefix = '#/$defs/'
        if not ref.startswith(prefix):
            return None
        target = _as_json_dict(definitions.get(ref.removeprefix(prefix)))
        return deepcopy(target) if target is not None else None

    def walk(node: object) -> None:
        node_dict = _as_json_dict(node)
        if node_dict is not None:
            ref = node_dict.get('$ref')
            if isinstance(ref, str) and len(node_dict) > 1:
                resolved = resolve_ref(ref)
                if resolved is not None:
                    siblings = {key: value for key, value in node_dict.items() if key != '$ref'}
                    node_dict.clear()
                    node_dict.update(resolved)
                    node_dict.update(siblings)
            for value in list(node_dict.values()):
                walk(value)
            return
        node_list = _as_json_list(node)
        if node_list is not None:
            for value in node_list:
                walk(value)

    walk(schema)
