# S-13 TDD plan — Make Tasks and one simple Goals product local-authoritative

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | S-13 |
| Type | Local-authority adaptation and feature reduction |
| Deliverable | Execution-grade TDD implementation plan only |
| Assigned decisions | IR-025 through IR-032, IR-098 through IR-105, IR-616 through IR-658, IR-825 |
| Required predecessor | S-10 local conversations/source-session authority; S-06 sharing/connector deletion is already integrated in this checkout |
| Planned behavioral TDD cycles | 17, after one non-counted entry/rebase gate |
| Product-code status | No product code is changed by this document |

This plan is the implementation contract for replacing the current local-cache-plus-cloud-authority task system with one owner-scoped GRDB task authority, retaining the deliberately selected Tasks and Task Assistant behavior, retaining one deliberately small local Goals product, and deleting the remote task/goal control planes and rejected UI/runtime branches. It is not permission to mutate live infrastructure.

## 2. Planning status and pinned baseline

- Planning checkout: branch `review-wave-1-deletions` at full commit `0d9934c9d2ed61bd02ac8784e50f56ee816257c3`.
- Baseline proof run while planning: `git merge-base --is-ancestor 0d9934c HEAD` returned success.
- Requirements proof run while planning: `python3 bootstrap-scaffold/validate-requirements-ledger.py` returned `PASS (714 indexed rows, 714 detailed sections, all reviewed)`.
- Current status: **researched; implementation must not start until integrated S-10 is present and this inventory has been refreshed against that tree**.
- The current checkout contains the completed S-06/S-07 Wave 1 state, but S-10 is represented only by an untracked planning document, not integrated production code. The source-grounded flow below therefore describes the real pre-S-10 implementation at the pinned baseline.
- This plan treats `bootstrap-scaffold/requirements-challenge.md` as the decision authority. When an earlier decision is narrowed or reversed by a later assigned decision, the later decision wins: IR-643 supersedes IR-032's local review-inbox wording; IR-652 supersedes IR-651's slider deletion; IR-629, IR-630, IR-631, IR-633, IR-634, IR-635, and IR-647 narrow the broad field-retention language in IR-025/IR-620/IR-625.
- Historical GRDB migrations and changelog entries are evidence, not live product compatibility contracts. Existing migration names remain immutable; a new forward migration makes old and fresh databases converge on the retained schema.
- There is no inherited Omni customer population. Do not add cloud backfills, old-ID adapters, deprecated aliases, dual writes, ignored request fields, fake-success routes, or no-op services.

## 3. Outcome

At S-13 repository closure:

1. `RewindDatabase`'s per-owner GRDB database and its `action_items` table are the sole durable authority for task identity, description, completion, deletion/Undo, due date, priority, recurrence, order, retained source/evidence fields, and source-session linkage.
2. Every retained mutation—Tasks UI, Dashboard/Home projections, typed Chat tools, realtime/PTT task tools, Task Assistant extraction, recurrence, automation, and S-10's conversation cascade—commits through `ActionItemStorage` and is complete without a network response.
3. `TasksStore` is an observable projection/orchestrator over local storage, not a synchronizer. It has no server paging, merge, census, reconciliation, retry, rollback, or full-sync state.
4. Due-time task reminders are durable local `UNUserNotificationCenter` requests keyed by the surfaced local task ID; create/reschedule replaces them, completion/deletion/deadline removal cancels them, and launch/owner transitions reconcile them from GRDB.
5. The visible Tasks product is one grouped To Do/Done list with the exact retained search, inline creation/editing, recurrence, priority, details/provenance, Undo, drag/order, keyboard, pagination, settings, and Task Assistant behavior. Every explicitly rejected task field, control, view, scheduler, ranking system, suggestion queue, task-attached agent, and workstream is absent.
6. `GoalStorage` and the local `goals` table are the sole authority for a stable local goal ID, title, optional description, active/completed status, and timestamps. The surviving Dashboard/onboarding/Chat goal paths work offline; numeric progress, AI generation/advice, task links, canonical goal lifecycle, and both cloud goal systems are absent.
7. No Mac production path calls task, staged-task, candidate, goal, workstream, task-tool, or productivity-score APIs. Their backend routes, Firestore implementations, task-specific push helpers, generated client operations, route policy, indexes, fixtures, scripts, workflow, tests, and current docs are deleted or narrowed.
8. Removed HTTP operations are absent from FastAPI/OpenAPI and fail with 404; no 410 compatibility registry or inert replacement survives.
9. Offline use, restart durability, account switching/owner isolation, conversation-source integration, and a real named non-production bundle have been exercised before closure.

## 4. Authorizing requirements: individual IR map

The table maps every one of the 60 assigned IRs to its concrete S-13 disposition and the cycle that proves it. “Handoff” still means the IR is accounted for: S-13 supplies the local task/goal input, while the adjacent product owner implements its own UI/runtime.

| IR | Required disposition in S-13 | Proof cycle |
|---|---|---|
| IR-025 | Make local GRDB tasks authoritative; delete backend IDs/sync flags, `/v1/action-items` use, Firestore copies, API paging/merge/census/reconcile/retry/rollback/full-sync/migration paths. Later field decisions below narrow its early tags/scores/metadata wording. | C2, C15, C16 |
| IR-026 | Delete candidate/staged compatibility, What Matters Now, cloud context/open-loop uploads, intervention/feedback/outcome stores, outboxes, rollout/control contracts. Its older “port review under IR-032” clause is superseded by IR-643. | C10, C17 |
| IR-027 | Keep one local goal with stable local identity, title, optional description, active/completed state; make Chat read active local goals; delete both backend goal systems, sync, numeric progress, AI goal features, stale retirement, canonical lifecycle, idempotency/account-generation, and task/workstream links. | C13, C17 |
| IR-028 | Delete Work on this/task sidebar chat/Execute, task agent state, workstream IDs, detail/events/artifacts/checkpoints/continuity/receipts/control, and their UI/settings/tests/contracts/Firestore; preserve ordinary main Chat. | C14, C17 |
| IR-029 | Do not implement Focus history here. S-13 only exposes owner-scoped local task/goal reads needed by S-14; S-14 owns the local Focus record/history reduction. | Handoff to S-14; gate G5 |
| IR-030 | Do not alter Focus classification, cooldown, notifications, or persistence here. S-13 removes cloud task/goal inputs and supplies local inputs; S-14 owns the Focus coach localization. | Handoff to S-14; gate G5 |
| IR-031 | Keep allowed app/window selection, context-switch and messaging triggers, Gemini extraction, confidence/ownership policy, local task/goal context, dedupe, source/evidence, and idempotent direct local writes. Delete outbox/candidate/staged/promotion/server-copy paths. | C10, C11 |
| IR-032 | Do **not** create the previously proposed local candidate queue. IR-643's later decision deletes Suggested and ambiguous review entirely; direct high-confidence admission and ambiguous discard are the final rule. | C10 |
| IR-098 | Retain realtime `create_action_item`, write through local `ActionItemStorage`, and preserve provider-spoken confirmation. | C12 |
| IR-099 | Keep model/tool-description intent, owner/active-turn/allowlist/input-hash/replay/local-mutation fences; add no parser, confirmation turn, preview, or separate dispatch. | C12 |
| IR-100 | When voice `create_action_item` omits `due_at`, set `Date() + 24 hours`; validate and preserve an explicit due time. | C12 |
| IR-101 | Key local notification requests by surfaced local ID; create/update replace, completion/delete/deadline clear cancel, launch/owner transitions reconcile; delete backend copy/token/FCM dependency. | C4, C5, C6, C7, C12 |
| IR-102 | Do not emit an immediate Task Added system banner. Persist locally, let UI observe the row, speak the tool result, and deliver only the later due reminder. | C12 |
| IR-103 | Keep voice complete/pending, rename, and reschedule through owner-authorized local writes, immediate local invalidation, and local reminder reconciliation; delete backend PATCH/refresh/FCM banner paths. | C12 |
| IR-104 | Keep model-selected intent/matching and ambiguity handling plus owner/run/attempt/allowlist/replay fences; use surfaced local IDs and add no second confirmation/read receipt. | C12 |
| IR-105 | Keep realtime `get_tasks` for overdue/today and broader `get_action_items` for future/undated/completed/date-filter/full-list reads; both query local storage. | C12 |
| IR-616 | Keep the visible grouped list as canonical; delete `tasksViewIsBoard`, segmented control, `tasksBoardView`, Board columns/placeholders, and `TaskBoardCard`. | C9 |
| IR-617 | Rename the first deadline section exactly to **Today & Overdue** while preserving grouping and ordering. | C1 |
| IR-618 | Delete the first-section bulk deadline-clear ×, alert, `clearTodayDeadlinesForIncompleteTasks`, plumbing, tests, and copy. | C9 |
| IR-619 | Keep case-insensitive description search across unfinished and completed non-deleted local records; active search ignores the To Do/Done switch; no backend/semantic/model search. | C8 |
| IR-620 | Keep the circled-check To Do/Done switch; delete `TaskFilterGroup`, `TaskFilterTag`, `DynamicFilterTag`, advanced-filter UI/state/query/count branches. Later IR-629/630 delete tags/category despite this earlier preservation clause. | C8, C9 |
| IR-621 | Keep +, Command-N, Return creation, Escape cancel, and selected-task inline placement; delete `showingCreateTask`, `TaskCreateSheet`, and modal-only state/tests. | C3, C9 |
| IR-622 | Keep selected-row context and exact mappings: Today 11:59 PM, Tomorrow start of day, Later +7 days start of day, No Deadline nil; flat view inherits exact selected date; no preview/confirmation. | C3, C7 |
| IR-623 | Keep click/double-Return editing, one-second debounce, Return/click-away/Escape Save & exit, trim/prior-value restore, and manual-edit marker; local transaction is final. | C3 |
| IR-624 | Keep checkbox/Space animation, immediate To Do/Done movement, history, and reopening the same row/metadata; reconcile reminders; no remote rollback. | C5 |
| IR-625 | Keep Daily/Weekdays/Weekly/Every 2 Weeks/Monthly/Never; completed row stays Done; atomically create exactly one future occurrence and skip missed backlog. Copy only fields retained after IR-629/630/631/647. | C5 |
| IR-626 | Delete `RecurringTaskScheduler`, its coordinator/start/stop/timer/retry/query/tests; retain recurrence generation and reminders, never automatic agent execution. | C5, C14 |
| IR-627 | Keep per-row calendar/date-time Save/Cancel, relative labels, recurrence indicator; add **Remove deadline**, move to No Deadline, and cancel the reminder. | C3, C4 |
| IR-628 | Keep unfinished-row hover **+ Priority**, High/Medium/Low only, immediate choice/checkmark/badge; no clear/None action. | C3 |
| IR-629 | Delete tags across `TagBadgeInteractive`, modal, prompts/models, metadata/accessors, details, filters, agents, recurrence, tests, schema, and contracts; no migration for hypothetical users. | C9, C10, C15 |
| IR-630 | Delete semantic task `category` across model/storage/UI/prompt/recurrence/Chat/contracts; preserve the unrelated due-date `TaskCategory`. | C9, C10, C15 |
| IR-631 | Delete `source_category`/`source_subcategory` from prompt/tool/model/record/metadata/filter/tests; preserve `source`, `sourceApp`, `windowTitle`, context/activity, confidence, capture facts, and evidence/provenance. | C9, C10, C15 |
| IR-632 | Keep info-circle hover preview, pointer-transfer delay, full fixed scrolling Task Details sheet, close behavior, retained task state and explicit source/evidence fields; remove rejected children. | C9 |
| IR-633 | Delete `TaskDetailMetadataProjection` catch-all use, `allMetadataEntries`, `remainingMetadata`, and **Other Info**; render only explicitly retained fields and add no raw-metadata replacement. | C9 |
| IR-634 | Delete `source = omi-analytics`, Analysis section and `original_message`/`creation_reason`/`key_findings`/`search_summary`/`relevant_files` compatibility. Preserve PostHog diagnostics and retained Gemini extraction. | C9 |
| IR-635 | Keep `inferred_deadline` only as transient validated model output converted to `dueAt`; do not persist or display the raw string. | C9, C10, C15 |
| IR-636 | Hide the task-detail Conversation/raw local session ID and raw Goal row; preserve the S-10 relationship for conversation lookup/cascade, not navigation. | C9, C15 |
| IR-637 | S-06 already removed public task sharing. S-13 only reruns exact residue searches and must not recreate Share UI, APIs, Redis tokens, public pages, copies, generated contracts, or notifications. | G2, C9, residue closure |
| IR-638 | Keep hover trash/Command-D/flat left swipe/no confirm/animation/five-second toast; max ten newest-first pending rows with count/timer reset; local soft-delete before UI, same-row Undo, timeout purge, shutdown/owner nonrecoverability, launch purge. | C6 |
| IR-639 | Delete multi-select state, header/row controls, gestures/gates, `TasksStore.deleteMultipleTasks`, backend loops, tests/automation; add no bulk replacement. | C9, C16 |
| IR-640 | Delete `indentLevel`, UserDefaults fallback, Tab/Shift-Tab, buttons/swipes/guides/padding/sort payload/contracts/tests. Rows are flat; left swipe deletes. | C7, C15 |
| IR-641 | Keep grouped To Do drag handle/targets/preview, same-section order, exact cross-section due mappings, No Deadline clear, transaction-before-UI, reminder update, coalesced local numeric `sortOrder`, fallback sort. Disable in search/Done; delete backend/UserDefaults authority. | C7 |
| IR-642 | Keep Up/Down, captured-ID single Return New below, double Return edit, Space, Command-D, Command-N, Escape behavior, 0.4-second timing, scrolling/selection/hints and context guards; delete indent keys/hints. | C7 |
| IR-643 | Delete Suggested/Checking Suggested, `SuggestedTasksStore`, candidate models/adapter/actions/policies, Do now/Later/Dismiss/Edit, suppression, attribution/outboxes, hydration/navigation/automation/tests, and all candidate/staged/control/backend residue. No local candidate table. | C10, C17 |
| IR-644 | Keep conditional non-manual+provenance **Why** / **Why Omi added this** read-only popover, plain-language source classification, linked-source count, accessibility ID; move it out of deleted Suggested code and add no raw IDs/navigation/network. | C9, C10 |
| IR-645 | Keep local `createdAt < 60s` New capsule/background and precedence; natural recomputation only, no timer/persisted state/count/settings/analytics/cloud. | C1, C9 |
| IR-646 | Delete `TaskPrioritizationService`, startup/timers/Gemini/profile refresh/last-run/gate/staged scoring/backend batch score/Re-score/tests/docs; preserve manual priority/order and unrelated AI Profile. | C9, C10, C15, C17 |
| IR-647 | Delete `relevanceScore`/`scoredAt` across models/schema/migrations/backfills/search/Chat/context/prompts/contracts/tests. Use deterministic priority/due/order/recency context, no replacement AI score. | C2, C9, C10, C15, C16 |
| IR-648 | Keep local 100-row initial pages, separate To Do/Done offsets, extra-row/count `hasMore`, near-bottom/Load More, refresh/retry/loading/empty/completed-empty/search-empty states; no network truth. | C8 |
| IR-649 | Keep gear, **Task Settings** help, `.navigateToTaskSettings`, Settings/Advanced navigation and Task Assistant highlight; point only to retained controls. | C11 |
| IR-650 | Keep Task Assistant card/switch/default-on/UserDefaults/runtime checks/independence; delete `SettingsSyncManager` push/hydration for Task settings and discard disabled in-flight work before observation/task mutation. | C10, C11 |
| IR-651 | Superseded by IR-652. Do not delete the interval slider; delete only its cloud request/response and settings-sync ownership. | C11 |
| IR-652 | Keep **Extraction Interval**, subtitle, 10 seconds/10 minutes/1 hour, ten-minute default/fallback, local preference/formatting/slider; earlier context-switch/~15-second messaging triggers remain; change need not rearm sleeping timer. | C11 |
| IR-653 | Keep label/subtitle, 30–90% ten-point steps, 75% default/display/local persistence, observation-before-threshold; fixed 80% safety floor still blocks ambiguous visible tasks. | C10, C11 |
| IR-654 | Keep prompt row/Edit/window/per-keystroke local persistence/count/reset/done/Command-Return/no Cancel/no Save; delete cloud settings ownership and rejected schema fields/branches; code gates override prompt. | C10, C11 |
| IR-655 | Keep Test Run reusable window, previous 24h/editable range/up to 100,000 frames, real Gemini, filters, sequential context-switch replay, local searches, stop-between-frames/errors/progress/results, and zero observations/tasks. Add no cap/warning/sampling/dev gate. | C11 |
| IR-656 | Keep Allowed Apps copy/default set/sorted rows/icons/browser badges/remove/add/Return/running chips/refresh/exact display-name match/all enforcement/Rewind exclusion precedence/empty restores defaults. | C11 |
| IR-657 | Keep Browser Keywords copy/default list/chips/UI filtering/add-remove/count/case-insensitive dedupe/browser classification/title substring/missing-title reject/nonbrowser bypass/all enforcement/empty restores defaults. | C11 |
| IR-658 | Keep non-prod local automation `create_task`, bounded `seed_tasks`, `toggle_task`, `delete_task`, `reorder_task`, `dump_tasks`; real paths, ambiguity, headless load, flush/readback/marker/stable IDs. Delete backend fields/waits and `inject_requery_during_drag`. | C7, C8, C15 |
| IR-825 | Delete `/v1/daily-score`, `/v1/scores`, Firestore calculations, Python response models, Mac `getScores`/state/loading/widgets/exporter entry, generated contracts, route policy, tests/docs; retain ordinary completion data/calculations only if another retained caller is proved. | C16 |

