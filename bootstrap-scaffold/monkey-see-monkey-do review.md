# Monkey-see-monkey-do review

## What this review is actually asking

Intentive started from the imported Omi snapshot at repository commit `81b5b889` (upstream Omi `99e0e60`). Omi was the bootstrap: when its code already solved a problem and the product decision did not require a different solution, the fastest move was to keep that code and change only the owner, name, endpoint, or storage location.

`requirements-challenge.md` and `deletion-map.md` already decided what the product should keep, delete, and simplify. This document does **not** use the later slice TDD plans as authority: those plans may themselves have selected a more elaborate implementation than the two governing documents required. It asks a narrower question:

> While implementing each settled slice, where did we add a new framework, policy object, migration, state machine, test-only production seam, release guard, or replacement subsystem when we could have kept Omi's working shape and made the minimum required edit?

This is an additions review. Deletions are not criticized merely for being large. Generated OpenAPI files are not treated as hand-designed complexity. A file move or rename is not called reinvention when Git shows that it mostly preserved Omi code.

## Correction after independent code review

The first version of this document overcounted. It sometimes treated a large implementation or a large test suite as proof of overengineering, and in several places it recommended deleting behavior that `requirements-challenge.md` or `deletion-map.md` explicitly required. Those are false positives.

This revision applies a stricter rule:

- the governing requirement and deletion-map decision come first;
- the imported Omi implementation is the baseline pattern;
- the slice commit and wave closeout show what we actually added;
- a TDD plan can explain why code was written, but it cannot turn an optional design choice into a product requirement;
- line count alone is never a finding; and
- tests and guards are counted separately only when they create a genuinely separate production seam or a second maintained description of the same contract.

The result is deliberately smaller and more trustworthy. In particular, the earlier criticism of S-13 reminders/goals, S-20 fair-use recovery, S-23 structured export, S-27 artifact cleanup, and S-29 update/libwebp/identity work has been removed or narrowed because those behaviors are explicitly required.

One important premise changes several judgments: Intentive has never shipped and has no existing Intentive users. We need a new bundle identity and new storage namespace so we do not operate on Omi's installation. We do **not** need migrations that preserve an imaginary population of old Intentive data.

## How to read the recommendations

- `KEEP` — the addition is a necessary or sensible version of the Omi pattern.
- `SIMPLIFY` — keep the required behavior, but remove the named extra layer around it.
- `REMOVE` — remove only the named added mechanism; this never authorizes deleting required behavior around it.
- `LIKELY SIMPLIFY` — the commit shows a concrete simplification candidate, but the exact replacement should be confirmed against the current callers while editing.
- `NO MATERIAL REINVENTION FOUND` — I checked the additions and would be manufacturing a complaint if I called them a redesign.

"Monkey-see-monkey-do" below never means blindly preserving an Omi product feature that the requirements rejected. It means preserving Omi's proven implementation pattern for the part we decided to keep.

## Audit coverage

