---
type: Codebase guide
title: Development and wiki maintenance
description: Describe setup, component entrypoints, pinned development Node and native wiki update/resume lifecycle.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:07:01.245Z
sources:
  - id: openwiki-source-7c03237a6b57ffb3e526a51b
    resource: repo://.nvmrc
  - id: openwiki-source-221ccd7dfd0766ec2939c6ec
    resource: repo://desktop/macos/agent/package.json
  - id: openwiki-source-fd55fa27de60ffa7dc0fc82e
    resource: repo://desktop/macos/agent/scripts/generate-tool-surfaces.mjs
  - id: openwiki-source-edc5df9f3e1eaa7250675764
    resource: repo://desktop/macos/agent/tests/runtime-stdio-contract.test.ts
  - id: openwiki-source-012f2c78e3b1446dfc35803f
    resource: repo://Makefile
generated: { by: "codex", at: "2026-09-15T13:07:01.245Z" }
---
# Development and wiki maintenance

Start at the repository root. `make setup` refreshes the main baseline, installs worktree-safe Git hooks and synchronizes the backend environment. It deliberately leaves the desktop runtime and app environment opt-in. The repository pins development Node to 22.22.0 in `.nvmrc`.

## Local commands

| Task | Command from repository root |
| --- | --- |
| Install prerequisites and hooks | `make setup` |
| Start local/offline services | `PROVIDER_MODE=offline make dev-up` |
| Check the local harness | `make dev-check USER=alice` |
| Backend component tests | `backend/test.sh` |
| Desktop component tests | `desktop/macos/test.sh` |
| Node runtime checks | `cd desktop/macos/agent && npm run build && npm test` |
| Shared deterministic contract | `make preflight` |
| Build and smoke canonical image | `make runtime-image-smoke SERVICE=backend` |

Read [backend](../../INSTRUCTIONS.md#backend-guidance) or [desktop guidance](../../INSTRUCTIONS.md#desktop-guidance) for component prerequisites and named-bundle launch commands. Do not restart a production app to test a documentation or development-tooling change.

Build the Node runtime before running its tests: the stdio fixture launches `dist/index.js`, and the tool-surface generator imports the compiled manifest. Running tests without that build reports missing-module failures.

## Native OpenWiki lifecycle

The [authored maintenance instructions](../../INSTRUCTIONS.md#wiki-maintenance) select stock OpenWiki 0.5.2. With Node 22.22.0 active, install it using `npm install -g openwiki@0.5.2`, then `openwiki integrations install codex --project .`. A fresh Codex session discovers the project MCP and skill. It uses the host model session; this documentation integration needs no additional model account or tracing service.

After source and tests stabilize, call native `openwiki_begin` in update mode. If planning is requested, research the changed behavior and submit the affected page plan. For each `openwiki_next_page` assignment, update that page and submit sparse claim decisions. Finish after the queue completes. A no-change result needs no fabricated edit. Use `force: true` for guidance-only regeneration; resume interrupted work through begin and its durable queue.

Initialization replaces generated pages while preserving the instruction brief. Create the empty Company directory after initialization starts and remove the scaffolded scheduled workflow. OpenWiki generates its structural indexes at finalization. Never hand-edit Claims or completion metadata.

Commit wiki changes with the implementation on the current branch. The existing explicit-push rule still governs publishing.

## Source evidence

- [Makefile](../../../Makefile#L21-L36)
- [Makefile](../../../Makefile#L35-L55)
- [.nvmrc](../../../.nvmrc)

- [Node package scripts](../../../desktop/macos/agent/package.json#L1-L12)
- [Runtime stdio fixture](../../../desktop/macos/agent/tests/runtime-stdio-contract.test.ts#L17-L36)
- [Tool-surface generator](../../../desktop/macos/agent/scripts/generate-tool-surfaces.mjs#L1-L15)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
