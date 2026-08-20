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

The backend remains a transient managed-compute boundary for live speech and
the three candidate-only conversation operations: discard, structure, and
action-item extraction. Those operations return candidates; the Mac validates
and commits them locally. Cloud conversation playback, reusable People/voice
identity, public conversation sharing, and Store Recordings/Private Cloud Sync
settings are not macOS product surfaces.

Continuous cloud transcription uses one Firebase-authenticated `/v4/listen`
socket. The Mac snapshots language, optional translation target, and ordered
vocabulary for the recording; audio is fixed mono 16 kHz signed PCM. The backend
streams it to managed Modulate and returns only stable UUID segments with
zero-based numeric speakers, truthful transport/account status, and optional
Gemini 2.5 Flash-Lite translations keyed to the segment. It does not create,
persist, identify, roll over, reconcile, or finalize a conversation.

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

## Before you build

- Large or ambiguous features start as a GitHub issue.
- Trace product behavior to its owning source, public seam, and concrete guard
  test before changing it.
- A product rule without a guard surface is guidance, not an enforced contract.

## Maintainer operating rule

When declining a PR for direction or taste, cite the applicable principle here
or the concrete repository guard that protects it. Tribal “no” becomes written
guidance or an enforceable test.
