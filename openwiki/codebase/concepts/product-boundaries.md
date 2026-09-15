---
type: Codebase guide
title: Product authority and constraints
description: Explain implemented local product ownership and link normative guidance without treating policy as code evidence.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-62abf112d5ded48560527143
    resource: repo://backend/routers/memory_compute.py
  - id: openwiki-source-45a66916bd16b1697eca50f8
    resource: repo://backend/utils/billing/config.py
  - id: openwiki-source-948937d6dce1b6ceff01afbb
    resource: repo://backend/utils/other/endpoints.py
  - id: openwiki-source-1abc263ea013010fb0b5800b
    resource: repo://desktop/macos/agent/src/runtime/runtime-owner-authority.ts
  - id: openwiki-source-83de7f0f3608399f3b050de3
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
---
# Product authority and constraints

The authored [product constraints](../../INSTRUCTIONS.md#product-constraints) define Intentive's direction. This page explains how the implementation expresses those boundaries; it does not infer product policy from code or claim that an archived decision is mechanically verified.

## Local product, managed compute

The Mac owns its conversation archive and Memory lifecycle. Backend conversation operations return generation-bound candidates; Memory operations return bounded extraction, normalization and consolidation proposals. The receiving local owner validates and commits accepted results. Ordinary Chat instead uses the Node catalog and journal, with Swift providing Home presentation, drafts and tool effects.

This division lets local archive operations retain a clear owner even when a provider fails. A successful HTTP response is not a durable Memory commit. A live transcription socket is not a hosted conversation archive. An agent response is not authority to perform a tool effect for a different account.

## Identity and admission

Firebase identity remains a hosted boundary. Product compute uses participant admission, while the backend also exposes authenticated account lifecycle operations. Billing availability is a separate typed configuration with disabled mode as its default. Do not treat “billing disabled” as “authentication disabled,” or infer that every authenticated identity is a configured hosted participant.

The runtime separately requires an owner handshake and prevents same-process owner replacement. The Mac's database generation and local authorization snapshots protect delayed reads and commits. These mechanisms support the same account boundary at different effect owners.

## How to change behavior

Read the relevant final IR decisions and current product constraints in the brief, then follow the owning source and test. Update both behavioral tests and authored guidance when an authorized product decision changes. [Memory](../workflows/memory.md), [Chat and voice](../workflows/chat-voice.md), and [account lifecycle](../workflows/account-lifecycle.md) provide concrete traces. Open release and provider obligations remain open until their own evidence exists.

## Source evidence

- [backend/utils/other/endpoints.py](../../../backend/utils/other/endpoints.py#L132-L175)
- [backend/routers/memory_compute.py](../../../backend/routers/memory_compute.py)
- [desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift#L86-L119)
- [backend/utils/billing/config.py](../../../backend/utils/billing/config.py)
- [desktop/macos/agent/src/runtime/runtime-owner-authority.ts](../../../desktop/macos/agent/src/runtime/runtime-owner-authority.ts)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
