# S-10 — Make conversations and transcripts local-authoritative

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | S-10 |
| Type | Local-authority adaptation and hosted-conversation surface deletion |
| Assigned output | `bootstrap-scaffold/wave-2/s-10 tdd.md` |
| Assigned requirements | IR-004; IR-020 through IR-023; IR-121 through IR-123; IR-293 through IR-405; IR-727; IR-732 |
| Assigned requirement count | 123 |
| Direct predecessors | S-02 and S-03, already present in the pinned checkout |
| Implementation shape | Thirteen ordered public-seam RED/GREEN cycles |
| Product-code status of this document | Planning only; no product code is changed by S-10 planning |

This document is the execution contract for moving the retained macOS conversation product from a server-owned record plus local cache to one owner-scoped GRDB authority. It covers ambient capture, Quick Note, list/detail/search, folders, speaker labels, local finalization, discard, merge, summary and action-item candidate computation, local deletion, export/read consumers, and deletion of the now-unneeded Mac-to-cloud conversation projection.

## 2. Planning status and pinned baseline

The source audit and every path, symbol, route, schema, workflow, and command named as **current** below were checked against this checkout on 2026-08-16.

- Required baseline: `0d9934c`.
- Inspected HEAD: `0d9934c9d2ed61bd02ac8784e50f56ee816257c3` on `review-wave-1-deletions`.
- `git merge-base --is-ancestor 0d9934c HEAD` returned success.
- `git rev-list --left-right --count HEAD...origin/main` returned `11 0`: this checkout is eleven commits ahead of and zero commits behind the current local `origin/main` ref. The earlier claim that `origin/main` had advanced was false and must not be copied into implementation work.
- `python3 bootstrap-scaffold/validate-requirements-ledger.py` passed with 714 indexed rows, 714 detailed sections, and every row reviewed.
- The only assigned file for this planning task is this file. The neighboring untracked S-11 through S-14 plans are user-owned and must remain untouched.

Before product implementation begins, run `make setup` as required by `AGENTS.md`, then rerun the baseline, ledger, and inventory commands in sections 13 and 14. Stop if the implementation checkout no longer contains `0d9934c`, if an assigned IR changes, or if S-02/S-03 local database ownership has been reverted. Do not switch branches in the current worktree.

Paths marked **(new)** below are intentional implementation outputs whose parent directory and name collision were checked; they are not claimed to exist at this baseline. All other named paths and symbols exist now.

## 3. Outcome

At repository completion:

1. The signed-in Mac owner's `omi.db` is the sole durable authority for conversation identity, transcript segments, retained capture metadata, lifecycle, title/overview/emoji, commitments, starring, folder membership, local speaker labels, merge provenance, and deletion.
2. Capture writes a stable UUID conversation identity and stable UUID segment identities before any provider callback can escape the ingestion boundary. GRDB integer row IDs remain private implementation details.
3. Local Parakeet and managed cloud STT are interchangeable transient segment producers. The cloud socket does not create, name, reconcile, roll over, or finalize a conversation for the Mac.
4. The Conversations list, detail, search, paging, filters, folders, speaker naming, Home counts, citations, automation, downstream AI context, and S-08 export read the local store, including while the Python API is unavailable and after app restart.
5. Empty capture is deleted locally, captures over 100 words are kept without a model call, and short nonempty capture uses the retained `conv_discard` compute. Any transport, provider, or parse failure keeps the recording.
6. `conv_structure` and `conv_action_items` remain separate authenticated transient computations. The backend receives bounded inputs, returns candidates, and writes no conversation, transcript, task, vector, notification, or Firestore state. The Mac generation-checks and commits accepted output locally; either job may fail without hiding the transcript or erasing the other result.
7. Permanent deletion and merge are local transactions with explicit crash behavior and source-linked task/memory cleanup seams.
8. Cloud recording/playback, People and persistent voice identity, public sharing, folder seeding/reorder/AI assignment, cloud conversation sync/finalization, rejected metadata, and the Mac's rejected settings are absent from the repository wherever S-10 owns their last caller.
9. Backend listen internals and hosted datastores that are still required by S-16/S-19/S-23 are not falsely declared deleted. S-10 removes the Mac authority dependency and records the exact handoff; the owning later slice performs final teardown.

## 4. Authorizing requirements

Every assigned decision is mapped individually. “Cycle” names the S-10 cycle that proves the requirement; “handoff” means S-10 removes the Mac dependency while the listed later slice owns remaining shared backend residue.

| IR | Materialized implementation decision | Proof / owner |
|---|---|---|
| IR-004 | Delete transcript promotion and synchronization; make local GRDB authoritative. | C1-C3, C13 |
| IR-020 | Treat `/v4/listen` as transient STT only; reject server conversation identity/lifecycle as Mac authority. | C2-C3; S-16 backend handoff |
| IR-021 | Delete persisted voice samples/embeddings and cross-conversation recognition; keep diarization plus local labels. | C8, C13; S-16/S-23 handoff |
| IR-022 | Delete reusable People; store names only within one conversation. | C8, C13 |
| IR-023 | Store language, auto-detect/single-language mode, and vocabulary on the Mac and send an immutable per-session snapshot. | C2, C13 |
| IR-121 | Delete conversation audio chunk storage, merge jobs, and cloud playback; add no replacement recording player. | C13; S-23/S-25 operational handoff |
| IR-122 | Delete Store Recordings and Private Cloud Sync settings and API calls. | C13 |
| IR-123 | Delete training-data opt-in and its forced private-cloud/audio behavior. | C13 |
| IR-293 | Preserve the Conversations title and subtitle exactly. | C5, named-bundle acceptance |
| IR-294 | Preserve Select/Merge; replace the hosted merge with crash-safe local merge. | C10 |
| IR-295 | Preserve Quick Note and the Rewind live transcript/notes workspace without redesign. | C2-C3, acceptance |
| IR-296 | Preserve Start Recording exactly. | C2, acceptance |
| IR-297 | Preserve compact and full-screen live transcript presentation. | C2, acceptance |
| IR-298 | Run the existing title/overview search locally with its 250 ms debounce, newest-first order, and 50-result ceiling. | C5 |
| IR-299 | Preserve loading/failure states; use `Couldn't search conversations. Try again.` instead of connection-specific copy. | C5 |
| IR-300 | Preserve the existing No Results state. | C5 |
| IR-301 | Make starring and the Starred filter transactional local state. | C6 |
| IR-302 | Execute the complete date filter against local capture timestamps/calendar boundaries. | C5 |
| IR-303 | Keep folder tabs and manual assignment with local authority. | C7 |
| IR-304 | Keep New Folder with local validation and insertion. | C7 |
| IR-305 | Delete AI folder assignment and the folder Description field. | C7, C13 |
| IR-306 | Delete Work/Personal/Social seeding and system/category protection. | C7, C13 |
| IR-307 | Keep Edit Folder locally. | C7 |
| IR-308 | Delete a folder and move/unassign its conversations in one local transaction. | C7 |
| IR-309 | Delete reorder protocol/UI/API; retain creation order. | C7, C13 |
| IR-310 | Delete Copy Link and hosted conversation sharing. | C13 |
| IR-311 | Keep row Copy Transcript and fetch local detail on demand. | C5, C8 |
| IR-312 | Keep title editing as a durable local manual override. | C6 |
| IR-313 | Keep Delete Conversation as permanent local deletion. | C9 |
| IR-314 | Cascade deletion to every exact source-linked task, regardless of task completion or later edits. | C9 |
| IR-315 | Keep row-to-detail navigation with local detail loading. | C5 |
| IR-316 | Delete hidden Expanded row mode; Compact is the only row. | C5, C13 |
| IR-317 | Preserve the one-minute New treatment. | C5 |
| IR-318 | Preserve the Compact identity block. | C5 |
| IR-319 | Preserve date sections and flat list rendering. | C5 |
| IR-320 | Delete only the two dead row folder/source label helpers. | C13 |
| IR-321 | Preserve initial loading, now driven by GRDB. | C5 |
| IR-322 | Preserve failed-load/retry with neutral local copy and a GRDB retry. | C5 |
| IR-323 | Show the current true-empty state only for genuinely empty history. | C5 |
| IR-324 | Add the minimum distinct zero-match state for active filters. | C5 |
| IR-325 | Preserve 50-row manual pagination and Load older locally. | C5 |
| IR-326 | Preserve all current refresh triggers and activation cooldown, but refresh only local state. | C5 |
| IR-327 | Preserve the detail static identity header. | C8 |
| IR-328 | Preserve the non-completed status badge, driven by local lifecycle. | C8 |
| IR-329 | Delete plan-based lazy-on-first-open enrichment. | C8, C13 |
| IR-330 | Preserve the detail processing overlay using local enrichment state. | C8, C11-C12 |
| IR-331 | Preserve the bounded completion refresh loop as local observation, not server polling. | C8, C11-C12 |
| IR-332 | Preserve the View/Hide Transcript pill. | C8 |
| IR-333 | Preserve the side drawer and full-window transcript expansion. | C8 |
| IR-334 | Preserve drawer identity and segment-count badge. | C8 |
| IR-335 | Preserve Expand/Collapse. | C8 |
| IR-336 | Preserve both detail Copy Transcript buttons. | C8 |
| IR-337 | Preserve the X close/reset transition and use it for both close controls. | C8 |
| IR-338 | Delete per-conversation billing locks and Transcript locked UI. | C8, C13 |
| IR-339 | Preserve the genuine empty-transcript state. | C8 |
| IR-340 | Preserve Loading transcript for local detail reads. | C8 |
| IR-341 | Preserve base transcript bubbles. | C8 |
| IR-342 | Preserve translated bubbles and store received translation results locally. | C2, C8 |
| IR-343 | Preserve the speaker-label entry point and route it to local naming. | C8 |
| IR-344 | Preserve Name Speaker sheet shell and preview. | C8 |
| IR-345 | Narrow Who is this to `You` or a conversation-local name. | C8 |
| IR-346 | Preserve the apply-scope checkbox. | C8 |
| IR-347 | Make Save one GRDB transaction; Cancel writes nothing. | C8 |
| IR-348 | Preserve the Conversation Details card shell. | C8 |
| IR-349 | Keep generated Summary with local result authority. | C11 |
| IR-350 | Delete Source chip and unsupported device-label mapping. | C8, C13 |
| IR-351 | Preserve Duration. | C8 |
| IR-352 | Delete generated category and its chip. | C8, C13 |
| IR-353 | Preserve Action Items against authoritative local task rows. | C8, C12 |
| IR-354 | Keep the opened event but omit `conversation_id`. | C8 |
| IR-355 | Keep non-production automation and make every read/mutation local. | C5-C10 |
| IR-356 | Store conversation language locally. | C2 |
| IR-357 | Store detected commitments locally; never create Calendar records. | C11 |
| IR-358 | Capture one real, opt-in, conversation-scoped Mac location snapshot locally. | C2 |
| IR-359 | Delete wearable-camera conversation photos. | C13 |
| IR-360 | Store the recording-time IANA timezone and send it to retained compute. | C2, C11-C12 |
| IR-361 | Store recording input-device name locally. | C2 |
| IR-362 | Keep empty/over-100/short-transcript discard policy with a local result. | C4 |
| IR-363 | Keep local finalization cause/timing; delete cloud-sync finalization states. | C3 |
| IR-364 | Commit generated title locally unless a manual override exists. | C6, C11 |
| IR-365 | Commit generated emoji locally. | C11 |
| IR-366 | Delete mobile-only current-city Chat context; do not recreate it from local location. | C13 |
| IR-367 | Physically delete a session after an affirmative discard decision and create no derivations. | C4 |
| IR-368 | Delete generic `external_data`; retain only typed local merge provenance. | C10, C13 |
| IR-369 | Delete hosted data-protection levels and migration UI/API/contracts. | C13; S-23 datastore handoff |
| IR-370 | Delete conversation and memory client-device provenance. | C1, C13; S-12 owns Memory model cleanup |
| IR-371 | Delete hidden model-extracted search metadata; search only title/overview. | C5, C13 |
| IR-372 | Delete whole-recording transcript replacement/provider comparison. | C13 |
| IR-373 | Delete Firestore transcript compression and the conversation parity fixture/cases. | C13 |
| IR-374 | Delete hosted processing-ID aliases and conversation memory-compatibility events. | C13; S-12/S-23 handoff |
| IR-375 | Delete Calendar event links from conversations. | C11, C13 |
| IR-376 | Delete backend-only summary mutation. | C13 |
| IR-377 | Delete backend-only segment-text correction. | C13 |
| IR-378 | Delete per-speaker analytics API. | C13 |
| IR-379 | Delete arbitrary transcript-prompt API. | C13 |
| IR-380 | Delete hosted speaker-identity search filter. | C5, C13 |
| IR-381 | Replace broad durable source taxonomy with only retained local capture kind where presentation needs it. | C1-C2, C13 |
| IR-382 | Delete `speech_profile_processed`. | C2, C13 |
| IR-383 | Delete `ImprovedTranscriptSegment` and `ImprovedTranscript`. | C13 |
| IR-384 | Do not persist custom-STT/provider identity; S-16 removes the client-supplied listen protocol itself. | C2, C13; S-16 handoff |
| IR-385 | Use one canonical numeric speaker ID. | C1-C2, C8 |
| IR-386 | Require a stable segment UUID at ingestion beside the private GRDB row ID. | C1-C2 |
| IR-387 | Keep live Rewind speaker naming and apply it locally to future matching speaker numbers in the same conversation. | C8 |
| IR-388 | Port same-speaker fragment joining to one provider-independent local normalizer. | C2 |
| IR-389 | Port cross-speaker boundary reassignment to that normalizer. | C2 |
| IR-390 | Port trim/double-space/comma/period/question-mark cleanup to that normalizer. | C2 |
| IR-391 | Use one local transcript formatter for all retained model requests. | C2, C4, C11-C12 |
| IR-392 | Format the user as `AuthService.givenName`, falling back to `User`; UI still displays `You`. No Firestore profile lookup. | C2, C8, C11-C12 |
| IR-393 | Preserve optional timestamps and the overlap guard from `TranscriptSegment.can_display_seconds`. | C2 |
| IR-394 | Stop Mac consumption of server timeout/rollover/finalization; S-16 deletes that listen ownership. | C2-C3; S-16 handoff |
| IR-395 | Stop sending/handling Python spoken-question onboarding mode; S-16 deletes its protocol. | C2, C13; S-16 handoff |
| IR-396 | Stop sending/storing call identity; S-16 deletes the listen field. | C2, C13; S-16 handoff |
| IR-397 | Delete Mac client/cloud conversation-ID binding and reconciliation. | C1-C3, C13; S-16 handoff |
| IR-398 | The Mac has no browser-listen dependency; S-16 deletes `/v4/web/listen` and rewrites its tests. | C13 residue proof; S-16 handoff |
| IR-399 | The Mac sends only retained mono input; S-16 deletes multi-channel admission. | C2; S-16 handoff |
| IR-400 | Stop sending an STT-provider hint; provider selection remains server-owned transient policy. | C2; S-16 handoff |
| IR-401 | Do not send a VAD override; preserve the backend-configured VAD gate until S-16 narrows listen. | C2; S-16 handoff |
| IR-402 | Accept cloud-STT translation as transient output and persist it only in local segments. | C2, C8 |
| IR-403 | Send mono 16 kHz linear PCM on the retained listen path; S-16 removes codec compatibility. | C2; S-16 handoff |
| IR-404 | Stop stable listen device identity and app-version identity; keep only coarse `macos` failure diagnostics. | C2, C13; S-16 handoff |
| IR-405 | Consume only truthful `ready`/`stt_failed`; stop cloud lifecycle and `last_memory` handling. | C2-C3, C13; S-16 handoff |
| IR-727 | Keep separate `conv_structure` and `conv_action_items` calls/prompts as transient compute; validate and commit results on Mac. | C11-C12; S-22 model-policy handoff |
| IR-732 | Keep `conv_discard` transient compute; empty discards, over 100 words keeps, and any model failure keeps. | C4; S-22 model-policy handoff |

