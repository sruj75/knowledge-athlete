"""Only selected client conversation examples may contain evaluation text."""

from collections.abc import Mapping
from typing import cast

from models.desktop_ai import ChatTerminalObservation, SupervisorDecisionObservation, TerminalTurnObservation


def chat_input_shape(payload: Mapping[str, object]) -> dict[str, object]:
    contents = payload.get('contents', payload.get('messages'))
    return {
        'content_count': len(cast(list[object], contents)) if isinstance(contents, list) else 0,
        'has_tools': bool(payload.get('tools')),
    }


def chat_output_shape(output: object) -> dict[str, int]:
    if not isinstance(output, Mapping):
        return {'text_chars': 0, 'tool_call_count': 0}
    values = cast(Mapping[str, object], output)
    text = values.get('text')
    tools = values.get('tool_calls')
    return {
        'text_chars': len(text) if isinstance(text, str) else 0,
        'tool_call_count': len(cast(list[object], tools)) if isinstance(tools, list) else 0,
    }


def reviewed_example(
    event: TerminalTurnObservation | ChatTerminalObservation | SupervisorDecisionObservation,
) -> dict[str, object]:
    if not event.evaluation_sharing:
        return {}
    result: dict[str, object] = {'conversation': [item.model_dump(exclude_none=True) for item in event.conversation]}
    if isinstance(event, SupervisorDecisionObservation):
        result['transcripts'] = [item.model_dump() for item in event.transcripts]
        result['guidance'] = event.note
    return result
