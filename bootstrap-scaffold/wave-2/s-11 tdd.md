# S-11 — Make Chat and Home local-authoritative

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | S-11 |
| Outcome | Ordinary macOS Chat and its Home presentation are local-authoritative |
| Assigned decisions | IR-003, IR-040–IR-045, IR-500–IR-530, IR-721, IR-722, IR-731, IR-932 |
| Required predecessors | S-05, S-06, S-07, S-10, S-12 |
| Primary owners changed | macOS `ChatProvider`, Home, the local Node journal/catalog, the two transient greeting/title backend routes |
| Non-goals | Windows; global model cleanup; final Tasks/Focus/Insight/Profile storage migrations; live cloud-data deletion; releases |
| Planning baseline | `0d9934c9d2ed61bd02ac8784e50f56ee816257c3` |

This is the execution plan for the slice, not a proposal to create another plan. Every path and existing symbol below was checked at the planning baseline. Names prefixed **[new]** are intentional target additions; all other names exist in this checkout.

## 2. Planning status and baseline proof

The planning checkout is exactly `0d9934c9d2ed61bd02ac8784e50f56ee816257c3`, and `git merge-base --is-ancestor 0d9934c HEAD` succeeds. `python3 bootstrap-scaffold/validate-requirements-ledger.py` reports 714 indexed decisions, 714 detailed decisions, and all decisions reviewed.

Implementation must not start merely because this document exists. First integrate S-05, S-06, S-07, S-10, and S-12, rebase onto the then-current `origin/main`, rerun the inventory in §§6–7 and the residue searches in §13, and record any changed path or contract in this document. S-10 and S-12 are planning artifacts rather than integrated production changes at this baseline, so their target APIs cannot be assumed to exist yet.

Planning constraints:

- Do not preserve the former draft’s speculative `/v2/chat/greeting` or `/v2/chat/title` paths. The verified routes are `POST /v2/chat/initial-message` and `POST /v2/chat/generate-title` in `backend/routers/chat_sessions.py`.
- The literal symbol `chat_graph` does not exist. The current hosted graph path is `backend/utils/retrieval/graph.py::execute_graph_chat`, called from `backend/utils/chat.py`.
- No compatibility aliases or legacy-data migrations are added. This is an unreleased fork with no inherited Omi customer data.
- Windows is ignored: do not inspect, change, repair, or delete Windows code as part of S-11.
- Product behavior changes require behavioral tests through production seams. Source searches are residue tripwires only.

## 3. Required outcome and success boundary

At completion, `omi-agentd.sqlite3` is the sole authority for ordinary Chat identity, catalog metadata, and accepted turns. Swift owns app-managed attachment bytes and drafts. The backend performs only authenticated, bounded, transient inference for `/v2/chat/completions`, the existing greeting route, and the existing title route; it stores no normal Chat session, message, attachment, rating, greeting, title, prompt, or output record.

Home is the canonical ordinary Chat host. The user can create, switch, search, rename, star, delete, reopen, attach to, and resume chats from Home; the same timeline remains continuous across Home, the floating bar, PTT, and realtime voice. With normal Chat persistence endpoints unavailable, all those operations survive app/agent restart and remain isolated by authenticated owner. Managed Pi still answers from the local journal and the S-10/S-12 local context surfaces.

Success requires both positive and negative proof:

- Positive: the retained Home/Chat, capture/listening, draft, attachment, error, layout, navigation, monthly-quota, and voice-continuity behavior works in a named bundle.
- Negative: no macOS/Node caller projects or reconciles ordinary Chat to the backend; removed product-data routes fail closed; the transient greeting/title handlers cannot read or write Chat product data; the duplicate `ChatPage` and legacy voice importer no longer compile into the app.
- Operational: repository closure is recorded separately from any future deletion of live Firestore/GCS/provider data or infrastructure.

## 4. Assigned IR-by-IR implementation map

| IR | Required decision and concrete S-11 implementation | Proof owner |
|---|---|---|
| IR-003 | Keep the local kernel conversation journal; delete ordinary-Chat backend projection, retry, reconciliation, and remote import. | Cycles 1, 8, 9 |
| IR-040 | Keep complete multi-chat behavior locally. Add owner-scoped catalog create/list/update/delete over existing local sessions and keep `default` as the stable single-chat identity. | Cycles 2–4 |
| IR-041 | Generate a new-thread greeting through the existing transient route, assign identity on the Mac, journal it locally, and treat failure as nonfatal. The greeting does not count as the first exchange for title generation. | Cycle 5 |
| IR-042 | Generate a title only after the first completed real user/assistant exchange, cap it at six words, fall back to `New Chat`, and use title-origin compare-and-set so manual rename always wins. | Cycles 2, 6 |
| IR-043 | Delete normal Chat rating controls, payloads, routes, analytics, and persistence while retaining independently owned message-report routes. | Cycle 10 |
| IR-044 | Materialize selected/pasted attachments into owner/chat-scoped Application Support before journal admission; retain local URI/name/MIME/presentation and first-image bytes; limit to four; never delete the source file. | Cycle 7 |
| IR-045 | Keep one assistant and remove remaining app/persona branches or selectors in the scoped Chat path; retain the current `OneAssistantChatContractTests` guard. | Cycles 1, 11 |
| IR-500 | Make Home the default history-aware hub and the sole ordinary Chat presentation. | Cycles 4, 14 |
| IR-501 | Preserve the local greeting behavior described by IR-041 in Home. | Cycle 5 |
| IR-502 | Preserve the exact Focus status claim presented by Home; S-14 owns the final Focus storage authority. | Cycles 1, 12 |
| IR-503 | Preserve an exact task count from the current local task store, not a server aggregate. | Cycle 12 |
| IR-504 | Keep a stable, diverse typed Home list and delete timer-driven automatic rotation. | Cycle 12 |
| IR-505 | Present local Insight rows and make open/read/dismiss actions call `InsightStorage.markAsRead` and `InsightStorage.dismissInsight`; S-14 later replaces that store’s underlying persistence. | Cycle 12 |
| IR-506 | Preserve task navigation through `TaskNavigationRequestStore`; hide a row only as a presentation decision, not by mutating authority. | Cycles 12, 14 |
| IR-507 | Preserve the contextual fallback and editable Ask prefill. | Cycles 1, 13 |
| IR-508 | Preserve once-per-day suggestion caching, but build its bounded prompt only from local conversation, memory, task, and goal sources delivered by S-10/S-12 and current local task/goal stores. | Cycle 12 |
| IR-509 | Delete the Home goals strip, goals widget/sheets, and their Home-only wiring. Do not delete the underlying goal store owned by S-13/S-14. | Cycle 14 |
| IR-510 | Keep the shared Home composer and its send/stop state machine backed by `ChatProvider.mainInstance`. | Cycles 1, 4, 13 |
| IR-511 | Keep Home attachment selection/paste/preview, but require text before send; use the managed local attachment lifecycle from IR-044. | Cycles 7, 13 |
| IR-512 | Keep the already-achieved absence of the Home Connect tray and `home_connect_toggle`; add no replacement. | Cycles 1, 14 |
| IR-513 | Delete `DashboardIntelligenceStore`, its client/outbox/automation, and cloud recommendation ownership; extract and retain `TaskNavigationRequestStore` as a narrow local navigation primitive. | Cycles 12, 14 |
| IR-514 | Keep a static empty-chat welcome in Home, truthful and product-neutral until S-30 owns final identity/copy; delete the duplicate `ChatPage` welcome. | Cycles 4, 14 |
| IR-515 | Preserve capture control semantics exactly through `CaptureListeningLogic` and the existing Home controls. | Cycles 1, 13 |
| IR-516 | Preserve listening control semantics exactly. | Cycles 1, 13 |
| IR-517 | Keep the capture/listening mode switch, but expose explicit named `Meetings Only` and `Always` choices rather than a hover-only affordance. | Cycle 13 |
| IR-518 | Preserve responsive single-column behavior and readable content caps. | Cycles 1, 13 |
| IR-519 | Preserve the Ask control’s verified width policies, including the 560/980-point content bounds in `DashboardPage`. | Cycles 1, 13 |
| IR-520 | Preserve the reduced-motion transition path. | Cycles 1, 13 |
| IR-521 | Keep a neutral dark palette, move Home tokens to `Theme/OmiColors.swift`, and introduce no purple. | Cycle 13 |
| IR-522 | Retain and narrow local automation to canonical Home Chat: `home_open_chat`, `home_close_panel`, `home_ask`, `home_attach`, `ask_main_chat`, and `ask_main_chat_no_wait`. | Cycles 4, 14 |
| IR-523 | Narrow startup/foreground refresh to surviving Chat, local suggestion, task, and capture owners; delete score/goals/intelligence/connect/counter refresh wrappers. | Cycles 12, 14 |
| IR-524 | Delete hidden `ChatPage`; route semantic Chat navigation to Home and `MainChatNavigationRequestStore`. | Cycle 14 |
| IR-525 | When `multiChatEnabled` is on, show a compact complete catalog in Home with New/select/search/star filter/rename/star/delete; when off, keep only `default`. | Cycles 2–4 |
| IR-526 | Render all three current error forms in Home: `ChatErrorCard`, structured `currentError`, and the generic `errorMessage` fallback. | Cycles 1, 13 |
| IR-527 | Delete the lifetime-cost `$50` nudge and Chat-page-only auth/modal residue; retain the monthly `FloatingBarUsageLimiter` popup. The former Claude auth sheet is already absent at this baseline and must stay absent. | Cycles 1, 13–14 |
| IR-528 | Delete top-nav aggregate new-item counters and badge plumbing. | Cycle 14 |
| IR-529 | Preserve Escape-to-Home behavior from conversations, memories, tasks, and rewind. | Cycles 1, 14 |
| IR-530 | Preserve `DesktopTopBar` compact navigation on narrow widths and persistent capture/settings access. | Cycles 1, 14 |
| IR-721 | Keep title generation on the existing authenticated title route, pin the workload to Gemini 2.5 Flash-Lite in every environment profile, bound input/timeout, count usage only, and persist only the local catalog result. | Cycle 6 |
| IR-722 | Keep greeting generation on the existing authenticated initial-message route, pin the workload to OpenAI GPT-5.4-mini in every environment profile, send bounded local context, count usage only, and persist only the local journal turn. | Cycle 5 |
| IR-731 | Delete old hosted Chat persona/RAG/extraction paths while retaining managed Pi, `/v2/chat/completions`, local retrieval/tools, local attachments, transient greeting/title compute, PTT/STT, and message reporting. | Cycle 11 |
| IR-932 | Delete `LegacyVoiceJournalImporter` and its launch state/tests while preserving direct voice writes into the shared local journal and typed/voice continuity. | Cycles 1, 15 |

## 5. Dependencies, entry gates, and assumptions

S-11 depends on these completed contracts, not just merged filenames:

| Predecessor | Contract S-11 consumes | Entry evidence / stop gate |
|---|---|---|
| S-05 | Owner identity is stable across Swift and the Node runtime. | Owner-switch tests prove no catalog, draft, attachment, or journal leakage. Stop if owner identity is still free text or a fallback identity. |
| S-06 | One-assistant Chat and the retained managed-Pi path are established. | `OneAssistantChatContractTests` and `/v2/chat/completions` tests pass. Stop if any normal Chat caller still selects an app/persona. |
| S-07 | The kernel journal is the accepted-turn authority across Home/floating/PTT/voice. | `ChatTimelineContinuityTests`, agent continuity tests, and the cross-surface smoke pass. Stop if any producer appends a separate visible-message store. |
| S-10 | A bounded local conversation query surface exists for Home suggestions and greeting context. | Its public protocol and owner isolation tests are integrated. Stop rather than calling `APIClient.getConversations` as a fallback. Memory query authority comes from S-12. |
| S-12 | Local memory authority/query is integrated and available to managed Pi and Home. | Offline/restart query proof passes. Stop if the only usable source is backend memory retrieval. |

