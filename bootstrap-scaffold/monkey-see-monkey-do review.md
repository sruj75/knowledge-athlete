# Monkey-see-monkey-do review

## What this review is actually asking

Intentive started from the imported Omi snapshot at repository commit `81b5b889` (upstream Omi `99e0e60`). Omi was the bootstrap: when its code already solved a problem and the product decision did not require a different solution, the fastest move was to keep that code and change only the owner, name, endpoint, or storage location.

`requirements-challenge.md` already decided what the product should keep, delete, and simplify. This document does **not** debate those decisions again. It asks a narrower question:

> While implementing each settled slice, where did we add a new framework, policy object, migration, state machine, test-only production seam, release guard, or replacement subsystem when we could have kept Omi's working shape and made the minimum required edit?

This is an additions review. Deletions are not criticized merely for being large. Generated OpenAPI files are not treated as hand-designed complexity. A file move or rename is not called reinvention when Git shows that it mostly preserved Omi code.

One important premise changes several judgments: Intentive has never shipped and has no existing Intentive users. We need a new bundle identity and new storage namespace so we do not operate on Omi's installation. We do **not** need migrations that preserve an imaginary population of old Intentive data.

## How to read the recommendations

- `KEEP` — the addition is a necessary or sensible version of the Omi pattern.
- `SIMPLIFY` — keep the required behavior, but remove the extra layers around it.
- `REMOVE` — the added mechanism solves a problem this product does not currently have.
- `LIKELY SIMPLIFY` — the evidence points to overengineering, but the exact replacement should be confirmed while editing the owning code.
- `NO MATERIAL REINVENTION FOUND` — I checked the additions and would be manufacturing a complaint if I called them a redesign.

"Monkey-see-monkey-do" below never means blindly preserving an Omi product feature that the requirements rejected. It means preserving Omi's proven implementation pattern for the part we decided to keep.

## Audit coverage

| Slice | Implementation scope reviewed | Added lines | Result |
|---|---|---:|---|
| S-01 | `eb73915f` | 259 | 3 material simplifications |
| S-02 | `3af14608` | 937 | 2 material simplifications |
| S-03 | `6f1967f7` | 1,994 | 3 material simplifications |
| S-04 | `f3265450` | 758 | 3 material simplifications |
| S-05 | `c026719a` | 2,030 | 3 material simplifications |
| S-06 | `ff528f8a` | 40,690, including 35,160 generated OpenAPI lines | 3 material simplifications |
| S-07 | `d67d6e6e` | 862 | 2 material simplifications |
| S-08 | `7e6e0b5d` | 388 | 3 material simplifications |
| S-09 | `3aab1026` | 847 | 4 material simplifications |
| S-10 | `77a77e39` | 18,337, including 8,038 generated OpenAPI lines | 5 material simplifications |
| S-11 | `131018d8` | 8,346, including 912 generated OpenAPI lines | 4 material simplifications |
| S-12 | `73dd3a8a` | 10,754, including 3,168 generated OpenAPI lines | 5 material simplifications |
| S-13 | `46d67ccb` | 10,402, including 4,290 generated OpenAPI lines | 4 material simplifications |
| S-14 | `26c67df6` | 5,368, including 1,656 generated OpenAPI lines | 4 material simplifications |
| S-15 | `e7c25932` | 103 | No material reinvention found |
| S-16 | `cf64b673` | 2,033 | 3 material simplifications |
| S-17 | `5c649679` | 2,683 | 4 material simplifications |
| S-18 | `a0468e58` | 3,614 | 4 material simplifications |
| S-19 | `684d97a4` | 2,480 | 4 material simplifications |
| S-20 | `16e86b97` | 5,766 | 5 material simplifications |
| S-21 | `ee35939d` | 2,314 | 3 material simplifications |
| S-22 | `5d6573ff` | 2,244 | 5 material simplifications |
| S-23 | `06a917e7` | 5,031 | 4 material simplifications |
| S-24 | `ac3ba541` | 431 | No material reinvention found |
| S-25 | `fbdb339f` | 1,461 | 2 material simplifications |
| S-26 | `3a9dbdd0` | 1,623 | 3 material simplifications |
| S-27 | `5a7cfa5a` | 4,885 | 7 material simplifications |
| S-28 | `47efd453` | 350 | 3 material simplifications |
| S-29 | Everything after `5a7cfa5a` through current `HEAD` `f504c0a3` | 4,917 | 7 material simplifications |

The slice commits did not land in numeric order in every wave. The table uses the logical slice number, not Git's display order. S-29 deliberately includes all current branch commits after S-28/S-27 integration, including the update, libwebp, identity, Sentry, documentation, release-guard, and acceptance-test follow-ups. The only uncommitted product-independent items at review time were this document and an unrelated `.ua/` directory; there was no additional uncommitted product code to assign to S-29.

---

## S-01 — Remove the cloud Agent VM and database mirror

**Beginner context:** Omi had the normal assistant on the Mac and a second per-user computer in Google Cloud. This slice correctly removed the cloud computer. The question is whether we changed unrelated machinery while doing that.

### S01-01 — We rebuilt the retained image-publishing path

Omi already used the standard `docker/build-push-action` to build and publish the desktop backend and return its digest. The unwanted Agent VM had its own separate build step. S-01 could have deleted only that second step. Instead, both retained workflows were changed to build locally, smoke-test that exact local image, push it manually, inspect the registry digest, and enforce the sequence with `.github/scripts/check-desktop-backend-release-policy.py` and tests.

**Monkey-see-monkey-do:** delete the Agent VM image block and leave Omi's retained backend image action alone. **Recommendation: `SIMPLIFY`.** Exact-artifact smoke testing may be valuable later, but it was a new release-system project hiding inside a deletion slice.

### S01-02 — We put a test trigger into production code for memory-pressure cleanup

`DesktopAutomationBridge.swift`, `ResourceMonitor.swift`, and `HardeningSeamActionTests.swift` gained a non-production `simulate_memory_remediation` action and a wrapper to exercise the path after Agent VM hooks disappeared. This made the product expose a new automation seam solely so a deletion could be tested.

**Monkey-see-monkey-do:** remove the Agent VM callback from Omi's existing remediation path and keep the path itself unchanged. Test the remaining behavior through the existing resource-monitor entry point. **Recommendation: `SIMPLIFY`.** Do not keep a product API whose only customer is a test for removed code.

### S01-03 — The release-policy guard grew instead of shrinking mechanically

The static checker and its tests were expanded to prescribe the new build/smoke/push choreography. The requirement was structural absence of the VM, not a new release policy language.

**Monkey-see-monkey-do:** remove Agent VM workflow names, images, routes, and expectations from the existing checks. Do not make the checker dictate a replacement pipeline. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** the small route-retirement test covering the seven removed Agent VM routes and neighboring retained routes is a useful behavioral fence. It proves we deleted the right server surface without inventing a new runtime.

---

## S-02 — Remove wearables, the Omi write-ahead log, and device-audio ingestion

**Beginner context:** this slice made the Mac microphone the only capture source. Most work was deletion. The main mistake was protecting old data shapes that Intentive will never inherit.

### S02-01 — We built legacy-photo preservation for nonexistent users

The additions introduced `conversation_has_legacy_photos`, reads from old photo subcollections, merge rejection, recording-session protection, and a `LEGACY_PHOTO_MERGE_ERROR`. The commit even described preserving legacy photo data during cleanup. That makes sense for a shipped Omi upgrade; it does not make sense for a new Intentive namespace with zero users.

**Monkey-see-monkey-do:** delete wearable-photo writes, reads, merge rules, and cleanup code together. New Intentive databases start without the legacy photo shape. **Recommendation: `REMOVE`.**

### S02-02 — We preserved transitional decoding compatibility

`ServerConversationDecodingTests.swift` and related conversion code gained compatibility coverage for historical conversation payload details while the product was removing the server/wearable ownership that produced them. It prolongs an old wire format inside a fork that is meant to start clean.

**Monkey-see-monkey-do:** keep only the fields still emitted by the retained Mac/backend path. Do not add compatibility for Omi records we will not import. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** `backend/database/job_run_locks.py` was mostly a narrow extraction of a shared helper from a deleted owner. Moving a still-used Omi primitive is exactly the kind of preservation we want.

---

## S-03 — Remove hosted Parakeet and every Deepgram branch

**Beginner context:** Omi supported several speech-to-text providers. The decision was to keep the managed Modulate route and delete the others. We did not need to redesign speech-to-text itself.

### S03-01 — We created a miniature Modulate testing service

