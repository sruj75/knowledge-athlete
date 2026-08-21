# S-14 — Make Focus, Insights, proactive advice, and AI Profile local-authoritative

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | S-14 |
| Wave | Wave 2 — establish local authority before deleting remote authority |
| Assigned output | `bootstrap-scaffold/wave-2/s-14 tdd.md` |
| Assigned decisions | IR-029 through IR-038, IR-229 through IR-231, IR-505, IR-508, IR-659 through IR-682, IR-723, IR-724, IR-814, IR-829 |
| Product boundary | Mac Focus, Insights, Live Suggestions, AI Profile, local proactive settings and notifications; rejection of their cloud mirrors, Daily Summary, notification-model workloads, and Notifications Cloud Run job |
| Implementation rule | Protect retained behavior first, establish one local owner, migrate every caller, prove offline/restart/account-switch behavior, delete remote authority, then simplify. Do not create compatibility shells. |

This is the execution-grade TDD plan for S-14. It is not authorization to mutate production or live-cloud state while writing this document.

## 2. Planning status and pinned baseline

| Evidence | Verified planning state on 2026-08-16 |
|---|---|
| Checkout | `/Users/srujanu/conductor/workspaces/knowledge-athlete/honiara` |
| Current branch | `review-wave-1-deletions` |
| Pinned code baseline | `0d9934c9d2ed61bd02ac8784e50f56ee816257c3` |
| Baseline ancestry | `git merge-base --is-ancestor 0d9934c9d2ed61bd02ac8784e50f56ee816257c3 HEAD` returned success |
| Planning-time `origin/main` | `3aab1026357fb0be6bcf567c24df84684ba6198e` |
| Requirements proof | `python3 bootstrap-scaffold/validate-requirements-ledger.py` passes with 714 indexed rows, 714 detailed sections, all reviewed |
| Source grounding | Every current path, symbol, route, table, job, workflow, and command named as existing below was found in this checkout. Planned new test/type names are explicitly marked **new**. |
| Readiness | Research complete. Implementation is blocked on the predecessor gates in Section 5 and then must be refreshed against the integrated execution HEAD. |

The pinned baseline is evidence for this plan, not permission to implement against stale code. Before the first RED, fetch and integrate current `origin/main`, integrate the required predecessor slices, record the new immutable execution SHA, and repeat the inventory. If an expected predecessor seam differs, update this plan or stop; do not recreate the predecessor or add a temporary adapter that preserves the rejected cloud shape.

## 3. Outcome

At completion, one signed-in Mac owner has one authoritative local source for each retained private behavior:

- accepted Focus transitions live only in the owner’s GRDB `focus_sessions` table;
- Insights live only as owner-local Memory records tagged `tips`; `InsightStorage` may project those rows but may not persist a second copy;
- AI Profile history lives only in the owner’s GRDB `ai_user_profiles` table;
- assistant controls and the master notification/frequency controls live only in local preferences;
- Home questions are generated from bounded local context and cached per owner/day;
- Focus and Insights share one top-level Insights hub, with exact local record navigation;
- proactive cards and macOS notifications use the local presentation/Chat-journal path;
- the Mac can read, mutate, and navigate these products after restart and while the Python product-data backend is unavailable.

The following rejected authorities are absent from the repository surface after their callers leave: Focus session/stat APIs, server AI Profile, assistant/notification/Mentor settings mirrors, cloud Daily Summary, cloud Mentor/App proactive-model residue, GPT-personalized purchase/quota pushes, and the Notifications Cloud Run job. Generic FCM primitives with proven non-S-14 callers remain for S-23; billing, entitlement, quota, managed Gemini proxy, capture, local Chat, local Tasks/Goals, local Memories, and Rewind remain owned by their respective slices.

## 4. Authorizing requirements: individual IR mapping

| IR | Decision implemented by S-14 | Plan coverage |
|---|---|---|
| IR-029 | Keep a simple local Focus view: current state, delay/cooldown, today totals, and a short recent list. Delete 30-day/all-time browsing, search, top-distraction presentation, UserDefaults history, backend IDs, and sync. | Cycles 1–3 |
| IR-030 | Keep screenshot/context Gemini Focus judgment, exclusions, cadence, notification, and glow. Persist only durable Focus sessions; delete duplicate Memory rows, backend Memory writes, sync bookkeeping, and unused Focus APIs. | Cycles 1–3, 13 |
| IR-031 | Keep high-confidence/explicit automatic Task extraction, but admit directly through S-13’s local task authority with local dedup/provenance. | Cycle 8 protection test and S-13 handoff |
| IR-032 | Superseded by IR-643: do not create a Suggested review queue, staged candidate authority, promotion path, or uncertain-update compatibility behavior. | Section 5 gate; Cycle 8 protection test |
| IR-033 | Keep automatic screenshot-to-Memory extraction, but its accepted write terminates in S-12’s local Memory transaction; S-14 only removes settings sync interference and protects notification behavior. | Cycle 8 and S-12 handoff |
| IR-034 | Keep the two-phase Insight/Advisor analysis, selected screenshot context, cadence/confidence/exclusions/dedup, notifications, history, search/filter/detail, and actions. Make local `tips` Memory rows the sole authority; delete backend Memory sync and the UserDefaults copy. | Cycles 4–5 |
| IR-035 | Keep Live Suggestions distinct from stored Insights: context-switch/dwell/cooldown/daily-budget gates, local grounding, Gemini, floating card, notification throttle/snooze, local Chat continuity, bounded telemetry, and local settings. | Cycles 8 and 10 protection tests |
| IR-036 | Make shared/Focus/Task/Insight/Memory assistant settings local-authoritative. Delete server pull/push/deep merge/startup overwrite. | Cycle 8 |
| IR-037 | Keep the local master Notifications switch, exact 0–5 frequency policy, migration, snooze, and functional-notification exceptions; delete cloud settings sync. | Cycle 8 |
| IR-038 | Keep factual daily AI Profile generation, two-stage Gemini consolidation, five prior profiles, local history/edit/regenerate/delete, onboarding file-exploration input, and all assistant consumers. Use only local inputs and local `ai_user_profiles`; delete server profile/sync/cache. | Cycle 6 |
| IR-229 | Keep the visible master notification switch and six local levels: Off, Minimal, Low, Balanced, High, Maximum. | Cycle 8 |
| IR-230 | Keep local Live Suggestions, Focus, Task, Insight, and Memory notification switches; remove backend push/hydration. | Cycle 8 |
| IR-231 | Delete Daily Summary settings card, toggle, hour state, API load/update calls, and settings-search entries. | Cycle 12 |
| IR-505 | Home Insight rows open the real owner-local Insight and mark it read; X dismisses locally. Delete recommendation-only Later/feedback semantics from local Insight rows. | Cycles 5 and 9 |
| IR-508 | Keep at most two personalized daily Home questions plus the universal/static questions, owner/day cache, sanitization, generation fence, successful-empty hold, failure retry, and ask-bar prefill. Replace server reads with local context and remove onboarding-suggestion input. | Cycle 7 |
| IR-659 | Top navigation is visibly and plainly Home / Memory / Tasks / Insights; the combined hub defaults to Insights and retains a Focus segment. | Cycle 9 |
| IR-660 | Exact Focus delete and Clear All mutate durable GRDB, recompute projections, restore UI on failure, and expose an error. | Cycle 2 |
| IR-661 | “Monitoring” requires both Focus enabled and canonical capture actually active; otherwise say “Focus disabled”, “Capture off”, or “Capture blocked”. | Cycle 3 |
| IR-662 | Preserve the current unqualified restored Focus card presentation exactly. | Cycle 3 characterization and acceptance |
| IR-663 | Extend only the newest Focus period to now when stopped; older periods end at the next transition. | Cycle 2 |
| IR-664 | Do not add a one-second timer for normal Focus totals; the existing one-second tick is only for delay/cooldown countdown. | Cycle 3 |
| IR-665 | On owner change clear every Focus projection and generation-fence load/insert/refresh/delete/clear. Use the predecessor’s per-owner directory; do not delete the prior owner’s database. | Cycles 1–2 |
| IR-666 | Enforce newest 500 and 30-day Focus retention for the current owner after insert, startup, and refresh. | Cycle 2 |
| IR-667 | Preserve the exact current Focus empty-state copy. | Cycle 3 |
| IR-668 | Preserve both visible Refresh affordances; rename misleading `refreshFromBackend` internals and make refresh local-only. | Cycles 2–3 |
| IR-669 | Store all Insights; the page reads the newest 100. Do not add an Insight-retention cap. | Cycle 4 |
| IR-670 | On owner switch clear every Insight projection, selection, loading/error state, and generation-fence all asynchronous work. | Cycles 4–5 |
| IR-671 | Clear All deletes every current-owner `tips` record, including dismissed/older-than-100 rows, in one transaction; ordinary Memories remain. | Cycle 5 |
| IR-672 | Delete removes exactly one current-owner tagged record; failure rolls back and surfaces an error. | Cycle 5 |
| IR-673 | Dismiss updates exactly one tagged record, keeps Show Dismissed useful, and rolls back/surfaces error on failure. | Cycle 5 |
| IR-674 | Opening an Insight shows the detail even if the read write fails; restore unread state and surface the write error. | Cycle 5 |
| IR-675 | Mark All Read updates all current-owner tagged rows, including dismissed, filtered, older-than-100, and currently unrendered rows, transactionally. | Cycle 5 |
| IR-676 | Preserve the exact current Insights empty-state copy. | Cycle 5 characterization and acceptance |
| IR-677 | The top-level Insights navigation item has no badge or status decoration. | Cycle 9 |
| IR-678 | Home opens the combined hub on Insights and resolves the exact owner-local record; missing/stale-owner requests fail truthfully rather than opening a different record. | Cycle 9 |
| IR-679 | `navigate insight` enters the combined hub on Insights. Delete the standalone `.insight` page route; direct component previews may remain. | Cycle 9 |
| IR-680 | `navigate focus` enters the same combined hub on Focus. | Cycle 9 |
| IR-681 | Final numbered shortcuts are ⌘1 Home, ⌘2 Memory with Memories selected, ⌘3 Tasks, ⌘4 Insights. Remove numbered Rewind; preserve global ⌘⌥R and Settings ⌘,. Make `navigate_via_shortcut` identical. | Cycle 9 |
| IR-682 | Insight floating-card click enters the current owner’s local Chat journal with origin `proactive_notification`; X/time-out affect presentation only and do not mutate the stored Insight. | Cycle 10 |
| IR-723 | Delete the separate Python cloud Mentor/App proactive-notification model workload and exclusive configuration/tests/docs. Preserve Mac assistants and direct managed Gemini compute; do not build a replacement Mentor pipeline. | Cycle 10 |
| IR-724 | Delete GPT-personalized subscription and credit-limit push copy, cloud Memory reads, credit-push Redis dedupe, and payment/listen callers. Preserve structured billing/quota truth and the existing Mac handling of `freemium_threshold_reached`; preserve the separately static silent-user nudge. | Cycle 11 |
| IR-814 | Delete the complete Notifications Cloud Run job, its wearable/Daily Summary cron, image/workflow/runtime manifest/validation/docs/tests. Preserve generic notification helpers only where another live caller exists. | Cycle 13 |
| IR-829 | Delete `GET/PATCH /v1/users/mentor-notification-settings`, models, Firestore helper/field/cache key, generated bindings, route-policy entries, tests, and docs. | Cycle 10 |

Supporting decisions that constrain implementation but are not reassigned to S-14: IR-039 authorizes complete Daily Summary deletion; IR-160 removes onboarding suggestions from Home question composition; IR-246 keeps Stable/Beta update choice local while preserving the server’s public desktop update-policy/release machinery; IR-515 owns canonical capture-status derivation; IR-643 supersedes IR-032; IR-826 leaves final generic FCM deletion to S-23.

## 5. Dependencies and entry gates

### Required predecessor shapes

| Dependency | Exact shape S-14 consumes | Gate and stop condition |
|---|---|---|
| S-10 Conversations | Owner-scoped `TranscriptionStorage`/archive reader with stable local conversation identities, bounded recent-summary reads, and no cloud fallback. | Required before Cycles 6–7. Stop if only `APIClient.getConversations` can provide profile/question input. |
| S-12 Memory | Owner-scoped GRDB `MemoryStorage` with local query/command operations, stable local record identity, `tags` including `tips`, read/dismiss fields, transactional bulk mutation, and authorization snapshots. | Required before Cycles 4–7. Stop if S-14 would need to add another Memory table/cache, use `/v3/memories`, or infer owner from mutable global state after an await. |
| S-13 Tasks/Goals | `ActionItemStorage`/`TasksStore` local task authority and `GoalStorage` local goal authority; accepted automatic extraction admits directly with dedup/provenance and no Suggested queue. | Required before Cycles 6–8. Stop if the integrated task path still requires backend IDs, candidates, staging, or promotion. |
| S-15 Rewind/capture | Final local screenshot/context read boundary and canonical capture-health ownership. | Required before Cycles 1 and 3 if its interface changes `ProactiveAssistantsPlugin`, `CaptureListeningLogic`, or screenshot reads. Do not reproduce Rewind storage. |
| S-11 Chat/Home | Local Chat journal admission/query seam and final Home shape after cloud Dashboard intelligence removal. | Required before Cycles 7, 9, and 10. Stop if notification continuity would write a second Chat store or Home still exposes rejected recommendation semantics. |

The plan intentionally does not freeze speculative predecessor symbol names beyond the contracts above. At execution, replace those descriptions with the actual integrated symbols in the implementation PR and its tests.

### Mandatory entry sequence

```bash
git fetch origin --prune
git status --short
git rebase origin/main
git rev-parse HEAD
git merge-base --is-ancestor 0d9934c9d2ed61bd02ac8784e50f56ee816257c3 HEAD
python3 bootstrap-scaffold/validate-requirements-ledger.py
make setup
test -x "$(git rev-parse --git-path hooks)/pre-commit" && echo OK
```

Then rerun every residue command in Section 13 and record a refreshed caller ledger in the implementation PR. `make setup` is required before the first commit, not while producing this planning-only file.

### Entry gates