S-13 is not an entry dependency. During S-11, `ActionItemStorage` and `GoalStorage` remain the current local inputs; S-13 owns their eventual final authority. S-14 owns final Focus/Insight/Profile storage consolidation, but S-11 must remove Home’s cloud intelligence dependency and make the currently local Insight actions work. S-21, S-22, S-23, S-24, S-28, and S-30 receive explicit handoffs in §12.

Before Cycle 1:

1. Run `make setup`, confirm the installed pre-commit hook, and rebase/refresh according to repository policy without switching the worktree branch.
2. Run the §13 inventory searches and update this document if predecessor integration changed any owner, route, or file.
3. Run `python3 bootstrap-scaffold/validate-requirements-ledger.py`.
4. Run the existing focused characterization tests named in Cycle 1.
5. Stop on any unexplained failure; do not normalize a broken starting state into new expectations.

## 6. Verified current production codeflow

The following is the current non-Windows production flow at the planning baseline.

### Ordinary typed Chat

1. `DashboardPage` and `ChatPage` both render `ChatProvider.mainInstance`; `PageContentView` in `MainWindow/DesktopHomeView.swift` still renders `ChatPage` for sidebar raw value `2`.
2. `ChatProvider.sendMessage` waits for `ChatAttachment` uploads, prepares `AgentQueryAttachment` values, writes the accepted user turn through `KernelTurnJournal`, and invokes managed Pi through `AgentBridge`/`AgentRuntimeProcess`.
3. The Node runtime resolves a stable surface conversation in `runtime/surface-session.ts`; `KernelSessions` and `ConversationJournal` persist session/mapping/turn state in `omi-agentd.sqlite3` through `runtime/sqlite-store.ts`.
4. The same accepted turn is queued for backend projection by `runtime/backend-turn-projection.ts`; `agent/src/index.ts` pumps message and conversation-delete outboxes and exchanges `journal_backend_sync`, `journal_backend_delete`, and `journal_backend_reconcile` messages with Swift.
5. Swift `KernelJournalBackendSyncDriver` calls the `/v2/desktop/messages*` methods in `Chat/APIClient+KernelJournal.swift`; `backend/routers/chat_sessions.py` writes/reconciles Firestore through `backend/database/chat.py`.
6. On selection/default load, `ChatProvider.selectSession` and initialization hydrate the local journal but can call the legacy backend-message import/reconcile paths. `LegacyMainChatSessionAliasMigration` can also import historical main-chat aliases.
7. `ChatProvider.fetchSessions`, `createNewSession`, `toggleStarred`, `updateSessionTitle`, and `deleteSession` call `Services/APIClient/APIClient+ChatSessions.swift`, which uses `/v2/chat-sessions*`; the local journal therefore owns turns while the backend still owns ordinary catalog metadata.

### Greeting and title

1. A new session calls `ChatProvider.fetchInitialMessage`, which calls `POST /v2/chat/initial-message` with `session_id` through `APIClient+ChatSessions.swift`.
2. `backend/routers/chat_sessions.py::create_initial_message` calls `backend/utils/chat.py::initial_message_util`; that path reads backend user/memory state, creates/persists a backend message identity, and uses `backend/utils/llm/chat.py::initial_chat_message`/the `chat_responses` feature.
3. After the first response, `ChatProvider.generateSessionTitle` sends the session ID and current messages to `POST /v2/chat/generate-title`.
4. `backend/routers/chat_sessions.py::generate_session_title` uses `get_llm('session_titles')` and mutates the backend chat session title. The current model configuration does not yet satisfy the exact IR-721/IR-722 pinning contract.

### Attachments

1. `ChatAttachment` represents pending/uploaded/local-only/failed state and enforces the current selection limits.
2. `APIClient+Messages.swift` uploads through `/v2/files`; the backend path in `backend/routers/chat.py` uses OpenAI Files, GCS thumbnail/object helpers, and Firestore file metadata through `backend/utils/other/chat_file.py`.
3. `ChatResource` is already the journal-facing resource/presentation abstraction. `AgentQueryAttachment` already accepts `attachmentId`, display name, MIME type, size, URI, and bytes fallbacks. S-11 reuses both rather than adding a second resource model.

### Voice continuity

`RealtimeHubController+SessionLifecycle.swift`, `RealtimeHubController+StreamingJournal.swift`, `RealtimeHubController+SessionDelegate.swift`, and `VoiceTurnCoordinator.swift` write direct voice turns to the same journal/surface identity as Home Chat. Separately, `LegacyVoiceJournalImporter.swift` is invoked from `RealtimeHubController` lifecycle state to import an obsolete history source. S-11 deletes only the importer and preserves the direct write path.

### Home

1. `DashboardPage` owns `HomeSuggestionsStore`, `FocusStorage`, `DashboardIntelligenceStore`, `InsightStorage`, and `HomeStatusStore`. `DashboardViewModel` also loads server score/tasks/goals.
2. `HomeKnowsListComposer` merges task, recommendation, insight, and question rows, while `DashboardPage` advances timer-driven rotation. Local `InsightStorage` rows can be displayed, but `openKnowsRow`/dismiss/later behavior is implemented only for `DashboardIntelligenceStore` recommendations.
3. `GeminiHomeSuggestionGenerator` calls `APIClient.getMemories`, `getConversations`, `getActionItems`, and `getGoals`; `HomeSuggestionsStore.refreshIfNeeded` already owns the useful owner/day cache semantics.
4. `DashboardPage.homeAskBar` presents the shared `ChatProvider`; only structured `currentError` reaches `ChatErrorCard`, while the generic `errorMessage` fallback exists on `ChatPage`.
5. `DesktopAutomationBridge` exposes `home_open_chat`, `home_close_panel`, `home_ask`, `home_attach`, `ask_main_chat`, and `ask_main_chat_no_wait`. `MainChatNavigationRequestStore` already opens Home Chat for the `.navigateToChat` notification.
6. `DesktopTopBar` uses `ViewThatFits` and `TopNavigationBarLayout` for responsive navigation but also shows aggregate conversation/memory/task counters. `DesktopHomeView.scheduleConversationWarmup` performs some counter-only warmups.

## 7. Complete caller and dependency inventory

This inventory is complete for non-Windows S-11 authority at the planning baseline. A file can appear in more than one row because it crosses an authority boundary.

### macOS production owners and callers

