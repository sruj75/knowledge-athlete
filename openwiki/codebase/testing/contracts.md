---
type: Codebase guide
title: Tests and repository contracts
description: Explain hermetic test runners, workflow registry, documentation gates and shared manifest.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-3c5fb0f9d251edf233879d40
    resource: repo://.github/actions/release-eligibility/action.yml
  - id: openwiki-source-5ecd22a8e92cec9cc695e88c
    resource: repo://.github/scripts/check_package_architecture_maps.py
  - id: openwiki-source-23a07ed15c560c1126283036
    resource: repo://.github/scripts/check-desktop-changelog.py
  - id: openwiki-source-e3f9a19b526001fa9705952b
    resource: repo://.github/scripts/pr_preflight.py
  - id: openwiki-source-ecca44aa084e91aded2c105f
    resource: repo://.github/scripts/test_backend_candidate_probe.py
  - id: openwiki-source-7530c7eab9bc82ec52ca4f19
    resource: repo://.github/scripts/test_check_package_architecture_maps.py
  - id: openwiki-source-324e72713e22c9e2553c7392
    resource: repo://.github/scripts/test_desktop_changelog.py
  - id: openwiki-source-525cd1c034c50a5bed667e46
    resource: repo://.github/workflows/repo-checks.yml
  - id: openwiki-source-562818e69f546fe1d78b3597
    resource: repo://backend/scripts/select_backend_unit_tests.py
  - id: openwiki-source-ab35a4b0a65731bead12639d
    resource: repo://backend/test.sh
  - id: openwiki-source-ef65c2f64080826662c12d53
    resource: repo://backend/testing/import_isolation.py
  - id: openwiki-source-8c64fead8c8caad37dea1f70
    resource: repo://backend/tests/unit/test_desktop_conversation.py
  - id: openwiki-source-8c40c7f2c568311d665a5ad7
    resource: repo://backend/tests/unit/test_desktop_realtime.py
  - id: openwiki-source-533d858e0a14018e47b7cc2b
    resource: repo://backend/tests/unit/test_desktop_tts_updates.py
  - id: openwiki-source-3ed14971b31729972bb6d50c
    resource: repo://backend/tests/unit/test_langfuse_observability.py
  - id: openwiki-source-44ad4321bfb7e29f77339266
    resource: repo://backend/tests/unit/test_public_compute_access_topology.py
  - id: openwiki-source-19de91ecaf934d5786e88f8b
    resource: repo://backend/tests/unit/test_public_compute_access.py
  - id: openwiki-source-276b6bd5d516d3e8277c2462
    resource: repo://backend/tests/unit/test_voice_provider_probe.py
  - id: openwiki-source-3980081a58a01382ad067c02
    resource: repo://desktop/macos/agent/tests/conversation-storage.test.ts
  - id: openwiki-source-72dffde2f3f4878ee649e458
    resource: repo://desktop/macos/Desktop/Tests/ConversationAudioLevelTests.swift
  - id: openwiki-source-523ecad9a8c0ea5762adfd5c
    resource: repo://desktop/macos/Desktop/Tests/ConversationDiagnosticLedgerTests.swift
  - id: openwiki-source-e258a11230cac85403c011e3
    resource: repo://desktop/macos/Desktop/Tests/ConversationLifecycleTests.swift
  - id: openwiki-source-16d471086ed15fce2dbb4570
    resource: repo://desktop/macos/Desktop/Tests/ConversationMeterDeliveryTests.swift
  - id: openwiki-source-3e930575818dad6d1f40ea0b
    resource: repo://desktop/macos/Desktop/Tests/ConversationOutputAdmissionTests.swift
  - id: openwiki-source-aac74c2c79bc006e52c8058a
    resource: repo://desktop/macos/Desktop/Tests/ConversationPresentationPreviewTests.swift
  - id: openwiki-source-3a40047b453ba7a3c4a3cd28
    resource: repo://desktop/macos/Desktop/Tests/ConversationPresentationTests.swift
  - id: openwiki-source-8e7da6716cdbf6513a389519
    resource: repo://desktop/macos/Desktop/Tests/SupervisorDiagnosticMetricsTests.swift
  - id: openwiki-source-ec2aa1ff3fb10c3cb271e0b4
    resource: repo://desktop/macos/Desktop/Tests/SupervisorServiceTests.swift
  - id: openwiki-source-38a1b3c7a8acf2ceea409825
    resource: repo://desktop/macos/e2e/flows/supervisor-conversation.yaml
  - id: openwiki-source-2a54d9d29c8899e4e49d806c
    resource: repo://desktop/macos/test.sh
