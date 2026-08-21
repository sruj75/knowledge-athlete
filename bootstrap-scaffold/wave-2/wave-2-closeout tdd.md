# Wave 2 closeout TDD plan — preserve behavior and finish local authority

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | **Wave 2 closeout** (unnumbered; S-18 remains the Dodo slice) |
| Baseline | `origin/main` at `26c67df6` |
| Product authority | [`PRODUCT.md`](../../PRODUCT.md) |
| Roadmap | [`../deletion-map.md`](../deletion-map.md) |
| Failure class | `FC-split-mutation-authority` for owner/duplicate-authority repairs |

## 2. Goal

Close the integrated S-12, S-13, and S-14 authorization and duplicate-authority defects without changing retained product behavior. Revalidate S-10 through S-18 as one repository state. The free MVP remains `BILLING_MODE=disabled`; this checkpoint permits Wave 3 repository work but does not mark operational Dodo activation complete.

## 3. Non-negotiable behavior contract

Prompts, model choices, tool schemas, confidence/admission thresholds, capture cadence, deduplication policy, UI flows, search results, notification identifiers and copy, Focus cooldowns, reminder timing, and the disabled billing experience remain unchanged. The work changes only which owner may commit delayed work, which local table owns retained data, and whether publication happens after persistence.

## 4. Entry baseline

- S-10, S-11, S-15, S-16, and S-17 are repository-integrated and receive regression coverage only.
- S-12 captures only an owner string before extraction and captures a fresh authorization generation after the provider returns.
- S-13 captures fresh authorization separately for observations and task persistence after extraction.
- S-14 mutates Focus history/status before durable insertion and still exposes `proactive_extractions` as a second current authority.
- Conversation task similarity and parts of OCR/task embedding can send owner A content using credentials minted after an A-to-B or same-UID ABA transition.
- Reminder reconciliation fences the caller but not each suspended notification operation.
- S-18 is a valid disabled repository/MVP checkpoint and intentionally has no provider transaction acceptance.

## 5. Shared owner transaction

Capture one `RuntimeOwnerAuthorizationSnapshot` before user-derived asynchronous compute. Pass it through every read, provider call, local mutation, index update, telemetry terminal, notification, and event publication. Revalidate after every suspension and immediately before each side effect. An owner string alone never authorizes delayed work.

`ProactiveAssistant` gains an explicit owner-reset requirement. The coordinator runs every assistant reset inside `RuntimeOwnerIdentity`'s exclusive transition before the next generation becomes visible. Embedding indexes, assistant history/context/dedup caches, queued frames, timers, and pending tasks are owner-generation state and clear there.

## 6. RED cycle — embeddings and conversation enrichment

- Suspend authentication or index loading, transition A→B and A→nil→A, then resume.
- Assert A transcript/OCR/task text is never sent with the replacement generation's credential.
- Assert a stale task index never contributes matches for B.
- Assert the normal same-owner similarity result and empty-context fallback are unchanged.

GREEN requires owner snapshots on embedding, batch embedding, index load/search/update, OCR batching/backfill/search, Memory recall, Task search, and conversation similarity.

## 7. RED cycle — Memory

Suspend the extraction override, perform A→B and same-UID ABA, then return a valid high-confidence result. Assert no Memory row, dedup-cache entry, telemetry terminal, notification, or `memoryExtracted` event. Same-generation success must still insert once and publish once; insertion failure publishes no historical success.

## 8. RED cycle — Tasks and observations

Drive the production `processFrame` path through an injected extraction seam. Suspend extraction across A→B and same-UID ABA. Assert no observation, task, previous-task cache entry, analytics event, notification, or `taskExtracted` event. Preserve prompt/tool/admission/dedup/due-date behavior. Logs contain bounded shape/outcome information, never the extracted title.

## 9. RED cycle — reminders

Suspend pending-request enumeration and notification add across owner transition. Revalidate before and after every await and before each remove/add. If add finishes after revocation, remove that exact identifier immediately. Preserve request identifiers, title/body, due trigger, committed-task semantics, and reminder-specific errors.

## 10. RED cycle — Focus

Inject analysis and persistence operations. Suspend analysis across A→B and same-UID ABA; inject insertion failure. Assert no history/status/callback/FocusStorage/glow/analytics/notification mutation. On success, insert first and then publish the exact existing state transition, cooldown, callback, and copy.

## 11. RED cycle — sole proactive authority

Replay an old-schema database containing memory, advice, and task extraction rows. The new `retireProactiveExtractionsAuthority` migration copies unmatched retained data exactly once, rejects unknown legacy types, and then removes the current table, FTS table, triggers, and indexes. Historical migration bodies remain unchanged.

Current models, storage APIs, Chat annotations, and discoverability tests expose only canonical Memories, `tips`, Tasks, Focus sessions, and AI profiles.

## 12. RED cycle — backend closure

- Remove only obsolete tests that open deleted Goals and Action Items router source files.
- When subscription cache revalidation throws, preserve the free/fail-open response and emit the shared sanitized `record_fallback` event exactly once.

## 13. Documentation handoff

Create [`../dodo-integration.md`](../dodo-integration.md) as the permanent free-MVP-to-Dodo activation handoff. Update `deletion-map.md`, `FORK.md`, and the S-12/S-13/S-14/S-18 status language only after the corresponding proof is green. Never describe disabled mode as final S-18 closure.

## 14. Focused verification

