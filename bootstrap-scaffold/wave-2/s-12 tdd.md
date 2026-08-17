# S-12 TDD plan — make Memories local-authoritative and delete knowledge authority

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | **S-12** |
| Name | **Make Memories local-authoritative and delete knowledge authority** |
| Type | Local-authority adaptation |
| Primary decisions | IR-024, IR-033, IR-256 through IR-292, IR-710, IR-728 through IR-730, IR-815 |
| Depends on | S-06 and S-10 |
| Output | `bootstrap-scaffold/wave-2/s-12 tdd.md` |

This document is the implementation plan. It does not authorize implementation, a commit, a push, a PR, a deploy, or live infrastructure mutation.

## 2. Planning status and pinned baseline

- **Planning status:** ready with one predecessor gate and two separately authorized operational gates recorded below.
- **Pinned Wave 1 baseline:** `0d9934c9d2ed61bd02ac8784e50f56ee816257c3` (`docs(wave1): record S07 closeout evidence`).
- **Baseline proof run while planning:** `git merge-base --is-ancestor 0d9934c HEAD` exited 0. `HEAD` was exactly `0d9934c` on `review-wave-1-deletions`.
- **Requirements proof run while planning:** `python3 bootstrap-scaffold/validate-requirements-ledger.py` passed with 714 indexed rows and 714 detailed decisions.
- **Repository state before writing this plan:** clean.
- **Release-contract premise:** current `FORK.md` says this fork has not shipped an application build or public API contract and has no users. Therefore the final implementation must hard-remove rejected APIs and shapes instead of adding compatibility responses, dual writes, aliases, backfills, or migration services. Recheck that premise at execution time; if it has changed, stop before Cycle 12.
- **Already integrated predecessor:** S-06 is present in this baseline. Brain Map/Atlas, public/private visibility UI, Workflow presentation, and the `This device` filter are already partly or wholly retired. S-12 consumes and guards that result; it does not recreate or redo S-06.
- **Not integrated while planning:** S-10. The current checkout still uses backend conversation IDs and server detail fetches. The mandatory rebase/inventory gate in Section 5 must run before S-12 touches source-conversation identity, extraction admission, navigation, or deletion cascades.

Only read-only planning checks have run. No product test or acceptance command is claimed GREEN by this document.

## 3. Outcome

At S-12 completion, the effective owner's `omi.db` is the only durable authority for Memory identity, content, category, Short-term/Long-term/Archive lifecycle, provenance, revisions, processing state, audit transitions, vectors, read/dismiss state, source links, editing, deletion, Undo, search, and pagination.

The retained product still behaves like Memories:

- the current Memory hub opens Memories directly and keeps Conversations in the current hover/compact path;
- Default, Short-term, Long-term, and Archive retain their selected behavior;
- Add, edit, category/tier filters, literal search, paging, local semantic recall, source navigation, Tips, Context, screenshot links, delete, four-second Undo, bulk default deletion, Retry, empty, and no-results states remain;
- screenshot extraction, conversation extraction, Focus/Insight writers, normal Chat, managed Pi, realtime PTT, Home, profile/goal context, and proactive readers all use the same local authority;
- authenticated Python endpoints perform only three bounded, transient OpenAI GPT-4.1-mini judgments: `memory_l1`, `memory_l2`, and `memory_conflict`; the existing retained Gemini proxy remains the transient embedding boundary until S-22 re-homes shared model transport;
- no Python route, Firestore collection, hosted vector projection, retry cursor, maintenance job, tool endpoint, generated app-client DTO, or reconciliation path is a second Memory authority.

The final architecture is not “local cache plus disabled sync.” Sync identity and state are gone. The backend cannot list, mutate, search, review, maintain, or persist product Memories.

## 4. Authorizing requirements

The live decisions below are the authority. This action ledger makes every S-12-assigned decision explicit.