## 5. Dependencies and entry gates

### Required predecessors

- **S-02 / IR-012, IR-013, IR-014, IR-359, and IR-823:** `RewindDatabase` already supplies per-effective-owner databases, generation-aware queue access through `getDatabaseQueueWithGeneration()`, owner switching, WAL configuration, and owner-isolation tests. S-10 must extend this owner fence; it must not create a second database or identity switch mechanism.
- **S-03 / capture durability:** the pinned checkout already has `transcription_sessions`, `transcription_segments`, `live_notes`, local capture persistence, restart recovery, and the named-bundle capture automation seam. S-10 converts this cache/upload schema into authority rather than building a parallel store.

### Entry checks

```bash
git merge-base --is-ancestor 0d9934c HEAD
git rev-list --left-right --count HEAD...origin/main
git status --short
python3 bootstrap-scaffold/validate-requirements-ledger.py
test -x "$(git rev-parse --git-path hooks)/pre-commit" && echo OK
```

After `make setup`, rerun the first four commands and the section 13 inventory. Stop before implementation if:

- the baseline is absent;
- the ledger no longer assigns exactly the 123 IRs above to S-10;
- `RewindDatabase.getDatabaseQueueWithGeneration()` or its owner-generation contract is gone;
- another in-flight slice has already changed any current file named in section 7 without an explicit reconciliation;
- a current external Mac client outside this repository is claimed as a required consumer of a route S-10 plans to remove. Repository evidence alone cannot authorize breaking an unknown external client; this is a product-owner gate.

No live Firestore/GCS/Cloud Tasks deletion, production deploy, or production-app mutation is an implementation entry prerequisite.

## 6. Current production codeflow

### 6.1 Capture and transcript persistence today

```text
AppState.startTranscription
  desktop/macos/Desktop/Sources/AppState/AppState+Transcription.swift
    -> TranscriptionStorage.startSession(...)
    -> local path: LocalTranscriptionService emits TranscriptionService.BackendSegment
    -> cloud path: TranscriptionService opens /v4/listen and emits the same Swift wire type
    -> AppState.handleBackendSegments(...)
       desktop/macos/Desktop/Sources/AppState/AppState+ListenEvents.swift
       -> updates in-memory SpeakerSegment state
       -> persistBackendSegmentsToStorage(...)
       -> TranscriptionStorage.upsertSegment(...)

cloud-only messages today
    -> conversation_session binds a server ID through bindBackendConversation(...)
    -> memory_processing_started / memory_created / service_status influence or log hosted lifecycle
    -> translation updates local segment JSON
    -> speaker suggestion carries reusable person_id

finishConversation / stopTranscription
    -> flush local Parakeet or close WebSocket
    -> TranscriptionStorage.finishSession(...)
    -> ConversationFinalizationService.finalizeSession(...)
       -> localSegments uploads POST /v1/conversations/from-segments
       -> cloudReconcile finalizes or reads a hosted conversation
       -> syncServerConversation(...) hydrates the local cache
```

The important current fact is that both providers already converge at `handleBackendSegments`, and both already write GRDB before finalization. The authority inversion therefore belongs at this existing common seam. The defect is what happens after ingestion: stable identity is optional, cloud IDs are bound into the row, and finalization uploads/reconciles a server record.

### 6.2 List, detail, search, and mutation today

```text
ConversationsPage / ConversationRowView / ConversationDetailView
  -> AppState+DataLoading
  -> ConversationRepository
     -> LiveConversationLocalDataSource (TranscriptionStorage cache)
     -> LiveConversationRemoteDataSource (APIClient /v1/conversations*)
     -> ConversationReconciliationPolicy + optimistic mutation rollback
  -> [ServerConversation] is published back into AppState and SwiftUI
```

`ConversationRepository.load` emits cache and then server snapshots, `refresh` is a server refresh, `loadMore` requests remote pages, and `detail` may return cached detail before remote detail. Star, title, folder, and delete mutate the server and mirror/roll back the cache. Search is remote-only. `AppState+DataLoading` bypasses the repository for folders and People.

### 6.3 Backend conversation ownership today

- `backend/routers/conversations.py` exposes creation/finalization/reprocess/list/count/detail/title/summary/segment mutation/transcript variants/delete/recording/events/embedded action items/speaker assignment/star/search/analytics/test-prompt/merge.
- `backend/routers/folders.py` exposes hosted folder CRUD, reorder, folder conversation reads, assignment, and bulk move.
- `backend/routers/action_items.py` exposes dedicated conversation-action-item list/count/delete endpoints in addition to the global task API.
- `backend/routers/sync.py` exposes audio precache/signed URLs/download and the `/v2/audio-merge-jobs/run` worker handler.
- `backend/routers/users.py` owns geolocation, recording/private-cloud flags, People, language/transcription preferences, data-protection migrations, training opt-in, and location-context consent.
- `backend/routers/transcribe.py` admits `/v4/listen` and `/v4/web/listen`; `ListenSessionRuntime` composes `LiveConversationController`, `TranscriptProcessor`, `ConversationCache`, `SpeakerMatcher`, and `ListenPersistence`.
- `LiveConversationController` creates Firestore in-progress conversations, emits conversation IDs/lifecycle, polls timeout/rollover, and schedules hosted finalization. `TranscriptProcessor` merges, translates, writes Firestore, and emits segments. `SpeakerMatcher` loads persistent People/voice data.
- `process_conversation._get_structured` reads hosted timezone/language/profile/People/calendar data, formats the transcript, runs discard, structure, and action-item calls, then `process_conversation`, `_save_action_items`, vector functions, memory extraction, notifications, and database helpers persist projections.
- `backend/database/conversation_finalization_jobs.py`, `backend/services/conversation_finalization.py`, and `backend/main.py` own durable finalization jobs and startup/periodic reconciliation. `backend/database/conversations.py` owns Firestore records, encryption/compression compatibility, lifecycle, and recording metadata. `backend/database/folders.py` owns hosted folders and default seeding.

### 6.4 Current local schema

`RewindDatabase` migrations `createTranscriptionStorage`, `addTranscriptionFinalizationMetadata`, `addTranscriptionClientConversationId`, `expandTranscriptionSchema`, and `addConversationCacheAuthority` create/extend:

- `transcription_sessions`: local row ID; capture times/source/language/timezone/input device; upload status/retry/error; `backendId`, `clientConversationId`, `backendSynced`; finalization strategy/reason/times; title/overview/emoji/category/action-items/events/geolocation/apps; hosted status/discard/delete/lock/star/folder; server update/cache completeness.
- `transcription_segments`: local row ID, cascading `sessionId`, numeric `speaker`, text/times/order, optional server `segmentId`, `speakerLabel`, `isUser`, `personId`, and later translation JSON.
- `live_notes`: cascading `sessionId` relationship.
- `action_items` and `memories`: nullable string `conversationId` links, but no database foreign key to conversations. `MemoryStorage.softDeleteMemoriesByConversationId` exists; ActionItemStorage has no exact-source cascade query today.

This is a server-shaped cache with useful local durability, not yet a local domain authority.

## 7. Complete caller and dependency inventory

This inventory is complete for non-Windows in-repository current callers found by symbol and route search at the pinned baseline. Tests are included where they define an executable contract. Windows is excluded by IR-009 and section 8.

### 7.1 macOS authority, capture, and lifecycle

| Current file | Current symbols / dependency | S-10 action |
|---|---|---|
| `desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift` | `getDatabaseQueueWithGeneration`, `retargetEffectiveOwner`, `switchUser`; migrations named in 6.4 | Extend with the local-authority migration and owner-safe tables/indexes. |
| `desktop/macos/Desktop/Sources/Rewind/Core/TranscriptionModels.swift` | `TranscriptionSessionStatus`, `TranscriptionFinalizationStrategy`, `TranscriptionFinalizationReason`, `ConversationCacheCompleteness`, `TranscriptionSessionRecord`, `TranscriptionSegmentRecord`, conversions to/from `ServerConversation` | Replace server/cache/upload shapes with retained local domain and required IDs; delete conversions. |
| `desktop/macos/Desktop/Sources/Rewind/Core/TranscriptionStorage.swift` | `startSession`, `finishSession`, backend binding/upload state, segment append/upsert/assignment, recovery, server sync/cache reads | Deepen into the sole store in place; replace backend-keyed methods with conversation UUID methods. |
| `desktop/macos/Desktop/Sources/AppState/AppState+Transcription.swift` | capture start/rotation/finish, Quick Note automation, `automationStartCaptureTestSession`, `automationInjectCaptureTestTranscript`, `automationInjectCaptureTestTranscriptMulti`, `automationStopCaptureTestSession` | Generate local identity first, snapshot settings/metadata, finalize locally, retain automation. |
| `desktop/macos/Desktop/Sources/AppState/AppState+ListenEvents.swift` | `handleBackendSegments`, `persistBackendSegmentsToStorage`, `bindActiveSessionToBackendConversation`, `acceptsLifecycleEnvelope`, `handleListenEvent`, `updateTranscriptDisplay` | Keep the common segment/translation seam; delete cloud identity/lifecycle/People handling. |
| `desktop/macos/Desktop/Sources/LocalTranscriptionService.swift` | emits `TranscriptionService.BackendSegment` | Keep as transient producer; no domain ownership. |
| `desktop/macos/Desktop/Sources/TranscriptionService.swift` | `BackendSegment`, `/v4/listen` connection and event decoding | Adapt request/event surface only; S-16 owns final wire deletion. |
| `desktop/macos/Desktop/Sources/ConversationFinalizationService.swift` | `finalizeSession`, `recoverPendingFinalizations` and all upload/cloud reconcile helpers | Replace in place with local admission plus durable enrichment work; delete upload/reconcile. |
| `desktop/macos/Desktop/Sources/TranscriptionRetryService.swift` | crash scan/statistics and calls to `ConversationFinalizationService.recoverPendingFinalizations` | Adapt to local finalization/enrichment recovery. |
| `desktop/macos/Desktop/Sources/Chat/RuntimeOwnerIdentity.swift` | invalidates `TranscriptionStorage` on owner change | Retain owner-change invalidation against local authority. |

