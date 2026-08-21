# Wave 3 · S-19 — Reconnect PTT to local product data and remove rejected tools

## 1. Title and slice identity

| Field | Value |
|---|---|
| Wave | 3 — reconnect retained cross-domain behavior to local owners |
| Slice | S-19 |
| Name | Reconnect PTT to local product data and remove rejected tools |
| Plan kind | TDD implementation plan; no implementation is contained here |
| Primary decisions | IR-054 through IR-119, IR-600 through IR-602, IR-924 through IR-926, IR-932 |
| Future development bundle | `omi-wave3-s19` |
| Target branch for a future PR | `main` |
| Output | `bootstrap-scaffold/wave-3/s-19 tdd.md` |

This slice preserves the complete spoken-assistant lifecycle while changing where its retained tools obtain durable product data. It also removes the voice-only tools and wire data that the requirements review rejected. It is not a PTT redesign, a model-portfolio migration, or a cloud-data decommission.

## 2. Planning status and pinned baseline

**Status:** ready to start. Entry gates in section 5 remain cycle-specific. This document plans future changes; it does not claim that any RED, GREEN, component suite, named-bundle run, or live user path has passed.

Planning was performed against the exact completed Wave 2 closeout:

```text
HEAD = 711269baf5e653bd62132688998732207f11dd3c
Wave 2 closeout ancestor check = passed
Additional product commits after the closeout = none
Working tree before planning = clean
```

The baseline commands were:

```bash
git merge-base --is-ancestor 711269baf5e653bd62132688998732207f11dd3c HEAD
git rev-parse HEAD
git status --short --branch
python3 bootstrap-scaffold/validate-requirements-ledger.py
```

The planning-time ledger validator reported all 714 indexed rows and all 714 detailed sections present and reviewed. Future implementation must re-run these checks after rebasing onto the then-current integrated predecessor state. A different HEAD is not automatically wrong, but any product delta since `711269ba` must be inventoried before Cycle 1; do not silently apply this source inventory to a materially changed tree.

## 3. Outcome

When S-19 is complete:

- held and locked PTT, the warm realtime session, OpenAI Realtime, Gemini Live, failover, relay, final batch STT, language correction, barge-in, screen understanding, journal continuity, diagnostics, status banners, and notch lifecycle still behave as reviewed;
- `get_conversations`, `search_conversations`, `get_memories`, `search_memories`, `get_daily_recap`, `search_screen_history`, `get_tasks`, `get_action_items`, `create_action_item`, and `update_action_item` obtain or commit durable product state through the current authenticated owner's local Mac authority;
- conversation topic search is local hybrid search: FTS5 over authoritative title/overview plus locally persisted embeddings and local similarity, with keyword hits merged before semantic hits;
- transient embedding and managed-model computation may cross the authenticated backend, but the backend does not become durable Conversation, Memory, Task, Rewind, or recap authority;
- every asynchronous tool path carries one immutable `RuntimeOwnerAuthorizationSnapshot` (or the already-bound voice-turn owner derived from it) through compute, reads, writes, indexing, reminders, telemetry, and publication, and rejects late results after an owner transition;
- the three hosted conversation-tool routes, their exclusive service/DTO/client residue, the unread realtime-session audit writer, unused usage identity fields, customer-BYOK residue, `point_click`, and realtime `ask_higher_model`/its live-web claim are gone;
- no tool declaration, generated tool surface, provider instruction, runtime dispatcher, permission policy, test fixture, or current documentation advertises a deleted tool, account plan, or provider path;
- normal typed Chat still uses managed Claude through `/v2/chat/completions`; both realtime providers remain; shared cloud Conversation/Typesense/Pinecone infrastructure is handed to S-23/S-24 rather than prematurely deleted; and billing remains disabled.

## 4. Authorizing requirements

The live `requirements-challenge.md` decisions are authoritative. No conflict was found between those decisions and the S-19 brief in `deletion-map.md` at this baseline.

| Decisions | Required S-19 treatment |
|---|---|
| IR-054 | Keep PTT as a parent capability; completion is the full child traversal, not merely a successful microphone turn. |
| IR-055, IR-059, IR-060, IR-061 | Keep the WebSocket relay fallback, final completed-turn batch STT, provider-native realtime primary path, both OpenAI and Gemini, explicit switching, and cross-provider failover. |
| IR-056, IR-057, IR-058, IR-062 | Keep count-only per-user usage/cost/quota; delete the unread hashed `realtime_sessions` audit documents/writer and all customer-BYOK access/residue; managed service credentials remain. |
| IR-063, IR-064, IR-065, IR-066 | Keep Accessibility-backed global hold, double-tap locked mode, presets/custom/disabled shortcut state, and Automatic plus stable-UID microphone selection. |
| IR-067, IR-068 | Repair optional audible start/end cues and their ordering around the retained enabled-by-default output muting; make cancel/error semantics deliberate. |
| IR-069, IR-070 | Keep the existing accidental-tap/silence/non-speech admission and complete CoreAudio near-zero detection/recovery behavior. |
| IR-071, IR-072 | Keep ordered Voice Assistant Languages and local per-turn correction; make all three batch callers use that authority, followed by at most one multilingual/auto-detect retry when a language-specific result is empty. Delete the English special case and ambient-language coupling. |
| IR-073, IR-074, IR-075 | Keep immediate barge-in, persist the old question plus only produced partial answer, and retain one interrupted marker projected to UI and next-turn context. |
| IR-076, IR-077, IR-078, IR-079 | Keep current-screen vision, one raw in-memory capture at PTT-down, opportunistic local OCR correction with provenance/no backend hint leakage, and eager background JPEG/hash preparation. |
| IR-080, IR-081, IR-082, IR-083 | Keep five-second freshness, the typed-Chat-only sharing-toggle scope, frontmost-window display selection with ambiguous fail-closed behavior, and one whole selected-display image. |
| IR-084, IR-085, IR-086 | Keep the current one-image/no-detail-tile behavior and hidden `report_screen_observation` protocol; delete physical coordinate click actuation end to end while retaining Accessibility for global PTT. |
| IR-087, IR-088, IR-089 | Keep personal-data grounding and `search_screen_history`; preserve its exact shared maximum-15 payload, internal IDs/scores, and 300 OCR characters per match. |
| IR-090, IR-091 | Repair and keep one local six-section daily recap, generic non-negative `days_ago`, arbitrary periods, the existing per-section formatter, and unbounded Conversation/Task rows. Do not add the rejected seven-day/twenty-row bounds. |
| IR-092 | Keep newest-first recent/date-filtered `get_conversations`, replacing `APIClient.toolGetConversations` and `GET /v1/tools/conversations` with local Transcription GRDB reads and equivalent formatting. |
| IR-093 | Keep semantic `search_conversations`; replace cloud Firestore/Typesense/vector reads with local FTS5 title/overview, transient embedding compute, locally persisted vectors, local similarity/date constraints, and keyword-first merge. Do not downgrade to `LIKE`-only search. |
| IR-094, IR-095 | Keep broad/date-filtered Memory listing and specific semantic Memory search through `MemoryStorage` and its local vector authority. Remove stale backend/auth/latency claims from the canonical tool manifest. |
| IR-096, IR-097 | Keep local overdue/due-today `get_tasks` and local rich `get_action_items` with limit/offset, completion, created-date, and due-date filters. |
| IR-098, IR-099, IR-100, IR-101, IR-102 | Keep model/prompt-authorized local task creation, the implicit local `now + 24h` due date, and keyed local reminder schedule/reconcile/cancel. Delete—not locally recreate—the immediate system “Task Added” banner; spoken confirmation and later reminder remain. |
| IR-103, IR-104, IR-105 | Keep local complete/pending, rename, and reschedule; keep model-owned intent/matching/ambiguity; allow fast `get_tasks` or rich `get_action_items` lookup and fix guidance that incorrectly mandates only `get_tasks`. |
| IR-106, IR-107 | Keep Google Calendar creation absent. Keep native tools only for Screen Recording, Microphone, Notifications, and Accessibility; remove Automation and Full Disk Access from external-surface parsing/claims. |
| IR-108, IR-109, IR-110 | Keep the local kernel journal as sole PTT history authority, typed/PTT continuation in the same selected local Chat, and preconnected provider session. |
| IR-111, IR-112, IR-113 | Delete the four context-plan/cache fields from the usage wire while retaining actual token counts including cached input; keep transport/owner/context replacement and failover; do not alter normal typed Chat's managed-Claude `/v2/chat/completions` path. |
| IR-114, IR-115, IR-116, IR-117, IR-118, IR-119 | Keep deprecated PTT start/end PostHog events absent; preserve product-owned Sentry/PostHog, privacy-bounded lifecycle diagnostics, `QueryTracer` JSONL behavior, two-second terminal banners, and recording/locked/thinking/speaking UI. |
| IR-600 | Preserve Auto, Gemini, and OpenAI selection and the daily Artificial Analysis proxy-model refresh exactly. |
| IR-601, IR-602 | Delete realtime `ask_higher_model`, its unique Claude execution/body, and its `omi_web_search` current-facts claim. Do not delete normal typed Chat or absorb S-22's wider model/public-web work. |
| IR-924 | Preserve live-only, bounded, exactly-once completed managed-Pi context; the rejected `workstream` trigger is already absent and must stay absent. |
| IR-925 | Preserve Notch task-save receipts and conversation-end follow-up cards; task confirmation/undo must use authoritative local task operations. |
| IR-926 | Inject the complete visible notch card (title and message plus provenance) as bounded untrusted context, owner-fenced across account change, without persistence or a synthetic response. |
| IR-932 | Keep the retired UserDefaults voice-outbox importer absent; preserve current kernel-journal persistence and continuity. |

Requirement revalidation is a hard Gate 0, not permission to reopen these decisions. If either authority document changes, stop and reconcile the new reviewed decision before changing production code.

## 5. Dependencies and entry gates

### Gate 0 — baseline, decisions, and complete retained fence

Before implementation:

1. run `make setup` in the implementation worktree and confirm the linked-worktree-safe pre-commit hook is executable;
2. fetch `origin`, rebase/merge only through the repository's current feature-branch process, and record every product delta since `711269ba` without switching the current worktree's branch;
3. re-run the requirements-ledger validator and compare the S-19 brief/detailed decisions;
4. refresh all non-Windows callers of the canonical manifest, `ChatToolExecutor`, PTT controller/session, local stores, three backend conversation routes, realtime usage endpoints, and notification bridges;
5. run the retained PTT characterization suites and `agent-logic-harness.sh` before the first deletion; and
6. stop if the baseline is dirty from unrelated work or if a new caller makes an ownership boundary ambiguous.

