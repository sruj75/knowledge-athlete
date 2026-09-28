---
type: Codebase guide
title: Chat, tools and voice
description: Trace Home Chat through kernel and Gemini plus the Gemini Live recovery path and local tools.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-22fbe8e419c78e59a910956c
    resource: repo://desktop/macos/agent/src/runtime/conversation-journal.ts
  - id: openwiki-source-62d945a031f8cfbb45021e15
    resource: repo://desktop/macos/agent/tests/conversation-journal.test.ts
  - id: openwiki-source-e762e0de342d9685ba91244f
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/AIEvaluationFeedbackView.swift
  - id: openwiki-source-b84455af73b70bd37a1e4cd0
    resource: repo://desktop/macos/Desktop/Sources/Chat/ChatMessage.swift
  - id: openwiki-source-8cccfc7e26d01ce730e0f49e
    resource: repo://desktop/macos/Desktop/Sources/Chat/KernelTurnJournal.swift
  - id: openwiki-source-f1efbd1a25d10b5d7c7d4775
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/PTTBatchTranscriptionPolicy.swift
  - id: openwiki-source-a06ede6cec7facee4647ba62
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController%2BPushToTalk.swift
  - id: openwiki-source-9fa7197ddcfd64cf31d5f460
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController%2BSessionDelegate.swift
  - id: openwiki-source-d3a88be39f01bdd4a0057cdf
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController%2BSessionLifecycle.swift
  - id: openwiki-source-d961728264020390f7b3849f
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController%2BSupervisor.swift
  - id: openwiki-source-e29c22c18eb45e7f7d2f3fc8
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController%2BTurnPersistence.swift
  - id: openwiki-source-6cab9acfa3869452a0792b9a
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubSession.swift
  - id: openwiki-source-5235c3e4e03b2e78ba2bd0e0
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubSessionTypes.swift
  - id: openwiki-source-4b674425e211b49d3fcdd759
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeTurnPersistence.swift
  - id: openwiki-source-c4851e5ad253e57eeaa6684e
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/VoiceTurnCoordinator.swift
  - id: openwiki-source-21802c0cbbe5aeada371f269
    resource: repo://desktop/macos/Desktop/Sources/MainWindow/Components/ChatMessageMetadataRow.swift
  - id: openwiki-source-e0e1aceea6bbd06a72738ece
    resource: repo://desktop/macos/Desktop/Sources/ProactiveAssistants/Supervisor/SupervisorService.swift
  - id: openwiki-source-d2fcc2b5c63a2a31e81a6ae9
    resource: repo://desktop/macos/Desktop/Sources/Providers/ChatProvider.swift
  - id: openwiki-source-60e99a5c14248df3a5999a25
    resource: repo://desktop/macos/Desktop/Sources/Providers/ChatToolExecutor.swift
  - id: openwiki-source-6e7c96ad2c3b57bb1ecbf498
    resource: repo://desktop/macos/Desktop/Sources/VoiceTurnDomain/VoiceTurnStateMachine.swift
  - id: openwiki-source-d28a6d232eca8d9c728ee6f3
    resource: repo://desktop/macos/Desktop/Tests/PTTBatchLanguagePolicyTests.swift
  - id: openwiki-source-0adbb8127cc707067b3adf30
    resource: repo://desktop/macos/Desktop/Tests/RealtimeHubSessionInputLifecycleTests.swift
generated: { by: "codex", at: "2026-09-28T09:46:29.604Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-28T09:46:29.604Z
---
# Chat, tools and voice

Home presents ordinary Chat while the Node runtime owns accepted turns and catalog metadata. Swift keeps provisional UI state and drafts, then projects accepted journal results. The [kernel and Pi architecture](../architecture/desktop-agent.md) explains the local process boundary and managed model loop.

## Typed Chat and tools

A user turn reaches `ChatProvider`, the runtime process and the kernel. Pi requests inference through the authenticated Gemini gateway. Tool invocations return through the private relay to `ChatToolExecutor`, which performs retained local effects under the captured owner authority. Tool results preserve their invocation/run identity so a delayed completion cannot be attached to an unrelated turn.

SQL and semantic search use local data. Task and goal writes have typed local tools; raw SQL is not permission to bypass those owners. Catalog and journal generation counters invalidate stale fetches and mutations when the owner changes. UI text that arrived before durable acceptance must not be presented as terminal journal success.

## PTT and realtime recovery

Realtime voice uses Gemini Live. The controller associates reconnect and retained PCM buffers with a turn and admitted session context. It drops buffers for superseded turns and preserves a context-fresh reconnect buffer through PTT release. If Live cannot finish, completed-turn recovery uses the existing silence/language policy, batch transcription, Gemini Chat and retained spoken output.

When an interruption requires a fresh Live connection, its three-second replacement deadline owns the buffered capture. The ordinary one-second warm timeout is cancelled during that replacement; readiness records the already-admitted input before the manager flushes PCM, preventing a second input admission and replacement. If readiness arrives without manager admission, a short rescue deadline remains. Ordinary cold PTT retains its one-second warm recovery.

Journal-accepted batch-recovery user/assistant text also reaches B. `VoiceTurnCoordinator` captures observation authority when the voice turn begins and retains it through fallback completion. The generated pair is observed before playback completes; terminal delivery or interruption updates it. Owner or supervisor-session changes reject late observations. This feeds B’s existing bounded snapshot and introduces no additional journal or export path.

`PTTBatchTranscriptionPolicy` uses voice languages and the turn/context vocabulary, not ambient meeting-language preferences. It checks authorization before and after the provider call. An empty single-language result can retry once with `multi`; the shared fallback callback records whether that retry recovered or exhausted.

## Supervisor-origin speech

A's native Gemini Live connection is separate from the Pi text/tool loop described above. [B's supervisor](supervisor-conversation.md) hands private guidance to `RealtimeHubController`, which admits a genuine `.supervisor` intent through `VoiceTurnCoordinator`. Admission requires idle voice; speech dispatch additionally checks current owner/session/context, snooze, notifications and frequency. The reducer starts neither microphone capture nor the PTT capture timeout.

