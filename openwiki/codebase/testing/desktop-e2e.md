---
type: Codebase guide
title: Desktop end-to-end verification
description: Explain named bundles, flow inventory, tiers, source identity and physical versus synthetic evidence.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-3980081a58a01382ad067c02
    resource: repo://desktop/macos/agent/tests/conversation-storage.test.ts
  - id: openwiki-source-1a5c75ab5fe48066cb01992a
    resource: repo://desktop/macos/Desktop/Sources/Automation/ConversationPresentationPreview.swift
  - id: openwiki-source-1755dc193842bf4d7add2bd1
    resource: repo://desktop/macos/Desktop/Sources/Automation/DesktopAutomationConversationPreviewActions.swift
  - id: openwiki-source-6b5fc7ac4b4a739ef71b172a
    resource: repo://desktop/macos/Desktop/Tests/AmbientCaptureLifecycleTests.swift
  - id: openwiki-source-c8eeff499a30efe076e6b5cf
    resource: repo://desktop/macos/Desktop/Tests/APIClientAuthRetryTests.swift
  - id: openwiki-source-e258a11230cac85403c011e3
    resource: repo://desktop/macos/Desktop/Tests/ConversationLifecycleTests.swift
  - id: openwiki-source-e8af95bb11237ff7601f5bab
    resource: repo://desktop/macos/Desktop/Tests/ConversationLiveSessionTests.swift
  - id: openwiki-source-c51f6727367f386a1974bb34
    resource: repo://desktop/macos/Desktop/Tests/ConversationOpeningRequestTests.swift
  - id: openwiki-source-3e930575818dad6d1f40ea0b
    resource: repo://desktop/macos/Desktop/Tests/ConversationOutputAdmissionTests.swift
  - id: openwiki-source-ea8390b2f38b3efb30eabe98
    resource: repo://desktop/macos/Desktop/Tests/ConversationPendingAudioTests.swift
  - id: openwiki-source-aac74c2c79bc006e52c8058a
    resource: repo://desktop/macos/Desktop/Tests/ConversationPresentationPreviewTests.swift
  - id: openwiki-source-c5914c9070f6356327633f39
    resource: repo://desktop/macos/Desktop/Tests/OnboardingCompletionBehaviorTests.swift
  - id: openwiki-source-3a6beeb263fb2e3086419d17
    resource: repo://desktop/macos/Desktop/Tests/OnboardingSkipBehaviorTests.swift
  - id: openwiki-source-6381aced3f5b7d306db135b9
    resource: repo://desktop/macos/Desktop/Tests/SupervisorAudioTimelineTests.swift
  - id: openwiki-source-ec2aa1ff3fb10c3cb271e0b4
    resource: repo://desktop/macos/Desktop/Tests/SupervisorServiceTests.swift
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
generated: { by: "codex", at: "2026-10-14T15:50:15.263Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-10-14T15:50:15.263Z
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
| T0 static flow contract | `./scripts/desktop-core-harness.sh --self-check` |
| T1 named-bundle flows | `./scripts/desktop-core-harness.sh --tier 1 --bundle omi-core-e2e` |
| T2 offline stack and flows | `./scripts/desktop-core-harness.sh --tier 2 --bundle omi-core-e2e` |
| T3 flow ladder | `./scripts/desktop-core-harness.sh --tier 3 --bundle omi-core-e2e` |
| Separate fault bundle | `./scripts/desktop-core-harness.sh --fault-suite` |
| Retained Node storage contracts | `./scripts/test-conversation-storage.sh` |

T1–T3 reject non-macOS execution and production bundle selection. T2+ ensures the dev stack, runs flows through the selected tier and adds the spatial-overlay Swift harness. The retired Pi continuity gauntlet is no longer invoked. `--keep-stack` preserves the T2+ stack after completion. Readiness mode checks static contracts and the offline stack without launching app flows.

For narrow manual diagnosis, use `./scripts/omi-ctl health`, `state`, `screens`, `actions` and `log-path`; `action <name> [key=value ...]` invokes a registered semantic action. `OMI_AUTOMATION_PORT` selects the local bridge. Health/log-path use its public identity route; state and actions obtain the per-launch bearer token from the local token file. Inspect action descriptors and the current state before selecting a mutating action.

## Flow ownership

Flow YAML lives beside the E2E feature inventory, and `check-e2e-flow-coverage.py --strict` is called by the desktop runner. Keep a behavior's automation hooks, flow and owning tests aligned.

Physical microphone capture, system permissions, visible UI transitions and real-provider recall need their own evidence. A synthetic terminal-success record proves a controlled lifecycle, not that a person spoke and the model remembered it. The [qualification guide](../operations/qualification.md) links the open one-final-SHA obligations.

## All-day listening coverage

The [capture workflow](../workflows/capture-transcription.md) is covered at three existing boundaries: `SystemAudioCaptureModeSettingsTests` and `PersistedCaptureLaunchPolicyTests` exercise defaults and restoration; `OnboardingCompletionBehaviorTests` and `OnboardingSkipBehaviorTests` exercise completion directly from both final-demo controls, repeated completion, late demo warmup and neutral global Skip; `AmbientCaptureLifecycleTests` drives real `AppState` reconciliation with microphone and system-audio hardware adapters. Controlled completions test stopping and replacement sessions during asynchronous startup. The lifecycle suite also checks independent System Audio disablement, independent microphone/system enablement, denied microphone with healthy system capture, and preservation of the other permitted source on failure. These tests prove orchestration, not physical audio acquisition.

Run affected XCTest suites in separate processes, for example `xcrun swift test --package-path desktop/macos/Desktop --filter 'AmbientCaptureLifecycleTests/'` from the repository root. `desktop/macos/test.sh` includes the unchanged transcript-storage regressions and runs desktop XCTest suites with process isolation.

`onboarding-flow.yaml` is a manual genuine-onboarding flow: the existing screen-and-voice demo is the last stage, and its Continue or demo-local Skip for now opens Home directly with all-day listening enabled. There is no listening-mode or replacement confirmation stage. Repeated setup remains valid, and global Skip leaves capture inactive across relaunch. Its sleep/wake and closed-lid-but-awake checks need an actual Mac configuration. `audio-recording.yaml` separately checks that turning System Audio off leaves microphone listening available and that pausing Listening stops both sources. T2 synthetic transcript injection cannot replace these UI and hardware checks.

## Supervisor conversation coverage

`SupervisorServiceTests` drives actual scheduling with controlled images, revisions, inference completion and clock. It covers fixed coalescing, quiet reconsideration, shared tokens, one request/latest snapshot, stale context, account revocation and quota pause. `SupervisorWebcamTests` and `AmbientCaptureLifecycleTests` cover independent inputs and unavailable-source isolation. `SupervisorAudioTimelineTests` covers capture/provider time mapping and direct-conversation precedence.

`ConversationLifecycleTests` covers logical identity, sticky fallback and listening-only silence. `ConversationLiveSessionTests` exercises automatic VAD, the fixed lifecycle function, idle `turnComplete:false` framing and exclusive usage. `ConversationOpeningRequestTests`, `ConversationPendingAudioTests` and `ConversationOutputAdmissionTests` cover cancelled deferred opens, bounded microphone prefix and initial canonical admission before audio. These controlled seams do not establish the provider's silent-append or physical echo behavior.

`ConversationPromptBindingTests`, owner-bound API tests and backend conversation contracts preserve one exact instruction receipt across routes and reject stale owners or caller-defined capabilities. History projection and Node storage tests cover distinct admission-ordered tails, revision/idempotency, historical reopen and orphan repair. Delivery-domain tests distinguish interrupted speech from a failed save.

`AIEvaluationExportTests` and production API request tests check bounded export, consent epochs and owner revalidation after delayed token lookup. Private guidance is excluded even with opt-in; a telemetry 401 does not refresh, replay or sign out.

`supervisor-conversation.yaml` remains manual. It requires several replies from user/B starts, spoken interruption on speakers/headphones/Bluetooth, all end conditions, multiple forced-fallback exchanges, silent private cues, independent input failures, prompt/privacy checks and a real eight-hour resource soak. T2/T3 success, injected PCM, provider-returned audio or a fake-clock workday cannot mark that flow passed. Record source/bundle/backend identity and measured timings separately from any blocked row.

### Synthetic notch preview

The non-production `debug_bar_state` action borrows an empty floating conversation surface using the same presentation mapper. Supported states are `opening`, `listening`, `thinking`, `speaking`, `reconnecting`, and `idle`; `answering` remains an alias for speaking. Optional `microphone_level` and `playback_level` values must be finite numbers from zero to one. The response marks levels as synthetic and reports `usesNotchIsland`.

Select the exact named bundle's automation port, inspect its state, then use `action debug_bar_state state=opening` or `action debug_bar_state state=listening microphone_level=0.06`. Finish with `action debug_bar_state state=idle`. The action rejects production bundles and active work or user content, and starts no capture, provider, or conversation timer. It may initialize the existing empty window before onboarding completes. Cleanup releases only its meter and still-owned presentation; a real conversation or a new draft must retain ownership. A hidden starting surface returns to hidden, so cleanup evidence may be state rather than a floating-window image.

`ConversationPresentationPreviewTests` covers those ownership boundaries with the real mapper and meter. Rendered previews verify the original visual components with injected levels. They cannot verify physical microphone levels, acoustic echo cancellation, audible output or natural interruption.

See the [conversation workflow](../workflows/chat-voice.md), [Supervisor workflow](../workflows/supervisor-conversation.md) and [export policy](../integrations/telemetry.md) for the implementation owners.

## Safe execution

Use only named test bundles and the prescribed local harness. Preserve manifests and logs in private local evidence locations, never provider tokens or raw personal content in the wiki. Report the exact commands, source identity, mode and outcome; do not convert a skipped or blocked tier into a pass.

## Source evidence

- [desktop/macos/scripts/desktop-core-harness.sh](../../../desktop/macos/scripts/desktop-core-harness.sh)
- [desktop/macos/test.sh](../../../desktop/macos/test.sh#L1-L21)
- [desktop/macos/scripts/check-e2e-flow-coverage.py](../../../desktop/macos/scripts/check-e2e-flow-coverage.py)

- [Tier dispatch](../../../desktop/macos/scripts/desktop-core-harness.sh#L1110-L1205)
- [Bridge command authentication](../../../desktop/macos/scripts/omi-ctl#L1-L75)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