### 7.2 repository, state, and UI

| Current file | Current symbols / dependency | S-10 action |
|---|---|---|
| `desktop/macos/Desktop/Sources/MainWindow/Conversations/ConversationRepository.swift` | `ConversationListQuery`, remote/local protocols and implementations, `ConversationRepositorySnapshot`, `ConversationRepository` load/refresh/page/search/detail/mutations | Make a presentation adapter over the local store; delete remote protocol/snapshot provenance/reconciliation. |
| `desktop/macos/Desktop/Sources/ConversationReconciliationPolicy.swift` | server/cache/pending-mutation reconciliation | Delete after repository tests prove local authority. |
| `desktop/macos/Desktop/Sources/AppState.swift` | `conversationRepository`, published conversations/folders/people, snapshot hookup/reset | Publish local models/folders; remove People state. |
| `desktop/macos/Desktop/Sources/AppState/AppState+DataLoading.swift` | load/refresh/page/star; folder CRUD; title/detail/search/delete; `fetchPeople`, `createPerson`, `assignSpeakerToSegments` | Keep the retained conversation/folder facade names, point them to GRDB, delete the three People methods, and add one local speaker-label facade. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/ConversationsPage.swift` | list/filter/select/merge/search and `performMerge`; Quick Note/Start Recording headers | Retain UX; call local merge/search/store. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/ConversationListView.swift` | conversation list/date sections/load older | Move from `ServerConversation` to local summaries. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/ConversationRowView.swift` | compact row, star/title/folder/delete/copy | Preserve retained actions; delete Expanded/dead helpers/Copy Link. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/OmiSearchField.swift` | `DebouncedSearchCoordinator.standardDelayNanoseconds = 250_000_000` | Retain the exact shared debounce/cancellation behavior. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/ConversationDetailView.swift` | detail header/status/overlay/cards/transcript drawer/copy/speaker save/delete/title | Read local detail/tasks; remove lock/category/source/People/API mutations. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/FolderManagementViews.swift` | create/edit/delete destination UI | Keep shell; remove description/system/reorder concepts. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/NameSpeakerSheet.swift` | Person-backed naming | Narrow to You or conversation-local name. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/LiveNameSpeakerSheet.swift` | live Person-backed naming | Apply local label to current/future numeric speaker in same conversation. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/SpeakerBubbleView.swift` | person/speaker presentation | Read local labels. |
| `desktop/macos/Desktop/Sources/Rewind/UI/RewindPage.swift` | live naming entry | Retain, localize. |
| `desktop/macos/Desktop/Sources/MainWindow/ConversationDetailAutomationState.swift` | detail automation state | Retain as acceptance seam. |

### 7.3 direct conversation consumers outside the Conversations page

| Current file and symbol | Current read | Required migration |
|---|---|---|
| `desktop/macos/Desktop/Sources/MainWindow/Pages/HomeStatusStore.swift` `HomeStatusLoader.live`, `HomeKnowledgeCounts`, `accountHasOmiDeviceConversations` | `getConversationsCount` plus `APIClient.hasOmiDeviceConversations` | Use local count; delete the wearable-source history flag/default/query with the broad source taxonomy. |
| `desktop/macos/Desktop/Sources/TierManager.swift` refresh | `getConversationsCount` | Local count; entitlement remains cloud. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/Settings/Components/SettingsContentView+Controls.swift` count load | `getConversationsCount` | Local count. |
| `desktop/macos/Desktop/Sources/MainWindow/Dashboard/HomeSuggestionsStore.swift` | `getConversations` | Local page/context reader. |
| `desktop/macos/Desktop/Sources/AuthService.swift` conversation-based state load | `getConversations(limit: 10)` | Local owner-scoped history read. |
| `desktop/macos/Desktop/Sources/ProactiveAssistants/Services/AIUserProfileService.swift` | `getConversations` | Local reader; S-14 owns profile authority. |
| `desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/Goals/GoalsAIService.swift` | two `getConversations` calls | Local reader; S-14 owns goal behavior. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/ChatPage.swift` citation open | `getConversation` | Local detail by source UUID. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/DashboardPage.swift` citation open | `getConversation` | Local detail. |
| `desktop/macos/Desktop/Sources/MainWindow/Pages/MemoriesPage.swift` `navigateToConversation` | `getConversation` | Local source relationship; coordinate S-12. |
| `desktop/macos/Desktop/Sources/DesktopAutomationBridge.swift` conversation list/detail/delete/star/folder/speaker/settings actions | AppState plus direct API fallbacks | Remove fallbacks and expose deterministic local receipts. |
| `desktop/macos/Desktop/Sources/AnalyticsManager.swift` and `desktop/macos/Desktop/Sources/PostHogManager.swift` `conversationDetailOpened(conversationId:)` | Sends `conversation_id` | Replace with a no-ID `conversationDetailOpened()` event and update its tests/caller. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/RecentConversationsWidget.swift`, `DesktopHomeView.swift`, `ViewExporter.swift`, `ConcurrencySendable.swift` | `ServerConversation` projection | Move to local summary/detail or remove obsolete sendability wrapper. |
| `desktop/macos/Desktop/Sources/Providers/ChatToolExecutor.swift` | local SQL conversation tools plus separate remote `/v1/tools` retrieval | Keep local SQL shape synchronized; remote PTT tool paths are S-19. |

### 7.4 settings and rejected metadata callers

- `desktop/macos/Desktop/Sources/Services/APIClient/APIClient+Settings.swift`: `getTranscriptionPreferences`, `updateTranscriptionPreferences`, `getUserLanguage`, `updateUserLanguage`, `getPrivateCloudSync`, plus recording-related models/methods in the same file.
- `desktop/macos/Desktop/Sources/MainWindow/Pages/Settings/Components/SettingsContentView+BillingHelpers.swift`: loads language, private-cloud state, and transcription preferences.
- `desktop/macos/Desktop/Sources/MainWindow/Pages/Settings/Components/SettingsContentView+SettingsUpdates.swift`: writes language and transcription preferences.
- `desktop/macos/Desktop/Sources/MainWindow/Pages/Settings/Sections/SettingsContentView+NotificationsPrivacy.swift`, `desktop/macos/Desktop/Sources/MainWindow/Pages/SettingsPage.swift`, and `desktop/macos/Desktop/Sources/MainWindow/SettingsSidebar.swift`: Store Recordings/Private Cloud presentation and search state.
- `desktop/macos/Desktop/Sources/Onboarding/SecondBrain/SBOnboardingModel.swift`: writes the selected language to the backend.
- `desktop/macos/Desktop/Sources/ProactiveAssistants/Assistants/Insight/InsightAssistant.swift` and `desktop/macos/Desktop/Sources/Providers/ChatToolExecutor.swift`: read/write general user language. S-10 changes only capture-language authority; S-14 owns non-conversation assistant-language consolidation.
- `desktop/macos/Desktop/Info.plist` currently has microphone/audio/screen usage strings and no location usage string. `Omi.entitlements` and `Omi-Release.entitlements` have no location-specific entitlement. C2 must add the usage description required by the chosen Core Location API, without adding continuous/background location.

### 7.5 backend routes, persistence, and jobs

| Current owner | Exact current surface | S-10 disposition |
|---|---|---|
| `backend/routers/conversations.py` | `create_conversation_from_segments_user`, `process_in_progress_conversation`, `finalize_conversation`, `get_conversation_finalization_status`, `reprocess_conversation`, list/count/detail, title/summary/segment/transcript/delete/recording/events/action-item/speaker/star/search/analytics/test-prompt/merge handlers | Add no compatibility alias. Remove S-10-exclusive public CRUD/processing routes after all callers migrate; shared internals survive only under explicit handoffs. |
| `backend/routers/folders.py` | `get_folders`, `create_folder`, `get_folder`, `update_folder`, `delete_folder`, `reorder_folders`, `get_folder_conversations`, `move_conversation_to_folder`, `bulk_move_conversations` | Delete route surface and direct tests after C7. |
| `backend/routers/action_items.py` | `get_conversation_action_items`, `get_conversation_action_items_count`, `delete_conversation_action_items` | Delete only conversation-specific endpoints; S-13 owns global task endpoints. |
| `backend/routers/sync.py` | audio precache/URL/download and `run_audio_merge_job` | Remove public playback surface when no retained caller remains; S-25 owns worker-service closure and S-23 owns stored artifacts. |
| `backend/routers/users.py` | geolocation, recording/private-cloud, People, language/prefs, migration/data protection, training, location context | Remove only routes whose complete in-repo ownership is S-10; leave general language or shared profile routes until their owner slice. |
| `backend/routers/transcribe.py` and `backend/routers/listen/*` | `/v4/listen`, `/v4/web/listen`, `ListenSessionRuntime`, `LiveConversationController`, `TranscriptProcessor`, `ConversationCache`, `SpeakerMatcher`, `ListenPersistence` | S-10 removes Mac authority coupling; S-16 owns protocol/listen deletion. |
| `backend/utils/conversations/process_conversation.py` | `_fetch_dedup_candidates`, `_get_structured`, `_save_action_items`, `process_conversation`, vector/memory/notification helpers | New compute routes call the pure retained functions directly, never this persistence orchestrator. S-23 deletes hosted projection. |
| `backend/utils/llm/conversation_processing.py` | `should_discard_conversation`, `extract_action_items`, `get_transcript_structure`, `get_reprocess_transcript_structure`; calendar/category/event legacy inside prompts | Adapt to candidate-only DTOs and retained fields while preserving validated prompt behavior. |
| `backend/utils/llm/model_config.py` | premium `conv_structure`/`conv_action_items` map to OpenAI `gpt-5.4-mini`; `conv_discard` maps to OpenAI `gpt-4.1-nano`; max profile currently maps larger models | S-10 uses feature keys, not a new client. S-22 owns profile/model routing; see risk R8. |
| `backend/models/transcript_segment.py` | `TranscriptSegment.segments_as_string`, `can_display_seconds`, `combine_segments`, `ImprovedTranscript*` | Port retained formatting/normalization behavior to Swift, then delete rejected schemas where no backend owner remains. |
| `backend/database/conversations.py`, `backend/database/folders.py` | Firestore conversation/folder authority, encryption/compression, lifecycle, default folders | Stop new Mac writes. Physical datastore/helper deletion is S-23 unless no shared caller remains in S-10. |
| `backend/database/conversation_finalization_jobs.py`, `backend/services/conversation_finalization.py`, `backend/main.py` | finalization job docs, leases/projections, startup and periodic reconciliation | Stop creating jobs for Mac; final removal follows S-16/S-23. |

### 7.6 contracts, generated code, and tests

- `desktop/macos/Desktop/Sources/APIClient.swift` contains `ServerConversation`-based CRUD/search/count/merge/folder methods.
- `desktop/macos/Desktop/Sources/Services/APIClient/APIClient+ConversationModels.swift`, `APIClient+People.swift`, and `APIClient+Memories.swift` contain current wire/domain adapters and creation/finalization requests.
- `desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift` contains generated conversation DTOs and user geolocation methods. Generation is controlled by `backend/scripts/generate_swift_openapi_types.py`; its current `TARGET_SCHEMAS` includes Conversation/Structured/ActionItem/Event/TranscriptSegment/Geolocation/AudioFile and related enums.
- `backend/scripts/export_openapi.py` currently includes `/v1/conversations`, `/v1/folders`, `/v1/sync`, and `/v1/users` in `APP_CLIENT_PREFIXES`; it imports `backend/main.py`, not `desktop_backend.py`, for the app-client schema.
- `backend/route_policy_manifest.yaml` and `backend/route_policy_legacy_missing_routes.txt` inventory current route policy.
- `backend/testing/contracts/test_desktop_backend_parity.py` has four conversation codec/query cases followed by Memory cases. `contract_tests/fixtures/conversations.json` is the shared conversation fixture.
- `.github/workflows/desktop-backend-contracts.yml` has an independent `desktop-core-e2e-t0` job and a mixed hosted `contracts` job. S-10 removes conversation cases, fixture, and the `backend/database/conversations.py` trigger only. S-12 removes the remaining Memory job/triggers/discovery registration later.
- Current focused Swift contracts include `ConversationRepositoryTests`, `ConversationReconciliationPolicyTests`, `ServerConversationDecodingTests`, `APIClientConversationCountTests`, `TranscriptionSessionRecordTests`, `TranscriptionStorageRecoveryTests`, `TranscriptionFinalizationStateMachineTests`, `TranscriptionRetryResilienceTests`, `TranscriptSpeakerAssignmentTests`, `ConversationMergeSelectionTests`, `ConversationDetailAutomationStateTests`, `HomeStatusStoreTests`, `ListenProtocolTests`, and `LiveTranscriptionFailureStateTests`.
- Current real-path flows are `capture-lifecycle.yaml`, `conversation-detail.yaml`, `conversation-folders.yaml`, `speaker-naming.yaml`, `language.yaml`, `vocabulary.yaml`, `quick-note.yaml`, `recording-finalization.yaml`, `audio-recording.yaml`, and `privacy-settings.yaml` under `desktop/macos/e2e/flows/`. C13 deletes or rewrites flows for rejected audio/settings behavior; it does not silently leave dead acceptance contracts.

## 8. Behavior classification

### KEEP AS IS

- Conversations header, Select control, Quick Note, Start Recording, compact/full live transcript, Rewind notes workspace.
- Search loading and No Results visual states, one-minute New treatment, Compact row identity, date section grouping, true-empty history, initial loading, 50-row Load older affordance, and existing refresh triggers/cooldown.
- Detail header, non-completed badge, processing overlay, transcript pill/drawer/full-window presentation, drawer identity/count, Expand/Collapse, both Copy Transcript actions, common close/reset transition, empty/loading transcript states, base/translated bubbles, detail card, Duration, and Action Items section.
- Name Speaker shell/preview, You option, custom local name entry, apply-all checkbox, Save/Cancel footer, and live naming entry.
- The existing discard prompt semantics, structure prompt behavior that applies to retained fields, action-item prompt/date validation/dedup behavior, usage tracking, and failure isolation.
- Server-configured VAD, transient cloud-STT translation, ready/failure truth, and mono 16 kHz linear PCM target behavior.

“As is” means visual/behavioral invariants, not continued `ServerConversation`, People, backend, or cache implementation.

### ADAPT

- `TranscriptionStorage` and its schema from upload cache to sole conversation authority.
- `ConversationRepository` from cache/remote reconciler to local presentation adapter.
- Common segment ingestion so both providers receive stable IDs and the same local normalization.
- Capture settings, language, timezone, input device, translations, and one-shot location into per-conversation local state.
- Finalization/recovery into local lifecycle plus durable, generation-fenced enrichment work.
- Search, list/count/detail/page, title/star, folders, speaker labels, merge, deletion, citations, automation, Home/status/profile/goals consumers, and S-08 export to local reads.
- Python discard/structure/action functions into three authenticated stateless candidate endpoints. The endpoint names in section 10 are new deliberate contracts, not current paths.
- Existing task embedding/search primitives (`EmbeddingService`, `ActionItemStorage`) only as needed to preserve local related-open-task selection; S-13 owns the full task authority rewrite.
- OpenAPI targets/generator output to retain only candidate-compute DTOs needed by Mac.

### DELETE

- Promotion/upload/retry/reconciliation, server/cache snapshot precedence, backend IDs/sync flags/server timestamps/cache completeness, and cloud finalization status.
- Hosted conversation CRUD/search/merge/folders/speaker/action-item/recording/sharing/analytics/test-prompt/manual-mutation API surface when its last in-tree caller is removed.
- Cloud audio chunks, playback artifacts, audio merge dispatch/route contracts, Store Recordings, Private Cloud Sync, and training opt-in UI/API.
- Reusable People, person IDs, voice samples/embeddings, speech-profile processing, cross-conversation recognition, and People-backed search.
- Copy Link/sharing, per-conversation locks, category, Source chip/device label mapping, device provenance, generic `external_data`, hosted processing aliases, data-protection levels, transcript compression, whole-recording comparison/replacement, wearable photos, Calendar links/creation, hidden search metadata, broad source taxonomy, and improved-transcript schemas.
- AI folder assignment/description, default Work/Personal/Social folders/protection, and folder reorder protocol.
- Cloud lifecycle/last-memory event handling and client/cloud identity binding.
- Conversation portion of the parity test/fixture/workflow trigger and obsolete generated DTOs.

### SIMPLIFY AFTER

These deletions are unlocked only after the named proof; doing them earlier destroys the executable seam.

| Current surface | Simplify/delete after |
|---|---|
| Server conversion methods and `ServerConversation` UI types | C5 and C8 local list/detail tests plus migrated direct callers are GREEN. |
| Backend-keyed `TranscriptionStorage` methods and cloud enum cases | C1-C3 migration/finalization/recovery are GREEN. |
| `ConversationReconciliationPolicy.swift` and remote repository protocols | C5-C7 mutation, paging, failure, owner-switch tests are GREEN. |
| People state/API models | C8 single/apply-all/live label tests are GREEN. |
| Hosted merge implementation used by desktop | C10 crash recovery and atomic source deletion are GREEN. |
| Hosted processing orchestration for Mac | C4/C11/C12 candidate-only statelessness tests are GREEN. Shared S-12/S-13/S-16/S-19 callers remain until their slices. |
| OpenAPI Conversation/Folder/Person/Audio DTO targets | C13 compilation proves no retained Mac type imports them. |
| Conversation parity fixture/cases | C13 local authority and route-absence contracts are GREEN; Memory half remains. |

### OUT OF SCOPE

- All `desktop/windows/**` behavior and Windows API consumers (IR-009).
- S-08 archive packaging/account deletion beyond providing `ConversationArchiveReader`.
- Full local Memory authority/cascade semantics (S-12) and full Task authority/dedup/index lifecycle (S-13); S-10 supplies source IDs and atomic hooks only.
- Goal/profile/language product redesign (S-14); S-10 changes their conversation input reads and capture settings only.
- Final `/v4/listen` wire and hosted listener deletion (S-16).
- PTT `/v1/tools/conversations`, `/search`, and `/search-chunks` migration (S-19).
- Fair-use/subscription accounting (S-20), global model/gateway choice (S-22), complete hosted conversation datastore cleanup (S-23), hosted vector/search infrastructure (S-24), worker deployment deletion (S-25), and namespace/rebrand work (S-28).
- A local raw-audio recorder/player, cloud import/backfill, cross-device conversation sync, public sharing, calendar writing, or reusable contact/voice identity. None may be introduced as a “replacement.”

## 9. Retained behavioral invariants

1. A capture admitted by the UI gets its local conversation UUID before the first segment is persisted.
2. Every persisted segment has a required stable UUID at first ingestion and a private GRDB row ID; retries with the same UUID update rather than duplicate.
3. Local and cloud STT enter the same normalizer/store transaction and produce the same durable shape.
4. Provider name, server conversation ID, call ID, stable device ID, and reusable person ID never enter the durable conversation schema.
5. Same-speaker joining, cross-speaker boundary repair, and punctuation cleanup match `TranscriptSegment.combine_segments` behavior before the Python implementation is retired, except the rejected provider/speech-profile equality gates are deliberately absent.
6. The common formatter uses numeric speaker IDs; the authenticated user's first name comes from `AuthService.givenName`, falls back to `User`, and UI copy remains `You`.
7. Optional timestamps are emitted only when the retained overlap guard says they are displayable.
8. Language, single-language/auto-detect mode, vocabulary, IANA timezone, and input-device display name are snapshotted per session. Mid-session preference changes affect only the next session.
9. Location is one opt-in, one-shot capture. Denied/restricted/timeout/unavailable means nil and never blocks capture; there is no background tracking or city fallback.
10. A finished transcript appears locally immediately, before discard or enrichment network work.
11. Empty transcript is deleted without a model call; more than 100 words is kept without a model call; short nonempty transcript calls `conv_discard`; all classifier failures keep.
12. An affirmative discard physically deletes the conversation, segments, live notes, and any not-yet-committed derivations. No discarded row appears in list/export/search.
13. Structure and action-item computation are different requests and durable work items. One can succeed when the other fails. The retained detail observer makes at most 15 local refresh checks separated by two seconds; it performs no server polling.
14. Model responses are candidates only. A stale owner or conversation generation can never commit.
15. Manual title override wins over every later generated title, retry, restart recovery, and merge enrichment.
16. Title, overview, emoji, commitments, and accepted action items are committed in local transactions; the backend performs no durable write.
17. Action-item due dates retain current local-time parsing/UTC normalization and past-date clearing. Related candidates are open, recent, source-aware local tasks only.
18. List order is newest first; page size is 50; Load older appends without duplicates; search is title/overview only, debounced 250 ms and capped at 50.
19. Date filters use capture timestamps and local calendar boundaries. Star/folder/date filters compose rather than silently replace one another.
20. The page keeps the literal header `Conversations` and subtitle `Recordings, notes, and transcripts from your day`. The retained list states remain `Loading conversations...`, `Failed to load conversations` with `Try Again`, and true-empty `No Conversations` / `Start recording to capture your first conversation`; filtered-zero remains `No conversations found` / `Try a different search term`. Search and local read failures never use network-specific wording.
21. Star, title, folder assignment, folder delete/reassignment, speaker label, merge, and delete survive quit/relaunch and never require a server echo.
22. Folder names/colors/creation order remain; description, system/category protection, default seeding, AI assignment, and reorder do not.
23. A speaker label is scoped to `(conversation UUID, numeric speaker ID)`. Apply-all affects matching segments in that conversation; live naming affects future same-number segments in that conversation only.
24. Translations received during cloud STT are local segment data and render after restart.
25. Permanent delete removes every exact source-linked task regardless of completion/edit state and invokes the S-12 memory cleanup seam; unrelated records remain.
26. Merge preserves chronological segment order and gap adjustment, never deletes sources until the replacement is valid, is restart-recoverable, records typed source UUID provenance, and re-enriches the replacement.
27. Owner switch cancels/invalidate in-flight reads and compute. No old-owner rows, counts, candidates, or mutations appear in the new owner database.
28. Offline/restart behavior covers list/detail/search/paging/mutations and completed transcript visibility. Only new managed-STT/model compute may be unavailable.
29. Analytics may record detail opened but must not include the conversation UUID or raw transcript/PII.
30. No local/cloud dual-write, compatibility adapter, legacy alias, or fallback server read survives repository closure.

## 10. Target authority and ownership model

### 10.1 One owner and one durable path

`TranscriptionStorage` remains the existing actor and becomes the deep local conversation module rather than introducing a parallel `ConversationStore`. It acquires typed local read/mutation methods and is the only code allowed to write conversation tables. `ConversationRepository` remains `@MainActor` presentation state only. Every store operation obtains the current `DatabasePool` plus generation through `RewindDatabase.getDatabaseQueueWithGeneration()` and rechecks authorization before commit.

```text
SwiftUI / automation / archive / downstream assistants
                  |
          ConversationRepository (presentation only)
                  |
          TranscriptionStorage actor
                  |
      RewindDatabase owner pool + generation
                  |
                omi.db

STT providers -> AppState.handleBackendSegments -> local normalizer -> same store
model compute -> candidate DTO -> generation/validation fence -> same store
```

### 10.2 Local identity and schema

Extend `RewindDatabase.swift` with one forward-only migration registered exactly as `makeConversationsLocalAuthoritative`. Rebuild the two legacy tables within the migration so rejected columns are physically absent instead of left nullable forever.

- `transcription_sessions`: private `id`; required unique `conversationId` UUID string; `startedAt`, `finishedAt`; language, timezone, input-device name; local lifecycle; finalization reason/start/completion; title, manual-title flag, overview, emoji, commitments JSON, one-shot geolocation JSON; starred; nullable folder UUID; created/updated; monotonically increasing `contentGeneration`. The broad durable source field is removed.
- `transcription_segments`: private `id`; cascading session row ID; required unique stable segment UUID; one numeric speaker ID; text/start/end/order; `isUser`; translations JSON; created/updated. Names live only in `conversation_speaker_labels`, not duplicated on segments.
- `conversation_folders` **(new table in the migration)**: UUID, trimmed 1-100-character name (preserving the current `Folder` name bound), retained color, creation timestamp. The current workflow does not reject duplicate names, so the local table must not add a name-uniqueness rule. `transcription_sessions.folder` references this UUID with `ON DELETE SET NULL`. No description/order/system/category columns.
- `conversation_speaker_labels` **(new table)**: conversation UUID plus numeric speaker ID primary key, name, `isUser`, updated timestamp; foreign-key cascade to session authority.
- `conversation_merge_sources` **(new table)**: replacement conversation UUID, source conversation UUID, source ordinal; typed provenance only.
- `conversation_enrichment_work` **(new table)**: conversation UUID, content generation, kind (`discard`, `structure`, `actionItems`), state (`pending`, `running`, `succeeded`, `failed`), attempt/error/timestamps. This is local compute work, never upload/sync state.

Migration rules, in one transaction per owner database:

1. Prefer a valid existing `clientConversationId` UUID. Otherwise preserve a valid `backendId` UUID only as the new local UUID value, without retaining its “backend” meaning; otherwise generate a UUID.
2. Build an old `backendId`/`clientConversationId` to local UUID map and rewrite exact `action_items.conversationId` and `memories.conversationId` values in the same transaction. Never rewrite a partial or fuzzy match.
3. Preserve every non-discarded local row and transcript, including unsynced/failed rows. Generate a segment UUID for every missing/invalid `segmentId`; preserve valid unique UUIDs.
4. Resolve duplicate candidate IDs deterministically by keeping the earliest row's ID and generating new IDs for later rows; record no remote alias table.
5. Physically omit rows already marked discarded/deleted and let foreign-key cascades remove their segments/live notes. Invoke explicit task/memory cleanup for their old exact IDs before dropping the old tables.
6. Translate legacy recording/upload/processing states to local lifecycle without scheduling uploads. A recording row remains recording; a finished row with transcript becomes finalizing/pending local admission; a completed row remains visible/completed; irrecoverable empty rows are deleted.
7. After commit, no retained table has `backendId`, `backendSynced`, `serverUpdatedAt`, `cacheCompleteness`, `retryCount` for upload, `finalizationStrategy`, `category`, `eventsJson`, `appsResultsJson`, `isLocked`, `personId`, `speakerLabel`, or durable provider identity.

### 10.3 Store API

Use current files rather than a second module. Add typed local models in `TranscriptionModels.swift` and methods in `TranscriptionStorage.swift` for:

- `beginConversation`, provider-independent `upsertSegments`, `finishConversation`, `recoverLocalFinalization`;
- `listConversations(query:offset:limit:)`, `countConversations(query:)`, `conversationDetail(id:)`, and `searchConversations(text:limit:)`;
- `setStarred`, `setManualTitle`, `moveToFolder`, folder create/update/delete-and-reassign;
- `setSpeakerLabel(conversationId:speakerId:name:isUser:applyToExisting:)`;
- `deleteConversationCascade` and the prepare/validate/commit/recover local merge operations;
- enrichment claim/succeed/fail methods keyed by conversation UUID, content generation, kind, and owner authorization;
- `conversationArchivePage(after:limit:)`, exposed through a small `ConversationArchiveReader` protocol declared beside the store for S-08.

The exact method spelling is an implementation-level target, not a compatibility promise. Tests call the public behavior seam; no duplicate old/new API remains after callers migrate.

### 10.4 Transcript normalization and formatting

Add `desktop/macos/Desktop/Sources/Rewind/Core/LocalTranscriptFormatter.swift` **(new; parent directory exists and name is unused)**. It owns:

- the provider-independent Swift port of `TranscriptSegment.combine_segments` for same-speaker join, boundary repair, removed segment UUIDs, and punctuation spacing;
- a deterministic formatted transcript using conversation-local labels, `AuthService.givenName`/`User`, and optional timestamps gated by the overlap rule;
- a bounded model-input renderer shared by discard, structure, and action-item jobs.

It does not own persistence or UI models. Static golden vectors copied from Python are a parity tripwire; behavioral store tests prove actual ingestion.

### 10.5 Transient compute contract

Introduce these authenticated endpoints in `backend/routers/conversation_compute.py` **(new; checked absent)** and include the router in `backend/main.py`:

- `POST /v1/conversation-compute/discard`
- `POST /v1/conversation-compute/structure`
- `POST /v1/conversation-compute/action-items`

Use one `generation_id: UUID` supplied and echoed for stale-response rejection. Requests contain only the bounded formatted transcript and the minimum immutable context:

- discard: generation, transcript, nonnegative duration;
- structure: generation, transcript, capture start, language/output language, IANA timezone;
- action items: generation, transcript, capture start, language/output language, IANA timezone, and at most ten local related open-task candidates with per-request opaque tokens, descriptions, and due dates. The Mac keeps the token-to-local-row mapping; it does not send a GRDB row ID or legacy `backendId`.

The request contract is exact: transcript is nonblank and at most 1,000,000 Unicode characters; duration is finite and nonnegative; language/output-language strings are 1-32 characters; timezone is 1-128 characters and must resolve through `ZoneInfo`; related-task tokens must match `t0` through `t9`, descriptions are nonblank and at most 4,096 characters (the current canonical task bound), and the list maximum is ten. Pydantic rejects violations with 422. The Mac does not truncate silently: an oversized transcript remains fully durable and visible locally while that enrichment work records a local validation failure.

Responses are typed candidates only:

- discard: generation plus boolean;
- structure: generation plus title, overview, emoji, and commitment candidates with `created` always false and no Calendar URL;
- action items: generation plus validated create/update/complete candidates and normalized due dates.

Candidate validation is exact: title is at most 256 characters and ten whitespace-delimited words; overview is at most 50,000 characters; emoji is exactly one extended grapheme cluster; commitment candidates and action candidates are each capped at 100; action descriptions are nonblank and at most 4,096 characters; update/complete targets must exactly match a `t0`-through-`t9` token sent in that request, which the Mac resolves back to the retained local row under the owner/generation fence. Any malformed response fails that work item without a partial commit.

The routes call `should_discard_conversation`, `get_transcript_structure`, and `extract_action_items` through `Features.CONVERSATION_DISCARD`, `CONVERSATION_STRUCTURE`, and `CONVERSATION_ACTION_ITEMS`. They must not call `process_conversation`, `_get_structured`, `_save_action_items`, database modules, Pinecone, FCM, GCS, or Calendar. Structure and action-items are not combined. `get_transcript_structure` must be narrowed so rejected category/calendar-link output cannot re-enter the candidate schema.

Add `desktop/macos/Desktop/Sources/Services/APIClient/APIClient+ConversationCompute.swift` **(new; checked absent)** for only these DTOs/requests. Add the schemas to the existing OpenAPI generator target and remove old conversation DTO targets only after compilation proves no caller.

For action-item related context, reuse local `EmbeddingService.embed/searchSimilar` plus `ActionItemStorage.getActionItem` where available, filter to `.actionItem`, incomplete, nondeleted, updated/created within seven days, exclude tasks whose exact source is the current or merged source IDs, threshold at the current backend value `0.6`, and cap ten. If embedding compute is unavailable, send no related-task context and continue; do not fall back to cloud task storage. C12 verifies both paths. Full task lifecycle remains S-13.

### 10.6 Lifecycle and ownership

- Local conversation lifecycle: `recording -> finalizing -> processing -> completed`, plus `merging` and visible failure metadata for local read or compute failure. Uploading/pending-upload/cloud-reconcile are invalid.
- Finishing closes segment writes, increments `contentGeneration`, and runs discard. Kept content becomes visible immediately. Structure and action work is then admitted independently.
- Discard gets one attempt because its failure contract is “keep”; failure records the existing fallback telemetry and immediately admits the two enrichment jobs. Structure and action work reuse the current bounded recovery policy: attempt immediately, recover on launch and on the existing 60-second retry tick, and mark that kind failed after five attempts. A manual retry creates a new work generation; it never mutates an exhausted record in place.
- Any segment/title/merge change that invalidates generated content increments generation. Old responses are ignored and their work item is terminally superseded.
- Owner switch invalidates the store generation, URL tasks, and pending commits. A backend response alone never authorizes a write.
- A model failure marks only its local work item failed and calls `DesktopDiagnosticsManager.shared.recordFallback` when it changes correctness/mode. It does not mark the conversation failed or invisible.

## 11. Ordered TDD cycles

Run one cycle at a time. Do not write the next RED until the current GREEN passes. Refactor only while green. Every behavioral test uses a public production seam and a temporary owner-scoped database; source-string checks are residue tripwires, not regression coverage.

### Cycle 1 — Stable local identity, migration, and archive reader

- **RED:** Add `ConversationLocalAuthorityMigrationTests` and `ConversationArchiveReaderTests` proving fresh schema, all legacy migration branches in 10.2, required UUIDs, exact child-link rewrites, discarded-row removal, no old-owner leakage, stable pagination, and no backend/sync fields in archive output.
- **Why RED now:** current schema permits optional `clientConversationId`/`segmentId`, retains cache/upload columns, and has no local folders/labels/merge/work tables or archive reader.
- **Minimum GREEN:** add the one GRDB migration; reshape `TranscriptionSessionRecord`/`TranscriptionSegmentRecord`; expose owner-fenced archive paging and identity reads. Do not migrate UI/capture yet.
- **Retained behavior:** per-owner `omi.db`, WAL, current capture rows, transcripts, live-note cascade, and valid source relationships survive migration.
- **Expected code:** `RewindDatabase.swift`, `TranscriptionModels.swift`, `TranscriptionStorage.swift`; `ActionItemModels.swift`/`MemoryModels.swift` only for exact ID rewrite compatibility; no backend files.
- **Expected tests:** `desktop/macos/Desktop/Tests/ConversationLocalAuthorityMigrationTests.swift` **(new)**, `ConversationArchiveReaderTests.swift` **(new)**, retained `RewindDatabaseCurrentUserIdConcurrencyTests` and `RewindDatabaseLifecycleTests`.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'ConversationLocalAuthorityMigrationTests|ConversationArchiveReaderTests|RewindDatabaseCurrentUserIdConcurrencyTests|RewindDatabaseLifecycleTests'` from `desktop/macos`.
- **Deletion unlocked:** old schema conversion helpers only after legacy fixtures migrate successfully; no current callers yet.
- **Stop condition:** any legacy non-discarded transcript or exact task/memory source link cannot be migrated deterministically, or owner generation can change between queue acquisition and commit.

### Cycle 2 — Provider-independent ingestion, formatting, preferences, and location

- **RED:** Add store-level tests that feed equivalent local/cloud `BackendSegment` batches and assert identical stable rows, idempotent updates, combine/boundary/punctuation golden cases, translations, one numeric speaker ID, formatter names/timestamps, immutable session preference snapshots, and authorized/denied/timeout one-shot location behavior.
- **Why RED now:** `handleBackendSegments` persists optional server IDs/provider-shaped fields; normalization lives in Python; preferences are backend-synced; no Core Location producer or usage string exists.
- **Minimum GREEN:** add `LocalTranscriptFormatter.swift`; generate IDs before persistence; adapt `handleBackendSegments` and both producers; add a narrow one-shot Core Location provider and the required `Info.plist` usage description; snapshot local settings/timezone/input device at begin.
- **Retained behavior:** live transcript delivery, Quick Note, compact/full views, local/cloud STT switching, translation rows, and current capture timing.
- **Expected code:** `AppState+Transcription.swift`, `AppState+ListenEvents.swift`, `LocalTranscriptionService.swift`, `TranscriptionService.swift`, `TranscriptionStorage.swift`, `TranscriptionModels.swift`, `LocalTranscriptFormatter.swift` **(new)**, `desktop/macos/Desktop/Info.plist`, `desktop/macos/Desktop/Sources/ProactiveAssistants/Services/AssistantSettings.swift`, `SettingsContentView+BillingHelpers.swift`, `SettingsContentView+SettingsUpdates.swift`, `SettingsContentView+Transcription.swift`, `SBOnboardingModel.swift`, and the settings automation actions in `DesktopAutomationBridge.swift`. `AuthService.givenName` is a read dependency and does not require modification.
- **Expected tests:** `LocalTranscriptFormatterTests.swift` **(new)**, `ConversationIngestionTests.swift` **(new)**, `ConversationLocationSnapshotTests.swift` **(new)**; adapt `ListenProtocolTests`, `TranscriptSpeakerAssignmentTests`, and capture automation tests.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'LocalTranscriptFormatterTests|ConversationIngestionTests|ConversationLocationSnapshotTests|ListenProtocolTests|TranscriptSpeakerAssignmentTests'`.
- **Deletion unlocked:** durable provider/person/speech-profile fields, backend conversation binding in AppState, capture calls to backend preferences, and logged-only lifecycle handlers.
- **Stop condition:** local and cloud segments need different durable schemas; location denial blocks capture; or golden formatter output cannot match the retained Python behavior without preserving rejected fields.

### Cycle 3 — Local finalization and restart recovery

- **RED:** Rewrite finalization state-machine/retry tests to prove each current `TranscriptionFinalizationReason`, immediate local visibility, exactly-once finish, crash recovery, no upload/API request, stale-owner rejection, and bounded recovery of local work.
- **Why RED now:** `ConversationFinalizationService` selects `localSegments` upload or `cloudReconcile`, and `TranscriptionRetryService` retries that server lifecycle.
- **Minimum GREEN:** replace finalization service internals with local close/generation/work admission; adapt retry service; stop trusting `conversation_session`, memory-processing, and hosted completion events.
- **Retained behavior:** user stop, finish-and-continue, meeting end, max-duration rotation, crash recovery, timing metadata, and nonblocking continuation.
- **Expected code:** `ConversationFinalizationService.swift`, `TranscriptionRetryService.swift`, `AppState+Transcription.swift`, `AppState+ListenEvents.swift`, `TranscriptionStorage.swift`, `TranscriptionModels.swift`.
- **Expected tests:** adapt `TranscriptionFinalizationStateMachineTests.swift`, `TranscriptionRetryResilienceTests.swift`, `TranscriptionStorageRecoveryTests.swift`; add `ConversationLocalFinalizationTests.swift` **(new)** for the public local admission seam.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'TranscriptionFinalizationStateMachineTests|TranscriptionRetryResilienceTests|TranscriptionStorageRecoveryTests|ConversationLocalFinalizationTests'`.
- **Deletion unlocked:** `ConversationFinalizationStrategy`, backend binding/upload/retry/reconcile methods, `createConversationFromSegments`/`finalizeConversation` Mac calls, and cloud lifecycle acceptance.
- **Stop condition:** quit/relaunch can strand a nonempty finished capture invisibly, or finalization can commit after owner switch.

### Cycle 4 — Discard admission and physical disposal

- **RED:** Backend route tests prove authentication, input bounds, empty/over-100 fast paths, lenient parse compatibility, usage tracking, fail-keep, generation echo, and zero persistence calls. Swift tests prove local deletion only on affirmative current-generation result and no derivations.
- **Why RED now:** `should_discard_conversation` is buried inside hosted `process_conversation`; Mac finalization cannot use it without creating/uploading a server conversation.
- **Minimum GREEN:** add discard compute route/DTO/client; admit it from local finalization; make empty and over-100 decisions locally with exactly the same thresholds; physically delete affirmative discard.
- **Retained behavior:** current `conv_discard` prompt/duration context and `LenientDiscardParser`; failures keep.
- **Expected code:** `backend/routers/conversation_compute.py` **(new)**, `backend/main.py`, `backend/utils/llm/conversation_processing.py`; `APIClient+ConversationCompute.swift` **(new)**, `ConversationFinalizationService.swift`, `TranscriptionStorage.swift`.
- **Expected tests:** `backend/tests/routers/test_conversation_compute.py` **(new)** plus retained `backend/tests/unit/test_conversation_discard_parsing.py`; `ConversationDiscardAdmissionTests.swift` **(new)**.
- **Focused verification:** `(cd backend && .venv/bin/python -m pytest -q tests/unit/test_conversation_discard_parsing.py tests/routers/test_conversation_compute.py)` and Swift filter `ConversationDiscardAdmissionTests`.
- **Deletion unlocked:** hosted discard admission for Mac and retained `discarded` tombstones in local schema.
- **Stop condition:** any exception path discards content, the route touches a database/vector/notification helper, or a stale response can delete a newer transcript.

### Cycle 5 — Local catalog, detail, search, filters, paging, and readers

- **RED:** Replace repository tests with local public-seam cases for newest-first paging 50 at a time, no duplicates, count, combined filters/date boundaries, 250 ms title/overview-only search capped at 50, exact error copy, true-empty vs filtered-zero, detail-on-demand copy, refresh cooldown, offline restart, owner switching, and every direct caller in 7.3.
- **Why RED now:** repository reads local cache then server, search is remote-only, and many non-page consumers bypass the repository.
- **Minimum GREEN:** add store query methods; reduce repository to presentation state; migrate list/detail/search/count consumers and local automation reads while preserving views.
- **Retained behavior:** header, row layout, New badge, date sections, loading/no-results/true-empty visuals, row navigation/copy, manual paging, and refresh triggers.
- **Expected code:** `ConversationRepository.swift`, `AppState.swift`, `AppState+DataLoading.swift`, list/row/page/detail files, and every direct consumer listed in 7.3; `TranscriptionStorage.swift` and models.
- **Expected tests:** rewrite `ConversationRepositoryTests.swift`, `HomeStatusStoreTests.swift`, `ConversationDetailAutomationStateTests.swift`; add `ConversationLocalQueryTests.swift` **(new)** and focused caller tests where current suites exist.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'ConversationRepositoryTests|ConversationLocalQueryTests|HomeStatusStoreTests|ConversationDetailAutomationStateTests'`.
- **Deletion unlocked:** `LiveConversationRemoteDataSource`, cache/server snapshot source, reconciliation reads, count cache, remote search/detail/list/count API methods, `ServerConversation` from migrated views/callers, and Expanded row.
- **Stop condition:** any ordinary list/detail/search/count/citation/export read requires network, or filtered-zero is indistinguishable from empty history.

### Cycle 6 — Star, manual title, and generated-title precedence

- **RED:** Test rapid conflicting star/title mutations, latest-intent display, transaction failure rollback, relaunch durability, stale enrichment response, and manual-title precedence across retry/restart/merge.
- **Why RED now:** repository optimistic mutations wait for server canonical responses and use rollback baselines.
- **Minimum GREEN:** make each mutation one owner-fenced store transaction, then update presentation from the committed local snapshot; add explicit manual-title state.
- **Retained behavior:** instant star/title UI, Starred filter, Edit Title sheet/action, and generated title when no override exists.
- **Expected code:** `TranscriptionStorage.swift`, `TranscriptionModels.swift`, `ConversationRepository.swift`, `AppState+DataLoading.swift`, `ConversationRowView.swift`, `ConversationDetailView.swift`.
- **Expected tests:** `ConversationLocalMutationTests.swift` **(new)** plus relevant repository tests.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'ConversationLocalMutationTests|ConversationRepositoryTests'`.
- **Deletion unlocked:** remote star/title methods, mutation slots/baselines used only for network rollback, and title server response models.
- **Stop condition:** UI can display uncommitted state after a failed transaction or generated output can overwrite a user title.

### Cycle 7 — Local folder lifecycle

- **RED:** Test whitespace trimming, blank rejection, the current 100-character bound, duplicate-name allowance, create/edit/list in creation order, assignment/unassignment, deletion with selected destination or nil, atomic rollback, owner isolation, and absence of default/system/description/reorder behavior.
- **Why RED now:** folders are direct API calls with hosted schema fields and default-system semantics.
- **Minimum GREEN:** implement `conversation_folders` store transactions, migrate AppState and management UI, and preserve retained name/color interactions.
- **Retained behavior:** tabs, New Folder, Edit Folder, manual assignment, Delete Folder destination choice.
- **Expected code:** `RewindDatabase.swift`, `TranscriptionStorage.swift`, `TranscriptionModels.swift`, `AppState.swift`, `AppState+DataLoading.swift`, `FolderManagementViews.swift`, `ConversationsPage.swift`, row/detail folder controls.
- **Expected tests:** `ConversationFolderStorageTests.swift` **(new)**, rewrite folder portions of repository/automation tests.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'ConversationFolderStorageTests|ConversationRepositoryTests|ConversationDetailAutomationStateTests'`.
- **Deletion unlocked:** folder API methods/models, `backend/routers/folders.py` public surface and exclusive tests, database default seeding from the desktop path, description/system/category/reorder UI/protocol.
- **Stop condition:** folder delete can orphan a foreign key or partially move conversations, or creation order changes after restart.

### Cycle 8 — Detail projection, local speaker labels, translations, and local task display

- **RED:** Test every retained detail state in IR-327 through IR-353, local detail loading, translated rows after restart, You/custom naming single/apply-all/future-live behavior, Save atomicity/Cancel no-op, local action-item source query, and analytics without conversation ID.
- **Why RED now:** detail consumes `ServerConversation`, People, `personId`, remote assignment, embedded `actionItemsJson`, locks/category/source.
- **Minimum GREEN:** project local detail/task rows; add scoped label transaction; update live ingestion label lookup; remove rejected cards/chips/locks/People while keeping shells/transitions.
- **Retained behavior:** exact detail/drawer/copy/bubble/naming/action-item UX enumerated in sections 4 and 8.
- **Expected code:** `ConversationDetailView.swift`, `SpeakerBubbleView.swift`, `NameSpeakerSheet.swift`, `LiveNameSpeakerSheet.swift`, `RewindPage.swift`, `AppState+DataLoading.swift`, `TranscriptionStorage.swift`, `ActionItemStorage.swift` narrow query seam, analytics call site.
- **Expected tests:** adapt `TranscriptSpeakerAssignmentTests.swift`, `ConversationDetailAutomationStateTests.swift`; add `ConversationSpeakerLabelTests.swift` and `ConversationDetailProjectionTests.swift` **(new)**.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'ConversationSpeakerLabelTests|ConversationDetailProjectionTests|TranscriptSpeakerAssignmentTests|ConversationDetailAutomationStateTests'`.
- **Deletion unlocked:** People UI/API/state, person IDs, remote speaker assignment, embedded action items, lock/category/source metadata, and lazy-first-open enrichment.
- **Stop condition:** a label leaks across conversations, future live segments ignore the saved mapping, or Action Items renders a server-embedded copy.

### Cycle 9 — Permanent local deletion cascade

- **RED:** Seed a conversation with segments, live notes, completed/edited/open exact-source tasks, linked memory, and unrelated records. Prove one authorized operation removes exact descendants, invokes the Memory seam, preserves unrelated rows, rolls back on injected failure, removes list/search/archive visibility, and remains deleted after restart.
- **Why RED now:** `deleteByBackendId` and remote cascade are authoritative; task rows lack an exact-source deletion method and memories currently soft-delete separately.
- **Minimum GREEN:** implement one store-coordinated transaction/authorization lease; add narrow exact-source task and memory cleanup methods. If GRDB actor boundaries prevent a single database closure, expose transaction-scoped helpers over the same owner pool rather than sequential best-effort calls.
- **Retained behavior:** Delete confirmation and navigation away after successful deletion.
- **Expected code:** `TranscriptionStorage.swift`, `ActionItemStorage.swift`, `MemoryStorage.swift`, and repository/AppState/detail/row delete paths. Existing `live_notes.sessionId` foreign-key cascade requires no `NoteStorage.swift` change.
- **Expected tests:** `ConversationDeletionCascadeTests.swift` **(new)** plus repository/detail automation deletion cases.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'ConversationDeletionCascadeTests|ConversationRepositoryTests|ConversationDetailAutomationStateTests'`.
- **Deletion unlocked:** remote delete/cascade calls, local deleted tombstone state, and backend-keyed delete helpers.
- **Stop condition:** exact-source cleanup cannot share one owner-fenced transaction, or any injected failure leaves a partial cascade.

### Cycle 10 — Crash-safe local merge

- **RED:** Test two-or-more source validation, chronological ordering, current gap adjustment, stable copied segment IDs without collisions, `.merging` replacement invisibility, typed provenance, interruption before/after validation, restart recovery, source preservation until commit, atomic final source cascade, and new enrichment generation.
- **Why RED now:** `ConversationsPage.performMerge` calls hosted `merge_conversations`, which also manipulates GCS audio, photos, vectors, notifications, and source deletion.
- **Minimum GREEN:** implement prepare/copy/validate/commit phases in local store. Until final commit, sources remain visible and replacement is hidden. Recovery either completes a validated replacement or deletes the incomplete replacement with sources untouched.
- **Retained behavior:** Select/Merge controls, chronological combined transcript, navigation/result refresh.
- **Expected code:** `TranscriptionStorage.swift`, `TranscriptionModels.swift`, `ConversationsPage.swift`, `ConversationRepository.swift`; local formatter/gap helper.
- **Expected tests:** `ConversationLocalMergeTests.swift` **(new)** and retained `ConversationMergeSelectionTests.swift`.
- **Focused verification:** `./scripts/dev-feedback.py --once swift 'ConversationLocalMergeTests|ConversationMergeSelectionTests'`.
- **Deletion unlocked:** desktop `mergeConversations`, merge response DTOs, server merge dependency for Mac, generic external-data provenance.
- **Stop condition:** any crash point can delete a source before a validated replacement is durable, or recovery can produce two visible replacements.

### Cycle 11 — Structure/summary/emoji/commitment enrichment

- **RED:** Backend tests prove authenticated/bounded candidate-only structure, IANA timezone/local capture-time handling, retained prompt caching/validation, no category/Calendar links/writes, no database imports/calls, usage tracking, and generation echo. Swift tests prove durable work/retry, owner/content-generation fencing, manual-title protection, local commit, independent failure, restart recovery, and no Calendar creation.
- **Why RED now:** `get_transcript_structure` is invoked by hosted `process_conversation`, returns rejected category/events shape, and the server persists the whole conversation.
- **Minimum GREEN:** add structure route and generated/manual DTO client, narrow retained response, run it from durable local work, validate and commit title/overview/emoji/commitments locally.
- **Retained behavior:** current `conv_structure` feature key, prompt structure for retained fields, local-time conversion, title/overview/emoji quality, commitments with `created = false`, processing overlay.
- **Expected code:** `backend/routers/conversation_compute.py` **(new)**, `backend/main.py`, `conversation_processing.py`, candidate models; `APIClient+ConversationCompute.swift` **(new)**, `ConversationFinalizationService.swift`, `TranscriptionStorage.swift`, `ConversationDetailView.swift`.
- **Expected tests:** extend `backend/tests/routers/test_conversation_compute.py`; retain relevant conversation-processing/prompt-cache/QoS unit tests; add `ConversationStructureEnrichmentTests.swift` **(new)**.
- **Focused verification:** backend compute route tests plus `tests/unit/test_omi_qos_tiers.py` selected `conv_structure` cases; Swift filter `ConversationStructureEnrichmentTests|ConversationDetailProjectionTests`.
- **Deletion unlocked:** hosted structure persistence for Mac, generated category, Calendar event-link path, plan-based lazy enrichment, manual summary route dependency.
- **Stop condition:** response can write backend state, rejected fields remain in the public DTO, or stale/generated title can beat manual title.

### Cycle 12 — Separate action-item enrichment and local dedup

- **RED:** Backend tests prove a different route/call from structure, at most ten supplied open candidates, completed-candidate defense, task ID exactness, date normalization/past clearing, candidate-only/no-write behavior, auth/bounds/generation. Swift tests prove local seven-day/open/source exclusions, 0.6 similarity threshold, empty-context fallback, exact source UUID, transactional candidate application, independent failure, and no overwrite of successful structure.
- **Why RED now:** `_fetch_dedup_candidates` reads Pinecone/Firestore and `_save_action_items` writes embedded and standalone cloud tasks/vectors/notifications.
- **Minimum GREEN:** expose pure action candidate route; gather bounded local candidates through `EmbeddingService`/`ActionItemStorage`; validate candidate actions against sent opaque IDs; apply through local task seams with source UUID.
- **Retained behavior:** separate `conv_action_items` feature/prompt, prompt caching, commitment/request filters, future due-date resolution, dedup/update/complete proposal behavior, and Action Items detail section.
- **Expected code:** `backend/routers/conversation_compute.py` **(new)**, `conversation_processing.py`; `APIClient+ConversationCompute.swift` **(new)**, `ConversationFinalizationService.swift`, `ActionItemStorage.swift`, and the detail projection. Current `EmbeddingService.embed`, `searchSimilar`, and `indexLoaded` are consumed without changing `EmbeddingService.swift`.
- **Expected tests:** extend backend compute route tests and existing action-item date/prompt tests; add `ConversationActionItemEnrichmentTests.swift` **(new)** and narrow ActionItemStorage tests.
- **Focused verification:** backend action candidate cases; `./scripts/dev-feedback.py --once swift 'ConversationActionItemEnrichmentTests|ConversationDetailProjectionTests|ActionItemLocalIdentityMutationTests'`.
- **Deletion unlocked:** `_fetch_dedup_candidates`/`_save_action_items` as Mac conversation dependencies, embedded conversation action items, cloud task/vector/notification side effects from Mac finalization.
- **Stop condition:** backend resolves arbitrary local IDs, completed/deleted tasks suppress new work, a failed action call changes structure output, or source identity is not exact.

### Cycle 13 — Projection removal, route/contracts cleanup, and residue closure

- **RED:** Invert existing request/route/generator/parity tests so retired Mac requests and S-10-owned public backend routes are absent, retained compute/listen/PTT/Memory routes remain, generated Swift compiles without retired DTOs, and residue allowlists contain only explicit later-slice owners.
- **Why RED now:** old API methods/models/routes/workflows/tests remain executable even after local behavior is green.
- **Minimum GREEN:** migrate last callers; delete remote/cache/reconcile types, rejected settings/UI, S-10-owned routes/helpers/tests, conversation fixture/cases/workflow trigger, obsolete generated targets/output; update route manifest, `PRODUCT.md`, `backend/AGENTS.md`, `desktop/macos/AGENTS.md`, `FORK.md`, affected E2E docs/flows, `desktop/macos/CHANGELOG.json`, and check manifests together.
- **Retained behavior:** `/v4/listen` transient transport until S-16; PTT `/v1/tools` until S-19; Memory/task/general language routes owned elsewhere; independent `desktop-core-e2e-t0`; S-12's Memory parity cases/job.
- **Expected code:** every migrated file in section 7; `backend/main.py`, affected routers/manifests/tests, `export_openapi.py`, `generate_swift_openapi_types.py`, `OmiApi.generated.swift`, parity test/fixture/workflow, `PRODUCT.md`, root/component `AGENTS.md`, `FORK.md`, relevant E2E flows/docs.
- **Expected tests:** route absence/presence, OpenAPI generator, desktop REST inventory, rewritten/removed old request tests, retained parity Memory cases, static residue tests only where an existing guard already owns the invariant.
- **Focused verification:** all commands in sections 13 and 14, followed by component suites and named-bundle acceptance.
- **Deletion unlocked:** all remaining S-10-owned compatibility code. Later-slice allowlisted residue remains documented, not hidden.
- **Stop condition:** a non-Windows in-tree caller remains, OpenAPI/route policy is stale, Memory parity/T0 is removed early, or deletion would cross an S-16/S-19/S-23 live owner.

## 12. Cross-slice ownership and handoffs

| Slice | S-10 provides / changes | S-10 must not take |
|---|---|---|
| S-02 | Extends its owner-scoped DB generation and authorization lease. | A second DB, user-key system, or cross-owner fallback. |
| S-03 | Converts its durable capture/session seam to authority and preserves real capture acceptance. | Audio capture redesign unrelated to local authority. |
| S-08 | `ConversationArchiveReader` with complete owner-scoped paging, transcript, and retained metadata; no cloud fetch. | Archive packaging, account deletion orchestration, or upload. |
| S-11 | Local summary/detail/count reader for Home and citation navigation. | Home/Chat product redesign. |
| S-12 | Stable conversation UUID, exact memory source rewrite, and transaction-scoped deletion hook. | Full Memory schema/sync/search lifecycle. S-12 removes final parity file/job/discovery residue. |
| S-13 | Stable conversation UUID, exact task source, related-open-task query/application seam, delete/merge source handling. | Full Task authority, staged tasks, or task sync retirement. |
| S-14 | Local conversation reader plus local capture language snapshot. | General assistant language/profile/goal authority. |
| S-16 | Mac stops server conversation IDs, lifecycle, custom-provider/device/call/VAD override/multichannel/web-listen dependencies; receives an explicit remaining listen allowlist. | Final `/v4/listen` implementation, backend `LiveConversationController`/SpeakerMatcher deletion, or transport rollout. |
| S-19 | Leaves remote PTT `/v1/tools/conversations`, `/search`, `/search-chunks` untouched and identified. | PTT retrieval/tool migration. |
| S-20 | Preserves auth and usage tracking on three compute routes. | Subscription/fair-use redesign. |
| S-22 | Calls existing `conv_discard`, `conv_structure`, `conv_action_items` feature keys. | Model-profile/gateway/shadow system deletion or hard-coded provider policy. |
| S-23 | Stops new Mac Firestore conversation/folder/task/audio writes and identifies server-only helpers/collections/jobs. | Live collection wipes, final hosted datastore deletion, or deployed migration. |
| S-24 | Removes Mac conversation search/vector dependency; local title/overview search and local task similarity remain. | Global Pinecone/index deletion. |
| S-25 | Removes Mac audio/finalization job creation and public playback usage. | Cloud Run/Cloud Tasks deployment deletion. |
| S-28 | Supplies no server-shaped names in retained local contracts. | Namespace/rebrand work. |

Shared-file rule: if S-12 or S-13 has already changed `MemoryStorage.swift`, `ActionItemStorage.swift`, their models, or migrations when implementation starts, rebase and preserve their authority model. S-10 may add only the minimum source-linked transaction seams, in a separate commit if they are independently testable.

## 13. Repository residue-search strategy

Run searches from repository root. Each command must return either no match or matches listed in a checked-in handoff table with exact later owner and reason. Tests/fixtures that intentionally assert absence may be allowlisted separately from production code. Windows matches are excluded explicitly; generated/build/vendor directories are excluded where shown.

### Desktop authority residue

```bash
rg -n 'ServerConversation|ConversationRemoteDataSource|LiveConversationRemoteDataSource|ConversationSnapshotSource|ConversationReconciliationPolicy' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests

rg -n 'backendId|backendSynced|serverUpdatedAt|cacheCompleteness|pendingUpload|pending_upload|uploading|cloudReconcile|cloud_reconcile|finalizationStrategy' \
  desktop/macos/Desktop/Sources/Rewind/Core desktop/macos/Desktop/Sources/ConversationFinalizationService.swift \
  desktop/macos/Desktop/Sources/TranscriptionRetryService.swift desktop/macos/Desktop/Tests

rg -n 'bindBackendConversation|syncServerConversation|upsertFromServerConversation|upsertSegmentsFromServerConversation|deleteByBackendId|update.*ByBackendId' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests
```

### Rejected conversation metadata and UI

```bash
rg -n 'personId|person_id|speech_profile_processed|stt_provider|isLocked|Transcript locked|Copy Link|external_data|processingConversationId|processingMemoryId' \
  desktop/macos/Desktop/Sources backend --glob '!backend/testing/**' --glob '!backend/tests/**'

rg -n 'Store Recording|Store Recordings|Private Cloud|training.data|data.protection|conversation_audio|audioFiles|AudioFile' \
  desktop/macos/Desktop/Sources backend/routers backend/database backend/services backend/utils \
  --glob '!backend/testing/**' --glob '!backend/tests/**'

rg -n 'Work|Personal|Social|category_mapping|initialize_system_folders|reorder_folders|folder.*description|description.*folder' \
  desktop/macos/Desktop/Sources/MainWindow backend/routers/folders.py backend/database/folders.py

rg -n 'ImprovedTranscript|transcript_segments_compressed|data_protection_level|calendar_meeting_context|meeting_link|client_device_id|client_platform|call_id' \
  desktop/macos/Desktop/Sources backend/models backend/routers backend/database backend/utils/conversations backend/utils/llm
```

Interpret `calendar_meeting_context` carefully: no conversation structure/action route may accept it, while separately owned Calendar code outside the conversation domain is not S-10 residue. Interpret `client_platform` carefully: coarse `macos` diagnostics may survive only in the S-16 listen allowlist.

### Retired Mac REST calls and route surface

```bash
rg -n 'v1/conversations|v1/folders|v1/sync/audio|v2/audio-merge-jobs/run|v1/users/(people|store-recording-permission|private-cloud-sync|training-data-opt-in|transcription-preferences|geolocation|location-context-consent)' \
  desktop/macos backend .github scripts contract_tests \
  --glob '!desktop/windows/**' --glob '!desktop/macos/Desktop/.build/**' \
  --glob '!desktop/macos/Desktop/Sources/Generated/**'

rg -n 'getConversations\(|getConversation\(|getConversationsCount\(|searchConversations\(|mergeConversations\(|getFolders\(|getPeople\(|assignSegmentsBulk\(' \
  desktop/macos/Desktop/Sources --glob '*.swift'

rg -n 'testing/contracts|test_desktop_backend_parity|contract_tests/fixtures/conversations.json|desktop-backend-contracts|backend/database/conversations.py' \
  .github backend scripts contract_tests FORK.md
```

Expected retained route matches at S-10 close:

- the three `/v1/conversation-compute/*` endpoints and their client/tests;
- `/v4/listen` plus S-16-owned internals/tests;
- PTT `/v1/tools/conversations`, `/search`, `/search-chunks` under S-19;
- any server-only conversation persistence explicitly required until S-16/S-23, with no ordinary Mac caller;
- Memory cases in `test_desktop_backend_parity.py`, the mixed `contracts` job, Memory fixture/trigger, and independent T0 job until S-12.

### Identity and local-schema proof

```bash
rg -n 'conversationId|segmentId|conversation_folders|conversation_speaker_labels|conversation_merge_sources|conversation_enrichment_work' \
  desktop/macos/Desktop/Sources/Rewind/Core desktop/macos/Desktop/Tests

rg -n 'ConversationArchiveReader|conversationArchivePage' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests

rg -n '/v1/conversation-compute/(discard|structure|action-items)' \
  backend desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests
```

## 14. Focused and component-level verification commands

Commands are verified against the current guides/scripts. Replace the quoted Swift filter with the current cycle's test names; `dev-feedback.py` accepts a regex filter.

### Fast loop

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'ConversationLocalAuthorityMigrationTests|ConversationArchiveReaderTests'
```

```bash
cd backend
.venv/bin/python -m pytest -q \
  tests/unit/test_conversation_discard_parsing.py \
  tests/routers/test_conversation_compute.py
```

For pre-existing tests whose exact file survives, use the same command with their actual path; do not invent a test selector before the RED file exists.

### Contract and generated-surface checks

```bash
cd backend
scripts/openapi_runner.sh scripts/route_policy_inventory.py \
  --manifest route_policy_manifest.yaml --check --report-only
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
.venv/bin/python -m pytest testing/contracts -v
```

During C13, regenerate intentionally with:

```bash
cd backend
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
```

Do not delete the whole parity invocation in S-10: Memory cases remain until S-12. If `backend/testing/contracts` has already been removed by an integrated S-12, reconcile against that landed state instead of recreating it.

### Component suites and compile

```bash
cd desktop/macos
./test.sh
xcrun swift build -c debug --package-path Desktop
```

```bash
cd backend
bash test-preflight.sh
bash test.sh
```

### Repository gates

```bash
make preflight
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
```

If implementation is a `fix:` commit, follow the root guide before committing:

```bash
scripts/pr-preflight --suggest
scripts/failure-class
```

The implementation PR body must also pass `scripts/pr-preflight --pr-body-file /tmp/pr-body.md`. This planning task does not create a PR or product commit.

## 15. Real named-bundle and user-path acceptance

Never stop or replace `/Applications/Omi.app` or `Omi Beta.app`. Use a disposable named bundle.

### Build and bring-up

```bash
cd desktop/macos
OMI_APP_NAME="omi-s10-local-conversations" OMI_AUTOMATION_PORT=47810 ./run.sh --full
OMI_AUTOMATION_PORT=47810 ./scripts/omi-ctl wait-ready
OMI_AUTOMATION_PORT=47810 ./scripts/omi-ctl health
```

After the first full build, reuse it only with `OMI_APP_NAME="omi-s10-local-conversations" OMI_AUTOMATION_PORT=47810 ./run.sh --yolo --fast-only`. Confirm `OMI_AUTOMATION_PORT=47810 ./scripts/omi-ctl health` identifies `omi-s10-local-conversations` before exercising it. If port 47810 is occupied, choose one free high port and use that exact value for the launch, every `omi-ctl`, and every `omi-harness` command.

### Required T1 paths

Run current retained flows individually through the bridge lane, updating their assertions to local authority:

```bash
cd desktop/macos
scripts/omi-harness run e2e/flows/capture-lifecycle.yaml --lane bridge --port 47810 --bundle-id com.omi.omi-s10-local-conversations
scripts/omi-harness run e2e/flows/conversation-detail.yaml --lane bridge --port 47810 --bundle-id com.omi.omi-s10-local-conversations
scripts/omi-harness run e2e/flows/conversation-folders.yaml --lane bridge --port 47810 --bundle-id com.omi.omi-s10-local-conversations
scripts/omi-harness run e2e/flows/speaker-naming.yaml --lane bridge --port 47810 --bundle-id com.omi.omi-s10-local-conversations
scripts/omi-harness run e2e/flows/language.yaml --lane bridge --port 47810 --bundle-id com.omi.omi-s10-local-conversations
scripts/omi-harness run e2e/flows/vocabulary.yaml --lane bridge --port 47810 --bundle-id com.omi.omi-s10-local-conversations
scripts/omi-harness run e2e/flows/quick-note.yaml --lane bridge --port 47810 --bundle-id com.omi.omi-s10-local-conversations
scripts/omi-harness run e2e/flows/recording-finalization.yaml --lane bridge --port 47810 --bundle-id com.omi.omi-s10-local-conversations
```

`audio-recording.yaml` is a manual microphone/system-audio capture flow, not cloud playback; retain and execute its checklist against the named bundle. Rewrite `privacy-settings.yaml` so its snapshot asserts Store Recordings and Private Cloud Sync are absent while retained local permission/privacy controls remain.

Manual/automation acceptance must prove:

1. Capture with local Parakeet, stop, see the conversation immediately, open/copy transcript, quit/relaunch, and see identical data.
2. Capture with managed cloud STT when a development endpoint/entitlement is available; verify no server conversation ID is required and received translations survive restart.
3. Disconnect or point `OMI_PYTHON_API_URL` at an unreachable local address after capture; list/detail/search/date/star/folder/title/speaker/copy/merge/delete and relaunch still work. No operation silently falls back to cloud data.
4. Search title and overview with debounce; verify exact loading/failure/no-results copy, filter-zero vs true-empty, 50-row Load older, date/star/folder combinations, activation refresh cooldown.
5. Name one speaker, apply to one/all, inject a future same-number segment, and verify only this conversation changes.
6. Merge multiple conversations, kill only the disposable named bundle at each injected merge checkpoint, relaunch, and verify either sources or one validated replacement—not data loss/duplication.
7. Delete a conversation with completed/edited source tasks and a linked memory fixture; verify exact cascade and unrelated preservation.
8. Switch between two test owners while reads and enrichment responses are in flight; verify zero cross-owner display/commit.
9. Exercise location with two fresh disposable bundle identities or resettable test doubles: authorized returns one snapshot; denied/restricted/timeout records none and capture succeeds. Do not reset permissions for production bundles.
10. With a development backend and non-production credentials, exercise the three compute calls separately and verify structure can succeed while action items fail and vice versa. Inspect local DB state and backend logs for candidate-only behavior and sanitized logging.

Run Tier 2 after individual T1 flows:

```bash
cd desktop/macos
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-s10-local-conversations
```

Save receipts/logs under the harness result directory and record exact commands/results in the eventual commit/PR evidence. Missing live model credentials block only the live-compute acceptance item; they do not waive hermetic tests, offline/restart proof, or local capture acceptance.

## 16. Repository closure versus separately authorized live operational closure

### Repository closure in the S-10 implementation PR

- Mac no longer writes, reads, reconciles, or identifies conversations through hosted records.
- All non-Windows in-tree ordinary callers use local APIs; residue is empty or has an exact S-16/S-19/S-23 handoff.
- S-10-owned public routes, DTOs, request tests, settings, and parity conversation fixture/cases/triggers are removed.
- The three stateless compute routes, auth/usage/bounds/no-write tests, and generated client contract are present.
- Local schema migration, behavioral tests, full component suites, preflight, named-bundle offline/restart paths, and docs are complete.
- No compatibility alias or dual-write remains.

### Live operational closure requiring separate authorization

Repository completion does **not** prove or authorize:

- deploying the Python backend or desktop release;
- deleting existing Firestore conversation/folder/People/finalization documents or indexes;
- deleting GCS audio/playback objects;
- deleting/draining Cloud Tasks queues, Cloud Run worker/service configuration, scheduled jobs, Redis keys, Pinecone indexes, or secrets;
- removing external API support before confirming supported non-repository clients;
- migrating/importing a user's historic cloud-only conversations into the Mac.

Those are S-16/S-23/S-24/S-25 or release operations. Their closure needs production inventory, approved rollout/retention policy, backups where applicable, live telemetry, and explicit user sign-off. S-10 must stop creating new Mac-hosted conversation state so later cleanup has a stable cutoff, and must document the deployed version/time that establishes that cutoff when deployment is eventually authorized.

No code merge alone closes an incident or data-removal obligation. Live closure requires evidence from the deployed environment and a named owner.

## 17. Risks, ambiguities, and explicit stop points

| ID | Risk / ambiguity | Gate and mitigation |
|---|---|---|
| R1 | Existing local rows may have no UUID, duplicate IDs, or conflicting backend/client IDs. | Migration tests cover every branch; stop rather than drop a non-discarded transcript. Generate new IDs and rewrite only exact local references. |
| R2 | `action_items`/`memories` lack FK relationships and live behind separate actors. | Use the same owner DB transaction/authorization lease; do not accept sequential best-effort cascade. Coordinate S-12/S-13 before touching shared files. |
| R3 | The current local schema is a partial server cache, so some cloud-only history may never exist locally. | S-10 has no cloud backfill authorization. Product owner must explicitly choose an import project if historic cloud-only data is launch-critical. This does not block new local authority. |
| R4 | Server lifecycle messages and `/v4/listen` internals are entangled with segment delivery. | S-10 stops Mac consumption but does not delete shared backend machinery until S-16. Keep an exact allowlist and behavioral cloud-STT test. |
| R5 | Deleting public routes may break unknown external mobile/web clients not present in the checkout. | In-repo search is necessary but not sufficient for external clients. Require API ownership confirmation before live deploy/removal; repository can first remove Mac callers. |
| R6 | One-shot Core Location has no current implementation or usage string. | Build behind a protocol, test all authorization states/timeouts, add only required foreground usage copy, and stop if release signing/capability review requires broader permission. |
| R7 | Local merge and cascades can lose data under crashes. | Failure-injection tests at every boundary; sources survive until final transaction; no audio merge. Stop on any ambiguous recovery state. |
| R8 | IR-727 names GPT-5.4-mini, while current `model_config.py` also maps the max profile to GPT-5.4; gateway/shadow routes exist. | S-10 calls the existing feature keys and verifies the premium mapping/prompt behavior without hard-coding a new model. S-22 owns profile/gateway policy. Stop if product requires one fixed model across profiles before S-22 decides it. |
| R9 | Backend prompt currently returns category and Calendar events and may read hosted profile/calendar context. | Candidate DTO omits category/links; Mac supplies local first name/timezone/transcript; no Firestore profile/calendar lookup. Preserve commitment candidates with `created = false`. |
| R10 | Action-item semantic dedup currently depends on Pinecone/Firestore; local `EmbeddingService` uses transient Gemini proxy and a mixed action/staged index. | Filter `.actionItem`, open/recent/source exclusions, threshold/cap; fail with empty related context rather than cloud fallback. S-13 owns deeper task-index cleanup. |
| R11 | Generated DTO removal can accidentally break unrelated Memory/Task clients because `TARGET_SCHEMAS` is transitive. | Regenerate, compile, run app-client generator tests and remaining Memory parity; remove schemas only when no retained reference. |
| R12 | “Processing” can become another sync state. | Store work by kind/generation only; transcript remains visible; errors are local compute errors; no upload terminology or server polling. |
| R13 | Static residue searches can produce false confidence. | They run only after public-seam behavioral tests and named-bundle acceptance. Any new guard must cite a real failure class/incident and existing CI lane per `AGENTS.md`. |
| R14 | Scope can expand into S-12/S-13/S-16/S-23. | Respect section 12. Stop and split/handoff when a change is not necessary to make the Mac conversation path local-authoritative. |

External inputs that can remain unresolved at repository completion:

- live development Firebase/OpenAI credentials for manual candidate-compute acceptance;
- production external-client inventory and deployed route-removal timing;
- policy for preexisting cloud-only user history and data retention/deletion.

None permits a dual-authority fallback. If an external decision delays route deletion, the Mac still stops using/writing the route and the residue is explicitly assigned rather than retained as compatibility code.

## 18. Final completion checklist

### Requirements and architecture

- [ ] All 123 assigned IRs remain individually mapped and their behavioral tests are traceable to the cycles above.
- [ ] Baseline and ledger gates pass on the implementation checkout.
- [ ] `omi.db` is the only durable Mac conversation/transcript authority; no dual-write or server fallback exists.
- [ ] Local identity, owner generation, migration, archive reader, and schema column absence are proven.
- [ ] S-08/S-11/S-12/S-13/S-14/S-16/S-19/S-22/S-23/S-24/S-25 handoffs are recorded in code/PR documentation where applicable.

### Behavior

- [ ] Both STT producers persist through one local ingestion/normalization seam with required UUIDs.
- [ ] Local finalization/restart recovery and every retained finalization reason pass.
- [ ] Empty, over-100-word, short-classifier, affirmative-discard, and fail-keep cases pass.
- [ ] List/detail/count/search/date/star/folder/page/refresh/offline/owner-switch behavior passes with exact UI states/copy.
- [ ] Manual title precedence, local generated title/overview/emoji/commitments, and separate action-item failure isolation pass.
- [ ] Detail/drawer/copy/translation/speaker-label/action-item presentation invariants pass.
- [ ] Permanent delete cascade and crash-safe merge pass injected-failure and restart tests.
- [ ] Location authorized/denied/restricted/timeout behavior passes without background tracking.

### Deletion and boundaries

- [ ] Every KEEP AS IS / ADAPT / DELETE / SIMPLIFY AFTER / OUT OF SCOPE item is reconciled.
- [ ] All section 13 searches are empty or have exact later-slice allowlist entries.
- [ ] S-10-owned Mac REST calls/routes/settings/DTOs/tests are removed.
- [ ] Conversation parity cases and `contract_tests/fixtures/conversations.json` are removed; Memory parity and independent T0 remain unless S-12 has landed.
- [ ] `/v4/listen`, PTT tools, shared hosted storage/jobs, and general language APIs are changed only within the ownership boundaries in section 12.
- [ ] No new TODO/FIXME/HACK lacks a tracking issue; no compatibility alias remains.

### Verification and evidence

- [ ] Every cycle's RED was observed for the intended behavioral reason and its GREEN focused command passed.
- [ ] OpenAPI route policy, Swift generator `--check`, and remaining parity contracts pass.
- [ ] `desktop/macos/test.sh`, desktop debug compile, `backend/test-preflight.sh`, and `backend/test.sh` pass.
- [ ] `make preflight`, the ledger validator, and `git diff --check` pass.
- [ ] `omi-s10-local-conversations` completed the required local/cloud-if-available, offline, restart, owner-switch, merge-interruption, cascade, settings, and location acceptance paths.
- [ ] Real-path commands and receipts are in the commit/PR evidence; any unavailable live credential check is named honestly.
- [ ] `PRODUCT.md`, `backend/AGENTS.md`, `desktop/macos/AGENTS.md`, `FORK.md`, affected E2E docs/flows, generated contracts, manifests, and desktop changelog are updated with code when required.
- [ ] A `fix:` change declares/validates its failure class and the PR body passes `scripts/pr-preflight`.
- [ ] No production app, production data, deployment, push, PR, or merge occurred without the separately required authorization.

S-10 repository work is complete only when every applicable box is checked and repository closure is not misreported as live operational cleanup.
