---
type: Codebase guide
title: Memory lifecycle
description: Trace intake, normalization, revision/owner fencing, embedding and local retrieval with tests.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-62abf112d5ded48560527143
    resource: repo://backend/routers/memory_compute.py
  - id: openwiki-source-5fe974b198877ecf775fae46
    resource: repo://backend/tests/unit/test_memory_compute.py
  - id: openwiki-source-577b743ef6d29a4ab11ce6a1
    resource: repo://desktop/macos/Desktop/Sources/ProactiveAssistants/ProactiveAssistantsPlugin.swift
  - id: openwiki-source-e0e1aceea6bbd06a72738ece
    resource: repo://desktop/macos/Desktop/Sources/ProactiveAssistants/Supervisor/SupervisorService.swift
  - id: openwiki-source-83de7f0f3608399f3b050de3
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift
  - id: openwiki-source-67c279c1fb27efbebf9fa81a
    resource: repo://desktop/macos/Desktop/Tests/LocalMemoryLifecycleRunnerTests.swift
  - id: openwiki-source-c40e9e241b6526aaeb39d5dc
    resource: repo://desktop/macos/e2e/flows/proactive-memory-writers-retention.yaml
generated: { by: "codex", at: "2026-09-27T17:33:01.317Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-27T19:56:49.848Z
---
# Memory lifecycle

MemoryStorage is the local archive owner. Intake starts as local assertions and provenance, then `LocalMemoryLifecycleRunner` processes durable work. Backend extraction, normalization and consolidation return proposals; the local store decides whether the proposal still applies and commits it.

## Supervisor reads and retired screen writers

The [A–B–C supervisor](supervisor-conversation.md) reads up to twenty existing local Memories and the latest profile under captured owner authorization. Those reads are bounded and empty results are valid; they do not regenerate a profile or add semantic retrieval. B returns only private conversation guidance and has no product-write capability.

The five old screen workers no longer register or run, so they no longer create Memory, Tasks, Focus or Insights from screenshots. Their records remain readable, and the local Memory lifecycle, archive/search, manual operations and independent conversation enrichment continue through their existing owners. The retention flow checks this separation; changing the supervisor does not replace the lifecycle described below.

## Processing loop

The runner initializes the active database, captures its pool generation, recovers interrupted work, finalizes expired deletion windows and enqueues due lifecycle work. It processes normalization, extraction, embeddings and consolidation in bounded batches. Work leases carry input revision/generation and enough identity to validate a delayed result.

For normalization, the request contains a unique request ID, captured revision, bounded assertion and provenance tokens. The response must match the request/revision before `completeNormalization` receives the expected revision, owner generation and receipt identity. Authorization revocation is distinct from an ordinary provider failure; it must not authorize a write into the next account's database.

```mermaid
flowchart LR
  Intake[Local intake] --> Work[Durable leased work]
  Work --> Compute[Bounded proposal compute]
  Compute --> Fence[Validate request revision and owner]
  Fence --> Commit[Atomic local result and receipt]
  Commit --> Search[Local archive and semantic retrieval]
```

## Persistence and failure

Extraction validates grounded evidence before admitting candidates. Consolidation applies one coherent local decision. Embeddings are computed externally when required, but vectors and retrieval remain local. Failed or interrupted work is recovered through the existing durable lease/backoff mechanism rather than an unbounded background retry loop.

The lifecycle tests exercise stale normalization revisions, invalid extraction quotes, receipt replay, atomic consolidation, bounded retry, pool reopen, current-revision embedding and conflicting supersession. These tests establish local behavior; they do not prove a deployed provider's semantic quality.

Read [product constraints](../../INSTRUCTIONS.md#product-constraints) and the relevant IR decisions before changing layer visibility, expiry, Undo, provenance or retention. [Local data](../architecture/local-data.md) and [account export](account-lifecycle.md) describe the adjacent storage and owner boundaries.

## Source evidence

- [desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift#L82-L131)
- [desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/LocalMemoryLifecycleRunner.swift#L133-L174)
- [desktop/macos/Desktop/Tests/LocalMemoryLifecycleRunnerTests.swift](../../../desktop/macos/Desktop/Tests/LocalMemoryLifecycleRunnerTests.swift)
- [backend/routers/memory_compute.py](../../../backend/routers/memory_compute.py)
- [backend/tests/unit/test_memory_compute.py](../../../backend/tests/unit/test_memory_compute.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