- Swift owner-generation behavior for Memory, Tasks, Focus, reminders, embeddings, and conversation enrichment.
- GRDB upgrade and fresh-schema assertions, including canonical data cardinality.
- Chat discoverability over canonical local tables and absence of proactive extraction exposure.
- Backend subscription fallback telemetry plus surviving rate-limit and clean-sweep tests.

## 15. Component verification

Run `backend/test.sh`, `desktop/macos/test.sh`, the 714/714 requirements-ledger validator, `git diff --check`, `make preflight`, and `scripts/pr-preflight`. A deterministic failure introduced by this diff is repaired before closeout; unrelated environmental blockers are reported exactly.

## 16. Named-bundle acceptance

Use only `omi-wave2-closeout`. Exercise local Memory add/search/delete/Undo and extraction, Task CRUD/reminders/extraction, Focus transition/history, Insight actions, conversation enrichment, Chat queries over canonical local data, owner switch/return, restart, and offline recovery. Exercise disabled billing with **Skip**, no entitlement grant, and zero Dodo/Stripe calls. Never launch or stop production Omi bundles.

## 17. Post-Wave-6 S-18 gate

After all six waves, separately authorize Dodo test credentials and prove hosted checkout, signed/idempotent webhook projection, bounded reconciliation, portal, plan change, cancellation/access-end, quota/fair-use, failure recovery, and account deletion. Production activation requires another explicit authorization plus a bounded live transaction/cancellation proof, monitoring, and rollback evidence.

## 18. Close conditions

- Same-UID ABA and cross-owner delayed results are rejected on every changed surface.
- Durable state commits before user-visible publication.
- One canonical local authority remains for each retained domain.
- Retained behavior and copy are unchanged.
- S-12, S-13, and S-14 have green repository evidence.
- The disabled S-18 checkpoint is clearly sufficient for Wave 3 source work and clearly incomplete for paid release.
- No credentials, live provider resources, Windows changes, production app operations, push, PR, merge, or deployment are part of this slice.

## 19. Implementation and verification record — 2026-08-21

**Repository outcome:** S-12, S-13, and S-14 closeout defects are repaired and
their repository dependency is complete for Wave 3. S-18 remains **disabled
checkpoint reached, final activation outstanding**. No prompt, threshold,
cadence, notification copy, UI flow, search/task/Focus policy, or free-MVP
behavior was changed.

### Green closeout evidence

- The focused owner-fence selection passed 21/21 after the final SwiftLint-safe
  test cleanup. Earlier focused runs also passed the Memory/Task/Focus,
  conversation, reminder, embedding, and OCR same-UID/cross-owner cases.
- `S14LocalAuthorityMigrationTests` passed 4/4, including duplicate legacy rows,
  canonical work-queue handoff, unknown-type rejection, and final schema
  retirement. Canonical Chat discoverability coverage passed with the migration
  selection.
- `desktop/macos/scripts/agent-logic-harness.sh` passed all four stages in 86.70
  seconds.
- The focused backend billing/rate-limit/migration selection passed 76 tests.
  The full file-isolated backend runner's three maximum-parallel timing failures
  (`test_chat_agent_provider_retry.py`, `test_rate_limiting.py`, and
  `test_clean_sweep_migrations.py`) then passed 87/87 when rerun through the same
  official `test.sh` runner.
- `python3 bootstrap-scaffold/validate-requirements-ledger.py` passed with 714
  indexed rows and 714 detailed sections.
- Both local `make preflight` and CI-lane `scripts/pr-preflight --pr-body-file`
  passed all 30 selected checks with `Failure-Class:
  FC-split-mutation-authority`. `git diff --check`, Swift format, SwiftLint, the
  test-quality ratchet, E2E-flow coverage, and the source line-count ratchet are
  green.
- The offline `omi-wave2-closeout` bundle passed Memory CRUD, Task CRUD,
  disabled billing, Rewind artifact recovery, Alice sign-out, Bob restart, and
  the same four core flows again as Bob. The billing flow proved literal
  **Skip**, checkout/portal disabled, no entitlement/quota/paywall mutation, and
  no checkout request. Neither production Omi bundle was touched.

### Truthful inherited-suite record

The repository-wide Swift runner built all closeout code and ran 366 suites, but
19 target-branch suites remained red. Two representative failures were rerun
unchanged on detached `origin/main` and reproduced there:
`LocalMemoryLifecycleRunnerTests` (fixture extraction count) and
`TasksStoreOwnerBoundaryTests` (UserNotifications bundle proxy). The other red
suites were not individually claimed as baseline-reproduced. Therefore this
record does not falsely claim one clean `desktop/macos/test.sh` pass.

The offline Tier-2 matrix passed 19/29 entries, including every core closeout
flow above and the spatial-overlay suite. Its ten remaining red integration
flows were `capture-lifecycle`, `chat-hermetic`, `conversation-detail`,
`floating-bar-functional`, `home-stage`, `keyboard-shortcuts`, `memory-depth`,
`quick-note`, `recording-finalization`, and `speaker-naming`. These failures and
the full-suite debt are reported rather than broadened into behavior-changing
repairs. They do not restore a cloud authority or change the Wave 3 source
dependency, but they remain release-suite debt to clear before claiming a fully
green repository-wide desktop release.

No real provider credentials, Dodo/Stripe call, cloud mutation, deployment,
production-app operation, push, PR, or merge occurred.
