---
type: Codebase guide
title: Build identity and signing
description: Explain checked-in identity, signing inputs, assets, clean named bundles and immutable release provenance.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-10-14T14:40:28.560Z
sources:
  - id: openwiki-source-44eedcfce6140b49b80aa902
    resource: repo://.github/scripts/desktop-release-source-identity.py
  - id: openwiki-source-221ccd7dfd0766ec2939c6ec
    resource: repo://desktop/macos/agent/package.json
  - id: openwiki-source-36b02556083284f5a7ed4b02
    resource: repo://desktop/macos/Desktop/Info.plist
  - id: openwiki-source-17d204e866388c799dad32de
    resource: repo://desktop/macos/Desktop/Omi-Release.entitlements
  - id: openwiki-source-23038f304cdac57febf8872b
    resource: repo://desktop/macos/Desktop/Omi.entitlements
  - id: openwiki-source-fa25afaba6337b7634ae58d1
    resource: repo://desktop/macos/Desktop/Sources/ProactiveAssistants/Services/AssistantSettings.swift
  - id: openwiki-source-c995232429de1e849f638195
    resource: repo://desktop/macos/run.sh
  - id: openwiki-source-0b4dcf4effcd8c8d917e9e0c
    resource: repo://desktop/macos/scripts/prepare-agent-runtime.sh
  - id: openwiki-source-037186bba9f18f2d2528ae17
    resource: repo://desktop/macos/scripts/prepare-desktop-bundle-native-deps.sh
  - id: openwiki-source-154a659480b055a7d2cacbc5
    resource: repo://desktop/macos/tests/test-prepare-desktop-bundle-native-deps.sh
  - id: openwiki-source-7c87e44d7a9e2fc5525ed3c1
    resource: repo://desktop/macos/tests/test-run-signing-identity.sh
generated: { by: "codex", at: "2026-10-14T14:40:28.560Z" }
---
# Build identity and signing

A development bundle and a published release carry different evidence. `desktop/macos/run.sh` builds and signs local bundles; native dependency preparation arranges the embedded frameworks, Node runtime and app executable before signing. Publishing uses the separate candidate and qualification workflows.

## Local build path

Run from the macOS directory with an explicit `OMI_APP_NAME=omi-<task>` as prescribed by [desktop guidance](../../INSTRUCTIONS.md#desktop-guidance). The launcher resolves an available signing identity, signs embedded frameworks and Node with their corresponding entitlements, then signs the app bundle. A locally signed build is not a notarized distributable.

Keep native preparation in the existing script so the local and release builds agree about bundled dependencies. Its shell tests exercise staging behavior; signing-identity tests cover launcher selection. Do not target the production Omi or Omi Beta applications during development.

## Conversational runtime and camera

`prepare-agent-runtime.sh` builds and stages the retained Node conversation storage package. The package has `zod` as its only production dependency; Pi, extension bundles, tool sockets and execution-broker packaging are gone. Historical SQLite data stays at the existing storage location.

Both development and release app entitlements include camera access, and `Desktop/Info.plist` declares the camera usage purpose. These declarations permit the platform permission flow; they do not grant permission or enable the opt-in webcam. Missing camera permission must leave the other permitted inputs usable. Verify the final signed bundle as well as source declarations when qualifying an artifact.

A named local launch demonstrates packaging on that machine. It does not establish macOS minimum-version compatibility, notarization, human-heard interruption or eight-hour resource stability.

## Candidate provenance

The release source-identity tool validates full forty-character Git SHAs and exact macOS release tag syntax. It checks ancestry and walks first-parent history to detect newer releasable inputs; a net diff alone would miss an intervening change that was later reverted. Candidate artifact, source, qualification and promotion identities must remain correlated through delivery.

The [release guide](../operations/releases.md) describes promotion and rollback. Real signed/notarized acceptance remains one of the [open qualification obligations](../../INSTRUCTIONS.md#unresolved-commitments).

## Assets and authored approval

The compact [Asset provenance guidance](../../INSTRUCTIONS.md#asset-provenance) links the immutable record of owner-supplied hashes, approved uses, shipping transformations and the rejected grass-icon experiment. Those are authored provenance facts, not code Claims or a new third-party license. Preserve the repository licenses and the vendored libwebp record in their required locations.

## Source evidence

- [desktop/macos/run.sh](../../../desktop/macos/run.sh#L435-L509)
- [desktop/macos/tests/test-run-signing-identity.sh](../../../desktop/macos/tests/test-run-signing-identity.sh)
- [.github/scripts/desktop-release-source-identity.py](../../../.github/scripts/desktop-release-source-identity.py#L12-L132)
- [desktop/macos/scripts/prepare-desktop-bundle-native-deps.sh](../../../desktop/macos/scripts/prepare-desktop-bundle-native-deps.sh)
- [desktop/macos/tests/test-prepare-desktop-bundle-native-deps.sh](../../../desktop/macos/tests/test-prepare-desktop-bundle-native-deps.sh)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
