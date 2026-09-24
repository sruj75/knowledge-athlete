---
type: Codebase guide
title: Development and wiki maintenance
description: Describe setup, component entrypoints, pinned development Node and native wiki update/resume lifecycle.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-311b902b81b9fbe111c8359f
    resource: repo://.conductor/settings.toml
  - id: openwiki-source-6445599f26c9a35886c1c46e
    resource: repo://.github/PULL_REQUEST_TEMPLATE.md
  - id: openwiki-source-19d91df3181544492a10253e
    resource: repo://.github/scripts/check_policy_change_review.py
  - id: openwiki-source-16d213dfcc8beae17f8096fe
    resource: repo://.github/scripts/prepare_codebase_map_check.py
  - id: openwiki-source-7c03237a6b57ffb3e526a51b
    resource: repo://.nvmrc
  - id: openwiki-source-8fe7ebf00619b8e43f932fa4
    resource: repo://backend/.python-version
  - id: openwiki-source-46e5675fdb0a0bc8e230444f
    resource: repo://backend/scripts/run-unit-ci.sh
  - id: openwiki-source-d5a3474b416677112c06b1cc
    resource: repo://backend/scripts/sync-python-deps.sh
  - id: openwiki-source-221ccd7dfd0766ec2939c6ec
    resource: repo://desktop/macos/agent/package.json
  - id: openwiki-source-fd55fa27de60ffa7dc0fc82e
    resource: repo://desktop/macos/agent/scripts/generate-tool-surfaces.mjs
  - id: openwiki-source-edc5df9f3e1eaa7250675764
    resource: repo://desktop/macos/agent/tests/runtime-stdio-contract.test.ts
  - id: openwiki-source-012f2c78e3b1446dfc35803f
    resource: repo://Makefile
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
  - id: openwiki-source-f00382734bf395713169fe50
    resource: repo://scripts/dev-harness/desktop-run-local.sh
  - id: openwiki-source-1a71f2c58cd0b293815e7b47
    resource: repo://scripts/dev-harness/tests/test_desktop_profile.py
  - id: openwiki-source-06044ee38485672b205128e8
    resource: repo://tools/codebase-map/lib/diagram-source.mjs
  - id: openwiki-source-cadbf0c250f5afb51126591d
    resource: repo://tools/codebase-map/package.json
  - id: openwiki-source-fa2531a1c23faf0486307e94
    resource: repo://tools/codebase-map/tests/browser/viewer.spec.ts