| File | Current symbols / responsibility | S-11 disposition |
|---|---|---|
| `desktop/macos/Desktop/Sources/Providers/ChatProvider.swift` | `ChatSession`, `ChatProvider`, `fetchSessions`, `createNewSession`, `selectSession`, `deleteSession`, `toggleStarred`, `updateSessionTitle`, `initializeVisibleMessages`, `sendMessage`, `generateSessionTitle`, `clearChat`; legacy compatibility helpers | Replace remote catalog calls with the local catalog; retain one shared provider/timeline; remove lifetime nudge and legacy import/projection plumbing. |
| `desktop/macos/Desktop/Sources/Services/APIClient/APIClient+ChatSessions.swift` | Chat-session CRUD, greeting/title calls, and co-located AI-profile calls | Move any independently retained AI-profile code first; retain only stateless greeting/title clients under a truthful filename; delete session CRUD. |
| `desktop/macos/Desktop/Sources/Services/APIClient/APIClient+Messages.swift` | `deleteMessages`, `/v2/files`, `ChatFileResponse` | Delete ordinary Chat deletion/upload use after local attachment GREEN; preserve unrelated callers only if refreshed inventory proves them. |
| `desktop/macos/Desktop/Sources/Chat/APIClient+KernelJournal.swift` | save/get/reconcile/delete DTOs and `/v2/desktop/messages*` calls | Delete after the authority proof gate. |
| `desktop/macos/Desktop/Sources/Chat/KernelJournalBackendSyncDriver.swift` | `KernelJournalConversationBarrier`, `KernelJournalBackendSyncDriver` | Delete after the authority proof gate. |
| `desktop/macos/Desktop/Sources/Chat/AgentRuntimeProcess.swift` | Node process/protocol bridge and journal result handlers | Retain process bridge; remove sync/delete/reconcile and legacy-import message handlers. |
| `desktop/macos/Desktop/Sources/Chat/AgentBridge.swift` | `AgentBridge`, `AgentQueryAttachment`, surface sessions, `LegacyMainChatSessionAliasMigration` | Retain managed Pi, attachments, and session binding; delete main-chat alias migration. |
| `desktop/macos/Desktop/Sources/Chat/KernelTurnJournal.swift` | journal turn DTOs/replay/write/update/terminalization | Keep as the Swift journal boundary. |
| `desktop/macos/Desktop/Sources/Chat/ChatResource.swift` | `ChatResource`, persistence/hydration, strip/actions | Adapt as the single managed-local attachment resource representation. |
| `desktop/macos/Desktop/Sources/Chat/ChatAttachment.swift` | pending/uploaded/local-only/failed UI attachment state | Adapt materialization and remove server-ID/upload authority. |
| `desktop/macos/Desktop/Sources/Chat/ChatDraftStore.swift` | owner/scope/context-keyed atomic Application Support drafts | Keep; prove chat and owner isolation under named bundle IDs. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/DashboardPage.swift` | `DashboardViewModel`, `DashboardPage`, Home stage/composer/errors/controls, `openKnowsRow`, `HomePalette`, `HomeAskBar`, `HomeStatusButton`, `HomeListeningStatusButton` | Make canonical Chat host; migrate local sources/actions; simplify duplicate/cloud-only UI while preserving retained behavior. |
| `desktop/macos/Desktop/Sources/MainWindow/Dashboard/HomeSuggestionsStore.swift` | `HomeSuggestionComposer`, `HomeSuggestionGenerating`, `HomeSuggestionsStore`, `GeminiHomeSuggestionGenerator` | Preserve once/day cache; replace remote reads with bounded local source protocols. |
| `desktop/macos/Desktop/Sources/MainWindow/Dashboard/HomeKnowsComposer.swift` | typed Home rows and rotation | Keep typed composition; delete automatic rotation state. |
| `desktop/macos/Desktop/Sources/MainWindow/Dashboard/DashboardIntelligenceStore.swift` | `DashboardIntelligenceClient`, `TaskNavigationRequestStore`, recommendation/goals/feedback outbox/automation | Extract `TaskNavigationRequestStore` to **[new]** `MainWindow/Dashboard/TaskNavigationRequestStore.swift`; delete the rest. |
| `desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/Insight/InsightStorage.swift` | `StoredInsight`, `InsightStorage`, `markAsRead`, `dismissInsight`, `visibleInsights` | Use as the local Home behavior seam; S-14 owns removal of its backend sync/UserDefaults authority. |
| `desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/Focus/FocusStorage.swift` | `FocusStorage`, current focus/status/history plus cloud sync | Read current local projection only; S-14 owns final storage migration. |
| `desktop/macos/Desktop/Sources/Rewind/Core/ActionItemStorage.swift` | current local task cache | Read for Home count/context; S-13 owns final authority. |
| `desktop/macos/Desktop/Sources/Rewind/Core/GoalStorage.swift` | current local goal cache | Read only for bounded suggestion context; remove Home goal UI; S-13/S-14 own final authority. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/HomeStatusStore.swift` | `HomeKnowledgeCounts`, `HomeStatusLoader`, `HomeStatusStore` | Delete after proving the redesigned Home has no retained reader. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/ChatPage.swift` | duplicate Chat page/catalog, generic error banner, stale modals/copy | Delete after Home catalog/error GREEN. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/ChatSessionsSidebar.swift` | `ChatSessionsSidebar`, `SessionRow` | Move/reuse the compact catalog presentation inside Home, then delete the duplicate file or rename it to the canonical Home component. |
| `desktop/macos/Desktop/Sources/MainWindow/DesktopHomeView.swift` | `PageContentView`, sidebar routing, `resolvedAutomationTarget`, Escape handling, warmups | Remove `.chat` page rendering, route semantic chat to Home, keep remaining raw values and Escape behavior, remove counter-only warmups. |
| `desktop/macos/Desktop/Sources/MainWindow/SidebarView.swift` | `SidebarNavItem`, including `.chat = 2` | Delete `.chat` without renumbering other persisted/raw navigation values. |
| `desktop/macos/Desktop/Sources/MainWindow/MainChatNavigationRequest.swift` | `MainChatNavigationRequestStore` and open notification | Keep as the canonical semantic open-Home-Chat seam. |
| `desktop/macos/Desktop/Sources/MainWindow/DesktopTopBar.swift` | `DesktopTopBar`, `TopNavigationBarLayout`, compact menu, badges | Keep responsive structure/capture/settings; remove aggregate count/badge inputs. |
| `desktop/macos/Desktop/Sources/DesktopAutomationBridge.swift` | Home/Chat semantic actions and route resolver | Preserve/narrow retained actions to Home; remove hidden Chat-page target. |
| `desktop/macos/Desktop/Sources/ViewExporter.swift` | preview/export registrations for `ChatPage` and `ChatSessionsSidebar` | Remove retired exports; point any retained catalog export at Home. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/SettingsPage.swift` and `.../Settings/Sections/SettingsContentView+Assistants.swift` | `multiChatEnabled` and legacy-Home design settings | Keep multi-chat; remove legacy-Home alternative/toggle after canonical Home GREEN. |
| `desktop/macos/Desktop/Sources/MainWindow/SettingsSidebar.swift` and `desktop/macos/Desktop/Sources/DesktopAutomationManagedAccessActions.swift` | settings navigation/automation references | Remove only legacy-Home/retired Chat references found by refreshed inventory. |
| `desktop/macos/Desktop/Sources/Theme/OmiColors.swift` | shared desktop color tokens | Receive neutral Home tokens; no purple. |
| `desktop/macos/Desktop/Sources/FloatingControlBar/LegacyVoiceJournalImporter.swift` | obsolete importer | Delete. |
| `desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController.swift`, `RealtimeHubController+SessionLifecycle.swift` | importer state/invocation plus active session lifecycle | Remove importer state/call; retain current direct journal lifecycle. |
| `RealtimeHubController+StreamingJournal.swift`, `RealtimeHubController+SessionDelegate.swift`, `VoiceTurnCoordinator.swift` in the same directory | direct voice journal and cross-surface continuity | Keep and characterize. |

### Node local authority

| File | Current symbols / responsibility | S-11 disposition |
|---|---|---|
| `desktop/macos/agent/src/runtime/sqlite-store.ts` | `sessions`, `surface_conversations`, `conversation_turns`, backend outbox/reconcile tables | Add `title_origin` and `starred` to `sessions`; reuse existing tables; later drop ordinary-Chat projection/reconcile tables only when no other owner uses them. |
| `desktop/macos/agent/src/runtime/kernel-sessions.ts` | `KernelSessions`, internal `listSessions` and session lifecycle | Add owner-scoped catalog operations over existing sessions. |
| `desktop/macos/agent/src/runtime/surface-session.ts` | `resolveSurfaceSession`, stable `external_ref_id`, shared main/floating/voice mapping | Keep; public chat ID is `external_ref_id`, while internal session ID remains private. |
| `desktop/macos/agent/src/runtime/conversation-journal.ts` | `ConversationJournal`, accepted visible turns | Keep; derive preview/count/activity from accepted visible turns. |
| `desktop/macos/agent/src/runtime/backend-turn-projection.ts` | backend message/delete projection and leases | Delete after Cycle 8. |
| `desktop/macos/agent/src/protocol.ts` | JSONL request/result schemas including sync/reconcile/legacy import | Add **[new]** catalog request/result variants; later delete sync/reconcile/import variants. |
| `desktop/macos/agent/src/index.ts` | transport dispatch, projection pump, result handlers, legacy import handler | Add catalog dispatch; remove projection pump/handlers after local authority proof. |

The target JSONL operations are **[new]** `chat_catalog_list`, `chat_catalog_create`, `chat_catalog_update`, and `chat_catalog_delete`, each owner-scoped and receipt-bearing. The target **[new]** `LocalChatSummary` contains `chatId`, `title`, `titleOrigin` (`default | automatic | manual`), `preview`, `messageCount`, `createdAtMs`, `lastActivityAtMs`, and `starred`. Create accepts a caller-generated UUID for retry idempotency. Automatic title update is compare-and-set only while `titleOrigin == default`; manual rename sets `manual`. Search/grouping remain Swift presentation logic.

The verified current `sessions` schema already contains `session_id`, `owner_id`, `agent_definition_id`, `title`, `status`, `surface_kind`, external-reference fields, legacy-alias fields, execution defaults/model metadata, `metadata_json`, creation/update/activity timestamps, and migration-added `execution_role`, `provider_boundary`, and `current_profile_generation`. `surface_conversations` is keyed by owner/surface/external reference and maps to `conversation_id` plus `agent_session_id`. `conversation_turns` begins with conversation/turn/role/surface/content/timestamps/metadata and has migration-added origin, lifecycle status, content blocks, resources, producing run/attempt, remote ID, sequence, producer ID, and payload hash. S-11 adds only the catalog columns to `sessions`; it does not duplicate any of these identities or turn fields.

### Backend routes, helpers, models, and contracts

| File | Current dependency | S-11 disposition |
|---|---|---|
| `backend/main.py` | mounts `chat`, `chat_sessions`, and `desktop_chat` routers | Keep retained routers; remove deleted route registrations only through router changes. |
| `backend/desktop_backend.py` | mounts `desktop_chat` and `desktop_deprecated` | Keep; remove S-11-owned 410 entries from `desktop_deprecated` so retired paths are absent/404. S-26 owns service consolidation. |
| `backend/routers/chat_sessions.py` | `POST/GET /v2/chat-sessions`, `GET/PATCH/DELETE /v2/chat-sessions/{session_id}`, `POST/GET/DELETE /v2/desktop/messages`, `GET /v2/desktop/messages/reconcile`, `PATCH /v2/desktop/messages/{message_id}/rating`, `POST /v2/chat/initial-message`, `POST /v2/chat/generate-title`, and `GET /v1/users/stats/chat-messages` | Delete storage/session/rating/count authority; adapt the two existing compute routes to stateless bounded requests/responses. |
| `backend/routers/desktop_chat.py` | retained authenticated/rate-limited `/v2/chat/completions`, count/usage, managed provider path | Keep. |
| `backend/routers/desktop_deprecated.py` | explicit 410 table for removed desktop routes | Remove entries retired by S-11 so absence is 404; do not add duplicate handlers. |
| `backend/routers/chat.py` | `POST/GET/DELETE /v2/messages`, `POST /v2/initial-message`, `POST /v2/files`, `POST /v1/files`, `DELETE /v1/messages`, `POST /v1/initial-message`, `PATCH /v2/messages/{message_id}/rating`, report routes, and voice routes | Delete only normal-Chat-exclusive branches after caller proof; retain `POST /v2/messages/{message_id}/report`, `POST /v1/messages/{message_id}/report`, `POST /v2/voice-messages`, `POST /v2/voice-message/transcribe`, `WS /v2/voice-message/transcribe-stream`, and `/v1/files` until their assigned owners act. |
| `backend/database/chat.py` | Firestore Chat session/message/file/rating/report helpers shared by several routes | Delete functions only after per-function caller search; retain helpers required by report, voice, export, or account-deletion owners and hand them to S-23/S-24. |
| `backend/models/chat_session.py`, `backend/models/chat.py` | session/message/file DTOs, some shared | Delete only unreferenced normal-Chat DTOs; retain independently owned voice/report DTOs. |
| `backend/utils/chat.py` | `initial_message_util`, older hosted Chat flow, voice helpers, calls `execute_graph_chat` | Replace persisted greeting helper; delete only obsolete hosted Chat branches; retain voice/report-related helpers. |
| `backend/utils/llm/chat.py` | `initial_chat_message`, classifications, older Chat LLM helpers | Make greeting context caller-supplied/bounded and delete only dead hosted-Chat helpers. |
| `backend/utils/llm/model_config.py` | `chat_responses`, `chat_extraction`, `session_titles` features | Pin dedicated greeting/title workloads as required; remove `chat_extraction` and dead settings. S-22 owns global portfolio normalization. |
| `backend/utils/llm/clients.py`, `backend/utils/llm/gateway_client.py`, `backend/utils/llm/conversation_processing.py`, `backend/utils/metrics.py` | `chat_extraction` client routing, fallback/comparison logic, and metrics; some callers are not normal Chat | Remove the old feature completely only after the refreshed caller inventory and its assigned predecessor deletions leave no retained caller; move any provider-neutral retained helper first. |
| `backend/llm_gateway/config/generated_route_overrides.yaml`, `feature_bundles.yaml`, `route_artifacts.yaml` | `chat_extraction` route/bundle/evaluation artifacts | Delete the retired feature entries with the implementation; do not leave a gateway-only route. |
| `backend/docs/llm/model_endpoint_inventory.yaml` and `backend/scripts/smoke-llm-gateway-openai-schemas.py` | model inventory and schema smoke references | Remove retired feature coverage; preserve independently retained model smoke coverage. |
| `backend/utils/retrieval/graph.py` | `execute_graph_chat` | Remove only after all non-Windows callers are gone; do not refer to nonexistent `chat_graph`. |
| `backend/utils/other/chat_file.py` and storage helpers it calls | backend Chat-file metadata/object handling | Delete only `/v2/files`-exclusive code; retain `/v1/files`/other object owners for S-24. |
| `backend/scripts/migrate_chat_usage.py`, `backend/scripts/users/chats_analysis.py`, `backend/scripts/nps.py`, `backend/scripts/chat/stream_test.py` | Chat persistence/rating/old-stream operational scripts | Delete or narrow only if refreshed symbol/route searches prove exclusive ownership. |
| `.github/scripts/test_run_checks.py`, `.github/scripts/test_pre_push_ci_prediction.py` | diff-to-check selection references to `backend/routers/chat_sessions.py` | Keep unless route-file deletion changes the selection contract; update only with the owning manifest/check behavior. No Chat-specific scheduled workflow/job was found by the planning-baseline workflow search. |
| `backend/scripts/export_openapi.py`, `backend/scripts/openapi_runner.sh`, `backend/scripts/generate_swift_openapi_types.py` | app-client contract generation | Regenerate after route/model changes. |
| `docs/api-reference/app-client-openapi.json`, `desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift` | generated app-client surface | Remove retired generated endpoints/types; do not invent greeting/title generated clients unless the surface manifest includes them. |
| `backend/route_policy_manifest.yaml`, `backend/route_policy_legacy_missing_routes.txt` | route policy and missing-route baseline | Represent retained adapted routes and removed routes accurately; delete stale baseline entries rather than masking absence. |

The adapted greeting request is bounded local `profile_text` plus local `memories`, and its response is only `message`; the Mac creates the ID and journals it. The adapted title request is only the first real user text and assistant text, and its response is only `title`. Neither request contains `session_id`, and neither handler reads/writes Chat collections or stores prompt/output. Authentication, rate limit, timeout, and count-only accounting remain backend concerns.

### Tests, harnesses, flows, and docs that constrain the change

- Swift behavioral suites: `ChatConversationSwitchTests`, `ChatDraftStoreTests`, `ChatErrorStateTests`, `ChatJournalWritePathTests`, `ChatResourceTests`, `ChatTimelineContinuityTests`, `KernelTurnRecordedProjectionTests`, `KernelJournalBackendReconcileTests`, `KernelJournalBackendDeleteTests`, `LegacyMainChatSessionAliasMigrationTests`, `LegacyVoiceJournalImporterTests`, `OneAssistantChatContractTests`, `DesktopChatDriftGuardTests`, `DashboardCaptureStateTests`, `HomeAskFocusPolicyTests`, `HomeKnowsComposerTests`, `HomeRedesignRegressionTests`, `HomeStageCloseSemanticsTests`, `HomeStatusStoreTests`, `HomeSuggestionsStoreTests`, and `TopNavigationBarLayoutTests` under `desktop/macos/Desktop/Tests/`.
- Node suites: `surface-session.test.ts`, `conversation-journal.test.ts`, `sqlite-store.test.ts`, `protocol-v2.test.ts`, `jsonl-transport.test.ts`, `chat-continuity-invariant.test.ts`, `cross-surface-contract-smoke.test.ts`, `context-snapshot.test.ts`, and `external-surface-authority.test.ts` under `desktop/macos/agent/tests/`.
- Backend suites: `backend/tests/unit/test_desktop_migration.py`, `test_desktop_message_quota_router.py`, `test_chat_quota_counting_router.py`, `test_chat_session_normalize.py`, `test_chat_session_response_model.py`, `test_chat_message_count.py`, `test_desktop_chat.py`, `test_file_upload_endpoint_security.py`, `test_file_upload_security.py`, `test_openapi_contract.py`, `test_route_policy_inventory.py`, and old hosted-Chat tests discovered by §13.
- E2E flows: `desktop/macos/e2e/flows/home.yaml`, `home-stage.yaml`, `chat-hermetic.yaml`, `navigation.yaml`, and the affected export inventory in `view-export-retained-surfaces.yaml`.
- Owner documents: `PRODUCT.md`, `desktop/macos/AGENTS.md`, `desktop/macos/agent/src/ARCHITECTURE.md`, backend component guidance, and API reference/contracts. Update them with code; do not leave this plan as the only authority description.

## 8. Behavior classification

### KEEP AS IS

- `ChatProvider.mainInstance` as the single visible ordinary/voice timeline owner.
- Journal-before-visible-turn admission, replay, terminalization, local managed-Pi execution, local tools/retrieval, send/stop, draft isolation, and `default` chat identity.
- `ChatResource` presentation/hydration, `AgentQueryAttachment`, four-attachment limit, first-image bytes behavior, citation/report presentation where independently retained, PTT/STT, monthly quota popup, and message reporting.
- Home capture/listening semantics, contextual Ask prefill, reduced-motion path, readable width caps, compact top navigation, Escape-to-Home, and retained Home automation action names.
- `multiChatEnabled`; when false, the UI exposes only `default`.

### ADAPT

- Existing Node `sessions` rows become the catalog authority by adding `title_origin` and `starred`; catalog summaries derive preview/count/activity from journal turns.
- `ChatProvider` consumes local JSONL catalog receipts instead of backend session CRUD.
- `POST /v2/chat/initial-message` and `POST /v2/chat/generate-title` become stateless, bounded compute endpoints with the IR-specified pinned models.
- `ChatAttachment` materializes app-owned bytes before journal admission and persists a `ChatResource` URI; attachment garbage collection is reference-safe.
- `DashboardPage` hosts the catalog and all ordinary Chat states. `HomeSuggestionsStore` reads bounded local sources. Insight rows call `InsightStorage` actions.
- Home colors move from `HomePalette` into shared neutral theme tokens.

### DELETE

- Backend chat-session catalog authority, ordinary message projection/reconcile/delete outboxes, legacy backend message/session import, main-chat alias migration, normal Chat rating, `/v2/files` normal-Chat use, and backend greeting/title mutation.
- Old hosted Chat persona/RAG/extraction branches, including `chat_extraction` and `execute_graph_chat` once no caller remains.
- `DashboardIntelligenceStore` except extracted task-navigation state, Home goals presentation, timer rotation, `HomeStatusStore` when proven unread, aggregate top-nav badges/counters, lifetime-cost nudge, legacy Home alternative, duplicate `ChatPage`, and its sidebar route.
- `LegacyVoiceJournalImporter` and its state/invocation/tests.

### SIMPLIFY AFTER

- Simplify `APIClient+ChatSessions.swift` only after moving independently retained AI-profile code and after local catalog + transient compute clients are green.
- Simplify `backend/database/chat.py`, `backend/models/chat.py`, and `backend/routers/chat.py` function-by-function after refreshed callers prove which voice/report/export/account-deletion paths survive.
- Drop Node projection tables only after the no-projection build and restart tests prove no retained surface uses them; a table may remain temporarily unreachable for one cycle, but not at final closure.
- Consolidate/rename `ChatSessionsSidebar` only after Home catalog behavior passes; delete the source only when no preview/export/test references it.

### OUT OF SCOPE

- Windows code and Windows route/client behavior.
- Final Tasks/Goals authority (S-13), final Focus/Insight/Profile authority and consolidated presentation (S-14), broader shell consolidation (S-21), global provider/model portfolio (S-22), final shared backend product-data/account deletion (S-23), global object storage (S-24), service consolidation (S-26), storage namespaces (S-28), release pipeline (S-29), and literal brand/copy decisions (S-30).
- Deleting live Firestore/GCS/OpenAI Files data, indexes, buckets, secrets, scheduled jobs, or infrastructure. That is a separately authorized operational task.

## 9. Retained behavioral invariants

1. One accepted-turn authority: a user/assistant/voice turn is journaled before it becomes durable/visible; no second message store or dual-write bandage is introduced.
2. One timeline: Home, floating Chat, PTT, and realtime voice resolve the same owner/chat to the same conversation and survive restart without backend history.
3. Owner isolation: owner A cannot list, hydrate, draft into, attach to, rename, star, or delete owner B’s chat. Owner transition clears visible state before B hydrates.
4. `default` is stable and cannot disappear in single-chat mode. Turning multi-chat off hides other chats; it does not silently delete them.
5. Catalog order, preview, count, and activity come from accepted visible journal turns; aborted/hidden/tool-only lifecycle rows do not inflate them.
6. New-chat greeting failure is nonfatal. The greeting is locally identified/journaled and does not trigger automatic title generation.
7. Automatic title uses exactly the first completed real user/assistant pair, has at most six words, falls back to `New Chat`, and never overwrites a manual title.
8. Attachments are app-managed before send; source files are never deleted; reopening works after the source moves/disappears; garbage collection deletes only app-owned bytes unreferenced by every surviving journal turn.
9. Managed Pi and local context remain usable when backend Chat storage routes are unavailable. Only inference/auth/quota can require network.
10. Home composer, stop, editable prefill, generic/structured error recovery, drafts, and attachment UI use the same `ChatProvider`, not a Home-specific clone.
11. Capture and listening meanings, monthly quota, responsive layouts, reduced motion, compact navigation, settings/capture access, and Escape-to-Home do not regress.
12. Home shows no Connect tray, Claude-auth sheet, lifetime-cost nudge, auto-rotating list, goals presentation, cloud intelligence, aggregate badge, or hidden Chat page.
13. Remaining sidebar raw values are not renumbered when `.chat = 2` is removed.
14. Transient greeting/title routes require authentication, bound payload/token/time, record count/usage only, and cannot read/write product-data stores or log prompt/output/PII.
15. Static residue checks supplement rather than replace behavioral tests.

## 10. Target authority and ownership model

| Data / behavior | Sole durable authority after S-11 | Read/write seam | Explicitly forbidden |
|---|---|---|---|
| Ordinary chat ID, title, title origin, star, created/activity metadata | Owner-scoped `sessions` row in `omi-agentd.sqlite3` | **[new]** catalog JSONL operations via `AgentRuntimeProcess` | Firestore `chat_sessions`; Swift-only shadow catalog |
| Accepted ordinary/voice turns, resource references, preview/count source | `conversation_turns` plus existing surface/session mappings in `omi-agentd.sqlite3` | `KernelTurnJournal` / `ConversationJournal` | `/v2/desktop/messages*`, background projection, backend import/reconcile |
| Draft text and unsent attachment selection | `ChatDraftStore` in named-bundle Application Support, owner/chat keyed | existing draft API | backend draft/session state; cross-owner fallback |
| Attachment bytes | **[new]** owner/chat-scoped directory under `DesktopLocalProfile.applicationSupportURL()/ChatAttachments/v1` | adapted `ChatAttachment` → `ChatResource` → journal | `/v2/files`, OpenAI Files/GCS/Firestore for ordinary Chat; deleting source files |
| Greeting result | Local journal turn only | adapted `POST /v2/chat/initial-message` returns `message` | server message/session ID or persistence |
| Title result | Local catalog only | adapted `POST /v2/chat/generate-title` returns `title` | server session mutation or prompt/output persistence |
| Managed assistant answer | Local journal; transient provider execution | retained `/v2/chat/completions` and managed Pi | old `/v2/messages` hosted persona/RAG path |
| Home task/count/context | Current local `ActionItemStorage`; later S-13 authority | bounded local source adapter | Home server aggregates |
| Home Focus/Insight projections | Current local `FocusStorage`/`InsightStorage`; later S-14 authority | read projection; `markAsRead`/`dismissInsight` | `DashboardIntelligenceStore` as competing authority |
| Daily Home questions | Owner/day cache in `HomeSuggestionsStore` | bounded S-10/S-12 local context + current local task/goal adapters; transient generator | direct `APIClient.getMemories/getConversations/getActionItems/getGoals` fallback |
| Task row navigation | extracted `TaskNavigationRequestStore` | local request/consume | cloud intelligence outbox |

Catalog deletion is one local transaction: validate owner, remove the public chat’s mapping/session/turns, select `default` or the next local summary, and return a receipt. Swift then performs attachment garbage collection by scanning all surviving journal resource URIs for that owner. Partial Node deletion or GC failure is surfaced and retried safely; it must never delete source files or another owner’s bytes.

## 11. Ordered RED/GREEN implementation cycles

Run cycles in order. A GREEN that depends on a later deletion is incomplete; a deletion before its named gate is prohibited.

### Cycle 1 — Freeze retained continuity and Home behavior

- **Behavioral RED:** add/strengthen tests that exercise one provider/timeline across Home, floating/PTT/voice; owner switch; multi-chat on/off; per-chat drafts; Home send/stop/error states; no Connect/auth/lifetime UI; capture/listening; explicit mode semantics; responsive/reduced-motion/Escape behavior. Tests must fail for any currently unguarded retained contract, not because production is intentionally broken.
- **Why RED now:** current coverage is split across page/source tripwires, generic error is not rendered by Home, explicit named listening choices are absent, and cloud/session behavior can satisfy tests without proving offline local authority.
- **Minimum GREEN:** characterization seams/fakes call production reducers/providers and describe the existing retained behavior. Do not migrate authority yet.
- **Protected behavior:** invariants 1–3 and 9–15.
- **Expected files:** existing tests listed in §7, especially `ChatTimelineContinuityTests.swift`, `ChatConversationSwitchTests.swift`, `ChatDraftStoreTests.swift`, `ChatErrorStateTests.swift`, `DashboardCaptureStateTests.swift`, `HomeAskFocusPolicyTests.swift`, `HomeRedesignRegressionTests.swift`, `HomeStageCloseSemanticsTests.swift`, `OneAssistantChatContractTests.swift`, `TopNavigationBarLayoutTests.swift`; **[new]** `HomeChatAuthorityTests.swift` only if no existing suite is a truthful owner.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'HomeChatAuthorityTests'`; run the exact affected existing XCTest classes through the same command; `./scripts/agent-logic-harness.sh --cross-surface-smoke`.
- **Deletion unlocked:** none.
- **Stop condition:** any retained invariant cannot be exercised through a production seam, or the starting tests expose an unexplained regression.