generated: { by: "codex", at: "2026-10-15T08:50:15.427Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-10-15T15:18:48.302Z
---
# Tests and repository contracts

The repository has component test runners and a shared deterministic governance manifest. They answer different questions: tests exercise behavior, static tripwires detect forbidden structures, and preflight selects the checks relevant to the diff. A static source assertion is not proof that a live provider or GUI path worked.

## Component tests

`backend/test.sh` selects discovered unit-test files, supplies hermetic credentials, excludes integration/slow markers by default, and normally isolates files in separate pytest processes. Its local CPU-duration ratchet can make a run nonzero even when assertions pass; report that outcome accurately. The workflow-contract registry maps high-risk workflows to owned sources and tests so changes select their relevant coverage.

For dependency isolation, patch lazy-held clients at their owning seam. The direct-A stream fixture overrides the lazy Langfuse client getter so inherited developer credentials cannot initialize an external exporter. Separate observability contract tests still exercise generation lifecycle and export policy. When import-time substitution is unavoidable, `backend/testing/import_isolation.py` provides a scoped module-stubbing context that restores both module entries and parent attributes. Do not introduce module-level fake clients that leak into neighboring tests.

`desktop/macos/test.sh` discovers shell launcher tests, verifies E2E flow coverage, runs the desktop backend tests, then invokes Swift suites in per-suite process isolation. The retained Node storage package has its own Vitest runner and TypeScript build; build before its stdio tests. The desktop backend selection includes authenticated conversation and Supervisor contracts. The app's shared local databases and preferences explain why one combined Swift process is not equivalent to the official runner.

## Conversational seams

The conversation lifecycle/audio seam covers listening-only silence, completion supersession, automatic Live input, bounded preconnection audio, interruption fences and accepted-before-playback admission. Observation-to-guidance tests cover one inference/latest pending state, shared event/quiet budgets, fresh frames, context expiry, independent inputs and account isolation. Backend contracts cover auth, prompt receipts, fixed capabilities, bounded multimodal payloads and private-content exclusion. Journal tests preserve seeded-history reopen, generation/idempotency, revision order and actual delivery metadata.

Presentation tests exercise opening/listening/thinking/speaking projection, quiet open intervals and interruption priority independently of per-answer capture ownership. Audio tests use known PCM/render buffers and real meter delivery to check RMS, ambient isolation, stale receipts and output-only interruption. Common-opening tests cover reveal ordering, snooze admission and explicit hide. Preview tests use the real mapper/meter with a substituted operating-system window, including safe cleanup when user content or a real conversation takes ownership. These tests do not start physical audio hardware.

`ConversationDiagnosticLedgerTests` covers owner/generation input fencing, terminal deduplication, bounded metadata and reauthentication purge. `SupervisorDiagnosticMetricsTests` checks idempotent receipts and aggregate timings; service tests verify read-only snapshots, reset isolation and rejection of old-session completions. Offline Live/TTS tests install failing provider-client seams and require the unavailable response before provider calls or TTS metering.

Retired Tasks and execution expectations must become rejection or historical-preservation coverage, not skipped tests or reactivated features. The manual flow separately requires provider silent append, physical speaker/headphone/Bluetooth interruption and an actual eight-hour soak. A passing source or fake-clock test cannot satisfy those rows. They describe the full manual coverage; the [authored initial launch scope](../../INSTRUCTIONS.md#product-constraints) does not add the extended route matrix or soak as gates for the short owner pilot.

### Release-probe request and stream contracts

The stdlib-only candidate-probe suite drives the actual helper with bounded HTTP/SSE fixtures and checks current route/field declarations against repository source. Its AST checks are structural tripwires. The backend conversation suite separately passes real probe requests through `ConversationRespondRequest`, including a 4,001-character first answer carried into a 4,000-character historical turn while evidence keeps the full answer count. This distinguishes current schema behavior from two mutually consistent mocks.

Voice-probe tests mount the current conversation-session and realtime routers with synthetic identity and prompt/provider seams. They verify one conversation ID and exact prompt receipt through bootstrap, mint and Live setup; malformed or changed receipts fail before provider connection, and credentials/prompt content stay out of output. Socket framing and failure bounds remain separately covered. These tests establish hermetic request/transport behavior, not paid-provider availability or physical voice acceptance.

## Documentation contracts

The existing reference checker covers wiki Markdown links and the remaining entrypoints, including encoded source paths and native repository URIs. The agent-size ratchet applies to the root AGENTS and CLAUDE entrypoints; detailed rules belong in the preserved brief.

Oversized source packages are mapped through a factual wiki page's standard `resource: repo://<package-path>` metadata. Structural indexes, a body's incidental URI mention, and nested evidence resources do not satisfy ownership. Existing baseline warnings and growth failures remain part of the same package ratchet. OpenWiki independently owns page format, Claims and finalization.

`make preflight` runs the shared local lane used alongside CI. Update tests and both manifest lanes together when a contract changes. See [desktop E2E](desktop-e2e.md) for physical-path evidence and [development](../operations/development.md) for commands.

## Changelog enforcement on main

PR preflight, main-push Hygiene and Release Eligibility use the shared changelog checker. The `no-changelog-needed` PR label exempts the PR check; main-push checks operate on the committed diff without that label. Internal tools such as the source-layout checker are exempt in the checker itself, so the same classification applies after merge.

`Package.swift` normally requires a changelog. The checker recognizes one narrow documentation cleanup: the entire manifest edit only removes Markdown entries from plain `exclude` arrays, and the referenced documents are deleted in the same Git comparison. Dependency, resource, Swift-exclusion and other package edits remain gated, as do mixed changes to product source. Unrecognized syntax also remains gated. The regression test runs the actual CLI over temporary Git commits, covering the documentation migration and cases that must still fail.

Public-compute regressions exercise more than five distinct verified identities, rejected HTTP/WebSocket credentials, hosted synthetic-token denial, retained account operations and mounted-route authentication topology. Live mint tests exercise allowed issuance, burst/daily rejection and unavailable limiter storage before provider transport. These are hermetic seam checks, not real Google sign-in or funded voice acceptance.

## Source evidence

- [Public compute authentication and quota regressions](../../../backend/tests/unit/test_public_compute_access.py)
- [Mounted-route authentication topology](../../../backend/tests/unit/test_public_compute_access_topology.py)
- [Dedicated tracing contracts](../../../backend/tests/unit/test_langfuse_observability.py)

- [Portable candidate-probe fixtures](../../../.github/scripts/test_backend_candidate_probe.py)
- [Conversation request-model regression](../../../backend/tests/unit/test_desktop_conversation.py#L222-L281)
- [Prompt-bound voice probe tests](../../../backend/tests/unit/test_voice_provider_probe.py)

- [backend/test.sh](../../../backend/test.sh#L35-L105)
- [backend/scripts/select_backend_unit_tests.py](../../../backend/scripts/select_backend_unit_tests.py)
- [desktop/macos/test.sh](../../../desktop/macos/test.sh)
- [.github/scripts/check_package_architecture_maps.py](../../../.github/scripts/check_package_architecture_maps.py)
- [.github/scripts/test_check_package_architecture_maps.py](../../../.github/scripts/test_check_package_architecture_maps.py)
- [backend/testing/import_isolation.py](../../../backend/testing/import_isolation.py)
- [.github/scripts/check-desktop-changelog.py](../../../.github/scripts/check-desktop-changelog.py)
- [.github/scripts/test_desktop_changelog.py](../../../.github/scripts/test_desktop_changelog.py)
- [.github/workflows/repo-checks.yml](../../../.github/workflows/repo-checks.yml)
- [.github/actions/release-eligibility/action.yml](../../../.github/actions/release-eligibility/action.yml)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