The slice added `backend/testing/listen_pusher_stack/modulate_stub.py`, new offline-app factories, fake provider routing, and a wider dev-harness provider matrix. This is useful test infrastructure, but it is substantially more than deleting Parakeet and Deepgram branches around Omi's existing Modulate implementation.

**Monkey-see-monkey-do:** retain Omi's Modulate path and use a small injected fake response at its current client seam. **Recommendation: `SIMPLIFY`.** A protocol-faithful fake service is not needed until an actual integration failure demands it.

### S03-02 — Provider retirement turned into broad observability work

`backend/charts/monitoring/alert-rules.json` gained 306 lines, while VAD, fair-use, runtime validation, and provider tests also grew. Some edits renamed retained concepts, but the amount of new monitoring and validation exceeds the requirement to remove two providers.

**Monkey-see-monkey-do:** delete alerts and environment keys exclusive to the retired providers; keep Omi's Modulate alerts and behavior. **Recommendation: `LIKELY SIMPLIFY`.** Review individual retained alerts before removal, but do not use this slice to redesign the monitoring catalog.

### S03-03 — We expanded transitional provider matrices

The dev harness and runtime tests learned extra combinations to prove which provider is selected in every environment. Once only one managed STT provider remains, much of that matrix is testing choices that no longer exist.

**Monkey-see-monkey-do:** make Modulate the fixed managed implementation and keep one success test plus one failure test. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** changing Parakeet-specific VAD names to provider-neutral names was a mechanical cleanup where the underlying Omi logic remained useful.

---

## S-04 — Remove impossible controls and repository zombies

**Beginner context:** a "repository zombie" is code or a control that looks alive but cannot work anymore. This should have been one of the most deletion-only slices.

### S04-01 — We added a new production-routing static checker

`.github/scripts/check-desktop-production-routing.py` and its test added roughly 181 lines to scan source and workflow policy. This was a new guard system created while removing dead controls.

**Monkey-see-monkey-do:** delete the dead routes, settings, workflows, and their old checks. Let existing compile tests and route tests prove the retained path. **Recommendation: `REMOVE`.**

### S04-02 — We substantially rewrote the release-process guard

`check-release-process-guards.py` gained 118 lines, its tests grew, and the manifest gained more policy entries. Instead of making the old checker smaller after deleting zombies, the slice made release policy more prescriptive.

**Monkey-see-monkey-do:** remove references to deleted workflows and leave the remaining Omi release checks unchanged. **Recommendation: `SIMPLIFY`.**

### S04-03 — We created a failure class for a generated-contract problem during cleanup

`FC-generated-contract-missing-source.json` and associated generator/check changes formalized a new repository governance mechanism. The generated Swift source did need to remain reproducible, but this was not required to delete impossible controls.

**Monkey-see-monkey-do:** preserve Omi's generator command and ensure the generated file is produced by the existing build/check. Track a real failure separately if it recurs. **Recommendation: `REMOVE` from this slice's solution.**

---

## S-05 — Make managed Pi the only local agent runtime

**Beginner context:** Omi had more than one way to enter or configure its local agent. The settled decision was one Pi-based runtime. The direct job was to remove alternate entrances.

### S05-01 — We added an upgrade migration for an app with no users

The slice added `MANAGED_PI_EXECUTION_PROFILE_MIGRATION_VERSION = 29` and a migration that rewrites old sessions, bindings, and preferences into the Pi execution profile. This is the kind of safety Omi needs for an installed population. Intentive has no installed population in its new namespace.

**Monkey-see-monkey-do:** delete the alternate adapters and make Pi the only default for newly created state. **Recommendation: `REMOVE`.**

### S05-02 — We introduced a temporary higher-model bridge

`APIClient+HigherModel.swift` added a new managed synthesis client and a fixed retained-model path, explicitly waiting for S-22 to own the final model migration. That created an abstraction we already knew was temporary.

**Monkey-see-monkey-do:** keep Omi's current higher-model call until S-22, then change the retained provider/model in one place. **Recommendation: `REMOVE` the transitional layer.**

### S05-03 — We added small policy/parser seams around a single runtime

Helpers such as `LoopbackHTTPParsing.swift`, extra execution-profile state, and broad runtime fixtures made a now-single-choice system look configurable. With one agent runtime, many of these types represent no real decision.

**Monkey-see-monkey-do:** call the one Pi runtime directly through Omi's existing agent interface and keep only the packaged-runtime smoke test. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** preserving the packaged Pi runtime test was sensible. It checks the actual thing users will run rather than a speculative abstraction.

---

## S-06 — Remove external product surfaces and keep one assistant

**Beginner context:** this removed the app marketplace, connectors, public MCP, sharing/import, and other Omi product surfaces while retaining one local assistant. The raw addition count looks frightening, but 35,160 lines were generated OpenAPI and several "new" Swift files were code moved out of deleted views.

### S06-01 — We added a migration to retire local tables from an installation that cannot exist

`RewindDatabase+ExternalSurfaceRetirement.swift` and `ExternalSurfaceRetirementMigrationTests.swift` drop or reshape old knowledge-graph/index tables and columns. That protects an upgrade from an earlier Intentive build. There are no such deployed builds.

**Monkey-see-monkey-do:** stop creating those tables in the new schema and delete all callers. A clean Intentive database never needs to migrate them. **Recommendation: `REMOVE`.**

### S06-02 — We built a bespoke one-assistant integration fixture

`OneAssistantChatContractTests.swift` added 211 lines with many injected closures and fake dependencies to prove that one assistant path survives. The result is a second model of the chat system maintained just for the test.

**Monkey-see-monkey-do:** keep Omi's existing chat behavior test, remove marketplace/persona selection, and add one assertion that the retained assistant opens and sends. **Recommendation: `SIMPLIFY`.**

### S06-03 — We multiplied acceptance flows for a deletion

The slice added several E2E flows and browser/automation contracts around the surviving surface. This gives confidence, but it also makes every future UI change maintain several descriptions of the same path.

**Monkey-see-monkey-do:** keep one end-to-end "open retained assistant and send a message" flow and focused route-absence tests for deleted backend surfaces. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** `PermissionGuidanceOverlay`, `FlowLayout`, `DismissableSheet`, `OverlayModalEscapeCatcher`, and `OnboardingChatPersistence` mostly preserve Omi code that had lived inside files being deleted. `daily_summary.py` is also largely a rename from `external_integrations.py`. These are good examples of moving the useful bricks instead of rebuilding them.

---

## S-07 — Remove customer BYOK and preserve managed access

**Beginner context:** BYOK means users supplying their own model-provider keys. The decision was to remove that choice and always use the product's managed access.

### S07-01 — We added production automation endpoints to inspect a removed choice

`DesktopAutomationManagedAccessActions.swift` exposes managed-access snapshots, and new automation tests use it to verify that BYOK controls and BYOK-shaped errors are gone. The production app gained an observation API because the test wanted to see an absence.

**Monkey-see-monkey-do:** delete key-entry controls and customer-key headers, then update Omi's existing authentication and settings tests. **Recommendation: `REMOVE` the dedicated automation action.**

### S07-02 — We retained a large decision matrix after removing the decision

`ManagedAccessDecisionTests.swift`, `RealtimeManagedAuthenticationTests.swift`, API routing tests, Pi adapter tests, and additional harness seams cover many combinations of managed/customer access. Once customer access is deleted, the important rule is simple: all supported calls use managed authentication.

**Monkey-see-monkey-do:** one core managed-auth test per real transport plus one rejection test for customer headers. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** rejecting customer keys at backend boundaries is a useful fail-closed test. It prevents accidental reintroduction without designing a new runtime.

---

## S-08 — Re-own account identity and lifecycle

**Beginner context:** authentication, sign-out, account deletion, and export already worked in Omi. This slice mostly needed new ownership and removal of redundant profile fields without weakening those flows.

### S08-01 — We wrapped an already-working sign-out sequence in a new action type

`ExplicitSignOutAction.swift` is an injected 34-line wrapper around the sign-out ordering, accompanied by a dedicated test file and new E2E coverage. The requirement explicitly said to keep sign-out behavior unchanged.

**Monkey-see-monkey-do:** leave Omi's sign-out handlers in place and remove only calls that clean up retired providers or data owners. **Recommendation: `SIMPLIFY`.**

### S08-02 — We created a recorder object for two simple side effects

`OnboardingAcquisitionSourceRecorder.swift` wraps writing one local default and recording one PostHog property. It is a middle layer with no product decision of its own.