### Cycle 2 — Establish the local catalog in the Node authority

- **Behavioral RED:** Node tests create/list/update/delete chats for two owners; prove idempotent create, `default`, ordering, derived preview/count/activity, star, automatic/manual title precedence, restart, and atomic delete.
- **Why RED now:** `KernelSessions.listSessions` is internal; `sessions` lacks `title_origin` and `starred`; no public catalog protocol exists.
- **Minimum GREEN:** add the two constrained columns to `sessions`; implement **[new]** `LocalChatSummary` and the four owner-scoped JSONL operations over `KernelSessions`/`ConversationJournal`; derive presentation fields from accepted visible turns.
- **Protected behavior:** existing `resolveSurfaceSession` mapping and journal continuity; no duplicate chat table.
- **Expected production files:** `agent/src/runtime/sqlite-store.ts`, `kernel-sessions.ts`, `surface-session.ts`, `conversation-journal.ts`, `agent/src/protocol.ts`, `agent/src/index.ts`.
- **Expected tests/docs:** **[new]** `agent/tests/chat-catalog.test.ts`; adapt `sqlite-store.test.ts`, `surface-session.test.ts`, `conversation-journal.test.ts`, `protocol-v2.test.ts`, `jsonl-transport.test.ts`; update `agent/src/ARCHITECTURE.md`.
- **Focused verification:** `cd desktop/macos/agent && npm test -- tests/chat-catalog.test.ts tests/sqlite-store.test.ts tests/protocol-v2.test.ts && npm run build`.
- **Deletion unlocked:** none; backend remains available while the new authority is proved.
- **Stop condition:** catalog metadata needs a second store, owner is optional, derived values disagree with journal replay, or a retry can create two chats.

