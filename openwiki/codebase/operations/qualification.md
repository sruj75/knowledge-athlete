---
type: Codebase guide
title: Qualification and open obligations
description: Explain evidence gates and existing harnesses; link authored open commitments without claiming qualification.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-3b73c81eefcd909208670ce0
    resource: repo://.github/checks-manifest.yaml
  - id: openwiki-source-a2e9f488324574616875f69a
    resource: repo://.github/failure-classes/FC-provider-http-error-format.json
  - id: openwiki-source-b1a0c4c7878c2939e6b73152
    resource: repo://.github/failure-classes/FC-public-web-routing-parity.json
  - id: openwiki-source-6d3dedd47b97bc8466968f9a
    resource: repo://.github/failure-classes/FC-selection-overlay-layout-loop.json
  - id: openwiki-source-7c8fa8df1fbcb76046ab158a
    resource: repo://.github/failure-classes/FC-split-mutation-authority.json
  - id: openwiki-source-4614724a189e4cc9cf1a0f57
    resource: repo://.github/failure-classes/FC-surface-tool-authority-projection.json
  - id: openwiki-source-19d91df3181544492a10253e
    resource: repo://.github/scripts/check_policy_change_review.py
  - id: openwiki-source-2086e730056d335da93dacd1
    resource: repo://.github/scripts/publish_guardrail_pulse.py
  - id: openwiki-source-54aa0818a69c7dc32f892aa8
    resource: repo://.github/scripts/run_checks.py
  - id: openwiki-source-ecca44aa084e91aded2c105f
    resource: repo://.github/scripts/test_backend_candidate_probe.py
  - id: openwiki-source-6fc056d3bbb591906ac1f888
    resource: repo://.github/scripts/test_check_policy_change_review.py
  - id: openwiki-source-54e240f9ab6a71a2b90a1c33
    resource: repo://.github/workflows/guardrail-baseline-pulse.yml
  - id: openwiki-source-8c64fead8c8caad37dea1f70
    resource: repo://backend/tests/unit/test_desktop_conversation.py
  - id: openwiki-source-276b6bd5d516d3e8277c2462
    resource: repo://backend/tests/unit/test_voice_provider_probe.py
  - id: openwiki-source-e762e0de342d9685ba91244f
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/AIEvaluationFeedbackView.swift
  - id: openwiki-source-e0ddaa9325c2b96bfacccfee
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/AIEvaluationReporter.swift
  - id: openwiki-source-21802c0cbbe5aeada371f269
    resource: repo://desktop/macos/Desktop/Sources/MainWindow/Components/ChatMessageMetadataRow.swift
  - id: openwiki-source-317262cd3f709b346ea8731c
    resource: repo://desktop/macos/Desktop/Tests/GeminiBackgroundRoutingTests.swift
  - id: openwiki-source-38a1b3c7a8acf2ceea409825
    resource: repo://desktop/macos/e2e/flows/supervisor-conversation.yaml
  - id: openwiki-source-fa2531a1c23faf0486307e94
    resource: repo://tools/codebase-map/tests/browser/viewer.spec.ts