### Integrated predecessors consumed

The exact Wave 2 closeout integrates S-05 through S-07 and S-10 through S-16. S-19 consumes, but does not reproduce:

- S-10 `TranscriptionStorage`/`transcription_sessions` and local conversation lifecycle;
- S-12 `MemoryStorage`, `MemorySemanticRecall`, and local Memory vectors;
- S-13 `ActionItemStorage`, `TasksStore`, local task IDs, and `TaskReminderService`;
- S-14 local Focus/Insights data used by recap;
- S-15 local Rewind/OCR vector search; and
- S-16 transient `/v4/listen` behavior and local transcript commit.

If any of those public seams or schemas changed after this plan, affected cycles stop at RED until their current owning contract is documented. No temporary backend compatibility adapter is allowed.

### S-19 execution dependencies

The ordered implementation dependency is:

```text
Gate 0
  -> Cycles 1–2 retained capture/language repair
  -> Cycles 3–4 local Conversation listing and hybrid index
  -> Cycles 5–8 remaining local data/tool authority
  -> Cycle 9 owner-bound completion/notch bridges
  -> Cycles 10–12 rejected tool and realtime-wire deletion
  -> Cycle 13 hosted conversation-tool retirement and full integration closure
```

Cycle 4's local vector lifecycle must be GREEN before Cycle 13 removes hosted semantic routes. All local consumers must be GREEN before the cloud boundary is deleted. The final route deletion never substitutes a fake success or retained empty router.

### Inputs that may block only live acceptance/operations

- Both managed realtime providers, authentication, and appropriate non-production TCC grants must be available to exercise the named bundle. Absence blocks only the associated live acceptance lane, not hermetic implementation/tests.
- Current product-owned Sentry/PostHog configuration must already have been integrated by its owning slice. S-19 preserves it and will stop rather than invent project IDs or credentials.
- Live `users/{uid}/realtime_sessions` document existence and any cloud search resources are unknown from the repository. This does not block repository closure; it blocks only later operational inventory/decommission.

## 6. Current production codeflow

### PTT capture, provider, and persistence flow

```text
global hold / double tap / automation manager probe
  -> PushToTalkManager.startListening / enterLockedListening
  -> VoiceTurnCoordinator binds owner + lifecycle identity
  -> selected microphone capture + one PTT-down screen image
  -> local admission / language identifier / warm-session routing
  -> OpenAI Realtime or Gemini Live (with provider failover)
       -> retained screen/report and local authorized tool calls
     OR backend omni relay
     OR one of three final batch-STT callers
  -> provider output / barge-in reducer
  -> selected local Chat + kernel journal
  -> local TTS/notch states, diagnostics, count-only usage report
```

`PushToTalkManager.startListening` and `enterLockedListening` currently mute output before playing `NSSound(named: "Funk")`; there is no end cue. `continueFinalization` restores output. The three batch call sites in `PushToTalkManager.swift` independently use `AssistantSettings.effectiveTranscriptionLanguage`; only the primary path has a short empty-result English retry. `AssistantSettings.voiceLanguages`/`voiceBaseLanguages` and `PTTLanguageIdentifier.Verdict` are the reviewed PTT authority that these callers currently bypass.

### Tool declaration and execution flow

```text
desktop/macos/agent/src/runtime/omi-tool-manifest.ts
  -> scripts/generate-tool-surfaces.mjs
  -> GeneratedToolCapabilities.swift
  -> GeneratedRealtimeTools.swift
  -> GeneratedToolExecutors.swift
  -> agent/tests/fixtures/tool-manifest.json
  -> realtime provider declarations / Pi capability projection
  -> RealtimeHubController+SessionDelegate authorization
  -> realtimeHub executor or ChatToolExecutor
```

The canonical manifest still advertises `point_click` and `ask_higher_model`. It correctly exposes only four permission types in the tool schemas, but `external-surface-tool-policy.ts` still parses and delegates Automation and Full Disk Access. Conversation and Memory entries still claim `fast network`/authenticated backend preconditions even where execution is or must become local. `update_action_item` voice guidance incorrectly says every ID must come from `get_tasks`.

### Product-data tool flow today

| Tool | Current real authority/path | Current defect or retained state |
|---|---|---|
| `get_conversations` | `ChatToolExecutor.executeBackendTool` -> `APIClient.toolGetConversations` -> `GET /v1/tools/conversations` -> Firestore formatter | Must move to owner-fenced `TranscriptionStorage`; manifest says network/backend; default still asks for transcripts despite voice summary contract. |
| `search_conversations` | Swift -> `POST /v1/tools/conversations/search` -> backend Typesense keyword + hosted vector + Firestore hydration | Must become local FTS5 + local vectors + keyword-first merge. |
| unadvertised `/search-chunks` | `POST /v1/tools/conversations/search-chunks` -> Pinecone transcript chunks + Firestore hydration | No current non-Windows product caller; delete route with the hosted conversation-tool family but preserve shared ingestion/vector primitives for S-24. |
| `get_memories` | `ChatToolExecutor.executeLocalMemoryTool` -> `MemoryStorage.listForTool` | Already local; add owner-suspension behavior coverage and make manifest truthful. |
| `search_memories` | `MemorySemanticRecall.search` -> transient query embedding -> owner-fenced local vector rank | Already local; protect offline/restart/late-result behavior and remove stale manifest claims. |
| `search_screen_history` | realtime alias -> existing local `OCREmbeddingService`/Rewind search | Already local and exact payload retained. |
| `get_daily_recap` | one `RewindDatabase` read lease with six SQL queries | Intended local, but current SQL names retired Wave 2 columns (`category`, `deleted`, `discarded` on conversations and `deleted` on memories); it is not valid against the canonical schema. |
| `get_tasks` | realtime hub -> `TasksStore`/local task authority | Already local and retained. |
| `get_action_items` | misleading `executeBackendTool` branch -> `ActionItemStorage.getFilteredActionItems` | Already local; needs owner-snapshot coverage and truthful naming/guidance. |
| `create_action_item` | `TasksStore.createTask`, local `+24h`, local reminder result | Already local; preserve no immediate system banner. |
| `update_action_item` | `ActionItemStorage` lookup + `TasksStore.toggleTask/updateTask` | Already local; correct lookup guidance and protect reminder reconciliation/owner loss. |

### Rejected and overbroad paths today

- `RealtimeHubController+SessionDelegate.swift`, `RealtimeHubController+Tools.swift`, `RealtimeHubTools.swift`, `Chat/APIClient+HigherModel.swift`, and generated surfaces implement realtime `ask_higher_model`; the body sets `omi_web_search: true`.
- The same controller/manifest/generation chain implements `point_click` with owner-fenced `CGEvent` left-button posts. Accessibility remains separately required by the global shortcut.
- `backend/routers/desktop_realtime.py` writes a SHA-256 token-keyed `users/{uid}/realtime_sessions` document after each mint; no reader was found. Its `UsageReport` accepts four unused context identity/replacement fields, and its trial copy still promises “bring your own keys.”
- `APIClient.reportRealtimeUsage` and `RealtimeHubSession` carry those four fields solely into the report. Local context-plan/cache identities remain important to session correctness and must not be deleted from their local owners.
- Calendar creation, the immediate system Task Added sender, deprecated PTT start/end events, the `workstream` completion trigger, and the UserDefaults voice-outbox importer are already absent from current production source. Their tests are absence ratchets, not invitations to invent a migration cycle.

### Completion and Notch context today

`AgentCompletionVoiceDelivery` already retains bounded exactly-once delivery for live managed-Pi completion context, and its trigger set excludes `workstream`. `NotchMomentsCoordinator` already validates/undoes task receipts through local `ActionItemStorage`/`TasksStore`.

`NotchCardVoiceDelivery.Card` contains only `id` and `text`. `FloatingControlBarManager.presentNotification` passes a context block built from `notification.message` but omits the visible title. The delivery has newest-only pending state, a 50-ID delivered bound, retry on connect/input-window, untrusted framing, and no response request, but it lacks owner identity. `FloatingControlBarManager.resetOwnerProjection`, invoked from `.runtimeOwnerDidChange`, clears other notification projections but not this bridge.

## 7. Complete caller and dependency inventory

This is the implementation inventory to refresh at Gate 0. Paths are current non-Windows paths; `desktop/windows/**` is explicitly nonexistent for this slice's scope.