### Cycle 3 — Migrate `ChatProvider` to the local catalog

- **Behavioral RED:** Swift tests drive the real runtime-client seam and expect fetch/create/select/rename/star/delete/restart without `APIClient+ChatSessions` CRUD; multi-chat-off exposes only stable `default`; manual rename wins over an in-flight automatic title.
- **Why RED now:** `ChatProvider` methods call backend Chat-session APIs and `ChatSession` is server-shaped.
- **Minimum GREEN:** map catalog receipts to a local summary model, preserve public `ChatProvider` behavior where useful, generate IDs client-side, and make all catalog mutations wait for local receipts. Search/grouping stay Swift-only.
- **Protected behavior:** current selected-chat recovery, drafts, in-flight send cancellation/selection rules, and one `ChatProvider.mainInstance`.
- **Expected production files:** `Providers/ChatProvider.swift`, `Chat/AgentRuntimeProcess.swift`, `Chat/AgentBridge.swift`, and protocol DTO plumbing; **[new]** Swift catalog DTO/client file only if keeping it out of the provider creates a deeper boundary.
- **Expected tests:** adapt `ChatConversationSwitchTests.swift`, `ChatDraftStoreTests.swift`, `ChatTimelineContinuityTests.swift`, `KernelContractWireTests.swift`; **[new]** `LocalChatCatalogTests.swift`.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'LocalChatCatalogTests'`; `python3 scripts/dev-feedback.py --once swift 'ChatConversationSwitchTests'`; `./scripts/agent-logic-harness.sh --cross-surface-smoke`.
- **Deletion unlocked:** backend session CRUD callers can be marked unreachable, but files/routes remain until Cycle 10.
- **Stop condition:** any catalog action succeeds optimistically without a local receipt, default/single-chat behavior changes, or a Swift shadow store becomes authoritative.

### Cycle 4 — Put the complete compact catalog in canonical Home

- **Behavioral RED:** Home tests and bridge E2E cover New, select, search, star filter, rename, star/unstar, confirmed delete, selection fallback, empty new thread, and multi-chat-off behavior while asserting the same timeline/composer instance.
- **Why RED now:** the complete catalog lives in `ChatSessionsSidebar`/`ChatPage`; Home has the chat stage but not the full catalog.
- **Minimum GREEN:** present the catalog inside `DashboardPage`, reusing/extracting `ChatSessionsSidebar` behavior without a second Chat page; route retained Home automation through it.
- **Protected behavior:** Home Ask/editor/stop, `MainChatNavigationRequestStore`, compact stage, no Connect, static empty welcome.
- **Expected production files:** `DashboardPage.swift`, `ChatSessionsSidebar.swift`, `MainChatNavigationRequest.swift`, `DesktopAutomationBridge.swift`, `Providers/ChatProvider.swift`, `ViewExporter.swift`.
- **Expected tests/flows:** `HomeRedesignRegressionTests.swift`, `HomeStageCloseSemanticsTests.swift`, `ChatConversationSwitchTests.swift`, **[new]** `HomeChatCatalogTests.swift`; update `e2e/flows/home-stage.yaml` and `chat-hermetic.yaml`.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'HomeChatCatalogTests'`; `python3 scripts/omi-harness run e2e/flows/home-stage.yaml --lane bridge` against the test harness.
- **Deletion unlocked:** duplicate catalog presentation can be removed in Cycle 14 only after error/modals/navigation are also migrated.
- **Stop condition:** Home creates a second provider/timeline, a catalog action is unavailable, or automation bypasses the same production action.

### Cycle 5 — Make greeting compute transient and local-persisted

- **Behavioral RED:** backend tests require auth, bounded `profile_text`/`memories`, timeout/rate/count-only behavior, GPT-5.4-mini selection, `{message}` only, and a data-store spy proving zero Chat reads/writes. Swift tests require Mac-assigned ID, local journal admission, nonfatal failure, and no title trigger.
- **Why RED now:** `/v2/chat/initial-message` accepts a session ID, reads backend profile/memory, and creates a backend message through `initial_message_util`.
- **Minimum GREEN:** adapt that exact route and client; build bounded context from S-10/S-12 locally; journal the response through the normal accepted-turn seam. Do not introduce a second route.
- **Protected behavior:** usable empty welcome/composer on error, owner isolation, no raw PII logging.
- **Expected production files:** `backend/routers/chat_sessions.py`, `backend/utils/chat.py`, `backend/utils/llm/chat.py`, `backend/utils/llm/model_config.py`, `Services/APIClient/APIClient+ChatSessions.swift` or a truthfully renamed client, `Providers/ChatProvider.swift`.
- **Expected tests/contracts:** **[new]** `backend/tests/unit/test_s11_chat_compute.py::test_initial_message_is_stateless`; **[new]** `ChatGreetingTests.swift`; model gateway configuration/QoS tests; OpenAPI/route policy only if this route belongs to the app-client surface.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once python 'tests/unit/test_s11_chat_compute.py::test_initial_message_is_stateless'`; `python3 scripts/dev-feedback.py --once swift 'ChatGreetingTests'`.
- **Deletion unlocked:** persisted `initial_message_util` Chat branch and greeting message/session DTO fields.
- **Stop condition:** handler imports a product-data repository, accepts server session/message identity, emits unbounded context, persists/logs content, or model configuration can select a different model.

### Cycle 6 — Make title compute transient and locally authoritative

- **Behavioral RED:** backend tests require auth, only the first user/assistant texts, bounds/timeout/rate/count-only behavior, Gemini 2.5 Flash-Lite in every config profile, `{title}` only, and zero Chat-store access. Swift/Node tests prove first-real-exchange timing, six words, fallback, restart, and manual-rename compare-and-set.
- **Why RED now:** `/v2/chat/generate-title` accepts session/history and mutates backend session state; `session_titles` is not the required pinned contract.
- **Minimum GREEN:** adapt that exact handler/client; locally normalize to six words; persist through `chat_catalog_update` with expected title origin `default`.
- **Protected behavior:** greeting excluded from trigger; no retry can overwrite `manual`; title failure never blocks the accepted exchange.
- **Expected production files:** `backend/routers/chat_sessions.py`, `backend/utils/llm/model_config.py`, the retained/renamed Swift transient compute client, `Providers/ChatProvider.swift`, `agent/src/runtime/kernel-sessions.ts`.
- **Expected tests/contracts:** **[new]** `backend/tests/unit/test_s11_chat_compute.py::test_generate_title_is_stateless`, **[new]** `ChatAutomaticTitleTests.swift`, `agent/tests/chat-catalog.test.ts`, gateway config/QoS tests, route/OpenAPI contracts if applicable.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once python 'tests/unit/test_s11_chat_compute.py::test_generate_title_is_stateless'`; `python3 scripts/dev-feedback.py --once swift 'ChatAutomaticTitleTests'`; `cd agent && npm test -- tests/chat-catalog.test.ts`.
- **Deletion unlocked:** backend session-title mutation and full-history request DTOs.
- **Stop condition:** title generation receives IDs/history beyond the first pair, has a persistence import, or manual rename can lose a race.

### Cycle 7 — Materialize and retain local attachments