**Monkey-see-monkey-do:** keep those two calls where Omi already made them after deleting the backend mirror. **Recommendation: `REMOVE` the wrapper.**

### S08-03 — Account-deletion cleanup was hardened beyond the slice

`backend/services/users/account_deletion.py` gained `AccountCleanupFailure`, an empty purge result, and a reorganized cleanup function with additional tombstone-failure behavior. That may be a good bug fix, but it is a redesign of retained deletion orchestration while the requirement was to remove unused feedback/profile inputs.

**Monkey-see-monkey-do:** delete retired cleanup targets and request fields while preserving Omi's durable deletion worker. Make tombstone hardening a separate evidence-backed fix if needed. **Recommendation: `SIMPLIFY`.**

---

## S-09 — Remove legacy observability and feedback surfaces

**Beginner context:** this slice was meant to remove Crisp, Sentry-to-task feedback, and rejected telemetry while retaining narrowly owned analytics, diagnostics, and model tracing.

### S09-01 — We accidentally rebuilt a cloud screen-activity product

`backend/routers/desktop_screen_activity.py` added a new `/v1/screen-activity/sync` route, with tests and parity capture. It accepts desktop screen activity and writes searchable cloud data. That contradicts the already-settled local-only Rewind direction and was deleted again in S-15.

**Monkey-see-monkey-do:** do not resurrect the missing route. Keep Omi's local Rewind and remove the old Crisp/feedback code. **Recommendation: `REMOVE`.** This is the clearest case in Wave 1 where extra implementation actively moved opposite to the product plan.

### S09-02 — We introduced a presentation model just to remove feedback actions

`ChatMessageActionPresentation.swift` and its tests decide which message action buttons should appear after rating/feedback is removed. The old view already owned those buttons.

**Monkey-see-monkey-do:** delete the rejected rating/feedback buttons directly from `ChatBubble` and `AIResponseView`. **Recommendation: `REMOVE` the extra presentation layer.**

### S09-03 — We built compatibility projection for legacy Sentry metadata

`TaskDetailMetadataProjection` and its tests hide historical Sentry-feedback keys from task detail. In a clean Intentive data namespace, no task contains those legacy keys.

**Monkey-see-monkey-do:** delete Sentry-feedback task creation and the corresponding UI fields. Do not add a sanitizer for records we will not import. **Recommendation: `REMOVE`.**

### S09-04 — Tracing repair and operational docs expanded an observability deletion

The slice added LangSmith binding behavior, async-offload tests, metrics tests, and operational documents while removing old feedback products. These may improve Omi, but they are not necessary to re-own the retained observability paths.

**Monkey-see-monkey-do:** change the retained service credentials/identifiers and delete rejected integrations. Handle a demonstrated tracing bug separately. **Recommendation: `LIKELY SIMPLIFY`.**

---

## S-10 — Make conversations and transcripts local-authoritative

**Beginner context:** "local-authoritative" means the Mac's database is the official copy. Omi already had local Rewind/transcription storage, but its Conversations product still depended heavily on backend records. Some new local schema was necessary. The overengineering was recreating server orchestration inside the Mac.

### S10-01 — We built a local job-control plane

`TranscriptionStorage+LocalAuthority.swift` added about 1,870 lines covering begin/upsert/finalize/discard, enrichment work leases, claims, retries, recovery, merge handling, and idempotency. In plain English, the Mac database became a small workflow server.

**Monkey-see-monkey-do:** make Omi's existing local transcript/conversation rows the source of truth, perform the next required step directly, and retry only at the call site that can actually fail. **Recommendation: `SIMPLIFY` aggressively.** Keep the local data, remove generic leasing and job orchestration until real concurrency requires it.

### S10-02 — We created parallel model and presentation stacks

The slice added `LocalConversationModels.swift`, `ConversationPresentationModels.swift`, `LocalTranscriptFormatter.swift`, and a substantially redesigned `ConversationRepository.swift`. Several layers translate the same conversation between database, repository, and UI shapes.

**Monkey-see-monkey-do:** retain Omi's conversation models and UI, replacing the repository's backend calls with direct reads from the existing local store. Add one adapter only where the shapes truly differ. **Recommendation: `SIMPLIFY`.**

### S10-03 — We created a dedicated conversation-compute protocol

`backend/routers/conversation_compute.py`, `APIClient+ConversationCompute.swift`, new wire models, generated clients, and 336 backend test lines create a separate transient service for title, structure, and enrichment compute.

**Monkey-see-monkey-do:** reuse Omi's retained authenticated model/chat call and send the bounded prompt from the Mac. If a dedicated endpoint is necessary for secret ownership, make it a thin request/response adapter rather than a new conversation subsystem. **Recommendation: `LIKELY SIMPLIFY`.**

### S10-04 — We wrote an upgrade migration for pre-release local state

`RewindDatabase+ConversationLocalAuthority.swift` and 254 lines of migration tests move old conversation data into the new authority model. This solves an upgrade population Intentive does not have.

**Monkey-see-monkey-do:** define the clean schema once and seed only test fixtures. **Recommendation: `REMOVE` compatibility migration branches that exist solely for old Omi/Intentive rows.**

### S10-05 — The test suite mirrors every internal state transition

Separate suites cover ingestion, finalization, migration, discard admission, action enrichment, speaker labels, merges, repository mapping, and structure enrichment. Many tests lock in the newly invented workflow rather than only the user contract.

**Monkey-see-monkey-do:** keep tests for capture-to-local-save, list/read, one mutation, and the main compute failure. Delete tests whose only purpose is protecting removable leases or adapter layers. **Recommendation: `SIMPLIFY`.**

---

## S-11 — Make Chat and Home local-authoritative

**Beginner context:** typed Chat and Home history needed to stop using cloud product-data storage. Omi already had a local Node/Pi runtime and existing Chat UI. The quickest path was to keep those and change persistence ownership.

### S11-01 — ChatProvider became a second local application server

`ChatProvider.swift` gained roughly 1,310 lines, while `AgentRuntimeProcess.swift`, Node kernel sessions, the conversation journal, and SQLite state all grew. Responsibility for catalog loading, projections, turn completion, titles, greetings, drafts, attachments, and runtime receipts is now spread across several owners.

**Monkey-see-monkey-do:** let the existing local runtime own its session journal and let Omi's existing ChatProvider render it. Add a narrow list/load method rather than recreating catalog state in Swift. **Recommendation: `SIMPLIFY`.**

### S11-02 — We created overlapping catalog and projection layers

`LocalChatCatalog`, `KernelTurnProjection`, ChatProvider's own catalog state, and Home catalog presentation all translate local session data. These layers mostly exist because the new implementation split one concept across Swift and Node.

**Monkey-see-monkey-do:** expose one stable session record from the local runtime and use it directly in the retained Omi catalog UI. **Recommendation: `SIMPLIFY`.**

### S11-03 — Attachment ownership became a mini file-management system

`LocalChatAttachmentStore.swift` copies files into owner/chat directories and adds garbage collection and protected-path behavior. Local ownership does require durable attachments, but this is more machinery than Omi's explicit attachment flow needs at bootstrap.

**Monkey-see-monkey-do:** copy selected files once into one app-managed attachments directory, store the relative path in the local chat record, and delete it with that record. **Recommendation: `LIKELY SIMPLIFY`.** Add more lifecycle policy only after a real retention case appears.

### S11-04 — New receipt variants were invented to trigger titles and greetings

The Node conversation journal and Swift runtime gained "first completed real pair"-style receipt behavior and associated projection/tests. That is a new cross-process protocol for UI behavior Omi already knew how to perform.

**Monkey-see-monkey-do:** retain Omi's existing title/greeting trigger and call it after the local turn completes. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** `HomeChatCatalog.swift` is largely a rename of `ChatSessionsSidebar.swift`; that is preservation, not reinvention. A local draft store is also a reasonable direct replacement for cloud-backed drafts. The 1,145-line `HomeChatCatalogTests.swift`, however, is disproportionate for mostly retained UI and should shrink with the architecture.

---

## S-12 — Make Memories local-authoritative

**Beginner context:** Memories are durable facts the assistant remembers. They needed to live on the Mac, while model inference could remain a transient managed service. A local table and direct CRUD were necessary; a general workflow engine was not automatically necessary.

### S12-01 — We recreated a backend worker scheduler inside the Mac

`LocalMemoryLifecycleRunner.swift` added 583 lines for a repeating scheduler, work leasing, normalization, extraction, embedding, consolidation, retry, and recovery. `MemoryStorage.swift` grew by 1,222 lines to support the states. This is a local background-job platform, not merely local memory storage.