1. **Clean scope gate:** preserve unrelated worktree changes. S-14 implementation must be isolated in its own worktree/branch and must not absorb other slices’ edits.
2. **Predecessor gate:** do not start a cycle that consumes a predecessor until that predecessor is integrated. Safe Focus-only characterization may be written earlier, but no production migration may bake in the pre-integration shape.
3. **Authority gate:** a GREEN cannot introduce a fallback read/write to a rejected backend, a sync outbox, a compatibility alias, or a second cache of private product data.
4. **Owner gate:** every asynchronous read, Gemini request, local mutation, publish, notification, and navigation request carries one `RuntimeOwnerAuthorizationSnapshot` or a predecessor-owned equivalent. A string owner check alone is insufficient across account-generation changes.
5. **Migration gate:** existing GRDB data must survive forward migration. Never rewrite historical migrations; add a new idempotent migration and test upgrade from the old schema.
6. **Behavioral-test gate:** source-string tests may guard forbidden residue but do not satisfy the RED. Each cycle’s RED must execute production behavior through a controllable seam.
7. **Cross-slice gate:** if removing a shared backend helper affects a retained caller outside S-14, stop and hand it to the owning slice instead of broadening deletion.
8. **Operational gate:** repository deletion does not authorize deleting a live Cloud Run job, scheduler, image, Firestore data, Redis keys, or secrets. Section 16 keeps those closures separate.

## 6. Verified current production codeflow

### Focus

1. `ProactiveAssistantsPlugin` captures screen/app changes and drives `FocusAssistant.processFrame` in `desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/Focus/FocusAssistant.swift`.
2. `FocusAssistant` applies delay/cooldown/excluded-app policy, builds local context from `GoalStorage.getLocalGoals`, `ActionItemStorage.getTopRelevanceTasks`, `MemoryStorage.getLocalMemories`, and `AIUserProfileService.getLatestProfile`, then calls Gemini.
3. On a status transition, `saveFocusSessionToSQLite` inserts a `FocusSessionRecord` through `ProactiveStorage.insertFocusSession`.
4. The same accepted event is copied into local Memory by `saveFocusToMemoriesTable`, copied again to cloud Memory by `syncFocusSessionToBackend` -> `APIClient.createMemory`, then marked with `ProactiveStorage.updateFocusSessionSyncStatus` and `MemoryStorage.markSynced`.
5. Only after that chain does `FocusStorage.addSession` publish to UI and `NotificationService.sendNotification`/glow present the change.
6. `FocusStorage` also maintains a process-global `sessions` projection: it loads/saves `omi.focus.sessions` in UserDefaults, loads 30 days/500 rows from GRDB, exposes `refreshFromBackend` even though that method is local, and uses backend-vs-SQLite deletion branches based on string IDs/sync fields.
7. `FocusPage` derives “Monitoring” from `FocusAssistantSettings.isEnabled` alone, supports search/historical mode/top distractions, and performs optimistic delete/clear without durable error rollback. Its one-second timer updates delay/cooldown only; current totals are computed on demand.
8. `backend/routers/focus_sessions.py` still registers POST/GET/DELETE `/v1/focus-sessions` and GET `/v1/focus-stats` through `backend/main.py`, with `backend/models/focus_session.py` and `backend/database/focus_sessions.py`. No current Mac production caller uses these routes; current Swift response DTOs at the bottom of `FocusStorage.swift` are orphaned.

### Insights / Advisor

1. `InsightAssistant` runs the retained periodic two-phase path: SQL/context selection (up to seven tool calls), selected screenshot Gemini analysis, local confidence/exclusion/dedup checks, and an in-memory `previousInsights` context window.
2. `handleResultWithScreenshot` first inserts a `MemoryRecord` tagged `tips` through `MemoryStorage.insertLocalMemory`.
3. It then calls `syncInsightToBackend` -> `APIClient.createMemory`, marks the local row synced, and separately calls `InsightStorage.addInsight`.
4. `InsightStorage` persists a second `[StoredInsight]` copy under UserDefaults key `omi.advice.history`, trims it to 100, starts `syncFromBackend` at initialization, reads `/v3/memories` with `tags: ["tips"]`, and performs update/delete calls against backend Memory.
5. `InsightPage` renders newest cached rows with search/category/Show Dismissed and exact empty copy. A row tap calls `markAsRead` before assigning `selectedInsight`; delete/dismiss/mark-all/clear mutate the cache optimistically and do not restore on remote failure. `markAllReadOnBackend` computes unread IDs after the local map has already marked every row read, so the current backend loop can become a no-op.
6. `DashboardPage.homeKnowsInsightCandidates` mixes cloud `DashboardIntelligenceStore.recommendations` with `InsightStorage.insightHistory`. Local Insight rows have no working open/dismiss/later path because the handlers resolve only recommendation IDs.

### AI Profile

1. `AIUserProfileService` reads/writes GRDB table `ai_user_profiles` through `RewindDatabase.databasePool` and caches the current pool generation.
2. `shouldGenerate` compares the latest `generatedAt` with 24 hours. `generateProfile` fetches cloud inputs in parallel: 100 Memories, 50 action items, active Goals, 20 recent Conversations from the prior seven days, and 30 Chat messages. The current conversation call does not pass a completed-status filter; the target local reader must follow IR-038 and select completed local conversations/transcripts.
3. Stage one asks Gemini for a factual profile; stage two consolidates it with up to five prior local profiles. The service inserts an `AIUserProfileRecord` locally and then fire-and-forgets `APIClient.syncAIUserProfile`, flipping `backendSynced` on success.
4. `updateProfileText` and `saveExplorationAsProfile` follow the same local-then-cloud pattern. `deleteProfile`, `deleteAllProfiles`, and `getAllProfiles(limit: 30)` are local.
5. Current consumers are `ChatProvider`, `FocusAssistant`, `GoalsAIService`, `InsightAssistant`, `TaskAssistant`, and `TaskPrioritizationService`; Settings Advanced provides history, edit, delete, regenerate, and onboarding file-exploration insertion.
6. The cloud projection is `GET/PATCH /v1/users/ai-profile` in `backend/routers/users.py`, backed by `backend/database/users.py` field `ai_user_profile` and `_USER_AI_PROFILE_CACHE`. The Mac calls PATCH only; generated Swift and OpenAPI expose both methods.
7. IR-038 also names a hosted MCP profile projection, but a current-checkout production search finds no reader beyond the users route/helper above. Treat that projection as already absent, keep it in residue searches, and do not invent deletion work.

### Home questions

1. `HomeSuggestionsStore` owns an owner/day UserDefaults entry (`homePersonalizedSuggestions.v1.<ownerID>`), publishes cached questions immediately, captures `RuntimeOwnerAuthorizationSnapshot`, generation-fences owner switches, retries failures, and records successful empty results for the day.
2. `GeminiHomeSuggestionGenerator` currently reads 200 server Memories, 30 completed server Conversations, 50 open server action items, and server Goals, distinguishes unavailable/thin/available context, and asks Gemini for up to two questions.
3. `HomeSuggestionComposer.compose(personalized:onboarding:)` combines personalized, onboarding, and static questions. IR-160 requires removing the onboarding input while retaining the universal first question, sanitization, and static top-up.

### Protected adjacent assistants

1. `desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/TaskExtraction/TaskAssistant.swift` currently turns an accepted extraction into a hidden `StagedTaskRecord` through `saveTaskToSQLite`/`StagedTaskStorage.insertLocalStagedTask`, then `syncTaskToBackend` resolves cloud candidate workflow mode and receipts. S-13, not S-14, replaces this current outbox/staging path with direct owner-local Task admission under IR-031/032/643. S-14 must characterize the integrated S-13 behavior before removing settings sync and must not preserve these pre-S-13 symbols as compatibility.
2. `desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/MemoryExtraction/MemoryAssistant.swift` calls `MemoryAssistantDurabilityPipeline.persistSyncAndEmit` from `MemoryAssistantTelemetry.swift` before analytics/notification/event publication. S-12 owns converting that durability terminal to local Memory-only admission under IR-033. S-14 protects the final pipeline’s settings and notification behavior; it does not implement a second Memory writer.
3. `desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/Suggestions/SuggestionAssistant.swift` uses `SuggestionGatePolicy` from `SuggestionModels.swift` for excluded-app, snooze, dwell, cooldown, daily-budget, and grounding decisions; its daily evaluation budget is 40. Accepted output goes through Gemini and `deliver` to a `FloatingBarNotification` with bounded `SuggestionAssistantTelemetry`. It does not persist an Insight or call the cloud Mentor model. This entire behavior remains distinct and retained under IR-035.

### Settings and local notification policy

1. `AssistantSettings`, `FocusAssistantSettings`, `TaskAssistantSettings`, `InsightAssistantSettings`, `MemoryAssistantSettings`, and `SuggestionAssistantSettings` already persist their runtime controls in UserDefaults.
2. `SettingsSyncManager` nevertheless treats server `assistant_settings` as authoritative: `syncFromServer` applies remote sections and `update_channel`; `syncToServer` and `pushPartialUpdate` write local values back.
3. Pulls run from `AuthService`, launch/activation in `OmiApp`, and `SettingsContentView.loadBackendSettings`. A one-time capture repair in `DesktopHomeView` calls `syncToServer`. Settings Assistants and Notifications invoke `pushPartialUpdate` on each toggle/field mutation.
4. `NotificationService` already reads local keys `notifications_enabled` and `notification_frequency`. The exact frequency policy is 0 Off, 1 one/hour, 2 one/30 minutes, 3 one/10 minutes, 4 one/3 minutes, 5 unthrottled. Its throttle and metadata are owner-scoped; snooze and functional-notification exceptions are local.
5. `NotificationService.migrateToOffByDefaultIfNeeded` sets the local frequency to 0 but also PATCHes `/v1/users/notification-settings`. Settings load/toggle/slider and two Desktop Automation actions still GET/PATCH that route.
6. Daily Summary state (`dailySummaryEnabled`, `dailySummaryHour`, `dailySummaryTime`) is loaded from `/v1/users/daily-summary-settings` and rendered in Notifications settings; `SettingsSidebar` indexes Daily Summary and Summary Time.

### Hub, Home, shortcuts, and notification-to-Chat

1. `SidebarNavItem` currently has `.focus = 5`, `.insight = 6`, and `.rewind = 7`. `TopNavigationRoutes.primaryItems` currently contains only Home, Memory, Tasks.
2. `FocusHubPage` is private to `DesktopHomeView.swift`, uses an integer `segment` defaulting to Insights, and mounts `InsightPage` or `FocusPage`. `PageContentView` mounts that hub at raw 5 and a second standalone `InsightPage` at raw 6.
3. `resolvedAutomationTarget("focus")` returns `.focus`; `resolvedAutomationTarget("insight")` returns `.insight`.
4. Current commands are ⌘1 Home, ⌘2 Conversations, ⌘3 Memories, ⌘4 Tasks, ⌘5 Rewind, plus ⌘, Settings and global ⌘⌥R Rewind. `DesktopAutomationBridge.navigate_via_shortcut` mirrors 1–5 and Settings. `MemoryHubDestination.destination(for:)` intentionally maps `.conversations` to the Conversations child, so it must be changed for the new ⌘2 contract.
5. `NotificationService.sendNotification` creates `FloatingBarNotification` with immutable `ownerID` and context. `FloatingControlBarManager.presentNotification` calls `persistNotificationMessageIfNeeded`, which records a local Chat journal exchange with origin `proactive_notification`; `openNotificationAsChat` rejects stale owners and opens that conversation. X/time-out currently dismiss presentation only.

### Rejected backend notification products

1. `backend/utils/llm/proactive_notification.py` still contains relevance, draft, critic, and combined `evaluate_proactive_notification` model functions, but a repository-wide production search finds no production import/caller in this checkout. Only tests and model/config/inventory residue reference it.
2. `backend/utils/llm/notifications.py` reads Firestore Memories and uses the `notifications` model for subscription and credit-limit copy. `backend/utils/notifications.py` exposes `send_subscription_paid_personalized_notification` and `send_credit_limit_notification`.
3. `backend/routers/payment.py` invokes the purchase notification after a paid checkout. `backend/routers/listen/runtime.py` invokes the credit notification while separately emitting the authoritative `FreemiumThresholdReachedEvent`; the same file also invokes the separately static `send_silent_user_notification`, which IR-724 preserves.
4. `backend/modal/job.py` calls `utils.other.jobs.start_job`. In this checkout `utils.other.jobs.start_job` invokes only `utils.other.notifications.start_cron_job`; there is no remaining X/Twitter sync invocation. That cron sends the wearable reminder and generates/stores/pushes Daily Summaries.
5. The job is registered by `backend/modal/Dockerfile.notifications_job`, `.github/workflows/gcp_notifications_job.yml`, `backend/runtime_images.json`, and `backend/deploy/runtime_env.yaml`, with validator/concurrency/pre-push/check-manifest/workflow-contract references.

## 7. Complete caller and dependency inventory at the pinned baseline

### Mac production and tests

Unless a row begins with another root, source paths in this table are relative to `desktop/macos/Desktop/Sources/`; test paths are relative to `desktop/macos/Desktop/Tests/`.