## 5. Dependencies and entry gates

### G0 — fresh implementation baseline

Before the first production edit, run `make setup`, fetch `origin`, and record `git rev-parse HEAD`, `git merge-base HEAD origin/main`, and `git log -1 --format='%H %s'`. Work in the current worktree/branch; do not rename or switch it. Re-run the requirements-ledger validator. If the ledger or deletion-map S-13 brief changed, stop and update this plan before code.

### G1 — integrated S-10 is mandatory

S-10 must already provide the production shape selected by IR-314 and IR-353:

- one owner-scoped stable local source-session ID on the authoritative local conversation/session row;
- a local relationship from `action_items` to that source session;
- Conversation Detail's Action Items count/rows querying `ActionItemStorage`, not `Structured.actionItems`/`actionItemsJson` or `/v1/conversations/{conversation_id}/action-items`;
- permanent deletion of every still-linked local task in the same transaction as source-session deletion while unrelated tasks survive.

At execution, record the integrated S-10 commit and exact symbols it introduced, then replace every pre-S-10 path/symbol in this plan with the integrated names. Stop C2/C15 if S-10 is absent or if it still exposes only backend conversation IDs. Do not build a temporary ID bridge, duplicate relationship, cloud lookup, title cache, or embedded action-item copy.

### G2 — S-06 sharing boundary

S-06 is present at this baseline and owns IR-637. The current source search finds no live `shareTasks`, `task_share`, `h.omi.me/tasks`, or task Share control. S-13 must preserve that absence. A discovered live sharing caller after rebase is a stop condition: assign it to the S-06 integration follow-up rather than recreating task publication.

### G3 — owner and schema safety

`RewindDatabase.switchUser(to:)`, pool generation, and the per-user path under `~/Library/Application Support/Omi/users/{userId}/` are current authority boundaries. All tests use isolated temporary databases. Stop any cycle that cannot demonstrate wrong-owner rejection, stale-pool invalidation, and no cross-owner notification/Undo leakage.

### G4 — no premature backend deletion

Do not begin C16/C17 until C1–C15 are green with the task/goal network unavailable, a cold restart, and owner switching. Every retained in-tree Mac caller must either use local storage or be deleted. A remaining production call to a retiring operation blocks backend teardown.

### G5 — cross-slice consumer refresh

S-14 consumes local task/goal context for Focus, Insight, proactive advice, and AI Profile. S-19 consumes local task tools for the broader PTT lifecycle. S-21 protects Tasks navigation/shell behavior. Before deleting a shared field or helper, compile against their integrated work or record the exact downstream adaptation in the same branch. S-13 must not implement their product behavior.

### G6 — generated and route contracts

OpenAPI and generated Swift/agent tool surfaces must change only after production callers move. Removed operations must disappear, not become deprecated/410/no-op operations. A generator mismatch, unexplained route-policy entry, or retained app client is a hard stop before C16/C17 GREEN.

## 6. Verified current production codeflow

This is the actual pinned-baseline flow, not the target.

### Task identity, database, and reads

1. `RewindDatabase` in `desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift` initializes a per-owner GRDB pool. Migration `createActionItemsTable` creates `action_items`; later migrations add tags, FTS, relevance, agent, goals, staged tasks/FTS, ordering/indent, task chat, recurrence, and canonical task fields.
2. `ActionItemRecord` in `Rewind/Core/ActionItemModels.swift` stores an optional local `Int64` `id` plus `backendId`/`backendSynced` and many retained/rejected fields. `TaskActionItem` in `TaskActionItem.swift` is a server-shaped string-ID projection. `ActionItemTaskIdentity` and `fetchRecord(_:surfacedId:)` in `ActionItemStorage.swift` accept either `.backend(String)` or `.local(Int64)`; local IDs are surfaced as `local_<rowid>`.
3. `ActionItemStorage` already performs real local reads (`getLocalActionItems`, `getFilteredActionItems`, `searchLocalActionItems`, count variants, FTS, ID lookup) and writes (`insertLocalActionItem`, `updateCompletionStatus`, `updateActionItemFields`, `updateSortOrders`, soft/hard delete and purge). The same actor also contains cloud-cache authority (`syncTaskActionItems`, `reconcileDashboardVisibilityFields`, `markAbsentTasksAsStaged`, `hardDeleteAbsentTasks`, `markSynced`, `getUnsyncedActionItems`, backend-ID delete), relevance/embedding APIs, agent state, and due-recurring-agent queries.
4. `TasksStore.shared` in `Stores/TasksStore.swift` is the observable source used by UI, but it is currently a two-authority orchestrator. `loadDashboardTasks`, `refreshDashboardTasksFromServer`, `refreshTasksIfNeeded`, `reconcileWithAPIIfNeeded`, `loadTasks`, `fetchPage`, `syncPage`, `reconcileConfirmedEmptyCloud`, `loadIncompleteTasks`, `loadCompletedTasks`, `loadDeletedTasks`, migration calls, `retryUnsyncedItems`, paging, create/toggle/delete/restore/update/tag/bulk methods, and `syncScoresToBackend` mix API truth, local cache, rollback, and local-only fallbacks.
5. `DashboardTaskRefreshService.refresh` and `DashboardTaskRefreshPolicy` fetch a bounded server window/exact rows, synchronize it into SQLite, reconcile visibility, and hard-delete absent server rows. `StartupWarmupCoordinator`, `DashboardPage.DashboardViewModel`, `HomeStatusStore`, `TodaysTasksWidget`, `AboutUserCard`, and `NotchMomentsCoordinator` consume the shared task projection.

### Tasks page behavior and mutations

1. `TasksPage.swift` contains `TasksViewModel`, the `TasksPage` SwiftUI hierarchy, due-date `TaskCategory`, advanced filter types, row/detail/editor/drag/keyboard/Undo/automation behavior, and `registerAutomationActions`.
2. The visible page loads through `TasksStore`, but filtered/search paths query `ActionItemStorage` directly. Create, complete, update, delete/restore, and reorder optimistically update memory/local storage and also call API methods. `syncSortOrdersToBackend` and `batchUpdateSortOrders` make network acceptance part of order completion. UserDefaults contains legacy ordering/indent fallback.
3. `TaskRow`, `DueDateBadgeInteractive`, `PriorityBadgeInteractive`, `TagBadgeInteractive`, `InlineTaskCreationRow`, `TaskCreateSheet`, `UndoToastView`, `TaskCategorySection`, `TaskDragDropModifier`, and keyboard monitoring implement the current interaction surface. `TaskDetailButton`, `TaskDetailTooltip`, `TaskDetailView`, and `TaskDetailMetadataProjection` in `TaskDetailViews.swift` display explicit fields plus generic metadata.
4. Completion currently delegates to `TasksStore.toggleTask`; recurrence creation is a follow-on store operation rather than one guaranteed local transaction. `RecurringTaskScheduler` is a different dormant one-minute task-agent execution loop configured by `ViewModelContainer` and stopped in `OmiApp`; it is not the retained recurrence generator.
5. Deletion uses local soft deletion and an in-memory Undo stack, but final purge is coupled to cloud/full-sync lifecycle. The automation actions wait for backend IDs/sync and include the server-refresh test-only `inject_requery_during_drag` action.

### Task Assistant and Suggested path

1. `ProactiveAssistantsPlugin` constructs/registers `TaskAssistant`, starts `TaskPrioritizationService` and `TaskPromotionService`, and stops promotion. `TasksPage` also starts prioritization. `TaskAssistantSettings` stores the switch, prompt, interval, confidence, notifications, Allowed Apps, and Browser Keywords in `UserDefaults`; `SettingsSyncManager` also hydrates/pushes them to the backend.
2. `TaskAssistant` receives eligible screen frames/context switches and messaging fast-path events, builds Gemini input using local task/goal context, calls Gemini, and applies policy/dedupe. Its present `saveTaskToSQLite`/`syncTaskToBackend` path writes staged/candidate representations, calls `ScreenCandidateAdapter`, uploads task-intelligence attribution, and triggers promotion rather than finishing as one ordinary local task.
3. `StagedTaskStorage`, `SuggestedTasksStore`, `SuggestedTasksSection`, `ScreenCandidateAdapter`, `TaskPromotionService`, and `TaskPrioritizationService` implement the local/cloud review, promotion, and ranking layers. `EmbeddingService` currently indexes both `action_items` and `staged_tasks`.
4. `SettingsContentView+Assistants.swift` exposes the retained controls plus the rejected Task Prioritization/Re-score row. `TaskPromptEditorWindow` writes the prompt immediately. `TaskTestRunnerWindow` can replay up to 100,000 filtered screenshots sequentially through real Gemini and is intended not to mutate observations/tasks.

### Typed Chat and realtime/PTT tools

1. Tool definitions originate in `desktop/macos/agent/src/runtime/omi-tool-manifest.ts` and policy in `desktop-tool-policy.ts`, with generated Swift in `GeneratedRealtimeTools.swift`, `GeneratedToolCapabilities.swift`, and `GeneratedToolExecutors.swift` plus `agent/tests/fixtures/tool-manifest.json`.
2. `ChatToolExecutor.execute` handles `get_action_items`, `create_action_item`, `update_action_item`, task search, and delete behavior. The task cases at the current baseline call `APIClient+Tools` (`toolGetActionItems`, `toolCreateActionItem`, `toolUpdateActionItem`) and then server-refresh `TasksStore`; some other Chat paths directly use local SQL/`ActionItemStorage` and backend IDs.
3. `RealtimeHubController+SessionDelegate.executeAuthorizedRealtimeTool` handles `get_tasks` locally through `TasksStore.loadDashboardTasks`, returning overdue/today rows. Generated executors relay other task tools into `ChatToolExecutor`. `RealtimeHubSession`, `AuthorizedToolOwnerBoundAuth`, `LocalMutationAuthorization`, and the controller's current turn/run/replay gates protect dispatch; these fences survive.
4. `NotificationService` currently emits immediate generic notifications. `UserNotificationCallbackBridge` in `ProactiveAssistantsPlugin+NotificationSettings.swift` wraps settings, authorization, and add, but has no pending-request query/removal seam. Backend action-item routes call task-specific helpers in `backend/utils/notifications.py` for created/completed/data/update/deletion events.