generated: { by: "codex", at: "2026-09-24T12:25:42.469Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-24T12:34:37.289Z
---
# Development and wiki maintenance

Start at the repository root. `make setup` refreshes the main baseline, installs worktree-safe Git hooks, and synchronizes the backend environment. It deliberately leaves the desktop runtime and app environment opt-in. The repository pins development Node to 22.22.0 in `.nvmrc`.

## Local commands

| Task | Command from repository root |
| --- | --- |
| Install prerequisites and hooks | `make setup` |
| Start local/offline services | `PROVIDER_MODE=offline make dev-up` |
| Initialize/check local configuration | `make dev-init`, then `make dev-check` |
| Launch a named local Mac | `make desktop-run-local DESKTOP_USER=alice DESKTOP_APP_NAME=omi-my-task` |
| Backend component tests | `backend/test.sh` |
| Desktop component tests | `desktop/macos/test.sh` |
| Node runtime checks | `cd desktop/macos/agent && npm run build && npm test` |
| Codebase map development | `npm --prefix tools/codebase-map run dev` |
| Codebase map build and browser checks | `npm --prefix tools/codebase-map run check` |
| Shared deterministic contract | `make preflight` |
| Build and smoke canonical image | `make runtime-image-smoke SERVICE=backend` |

The local launcher requires a valid workspace sentinel and a seeded synthetic user, validates the resolved local profile, then launches through `desktop/macos/run.sh`. The `DESKTOP_USER` selector chooses the synthetic account; `DESKTOP_APP_NAME` gives the bundle its own identity. Start the offline stack before launching. Read the [backend](../../INSTRUCTIONS.md#backend-guidance) and [desktop rules](../../INSTRUCTIONS.md#desktop-guidance) for the policy boundaries.

## Prerequisites and focused checks

The backend dependency synchronizer reads the exact Python version from `backend/.python-version` (currently 3.11.15), selects the platform lock, resolves/installs that interpreter through `uv`, and synchronizes its virtual environment. Refresh it with `bash backend/scripts/sync-python-deps.sh`. Intentional dependency changes use `backend/scripts/update-python-lock.sh`.

The local Mac launcher lists Xcode/`xcrun`, Python, `uv`, Node/npm and codesigning tools among its prerequisites; Cloudflare tooling is needed when its tunnel is selected. The emulator harness checks Node/npm, Java and its other local dependencies through `make dev-check`. Install the local libwebp dependency before packaging; [build/signing](../integrations/build-signing.md) explains that boundary.

From `desktop/macos/`, use `xcrun swift build -c debug --package-path Desktop` for compile-only feedback. Before a runtime/Chat/voice QA bundle, the compact contract command is `./scripts/agent-logic-harness.sh --cross-surface-smoke`. A compile is not a running app: use the named local launcher above, then `./scripts/omi-ctl health`, `./scripts/omi-ctl actions` and `./scripts/omi-ctl log-path` on its configured automation port. The bridge returns runtime/backend identity and the exact private log path; [desktop E2E](../testing/desktop-e2e.md) covers tiered evidence.

`backend/test.sh` executes its selected test-file list. The full CI wrapper `backend/scripts/run-unit-ci.sh` also runs environment preflight and the applicable typecheck before delegating to that executor. These command roles explain why a narrow test run and full component acceptance report different scope.

Build the Node runtime before running its tests: the stdio fixture launches `dist/index.js`, and the tool-surface generator imports the compiled manifest. Running tests without that build reports missing-module failures.

The isolated [codebase map viewer](codebase-map.md) requires `npm --prefix tools/codebase-map ci` and `npm --prefix tools/codebase-map exec -- playwright install chromium` before local checks. Its check command type-checks, tests source provenance, builds the static Next.js export, and exercises the full canonical map in Chromium. GitHub Actions installs these dependencies when the shared manifest selects the viewer check.

## Product map and PR handoff

The [Mermaid product map](../../../docs/architecture/intentive-codeflow.mmd) is a single tracked diagram. Its sections and source anchors support following product flows; it is maintained through reviewed edits when those flows change. There is no automatic graph-generation stage in setup or PR closeout.

The viewer reads this file during its static build and links to the exact source commit. Its Vercel setup publishes main and PR previews, with deployment skipping disabled; automatic publication does not update the diagram's meaning. Follow the [authored closeout rule](../../INSTRUCTIONS.md#pr-closeout) to review the map before closing a code change and update affected flows/source references in that PR. The PR template records an updated or reviewed-unchanged result.

Conductor's Create PR prompt finishes source/tests and the native wiki update, updates the map when relevant, commits the intended changes, and runs the required preflights before publishing the PR. It preserves the current branch and does not merge or archive the workspace. The next workspace inherits the committed map and documentation after they reach its starting branch.

For instruction and workflow changes, that prompt also requests the PR template's Policy changes section. Its four fields record the original decision, affected scope, before/after effect and preserved or changed qualifications. The shared preflight checks the disclosure on sensitive paths, including moved or deleted instructions; it does not prove the cited authorization is genuine. Read the [authored authority boundary](../../INSTRUCTIONS.md#instruction-authority-and-policy-changes) for the policy and the [provenance review](../../../docs/engineering/policy-provenance-review.md) for the incident that motivated this check.

## Native OpenWiki lifecycle

The [authored maintenance instructions](../../INSTRUCTIONS.md#wiki-maintenance) select stock OpenWiki 0.5.2. With Node 22.22.0 active, install it using `npm install -g openwiki@0.5.2`, then `openwiki integrations install codex --project .`. A fresh Codex session discovers the project MCP and skill. It uses the host model session; this documentation integration needs no additional model account or tracing service.

After source and tests stabilize, call native `openwiki_begin` in update mode. If planning is requested, research the changed behavior and submit the affected page plan. For each `openwiki_next_page` assignment, update that page and submit sparse claim decisions. Finish after the queue completes. A no-change result needs no fabricated edit. Use `force: true` for guidance-only regeneration; resume interrupted work through begin and its durable queue.

The instruction brief carries current scope and working constraints. Full IR decisions, old tutorials and dated acceptance records are reached through its pinned Git links; they are not copied into generated pages. Initialization replaces generated pages while preserving the instruction brief. Remove the scaffolded scheduled workflow before committing. OpenWiki generates its structural indexes at finalization. Never hand-edit Claims or completion metadata.

Commit wiki changes with the implementation on the current branch. The existing explicit-push rule still governs publishing.

## Source evidence

- [Makefile](../../../Makefile#L21-L39)
- [Conductor Create PR sequence](../../../.conductor/settings.toml#L5-L16)
- [.nvmrc](../../../.nvmrc)

- [Node package scripts](../../../desktop/macos/agent/package.json#L1-L12)
- [Runtime stdio fixture](../../../desktop/macos/agent/tests/runtime-stdio-contract.test.ts#L17-L36)
- [Tool-surface generator](../../../desktop/macos/agent/scripts/generate-tool-surfaces.mjs#L1-L15)

- [Local launch contract](../../../scripts/dev-harness/desktop-run-local.sh#L24-L78)
- [Named profile safety tests](../../../scripts/dev-harness/tests/test_desktop_profile.py#L34-L62)
- [Python synchronization](../../../backend/scripts/sync-python-deps.sh#L5-L47)
- [Local launcher options](../../../desktop/macos/run.sh#L45-L80)
- [Harness prerequisite checks](../../../scripts/dev-harness/dev_harness/cli.py#L1657-L1690)
- [Backend CI wrapper](../../../backend/scripts/run-unit-ci.sh#L40-L65)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