**Monkey-see-monkey-do:** save memory rows directly, invoke extraction after the owning event, and retry a failed call from a small bounded queue only if users actually need it. **Recommendation: `SIMPLIFY` aggressively.**

### S12-02 — The memory schema models internal workflow history, not just product data

`MemoryModels.swift` and `RewindDatabase+MemoryLocalAuthority.swift` introduce revisions, transitions, receipts, leases, claims, and consolidation state. Those concepts mostly support the runner we just invented.

**Monkey-see-monkey-do:** keep a memory ID, text, optional embedding, timestamps, source, and status needed by the UI. **Recommendation: `SIMPLIFY`.** Delete fields whose only consumer is the removable workflow machinery.

### S12-03 — We built a four-layer memory-compute protocol

The implementation added Swift request types, `APIClient+MemoryCompute.swift`, a Python route, Python models, and `backend/utils/llm/memory_compute.py`, plus generated clients. Much of it moves the same bounded payload through layers.

**Monkey-see-monkey-do:** use one thin authenticated compute endpoint or the retained generic model endpoint. The Mac remains the result owner; the server does not need to model the local lifecycle. **Recommendation: `SIMPLIFY`.**

### S12-04 — We migrated local memory history that Intentive does not have

The schema and migration tests preserve/reclassify old local-memory data and can enqueue migration work. A fresh Intentive namespace has no old memory database to convert.

**Monkey-see-monkey-do:** create the final clean table on first launch. **Recommendation: `REMOVE` the compatibility migration.**

### S12-05 — We built synthetic-profile and exhaustive lifecycle test infrastructure

`synthetic_profiles.py`, 442 lines of lifecycle-runner tests, 471 backend memory-compute test lines, and additional authority tests mostly validate internal machinery rather than the basic user outcome.

**Monkey-see-monkey-do:** test create/read/delete, one successful extraction, and one compute failure that leaves existing memory safe. **Recommendation: `SIMPLIFY`.**

---

## S-13 — Make Tasks and one simple Goal local-authoritative

**Beginner context:** the product decision was deliberately modest: local tasks and one simple goal. The slice needed local persistence and removal of backend authority, but it also redesigned significant UI and assistant behavior.

### S13-01 — A storage change became a Tasks and Dashboard redesign

`TasksPage.swift` gained 1,052 lines, `DashboardPage.swift` 453, `TasksStore.swift` 511, and new supporting views. This is not just replacing network reads with local reads; it is a substantial new product surface.

**Monkey-see-monkey-do:** keep Omi's Tasks and Dashboard presentation, replace its repository calls with `ActionItemStorage`/`GoalStorage`, and change only labels or controls rejected by the requirements. **Recommendation: `SIMPLIFY`.** Product redesign should be a later, visible slice.

### S13-02 — We added new reminder and home-status behavior

`TaskReminderService.swift`, 157 lines of reminder tests, and `HomeStatusControls.swift` introduce scheduling and status-control behavior while the assigned job was authority migration.

**Monkey-see-monkey-do:** keep Omi's existing task reminder behavior if it already worked; otherwise omit it until reminders are an explicit product requirement. **Recommendation: `REMOVE` new behavior not inherited from Omi.**

### S13-03 — The local task model gained identity/revision machinery for an empty population

`ActionItemStorage`, `TaskActionItem`, schema tests, and identity-mutation tests add local identity, update bands, and migration handling across many cases. Some stable IDs are required, but compatibility and conflict machinery assumes old records or multiple writers.

**Monkey-see-monkey-do:** one UUID per new task, direct local mutations, and a simple ordered query. **Recommendation: `SIMPLIFY`; remove legacy conversion and multi-writer defenses.**

### S13-04 — Goals acquired more domain behavior than "one simple goal"

`GoalStorage`, `GoalsWidget`, progress tests, chat-tool changes, and dashboard wiring create a richer goal model and several projections.

**Monkey-see-monkey-do:** one local goal record with title, optional target/progress, and direct display in the retained Omi slot. **Recommendation: `LIKELY SIMPLIFY`.** Keep only behavior directly demanded by `requirements-challenge.md`.

---

## S-14 — Make Focus, Insights, proactive advice, and AI Profile local-authoritative

**Beginner context:** these assistants already existed. Their durable results needed to move from hosted product data into the Mac. This was a data-owner change, not a request to invent a shared local-assistant platform.

### S14-01 — Each assistant was rebuilt around owner fences and lifecycle policy

`FocusStorage`, `InsightStorage`, `AIUserProfileService`, assistant implementations, and their tests gained owner checks, late-result rejection, continuity states, and mutation rules. The Wave 2 closeout then expanded this further with `RewindDatabase+OwnerAuthorization.swift` (264 lines), `OwnerAuthorizedStorageReads.swift` (221 lines), and `LocalMutationAuthorization.swift`.

**Monkey-see-monkey-do:** write each assistant's retained Omi result directly into the current local user's database and clear/switch the database on sign-out. **Recommendation: `SIMPLIFY`.** A single database-owner boundary is enough; every assistant does not need its own distributed authorization protocol.

### S14-02 — We added migration and retirement frameworks for unshipped assistant state

`S14LocalAuthorityMigrationTests.swift` plus `RewindDatabase+ProactiveAuthorityRetirement.swift` and closeout migration work convert or retire old proactive tables. That is upgrade engineering for a population that does not exist.

**Monkey-see-monkey-do:** define only the final local tables and never import Omi's proactive state. **Recommendation: `REMOVE`.**

### S14-03 — Navigation work leaked into the authority slice

`InsightsHubNavigation.swift`, `InsightPage.swift`, floating-control-bar changes, and navigation tests change how users move between assistant surfaces. S-21 was already assigned to shell/navigation simplification.

**Monkey-see-monkey-do:** keep Omi's existing presentation while swapping its data source, then let S-21 delete or rename destinations once. **Recommendation: `REMOVE` the interim navigation layer.**

### S14-04 — The test matrix freezes new internals

Separate suites cover focus authority, focus lifecycle, insight mutation, insight ownership, profile authority, settings authority, notification continuity, embeddings, and migrations. Many tests protect the newly introduced fences rather than the user-visible product.

**Monkey-see-monkey-do:** one retained flow per assistant and one sign-out/owner-switch test at the shared database boundary. **Recommendation: `SIMPLIFY`.**

---

## S-15 — Preserve local Rewind and delete every cloud copy/read path

**Result: `NO MATERIAL REINVENTION FOUND`.**

This is what a good deletion slice looks like. It added only 103 lines, mostly a focused backend route-retirement test, a Settings search contract update, a few neighboring assertions, and a changelog entry. It did not build a replacement screen-history service or migrate nonexistent user data.

**Monkey-see-monkey-do judgment:** keep this shape. Delete the cloud readers/writers and let Omi's already-working local Rewind remain. The only caution is to avoid growing the small retirement tests into a permanent source-scanning framework.

---

## S-16 — Keep `/v4/listen` as transient speech-to-text transport

**Beginner context:** the server should hear audio, return transcript events, and forget the conversation. The Mac owns persistence. The retained Omi WebSocket protocol already supplied much of that transport.

### S16-01 — A transient change produced a 559-line protocol contract test

`test_listen_transient_contract.py` exhaustively inspects many messages, removed fields, and boundary conditions. It gives confidence, but it duplicates the protocol implementation in test form and makes later harmless changes expensive.

**Monkey-see-monkey-do:** keep one end-to-end test that audio produces transient transcript events, one test that no server conversation is written, and one error-path test. **Recommendation: `SIMPLIFY`.**

### S16-02 — We introduced a parity-pack export subsystem

`backend/testing/parity_pack_v0/export.py`, its tests, README, live-capture changes, and later closeout repairs created an exporter for capturing protocol parity. That is reusable test infrastructure, but it is not needed to stop server persistence.

**Monkey-see-monkey-do:** record a small checked-in fixture from Omi's retained listen path or use the existing fake wire. **Recommendation: `REMOVE` unless parity packs have a real ongoing consumer.**

### S16-03 — The wire protocol was reshaped more than necessary

`TranscriptionService.swift`, listen runtime/contracts/receiver/transcripts, and multiple session tests added new bootstrap and finalization semantics while deleting server ownership. Some edits are required, but the simplest contract is "audio in, partial/final transcript out."

**Monkey-see-monkey-do:** preserve Omi's event names and streaming flow; remove conversation IDs, durable-finalization commands, and persistence side effects. **Recommendation: `LIKELY SIMPLIFY`.**