### Goals

1. `GoalRecord` stores a local row plus `backendId`, `backendSynced`, goal type, numeric/scale bounds/progress/unit, active/completed/deleted, and timestamps. `GoalStorage` can read local goals but primarily `syncServerGoals`/`syncServerGoal`, marks rows synced, finds unsynced rows, and mutates by backend ID.
2. `DashboardViewModel.loadDashboardData` calls `loadScores` and `loadGoals`; `loadGoals` fetches API goals then synchronizes `GoalStorage`. Goal create/update/progress/delete methods call `APIClient` first. `GoalsWidget`, `GoalsHistoryPage`, and `GoalCelebrationView` consume `Goal` from `APIClient+GoalModels.swift`.
3. A second cloud goal product lives in `DashboardIntelligenceStore` and `WhatMattersNowSection.swift` with canonical/focused goal projections. `GoalsAIService`, `GoalGenerationService`, goal prompts/models, onboarding `SBOnboardingModel`, and Chat progress extraction create/advise/update cloud goals and task links.
4. `TaskAssistant`, `AIUserProfileService`, Focus code, Chat prompts, and onboarding read cloud-shaped goals. `DesktopAutomationBridge` actions `goals_snapshot` and `create_test_goal` prefer/create API goals with numeric fields.

### Python/backend and storage

`backend/main.py` imports and mounts the following current routers. The task/goal operations are:

- `routers/action_items.py`: `PATCH /v1/action-items/batch`; `POST/GET /v1/action-items`; `GET /v1/action-items/search`; `GET /v1/action-items/ids`; `GET/PATCH/DELETE /v1/action-items/{action_item_id}`; `PATCH /v1/action-items/{action_item_id}/completed`; `POST /v1/action-items/batch-delete`; `POST /v1/action-items/batch`; and `GET/GET count/DELETE /v1/conversations/{conversation_id}/action-items`.
- task operations within retained `routers/tools.py`: `GET/POST /v1/tools/action-items` and `PATCH /v1/tools/action-items/{action_item_id}`.
- `routers/candidates.py`: create/list/migrate/control/get/accept/reject/expire under `/v1/candidates`.
- `routers/staged_tasks.py`: create/list/clear/delete/batch-scores/promote/migrate/migrate-conversation-items under `/v1/staged-tasks`.
- `routers/task_recommendations.py`: `/v1/what-matters-now`, evaluation, interventions, feedback, outcomes, context/open-loop snapshots, and `/v1/task-intelligence/debug/evaluations/{evaluation_id}`.
- `routers/goals.py`: current/all/create/canonical/focus/lifecycle/detail/progress-events/update/progress/history/delete/suggest/advice/extract-progress/get-by-id under `/v1/goals`.
- `routers/workstreams.py`: `POST /v1/work-intents`; workstream get/update; events; artifacts/status; checkpoints; and `/v1/workflow-migrations/task-goal-links`.
- `routers/scores.py`: `GET /v1/daily-score` and `GET /v1/scores`, both calculated by `database.action_items`.

Firestore implementations live in `database/action_items.py`, `candidates.py`, `staged_tasks.py`, `task_intelligence_control.py`, `task_recommendations.py`, `goals.py`, and `workstreams.py`. Candidate/control/recommendation/workstream code uses user subcollections including `action_items`, `candidates`, `candidate_idempotency_aliases`, `candidate_pending_claims`, `candidate_resolution_claims`, `staged_tasks`, `task_intelligence_control`, `task_intelligence_state`, `task_feedback`, `task_outcomes`, `task_interventions`, `task_attention_overrides`, `task_recommendation_projections`, `task_recommendation_decisions`, `task_context_snapshots`, `task_open_loop_snapshots`, `task_snapshot_receipts`, `goals`, goal event/history data, `workstreams`, workstream events/artifact refs/heads/checkpoints, and mutation/intent receipts. The exact live names must be re-derived from `.collection(...)` calls after S-10 rebase before deletion.

`firestore.indexes.json` currently has three `action_items` composite indexes, two `candidates` indexes, and one `task_attention_overrides` index. `backend/services/users/data_export.py` exports cloud `action_items`; `backend/services/users/account_deletion.py` enumerates action-item IDs to purge vectors; `database.users.delete_user_data` recursively deletes all user subcollections. S-13 removes the task-specific export/vector dependencies but does not weaken generic retained recursive account deletion.

## 7. Complete caller and dependency inventory

This inventory records every current production family discovered by exact-symbol/path searches at the pinned baseline. The execution-time refresh in G0/G1 is part of completeness because S-10 will change shared conversation files.

### Desktop production and schema inventory

| Current file(s) and verified symbol(s) | Current role | S-13 disposition |
|---|---|---|
| `Desktop/Sources/Rewind/Core/RewindDatabase.swift` — `RewindDatabase`, `createActionItemsTable`, `createActionItemsFTS`, `createGoalsTable`, `createStagedTasksTable`, `createStagedTasksFTS`, `addActionItemSortOrder`, `createTaskChatMessages`, `addActionItemRecurrence`, `addCanonicalTaskContractV1` | Per-owner pool and accumulated schema | ADAPT; add one forward convergent rebuild/drop migration, retain history |
| `Rewind/Core/ActionItemModels.swift` — `ActionItemRecord`, `StagedTaskRecord`; `TaskActionItem.swift` — `TaskActionItem` | Local/server/staged task shapes | ADAPT `ActionItemRecord`/projection to retained local shape; DELETE `StagedTaskRecord` and rejected fields |
| `Rewind/Core/ActionItemStorage.swift` — `ActionItemTaskIdentity`, `ActionItemStorage` and read/write/sync/rank/agent methods | Mixed local authority and cloud cache | ADAPT into sole authority; DELETE dual-ID/cloud/rank/agent branches; simplify after callers migrate |
| `Stores/TasksStore.swift` — `TasksStore` and load/refresh/reconcile/page/mutation methods | Observable cache plus API/local orchestration | ADAPT to local projection only; DELETE server state/rollback/migration/retry |
| `Stores/DashboardTaskRefreshService.swift`, `DashboardTaskRefreshPolicy.swift` | Server freshness/reconciliation | DELETE after local Dashboard/Home callers pass |
| `MainWindow/Pages/TasksPage.swift` — `TasksViewModel`, `TasksPage`, `TaskCategory`, task rows/sections/drag/editor/Undo/automation | Entire Tasks UI/control surface | ADAPT/prune per IR-616–658 |
| `MainWindow/Pages/TaskDetailViews.swift` — `TaskDetailButton`, `TaskDetailTooltip`, `TaskDetailView`, `TaskDetailMetadataProjection` | Hover and full details | KEEP shell; ADAPT explicit fields; DELETE generic projection/catch-alls |
| `MainWindow/Tasks/SuggestedTasksSection.swift`, `SuggestedTasksStore.swift` | Suggested review UI/store | DELETE, except move retained Why presentation into ordinary Tasks ownership |
| `Services/RecurringTaskScheduler.swift`; `ViewModelContainer.swift`; `OmiApp.swift` | Dormant recurring task-agent execution | DELETE scheduler and exact configure/stop calls |
| `MainWindow/Components/TaskChatPanel.swift`; `ProactiveAssistants/Assistants/TaskAgent/{TaskAgentManager,TaskAgentSettings,TaskAgentStatusRegistry,TaskAgentViews,TaskChatCoordinator,TaskChatRuntime,TaskChatState,TaskThreadProjection,TaskWorkstreamContinuity}.swift`; `Rewind/Core/TaskChatMessageStorage.swift`; `FloatingControlBar/ProactiveTaskExecute.swift` | Task-attached Chat/Execute/agent/workstream continuity | DELETE; preserve main `ChatProvider` and general runtime |
| `ProactiveAssistants/Assistants/TaskExtraction/{TaskAssistant,TaskAssistantSettings,TaskDeduplicationService,TaskModels}.swift` | Retained extraction/settings/dedupe | ADAPT to direct local admission and reduced schema |
| `TaskExtraction/{ScreenCandidateAdapter,TaskPrioritizationService,TaskPromotionService}.swift`; `Rewind/Core/StagedTaskStorage.swift` | Candidate/promotion/rank compatibility | DELETE |
| `ProactiveAssistants/ProactiveAssistantsPlugin.swift`; `Services/SettingsSyncManager.swift`; `SettingsPage.swift`; `Settings/Sections/SettingsContentView+Assistants.swift`; `ProactiveAssistants/UI/{TaskPromptEditorWindow,TaskTestRunnerWindow}.swift` | Startup/settings/Test Run | ADAPT retained controls; DELETE task sync/Re-score/startup branches |
| `Services/NotificationService.swift`; `ProactiveAssistantsPlugin+NotificationSettings.swift` — `UserNotificationCallbackBridge` | Existing system notification boundary | ADAPT narrowly for keyed pending-request schedule/query/remove; preserve unrelated notification behavior |
| `Services/APIClient/APIClient+TaskCatalog.swift`; `Stores/APIClient+Tasks.swift`; `Services/APIClient/APIClient+Tools.swift` | Task/candidate/staged/workstream/tool HTTP clients | DELETE retiring operations/files when no retained operations remain; do not delete unrelated tools |
| `Providers/ChatToolExecutor.swift`; `Providers/ChatProvider.swift`; `Chat/ChatPrompts.swift`; `Chat/DesktopCapabilityRegistry.swift` | Typed Chat task operations/schema/discoverability | ADAPT task operations and schema to local reduced model; preserve ordinary Chat |
| `FloatingControlBar/RealtimeHubController+SessionDelegate.swift`, `RealtimeHubSession.swift`, `AboutUserCard.swift`, `NotchMomentsCoordinator.swift`, `FloatingControlBarReceiptCard.swift` | Realtime task reads/writes and projections | ADAPT only task data calls; preserve lifecycle/voice/card contracts owned by S-19 |
| `agent/src/runtime/omi-tool-manifest.ts`, `desktop-tool-policy.ts`; generated `GeneratedRealtimeTools.swift`, `GeneratedToolCapabilities.swift`, `GeneratedToolExecutors.swift`; `agent/tests/fixtures/tool-manifest.json` | Tool schemas and generated relay | ADAPT retained local tools, delete rejected fields/tools, regenerate |
| `Rewind/Core/GoalRecord.swift`, `GoalStorage.swift` | Local mirror of cloud Goal | ADAPT into sole simple local authority |
| `Services/APIClient/APIClient+GoalModels.swift`; goal methods and `getScores` in `APIClient.swift` | Goal/score HTTP models/client | DELETE goal/score operations and rich cloud shapes after UI moves |
| `MainWindow/Pages/DashboardPage.swift` — `DashboardViewModel`; `Components/{GoalsWidget,GoalCelebrationView,DailyScoreWidget}.swift`; `Pages/GoalsHistoryPage.swift` | Goal and score UI | ADAPT one local goal surface; DELETE numeric/history/score-only behavior |
| `MainWindow/Dashboard/DashboardIntelligenceStore.swift`, `WhatMattersNowSection.swift`, `HomeSuggestionsStore.swift` | Canonical goals and task-intelligence Home product | DELETE rejected task/goal portions; preserve unrelated Home state under S-11/S-21 |
| `ProactiveAssistants/Assistants/Goals/{GoalGenerationService,GoalModels,GoalPrompts,GoalsAIService}.swift`; `Onboarding/SecondBrain/SBOnboardingModel.swift` | AI/numeric goal creation/advice/onboarding | DELETE AI goal services; ADAPT onboarding to local simple create |
| `ProactiveAssistants/Services/AIUserProfileService.swift`; Focus/Task Assistant goal consumers | Cross-slice goal context | ADAPT to `GoalStorage` read; S-14 owns broader behavior |
| `DesktopAutomationBridge.swift` — task actions, `goals_snapshot`, `create_test_goal`; `DesktopAutomationManagedAccessActions.swift` | Non-prod semantic acceptance | ADAPT to local IDs/data only; delete rejected actions/fields |
| `MainWindow/Components/TodaysTasksWidget.swift`; `Pages/HomeStatusStore.swift`; `StartupWarmupCoordinator.swift`; `ViewModelContainer.swift`; `MainWindow/DesktopTopBar.swift`; `TierManager.swift`; `ViewExporter.swift` | Secondary consumers/startup/export | ADAPT task/goal local reads; delete daily-score exporter entry only |
| `AnalyticsManager.swift`, `PostHogManager.swift` | Ordinary task analytics and task-intelligence events | KEEP retained task added/completed/deleted/extracted events if still authorized by S-09; DELETE attribution/promotion-only methods after caller proof; IR-634 does not delete product analytics |
| `ProactiveAssistants/Services/EmbeddingService.swift` | Combined action/staged local semantic index | DELETE staged branch; retain ordinary action-item embedding only if a retained local caller is proved after IR-619/647 review, otherwise simplify/delete under C10/C15 |

### Desktop test and acceptance inventory

Retain/rewrite into production-seam behavioral coverage: `ActionItemLocalIdentityMutationTests.swift`, `ActionItemsFTSRepairTests.swift`, `TasksStoreObserverTests.swift`, `TasksStoreOwnerBoundaryTests.swift`, `TasksViewModelCompletedToggleTests.swift`, `TasksViewModelLoadMoreTappedTests.swift`, `Task03ReorderStressTests.swift`, `TasksSortOrderBandingTests.swift`, `TaskAssistantContextPromptTests.swift`, `TaskAssistantPromptTests.swift`, `TaskDeduplicationSafetyTests.swift`, `TaskSourceClassificationTests.swift`, `TaskDetailMetadataProjectionTests.swift` (rewrite for explicit projection), `NotchMomentsFollowUpCountTests.swift`, `AuthorizedToolOwnerBoundAuthTests.swift`, `ChatToolExecutorActionItemIDTests.swift`, `ChatToolExecutorPolicyTests.swift`, `ChatToolExecutorSQLTests.swift`, `GoalProgressTests.swift` (replace numeric assertions with simple lifecycle), `SignOutStorageInvalidationTests.swift`, and shared test database support.

