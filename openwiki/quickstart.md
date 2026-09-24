---
type: Codebase guide
title: Start here
description: Orient contributors to the active Mac product, ownership, local setup and topic navigation.
tags: [intentive, codebase]
sources:
  - id: openwiki-source-311b902b81b9fbe111c8359f
    resource: repo://.conductor/settings.toml
  - id: openwiki-source-fcffbe3e28749eaf9a39557c
    resource: repo://backend/main.py
  - id: openwiki-source-221ccd7dfd0766ec2939c6ec
    resource: repo://desktop/macos/agent/package.json
  - id: openwiki-source-012f2c78e3b1446dfc35803f
    resource: repo://Makefile
  - id: openwiki-source-23775c3de52f3ab95a13cb8b
    resource: repo://README.md
generated: { by: "codex", at: "2026-09-24T10:47:55.441Z" }
verified:
  - by: openwiki/0.5.2
    at: 2026-09-24T10:47:55.441Z
---
# Start here

Intentive's active codebase is a macOS app with a bundled Node agent runtime and a managed Python backend. OpenWiki documents this repository's codebase only, with `codebase/` as the default destination for generated pages. Begin with the [system architecture](codebase/architecture/overview.md), then follow the task map below.

## Before changing code

Read the [compact authored brief](INSTRUCTIONS.md): Scope, Wiki maintenance, Engineering rules and the relevant component constraints. It keeps current rules and unresolved obligations, with targeted links to the full IR decisions and dated records in Git history. Read the applicable historical decision when changing its boundary; the full archive is not startup context. Generated pages hold implementation explanations, operating commands and source/test evidence. They do not override authored decisions or certify a live deployment.

For instruction imports, summaries or workflow-policy changes, start with [instruction authority](INSTRUCTIONS.md#instruction-authority-and-policy-changes) and the [policy disclosure check](codebase/operations/qualification.md#policy-change-disclosure). Historical text and current settings are not independent proof of the owner's intent.

## Find your task

| Task | Guide |
| --- | --- |
| Understand ownership | [Architecture](codebase/architecture/overview.md), [product boundaries](codebase/concepts/product-boundaries.md) |
| Look up provider accounts and settings | [Owner and provider record](codebase/operations/owner-provider-record.md) |
| Trace capture or lost transcript | [Capture and transcription](codebase/workflows/capture-transcription.md) |
| Change Chat, tools or PTT | [Chat and voice](codebase/workflows/chat-voice.md), [agent runtime](codebase/architecture/desktop-agent.md) |
| Change Memory processing | [Memory lifecycle](codebase/workflows/memory.md), [local data](codebase/architecture/local-data.md) |
| Trace export or account deletion | [Account lifecycle](codebase/workflows/account-lifecycle.md) |
| Change a backend route | [Backend](codebase/architecture/backend.md), [providers](codebase/integrations/providers.md), [billing](codebase/integrations/billing.md) |
| Review privacy boundaries | [Telemetry](codebase/integrations/telemetry.md) |
| Set up and test locally | [Development](codebase/operations/development.md), [contracts](codebase/testing/contracts.md), [desktop E2E](codebase/testing/desktop-e2e.md) |
| Navigate the product flows | [Mermaid product map](../docs/architecture/intentive-codeflow.mmd) |
| Change storage or migration tools | [Migrations](codebase/operations/migrations.md) |
| Work on delivery | [Build and signing](codebase/integrations/build-signing.md), [releases](codebase/operations/releases.md), [qualification](codebase/operations/qualification.md) |

## First local steps

At the repository root, activate the Node version in `.nvmrc`, run `make setup`, then select the component commands in the development guide. Setup refreshes main, installs Git hooks and synchronizes the backend environment. `make preflight` runs the shared local governance lane. The tracked Mermaid product map is updated through reviewed edits when relevant flows change. Tests and actual user-path evidence are both required by the authored engineering guide; report unavailable or failed evidence explicitly.

After source and tests stabilize, run the native OpenWiki update and include its pages and metadata in the same local change. Native finalization owns all structural indexes. Initialization preserves the brief and replaces generated state. Publishing still requires explicit user instruction.

For account emails, provider roles, operating modes, service/model settings, and credential locations, use the [owner and provider record](codebase/operations/owner-provider-record.md). Consult the [authored brief](INSTRUCTIONS.md) for active rules.

The [pre-migration provenance](INSTRUCTIONS.md#provenance-and-ownership) and commit-pinned archive references retain historical rationale. Inherited Windows code is outside this active-product documentation.

## Source evidence

- [backend/main.py](../backend/main.py#L95-L119)
- [desktop/macos/agent/package.json](../desktop/macos/agent/package.json#L1-L22)
- [Makefile](../Makefile#L21-L39)

[Start here](quickstart.md) · [Authored guidance](INSTRUCTIONS.md)
