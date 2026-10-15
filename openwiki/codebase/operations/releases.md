---
type: Codebase guide
title: Delivery and updates
description: Trace backend exact-SHA deployment and desktop qualification, promotion, signed artifacts and idle relaunch.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-10-15T06:57:13.407Z
sources:
  - id: openwiki-source-6934316e4f1b3e4bc3d82368
    resource: repo://.github/scripts/backend_candidate_probe.py
  - id: openwiki-source-44eedcfce6140b49b80aa902
    resource: repo://.github/scripts/desktop-release-source-identity.py
  - id: openwiki-source-8b209a766e65972401f06f98
    resource: repo://.github/scripts/test_desktop_release_flow_contract.py
  - id: openwiki-source-c8caf28f5c8356e5cde1fdbb
    resource: repo://.github/workflows/desktop_promote_prod.yml
  - id: openwiki-source-d53603b331ded77c93e8fe04
    resource: repo://.github/workflows/desktop_qualify_beta.yml
  - id: openwiki-source-3f92d7eea2d4b723dbf27202
    resource: repo://.github/workflows/gcp_backend.yml
  - id: openwiki-source-dc2e21fd8c87acad5a3f175f
    resource: repo://codemagic.yaml
  - id: openwiki-source-44b0e3d0a095c05af432fd4c
    resource: repo://desktop/macos/Desktop/Sources/UpdateRelaunchWindowPolicy.swift
  - id: openwiki-source-21d2f3bf0dc8ef63e1a84736
    resource: repo://desktop/macos/Desktop/Sources/UpdaterViewModel.swift
  - id: openwiki-source-8870fabff52713e7a9cb9151
    resource: repo://desktop/macos/Desktop/Sources/Updates/UpdateInstallationAdmission.swift
  - id: openwiki-source-5f82b394f0fb8c8ef82a6f25
    resource: repo://scripts/voice-provider-probe.sh
generated: { by: "codex", at: "2026-10-15T06:57:13.407Z" }
---
# Delivery and updates

