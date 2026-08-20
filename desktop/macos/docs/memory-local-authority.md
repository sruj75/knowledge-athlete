# Rewind local authority

`RewindDatabase` opens one GRDB `omi.db` for the current effective owner. The
database path is the owner boundary: local records do not carry an owner ID and
must never be copied between owner databases.

## Memory

`MemoryStorage` is the sole durable Memory module. Callers use its typed
commands and queries for page/search reads, admission, correction, read and
dismiss state, delete/Undo, source cascade, lifecycle work, transition receipts,
and vectors. Direct Memory SQL is limited to the generic read-only SQL tool.

The live schema is deliberately local-only:

- `memories` owns content, category/layer, expiry, revision, local provenance,
  UI state, pending deletion, and timestamps;
- `memory_processing_work` owns restart-safe revision/generation-bound leases;
- `memory_transitions` records idempotent lifecycle outcomes; and
- `memory_embeddings` stores revision-bound vectors with foreign-key cascade.

The forward `makeMemoriesLocalAuthoritativeS12` migration rebuilds legacy rows
while preserving their local primary keys and removes backend identity, sync,
review, scoring, device, public/private, headline, and compatibility fields.
The follow-up lifecycle migration converts legacy Tips rows to `interesting`,
assigns finite expiry to legacy Short-term rows, and queues normalization,
consolidation, and missing-vector work without changing local identities.
Historical migrations remain registered so both upgraded and fresh databases
converge through the same forward migration.

`LocalMemoryLifecycleRunner` is the only lifecycle scheduler. It leases work,
calls transient extraction/normalization/consolidation or embedding compute,
then commits through `MemoryStorage` only if the owner generation and input
revision are still current. Model responses never become an authority by
themselves. On an authorized database reopen it rebinds unfinished durable work
to the new pool generation, batches document embeddings, and selects conflict
context from revision-matched local vectors. Evidence, subject, sensitivity,
relationship, and supersession rules are revalidated in the local transaction.

Conversation deletion and merge use the transaction-scoped source hooks from
the conversation authority so Memory provenance and cascades stay atomic with
the local conversation change.
