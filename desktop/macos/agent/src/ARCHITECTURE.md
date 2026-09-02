# Desktop Agent Runtime Architecture

This package is the local desktop agent daemon. It owns durable agent identity,
execution profiles, routing, context admission, run/attempt state, physical-tool
authorization, the owner-scoped Chat catalog, and the cross-surface conversation
journal. Swift is a transport and presentation client; adapters execute model
work but do not own policy.

## Boundaries

```text
Swift desktop client
  <-> protocol.ts / index.ts (versioned JSONL transport)
       -> runtime/kernel.ts (public kernel facade)
          -> kernel-{core,sessions,runs,coordinator,artifacts}.ts
          -> desktop-intent-router.ts
          -> external-surface-tool-policy.ts
          -> context-snapshot.ts
          -> session-execution-profile.ts
          -> conversation-journal.ts
          -> run-tool-capability.ts -> tool-invocation-ledger.ts
          -> sqlite-store.ts (durable state)
       -> adapters/pi-mono.ts (managed model execution only)
       -> ../pi-mono-extension -> OMI_BRIDGE_PIPE (owned typed-tool transport)
```

## Ownership rules

- `protocol.ts` defines every message crossing the Swift/Node boundary. New
  authority-bearing operations must be typed here and correlated to their
  persisted owner, session, run, attempt, and claim generation where applicable.
- `index.ts` validates transport envelopes and connects physical I/O to kernel
  operations. It must not reimplement routing, profile, journal, or capability
  policy.
- `runtime/kernel.ts` is the public facade. Its split `kernel-*` modules contain
  the implementation domains and may share the narrow types in `kernel-types.ts`.
- `desktop-intent-router.ts` is the sole semantic route decision owner. Callers
  use atomic route-and-apply operations rather than reproducing policy.
- `external-surface-tool-policy.ts` implements a kernel-owned proposal policy
  invoked by the atomic route/relay path for every surface. It may recover a
  malformed permission proposal into the native tool or reject an external-app
  target, and it gates pill visibility against the persisted user prompt. Swift
  and provider prompts never reimplement this decision.
- `session-execution-profile.ts` owns immutable, generation-fenced session
  profiles. Preference changes affect future sessions only unless an explicit
  migration succeeds.
- `context-snapshot.ts` owns versioned context source selection, admission, and
  rendering. Surface policy and tool capability fingerprints are distinct from
  the shared base-content version.
- `kernel-sessions.ts` owns the local Chat catalog over `sessions`, including
  title origin, stars, derived previews/counts/activity, owner isolation, and
  atomic delete. `conversation-journal.ts` is the sole durable turn writer.
  Neither module projects normal Chat to a backend or maintains a remote
  reconcile/delete outbox. Swift invokes the typed `chat_catalog_*` protocol
  operations and presents their results; it does not own a shadow catalog.
- `run-tool-capability.ts` and `tool-invocation-ledger.ts` jointly authorize and
  record physical effects. Request IDs are tracing keys, never authorization.
- `sqlite-store.ts` owns schema creation, migrations, startup reconciliation,
  and transactions. Other modules do not issue lifecycle-altering schema DDL.
- `adapters/pi-mono.ts` translates a pinned run into managed Pi calls. It cannot
  mutate a session profile or directly execute desktop effects. The internal
  adapter protocol remains only as a test seam for kernel behavior.
- `artifact-storage.ts` owns per-run managed artifact directories. Every leaf
  attempt receives that directory as its adapter cwd; delegated objectives and
  raw control-tool cwd values cannot default a deliverable to Desktop. Explicit
  external-delivery reports are copied into the managed directory.
- Pi forwards typed prompts without adding a public-web policy or synthetic tool
  activity. Private desktop tools and explicit URL readers remain separate capabilities.
- Generated tool manifests and Swift executors are updated together through
  `../scripts/generate-tool-surfaces.mjs`; hand-edited capability mirrors are
  prohibited.

## Adjacent ownership

- Memory Export and onboarding connector names are not agent-runtime entrances;
  their removal or redesign belongs to S-06 and S-17.
- Task-attached agent, task-chat, and workstream persistence are retired; the
  runtime keeps only general Chat, realtime, delegated-agent, service, and
  floating-bar surfaces.
- The four live non-agent extraction callers retain their fixed Haiku request
  through the existing managed completion transport. Their model alias and any
  later migration belong to S-22. Retired agent/provider names may appear only
  in durable upgrade migrations and their regression fixtures.
- `@vitest/browser-playwright` in `package-lock.json` is optional peer metadata
  from Vitest, not an installed or packaged Playwright runtime. The packaged
  runtime contract test rejects that module and all retired adapter assets.

## Change checklist

When a change crosses an ownership boundary, add a behavioral contract test at
that boundary. Protocol changes require Swift and Node decode tests. Durable
changes require restart/idempotency tests. Provider or mode fallback paths must
use the repository's bounded fallback telemetry contract.