| Surface | Confirmed owners/callers | Tests/contracts/residue | S-19 action |
|---|---|---|---|
| Shortcut, capture, mute, sounds, batch fallback | `Desktop/Sources/FloatingControlBar/PushToTalkManager.swift`, `VoiceTurnCoordinator.swift`, `SystemAudioMuteController`, `ShortcutSettings`, `AssistantSettings.swift`, `PTTLanguageIdentifier.swift` | PTT state/reducer, silent-turn, language, settings, barge-in suites; manager automation action | Repair only cues/language; protect every adjacent lifecycle. |
| Realtime providers and warm transport | `RealtimeHubController.swift` plus `+SessionLifecycle`, `+TransportReplacement`, `+PushToTalk`, `RealtimeHubSession.swift`, `RealtimeHubSettings`, `RealtimeOmniService.swift` | reconnect/session/admission/provider/tool-result tests, hub harness | Keep OpenAI, Gemini, Auto, switching, relay, failover, replacement. |
| Screen protocol | `RealtimeHubController+ScreenEvidence.swift`, `RealtimeScreenEvidence.swift`, PTT capture, generated `screenshot`/`report_screen_observation` | `ptt-screen-probe.sh`, realtime screen evidence and system-instruction tests | Keep one image and hidden report protocol; no click. |
| Canonical tool source | `agent/src/runtime/omi-tool-manifest.ts`, `external-surface-tool-policy.ts`, `run-tool-capability.ts` | `omi-tool-manifest.test.ts`, policy/capability/cross-surface tests, manifest fixture | Make local metadata/guidance truthful, narrow permission parsing, delete rejected tools, regenerate. |
| Generated Swift/fixture surfaces | `Desktop/Sources/Generated/GeneratedToolCapabilities.swift`, `GeneratedRealtimeTools.swift`, `GeneratedToolExecutors.swift`, `agent/tests/fixtures/tool-manifest.json` | `scripts/generate-tool-surfaces.mjs --check`, `scripts/test-tool-surfaces.sh` | Regenerate; never hand-edit generated files. |
| Swift tool dispatcher | `Desktop/Sources/Providers/ChatToolExecutor.swift`, `RealtimeHubController+SessionDelegate.swift`, `RealtimeHubController+Tools.swift`, `RealtimeHubTools.swift` | `ChatToolExecutorActionItemIDTests`, hub instruction/authorization/tool tests | Introduce narrow local tool services/seams; remove backend-named mixed dispatcher and rejected branches after GREEN. |
| Conversation owner | `Rewind/Core/TranscriptionStorage+LocalAuthority.swift`, `OwnerAuthorizedStorageReads.swift`, `RewindDatabase+ConversationLocalAuthority.swift`, local session/segment schema | S-10 local authority/migration/finalization/repository tests | Add owner-fenced tool list/search/index seams; no second conversation repository. |
| Conversation local semantic index | Does not yet exist; pattern evidence in `MemoryStorage+Semantic.swift`, `MemorySemanticRecall.swift`, `OCREmbeddingService.swift`; transient compute in `EmbeddingService.swift` | New lifecycle, hybrid merge, owner/late-result tests | Add a Transcription-owned FTS5/vector projection tied to content generation; no cloud vector authority. |
| Memory owner | `MemoryStorage`, `MemoryStorage+Semantic.swift`, `MemorySemanticRecall.swift`, `EmbeddingService.swift` | S-12 lifecycle/semantic/owner tests | Consume and protect; no new Memory store or backend read. |
| Rewind owner | `RewindDatabase`, `RewindStorage`, `OCREmbeddingService`, semantic search execution in `ChatToolExecutor` | S-15 Rewind index/search/owner tests | Preserve exact search result contract. |
| Daily recap | `ChatToolExecutor.executeDailyRecap`, shared `omi.db` tables owned by Rewind/Transcription/Tasks/Focus/Memory/Observations | No adequate production behavior suite today | Replace stale ad-hoc schema access with a named owner-fenced local recap read surface and behavioral schema fixtures. |
| Task owner and reminders | `ActionItemStorage`, `TasksStore.swift`, `TaskReminderService.swift`, `NotchMomentsCoordinator.swift` | S-13 owner/reminder/task suites | Consume; correct guidance/naming; protect local list/write/reminder/receipt behavior. |
| Permission tools | generated tool schemas, native permission executor, `agent/src/runtime/external-surface-tool-policy.ts` | external-surface authority and cross-surface tests | Retain four types; delete only Automation/FDA permission claims/delegation. |
| Hosted conversation tools | `backend/routers/tools.py`, `backend/utils/retrieval/tool_services/conversations.py`, `backend/main.py` registration, `database.vector_db.search_transcript_chunks`, `hydrate_chunk_texts` | `test_tools_router.py`, `test_conversation_hybrid_search.py`, `test_conversation_render_factory.py`, S-10/S-13 retirement tests, REST inventory | Delete router/service only after local parity; keep shared primitives with other callers for S-23/S-24. |
| Handwritten Mac conversation client | `Desktop/Sources/Services/APIClient/APIClient+Tools.swift` (`ToolResponse`, `SearchRequest`, two methods) | caller searches and compile | Delete types/methods when no retained caller remains. |
| Route/OpenAPI inventory | `backend/route_policy_legacy_missing_routes.txt`, `backend/scripts/route_policy_inventory.py`, `backend/scripts/generate_swift_openapi_types.py`, `FORK.md` | route-policy check, app-client generator, `test_desktop_rest_inventory.py` | Remove three stale legacy keys/FORK handoff; prove no generated non-Windows operation remains. |
| Realtime usage/session audit | `backend/routers/desktop_realtime.py`, `Desktop/Sources/APIClient.swift`, `RealtimeHubSession.swift`, session-lifecycle construction | `backend/tests/unit/test_desktop_realtime.py`, usage/session Swift tests | Delete audit writer and four wire fields; preserve token math, quota/cost and local cache identities. |
| Higher-model voice path | canonical manifest/generated surfaces, `RealtimeHubController+SessionDelegate`, `+Tools.escalateToHigherModel`, `RealtimeHubTools.escalation*`, `Chat/APIClient+HigherModel.swift` | hub instruction/authorization, run-tool capability, tool manifest fixtures | Delete voice vertical; preserve normal typed Chat `/v2/chat/completions` and S-22 work. |
| Physical click path | canonical/generated surface, controller dispatch, `RealtimeHubController.click`/coordinate parser | barge-in/tool capability tests | Delete voice vertical; protect read-only screen tools and global-shortcut Accessibility. |
| Journal/chat continuity | local agent runtime/kernel journal, `ChatProvider`, `RealtimeTurnPersistence`, selected Chat projections | kernel-turn, chat-timeline, continuity, barge-in suites | Keep exactly; no UserDefaults importer. |
| Completion/notch | `AgentCompletionVoiceDelivery.swift`, `NotchMomentsCoordinator.swift`, `NotchCardVoiceDelivery.swift`, `FloatingControlBarWindow.swift` | corresponding completion/notch/untrusted-context/owner tests | Preserve completion/receipts; add full-card owner fence/reset. |
| Telemetry/UI | `DesktopDiagnosticsManager`, `QueryTracer`, `PostHogManager`, Sentry setup, floating state/window | diagnostics, UI projection/copy, failure banner tests | Preserve; no raw content; deleted tool/audit paths emit no replacement counter. |
| Account delete/export | `backend/services/users/account_deletion.py` and its tests still enumerate shared transcript-chunk Pinecone vectors; no `realtime_sessions` export/reader found | account-deletion storage tests | Do not delete shared vector enumeration before S-24; verify audit collection is neither retained product data nor a new export obligation. |
| External stores/config | hosted Conversation Firestore, Typesense/Pinecone search data, managed provider keys, `users/{uid}/llm_usage`, possible `realtime_sessions` docs | deployment/config and operational inventory only | Repository stops callers/writers. Live inventory/deletion is separate and authorized later. |

No S-19-owned scheduler, Redis namespace, GCS object family, Cloud Task, service, container, workflow, alert, or dedicated secret was found. Shared conversation/vector resources must not be inferred exclusive merely because the PTT route is deleted.

## 8. Behavior classification

| Category | Behavior/surface | Treatment |
|---|---|---|
| KEEP AS IS | PTT hold/locked/custom-disable shortcut; stable-UID mic; output mute; admission/recovery; realtime primary; OpenAI/Gemini/Auto/failover; relay/final batch recovery; barge-in/interrupted history; screen capture/report; Rewind payload; journal/selected Chat; warm replacement; diagnostics/traces/banners/notch states; managed-Pi completion; local Notch receipts | Add characterization where needed, but do not redesign semantics, thresholds, prompt rules, provider models, copy, or lifecycle. |
| ADAPT | start/end cue transition; all three batch language callers; Conversation list/search; Memory tool metadata/owner tests; daily recap; rich task guidance/owner tests; permission policy; complete Notch card owner bridge; realtime usage wire | Move durable authority to canonical local owners and preserve one authorization snapshot. |
| DELETE | `point_click`; voice `ask_higher_model` and `omi_web_search`; three `/v1/tools/conversations*` routes and exclusive service/client; `realtime_sessions` writer; four usage identity fields; PTT/customer BYOK residue and copy; Automation/FDA permission claims; immediate Task Added system banner; Calendar tool; deprecated PTT events; outbox importer | Some are already absent: keep absence through ratchets instead of manufacturing work. |
| SIMPLIFY AFTER | misleading `executeBackendTool` name/mixed dispatcher; stale manifest latency/preconditions; duplicated batch-STT branch policy; exclusive API response/request types/imports; route registration/imports; dead `resolveOmniKey`/managed-key error copy if caller inventory confirms exclusivity | Only after corresponding behavioral GREEN and caller inventory. No compatibility alias. |
| ACCELERATE AFTER | Measure the focused PTT manager/controller/tool test loop and named-bundle launch time after GREEN. Narrow the loop only if the measurement finds a material repeated delay; otherwise `none`. | Record before/after commands and timing without weakening the official component gates. |
| AUTOMATE LAST | Reuse the canonical tool-surface generator/checker and existing manifest lanes. Add automation only for a stable repeated inventory gap backed by a real failure; otherwise `none`. | Register any new stable check in existing local and CI lanes after the behavior and ownership are settled. |
| OUT OF SCOPE / DEFERRED | normal typed Chat and broader public-web/model routes (S-22); fair use (S-20); shell/navigation (S-21); hosted product deletion (S-23); Typesense/Pinecone/GCS/OpenAI Files decommission (S-24); deployments (S-25); Windows; billing/Dodo acceptance (S-18 after Wave 6) | Preserve shared files/primitives and hand off exact remaining residue. |

## 9. Retained behavioral invariants