| Slice | Implementation scope reviewed | Added lines | Result after correction |
|---|---|---:|---|
| S-01 | `eb73915f` | 259 | 2 simplification candidates |
| S-02 | `3af14608` | 937 | No material reinvention found |
| S-03 | `6f1967f7` | 1,994 | 1 simplification candidate |
| S-04 | `f3265450` | 758 | No material reinvention found |
| S-05 | `c026719a` | 2,030 | 3 simplification candidates |
| S-06 | `ff528f8a` | 40,690, including 35,160 generated OpenAPI lines | 2 simplification candidates |
| S-07 | `d67d6e6e` | 862 | 1 simplification candidate |
| S-08 | `7e6e0b5d` | 388 | 3 simplification candidates |
| S-09 | `3aab1026` | 847 | No material reinvention found |
| S-10 | `77a77e39` | 18,337, including 8,038 generated OpenAPI lines | 4 simplification candidates |
| S-11 | `131018d8` | 8,346, including 912 generated OpenAPI lines | 4 simplification candidates |
| S-12 | `73dd3a8a` | 10,754, including 3,168 generated OpenAPI lines | 4 simplification candidates |
| S-13 | `46d67ccb` | 10,402, including 4,290 generated OpenAPI lines | No material reinvention found |
| S-14 | `26c67df6` | 5,368, including 1,656 generated OpenAPI lines | 3 simplification candidates |
| S-15 | `e7c25932` | 103 | No material reinvention found |
| S-16 | `cf64b673` | 2,033 | 3 simplification candidates |
| S-17 | `5c649679` | 2,683 | 3 simplification candidates |
| S-18 | `a0468e58` | 3,614 | 3 simplification candidates |
| S-19 | `684d97a4` | 2,480 | 4 simplification candidates |
| S-20 | `16e86b97` | 5,766 | No material reinvention found |
| S-21 | `ee35939d` | 2,314 | 3 simplification candidates |
| S-22 | `5d6573ff` | 2,244 | 4 simplification candidates |
| S-23 | `06a917e7` | 5,031 | 2 simplification candidates |
| S-24 | `ac3ba541` | 431 | No material reinvention found |
| S-25 | `fbdb339f` | 1,461 | 2 simplification candidates |
| S-26 | `3a9dbdd0` | 1,623 | 3 simplification candidates |
| S-27 | `5a7cfa5a` | 4,885 | 6 simplification candidates |
| S-28 | `47efd453` | 350 | No material reinvention found |
| S-29 | Everything after `5a7cfa5a` through current `HEAD` `3605c00d` | 4,947 product/release/doc additions after excluding `.ua`, installed agent-skill files, and this review | No material reinvention found |

The slice commits did not land in numeric order in every wave. The table uses the logical slice number, not Git's display order. S-29 includes all current branch commits after S-27, including the update, libwebp, identity, Sentry, documentation, release-guard, acceptance-test, Firebase-development-app, and sign-in-provider follow-ups. The enormous committed `.ua` graph and installed Firebase skill package are tooling/reference material rather than Intentive product implementation, so their generated/reference line counts are excluded from the S-29 product number. Uncommitted changes outside this document were left untouched and were not assigned to a slice.

---

## S-01 — Remove the cloud Agent VM and database mirror

**Beginner context:** Omi had the normal assistant on the Mac and a second per-user computer in Google Cloud. This slice correctly removed the cloud computer. The question is whether we changed unrelated machinery while doing that.

### S01-01 — We rebuilt the retained image-publishing path

Omi already used the standard `docker/build-push-action` to build and publish the desktop backend and return its digest. The unwanted Agent VM had its own separate build step. S-01 could have deleted only that second step. Instead, both retained workflows were changed to build locally, smoke-test that exact local image, push it manually, inspect the registry digest, and enforce the sequence with `.github/scripts/check-desktop-backend-release-policy.py` and tests.

**Monkey-see-monkey-do:** delete the Agent VM image block and leave Omi's retained backend image action alone. **Recommendation: `SIMPLIFY`.** Exact-artifact smoke testing may be valuable later, but it was a new release-system project hiding inside a deletion slice.

### S01-02 — We put a test trigger into production code for memory-pressure cleanup

`DesktopAutomationBridge.swift`, `ResourceMonitor.swift`, and `HardeningSeamActionTests.swift` gained a non-production `simulate_memory_remediation` action and a wrapper to exercise the path after Agent VM hooks disappeared. This made the product expose a new automation seam solely so a deletion could be tested.

**Monkey-see-monkey-do:** remove the Agent VM callback from Omi's existing remediation path and keep the path itself unchanged. Test the remaining behavior through the existing resource-monitor entry point. **Recommendation: `SIMPLIFY`.** Do not keep a product API whose only customer is a test for removed code.

**What was not overengineering:** the small route-retirement test covering the seven removed Agent VM routes and neighboring retained routes is a useful behavioral fence. It proves we deleted the right server surface without inventing a new runtime.

---

## S-02 — Remove wearables, the Omi write-ahead log, and device-audio ingestion