Delete after replacement proof because they exclusively protect rejected authority/behavior: `ActionItemStorageVisibilityReconciliationTests.swift`, `ActionItemsListResponseTests.swift`, `DashboardTaskRefreshPolicyTests.swift`, `TasksStoreApiPageLimitTests.swift`, `TasksStoreEmptyCloudReconcileTests.swift`, `TasksStoreMergeWithoutAddingTests.swift`, `TasksSortOrderSyncFailureTests.swift`, `TaskReorderMirroredArraysTests.swift`, `TaskRequeryInjectionTests.swift`, `RecurringTaskSchedulerGateTests.swift`, `StagedTaskSyncIntegrityTests.swift`, `SuggestedTasksPresentationPolicyTests.swift`, `SuggestedTasksStoreTests.swift`, `TaskIntelligenceContractFixtureTests.swift`, `TaskChatLegacyAcpMigrationTests.swift`, `TaskThreadLegacyMigrationTests.swift`, `TaskThreadProjectionTests.swift`, `GoalGenerationServiceTests.swift`, and rejected goal/candidate cases inside `APIClientCandidateTests.swift`, `APIClientStagedScoreBatchTests.swift`, `DashboardIntelligenceStoreTests.swift`, `DesktopAutomationSecondaryActionTests.swift`, `APIClientRoutingTests.swift`, and auth-retry tests. Mixed test files are narrowed, not wholesale-deleted.

E2E/acceptance fixtures requiring exact rewrites are `desktop/macos/e2e/flows/tasks.yaml`, `tasks-crud.yaml`, `goals-dashboard.yaml`, `goal-ai-profile-generation.yaml`, `dashboard.yaml`, and `view-export-retained-surfaces.yaml`; delete `scripts/scenario-13-task-thread-e2e.sh`. `tasks.yaml` currently expects Today, Indent/Outdent, Suggested, and task chat; `tasks-crud.yaml` expects `synced`; `goals-dashboard.yaml` creates numeric API goals. Those expectations are explicitly rejected and cannot be copied forward.

### Backend production inventory

| Current file(s) | Verified responsibility | S-13 disposition |
|---|---|---|
| `backend/main.py` | Router imports/mounts | Remove only retiring router imports/includes |
| `routers/action_items.py`, `database/action_items.py`, `models/action_item.py` | Firestore task CRUD/search/paging/score/cascade | DELETE after Mac/S-10 migration |
| task operations in `routers/tools.py`; `utils/retrieval/tool_services/action_items.py`; `utils/retrieval/tools/action_item_tools.py` | Backend agent task tools | DELETE task operations/modules, retain conversation/memory tool router operations |
| `routers/candidates.py`, `database/candidates.py`, `models/candidate.py` | Candidate lifecycle and claims | DELETE |
| `routers/staged_tasks.py`, `database/staged_tasks.py`, `models/staged_task.py` | Staged compatibility/promotion | DELETE |
| `routers/task_recommendations.py`, `database/task_recommendations.py`, `models/task_recommendation.py`, `models/task_intelligence.py`, `database/task_intelligence_control.py` | What Matters/control/recommendations | DELETE |
| `utils/task_intelligence/` all 13 current Python modules | Capture, policy, candidates, contracts, rollout, migrations, recommendation/workstream association | DELETE only after any retained general helper caller is disproved; move no compatibility shell |
| `routers/goals.py`, `database/goals.py`, `models/goal.py`, `utils/goals_response.py`, `utils/llm/goals.py` | Cloud goals, AI advice/progress | DELETE goal-exclusive code |
| `routers/workstreams.py`, `database/workstreams.py`, `models/workstream.py`, `models/workstream_association.py` | Work intents/workstreams/artifacts/checkpoints | DELETE |
| `routers/scores.py`, `models/score.py`; `get_daily_score`/`get_scores` in `database/action_items.py` | Productivity score product | DELETE |
| `utils/notifications.py` task-specific `send_action_item_data_message`, update/deletion/batch/created/completed helpers and their action-item/candidate/conversation callers | FCM task copies/banners/reminder control | DELETE task-specific helpers/calls; preserve generic FCM for S-23 |
| `utils/conversations/process_conversation.py`, `merge_conversations.py`; task portions of `routers/conversations.py` and `utils/llm/conversation_processing.py` | Cloud conversation action-item creation/cascade | Reinspect after S-10; delete cloud task writes, preserve S-10 local producer/cascade boundary on Mac |
| `services/users/data_export.py` | Cloud action-item export | Remove backend action-item reader; hand local export reader acceptance to S-08 |
| `services/users/account_deletion.py` | Cloud action-item vector enumeration/purge | Remove task-vector purge after task/vector authority deletion; preserve generic worker/account wipe |
| `database/users.py:delete_user_data` | Recursive Firestore user-subcollection deletion | KEEP AS IS; it safely deletes any retained/stranded subcollection and is not task authority |
| `utils/metrics.py`, `testing/workflow_contracts.json`, `testing/import_isolation.py` | Mixed task-intelligence metrics/workflow/import contracts | Narrow only task-exclusive entries; retain other owners |

Backend tests exclusive to the deleted product are the current action-item, candidate, staged-task, task-intelligence/recommendation, goal, workstream, score portions of:

`test_action_item_canonical_contract.py`, `test_action_item_date_validation.py`, `test_action_item_dedup.py`, `test_action_item_idempotency.py`, `test_action_item_ids_endpoint.py`, `test_action_item_reminder_cancel_on_complete.py`, `test_action_item_tool_result_bound.py`, `test_action_item_vector_best_effort.py`, `test_action_items_conversation_list_malformed.py`, `test_action_items_date_coercion.py`, `test_action_items_date_range_validation.py`, `test_action_items_due_range_index_contract.py`, `test_action_items_pagination_order.py`, `test_action_items_router_pagination.py`, `test_action_items_timezone.py`, `test_activate_task_intelligence_dogfood_user.py`, `test_backend_candidate_capture.py`, `test_candidate_lifecycle.py`, `test_candidates_router.py`, `test_candidates_skip_malformed.py`, `test_conversation_action_items_count.py`, `test_get_candidate_skip_malformed.py`, `test_goal_context_null_message_text.py`, `test_goal_extraction_batch.py`, `test_goal_get_by_id.py`, `test_goal_progress_events_skip_malformed.py`, `test_goal_source_compatibility.py`, `test_goal_storage_coerce_guard.py`, `test_goals_id_fallback.py`, `test_goals_response_int_guard.py`, `test_goals_sort_missing_created_at.py`, `test_smoke_what_matters_now.py`, `test_staged_candidate_migration.py`, `test_staged_tasks_batch_scores.py`, `test_staged_tasks_dedup.py`, `test_staged_tasks_relevance_zero.py`, `test_staged_tasks_review_controls.py`, `test_task_intelligence_attribution.py`, `test_task_intelligence_contract_freeze.py`, `test_task_intelligence_known_gaps.py`, `test_task_intelligence_rollout.py`, `test_task_recommendations.py`, `test_what_matters_now_smoke_fixture.py`, `test_workstream_association.py`, `test_workstream_core.py`, `test_workstream_events_skip_malformed.py`, `test_workstream_list_skip_malformed.py`, and `test_workstream_router_contract.py`.

Mixed tests to narrow rather than blindly delete include `test_tools_router.py`, `test_desktop_migration.py`, `test_bounded_firestore_list_reads.py`, `test_firestore_query_contract.py`, `test_delete_account_purge_storage.py`, `tests/services/users/test_account_deletion.py`, `test_data_export.py`, `testing/e2e/test_boundary_contract_compatibility.py`, `testing/e2e/test_retrieval_search.py`, `testing/e2e/test_account_deletion_cloud_tasks.py`, and desktop REST/OpenAPI inventories.

### Contracts, generated code, jobs, config, and docs inventory

- `desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift` contains all current task/goal/score operations and models; regenerate after OpenAPI deletion.
- `backend/route_policy_manifest.yaml` contains candidate, goal, What Matters, workstream entries; `backend/route_policy_legacy_missing_routes.txt` contains old action-item/goal/staged/score operations; remove retiring operations from both, never allowlist their absence as “legacy missing.”
- `backend/scripts/export_openapi.py` currently advertises candidates, goals, workstreams, What Matters and action-item product access; narrow app prefixes/tags/description.
- `firestore.indexes.json` contains the three `action_items`, two `candidates`, and `task_attention_overrides` composite indexes; regenerate/check after repository deletion.
- Task-intelligence config/ops are `backend/config/task_intelligence_contract_v1.json`, `task_intelligence_sources_v1.json`, `backend/deploy/dev_candidate_acceptance.json`, `backend/docs/task_intelligence_baseline.md`, `backend/scripts/task_recommendation_live_eval.py`, `task_intelligence_fixture_runner.py`, `activate_task_intelligence_dogfood_user.py`, `run_dev_candidate_acceptance.py`, and `rebuild_workstream_association_index.py`.
- `.github/workflows/task-recommendation-live-eval.yml` is the task-recommendation job to delete. Uses of the word “candidate” in desktop release qualification, Cloud Run release candidates, transcription probes, and `/v2/desktop/beta/candidates/reserve` are unrelated and must remain.
- Current task fixtures include `backend/testing/e2e/fixtures/action_items.json`, `backend/tests/unit/fixtures/task_intelligence/{association_v1,canonical_round_trip_v1,capture_v2,ranking_v2}.json`, and task-intelligence cases in `backend/config/task_intelligence_contract_v1.json`.
- `backend/routers/desktop_deprecated.py` currently has 410 registry entries for task/goal/score/staged operations. Delete those entries so the removed routes fail by absence/404, not by a compatibility shell.
- Current docs/comments/schema descriptions in `backend/docs/db_pydantic_boundary.md`, `backend/docs/llm/model_endpoint_inventory.yaml`, `ChatPrompts.swift`, task E2E descriptions, `ViewExporter.swift`, component `AGENTS.md` files, and `PRODUCT.md` must be updated only where they make a live claim about the retired authority/product. Historical `CHANGELOG.json` entries stay historical.

## 8. Behavior classification

| Category | Complete S-13 classification |
|---|---|
| **KEEP AS IS** | Per-owner `RewindDatabase` pool/generation boundary; grouped To Do/Done concept; due-date `TaskCategory` grouping; ordinary main Chat and general agent runtime; realtime owner/run/allowlist/replay fences; Gemini provider/tool-loop behavior; Rewind privacy/exclusions; explicit task added/completed/deleted/extracted analytics if still owned by S-09; generic notification permission/delegate behavior; generic account deletion recursion; unrelated conversation/memory/tool APIs; unrelated release-candidate workflows; historical migration/changelog records. “As is” permits only call-site typing needed to consume the local authority, not behavior change. |
| **ADAPT** | `ActionItemRecord`, `ActionItemStorage`, `TasksStore`, Tasks/Dashboard/Home/About/Notch projections, inline editor, completion/recurrence, delete/Undo, order/keyboard/pagination, details/Why/New, Task Assistant/settings/Test Run, typed Chat and realtime task tools, `UserNotificationCallbackBridge`/notification seam, `GoalRecord`/`GoalStorage`/surviving goal UI/onboarding/Chat goal context, automation flows, S-10 source-session link/cascade/detail lookup, S-08 local export reader, generated local tool schemas. |
| **DELETE** | Cloud task IDs/sync/reconcile/retry/rollback/full sync; Firestore action items and task vectors; task API/tool routes; candidates/staged/Suggested/What Matters/control/recommendations/outboxes/feedback/outcomes; Board/advanced filters/full create/bulk clear/tags/category/source class/generic metadata/analytics task type/share residue/multiselect/indent; task ranking/relevance; dormant recurrence-agent scheduler; task chat/Execute/agents/workstreams; both cloud goal systems/sync/numeric progress/AI goals/task links; productivity-score routes/models/UI/export; task-specific FCM; exclusive indexes/jobs/workflows/scripts/config/tests/fixtures/generated code/docs; 410 compatibility entries. |
| **SIMPLIFY AFTER** | Once every caller uses local IDs, remove `ActionItemTaskIdentity`'s backend arm and any conversion overloads; collapse `TasksStore` server state into one local observation/loading state; remove server-shaped `TaskActionItem` Codable compatibility in favor of one local projection; compact ActionItemStorage methods after candidate/rank/agent deletion; reduce `EmbeddingService` after staged callers disappear; reduce Goal model/UI after API/numeric callers disappear; remove now-empty client extensions/files, router modules, settings models, generated groups, imports, metrics, and test support. Simplification occurs only after the enabling GREEN named in C15–C17. |
| **OUT OF SCOPE / DEFERRED** | S-10 conversation/transcript implementation; S-14 Focus/Insight/advice/AI Profile behavior and IR-029/030 persistence/UI; S-19 overall PTT activation/provider/transport/journal/vision lifecycle and non-task rejected tools; S-21 broad Home/navigation/settings shell redesign; S-22 model portfolio/transient compute; S-23 remaining backend products and generic FCM teardown; S-24 remaining cloud vector/object search; S-25 shared Cloud Tasks/deploy retargeting; S-27 live queue/IAM/region operations; S-28 final storage namespace cleanup; S-08 final export composition/acceptance; live Firestore/index/job/resource deletion. |

## 9. Retained behavioral invariants

These are acceptance contracts, not suggestions.

### Authority and ownership