1. A physical PTT press remains the final user-facing acceptance authority; forced transcript, reducer, controller, and manager probes are supporting lanes, not substitutes.
2. Held and locked capture use the same admission, mute, cue, mic, owner, route, and terminal cleanup rules. An end cue represents leaving real capture; failed admission or unrelated teardown must not accidentally sound like success.
3. Output is restored on normal finalization, cancellation, error, owner change, and reply playback exactly as today. Cue repair must not alter IR-068's default or pause media.
4. All three completed-turn batch callers choose language through one PTT policy: reviewed voice-language list + per-turn verdict, then at most one `multi`/provider auto-detect retry only after an empty language-specific result. No ambient setting and no unbounded retry.
5. Both OpenAI Realtime and Gemini Live remain selectable; Auto's daily Artificial Analysis refresh, same-provider replacement, cross-provider failover, relay, batch recovery, and fallback telemetry retain their exact ownership.
6. A data tool begins with the active tool/turn owner, captures one authorization snapshot, checks it before and after every suspension, and commits/publishes only while current. Same-UID reauthentication generation changes are treated as authorization changes where the current authority does so.
7. Offline local reads work from already-indexed data. Transient embedding failure returns a real bounded error/fallback and never creates phantom vectors or cloud authority. Restart reopens local indexes; owner switch cannot reveal, commit, notify, or speak prior-owner data.
8. `get_conversations` remains newest-first with current date/offset/limit/result formatting. Voice gets titles/summaries; no silent expansion of provider disclosure through default full transcripts.
9. `search_conversations` preserves explicit date constraints, FTS5 exact title/overview matches, local semantic matches, current limits/format, dedupe, and keyword-first merge. A content change invalidates/replaces its local vector; deletion removes all projections; late embeddings are discarded.
10. Memory and Rewind stay owner-local. Memory default-layer/archive visibility, semantic result formatting, and Rewind's max-15/internal-ID/score/300-character result remain unchanged.
11. Daily recap remains six local sections. `days_ago` has only a lower bound; Conversation and Task sections remain unbounded; Apps/Focus/Memories/Observations retain their existing display bounds. The fix must use current canonical schema/state semantics.
12. `get_tasks` stays the cheap overdue/due-today read; `get_action_items` handles future, undated, completed, filtered, or full lists. Model intent and ambiguity remain model-owned, while structural owner/turn/replay fences remain enforced.
13. Task create/update is atomic local product state. Missing due time remains `now + 24h`; due requests schedule/replace/cancel by owner + local ID; persistence failure produces no phantom UI, speech success, receipt, or reminder; no immediate system Task Added banner is added.
14. Screen understanding remains read-only. One fresh whole-display image and one hidden report protocol survive; `point_click` cannot be advertised or invoked.
15. PTT and typed Chat share the selected local conversation and kernel journal. Interrupted output and completion/notch context remain untrusted/provenanced and never synthesize a user turn or response.
16. Agent completion remains live-only, bounded, exactly once, and managed-Pi only. Notch card delivery remains newest-only, max 50 delivered IDs, non-durable, retry-on-capability, no unsolicited announcement, and now owner-bound with full visible title + message.
17. Backend realtime usage keeps non-negative actual text/audio/cached token accounting, cost/quota semantics, auth, paywall response class, and no raw content. Deleting the four fields does not delete local context planning or cache correctness.
18. Sentry/PostHog/QueryTracer/lifecycle diagnostics remain privacy-bounded. No raw transcript, Memory, task, OCR, screenshot, tool result, provider token, or local identifier is added to remote telemetry.
19. Removed routes are genuine 404s. Removed tools are absent from canonical, generated, provider, executor, policy, fixture, and documentation surfaces. No deprecated alias, fake-success response, ignored field, empty router, or compatibility shell remains.
20. `/v4/listen`, normal typed `/v2/chat/completions`, managed provider environment credentials, account deletion's shared vector cleanup, and all Windows surfaces are untouched.

## 10. Target authority, result ownership, and service-topology model

| Concern | Authoritative owner after S-19 | Allowed compute/transport | Durable result and publication |
|---|---|---|---|
| Voice turn identity/lifecycle | `VoiceTurnCoordinator` + current `RuntimeOwnerAuthorizationSnapshot` | selected realtime provider, relay, or batch STT | selected local Chat/kernel journal after current-owner validation |
| Conversation list/detail | `TranscriptionStorage` over owner-scoped `omi.db` | none | local summaries formatted by the tool adapter |
| Conversation keyword index | Transcription-owned GRDB FTS5 projection | none | same owner DB; content-generation-coupled |
| Conversation semantic index | Transcription-owned local vector projection | authenticated transient `EmbeddingService` only | vector + source generation in owner DB; similarity local |
| Memory list/search | `MemoryStorage` and its existing semantic projection | transient query embedding only | existing local Memory rows/vectors |
| Rewind search | `RewindStorage`/`OCREmbeddingService` | existing transient embedding compute where already reviewed | local Rewind rows/vectors |
| Daily recap | a named owner-fenced local recap read surface over current canonical tables | none | no new persistence; formatted result returned to active turn |
| Tasks and reminders | `ActionItemStorage`/`TasksStore`; `TaskReminderService` is a projection | none for durable task state; macOS notification scheduler for delivery | local task row first, then keyed local reminder and UI invalidation |
| Permission state | native macOS permission executor | System Settings/native prompts | no product cloud persistence |
| Agent/notch context | kernel run ledger and current visible local notification | realtime session injection | bounded in-memory delivery/checkpoint only; no new store |
| Usage/quota | backend `users/{uid}/llm_usage/{date}` count/cost ledger | authenticated `/v2/realtime/usage` | count-only increments; no context identity fields |
| Realtime credentials | managed backend mint using service-owned provider keys | OpenAI/Gemini mint endpoints | ephemeral token returned; no `realtime_sessions` product/audit document |

The required ownership sequence for any local semantic tool is:

```text
capture authorization snapshot + source generation
  -> read authoritative local source under read lease
  -> transiently compute query/source embedding if needed
  -> revalidate snapshot + source generation
  -> commit local vector/index under commit lease (source indexing only)
  -> revalidate snapshot
  -> rank/format bounded local result
  -> revalidate active turn before provider continuation/publication
```

Compute failures do not mutate product state. A late result for an old owner or content generation is discarded, not rehomed. There is no backend Conversation/Memory/Task write, sync status, reconciliation flag, or server fallback.

Target service topology is deliberately smaller:

```text
Mac local owners <-> transient authenticated compute routes / realtime transport
                  -> count-only realtime usage ledger

No Mac PTT call -> /v1/tools/conversations*
No mint -> users/{uid}/realtime_sessions
No voice tool -> physical click or higher-model/web escalation
```

## 11. Ordered TDD cycles

There are **13 planned TDD cycles**. Gate 0 is an entry gate, not a cycle. Each RED must execute production behavior through an injected store/transport/device seam; source scans below are supplementary static tripwires.

### Cycle 1 — Make PTT capture cues truthful and audible (IR-063–070)

- **Behavioral RED:** drive the real held and locked transition policy with injected sound/mute adapters. Assert an enabled start cue occurs before output mute, one end cue occurs after restore when real capture ends, disabled sounds emit neither cue, and admission failure/cancel/error use explicitly named terminal semantics. It fails because production mutes before the only start `Funk` cue and has no end cue.
- **Minimum GREEN:** extract only the capture audio-transition seam needed to inject `NSSound`/`SystemAudioMuteController`; order start cue then mute, restore then end cue for the reviewed terminal states, and route held/locked cleanup through it without changing the reducer.
- **Protected behavior:** shortcut admission, locked mode, output-mute default/restoration, interruption, diagnostics, silent-turn recovery, and terminal banners.
- **Authority before/after:** `PushToTalkManager`/`VoiceTurnCoordinator` before and after; no new persistence or service.
- **Expected changes:** `PushToTalkManager.swift`, a narrowly named local transition helper if needed, focused Swift behavior tests; Settings copy changes only if the implementation proves current copy inaccurate (expected none).
- **Focused verification:** `xcrun swift test --package-path Desktop --filter 'PTTCaptureCueLifecycleTests|PushToTalkStateMachineTests|PTTSilentTurnRecoveryWiringTests|VoiceTurnReducerTests'` from `desktop/macos`.
- **Deletion/simplification enabled:** remove duplicated direct `NSSound` construction only after both modes use the tested seam.
- **Stop:** if AppKit sound completion cannot provide deterministic ordering, keep the public behavior and use an injected fire-and-forget event contract; do not add sleeps or change mute semantics.

### Cycle 2 — Unify final batch language selection and bounded retry (IR-055, IR-059–061, IR-071–072)

- **Behavioral RED:** run each of the primary batch, warm-hub-timeout, and failed-relay production callers against a recording transcriber. Assert first language comes from `voiceLanguages` plus the turn's `PTTLanguageIdentifier.Verdict`, an empty language-specific result produces exactly one `multi` attempt, success/no-specific-verdict produces no retry, owner/turn loss cancels publication, and ambient transcription settings cannot affect calls. It fails because all callers read `effectiveTranscriptionLanguage`, only one retries, and that retry forces English.
- **Minimum GREEN:** add one bounded `PTTBatchTranscriptionPolicy`/executor used by all three call sites; pass the already captured turn audio, voice candidates, local verdict, context keywords, owner/turn identity, and existing fallback-reason telemetry.
- **Protected behavior:** actual provider/model reporting, batch recovery, silence gates, relay/warm fallback reasons, at-most-one completion claim, both realtime providers, and local language transcript correction.
- **Authority before/after:** ambient `AssistantSettings.effectiveTranscriptionLanguage` accidentally owns batch selection before; reviewed `voiceLanguages`/per-turn verdict owns it after. `VoiceTurnCoordinator` remains completion authority.
- **Expected changes:** `PushToTalkManager.swift`, `PTTLanguageIdentifier.swift` only if a public verdict seam is required, a small policy source/test, relevant language/fallback tests; no backend schema change.
- **Focused verification:** Swift filters `PTTBatchLanguagePolicyTests|AssistantSettingsLanguageTests|RealtimeHubReconnectContractTests|RealtimeHubBargeInContinuityTests` plus manager raw-PCM automation in section 15.
- **Deletion/simplification enabled:** delete the English short-turn special case and three route-specific language branches.
- **Stop:** if a provider's verified batch API does not use `multi` as auto-detect, stop and capture its current accepted wire value from `TranscriptionService`/backend contract; do not invent one.

### Cycle 3 — Move recent/date-filtered Conversation listing to `TranscriptionStorage` (IR-087, IR-092)

- **Behavioral RED:** seed owner A/B local conversations and segments, execute the real `get_conversations` tool adapter with recency/date/offset/limit inputs and backend transport forced to fail, then assert newest-first owner-A title/summary output, correct date bounds/pagination, no default transcript disclosure, restart parity, and late owner-switch rejection. It fails because production calls `APIClient.toolGetConversations`.
- **Minimum GREEN:** add an owner-authorized `TranscriptionStorage` tool-list read/formatter with the current accepted maximum and explicit summary projection; route `ChatToolExecutor` to it using the captured snapshot.
- **Protected behavior:** list versus semantic-search distinction, current input validation/defaults, titles/summaries and ordering, active-turn continuation, local Conversation UI/finalization.
- **Authority before/after:** Firestore/backend formatter before; owner-scoped `TranscriptionStorage` GRDB after.
- **Expected changes:** `TranscriptionStorage+LocalAuthority.swift`, `OwnerAuthorizedStorageReads.swift`, a narrow Conversation tool adapter in the Providers/Rewind owner boundary, `ChatToolExecutor.swift`, canonical manifest metadata/schema if transcript input is retired, and Swift tests.
- **Focused verification:** filters `PTTLocalConversationToolTests|ConversationRepositoryTests|ConversationLocalAuthorityMigrationTests|ConversationLocalFinalizationTests`.
- **Deletion/simplification enabled:** marks `APIClient.toolGetConversations` and its `ToolResponse` portion deletable after Cycle 4/13 confirms no other caller.
- **Stop:** if current route formatting includes a field absent from canonical local rows, stop and classify it: derive only from retained local data or explicitly record a requirements conflict; never restore a cloud copy.