---

## S-17 — Narrow onboarding and macOS permissions

**Beginner context:** most of Omi's onboarding behavior was supposed to stay. We mainly needed to delete screens and permissions for removed products. Instead, unchanged behavior was recast as a policy system.

### S17-01 — We created an onboarding policy-object family

`OnboardingExitPolicy.swift` (206 lines), `OnboardingLifecyclePolicy.swift` (97 lines), and `OnboardingFlow.swift` additions turn the flow into explicit policy/state objects. These types largely encode behavior the existing Omi views and model already performed.

**Monkey-see-monkey-do:** delete obsolete steps from Omi's step enum and navigation switch, keep its existing completion/skip logic, and update one flow test. **Recommendation: `SIMPLIFY`.**

### S17-02 — Authentication gained another owner-transition state machine

`AuthOwnerTransition.swift`, `AuthService` changes, persistence-clearing logic, and many tests add generation/transition handling around sign-in and sign-out. Some stale-result protection is sensible, but it duplicates the owner fences built in the local storage slices.

**Monkey-see-monkey-do:** make the database/session coordinator the single owner boundary. On account change, close the old store and open the new one. **Recommendation: `SIMPLIFY`.**

### S17-03 — Simple decisions became dedicated policy types

`ProactiveCapturePolicy` and launch-at-login changes give separate types to questions such as whether capture starts after onboarding and whether a bundle may register at login.

**Monkey-see-monkey-do:** keep these checks as small conditions at Omi's existing owners (`OmiApp`, onboarding completion, and launch manager). **Recommendation: `REMOVE` one-use middle layers.**

### S17-04 — We over-tested retained onboarding behavior

The additions include 316 lines of persistence-clearing tests, 194 skip tests, 169 permission tests, 121 completion tests, 109 answer-authority tests, policy tests, unit flow tests, and two E2E flows.

**Monkey-see-monkey-do:** one happy path, one skip/permission-denial path, and one sign-out reset test. **Recommendation: `SIMPLIFY`.**

---

## S-18 — Replace Stripe with disabled-first Dodo billing

**Beginner context:** some provider replacement was unavoidable. The "monkey" move was to keep Omi's billing interface and UI shape and replace the provider-specific adapter underneath it. Instead, we designed a new billing architecture.

### S18-01 — We created an eight-part billing package

`backend/utils/billing/` gained separate service, catalog, provider, config, projection, value, and store modules plus an architecture document; `backend/database/billing.py` added another layer. This is a platform designed for multiple future billing concerns before Intentive has one paying user.

**Monkey-see-monkey-do:** keep the existing subscription/checkout interface and implement a thin Dodo client behind it. Hard-code the first approved catalog in one config module. **Recommendation: `SIMPLIFY` substantially.**

### S18-02 — Firestore projection and reconciliation became separate systems

The implementation maps webhook state through provider objects, service objects, projections, database writes, and a desktop `BillingReconciler`. Each layer is individually tidy, but together they make one provider callback hard to follow.

**Monkey-see-monkey-do:** verify the Dodo webhook, translate it once into Omi's retained subscription shape, store it, and let the desktop read that shape. **Recommendation: `SIMPLIFY`.**

### S18-03 — We exposed billing internals through desktop automation

`DesktopAutomationBillingActions.swift` added 123 lines and dedicated tests so acceptance flows can observe simulated billing/reconciliation state.

**Monkey-see-monkey-do:** test the disabled state in the retained Settings UI and test webhook-to-subscription behavior at the backend boundary. **Recommendation: `REMOVE` the billing-specific automation API until a real end-to-end checkout exists.**

### S18-04 — The test suite is larger than the first billing implementation needs

More than 600 lines cover Dodo billing/webhook behavior, plus projections, wire contracts, reconciler tests, and UI helpers. Much of it locks in the new package boundaries.

**Monkey-see-monkey-do:** one checkout test, one signed webhook test, one invalid-webhook test, and one disabled-mode UI test. **Recommendation: `SIMPLIFY`.**

---

## S-19 — Reconnect push-to-talk to local product data

**Beginner context:** push-to-talk, or PTT, is the live voice conversation. It needed to query the local conversations/memories/tasks built in earlier slices and stop offering rejected tools. The simplest implementation would reuse those existing local services.

### S19-01 — We built a PTT-specific semantic-search stack

`TranscriptionStorage+SemanticSearch.swift`, `ConversationSemanticRecall.swift`, and `LocalConversationToolService.swift` add separate search, recall, and tool layers for PTT. This overlaps the local conversation storage and chat-tool query work already introduced in S-10 through S-13.

**Monkey-see-monkey-do:** have Omi's retained PTT tool executor call the one existing local conversation/memory/task query API directly. **Recommendation: `SIMPLIFY`.** There should not be one local-data architecture for typed Chat and another for voice.

### S19-02 — Daily recap became a new authority subsystem

`DailyRecapLocalAuthority.swift` and 184 lines of tests add a durable recap owner during a slice about PTT reconnection. A recap can be a query or transient generated result; it does not need another authority framework by default.

**Monkey-see-monkey-do:** compute the recap from retained local records when requested and cache it only if measured latency requires it. **Recommendation: `REMOVE` the separate authority layer.**

### S19-03 — Small capture decisions became three policy objects

`PTTCaptureAudioTransition.swift`, `PTTBatchTranscriptionPolicy.swift`, and notification-formatting policy isolate cue timing, language choice, and delivery formatting. These have one real owner: `PushToTalkManager`/the retained realtime controller.

**Monkey-see-monkey-do:** edit Omi's existing PTT methods directly and keep one small pure helper only where several callers genuinely share it. **Recommendation: `SIMPLIFY`.**

### S19-04 — Owner-authorized read wrappers spread again

`OwnerAuthorizedStorageReads.swift` gained more PTT-facing methods, extending the cross-cutting owner-fence system introduced during Wave 2 closeout.

**Monkey-see-monkey-do:** open the correct user's one local database at the session boundary, then let ordinary queries assume that database is authoritative. **Recommendation: `SIMPLIFY` at the shared boundary rather than per read.**

---

## S-20 — Move fair-use evidence local and keep bounded enforcement facts in cloud

**Beginner context:** detailed user evidence should stay on the Mac; the server may retain a small decision such as allowed, warned, or blocked. That boundary is reasonable. The implementation built a full distributed review workflow around it.

### S20-01 — We created a cloud review-request state machine

`backend/database/fair_use.py` gained 482 lines, `fair_use_reviews.py` added a route and utility layer, and the backend now models request states, transactions, retries, recovery, and review outcomes. This is a durable case-management system rather than a bounded enforcement-fact endpoint.

**Monkey-see-monkey-do:** send a small signed summary/counter to Omi's existing fair-use endpoint and receive the current enforcement decision. **Recommendation: `SIMPLIFY` aggressively.**

### S20-02 — We duplicated the workflow on the Mac

`FairUseReviewCoordinator.swift`, evidence models, and AppState/transcription changes maintain a local coordinator that mirrors the server review lifecycle. Now both sides understand pending, retrying, recovering, and completed review work.

**Monkey-see-monkey-do:** the Mac gathers local evidence, derives the bounded request once, sends it, and stores only the returned decision. **Recommendation: `SIMPLIFY`.**

### S20-03 — Automatic recovery was engineered before real usage

Dedicated tests cover automatic recovery, strict Firestore transaction behavior, emulator behavior, runtime states, and race cases. This anticipates operational failure modes before there is a user population or measured review volume.

**Monkey-see-monkey-do:** use one idempotent request ID and a bounded retry. Add a recovery worker only after an observed stuck-request failure. **Recommendation: `REMOVE` speculative recovery machinery.**

### S20-04 — We added a fair-use automation control plane

`FairUseAutomationBridgeTests.swift` alone has 508 added lines, with production automation commands and snapshots to exercise the distributed workflow.

**Monkey-see-monkey-do:** unit-test the bounded request and use one development fixture that returns allowed/warned/blocked. **Recommendation: `REMOVE` the domain-specific automation API.**

### S20-05 — The tests protect the invented architecture more than the privacy boundary

The slice added roughly 1,800 lines across review-request, state, runtime, recovery, coordinator, and automation tests. The most important contract is much smaller: raw evidence never leaves the Mac, and enforcement still works when the request succeeds or fails.

**Monkey-see-monkey-do:** keep tests for exactly those privacy and enforcement outcomes. **Recommendation: `SIMPLIFY`.**

---