**Beginner context:** this slice made the Mac microphone the only capture source. Most work was deletion. The important distinction is between removing live wearable/photo behavior and destructively deleting historical cloud data, which the governing documents keep separately gated.

**Corrected verdict: `NO MATERIAL REINVENTION FOUND`.** The first review got this wrong. `deletion-map.md` separates application behavior from destructive handling of inherited cloud data: the wearable/photo protocol becomes inaccessible, but existing remote photo data is not destroyed without separately authorized cleanup. `requirements-challenge.md` also keeps historical `ConversationSource` decoding so retained records remain readable. The legacy-photo guard and historical decoder therefore protect explicit boundaries; they are not compatibility work for imaginary Intentive installations.

`backend/database/job_run_locks.py` is also a narrow extraction of a still-used Omi helper from a deleted owner. That is exactly the monkey-see-monkey-do pattern we want.

---

## S-03 — Remove hosted Parakeet and every Deepgram branch

**Beginner context:** Omi supported several speech-to-text providers. The decision was to keep the managed Modulate route and delete the others. We did not need to redesign speech-to-text itself.

### S03-01 — We created a miniature Modulate testing service

The slice added `backend/testing/listen_pusher_stack/modulate_stub.py`, new offline-app factories, fake provider routing, and a wider dev-harness provider matrix. This is useful test infrastructure, but it is substantially more than deleting Parakeet and Deepgram branches around Omi's existing Modulate implementation.

**Monkey-see-monkey-do:** retain Omi's Modulate path and use a small injected fake response at its current client seam. **Recommendation: `SIMPLIFY`.** A protocol-faithful fake service is not needed until an actual integration failure demands it.

**Correction:** the earlier observability and “provider matrix” findings were too broad. Removing provider-specific deploy settings, alerts, fixtures, and selection cases is part of deleting Deepgram/hosted Parakeet, while proving the one retained Modulate path still succeeds and fails correctly is ordinary coverage. Changing Parakeet-specific VAD names to provider-neutral names is also a mechanical cleanup. Only the separate fake-service stack remains a credible simplification candidate.

---

## S-04 — Remove impossible controls and repository zombies

**Beginner context:** a "repository zombie" is code or a control that looks alive but cannot work anymore. This was mostly a deletion-and-narrowing slice, so Git rename detection matters before calling a surviving checker new.

**Corrected verdict: `NO MATERIAL REINVENTION FOUND`.** Git shows that `check-desktop-production-routing.py` is a 33%-similar rename and narrowing of Omi's mobile production-routing checker, not a new checker invented from scratch. The release-process guard shrank by roughly 886 net lines in this commit, so the earlier claim that it “grew” was factually wrong. The generated-contract failure class cites the real missing-schema failure from the imported subset rather than a hypothetical incident. This slice mostly deleted dead machinery and re-owned the small surviving checks.

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

**What was not overengineering:** `PermissionGuidanceOverlay`, `FlowLayout`, `DismissableSheet`, `OverlayModalEscapeCatcher`, and `OnboardingChatPersistence` mostly preserve Omi code that had lived inside files being deleted. `daily_summary.py` is also largely a rename from `external_integrations.py`. These are good examples of moving the useful bricks instead of rebuilding them.

---

## S-07 — Remove customer BYOK and preserve managed access

**Beginner context:** BYOK means users supplying their own model-provider keys. The decision was to remove that choice and always use the product's managed access.

### S07-01 — We added production automation endpoints to inspect a removed choice

`DesktopAutomationManagedAccessActions.swift` exposes managed-access snapshots, and new automation tests use it to verify that BYOK controls and BYOK-shaped errors are gone. The production app gained an observation API because the test wanted to see an absence.

**Monkey-see-monkey-do:** delete key-entry controls and customer-key headers, then update Omi's existing authentication and settings tests. **Recommendation: `REMOVE` the dedicated automation action.**

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

**Corrected verdict: `NO MATERIAL REINVENTION FOUND`.** The first review misunderstood the temporary `desktop_screen_activity.py` split. S-09 inherited one mixed Crisp/screen-history router. The commit removed Crisp and isolated the untouched non-Crisp remainder so S-15 could delete it; it did not invent a new product route. S-15 then removed that exact handed-off file.