### Cycle 4 — Establish local hybrid Conversation topic search (IR-053, IR-087, IR-093)

- **Behavioral RED:** through the real tool adapter and a controllable embedding seam, prove exact acronym/name keyword hits precede semantic-only hits, duplicates collapse, date/limit constraints match the current contract, title/overview edits replace projections, deletion removes them, restart preserves vectors, offline indexed search works, compute/persistence failure creates no phantom result, and an owner/content-generation change rejects a late embedding. It fails because local Conversation storage has only a bounded `LIKE` search and no FTS5/vector lifecycle; production calls the cloud hybrid route.
- **Minimum GREEN:** add Transcription-owned FTS5 title/overview projection and local vector table with source content generation; use retained transient `EmbeddingService` to produce embeddings, compare locally, and implement the existing keyword-first merge/result formatter under one owner snapshot.
- **Protected behavior:** semantic—not keyword-only—topic recall, exact keyword priority, local Conversation lifecycle, no raw transcript expansion, and transient-compute-only backend boundary.
- **Authority before/after:** Typesense + hosted vector + Firestore before; owner-scoped Transcription GRDB/FTS/vector after.
- **Expected changes:** Rewind/Transcription schema migration and lifecycle files, a `ConversationSemanticRecall`-style owner service, `ChatToolExecutor`, focused schema/index/hybrid tests, and architecture docs if the package guard requires them. No hosted vector primitive deletion.
- **Focused verification:** filters `ConversationSemanticRecallTests|PTTLocalConversationToolTests|ConversationLocalAuthorityMigrationTests|Wave2OwnerPublicationFenceTests`; force embedding transport offline after index creation and reopen the DB in the test.
- **Deletion/simplification enabled:** `APIClient.toolSearchConversations`, `SearchRequest`, and hosted PTT search caller become deletable; the old local `LIKE` helper is removed or retained only if a verified non-PTT caller owns it—never as a second semantic implementation.
- **Stop:** if the current canonical Conversation row has no stable content generation/deletion event usable by the index, stop and add that compiler-visible owner seam in this cycle before indexing; do not poll or scrape source text.

### Cycle 5 — Make retained Memory and Rewind voice grounding explicitly local (IR-087–089, IR-094–095)

- **Behavioral RED:** execute real `get_memories`, `search_memories`, and realtime `search_screen_history` projections with backend product-data reads disabled. Assert owner isolation, Memory date/pagination/default-layer behavior, semantic restart/offline behavior, late query rejection, and exact Rewind max-15/internal-ID/score/300-character output. The data paths largely pass today, while the canonical manifest contract fails because it labels Memory as backend/network and lacks a cross-surface local-authority proof.
- **Minimum GREEN:** pass the authorization snapshot explicitly through Memory tool reads/search where current TaskLocal checks are insufficient; update canonical manifest latency/preconditions/descriptions; add one behavior-level cross-surface test that executes the production Swift owner rather than only inspecting strings.
- **Protected behavior:** existing Memory policy markers/format, local vector rank, Rewind shared payload, provider continuation, no raw provenance expansion.
- **Authority before/after:** local owners before and after; the change makes the contract truthful and closes suspension gaps rather than introducing a new store.
- **Expected changes:** `ChatToolExecutor.swift`, `MemorySemanticRecall.swift`/owner wrappers only if required, canonical manifest/generated outputs, Memory/Rewind tool behavior tests and tool-surface tests.
- **Focused verification:** filters `PTTLocalMemoryToolTests|LocalMemoryLifecycleRunnerTests|Wave2OwnerPublicationFenceTests|RealtimeScreenEvidenceTests`, then `scripts/test-tool-surfaces.sh`.
- **Deletion/simplification enabled:** remove stale “authenticated backend” and “fast network” claims; do not delete `EmbeddingService` or Rewind result fields.
- **Stop:** if an owner-snapshot API is missing, add it to the canonical storage owner; do not wrap an unfenced read in a second tool-specific cache.

### Cycle 6 — Repair daily recap against canonical local schemas (IR-087, IR-090–091)

- **Behavioral RED:** seed current Wave 2 tables through owning production stores, execute `get_daily_recap` for 0, 1, 30, and a larger period, and assert all six sections, local-time bounds, Apps first-20, Focus/Memories first-10, Observations first-20, and *all* matching Conversation/Task rows. Assert owner switch during the read publishes nothing. It fails because current SQL references retired Conversation/Memory columns.
- **Minimum GREEN:** introduce one named owner-fenced local recap read model over current canonical tables, preserving the six queries/formatter and intentional unbounded sections; route `executeDailyRecap` through it rather than embedding stale schema in the provider executor.
- **Protected behavior:** arbitrary period, lower-bound-only clamp, exact section composition/bounds/copy, no backend summarizer or recap persistence.
- **Authority before/after:** intended shared local `omi.db` before but with stale direct SQL; explicit owner-scoped recap read owner after.
- **Expected changes:** `ChatToolExecutor.swift`, a package-appropriate local recap reader beside the database owner, current-schema behavior tests, and architecture docs if package boundaries change.
- **Focused verification:** filters `DailyRecapLocalAuthorityTests|TasksStoreOwnerBoundaryTests|ConversationLocalAuthorityMigrationTests|LocalMemoryLifecycleRunnerTests`.
- **Deletion/simplification enabled:** delete the six ad-hoc SQL blocks from `ChatToolExecutor` after parity; no row bounds may be added as “optimization.”
- **Stop:** if tables cannot share an owner-scoped read transaction, use their public read seams under the same captured snapshot and document snapshot consistency; do not bypass owner authorization to recover one transaction.

### Cycle 7 — Close the local Task voice contract (IR-096–105, IR-925 task receipt)

- **Behavioral RED:** execute real task tools through the authorized dispatcher against owner-local storage: fast overdue/today read; rich future/undated/completed/date filters; create with explicit and implicit `+24h` due; update complete/pending/name/due; reminder schedule/replace/cancel; failure/no-phantom publication; account switch; Notch receipt validation/undo. Add a provider-guidance contract allowing either read. It fails at least on inherited `update_action_item` guidance that mandates `get_tasks`; existing local mechanics become the adjacent passing fence.
- **Minimum GREEN:** make all tool reads use explicit owner-authorized storage APIs, correct canonical guidance to choose `get_tasks` or `get_action_items`, rename/split `executeBackendTool` after Conversation migration, and keep Notch receipt operations on the local ID/store.
- **Protected behavior:** model-owned intent/ambiguity, replay/allowlist/input fences, spoken confirmation, immediate local list update, +24h default, due reminder lifecycle, no immediate system Task Added banner.
- **Authority before/after:** local ActionItem/Tasks authority before and after; remove misleading backend semantics and any suspension gap.
- **Expected changes:** canonical manifest/generated output, `ChatToolExecutor.swift`, owner read wrappers if needed, Task/Reminder/Notch behavior tests; no backend Task route work.
- **Focused verification:** filters `PTTLocalTaskToolTests|ChatToolExecutorActionItemIDTests|TasksStoreOwnerBoundaryTests|TaskReminderServiceTests|NotchMomentsCoordinatorTests` and tool-surface tests.
- **Deletion/simplification enabled:** remove backend-named dispatcher residue, backend-refresh language, and any dead customer/server confirmation wording. Preserve the PostHog event named `Task Added`; it is analytics, not the rejected immediate system notification.
- **Stop:** if task persistence succeeds but reminder scheduling fails, return the current truthful reminder warning and keep the task; do not roll back durable state or claim full success silently.

### Cycle 8 — Narrow native permission tools to the four retained grants (IR-052, IR-086–087, IR-107)

- **Behavioral RED:** send direct and delegated permission requests through `routeExternalSurfaceTool`. Assert exactly Screen Recording, Microphone, Notifications, and Accessibility normalize/authorize; Automation and Full Disk Access reject as unsupported; generic/multi-permission, cross-app target, and missing current-turn consent still fail closed. It fails because external-surface policy still recognizes and can delegate the two rejected types.
- **Minimum GREEN:** delete the two entries/phrases/subjects from `external-surface-tool-policy.ts` and update behavior tests/fixtures without changing native permission executors for the four retained grants.
- **Protected behavior:** direct native route, explicit current-turn consent, single-permission affirmation, screen-share alias, Omi-only target, Accessibility used by global PTT.
- **Authority before/after:** native permission executor before and after; the agent policy loses only rejected vocabulary/routes.
- **Expected changes:** policy TypeScript and external-surface/cross-surface tests; generated schema should remain four-type and regenerate unchanged.
- **Focused verification:** targeted agent tests for `external-surface-authority` and `cross-surface-contract-smoke`, then `scripts/test-tool-surfaces.sh`.
- **Deletion/simplification enabled:** remove obsolete rejected phrases/subjects; do not delete desktop automation test capabilities or Accessibility APIs merely because their names contain “automation.”
- **Stop:** if a matching string belongs to non-production automation infrastructure rather than a macOS permission claim, preserve it and classify it; no broad word deletion.

### Cycle 9 — Owner-bind complete Notch context while preserving completion/receipts (IR-924–926)

- **Behavioral RED:** show a title-only, message-only, and title+message card for owner A, then exercise live delivery, refused-send retry, connect/input-window retry, newest-only replacement, 50-ID bound, duplicate suppression, mid-flight owner switch, and `FloatingControlBarManager.resetOwnerProjection`. Assert injected untrusted context exactly represents the visible title + message/provenance, owner B receives none, no persistence occurs, and no response is requested. It fails because `Card` has no owner and the handoff omits title.
- **Minimum GREEN:** make the shared notification-context renderer accept visible title and message; store authorization snapshot/owner in `NotchCardVoiceDelivery.Card`; revalidate before/after injection; clear pending/in-flight/delivered owner state from the existing `.runtimeOwnerDidChange` projection reset. Preserve `AgentCompletionVoiceDelivery` unchanged except test integration.
- **Protected behavior:** completion live-only/bounded/exactly-once/checkpoint-after-success; no `workstream`; local Notch task receipt/undo; newest-only card, max 50, no unsolicited response, untrusted framing.
- **Authority before/after:** unowned in-memory card before; owner-bound current notification projection after. Kernel remains completion authority; local Task store remains receipt authority.
- **Expected changes:** `NotchCardVoiceDelivery.swift`, `FloatingControlBarWindow.swift`, focused Notch/untrusted/owner tests; `AgentCompletionVoiceDelivery.swift` only if a shared reset hook is demonstrably necessary.
- **Focused verification:** filters `NotchCardVoiceDeliveryTests|UntrustedNotificationContextTests|AgentCompletionVoiceDeliveryTests|ProactiveNotificationContinuityTests|NotchMomentsCoordinatorTests`.
- **Deletion/simplification enabled:** consolidate typed/spoken card rendering into one tested formatter; remove message-only handoff.
- **Stop:** if title or owner is not available at the already-authorized `presentNotification` boundary, stop and extend `FloatingBarNotification` at its owner, not by looking up global current state later.