| Current file / symbol | Current callers or dependencies | S-14 disposition |
|---|---|---|
| `ProactiveAssistants/Assistants/Focus/FocusAssistant.swift` — `FocusAssistant`, `processFrame`, `saveFocusSessionToSQLite`, `saveFocusToMemoriesTable`, `syncFocusSessionToBackend` | Driven by `ProactiveAssistantsPlugin`; reads Goals, Tasks, Memories, AI Profile; publishes through `FocusStorage`, `NotificationService`, glow/event callbacks | Adapt; delete duplicate local/cloud writes and fence one local admission |
| Same file — `typealias GeminiService = FocusAssistant` | No production or test caller beyond the declaration | Simplify after migration; delete, no alias |
| `ProactiveAssistants/Assistants/Focus/FocusStorage.swift` — `FocusStorage` | `FocusPage`, `DashboardPage`, `SidebarView`, `NotchSystemControlsView`, `NotificationService`, `ProactiveAssistantsPlugin`, `FocusAssistant` | Adapt into owner-fenced GRDB-backed projection; delete UserDefaults/backend identity logic |
| Same file — `FocusSessionResponse`, `FocusStatsResponse` and related response DTOs | No Mac network caller; only local compile references | Delete after route retirement |
| `Rewind/Core/ProactiveModels.swift` — `FocusSessionRecord` | `FocusAssistant`, `ProactiveStorage`, `RewindDatabase` | Adapt; retain local fields/ID, remove `backendId`/`backendSynced` in forward migration |
| `Rewind/Core/ProactiveStorage.swift` — Focus CRUD/stats/sync methods | `FocusAssistant`, `FocusStorage` | Adapt; add transactional exact delete/clear/retention, delete sync methods |
| `Rewind/Core/RewindDatabase.swift` — `createFocusSessions`, `createAIUserProfiles` | All GRDB users | Adapt only with new forward migrations; keep historical migrations intact |
| `MainWindow/Pages/FocusPage.swift` — `FocusViewModel`, `FocusPage` | Hub and direct previews; reads `FocusStorage`/settings | Adapt presentation/status/actions; preserve exact empty/current card |
| `ProactiveAssistants/ProactiveAssistantsPlugin.swift` — Focus realtime updates/delay | Focus assistant and FocusStorage | Keep behavior; adapt only authorization/canonical status integration |
| `MainWindow/CaptureListeningLogic.swift` — `CaptureListeningLogic.captureStatus`; `ProactiveAssistants/ProactiveAssistantsPlugin+ScreenCaptureHealth.swift` — `screenCaptureHealth` | Home status/capture UI and Focus monitoring | Keep shared authority; consume it, do not invent another capture flag |
| `ProactiveAssistants/Assistants/Insight/InsightAssistant.swift` — `InsightAssistant`, `handleResultWithScreenshot`, `saveInsightToSQLite`, `syncInsightToBackend` | Driven by plugin; reads local SQL/screenshots/profile; writes Memory/backend/cache; notifies | Adapt to one S-12 Memory transaction and local notification |
| `ProactiveAssistants/Assistants/Insight/InsightStorage.swift` — `StoredInsight`, `InsightStorage` | `InsightPage`, `DashboardPage`, `SidebarView`, `InsightAssistant` | Adapt as a read/projection adapter over local tagged Memory or replace; delete UserDefaults/backend sync |
| `MainWindow/Pages/InsightPage.swift` — `InsightViewModel`, `InsightPage`, `InsightTimelineRow` | Combined hub, standalone raw case 6, direct previews | Adapt actions/error/owner navigation; preserve search/filter/detail and exact empty copy |
| `MainWindow/Pages/DashboardPage.swift` — `homeKnowsInsightCandidates`, `openKnowsRow`, dismiss/later handlers | `DashboardIntelligenceStore`, `InsightStorage`, `TaskNavigationRequestStore`, selected tab binding | Adapt local Insight rows to exact local actions; S-11 removes rejected recommendation owner |
| `MainWindow/SidebarView.swift` — `SidebarNavItem`, Insight/Focus counts/loading | `DesktopHomeView`, `DesktopTopBar`, commands, automation | Adapt raw route to one Insights hub; remove standalone Insight route/badge semantics |
| `MainWindow/DesktopTopBar.swift` — `TopNavigationRoutes.primaryItems` | `DesktopTopBar`, `TopNavigationBarLayoutTests` | Adapt to four plain items |
| `MainWindow/DesktopHomeView.swift` — `resolvedAutomationTarget`, `FocusHubPage`, `PageContentView` | Navigation notifications, Home, automation | Adapt to typed hub segment and exact Insight request; delete case 6 |
| `MainWindow/MemoryHubDestination.swift` — `destination(for:)` | Navigation notification handler, top bar, Cmd/automation | Adapt ⌘2/shortcut to `.memories`; preserve Memory menu behavior owned with S-10 |
| `OmiApp.swift` command group | Posts `.navigateToSidebarItem`; also settings sync launch hooks | Adapt numbered commands; preserve ⌘⌥R/⌘,; delete settings pull hooks |
| `DesktopAutomationBridge.swift` — `navigate_via_shortcut`, `settings_notifications_snapshot`, `set_notification_settings` | Non-production acceptance tooling | Adapt to final shortcut map and local settings; keep behaviorally useful harness |
| `ProactiveAssistants/Services/AIUserProfileService.swift` — all profile CRUD/generation | Consumers: `ChatProvider:2215`, `FocusAssistant:669`, `GoalsAIService:170`, `InsightAssistant:610`, `TaskAssistant:944`, `TaskPrioritizationService:107/109/353`; Settings Advanced/history/file exploration | Adapt inputs/output/owner fencing; keep public consumer seam; delete cloud sync field/calls |
| `Services/APIClient/APIClient+ChatSessions.swift` — `AIUserProfileResponse`, `syncAIUserProfile` | `AIUserProfileService` only | Delete after local Profile GREEN |
| `MainWindow/Dashboard/HomeSuggestionsStore.swift` — composer/store/generator | `DashboardPage` observes the store and composes chips; `ChatProvider` also calls `HomeSuggestionComposer.compose` with `HomeSuggestionsStore.shared.personalizedQuestions`; tests are in `HomeSuggestionsStoreTests.swift` | Adapt both production compose callers, generator inputs, and signature; retain store policy |
| `ProactiveAssistants/Assistants/TaskExtraction/TaskAssistant.swift` — `saveTaskToSQLite`, `syncTaskToBackend`; `Rewind/Core/StagedTaskStorage.swift` | Current pre-S-13 automatic Task path; settings and profile consumers touch S-14 | S-13 replaces authority; S-14 only protects final direct admission while removing settings sync |
| `ProactiveAssistants/Assistants/MemoryExtraction/MemoryAssistant.swift` and `ProactiveAssistants/Assistants/MemoryExtraction/MemoryAssistantTelemetry.swift` — `MemoryAssistantDurabilityPipeline.persistSyncAndEmit` | Current pre-S-12 automatic Memory path; notification/settings are S-14-adjacent | S-12 replaces durability terminal; S-14 protects final settings/notification behavior |
| `ProactiveAssistants/Assistants/Suggestions/SuggestionAssistant.swift`, `ProactiveAssistants/Assistants/Suggestions/SuggestionModels.swift`, `ProactiveAssistants/Assistants/Suggestions/SuggestionAssistantTelemetry.swift`, `ProactiveAssistants/Assistants/Suggestions/SuggestionAssistantSettings.swift` | `ProactiveAssistantsPlugin`, local notification/floating bar, Settings | Keep Live Suggestions behavior; localize settings only and guard against cloud Mentor/Insight conflation |
| `ProactiveAssistants/Services/SettingsSyncManager.swift` | `AuthService.swift`, `OmiApp.swift`, `MainWindow/DesktopHomeView.swift`, `MainWindow/Pages/Settings/Components/SettingsContentView+BillingHelpers.swift`, 13 mutations in `MainWindow/Pages/Settings/Sections/SettingsContentView+Assistants.swift`, 4 notification mutations in `SettingsContentView+NotificationsPrivacy.swift`; `MemoryAssistantTelemetryTests.swift` and `PersistedCaptureLaunchPolicyTests.swift` call `applyRemoteSettings` | Delete after direct-local behavior is protected and every listed caller/test migrates |
| `ProactiveAssistants/Services/AssistantSettings.swift` and Focus/Task/Insight/Memory/Suggestion settings files | Plugin/assistants/settings UI | Keep local stores; adapt runtime reconciliation where it formerly waited for `.assistantSettingsDidSyncFromServer` |
| `ProactiveAssistants/Services/NotificationService.swift` | Direct producers are `ProactiveAssistantsPlugin`, `SuggestionAssistant`, `FocusAssistant`, `GoalGenerationService`, `MemoryAssistant`, and `InsightAssistant`; the service also presents contextual Task notifications and screen-capture functional notifications through the floating bar/native center | Keep local delivery/throttle; remove server migration push only |
| `Services/APIClient/APIClient+Settings.swift` — Daily Summary, notification, assistant methods/models | Settings UI, automation, `SettingsSyncManager`, API routing tests | Delete only S-14 methods/models; preserve language/transcription/privacy/update-policy siblings |
| `MainWindow/Pages/Settings/Components/SettingsContentView+BillingHelpers.swift` — `loadBackendSettings` | Settings page load | Adapt parallel tuple to omit Daily Summary/notification/assistant calls without changing other settings |
| `MainWindow/Pages/Settings/Components/SettingsContentView+SettingsUpdates.swift` | Notifications and Daily Summary views | Adapt notifications to local writes; delete Daily Summary function |
| `MainWindow/Pages/Settings/Sections/SettingsContentView+NotificationsPrivacy.swift` | Settings page | Keep notification controls and five assistant switches; delete Daily Summary card |
| `MainWindow/SettingsSidebar.swift` | Settings search | Delete Daily Summary/Summary Time entries; preserve Notifications/Plan and Usage |
| `FloatingControlBar/FloatingControlBarState.swift` — `FloatingBarNotification(Context)` | Local assistant producers and floating-bar manager | Keep owner provenance and context |
| `FloatingControlBar/FloatingControlBarWindow.swift` — `openNotificationAsChat`, `persistNotificationMessageIfNeeded` | Floating-bar views call open; journal uses `recordJournalExchange(origin: "proactive_notification")` | Keep/adapt only as required by S-11 seam; add Insight-specific behavior tests |
| Existing tests `FocusStorageSessionIdTests`, `HomeSuggestionsStoreTests`, `APIClientAssistantSettingsTests`, `SettingsResponseTests`, `PersistedCaptureLaunchPolicyTests`, `TopNavigationBarLayoutTests`, `DesktopAutomationSecondaryActionTests`, notification tests | Current behavior/static contracts | Rewrite/delete only when production owner disappears; add behavioral tests named in cycles |

### Backend, generated contracts, jobs, and docs

| Current file / symbol or surface | Current callers/dependencies | S-14 disposition |
|---|---|---|
| `backend/routers/focus_sessions.py` and `backend/main.py` router registration | No current Mac caller; boundary/e2e tests and deprecated route list reference it | Delete router/registration/routes |
| `backend/models/focus_session.py`, `backend/database/focus_sessions.py` | Focus router only | Delete after import/caller proof |
| `backend/routers/users.py` — Daily Summary endpoints and models | Settings API, generated clients, `utils.llm.daily_summary`, DB, FCM | Delete complete product |
| Same file — Mentor notification settings models/routes | `database.notifications` helpers; generated clients; no Mac caller | Delete |
| Same file — notification settings models/routes | Settings UI/automation and `database.users` | Delete after local settings GREEN |
| Same file — assistant settings models/routes | `SettingsSyncManager`, `database.users`, generated contracts | Delete after local settings GREEN |
| Same file — AI Profile models/routes | Mac PATCH, generated contracts, `database.users` | Delete after local profile GREEN |
| `backend/database/users.py` — notification/assistant/profile helpers | Above routes only; `update_channel` is also a top-level user field | Delete exclusive helpers/fields; preserve `database.desktop_update_channels` and public update-policy machinery |
| `backend/database/notifications.py` — Daily Summary and Mentor helpers | Daily Summary routes/job/tool, Mentor routes | Delete exclusive functions/cache key; preserve token/timezone helpers only if a surviving caller remains |
| `backend/database/daily_summaries.py` | Daily Summary routes/job only | Delete |
| `backend/database/redis_db.py` — `try_acquire_daily_summary_lock`, credit-limit sent helpers | Daily Summary job/routes and generated credit push | Delete exact helpers; preserve unrelated Redis API |
| `backend/utils/llm/daily_summary.py`, `models/daily_summary_payload.py` | Daily Summary routes/job; model config/usage/docs | Delete |
| `backend/utils/retrieval/tools/notification_settings_tools.py` — `manage_daily_summary_tool` | `backend/utils/retrieval/tools/__init__.py`, `backend/utils/retrieval/agentic.py`, Chat/LangSmith prompt text | Delete exact tool/registrations/prompt guidance |
| `backend/utils/llm/proactive_notification.py` | No production caller at pinned baseline; tests and `model_config`, gateway overrides, endpoint inventory | Delete residue; no replacement |
| `backend/utils/llm/notifications.py` — purchase/credit generators and shared Memory reader | `backend/utils/notifications.py`; static silent generator also lives here | Delete model-backed purchase/credit functions and model route while retaining/moving the static silent nudge without a model dependency |
| `backend/utils/notifications.py` — personalized purchase/credit functions and shared generic send helpers | Deleted-call candidates: `backend/routers/payment.py`, `backend/routers/listen/runtime.py`, Daily Summary job. Current generic callers also include `backend/routers/notifications.py`, `backend/routers/users.py` training notification, `backend/utils/conversations/process_conversation.py`, `backend/utils/chat.py`, `backend/utils/wrapped/generate_2025.py`, `backend/utils/retrieval/tool_services/action_items.py`, `backend/utils/retrieval/tools/action_item_tools.py`, and `backend/utils/fair_use.py`. | Delete exact personalized functions/imports; preserve generic send/static silent nudge and every caller still retained at execution HEAD; hand final FCM cleanup to S-23 |
| `backend/routers/payment.py` paid-checkout notification branch | Personalized purchase function | Delete notification branch; preserve subscription reconciliation/status |
| `backend/routers/listen/runtime.py` credit-push calls | Two calls; authoritative `FreemiumThresholdReachedEvent` is separate; static silent nudge is separate | Delete credit-push imports/calls, preserve event and static nudge |
| `backend/modal/job.py`, `backend/utils/other/jobs.py`, `backend/utils/other/notifications.py` | Notifications job entry -> wearable + Daily Summary cron only in current checkout | Delete after retained-caller proof |
| `backend/modal/Dockerfile.notifications_job`, `.github/workflows/gcp_notifications_job.yml` | `runtime_images.json`, runtime env, checks, concurrency, pre-push, workflow contracts | Delete and update all registries |
| `backend/runtime_images.json`, `backend/deploy/runtime_env.yaml`, `backend/scripts/validate-backend-runtime-env.py` | Deployment/render/tests | Remove only `notifications-job` entries and validation branches |
| `.github/checks-manifest.yaml`, `.github/scripts/check-deployment-concurrency.py`, `scripts/pre-push`, backend unit workflow filters, `backend/testing/workflow_contracts.json` | CI/push contract | Remove exact deleted-workflow/job references; preserve shared checks |
| `backend/utils/llm/model_config.py`, `backend/utils/llm/usage_tracker.py`, `backend/llm_gateway/config/generated_route_overrides.yaml`, `backend/docs/llm/model_endpoint_inventory.yaml`, `backend/utils/llm/ARCHITECTURE.md` | LLM routing/accounting/docs | Remove `daily_summary`, `proactive_notification`, and `notifications` entries only after caller deletion |
| `backend/routers/desktop_deprecated.py`, `backend/route_policy_legacy_missing_routes.txt` | 410 compatibility inventory for several S-14 routes | Delete S-14 route entries; do not leave 410 shells |
| `docs/api-reference/app-client-openapi.json`, `desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift` | Generated app-client contract | Regenerate after route deletion; never hand-edit |
| Backend tests matching Daily Summary, notifications job, mentor/proactive notification, assistant/profile/settings routes | Mix of exclusive S-14 tests and retained generic-notification tests | Delete exclusive tests; adapt retained sibling tests; add route-retirement and retained-boundary behavioral tests |