## S-21 — Simplify navigation, Settings, and Home

**Beginner context:** this was intentionally a shell cleanup. Omi already had navigation and settings switches; rejected destinations could have been removed from those lists.

### S21-01 — We replaced the old navigation switch with a navigation policy layer

`DesktopNavigation.swift`, `DesktopAutomationNavigation.swift`, and three dedicated navigation/contract test suites define routes, visibility, selection, and automation mapping in new types.

**Monkey-see-monkey-do:** delete rejected cases from Omi's destination enum/sidebar and keep the existing selection binding. **Recommendation: `SIMPLIFY`.** A smaller product does not need a larger routing framework.

### S21-02 — Your Stats gained a separate projection module

`YourStatsLocalProjection.swift` and 239 lines of tests convert local records into stats presentation. A small query/presentation helper is reasonable, but this module and matrix go beyond showing a few retained numbers.

**Monkey-see-monkey-do:** query the local stores in the retained Stats view model and format the handful of displayed values there. **Recommendation: `LIKELY SIMPLIFY`.**

### S21-03 — Static shell behavior is tested in too many ways

Settings destination contracts, shell visibility tests, navigation policy tests, automation navigation tests, home-owner tests, and feature-tier retirement tests overlap heavily.

**Monkey-see-monkey-do:** keep one navigation test, one Settings search/destination test, and one E2E shell smoke. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** the actual deletion of rejected sidebar items and the retained Permissions page are aligned with the product requirement. The problem is the extra policy and acceptance scaffolding around them.

---

## S-22 — Narrow managed models to retained workloads

**Beginner context:** Omi already knew how to call Anthropic, Gemini/Vertex, and other providers. The requirement was to delete providers and model choices we no longer wanted, not to build a new model gateway toolkit.

### S22-01 — We wrote a custom Anthropic transport

`backend/utils/llm/anthropic_transport.py` added 250 lines and its test added 270. It owns request construction, caching, response parsing, and errors that Omi's existing provider client already handled.

**Monkey-see-monkey-do:** keep Omi's proven Anthropic client and delete unsupported model/provider branches around it. **Recommendation: `SIMPLIFY` or revert to the retained client.**

### S22-02 — A simple model map became a detailed workload registry

`backend/utils/llm/model_config.py` replaced Omi's feature-to-provider/model table with `ManagedModelWorkload` records. Every record carries a caller, input contract, output contract, usage feature, result owner, failure policy, and lifecycle state. This turns a cleanup list into a domain registry that must stay synchronized with routes and clients.

**Monkey-see-monkey-do:** delete the rejected profile/provider branches and keep one small feature-to-provider/model map for the retained calls. **Recommendation: `SIMPLIFY`.** The routes themselves already say who calls them and who owns the result.

### S22-03 — We created a generic structured-payload abstraction

`backend/llm_gateway/gateway/structured_payload.py` adds a reusable translation layer for structured model results. The retained workloads could keep their existing request/response shapes.

**Monkey-see-monkey-do:** use the provider SDK's structured-output support directly in the few retained calls. **Recommendation: `LIKELY SIMPLIFY`.**

### S22-04 — Vertex authentication became another abstraction

`vertex_auth.py` and tests wrap credential/project/location behavior that the Google client libraries and Omi configuration already supplied.

**Monkey-see-monkey-do:** change the project/location credentials in Omi's retained Gemini/Vertex client. **Recommendation: `SIMPLIFY`.**

### S22-05 — Inventory, handoff, and continuity machinery grew around a deletion

The model endpoint inventory, S25 gateway handoff document, model config expansion, and agent continuity gauntlet updates describe and enforce a new portfolio architecture. Documentation is useful, but much of the machinery exists because the slice redesigned retained calls.

**Monkey-see-monkey-do:** one small retained-workload table and direct deletion of every other branch. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** `provider_usage.py` is largely a renamed and reduced version of Omi's old gateway accounting module. Removing its pricing ledger while preserving provider response usage is a simplification, not a new accounting system.

---

## S-23 — Delete rejected hosted products and product-data schemas

**Beginner context:** this was another deletion-heavy slice. Two retained needs—local export and local warnings—did require replacements, but both replacements became standalone frameworks.

### S23-01 — Local export became a 590-line archival system

`LocalUserDataExport.swift` walks many stores, builds manifests, copies files, handles exclusions, and packages an archive; tests add another 429 lines. Export is valuable, but the implementation is a general-purpose exporter before the local data format has stabilized.

**Monkey-see-monkey-do:** copy the owned local database plus the small set of user-created attachment folders into a zip, with a short README describing the snapshot. **Recommendation: `SIMPLIFY`.**

### S23-02 — Warning delivery became a notification subsystem

`FairUseWarningNotification.swift` added 327 lines, `FloatingBarNotificationPolicy` 65, and warning tests 464. This creates policy, formatting, continuity, and delivery behavior for a message that can travel through Omi's retained notification service.

**Monkey-see-monkey-do:** map the server's bounded warning code to one local notification at the existing `NotificationService`. **Recommendation: `SIMPLIFY`.**

### S23-03 — We created a slice-specific automation API

`DesktopAutomationS23Actions.swift` added 238 lines for export and warning acceptance. Slice-numbered production automation is a warning sign: the product now knows how the implementation project was organized.

**Monkey-see-monkey-do:** exercise export through the Settings button and inject a warning at the existing notification seam. **Recommendation: `REMOVE` the slice-specific bridge.**

### S23-04 — Fourteen retirement/acceptance test surfaces duplicated absence

Integrated route-closure tests, per-product retirement tests, export tests, notification tests, automation tests, and E2E flows repeatedly prove that deleted hosted products are absent.

**Monkey-see-monkey-do:** one route-manifest assertion for removed backend families, one export behavior test, one warning test, and one Settings E2E flow. **Recommendation: `SIMPLIFY`.**

---

## S-24 — Delete hosted search, vectors, and product-object storage

**Result: `NO MATERIAL REINVENTION FOUND`.**

The 431 added lines are mostly focused edits to existing tests, voice-message behavior, account deletion, and documentation. No large replacement storage/search system was added. The four-line qualification-lease implementation and its test churn are adjacent harness work, but they do not amount to a new architecture.

**Monkey-see-monkey-do judgment:** keep this slice's basic shape. It removed Typesense, Pinecone, product GCS objects, and staging while preserving the required local owners. Do not manufacture a simplification merely because tests changed.

---

## S-25 — Delete workers, duplicate services, and GKE control planes

**Beginner context:** Omi's surviving backend was being collapsed onto one Cloud Run service. Most work should have been deleting duplicate workers and retargeting the few durable tasks.

### S25-01 — Deployment deletion expanded into a concurrency-policy checker

`.github/scripts/check-deployment-concurrency.py` added 287 lines, while release-vector verification, deploy-status reporting, runtime-manifest contracts, and workflow tests also grew. We removed service topology but added a sizable static model of that topology.

**Monkey-see-monkey-do:** delete retired GKE/worker workflow entries, keep Omi's canonical backend deploy job, and make the existing smoke check target that service. **Recommendation: `SIMPLIFY`.**

### S25-02 — Release-vector verification became a new policy surface

`verify_backend_release_vector.py` and 144 lines of tests encode how candidate, image, service, and traffic identities must align. This can catch real deployment mistakes, but it is a new release system rather than the minimum worker-retirement edit.

**Monkey-see-monkey-do:** use the image digest Omi's existing workflow already passes into Cloud Run and verify the deployed revision once. **Recommendation: `LIKELY SIMPLIFY`.** Keep one real deploy assertion, not a parallel policy engine.

**What was not overengineering:** `backend/utils/voice_messages.py` is mostly a rename/move from the deleted sync file owner. The account-deletion task identity test is also a focused check that durable deletion work reaches the surviving service.

---

## S-26 — Consolidate one canonical Python backend and development harness

**Beginner context:** after the worker deletions, the repo still had names and workflows for a separate "desktop backend." The direct move was to rename the one surviving backend and delete duplicate launch/deploy paths.

### S26-01 — A renamed probe became a generalized 402-line candidate system

`backend_candidate_probe.py` is recognizably based on Omi's `desktop_backend_candidate_probe.py`, so the move itself is good. But the retained/new probe plus 122 test lines grew into a broader candidate-validation contract during a topology rename.

**Monkey-see-monkey-do:** rename Omi's existing probe and change its service/image inputs; do not broaden what it proves. **Recommendation: `SIMPLIFY`.**

### S26-02 — We wrote a new image-lineage verifier

