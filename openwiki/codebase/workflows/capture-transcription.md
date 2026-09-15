---
type: Codebase guide
title: Capture and transcription
description: Trace local capture/finalization and transient cloud STT, keeping ambient transcription separate from voice turns.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-3a8324c40231cdb47b14a0c8
    resource: repo://backend/routers/listen/runtime.py
  - id: openwiki-source-f7722263eacd863981b7ef48
    resource: repo://backend/tests/unit/test_listen_transient_contract.py
  - id: openwiki-source-7b28599e5fadd910008e71c1
    resource: repo://desktop/macos/Desktop/Sources/AppState/AppState%2BListenEvents.swift
  - id: openwiki-source-68f304488b5eba9e53815f71
    resource: repo://desktop/macos/Desktop/Sources/AppState/AppState%2BTranscription.swift
  - id: openwiki-source-0ed8e411deb2244cca5f7d5f
    resource: repo://desktop/macos/Desktop/Sources/ConversationFinalizationService.swift
  - id: openwiki-source-afd2ee5cdf854c9307c25e08
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/LocalTranscriptFormatter.swift
  - id: openwiki-source-09ee795cdf804c9c27a7a9a6
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/TranscriptionStorage%2BLocalAuthority.swift
  - id: openwiki-source-5f30adb7a7fdc16ada6d6f6e
    resource: repo://desktop/macos/Desktop/Tests/ConversationIngestionTests.swift
generated: { by: "codex", at: "2026-09-15T15:29:21.904Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T15:29:21.904Z
---
# Capture and transcription

Ambient capture and push-to-talk are different workflows. Ambient transcription produces the local conversation archive. PTT produces an interactive voice turn and has its own bounded recovery policy described in [Chat and voice](chat-voice.md).

## Ambient path

`AppState+Transcription` admits local capture and creates a conversation handle before starting transcription. Apple Silicon can use local Parakeet; Intel and local-model failures can take the cloud path. Microphone and system audio feed separate local transcription instances or the mixed cloud stream. Conversation finalization and the archive repository remain on the Mac.

Owner transition quiesces capture, including pending final-tail work, before moving authority. Meeting-ended and duration-boundary handling finalize local conversations rather than waiting for a backend conversation object. Capture lifecycle, retry and finalization need to be traced together when diagnosing missing tail audio.

## Transcript chronology

Provider delivery order is not spoken order. The live AppState projection and local archive both use `LocalTranscriptFormatter.chronologicallyOrdered`: start time first, original arrival order for equal-time segments, then stable input order. Live updates sort before publishing to the transcript monitor. Storage sorts the raw ingestion records before normalization joins adjacent fragments and assigns the saved display order.

A correction with the same segment ID retains its original arrival position, even when its timestamp changes. Live `arrivalOrder` and persistent `sourceOrder` keep that tie-breaker independent of the current display position. Existing keyed translations survive a text-only correction. The regression tests drive real AppState ingestion and GRDB writes, close and reopen the database, and compare the live/monitor order with the restored conversation. This establishes synthetic ingestion and persistence behavior, not natural microphone or provider qualification.

## Transient cloud path

The retained `/v4/listen` route accepts an immutable language/translation/vocabulary snapshot and fixed audio transport. Its runtime supervises connection tasks, receives audio, manages provider/admission/usage status, and sends transient transcript events. Modulate final utterances become stable UUID segments with zero-based numeric speaker IDs; translation is keyed to those segments.

There is no client-conversation identity in the accepted socket query. The tests reject retired/unknown query fields, prove that a real route streams a segment plus keyed translation without product persistence, and preserve the original segment when translation fails. Usage/account facts still have a retained backend owner; that does not imply hosted conversation storage.

```mermaid
flowchart LR
  Audio[Mac microphone and system audio] --> Choice[Transcription selection]
  Choice --> Local[Local Parakeet]
  Choice --> Socket[Authenticated listen socket]
  Socket --> Modulate[Managed STT]
  Local --> Archive[Mac conversation and transcript stores]
  Modulate --> Segments[Transient canonical segments]
  Segments --> Archive
```

For a failure, identify whether admission, capture, transport, canonical segment delivery or local finalization failed. Follow `ConversationFinalizationService` into its local store and candidate-compute calls. A server WebSocket success alone cannot prove a durable conversation; a local synthetic test cannot prove physical microphone capture.

## Source evidence

- [desktop/macos/Desktop/Sources/AppState/AppState+Transcription.swift](../../../desktop/macos/Desktop/Sources/AppState/AppState+Transcription.swift#L67-L115)
- [desktop/macos/Desktop/Sources/AppState/AppState+Transcription.swift](../../../desktop/macos/Desktop/Sources/AppState/AppState+Transcription.swift#L150-L226)
- [backend/tests/unit/test_listen_transient_contract.py](../../../backend/tests/unit/test_listen_transient_contract.py#L120-L247)
- [backend/tests/unit/test_listen_transient_contract.py](../../../backend/tests/unit/test_listen_transient_contract.py#L376-L425)
- [backend/routers/listen/runtime.py](../../../backend/routers/listen/runtime.py#L57-L111)
- [desktop/macos/Desktop/Sources/ConversationFinalizationService.swift](../../../desktop/macos/Desktop/Sources/ConversationFinalizationService.swift)
- [desktop/macos/Desktop/Tests/ConversationIngestionTests.swift](../../../desktop/macos/Desktop/Tests/ConversationIngestionTests.swift)
- [desktop/macos/Desktop/Sources/AppState/AppState+ListenEvents.swift](../../../desktop/macos/Desktop/Sources/AppState/AppState+ListenEvents.swift#L1-L78)
- [desktop/macos/Desktop/Sources/Rewind/Core/LocalTranscriptFormatter.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/LocalTranscriptFormatter.swift#L12-L28)
- [desktop/macos/Desktop/Sources/Rewind/Core/TranscriptionStorage+LocalAuthority.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/TranscriptionStorage+LocalAuthority.swift#L58-L142)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
