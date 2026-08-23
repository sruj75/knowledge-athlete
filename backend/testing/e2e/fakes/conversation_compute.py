"""Deterministic conversation-compute boundaries for the offline dev harness.

The production routes remain assembled and authenticated. Only their external
LLM collaborators are replaced, so named-bundle tests still exercise request
validation, response shaping, and the Mac's durable finalization pipeline.
"""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any


def fake_should_discard_conversation(*_args: Any, **_kwargs: Any) -> bool:
    return False


def fake_get_transcript_structure(*_args: Any, **_kwargs: Any) -> SimpleNamespace:
    return SimpleNamespace(
        title='Hermetic Local Conversation',
        overview='A deterministic local-harness conversation.',
        emoji='🧪',
        category='other',
        events=[],
    )


def fake_extract_action_items(*_args: Any, **_kwargs: Any) -> list[Any]:
    return []


def install_offline_conversation_compute_fakes() -> None:
    """Replace only provider-backed conversation helpers in offline processes."""

    from utils.llm import conversation_processing

    conversation_processing.should_discard_conversation = fake_should_discard_conversation
    conversation_processing.get_transcript_structure = fake_get_transcript_structure
    conversation_processing.extract_action_items = fake_extract_action_items
