# Omi Product Principles

Short north star for humans and agents. Read this before proposing features or
landing PRs that change product behavior. Engineering standards live in
[`AGENTS.md`](AGENTS.md). Concrete behavior contracts live beside their owning
source and tests.

## Principles

1. **Memory-first.** Protect the core loop:
   **Capture → Understand → Remember → Retrieve → Act**.
   If Omi fails to capture or preserve memory, nothing else matters.

2. **Trust over cleverness.** Prefer reliable capture, sync, and retrieval over
   flashy features. Silent data loss and dual sources of truth are product bugs.

3. **One product mind.** Surfaces are input/output against one shared product
   experience — not separate products with competing authorities. This does
   not make every capture cloud-backed: persisted Rewind OCR history,
   embeddings, and video remain local to the Mac.

4. **Harness over heuristics.** Where we integrate with surfaces we do not own,
   invest in durable harnesses and contracts, not brittle one-off automation.

5. **Taste floor.** Stay on-brand. Prefer deleting dual paths over
   feature-flagging them forever.

6. **Managed desktop access.** Desktop AI, voice, transcription, and agent
   surfaces use account entitlement plus product-owned provider credentials.
   They do not solicit, forward, or select customer-supplied provider keys.
   The concrete guards live in the desktop managed-access, request-routing,
   realtime-authentication, and agent-runtime tests and the backend route tests.

## macOS conversation authority

The Mac owns its conversation archive in its owner-scoped local GRDB database.
Capture creates one stable local conversation ID; list, detail, search, folders,
stars, titles, speaker labels, merge, deletion, and restart recovery read and
write that local authority. The desktop does not project conversations to
Firestore, reconcile server snapshots, or fall back to hosted conversation
data.

The backend remains a transient managed-compute boundary for live speech, the
three candidate-only conversation operations (discard, structure, and
action-item extraction), and fair-use classification. Conversation operations
return candidates that the Mac validates and commits locally. Fair-use compute
accepts only a bounded owner-local metadata projection, runs the pinned GPT-5.1
contract transiently, and persists only content-free enforcement facts. Cloud
conversation playback, reusable People/voice identity, public conversation
sharing, and Store Recordings/Private Cloud Sync settings are not macOS product
surfaces.

Continuous cloud transcription uses one Firebase-authenticated `/v4/listen`
socket. The Mac snapshots language, optional translation target, and ordered
vocabulary for the recording; audio is fixed mono 16 kHz signed PCM. The backend
streams it to managed Modulate and returns only stable UUID segments with
zero-based numeric speakers, truthful transport/account status, and optional
Gemini 2.5 Flash-Lite translations keyed to the segment. It does not create,
persist, identify, roll over, reconcile, or finalize a conversation.

## macOS Chat and Home authority

Home is the canonical ordinary-Chat host. The owner-scoped Node SQLite catalog
owns Chat identity, titles, title origin, stars, activity metadata, and accepted
turns; Swift owns drafts and app-managed attachment bytes. The desktop does not
project normal Chat sessions, messages, ratings, or attachments to Firestore and
does not reconcile a server catalog.

The persistent primary navigation is Home, Memory, Tasks, and Insights. Memory
owns the Memories and Conversations destinations, while Insights owns Insights
and Focus. Semantic Chat navigation opens the Chat stage inside Home; it is not a
standalone page or raw navigation destination.

The backend is transient compute only for managed assistant completion and the
authenticated, bounded greeting and title routes. Greeting and title results are
identified and committed locally. Home reads tasks, Focus, Insights, and daily
suggestions from their local authorities and must not restore a hosted dashboard
fallback.

## macOS Memory authority

The Mac owns its Memory archive in the same owner-scoped local `omi.db` boundary
as conversations. Add, edit, delete/Undo, bulk deletion, page/search queries,
source provenance, lifecycle transitions, and semantic vectors commit through
`MemoryStorage`; they do not reconcile with or fall back to a hosted Memory
store. Default reads include active Short-term and Long-term rows and hide
Archive, expired, dismissed, and pending-deletion rows.

