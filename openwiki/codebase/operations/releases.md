---
type: Codebase guide
title: Delivery and updates
description: Trace backend exact-SHA deployment and desktop qualification, promotion, signed artifacts and idle relaunch.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T14:14:00.034Z
sources:
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
generated: { by: "codex", at: "2026-09-15T14:14:00.034Z" }
---
# Delivery and updates

Backend deployment and desktop publication use separate evidence and mutation paths. The shared rule is that the accepted source, tested artifact and promoted identity must agree. [Delivery guidance](../../INSTRUCTIONS.md#delivery-guidance) owns the operating constraints and explicit authorization rules.

## Backend

The manual Cloud Run workflow accepts an environment, exact release SHA and mode. Deploy, traffic repair, read-only foundation readiness and artifact cleanup dry-run are distinct modes. The environment-scoped backend-stack concurrency group serializes deployment mutations without canceling a running operation.

The runtime environment contract defines the canonical deployment shape. The workflow obtains short-lived GitHub workload identity, builds and identifies the candidate, runs readiness/acceptance gates, promotes traffic and verifies the serving release vector. Failure/rollback evidence matters because a successful image build cannot prove the serving service matches it. Break-glass inputs relax a named evidence gate while retaining the merged-source boundary.

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

The updater passes a current local activity snapshot into installation admission. Capture, voice and Chat activity can keep installation scheduled for quit; the policy must not use a timeout to interrupt active work. Window restoration is a separate concern: the relaunch policy persists an attempt record and whether the main window should be restored, then consumes that record after relaunch.

Before changing delivery tooling, trace the precise workflow, script and contract tests that own the transition. Production configuration, signed/notarized acceptance and owner/legal destinations include outstanding authored obligations; repository source is not live deployment evidence.

## Source evidence

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
