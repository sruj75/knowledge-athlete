---
type: Codebase guide
title: Chat, tools and voice
description: Trace Home Chat through kernel and Gemini plus the Gemini Live recovery path and local tools.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-22fbe8e419c78e59a910956c
    resource: repo://desktop/macos/agent/src/runtime/conversation-journal.ts
  - id: openwiki-source-62d945a031f8cfbb45021e15
    resource: repo://desktop/macos/agent/tests/conversation-journal.test.ts
  - id: openwiki-source-f1efbd1a25d10b5d7c7d4775
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/PTTBatchTranscriptionPolicy.swift
  - id: openwiki-source-a06ede6cec7facee4647ba62
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController%2BPushToTalk.swift
  - id: openwiki-source-d2fcc2b5c63a2a31e81a6ae9
    resource: repo://desktop/macos/Desktop/Sources/Providers/ChatProvider.swift
  - id: openwiki-source-60e99a5c14248df3a5999a25
    resource: repo://desktop/macos/Desktop/Sources/Providers/ChatToolExecutor.swift
  - id: openwiki-source-d28a6d232eca8d9c728ee6f3
    resource: repo://desktop/macos/Desktop/Tests/PTTBatchLanguagePolicyTests.swift
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
---
# Chat, tools and voice

Home presents ordinary Chat while the Node runtime owns accepted turns and catalog metadata. Swift keeps provisional UI state and drafts, then projects accepted journal results. The [kernel and Pi architecture](../architecture/desktop-agent.md) explains the local process boundary and managed model loop.

## Typed Chat and tools

A user turn reaches `ChatProvider`, the runtime process and the kernel. Pi requests inference through the authenticated Gemini gateway. Tool invocations return through the private relay to `ChatToolExecutor`, which performs retained local effects under the captured owner authority. Tool results preserve their invocation/run identity so a delayed completion cannot be attached to an unrelated turn.

SQL and semantic search use local data. Task and goal writes have typed local tools; raw SQL is not permission to bypass those owners. Catalog and journal generation counters invalidate stale fetches and mutations when the owner changes. UI text that arrived before durable acceptance must not be presented as terminal journal success.

## PTT and realtime recovery

Realtime voice uses Gemini Live. The controller associates reconnect and retained PCM buffers with a turn and admitted session context. It drops buffers for superseded turns and preserves a context-fresh reconnect buffer through PTT release. If Live cannot finish, completed-turn recovery uses the existing silence/language policy, batch transcription, Gemini Chat and retained spoken output.

`PTTBatchTranscriptionPolicy` uses voice languages and the turn/context vocabulary, not ambient meeting-language preferences. It checks authorization before and after the provider call. An empty single-language result can retry once with `multi`; the shared fallback callback records whether that retry recovered or exhausted.

## Verification

Owner authority tests prove runtime handshake/revocation. Journal tests prove accepted-turn persistence. PTT language-policy tests exercise the retry and authorization seam; realtime continuity and persistence-fence suites cover their owning state machines. These are complementary to natural physical-PTT/provider evidence in [qualification](../operations/qualification.md).

When changing voice or Chat, identify the authority for input, turn identity, tool effects, accepted journal output and playback separately. A successful model response alone does not prove all those transitions completed.

## Source evidence

- [desktop/macos/Desktop/Sources/Providers/ChatProvider.swift](../../../desktop/macos/Desktop/Sources/Providers/ChatProvider.swift#L914-L946)
- [desktop/macos/agent/src/runtime/conversation-journal.ts](../../../desktop/macos/agent/src/runtime/conversation-journal.ts)
- [desktop/macos/agent/tests/conversation-journal.test.ts](../../../desktop/macos/agent/tests/conversation-journal.test.ts)
- [desktop/macos/Desktop/Sources/FloatingControlBar/PTTBatchTranscriptionPolicy.swift](../../../desktop/macos/Desktop/Sources/FloatingControlBar/PTTBatchTranscriptionPolicy.swift)
- [desktop/macos/Desktop/Tests/PTTBatchLanguagePolicyTests.swift](../../../desktop/macos/Desktop/Tests/PTTBatchLanguagePolicyTests.swift)
- [desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController+PushToTalk.swift](../../../desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController+PushToTalk.swift)
- [desktop/macos/Desktop/Sources/Providers/ChatToolExecutor.swift](../../../desktop/macos/Desktop/Sources/Providers/ChatToolExecutor.swift#L820-L838)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
