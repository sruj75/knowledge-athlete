---
type: Codebase guide
title: Local data and Rewind
description: Explain account-scoped GRDB, Rewind capture/OCR/video, tasks, goals and semantic retrieval.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-10-14T14:40:28.560Z
sources:
  - id: openwiki-source-f16497173de6b612a819df04
    resource: repo://desktop/macos/Desktop/Sources/Account/Export/LocalUserDataExport.swift
  - id: openwiki-source-589f41062c2e58cbb24b065e
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/MemoryStorage.swift
  - id: openwiki-source-4059e2529808adde0c26d6e6
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift
  - id: openwiki-source-ab1c6a4d164017e8ca7bcd50
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase%2BOwnerAuthorization.swift
  - id: openwiki-source-09ee795cdf804c9c27a7a9a6
    resource: repo://desktop/macos/Desktop/Sources/Rewind/Core/TranscriptionStorage%2BLocalAuthority.swift
  - id: openwiki-source-7b0d5464dac2e7f707ae6a5a
    resource: repo://desktop/macos/Desktop/Tests/ConversationRepositoryTests.swift
  - id: openwiki-source-579038dc53c8195eeb78fd6d
    resource: repo://desktop/macos/Desktop/Tests/FocusLocalAuthorityTests.swift
  - id: openwiki-source-963371100be9c0fa7cc7bc80
    resource: repo://desktop/macos/Desktop/Tests/MemoryLocalAuthorityTests.swift
generated: { by: "codex", at: "2026-10-14T14:40:28.560Z" }
---
# Local data and Rewind

The Mac has two complementary local persistence owners. GRDB in `RewindDatabase` holds the app's product archive and Rewind state. The [Node runtime](desktop-agent.md) holds the Chat catalog and accepted-turn journal. Swift drafts and attachment files are not a second durable Chat catalog.

## GRDB ownership

Conversations and Memories use component stores on the active owner's database. Historical tasks, simple goals and Focus remain in that database for decoding, referenced content and authorized export. `RewindDatabase` exposes a pool generation so asynchronous work can identify the database it started against. Owner-authorized read and write methods revalidate the captured authorization; screenshot insertion holds a commit lease and checks authority around the database mutation. A delayed callback must not simply fetch whichever database is current now.

`MemoryStorage` owns active assertions, lifecycle receipts and semantic vectors. Retained task/goal schemas and storage readers are historical compatibility surfaces; active task creation, recurrence, reminders and coaching inputs are retired. A hosted candidate response does not itself become a durable product object.

Conversation recovery supersedes pending or running action-item enrichment, and admissions/claims reject that retired kind. Structure and generic Memory work continue. Historical Focus export pages by timestamp and ID beyond the former 500-row limit, including equal timestamps. No migration deletes these records.

## Rewind capture and retrieval

Rewind associates screenshot metadata and OCR with local video chunks. The indexer and its owner-authorization extension perform local indexing work; the database's owner-aware search and embedding reads keep asynchronous retrieval scoped to the captured owner. Video availability and abandoned-chunk quarantine are part of screenshot admission, so a metadata row is not proof that arbitrary video bytes are safe to read.

This is a storage architecture statement, not a promise that all compute runs locally. Managed providers may receive bounded selected inputs, while persisted Rewind history stays under the Mac's authority. See [providers](../integrations/providers.md), [Memory lifecycle](../workflows/memory.md), and [account export](../workflows/account-lifecycle.md).

Supervisor fresh-frame acquisition is separate from archival admission. Its quiet checks can observe an unchanged screen without creating duplicate archive or OCR writes. Webcam holds only its latest bounded frame in memory and produces no recording.

## Verification and changes

Use the focused local-authority, conversation and Memory tests before changing shared persistence. Schema and namespace changes have additional [migration](../operations/migrations.md) obligations. The authored product constraints define which local capabilities must survive; generated storage explanations do not authorize data cleanup.

## Source evidence

- [desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase+OwnerAuthorization.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase+OwnerAuthorization.swift#L4-L31)
- [desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift#L178-L197)
- [desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase+OwnerAuthorization.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase+OwnerAuthorization.swift#L32-L84)
- [desktop/macos/Desktop/Sources/Rewind/Core/MemoryStorage.swift](../../../desktop/macos/Desktop/Sources/Rewind/Core/MemoryStorage.swift)
- [desktop/macos/Desktop/Tests/MemoryLocalAuthorityTests.swift](../../../desktop/macos/Desktop/Tests/MemoryLocalAuthorityTests.swift)
- [desktop/macos/Desktop/Tests/ConversationRepositoryTests.swift](../../../desktop/macos/Desktop/Tests/ConversationRepositoryTests.swift)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