The 32-line `ChatMessageActionPresentation` helper and `TaskDetailMetadataProjection` are small extractions that let the commit remove rejected feedback behavior without tangling the retained Chat and Task presentation. The LangSmith work repaired trace correlation that the retained observability boundary depended on. None is strong enough to call a wheel reinvention.

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

---

## S-13 — Make Tasks and one simple Goal local-authoritative

**Corrected verdict: `NO MATERIAL REINVENTION FOUND`.** The earlier section was not supported by the governing requirements.

- Local schedule/reschedule/cancel reminders are explicitly retained in `requirements-challenge.md`; `TaskReminderService.swift` is implementing that decision, not adding a surprise feature.
- Stable owner-scoped task identity, deterministic local ordering, and account-switch safety are part of making Tasks local-authoritative. They cannot be reduced to an unowned global list.
- The “Goals became richer” claim was backwards. In commit `46d67ccb`, `GoalsWidget.swift` lost 912 lines while adding 112, and `GoalStorage.swift` lost 223 while adding 111. The slice removed AI/progress/history complexity to reach the one-simple-goal requirement.
- Large additions to `TasksPage.swift` and `DashboardPage.swift` are not, by themselves, evidence of a redesign. The requirements retain a detailed Tasks surface and Home behavior. This review did not isolate a new user behavior or duplicate production authority beyond those decisions.

The right monkey-see-monkey-do conclusion is to keep this slice unless a future code-level review can point to a specific duplicated mechanism. File size alone is not enough.

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

**Corrected verdict: `NO MATERIAL REINVENTION FOUND`.** The first review reopened product decisions that `requirements-challenge.md` and `deletion-map.md` had already settled.

The required behavior is not merely “send a counter and get allowed/blocked.” The governing documents retain the existing managed GPT-5.1 semantic classifier, bounded seven-day/up-to-thirty-conversation evidence, graduated warning/final-warning/restrict stages, automatic seven-day and thirty-day recovery, support reset/override/resolve behavior, content-free history, and backend-derived enforcement. They also require local evidence to cross only in one authenticated transient request and never become hosted product content.

Against that contract:

- the backend pending request and idempotent retry are needed so a transient disconnect does not create a phantom strike or lose an admitted review;
- the Mac coordinator is in-memory coordination around the one local evidence read and authenticated submission, not a second durable review store;
- the transactional backend acceptance is needed to keep the event and enforcement state from disagreeing;
- recovery and support history are explicitly retained product behavior; and
- the automation/tests exercise privacy, owner switching, idempotency, and the required state transitions rather than inventing a second fair-use product.

There may still be ordinary cleanup opportunities inside the code, but this audit did not isolate a concrete extra authority or duplicate durable store. Recommending a summary/counter endpoint would change the requirement rather than simplify its implementation.

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

**What was not overengineering:** `provider_usage.py` is largely a renamed and reduced version of Omi's old gateway accounting module. Removing its pricing ledger while preserving provider response usage is a simplification, not a new accounting system.

---

## S-23 — Delete rejected hosted products and product-data schemas

**Beginner context:** this was another deletion-heavy slice. Two retained needs—complete offline local export and local delivery of retained warnings—required real replacement work. Those behaviors are not findings.

**Required, not overengineering:** IR-830 explicitly requires an independently specified, versioned export of local-authoritative product data. Copying `omi.db` and attachment folders would expose raw implementation storage, omit domains that live outside that database, and violate the export contract. Complete paged readers, deterministic ordering, one owner fence, offline operation, atomic replacement, and failed-partial cleanup are the point of `LocalUserDataExport.swift`.

The warning path is also required because S-23 deletes FCM only after surviving fair-use and managed-usage warnings have an authenticated structured state seam and deterministic Mac in-app/local notification delivery. The earlier recommendation to collapse it to an unexamined notification call was too vague to count as a finding.