The Live transport sends one standalone `realtimeInput.text` message for private initiation. It does not bracket a no-microphone turn with audio activity markers. Physical PTT retains its activity start, PCM/context and activity end sequence. A warm connection that already contains a completed or attempted response is replaced before an automatic turn, with a fresh response identity and prompt receipt. The note is consumed before sending. An ambiguous connection failure cancels the automatic turn instead of reconnecting to replay it or entering batch-STT recovery. Ordinary user PTT keeps its existing recovery policy. Automatic admission, send and provider errors record only a fixed stage, bounded failure kind/domain/code and Boolean state, never the private note or raw provider reason.

After a tool-only response, the existing bounded continuation also sends standalone text, preserving its current identity and one-attempt guard. It does not open a microphone activity window.

`guide_next_turn` keeps one expiring note for the next PTT input window and does not initiate speech. PTT admission immediately interrupts an active automatic turn through the existing output owner. Automatic turns reject tool calls in code; private notes do not authorize user-turn tool effects.

Supervisor output is admitted as an assistant-only entry in the existing canonical journal through `RealtimeHubController+TurnPersistence`. The continuity key carries opaque decision correlation; no invented user utterance or private note enters journal text. Completed delivery requires both provider completion and actual playback drain. Accepted generated text has journal status `completed`; a separate bounded `voiceDeliveryOutcome` persists whether speech completed, was cancelled, failed or was suppressed. Restored Chat shows “Interrupted”, “Voice reply incomplete” or “Not spoken” accordingly. A genuine journal failure still shows “Couldn't save this reply”. Generated text alone cannot prove full delivery. The [evaluation reporter](../integrations/telemetry.md) links these outcomes and user scores to both prompt versions without affecting speech on export failure.

Helpful/unhelpful feedback shares the message metadata row's keyboard focus state with copy and context controls, so focusing a feedback button reveals the quiet row. The floating response view retains its own local focus state.

## Verification

Owner authority tests prove runtime handshake/revocation. Journal tests prove accepted-turn persistence. PTT language-policy tests exercise the retry and authorization seam; realtime continuity and persistence-fence suites cover their owning state machines. These are complementary to natural physical-PTT/provider evidence in [qualification](../operations/qualification.md).

When changing voice or Chat, identify the authority for input, turn identity, tool effects, accepted journal output and playback separately. A successful model response alone does not prove all those transitions completed.

## Source evidence

- [desktop/macos/Desktop/Sources/Providers/ChatProvider.swift](../../../desktop/macos/Desktop/Sources/Providers/ChatProvider.swift#L825-L857)
- [desktop/macos/agent/src/runtime/conversation-journal.ts](../../../desktop/macos/agent/src/runtime/conversation-journal.ts)
- [desktop/macos/agent/tests/conversation-journal.test.ts](../../../desktop/macos/agent/tests/conversation-journal.test.ts)
- [desktop/macos/Desktop/Sources/FloatingControlBar/PTTBatchTranscriptionPolicy.swift](../../../desktop/macos/Desktop/Sources/FloatingControlBar/PTTBatchTranscriptionPolicy.swift)
- [desktop/macos/Desktop/Tests/PTTBatchLanguagePolicyTests.swift](../../../desktop/macos/Desktop/Tests/PTTBatchLanguagePolicyTests.swift)
- [desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController+PushToTalk.swift](../../../desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController+PushToTalk.swift)
- [desktop/macos/Desktop/Sources/Providers/ChatToolExecutor.swift](../../../desktop/macos/Desktop/Sources/Providers/ChatToolExecutor.swift#L820-L838)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