### Cycle 10 — Delete realtime physical click vertically (IR-076, IR-085–086)

- **Behavioral RED:** canonical tool projection/provider contract must omit `point_click`, and an injected/provider attempt must fail as unknown/not allowed without posting a `CGEvent`; `screenshot` + `report_screen_observation` must still complete. It fails because the tool is declared, generated, dispatched, and physically executable.
- **Minimum GREEN:** delete the canonical manifest entry/voice schema, regenerate, delete executor dispatch/coordinate parser/CGEvent helper and exclusive tests/imports, and update provider instructions/fixtures.
- **Protected behavior:** read-only current-screen capture/report, permission behavior, owner tool fence, Accessibility-backed shortcut, barge-in and provider continuation.
- **Authority before/after:** realtime model can actuate owner-fenced physical click before; no physical click capability exists after.
- **Expected changes:** canonical/generated tool surfaces, `RealtimeHubController+SessionDelegate.swift`, `RealtimeHubController+Tools.swift`, tests/fixture; remove `CoreGraphics` import only if caller inventory proves exclusive.
- **Focused verification:** tool-surface tests plus Swift filters `HubSystemInstructionTests|RealtimeScreenEvidenceTests|RealtimeHubBargeInContinuityTests|AuthorizedToolOwnerBoundAuthTests`.
- **Deletion/simplification enabled:** remove finite-coordinate and physical-effect helpers if no retained caller; do not remove generic owner-bound physical-effect infrastructure owned elsewhere.
- **Stop:** any retained non-voice caller of a shared helper must be split/protected before deletion; do not hide the tool behind an unadvertised alias.

### Cycle 11 — Delete realtime higher-model/live-web escalation vertically (IR-113, IR-601–602)

- **Behavioral RED:** realtime provider manifest and runtime capability must omit `ask_higher_model`; a proposed call must fail not-allowed/unknown; ordinary typed Chat through `/v2/chat/completions` must still succeed in its hermetic transport test. It fails because the voice tool, dispatcher, body, `omi_web_search`, and API helper remain.
- **Minimum GREEN:** delete the canonical/generated tool entry, session dispatch, `escalateToHigherModel`, `RealtimeHubTools.escalationSystemPrompt/escalationBody`, and `Chat/APIClient+HigherModel.swift` if caller inventory remains exclusive; update fixtures/tests/instructions.
- **Protected behavior:** direct realtime answers, local grounding tools, normal typed managed-Claude Chat, both realtime providers, and S-22-owned model/public-web routes.
- **Authority before/after:** voice model could call a second managed Claude/web path before; active realtime model answers with retained tools after. Typed Chat authority is unchanged.
- **Expected changes:** manifest/generated output, three realtime Swift files, exclusive API helper, agent/Swift tests and current architecture docs that advertise the voice tool.
- **Focused verification:** tool-surface tests; Swift filters `HubSystemInstructionTests|RealtimeHubBargeInContinuityTests|DesktopCoordinatorServiceTests`; typed Chat backend/client focused tests.
- **Deletion/simplification enabled:** remove voice-only context-cache body assembly and live-web claim. Do not remove `/v2/chat/completions`, Claude adapters, generic `omi_web_search` owned by S-22, or failure-class lifecycle records here.
- **Stop:** if `APIClient.askHigherModel` gains a retained non-voice caller, keep/split that client helper but still remove the voice declaration/dispatch; record the S-22 handoff.

### Cycle 12 — Minimize the managed realtime credential/usage wire (IR-056–058, IR-062, IR-111)

- **Behavioral RED:** mint OpenAI/Gemini through stubbed upstreams and assert no Firestore session-audit write occurs; report usage with actual/cached counts and assert unchanged cost/quota increments; send any of the four retired fields and assert schema rejection rather than silent ignore; assert trial/error copy offers managed recovery, not customer keys. Swift wire serialization must contain only provider/model and token counts. It fails because mint persists `realtime_sessions`, schemas accept four fields, Swift sends them, and copy promises BYOK.
- **Minimum GREEN:** delete `_record_session`/`_persist_session`, `hashlib`/exclusive DB executor imports, and both calls; remove four Pydantic/Swift report parameters/body keys and session pass-through; make the narrowed Pydantic request model reject unknown fields so old keys are not silently ignored; remove dead `resolveOmniKey`/provider-key user guidance after caller proof; update managed trial copy without changing status/reason semantics.
- **Protected behavior:** provider-owned service credentials, authenticated ephemeral mint, both provider models, expiry behavior, token/cached-token math, llm_usage cost/quota/call count, error/fallback telemetry, local context cache correctness.
- **Authority before/after:** Firestore audit + usage ledger before; count-only `llm_usage` authority after. Local context hashes remain in local session planning but leave the backend wire.
- **Expected changes:** `backend/routers/desktop_realtime.py`, `test_desktop_realtime.py`, `APIClient.swift`, `RealtimeHubSession.swift`, construction/call sites/tests, and current user-facing docs/copy; no deployment secret deletion.
- **Focused verification:** backend focused runner for `test_desktop_realtime.py`; Swift filters `RealtimeHubSessionInputLifecycleTests|RealtimeHubReconnectContractTests|HubAuthTests` (using current actual suite names at Gate 0); inspect encoded request body behaviorally.
- **Deletion/simplification enabled:** no token hash/audit writer, no ignored fields, no customer-key seam; preserve `OPENAI_API_KEY`/`GEMINI_API_KEY` as backend-managed config.
- **Stop:** if a real audit reader, compliance control, or account lifecycle caller appears at Gate 0, stop Cycle 12 and obtain an updated reviewed decision; do not strand a read path or silently erase required records.

### Cycle 13 — Retire the hosted Conversation-tool boundary and prove complete PTT closure (all assigned decisions)

- **Behavioral RED:** backend TestClient proves all three `/v1/tools/conversations`, `/search`, and `/search-chunks` routes still exist; non-Windows caller inventory finds the handwritten API methods and hosted formatter; full canonical tool contract still fails if any rejected/account/provider claim remains. Adjacent tests protect generic Conversation APIs/vector/account deletion, `/v4/listen`, typed Chat, both providers, journal, screen protocol, completion/notch, telemetry, and UI.
- **Minimum GREEN:** after Cycles 3–7 are GREEN, delete `backend/routers/tools.py`, unregister/import it from `backend/main.py`, delete `utils/retrieval/tool_services/conversations.py` only after its full non-Windows caller inventory is empty, delete `APIClient+Tools.swift` if its types are exclusive, update route legacy baseline/REST inventories/FORK handoff and focused tests, regenerate/check contracts, and remove only now-dead imports. Add genuine 404/fail-closed route tests. Keep absence ratchets for Calendar, immediate banner, deprecated events, `workstream`, and UserDefaults importer.
- **Protected behavior:** local list/hybrid search, generic hosted Conversation routes still owned elsewhere, transcript-chunk ingestion/account deletion until S-24, `/v4/listen`, typed Chat, complete PTT lifecycle, both providers, usage, local journal, diagnostics, and visuals.
- **Authority before/after:** hosted PTT Conversation router before; local Transcription/Memory/Rewind/Task owners plus transient compute after. No empty backend tool service remains.
- **Expected changes:** backend router registration/service/tests/route baseline, handwritten Mac client, `FORK.md`, canonical/generated surfaces and current docs, new S-19 closure tests; shared database/vector modules only for demonstrably exclusive symbols.
- **Focused verification:** new `test_s19_ptt_tool_retirement.py`, affected existing backend tests through `backend/test.sh`, local Swift S-19 suites, tool-surface harness, route/OpenAPI checks, exact residue scans, manager/controller/natural PTT lanes.
- **Deletion/simplification enabled:** final dead DTOs/imports/names/copy and exclusive hosted formatter disappear. Remaining Typesense/Pinecone/Firestore data owners are explicitly handed to S-23/S-24.
- **Stop:** do not delete any shared `vector_db`, transcript hydration, account-deletion, conversation API, deployment, index, secret, or storage resource with a retained caller. If the route is present in a released generated non-Windows contract at Gate 0, stop and resolve the current unreleased-fork compatibility evidence rather than ship a fake route.

## 12. Cross-slice ownership and handoffs

| Slice | S-19 owns/consumes | Boundary and handoff |
|---|---|---|
| S-05/S-07 | Consume retained provider/fallback and managed-only access | Preserve both providers and current auth. Delete only remaining PTT BYOK residue; do not redo subscription/auth work. |
| S-09 | Consume product-owned telemetry configuration | Preserve Sentry/PostHog and privacy-bounded diagnostics. Any unresolved project identity returns to S-09/operations; S-19 does not invent it. |
| S-10 | Consume `TranscriptionStorage` local authority/schema | Add tool read/index projections through its public owner. Do not reintroduce backend Conversation sync. |
| S-12 | Consume Memory local/vector authority | Contract-test and describe it truthfully; no duplicate Memory index. |
| S-13 | Consume Tasks/Goals/reminder local authority | Correct voice guidance/owner use; no task schema/cloud migration. |
| S-14/S-15 | Consume local Focus/Insight/Rewind data | Repair recap and preserve Rewind result contract; no new cloud copy. |
| S-16 | Consume transient listen/batch STT and local transcript authority | Change only PTT batch language policy; `/v4/listen` and ambient STT remain out of scope. |
| S-20 | No implementation dependency for S-19 | Preserve count-only `/v2/realtime/usage` semantics. Do not absorb fair-use classifier/strikes/allowance. |
| S-21 | S-19 supplies final reachable PTT/tool shell | S-21 may later remove unreachable shell residue; S-19 does not redesign navigation/settings. |
| S-22 | Shared files: canonical tool/model descriptions, realtime controller/session, backend `/v2/chat/completions`, provider settings | **S-19 owns** local voice tool surface, voice `ask_higher_model` deletion, PTT data authority, both provider preservation. **S-22 owns** broader managed model portfolio, normal Chat/public-web behavior, model routes/adapters. Gate 0 refresh and small commits reduce conflicts; neither slice deletes a retained provider. |
| S-23 | S-19 deletes only PTT route callers | Hosted Conversation/Memory/Task products and Firestore families remain S-23-owned until its predecessors integrate. |
| S-24 | Consumes S-19 local Conversation/Memory search authority | S-19 must leave a precise list of remaining Typesense/Pinecone/transcript-chunk symbols/resources. S-24, after S-23, owns infrastructure deletion. |
| S-25 | none | No service/job/deployment/image/workflow deletion is authorized here. |
| S-18/Dodo | none during Wave 3 | `BILLING_MODE=disabled`; no Dodo transaction, entitlement, onboarding paywall, or Stripe restoration. Final acceptance stays post-Wave-6. |
| Windows | none | Never inspect, modify, generate, repair, test, or clean `desktop/windows/**` or Windows-only surfaces. |

