---
type: Codebase guide
title: Qualification and open obligations
description: Explain evidence gates and existing harnesses; link authored open commitments without claiming qualification.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-3b73c81eefcd909208670ce0
    resource: repo://.github/checks-manifest.yaml
  - id: openwiki-source-19d91df3181544492a10253e
    resource: repo://.github/scripts/check_policy_change_review.py
  - id: openwiki-source-16d213dfcc8beae17f8096fe
    resource: repo://.github/scripts/prepare_codebase_map_check.py
  - id: openwiki-source-2086e730056d335da93dacd1
    resource: repo://.github/scripts/publish_guardrail_pulse.py
  - id: openwiki-source-54aa0818a69c7dc32f892aa8
    resource: repo://.github/scripts/run_checks.py
  - id: openwiki-source-6fc056d3bbb591906ac1f888
    resource: repo://.github/scripts/test_check_policy_change_review.py
  - id: openwiki-source-54e240f9ab6a71a2b90a1c33
    resource: repo://.github/workflows/guardrail-baseline-pulse.yml
  - id: openwiki-source-bcd362fbbe23cf1c0d8329bd
    resource: repo://desktop/macos/scripts/check-gauntlet-evidence-at-head.sh
  - id: openwiki-source-275b2622aa4001b497c886f2
    resource: repo://desktop/macos/tests/test-check-gauntlet-evidence-at-head.sh
  - id: openwiki-source-cadbf0c250f5afb51126591d
    resource: repo://tools/codebase-map/package.json
  - id: openwiki-source-fa2531a1c23faf0486307e94
    resource: repo://tools/codebase-map/tests/browser/viewer.spec.ts
generated: { by: "codex", at: "2026-09-24T12:25:42.469Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-24T12:25:42.469Z
---
# Qualification and open obligations

Qualification binds evidence to the exact source and artifact being accepted. The continuity evidence gate reads local harness manifests and verifies their full Git identity, green completion, expected rows and privacy-safe evidence. A convenient historical run or a successful fake-provider response is not a substitute for a missing real-provider row.

## Evidence boundaries

| Evidence | What it can establish |
| --- | --- |
| Component and contract tests | Controlled behavior of the checked-out implementation |
| Hermetic E2E | Wiring and lifecycle under deterministic local dependencies |
| Named-bundle manifests | Behavior of the actual identified test binary |
| Natural PTT/provider continuity | Physical capture and retained live-provider behavior |
| Deployment/release records | Exact serving source or signed artifact and operational transitions |

`check-gauntlet-evidence-at-head.sh` validates source identity and rejects incomplete, dirty or privacy-unsafe records. Its stricter final-closeout requirements are branch-sensitive; do not infer universal green coverage from a nonblocking branch invocation. The underlying continuity harness and source-evidence tests own the concrete row contract.

The shared deterministic manifest runs checks in named local and CI lanes. Repo Checks separates PR metadata preflight from code-change detection and Hygiene, and prepares the dependencies required by its selected checks. Pre-push retains the shared PR preflight and the component/evidence checks for the actual pushed diff. The Mermaid map supports source navigation; it does not certify product acceptance.

The [codebase map viewer](codebase-map.md) adds a diff-selected build and browser check in both lanes. Its Chromium tests exercise the complete canonical diagram, navigation, resize/fullscreen, malformed-input recovery and commit links against the static export. CI provisions its locked packages and browser through the same manifest selection. A passing viewer check establishes rendering and source-loading behavior; semantic map accuracy and the live Vercel Git connection/deployment still need their own review and observation.

## Policy-change disclosure

The shared manifest selects `policy-change-review` in both PR lanes. The guard examines instruction files, Conductor settings, workflow/action definitions, check implementations and preflight/hook entrypoints. It combines a committed diff with supplied local changed paths and, for local HEAD inputs, a worktree diff. Rename detection is disabled so moving or deleting an instruction does not hide its old path.

Sensitive changes require a visible `## Policy changes` section with nonempty `Policy-Source`, `Policy-Scope`, `Policy-Effect` and `Policy-Qualifications` fields. Commented templates, fenced examples and placeholder-only fields do not satisfy it. Unrelated application changes return successfully without a policy declaration. The check requires PR metadata, so post-merge runs exclude it through the existing metadata-check category.

This is a disclosure check, not authentication of the user's request or verification of live GitHub settings. Reviewers still compare the original request, retained qualifications and actual diff. The [authored authority rules](../../INSTRUCTIONS.md#instruction-authority-and-policy-changes) and [incident review](../../../docs/engineering/policy-provenance-review.md) explain that boundary. Disposable-repository tests exercise instruction migration, dirty files, staged and committed renames, enforcement edits and manifest selection.

## Weekly guardrail report

The weekly/manual Guardrail baseline pulse remains separate from the product map. Its main-only, serialized workflow uses a dedicated App token from the `guardrail-pulse-publisher` environment to publish history; issue reporting uses `GITHUB_TOKEN`.

The publisher fetches fresh main and accepts only one append-only change to `.github/guardrail-pulse-history.jsonl`, containing one valid report row. It rejects unrelated files, modified prefixes, deletions, renames, mode changes, extra commits and dirty-checkout output. A competing push causes a fresh fetch, regeneration and validation, with at most three attempts and no force-push.

The [authored delivery rules](../../INSTRUCTIONS.md#delivery-guidance) preserve the Intentive Guardrail Pulse App and its narrowly intended report access. Repository code does not establish the live GitHub ruleset or credential state; verify those separately when changing publication settings.

## Open authored commitments

[Unresolved commitments](../../INSTRUCTIONS.md#unresolved-commitments) summarize BL-001, BL-002 and BL-003 and link their complete dated records and exit evidence in Git history. Provider availability did not close final continuity qualification. An initial read-only infrastructure inventory did not complete classification, recovery or rollback acceptance. Broad local evidence did not close final-source hosted verification.

The accepted IR decisions name their original owner/evidence groups. The signed-release and billing handoffs remain distinct. This page explains the mechanics; it does not mark any of those obligations complete or replace their original per-slice acceptance records.

The [authored REP acceptance requirements](../../INSTRUCTIONS.md#accepted-requirements) retain classified source-residue searches and retained-owner behavioral evidence, together with diff hygiene, `make preflight` and PR preflight. Migrated wiki checks cover documentation; they do not replace those source-cleanup or per-slice obligations.

Use [desktop E2E](../testing/desktop-e2e.md) to select a test surface and [releases](releases.md) to understand candidate delivery. Keep commands, source SHA, artifact identity and outcomes together when reporting evidence.

## Source evidence

- [desktop/macos/scripts/check-gauntlet-evidence-at-head.sh](../../../desktop/macos/scripts/check-gauntlet-evidence-at-head.sh)
- [desktop/macos/tests/test-check-gauntlet-evidence-at-head.sh](../../../desktop/macos/tests/test-check-gauntlet-evidence-at-head.sh)
- [.github/checks-manifest.yaml](../../../.github/checks-manifest.yaml)
- [Pushed-candidate checks](../../../scripts/pre-push)
- [Weekly report workflow](../../../.github/workflows/guardrail-baseline-pulse.yml)
- [Append-only report publisher](../../../.github/scripts/publish_guardrail_pulse.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
