---
type: Codebase guide
title: Tests and repository contracts
description: Explain hermetic test runners, workflow registry, documentation gates and shared manifest.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T16:15:28.553Z
sources:
  - id: openwiki-source-3c5fb0f9d251edf233879d40
    resource: repo://.github/actions/release-eligibility/action.yml
  - id: openwiki-source-5ecd22a8e92cec9cc695e88c
    resource: repo://.github/scripts/check_package_architecture_maps.py
  - id: openwiki-source-23a07ed15c560c1126283036
    resource: repo://.github/scripts/check-desktop-changelog.py
  - id: openwiki-source-e3f9a19b526001fa9705952b
    resource: repo://.github/scripts/pr_preflight.py
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
  - id: openwiki-source-2a54d9d29c8899e4e49d806c
    resource: repo://desktop/macos/test.sh
generated: { by: "codex", at: "2026-09-15T16:15:28.553Z" }
---
# Tests and repository contracts

The repository has component test runners and a shared deterministic governance manifest. They answer different questions: tests exercise behavior, static tripwires detect forbidden structures, and preflight selects the checks relevant to the diff. A static source assertion is not proof that a live provider or GUI path worked.

## Component tests

`backend/test.sh` selects discovered unit-test files, supplies hermetic credentials, excludes integration/slow markers by default, and normally isolates files in separate pytest processes. Its local CPU-duration ratchet can make a run nonzero even when assertions pass; report that outcome accurately. The workflow-contract registry maps high-risk workflows to owned sources and tests so changes select their relevant coverage.

For dependency isolation, patch lazy-held clients at their owning seam. When import-time substitution is unavoidable, `backend/testing/import_isolation.py` provides a scoped module-stubbing context that restores both module entries and parent attributes. Do not introduce module-level fake clients that leak into neighboring tests.

`desktop/macos/test.sh` discovers shell launcher tests, verifies E2E flow coverage, runs the desktop backend tests, then invokes Swift suites in per-suite process isolation. The Node agent package has its own Vitest runner and TypeScript build. The app's shared local databases and preferences explain why one combined Swift process is not equivalent to the official runner.

## Documentation contracts

The existing reference checker covers wiki Markdown links and the remaining entrypoints, including encoded source paths and native repository URIs. The agent-size ratchet applies to the root AGENTS and CLAUDE entrypoints; detailed rules belong in the preserved brief.

Oversized source packages are mapped through a factual wiki page's standard `resource: repo://<package-path>` metadata. Structural indexes, a body's incidental URI mention, and nested evidence resources do not satisfy ownership. Existing baseline warnings and growth failures remain part of the same package ratchet. OpenWiki independently owns page format, Claims and finalization.

`make preflight` runs the shared local lane used alongside CI. Update tests and both manifest lanes together when a contract changes. See [desktop E2E](desktop-e2e.md) for physical-path evidence and [development](../operations/development.md) for commands.

## Changelog enforcement on main

PR preflight, main-push Hygiene and Release Eligibility use the shared changelog checker. The `no-changelog-needed` PR label exempts the PR check; main-push checks operate on the committed diff without that label. Internal tools such as the source-layout checker are exempt in the checker itself, so the same classification applies after merge.

`Package.swift` normally requires a changelog. The checker recognizes one narrow documentation cleanup: the entire manifest edit only removes Markdown entries from plain `exclude` arrays, and the referenced documents are deleted in the same Git comparison. Dependency, resource, Swift-exclusion and other package edits remain gated, as do mixed changes to product source. Unrecognized syntax also remains gated. The regression test runs the actual CLI over temporary Git commits, covering the documentation migration and cases that must still fail.

## Source evidence

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