### S23-03 — We created a slice-specific automation API

`DesktopAutomationS23Actions.swift` added 238 lines for export and warning acceptance. Slice-numbered production automation is a warning sign: the product now knows how the implementation project was organized.

**Monkey-see-monkey-do:** exercise export through the Settings button and inject a warning at the existing notification seam. **Recommendation: `REMOVE` the slice-specific bridge.**

### S23-04 — Fourteen retirement/acceptance test surfaces duplicated absence

Integrated route-closure tests, per-product retirement tests, export tests, notification tests, automation tests, and E2E flows repeatedly prove that deleted hosted products are absent.

**Monkey-see-monkey-do:** keep the behavior tests for complete export, warning delivery, and the main failure path. Consolidate only overlapping route-absence assertions that exercise the same public app registry. **Recommendation: `LIKELY SIMPLIFY`.** The number of test files alone is not evidence; the candidate is the duplicated route-absence coverage.

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

### S27-05 — We added a workflow-contract checker beside all the other checkers

`backend_workflow_contract.py`, a larger runtime validator, workflow tests, and manifest entries statically enforce the workflow's shape. This is another description of a workflow that could simply be the authoritative executable description.

**Monkey-see-monkey-do:** keep Omi's working workflow shape and test its rendered/deployed result, not its source choreography. **Recommendation: `SIMPLIFY`.**

### S27-06 — Redis access was refactored while changing ownership

`redis_connection.py` and 220 lines of tests introduced a lazy/TLS connection owner and moved callers to it. Centralizing credentials can be sound, but it is a runtime refactor mixed into cloud-name replacement.

**Monkey-see-monkey-do:** change Omi's Redis URL/secret and retain its client behavior. Refactor connection lifetime only for a demonstrated leak or TLS problem. **Recommendation: `LIKELY SIMPLIFY`.**

**Required, not overengineering:** the earlier artifact-cleanup finding was wrong. IR-885 and `deletion-map.md` explicitly require a dry run that selects only untagged artifacts older than 30 days while protecting every exact release/candidate/rollback digest. `artifact_cleanup_policy.py` implements that decision. We can simplify its code if duplicate logic is found, but we cannot defer or delete the behavior without reopening the requirement.

**Overall judgment:** S-27 still contains the largest concentration of credible release/infrastructure simplification candidates. The owned cloud boundary, dry-run cleanup, rollback protection, and live verification are necessary. The question is narrower: do the foundation contract, static drift parser, live parser, WIF parser, workflow parser, and Redis refactor duplicate facts that one executable environment declaration and the actual provider APIs could own?

---

## S-28 — Establish clean Mac storage and installation identity

**Corrected verdict: `NO MATERIAL REINVENTION FOUND`.** `deletion-map.md` makes the acceptance boundary explicit: clean install, upgrade from Intentive's own first build, reset, sign-out, account switch, and uninstall/reinstall must never read or mutate an Omi installation.

The injected filesystem/process seams are how the tests can drive the real production startup and database code against synthetic roots without touching a real Omi installation. `StartupSystemMaintenancePolicy` is the narrow observation point for proving that retained startup work still runs while Omi process termination and deletion do not. The two suites cover different owners: database/filesystem takeover and startup process/app takeover.

This is not migration support for nonexistent Intentive users. It is a negative safety proof around the new product boundary. The new bundle ID, typed identity, separate writable namespaces, and no-touch tests should remain.

---

## S-29 — Re-own Mac build, signing, updates, previews, and release destinations

**Scope used for this review:** every commit after `5a7cfa5a` through current `HEAD` `3605c00d`, not only the first three changes. This includes safe update admission, universal libwebp preparation, release documentation, desktop identity, Sentry, owner/provider decisions, release boundaries, guard alignment, acceptance follow-ups, Firebase development-app registration, and sign-in-provider enablement. The committed `.ua` graph, the review document, and installed Firebase skill references are excluded from product-complexity judgments.

**Corrected verdict: `NO MATERIAL REINVENTION FOUND`.** The three examples that originally motivated this review—safe update installation, universal libwebp preparation, and central desktop identity—are all direct requirements, not optional polishing.