A repository-wide literal scan outside `bootstrap-scaffold/` found no additional Apple production caller for `assistant-settings`, `notification-settings`, `ai-profile`, `daily-summary`, or `focus-sessions`. The remaining hits are the backend registrations/helpers/tests above, `docs/api-reference/app-client-openapi.json`, generated Mac bindings, and Windows sources/audit documents. Windows is explicitly out of scope; generated Mac/OpenAPI residue is deleted by regeneration, not by hand. Rerun this same scan after predecessor integration because a new caller is a stop condition, not permission to preserve a retired route.

### Exact current test dependency inventory

| Current tests | Current dependency | Required treatment |
|---|---|---|
| `desktop/macos/Desktop/Tests/FocusStorageSessionIdTests.swift`, `HomeAskFocusPolicyTests.swift` | Backend/string Focus identity and Home Focus presentation | Replace identity assumptions; retain Home policy behavior |
| `desktop/macos/Desktop/Tests/HomeSuggestionsStoreTests.swift` | Home composer, cache, failure/thin/owner behavior | Adapt to local generator and no onboarding parameter |
| `desktop/macos/Desktop/Tests/APIClientRoutingTests.swift`, `APIClientAssistantSettingsTests.swift`, `SettingsResponseTests.swift` | Retired Daily Summary/assistant/notification client methods and DTOs | Delete only retired route assertions; retain neighboring API routing coverage |
| `desktop/macos/Desktop/Tests/PersistedCaptureLaunchPolicyTests.swift`, `MemoryAssistantTelemetryTests.swift` | `SettingsSyncManager.applyRemoteSettings` and sync notification | Replace with local reconciliation behavior; retain capture/Memory telemetry invariants |
| `desktop/macos/Desktop/Tests/TopNavigationBarLayoutTests.swift`, `DesktopAutomationSecondaryActionTests.swift` | Current three-item nav and 1–5 shortcut map | Adapt to IR-659/681 behavior |
| `desktop/macos/Desktop/Tests/NotificationMetadataEvictionTests.swift`, `NotificationRegistrationRepairTests.swift`, `UntrustedNotificationContextTests.swift`, `UserNotificationCallbackBridgeTests.swift` | Generic local notification safety | Retain; add S-14 continuity coverage rather than rewriting unrelated expectations |
| `backend/testing/e2e/test_boundary_contract_compatibility.py`, `backend/tests/unit/test_desktop_migration.py` | Focus route/wire compatibility and server settings helpers | Delete exact retired cases; preserve unrelated migration coverage |
| `backend/testing/e2e/test_user_auth_profile.py`, `backend/tests/unit/test_firestore_cache.py` | `/v1/users/ai-profile` and its Firestore cache | Delete profile-specific cases after local Profile GREEN |
| `backend/tests/unit/test_assistant_settings_response_models.py` | Assistant settings schema/OpenAPI | Delete with the retired route |
| `backend/tests/unit/test_daily_notification_timezone_selection.py`, `test_daily_summary_empty_overview.py`, `test_daily_summary_hour_midnight.py`, `test_daily_summary_race_condition.py`, `test_daily_summary_regenerate.py`, `test_daily_summary_zero_coordinate_locations.py`, `test_other_notifications_async_boundaries.py` | Daily Summary and Notifications cron | Delete if wholly exclusive; split any independently retained notification assertion first |
| `backend/tests/unit/test_lock_bypass_fixes.py`, `test_storage_fanout_limits.py`, `test_notification_database_sync_boundaries.py`, `test_clean_sweep_migrations.py` | Mixed files containing Daily Summary sections | Remove only exact Daily Summary tests/import stubs; retain other incident guards |
| `backend/tests/unit/test_notifications_job_import.py`, `test_notifications_job_orchestrator.py` | Notifications job entry/orchestrator | Delete with job |
| `backend/tests/unit/test_backend_runtime_env_validator.py`, `test_render_backend_runtime_env.py`, `test_runtime_image_contracts.py`, `test_workflow_contracts.py`, `test_preflight_cloud_run_deploy.py` | Runtime/job registries and workflow contract | Adapt exact `notifications-job` expectations; retain every other runtime |
| `backend/tests/unit/test_proactive_notification_language.py`, proactive portions of `test_insight_date_grounding.py`, `backend/tests/integration/test_qos_real_llm.py`, `test_qos_live_cp9.py` | Dead `proactive_notification` model purpose | Delete exact exclusive tests/cases and model-purpose expectations |
| `backend/tests/unit/test_firestore_read_ops_cache.py`, `test_prompt_cache_optimization.py`, `test_prompt_cache_integration.py` | Mentor frequency helper/cache or import stubs | Remove Mentor-specific sections/stubs; retain other cache/prompt tests |
| `backend/tests/unit/test_credit_limit_notification_async.py`, generated-copy portions of `test_notification_async_boundaries.py`, `test_notification_token_cleanup.py` | GPT credit/purchase functions and imports | Delete/adapt exact generated-copy cases; retain generic token/send behavior |
| `backend/tests/unit/test_listen_persistence.py`, payment tests including `test_payment_promotion_codes.py` | Call-site stubs for generated pushes plus retained state | Remove notification stubs and assert retained event/reconciliation behavior |
| `backend/tests/unit/test_silent_notification_async.py` | Separately static silent-user nudge | Retain and prove it no longer imports the `notifications` model route |

## 8. Behavior classification

| Classification | Surface | Required treatment |
|---|---|---|
| KEEP AS IS | Focus Gemini judgment prompt/schema, delay/cooldown, exclusions, notification/glow semantics | Characterize before persistence edits; only replace context sources with predecessor-local equivalents. |
| KEEP AS IS | Insight two-phase SQL/screenshot Gemini flow, up-to-seven tool calls, cadence/confidence/dedup/exclusions | Keep compute transient and direct through the guarded Gemini proxy. |
| KEEP AS IS | Live Suggestions assistant, dwell/cooldown/daily budget, floating card, telemetry | Protect from settings/model cleanup; it is not stored Insight and not cloud Mentor. |
| KEEP AS IS | `NotificationService` local throttle/snooze/functional-notification behavior | Remove backend sync only. Keep exact intervals and owner-scoped state. |
| KEEP AS IS | Local Chat journal origin `proactive_notification` | Preserve S-11 single-writer admission and notification provenance. |
| KEEP AS IS | AI Profile prompt intent, two-stage generation, daily cadence, five-profile consolidation, settings/onboarding consumers | Change sources and authority, not product meaning. |
| KEEP AS IS | Capture authority in `CaptureListeningLogic`/AppState/plugin health | Focus consumes this shared derivation. |
| KEEP AS IS | Stable/Beta local Sparkle behavior and unauthenticated desktop update-policy service | Remove only its coupling to assistant settings. |
| ADAPT | `FocusAssistant` + `ProactiveStorage` + `FocusStorage` | One owner-fenced GRDB write, durable projection, local-only mutation/refresh/retention. |
| ADAPT | `FocusSessionRecord`/`focus_sessions` current schema | Forward-migrate away sync columns/index while preserving local IDs and rows. |
| ADAPT | `InsightStorage` | Projection/query adapter over `tips` rows, not persistence; use stable local IDs. |
| ADAPT | `InsightAssistant` | Commit tagged Memory once before UI/notification; no backend/cache fan-out. |
| ADAPT | `AIUserProfileService`/`ai_user_profiles` | Local context, owner snapshot, local commit; remove `backendSynced`. |
| ADAPT | Home suggestions generator/composer | Local bounded inputs, no onboarding input, same per-owner/day policy. |
| ADAPT | Assistant/notification Settings UI and automation | Read/write local owners directly and reconcile runtime immediately. |
| ADAPT | Top nav, hub, Home actions, automation, shortcuts | One typed Insights hub; exact local Insight request; final shortcut map. |
| ADAPT | Payment/listen behavior around removed generated pushes | Preserve purchase/quota state and listen threshold event; remove only generated FCM copy. |
| DELETE | UserDefaults `omi.focus.sessions` and `omi.advice.history` | Remove after migration/projection tests; no import into a second authority. GRDB rows already hold authoritative retained data. |
| DELETE | Focus duplicate Memory and backend Memory writes, sync status, backend IDs | Remove after Cycle 1 GREEN. |
| DELETE | Insight backend Memory create/read/update/delete and cache fan-out | Remove after Cycles 4–5 GREEN. |
| DELETE | Server Focus routes/models/database; AI Profile; assistant/notification/Mentor settings routes/helpers | Remove after corresponding Mac callers are green. |
| DELETE | Daily Summary UI/API/storage/generation/tool/deep-link/settings/search/job paths | Complete product deletion, not a hidden/disabled shell. |
| DELETE | Cloud proactive notification model and exclusive config/tests/docs | It has no production caller at the pinned baseline. |
| DELETE | GPT purchase/credit notification model, Memory reads, credit Redis dedupe, callers | Do not substitute another model or local-memory personalization. |
| DELETE | `notifications-job` entry/image/workflow/runtime/deploy control plane | Repository deletion in Cycle 13; live deletion is Section 16. |
| SIMPLIFY AFTER | `FocusStorage.refreshFromBackend` | Rename to truthful local refresh only after every caller moves. |
| SIMPLIFY AFTER | Orphan Focus API response DTOs and `GeminiService` typealias | Delete after compile/residue proof; no compatibility aliases. |
| SIMPLIFY AFTER | `SidebarNavItem.focus`/`.insight` raw routes | Replace with one accurately named Insights-hub route and typed segment; delete standalone raw case. |
| SIMPLIFY AFTER | Old GRDB sync column declarations in historical migrations | Keep historical steps solely for upgrade replay; current schema and models must not expose them. |
| OUT OF SCOPE / DEFERRED | S-10 Conversation storage/detail/cascade implementation | Consume only. |
| OUT OF SCOPE / DEFERRED | S-12 general Memory CRUD/vector/lifecycle implementation | Consume only; S-14 owns Insight semantics over `tips`. |
| OUT OF SCOPE / DEFERRED | S-13 task/goal authority and automatic Task admission implementation | Protect and consume only. |
| OUT OF SCOPE / DEFERRED | S-15 Rewind/screenshot authority implementation | Consume only. |
| OUT OF SCOPE / DEFERRED | Generic FCM token/router/infrastructure deletion | S-23; retain proven callers now. |
| OUT OF SCOPE / DEFERRED | Broader shell/release cleanup | S-21 and release slices, except exact IR-659/679/680/681 routes. |
| OUT OF SCOPE / DEFERRED | Windows | Explicitly ignored by the deletion program. |

## 9. Retained behavioral invariants

1. **One authority per private product:** no event is durably represented in both GRDB/UserDefaults/cloud, and no read falls back across authorities.
2. **Persistence before publication:** Focus, Insight, and Profile results become visible/notifiable only after the owner-local transaction commits. A failed commit produces no phantom card or notification.
3. **Owner generation, not only owner string:** a late load/Gemini/write/mutation/navigation result from an invalidated authorization generation is dropped without touching the new owner’s state.
4. **Owner switch is projection cleanup, not data deletion:** clear in-memory rows, current selections, timers, loading/error state, pending navigation, and task generations; retain the prior owner’s database directory.
5. **Focus retention:** current-owner `focus_sessions` contains at most 500 rows and no rows older than 30 days after insert, startup, or refresh. UI stays today/recent rather than exposing a 30-day browser.
6. **Focus time math:** the newest period may extend to now; no earlier period extends beyond its following transition. Delay/cooldown countdown may tick each second; normal totals must not.
7. **Truthful monitoring:** Focus disabled outranks capture state; enabled + canonical active capture says Monitoring; canonical inactive says Capture off; blocked/permission-broken says Capture blocked.
8. **Exact Focus presentation/mutation:** the restored analyzed card remains the same unqualified card: headline `Focused` or `Distracted`, focus-rate leading value/`FOCUS RATE`, and optional app subtext—do not add a “live/current/restored” qualifier. Empty history remains `No sessions yet` plus `Focus sessions appear here as you work.\nEnable Focus monitoring in Settings to begin.` and its visible `Refresh`. Delete/clear are transactional and rollback UI on failure. Refresh is local and both visible refresh controls remain.
9. **Insight authority/query split:** all accepted Insights remain as `tips` rows; the page window is newest 100 only. “100” is a presentation bound, never a retention policy.
10. **Exact Insight mutation scope:** one-row actions resolve a current-owner local ID and confirm `tips`; bulk actions query all current-owner `tips` rows inside one transaction. Ordinary Memories are never mutated.
11. **Open even if mark-read fails:** detail presentation does not wait on mutation; failed read state is restored and the error remains visible. Empty Insights remains `No insights yet`, `Proactive insights from Omi will appear here as you work.\nEnable the Insight Assistant to start seeing them.`, and `Settings → Proactive Assistants`.
12. **Show Dismissed remains meaningful:** dismiss changes persistent local state but does not delete; notification X/time-out changes no Insight state.
13. **AI Profile history and facts:** generation remains factual, bounded, two-stage, daily, and informed by up to five prior profiles. Local editing, regeneration, deletion, onboarding exploration, and every current consumer remain functional.
14. **Home question policy:** one universal first question plus no more than two sanitized personalized/static questions; per-owner/day successful result including empty; transient failure retries; stale-owner result drops; tap prefills without auto-send.
15. **Notification policy:** exact local master/frequency and per-assistant controls survive restart; 0–5 semantics do not drift; snooze and functional exception behavior stay intact.
16. **Live Suggestions separation:** it does not create an Insight row or cloud Mentor record. Its floating card and telemetry remain bounded/local.
17. **Chat continuity:** notification journal admission uses the S-11 writer and origin `proactive_notification`; click opens only if the notification owner is current.
18. **Navigation contract:** one plain Insights top-level item, default Insights segment, Focus segment retained, no standalone Insight route/badge, exact Home/local-record navigation, and the final keyboard/automation map.
19. **Quota truth survives copy deletion:** `FreemiumThresholdReachedEvent` and local handling remain; subscription reconciliation, usage accounting, paywall/upgrade UI, and static silent-user nudge remain.
20. **No compatibility shell:** deleted routes are absent, not 410 aliases; deleted Swift names do not survive as deprecated aliases; deleted job has no placeholder workflow.