Backend deployment and desktop publication use separate evidence and mutation paths. The shared rule is that the accepted source, tested artifact and promoted identity must agree. [Delivery guidance](../../INSTRUCTIONS.md#delivery-guidance) owns the operating constraints and explicit authorization rules.

## Backend

The manual Cloud Run workflow accepts an environment, exact release SHA and mode. Deploy, traffic repair, read-only foundation readiness and artifact cleanup dry-run are distinct modes. The environment-scoped backend-stack concurrency group serializes deployment mutations without canceling a running operation.

The runtime environment contract defines the canonical deployment shape. The workflow obtains short-lived GitHub workload identity, builds and identifies the candidate, runs readiness/acceptance gates, promotes traffic and verifies the serving release vector. Failure/rollback evidence matters because a successful image build cannot prove the serving service matches it. Break-glass inputs relax a named evidence gate while retaining the merged-source boundary.

### Candidate conversation and Live probes

Before shifting traffic, the manual backend workflow runs the candidate conversation helper and the managed voice-provider helper with a protected Firebase token file. Candidate evidence remains bound to the admitted source, revision, image digest, tag and workflow run. The conversation helper checks shallow process health, advertised compatibility and read-only Firestore availability, then creates one `/v1/conversation/session` and sends two `/v1/conversation/respond` turns with the same validated prompt reference. It parses the application's `text_delta`/`done` stream, requires terminal usage and prompt identity, and rejects premature completion or unsupported events. Both fixed fixtures ask to keep the conversation open.

The conversation probe bounds first-event latency to 20 seconds and a response to 70 seconds, caps stream/text size and carries at most 4,000 characters per historical turn. Its receipt records counts/timings and target identity rather than conversation text or credentials. The root compatibility version remains a separate advertised contract; the removed raw-provider chat route is not used.

The voice helper first resolves that logical conversation's A instructions, mints `/v2/realtime/session` with the same conversation ID and prompt reference, and verifies the returned complete receipt before connecting. Provider setup uses the pinned instructions, automatic voice activity detection, transcription, the fixed `end_conversation` signal and the current Live voice/session settings. It sends standalone text without manual microphone activity markers. A successful terminal provider event proves that bounded protocol exchange only; human-heard audio, natural interruption and silent Supervisor guidance require their separate acceptance paths.

## Desktop

Candidate planning, signing, qualification and promotion are distinct stages. Source identity checks inspect first-parent history, and qualification records bind source SHA and artifact digest. Follow [build/signing](../integrations/build-signing.md) and [qualification](qualification.md); local compilation alone does not authorize a release claim. Existing changelog JSON remains release data in its native location.

### Release owners and entrypoints

| Stage | Implemented owner |
| --- | --- |
| Artifact build | Root `codemagic.yaml`: `intentive-macos-release` and manual/API-only `intentive-macos-preview` |
| Signed owner evidence | `desktop/macos/scripts/collect-owner-manual-beta-qualification.sh` in the isolated exact-tag checkout |
| Beta qualification | Manual `desktop_qualify_beta.yml` with `release_tag` and exact `owner_evidence_asset` |
| Stable promotion | Protected manual `desktop_promote_prod.yml` with `release_tag` and `confirm=promote-stable` |

The shared Codemagic pipeline validates inputs/source, imports signing identity, builds, signs nested code and the outer bundle, notarizes, signs Sparkle archives, publishes symbols, smokes the signed artifacts and publishes immutable evidence. The release workflow captures both Stable and Beta artifacts and smoke results. Preview uses its separate protected group and has no tag trigger.

Beta qualification runs on Ubuntu against owner-collected Mac evidence. It rejects a different GitHub actor before candidate access, binds the tag to a clean exact commit, and downloads exactly one copy of each expected artifact and content-addressed evidence asset. The contract tests execute the owner-dispatch shell with accepted and rejected identities. A fixture pass establishes that guard, not live signed-Mac qualification.

Stable promotion has its own `prod` environment and non-canceling lock. It checks the approved production API and a successful trusted qualification for the exact candidate before pointer work. These scripts are the executable procedure; the [open release prerequisites](../../INSTRUCTIONS.md#unresolved-commitments) and [dated ownership record](../../INSTRUCTIONS.md#provenance-and-ownership) retain the human authorization/evidence boundary. Merely documenting a command does not dispatch it.

## Installed update behavior

The updater passes a current local activity snapshot into installation admission. Ambient startup/finalization, an open logical conversation, active provider/playback, connection/reconnection and typed streaming keep installation scheduled for quit; the policy must not use a timeout to interrupt active work. Waiting between conversation replies does not make the open conversation idle for update purposes. Retired general tool work contributes no active count. Window restoration is a separate concern: the relaunch policy persists an attempt record and whether the main window should be restored, then consumes that record after relaunch.

Before changing delivery tooling, trace the precise workflow, script and contract tests that own the transition. Production configuration, signed/notarized acceptance and owner/legal destinations include outstanding authored obligations; repository source is not live deployment evidence.

## Source evidence

- [Candidate conversation probe](../../../.github/scripts/backend_candidate_probe.py)
- [Prompt-bound voice probe](../../../scripts/voice-provider-probe.sh)
- [Pre-traffic probe workflow](../../../.github/workflows/gcp_backend.yml#L826-L852)

- [.github/workflows/gcp_backend.yml](../../../.github/workflows/gcp_backend.yml#L1-L95)
- [desktop/macos/Desktop/Sources/Updates/UpdateInstallationAdmission.swift](../../../desktop/macos/Desktop/Sources/Updates/UpdateInstallationAdmission.swift)
- [desktop/macos/Desktop/Sources/UpdaterViewModel.swift](../../../desktop/macos/Desktop/Sources/UpdaterViewModel.swift#L554-L610)
- [desktop/macos/Desktop/Sources/UpdateRelaunchWindowPolicy.swift](../../../desktop/macos/Desktop/Sources/UpdateRelaunchWindowPolicy.swift)
- [.github/scripts/desktop-release-source-identity.py](../../../.github/scripts/desktop-release-source-identity.py#L12-L132)

- [Codemagic build stages](../../../codemagic.yaml#L1-L106)
- [Owner qualification admission](../../../.github/workflows/desktop_qualify_beta.yml#L1-L118)
- [Executable owner-identity tests](../../../.github/scripts/test_desktop_release_flow_contract.py#L144-L173)
- [Protected Stable promotion](../../../.github/workflows/desktop_promote_prod.yml#L1-L111)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
