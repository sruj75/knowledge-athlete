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

## Proposed canonical memory lifecycle

This direction remains proposed; it is not an enforced contract until the
owning implementation and concrete guard tests establish it.

All new memory intake starts as broad Short-term capture. Maintenance gives
each pending item exactly one consolidation route: promote, archive, review, or
reject. Promotion is the only route into Long-term, and it is admitted only
when one atomic ledger transaction records the server-authored promotion
receipt binding the source revision, output content, evidence, and superseded
memories. There is no direct, generic, or fast-track promotion path.

Default retrieval includes eligible Short-term and Long-term memory, collapsed
by canonical lineage so one logical memory appears once. Search/vector and
compatibility projections are derived views: their updates are committed to
the outbox with canonical state and retried from authoritative memory, never
treated as memory authority themselves.

## Before you build

- Large or ambiguous features start as a GitHub issue.
- Trace product behavior to its owning source, public seam, and concrete guard
  test before changing it.
- A product rule without a guard surface is guidance, not an enforced contract.

## Maintainer operating rule

When declining a PR for direction or taste, cite the applicable principle here
or the concrete repository guard that protects it. Tribal “no” becomes written
guidance or an enforceable test.
