---
type: Codebase guide
title: Tests and repository contracts
description: Explain hermetic test runners, workflow registry, documentation gates and shared manifest.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-5ecd22a8e92cec9cc695e88c
    resource: repo://.github/scripts/check_package_architecture_maps.py
  - id: openwiki-source-7530c7eab9bc82ec52ca4f19
    resource: repo://.github/scripts/test_check_package_architecture_maps.py
  - id: openwiki-source-562818e69f546fe1d78b3597
    resource: repo://backend/scripts/select_backend_unit_tests.py
  - id: openwiki-source-ab35a4b0a65731bead12639d
    resource: repo://backend/test.sh
  - id: openwiki-source-ef65c2f64080826662c12d53
    resource: repo://backend/testing/import_isolation.py
  - id: openwiki-source-2a54d9d29c8899e4e49d806c
    resource: repo://desktop/macos/test.sh
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
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

## Source evidence

- [backend/test.sh](../../../backend/test.sh#L35-L105)
- [backend/scripts/select_backend_unit_tests.py](../../../backend/scripts/select_backend_unit_tests.py)
- [desktop/macos/test.sh](../../../desktop/macos/test.sh)
- [.github/scripts/check_package_architecture_maps.py](../../../.github/scripts/check_package_architecture_maps.py)
- [.github/scripts/test_check_package_architecture_maps.py](../../../.github/scripts/test_check_package_architecture_maps.py)
- [backend/testing/import_isolation.py](../../../backend/testing/import_isolation.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
