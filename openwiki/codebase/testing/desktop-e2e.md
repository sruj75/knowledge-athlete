---
type: Codebase guide
title: Desktop end-to-end verification
description: Explain named bundles, flow inventory, tiers, source identity and physical versus synthetic evidence.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-276b6bd5d516d3e8277c2462
    resource: repo://backend/tests/unit/test_voice_provider_probe.py
  - id: openwiki-source-6b5fc7ac4b4a739ef71b172a
    resource: repo://desktop/macos/Desktop/Tests/AmbientCaptureLifecycleTests.swift
  - id: openwiki-source-c8eeff499a30efe076e6b5cf
    resource: repo://desktop/macos/Desktop/Tests/APIClientAuthRetryTests.swift
  - id: openwiki-source-c5914c9070f6356327633f39
    resource: repo://desktop/macos/Desktop/Tests/OnboardingCompletionBehaviorTests.swift
  - id: openwiki-source-3a6beeb263fb2e3086419d17
    resource: repo://desktop/macos/Desktop/Tests/OnboardingSkipBehaviorTests.swift
  - id: openwiki-source-2fd985b3fe67bf34e47b6cf5
    resource: repo://desktop/macos/Desktop/Tests/PersistedCaptureLaunchPolicyTests.swift
  - id: openwiki-source-0adbb8127cc707067b3adf30
    resource: repo://desktop/macos/Desktop/Tests/RealtimeHubSessionInputLifecycleTests.swift
  - id: openwiki-source-6381aced3f5b7d306db135b9
    resource: repo://desktop/macos/Desktop/Tests/SupervisorAudioTimelineTests.swift
  - id: openwiki-source-1592e120abd19e2542953971
    resource: repo://desktop/macos/Desktop/Tests/SupervisorPTTHandoffTests.swift
  - id: openwiki-source-ec2aa1ff3fb10c3cb271e0b4
    resource: repo://desktop/macos/Desktop/Tests/SupervisorServiceTests.swift
  - id: openwiki-source-a35d04e6c48b5c933f303b81
    resource: repo://desktop/macos/Desktop/Tests/SupervisorVoiceDeliveryJournalTests.swift
  - id: openwiki-source-5868e015ddfc06ba519b2fd9
    resource: repo://desktop/macos/Desktop/Tests/SystemAudioCaptureModeSettingsTests.swift
  - id: openwiki-source-db3e257106cfb3cc74404f2a
    resource: repo://desktop/macos/Desktop/Tests/VoiceFallbackSupervisorObservationTests.swift
  - id: openwiki-source-817647037a7a2f498d04beb7
    resource: repo://desktop/macos/Desktop/Tests/VoiceTurnCoordinatorTests.swift
  - id: openwiki-source-6dc8033075abd90b29974c20
    resource: repo://desktop/macos/Desktop/Tests/VoiceTurnDomainTests/VoiceReplacementDeadlineTests.swift
  - id: openwiki-source-37264eb7b55d74ddb5f6107a
    resource: repo://desktop/macos/e2e/flows/audio-recording.yaml
  - id: openwiki-source-b877eb680c762b94400c700b
    resource: repo://desktop/macos/e2e/flows/onboarding-flow.yaml
  - id: openwiki-source-38a1b3c7a8acf2ceea409825
    resource: repo://desktop/macos/e2e/flows/supervisor-conversation.yaml
  - id: openwiki-source-7b7bd425584dcecda56e70ae
    resource: repo://desktop/macos/scripts/check-e2e-flow-coverage.py
  - id: openwiki-source-1d70e9d198b8f1602d970413
    resource: repo://desktop/macos/scripts/desktop-core-harness.sh
  - id: openwiki-source-e05dc09d548050f1b61f3c9a
    resource: repo://desktop/macos/scripts/omi-ctl
  - id: openwiki-source-2a54d9d29c8899e4e49d806c
    resource: repo://desktop/macos/test.sh
  - id: openwiki-source-5f82b394f0fb8c8ef82a6f25
    resource: repo://scripts/voice-provider-probe.sh