## 10. Target authority and ownership model

| Data / behavior | Sole durable owner | Read model / mutation seam | Compute / presentation | Explicitly forbidden |
|---|---|---|---|---|
| Focus sessions | Owner-scoped GRDB `focus_sessions` in predecessor per-owner database directory | `ProactiveStorage` transactional commands plus a `FocusStorage` main-actor projection | `FocusAssistant` + Gemini; Focus page, glow, local notifications | Focus Memory copy, backend Memory, Focus API, UserDefaults history, sync IDs/outbox |
| Insights | S-12 owner-scoped GRDB Memory row tagged `tips` | S-14 domain adapter over S-12 Memory query/transaction commands: newest-100 read, exact ID, insert, read/dismiss/delete, all-tagged read/clear | `InsightAssistant` + Gemini; Insights page/Home/card | `StoredInsight` persisted cache, backend `/v3/memories`, second Insight table, 100-row deletion cap |
| AI Profile | Owner-scoped GRDB `ai_user_profiles` | `AIUserProfileService` local CRUD/history; a bounded local context reader composed from S-10/S-12/S-13/S-11 | Two-stage Gemini; Settings and assistant consumers | Firestore `ai_user_profile`, API sync, cache, backendSynced/outbox |
| Assistant controls | Local UserDefaults classes already owned by each assistant | Direct setters plus one local runtime-reconciliation signal when required | Settings UI / plugin | `SettingsSyncManager`, `assistant_settings`, server startup overwrite |
| Notification master/frequency | `NotificationService` UserDefaults keys | Local Settings UI and local automation actions | `NotificationService` throttle/delivery | `/notification-settings`, remote hydration, server migration push |
| Home questions | Per-owner/day local UserDefaults cache in `HomeSuggestionsStore` | Snapshot-bound local context reader | Gemini + ask-bar chips | Server product-data reads, onboarding suggestion input, cross-owner cache |
| Hub navigation | Main-window navigation state plus a proposed **new** typed `InsightsHubSegment` and owner-bound pending Insight request | `DesktopHomeView` consumes requests and exact local IDs | Top bar/Home/automation/keyboard | Standalone `.insight` page route, raw integer segment requests, stale-owner fallback |
| Proactive Chat continuity | S-11 local kernel journal | Existing `recordJournalExchange`/final S-11 equivalent | Floating card/native notification/Chat | Cloud Mentor history, second Chat store, mutation on dismiss |
| Purchase/quota truth | Retained backend billing/entitlement/quota state | Existing payment reconciliation and listen `FreemiumThresholdReachedEvent` | Existing Mac paywall/usage UI and fixed local messaging where required | GPT copy, Memory personalization, credit-push Redis dedupe |

The proposed `InsightsHubSegment`/pending request is an implementation name, not a claim that it exists in the pinned checkout. Put it in an existing MainWindow source or a clearly marked **new** `Desktop/Sources/MainWindow/InsightsHubNavigation.swift`; it stores only `segment`, current-owner authorization provenance, and a stable local Insight ID. It must never store a copied Insight payload.

## 11. Ordered RED/GREEN TDD cycles

### Cycle 1 — Focus single local admission and owner fencing

- **Behavioral RED:** Through injected Focus analysis/persistence seams, start an owner-A analysis, switch authorization generation before Gemini returns, and prove no row/UI/card is published. For a current owner, prove one accepted transition creates exactly one GRDB Focus row, survives a new store instance, and a forced insert failure creates no row/UI/notification. Seed `omi.focus.sessions` and assert it is removed without importing a second history. Assert zero Memory/backend calls.
- **Why it fails now:** `FocusAssistant` uses owner-string guards, writes Focus plus local Memory plus backend Memory, retains sync fields, and publishes through a UserDefaults-backed process-global projection.
- **Minimum GREEN:** Capture one authorization snapshot before analysis; revalidate it after every await and inside the GRDB write. Commit one `FocusSessionRecord`, then publish `FocusStorage` and notification/glow. Load the projection only from current-owner GRDB. Remove `saveFocusToMemoriesTable`, `syncFocusSessionToBackend`, sync marking, and clear the obsolete UserDefaults history without importing it.
- **Retained behavior:** Existing Gemini schema/prompt, context ordering, excluded apps, analysis delay/cooldown, confidence/status transition logic, event callback, glow and local notification content.
- **Expected code:** `FocusAssistant.swift`, `FocusStorage.swift`, `ProactiveModels.swift`, `ProactiveStorage.swift`, `RewindDatabase.swift`; consume final S-12/S-13/S-15 context seams. Add a forward schema migration; do not alter `createFocusSessions`.
- **Expected tests:** **new** `Desktop/Tests/FocusLocalAuthorityTests.swift`; **new** `Desktop/Tests/S14LocalAuthorityMigrationTests.swift`; adapt `FocusStorageSessionIdTests.swift` away from backend/string IDs.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter FocusLocalAuthorityTests` and `--filter S14LocalAuthorityMigrationTests`.
- **Deletion unlocked:** Focus Memory copy, cloud Memory write, sync retry/status methods, `backendId`/`backendSynced` in current model/schema, `omi.focus.sessions` read/write.
- **Stop condition:** S-12/S-13/S-15 local context or owner snapshot cannot be consumed without reintroducing a cloud read or mutable-owner lookup after an await.

### Cycle 2 — Focus durable lifecycle, retention, and restart

- **Behavioral RED:** Seed current-owner rows including >30-day and >500 cases. Assert startup, refresh, and insert prune to newest 500 within 30 days; exact delete/clear persist across a reconstructed store; injected delete/clear failure restores the prior projection and exposes error; owner switch clears projections and late load/mutation results cannot publish. Assert newest interval extends to now and older intervals end at the next transition.
- **Why it fails now:** `deleteSession` selects local/backend behavior from string IDs and swallows failures, `clearAll` clears only cache, refresh is misleadingly named, retention is query-only, and owner changes do not fence every operation.
- **Minimum GREEN:** Add transactional exact delete, all-delete, and retention commands to `ProactiveStorage`; give `FocusStorage` stable local IDs, async result/error APIs, generation tokens, current-owner reload, and rollback/reload on mutation failure. Rename `refreshFromBackend` to truthful local refresh and move both visible callers.
- **Retained behavior:** Current status/app, delay/cooldown state, day stats, local IDs, and the two visible Refresh affordances.
- **Expected code:** `ProactiveStorage.swift`, `FocusStorage.swift`, `FocusPage.swift`, owner-change integration in `RuntimeOwnerIdentity` notification consumers.
- **Expected tests:** extend `FocusLocalAuthorityTests.swift`; **new** `Desktop/Tests/FocusLifecycleBehaviorTests.swift` with a real temporary GRDB pool and fault-injected command boundary.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter FocusLifecycleBehaviorTests`.
- **Deletion unlocked:** backend-ID delete branch, cache save/load/trim helpers, stale response DTOs once Cycle 3 compiles.
- **Stop condition:** retention would need to delete another owner’s directory, or exact rollback can be implemented only as a second in-memory authority.

### Cycle 3 — Focus truthful page and capture state

- **Behavioral RED:** Drive four monitoring states (disabled, enabled+active, enabled+inactive, enabled+blocked), today totals/recent rows, restored current card, exact empty copy, countdown behavior, and both refresh buttons. Assert no search, historical mode, top-distraction summary, or one-second normal-total updater remains.
- **Why it fails now:** `FocusPage.isMonitoring` checks only Focus enabled; page/view model still own search/all-time/top-distraction state; the storage/cache shape leaks remote-era presentation.
- **Minimum GREEN:** Derive a typed page state from `FocusAssistantSettings.isEnabled` plus canonical `CaptureListeningLogic.captureStatus`/plugin health; keep today/recent only; preserve current restored card and exact empty strings; let only delay/cooldown use the existing timer.
- **Retained behavior:** Exact current Focus empty text, current state card, focused/distracted colors/icons, today totals, short recent list, delay/cooldown controls, both Refresh controls.
- **Expected code:** `FocusPage.swift`, `DesktopHomeView.swift` only to pass canonical `appState` if needed, and the existing capture-status owner only if one shared extension is necessary.
- **Expected tests:** **new** `Desktop/Tests/FocusPageBehaviorTests.swift`; adapt `HomeAskFocusPolicyTests.swift` only if shared status types move.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter FocusPageBehaviorTests`.
- **Deletion unlocked:** `showHistorical`, Focus search state, top-distraction presentation, stale “Monitoring” boolean, orphan Focus network DTOs/typealias.
- **Stop condition:** implementation duplicates capture truth rather than consuming the IR-515 owner, or exact current copy/card cannot be characterized before change.

### Cycle 4 — Insight single `tips` authority and newest-100 projection

- **Behavioral RED:** Against a temporary owner-local Memory database, generate one accepted Insight and assert exactly one `tips` row, no UserDefaults payload, no API call, and notification only after commit. Seed obsolete `omi.advice.history` data and assert it is removed without import. Seed 130 `tips` rows plus ordinary Memories; assert storage retains all 130 while the projection returns newest 100. Switch owner during analysis/load and assert no stale row/projection/card.
- **Why it fails now:** `InsightAssistant` writes local Memory, backend Memory, and `InsightStorage`; `InsightStorage` persists `omi.advice.history`, trims to 100, and initializes by reading the backend.
- **Minimum GREEN:** Use S-12’s transaction to insert the tagged record and return its stable local ID. Replace `InsightStorage` persistence with a main-actor projection/query adapter over S-12 Memory; clear the obsolete UserDefaults cache without importing it; load newest 100 with dismissed rows available to filtering; preserve all rows in the database. Capture one owner authorization for generation through publication.
- **Retained behavior:** Two-phase Advisor flow, up-to-seven SQL/tool calls, screenshot selection, prompt/schema, exclusions, confidence, dedup context, analytics, notification content, search/filter/detail fields.
- **Expected code:** `InsightAssistant.swift`, `InsightStorage.swift` (or a **new** `InsightHistoryStore.swift` projection), `InsightPage.swift`, S-12 Memory query/command implementation, `ProactiveModels.swift` only if obsolete extraction residue is identified.
- **Expected tests:** **new** `Desktop/Tests/InsightLocalAuthorityTests.swift`; use real local Memory records and injected Gemini/persistence boundaries.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter InsightLocalAuthorityTests`.
- **Deletion unlocked:** `syncInsightToBackend`, `StoredInsight(from: ServerMemory)`, `syncFromBackend`, `omi.advice.history`, `FirebaseCore` import in Insight storage, backend Memory read/create calls.
- **Stop condition:** S-12 does not expose tags/read/dismiss metadata transactionally, or S-14 would need a second table/cache to render Insights.

### Cycle 5 — Insight exact mutations and failure semantics

- **Behavioral RED:** Seed visible, dismissed, unread, filtered, and older-than-100 `tips` rows plus ordinary Memories. Verify exact delete, exact dismiss, detail-open/read, Mark All Read, and Clear All. Inject each transaction failure: the affected projection restores, error is visible, detail still opens for mark-read failure, and ordinary Memories remain unchanged. Verify stale-owner and missing-ID requests are rejected truthfully.
- **Why it fails now:** Mutations are optimistic cache changes followed by best-effort backend tasks; clear/mark-all operate on only cached rows; read mutation precedes detail selection; failures are logged only.
- **Minimum GREEN:** Resolve local ID + `tips` predicate under the current authorization. Run single-record and all-tagged mutations in one S-12 transaction, then refresh the newest-100 projection. Present detail immediately; on read failure restore unread and retain sheet/error. Reset selections/errors on owner change.
- **Retained behavior:** Search, category chips/counts, Show Dismissed, detail content, confirmation dialog, exact empty copy, unread count, row hover actions.
- **Expected code:** `InsightStorage.swift`/replacement, `InsightPage.swift`, S-12 tagged Memory command seam, later Home call seam.
- **Expected tests:** **new** `Desktop/Tests/InsightMutationBehaviorTests.swift`; extend `InsightLocalAuthorityTests.swift` for all-row scope.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter InsightMutationBehaviorTests`.
- **Deletion unlocked:** backend update/delete/bulk loops, cache rollback workarounds, recommendation-style local Later action.
- **Stop condition:** bulk commands enumerate only the current 100-row projection, or a mutation can target an untagged/other-owner Memory.

### Cycle 6 — AI Profile local inputs, output, history, and consumers

- **Behavioral RED:** With local S-10/S-12/S-13/S-11 fixtures, assert the generator reads at most 100 Memories, 50 Tasks, active Goals, 20 completed Conversations from seven days, 30 local journal messages, and up to five past profiles; makes two Gemini stages; commits locally before publishing; survives service restart; and drops a result after owner generation changes. Force each source unavailable/thin and a DB failure. Exercise edit, regeneration, delete, history, and onboarding exploration. Assert no profile HTTP call.
- **Why it fails now:** All five current inputs come from `APIClient`; local writes fire-and-forget PATCH to `/v1/users/ai-profile`; `backendSynced` remains in record/schema; authorization is not one generation-bound snapshot across the whole workflow.
- **Minimum GREEN:** Compose a bounded read-only local context source from integrated predecessor APIs under one snapshot; preserve source bounds and fail-soft partial context; run both Gemini stages; commit `AIUserProfileRecord` locally and only then publish. Forward-migrate away `backendSynced`; remove sync tasks. Keep the `AIUserProfileService` consumer API or migrate every in-tree consumer in the same change.
- **Retained behavior:** >24h cadence, factual prompt, stage-two consolidation, up to five prior profiles, current profile size behavior, 30-row Settings history, edit/delete/regenerate, exploration save, and all six current consumer families.
- **Expected code:** `AIUserProfileService.swift`, `RewindDatabase.swift`, `ChatPrompts.swift` schema annotations, current consumer files only if the method signature changes; delete `APIClient+ChatSessions.swift` profile DTO/method; backend profile route/helper/contracts later in this cycle.
- **Expected tests:** **new** `Desktop/Tests/AIUserProfileLocalAuthorityTests.swift`; extend `S14LocalAuthorityMigrationTests.swift`; backend **new** `tests/unit/test_s14_local_authority_route_retirement.py` mounts the app and asserts removed profile route is absent.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter AIUserProfileLocalAuthorityTests`; `cd backend && PYTHONPATH=. python -m pytest -q tests/unit/test_s14_local_authority_route_retirement.py`.
- **Deletion unlocked:** `syncAIUserProfile`, `AIUserProfileResponse`, local sync flag/index references, `/v1/users/ai-profile`, Firestore helper/cache, generated bindings/route-policy entries/tests.
- **Stop condition:** any consumer needs a backend profile fallback, or local journal/conversation reads require coupling the profile service to a mutable UI singleton.

