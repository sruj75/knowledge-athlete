---
type: Codebase guide
title: Desktop end-to-end verification
description: Explain named bundles, flow inventory, tiers, source identity and physical versus synthetic evidence.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T14:14:00.034Z
sources:
  - id: openwiki-source-7b7bd425584dcecda56e70ae
    resource: repo://desktop/macos/scripts/check-e2e-flow-coverage.py
  - id: openwiki-source-1d70e9d198b8f1602d970413
    resource: repo://desktop/macos/scripts/desktop-core-harness.sh
  - id: openwiki-source-e05dc09d548050f1b61f3c9a
    resource: repo://desktop/macos/scripts/omi-ctl
  - id: openwiki-source-2a54d9d29c8899e4e49d806c
    resource: repo://desktop/macos/test.sh
generated: { by: "codex", at: "2026-09-15T14:14:00.034Z" }
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