generated: { by: "codex", at: "2026-09-28T09:46:29.604Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-28T09:46:29.604Z
---
# Desktop end-to-end verification

Desktop E2E uses named development bundles and a checked-in flow inventory. The harness records which source and binary it exercised. The [authored testing guidance](../../INSTRUCTIONS.md#desktop-testing-guidance) selects the minimum required tier for each changed surface; the commands below are implemented by the existing harness.

## Evidence selection

The desktop-core harness supports local flow lint/smoke, named-bundle automation, offline service-backed flows and a fault suite. Its command help lists the accepted tier names and bundle options. The normal named bundle and fault bundle are distinct; choosing the fault suite must not accidentally target a stale ordinary development app.

Before higher-tier runs, health checks bind the bundle's `sourceGitSHA` and clean-source status to the expected repository state. Offline service-backed acceptance also checks the harness provider-mode sentinel. These checks prevent a stale binary or live-service stack from being labeled as current hermetic evidence.

## Tier and bridge commands

Run these commands from `desktop/macos/`. For T1+, first launch the matching named bundle using the [local development procedure](../operations/development.md); select its bridge port explicitly when multiple bundles are running.

| Evidence | Command |
| --- | --- |
| T0 static flow/gauntlet contract | `./scripts/desktop-core-harness.sh --self-check` |
| T1 named-bundle flows | `./scripts/desktop-core-harness.sh --tier 1 --bundle omi-core-e2e` |
| T2 offline stack and flows | `./scripts/desktop-core-harness.sh --tier 2 --bundle omi-core-e2e` |
| T3 flow ladder plus continuity | `./scripts/desktop-core-harness.sh --tier 3 --bundle omi-core-e2e` |
| Separate fault bundle | `./scripts/desktop-core-harness.sh --fault-suite` |
| Runtime/Swift/Node contract smoke | `./scripts/agent-logic-harness.sh --cross-surface-smoke` |

T1–T3 reject non-macOS execution and production bundle selection. T2+ ensures the dev stack, runs flows through the selected tier and adds the spatial-overlay Swift harness; T3 also invokes the continuity gauntlet. `--keep-stack` preserves the T2+ stack after completion. Readiness mode checks static contracts and the offline stack without launching app flows.

For narrow manual diagnosis, use `./scripts/omi-ctl health`, `state`, `screens`, `actions` and `log-path`; `action <name> [key=value ...]` invokes a registered semantic action. `OMI_AUTOMATION_PORT` selects the local bridge. Health/log-path use its public identity route; state and actions obtain the per-launch bearer token from the local token file. Inspect action descriptors and the current state before selecting a mutating action.

The continuity wrapper offers `--suite prompts`, `continuity`, `agents`, `resilience` and `all`, with an explicit named `--bundle-id`. Its `--self-check` proves wiring only. Physical PTT/final-provider rows still need the actual microphone/provider path and the [authored acceptance rules](../../INSTRUCTIONS.md#desktop-testing-guidance); injected PCM or a controller probe must not be reported as natural capture.

## Flow ownership

Flow YAML lives beside the E2E feature inventory, and `check-e2e-flow-coverage.py --strict` is called by the desktop runner. Keep a behavior's automation hooks, flow and owning tests aligned. The Markdown PTT shadow-state census is an executable test fixture and remains in its original test location; it is not general documentation to regenerate.

Physical microphone capture, system permissions, visible UI transitions and real-provider recall need their own evidence. A synthetic terminal-success record proves a controlled lifecycle, not that a person spoke and the model remembered it. The [qualification guide](../operations/qualification.md) links the open one-final-SHA obligations.

## All-day listening coverage

The [capture workflow](../workflows/capture-transcription.md) is covered at three existing boundaries: `SystemAudioCaptureModeSettingsTests` and `PersistedCaptureLaunchPolicyTests` exercise defaults and restoration; `OnboardingCompletionBehaviorTests` and `OnboardingSkipBehaviorTests` exercise completion directly from both final-demo controls, repeated completion, late demo warmup and neutral global Skip; `AmbientCaptureLifecycleTests` drives real `AppState` reconciliation with microphone and system-audio hardware adapters. Controlled completions test stopping and replacement sessions during asynchronous startup. The lifecycle suite also checks independent System Audio disablement, required microphone failure and optional system-audio failure. These tests prove orchestration, not physical audio acquisition.

Run affected XCTest suites in separate processes, for example `xcrun swift test --package-path desktop/macos/Desktop --filter 'AmbientCaptureLifecycleTests/'` from the repository root. `desktop/macos/test.sh` includes the unchanged transcript-storage regressions and runs desktop XCTest suites with process isolation.

`onboarding-flow.yaml` is a manual genuine-onboarding flow: the existing screen-and-voice demo is the last stage, and its Continue or demo-local Skip for now opens Home directly with all-day listening enabled. There is no listening-mode or replacement confirmation stage. Repeated setup remains valid, and global Skip leaves capture inactive across relaunch. Its sleep/wake and closed-lid-but-awake checks need an actual Mac configuration. `audio-recording.yaml` separately checks that turning System Audio off leaves microphone listening available and that pausing Listening stops both sources. T2 synthetic transcript injection cannot replace these UI and hardware checks.

## Supervisor conversation coverage

`SupervisorServiceTests` drives the real coordinator with controlled observations and inference completions: corrected segments, echo precedence, empty context, owner/app revocation, single-flight/latest-input behavior, stale guidance and quota pause. `SupervisorAudioTimelineTests` checks stream-to-capture mapping, missing spans and clock/reconnect boundaries. Voice reducer/coordinator and Live input lifecycle tests prove genuine no-microphone supervisor admission, private text transport, warm boundaries, assistant-only journal behavior, PTT priority and no automatic replay after ambiguous failure.

`RealtimeHubSessionInputLifecycleTests` also drives real controller admission through a controllable raw transport and its `setupComplete` event. It verifies provider rejection produces a bounded diagnostic and terminal failure without replay. Separate wire tests require one standalone text message for supervisor and post-tool turns; microphone activity markers remain part of PTT. The direct provider probe uses the same text-only request contract. These checks do not establish physical playback.

`SupervisorPTTHandoffTests` drives the real supervisor admission, playback ownership and physical PTT manager entry with injected PCM, then the production replacement callback through a controlled socket. It checks that the required replacement deadline retains capture, readiness sends input exactly once, release sends one activity end and private automatic guidance is not replayed. Reducer tests separately cover replacement timeout and late readiness while preserving ordinary cold-PTT recovery. These are deterministic transport and state-machine checks, not physical microphone evidence.

`VoiceFallbackSupervisorObservationTests` verifies that only journal-accepted fallback exchanges enter B under the owner/session captured when recording began, and that completion waits for playback drain. Cancellation updates the existing exchange; session or owner changes reject late observations. `SupervisorVoiceDeliveryJournalTests` checks assistant-only identity, preserved correlation, delivery metadata round-trips and the precedence of a genuine journal failure over the speech-delivery label.

`AIEvaluationExportTests` checks the bounded export representation and consent epochs. `APIClientAuthRetryTests` additionally drives actual observation requests while token lookup is suspended: off/on revocation removes queued Chat/B text, and a telemetry 401 neither retries nor signs out. These tests exercise implementation boundaries without proving audible output or natural microphone acquisition.

The `supervisor-conversation.yaml` flow deliberately has `tier: manual`. Use a named development bundle with authenticated Gemini and selected managed A/B prompt versions. Observe a controlled screen/transcript event, let B privately cause A to speak, physically interrupt or reply with PTT, and verify that B receives the exchange and playback status. Repeat with speakers and headphones. Check helpful/unhelpful linkage to both prompt versions, normal metadata-only tracing, selected-session bounded text and revocation while work is queued. Its remaining steps cover speech controls, stale notes, empty context, excluded inputs, quotas and connection/prompt/telemetry failures.

A T2/T3 success cannot mark this manual flow passed. Keep the measured input, evaluation and playback timings, source/bundle identity and request count alongside the result. The [workflow](../workflows/supervisor-conversation.md) explains the causal path; the [export policy](../integrations/telemetry.md) limits saved evidence.

## Safe execution

Use only named test bundles and the prescribed local harness. Preserve manifests and logs in private local evidence locations, never provider tokens or raw personal content in the wiki. Report the exact commands, source identity, mode and outcome; do not convert a skipped or blocked tier into a pass.

## Source evidence

- [desktop/macos/scripts/desktop-core-harness.sh](../../../desktop/macos/scripts/desktop-core-harness.sh)
- [desktop/macos/test.sh](../../../desktop/macos/test.sh#L1-L21)
- [desktop/macos/scripts/check-e2e-flow-coverage.py](../../../desktop/macos/scripts/check-e2e-flow-coverage.py)

- [Tier dispatch](../../../desktop/macos/scripts/desktop-core-harness.sh#L1110-L1205)
- [Bridge command authentication](../../../desktop/macos/scripts/omi-ctl#L1-L75)
- [Continuity suite selection](../../../desktop/macos/scripts/agent-continuity-gauntlet.sh#L38-L60)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