### Cycle 7 — Home questions from bounded local context

- **Behavioral RED:** Generate owner-A questions from local Memories/Conversations/Tasks/Goals, then verify sanitization, universal-first, max two follow-ups, static top-up, owner/day cache, successful-empty hold, transient failure retry, next-day refresh, signed-out empty, and owner-switch result drop. Assert no server data client is invoked and no onboarding question participates.
- **Why it fails now:** `GeminiHomeSuggestionGenerator` calls four backend product-data APIs and `compose` accepts onboarding suggestions.
- **Minimum GREEN:** Replace the generator’s data fetches with S-10/S-12/S-13 bounded local readers under its existing snapshot; keep unavailable/thin/available classification; change composer to `compose(personalized:)`; migrate its sole production caller and tests.
- **Retained behavior:** Existing question prompt/schema, daily cache key/version unless a migration is required, 72-character sanitizer, universal question, static fallbacks, tap-to-prefill and no auto-send.
- **Expected code:** `HomeSuggestionsStore.swift`, `DashboardPage.swift` call site, integrated local context adapters.
- **Expected tests:** update `HomeSuggestionsStoreTests.swift` behaviorally; add no source-string-only substitute.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter HomeSuggestionsStoreTests`.
- **Deletion unlocked:** `APIClient.getMemories/getConversations/getActionItems/getGoals` calls from Home generator and onboarding compose parameter.
- **Stop condition:** local readers cannot distinguish failed from successfully empty context, because that would burn the daily slot incorrectly.

### Cycle 8 — Local assistant and notification settings without regressions

- **Behavioral RED:** In isolated UserDefaults, toggle shared, Focus, Task, Insight, Memory, Live Suggestions, master Notifications, and every 0–5 frequency level; reconstruct owners/services and assert persistence plus immediate runtime reconciliation. Assert no GET/PATCH occurs on sign-in, launch, activation, settings load, capture migration, or mutations. Characterize automatic Task/Memory extraction and Live Suggestions before/after. Verify update channel remains local and still triggers its existing updater behavior.
- **Why it fails now:** `SettingsSyncManager` pulls/pushes at all those lifecycle points; notification migration/settings/automation still call the server; server response can overwrite local capture/update channel and assistant fields.
- **Minimum GREEN:** Remove `SettingsSyncManager`; route UI directly to existing local settings classes; replace `.assistantSettingsDidSyncFromServer` reconciliation with an accurately named local signal/direct call only where runtime owners require it; make notification automation local; remove the backend push from the off-by-default migration. Decouple `UpdaterViewModel.updateChannel` from assistant settings without altering `getDesktopUpdatePolicy` or `backend/database/desktop_update_channels.py`.
- **Retained behavior:** Exact 0–5 intervals, master default behavior, opt-in frequency 0, snooze, functional exceptions, per-assistant controls, prompt/exclusion/cadence settings, screen-capture repair semantics, Stable/Beta behavior, Task direct admission, Memory direct admission, Live Suggestions gates.
- **Expected code:** settings classes, `NotificationService.swift`, `SettingsContentView+Assistants.swift`, `SettingsContentView+NotificationsPrivacy.swift`, `SettingsContentView+SettingsUpdates.swift`, `SettingsContentView+BillingHelpers.swift`, `DesktopHomeView.swift`, `OmiApp.swift`, `AuthService.swift`, `DesktopAutomationBridge.swift`, `APIClient+Settings.swift`; backend assistant/notification routes/helpers and generated contracts.
- **Expected tests:** **new** `Desktop/Tests/AssistantSettingsLocalAuthorityTests.swift`; adapt `PersistedCaptureLaunchPolicyTests.swift`, `APIClientAssistantSettingsTests.swift`, `SettingsResponseTests.swift`, `DesktopAutomationSecondaryActionTests.swift`; add removed-route cases to `test_s14_local_authority_route_retirement.py` and retained updater tests.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter AssistantSettingsLocalAuthorityTests`; `--filter PersistedCaptureLaunchPolicyTests`; backend route-retirement test.
- **Deletion unlocked:** `SettingsSyncManager.swift`, lifecycle calls/event, `get/updateAssistantSettings`, `get/updateNotificationSettings`, response DTOs, server routes/Firestore helpers/generated methods/tests, server notification migration push.
- **Stop condition:** a predecessor still expects `.assistantSettingsDidSyncFromServer`, update channel is accidentally removed rather than localized, or S-14 changes S-12/S-13 assistant behavior instead of only its settings path.

### Cycle 9 — Canonical Insights hub, Home actions, navigation, and shortcuts

- **Behavioral RED:** Assert four plain top items in order; top Insights opens default Insights segment with no badge; `navigate insight` and `navigate focus` choose correct segments of one hub; no standalone Insight page case exists; Home local Insight opens exact current-owner ID and marks read; X dismisses exact row; missing/stale owner surfaces unavailable; Focus Home row opens Focus segment. Assert ⌘1/2/3/4 and `navigate_via_shortcut` match, ⌘2 selects Memories, numbered Rewind is absent, ⌘⌥R and ⌘, remain.
- **Why it fails now:** top nav lacks Insights; raw cases 5/6 mount duplicate paths; Home resolves Insight handlers only against recommendations; segment is private integer state; shortcuts still target Conversations/Memories/Tasks/Rewind.
- **Minimum GREEN:** Replace raw Focus/Insight routes with one accurately named Insights hub plus typed segment/request; remove case 6; route Home/automation/commands through it; consume exact stable local IDs and authorization provenance; change Memory shortcut destination to `.memories`; remove Insight badge/status coupling.
- **Retained behavior:** Combined hub styling/default, direct page previews, Memory dropdown, Settings shortcut, global Rewind shortcut, Home question prefill, Task navigation owned by S-13.
- **Expected code:** `SidebarView.swift`, `DesktopTopBar.swift`, `DesktopHomeView.swift`, `MemoryHubDestination.swift`, `DashboardPage.swift`, `OmiApp.swift`, `DesktopAutomationBridge.swift`; optional **new** `MainWindow/InsightsHubNavigation.swift`.
- **Expected tests:** **new** `Desktop/Tests/InsightsHubNavigationTests.swift`; adapt `TopNavigationBarLayoutTests.swift`, `DesktopAutomationSecondaryActionTests.swift`, and Home composer/store tests; use real navigation reducer/store behavior, not only source strings.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter InsightsHubNavigationTests`; `--filter TopNavigationBarLayoutTests`; `--filter DesktopAutomationSecondaryActionTests`.
- **Deletion unlocked:** `.insight` standalone route, stale loading/badge state, raw integer segment requests, numbered Rewind shortcut, recommendation-only local Insight Later path.
- **Stop condition:** exact record navigation requires copying the Insight payload, a stale request silently opens another row, or S-10’s Memory hub cannot honor the new ⌘2 contract without coordination.

### Cycle 10 — Local proactive notification continuity; cloud Mentor/Profile setting residue deletion

- **Behavioral RED:** Present an owner-local Insight notification, assert journal admission once with origin `proactive_notification`, click opens the current owner’s local Chat context, and X/time-out leaves Insight read/dismiss/delete state unchanged. Switch owner before admission/click and assert rejection. Backend test imports the live app and asserts Mentor settings routes are absent; repository/model inventory has no `proactive_notification` route.
- **Why it fails now:** local continuity exists but lacks S-14 end-to-end Insight mutation proof; the dead Python proactive model and orphan Mentor setting remain in source/config/contracts.
- **Minimum GREEN:** Preserve/adapt the existing S-11 journal path and add owner-bound tests; delete `backend/utils/llm/proactive_notification.py`; remove its model config/gateway override/usage/docs/tests; delete Mentor GET/PATCH models/routes, `get/set_mentor_notification_frequency`, `mentor_frequency:<uid>` cache behavior, generated bindings and route-policy residue.
- **Retained behavior:** Mac Focus/Task/Memory/Insight/Live Suggestions, direct Gemini proxy, floating/native notification display, generic FCM pending S-23, local origin string and bounded telemetry.
- **Expected code:** `FloatingControlBarWindow.swift` only if S-11 interface requires adaptation; `NotificationService.swift`; Insight tests; backend files enumerated above; generated OpenAPI/Swift.
- **Expected tests:** **new** `Desktop/Tests/ProactiveNotificationContinuityTests.swift`; extend S-11 continuity tests where present; backend **new** `tests/unit/test_s14_notification_model_retirement.py`; delete exclusive `test_proactive_notification_language.py`/proactive portions of date-grounding and Mentor cache tests.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter ProactiveNotificationContinuityTests`; `cd desktop/macos && ./scripts/agent-logic-harness.sh`; backend focused retirement tests.
- **Deletion unlocked:** cloud proactive file/model/usage/config/docs/tests, Mentor setting route/model/helper/cache/generated contract.
- **Stop condition:** a newly discovered production caller invokes `evaluate_proactive_notification`, or notification Chat admission would bypass the S-11 single writer.

### Cycle 11 — Remove GPT purchase/credit push copy and preserve authoritative state

- **Behavioral RED:** Payment webhook success still reconciles the paid subscription but makes no personalized notification/model/Memory call. Listen initialization and threshold refresh still emit `FreemiumThresholdReachedEvent(remaining_seconds:action:)` and update credit state without generated FCM/Redis dedupe. The Mac’s existing listen-event handler sets the paywall/upgrade presentation. Static silent-user notification remains callable without the `notifications` model.
- **Why it fails now:** payment calls `send_subscription_paid_personalized_notification`; listen calls `send_credit_limit_notification`; both route through `utils.llm.notifications` Memory reads/model calls, and credit pushes use Redis sent-state.
- **Minimum GREEN:** Delete purchase notification branch and both listen credit-push calls/imports; delete generated-copy functions/Memory reader and `notifications` model/usage/config entries; delete only `has/set_credit_limit_notification_been_sent`. Keep payment truth, `FreemiumThresholdReachedEvent`, `AppState+ListenEvents`, Plan and Usage UI, and the static silent-user nudge in a non-model helper.
- **Retained behavior:** Billing/entitlement/quota calculations, Dodo/Stripe reconciliation currently retained elsewhere, plan/usage details, upgrade action, listen threshold event, local fixed UI, generic sends, static silent nudge.
- **Expected code:** `routers/payment.py`, `routers/listen/runtime.py`, `utils/notifications.py`, `utils/llm/notifications.py` (delete if static nudge is moved and no caller remains), `database/redis_db.py`, model config/usage/docs.
- **Expected tests:** **new** `backend/tests/unit/test_s14_notification_copy_retirement.py`; adapt payment and listen tests to assert structured state/no generated call; delete `test_credit_limit_notification_async.py` and exclusive cases in `test_notification_async_boundaries.py`; preserve/adapt `test_silent_notification_async.py`.
- **Focused verification:** `cd backend && PYTHONPATH=. python -m pytest -q tests/unit/test_s14_notification_copy_retirement.py tests/unit/test_silent_notification_async.py tests/unit/test_listen_persistence.py`.
- **Deletion unlocked:** `notifications` LLM route, subscription-notification usage feature, purchase/credit prompts, Firestore Memory read, credit Redis keys, webhook/listen notification callers.
- **Stop condition:** the threshold event is not consumed by the Mac at execution HEAD, or a removed helper also serves a retained non-generated notification caller.

### Cycle 12 — Delete Daily Summary as a complete product