`verify_backend_image_lineage.py` added 178 lines and its test added 84. It independently models repository, digest, candidate, and deployed-image lineage.

**Monkey-see-monkey-do:** carry the digest from Omi's existing build output into its deploy step and assert the Cloud Run revision uses that digest. **Recommendation: `LIKELY SIMPLIFY`.**

### S26-03 — Backend consolidation pulled desktop release machinery along with it

`desktop_release_doctor_report.py`, release-flow/manifest tests, preview workflow, `run.sh`, and API routing tests changed while the assigned problem was one canonical Python plane. Some name/path edits are required, but the new cross-release checks enlarge the blast radius.

**Monkey-see-monkey-do:** rename the retained local launcher (`python-desktop-backend-dev.sh` to `python-backend-dev.sh`) and point all callers at it. Leave desktop artifact release policy for S-29. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** Git identifies `python-backend-dev.sh` and `desktop-core-contracts.yml` largely as renames. Those are the desired mechanical edits, not fresh inventions.

---

## S-27 — Re-own Cloud Run, Redis, Firestore, GCS, and deployment

**Beginner context:** this is where Omi's cloud project names, identities, secrets, buckets, and services needed to become ours. Omi already had functioning deployment workflows. The monkey move was mostly substitution plus deletion of infrastructure we no longer used.

### S27-01 — We invented a foundation configuration language

`backend/deploy/runtime_env.yaml` gained 288 lines and `foundation_contract.py` another 146, defining an extensive declarative model of environments, identities, services, buckets, secrets, and permissions.

**Monkey-see-monkey-do:** copy Omi's retained dev/prod workflow and replace its project ID, service name, region, registry, bucket, and secret names with owned values. **Recommendation: `SIMPLIFY` to the configuration actually consumed by deployment.**

### S27-02 — We added a 758-line static drift checker

`foundation_drift.py` plus 522 lines of tests scans repository configuration for disagreements with the new foundation contract. This is a custom linter for a custom configuration language created in the same slice.

**Monkey-see-monkey-do:** make one workflow/config file authoritative and have deployment read it directly, eliminating the duplicated representations that can drift. **Recommendation: `REMOVE` most of the drift framework.**

### S27-03 — We added a second 434-line live-contract checker

`foundation_live_contract.py` separately inspects real cloud resources and compares them with the declared model. A deployment smoke check is useful; a second policy interpreter is expensive.

**Monkey-see-monkey-do:** after deployment, call the retained health endpoint and ask Cloud Run for the active revision/image. Check a bucket or Redis only in the workflow that actually needs it. **Recommendation: `SIMPLIFY`.**

### S27-04 — Workload Identity Federation got its own policy parser

`wif_claim_policy.py` added 241 lines and 152 lines of tests to validate trust claims. Moving away from inherited Omi credentials is necessary, but GitHub and Google already express the policy in their workflow/provider configuration.

**Monkey-see-monkey-do:** copy Omi's WIF workflow pattern, substitute our repository/environment/provider IDs, and rely on the provider's configured attribute condition plus one authentication smoke. **Recommendation: `LIKELY SIMPLIFY`.**

### S27-05 — Artifact cleanup became a policy engine

`artifact_cleanup_policy.py`, tests, and workflow wiring define cleanup decisions for images/artifacts. That is lifecycle optimization, not required to re-own the foundation.

**Monkey-see-monkey-do:** keep Omi's retention command/policy with our registry name, or defer cleanup until artifacts actually accumulate. **Recommendation: `REMOVE` from bootstrap scope.**

### S27-06 — We added a workflow-contract checker beside all the other checkers

`backend_workflow_contract.py`, a larger runtime validator, workflow tests, and manifest entries statically enforce the workflow's shape. This is another description of a workflow that could simply be the authoritative executable description.

**Monkey-see-monkey-do:** keep Omi's working workflow shape and test its rendered/deployed result, not its source choreography. **Recommendation: `SIMPLIFY`.**

### S27-07 — Redis access was refactored while changing ownership

`redis_connection.py` and 220 lines of tests introduced a lazy/TLS connection owner and moved callers to it. Centralizing credentials can be sound, but it is a runtime refactor mixed into cloud-name replacement.

**Monkey-see-monkey-do:** change Omi's Redis URL/secret and retain its client behavior. Refactor connection lifetime only for a demonstrated leak or TLS problem. **Recommendation: `LIKELY SIMPLIFY`.**

**Overall judgment:** S-27 contains the largest concentration of release/infrastructure reinvention. The owned cloud boundary is necessary; the local DSL plus drift parser plus live parser plus WIF parser plus cleanup parser is not the fastest credible route.

---

## S-28 — Establish clean Mac storage and installation identity

**Beginner context:** this requirement is important even with zero users. Intentive must have its own bundle ID and storage root so it does not read, move, or delete Omi's installation. The direct solution is a new identity plus removal of Omi takeover behavior.

### S28-01 — Deleting takeover code required new injectable filesystem seams

`RewindDatabase.swift` gained 127 lines to parameterize storage locations and filesystem behavior, largely so `OmiTakeoverIsolationTests.swift` could prove that foreign state is not touched.

**Monkey-see-monkey-do:** give Intentive a new Application Support path and database filename, then delete all Omi import/takeover branches. **Recommendation: `SIMPLIFY`.** One small path test is enough.

### S28-02 — Startup maintenance became a command-sink policy

`StartupSystemMaintenancePolicy.swift` adds an injected command sink that decides which cleanup commands launch may run. It exists mainly to prove that legacy Omi maintenance is absent.

**Monkey-see-monkey-do:** remove calls to Omi cleanup/import commands from `OmiApp` and keep the ordinary retained startup calls inline. **Recommendation: `REMOVE` the one-use policy object.**

### S28-03 — Isolation was tested through two large suites

`OmiTakeoverIsolationTests.swift` added 118 lines and `LegacyAppTakeoverIsolationTests.swift` 53, on top of identity/storage tests. The important contract is one negative fact: an Intentive launch never touches Omi paths.

**Monkey-see-monkey-do:** one test with a fake Omi directory and a fresh Intentive directory, asserting the former remains byte-for-byte unchanged. **Recommendation: `SIMPLIFY`.**

**What must remain:** the new bundle identifier and new writable namespaces are not overengineering. They are precisely how a separate product avoids touching Omi. What is unnecessary is migration machinery after that separation is established.

---

## S-29 — Re-own Mac build, signing, updates, previews, and release destinations

**Scope used for this review:** every commit after `5a7cfa5a` through current `HEAD` `f504c0a3`, not only the first three changes. This includes `a3daff0e` through `f504c0a3`: safe update admission, universal libwebp preparation, release documentation, desktop identity, Sentry, owner/provider decisions, release boundaries, guard alignment, and acceptance-test follow-ups.

**Beginner context:** Intentive needs its own bundle identity, signing, Sentry project, update feed, release destinations, and backend URL. Omi already had a sophisticated Sparkle/release setup. Most of this should have been literal re-ownership of that setup.

### S29-01 — Safe updates became a cross-application activity state machine

Omi already had `DeferredUpdateInstall`: development builds stayed install-on-quit, while release builds checked recent speech, waited for a 120-second silence window, polled every five seconds, and installed once. S-29 replaced this with `UpdateInstallationActivitySnapshot`, which inspects nine signals across AppState, realtime capture, provider activity, playback, pending tools, token minting, active voice turns, typed-chat sends, and streaming messages. It also added scheduling/cancellation generations and refactored transcription finalization to expose more activity state.

**Monkey-see-monkey-do:** keep Omi's existing deferred installer. If the speech heuristic is genuinely too narrow, replace its `lastSpeechProvider` with one simple `isAppBusy` closure owned by AppState; do not make the updater know nine subsystems. **Recommendation: `SIMPLIFY` aggressively.**

### S29-02 — Update safety pulled unrelated transcription refactoring into the slice

To feed the admission snapshot, `AppState+Transcription.swift` was substantially reorganized, new activity counters were exposed, operations became injectable, and max-duration/finalization paths changed. That increases regression risk in live capture just to decide when Sparkle may quit the app.

**Monkey-see-monkey-do:** ask one existing top-level session owner whether user work is active. Leave transcription internals untouched. **Recommendation: `REMOVE` updater-driven transcription seams.**

### S29-03 — Universal libwebp preparation became a build system inside the build system