- A task mutation is accepted only after the owner-scoped GRDB transaction commits. UI success, tool success, automation success, and speech never precede that commit.
- A surfaced task ID is stable across reload/restart and resolves only inside its owner database. A stale owner lease, switched pool generation, or another owner's surfaced ID fails closed without mutation.
- No retained task/goal behavior requires a backend response. Network refusal may affect unrelated hosted model/auth services but not already-authorized local CRUD, order, recurrence, reminders, or goal lifecycle.
- S-10 source-linked tasks retain the exact stable relationship after user edits. Source-session deletion permanently deletes all still-linked tasks in the same transaction and leaves unrelated rows untouched. Task details never reveal the raw relationship ID.
- Fresh install and upgraded database end with the same retained columns/tables/indexes/triggers. Row IDs, retained data, and valid S-10 links survive the forward migration.

### Tasks list, editing, lifecycle, and order

- One list, To Do/Done switch, first header exactly **Today & Overdue**, and existing due ordering/styling.
- Search is local case-insensitive description search over non-deleted To Do and Done together; active search ignores the status switch and makes drag/drop unavailable.
- Inline creation keeps +/Command-N/Return/Escape, selected-row New below placement, no date preview, and exact Today/Tomorrow/Later/No Deadline mappings.
- Edit keeps one-second debounce, Return/click-away/Escape Save & exit, trim, prior-value restore for empty/unchanged text, and the manual marker.
- Priority is exactly High/Medium/Low once set; there is no visible clear action. A deadline can be removed only from that task's popover and cancels its reminder.
- Completion/reopen uses the same row, preserves retained metadata/order, moves immediately after the local transaction, and reconciles reminders.
- Recurrence offers Daily, Weekdays, Weekly, Every 2 Weeks, Monthly, Never; completion and exactly one future row are atomic; missed occurrences do not backfill.
- Undo is five seconds, newest first, maximum ten, with visible count and timer reset. It restores the same local row. Timeout purges pending rows; app/owner exit makes them nonrecoverable; startup removes stranded user tombstones.
- Drag is available only in ordinary grouped To Do, applies exact due mappings across sections, locally persists numeric `sortOrder` before visual acceptance, coalesces rapid writes, and retains fallback order for never-manually-ordered rows.
- Keyboard keeps the exact 0.4-second captured-ID Return behavior and cancellation contexts; Tab/Shift-Tab and indent hints are absent.
- To Do and Done each begin at 100 local rows with independent offsets and deterministic extra-row/count `hasMore`; loading/empty/completed-empty/search-empty/retry/refresh/Load More remain truthful local states.

### Details, provenance, and Task Assistant

- Details retain hover/pointer transfer/full sheet/scroll/close and only explicitly retained fields. There is no raw metadata, raw source-session ID, goal ID, tags/category/source class, AI analysis compatibility, or task-agent state.
- **Why Omi added this** appears only for non-manual tasks with provenance and remains read-only/plain-language with linked-source count and accessibility ID. **New** is computed from local `createdAt < 60 seconds` without a timer or persisted read state.
- Task Assistant stays default-on and independent of shared Rewind/screen-analysis switches. Turning it off prevents new analysis and invalidates in-flight work before either observation or task mutation.
- Only explicit or clearly user-owned high-confidence captures reach `action_items`; the fixed 80% safety floor cannot be weakened by the visible 30–90% setting. Ambiguous/update/complete/refinement detections do not create a queue and leave no candidate/staged row.
- Direct admission is owner-scoped, idempotent, deduplicated against ordinary local tasks, and preserves allowed source/app/window/context/activity/confidence/capture-policy/evidence facts.
- Interval, confidence, prompt, Allowed Apps, and Browser Keywords retain the exact IR-652–657 behavior. Test Run may perform expensive real Gemini analysis but creates zero observations, tasks, candidates, or settings mutations.

### Tools, reminders, and goals

- `get_tasks` retains overdue/today scope; `get_action_items` covers broader local queries. Create/update/delete use local IDs and preserve every existing owner/run/attempt/allowlist/input-hash/replay/local-mutation fence.
- Voice creation with no due date uses `Date() + 24 hours`; explicit validated dates survive. Success is spoken; no immediate Task Added notification is emitted.
- Reminder request identifiers derive from the surfaced local task ID and owner namespace. Replace/cancel/reconcile operations are idempotent; notification denial/failure is reported/telemetried through existing sanitized mechanisms but never rolls back task data.
- A simple goal has only stable local ID, title, optional description, active/completed status, and timestamps. Manual create/edit/complete, restart durability, owner isolation, surviving Dashboard/onboarding UI, and active-goal Chat context work offline.
- Ordinary main Chat remains functional after task-attached Chat/Execute/workstreams are gone.

## 10. Target authority and ownership model

### Task data model and public boundary

`ActionItemRecord.id: Int64` becomes the only durable task identity. The existing `local_<rowid>` surfaced representation is the only string form crossing UI/tool/automation boundaries; it is not a second stored identity. `backendId`, `backendSynced`, canonical cloud IDs, and backend/local branching are removed. After all callers compile on the local form, simplify/delete the backend arm of the current `ActionItemTaskIdentity` rather than preserving an alias.

The retained `action_items` schema is limited to:

- `id`, `description`, `completed`, `deleted`, a local user-deletion tombstone marker/time needed by five-second Undo, `createdAt`, `updatedAt`, `completedAt`;
- `dueAt`, `priority`, `recurrenceRule`, a local recurrence-series/parent identity sufficient to prove one-next-occurrence, and `sortOrder`;
- the S-10 stable source-session foreign key plus `source`, `screenshotId`, `confidence`, `sourceApp`, `windowTitle`, `contextSummary`, `currentActivity`, and a typed/minimal provenance representation required by IR-031/644;
- FTS/index data only when used by retained local description search; embeddings only if a retained non-staged caller is demonstrated.

Rejected columns include backend sync/IDs, tags, semantic category, source category/subcategory, generic metadata, inferred-deadline raw string, goal/workstream/canonical-task fields, due confidence if exclusive to removed candidate workflow, supersession state, indent, relevance/scored timestamps, task-agent/chat fields, and `fromStaged`. Do not keep a JSON “miscellaneous” escape hatch for deleted fields.

`ActionItemStorage` owns all task transactions and queries. `TasksStore` observes/loads projections and presents errors/loading; it does not own an independent durable cache or network truth. UI/Chat/realtime/Assistant/automation call the same storage behavior. Direct SQL in Chat is narrowed so retained task writes cannot bypass typed validation, owner fencing, recurrence, reminders, provenance, and observation invalidation.

### Reminder boundary

Extend the current `UserNotificationCallbackBridge`/notification service boundary, rather than calling `UNUserNotificationCenter.current()` from every caller. The production seam must support schedule/add, list pending, and remove by exact identifier; tests inject a controllable boundary. The authoritative task transaction completes first, then reminder reconciliation runs idempotently. If scheduling fails, the task remains correct and the UI/tool reports a reminder-specific failure without pretending the task failed.

### Goal model

`GoalRecord.id: Int64` is the only durable goal ID, surfaced using the same explicit local-ID convention. The retained columns are `id`, `title`, optional `goalDescription`, `isActive` (or an equally typed active/completed state), `completedAt`, `createdAt`, and `updatedAt`. Remove `backendId`, `backendSynced`, `goalType`, numeric bounds/current/target, unit, cloud deletion/reconcile state, and conversion through API `Goal` JSON. `GoalStorage` owns local create/read/edit/complete and active-goal reads. Dashboard/onboarding/Chat consume that projection.

### Mutation sequencing

For create/update/complete/reopen/delete/reorder/recurrence:

1. capture the current owner lease and validate surfaced local ID/input;
2. execute one GRDB transaction for all authoritative row changes (completion plus recurrence child, order plus due-date move, conversation cascade, or Undo state as applicable);
3. revalidate the owner/generation before publishing the projection;
4. reconcile the one affected reminder or owner reminder set;
5. publish `TasksStore`/Dashboard/Chat/automation observation and return success.

There is no network stage and therefore no remote rollback. Reminder failure is a separate partial effect with explicit evidence, never a second authority.

## 11. Ordered RED/GREEN TDD cycles

The entry/rebase gate is not counted as a TDD cycle. C1–C17 are sequential vertical cycles. Each RED must be observed failing for the intended behavioral reason before GREEN. Test through production seams and temporary GRDB/notification/tool boundaries; source-string checks are labelled static tripwires and never substitute for behavior.

### Entry gate — rebase, ledger, inventory, and predecessor contract (not a TDD cycle)

- **Action:** satisfy G0–G6; record S-10/S-06 commits; rerun the inventory/residue commands in section 13; compare route/OpenAPI/tool manifests; run current focused task/goal tests to establish a baseline.
- **Expected files:** this plan/evidence only until the gate passes; no production edits.
- **Verification:** baseline/ledger commands in sections 2 and 14.
- **Deletion unlocked:** none.
- **Stop:** S-10 absent or its local ID/cascade/detail contract differs; ledger conflict; unowned dirty overlap; baseline tests fail in the intended change area without a recorded pre-existing explanation.

### C1 — protect the retained local list and owner boundary

- **RED:** add production-seam tests that seed two owner databases and require only the active owner's non-deleted rows; exact **Today & Overdue** heading/order; To Do/Done grouping; local `createdAt < 60s` New semantics; wrong-owner/stale-generation read rejection. Characterize retained Dashboard/Home counts without making network calls.
- **Why RED now:** heading is **Today**, `TasksStore`/Dashboard refresh can consult the server, and the local/server ownership boundary is not the sole truth.
- **GREEN:** make the smallest list/projection changes necessary to derive these reads from owner-scoped `ActionItemStorage`; change only the heading; keep server deletion for later C15.
- **Files/tests:** `TasksPage.swift`, `TasksStore.swift`, `ActionItemStorage.swift`, Dashboard/Home consumers; rewrite/add focused cases adjacent to `TasksStoreOwnerBoundaryTests.swift`, `TasksStoreObserverTests.swift`, `NotchMomentsFollowUpCountTests.swift`.
- **Retained behavior:** grouping, styling, current ordering, New badge, Dashboard/Home adjacent projections.
- **Verify:** `./scripts/dev-feedback.py --once swift 'TasksStoreOwnerBoundaryTests|TasksStoreObserverTests|NotchMomentsFollowUpCountTests'` from `desktop/macos`.
- **Deletion unlocked:** none; this is the keep fence.
- **Stop:** active owner cannot be injected/isolated or S-10 changes the database owner seam.

### C2 — stable local identity and authoritative basic CRUD

- **RED:** offline tests require create/read/rename/due/priority/delete lookup by one surfaced `local_<rowid>` across storage reconstruction; another owner cannot resolve it; invalid IDs fail; no API transport is invoked; bounded Chat context uses priority/due/order/recency without relevance fields.
- **Why RED now:** `TaskActionItem` and mutations branch on backend IDs, cloud sync flags, and relevance state.
- **GREEN:** make the GRDB row ID the sole identity for the tested operations; centralize basic transactions in `ActionItemStorage`; migrate the first UI/store caller; stop assigning relevance; do not yet remove all remote code.
- **Files/tests:** `ActionItemModels.swift`, `ActionItemStorage.swift`, `TaskActionItem.swift`, `TasksStore.swift`, `ChatPrompts.swift`; replace `ActionItemLocalIdentityMutationTests.swift` with sole-identity assertions and add deterministic-context cases.
- **Retained behavior:** task content, priority/due facts, stable observation, FTS repair.
- **Verify:** focused identity, owner, FTS, and Chat prompt tests.
- **Deletion unlocked:** backend-ID branches for migrated CRUD; relevance assignment in the migrated path.
- **Stop:** a retained caller requires a backend ID for behavior not assigned to deletion, or S-10 source IDs are not ready.

### C3 — inline creation, edit, deadline, and priority

- **RED:** UI/view-model tests cover +/Command-N/Return/Escape, selected-row New below, the four exact due mappings, no preview, one-second debounce, all save exits, trim/restore/manual marker, individual **Remove deadline**, and High/Medium/Low with no clear action. Every accepted edit must be visible after reload with a failing API transport.
- **Why RED now:** local/staged/backend ID branches can skip durable updates; edits/order still include remote rollback; Remove deadline is absent.
- **GREEN:** route inline create and row edits through local transactions; add Remove deadline; preserve the exact keyboard/UI semantics; leave reminder scheduling as the failing boundary for C4.
- **Files/tests:** `TasksPage.swift`, `TasksStore.swift`, `ActionItemStorage.swift`; focused view-model/editor/due/priority tests and `tasks.yaml` expectations.
- **Retained behavior:** IR-621–623, 627, 628.
- **Verify:** focused Tasks view-model test filter plus debug compile.
- **Deletion unlocked:** `TaskCreateSheet`, `showingCreateTask`, modal-only state/helpers/tests, cloud rollback from edit/create.
- **Stop:** a due mapping differs from the ledger or UI tests cannot drive the production save path.

### C4 — local reminder lifecycle

- **RED:** inject the existing notification boundary and require exact surfaced-ID request keys; create/due update replaces one request; deadline removal/completion/delete cancels; launch and owner switch remove stale requests and recreate only authoritative future-due requests; overdue startup causes no immediate catch-up banner; denied/schedule failure leaves the task committed and produces a reminder-specific result.
- **Why RED now:** no keyed local task reminder owner exists; backend FCM owns task messages; `UserNotificationCallbackBridge` cannot query/remove pending requests.
- **GREEN:** extend the current bridge/service with the minimal pending-query/remove functionality and call it from one storage-orchestration point after GRDB commits.
- **Files/tests:** `ProactiveAssistantsPlugin+NotificationSettings.swift`, `NotificationService.swift`, `ActionItemStorage.swift`/`TasksStore.swift`; new focused reminder lifecycle tests using a controllable notification seam.
- **Retained behavior:** due delivery, notification permission behavior, unrelated notification categories/delegate callbacks.
- **Verify:** reminder test filter and existing notification regression tests.
- **Deletion unlocked:** Mac/server task reminder coordination for migrated callers; not backend helpers until C16.
- **Stop:** notification identifier is not owner-namespaced, reconciliation can touch another owner, or task failure is coupled to notification failure.

