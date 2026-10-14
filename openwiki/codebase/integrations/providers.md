---
type: Codebase guide
title: Managed model providers
description: Map LLM package responsibilities, Gemini workloads, Modulate, TTS and server-held keys.
tags: [intentive, codebase]
resource: repo://backend/utils/llm
sources:
  - id: openwiki-source-8c3da56dbbaf9fe6eb52b9bd
    resource: repo://backend/config/stt_provider_policy.py
  - id: openwiki-source-477ee7f176f7957c006c22b7
    resource: repo://backend/routers/desktop_conversation.py
  - id: openwiki-source-4506f9d22a7ec8a8f8d47ba3
    resource: repo://backend/routers/desktop_proxy.py
  - id: openwiki-source-246adce1bd09822e870e6154
    resource: repo://backend/routers/desktop_realtime.py
  - id: openwiki-source-436c23d0e71e7e8c078ad9ef
    resource: repo://backend/routers/desktop_supervisor.py
  - id: openwiki-source-f9557f9df695b6659e2ddd5c
    resource: repo://backend/routers/desktop_tts_updates.py
  - id: openwiki-source-aeeaf88f155573378474eb0c
    resource: repo://backend/utils/llm/gemini_usage.py
  - id: openwiki-source-6439c0b00e9284c12c7afccb
    resource: repo://backend/utils/llm/model_config.py
  - id: openwiki-source-03e90258dd4af40e9e153037
    resource: repo://backend/utils/llm/providers.py
  - id: openwiki-source-b923075d856f4498032624f2
    resource: repo://backend/utils/observability/conversation_prompts.py
  - id: openwiki-source-63500ad8455656e0ed04a9b7
    resource: repo://backend/utils/observability/langfuse_prompts.py
  - id: openwiki-source-9eb663951a8b4854a33ecbc8
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/ConversationPromptBindingStore.swift
generated: { by: "codex", at: "2026-10-14T14:40:28.560Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-10-14T14:40:28.560Z
---
# Managed model providers

The LLM package has an explicit workload inventory. Each workload records its provider, model, caller, input/output contract, result owner, usage feature and failure policy. `clients.py` resolves those workloads; `providers.py` constructs and caches native Gemini clients using the backend-held key. Product features should request a workload, not invent a global model fallback.

## Current provider roles

| Work | Implemented route/provider |
| --- | --- |
| Direct conversational A and Supervisor B | Managed Gemini 3.8 Flash with low thinking |
| Retained background text, structure and Memory | Existing Gemini 3.7 Flash workloads |
| Conversation candidates, Memory proposals and fair-use classification | Explicit Gemini workloads with local result owners or bounded enforcement results |
| Session title and transcript translation workloads | Gemini 2.5 Flash-Lite entries in the workload inventory |
| Desktop embeddings | Allowlisted `gemini-embedding-001` proxy |
| Realtime voice | `models/gemini-3.1-flash-live-preview` credential route |
| Cloud speech recognition | Modulate `modulate-velma-2` |
| Spoken output | OpenAI `gpt-4o-mini-tts` |

The desktop proxy also recognizes shipped older text-model names and maps them to the available 3.7 model. This existing wire behavior is distinct from the explicit server workload inventory; changing one does not prove every other model caller migrated.

## Managed conversational instructions

The resolver has two roles: `intentive-live-system` for every A route and `intentive-supervisor-system` for B. `LANGFUSE_PROMPT_LABEL` defaults to `production`; the label resolver's SDK cache defaults to 300 seconds through `LANGFUSE_PROMPT_CACHE_TTL_SECONDS`.

`POST /v1/conversation/session` returns A's instruction text, name, exact version, source and SHA-256 before Live connection. Swift pins it to the logical conversation. Direct replies, Live minting, reconnects and sticky batch fallback reuse that reference. The backend cache keys by source/version/hash; a cache miss fetches the exact Langfuse version and validates its hash, never rereading the mutable label. A mismatched reference fails with 409; unavailable pinned instructions fail with 503.

At creation only, unavailable Langfuse selects the tool-free repository `conversation-v1` instruction. B resolves its prompt per evaluation and returns `wait` without inference when managed instructions are unavailable. These are different failure contracts. The retired tool-bearing Chat instruction is not A's fallback.

Code constructs provider payloads, permits only A's fixed `end_conversation` signal, and gives B no tools. [Supervisor guidance](../workflows/supervisor-conversation.md) cannot change permissions or system policy. Returned model versions and disjoint uncached/cached input, output and thinking token counts support measurement; requested model names are not evidence of actual returned versions.

## Request and failure boundaries

Swift sends owner-bound Firebase identity to the managed backend. Node serves local storage and receives no model credential. Backend Gemini construction reads the server key, attaches usage/error callbacks, and caches by model, streaming, thinking configuration and feature. Unknown managed providers fail explicitly.

Compute failure policy belongs to the workload and caller: discard can preserve a conversation on failure; other candidate operations can fail independently. Realtime has its own bounded PCM recovery path described in [Chat and voice](../workflows/chat-voice.md). Do not generalize that recovery into a cross-provider text switch.

The package's parsing, conversation processing, Memory computation, temporal handling, transport and accounting helpers support these explicit contracts. [Backend guidance](../../INSTRUCTIONS.md#backend-guidance) owns logging and executor rules. Credentials and live qualification are outside this wiki's evidence; the [open commitments](../../INSTRUCTIONS.md#unresolved-commitments) remain authoritative.

## Source evidence

- [Exact instruction resolution](../../../backend/utils/observability/conversation_prompts.py)
- [Exclusive token accounting](../../../backend/utils/llm/gemini_usage.py)
- [backend/utils/llm/model_config.py](../../../backend/utils/llm/model_config.py)
- [backend/utils/llm/providers.py](../../../backend/utils/llm/providers.py)
- [backend/routers/desktop_proxy.py](../../../backend/routers/desktop_proxy.py#L20-L45)
- [backend/routers/desktop_realtime.py](../../../backend/routers/desktop_realtime.py#L20-L30)
- [backend/config/stt_provider_policy.py](../../../backend/config/stt_provider_policy.py#L12-L22)
- [backend/routers/desktop_tts_updates.py](../../../backend/routers/desktop_tts_updates.py#L18-L30)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
