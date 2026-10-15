---
type: Codebase guide
title: Continuous spoken and typed conversation
description: Trace one A conversation through native Live, typed input, sticky fallback, interruption and canonical history.
tags: [intentive, codebase, conversation]
sources:
  - id: openwiki-source-e762e0de342d9685ba91244f
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/AIEvaluationFeedbackView.swift
  - id: openwiki-source-9eb663951a8b4854a33ecbc8
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/ConversationPromptBindingStore.swift
  - id: openwiki-source-8e70ba175d72a4aff54aedaa
    resource: repo://desktop/macos/Desktop/Sources/AudioLevelMonitor.swift
  - id: openwiki-source-8cccfc7e26d01ce730e0f49e
    resource: repo://desktop/macos/Desktop/Sources/Chat/KernelTurnJournal.swift
  - id: openwiki-source-02c49fb013004ec031bc2742
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/ConversationDuplexAudio.swift
  - id: openwiki-source-41451213687bdacd0fa49963
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/ConversationLifecycle.swift
  - id: openwiki-source-db06656b742d5a9138835e33
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/ConversationLiveSession.swift
  - id: openwiki-source-d4c66d210abf73b1f4b812e3
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/ConversationPresentation.swift
  - id: openwiki-source-8fbcb59bd0bb6341de1f06c1
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/ConversationSpeechRenderer.swift
  - id: openwiki-source-65f1ed7dfa0d6b5cfc855b63
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/ConversationVoiceController.swift
  - id: openwiki-source-ab4b15f25786468c25ab6529
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/FloatingControlBarState.swift
  - id: openwiki-source-e8cf31348baac3bf1e24a706
    resource: repo://desktop/macos/Desktop/Sources/FloatingControlBar/FloatingConversationOpening.swift
  - id: openwiki-source-21802c0cbbe5aeada371f269
    resource: repo://desktop/macos/Desktop/Sources/MainWindow/Components/ChatMessageMetadataRow.swift
  - id: openwiki-source-e0e1aceea6bbd06a72738ece
    resource: repo://desktop/macos/Desktop/Sources/ProactiveAssistants/Supervisor/SupervisorService.swift
  - id: openwiki-source-d2fcc2b5c63a2a31e81a6ae9
    resource: repo://desktop/macos/Desktop/Sources/Providers/ChatProvider.swift