### C5 — atomic completion, reopening, and recurrence

- **RED:** production storage tests require same-row complete/reopen with retained fields/order; reminder cancel/recreate; each recurrence option; exactly one next future row; no missed backlog; current row remains Done; completion plus child insert rolls back together on injected database failure.
- **Why RED now:** completion and recurrence are store follow-ons and server-coupled, and dormant agent scheduler behavior is adjacent.
- **GREEN:** implement one owner-scoped GRDB transaction for completion/next occurrence; copy only retained fields; run post-commit reminder reconciliation; remove automatic agent scheduler wiring.
- **Files/tests:** `ActionItemStorage.swift`, `TasksStore.swift`, `TasksPage.swift`, `RecurringTaskScheduler.swift`, `ViewModelContainer.swift`, `OmiApp.swift`; replace `RecurringTaskSchedulerGateTests.swift` with recurrence transaction coverage and extend `TasksViewModelCompletedToggleTests.swift`.
- **Retained behavior:** checkbox/Space/animation/history/reopen and IR-625 recurrence.
- **Verify:** focused completion/recurrence/reminder tests.
- **Deletion unlocked:** `RecurringTaskScheduler`, due-agent query exclusive to it, configure/start/stop/tests; backend completion/create/echo coupling for this path.
- **Stop:** transaction cannot preserve S-10 linkage or recurrence identity without a rejected cloud field; redesign the local minimal recurrence field before proceeding.

### C6 — five-second deletion and Undo durability boundary

- **RED:** fake-clock/storage tests require soft-delete acceptance before row removal; no UI success on DB failure; max-ten newest-first stack/count/timer reset; same-row field/order restoration; timeout hard purge of all pending; launch purge of stranded user tombstones; owner switch/app shutdown makes pending items nonrecoverable; reminders cancel/restore; conversation cascade bypasses Undo and remains permanent.
- **Why RED now:** Undo is memory-only and permanent purge belongs to removed full-cloud sync.
- **GREEN:** make the tombstone/Undo lifecycle owner-scoped and locally purged, with deterministic clock/shutdown seams and post-commit reminders.
- **Files/tests:** `ActionItemModels.swift`, `ActionItemStorage.swift`, `TasksStore.swift`, `TasksPage.swift`, owner lifecycle integration; new Undo lifecycle behavioral tests.
- **Retained behavior:** exact IR-638 UI and S-10 permanent cascade distinction.
- **Verify:** focused Undo/owner/reminder tests.
- **Deletion unlocked:** backend DELETE/recreate, backend-ID branches, full-sync purge owner, synchronization-only deletion tests.
- **Stop:** an owner switch can expose/restore prior-owner pending entries, or app termination leaves an intended Undo recoverable.

### C7 — local drag/order and page-scoped keyboard behavior

- **RED:** view-model/storage tests cover same-section reorder without deadline change, all cross-section mappings including nil, transaction-before-visual acceptance, reminder effects, rapid reorder coalescing, persisted order after restart, no UserDefaults/backend flush, fallback order, disabled drag in search/Done; exact captured-ID 0.4-second keyboard behavior and cancellation contexts; flat left-swipe delete and no indent keys/hints.
- **Why RED now:** order writes local plus backend/UserDefaults; indentation and hidden requery test state remain; delayed Return can be sensitive to selection changes.
- **GREEN:** persist `sortOrder`/cross-section `dueAt` in local transactions, coalesce local writes, remove indentation and legacy order state, and preserve/correct keyboard cancellation through production handlers.
- **Files/tests:** `TasksPage.swift`, `ActionItemStorage.swift`, `TasksStore.swift`, automation registration; rewrite `Task03ReorderStressTests.swift`, `TasksSortOrderBandingTests.swift`, keyboard tests; delete sync/requery/indent-only tests.
- **Retained behavior:** IR-641/642 and IR-638 left swipe.
- **Verify:** focused reorder/keyboard/automation tests.
- **Deletion unlocked:** `indentLevel`, `TasksIndentLevels`, indent UI/keys/contracts; backend sort APIs/flush/retry; UserDefaults order fallback; `inject_requery_during_drag`.
- **Stop:** order acceptance occurs before storage commit or a partial search set can mutate full-list order.

### C8 — local search, pagination, and truthful list states

- **RED:** seed >200 To Do and >200 Done tasks and require independent 100-row pages, exact-100 no false `hasMore`, extra-row/count boundary, near-bottom and explicit load, refresh/retry, initial/empty/completed-empty/search-empty states, and global bounded search across statuses. Refuse all network requests.
- **Why RED now:** server API pages, merge, and reconciliation determine current loading/`hasMore`; filtered branches remain.
- **GREEN:** implement all list/search/count/page calculations in `ActionItemStorage` and make `TasksStore`/`TasksViewModel` expose those results only.
- **Files/tests:** `ActionItemStorage.swift`, `TasksStore.swift`, `TasksPage.swift`; rewrite `TasksStoreApiPageLimitTests.swift`/`TasksViewModelLoadMoreTappedTests.swift` as local boundary tests; keep FTS repair tests.
- **Retained behavior:** IR-619, IR-620 switch, IR-648 states.
- **Verify:** focused page/search/load tests.
- **Deletion unlocked:** server pagination/merge/census/confirmed-empty logic and advanced filter query/count state after C9 UI removal.
- **Stop:** FTS/search changes semantic scope beyond case-insensitive description matching or exact-100 remains ambiguous.

### C9 — prune rejected Tasks UI and data fields

- **RED:** presentation and schema tests assert the retained list/editor/details/Why/New surface and absence of Board, bulk clean, advanced filters, full create sheet, tags/category/source class, raw/generic metadata, omi-analytics Analysis, inferred-deadline raw value, Conversation/Goal rows, multiselect/bulk, indent, ranking/Re-score, Suggested coupling, and task-agent controls. Static tripwires may assert deleted symbols are absent only after behavioral tests prove retained shells.
- **Why RED now:** all rejected symbols/fields are present except S-06 sharing; detail catch-alls can resurrect deleted metadata.
- **GREEN:** delete the named UI/state/model plumbing; move the Why component into ordinary Tasks ownership; explicitly render only retained details; keep provenance/source facts typed; update prompt/schema projections without yet deleting remote producers.
- **Files/tests:** `TasksPage.swift`, `TaskDetailViews.swift`, `TaskActionItem.swift`, `ActionItemModels.swift`, settings and automation UI; rewrite/delete the inventory's exclusive presentation tests and `tasks.yaml`.
- **Retained behavior:** list, inline editing, details shell, Why, New, settings gear, recurrence/reminders/order/keyboard.
- **Verify:** focused presentation/detail/source tests, desktop test-quality checker, debug compile.
- **Deletion unlocked:** all rejected UI/types/helpers and corresponding fields from new writes; physical schema removal waits C15 migration.
- **Stop:** a remaining explicit retained field depends on generic metadata JSON; type it before deleting the catch-all.

### C10 — Task Assistant direct local admission and no review queue

- **RED:** production Assistant tests feed explicit/high-confidence, ambiguous, duplicate, replayed, wrong-owner, and disabled-mid-flight model results. Require exactly one ordinary local task for accepted input, zero task/candidate/staged/observation mutation for rejected disabled work, ambiguous discard, typed provenance, transient inferred deadline conversion, deterministic local context, and no candidate/outbox/API call.
- **Why RED now:** `TaskAssistant` writes staged/candidate state, `ScreenCandidateAdapter` calls cloud control, and promotion/ranking finish admission.
- **GREEN:** make policy-approved results insert idempotently through `ActionItemStorage`; retain local dedupe and typed provenance; delete candidate/staged/promotion/rank branches and invalidate in-flight work on disable/owner change before observation/task commit.
- **Files/tests:** `TaskAssistant.swift`, `TaskModels.swift`, `TaskDeduplicationService.swift`, `TaskAssistantSettings.swift`, `EmbeddingService.swift`, plugin startup, Suggested/staged/candidate/rank services; rewrite Assistant/dedupe/source tests and delete candidate fixture tests.
- **Retained behavior:** Gemini extraction triggers/context, safety/confidence, source evidence, dedupe, automatic ordinary task creation.
- **Verify:** focused Task Assistant tests with injected Gemini/model results and API refusal.
- **Deletion unlocked:** `ScreenCandidateAdapter`, `StagedTaskStorage`, `SuggestedTasksStore/Section`, `TaskPromotionService`, `TaskPrioritizationService`, candidate/staged local tables/FTS/index branch, task-intelligence analytics/outboxes.
- **Stop:** accepted work cannot atomically enforce owner/idempotency/dedupe, or Test Run shares a mutation-enabled code path without an explicit no-commit mode.

### C11 — retained Task Assistant controls and Test Run

- **RED:** settings/UI tests cover default-on local switch and cancellation, interval choices/default/fallback/event timing/no-rearm, confidence range/default/80% floor, prompt window exact controls/local persistence/code override, Test Run range/100k/filter/sequential-real-call/stop/errors/zero-mutation, Allowed Apps, Browser Keywords, and Tasks gear navigation. Assert no task settings network hydration/push and no Re-score.
- **Why RED now:** `SettingsSyncManager` owns cloud hydration/push, Re-score is visible, and rejected prompt/schema branches remain.
- **GREEN:** keep the selected controls locally, remove task settings from `SettingsSyncManager` request/response handling, delete Re-score, and separate Test Run observation from production mutation while retaining the same analysis/filter behavior.
- **Files/tests:** `TaskAssistantSettings.swift`, `SettingsContentView+Assistants.swift`, `SettingsPage.swift`, `SettingsSyncManager.swift`, `TaskPromptEditorWindow.swift`, `TaskTestRunnerWindow.swift`, `DesktopAutomationManagedAccessActions.swift`; focused settings/prompt/Test Run tests.
- **Retained behavior:** every exact IR-649–657 UI/persistence quirk.
- **Verify:** focused settings/Assistant tests and automation settings tests.
- **Deletion unlocked:** task cloud settings fields/models/tests and prioritization settings residue.
- **Stop:** implementation proposes a Test Run cap/warning/sampling change, bundle-ID redesign, or prompt cloud fallback; those contradict the ledger.

### C12 — typed Chat and realtime/PTT local task tools

- **RED:** tool-relay and Swift integration tests require local `get_tasks`, broad `get_action_items`, create with +24h default, explicit date preservation, rename/reschedule/complete/pending/delete, reminder effects, immediate local observation, owner/run/attempt/allowlist/input-hash/replay/idempotency fences, ambiguous model-selected ID failure, spoken result, and no immediate Task Added banner/API/server refresh. Offline transport must fail if invoked.
- **Why RED now:** `ChatToolExecutor` task cases call `APIClient+Tools` and refresh server state; broader reads are backend; task reminder messaging is server-owned.
- **GREEN:** route retained task tools to typed `ActionItemStorage` operations using surfaced local IDs and existing authorization fences; update manifest/descriptions/generated executors; keep `get_tasks` scope and main Chat.
- **Files/tests:** `ChatToolExecutor.swift`, `ChatProvider.swift`, `APIClient+Tools.swift`, realtime delegate/session, manifest/policy/generated tool files, tool fixtures/tests, TasksStore observation, notifications.
- **Retained behavior:** natural model intent and all PTT authorization/lifecycle boundaries.
- **Verify:** `bash desktop/macos/scripts/test-tool-surfaces.sh`; focused owner/auth/tool/reminder tests; `./scripts/agent-logic-harness.sh --cross-surface-smoke` if agent runtime files changed.
- **Deletion unlocked:** desktop task API tool methods, server-refresh post effects, backend-ID resolution, task-tool HTTP operations after C16.
- **Stop:** a tool bypasses typed storage through unrestricted SQL, weakens an auth/replay fence, or S-19 has concurrently changed the dispatch seam without rebase.

### C13 — one simple local Goals product

- **RED:** temporary-database/UI/automation tests require offline create/edit/complete, stable local ID across restart, owner isolation, active-goal Chat read, Dashboard render, onboarding local create, and no numeric/progress/API call. Completion preserves row/history state needed by the simple UI without cloud lifecycle.
- **Why RED now:** `GoalStorage` mirrors API `Goal`, mutations use backend IDs, Dashboard/API and two goal systems own state, onboarding/AI services create numeric cloud goals.
- **GREEN:** reduce `GoalRecord` and `GoalStorage` to local CRUD/lifecycle; migrate surviving Dashboard/onboarding/Chat consumers; rewrite `goals_snapshot`/`create_test_goal` to the simple local shape; remove AI/numeric/canonical paths from migrated UI.
- **Files/tests:** `GoalRecord.swift`, `GoalStorage.swift`, `DashboardPage.swift`, `GoalsWidget.swift`, `GoalsHistoryPage.swift`, `GoalCelebrationView.swift`, onboarding, Chat prompts/consumers, automation; rewrite `GoalProgressTests.swift` and `goals-dashboard.yaml`.
- **Retained behavior:** one local goal capability, optional description, active/completed, active Chat context.
- **Verify:** focused goal/owner/onboarding/automation tests with API refusal.
- **Deletion unlocked:** API Goal conversion/sync/numeric fields, AI goal services, canonical Dashboard goal UI/store, task-goal links on desktop; backend waits C17.
- **Stop:** S-14 requires a field beyond title/description/active/completed; S-14 must adapt rather than expanding S-13's goal model.

### C14 — remove task-attached agent, Execute, and workstream behavior