- **Behavioral RED:** select and paste tests prove materialize-before-journal, owner/chat path isolation, four-file cap, text-required send, MIME/name/URI/presentation retention, first-image bytes, source disappearance, restart, failed copy/send, delete, and shared-reference-safe GC.
- **Why RED now:** normal Chat waits for `/v2/files`; resource durability can depend on server ID/GCS/OpenAI Files and the original URL.
- **Minimum GREEN:** add **[new]** owner/chat attachment store beneath `DesktopLocalProfile.applicationSupportURL()/ChatAttachments/v1`; copy atomically; write managed `file://` `ChatResource`s; pass existing `AgentQueryAttachment`; GC only after scanning surviving journal resources.
- **Protected behavior:** never delete source paths; no bytes cross owners; local attachment failure remains recoverable and cannot journal a dangling resource.
- **Expected production files:** `Chat/ChatAttachment.swift`, `Chat/ChatResource.swift`, `Chat/AgentBridge.swift`, `Providers/ChatProvider.swift`; **[new]** `Chat/LocalChatAttachmentStore.swift`.
- **Expected tests:** adapt `ChatResourceTests.swift`, `ChatJournalWritePathTests.swift`, `ChatDraftStoreTests.swift`; **[new]** `LocalChatAttachmentStoreTests.swift` and Home attachment cases.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'LocalChatAttachmentStoreTests'`; `python3 scripts/dev-feedback.py --once swift 'ChatResourceTests'`; `python3 scripts/dev-feedback.py --once swift 'ChatJournalWritePathTests'`.
- **Deletion unlocked:** normal Chat `/v2/files` client usage and server upload wait.
- **Stop condition:** the journal can reference an unmanaged/or missing file, GC lacks a complete surviving-reference scan, or a source file can be removed.

### Cycle 8 — Prove local authority before deletion

- **Behavioral RED:** an offline integration fixture fails every normal Chat persistence endpoint and then performs create/switch/rename/star/delete/reopen, attachment send/reopen, process restart, owner A→B→A, typed→voice→typed continuity, and managed-Pi local recall.
- **Why RED now:** projection/reconcile/import paths can conceal missing local behavior, and current attachment/catalog authority is remote.
- **Minimum GREEN:** all scenarios pass using only local catalog/journal/attachment stores; transient inference may be stubbed hermetically, while managed-Pi wiring is exercised through its controllable seam.
- **Protected behavior:** all invariants in §9.
- **Expected files:** **[new]** Swift/Node integration tests under existing test roots; `e2e/flows/chat-hermetic.yaml`; existing continuity tests and offline harness fixtures. Production changes should be fixes to Cycles 2–7, not a fallback layer.
- **Focused verification:** `cd desktop/macos && ./scripts/agent-logic-harness.sh --cross-surface-smoke`; `python3 scripts/omi-harness run e2e/flows/chat-hermetic.yaml --lane bridge`; `cd desktop/macos/agent && npm test -- tests/chat-continuity-invariant.test.ts tests/cross-surface-contract-smoke.test.ts`.
- **Deletion unlocked:** Cycles 9–11. No remote-authority deletion occurs before this gate is green.
- **Stop condition:** any scenario needs `/v2/chat-sessions*`, `/v2/desktop/messages*`, `/v2/files`, legacy import, reconciliation, or backend product-data reads.

### Cycle 9 — Delete projection, reconciliation, and legacy session import

- **Behavioral RED:** invert production-boundary tests so any `journal_backend_sync/delete/reconcile`, projection-pump startup, remote hydrate, or `import_legacy_main_chat_sessions` request fails; keep continuity tests green.
- **Why RED now:** these protocols, drivers, tables, pumps, and handlers still compile and may run.
- **Minimum GREEN:** remove Swift driver/API/result handling, Node protocol/pump/outbox/reconcile state, backend-message import, and main-chat alias migration. Drop exclusively owned SQLite tables in the schema upgrade with no customer compatibility path.
- **Protected behavior:** journal writes/replay, surface mapping, local catalog, direct voice persistence, owner isolation.
- **Expected production files:** `Chat/APIClient+KernelJournal.swift`, `Chat/KernelJournalBackendSyncDriver.swift`, `Chat/AgentRuntimeProcess.swift`, `Chat/AgentBridge.swift`, `Providers/ChatProvider.swift`, Node `protocol.ts`, `index.ts`, `backend-turn-projection.ts`, `sqlite-store.ts`.
- **Expected tests/docs:** delete `KernelJournalBackendReconcileTests.swift`, `KernelJournalBackendDeleteTests.swift`, `LegacyMainChatSessionAliasMigrationTests.swift`; replace `KernelTurnRecordedProjectionTests` with local-only authority assertions; update Node protocol/schema tests, `desktop/macos/AGENTS.md`, and `agent/src/ARCHITECTURE.md`.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'ChatTimelineContinuityTests'`; `./scripts/agent-logic-harness.sh --cross-surface-smoke`; `cd desktop/macos/agent && npm test && npm run build`.
- **Deletion unlocked:** backend `/v2/desktop/messages*` and legacy session/message storage routes.
- **Stop condition:** a retained non-Windows surface still owns an outbox row/protocol call, or removal breaks direct voice/typed continuity.

### Cycle 10 — Delete normal Chat cloud storage APIs and contracts

- **Behavioral RED:** router/route-policy/OpenAPI tests require absence (404, not retained 410) of `/v2/chat-sessions*`, `/v2/desktop/messages*`, normal rating, `/v1/users/stats/chat-messages`, and ordinary `/v2/files` use; retained compute/report/STT and `/v1/files` tests remain green.
- **Why RED now:** `chat_sessions.py`, `chat.py`, `desktop_deprecated.py`, generated contracts, clients, models, and database helpers still expose or reference them.
- **Minimum GREEN:** delete route handlers/DTOs/clients and per-function Firestore helpers proven exclusive; regenerate app-client contracts; remove S-11 route-policy missing baselines. Preserve independently called report, voice STT, export/account deletion, and `/v1/files` surfaces.
- **Protected behavior:** authenticated `/v2/chat/completions`, adapted greeting/title, monthly quota/account usage, report endpoints, voice STT.
- **Expected production/contracts:** backend files and generated/route-policy files in §7; `Services/APIClient/APIClient+ChatSessions.swift`, `APIClient+Messages.swift` after retained-code extraction.
- **Expected tests:** delete/rewrite obsolete session/projection/count/rating tests; adapt `test_desktop_migration.py`, route policy/OpenAPI tests, file-upload security tests, and retained report/desktop-chat tests. New route-absence tests must invoke the mounted apps.
- **Focused verification:** from `desktop/macos`, run `python3 scripts/dev-feedback.py --once python 'tests/unit/test_s11_chat_route_absence.py'`, then the existing `test_desktop_migration.py`, `test_openapi_contract.py`, `test_route_policy_inventory.py`, and `test_desktop_chat.py` files one at a time through the same Python runner; run the exact OpenAPI/route commands in §14.
- **Deletion unlocked:** dead database/model/file helpers and exclusive operational scripts after residue proof.
- **Stop condition:** a helper’s remaining caller belongs to voice/report/export/account deletion/S-24, a removed route returns 410/200, or retained compute loses auth/rate/quota behavior.

### Cycle 11 — Delete obsolete hosted Chat persona/RAG/extraction

- **Behavioral RED:** mounted-router and dependency tests prove ordinary desktop Chat reaches managed Pi `/v2/chat/completions`, while old `/v2/messages` persona/RAG/extraction flow cannot be reached; retained report/PTT/STT/file owners still pass.
- **Why RED now:** `backend/routers/chat.py`, `backend/utils/chat.py`, `backend/utils/llm/chat.py`, `model_config.py`, and `retrieval/graph.py` contain old hosted paths; there is no literal `chat_graph` symbol to delete.
- **Minimum GREEN:** remove only caller-free normal-Chat branches, `chat_extraction`, and `execute_graph_chat` after all call sites are gone. Preserve managed Pi, local tools/retrieval, adapted greeting/title, PTT/STT, and reports.
- **Protected behavior:** IR-731 retained list and one-assistant invariant.
- **Expected production files:** `backend/routers/chat.py`, `backend/utils/chat.py`, `backend/utils/llm/chat.py`, `backend/utils/llm/model_config.py`, `backend/utils/retrieval/graph.py`, exclusive scripts from §7.
- **Expected tests:** retire old hosted-Chat tests only with their production path; retain/adapt `_chat_router_test_harness.py`, `test_desktop_chat.py`, voice/report tests; remove `test_llm_gateway_chat_extraction_pilot.py`, gateway config/route-ref/client tests, and integration QoS expectations only with the retired feature, preserving unrelated cases in mixed files.
- **Focused verification:** from `desktop/macos`, run `python3 scripts/dev-feedback.py --once python 'tests/unit/test_desktop_chat.py'` and each retained report/voice test found by §13; run §13 call-site searches and the full backend suite before deletion is accepted.
- **Deletion unlocked:** dead imports, configs, and scripts with zero non-Windows callers.
- **Stop condition:** a retained report/voice path shares the candidate function, or managed Pi/local retrieval coverage is not green.

### Cycle 12 — Make Home content local and stable

- **Behavioral RED:** Home tests require exact local task count, Focus claim, task/Insight/question diversity, functional local Insight open/read/dismiss, task navigation without authority mutation, stable ordering without timer rotation, once/day per-owner caching, bounded local context, and no remote API fallback.
- **Why RED now:** `DashboardIntelligenceStore` owns actionable recommendation behavior, local Insight actions are no-ops from Home, rotation is timer-driven, and `GeminiHomeSuggestionGenerator` fetches remote product data.
- **Minimum GREEN:** add narrow local source protocols/adapters over integrated S-10/S-12 and current `ActionItemStorage`/`GoalStorage`; reuse `HomeSuggestionsStore` owner/day cache; wire Insight actions; extract `TaskNavigationRequestStore`; remove rotation state.
- **Protected behavior:** contextual editable prefill, typed rows, task navigation, Focus wording, owner/day isolation, suggestion failure fallback.
- **Expected production files:** `DashboardPage.swift`, `HomeSuggestionsStore.swift`, `HomeKnowsComposer.swift`, `DashboardIntelligenceStore.swift`, **[new]** `TaskNavigationRequestStore.swift`, `InsightStorage.swift`, `FocusStorage.swift`, `ActionItemStorage.swift`, `GoalStorage.swift`; predecessor local query files as adapters only.
- **Expected tests:** adapt `HomeSuggestionsStoreTests.swift`, `HomeKnowsComposerTests.swift`, `DashboardIntelligenceStoreTests.swift`, `HomeAskFocusPolicyTests.swift`; **[new]** `HomeLocalSourceTests.swift` and Insight action behavior cases.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'HomeLocalSourceTests'`; run `HomeSuggestionsStoreTests`, `HomeKnowsComposerTests`, and `HomeAskFocusPolicyTests` filters.
- **Deletion unlocked:** `DashboardIntelligenceStore` cloud client/outbox/automation, remote suggestion reads, rotation timer.
- **Stop condition:** any local source is unavailable and code proposes a backend fallback, prompt input is unbounded, or Insight/task actions require cloud acknowledgement.

### Cycle 13 — Complete retained Home controls, errors, attachments, layout, and theme

- **Behavioral RED:** UI/state tests cover generic plus structured error rendering/retry, text-required attachment send, send/stop, explicit `Meetings Only`/`Always`, capture/listening exact semantics, width caps, narrow layout, reduced motion, monthly quota, neutral shared tokens, and absence of lifetime/auth/Connect UI.
- **Why RED now:** Home omits generic `errorMessage`; listening mode is hover-only; Home owns private palette tokens; lifetime cost nudge still initializes from `ChatProvider`.
- **Minimum GREEN:** render the missing fallback, expose named mode choices without changing capture logic, consume shared `OmiColors`, and remove the lifetime-cost request/alert while retaining `FloatingBarUsageLimiter` monthly quota.
- **Protected behavior:** `CaptureListeningLogic`, Ask bounds, compact top bar, composer/draft/attachment semantics, no purple.
- **Expected production files:** `DashboardPage.swift`, `ChatErrorCard.swift`, `CaptureListeningControls.swift` and/or existing Home controls, `Theme/OmiColors.swift`, `Providers/ChatProvider.swift`, `DesktopTopBar.swift` only if needed for retained layout.
- **Expected tests/flows:** `ChatErrorStateTests.swift`, `DashboardCaptureStateTests.swift`, `HomeRedesignRegressionTests.swift`, `TopNavigationBarLayoutTests.swift`, Home attachment tests, `home.yaml`, `home-stage.yaml`.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'ChatErrorStateTests'`; run `DashboardCaptureStateTests`, `HomeStageCollapseCatcherTests`, and `TopNavigationBarLayoutTests`; `python3 scripts/omi-harness run e2e/flows/home.yaml --lane bridge`.
- **Deletion unlocked:** page-only lifetime/auth/error UI and `HomePalette`.
- **Stop condition:** capture/listening state transitions change, generic errors disappear, monthly quota is removed, or any purple token/color is introduced.

### Cycle 14 — Delete duplicate Home/Chat shell and cloud-only residue

