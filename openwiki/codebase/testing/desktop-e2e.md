---
type: Codebase guide
title: Desktop end-to-end verification
description: Explain named bundles, flow inventory, tiers, source identity and physical versus synthetic evidence.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-7b7bd425584dcecda56e70ae
    resource: repo://desktop/macos/scripts/check-e2e-flow-coverage.py
  - id: openwiki-source-1d70e9d198b8f1602d970413
    resource: repo://desktop/macos/scripts/desktop-core-harness.sh
  - id: openwiki-source-2a54d9d29c8899e4e49d806c
    resource: repo://desktop/macos/test.sh
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
---
# Desktop end-to-end verification

Desktop E2E uses named development bundles and a checked-in flow inventory. The harness records which source and binary it exercised. [Desktop testing guidance](../../INSTRUCTIONS.md#desktop-testing-guidance) preserves the detailed tier commands and operating rules.

## Evidence selection

The desktop-core harness supports local flow lint/smoke, named-bundle automation, offline service-backed flows and a fault suite. Its command help lists the accepted tier names and bundle options. The normal named bundle and fault bundle are distinct; choosing the fault suite must not accidentally target a stale ordinary development app.

Before higher-tier runs, health checks bind the bundle's `sourceGitSHA` and clean-source status to the expected repository state. Offline service-backed acceptance also checks the harness provider-mode sentinel. These checks prevent a stale binary or live-service stack from being labeled as current hermetic evidence.

## Flow ownership

Flow YAML lives beside the E2E feature inventory, and `check-e2e-flow-coverage.py --strict` is called by the desktop runner. Keep a behavior's automation hooks, flow and owning tests aligned. The Markdown PTT shadow-state census is an executable test fixture and remains in its original test location; it is not general documentation to regenerate.

Physical microphone capture, system permissions, visible UI transitions and real-provider recall need their own evidence. A synthetic terminal-success record proves a controlled lifecycle, not that a person spoke and the model remembered it. The [qualification guide](../operations/qualification.md) links the open one-final-SHA obligations.

## Safe execution

Use only named test bundles and the prescribed local harness. Preserve manifests and logs in private local evidence locations, never provider tokens or raw personal content in the wiki. Report the exact commands, source identity, mode and outcome; do not convert a skipped or blocked tier into a pass.

## Source evidence

- [desktop/macos/scripts/desktop-core-harness.sh](../../../desktop/macos/scripts/desktop-core-harness.sh)
- [desktop/macos/test.sh](../../../desktop/macos/test.sh#L1-L21)
- [desktop/macos/scripts/check-e2e-flow-coverage.py](../../../desktop/macos/scripts/check-e2e-flow-coverage.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
