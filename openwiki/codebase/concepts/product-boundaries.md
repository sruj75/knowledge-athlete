---
type: Codebase guide
title: Product authority and constraints
description: Explain implemented local product ownership and link normative guidance without treating policy as code evidence.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-477ee7f176f7957c006c22b7
    resource: repo://backend/routers/desktop_conversation.py
  - id: openwiki-source-246adce1bd09822e870e6154
    resource: repo://backend/routers/desktop_realtime.py
  - id: openwiki-source-62abf112d5ded48560527143
    resource: repo://backend/routers/memory_compute.py
  - id: openwiki-source-45a66916bd16b1697eca50f8
    resource: repo://backend/utils/billing/config.py
  - id: openwiki-source-b923075d856f4498032624f2
    resource: repo://backend/utils/observability/conversation_prompts.py
  - id: openwiki-source-948937d6dce1b6ceff01afbb
    resource: repo://backend/utils/other/endpoints.py
  - id: openwiki-source-d02a185b5b5f1d238504f680
    resource: repo://desktop/macos/agent/src/conversation-protocol.ts
  - id: openwiki-source-f16497173de6b612a819df04
    resource: repo://desktop/macos/Desktop/Sources/Account/Export/LocalUserDataExport.swift
  - id: openwiki-source-fd817795de0b62f9f7f585da
    resource: repo://desktop/macos/Desktop/Sources/MainWindow/DesktopNavigation.swift
  - id: openwiki-source-83de7f0f3608399f3b050de3
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift
generated: { by: "codex", at: "2026-10-14T14:40:28.560Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-10-14T14:40:28.560Z
---
# Product authority and constraints

The authored [product constraints](../../INSTRUCTIONS.md#product-constraints) define Intentive's direction. This page explains how the implementation expresses those boundaries; it does not infer product policy from code or claim that an archived decision is mechanically verified.

## Local product, managed compute

The Mac owns its conversation archive and Memory lifecycle. Backend conversation operations return generation-bound candidates; Memory operations return bounded extraction, normalization and consolidation proposals. The receiving local owner validates and commits accepted results. Typed and spoken A use the same Node catalog and journal, with Swift owning presentation, drafts, lifecycle and controlled audio.

This division lets local archive operations retain a clear owner even when a provider fails. A successful HTTP response is not a durable Memory commit. A live transcription socket is not a hosted conversation archive. A model response is not authority to mutate unrelated product records or change accounts.

## Identity and admission

Firebase identity remains a hosted boundary. Product compute uses participant admission, while the backend also exposes authenticated account lifecycle operations. Billing availability is a separate typed configuration with disabled mode as its default. Do not treat “billing disabled” as “authentication disabled,” or infer that every authenticated identity is a configured hosted participant.

The storage process requires a fixed startup owner and rejects requests for another owner. The Mac's database generation and local authorization snapshots protect delayed reads and commits. These mechanisms support the same account boundary at different effect owners.

## Instructions and executable authority

A's immutable instruction receipt is resolved at logical conversation creation and reused for Live, direct typed replies, reconnects and fallback. Langfuse supplies versioned instructions, while code enforces permissions, bounds, scheduling, persistence and the single fixed `end_conversation` signal. B's reasoning can request a cue or intervention; it cannot grant itself capture permission or execute general tools.

Home and Memory are active navigation. Tasks, simple goals, Insights and Focus have no active producers, reminders or coaching inputs. Their historical tables, decoding and owner-authorized exports remain, as do existing tips-tagged Memories and generic Memory lifecycle work. Retiring a feature is not authorization to delete its history.

## How to change behavior

Read the relevant final IR decisions and current product constraints in the brief, then follow the owning source and test. Update both behavioral tests and authored guidance when an authorized product decision changes. [Memory](../workflows/memory.md), [Chat and voice](../workflows/chat-voice.md), and [account lifecycle](../workflows/account-lifecycle.md) provide concrete traces. Open release and provider obligations remain open until their own evidence exists.

## Source evidence

- [backend/utils/other/endpoints.py](../../../backend/utils/other/endpoints.py#L132-L175)
- [backend/routers/memory_compute.py](../../../backend/routers/memory_compute.py)
- [desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift#L86-L119)
- [backend/utils/billing/config.py](../../../backend/utils/billing/config.py)
- [Storage owner](../../../desktop/macos/agent/src/conversation-protocol.ts)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