Omi already vendored universal `libwebp`/`libsharpyuv` dylibs, documented their creation, copied them into release bundles, rewrote load paths, signed nested code, and had `test-bundled-dylib-rewrite.sh`. S-29 added `prepare-release-libwebp.sh` (464 lines), `rebuild-release-libwebp.sh` (106), `test-release-libwebp.sh` (161), and expanded the signed-artifact smoke. The new path checks fixed checksums, exact architectures, install IDs, minimum OS versions, dependency counts, ABI compatibility, executable linkage, rpaths, signing identity, and can rebuild from source.

**Monkey-see-monkey-do:** use Omi's vendored universal dylibs and existing copy/rewrite/sign steps. Add one `lipo -archs` assertion if we need proof that both `arm64` and `x86_64` are present. **Recommendation: `SIMPLIFY` aggressively.** This is the clearest S-29 wheel reinvention.

### S29-04 — We created a second central identity authority

Omi already centralized bundle-family behavior in `AppBuild.swift` and storage paths in `DesktopStorageIdentity`. S-29 added `OmiSupport/DesktopProductIdentity.swift` with a `Family` enum and constants for bundle IDs, filenames, URL schemes, environment variables, keychain services, path components, and feature permissions. `AppBuild.swift` still exists and grew by 210 lines, so identity now flows through two broad authorities rather than one.

**Monkey-see-monkey-do:** replace the Omi literals inside `AppBuild` and `DesktopStorageIdentity` with Intentive values. Keep one owner for bundle behavior and one narrow storage helper if necessary. **Recommendation: `SIMPLIFY`; do not keep two central identity models.**

### S29-05 — Clean-install identity acquired a large acceptance matrix

`CleanInstallationLifecycleTests.swift` added 169 lines, `DesktopProductIdentityTests.swift` 129, `AppBuildBetaIdentityTests.swift` grew by 103, and storage, keychain, login-item, installer, single-instance, client-device, and API-routing tests all expanded. Much of this verifies every derived name and permission for stable, beta, development, named development, and preview families.

**Monkey-see-monkey-do:** test the stable and dev bundle IDs, their separate Application Support paths, and the single crucial negative rule that Omi paths are untouched. Let the existing beta/preview tests keep their original shape with renamed constants. **Recommendation: `SIMPLIFY`.**

### S29-06 — Backend re-ownership became signed metadata plus fail-closed startup validation

Omi's `DesktopBackendEnvironment` used constant production and development URLs. S-29 changed production to optional `IntentiveProductionAPIURL` metadata, validates scheme/host and rejects Omi/BasedHardware hosts, ignores overrides for production identities, and calls `preconditionFailure` if signed metadata is missing or malformed. Static production-routing guards and API routing tests then enforce the new scheme.

**Monkey-see-monkey-do:** replace Omi's production URL constant with Intentive's owned URL and preserve Omi's existing dev override behavior. **Recommendation: `SIMPLIFY`.** A missing provider value can disable release creation; the shipped app should not need a new metadata parser and startup crash path for a constant endpoint.

### S29-07 — Name substitution expanded into release-guard proliferation

Auto-beta candidate checks, release doctor, release manifest/schema tests, production-routing checks, qualification evidence, stable promotion verifiers, signed smoke tests, app-config tests, beta-variant tests, and many E2E feature vectors were all changed or expanded. Some edits are necessary because identifiers changed; others make the repository prove the same identity/release fact in several places.

**Monkey-see-monkey-do:** copy Omi's release workflow, replace the bundle IDs, app name, repository, feed, signing/notarization values, and public URLs, and run its existing signed-artifact smoke. Add one end-to-end candidate build rather than several source-policy mirrors. **Recommendation: `SIMPLIFY`.**

**What was not overengineering:** `DesktopSentryConfiguration.swift` is only a small set of owned Sentry constants and is a reasonable direct substitution. `OWNER-PROVIDER-DECISIONS.md` is useful evidence about which external values are still missing. Renaming beta scripts and release copy is also mechanical. The new Intentive bundle/storage identity itself is required; the criticism is the second abstraction and the surrounding guard matrix, not the rebrand.

---

## What the wave closeouts changed about these judgments

The closeouts matter because they show whether a slice's "small" abstraction stayed small once the wave was integrated.

### Wave 1 closeout — `3114f616`

This closeout was mostly cleanup: it deleted obsolete checks, failure classes, gateway configuration, BYOK tests, and other residue. It did not introduce a major new product subsystem. The important lesson is that the earlier slices created enough guard and compatibility residue that the closeout had to remove large amounts of it. That supports simplifying S-01 through S-09 at the source instead of adding and later pruning checks.

### Wave 2 closeout — `bdb126dd`

This closeout materially deepened the owner-authorization design. It added `RewindDatabase+OwnerAuthorization.swift`, `OwnerAuthorizedStorageReads.swift`, `RewindDatabase+ProactiveAuthorityRetirement.swift`, `LocalMutationAuthorization.swift`, new owner-fence helpers across assistants, and hundreds of tests. Those additions are included in the S-12, S-13, and especially S-14 judgments above.

In coffee-shop English: each local feature had already put a lock on its own door. The closeout then built a second security desk in the hallway and taught every room how to ask that desk for permission. For a single-user Mac app with a newly opened per-account database, the cleaner boundary is to open the right database once and keep stale async results from writing after an account switch.

### Waves 3–4 closeout — `402d9fea` and `22ad2f16`

The closeout repaired real integration gaps, but it also shows the cost of prior architecture:

- parity capture needed another local-only repair and more tests (`a57b3f8d`), reinforcing the S-16 recommendation to avoid a parity-export subsystem;
- fair-use review needed Redis fallback telemetry and log-redaction repairs (`95d5da6`, `2d0f44fc`), reinforcing the S-20 recommendation to keep the server contract small;
- PTT acceptance was split into a 305-line `RealtimeHubController+LocalProfile.swift` file (`e8b07c18`) with more acceptance coverage, reinforcing the S-19 concern about a voice-specific local-data architecture;
- the broad acceptance restoration commit (`b15d07e3`) touched API routing, conversation compute, realtime policies, local memories, tasks, signing, and many tests at once. That is the integration tax of numerous new seams.

Moving the 299 existing realtime lines into a named file is not itself bad. The concern is that the closeout had to coordinate so many invented contracts to prove the retained Omi experience still worked.

---

## Highest-value simplifications

If we simplify later, do not attack all 102 scenarios at once. These are the highest-return places because one change removes a whole family of complexity:

1. **S-29 release path:** keep Omi's updater and libwebp packaging shape; collapse identity into the existing owner; substitute release values instead of maintaining parallel guard systems.
2. **S-27 cloud foundation:** keep one executable deploy configuration; remove the custom contract/drift/live/WIF/cleanup checker stack where it merely restates that configuration.
3. **S-10 and S-12 local authority:** keep the local data, but remove general-purpose leases, claims, workflow histories, and duplicated model/projection layers that have no present concurrency requirement.
4. **S-20 fair use:** reduce the distributed review workflow to local evidence plus one bounded server decision.
5. **Wave 2 owner fencing:** enforce account ownership once when opening/switching the local database instead of wrapping every read, write, assistant, and late callback.
6. **Production automation seams:** remove slice/domain-specific actions created only so tests can inspect an absence; drive the real retained user entry point or test the owning module directly.
7. **Legacy migrations:** remove compatibility for Omi or earlier Intentive populations that the new bundle/storage namespace will never load.

## Things we should deliberately leave alone

- S-15 and S-24 are good deletion-slice examples; do not invent cleanup work for them.
- Keep the new Intentive bundle ID and isolated writable paths. Separate identity is what protects Omi, not a concession to nonexistent Intentive users.
- Keep generated API clients generated; their line counts are not evidence of design excess by themselves.
- Keep code that Git identifies as a move/rename when its old owner was deleted and the behavior is still needed.
- Keep one meaningful behavior test for each retained user path and its main failure. The problem is duplicated harnesses and internal-state matrices, not testing itself.
- Keep the small owned Sentry configuration and the owner/provider decision record.

## Bottom line

The audit found **102 material simplify/remove scenarios across S-01 through S-29**. The recurring failure was not that we chose the wrong product requirements. It was that we treated each requirement as an opportunity to make Omi more architecturally perfect.

For this bootstrap, the professional default should be much plainer:

1. delete the rejected Omi product surface;
2. preserve the retained Omi code path;
3. replace names, IDs, endpoints, credentials, and storage ownership mechanically;
4. add only the smallest test that proves the changed boundary; and
5. build a new abstraction only after a present-tense Intentive problem cannot be solved cleanly through Omi's existing seam.

That is not careless copying. It is the reason to bootstrap from a mature open-source product in the first place.