generated: { by: "codex", at: "2026-10-15T15:18:48.302Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-10-15T15:18:48.302Z
---
# Qualification and open obligations

Qualification binds evidence to the exact source and artifact being accepted. Component tests, named offline launches, live-provider probes and human-heard conversation are separate evidence. The retired Pi/PTT continuity gauntlet is not an acceptance route for the new conversation architecture.

## Evidence boundaries

| Evidence | What it can establish |
| --- | --- |
| Component and contract tests | Controlled behavior of the checked-out implementation |
| Hermetic E2E | Wiring and lifecycle under deterministic local dependencies |
| Named-bundle manifests | Behavior of the actual identified test binary |
| Natural spoken conversation | Physical capture and retained live-provider behavior |
| Deployment/release records | Exact serving source or signed artifact and operational transitions |

Record the full source SHA, dirty-state qualification, bundle identity, backend fingerprint and privacy-safe observations for a named run. An offline startup or returned PCM cannot establish what a person heard.

The shared deterministic manifest runs checks in named local and CI lanes. Repo Checks separates PR metadata preflight from code-change detection and Hygiene, and prepares the dependencies required by its selected checks. Pre-push retains the shared PR preflight and the component/evidence checks for the actual pushed diff. The Mermaid map supports source navigation; it does not certify product acceptance.

The [codebase map viewer](codebase-map.md) adds a diff-selected build and browser check in both lanes. Its Chromium tests account for all six areas, 37 nodes and 57 connections across generated local views, including dense and internally disconnected areas. They exercise explicit click/keyboard entry, full labels at natural size, native wheel/touch scrolling without diagram zoom, mouse dragging, remembered positions, cached local flows, fixed geographic regions, connection inspection and destination focus, resize/fullscreen, reduced motion, parse/layout recovery and commit links against the static export. Recovery includes a local render failure, retained retry when reselecting that area, and a successful retry. Spatial tests verify deterministic geographic projection and non-overlap. CI provisions its locked packages and browser through the same manifest selection. A passing viewer check establishes rendering and source-loading behavior; semantic map accuracy and the live Vercel Git connection/deployment still need their own review and observation.

## Release-probe regression evidence

The portable candidate-probe fixtures exercise the executable helper's conversation bootstrap, pinned receipt, two typed SSE responses, terminal usage, stream bounds and redacted evidence. Their source-contract tripwires check current route and field declarations; real request-model coverage lives in the backend conversation tests, including a long first answer carried into bounded follow-up history. The voice-probe tests mount the current conversation-session and realtime routers with synthetic authentication, then substitute provider transport to check receipt reuse, Live setup and failure/redaction paths. These hermetic tests do not establish funded provider availability, actual speech or silent B guidance.

Failure-class metadata points to retained guard owners: HTTP status/detail coverage in `GeminiBackgroundRoutingTests`, selectable-content layout coverage in `ChatTimelineContinuityTests`, and canonical conversation-storage plus Memory ownership tests. Optional artifact references for fully retired routing/execution projections are absent; historical class identities and lifecycle records remain separate from those live coverage pointers. Registry validation checks declared artifact paths rather than proving the tests' behavioral scope.

## Conversational product qualification

The October 15 [authored launch scope](../../INSTRUCTIONS.md#product-constraints) starts with one real owner pilot, then the existing signed/notarized public DMG path. The full manual flow below retains broader audio-route and eight-hour coverage. Those extended checks remain unperformed qualifications; they are not added gates for the short owner pilot. Component or offline evidence cannot mark them complete.

The manual `supervisor-conversation` flow requires the exact named development bundle, authenticated Gemini and identified A/B instructions. Both user and B starts must support several replies without another shortcut press. Natural interruption must be heard and exercised on speakers, headphones and a supported Bluetooth route, with output stopped promptly and no self-trigger from A's playback.

Its startup check records the current physical route and requires an open Live connection with microphone availability and increasing processed PCM. A device exposing discrete multichannel capture must negotiate the same mono client format on both sides of voice processing. Confirm real speech changes the microphone waveform, admits a reply and produces an answer a person hears: PCM byte counts include silence. An opening error or silent conversion fails that hardware check. Synthetic converter tests cannot establish physical format negotiation or hearing.

Both starts must reveal the same original notch/chat surface, with blue opening glow, thinking, real microphone-level input waves and rendered-playback feedback. Check visibility between replies and after focus loss, rapid close/reopen, and clean conversation termination on explicit hide/snooze. The non-production `debug_bar_state` preview can render these phases with declared synthetic levels without starting capture or providers. Restore `idle` after preview; these images establish presentation only and cannot pass physical voice acceptance.

Verify explicit close, completion after final playback, newer activity superseding an old end signal and 60 seconds of available-input listening silence. Generation, playback and recovery pause the timer. Forced Live failure must preserve the same conversation and exact instruction receipt through multiple sticky batch exchanges with interruption and no Pi invocation.

Private guidance must wait through generation/playback and append at an idle boundary without unsolicited competing speech. Wire shape alone does not prove this provider behavior. Check partial transcript revisions, interrupted delivery, stale cue rejection, independent permissions, camera denial/disconnection and account/lock/sleep isolation. An unchanged scene must remain observable without duplicate archive/OCR writes.

Prompt pinning, telemetry privacy and quota retry behavior have separate assertions. Private guidance/images never enter history or observability, even in a selected evaluation session. Metadata receipts may correlate B decisions, actual delivery and feedback; old journal rows do not recreate in-memory feedback receipts after restart.

For local preparation, use the nonproduction `conversation_diagnostics_snapshot` and `supervisor_diagnostics_snapshot` actions described under [measurement boundaries](../integrations/telemetry.md#measurement-boundaries). The manual flow asks for step-bound A snapshots and B timing/budget observations. PCM counters include silence; a sealed playback drain still requires a completed outcome and human-heard evidence. B round-trip time is not provider-only latency. Offline fixtures and a capture-inactive snapshot smoke check require no paid inference and do not pass the physical/provider rows.

After provider and physical checks pass, perform the real eight-hour observation/resource soak, measuring CPU/memory, evaluation counts, exclusive tokens, capture/queue/provider/end-to-end timing, skipped work and quota gaps. Fake-clock scheduling profiles support comparison but establish neither real resource stability nor a production cost ceiling. Missing provider access, silent-append failure or natural-interruption failure remains an explicit qualification blocker.

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

- [.github/checks-manifest.yaml](../../../.github/checks-manifest.yaml)
- [Pushed-candidate checks](../../../scripts/pre-push)
- [Weekly report workflow](../../../.github/workflows/guardrail-baseline-pulse.yml)
- [Append-only report publisher](../../../.github/scripts/publish_guardrail_pulse.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