generated: { by: "codex", at: "2026-10-14T15:50:15.263Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-10-15T08:34:31.929Z
---
# Continuous spoken and typed conversation

A has one logical conversation above individual utterances and provider connections. `ConversationVoiceController` owns voice lifecycle and duplex output; `ChatProvider` joins that conversation through the shared typed lease and prompt binding. The existing Node journal remains the accepted-history owner. Pi, general tools and child agents are removed.

## Open, converse and end

The shortcut toggles the same floating surface used for B initiation. A conversation connects, stays open between replies and can reconnect without changing its identity. Losing window focus does not close it. Logical conversation ID, utterance ID and connection generation are separate, so late connection/turn callbacks cannot act on a replacement.

Explicit closure ends immediately. A's only fixed lifecycle signal, `end_conversation`, waits for final playback; newer user activity invalidates an obsolete signal. Sixty seconds of listening silence also ends the conversation, counting only available-input listening time. Generation, playback and recovery pause counting; B activity and system audio do not reset it.

## Original conversation surface

The shared opening boundary cancels an old dismiss animation, reveals the bar, then opens the existing conversation panel without changing its saved visibility preference. User starts are explicit; B starts retain background snooze admission. Explicit hide/snooze ends the conversation before removing its microphone indicator. Focus loss and temporary presentation transitions remain separate.

`ConversationPresentation` is a read-only projection of logical lifecycle and physical input/output, not a second conversation owner. It drives the retained blue opening glow, thinking animation and waveform components. Connecting/reconnecting shows opening; a pending answer shows thinking; actual rendered output shows speaking. User speech takes priority during interruption. Quiet open periods remain listening, so the surface stays visibly open between replies. Legacy per-turn projection and old PTT hints cannot override an active conversation snapshot.

Processed microphone PCM supplies the input RMS meter; the output engine's mixer tap supplies playback RMS. The controller's meter receipt isolates these from ambient meter writes/reset. Playback generations reject late render callbacks; interruption clears output feedback while preserving microphone levels, and logical close clears both. No queued-audio estimate or synthetic provider state is used as the production waveform level.

## One instruction version

Before attempting Live, Swift calls authenticated `/v1/conversation/session` and pins the returned text/name/version/source/hash. All direct, Live, reconnect and fallback routes use that receipt. Backend exact-version resolution prevents a mutable Langfuse label from changing instructions midway. A versioned tool-free repository instruction may be selected only when creating the conversation.

Closed typed chat sends bounded history/current message, permitted context and optional private guidance to `/v1/conversation/respond`. When the same voice conversation is open, typed input joins its current A route. The typed lease prevents a concurrent B opening or second answer; queued guidance waits for the next safe reply. The backend constructs policy and the fixed lifecycle capability, rather than accepting caller-defined instructions or tools.

## Continuous audio and interruption

`ConversationLiveSession` enables automatic voice activity detection and retains its connection across ordinary replies. `ConversationDuplexAudio` uses one voice-processing AVAudioEngine for processed 16 kHz microphone input and controlled 24 kHz PCM output. Native PCM, generated TTS and system speech all feed that output, giving echo cancellation its render reference. Ambient system-audio observation remains separately owned.

On user speech, the controller stops and flushes playback, cancels obsolete generation/synthesis and fences late callbacks. The interrupted outcome is persisted asynchronously without holding the next utterance behind journal acknowledgement. A bounded ten-second preconnection microphone prefix cannot silently drop its beginning: overflow rejects that Live prefix and uses the complete bounded segmented utterance for fallback.

After bounded same-provider recovery fails, the conversation stays in batch mode until it ends. Processed microphone feeds the existing Silero model with 500 ms preroll and 800 ms trailing silence, then existing batch STT, direct A and controlled generated/system TTS. It retains the prompt, history, interruption and silence semantics. An ambiguously delivered proactive opening is never replayed automatically.

## Acceptance and observation

Initial canonical journal admission precedes visible text and audible PCM. The output admission gate buffers bounded native audio while the first write is pending; batch speech awaits transcript/response-target admission before inference. Stable turn IDs revise the same exchange rather than creating duplicates. The history tail preserves original admission order for each latest revision.

A proactive exchange persists only assistant output, without an invented user message or private cue. Delivery metadata remains distinct from journal success: completion requires provider completion and playback drain; interruption, failure and unspoken output retain their own outcomes. A genuine save failure still has its save warning. Terminal timing is captured at visible/playback completion before waiting for the final write.

B receives bounded partial transcript revisions and actual terminal outcomes under captured owner/session authority. Same-ID revisions replace earlier text. Private cues wait during generation/playback, then append silently with `clientContent` and `turnComplete:false` at an idle boundary; fallback receives private provider context. They never become user messages, journal text or telemetry content.

Helpful/unhelpful feedback retains the metadata row's keyboard-focus visibility; floating feedback uses local focus state. Evaluation receipts correlate the actual pinned A prompt with B decisions and delivery, without making telemetry a prerequisite for speech.

## Verification

Lifecycle, Live protocol, segmentation, playback, prompt-binding, pending-audio, output-admission, owner-bound API and journal tests cover controlled implementation seams. The [manual qualification](../operations/qualification.md#conversational-product-qualification) separately requires provider silent append, human-heard speaker/headphone/Bluetooth interruption and a real eight-hour soak. Wire framing or returned PCM is not physical acceptance.

Presentation and meter tests also exercise continuous listening, interruption priority, scoped callback rejection and preservation of the original geometry. The [development preview](../testing/desktop-e2e.md#synthetic-notch-preview) can render these states with explicitly synthetic levels; it is not evidence of physical capture or human-heard output.

## Source evidence

- [Conversation owner](../../../desktop/macos/Desktop/Sources/FloatingControlBar/ConversationVoiceController.swift)
- [Lifecycle](../../../desktop/macos/Desktop/Sources/FloatingControlBar/ConversationLifecycle.swift)
- [Live protocol](../../../desktop/macos/Desktop/Sources/FloatingControlBar/ConversationLiveSession.swift)
- [Duplex audio](../../../desktop/macos/Desktop/Sources/FloatingControlBar/ConversationDuplexAudio.swift)
- [Typed routing and history](../../../desktop/macos/Desktop/Sources/Providers/ChatProvider+Conversation.swift)
- [Prompt binding](../../../desktop/macos/Desktop/Sources/AIObservability/ConversationPromptBindingStore.swift)
- [Canonical storage](../../../desktop/macos/agent/src/conversation-storage.ts)

[Supervisor](supervisor-conversation.md) · [Telemetry](../integrations/telemetry.md) · [Start here](../../quickstart.md)
