---
type: Codebase guide
title: Build identity and signing
description: Explain checked-in identity, signing inputs, assets, clean named bundles and immutable release provenance.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-44eedcfce6140b49b80aa902
    resource: repo://.github/scripts/desktop-release-source-identity.py
  - id: openwiki-source-c995232429de1e849f638195
    resource: repo://desktop/macos/run.sh
  - id: openwiki-source-037186bba9f18f2d2528ae17
    resource: repo://desktop/macos/scripts/prepare-desktop-bundle-native-deps.sh
  - id: openwiki-source-154a659480b055a7d2cacbc5
    resource: repo://desktop/macos/tests/test-prepare-desktop-bundle-native-deps.sh
  - id: openwiki-source-7c87e44d7a9e2fc5525ed3c1
    resource: repo://desktop/macos/tests/test-run-signing-identity.sh
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
---
# Build identity and signing

A development bundle and a published release carry different evidence. `desktop/macos/run.sh` builds and signs local bundles; native dependency preparation arranges the embedded frameworks, Node runtime and app executable before signing. Publishing uses the separate candidate and qualification workflows.

## Local build path

Run from the macOS directory with an explicit `OMI_APP_NAME=omi-<task>` as prescribed by [desktop guidance](../../INSTRUCTIONS.md#desktop-guidance). The launcher resolves an available signing identity, signs embedded frameworks and Node with their corresponding entitlements, then signs the app bundle. A locally signed build is not a notarized distributable.

Keep native preparation in the existing script so the local and release builds agree about bundled dependencies. Its shell tests exercise staging behavior; signing-identity tests cover launcher selection. Do not target the production Omi or Omi Beta applications during development.

## Candidate provenance

The release source-identity tool validates full forty-character Git SHAs and exact macOS release tag syntax. It checks ancestry and walks first-parent history to detect newer releasable inputs; a net diff alone would miss an intervening change that was later reverted. Candidate artifact, source, qualification and promotion identities must remain correlated through delivery.

The [release guide](../operations/releases.md) describes promotion and rollback. Real signed/notarized acceptance remains one of the [open qualification obligations](../../INSTRUCTIONS.md#unresolved-commitments).

## Assets and authored approval

The exact owner-supplied asset hashes, approved uses, shipping transformations and rejected grass-icon experiment are in [Asset provenance](../../INSTRUCTIONS.md#asset-provenance). Those are authored provenance facts, not code Claims or a new third-party license. Preserve the repository licenses and the vendored libwebp record in their required locations.

## Source evidence

- [desktop/macos/run.sh](../../../desktop/macos/run.sh#L435-L509)
- [desktop/macos/tests/test-run-signing-identity.sh](../../../desktop/macos/tests/test-run-signing-identity.sh)
- [.github/scripts/desktop-release-source-identity.py](../../../.github/scripts/desktop-release-source-identity.py#L12-L132)
- [desktop/macos/scripts/prepare-desktop-bundle-native-deps.sh](../../../desktop/macos/scripts/prepare-desktop-bundle-native-deps.sh)
- [desktop/macos/tests/test-prepare-desktop-bundle-native-deps.sh](../../../desktop/macos/tests/test-prepare-desktop-bundle-native-deps.sh)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
