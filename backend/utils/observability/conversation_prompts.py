"""Resolve A's owned instruction once and identify it across conversation routes."""

from collections import OrderedDict
from hashlib import sha256
from threading import Lock

from models.desktop_conversation import ConversationPromptReceipt, ConversationPromptReference
from utils.observability.langfuse import get_langfuse_client
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt, get_runtime_prompt
from utils.llm.desktop_llm_stub import llm_stub_enabled

CONVERSATION_FALLBACK_VERSION = 'conversation-v1'
CONVERSATION_FALLBACK_TEXT = (
    "You are Intentive, a conversational companion. Respond to the user's current message "
    'using the supplied context. You can converse but cannot execute actions.'
)
_MAX_CACHED_PROMPTS = 128
_cache: OrderedDict[tuple[str, str, str], ResolvedRuntimePrompt] = OrderedDict()
_cache_lock = Lock()


class ConversationPromptMismatchError(ValueError):
    pass


class ConversationPromptUnavailableError(RuntimeError):
    pass


def _receipt(prompt: ResolvedRuntimePrompt) -> ConversationPromptReceipt:
    return ConversationPromptReceipt(
        name='intentive-live-system',
        version=prompt.version,
        source='langfuse' if prompt.source == 'langfuse' else 'fallback',
        sha256=sha256(prompt.text.encode('utf-8')).hexdigest(),
        text=prompt.text,
    )


def _remember(prompt: ResolvedRuntimePrompt) -> ConversationPromptReceipt:
    receipt = _receipt(prompt)
    key = (receipt.source, receipt.version, receipt.sha256)
    with _cache_lock:
        _cache[key] = prompt
        _cache.move_to_end(key)
        while len(_cache) > _MAX_CACHED_PROMPTS:
            _cache.popitem(last=False)
    return receipt


def _fallback() -> ResolvedRuntimePrompt:
    return ResolvedRuntimePrompt(
        text=CONVERSATION_FALLBACK_TEXT,
        name='intentive-live-system',
        version=CONVERSATION_FALLBACK_VERSION,
        source='fallback',
    )


def bootstrap_conversation_prompt() -> ConversationPromptReceipt:
    if llm_stub_enabled():
        return _remember(_fallback())
    prompt = get_runtime_prompt('live')
    return _remember(prompt if prompt.source == 'langfuse' else _fallback())


def resolve_conversation_prompt(reference: ConversationPromptReference) -> ResolvedRuntimePrompt:
    """Resolve an exact policy receipt; never advance an active conversation's label."""
    key = (reference.source, reference.version, reference.sha256)
    with _cache_lock:
        cached = _cache.get(key)
        if cached is not None:
            _cache.move_to_end(key)
            return cached
    if reference.source == 'fallback':
        resolved = _fallback()
    else:
        try:
            client = get_langfuse_client()
            if client is None:
                raise ConversationPromptUnavailableError('Pinned instructions are unavailable')
            prompt = client.get_prompt(
                reference.name, version=int(reference.version), type='text', cache_ttl_seconds=300
            )
            compiled = prompt.compile()
            if (
                not isinstance(compiled, str)
                or not compiled.strip()
                or len(compiled) > 32000
                or bool(getattr(prompt, 'is_fallback', False))
                or str(getattr(prompt, 'version', '')) != reference.version
            ):
                raise ConversationPromptUnavailableError('Pinned instructions are unavailable')
            resolved = ResolvedRuntimePrompt(
                text=compiled, name=reference.name, version=reference.version, source='langfuse', prompt_client=prompt
            )
        except Exception as error:
            raise ConversationPromptUnavailableError('Pinned instructions are unavailable') from error
    if _receipt(resolved).sha256 != reference.sha256:
        raise ConversationPromptMismatchError('Pinned instruction reference does not match')
    _remember(resolved)
    return resolved


def conversation_prompt_receipt(prompt: ResolvedRuntimePrompt) -> ConversationPromptReceipt:
    return _receipt(prompt)