### Safe update installation is a required repair

IR-245 says the old VAD-only gate is ineffective and must be replaced with authoritative retained activity state for ambient meeting/transcription work, PTT/realtime voice, and active Chat/model/tool work. Omi's `DeferredUpdateInstall` cannot simply remain because its production activity signal has no reliable writer. `UpdateInstallationActivitySnapshot` collects the named authorities and preserves busy-to-idle waiting before Sparkle relaunches. The transcription changes expose real state to that one admission seam; they are not an updater-specific replacement transcription engine.

### Universal libwebp preparation is a required release input

IR-939 and `deletion-map.md` explicitly require the retained libwebp 1.5.0 cache to have executable provenance checks: expected checksums, both `arm64` and `x86_64`, `@rpath` install names, a compatible minimum macOS, nested signing, and a from-source rebuild fallback. Recommending only `lipo -archs` would leave most of the requirement unproved. The preparation/rebuild/test scripts are the executable owner of that boundary.

### `DesktopProductIdentity` is the one central authority

The earlier “second authority” claim was factually wrong. `AppBuild` consumes/delegates to `DesktopProductIdentity`; the new type centralizes the stable/Beta/dev/named-dev/preview family and the exact bundle, URL-scheme, Keychain, app-group, filename, and path capabilities required by the S-28/S-29 boundary. The continued existence of `AppBuild` does not make it a competing constant source.

### The acceptance and routing checks protect distinct release boundaries

The identity tests prove family derivation and no Omi namespace collision; install tests prove the retained atomic installer uses the new identity; routing checks prove a signed production bundle cannot silently ship an inherited Omi/BasedHardware endpoint; signed-artifact checks prove the actual bundle; promotion and preview checks protect their existing Omi release stages. A large combined line count does not prove those checks are duplicates.

### Current Firebase follow-ups are mechanical re-ownership

The commits after the first review replace development Firebase app metadata, record the owned project/provider state, enable the retained Apple/Google sign-in providers, and extend the existing app-config shell assertions. They do not add another authentication architecture. The large installed Firebase skill package is repository tooling/reference material and is not part of Intentive's runtime.

`DesktopSentryConfiguration.swift`, `OWNER-PROVIDER-DECISIONS.md`, beta-script renames, and release copy remain straightforward substitutions. This audit found no concrete S-29 mechanism that can be removed while still satisfying the governing update, identity, packaging, signing, routing, preview, and release requirements.

---

## What the wave closeouts changed about these judgments

The closeouts matter because they show whether a slice's "small" abstraction stayed small once the wave was integrated.

### Wave 1 closeout — `3114f616`

This closeout was mostly cleanup: it deleted obsolete checks, failure classes, gateway configuration, BYOK tests, and other residue. It did not introduce a major new product subsystem. The important lesson is that the earlier slices created enough guard and compatibility residue that the closeout had to remove large amounts of it. That supports simplifying S-01 through S-09 at the source instead of adding and later pruning checks.

### Wave 2 closeout — `bdb126dd`

This closeout materially deepened owner authorization with `RewindDatabase+OwnerAuthorization.swift`, `OwnerAuthorizedStorageReads.swift`, `RewindDatabase+ProactiveAuthorityRetirement.swift`, `LocalMutationAuthorization.swift`, and late-result fences across assistants.

The important correction is that owner fencing itself is required. The app supports sign-out, account changes, and same-UID reauthentication while asynchronous model/storage work may still be in flight. “Open the right database once” does not stop an old callback from owner A writing after owner B takes over. The remaining S-12/S-14 simplification question is only whether several feature-specific wrappers repeat a shared fence that could have one owner. S-13 is no longer cited as an overengineering example.

### Waves 3–4 closeout — `402d9fea` and `22ad2f16`

The closeout repaired real integration gaps, but it also shows the cost of prior architecture:

