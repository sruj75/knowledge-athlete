---
type: Codebase guide
title: Managed model providers
description: Map LLM package responsibilities, Gemini workloads, Modulate, TTS and server-held keys.
tags: [intentive, codebase]
resource: repo://backend/utils/llm
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-8c3da56dbbaf9fe6eb52b9bd
    resource: repo://backend/config/stt_provider_policy.py
  - id: openwiki-source-4506f9d22a7ec8a8f8d47ba3
    resource: repo://backend/routers/desktop_proxy.py
  - id: openwiki-source-246adce1bd09822e870e6154
    resource: repo://backend/routers/desktop_realtime.py
  - id: openwiki-source-f9557f9df695b6659e2ddd5c
    resource: repo://backend/routers/desktop_tts_updates.py
  - id: openwiki-source-6439c0b00e9284c12c7afccb
    resource: repo://backend/utils/llm/model_config.py
  - id: openwiki-source-03e90258dd4af40e9e153037
    resource: repo://backend/utils/llm/providers.py
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
---
# Managed model providers

The LLM package has an explicit workload inventory. Each workload records its provider, model, caller, input/output contract, result owner, usage feature and failure policy. `clients.py` resolves those workloads; `providers.py` constructs and caches native Gemini clients using the backend-held key. Product features should request a workload, not invent a global model fallback.

## Current provider roles

| Work | Implemented route/provider |
| --- | --- |
| Normal Pi Chat and desktop background text | Managed Gemini 3.7 Flash |
| Conversation candidates, Memory proposals and fair-use classification | Explicit Gemini workloads with local result owners or bounded enforcement results |
| Session title and transcript translation workloads | Gemini 2.5 Flash-Lite entries in the workload inventory |
| Desktop embeddings | Allowlisted `gemini-embedding-001` proxy |
| Realtime voice | `models/gemini-3.1-flash-live-preview` credential route |
| Cloud speech recognition | Modulate `modulate-velma-2` |
| Spoken output | OpenAI `gpt-4o-mini-tts` |

The desktop proxy also recognizes shipped older text-model names and maps them to the available 3.7 model. This existing wire behavior is distinct from the explicit server workload inventory; changing one does not prove every other model caller migrated.

## Request and failure boundaries

The Node adapter sends Firebase identity to the managed backend and scrubs direct provider keys from its environment. Backend Gemini construction reads the server key, attaches usage/error callbacks, and caches by model, streaming, thinking configuration and feature. Unknown managed providers fail explicitly.

Compute failure policy belongs to the workload and caller: discard can preserve a conversation on failure; other candidate operations can fail independently. Realtime has its own bounded PCM recovery path described in [Chat and voice](../workflows/chat-voice.md). Do not generalize that recovery into a cross-provider text switch.

The package's parsing, conversation processing, Memory computation, temporal handling, transport and accounting helpers support these explicit contracts. [Backend guidance](../../INSTRUCTIONS.md#backend-guidance) owns logging and executor rules. Credentials and live qualification are outside this wiki's evidence; the [open commitments](../../INSTRUCTIONS.md#unresolved-commitments) remain authoritative.

## Source evidence

- [backend/utils/llm/model_config.py](../../../backend/utils/llm/model_config.py)
- [backend/utils/llm/providers.py](../../../backend/utils/llm/providers.py)
- [backend/routers/desktop_proxy.py](../../../backend/routers/desktop_proxy.py#L20-L45)
- [backend/routers/desktop_realtime.py](../../../backend/routers/desktop_realtime.py#L20-L30)
- [backend/config/stt_provider_policy.py](../../../backend/config/stt_provider_policy.py#L12-L22)
- [backend/routers/desktop_tts_updates.py](../../../backend/routers/desktop_tts_updates.py#L18-L30)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