- **RED:** UI/runtime tests require no task chat panel/open control/Execute/background-investigation/workstream settings/status/artifact/checkpoint/session surface while main Chat can read and mutate a selected/local task. Ensure general `AgentRuntimeStatusStore` remains for non-task surfaces.
- **Why RED now:** task rows, coordinator, runtime, status registry, local task-chat storage, continuity, and scenario script are live.
- **GREEN:** delete the complete task-specific runtime/UI/storage wiring and fields; remove only task surface cases from shared registries; keep main Chat and general Pi/runtime paths.
- **Files/tests:** all TaskAgent files listed in section 7, `TaskChatPanel.swift`, `TaskChatMessageStorage.swift`, `ProactiveTaskExecute.swift`, Tasks page/settings/plugin/container/runtime status cases, `scenario-13-task-thread-e2e.sh`; delete/narrow task-thread tests.
- **Retained behavior:** ordinary main Chat/local task tools and unrelated agent sessions.
- **Verify:** focused Chat discoverability/tool/runtime tests plus agent cross-surface smoke.
- **Deletion unlocked:** task agent/chat schema columns/tables and workstream desktop clients/models; backend workstreams waits C17.
- **Stop:** a shared runtime type has a retained non-task caller; narrow its task enum/case instead of deleting the file.

### C15 — converge local schema, automation, callers, restart/offline, and remove desktop cloud authority

- **RED:** fresh and upgraded database fixtures require identical retained schema; retained task/goal rows and IDs/source links survive migration; rejected columns/tables/indexes/triggers are gone; every UI/Chat/realtime/Assistant/automation caller works with API endpoints refusing; restart and owner switch preserve isolation/reminders/order/Undo rules. Automation results contain local IDs and no `synced`/remote waits; `inject_requery_during_drag` is absent. Local export reader returns task/goal data for the S-08 handoff.
- **Why RED now:** accumulated migrations create cloud/staged/agent/rank fields and callers/clients still exist even after behavioral migration.
- **GREEN:** add one forward table-rebuild/drop migration after S-10's migrations; rebuild retained FTS/indexes; delete desktop cloud clients, refresh services, sync settings/state, server conversions, rejected tables and local residues; update automation/E2E/export reader and docs. Do not rewrite historical migrations.
- **Files/tests:** `RewindDatabase.swift`, record/storage/store/client/generated/automation/E2E/export/Chat schema/component docs identified above; schema migration fixtures and restart/offline/owner tests.
- **Retained behavior:** all C1–C14 invariants and correct local schema evolution.
- **Verify:** focused schema/owner/offline tests, tool surfaces, OpenAPI check after clients move, named-bundle acceptance section 15.
- **Deletion unlocked:** C16/C17 backend teardown.
- **Stop:** any retained Mac production caller still sends a retiring HTTP operation, migration loses a retained field/row ID/S-10 link, or S-08 has no named local export handoff.

### C16 — delete backend action-item/tool/reminder/score authority

- **RED:** FastAPI/OpenAPI tests require 404/absence for every action-item route listed in section 6, task operations under `/v1/tools/action-items`, `/v1/daily-score`, and `/v1/scores`; retained conversation/memory tool operations and account deletion still pass. Import-isolation tests require no deleted module import. Generated Swift must have no removed operation/model.
- **Why RED now:** routers are mounted, Firestore/data export/vector/push/score code and 410 registry entries remain.
- **GREEN:** delete action-item router/database/model and task retrieval tools, task-specific notification helpers/callers, score router/model/calculations, cloud action-item export/vector dependencies, router mounts, deprecated entries, route policy, indexes, OpenAPI/generated client, score widgets/state/export, exclusive tests/fixtures/docs; narrow mixed modules/tests.
- **Files/tests:** backend and desktop IR-025/101/825 inventory in section 7; `firestore.indexes.json`; route/OpenAPI files; generated Swift.
- **Retained behavior:** generic notifications/FCM, generic recursive account deletion, conversation/memory tools/routes, local Mac tasks/completion data.
- **Verify:** focused removed-route/retained-route/import/account tests, OpenAPI generation check, Firestore index generation check, backend component suite.
- **Deletion unlocked:** action-item Firestore authority repository closure.
- **Stop:** S-10 still calls conversation action-item routes, another retained backend product imports `database.action_items`, or a score calculation has a proved retained non-score caller; migrate/narrow first.

### C17 — delete backend candidate, staged, task-intelligence, cloud goal, and workstream control planes

- **RED:** route/OpenAPI/import tests require 404/absence for all candidate/staged/What Matters/task-intelligence/goal/work-intent/workstream operations in section 6; no exclusive config/index/job/workflow/fixture/model is importable or generated; retained backend health/auth/chat/conversation/memory routes still smoke-test.
- **Why RED now:** all routers, Firestore modules, task-intelligence utilities, config, workflow, route policy, fixtures, and 410 entries remain.
- **GREEN:** delete the complete exclusive control planes and narrow mixed main/metrics/account/release/docs files. Remove `.github/workflows/task-recommendation-live-eval.yml` only; preserve every unrelated release/Cloud Run/transcription “candidate” path.
- **Files/tests:** exact candidate/staged/recommendation/goal/workstream inventory in section 7 plus `main.py`, route policy/OpenAPI/generated code, Firestore indexes, configs/scripts/docs/tests.
- **Retained behavior:** local Mac tasks/goals/Assistant, main Chat, S-14 consumers, unrelated backend/release candidate infrastructure.
- **Verify:** focused removed-route/retained-route/import/OpenAPI/index checks, backend suite, desktop suite, `make preflight`, residue strategy.
- **Deletion unlocked:** final simplify-after pass: remove empty imports/files/helpers and dual projections, format, run all closure checks.
- **Stop:** any retained Mac caller remains, any shared module has an unclassified consumer, or deletion would touch live infrastructure. Repository deletion can finish; live closeout remains separately gated.

## 12. Cross-slice ownership and handoffs

| Slice | S-13 owns | S-13 consumes/hands off | Must not absorb/delete |
|---|---|---|---|
| S-06 | Preserve completed task-sharing/connector absence | Consumes no-sharing/no-external-task-integration state | Do not recreate export/share/connector APIs; do not modify unrelated S-06 surfaces |
| S-08 | Add/prove local task and simple-goal export readers needed for final Export My Data | Hand exact reader contract/evidence back to S-08, which owns composition/UI/acceptance | Account auth/session/deletion queue/IAM/live worker ownership |
| S-10 | Task-side source-session foreign key, linked-task query in `ActionItemStorage`, and task participation in same-transaction cascade | Consume S-10 stable local session identity and transaction boundary | Conversation/session/detail/folder/transcript authority; no temporary backend-ID adapter |
| S-11 | Keep Home/Dashboard task/goal projections local and compile-safe | Hand local projection to Home/Chat | Broader Home/Chat session/journal/navigation redesign |
| S-14 | Provide local task and active-goal reads; remove cloud task/goal assumptions from shared consumers | S-14 adapts Focus/Insight/advice/AI Profile and owns IR-029/030 | Focus history/coaching persistence, notifications, model flow, profile lifecycle |
| S-19 | Migrate task-specific tool implementations to local authority while preserving current fences | Hand stable local task tool behavior/schema to S-19 | PTT activation/provider/transport/turn/journal/vision lifecycle and non-task tools |
| S-21 | Keep Tasks tab/settings shortcut and selected UI behavior | S-21 may later simplify shell/navigation | Do not redesign navigation/Home/settings globally |
| S-22 | Expose deterministic local task/goal context | S-22 consumes it for model portfolio/transient compute | Model-provider portfolio and compute-policy decisions |
| S-23 | S-13 deletes explicitly assigned task/goal/score routes and task-specific FCM helpers | S-23 verifies absence while removing remaining hosted product/generic FCM surfaces | Do not delete generic FCM or unrelated backend products here |
| S-24 | Remove action-item vector dependency only when exclusive | S-24 owns remaining cloud vector/object search | Conversation/memory/screen vector systems |
| S-25/S-27 | None beyond removing S-13-only job references | Hand shared worker/deploy/live resource residue to those owners | Cloud Tasks queues, IAM, region, deploy orchestration, live mutation |
| S-28 | Make new task/goal local storage use the current per-owner namespace | S-28 performs final namespace cleanup | Do not move the whole Application Support tree in S-13 |

Shared-file conflict list requiring rebase review before edit: `RewindDatabase.swift`, `ChatPrompts.swift`, `ChatToolExecutor.swift`, `ChatProvider.swift`, `DesktopAutomationBridge.swift`, `DashboardPage.swift`, `HomeStatusStore.swift`, `StartupWarmupCoordinator.swift`, `ProactiveAssistantsPlugin.swift`, `SettingsSyncManager.swift`, `AIUserProfileService.swift`, Focus Assistant files, `backend/main.py`, `backend/routers/conversations.py`, `backend/utils/conversations/process_conversation.py`, `backend/services/users/{data_export,account_deletion}.py`, `backend/database/users.py`, `backend/route_policy_manifest.yaml`, `firestore.indexes.json`, OpenAPI/generated files, component guides, and mixed tests.

## 13. Repository residue-search strategy

Run from the repository root after the S-10 rebase to refresh inventory, after each deletion cycle for its family, and once at closure. Save output in PR evidence. Every hit must be classified as retained production, another slice's owner, historical changelog/migration, generated output awaiting regeneration, or defect. `rg` exit 1 means no hits and is success for a residue search; do not hide unexpected command errors.

### Authority, APIs, and IDs

```bash
rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'backendId|backendSynced|ActionItemTaskIdentity|refreshDashboardTasksFromServer|reconcileWithAPIIfNeeded|retryUnsyncedItems|syncTaskActionItems|reconcileDashboardVisibilityFields|markAbsentTasksAsStaged|fullSync|syncScoresToBackend' \
  desktop/macos backend agent

rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  '/v1/action-items|/v1/tools/action-items|/v1/staged-tasks|/v1/candidates|/v1/what-matters-now|/v1/task-intelligence|/v1/goals|/v1/work-intents|/v1/workstreams|/v1/workflow-migrations/task-goal-links|/v1/daily-score|/v1/scores' \
  desktop/macos backend agent .github firestore.indexes.json
```

### Rejected desktop behavior and fields

```bash
rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'tasksViewIsBoard|tasksBoardView|TaskBoardCard|TaskFilterGroup|TaskFilterTag|DynamicFilterTag|TaskCreateSheet|clearTodayDeadlinesForIncompleteTasks|TagBadgeInteractive|isMultiSelectMode|selectedTaskIds|deleteMultipleTasks|indentLevel|TasksIndentLevels|inject_requery_during_drag' \
  desktop/macos

rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'tagsJson|source_category|source_subcategory|allMetadataEntries|remainingMetadata|Other Info|omi-analytics|original_message|creation_reason|key_findings|search_summary|relevant_files|inferred_deadline|relevanceScore|scoredAt|fromStaged|goalId|workstreamId|chatSessionId|agentStatus' \
  desktop/macos backend agent
```

For `goalId`, `agentStatus`, and generic words such as `category`, inspect only task-domain hits; unrelated goals, general agent runtime, due-date `TaskCategory`, memory categories, analytics, and historical migration text are not residue.

### Candidate, task-agent, workstream, score, and cloud-goal products

```bash
rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'SuggestedTasks|Checking Suggested|ScreenCandidateAdapter|StagedTask|TaskPromotionService|TaskPrioritizationService|task_intelligence|task-recommendation|WhatMattersNow|DashboardIntelligenceStore' \
  desktop/macos backend agent .github firestore.indexes.json

rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'TaskChatPanel|TaskAgent|TaskChatCoordinator|TaskChatRuntime|TaskThreadProjection|TaskWorkstreamContinuity|ProactiveTaskExecute|RecurringTaskScheduler|workstream|work-intent|workflow-migrations/task-goal-links' \
  desktop/macos backend agent .github

rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'DailyScore|ScoreResponse|ScoreData|getScores|daily-score|/v1/scores|GoalGenerationService|GoalsAIService|goal_type|target_value|current_value|min_value|max_value|backendSynced' \
  desktop/macos backend agent .github
```

Release qualification and Cloud Run/transcription uses of “candidate” are retained and must be explicitly classified, not deleted by broad replacement.

### Persistence, notifications, contracts, operations, and sharing absence

```bash
rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'collection\(.?(action_items|candidates|staged_tasks|goals|workstreams|task_|goal_)|collectionGroup.*(action_items|candidates|task_attention_overrides)' \
  backend firestore.indexes.json

rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'send_action_item|send_action_items|action_item_vectors|delete_action_item_vectors|task_attention_overrides|task_context_snapshots|task_open_loop_snapshots|candidate_pending_claims|candidate_resolution_claims' \
  backend firestore.indexes.json

rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'shareTasks|task_share|h\.omi\.me/tasks|shared_from|Share task|Task shared' \
  desktop/macos backend agent .github

rg -n --hidden \
  -g '!desktop/macos/Desktop/.build/**' -g '!**/node_modules/**' -g '!.git/**' \
  'task_intelligence_contract_v1|task_intelligence_sources_v1|task_recommendation_live_eval|dev_candidate_acceptance|run_dev_candidate_acceptance|activate_task_intelligence_dogfood_user|rebuild_workstream_association_index' \
  backend .github
```

Also use structural listings so a renamed symbol cannot evade literal searches:

```bash
rg --files desktop/macos backend agent .github | sort | rg '(task|action.item|candidate|staged|goal|workstream|score)'
rg -n '^@(router|app)\.(get|post|put|patch|delete)' backend/routers
rg -n 'include_router\(' backend/main.py
rg -n 'registerMigration\(' desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift
```

## 14. Focused and component-level verification commands

These are future implementation commands unless section 2 explicitly says they were run while planning. Replace `<SwiftTestFilter>` and `<backend test paths>` with the exact tests changed in each cycle; do not claim a pass without recording output.

### Planning and diff hygiene

```bash
git merge-base --is-ancestor 0d9934c HEAD
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
git status --short
```