- **Behavioral RED:** Settings behavior test proves Notifications controls remain but Daily Summary card/state/search are absent. Backend app test proves every Daily Summary route returns route-not-found while retained neighboring user settings remain registered. Agentic tool inventory contains no Daily Summary tool. Generated OpenAPI/Swift contain no Daily Summary route/model.
- **Why it fails now:** UI, API client, routes, Firestore collection, preference fields, Redis lock, LLM generation, retrieval tool, deep link, prompts, generated contracts, job path, and extensive tests remain.
- **Minimum GREEN:** Delete Settings Daily Summary view/state/helpers/load tuple/search items; delete all six route families (settings GET/PATCH/test; list; detail GET/DELETE; regenerate), models, DB, lock, LLM, tool registrations and Chat/LangSmith guidance; remove Daily Summary job functions while Cycle 13 removes the job wrapper.
- **Retained behavior:** Home daily questions, local Insights/Profile, notification controls, language/transcription/privacy settings, generic `NotificationMessage` if other callers remain, generic FCM pending S-23.
- **Expected code:** Settings files, `APIClient+Settings.swift`, `routers/users.py`, `database/daily_summaries.py`, exact functions in `database/notifications.py`/`redis_db.py`, `utils/llm/daily_summary.py`, `models/daily_summary_payload.py`, retrieval tool/agentic/prompt files, `utils/other/notifications.py`, model config/docs/contracts.
- **Expected tests:** extend `test_s14_local_authority_route_retirement.py`; **new** `Desktop/Tests/DailySummaryRetirementTests.swift`; delete exclusive Daily Summary unit tests and adapt shared tests that stub its module.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter DailySummaryRetirementTests`; backend route-retirement test plus route-policy/OpenAPI checks from Section 14.
- **Deletion unlocked:** entire Daily Summary UI/API/persistence/model/tool/deep-link/test/doc surface and job payload.
- **Stop condition:** a retained non-S-14 product imports Daily Summary storage/tool code, or generic shared notification/model types cannot be separated without another slice.

### Cycle 13 — Delete Notifications job/control plane and close residue

- **Behavioral RED:** Runtime-image/manifest tests fail while `notifications-job` remains expected, then pass only when the image/workflow/runtime/validator/check contracts no longer register it. Backend imports/tests prove retained generic notification/payment/listen paths load without the job modules. Repository residue searches are empty or explicitly classified.
- **Why it fails now:** entry point, Dockerfile, workflow, runtime image/env, validation branches, concurrency registration, pre-push/workflow filters, workflow contract, tests, and AGENTS service map still name the job.
- **Minimum GREEN:** Delete `backend/modal/job.py`, `Dockerfile.notifications_job`, job-only `utils.other.jobs`/`utils.other.notifications`, and `.github/workflows/gcp_notifications_job.yml`; remove exact registry/env/validator/concurrency/check/pre-push/workflow-contract references; update backend service documentation. Preserve shared generic primitives only with enumerated live callers.
- **Retained behavior:** Local task reminders, local proactive cards/native notifications, billing/account state, listen threshold/static nudge, Sentry/PostHog, generic FCM routes/helpers with surviving callers, memory-maintenance job and every other runtime image.
- **Expected code:** deployment/control-plane files listed in Section 7, `backend/AGENTS.md`, `backend/runtime_images.json`, `backend/deploy/runtime_env.yaml`, `.github/checks-manifest.yaml`, and exclusive tests/docs/contracts.
- **Expected tests:** delete `test_notifications_job_import.py`, `test_notifications_job_orchestrator.py`, Daily Summary cron tests; adapt runtime-env/concurrency/runtime-image/workflow-contract tests; **new** `backend/tests/unit/test_s14_notifications_job_retirement.py` only if it exercises manifest loaders rather than scraping strings.
- **Focused verification:** `make runtime-image-source-closure`; both runtime-env checks; backend focused runtime/config tests; full commands in Section 14.
- **Deletion unlocked:** no further S-14 repository deletion. This cycle hands live operational cleanup to Section 16 and later generic FCM cleanup to S-23.
- **Stop condition:** a registered scheduler/job/image still targets the deleted entrypoint, or a “shared” helper lacks a proven surviving production caller.

## 12. Cross-slice ownership and handoffs

| Slice / owner | S-14 consumes or changes | S-14 must not steal | Closure handoff |
|---|---|---|---|
| S-10 Conversations | Bounded owner-local recent conversation summaries and stable IDs; ⌘2 Memory destination coordination | Conversation schema, transcription finalization, detail/cascade deletion | Report exact local reader and final Memory hub shortcut behavior |
| S-11 Chat/Home | Local journal read/admission and Home without cloud Dashboard intelligence | Kernel/journal single-writer, general Home recommendation deletion | Provide notification-origin tests and exact Home Insight request seam |
| S-12 Memory | Tagged `tips` query/transaction operations and local profile/question context | General Memory storage/vector/lifecycle, automatic Memory write implementation | Prove S-14 adds no second Insight store; report tag/read/dismiss requirements |
| S-13 Tasks/Goals | Local task/goal reads; automatic Task direct admission protected | Task schema, candidates/staging deletion, Goal authority | Report bounds and no Suggested queue |
| S-15 Rewind/capture | Screenshot/context reader and canonical capture truth | Rewind indexing/retention/schema | Report Focus monitoring integration and no duplicate status owner |
| S-18/S-20 billing/quota | Structured retained plan/usage truth | Billing provider, entitlement/quota accounting | Report deletion of copy-only pushes and preserved `FreemiumThresholdReachedEvent` |
| S-21 shell cleanup | Exact S-14 top nav/hub/shortcut result | Broader shell/legacy navigation cleanup | Hand off final nav enum/routes after `.insight` removal |
| S-22 model inventory | Removal of `daily_summary`, `proactive_notification`, `notifications` routes | Remaining provider/model choices | Hand off regenerated model endpoint inventory |
| S-23 FCM | Generic FCM primitives and static nudge remain temporarily | Final token/router/FCM deletion | Hand off enumerated surviving generic callers and removed S-14 callers |
| S-25 jobs | Absence of Notifications job | Other scheduled jobs/runtime images | Hand off updated runtime registry/env/workflow contracts |
| S-08 export | Final local Focus/Insight/Profile/settings read boundaries | Export implementation | Hand off stable local readers and note Insight full-set vs newest-100 distinction |
| S-28 namespaces | Current table/key names after S-14 | Global rename/migration program | Hand off retained `focus_sessions`, `ai_user_profiles`, Home cache, notification keys |

Shared deletion rule: delete an exclusive helper in S-14 only after `rg` proves all callers are S-14-owned or already removed. Otherwise record the exact caller/file and leave the helper to its owning slice. Do not add a deprecated alias to ease slice ordering.

## 13. Exact repository residue-search strategy

Run these at entry, after each relevant GREEN, and at final closure. Every nonempty final hit must be labeled retained shared behavior, historical migration input, generated output awaiting regeneration, test fixture for an old-schema upgrade, or a defect. “Known residue” without one of those owners is not closure.

```bash
# Focus authority, caches, sync, APIs, and stale UI
rg -n 'omi\.focus\.sessions|saveFocusToMemoriesTable|syncFocusSessionToBackend|refreshFromBackend|FocusSessionResponse|FocusStatsResponse|typealias GeminiService' desktop/macos/Desktop desktop/macos/Desktop/Tests
rg -n '/v1/focus-sessions|/v1/focus-stats|include_router\(focus_sessions\.router\)|routers\.focus_sessions|database\.focus_sessions|models\.focus_session' backend docs desktop/macos
rg -n 'backendId|backendSynced|idx_focus_synced' desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/Focus desktop/macos/Desktop/Sources/Rewind/Core/ProactiveModels.swift desktop/macos/Desktop/Sources/Rewind/Core/ProactiveStorage.swift desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift desktop/macos/Desktop/Tests
rg -n 'showHistorical|topDistractions|Search focus|All Time' desktop/macos/Desktop/Sources/MainWindow/Pages/FocusPage.swift desktop/macos/Desktop/Tests

# Insight sole authority and action residue
rg -n 'omi\.advice\.history|StoredInsight\(from:|syncFromBackend|syncInsightToBackend|updateInsightOnBackend|deleteInsightOnBackend|markAllReadOnBackend' desktop/macos/Desktop desktop/macos/Desktop/Tests
rg -n 'tags: \["tips"\]|tags=\["tips"\]|"tips"' desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests
rg -n 'Later|recordPrimaryAction|recordTaskFeedback' desktop/macos/Desktop/Sources/MainWindow/Pages/DashboardPage.swift desktop/macos/Desktop/Sources/MainWindow/Dashboard desktop/macos/Desktop/Tests

# AI Profile server projection and local sync residue
rg -n '/v1/users/ai-profile|v1/users/ai-profile|syncAIUserProfile|AIUserProfileResponse|ai_user_profile|_USER_AI_PROFILE_CACHE' desktop/macos backend docs
rg -n 'backendSynced' desktop/macos/Desktop/Sources/ProactiveAssistants/Services/AIUserProfileService.swift desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift desktop/macos/Desktop/Tests
rg -n 'APIClient\.shared\.(getMemories|getActionItems|getGoals|getConversations|getMessages)' desktop/macos/Desktop/Sources/ProactiveAssistants/Services/AIUserProfileService.swift

# Home questions must be local and onboarding-independent
rg -n 'compose\(personalized:.*onboarding:|APIClient\.shared\.(getMemories|getConversations|getActionItems|getGoals)' desktop/macos/Desktop/Sources/MainWindow/Dashboard/HomeSuggestionsStore.swift desktop/macos/Desktop/Tests/HomeSuggestionsStoreTests.swift

# Assistant/notification settings and Daily Summary
rg -n 'SettingsSyncManager|assistantSettingsDidSyncFromServer|getAssistantSettings|updateAssistantSettings|getNotificationSettings|updateNotificationSettings' desktop/macos/Desktop desktop/macos/Desktop/Tests
rg -n '/v1/users/(assistant-settings|notification-settings|mentor-notification-settings)|v1/users/(assistant-settings|notification-settings|mentor-notification-settings)' backend desktop/macos docs
rg -n 'assistant_settings|notifications_enabled|notification_frequency|mentor_notification_frequency|mentor_frequency:' backend
rg -ni 'daily[-_ ]summar|daily summaries|summary time|day_summary|manage_daily_summary_tool' desktop/macos backend docs .github scripts

# Navigation and exact shortcuts
rg -n 'case insight|case focus|SidebarNavItem\.insight|SidebarNavItem\.focus|case 6:|FocusHubPage|navigate_via_shortcut|keyboardShortcut\("[1-5]"' desktop/macos/Desktop desktop/macos/Desktop/Tests
rg -n 'insightStorage|insightHistory|homeKnowsInsightCandidates|openKnowsRow|knowsDismissHandler|knowsLaterHandler' desktop/macos/Desktop/Sources/MainWindow/Pages/DashboardPage.swift

# Rejected backend model workloads and notification callers
rg -n 'proactive_notification|evaluate_proactive_notification|NotificationDraft|ValidationResult|RelevanceResult' backend docs .github
rg -n 'generate_notification_message|generate_credit_limit_notification|send_subscription_paid_personalized_notification|send_credit_limit_notification|credit_limit_notification_sent' backend
rg -n 'freemium_threshold_reached|FreemiumThresholdReachedEvent|send_silent_user_notification' backend desktop/macos

# Notifications job/control plane
rg -n 'notifications-job|notifications_job|gcp_notifications_job|Dockerfile\.notifications_job|backend/modal/job\.py' backend .github scripts Makefile docs
rg -n 'utils\.other\.jobs|utils\.other\.notifications|start_cron_notification_job|send_daily_notification|send_daily_summary_notification' backend
test ! -e backend/modal/job.py
test ! -e backend/modal/Dockerfile.notifications_job
test ! -e .github/workflows/gcp_notifications_job.yml

# Generated and route-policy contracts
rg -n '/v1/users/(ai-profile|assistant-settings|notification-settings|mentor-notification-settings|daily-summary-settings|daily-summaries)' docs/api-reference/app-client-openapi.json desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift backend/route_policy_legacy_missing_routes.txt backend/routers/desktop_deprecated.py

# Final diff/scope
git diff --check
git status --short
git diff --name-only origin/main...HEAD
```

Expected historical exceptions: old `createFocusSessions`/`createAIUserProfiles` migration bodies may still mention removed columns so a database created at an older version can replay and then upgrade. Only migration code and upgrade fixtures may retain those strings; current record types, queries, indexes, Chat schema annotations, and new-database final schema may not.

## 14. Focused and component verification commands

### Focused desktop tests

```bash
cd desktop/macos
xcrun swift test --package-path Desktop --filter FocusLocalAuthorityTests
xcrun swift test --package-path Desktop --filter FocusLifecycleBehaviorTests
xcrun swift test --package-path Desktop --filter FocusPageBehaviorTests
xcrun swift test --package-path Desktop --filter InsightLocalAuthorityTests
xcrun swift test --package-path Desktop --filter InsightMutationBehaviorTests
xcrun swift test --package-path Desktop --filter AIUserProfileLocalAuthorityTests
xcrun swift test --package-path Desktop --filter HomeSuggestionsStoreTests
xcrun swift test --package-path Desktop --filter AssistantSettingsLocalAuthorityTests
xcrun swift test --package-path Desktop --filter InsightsHubNavigationTests
xcrun swift test --package-path Desktop --filter ProactiveNotificationContinuityTests
xcrun swift test --package-path Desktop --filter S14LocalAuthorityMigrationTests
xcrun swift test --package-path Desktop --filter DailySummaryRetirementTests
./scripts/agent-logic-harness.sh
```

The named test filters above marked **new** in the cycles become valid only after those files are added to the existing `Desktop/Tests` target.

### Focused backend tests and contract regeneration

```bash
cd backend
PYTHONPATH=. python -m pytest -q \
  tests/unit/test_s14_local_authority_route_retirement.py \
  tests/unit/test_s14_notification_model_retirement.py \
  tests/unit/test_s14_notification_copy_retirement.py \
  tests/unit/test_s14_notifications_job_retirement.py \
  tests/unit/test_silent_notification_async.py \
  tests/unit/test_listen_persistence.py

scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
scripts/openapi_runner.sh scripts/route_policy_inventory.py \
  --manifest route_policy_manifest.yaml --check --enforce-missing-baseline
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
```

The four `test_s14_*` files are planned **new** tests. If implementation combines them, preserve the same behavioral coverage and update these commands in the PR before claiming closure.

### Runtime/deployment configuration checks

```bash
python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-workflows
python3 backend/scripts/validate-backend-runtime-env.py --env prod --check-workflows
make runtime-image-source-closure
```

There is intentionally no `make runtime-image-smoke SERVICE=notifications-job` after Cycle 13 because the service is deleted. Smoke every retained image selected by the changed manifest through the normal registry/CI contract.

### Component and repository gates

```bash
cd desktop/macos
xcrun swift build -c debug --package-path Desktop
./test.sh

cd ../../backend
bash test-preflight.sh
bash test.sh

