from types import SimpleNamespace

import pytest

from utils.observability import langfuse_prompts


@pytest.mark.parametrize(
    'role,name', [('live', 'intentive-live-system'), ('supervisor', 'intentive-supervisor-system')]
)
def test_role_prompt_uses_owned_name_and_nonempty_bundled_fallback(monkeypatch, role, name):
    monkeypatch.setattr(langfuse_prompts, 'get_langfuse_client', lambda: None)
    fallback = langfuse_prompts.get_runtime_prompt(role)
    assert fallback.name == name
    assert fallback.text.strip()
    assert fallback.source == 'fallback'
    calls = []
    prompt = SimpleNamespace(version=7, is_fallback=False, compile=lambda: 'managed behavior')
    client = SimpleNamespace(get_prompt=lambda *args, **kwargs: (calls.append((args, kwargs)), prompt)[1])
    monkeypatch.setattr(langfuse_prompts, 'get_langfuse_client', lambda: client)
    resolved = langfuse_prompts.get_runtime_prompt(role)
    assert resolved.text == 'managed behavior'
    assert resolved.version == '7'
    assert calls[0][0] == (name,)
    assert resolved.receipt() == {'text': 'managed behavior', 'name': name, 'version': '7', 'source': 'langfuse'}


@pytest.mark.parametrize('text', ['', 'x' * 32001], ids=['empty', 'oversized'])
def test_unusable_live_prompt_uses_bundled_behavior_instead_of_breaking_mint(monkeypatch, text):
    prompt = SimpleNamespace(version=7, is_fallback=False, compile=lambda: text)
    monkeypatch.setattr(
        langfuse_prompts, 'get_langfuse_client', lambda: SimpleNamespace(get_prompt=lambda *_a, **_k: prompt)
    )
    result = langfuse_prompts.get_runtime_prompt('live')
    assert result.source == 'fallback'
    assert 0 < len(result.text) <= 32000


def test_remote_blank_prompt_is_valid_linked_and_uses_the_sdk_cache_contract(monkeypatch):
    calls = []
    prompt = SimpleNamespace(version=1, is_fallback=False, compile=lambda: '')

    class Client:
        def get_prompt(self, *args, **kwargs):
            calls.append((args, kwargs))
            return prompt

    monkeypatch.setattr(langfuse_prompts, 'get_langfuse_client', lambda: Client())

    resolved = langfuse_prompts.get_runtime_prompt()

    assert calls == [
        (
            ('intentive-chat-system',),
            {
                'label': 'production',
                'type': 'text',
                'cache_ttl_seconds': 300,
            },
        )
    ]
    assert resolved.text == ''
    assert resolved.name == 'intentive-chat-system'
    assert resolved.version == '1'
    assert resolved.source == 'langfuse'
    assert resolved.prompt_client is prompt


def test_missing_credentials_and_fetch_errors_use_the_intentionally_blank_fallback(monkeypatch):
    fallbacks = []
    monkeypatch.setattr(langfuse_prompts, 'record_fallback', lambda **kwargs: fallbacks.append(kwargs))
    monkeypatch.setattr(langfuse_prompts, 'get_langfuse_client', lambda: None)

    missing = langfuse_prompts.get_runtime_prompt()

    monkeypatch.setattr(
        langfuse_prompts,
        'get_langfuse_client',
        lambda: SimpleNamespace(get_prompt=lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError('private'))),
    )
    failed = langfuse_prompts.get_runtime_prompt()

    assert missing.text == failed.text == langfuse_prompts.FALLBACK_RUNTIME_PROMPT == ''
    assert missing.version == failed.version == 'fallback'
    assert missing.prompt_client is failed.prompt_client is None
    assert len(fallbacks) == 2


def test_prompt_name_and_ttl_are_configurable_with_safe_defaults(monkeypatch):
    monkeypatch.setenv('LANGFUSE_PROMPT_NAME', 'owned-chat-prompt')
    monkeypatch.setenv('LANGFUSE_PROMPT_CACHE_TTL_SECONDS', 'invalid')

    assert langfuse_prompts.get_prompt_name() == 'owned-chat-prompt'
    assert langfuse_prompts.get_prompt_cache_ttl_seconds() == 300

    monkeypatch.setenv('LANGFUSE_PROMPT_CACHE_TTL_SECONDS', '-1')
    assert langfuse_prompts.get_prompt_cache_ttl_seconds() == 300


def test_managed_prompt_precedes_the_existing_kernel_policy():
    remote = langfuse_prompts.ResolvedRuntimePrompt(
        text='managed procedure',
        name='intentive-chat-system',
        version='2',
        source='langfuse',
    )
    blank = langfuse_prompts.ResolvedRuntimePrompt(
        text='',
        name='intentive-chat-system',
        version='1',
        source='langfuse',
    )

    assert langfuse_prompts.compose_system_prompt(remote, 'kernel policy') == 'managed procedure\n\nkernel policy'
    assert langfuse_prompts.compose_system_prompt(blank, 'kernel policy') == 'kernel policy'
    assert 'Omi' not in langfuse_prompts.FALLBACK_RUNTIME_PROMPT


def test_local_qualification_can_select_a_nonproduction_prompt_label(monkeypatch):
    labels = []
    prompt = SimpleNamespace(version=2, is_fallback=False, compile=lambda: 'qualification behavior')
    client = SimpleNamespace(get_prompt=lambda *args, **kwargs: (labels.append(kwargs['label']), prompt)[1])
    monkeypatch.setattr(langfuse_prompts, 'get_langfuse_client', lambda: client)
    monkeypatch.setenv('LANGFUSE_PROMPT_LABEL', 'abc-local-qualification')
    for role in ['live', 'supervisor']:
        assert langfuse_prompts.get_runtime_prompt(role).version == '2'
    assert labels == ['abc-local-qualification', 'abc-local-qualification']
    monkeypatch.setenv('LANGFUSE_PROMPT_LABEL', '   ')
    langfuse_prompts.get_runtime_prompt('live')
    assert labels[-1] == 'production'