- **Behavioral RED:** navigation/automation tests require semantic `chat` to open Home’s chat stage, `.chat` page route absence without raw-value renumbering, Escape behavior, compact navigation, no aggregate counters/badges, no Home goals/intelligence/status/legacy-design branch, and no retired exports.
- **Why RED now:** `SidebarNavItem.chat`, `PageContentView` case 2, `ChatPage`, goals sheets, legacy Home branch/settings, `HomeStatusStore`, and top-bar counters remain.
- **Minimum GREEN:** redirect semantic Chat navigation through `.dashboard` plus `MainChatNavigationRequestStore`; delete duplicate page/catalog/modal paths and cloud-only Home owners; remove counter-only warmups; retain conversation/folder warmup if Memory Hub still owns it.
- **Protected behavior:** persisted raw values of remaining nav items, Escape-to-Home, capture/settings in compact top bar, Home automation names, selected chat/timeline.
- **Expected production files:** `ChatPage.swift` (delete), `ChatSessionsSidebar.swift` (delete/rename after consolidation), `DashboardPage.swift`, `DesktopHomeView.swift`, `SidebarView.swift`, `DesktopTopBar.swift`, `MainChatNavigationRequest.swift`, `DesktopAutomationBridge.swift`, `ViewExporter.swift`, settings files in §7, `DashboardIntelligenceStore.swift` (delete after extraction), `HomeStatusStore.swift` (delete), Home goal components only if zero other callers.
- **Expected tests/flows:** update/delete stale page/store tests; adapt `HomeRedesignRegressionTests.swift`, `HomeStageCloseSemanticsTests.swift`, `TopNavigationBarLayoutTests.swift`, automation tests, `navigation.yaml`, `chat-hermetic.yaml`.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'MainChatNavigationRequestStoreTests'`; run `HomeStageCloseSemanticsTests` and `TopNavigationBarLayoutTests`; `python3 scripts/omi-harness run e2e/flows/navigation.yaml --lane bridge`.
- **Deletion unlocked:** all zero-caller page wrappers, previews, settings, modals, counters, and UI helpers identified by §13.
- **Stop condition:** any retained raw navigation value changes, a semantic Chat action opens nothing, or removed Home stores still own user-visible data not handed off.

### Cycle 15 — Delete legacy voice import and close residue/docs

- **Behavioral RED:** voice continuity tests require typed→voice→typed replay after restart with no importer invocation, importer state, legacy history read, or protocol alias. Residue tripwires require zero scoped hits.
- **Why RED now:** `LegacyVoiceJournalImporter.swift`, lifecycle state/invocation, its tests, and legacy main-chat compatibility types still exist.
- **Minimum GREEN:** remove importer/state/tests and remaining S-11 compatibility metadata; keep direct writes in `RealtimeHubController+StreamingJournal`, `+SessionDelegate`, `VoiceTurnCoordinator`, and the common surface mapping. Update owner docs and API references.
- **Protected behavior:** direct authenticated PTT/voice journal persistence, replay, owner isolation, and floating/Home continuity.
- **Expected production/tests/docs:** delete `LegacyVoiceJournalImporter.swift` and `LegacyVoiceJournalImporterTests.swift`; edit `RealtimeHubController.swift`, `RealtimeHubController+SessionLifecycle.swift`, relevant Chat legacy types, `desktop/macos/AGENTS.md`, `agent/src/ARCHITECTURE.md`, and relevant API/product docs.
- **Focused verification:** `cd desktop/macos && python3 scripts/dev-feedback.py --once swift 'ChatTimelineContinuityTests'`; `./scripts/agent-logic-harness.sh --cross-surface-smoke`; run all §13 residue commands.
- **Deletion unlocked:** zero-caller compatibility types and comments identified by the residue ledger.
- **Stop condition:** the direct voice path is not independently green, or any residue hit is unexplained/unowned.

### Cycle 16 — Full repository and named-bundle closure

- **Behavioral RED:** none is manufactured. This is the acceptance gate; any failure reopens its owning cycle.
- **Why RED now:** the gate begins red if any focused suite, whole-component contract, generated check, real app lifecycle, auth/model routing, or deletion-residue proof is missing or failing.
- **Minimum GREEN:** all §14 commands pass; §15 named-bundle scenarios are exercised and recorded; §13 has only classified allowed hits; repository/live closure is recorded per §16.
- **Protected behavior:** every invariant and assigned IR.
- **Expected files:** no new production behavior in this cycle; only fixes in the owning earlier cycle, verification evidence, and required docs/changelog/PR material.
- **Focused verification:** all commands in §§14–15, then `make preflight`, `scripts/pr-preflight --suggest`, the ledger validator, and `git diff --check`.
- **Deletion unlocked:** none beyond explicitly authorized repository cleanup. Live data/infrastructure deletion remains prohibited.
- **Stop condition:** any suite, generated check, route absence check, named-bundle scenario, residue classification, or documentation contract is incomplete.

## 12. Cross-slice ownership and handoffs

| Slice | S-11 relationship | Handoff boundary |
|---|---|---|
| S-05 / S-06 / S-07 | Hard predecessors | S-11 consumes owner identity, one-assistant managed Pi, and journal continuity; it does not recreate them. |
| S-10 / S-12 | Hard predecessors | S-10 supplies bounded local conversation queries; S-12 supplies bounded local Memory queries. S-11 must stop if either source is absent, not add cloud fallbacks. |
| S-13 | Later task/goal authority | S-11 reads current local `ActionItemStorage`/`GoalStorage`, removes Home goal presentation, and avoids final storage redesign. |
| S-14 | Later Focus/Insight/Profile authority and presentation | S-11 makes Home actions local and removes Dashboard intelligence, but leaves final replacement of `FocusStorage`/`InsightStorage` internals and consolidated Insight/Focus/Profile UI to S-14. |
| S-21 | Broader shell | S-11 deletes only the duplicate Chat destination and Home-owned legacy branch; S-21 owns unrelated shell restructuring. |
| S-22 | Global model portfolio | S-11 pins only greeting/title workloads to the assigned models and records any temporary feature keys for S-22 normalization. |
| S-23 | Final backend product data/shared schema/account deletion | S-11 removes normal Chat route authority; helpers/collections retained for report, voice, export, or account deletion are explicitly handed to S-23. |
| S-24 | Global vector/object storage | S-11 removes ordinary Chat `/v2/files` use but retains `/v1/files` and shared storage helpers with an explicit S-24 ledger. |
| S-26 | Backend service consolidation | S-11 updates `desktop_deprecated` S-11 route entries but does not consolidate `main.py`/`desktop_backend.py`. |
| S-28 | Product storage namespaces | S-11 uses existing local profile/session namespace conventions and does not perform the global namespace migration. |
| S-30 | Product identity/copy | S-11 keeps an accessible static empty welcome and removes duplicate copy; S-30 owns the final literal identity and wording. |

For every retained backend function/table/object path, the implementation PR must name its live caller and later owner. “Shared” without a file/symbol and slice is not a valid handoff.

## 13. Exact residue-search commands and hit classification

Run from repository root before Cycle 1, after each deletion cycle, and at Cycle 16. Exclude Windows and immutable Git history. Save the final outputs in the PR evidence. Every hit must be classified as retained production, retained test/contract, immutable migration evidence, Windows/out of scope, or a named later-slice handoff; unexplained hits fail the gate.

```bash
rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(/v2/chat-sessions|/v2/desktop/messages|journal_backend_(sync|delete|reconcile)|import_legacy_main_chat_sessions|KernelJournalBackendSyncDriver|LegacyMainChatSessionAliasMigration)' \
  backend desktop/macos docs scripts

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(backend_turn_outbox|backend_conversation_delete_outbox|backend_reconcile_state|runLocalOnlyJournalDeliveryMigration|importLegacyBackendMessagesIfNeeded)' \
  desktop/macos backend

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(LegacyVoiceJournalImporter|importLegacyVoiceJournalIfNeeded|ChatLegacyCompatibilityMetadata|ChatLegacyPageCollector|ChatLegacyImportChronology)' \
  desktop/macos

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(ChatPage|ChatSessionsSidebar|SidebarNavItem\.chat|case[[:space:]]+\.chat|useLegacyHomeDesign|HomeStatusStore|DashboardIntelligenceStore|HomePalette)' \
  desktop/macos/Desktop

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(home_connect_toggle|Claude|\$50|totalOmiCost|newConversations|newMemories|newTasks|memoryBadge|newCount)' \
  desktop/macos/Desktop

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(/v2/files|ChatFileResponse|uploadFile|serverId|message.*rating|RateMessageRequest|chat-messages)' \
  backend desktop/macos docs scripts

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(chat_extraction|execute_graph_chat|initial_message_util|initial_chat_message|session_titles|chat_responses)' \
  backend desktop/macos

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(/v2/chat/initial-message|/v2/chat/generate-title|/v2/chat/completions|/v[12]/messages/.*/report|/v1/files)' \
  backend desktop/macos docs

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(getMemories|getConversations|getActionItems|getGoals|rotation|canRotate)' \
  desktop/macos/Desktop/Sources/MainWindow/Dashboard \
  desktop/macos/Desktop/Sources/MainWindow/Pages/DashboardPage.swift

rg -n --glob '!**/windows/**' --glob '!bootstrap-scaffold/**' \
  '(purple|Purple|#[0-9A-Fa-f]{6,8})' \
  desktop/macos/Desktop/Sources/MainWindow/Pages/DashboardPage.swift \
  desktop/macos/Desktop/Sources/Theme
```

Also run symbol-level caller searches before deleting shared backend helpers:

```bash
rg -n --glob '!**/windows/**' 'from (database|utils).*chat|import (database|utils).*chat|database\.chat|chat\.' backend
rg -n --glob '!**/windows/**' '(add_message|get_messages|delete_chat_session|save_chat_session|get_chat_sessions|save_chat_file|report_message)' backend
rg -n --glob '!**/windows/**' '(messages|chat_sessions|files)' backend/scripts backend/routers backend/database backend/utils
```

The expected final retained route hits are `/v2/chat/completions`, adapted `/v2/chat/initial-message`, adapted `/v2/chat/generate-title`, retained report routes, voice STT routes, and `/v1/files` until S-24. The expected final `chat_responses`/`session_titles` hits must be either the exact pinned transient workloads or an S-22 handoff; `chat_extraction`, `execute_graph_chat`, projection/import symbols, duplicate page symbols, and legacy importer symbols must have zero scoped production hits.

## 14. Focused, component, generated, and repository verification

Use focused commands during each cycle, then run every closure command below. Commands are verified against the current checkout; selectors added by this plan are marked by their **[new]** test names in §11.

### Focused desktop and Node loops

```bash
cd desktop/macos
python3 scripts/dev-feedback.py --once swift 'LocalChatCatalogTests'
python3 scripts/dev-feedback.py --once swift 'HomeChatCatalogTests'
python3 scripts/dev-feedback.py --once swift 'ChatTimelineContinuityTests'
python3 scripts/dev-feedback.py --once swift 'LocalChatAttachmentStoreTests'
python3 scripts/dev-feedback.py --once swift 'HomeSuggestionsStoreTests'
./scripts/agent-logic-harness.sh --cross-surface-smoke

cd agent
npm test -- tests/chat-catalog.test.ts tests/chat-continuity-invariant.test.ts tests/cross-surface-contract-smoke.test.ts
npm run build
```

### Focused backend loops

```bash
cd desktop/macos
python3 scripts/dev-feedback.py --once python 'tests/unit/test_s11_chat_compute.py'
python3 scripts/dev-feedback.py --once python 'tests/unit/test_s11_chat_route_absence.py'
python3 scripts/dev-feedback.py --once python 'tests/unit/test_desktop_chat.py'
python3 scripts/dev-feedback.py --once python 'tests/unit/test_desktop_migration.py'
python3 scripts/dev-feedback.py --once python 'tests/unit/test_openapi_contract.py'
python3 scripts/dev-feedback.py --once python 'tests/unit/test_route_policy_inventory.py'
python3 scripts/dev-feedback.py --once python 'tests/unit/test_file_upload_endpoint_security.py'
python3 scripts/dev-feedback.py --once python 'tests/unit/test_file_upload_security.py'
```

### Generated API and route policy

```bash
cd backend
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
scripts/openapi_runner.sh scripts/route_policy_inventory.py --manifest route_policy_manifest.yaml --check --enforce-missing-baseline
```

### Component and cross-surface closure

```bash
cd desktop/macos/agent
npm test
npm run build