### Focused macOS feedback

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift '<SwiftTestFilter>'
./scripts/swift-format-wrapper.sh format -i <changed-swift-files>
python3 scripts/check_desktop_test_quality.py
bash scripts/test-tool-surfaces.sh
./scripts/agent-logic-harness.sh --cross-surface-smoke
```

Run the agent harness only when the Chat/agent runtime surface changed; it complements, not replaces, focused Swift tests. Use the production storage/tool/notification seam with fakes only for OS/network/model boundaries and time.

### Focused backend and contract checks

```bash
cd backend
.venv/bin/python -m pytest -q <backend test paths>
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
cd ..
python3 backend/scripts/check_route_policy_baseline.py --base-ref origin/main
python3 backend/scripts/generate_firestore_indexes.py
```

If the index generator writes a file in check-less mode at execution time, run it only as the documented regeneration step, inspect the exact diff, and then rerun it to prove determinism. Do not mutate or deploy live indexes.

### Component and repository acceptance

```bash
bash desktop/macos/test.sh
(cd backend && bash test-preflight.sh && bash test.sh)
make preflight
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
```

Before a `fix:` commit/PR, run `scripts/pr-preflight --suggest`, declare/validate the failure class as required by `AGENTS.md`, draft the PR body, and run `scripts/pr-preflight --pr-body-file /tmp/pr-body.md`. These are delivery checks, not substitutes for exercising the user path.

## 15. Real named-bundle/user-path acceptance

Never start, stop, or test `/Applications/Omi.app`, `Omi Beta.app`, or their production bundle IDs. Use one unique `omi-*` development bundle and semantic automation first.

### Launch and restart recipe

```bash
cd desktop/macos
export OMI_APP_NAME=omi-s13-tasks
export OMI_AUTOMATION_PORT=47813
./run.sh --yolo
./scripts/omi-ctl wait-ready
./scripts/omi-ctl health
./scripts/omi-ctl navigate tasks
./scripts/omi-ctl actions
```

The current `run.sh` explicitly supports `--yolo` and `OMI_APP_NAME`; `omi-ctl` supports `wait-ready`, `health`, `navigate`, `actions`, and semantic `action`. Use `quit_and_reopen` from `desktop/macos/e2e/SKILL.md`/agent-swift for the restart proof, preserve the same automation port, and confirm a new listener PID and fresh log path before continuing. If semantic automation cannot reach a retained UI gesture, use agent-swift; do not switch among multiple click tools.

### Required real-path script

1. Create an inline task in Today & Overdue, edit with Escape Save & exit, assign High, set/remove/re-set a due time, and verify the reminder request via the test/automation seam.
2. Complete/reopen the same task; complete one recurring task and verify exactly one future row; restart and verify IDs, fields, order, and reminders.
3. Delete three tasks, verify newest-first/count/timer behavior, Undo one, let others expire, restart, and prove expired/stranded tombstones do not return.
4. Drag within a section and across every deadline section; verify search and Done disable drag; exercise Up/Down, captured single Return, double Return, Space, Command-D, Command-N, Escape, and absence of indent controls.
5. Seed 101+ To Do and 101+ Done rows through bounded `seed_tasks`; verify 100-row initial pages, Load More, global cross-status search, refresh, true empty, completed empty, no-results, and local stable IDs through `dump_tasks`.
6. Exercise retained Task Assistant settings exactly. With a controlled model result, prove explicit/high-confidence direct local creation and ambiguous discard. Run a tiny bounded Test Run sample for acceptance while retaining the production 100,000-frame capability; prove it changes neither observations nor tasks.
7. Through typed Chat and realtime/PTT, read broad and today tasks, create without due date (+24h), create with explicit due, rename/reschedule/complete/pending/delete, hear the tool result, observe immediate local UI, and verify there is no immediate Task Added system banner.
8. Create/edit/complete a simple local goal from the surviving UI; verify active goal Chat context; restart; switch owners and prove neither tasks, goals, Undo entries, nor reminders leak.
9. Delete an S-10 source conversation and prove every still-linked task is permanently removed while an unrelated task remains and no task details disclose the raw source-session ID.
10. Verify no Board, bulk clean, filters, full-create sheet, tags/categories/raw metadata, Suggested, task chat/Execute, ranking/Re-score, numeric goal/progress, or score widget remains; verify ordinary main Chat and retained Dashboard/Home task projections still work.

### Explicit offline acceptance

Use the repository's current refusal harness:

```bash
cd desktop/macos
eval "$(./scripts/omi-fault-inject.sh start refuse)"
OMI_APP_NAME=omi-s13-offline \
OMI_AUTOMATION_PORT=47814 \
OMI_SKIP_BACKEND=1 \
OMI_SKIP_TUNNEL=1 \
OMI_PYTHON_API_URL="$OMI_FAULT_URL" \
OMI_DESKTOP_API_URL="$OMI_FAULT_URL" \
./run.sh
```

With that named bundle, repeat local task CRUD/edit/order/complete/recurrence/delete/Undo, local goal CRUD/complete, and restart durability. Hosted Gemini/auth-dependent acceptance is a separate online step; offline authority acceptance must not pretend model calls work without a provider. Capture exact bundle ID, PID, automation port, log path, commands, screenshots/automation results, and the absence of retiring endpoint requests.

## 16. Repository closure versus separately authorized live operational closure

### Repository closure owned by the S-13 PR

- local authority and retained behavioral tests are green;
- every in-tree Mac caller is local or deleted;
- removed backend routes are absent/404 and absent from OpenAPI/generated Swift/route policy;
- task/goal Firestore code, exclusive indexes, job/workflow/config, task-specific notification helpers, tests, fixtures, metrics/alerts, and current docs are absent or explicitly handed off;
- fresh/upgraded schema, offline/restart/owner/S-10 integration, named-bundle paths, component suites, preflight, ledger, diff check, and residue classifications are recorded;
- S-08 receives the local export-reader handoff and S-14/S-19 receive stable local data/tool contracts.

Repository closure does **not** assert that a remote collection, index, queue, scheduled job, Cloud Run revision, metric, alert, token, or stored customer record was deleted. The fork has no inherited user migration obligation, but that is not authorization to mutate infrastructure.

### Live operational closure requiring separate authorization and owned-project evidence

Only after explicit user authorization and repository merge may the appropriate infrastructure owners inventory and remove live S-13-exclusive resources: Firestore composite indexes/collections, task-intelligence scheduled/workflow executions, secrets/config variables, queues/jobs, task-specific alerting/metrics, and deployed route revisions. S-23/S-25/S-27 own shared backend/FCM/worker/deploy resource decisions. Record project IDs, resource names, pre/post evidence, rollback limitations, and confirmation that no retained service owns each resource. Never infer live state from repository absence or guess credentials/project identifiers.

## 17. Risks, ambiguities, gates, and explicit stop points

| Risk or ambiguity | Gate / response |
|---|---|
| S-10 is not integrated in the planning checkout | G1 blocks task schema/source/cascade implementation. Safe C1 characterization can be prepared, but no identity/schema/backend teardown proceeds. |
| IR-032 conflicts with later IR-643 | Resolved by chronology and explicit IR-643 text: no local candidate/review table. Stop any implementation that ports Suggested/Later/Dismiss lifecycle. |
| IR-651 conflicts with later IR-652 | Resolved: keep the exact local interval slider; delete only cloud ownership. Stop any UI deletion based on IR-651 alone. |
| IR-025/620/625 mention tags/category/scores/metadata | Later IR-629/630/631/633/634/635/647/825 narrow them. The recurrence copy list contains only retained fields. |
| Existing `TaskActionItem` is deeply server-shaped | Migrate callers vertically, then delete the compatibility projection in C15. Do not add a second local DTO plus adapters that persist indefinitely. |
| Notification scheduling is an OS side effect after DB commit | Treat it as idempotent derived state; never roll back task data. Tests inject the verified bridge; named-bundle acceptance proves the OS path. |
| Task embeddings may have a retained ordinary-task caller | C10/C15 must enumerate `EmbeddingService` callers after staged deletion. Keep only proved ordinary local search; delete score/staged coupling. Do not decide from comments. |
| Goal consumers in S-14 may still expect numeric/cloud `Goal` | S-13 publishes the simple local shape; S-14 adapts. A request for more fields is a product-decision stop, not permission to retain cloud compatibility. |
| Backend conversation processing still writes/cascades cloud action items | Rebase on S-10 and inventory exact remaining callers. Backend deletion waits until the Mac local producer/cascade is green. |
| Broad “candidate” searches hit retained release candidates | Classify exact path/meaning. Never delete desktop beta/Cloud Run/transcription candidate machinery as task-intelligence residue. |
| `backend/services/users/data_export.py` loses cloud tasks/goals | S-13 supplies local reader contract/evidence; S-08 owns final export composition/UI. Repository closure requires a named handoff, not an empty export. |
| Generic FCM/account deletion code shares files with task helpers | Delete only task-specific helpers/vector/export imports. Preserve generic notification and recursive account wipe for S-23/S-08. |
| Removed routes currently have 410 compatibility entries | Delete the registry entries and assert 404/absence. A 200/204/410/no-op replacement is a closure failure. |
| Schema rebuild could lose row IDs, source links, recurrence/order, or FTS | C15 uses old-schema fixtures and transaction rollback; any loss blocks migration and backend deletion. Historical migrations remain unchanged. |
| Model/Test Run calls need managed credentials/network and can cost money | Unit tests inject model results. Real Test Run acceptance uses a deliberately tiny date/sample window without changing the retained 100k product capability; missing provider credentials block only that live-online acceptance and final closure, not local authority cycles. |
| Named bundle cannot sign in or notification permission is unavailable | Record the exact external input/state and continue hermetic/offline tests; final real-path closure remains blocked until the named non-prod bundle can exercise it. Never use the production app. |
| A mixed file has concurrent slice changes | Rebase, rerun inventory, and preserve the other owner's behavior. Do not overwrite, duplicate, or silently absorb it. |
| A proposed deletion lacks a real retained-path test | Stop and add the behavioral keep fence first. Static residue/source checks alone cannot authorize deletion. |

## 18. Final completion checklist

### Requirements and dependency closure

- [ ] Exact execution HEAD, merge-base, integrated S-06 commit, and integrated S-10 commit are recorded; `0d9934c` remains an ancestor or any deliberate new baseline is documented.
- [ ] Requirements ledger passes immediately before implementation and at final closure.
- [ ] All 60 assigned IR rows above were re-read in the live ledger; every supersession is applied exactly.
- [ ] S-10 stable local source-session ID, linked query, Conversation Detail read, and same-transaction cascade pass.
- [ ] S-08 local export reader, S-14 local context, S-19 local task tools, S-21 shell, and S-23/S-25/S-27 operational handoffs are recorded with exact commits/symbols.

### Retained local product

- [ ] C1–C17 each showed the intended RED before GREEN and recorded changed files/tests/commands/evidence.
- [ ] Every task producer/consumer uses one owner-scoped `ActionItemStorage` authority and surfaced local ID; no backend/local dual identity remains.
- [ ] Inline create/edit/deadline/priority, complete/reopen/recurrence, reminder lifecycle, deletion/Undo, order/drag, keyboard, search/pagination/states, details/Why/New, settings, Assistant/Test Run, Chat/PTT, automation, Dashboard/Home, and source cascade satisfy section 9.
- [ ] One simple local goal supports create/edit/complete/restart/owner isolation/Dashboard/onboarding/active Chat context with no numeric/cloud dependency.
- [ ] Offline refusal, cold restart, owner switch, fresh/upgraded database, and real named-bundle acceptance are recorded.
- [ ] Ordinary main Chat, retained notification behavior, retained Dashboard/Home projections, and unrelated backend routes remain green.

### Deletion and simplification closure

- [ ] Every DELETE item in section 8 and every exclusive inventory item in section 7 is gone; mixed files are narrowed without collateral deletion.
- [ ] No Board, bulk clean, advanced filters, modal create, tags/category/source class/raw metadata/analysis compatibility, share residue, multiselect, indent, Suggested, rank/relevance, dormant scheduler, task chat/agent/workstream, rich/cloud goals, or productivity score surface remains.
- [ ] No production Mac task/goal path calls retiring APIs, refreshes from server, polls for backend ID/sync, or rolls back on remote failure.
- [ ] Removed routes are absent/404; deprecated registry, route policy, OpenAPI/generated Swift/tool contracts, Firestore indexes, jobs/workflows/scripts/config/fixtures/tests/docs contain no unexplained live residue.
- [ ] `ActionItemTaskIdentity` backend arm, empty adapters/clients/services/imports, server-shaped conversions, dead metrics, and orphan test support were simplified only after caller migration.
- [ ] No no-op shell, deprecated alias, compatibility DTO, ignored field, fake success, cloud backfill, or hypothetical-user migration was introduced.

### Verification and delivery evidence

- [ ] All exact residue commands in section 13 were run after rebase and at closure; every surviving hit is classified.
- [ ] Focused Swift, tool-surface, agent (when applicable), backend route/import/OpenAPI/index, schema, notification, owner, and automation tests pass.
- [ ] `bash desktop/macos/test.sh` passes.
- [ ] `(cd backend && bash test-preflight.sh && bash test.sh)` passes.
- [ ] `make preflight` passes.
- [ ] `python3 bootstrap-scaffold/validate-requirements-ledger.py` passes.
- [ ] `git diff --check` passes and the final diff contains intentional S-13 implementation/docs only.
- [ ] The real named non-production bundle was exercised; exact bundle ID/PID/port/log/evidence and any unavailable external input are stated honestly.
- [ ] Component/product docs describe local Tasks/simple Goals and do not promise deleted behavior; historical changelog/migration records remain historical.
- [ ] Repository closure and any separately authorized live operational closure are reported separately; no live mutation is implied by merge.
