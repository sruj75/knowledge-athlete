---
type: Codebase guide
title: Qualification and open obligations
description: Explain evidence gates and existing harnesses; link authored open commitments without claiming qualification.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-3b73c81eefcd909208670ce0
    resource: repo://.github/checks-manifest.yaml
  - id: openwiki-source-525cd1c034c50a5bed667e46
    resource: repo://.github/workflows/repo-checks.yml
  - id: openwiki-source-bcd362fbbe23cf1c0d8329bd
    resource: repo://desktop/macos/scripts/check-gauntlet-evidence-at-head.sh
  - id: openwiki-source-275b2622aa4001b497c886f2
    resource: repo://desktop/macos/tests/test-check-gauntlet-evidence-at-head.sh
  - id: openwiki-source-f6dfb300ae1aff0b8b4f105b
    resource: repo://scripts/pre-push
generated: { by: "codex", at: "2026-09-18T08:23:57.133Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-18T08:23:57.133Z
---
# Qualification and open obligations

Qualification binds evidence to the exact source and artifact being accepted. The continuity evidence gate reads local harness manifests and verifies their full Git identity, green completion, expected rows and privacy-safe evidence. A convenient historical run or a successful fake-provider response is not a substitute for a missing real-provider row.

## Evidence boundaries

| Evidence | What it can establish |
| --- | --- |
| Component and contract tests | Controlled behavior of the checked-out implementation |
| Hermetic E2E | Wiring and lifecycle under deterministic local dependencies |
| Committed UA freshness | Matching analyzed inputs, fingerprints and structurally valid graph in the candidate commit |
| Named-bundle manifests | Behavior of the actual identified test binary |
| Natural PTT/provider continuity | Physical capture and retained live-provider behavior |
| Deployment/release records | Exact serving source or signed artifact and operational transitions |

`check-gauntlet-evidence-at-head.sh` validates source identity and rejects incomplete, dirty or privacy-unsafe records. Its stricter final-closeout requirements are branch-sensitive; do not infer universal green coverage from a nonblocking branch invocation. The underlying continuity harness and source-evidence tests own the concrete row contract.

The shared deterministic manifest selects `ua-graph-freshness` in both local and CI lanes, including report-only or empty diffs. Pre-push checks the actual pushed commit IDs, and the independent `UA Graph Freshness` job runs for each supported Repo Checks event. It has no dependency on the conditional Hygiene job. Scanner installation is an explicit preparation step; checking the committed content makes no model calls. This proves graph handoff evidence, not the semantic accuracy of every generated explanation or product acceptance. See [the workspace handoff guide](understand-anything.md) for failure handling and the separate GitHub activation prerequisite.

## Open authored commitments

[Unresolved commitments](../../INSTRUCTIONS.md#unresolved-commitments) summarize BL-001, BL-002 and BL-003 and link their complete dated records and exit evidence in Git history. Provider availability did not close final continuity qualification. An initial read-only infrastructure inventory did not complete classification, recovery or rollback acceptance. Broad local evidence did not close final-source hosted verification.

The accepted IR decisions name their original owner/evidence groups. The signed-release and billing handoffs remain distinct. This page explains the mechanics; it does not mark any of those obligations complete or replace their original per-slice acceptance records.

The [authored REP acceptance requirements](../../INSTRUCTIONS.md#accepted-requirements) retain classified source-residue searches and retained-owner behavioral evidence, together with diff hygiene, `make preflight` and PR preflight. Migrated wiki checks cover documentation; they do not replace those source-cleanup or per-slice obligations.

Use [desktop E2E](../testing/desktop-e2e.md) to select a test surface and [releases](releases.md) to understand candidate delivery. Keep commands, source SHA, artifact identity and outcomes together when reporting evidence.

## Source evidence

- [desktop/macos/scripts/check-gauntlet-evidence-at-head.sh](../../../desktop/macos/scripts/check-gauntlet-evidence-at-head.sh)
- [desktop/macos/tests/test-check-gauntlet-evidence-at-head.sh](../../../desktop/macos/tests/test-check-gauntlet-evidence-at-head.sh)
- [.github/checks-manifest.yaml](../../../.github/checks-manifest.yaml)
- [UA status job](../../../.github/workflows/repo-checks.yml#L25-L45)
- [Pushed-candidate checks](../../../scripts/pre-push#L190-L218)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