cd ../../..
cd desktop/macos
./test.sh
./scripts/agent-logic-harness.sh --cross-surface-smoke
python3 scripts/desktop-flow-lint.py

cd ../../backend
./test.sh
```

### Hermetic bridge flows

```bash
cd desktop/macos
python3 scripts/omi-harness run e2e/flows/home.yaml --lane bridge
python3 scripts/omi-harness run e2e/flows/home-stage.yaml --lane bridge
python3 scripts/omi-harness run e2e/flows/chat-hermetic.yaml --lane bridge
python3 scripts/omi-harness run e2e/flows/navigation.yaml --lane bridge
```

### Repository contracts

```bash
cd ../..
make preflight
scripts/pr-preflight --suggest
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
```

Before a `fix:` commit/PR, follow the emitted failure-class guidance and validate the required `Failure-Class` declaration with `scripts/failure-class`. Record commands and outcomes in the commit/PR evidence. A static source checker cannot substitute for any behavioral command above.

## 15. Named-bundle acceptance

Never touch `/Applications/Omi.app`, `/Applications/Omi Beta.app`, or their production bundle IDs. Use the dedicated test bundle `omi-s11-chat-home` (`com.omi.omi-s11-chat-home`).

Prepare the local/offline harness and first full bundle:

```bash
PROVIDER_MODE=offline make dev-up
make desktop-run-local DESKTOP_APP_NAME=omi-s11-chat-home DESKTOP_USER=alice
```

For a live transient-inference pass against the worktree backend, after credentials are available and without production bundles:

```bash
cd desktop/macos
OMI_APP_NAME=omi-s11-chat-home OMI_SKIP_BACKEND=0 OMI_SKIP_TUNNEL=1 ./run.sh --full
```

For subsequent Swift-only iteration, reuse the named bundle:

```bash
cd desktop/macos
OMI_APP_NAME=omi-s11-chat-home ./run.sh --yolo --fast-only
```

Acceptance script, performed through the real UI/automation bridge and verified with UI plus local logs/database receipts:

1. Confirm `./scripts/omi-ctl health` reports the named bundle, expected backend, and negotiated agent protocol.
2. Open Home; verify no separate Chat nav item, goals strip, Connect tray, counters/badges, lifetime nudge, or Claude-auth sheet.
3. With multi-chat off, send and stop a message in `default`; verify draft restoration, generic and structured errors, attachments disabled until text, and the static empty welcome on a fresh thread.
4. Enable multi-chat. Create three chats; search, select, rename, star/unstar, filter starred, delete with confirmation, and verify selection fallback. Restart the app and agent; verify titles, star state, previews, counts, selection, drafts, and histories.
5. Create a new chat; verify one greeting is locally journaled. Force greeting failure and verify the welcome/composer remains usable. Complete the first user/assistant exchange; verify a maximum-six-word automatic title. Rename before a delayed title response and prove manual wins.
6. Attach four mixed files including an image; move/delete the original source files after materialization; send and restart; verify previews/resources reopen from Application Support. Delete one chat and prove only unreferenced app-owned copies are collected.
7. Disable/fail `/v2/chat-sessions*`, `/v2/desktop/messages*`, and `/v2/files` in the harness. Repeat create/switch/rename/star/delete/reopen and restart; verify no request or retry is emitted.
8. Switch alice→bob→alice. Prove bob cannot list/hydrate alice’s chats, attachments, or drafts and alice’s state returns intact.
9. Send typed → authenticated natural PTT/voice → typed turns in the same chat and verify one ordered timeline after restart. Do not count a forced transcript or reducer-only test as voice acceptance.
10. Exercise local managed-Pi recall from prior local turns/context while Chat persistence routes remain unavailable.
11. Exercise capture and listening controls, explicit `Meetings Only`/`Always`, Home Ask prefill/edit/send/stop, Insight open/read/dismiss, task navigation, narrow/wide layouts, reduced motion, compact navigation, settings/capture access, and Escape-to-Home.
12. Run live continuity evidence against the named bundle:

```bash
cd desktop/macos
./scripts/agent-continuity-gauntlet.sh --suite continuity --bundle-id com.omi.omi-s11-chat-home
./scripts/check-gauntlet-evidence-at-head.sh block
```

13. Run `make dev-down` only for the worktree-owned harness when acceptance is finished. Do not kill or restart production apps.

Capture the bundle ID, Git SHA, owner IDs used, agent protocol, exact disabled-route fixture, scenario results, log paths, and gauntlet manifest path in PR evidence. Do not assert exact assistant prose.

## 16. Repository closure versus live-operational closure

Repository closure means:

- product code, tests, generated clients/specs, route policies, scripts, docs, and lifecycle wiring no longer expose ordinary backend Chat authority;
- adapted greeting/title routes are stateless and their tests prove no product-data access;
- removed routes fail absent/404 on both mounted backend applications as applicable;
- all repository tests, residue searches, named-bundle acceptance, and preflight gates pass.

Repository closure does **not** prove that live data or infrastructure has been removed. After the repository change is merged, a separately authorized operator must first perform a read-only inventory of:

- Firestore `users/{uid}/messages`, `chat_sessions`, and Chat `files` documents/subcollections;
- GCS Chat thumbnails/objects and OpenAI Files created by the retired `/v2/files` path;
- indexes, dashboards, alerts, scheduled jobs, scripts, secrets, service accounts, or retention/export/account-deletion workflows that mention retired Chat shapes;
- route traffic for every removed endpoint and retained report/voice/file endpoint.

That inventory must classify data by live reader/writer, retention/legal requirement, export/account-deletion dependency, later owner (S-23/S-24), deletion method, rollback/recovery, and evidence window. No live deletion, bucket/index removal, secret revocation, job disablement, or production deploy is authorized by S-11. Operational closure occurs only after explicit approval, backup/retention review, execution, and post-delete traffic/data verification.

## 17. Risks, gates, and mandatory stop points

| Risk | Gate / mitigation | Mandatory stop |
|---|---|---|
| Split-brain catalog and journal | Reuse local `sessions`/`conversation_turns`; derive summary fields; require receipt before UI success. | Any second authoritative Swift/SQLite/Firestore catalog is proposed. |
| Deletion before local completeness | Cycle 8 offline/restart/owner/voice/attachment gate precedes Cycles 9–11. | Any scenario still calls remote persistence/import/reconcile. |
| Manual title race | Node compare-and-set on title origin plus delayed-response test. | Automatic title can overwrite `manual`. |
| Attachment loss or destructive GC | Atomic materialization, journal reference scan, owner root, source-never-delete tests. | A dangling journal URI, cross-owner path, or source deletion is possible. |
| Shared backend helper over-deletion | Per-symbol caller search and explicit S-23/S-24 handoff. | A retained voice/report/export/account-deletion caller exists. |
| Model drift or data leakage | Exact model-profile tests, bounded DTOs, auth/rate/timeout/count-only, data-store/log spies. | Handler reads/writes product stores, logs content, or can select another model. |
| Home scope collision with S-13/S-14/S-21 | Change only S-11 presentation/adapter boundaries; document later owner. | Completing the slice requires redesigning their authority rather than consuming/handover. |
| Navigation compatibility regression | Remove `.chat` without renumbering; behavioral automation/Escape tests. | Existing remaining raw values or deep links change unintentionally. |
| Voice continuity regression | Characterize direct write path, delete importer only last, run natural PTT gauntlet. | Direct voice journal path is not green independently of importer. |
| False confidence from source tests | Behavioral tests and named bundle are required; searches only close residue. | Only string/order assertions prove a user contract. |
| Live data mistaken for repository scope | §16 separation and explicit authorization requirement. | Any destructive cloud/production action is proposed under this slice. |
| Stale predecessor assumptions | Rebase and refresh inventory before Cycle 1. | S-05/06/07/10/12 contracts differ from §§5–7. |
| Scope creep into Windows | All searches/edits exclude Windows. | A Windows change is needed or suggested; hand it to its owner instead. |

Each cycle stops on unexplained pre-existing test failure, a new `TODO`/`FIXME`/`HACK` without an issue, a compatibility layer, an unowned residual caller, or inability to exercise the production seam. Fix the owning cycle; do not add a fallback boolean or observer.

## 18. Final completion checklist

- [ ] S-05, S-06, S-07, S-10, and S-12 are integrated and their consumed contracts are recorded.
- [ ] Baseline/inventory/ledger checks were rerun after rebase; every assigned IR in §4 has implementation and proof.
- [ ] Existing journal/session tables, not a duplicate store, own catalog and accepted turns.
- [ ] Owner-scoped local catalog create/list/update/delete, restart, `default`, order, preview/count, star, and title-origin tests pass.
- [ ] `ChatProvider` has no ordinary backend session/message/file persistence dependency.
- [ ] Home is the sole ordinary Chat host and exposes every IR-525 catalog action when multi-chat is enabled.
- [ ] Greeting and title use the two verified existing endpoints, exact pinned models, bounded stateless DTOs, auth/rate/timeout/count-only, and zero product-data reads/writes.
- [ ] Greeting failure, six-word title fallback, first-real-pair rule, and manual-title race are tested.
- [ ] Local attachments are materialized before journal admission; four-file, source-loss, restart, failure, owner isolation, and safe-GC tests pass.
- [ ] Offline authority proof covers create/switch/rename/star/delete/reopen/attachments/restart/owner switch/managed Pi without remote storage.
- [ ] Projection, outbox, reconcile, backend import, main-chat alias migration, and their obsolete tests/tables/protocols are gone.
- [ ] Normal Chat session/message/rating/file routes and generated clients/contracts are gone; removed routes are absent/404.
- [ ] `/v2/chat/completions`, adapted greeting/title, PTT/STT, reports, monthly quota, and `/v1/files` handoff remain green.
- [ ] Old hosted persona/RAG/extraction paths are gone; no document claims a nonexistent `chat_graph` symbol.
- [ ] Home uses bounded local sources, functional local Insight actions, exact task/Focus behavior, and no timer rotation.
- [ ] Capture/listening, explicit modes, Ask prefill/send/stop, drafts/errors, responsive/reduced-motion layout, neutral theme, and Escape behavior pass.
- [ ] Goals presentation, Dashboard intelligence, Connect residue, lifetime nudge, aggregate badges/counters, legacy Home branch, hidden `ChatPage`, retired exports/modals, and voice importer are gone.
- [ ] Remaining navigation raw values were not renumbered; retained automation opens canonical Home Chat.
- [ ] Every §13 residue hit is zero or explicitly classified with a current symbol and later owner.
- [ ] OpenAPI generation/check and route-policy inventory pass with no stale missing-route baseline.
- [ ] Node `npm test`/build, desktop `./test.sh`, backend `./test.sh`, cross-surface harness, flow lint, and four hermetic flows pass.
- [ ] Named bundle `omi-s11-chat-home` was exercised through all §15 scenarios; continuity gauntlet evidence matches HEAD.
- [ ] `PRODUCT.md`, component `AGENTS.md`, `agent/src/ARCHITECTURE.md`, API docs, and required changelog/PR evidence moved with code.
- [ ] `make preflight`, failure-class/preflight contracts, requirements-ledger validator, and `git diff --check` pass.
- [ ] Repository closure and live-operational closure are recorded separately; no live deletion, deploy, release, push, PR, or merge occurred without its own authorization.
