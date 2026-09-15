---
type: Codebase guide
title: Data and namespace migrations
description: Explain retained schema/lifecycle migration tools and distinguish them from retired planning validation.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-4059e2529808adde0c26d6e6
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift
  - id: openwiki-source-005ad214e7c042d3f4dad5cf
    resource: repo://desktop/macos/Desktop/Tests/ConversationLocalAuthorityMigrationTests.swift
  - id: openwiki-source-c7e93ebfccaee22a4bb9bc34
    resource: repo://scripts/migration/mixpanel_export.sh
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
---
# Data and namespace migrations

Persistent changes belong to the component that owns the data. `RewindDatabase` registers named GRDB migrations and applies them to the active database pool. Its history includes screenshots, OCR/search, transcription, local product state and later lifecycle transitions. A documentation move does not change those schemas or authorize deleting user data.

## Local storage changes

Trace the current pool initialization, migration ordering and owner transition before changing a schema. The [local data guide](../architecture/local-data.md) explains generation fencing; [Memory](../workflows/memory.md) explains revision-bound work. A migration must preserve surviving user behavior, handle previously created databases, and include the behavioral test that exercises the actual old-to-new state transition.

The conversation local-authority migration test is an example of an owning seam. Historical migration discussions and final product decisions remain in the [authored decision register](../../INSTRUCTIONS.md#accepted-requirements). Their old planning ledger validator has been retired with that ledger; it is not a database migration runner.

## Retained analytics export utility

`scripts/migration/mixpanel_export.sh` is an inherited resumable analytics utility, separate from app schema migration and Company documentation. It exports one UTC day at a time to compressed JSONL, skips completed chunks, keeps a manifest/failure log, and uses an exclusive lock. It requires explicit service-account credentials and a project ID. Optional GCS mirroring is a real external operation. This OpenWiki adoption neither configures nor runs it.

Its shell uses GNU-style date operations, `flock`, `sha256sum`, `curl`, `gzip` and `jq`; inspect the executable before selecting a host. Do not assume the script's inherited example project identifies a currently owned destination. Credentials, exports and personal data remain outside wiki research and Git.

Operational resource decommission has its own [open handoff](../../INSTRUCTIONS.md#unresolved-commitments), including classification and rollback evidence. A source cleanup cannot prove a remote resource is unused.

## Source evidence

- [desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift#L1074-L1168)
- [desktop/macos/Desktop/Tests/ConversationLocalAuthorityMigrationTests.swift](../../../desktop/macos/Desktop/Tests/ConversationLocalAuthorityMigrationTests.swift)
- [scripts/migration/mixpanel_export.sh](../../../scripts/migration/mixpanel_export.sh#L1-L80)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