| Decision | S-12 interpretation |
|---|---|
| IR-024 | Make the Mac GRDB store sole authority; remove `/v3/memories`, Firestore copies, backend IDs/sync flags, retries, reconciliation, pruning, hosted parity artifacts, and cloud maintenance. |
| IR-033 | Keep the conservative Gemini screenshot-to-Memory producer and notifications; make one idempotent local transaction its durability terminal. |
| IR-256 | Consume S-06's complete Brain Map/knowledge-graph removal; keep only historical upgrade migrations and negative regression guards that are still required. |
| IR-257 | Keep the current grouped Memory navigation, direct Memories click, Conversations hover/compact entry, persistence, shortcuts, automation, pointer transit, and accessibility. |
| IR-258 | Keep `This device` absent; all visible memories already belong to the local owner profile. |
| IR-259 | Keep public/private/persona Memory state absent and remove remaining wire/schema/backend residue. |
| IR-260 | Port the same Default/Short-term/Long-term/Archive lifecycle, model-backed promotion semantics, expiry/archive transitions, tier reads/badges, audit, idempotency, cancellation, owner isolation, and crash recovery to the Mac. |
| IR-261 | Keep Workflow absent; retain About You, Insights, and Manual only. |
| IR-262 | Delete the category-name search box/state; preserve multi-select category rows and counts. |
| IR-263 | Keep staged multi-select behavior and live selected counts. |
| IR-264 | Keep visible-content literal search, debounce, stale-result fencing, local fallback, and bounded paging. |
| IR-265 | Keep Add Memory; Save creates a readable local Manual Short-term assertion plus pending processing, never a POST. |
| IR-266 | Close and clear only after local atomic acceptance; retain the draft on local failure; processing continues locally in the background. |
| IR-267 | Keep **Delete Default Memories** with its confirmation and scope; delete Short-term and Long-term locally, not Archive, and cancel any pending single-delete Undo. |
| IR-268 | Keep Loading/Retry with truthful local failure copy; Retry rereads GRDB only and raw errors remain hidden. |
| IR-269 | Keep a true empty state with local-source wording; use the reviewed local meaning now and let S-30 perform the final repository-wide copy pass. |
| IR-270 | Keep No Results unchanged and clear only category selection from that action. |
| IR-271 | Keep page size 100, final-ten prefetch, manual load, loading state, bounded reveal, and `<100` end detection; delete raw backend offsets/capabilities/full sync/reconciliation. |
| IR-272 | Keep the information hover, exact explanations, and the duplicated `Text(value)` rendering quirk. |
| IR-273 | Delete Memory-only `[Protected]`/`[Encrypted]` prefix handling; do not alter separately owned Chat presentation. |
| IR-274 | Delete Memory device provenance and labels; preserve `ClientDeviceService` and local app/window/manual/microphone/confidence/conversation provenance. |
| IR-275 | Keep the one-minute **New** rule exactly; do not add a timer. |
| IR-276 | Keep the selected card and inspector behavior. |
| IR-277 | Keep Tips/subcategories/**Why this tip?**; the first durable Insight is the local `interesting` row, not a temporary system row followed by cloud correction. |
| IR-278 | Keep the active inline editor; commit a local correction revision and pending processing; remove PATCH/backend-ID mutation and dead `EditMemorySheet`. |
| IR-279 | Trim and reject whitespace-only edits, close only after GRDB success, and retain draft on failure without inventing UI. |
| IR-280 | Keep four-second delete/Undo; the initial tombstone is durable, expiry/X/new delete hard-deletes the row and pending work, and Archive supports individual deletion. |
| IR-281 | Keep only Desktop, Screenshot, and Added by you plus local app/mic/confidence/time provenance; delete external source mappings. |
| IR-282 | Keep generic tags exactly. |
| IR-283 | Delete generic inspector Reasoning; retain reasoning only for Tips and retain the IR-272 tooltip. |
| IR-284 | Keep Context exactly. |
| IR-285 | Resolve **View Source Conversation** from S-10's stable local session identity and local detail projection, preserving loading/in-place/back behavior; remove `GET` detail. |
| IR-286 | Make conversation deletion atomically remove linked memories and their pending processing; task cascade remains separately owned; remove backend retraction/vector/refetch/orphan logic. |
| IR-287 | Set the exact subtitle to **“Memories and insights saved on this Mac”**. |
| IR-288 | Keep the two-line preview and dual-timestamp rules exactly. |
| IR-289 | Delete `reviewed`, `userReview`, scoring/review queues/routes/metadata; retain confidence, read/dismiss, and lifecycle audit. |
| IR-290 | Keep an Insight headline only as transient notification presentation/fallback; delete durable Memory headline fields. |
| IR-291 | Keep `screenshotId` as a local FK/index with `ON DELETE SET NULL`, including its Chat relation; do not invent new UI. |
| IR-292 | Delete all five `MemoryTier*` aliases; use `MemoryLayer*` names directly. |
| IR-710 | Keep bounded `memory_l2` normalization on managed OpenAI GPT-4.1-mini for explicit Add/Edit; Mac selects work, validates current revision, stores receipt/result locally, and commits nothing on failure. |
| IR-728 | Keep bounded `memory_l1` conversation extraction on managed OpenAI GPT-4.1-mini; Mac supplies local segments, verifies exact quotes/subjects, assigns identity, and admits candidates locally. |
| IR-729 | Delete legacy `memories`, `learnings`, `memory_category`, `memory_system_request_scope`, legacy extractor/writes/switching, and exclusive tests; retain only l1/l2/conflict Memory workloads. |
| IR-730 | Keep bounded batch `memory_conflict` on managed OpenAI GPT-4.1-mini; Mac selects a generation, validates conservation/references, and atomically commits or changes nothing. |
| IR-815 | Delete the complete cloud memory-maintenance job and repository control plane while preserving the local lifecycle and transient model compute. |

No live requirement conflicts with the deletion map were found. There is an ownership overlap: the S-25 brief also names the memory-maintenance job. IR-815 and the S-12 brief assign its complete Memory-specific repository source/control plane to S-12, so S-25 must consume that absence and remove only any later shared service-topology residue. Live cloud deletion remains a separate authorization boundary in Section 16.

## 5. Dependencies and entry gates

### Gate A — baseline and clean feature branch

Before implementation:

```bash
git fetch origin
git merge-base --is-ancestor 0d9934c HEAD
git status --short
python3 bootstrap-scaffold/validate-requirements-ledger.py
make setup
```

Stop if the ancestor check fails, if unrelated changes overlap the planned files, or if setup cannot establish the repository hooks. Work in the existing worktree/feature branch; do not switch branches and do not land on `main`.

### Gate B — consume S-06, do not redo it

Reconfirm before Cycle 1 that `MemoryHubDestination` has only Memories and Conversations, Brain Map/Atlas production sources are absent, S-06's forward migration removes `local_kg_nodes`/`local_kg_edges`, and `test_s06_external_surface_route_retirement.py` guards the removed routes. Historical create-then-drop migrations are required for upgrade correctness and are not residue.

Stop if S-06's final shape has regressed; repair or integrate S-06 rather than reproducing its deletion inside S-12.

### Gate C — mandatory S-10 rebase and inventory refresh

The planning baseline predates S-10. Cycles 1–5 may be developed only in Memory-exclusive files. Before Cycle 6 or any edit to conversation storage/deletion/navigation/contract files:

1. fetch and rebase the S-12 feature branch onto the exact integration commit containing completed S-10;
2. record that commit SHA in the implementation PR;
3. rerun the Memory/conversation caller inventory and the requirements ledger validator;
4. replace all current `conversationId: String`/backend-detail assumptions with S-10's actual public local identity and transaction seam—never a temporary dual-ID adapter.

S-12 expects S-10 to own and expose these behaviors, whatever final symbol names S-10 lands:

- a stable restart-durable local session identity;
- a public owner-scoped local session/detail projection with readable local segments and conversation-local speaker labels;
- local title/overview/time fields needed by source presentation;
- an atomic deletion transaction hook in the same effective-owner GRDB pool so linked memories and pending Memory work can be cascaded;
- no requirement that a backend conversation ID exist.

Current pre-S-10 evidence is `TranscriptionSessionRecord.id: Int64?`, `getSessionWithSegments(id:)`, `getSessionByBackendId(_:)`, and `MemoryRecord.conversationId: String?`; the final plan deliberately does not freeze those pre-migration shapes.

If S-10 is unavailable, Cycles 1–5 can proceed, but Cycle 6, the source-navigation portion of Cycle 10, and final hosted contract cleanup in Cycle 13 are blocked. Do not fake a local source, retain `GET /v1/conversations/{id}` as a bridge, or add parallel IDs.

### Gate D — authority and release premise

Immediately before hard route/schema removal, re-read `FORK.md` and inspect the generated app-client contract. If this product has shipped or an independently retained non-Windows caller now consumes a memory route, stop Cycle 12 and obtain a new requirement decision. Do not infer a legacy population from upstream Omi provenance. Do not inspect or modify `desktop/windows/`; it is outside the bootstrap scope.

### Gate E — external compute and live infrastructure

- Unit/T2 work uses controllable fake OpenAI/Gemini boundaries and synthetic local owners.
- Real l1/l2/conflict/embedding acceptance requires an owned development backend, a test account, and valid owned OpenAI/Gemini credentials. Missing credentials block only the real-provider checks and final close, not hermetic implementation.
- The checkout does not prove owned GCP project IDs, deployed scheduler/job names, Firestore databases, provider indexes, traffic, secrets, or retention policy. Missing live inventory blocks live decommission only. It never permits targeting the `based-hardware` projects or using `./run.sh --yolo`.

## 6. Current production codeflow

### Page reads and paging today

```text
Memory hub -> MemoriesPage / MemoriesViewModel
  -> read cached rows from MemoryStorage / GRDB
  -> read persisted canonical-lifecycle capability from UserDefaults
  -> choose canonical or legacy local scope (`tierIsExplicit`)
  -> GET /v3/memories with backend offsets/capability headers
  -> merge/adopt server rows, prune missing rows, store backend IDs/tier
  -> run full-sync/reconciliation and reveal 100-row pages
```

`MemoriesPage.swift` still owns backend offset, capability, full-sync and reconciliation state even though `MemoryStorage.swift` can already query local rows. Loading/Retry currently imply a network refresh. Category-name search also still exists.

### Mutations today

```text
Add -> POST /v3/memories -> sync returned row into GRDB
Edit -> PATCH backend ID -> update local row by backend ID
Delete -> local soft delete -> DELETE backend -> four-second Undo or finalization
Bulk delete -> server capability/permission branch plus local soft deletion
Read/dismiss -> backend mutation plus local mirror
conversation deletion -> local soft-delete by backend conversation ID
                       -> backend retraction/refetch/prune
```

The current `MemoryIdentity` prefers `backendId` and falls back to `local_<rowid>`. `MemoryRecord` and the original `memories` migration still carry `backendId`, `backendSynced`, review/scoring, durable headline, device provenance, and server-source fields.

### Local producers today

- `MemoryAssistant` selects a non-excluded screenshot and Gemini proposes at most one high-confidence record. `MemoryAssistantTelemetry` inserts locally, POSTs remotely, records a remote receipt, and marks the row synced.
- `FocusAssistant` and `InsightAssistant` insert a local row and then create a backend Memory. `InsightStorage` separately reads/mutates backend Tips and retains a duplicate `StoredInsight` UserDefaults authority.
- the Add sheet and inline editor are server mutation paths.
- conversation processing runs in Python: `process_conversation.py` chooses legacy/canonical extraction, reads hosted People/profile/memories/transcripts, writes Firestore/vector state, and later runs hosted conflict handling.

### Retained readers today

- `ChatProvider`, `SuggestionAssistant`, `AboutUserCard`, `HomeStatusStore`, and parts of Focus/Insight already query `MemoryStorage`.
- `ChatToolExecutor` sends `get_memories` and `search_memories` to `/v1/tools/memories*`; normal Chat, the local managed-Pi relay, and realtime PTT retain those tool names but currently receive cloud results.
- `HomeSuggestionsStore`, `GoalsAIService`, and `AIUserProfileService` fetch `/v3/memories` for context.
- `DesktopAutomationBridge` snapshots, QA exports, creates, edits, and deletes through live Memory APIs before checking the cache.
- `TierManager` and Settings expose cache `synced/unsynced` statistics.

### Backend authority today

`backend/main.py` mounts `routers.memories`, `memory_admin`, `memory_product`, and `tools`. Together with `database/memories.py`, `database/memory_*`, `database/product_memory_items.py`, `models/memory_*`, `utils/memory/**`, `utils/memory_ingestion/**`, `utils/retrieval/**`, and `utils/llm/{memories,working_observations,promotion_proposals,promotion_routes,durable_memory_patches}.py`, they implement:

- `/v3/memories` CRUD, batch, review, baseline, read, and lifecycle exposure;
- `/memory/search`, `/memory/vector/search`, `/memory/archive/search`, and `/memory/admin/**`;
- `/v1/tools/memories` list/search;
- Firestore legacy/canonical records, evidence, ledgers, projections, rollout controls, review queues, vectors/outboxes/repair, graph/product reads, and source replacement;
- legacy and canonical model selection and persistence;
- memory personalization in mixed Chat, daily summary, goals, notifications, conversation processing, payment/unlock, users/migrations, account deletion, export, and review code.

### Scheduled and contract authority today

`backend/modal/memory_maintenance_job.py` plus its Dockerfile, two GCP workflows, runtime image entry, runtime-env contract, scheduler validator, checks, pre-push references, tests, docs, and dev-harness maintenance runner form a complete second control plane. The mixed desktop/backend contract workflow still runs hosted Memory parity fixtures. Route policy, app-client OpenAPI, generated Swift DTOs, gauntlets, and the synthetic dev harness all still describe hosted canonical Memories.

## 7. Complete caller and dependency inventory

This is the execution inventory. Repeat it after the S-10 rebase and again before deletion; new hits must be classified, not ignored.

| Surface | Verified current owner/files | S-12 action |
|---|---|---|
| Navigation | `MemoryHubDestination.swift`, hub/top-bar code, navigation persistence, compact menu, shortcuts/automation | Keep S-06 shape and regression tests. |
| Main Memories UI | `MainWindow/Pages/MemoriesPage.swift` | Adapt reads/mutations to local commands; preserve selected UI; delete capability/sync/category-search/rejected presentation branches. |
| Provenance/detail/export | `MemoryProvenance.swift`, detail panel code in `MemoriesPage.swift`, `ViewExporter.swift` | Narrow to retained local sources/fields and preserve selected layout/fixtures. |
| Local schema/model | `RewindDatabase.swift`, `RewindDatabase+ExternalSurfaceRetirement.swift`, `MemoryModels.swift` | Add authoritative lifecycle/vector/audit schema through forward migrations; later rebuild Memory storage without rejected columns. Preserve S-06 upgrade migrations. |
| Local store | `MemoryStorage.swift` | Turn cache/sync actor into the deep authoritative query/command module; remove server adoption, sync, prune, and backend-ID APIs after callers move. |
| Owner fencing | `RuntimeOwnerIdentity.swift`, `LocalMutationAuthorization.swift`, `EffectiveOwnerDatabaseBoundaryTests.swift`, `MemoriesViewModelOwnerFenceTests.swift` | Reuse effective-owner database partition, authorization snapshots, cancellation, and commit leases for all delayed/model-backed commits. |
| Add/edit/delete UI | Add sheet, inline editor, card menus, Undo state in `MemoriesPage.swift` | Adapt to local atomic commands and background lifecycle; retain validation and timings. |
| Screenshot producer | `MemoryAssistant.swift`, `MemoryAssistantTelemetry.swift`, its settings/test runner/tests | Keep extraction behavior; replace durability/sync telemetry with idempotent local admission. |
| Focus producer | `FocusAssistant.swift`, `FocusStorage.swift` | Move only Memory row writes/deletes/reads to local authority; do not absorb S-14's Focus-session/settings authority. |
| Insight producer/history | `InsightAssistant.swift`, `InsightStorage.swift` | Make tagged local Memory the first/only durable **Memory** record and remove cloud Memory calls. S-14 owns the separate `StoredInsight` cache, final Insight history/mutation authority, profile and settings cleanup. |
| Local readers | `ChatProvider.swift`, `SuggestionAssistant.swift`, `AboutUserCard.swift`, `HomeStatusStore.swift` | Keep and move to the final typed query API where needed. |
| Other context readers | `HomeSuggestionsStore.swift`, `GoalsAIService.swift`, `AIUserProfileService.swift` | Replace only `/v3` Memory reads with bounded local queries. Their goal/profile/cloud products remain later-slice owners. |
| Chat/PTT/Pi | `ChatToolExecutor.swift`, `APIClient+Tools.swift`, `DesktopCapabilityRegistry.swift`, `GeneratedToolExecutors.swift`, `GeneratedRealtimeTools.swift`, Node `omi-tool-manifest.ts`, tool relay/policy, Pi extension | Keep `get_memories`/`search_memories` names and transport; execute Memory reads/search on the Mac. Delete only the two backend API client methods and backend routes, not tool capabilities. |
| Generic local SQL | `ChatToolExecutor.executeSQL`, generated schema/help | Retain as a local `omi.db` tool; update schema descriptions for final columns. It is a local consumer, not a second authority. |
| Automation/E2E | `DesktopAutomationBridge.swift`; `memories.yaml`, `memory-crud.yaml`, `memory-depth.yaml`, `proactive-memory-writers-retention.yaml`, snapshots, core harness docs | Adapt actions to production local commands; add offline/restart/lifecycle/source/cross-owner proof. Do not create test-only persistence behavior. |
| Cache statistics | `TierManager.swift`, `SettingsContentView+Controls.swift` | Remove synced/unsynced meaning and use retained local totals only; S-21 later owns tier/gating deletion. |
| Desktop Memory API | `APIClient+Memories.swift`, `APIClient+Tools.swift`, generated `OmiApi.generated.swift` | Delete Memory CRUD/list/tool methods and server DTOs. Preserve or move co-located conversation finalization methods to the S-10-owned API file rather than deleting them. |
| Backend routers | `routers/memories.py`, `memory_admin.py`, `memory_product.py`, Memory branches in `tools.py`, registrations in `main.py`, Memory entries in `desktop_deprecated.py` | Delete hosted product routes; add only the proposed stateless `memory_compute.py` route. Removed endpoints must be absent/404, not 410/fake success. |
| Backend persistence | `database/memories.py`, `memory_*.py`, `product_memory_items.py`, `review_queue.py`, Memory branches in `vector_db.py` and mixed account/export helpers | Delete Memory documents, projection/vector/outbox/review/rollout authority. Retain shared providers/collections only with another proven caller and hand them to S-23/S-24. |
| Firestore manifests | root `firestore.rules`, `firestore.indexes.json`, Firebase/check tests | Remove Memory-owned collection rules and composite indexes after Python callers are gone; preserve unrelated account/product rules. |
| Backend model/domain | `models/memories.py`, `models/memory_*.py`, `models/product_memory.py` | Replace only the three retained transient wire contracts in a new narrow module; delete durable/cloud models. |
| Backend processing | `utils/memory/**`, `utils/memory_ingestion/**`, `utils/llm/memories.py`, `utils/llms/memory.py`, `working_observations.py`, promotion/consolidation modules, retrieval memory services/tools | Port accepted deterministic policy/contracts to Mac plus stateless compute; delete cloud selection/persistence and legacy routes. |
| Mixed backend callers | `routers/conversations.py`, `routers/users.py`, `routers/payment.py`, `utils/conversations/{process_conversation,merge_conversations}.py`, `utils/llm/{chat,daily_summary,goals,notifications}.py`, `services/users/{account_deletion,data_export}.py` | Remove cloud Memory reads/writes/retraction/unlock/export. Preserve unrelated route behavior and accept bounded local context only where a retained Mac caller actually supplies it. |
| Model configuration | `utils/llm/model_config.py`, LLM gateway configuration/tests, usage tracking | Remove obsolete `memories`, `learnings`, `memory_category`, and request-scope branches; pin l1/l2/conflict. S-22 owns deletion of the shared gateway/global profiles. |
| Hosted vectors/search | Memory branches in `database/vector_db.py`, Pinecone/Typesense adapters, repair outboxes | S-12 removes Memory callers and Memory-specific adapters; S-24 deletes shared/global provider infrastructure and credentials after all products migrate. |
| Knowledge graph | S-06 negative tests/manifests and historical migrations; broad searches may still find historical/requirement text | Keep required forward-upgrade and negative-guard evidence; no production writer/route/projection may remain. |
| Job/control plane | `modal/memory_maintenance_job.py`, Dockerfile, `gcp_memory_maintenance_job*.yml`, runtime env/images, validators, workflow contracts, concurrency/check manifests, pre-push, dev-harness maintenance runner, AGENTS/docs/tests | Delete complete repository control plane under IR-815; update every shared registry in the same cycle. |
| Shared deploy surfaces | Memory env/collection entries in `backend/deploy/runtime_env.yaml`, `backend/charts/backend-listen/**`, `backend/charts/pusher/**`, `gcp_backend*.yml`, `gcp_notifications_job.yml`, shared monitoring/check baselines | Remove only Memory flags, collection names, cleanup clauses and registrations. S-25 owns the shared services/charts themselves. |
| Hosted parity | `backend/testing/contracts/test_desktop_backend_parity.py`, `contract_tests/fixtures/memories.json`, mixed workflow, discovery registry/tests | After S-10 removes conversation cases, remove final Memory cases/file/job/triggers/prefix while retaining independent T0. |
| OpenAPI/route policy | `route_policy_manifest.yaml`, `route_policy_legacy_missing_routes.txt`, `docs/api-reference/app-client-openapi.json`, generator target list, generated Swift | Remove hosted routes and DTOs; register/generate the three transient compute contracts only if they are part of the app-client surface. |
| Tests/scripts/docs | roughly 176 backend files matching Memory names plus Mac tests, gauntlets, dev scenarios, `backend/utils/memory/ARCHITECTURE.md`, `PRODUCT.md`, `FORK.md`, component guides | Delete cloud-exclusive proofs; port accepted behavioral tests; update architecture/current-state docs and add a user-visible changelog fragment. |

## 8. Behavior classification

| Category | Behavior and dependencies |
|---|---|
| **KEEP AS IS** | Memory hub/Conversations navigation from S-06; About You/Insights/Manual categories; multi-select/counts; card/detail/inspector layout; tags; Tips reasoning and tooltip; Context; one-minute New rule; two-line preview and dual timestamps; screenshot FK/link behavior; four-second duration; existing Gemini screenshot extraction policy/cadence/exclusions/confidence/one-result rule; local owner database partition; tool names `get_memories`/`search_memories`; retained account/billing; historical schema migrations needed for upgrade. |
| **ADAPT** | `MemoryStorage` to sole authority; local stable identity/revision; lifecycle/audit/retry runner; local vectors; Add/edit/delete/Undo/bulk/read/dismiss; truthful local Loading/Retry; paging/search; source conversation identity/detail/cascade after S-10; screenshot/Focus/Insight producers; Chat/PTT/Pi/Home/profile/goals/proactive readers; automation and E2E; l1/l2/conflict as stateless compute; OpenAPI/client contracts for compute only. |
| **DELETE** | `/v3/memories`; `/memory/**`; backend `/v1/tools/memories*`; Firestore Memory stores, rollout/cohort/canonical-vs-legacy, graph/product projections, hosted vectors/repairs/outboxes, sync/reconcile/prune/retry IDs, review/scoring, visibility/persona, device provenance, durable headline, generic reasoning, protected-prefix handling, Workflow/category-name search, five `MemoryTier*` aliases, legacy model routes/selector/per-memory resolver, maintenance job/control plane, Memory parity fixtures/workflow/discovery residue, cloud-exclusive tests/scripts/docs. |
| **SIMPLIFY AFTER** | Collapse Memory reads/writes behind one typed `MemoryStorage` public surface; collapse UI canonical/legacy branches; merge pending processing/lifecycle scheduling behind one runner; share one bounded compute client/response validator across the three feature routes without combining prompts; reduce cache stats to local meanings; delete adapters/protocols introduced only by old server authority; split mixed files only where it leaves a clearer retained owner. |
| **OUT OF SCOPE / DEFERRED** | S-10's conversation authority; S-11's final Chat/Home journal and shell; S-14's Focus/Insight/profile/settings authority beyond their Memory rows, including deletion of the separate `StoredInsight` cache; S-21's Feature Tiers removal; S-22's shared LLM gateway/global model portfolio removal; S-23's non-Memory hosted products/shared product schema cleanup; S-24's global Typesense/Pinecone/object-store teardown; S-25's remaining shared service topology; S-30's repository-wide rebrand/privacy/copy pass; Windows; live cloud deletion without explicit authorization. |

## 9. Retained behavioral invariants

1. **One owner, one file.** Every Memory read and commit is scoped to the current effective owner's per-user `omi.db`. Account swaps cancel work, invalidate views, and prevent late model/provider results from committing through `LocalMutationAuthorization.withCommitLease`.
2. **Local acceptance is terminal durability.** Add/edit/screenshot/Focus/Insight/conversation admission succeeds when its local transaction commits. A provider or backend outage cannot roll back an accepted row.
3. **Model output is only a proposal.** Python never chooses local IDs, persists retries, advances lifecycle state, or mutates Memories. Mac revision/generation validation and one GRDB transaction decide the result.
4. **No mutation on invalid/stale output.** Provider, parse, schema, subject, evidence, conservation, stale revision, stale generation, owner-change, or cancellation failure leaves authoritative content/lifecycle unchanged and locally retryable or reviewable.
5. **Lifecycle fidelity.** Default excludes Archive; Short-term expiry metadata and tier badges remain; Archive requires explicit access/acknowledgement; every transition is deterministic, idempotent, audited, and recoverable after crash/restart.
6. **Literal and semantic search are different.** Visible Memory-page search preserves local case-insensitive content behavior, debounce, stale-result fencing and 100-row paging. Agent `search_memories` preserves semantic recall through transient query embeddings and locally persisted vectors; it must not degrade to `LIKE` only.
7. **Deletion is coherent.** The first individual delete durably hides the row; Undo within four seconds restores it; finalization removes the row, vector and pending work. A new delete finalizes the old one. Bulk default deletion excludes Archive. Conversation deletion atomically cascades linked Memory rows and processing work.
8. **Source fidelity.** Conversation candidates cite exactly one supplied local segment per quote and retain the stable local session link. Screenshot links use `screenshotId` with `ON DELETE SET NULL`. No hosted People/profile lookup repairs attribution.
9. **Presentation fidelity.** The exact subtitle is “Memories and insights saved on this Mac.” Preserve the selected loading, empty, no-results, cards, inspector, Tips, Context, New, timestamp, pagination, hover, navigation, and accessibility behavior—including the duplicated tooltip text quirk.
10. **Private by structure.** There is no public/private state, share/persona switch, cloud copy, external-device label, hosted export, or server search. Local app/window/manual/mic/confidence/time/conversation/screenshot provenance remains.
11. **No secret or sensitive logging.** The Mac has no OpenAI key. Requests are authenticated and bounded. Raw memory/transcript/screenshot-derived content is absent from backend logs, durable backend state, metrics labels, traces, retry stores, and error bodies.
12. **Adjacent retained paths stay intact.** Conversation, Task, Chat/Pi transport, generic `execute_sql`, screenshot capture, Focus/Insight behavior, account/billing, embeddings proxy, T0 desktop harness, and S-06 negative guards change only at the explicitly named Memory seam.

## 10. Target authority and ownership model

### Durable local module

`MemoryStorage` remains the deep module and sole GRDB entry point for product Memory behavior. Do not add a second repository around it. Its final public surface should expose typed commands and queries such as:

- list/count/literal-search/semantic-search by layer, category, date, tag and page;
- accept explicit assertion, accept screenshot/Focus/Insight assertion, and accept grounded conversation candidates;
- correct a current revision;
- mark read/dismissed;
- begin/undo/finalize individual deletion and delete Default layers;
- select/lease/recover due processing, normalize, consolidate, expire/archive, and record transition receipts;
- resolve a local source conversation and cascade its deletion;
- update/delete local embeddings atomically with the owning row.

Exact symbol names are chosen during implementation; the boundary above is the contract. Callers do not execute Memory SQL or mutate `MemoryRecord` directly, except the separately retained generic local SQL tool's read path.

### Local schema

Use forward GRDB migrations; do not rewrite historical migrations. Preserve row primary keys during table rebuild so local references remain valid. The final schema contains only retained state:

- `memories`: local primary key, content, category, layer, expiry, revision, tags, manual/source-conversation/screenshot/local provenance, confidence, Tips-only reasoning, read/dismiss flags, pending-delete deadline, created/updated/corrected timestamps;
- a Memory processing/lease table: operation kind, input revision/generation, bounded state, attempts/next attempt, owner-generation binding and terminal status—no backend IDs;
- a transition/audit table: idempotency key, from/to layer and revision, validated receipt references, outcome and timestamp;
- a local embedding table: memory ID + revision/model identity + encoded vector, with FK cascade.

The exact physical split can be simplified if one table safely hides the same invariants. Tests assert behavior through `MemoryStorage`, plus schema/migration tests for FKs/indexes and rejected-column absence. There is no owner column because the effective-owner database path is already the compiler/runtime boundary; tests must prove the correct file is selected.

### Lifecycle runner

Add one proposed `LocalMemoryLifecycleRunner` actor (new name, not a current file) owned by the Mac app lifecycle. It wakes on startup and a bounded in-process cadence, leases due work from `MemoryStorage`, obtains an authorization snapshot, calls the transient compute/embedding boundary, and commits only through a current-owner lease. It has an injected clock and external compute boundary for deterministic tests. It stores no duplicate state outside GRDB and performs no cloud scheduling.

### Transient Python compute

Add one proposed `backend/routers/memory_compute.py` router with three exact authenticated operations:

- `POST /v1/memory/compute/extract` -> `memory_l1`;
- `POST /v1/memory/compute/normalize` -> `memory_l2`;
- `POST /v1/memory/compute/consolidate` -> `memory_conflict`.

Each route has typed bounded request/response models in a new narrow `models/memory_compute.py` and a stateless service in `utils/llm/memory_compute.py` (all proposed new paths). It calls the named OpenAI GPT-4.1-mini feature, reports existing aggregate usage accounting, and returns a proposal. It does not import Firestore/Redis/vector/product Memory modules or log bodies. The Mac sends an opaque request/revision/generation identity only to bind the response; it remains the sole owner of durable identity and state.

`memory_l1` accepts at most the reviewed 32-candidate bounded local transcript packet and returns quote/evidence references. `memory_l2` accepts one explicit Add/Edit assertion and returns normalized content plus the retained structured subject/predicate/arguments/sensitivity/rationale. `memory_conflict` accepts one bounded generation of due candidates plus locally selected relevant active records and returns exactly one complete decision per candidate. Provider transport can use the current shared model primitive until S-22 replaces it; the endpoint and validation contract must not depend on premium/max/BYOK switching.

The retained existing `/v1/proxy/gemini/...:embedContent` is transient compute only. `EmbeddingService` creates/query-embeds text, while vector storage and similarity remain local. S-22 may later narrow that shared proxy without changing local Memory authority.

### UI and tool consumers

`MemoriesViewModel`, automation, Chat/PTT/Pi tool execution, and proactive/context readers consume typed `MemoryStorage` queries/commands. Keep generated tool manifests and tool names. Move only `.getMemories` and `.searchMemories` dispatch from `executeBackendTool` to local execution; conversation/action-item tools remain backend until their owners migrate them.

## 11. Ordered TDD cycles

Use strict RED -> minimum GREEN -> focused verification for one behavioral slice at a time. Commit only after the cycle and its focused checks are GREEN. Refactor/deletion follows the behavior that makes it safe; do not bulk-write all tests before production code. Internal fakes are avoided: tests use a temporary real GRDB database and fake only external time/model/network boundaries.

### Cycle 1 — protect the retained page and S-06 navigation under a failed Memory network

- **Intended behavioral RED:** open Memories with a temporary owner GRDB containing Short-term, Long-term and Archive rows while a network sentinel fails any Memory API call. Assert direct Memory navigation/Conversations hover behavior, Default/explicit layer filtering, category counts/multi-select, literal search/debounce fencing, card/detail/Tips/Context/New/timestamp/tooltip behavior, 100-row paging, and truthful local Loading/Retry/empty/no-results states. Assert the exact future subtitle. Existing focused UI tests remain part of the fence.
- **Why RED now:** `MemoriesViewModel` still reads server capability state, chooses canonical/legacy scopes, fetches `/v3/memories`, reconciles, and reports connection-shaped errors; the subtitle and category search are still old.
- **Minimum GREEN:** introduce an injectable production `MemoryStorage`/database seam into the view model, make initial/retry/page/filter reads local-only, and preserve the existing UI behavior without yet deleting all old API code. Use a network trap only to prove no call occurs.
- **Retained behavior protected:** IR-257, IR-260, IR-263–264, IR-268–272, IR-275–276, IR-282–284, IR-287–288 and S-06 navigation.
- **Expected files:** `MemoriesPage.swift`, existing Memory UI/view-model tests, navigation tests, `MemoryDetailPanelTests.swift`, `MemoryLayerFilterTests.swift`, local e2e snapshot/flow, and `PRODUCT.md` only when the behavior becomes truthful.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'Memor(iesViewModel|yLayerFilter|yDetailPanel|yHub)'` from `desktop/macos`; run the Memory flow linter/self-check after flow edits.
- **Deletion/simplification enabled:** server capability/legacy-scope reads can be made unreachable from the page. Full API/sync deletion waits for all callers in Cycle 9.
- **Stop condition:** stop if S-06 navigation has regressed or if a retained UI behavior cannot be distinguished from server authority; repair the retained behavioral seam before changing storage.

### Cycle 2 — establish owner-scoped local identity, revision, lifecycle, audit and vector schema

- **Intended behavioral RED:** against fresh and upgraded databases, create/query a local Memory, close/reopen the pool, and assert stable local identity, revision, category/layer/expiry, screenshot FK, source fields, processing lease, audit transition, and embedding cascade. Switch Alice -> Bob -> Alice and assert isolation plus late-commit rejection. No server ID is required for any query or mutation.
- **Why RED now:** the table is described as bidirectional sync, identity prefers `backendId`, tier authority is split by `tierIsExplicit`, and no local lifecycle/transition/embedding store exists.
- **Minimum GREEN:** add forward migrations and typed local records/commands in `MemoryModels.swift`/`MemoryStorage.swift`; preserve historical migrations; add the minimal processing/audit/embedding tables and revision semantics. Do not drop old sync columns until every caller moves.
- **Retained behavior protected:** IR-024, IR-260, IR-274, IR-281, IR-289, IR-291 and effective-owner database boundaries.
- **Expected files:** `RewindDatabase.swift`, proposed Memory-specific migration helper if size requires it, `MemoryModels.swift`, `MemoryStorage.swift`, migration/storage/owner-boundary tests, database architecture docs.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'Memory(Storage|Migration|LocalAuthority|Owner|Embedding)'`.
- **Deletion/simplification enabled:** local row IDs/revisions replace backend identity for new call sites; final rejected-column rebuild waits for Cycle 10.
- **Stop condition:** stop if the migration cannot preserve existing local row IDs/screenshot links or if it bypasses the effective-owner database/commit lease.

### Cycle 3 — make Add and inline Edit local, then normalize through transient `memory_l2`

- **Intended behavioral RED:** Add trims an assertion, rejects whitespace, atomically inserts a readable Manual Short-term row plus pending normalization, closes only after that commit, and keeps the draft on local failure. The runner sends one bounded l2 request; a valid current-revision proposal commits normalized text/receipt, while provider/parse/stale-revision/owner-change failures change no accepted content and remain retryable. Edit uses the same revision contract without erasing material detail.
- **Why RED now:** Add and edit depend on POST/PATCH/backend IDs; no Mac processing runner or stateless l2 endpoint exists.
- **Minimum GREEN:** implement the smallest Add/Edit storage commands, runner path, typed compute client, authenticated `/v1/memory/compute/normalize` route, l2 schema/subject validation, and local receipt commit. Keep one explicit l2 prompt; do not introduce global provider redesign.
- **Retained behavior protected:** IR-265–266, IR-278–279, IR-710 and the Short-term presentation from IR-260.
- **Expected files:** `MemoriesPage.swift`, `MemoryStorage.swift`, proposed runner/client, proposed backend compute router/models/service, `main.py`, route policy/OpenAPI/generated Swift if used, Add/Edit tests, backend route/service tests, offline LLM stub.
- **Focused verification:** Swift `./scripts/dev-feedback.py --once swift 'Memory(Add|Edit|Normalization|LifecycleRunner)'`; backend `.venv/bin/python -m pytest -q tests/unit/test_memory_compute_normalize.py` from `backend`.
- **Deletion/simplification enabled:** remove Add/Edit calls and mutation request types from `APIClient+Memories.swift`; final shared file cleanup waits for S-10 rebase and Cycle 10.
- **Stop condition:** stop if the route persists/logs raw content, if provider selection is not exactly OpenAI GPT-4.1-mini `memory_l2`, or if local Save waits for provider success.

### Cycle 4 — make individual delete, four-second Undo, read/dismiss and bulk default deletion atomic locally

- **Intended behavioral RED:** with an injected clock, individual deletion commits a durable hidden tombstone immediately, Undo within exactly four seconds restores it, expiry/X/a second delete hard-deletes it plus embedding/pending work, Archive allows individual deletion, and bulk Default deletion removes only Short-term/Long-term after confirmation while cancelling pending Undo. Read/dismiss survives reopen. No network call occurs.
- **Why RED now:** finalization and bulk safety are entangled with backend permissions/IDs and current tombstones do not own processing/vector cleanup.
- **Minimum GREEN:** add local transactional commands and clock-driven finalization in `MemoryStorage`/view model; update all UI mutation paths and automation to use them.
- **Retained behavior protected:** IR-267, IR-280, IR-289 and existing confirmation/Undo presentation.
- **Expected files:** `MemoryStorage.swift`, `MemoriesPage.swift`, `InsightStorage.swift` only for Memory read/dismiss/delete calls, `DesktopAutomationBridge.swift`, local mutation/Undo/bulk tests, `memory-crud.yaml`.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'Memory(Delete|Undo|Bulk|Read|Dismiss|Crud)'`.
- **Deletion/simplification enabled:** delete backend bulk/read/delete client calls and `APIClientMemoryBulkSafetyTests`/mutation tests after replacement behavior is GREEN.
- **Stop condition:** stop if hard deletion can leave a vector/lease orphan, if bulk can include Archive without explicit individual action, or if Undo is only in-memory and the initial delete is not durable.

### Cycle 5 — port deterministic Short-term/Long-term/Archive scheduling and crash recovery

- **Intended behavioral RED:** seed due/non-due Short-term rows and an in-flight lease, advance a fake clock, restart the store/runner, and assert expiry, retry/backoff, lease recovery, archive/default visibility, idempotent transition/audit records, cancellation, and exactly-once application of a validated fake consolidation proposal. A stale owner/generation commits nothing.
- **Why RED now:** lifecycle tier comes from the server cohort/job; no local scheduler, lease, audit, or recovery behavior exists.
- **Minimum GREEN:** port the accepted deterministic policy and safety checks from current `short_term_lifecycle.py`, `canonical_required_processing.py`, `canonical_consolidation.py`, and maintenance tests into the Mac runner/store. Fake only the external model result in this cycle; do not retain Python durable state.
- **Retained behavior protected:** IR-260 and the no-mutation/idempotency/owner rules of IR-710/730.
- **Expected files:** proposed local runner, `MemoryStorage.swift`, lifecycle models/migrations, startup/app lifecycle wiring, deterministic lifecycle tests, `PRODUCT.md`, local Memory architecture doc.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'Memory(Lifecycle|Transition|Recovery|Expiry|Archive)'`.
- **Deletion/simplification enabled:** hosted maintenance policy is now behaviorally replaceable; actual backend/job deletion waits for real conflict integration and caller migration.
- **Stop condition:** stop if an existing hosted rule cannot be traced to an accepted IR-260 behavior, or if a local rule would require an unreviewed product timing/policy choice.

### Cycle 6 — admit grounded conversation memories and bind source navigation/deletion to S-10

- **Intended behavioral RED:** from an S-10 local session with local speaker-labelled segments, the runner sends one bounded l1 packet, accepts at most 32 candidates only when each quote matches exactly one supplied segment and subject attribution is valid, creates local Short-term rows/audit/source links, opens source detail locally in place, and atomically cascades linked rows/work on conversation deletion. Python stores nothing. Invalid quotes, duplicates, stale session revisions and owner changes commit nothing.
- **Why RED now:** extraction runs in hosted conversation processing and writes Firestore/vector state; Memory source navigation fetches a backend conversation by String ID; deletion retracts/refetches remotely.
- **Minimum GREEN:** after Gate C, consume S-10's exact public local session/detail/deletion seam; add `/v1/memory/compute/extract`, l1 typed validation, Mac quote/subject/admission logic, local source navigation, and same-pool cascade.
- **Retained behavior protected:** IR-285–286 and IR-728, including local name/language/context inputs and separation from screenshot/manual paths.
- **Expected files:** S-10's landed `TranscriptionStorage`/models/deletion coordinator only at its exposed extension seam, `MemoryStorage.swift`, Memories detail/navigation, proposed compute client/router/models/service, `process_conversation.py` Memory branches, conversation/Memory integration tests, source-link e2e.
- **Focused verification:** Swift `./scripts/dev-feedback.py --once swift 'Memory(Conversation|Source|Extraction|Cascade)'`; backend `.venv/bin/python -m pytest -q tests/unit/test_memory_compute_extract.py`.
- **Deletion/simplification enabled:** remove hosted conversation-memory extraction/admission/source replacement/retraction and the Memory page's backend detail fetch.
- **Stop condition:** hard stop without integrated S-10; also stop if its deletion seam cannot atomically cascade in the owner DB or if segment evidence lacks stable local identity.

### Cycle 7 — make semantic Memory recall and conflict consolidation local-authoritative

- **Intended behavioral RED:** creating/correcting/deleting a Memory updates/removes its local vector; a semantically related query with no matching substring returns the same bounded tool result shape from local similarity; owner A cannot search owner B. A due generation sends only selected local candidates/relevant active rows to `memory_conflict`; valid one-decision-per-input output atomically promotes/archives/reviews/rejects and create/duplicate/replace/merge/keep-both, while missing/invented/conflicting/stale references change nothing and retry/review locally.
- **Why RED now:** page search is literal only; agent semantic search uses hosted vector IDs plus Firestore; consolidation hydrates and commits cloud state.
- **Minimum GREEN:** integrate `EmbeddingService` with the local embedding table/similarity implementation, add local `MemoryStorage.semanticSearch`, implement `/v1/memory/compute/consolidate`, and port deterministic conservation/allowlist/supersession validation to the Mac transaction.
- **Retained behavior protected:** IR-260, IR-264, IR-710, IR-730 and the reviewed broad-vs-semantic tool distinction. Visible page search remains literal.
- **Expected files:** `MemoryStorage.swift`, proposed runner/client, `EmbeddingService.swift` only at its public result seam, Chat tool formatting helper, proposed backend compute modules, semantic/conflict tests, offline provider fixtures.
- **Focused verification:** Swift `./scripts/dev-feedback.py --once swift 'Memory(Semantic|Embedding|Conflict|Consolidation)'`; backend `.venv/bin/python -m pytest -q tests/unit/test_memory_compute_consolidate.py`.
- **Deletion/simplification enabled:** remove Memory Pinecone/Typesense search and vector repair callers; shared provider infrastructure waits for S-24.
- **Stop condition:** stop if vectors or queries would be persisted remotely, if literal page search is silently changed to semantic, or if a batch can partially commit after validation failure.

### Cycle 8 — move screenshot, Focus and Insight Memory writers to the local admission terminal

- **Intended behavioral RED:** screenshot extraction keeps cadence/exclusions/confidence/one-result/dedup/provenance/notification and succeeds after one idempotent local commit even when every Memory HTTP route fails. Focus writes the accepted local category/tags. Insight's first durable Memory row is `interesting` with Tips data and its Memory headline is notification-only; no generated Insight Memory is corrected or synchronized by a later cloud write.
- **Why RED now:** each writer still POSTs and marks synced; Insight also holds duplicate UserDefaults state and durable headline.
- **Minimum GREEN:** route each producer through the appropriate `MemoryStorage` admission command and rewrite `MemoryAssistantTelemetry` around local durability stages. Change only the Memory-row branches in Insight/Focus storage; preserve the separate `StoredInsight` cache and all non-Memory Focus/Insight behavior for S-14 to consolidate.
- **Retained behavior protected:** IR-033, IR-277, IR-281, IR-283–284, IR-290 and local owner/dedup/notification behavior.
- **Expected files:** Memory Assistant/Telemetry/tests, Focus Assistant/Storage Memory branches, Insight Assistant/Storage/tests, Memory models/store, proactive writer e2e, notification presentation.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'MemoryAssistant|Focus.*Memory|Insight.*Memory|ProactiveMemory'` and the focused `proactive-memory-writers-retention.yaml` flow.
- **Deletion/simplification enabled:** delete markSynced/remote receipt/retry stages and durable Memory headline storage; hand the separate `StoredInsight` cache to S-14 explicitly.
- **Stop condition:** stop if this absorbs assistant settings, Focus sessions, AI Profile, or other S-14 authority; only Memory records and their consumption move here.

### Cycle 9 — migrate every retained reader, Chat/PTT/Pi tool, and automation action

- **Intended behavioral RED:** with `/v3/memories` and backend `/v1/tools/memories*` forced to fail, normal Chat, a managed-Pi child, realtime PTT tool relay, Home suggestions/status, goal context, AI Profile context, Suggestions, About User, settings counts, QA export and CRUD automation all observe the same owner-local rows. `get_memories` preserves date/offset/limit formatting; `search_memories` preserves bounded content/category/local-time/relevance formatting and empty/error results. Owner change during a tool read fails closed.
- **Why RED now:** multiple callers fetch `/v3`; ChatToolExecutor groups Memory tools with backend RAG; automation creates/edits/deletes remotely; settings expose sync stats.
- **Minimum GREEN:** move all listed callers to bounded typed local queries/commands, add local tool formatters, split `.getMemories/.searchMemories` from `executeBackendTool`, remove only their APIClient methods, and preserve generated tool manifests/relay/capability names.
- **Retained behavior protected:** local personal grounding for normal Chat/PTT/Pi/proactive surfaces, existing tool arguments/result contracts, owner authorization, and adjacent conversation/action-item tools.
- **Expected files:** all Mac caller files listed in Section 7, `APIClient+Tools.swift`, Chat executor/capability/agent tests, automation bridge/actions, E2E flows/docs/gauntlet, Settings/TierManager Memory counters.
- **Focused verification:** Swift `./scripts/dev-feedback.py --once swift 'ChatTool.*Memor|Home.*Memor|Goals.*Memor|Profile.*Memor|DesktopAutomation.*Memor|AuthorizedToolOwner'`; `cd desktop/macos/agent && npm test -- omi-tool-manifest.test.ts tool-relay.test.ts external-surface-authority.test.ts`.
- **Deletion/simplification enabled:** every retained Mac caller is now independent of hosted Memory authority, permitting Cycles 10–13.
- **Stop condition:** stop if a retained tool invocation bypasses the Mac and executes in Python, if a local tool changes its public name/schema, or if another in-tree non-Windows caller remains unclassified.

### Cycle 10 — remove Mac cache/sync identity and rejected Memory presentation/schema residue

- **Intended behavioral RED:** migrate a pre-S-12 database and a fresh database, then assert retained rows/UI survive while final schema/domain/UI contains no backend ID/sync/capability/legacy scope, category search, protected prefix handling, device provenance, public/private, review/scoring, durable headline, generic non-Tips reasoning, dead edit sheet, or `MemoryTier*` alias. Exact subtitle and local source labels render. `screenshotId` and local conversation links still work.
- **Why RED now:** these fields/branches/aliases remain in current migrations, `MemoryRecord`, `ServerMemory`, page/UI and tests; some S-06 deletions left required storage cleanup for S-12.
- **Minimum GREEN:** rebuild the current Memory table through a forward migration preserving retained rows/IDs/FKs, reduce `MemoryRecord`, delete sync/reconciliation methods and DTOs, remove rejected UI branches and five aliases, and move any co-located retained conversation methods out of `APIClient+Memories.swift` without a compatibility alias.
- **Retained behavior protected:** IR-258–262, IR-272–276, IR-281–292, S-06 graph upgrade behavior, and all Cycles 1–9.
- **Expected files:** `RewindDatabase.swift`, external-surface migration tests, `MemoryModels.swift`, `MemoryStorage.swift`, `MemoriesPage.swift`, `MemoryProvenance.swift`, `APIClient+Memories.swift`, generated Swift, view fixtures/tests, schema/upgrade tests, changelog fragment.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'Memory(Migration|Provenance|Detail|Layer|LocalAuthority|Citation)'`; run `desktop/macos/scripts/swift-format-wrapper.sh format -i` on touched non-generated Swift files.
- **Deletion/simplification enabled:** delete obsolete API/sync/reconciliation tests (`APIClientMemory*`, `MemoryAuthoritativeTierSync`, `MemoryReconciliationScope`, `ServerMemoryV17Decoding`) only after equivalent local behavioral tests are GREEN.
- **Stop condition:** stop if table rebuild changes a local ID, breaks fresh-vs-upgrade parity, drops screenshot/source links, or deletes historical S-06 migrations needed for an old install to reach the final schema.

### Cycle 11 — converge on three stateless Memory compute workloads and delete old model routes

- **Intended behavioral RED:** FastAPI TestClient calls each authenticated compute endpoint with bounded synthetic data and a fake external model, observes the exact typed proposal, usage event, no raw-content log and zero Firestore/Redis/vector writes; over-limit/invalid/unauthenticated input fails closed. Model configuration exposes exactly `memory_l1`, `memory_l2`, and `memory_conflict` for Memory, each pinned to OpenAI GPT-4.1-mini. Searches find no callable legacy extractor/category/request-scope/per-memory resolver.
- **Why RED now:** there is no compute router; l1/l2/conflict are embedded in hosted durable modules beside `memories`, `learnings`, `memory_category`, cohort selection, legacy writes and provider profile branches.
- **Minimum GREEN:** finish the narrow compute module established in Cycles 3/6/7, extract only accepted prompts/contracts/validators from current files, remove obsolete feature keys/callers/usage branches and old conflict helper, and ensure the new service imports no durable Memory module.
- **Retained behavior protected:** exact l1/l2/conflict prompts, structured contracts, validation, usage accounting, and provider/model decisions from IR-710/728/730.
- **Expected files:** proposed backend compute modules, `utils/llm/model_config.py`, shared usage/config only at Memory entries, old `utils/llm`/`utils/memory` files, unit/integration tests, OpenAPI/route policy/docs.
- **Focused verification:** `cd backend && .venv/bin/python -m pytest -q tests/unit/test_memory_compute_*.py tests/unit/test_omi_qos_tiers.py tests/unit/test_llm_usage_endpoints.py` with exact selections adjusted to landed test names.
- **Deletion/simplification enabled:** legacy `memories`, `learnings`, `memory_category`, `memory_system_request_scope`, old ingestion/cohort/compatibility and exclusive tests/scripts can be deleted. S-22 later removes the shared gateway/global profiles; do not duplicate that work.
- **Stop condition:** stop if a supposedly shared helper still imports cloud Memory authority, if a removed feature has a retained caller, or if direct-provider transport cannot yet move without S-22—retain only the shared provider primitive and record the handoff, never a second Memory route.

### Cycle 12 — hard-delete Python Memory product authority and update generated contracts

- **Intended behavioral RED:** a composed backend app exposes the three compute POSTs but returns 404 for every `/v3/memories`, `/memory/**`, and `/v1/tools/memories*` method. Account/export/conversation/payment/chat/goals/notification paths perform no Memory collection/vector read/write. The generated app-client has compute DTOs only and no `MemoryDB`/Memory CRUD operations. Mac tests remain GREEN with those routes absent.
- **Why RED now:** routers are mounted, `desktop_deprecated.py` returns 410 for some Memory paths, Firestore/product/vector services and mixed callers remain, and OpenAPI/route policy/generated clients advertise them.
- **Minimum GREEN:** remove router registrations and Memory branches, delete exclusive database/models/services/ingestion/retrieval/product/admin/review/vector code, prune Memory clauses from mixed callers and account/export registries, remove Memory collection rules/indexes from root Firestore manifests, remove deprecated 410 entries, regenerate route policy/OpenAPI/Swift, and update S-06's adjacent route-retirement assertion to a truly retained endpoint rather than `/v3/memories`.
- **Retained behavior protected:** account/auth/billing, conversations/tasks, normal backend/model routes, local Chat/Pi transport, transient compute, shared embedding proxy and unrelated product data.
- **Expected files:** backend routes/main/database/models/utils/services/mixed callers from Section 7; root `firestore.rules`/`firestore.indexes.json`; route policy/missing baseline; OpenAPI generator/snapshot/generated Swift; backend route/absence tests; component docs.
- **Focused verification:** backend Memory compute/route-absence tests; `cd backend && scripts/openapi_runner.sh scripts/route_policy_inventory.py --manifest route_policy_manifest.yaml --check --report-only`; regenerate with `scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py`, then require `--check` GREEN.
- **Deletion/simplification enabled:** the backend has no product Memory authority; broad cloud-exclusive test deletion becomes safe.
- **Stop condition:** stop if `FORK.md` release premise changed, if a non-Windows retained caller remains, if a mixed helper cannot be separated without deleting retained behavior, or if removal would delete shared vector/provider infrastructure owned by S-24/S-22.

### Cycle 13 — delete maintenance/contracts/harness residue and close repository authority

- **Intended behavioral RED:** static ownership checks and component tests require no Memory Cloud Run image/job/scheduler/workflow/env/secret/rollout/monitoring entry; no hosted Memory parity file/fixture/job/discovery prefix; no cloud Memory dev scenario/maintenance runner; no active architecture/runbook/gauntlet claims Firestore authority. The independent desktop T0 job remains. Broad residue searches classify every remaining hit as retained local behavior, shared later-slice infrastructure with a named owner, historical migration/changelog, negative test, or requirement/roadmap text.
- **Why RED now:** the full job control plane, mixed contracts, discovery registry, memory-continuity gauntlets, V3 synthetic scenarios, runtime/config/check registrations and hosted architecture docs exist.
- **Minimum GREEN:** delete the IR-815 job/control-plane source and exclusive tests; remove Memory cases/fixture and, after S-10's conversation removal, delete the final parity file/contracts job/triggers/prefix and update `test_check_unit_test_discovery.py`; preserve T0. Move only the independently required synthetic Auth/local-profile seed into a neutral existing/new dev-harness owner, then delete the cloud-Memory scenario/maintenance interface without a compatibility alias. Update `AGENTS.md` component guides, `PRODUCT.md`, `FORK.md` current-state text, architecture docs, E2E docs, checks/pre-push/runtime registries and changelog.
- **Retained behavior protected:** local harness safety/auth, T0 self-check, backend/desktop suites, local lifecycle tests, account deletion, shared provider infrastructure and later-slice registries.
- **Expected files:** both memory-maintenance workflows, job/Dockerfile, runtime env/images, validators, workflow/check/concurrency/pre-push registries, dev harness/Makefile/docs/tests, hosted parity artifacts, discovery script/tests, cloud Memory e2e/gauntlets, component/product/provenance docs.
- **Focused verification:** job/runtime/discovery/check unit tests impacted by deletion; `./desktop/macos/scripts/desktop-core-harness.sh --self-check --skip-backend-contracts`; residue commands in Section 13.
- **Deletion/simplification enabled:** final repository closure; S-25 consumes an already absent job, S-23/S-24/S-22 receive only explicitly shared handoffs.
- **Stop condition:** hard stop if S-10 has not removed conversation parity ownership, if deleting a harness seed breaks independently retained local auth with no neutral owner, or if a residue hit lacks a proven owner/classification.

## 12. Cross-slice ownership and handoffs

| Slice | S-12 owns | S-12 consumes / hands off / must not do |
|---|---|---|
| S-06 | Regression protection for already deleted graph/Brain Map/public/device/Workflow UI dependencies that intersect Memory | Consume final navigation and migrations. Do not recreate graph or delete historical upgrade/negative guards. |
| S-10 | Memory's local source link, l1 input/admission integration, and Memory cascade inside the exposed transaction seam | Consume stable local session/detail/segment/deletion APIs after rebase. Do not own conversation storage, sync teardown, speaker product, summary, or task cascade. |
| S-11 | Local Memory tool/query behavior and bounded context supplied to Chat/Home | Hand off a stable local query surface. Do not own Chat journal/session/Home shell final authority. |
| S-14 | The Memory rows read/written by Focus, Insights, proactive context, and AI Profile; remove their Memory cloud calls | Hand off local queries and the still-separate `StoredInsight` cache for S-14's authorized consolidation. Do not localize all Focus sessions, Insight history/settings, assistant settings, or AI Profile sync. |
| S-21 | Only truthful local Memory count semantics needed by current Settings/TierManager callers | Do not delete the full Feature Tiers product; S-21 consumes simplified local counts. |
| S-22 | Exact three transient Memory workload contracts and pinned model behavior | Hand off removal of shared LLM gateway, global premium/max/BYOK profiles and provider transport. Do not keep old Memory routes to make S-22 easier. |
| S-23 | Delete Memory-exclusive backend product routes/schemas and Memory entries in shared account/export registries | Hand off non-Memory hosted products and shared container cleanup. Do not delete a shared registry/container with retained records. |
| S-24 | Establish local Memory vectors/search and remove Memory-specific hosted callers/adapters | Hand off global Pinecone/Typesense/object-storage credentials, services, alerts and shared adapters after all products migrate. |
| S-25 | Delete the complete Memory-specific job repository control plane under IR-815 | S-25 consumes the absence and deletes only later shared topology/live-inventory residue. No duplicate/no-op job remains. |
| S-30 | Exact IR-287 subtitle and truthful local Memory source/error copy now | Hand off repository-wide brand/privacy/legal copy validation; do not postpone the required subtitle. |

Shared-file rule: edit only the Memory-owned branch in mixed files, run the adjacent retained tests, and leave the file with a single truthful owner. If separation is needed, move retained code to its actual owner and delete the obsolete branch; do not leave deprecated aliases.

## 13. Repository residue-search strategy

Run searches after each deletion cycle and a final clean-tree pass. `rg` success is not automatically failure: classify every hit as **retained local**, **shared/deferred with named slice**, **historical upgrade/changelog**, **negative guard**, or **unexplained blocker**. An unexplained hit blocks completion.

```bash
# Mac remote/cache authority
rg -n -i 'backendId|backendSynced|markSynced|syncServerMemor|reconcil.*memor|prun.*memor|MemoryReadCapability|tierIsExplicit|X-Omi-Memory' desktop/macos

# Removed product routes and hosted authority
rg -n '/v3/memories|/v1/tools/memories|/memory/(admin|search|vector|archive)' backend desktop/macos .github docs scripts contract_tests
rg -n -i 'database\.memories|memory_(apply|ledger|outbox|projection|rollout|compatibility)|product_memory|review.queue|non.active.memory' backend
rg -n -i 'memory_items|memory_operations|memory_outbox|memory_review_queue|MEMORY_MODE|MEMORY_ENABLED_USERS|MEMORY_V3_GET_ENABLED|MEMORY_TYPESENSE_COLLECTION' firestore.rules firestore.indexes.json backend/deploy backend/charts .github

# Rejected fields/UI/model aliases
rg -n 'MemoryTier(Filter|Badge|Scope|Tests)?|\[Protected\]|\[Encrypted\]|primaryCaptureDevice|captureDeviceIds|userReview|reviewed|backendSynced|backendId|memory_category|memory_system_request_scope' desktop/macos backend
rg -n -i 'Workflow|This device|public.*memory|private.*memory|durable.*headline|Memory.*Reasoning' desktop/macos backend

# Old model and hosted search routes
rg -n "get_llm\(['\"](memories|learnings|memory_category)['\"]\)|['\"](memories|learnings|memory_category)['\"]:" backend
rg -n -i 'search_memories_by_vector|memory_vector|pinecone.*memor|typesense.*memor' backend desktop/macos

# Job/control-plane/contracts
rg -n -i 'memory[-_ ]maintenance|canonical_short_term_maintenance|MEMORY_MAINTENANCE' .github backend scripts Makefile
rg -n 'testing/contracts|test_desktop_backend_parity|contract_tests/fixtures/memories.json|desktop-backend-contracts' .github backend scripts contract_tests FORK.md

# Knowledge graph: only S-06 historical migration/negative evidence may remain
rg -n -i 'Brain Map|Memory Atlas|knowledge.graph|local_kg_|graph_projection' desktop/macos backend .github docs

# Inventory every surviving Memory-named source/test instead of trusting a narrow list
rg --files backend desktop/macos .github scripts docs contract_tests | rg -i 'memory|memories' | sort

# No accidental Windows work and no unrelated scope
git diff --name-only 0d9934c...HEAD
git diff --check
```

Also regenerate a backend route inventory and diff it against route policy. Removed routes must be absent rather than added to a “legacy missing” or deprecated 410 list. The only new Memory HTTP paths are the three compute POSTs.

Expected broad-search exceptions include `bootstrap-scaffold/**`, historical changelogs, the original create/drop migrations required for upgrades, local `memories` schema/tool descriptions, retained l1/l2/conflict names, retained local vector code, S-06 negative tests, and later-slice handoff docs. Record the exact exception file and reason in the PR; do not introduce a permanent allowlist unless an existing mechanical check requires it.

## 14. Focused and component-level verification commands

These are future implementation commands, not planning results.

### Focused Swift loops

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'Memory'
./scripts/dev-feedback.py --once swift 'MemoriesViewModel|MemoryStorage|MemoryLifecycle|MemoryCompute'
./scripts/dev-feedback.py --once swift 'ChatTool.*Memor|AuthorizedToolOwner|EffectiveOwnerDatabase'
./scripts/dev-feedback.py --once swift 'MemoryAssistant|Insight.*Memory|Focus.*Memory'
```

Use narrower filters per cycle. Run Swift formatting on touched non-generated files:

```bash
desktop/macos/scripts/swift-format-wrapper.sh format -i <touched-swift-files>
```

### Focused backend loops

```bash
cd backend
.venv/bin/python -m pytest -q tests/unit/test_memory_compute_*.py
.venv/bin/python -m pytest -q tests/unit/test_s12_memory_route_retirement.py
.venv/bin/python -m pytest -q tests/unit/test_check_unit_test_discovery.py
scripts/openapi_runner.sh scripts/route_policy_inventory.py --manifest route_policy_manifest.yaml --check --report-only
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
```

The first two test paths are planned new names and must be adjusted to the final landed names. They must run through FastAPI/TestClient or the public stateless service with a fake external model, not assert source order.

### Agent/runtime and E2E checks

```bash
cd desktop/macos/agent
npm test -- omi-tool-manifest.test.ts tool-relay.test.ts external-surface-authority.test.ts

cd ../
./scripts/desktop-core-harness.sh --self-check --skip-backend-contracts
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-s12-memories --port <isolated-port>
```

Update the T2 offline stub and flows so Add/edit/delete/restart/lifecycle/source/tool behavior exercises production commands. Do not use the old hosted Memory fixture as the proof.

### Component and repository gates

```bash
cd backend
bash test-preflight.sh
bash test.sh

cd ../desktop/macos
./test.sh

cd ../..
python3 bootstrap-scaffold/validate-requirements-ledger.py
make preflight
git diff --check
```

Because this changes a broad product boundary, the implementation PR also runs `scripts/pr-preflight --suggest`, declares the failure class in every `fix:` commit if applicable, drafts the PR body, and validates it with `scripts/pr-preflight --pr-body-file /tmp/pr-body.md`. No PR is opened or merged without the repository's authorization rules.

## 15. Real named-bundle and user-path acceptance

Use only the owned local harness first; never `--yolo`, never production Omi apps, and never upstream data.

```bash
PROVIDER_MODE=offline make dev-up
make dev-init
make desktop-run-local DESKTOP_APP_NAME=omi-s12-memories DESKTOP_USER=alice
cd desktop/macos
./scripts/omi-ctl health
./scripts/omi-ctl navigate memories
./scripts/omi-ctl actions
```

Cycle 13 must make `make dev-init` establish the final neutral synthetic Auth/profile scenario required by `desktop-run-local`; do not preserve `seed-memory-scenario` as an alias for the deleted hosted-Memory fixtures.

Exercise and retain evidence for this real path:

1. navigate through the Memory hub by direct click, hover to Conversations, compact navigation, Cmd+2 and automation; verify S-06 behavior;
2. with Alice, create a whitespace-trimmed Manual Memory; observe immediate local Short-term presentation and later offline-stub normalization without a `/v3` call;
3. edit it, restart the named bundle, and verify corrected text, tier, audit and pending/recovered processing;
4. create enough synthetic rows to prove 100-row paging/final-ten prefetch/manual load, category multi-select/counts, literal search/debounce/no-results, Default vs Archive and Short-term expiry text;
5. verify card/inspector/Tips/Context/New/timestamps/tooltip quirks, exact subtitle, local provenance, screenshot link and source conversation navigation/back;
6. delete/Undo within four seconds, let another delete expire, close another pending delete with X, delete an Archive item individually, and run **Delete Default Memories** while Archive survives;
7. invoke `get_memories` and semantically phrased `search_memories` through normal Chat, one managed-Pi child and PTT; verify the same local content and no backend Memory route;
8. trigger the screenshot/Focus/Insight synthetic production seams; verify first local durability, notifications, local history/read/dismiss/delete and no duplicate Insight Memory cache;
9. switch Alice -> Bob during an in-flight normalization/consolidation/embedding call; verify no Alice result appears or commits in Bob, then return to Alice and verify restart recovery;
10. make the Python Memory product routes unavailable after authentication (or use the bounded owned fault seam), repeat local page CRUD/search/paging/restart, and verify local behavior. Transient model-dependent work may enter truthful retry state, but accepted local rows and all non-model mutations continue;
11. inspect named-bundle logs through `./scripts/omi-ctl log-path`: no raw content, no `/v3/memories`, no `/v1/tools/memories`, no sync/reconcile/markSynced attempt, and no owner-crossing commit.

Use `agent-swift connect --bundle-id com.omi.omi-s12-memories`, snapshot, and screenshot only for UI/accessibility evidence the semantic bridge cannot expose. Do not use or restart `/Applications/Omi.app` or `Omi Beta.app`.

After the hermetic path is GREEN, repeat only the l1/l2/conflict/embedding cases against an **owned development** backend and synthetic account with valid owned provider credentials. Record endpoint, test account, request bounds, model identity and non-persistence/log evidence. Missing credentials block final model acceptance and must be reported; they do not justify using Omi's hosted backend.

## 16. Repository closure versus separately authorized live operational closure

### Repository closure owned by S-12

S-12 closes in source when:

- local Memory behavior and all retained callers are GREEN offline/restart/owner-switch;
- only the three stateless compute routes remain in Python;
- hosted Memory routes, persistence, model selectors, search/vector callers, job source/control plane, generated contracts, tests, fixtures, scripts, docs and configuration are removed;
- mixed registries and component guides truthfully reflect absence;
- S-10's conversation contract handoff and T0 preservation are complete;
- residue is fully classified and component/preflight gates pass.

Deleting repository workflow/manifests prevents redeployment but does not prove an already deployed resource or stored data is gone.

### Live operational closure requires separate explicit authorization

After repository implementation is merged through the authorized process, prepare a read-only inventory for each **owned** environment:

- Cloud Run `memory-maintenance-job` revisions/images and Scheduler `memory-maintenance-hourly` (actual names must be read, never guessed);
- Memory-specific service accounts/IAM, secrets, env vars, alerts/dashboards and artifact images;
- Firestore Memory collections/subcollections/control documents, indexes and retention rules;
- Redis Memory keys/cursors/leases;
- Pinecone/Typesense Memory namespaces/indexes and repair queues;
- any GCS/object paths containing Memory product data;
- traffic/caller/access logs proving no remaining client.

The plan does **not** authorize deletion of any item above. Do not query or mutate upstream `based-hardware` production/dev resources. With explicit authorization and verified owned project IDs, create a target-by-target runbook with backup/retention/legal decisions, dry-run inventory, exact commands, rollback limits and evidence. S-24 owns global hosted vector/search teardown and S-25 consumes broader service-topology closure; coordinate rather than deleting a shared provider prematurely.

Missing owned project IDs, credentials, retention policy, customer/data decision, or proof of zero callers blocks that live run only. Repository closure can still be reported separately, but the slice is not represented as operationally decommissioned.

## 17. Risks, ambiguities, and explicit stop points

| Risk / missing input | Blocks | Safe work before resolution | Evidence to reopen |
|---|---|---|---|
| S-10 not integrated | Cycle 6, source portion of Cycle 10, final parity deletion in Cycle 13 | Memory-exclusive Cycles 1–5 | Exact integrated SHA plus stable local session/detail/segment/deletion public seam and refreshed inventory. |
| S-25 also names memory-maintenance job | Any attempt to leave or recreate duplicate control-plane ownership | All local behavior and S-12 repository deletion | IR-815 remains authority: PR records S-12 deletion; S-25 handoff records only shared/live topology residue. Stop on a contrary live decision. |
| Shared S-22 provider/gateway code | Deletion of global QoS/gateway/provider primitives | Typed three-route behavior, old Memory feature deletion | Reference trace proves no non-Memory caller, or S-22 integration SHA. Keep shared primitive only, not Memory compatibility routes. |
| Shared S-24 Pinecone/Typesense code | Global credential/service/index deletion | Local vector index and removal of Memory-specific callers/adapters | S-24 inventory proving every product migrated and explicit operational authorization. |
| Shared S-14 Focus/Insight/Profile state | Broad local-authority or settings cleanup | Move only Memory reads/writes and duplicate Insight Memory record | S-14 integrated owner shape; no expansion from Memory rows into assistant settings/profile/session state. |
| Provider credentials/quality evidence unavailable | Real-provider named-bundle close for l1/l2/conflict/embedding | All hermetic tests and offline stub T2 | Owned dev endpoint/account, OpenAI/Gemini credentials, expected model identity and permission to transmit synthetic bounded data. |
| Live project/resource/retention data unavailable | Live cloud/data decommission | Complete repository plan/implementation and read-only local tests | Exact owned project/database/index/job IDs, authorization, retention/legal choice and zero-caller evidence. |
| Product has shipped after this plan | Hard API/schema removal in Cycle 12 | Local behavior behind current internal branch only | Updated released-contract requirement and migration/sunset decision. Never invent compatibility. |
| Existing local migration cannot preserve IDs/FKs | Cycle 10 schema reduction | Additive authoritative schema and caller migration | Fresh+upgrade behavioral proof with stable row IDs, screenshot/source references and rollback-safe migration. |
| Ported lifecycle policy is ambiguous | Cycle 5/7 affected transition | CRUD, search, owner fencing, pending state | Trace to a current hosted policy plus an accepted IR-260/710/730 behavior. If no decision covers it, stop and request a requirement decision. |
| A broad residue search finds a new caller | Relevant deletion cycle and final close | Unrelated already-GREEN cycles | File/symbol traced end to end and classified as migrate, retained shared owner, or authorized delete. |

Hard stop rules also apply if a test would assert source-string order instead of behavior, a proposed adapter exists only to preserve a retired shape, a compute response can mutate stale/other-owner state, a provider request logs/persists raw personal content, or a removed route returns 200/410 instead of being absent.

## 18. Final completion checklist

- [ ] `0d9934c` is still an ancestor; implementation baseline and S-10 integration SHA are recorded.
- [ ] Requirements ledger validator passes before and after implementation.
- [ ] Every IR in Section 4 has a linked test/change/deletion or an already-integrated S-06 guard.
- [ ] Cycles were executed vertically RED -> minimum GREEN; behavioral tests use real temporary GRDB and only external clock/model/network fakes.
- [ ] Effective-owner local GRDB is the sole durable authority; all visible and agent-driven mutations survive restart.
- [ ] Add/Edit local acceptance, l2 normalization, l1 extraction, conflict consolidation, lifecycle expiry/archive/recovery and local vectors are proven.
- [ ] Page, screenshot/Focus/Insight writers, Chat, Pi, PTT, Home, goals/profile context, Suggestions and automation all use the same local authority.
- [ ] Offline, restart, account-switch/late-result, source navigation/cascade, paging/search, delete/Undo/bulk and retained adjacent behaviors pass.
- [ ] Exact subtitle and all retained UI quirks are verified; rejected category search/fields/presentation/aliases are absent.
- [ ] Final local schema has no backend IDs/sync flags/review/scoring/device/durable-headline/public fields and preserves local IDs/FKs through upgrades.
- [ ] Python exposes only the three authenticated bounded compute POSTs for Memory and persists/logs no raw product data.
- [ ] `/v3/memories`, `/memory/**`, and backend `/v1/tools/memories*` are absent/404 from every app surface, route policy, OpenAPI and generated non-Windows client.
- [ ] Firestore Memory authority, root Memory rules/indexes, hosted review/search/vector/graph/projection/rollout/reconciliation and all exclusive callers/tests/docs are deleted.
- [ ] Complete repository memory-maintenance job/control plane is deleted and every shared registry/check/doc is updated.
- [ ] S-10 conversation parity artifacts are already absent; S-12 removes final Memory parity file/fixture/contracts job/discovery prefix while retaining T0.
- [ ] S-22/S-23/S-24/S-25 handoffs are explicit; no work from another slice was silently absorbed.
- [ ] Residue searches are fully classified; no unexplained active authority, compatibility shell, no-op service, deprecated alias, ignored field or fake-success response remains.
- [ ] Focused Swift/Python/agent/E2E checks, `backend/test.sh`, `desktop/macos/test.sh`, generated-contract checks and `make preflight` pass with evidence.
- [ ] A named `omi-s12-memories` bundle completes the local offline/restart/owner/tool user path without touching production apps or Omi cloud data.
- [ ] Owned real-provider acceptance either passes or is explicitly reported as blocked by the exact credential/input in Section 17.
- [ ] Repository closure and live operational closure are reported separately; no live resource was mutated without explicit authorization.
- [ ] User-visible changelog and truthful `PRODUCT.md`, `FORK.md`, architecture/component/E2E documentation move with the implementation.
- [ ] Final diff contains the intended implementation only, no Windows work, no requirements/roadmap edits, no unrelated cleanup, and no orphaned TODO/FIXME/HACK.