- parity capture needed another local-only repair and more tests (`a57b3f8d`), reinforcing the S-16 recommendation to avoid a parity-export subsystem;
- fair-use review needed Redis fallback telemetry and log-redaction repairs (`95d5da6`, `2d0f44fc`), but those repairs protect the explicitly required transient-evidence/content-free-state boundary and are not evidence that S-20 should be redesigned;
- `RealtimeHubController+LocalProfile.swift` mostly moved 299 existing lines into a named file, so the move itself is not reinvention; and
- the broad acceptance restoration commit (`b15d07e3`) touched many boundaries at once. That is useful integration evidence, but breadth alone does not prove every boundary was invented.

The closeout therefore strengthens the parity-pack simplification question, but it does not revive the removed S-20 finding or turn code movement/test breadth into findings.

---

## Highest-value simplifications

If we simplify later, do not attack every candidate at once. These are the highest-return places because one change could remove a whole family of complexity:

1. **S-27 cloud foundation:** keep the required environment, WIF, live verification, rollback protection, and dry-run artifact cleanup, but see whether one executable configuration can replace overlapping contract/drift/workflow interpreters.
2. **S-10 and S-12 local authority:** keep the required local data, restart safety, lifecycle transitions, and retry behavior, but look for generic leases, claims, workflow histories, and model/projection layers that duplicate an existing Omi owner.
3. **S-22 managed models:** keep every retained workload/provider decision while checking whether the custom transport, structured-payload layer, Vertex wrapper, and detailed workload registry restate provider SDK or route behavior.
4. **Wave 2 owner fencing:** keep the required A-to-B-to-A and late-callback protection, but consolidate feature-specific wrappers only where one shared database-generation fence can express the same behavior.
5. **Production automation seams:** remove slice/domain-specific actions created only so tests can inspect an absence; drive the real retained user entry point or test the owning module directly.
6. **Legacy migrations:** remove compatibility for Omi or earlier Intentive populations only where `requirements-challenge.md`/`deletion-map.md` do not expressly preserve historical data or an upgrade boundary.

## Things we should deliberately leave alone

- S-15 and S-24 are good deletion-slice examples; do not invent cleanup work for them.
- S-02, S-04, S-09, S-13, S-20, S-23's export/warning behavior, S-27's cleanup behavior, S-28, and S-29 contain corrections in this revision; do not reintroduce the removed claims without new commit evidence.
- Keep the new Intentive bundle ID and isolated writable paths. Separate identity is what protects Omi, not a concession to nonexistent Intentive users.
- Keep generated API clients generated; their line counts are not evidence of design excess by themselves.
- Keep code that Git identifies as a move/rename when its old owner was deleted and the behavior is still needed.
- Keep one meaningful behavior test for each retained user path and its main failure. The problem is duplicated harnesses and internal-state matrices, not testing itself.
- Keep the small owned Sentry configuration and the owner/provider decision record.

## Bottom line

After correction, the audit contains **60 concrete simplification candidates across S-01 through S-29**, not 102 “material findings.” A candidate means the commit added a named mechanism that appears broader than the Omi pattern needed for the governing decision; it is not a license to remove the required behavior, and it still needs caller-level confirmation before code changes.

The independent review and consistency pass removed 42 false, duplicate, or line-count-only claims. The biggest corrections were important: the required fair-use workflow, structured export, reminders/goals, artifact cleanup, no-touch identity proof, safe update gate, universal libwebp preparation, and central desktop identity are not overengineering. The credible recurring concern is narrower: some slices surrounded required behavior with additional policy objects, local workflow machinery, custom parsers, duplicate projections, automation-only production seams, or overlapping release/configuration descriptions.

For this bootstrap, the professional default should be much plainer:

1. delete the rejected Omi product surface;
2. preserve the retained Omi code path;
3. replace names, IDs, endpoints, credentials, and storage ownership mechanically;
4. add only the smallest test that proves the changed boundary; and
5. build a new abstraction only after a present-tense Intentive problem cannot be solved cleanly through Omi's existing seam.

That is not careless copying. It is the reason to bootstrap from a mature open-source product in the first place.