Shared-file rule: before editing `omi-tool-manifest.ts`, generated tool files, `RealtimeHubController*`, `RealtimeHubSession.swift`, `APIClient.swift`, `backend/main.py`, or model-route tests, compare current integrated S-20/S-22 work. If overlapping ownership changed, rebase and preserve their behavior; do not take the file's existence as ownership of every symbol.

## 13. Repository residue-search strategy

Run after the corresponding GREEN and again at final closure. All searches deliberately exclude Windows and historical decision/planning documents. A no-match exit is expected only where stated; any match is classified by a human as retained, shared handoff, test ratchet, or defect.

```bash
# Hosted PTT Conversation boundary: expected no production/client/current-doc matches.
rg -n 'v1/tools/conversations|toolGetConversations|toolSearchConversations|get_conversations_text|search_conversations_text' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests desktop/macos/agent backend FORK.md \
  --glob '!desktop/windows/**'

# Rejected realtime tools and their exact executors/claims: expected only explicit absence tests if retained.
rg -n 'ask_higher_model|escalateToHigherModel|escalationSystemPrompt|omi_web_search|point_click' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests desktop/macos/agent \
  --glob '!desktop/windows/**'

# Retired permission claims. Do not confuse local dev automation infrastructure with a permission type.
rg -n 'full_disk_access|full disk access|automation permission|automation access' \
  desktop/macos/agent/src/runtime/external-surface-tool-policy.ts \
  desktop/macos/agent/tests desktop/macos/Desktop/Sources/Generated

# Audit collection/writer and unused usage-wire fields: expected no live code/schema/body matches.
rg -n 'realtime_sessions|context_plan_id|stable_cache_identity|dynamic_context_identity|context_cache_replaced' \
  backend desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests \
  --glob '!desktop/windows/**'

# Customer-key product residue; managed backend environment keys are an explicit allowed class.
rg -n 'bring your own keys|BYOK|resolveOmniKey|customer.*api key|user.*api key' \
  backend desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests desktop/macos/agent \
  --glob '!desktop/windows/**'

# Already-absent rejected/deprecated behavior: expected absence tests or unrelated retained domain terms only.
rg -n 'create_calendar_event|send_action_item_created_notification|floating_bar_ptt_started|floating_bar_ptt_ended|realtime.*outbox|voice.*outbox' \
  backend desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests desktop/macos/agent \
  --glob '!desktop/windows/**'

# Truthfulness check for retained local tools: inspect every remaining network/backend claim.
rg -n 'get_conversations|search_conversations|get_memories|search_memories|get_action_items|create_action_item|update_action_item' \
  desktop/macos/agent/src/runtime/omi-tool-manifest.ts desktop/macos/Desktop/Sources/Generated \
  desktop/macos/Desktop/Sources/Providers desktop/macos/Desktop/Sources/Services/APIClient

# Shared hosted infrastructure handoff: matches are expected and must be enumerated, not deleted here.
rg -n 'Typesense|typesense|Pinecone|pinecone|search_transcript_chunks|transcript_chunk_vectors' \
  backend desktop/macos --glob '!desktop/windows/**'
```

Also use `rg -l` followed by targeted symbol search before deleting a shared file. Generated outputs are checked through their generator rather than declared clean by search alone. Static absence checks are labelled **static tripwires** and never replace the behavioral route/tool tests in Cycles 8–13.

## 14. Focused and component-level verification commands

These are future implementation commands. They were grounded in the current runner scripts; they have not been run as product validation while writing this plan.

### Focused Swift and agent tests

```bash
cd desktop/macos
xcrun swift test --package-path Desktop --filter 'PTTCaptureCueLifecycleTests|PTTBatchLanguagePolicyTests|PTTLocalConversationToolTests|ConversationSemanticRecallTests|PTTLocalMemoryToolTests|DailyRecapLocalAuthorityTests|PTTLocalTaskToolTests'
xcrun swift test --package-path Desktop --filter 'NotchCardVoiceDeliveryTests|UntrustedNotificationContextTests|AgentCompletionVoiceDeliveryTests|RealtimeHubBargeInContinuityTests|RealtimeHubReconnectContractTests|RealtimeScreenEvidenceTests|HubSystemInstructionTests'
./scripts/test-tool-surfaces.sh
./scripts/agent-logic-harness.sh
./scripts/agent-logic-harness.sh --cross-surface-smoke
```

The `S19...`/local-authority suite names above are planned test classes to add in the corresponding cycles. At Gate 0, use the exact final class names selected by the implementation and keep the command synchronized with them.

### Focused backend tests through the official runner

```bash
cd backend
printf '%s\n' \
  tests/unit/test_desktop_realtime.py \
  tests/unit/test_s19_ptt_tool_retirement.py \
  tests/unit/test_desktop_rest_inventory.py \
  tests/unit/test_s10_conversation_surface_retirement.py \
  tests/unit/test_s13_task_goal_surface_retirement.py \
  tests/unit/test_conversation_hybrid_search.py \
  tests/services/users/test_account_deletion.py \
  > /tmp/omi-s19-backend-tests.txt
BACKEND_UNIT_TEST_FILE_LIST=/tmp/omi-s19-backend-tests.txt bash test.sh
python3 scripts/check_unit_test_discovery.py
```

`test_s19_ptt_tool_retirement.py` is the planned behavioral 404/shared-adjacent suite. Delete or narrow old `test_tools_router.py`/formatter tests when their production owner is removed; never retain tests for nonexistent production code merely to fill this list.

### Route, OpenAPI, generated-client, formatting, and closure checks

```bash
cd backend
scripts/openapi_runner.sh scripts/route_policy_inventory.py --check --enforce-missing-baseline
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check

cd ..
desktop/macos/scripts/swift-format-wrapper.sh format -i <changed-swift-files>
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
```

The three routes currently sit in `route_policy_legacy_missing_routes.txt` and do not generate a retained `OmiAPI` DTO target. Regeneration is still mandatory and should produce no unrelated generated-client churn. If Gate 0 finds a new generated non-Windows operation, remove/regenerate it in Cycle 13 and add its contract test.

### Full component and PR gates

```bash
desktop/macos/test.sh
backend/test.sh
make preflight
scripts/pr-preflight --suggest
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
scripts/failure-class validate --pr-body-file /tmp/pr-body.md --base origin/main --head HEAD
```

Before a future `fix:` commit/PR, select and record `Failure-Class: FC-<slug> | new | none` from the actual preflight result. The PR must list exact commands/results and real user-path evidence. A changed behavior requires its regression test; no source-string-only test counts as that proof.

## 15. Real named-bundle and retained user-path acceptance

Only the future non-production named bundle may be launched. Never touch `/Applications/Omi.app`, `/Applications/Omi Beta.app`, `com.omi.computer-macos`, or `com.omi.computer-macos.beta`.

### Build/run and three distinct PTT lanes

```bash
cd desktop/macos
OMI_APP_NAME=omi-wave3-s19 ./run.sh

# Controller/current-screen protocol probe: real hub turn, synthetic transcript.
OMI_AUTOMATION_PORT=<reported-port> bash ./scripts/ptt-screen-probe.sh

# Manager/raw-capture route probe: real PushToTalkManager routing/admission, no controller redrive.
OMI_AUTOMATION_PORT=<reported-port> ./scripts/omi-ctl action ptt_manager_turn pcm=/absolute/path/to/pcm16-16k-mono.pcm
OMI_AUTOMATION_PORT=<reported-port> ./scripts/omi-ctl action ptt_turn_snapshot
```

For the manager lane, assert `injected_bytes` equals the actual file length and inspect typed admission/route/pending/terminal diagnostics only. For the controller screen probe, require `terminal_reason=success`, `pending_tool_count=0`, `screen_evidence_protocol_active=false`, and `screen_evidence_last_completion=completed`. Neither lane substitutes for the natural voice lane.

### Natural physical acceptance matrix

Using the real global shortcut and microphone in `omi-wave3-s19`:

1. verify the optional start and end cues are audible with output muting enabled, in held and double-tap locked modes; disabled sounds remain silent; cancellation/error does not produce misleading success feedback;
2. run a natural short utterance in at least two configured Voice Assistant Languages and exercise one controlled empty-first batch fallback, verifying at most one multilingual retry and no ambient-language/English special case;
3. select OpenAI, select Gemini, and select Auto in turn; complete a normal PTT exchange on each applicable route, then force documented transport failures to observe cross-provider, relay, and final batch behavior without changing provider policy;
4. ask for the latest Conversation and a date-bounded list; compare title/order/summary to the local Conversations UI while the retired product-data backend routes are unavailable;
5. ask a keyword-exact and semantically paraphrased Conversation-topic question; compare results to seeded local conversations, restart the app, repeat offline for already indexed data, and switch owners to prove isolation;
6. ask broad/specific Memory, Rewind screen-history, and today/long-period recap questions; compare with local surfaces and confirm the intentional unbounded Conversation/Task recap behavior with a controlled local dataset;
7. read overdue/today, future/undated, completed, and date-filtered tasks; create a task without a due time and one with a near due time; rename/reschedule/complete/reopen/undo through local IDs; observe local list changes, spoken confirmation, due reminder, and no immediate system Task Added banner;
8. ask a current-screen question and verify one whole-display image/report completion; confirm no physical-click tool is offered or action occurs;
9. barge in during speech and verify only produced partial output is marked interrupted in the shared selected Chat and available to the next turn;
10. complete a managed-Pi background run and show title-only/message-only/full Notch cards; ask a natural spoken follow-up, switch account before a pending delivery, and verify exactly-once current-owner untrusted context with no unsolicited answer;
11. terminate/reconnect a warm session, change provider/context, and verify replacement while journal continuity, status banners, notch recording/locked/thinking/speaking states, diagnostics, and usage counts remain correct; and
12. inspect safe local logs/telemetry evidence for lifecycle/fallback names and counts only—never raw transcript, OCR, Memory, Task, screenshot, provider token, or tool output.