New local intake begins in Short-term. A restart-safe local lifecycle runner
normalizes assertions, consolidates grounded candidates, expires or archives
rows, and records revision-bound transition receipts. Every delayed result is
committed only while its captured owner and input revision remain current.
Embedding compute is transient; vectors and similarity search remain local.

The backend exposes only three authenticated, bounded proposal operations for
Memory extraction, normalization, and consolidation. They use the pinned
OpenAI GPT-4.1-mini model, return opaque local tokens rather than durable IDs,
and own no Memory persistence, search index, maintenance schedule, or product
mutation authority.

## macOS task and goal authority

The Mac owns tasks and simple goals in the same owner-scoped local GRDB database.
Tasks expose one stable `local_<rowid>` identity and retain local CRUD, grouped
To Do/Done lists, search, due dates and reminders, priority, recurrence, order,
provenance, source-session linkage, and five-second Undo. One simple goal retains
a stable local identity, title, optional description, and active/completed state.
Dashboard, Chat, voice tools, automation, and Task Assistant all read or commit
through these local stores; their success never waits for a network response.

There is no hosted task/goal authority, task staging or suggestion queue, task
ranking, productivity score, task-attached chat/agent/workstream, numeric or
AI-generated goal system, or task-specific push-notification path. The backend
may return an untrusted action-item candidate from transient conversation compute,
but the Mac alone decides whether and how it becomes a durable task.

## macOS Focus, Insights, and profile authority

The Mac owns Focus sessions and AI Profile history in its owner-scoped local
GRDB database. Focus retains the current state, truthful capture status, today
totals, and a short recent history. AI Profile generation uses bounded local
inputs, commits only locally, and keeps five prior profiles. Neither product
syncs to or falls back to a hosted data authority.

Insights are owner-local Memory records tagged `tips`; the Insights UI is a
projection of that one authority, not a second store. Home questions use bounded
local context and owner/day caching. Home, Focus, and stored Insights navigate
through one top-level Insights hub, while Live Suggestions remain a distinct
local assistant behavior.

Assistant controls and the master notification switch/frequency are local
preferences. Proactive cards and macOS notifications may enter Chat only through
the accepted local journal continuity path. Daily Summary, server AI Profile,
server Focus, hosted assistant/notification/Mentor settings, personalized
purchase/quota push copy, and the Notifications Cloud Run job are not product
authorities. Cloud FCM delivery is not a product surface. Retained fair-use and
managed-usage facts remain server-authoritative, while the Mac presents fixed
truthful in-app copy and deduplicated local OS notifications under the active
owner boundary.

## Account data lifecycle

**Export My Data** writes one complete, deterministic JSON file from the active
owner's local Mac authorities: conversations/transcripts, Memories, tasks,
goals, Chat catalog/journal, Focus data, and a privacy-reviewed settings
allowlist. Export is owner-generation fenced, works without product network,
and never dumps raw databases, credentials, prompts, caches, or diagnostics.
The backend export returns retained account/subscription/usage metadata only.

Account deletion remains a durable backend job. Its required boundaries are
billing cancellation, Firebase Authentication deletion, recursive retained
Firestore deletion, and the exact Pinecone namespace-purge handoff owned by the
next storage slice. It does not restore cleanup clients for retired recordings,
People/voice identity, phone calling, notifications, or hosted product data.

## Before you build

- Large or ambiguous features start as a GitHub issue.
- Trace product behavior to its owning source, public seam, and concrete guard
  test before changing it.
- A product rule without a guard surface is guidance, not an enforced contract.

## Maintainer operating rule

When declining a PR for direction or taste, cite the applicable principle here
or the concrete repository guard that protects it. Tribal “no” becomes written
guidance or an enforceable test.