cd ..
python3 bootstrap-scaffold/validate-requirements-ledger.py
make preflight
scripts/pr-preflight --suggest
git diff --check
```

Before a `fix:` PR body, declare the suggested failure class as required by `AGENTS.md`, write the PR body to a file, and run `scripts/pr-preflight --pr-body-file <file>`. This slice is broad product migration/deletion work; do not label it as a bug fix merely to avoid describing its authority change.

## 15. Named-bundle user-path acceptance

Never run or restart `/Applications/Omi.app` or `Omi Beta.app`. Use one isolated named bundle and its isolated database:

```bash
cd desktop/macos
OMI_APP_NAME=omi-s14-local OMI_SKIP_TUNNEL=1 ./run.sh --full
./scripts/omi-macos-dev doctor
./scripts/omi-ctl wait-ready
./scripts/omi-ctl health
./scripts/omi-ctl screens
./scripts/omi-ctl state
```

Acceptance must exercise production behavior, not synthetic persistence alone:

1. **Owner A / Focus:** enable capture and Focus, produce a genuine focused→distracted→focused sequence from screen activity, observe current card/glow/notification, then inspect today totals/recent rows. Delete one row, refresh from both visible affordances, and clear all. Force capture off and blocked states and verify exact status labels.
2. **Focus restart/offline:** populate rows, run `./scripts/omi-ctl action quit_and_reopen`, wait with fresh `omi-ctl` calls, and prove rows/current math survive. Relaunch the same named bundle with cached auth and an unavailable product-data backend (`OMI_SKIP_BACKEND=1` plus a controlled unreachable `OMI_DESKTOP_API_URL`) and prove local Focus history/actions still work; Gemini-dependent new generation may truthfully fail.
3. **Owner A / Insights:** allow the real Insight assistant to produce a tagged result, open it from the hub and Home, verify read state, dismiss/Show Dismissed, delete, Mark All Read, and Clear All without altering an ordinary Memory. Confirm the exact empty copy when empty.
4. **Insight card / Chat:** generate another Insight notification, click it, verify the local Chat timeline contains one admitted assistant message with the notification context, then generate one and let it time out/X-dismiss; verify the Insight row did not mutate.
5. **AI Profile:** in Settings Advanced generate a profile from local data, edit it, regenerate, inspect prior history, delete one, restart, and verify surviving history. Exercise onboarding file exploration in a clean named profile if that surface remains at execution HEAD.
6. **Home questions:** verify universal + no more than two local-context questions, tap to prefill without sending, revisit same day without regeneration, and exercise successful-thin/failure behavior through the test seam.
7. **Settings:** toggle master notifications and all 0–5 levels plus Live Suggestions/Focus/Task/Insight/Memory controls. Restart and verify persistence. Use adapted local actions:

   ```bash
   ./scripts/omi-ctl action settings_notifications_snapshot
   ./scripts/omi-ctl action set_notification_settings enabled=true frequency=3
   ./scripts/omi-ctl action settings_notifications_snapshot
   ```

8. **Navigation/shortcuts:** verify top labels and no badge; `omi-ctl navigate insight`, `omi-ctl navigate focus`, Home exact-record routing, and the adapted `navigate_via_shortcut` actions for 1–4/comma. Verify ⌘2 opens Memory with Memories selected, ⌘4 opens Insights, ⌘5 has no numbered Rewind command, ⌘⌥R still opens Rewind, and ⌘, opens Settings.
9. **Owner B and late work:** sign out/in through the named app with a second development account. Before switching, hold load/Gemini/mutation completions at injected test seams. Prove B sees none of A’s Focus/Insights/Profile/Home/nav state and released A completions do not publish. Switch back to A and prove A’s local database was retained.
10. **No hidden backend authority:** obtain the bundle log with `./scripts/omi-ctl log-path` and search it for the retired route strings during all paths. No successful/attempted private-product call may appear. Record screenshots/log paths/test evidence in the PR without exposing private content.

Because this slice changes a Chat write path, run the named-bundle continuity gate after the above:

```bash
./scripts/agent-continuity-gauntlet.sh --suite continuity --bundle-id com.omi.omi-s14-local
./scripts/check-gauntlet-evidence-at-head.sh
```

## 16. Repository closure versus live operational closure

### Repository closure required in the implementation PR

- all Mac callers use local authorities and all retained tests/component gates are green;
- removed routes are absent from the FastAPI app, route policy, OpenAPI, generated Swift, and deprecated-route shell;
- removed model purposes/features/config/docs have no production import;
- `notifications-job` is absent from source, Dockerfile, workflow, runtime image registry, runtime env, validators, checks, pre-push, workflow contracts, tests, and service-map docs;
- historical GRDB upgrade migrations are tested and final schemas contain no active sync columns/indexes;
- residue searches are empty or classified;
- user-facing product direction is updated in `PRODUCT.md`; `backend/AGENTS.md` service map and relevant desktop guidance move with changed boundaries; add one valid JSON fragment under `desktop/macos/changelog/unreleased/` for the user-visible change.

### Live operational closure — separate authorization and evidence

The implementation task must not mutate live infrastructure or user data without new explicit authorization. Once authorized, inventory before deletion:

```bash
S14_PROJECT_ID="$(gcloud config get-value project)"
test -n "$S14_PROJECT_ID"
gcloud run jobs describe notifications-job --project "$S14_PROJECT_ID" --region us-central1 --format=json
gcloud scheduler jobs list --project "$S14_PROJECT_ID" --location us-central1 --format=json
gcloud container images list-tags "gcr.io/$S14_PROJECT_ID/notifications-job" --format=json
```

Then a named operator must separately close and record:

- the live `notifications-job` in each environment, every scheduler that invokes it, image tags/retention, and job-only secret/env bindings;
- Firestore collection `users/{uid}/focus_sessions/{session_id}`, user fields `ai_user_profile`, `assistant_settings`, `notifications_enabled`, `notification_frequency`, `mentor_notification_frequency`, `daily_summary_enabled`, `daily_summary_hour_local`, and subcollection `users/{uid}/daily_summaries/{summary_id}` under an approved data-deletion policy;
- cloud Memory rows tagged `focus` or `tips`, coordinated with S-12’s cloud-Memory retirement so a mixed collection is never mass-deleted by an unsafe S-14-only query;
- in-process Mentor cache keys `mentor_frequency:<uid>` by deployment retirement rather than speculative external deletion;
- Redis keys `users:<uid>:credit_limit_notification_sent` and `users:<uid>:daily_summary_lock:<date>` under an approved bounded cleanup;
- alerting/dashboards/runbooks that still name the job or rejected products.

Do not guess scheduler names or Secret Manager resources from repository labels. The live inventory output is the authority. Repository closure may be merged while live cleanup remains an explicitly owned operational follow-up, but the product must not keep calling the retired surfaces during that interval. Incident issues close only on live evidence.

## 17. Risks, gates, and explicit stop points

| Risk | Gate / mitigation | Stop when |
|---|---|---|
| Predecessor plans are not integrated at planning baseline | Mandatory execution rebase and full inventory; consume final seams only | A cycle would recreate S-10/S-12/S-13/S-15 behavior or add a cloud-shaped adapter |
| Owner leakage through late async work | Snapshot/generation on reads, compute, commit, publish, mutation, navigation; two-owner tests | Any post-await path relies only on `currentOwnerId()` string or publishes before revalidation |
| GRDB data loss while dropping sync fields | New forward migration plus old-schema upgrade fixture and final `PRAGMA table_info/index_list` assertions | Existing Focus/Profile rows or IDs do not survive |
| Insight page bound mistaken for retention | Separate full tagged query from newest-100 projection | Clear/mark-all operate on projection, or insert prunes older Insight rows |
| Duplicate authority disguised as “fast cache” | No persisted Focus/Insight UserDefaults; projections reconstruct from GRDB | A cache can diverge or is needed to make correctness pass |
| Local mutation UI lies on failure | Transaction result drives projection; injected failures and rollback | Delete/dismiss/clear reports success before durable commit or swallows error |
| Capture status drifts | Reuse canonical shared capture derivation | S-14 introduces another “is monitoring” flag |
| Settings cleanup breaks Task/Memory/Live Suggestions | Characterization tests across server-sync removal; predecessor owners review | A retained assistant relies on remote hydration or its behavior changes beyond localization |
| Update channel accidentally deleted with assistant route | Explicit IR-246 protection; local Sparkle tests; preserve desktop update policy/release DB | Stable/Beta or update checks stop working |
| Home exact Insight request races owner/refresh | Store local ID + authorization provenance, consume only after row availability | Missing row falls back to another row or copied payload |
| Chat notification creates second writer | S-11 journal API only; agent logic harness + live continuity gate | Any direct array/history append appears |
| IR-723 requirements describe older callers | Current inventory records no production caller; rerun at execution HEAD | A real production caller reappears—inventory and ownership must be resolved first |
| IR-724 copy deletion suppresses quota truth | Keep `FreemiumThresholdReachedEvent` and Mac handler under behavior tests | Structured event/local UI is absent or coupled to FCM success |
| Generic FCM over-deletion | Enumerate every `utils.notifications` caller; S-23 owns final removal | A non-S-14 retained caller needs the helper being deleted |
| Job removal leaves deployment residue | Runtime registry/env/concurrency/check/workflow tests and exact residue search | Any workflow/scheduler manifest still builds or invokes deleted source |
| Route removal becomes a 410 shell | Remove deprecated entries and generated clients | Deleted endpoint still registers under any status |
| Broad slice becomes unreviewable | One vertical RED/GREEN commit per cycle; report source-line size; independent cycles remain independently verifiable | A commit combines unrelated authority migration and job cleanup without a green boundary |
| Live deletion exceeds authorization | Separate Section 16 inventory/operator sign-off | Any command would delete Cloud Run, scheduler, image, Firestore, Redis, or secrets without explicit approval |

## 18. Final completion checklist

### Requirements and scope

- [ ] All 43 assigned IRs have an individual mapping in Section 4 and implementation evidence in a cycle, handoff, or explicit retained/out-of-scope boundary.
- [ ] The execution SHA, integrated predecessor SHAs, refreshed caller ledger, and requirements-validator result are recorded.
- [ ] No Windows work, compatibility shell, deprecated alias, staging queue, sync outbox, or second private-data authority was added.
- [ ] Only S-14-owned behavior was changed; S-10/S-11/S-12/S-13/S-15 and later-slice seams were consumed or handed off.

### Focus

- [ ] One owner-fenced GRDB write per accepted transition; no Memory/backend/cache fan-out.
- [ ] Restart/offline/owner-switch/late-result behavior is proven.
- [ ] Exact delete/clear rollback, 30-day/500 retention, current-period math, both refresh controls, truthful capture labels, restored card, and exact empty copy are proven.
- [ ] Current schema/models have no Focus sync fields/IDs/index; historical upgrade path is green.

### Insights and proactive continuity

- [ ] Local `tips` rows are sole authority; page newest-100 does not delete older rows.
- [ ] Exact read/dismiss/delete/mark-all/clear-all scopes and failures are proven against ordinary Memories and older/dismissed rows.
- [ ] Home opens/dismisses the exact owner-local record; stale/unavailable is truthful.
- [ ] Notification click admits once to current-owner local Chat with `proactive_notification`; dismissal/time-out does not mutate Insight.
- [ ] Live Suggestions remains distinct and green.

### AI Profile, Home, and settings

- [ ] AI Profile uses bounded local S-10/S-12/S-13/S-11 inputs, two Gemini stages, local commit, five-profile history, and every current consumer.
- [ ] Profile edit/regenerate/delete/onboarding exploration/restart/owner switch work; cloud route/cache/sync are gone.
- [ ] Home questions use local context, no onboarding input, and preserve per-owner/day empty/failure policy.
- [ ] Assistant and notification controls survive restart locally with exact 0–5 intervals; no lifecycle/settings/automation network call remains.
- [ ] Task/Memory automatic extraction and Live Suggestions are unchanged; update channel is local and functional.

### Navigation and deletion

- [ ] Top nav is plain Home / Memory / Tasks / Insights; default Insights + Focus segment; no badge or standalone Insight route.
- [ ] ⌘1/2/3/4, ⌘⌥R, ⌘,, and `navigate_via_shortcut` match IR-681 exactly.
- [ ] Focus/Profile/settings/Mentor/Daily Summary routes, models, storage, generated contracts, and deprecated shells are absent.
- [ ] Cloud proactive and GPT purchase/credit model workloads/config/usage/tests/docs are absent; quota event and static silent nudge remain.
- [ ] Daily Summary product and Notifications job/control plane are absent from every repository registry/check/doc.
- [ ] Generic notification primitives each have a named surviving caller or are deleted; S-23 receives the remainder.

### Verification and acceptance

- [ ] Every focused RED was observed before its GREEN and every cycle has a focused green command/evidence.
- [ ] Desktop debug build, `desktop/macos/test.sh`, backend preflight/suite, route policy, OpenAPI/generated Swift freshness, runtime env checks, runtime image source closure, requirements validator, `make preflight`, PR preflight, and `git diff --check` are green.
- [ ] Named bundle `omi-s14-local` exercised the real owner-A/owner-B, restart, offline-read, mutation-failure, navigation, settings, Profile, Focus, Insight, and Chat-continuity paths without touching production bundles.
- [ ] Section 13 residue commands are empty or every hit has an explicit retained/historical/generated owner.
- [ ] `PRODUCT.md`, component `AGENTS.md` guidance, generated docs/contracts, and one desktop changelog fragment moved with behavior.
- [ ] Repository closure and live operational closure are reported separately; no live destructive action is implied by a green repository PR.
- [ ] Final `git status --short` and diff review prove the implementation PR contains intentional S-14 files only; for this planning task, only `bootstrap-scaffold/wave-2/s-14 tdd.md` was modified.

## 19. Wave 2 closeout status — 2026-08-21

**Repository status: complete for the Wave 3 dependency.** The unnumbered
[`wave-2-closeout tdd.md`](wave-2-closeout%20tdd.md) makes Focus commit before
publication, resets every proactive assistant on an owner transition, and retires
`proactive_extractions` through a forward migration. Migration fixtures preserve
legacy memory, advice, and task data exactly once; current Chat discoverability
uses canonical Memories, Tasks, and `tips` only.

This status does not claim separately authorized live resource deletion. The
original planning checklist remains the detailed historical contract; closeout
evidence and inherited target-branch suite blockers are recorded in the closeout
slice.