Record bundle identifier, commit, port, provider, scenario, observable result, safe diagnostic snapshot, and pass/fail in the PR evidence. Provider credentials/TCC unavailable in the non-production environment are explicit unverified lanes, not implied passes.

## 16. Repository closure versus separately authorized live operational closure

### Repository closure in S-19

S-19 may remove code, tests, schemas, generated surfaces, route inventory, and current docs within its ownership. Repository closure requires:

- no current non-Windows caller/advertisement for deleted tools/routes/plans;
- no `realtime_sessions` writer or four-field usage wire;
- local behavior tests, full component suites, route-policy/OpenAPI/tool generation, exact residue searches, named-bundle evidence, and preflight GREEN;
- account deletion/export tests still pass for retained shared hosted data; and
- an explicit S-23/S-24 handoff of remaining Firestore/Typesense/Pinecone data and symbols.

S-19 does **not** deploy the backend or desktop, delete data, rotate/remove provider keys, change IAM, or mutate any live resource.

### Later read-only operational inventory

Using only verified environment/project identifiers from then-current deployment configuration, an authorized operator later inventories:

- whether any development/production `users/{uid}/realtime_sessions` documents exist and their retention/legal/backup classification;
- which hosted Conversation Firestore collections, Typesense collections, Pinecone indexes/namespaces, transcript-chunk vectors, and indexes are retained/shared/rejected/unknown after S-23/S-24;
- whether any route-specific dashboard, alert, metric, secret, service account, IAM binding, image, job, queue, or deployment exists despite no repository owner; and
- whether managed OpenAI/Gemini credentials are shared by retained services (expected) or exclusive to a rejected resource.

No project ID, resource name, customer count, credential, retention rule, or live state is inferred here.

### Separately authorized mutation/decommission

Any live delete/disable/rotation requires a separate explicit authorization after the read-only inventory, with exact target, backup/export requirement, legal retention, rollback or irreversibility statement, blast radius, and before/after evidence. Shared resources remain until their owning S-23/S-24/S-25 closure. Existing session-audit docs, if any, are a one-time operational data target—not a reason to keep a repository writer or add a legacy compatibility cleaner.

Billing remains `BILLING_MODE=disabled` through all waves. S-19 must not call Dodo, restore Stripe, grant entitlements, add a paywall, or make a provider transaction as “acceptance”; S-18's final Dodo exercise remains the separate post-Wave-6 gate.

## 17. Risks, ambiguities, and explicit stop points

| Risk / missing input | Affected cycles | Safe work that can proceed | Evidence required to reopen / owner |
|---|---|---|---|
| PTT controller breadth could regress capture or output ownership | 1–2, 8–12, 13 | Inventory and run unchanged manager/controller/both-provider fences | Production-seam RED/GREEN with unchanged reducer transitions; S-19 PTT owner |
| Local Conversation hybrid search has no current index | 4, 13 | Cycles 1–3 and independent retained-tool characterization | Local FTS/vector lifecycle passing edit/delete/restart/offline/late-result tests; S-19 local Conversation owner |
| Search parity could collapse to `LIKE` or reverse merge priority | 4, 13 | Establish exact keyword and semantic-only fixtures | Verified embedding model/dimension/wire contract and keyword-first behavioral result; S-19/S-22 embedding owners |
| Recap SQL is stale while IR-091 intentionally retains unbounded rows | 6, 13 | Characterize current bounds and canonical schemas | Behavioral recap test preserving the reviewed unbounded Conversation/Task rows; S-19 recap owner. A new cap requires a reviewed requirement. |
| Owner may change during embedding, DB work, reminder scheduling, or notch injection | 3–9, 13 | Add no late global-owner read; run unaffected capture cycles | One captured authorization snapshot with A→B/same-UID ABA and before/after-suspension tests; owning local store plus S-19 |
| Hosted route shares vector/hydration primitives with ingestion/account deletion | 4, 13 | Delete only proven-exclusive router/formatter work | Symbol-level caller matrix and exact S-24 handoff; S-19 route owner / S-24 provider owner |
| S-22 concurrently changes manifest/controller/session/model routes | 11–13 | Cycles 1–10 and non-overlapping inventory | Rebased S-22 integration plus symbol-level diff and both-provider/tool tests; S-19/S-22 owners |
| Several deletion targets may already be compliant | Owning cycle and 13 | Characterize behavior and add truthful absence proof | Current caller inventory showing absence; S-19 owner. Do not create fake migration churn. |
| “Automation” also names retained test infrastructure | 8, 13 | Preserve automation bridge, bundle isolation, and test actions | Caller/type inventory distinguishing permission claims from test control; S-17/S-19 owners |
| Development provider or TCC credentials unavailable | Named-bundle natural lane in 13 | Hermetic tests plus local manager/controller lanes | Authorized non-production credential/TCC evidence under Definition of Done; operator/S-19 owner. Production Omi apps remain prohibited. |
| Live `realtime_sessions` resources unknown | Operational closure only | Complete repository writer deletion | Verified read-only inventory and explicit mutation authorization; platform/data owner |
| Product-owned Sentry/PostHog IDs unavailable or stale | Telemetry acceptance in 13 | Preserve current config and run non-live telemetry tests | S-09-owned development identifiers/project evidence; S-09/operator owner |
| Generated route/tool surfaces drift | 8, 10–13 | Edit canonical sources only | Regeneration, `--check`, compile/runtime capability tests, and route inventory; S-19 generator owner |
| Voice higher-model deletion could overreach into typed Chat/public web | 11, 13 | Delete only voice-specific callers after characterization | Retained typed `/v2/chat/completions` behavioral fence and exact S-22 handoff; S-19/S-22 owners |
| Task Added banner could be confused with a retained PostHog event | 7, 13 | Preserve analytics and characterize notification behavior | Production-seam assertion deleting only the system banner; S-13/S-19 task owner and S-09 telemetry owner |

There is no unresolved product decision in the assigned IR set. The only unresolved inputs are current future-integration deltas, non-production provider/TCC availability for live acceptance, product-owned telemetry identifiers if not already configured, and authorized live-resource inventory. Each has a bounded stop point above.

## 18. Final completion checklist

- [ ] Gate 0 recorded the current commit, clean status, Wave 2 ancestry, decision validation, and all deltas since `711269ba`.
- [ ] Every assigned decision IR-054–119, IR-600–602, IR-924–926, and IR-932 is mapped and preserved/adapted/deleted exactly as section 4 states.
- [ ] All 13 cycles produced behavioral RED, minimum GREEN, focused evidence, enabled deletion/simplification, and honored their stop condition.
- [ ] Held/locked capture, optional cues/mute, admission/recovery, PTT language policy, barge-in, screen/report, warm replacement, relay/batch, both providers, Auto, diagnostics, traces, banners, and notch visual states pass.
- [ ] Conversation listing is local, newest-first, date/offset/limit correct, owner-fenced, restart-safe, and does not default-disclose transcripts.
- [ ] Conversation search is local FTS5 + local persisted vectors with transient compute, keyword-first merge, date/limit/dedupe parity, edit/delete/restart/offline/late-result coverage.
- [ ] Memory, Rewind, recap, and all Task tools execute through canonical local owners with one authorization snapshot and failure/no-phantom behavior.
- [ ] Daily recap uses current schemas while preserving arbitrary periods and unbounded Conversation/Task rows plus existing other-section bounds.
- [ ] Task create/update/read/reminder/receipt/undo behavior is local; `+24h` and spoken confirmation remain; the immediate system Task Added banner remains absent.
- [ ] Completion and Notch card context are bounded, exactly as retained, full-card, untrusted, non-durable, owner-fenced, and cleared/rejected across account change.
- [ ] `point_click`, voice `ask_higher_model`/live-web, Calendar creation, customer BYOK, deprecated PTT events, and UserDefaults importer are absent from canonical/generated/runtime/current-doc surfaces.
- [ ] Realtime mint no longer writes `users/{uid}/realtime_sessions`; usage sends only actual token counts and preserves current quota/cost/cached-token behavior.
- [ ] All three hosted PTT Conversation routes are genuine 404s, exclusive service/client/route-policy/FORK residue is gone, and no compatibility shell remains.
- [ ] `/v4/listen`, normal typed `/v2/chat/completions`, both realtime providers, shared account deletion/vector primitives, product telemetry, and Windows remain untouched.
- [ ] Tool surfaces were regenerated from the canonical manifest; OpenAPI/non-Windows generator checks, route-policy baseline, and backend test discovery pass without unrelated churn.
- [ ] Exact residue searches were reviewed and every surviving match is an explicit retained/shared handoff or labelled static absence test.
- [ ] Focused tests, `desktop/macos/test.sh`, `backend/test.sh`, `agent-logic-harness.sh`, `make preflight`, failure-class/PR preflight, and `git diff --check` pass with evidence recorded.
- [ ] The real `omi-wave3-s19` named bundle passed manager, controller, and natural physical PTT acceptance; any unavailable provider/TCC lane is explicitly unverified rather than implied GREEN.
- [ ] `PRODUCT.md`, component `AGENTS.md`, architecture docs, and `FORK.md` moved only where implementation changed their owned current contract.
- [ ] No new TODO/FIXME/HACK is orphaned; no purple UI, sensitive log, unbounded new retry, compatibility adapter, duplicate owner, or fake-success response was introduced.
- [ ] Repository closure and a separately authorized live read-only inventory/decommission remain distinct; no deployment or external mutation occurred in the implementation PR unless separately requested later.
- [ ] `BILLING_MODE=disabled` remains unchanged and no Dodo/Stripe/provider transaction was used.
- [ ] Final requirements-ledger validator and clean diff review confirm only intended implementation/docs changed; changes are committed in testable surfaces with commands/evidence in commit/PR text, never pushed/merged without the repository's current authorization rules.
