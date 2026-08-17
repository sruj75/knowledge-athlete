# S-15 — Preserve local Rewind and delete every cloud copy/read path

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | S-15 |
| Wave | Wave 2 — make retained Mac behavior authoritative |
| Assigned output | `bootstrap-scaffold/wave-2/s-15 tdd.md` |
| Assigned decisions | IR-011, IR-053, IR-088 through IR-091, IR-232 through IR-240, IR-683 through IR-699, IR-806, IR-807, IR-899 through IR-921 |
| Product boundary | Mac-local Rewind capture, OCR, video, SQLite, embeddings, search, timeline, settings, recovery, retention, PTT screen-history grounding, and daily recap; rejection of every shared-backend screen-history writer, copy, reader, index, and backend-agent entrance |
| Implementation rule | Treat the existing Mac Rewind stack as the authority. Protect it first, delete the disconnected cloud graph vertically, then simplify exclusive residue. Do not redesign retained behavior and do not add a compatibility shell. |

This is the execution-grade TDD plan for S-15. Producing it authorizes no
product-code change, deployment, data migration, live resource mutation, or
cloud-data deletion.

## 2. Planning status and pinned baseline

| Evidence | Verified planning state on 2026-08-16 |
|---|---|
| Checkout | `/Users/srujanu/conductor/workspaces/knowledge-athlete/honiara` |
| Current branch | `review-wave-1-deletions` |
| Pinned code baseline | `0d9934c9d2ed61bd02ac8784e50f56ee816257c3` |
| Required ancestry | `git merge-base --is-ancestor 0d9934c HEAD` returned success |
| Planning-time `origin/main` | `3aab1026357fb0be6bcf567c24df84684ba6198e` |
| Requirements proof | `python3 bootstrap-scaffold/validate-requirements-ledger.py` passes with 714 indexed rows, 714 detailed sections, all reviewed |
| Dependency proof | S-01's `test_agent_vm_route_retirement.py` and S-06's `test_s06_external_surface_route_retirement.py` are present; current production searches find neither the Agent-VM screenshot reader nor a hosted/public MCP screen-history surface |
| Source grounding | Every path, symbol, route, namespace, index, test, document, and command described as current below was found at the pinned checkout. Planned new test names are marked **new**. |
| Planning-only scope | Existing untracked S-10 through S-14 plans are user-owned and untouched. Only this assigned file may change for this task. |

The pinned SHA is research evidence, not an implementation base. Before the
first RED, integrate current `origin/main`, record the new immutable execution
SHA and predecessor SHAs, rerun the caller/residue inventory, and update stale
path names in the implementation record. The research roadmap mentioned an old
`desktop_screen_crisp.py` lead; the current writer is
`backend/routers/desktop_screen_activity.py`, and current source wins.

## 3. Outcome

At completion, Rewind remains one Mac-local product:

```text
ScreenCaptureKit
  -> ProactiveAssistantsPlugin
  -> RewindIndexer
  -> local video + OCR + owner-scoped GRDB/SQLite
  -> OCREmbeddingService
       -> authenticated Gemini desktop proxy (transient computation only)
       -> embedding BLOB returned to and stored on the Mac
  -> local FTS + local vector similarity
  -> selected-day Rewind UI
  -> local ChatToolExecutor search_screen_history / get_daily_recap

No edge
  -> /v1/screen-activity/sync
  -> Firestore users/{uid}/screen_activity
  -> Pinecone ns3
  -> backend get/search screen-activity tools
  -> hosted MCP or Agent VM
```

The Mac continues to capture, recover, retain, browse, text-search, semantic-
search, and ground PTT locally with all reviewed reachable, stale, and dormant
quirks unchanged. The authenticated Gemini proxy may see request content only
long enough to compute and return an embedding; it does not become product-data
authority, and vectors/similarity remain local.

The Python apps no longer accept a screen-history upload, persist or query
screen rows/vectors, expose screen activity to the backend agent, require its
Firestore index, enumerate it for Pinecone account deletion, advertise its
model purpose, or describe it as a retained backend capability. Deleted routes
are genuine 404s, not no-op successes, 410 shims, forwarding aliases, or feature
flags.

## 4. Authorizing requirements: individual IR mapping

| IR | Decision implemented or protected by S-15 | Plan coverage |
|---|---|---|
| IR-011 | Delete the shared-backend Rewind copy and its Firestore/Pinecone producer and consumer graph. | Cycles 2–4 |
| IR-053 | Keep authenticated transient Gemini embedding computation; store vectors and run similarity only on the Mac. | Entry keep fence; Cycles 2–3 protection; acceptance |
| IR-088 | Keep realtime PTT alias `search_screen_history` resolving to the local semantic-search executor. | Entry keep fence; acceptance |
| IR-089 | Keep up to 15 default matches with date/time, app, title, internal screenshot ID, score, and up to 300 OCR characters. | Entry keep fence; acceptance |
| IR-090 | Keep local `get_daily_recap` with its six GRDB queries over apps, conversations, tasks, Focus, memories, and observations. | Entry keep fence; acceptance |
| IR-091 | Keep arbitrary numeric recap periods with only the lower clamp; do not add a maximum or conversation/task row cap. | Entry keep fence; acceptance |
| IR-232 | Keep the local Rewind Storage card unchanged. | Cycle 1 protection; acceptance |
| IR-233 | Keep the complete Excluded Apps control unchanged. | Cycle 1 protection; acceptance |
| IR-234 | Keep automatic battery cadence and its information card unchanged. | Cycle 1 protection; acceptance |
| IR-235 | Keep local Data Retention setting and cleanup unchanged. | Cycle 1 protection; acceptance |
| IR-236 | Keep `--mode=rewind`, `RewindOnlyView`, and their dev/test role unchanged. | Entry keep fence; acceptance |
| IR-237 | Delete exactly `rewind.rewind`, `rewind.screencapture`, and `rewind.audiorecording` from Settings search; preserve the real Rewind page and controls. | Cycle 1 |
| IR-238 | Delete only `transcription.settings`; preserve the four concrete transcription entries and behavior. | Cycle 1 |
| IR-239 | Delete `general.rewind`, `general.askomi`, and `general.resetwindow`; preserve actual General, Floating Bar, font-size, and working reset controls. | Cycle 1 |
| IR-240 | Delete `privacy.storerecordings` and `privacy.cloudsync` with IR-122's underlying control deletion; do not change transient STT, local transcripts, PTT, or Rewind. | Cycle 1 dependency gate |
| IR-683 | Keep the customer-facing local Rewind workflow and local-authoritative history. | Entry keep fence; acceptance |
| IR-684 | Keep today as the opening date and one selected calendar day as the timeline/search boundary. | Entry keep fence; acceptance |
| IR-685 | Keep all stored history and the at-most-500 evenly sampled ordinary-day projection. | Entry keep fence; acceptance |
| IR-686 | Keep local FTS/text results first, local-vector results, dedupe, 100/50 bounds, 0.5 UI threshold, and text success when semantic compute fails. | Entry keep fence; acceptance |
| IR-687 | Keep exact app/window grouping within 30 seconds. | Entry keep fence; acceptance |
| IR-688 | Keep grouped list as search default plus List/Timeline switching and return behavior. | Entry keep fence; acceptance |
| IR-689 | Keep click/drag/scroll/arrow navigation and latest-image-request protection. | Entry keep fence; acceptance |
| IR-690 | Keep the last valid image when the newly selected frame cannot load. | Entry keep fence; acceptance |
| IR-691 | Keep dormant full-screen autoplay and its private playback model exactly. | Inventory protection; no edits |
| IR-692 | Keep dormant alternate timeline, preview, OCR Copy UI, and live-highlight helper. | Inventory protection; no edits |
| IR-693 | Keep dormant search/filter bar and loaded app-filter wiring. | Inventory protection; no edits |
| IR-694 | Keep dormant filmstrip, cache, match-count helper, and preview. | Inventory protection; no edits |
| IR-695 | Keep dormant grid, grouping, hover delete, and unused deletion wiring. | Inventory protection; no edits |
| IR-696 | Keep exact No Screenshots Yet presentation and every-second wording. | Entry keep fence; acceptance |
| IR-697 | Keep missing-permission explanation, desired-Capture enablement, and guided System Settings action. | Entry keep fence; acceptance |
| IR-698 | Keep hard Screen Recording permission reset, data-preserving restart, and recovery screen. | Entry keep fence; acceptance |
| IR-699 | Keep generic initial error and complete Retry behavior. | Entry keep fence; acceptance |
| IR-806 | Delete Typesense completely at its final owner; S-15 proves there is no screen-history Typesense path and hands shared removal to S-24. | Inventory; S-24 handoff |
| IR-807 | Remove the screen-history `ns3` Pinecone branch now; S-24 deletes the remaining shared Pinecone runtime after all other domain callers leave. | Cycle 4; S-24 handoff |
| IR-899 | Keep stale projection, diagnostic-only selected-date/search failure, and no Retry. | Acceptance; no edits |
| IR-900 | Keep exact Searching and No results found states. | Acceptance; no edits |
| IR-901 | Keep recovered-count banner and zero-record Rebuild Index workflow. | Entry keep fence; acceptance |
| IR-902 | Keep disabled-button-only rebuild progress and diagnostic-only failure. | Acceptance; no edits |
| IR-903 | Keep shared Capture control, health badges, permission handoff, and failed-start rollback. | Entry keep fence; acceptance |
| IR-904 | Keep Settings gear navigation directly to Rewind settings. | Acceptance; no edits |
| IR-905 | Keep advertising Command-Option-R while the listener recognizes Control-Option-R. | Acceptance; do not repair |
| IR-906 | Keep full-page behavior and the stale overlay/previous-page-closing descriptions. | Residue allowlist; do not rewrite docs/copy |
| IR-907 | Keep developer `navigate rewind` opening the real page. | Named-bundle acceptance |
| IR-908 | Keep quiet three-second today refresh, current skip conditions, and diagnostic-only failure. | Acceptance; no edits |
| IR-909 | Keep inclusive next-midnight and possible adjacent-day midnight duplication. | Acceptance; no edits |
| IR-910 | Keep current frame when captures arrive, falling back to newest only if it disappears. | Acceptance; no edits |
| IR-911 | Keep calculating undisplayed screenshot/index/storage statistics. | Cycle 1 and acceptance |
| IR-912 | Keep evenly spaced continuous presentation, hidden real gaps, launch-variable colors, hover details, and dormant gap machinery. | Acceptance; no edits |
| IR-913 | Keep reversed search-group timeline direction and yellow legend without visible markers. | Acceptance; no edits |
| IR-914 | Keep mouse-only activation after keyboard highlight and indefinite failed-thumbnail spinner. | Acceptance; do not repair |
| IR-915 | Keep old projection during loads and allow older date requests to overwrite newer selection. | Acceptance; do not repair |
| IR-916 | Keep trimmed-empty execution versus raw-nonempty presentation disagreement. | Acceptance; do not normalize |
| IR-917 | Keep active-chunk searchability despite ordinary-timeline exclusion and preserve No frame fallback. | Acceptance; no edits |
| IR-918 | Keep unrestricted past/future graphical dates and existing empty presentation. | Acceptance; no edits |
| IR-919 | Keep the broad app-wide local scroll monitor. | Acceptance; do not narrow |
| IR-920 | Keep all proven-unused Rewind rows, models, helpers, parameters, and published state unreachable. | Inventory protection; no cleanup |
| IR-921 | Keep both developer-only real-page visual-export registrations. | Entry keep fence; acceptance |

IR-122 is a dependency for IR-240, not reassigned to this slice. Its conversation-
audio controls/cards belong to S-10's rejected cloud-audio closure. S-15 owns the
two stale search-catalog IDs only after the underlying rows are removed at the
integrated execution HEAD. If S-10 has not removed the card/control yet, defer
those two IDs with an exact handoff rather than leaving search and card truth out
of sync or broadening S-15 into conversation-audio deletion.

## 5. Dependencies and entry gates

### Required predecessor shapes

| Dependency | Shape S-15 consumes | Gate and stop condition |
|---|---|---|
| S-01 | Agent VM routes/runtime and `AgentSyncService` screenshot-table mirroring are gone. | Already visible at the planning baseline. Stop if a refreshed inventory finds any VM reader/writer; S-01 must close it rather than S-15 recreating VM teardown. |
| S-06 | Hosted/public MCP and remote-MCP screen-history surfaces are gone while the retained private local tool transport remains. | Already visible at the planning baseline. Stop if a hosted MCP screen reader reappears; resolve predecessor ownership before Cycle 3. |
| S-10 / IR-122 | Store Recordings and Private Cloud Sync cards, state, and behavior are gone. | Required only for the two IR-240 search IDs. Do not delete a discoverable search target before its owned card lands, and do not implement IR-122 in S-15. |
| Current released contract | No supported client depends on `/v1/screen-activity/sync`; checked-in app-client OpenAPI and generated non-Windows Swift contain no binding at the planning baseline. | Recheck tags/contracts at execution. If a supported released contract contains it, stop and obtain the required contract-sunset/version decision; never add a fake-success or 410 shell. |
| Current caller inventory | No Mac uploader, hosted MCP reader, VM reader, generated client, Typesense screen branch, GCS/Redis copy, background job, workflow, alert, or secret is exclusive to screen history. | Rerun before deletion. A newly found producer/consumer must be assigned and removed or explicitly handed off; absence at this SHA is not timeless proof. |

### Mandatory execution entry sequence

```bash
git fetch origin --prune
git status --short
git rebase origin/main
git rev-parse HEAD
git merge-base --is-ancestor 0d9934c HEAD
python3 bootstrap-scaffold/validate-requirements-ledger.py
make setup
test -x "$(git rev-parse --git-path hooks)/pre-commit" && echo OK
```

Implementation happens in an isolated git worktree on the current feature
branch; do not rename the branch. Preserve unrelated changes. Commit each
vertical GREEN separately. Do not push, open a PR, merge, deploy, or delete live
data without the separate authorization required by `AGENTS.md`.

### Behavioral keep fence before the first RED

Run and record these existing green surfaces before editing. They are retained
characterization/acceptance fences, not retroactively labelled RED tests:

```bash
cd desktop/macos
xcrun swift test --package-path Desktop --filter RewindArtifactGauntletTests
xcrun swift test --package-path Desktop --filter RewindAbandonedChunkRecoveryTests
xcrun swift test --package-path Desktop --filter RewindDatabaseLifecycleTests
xcrun swift test --package-path Desktop --filter RewindRetentionCleanupTests
xcrun swift test --package-path Desktop --filter RewindSearchQueryExpansionTests
xcrun swift test --package-path Desktop --filter OCREmbeddingServiceOwnerResetTests
xcrun swift test --package-path Desktop --filter ScreenPrivacyExclusionTests
xcrun swift test --package-path Desktop --filter ScreenRecordingPermissionPolicyTests
xcrun swift test --package-path Desktop --filter AuthorizedToolExecutionTests
./scripts/test-tool-surfaces.sh
./scripts/agent-logic-harness.sh

cd ../../backend
.venv/bin/python -m pytest -q tests/unit/test_desktop_proxy.py
```

The requirements pre-agree the public seams: FastAPI route registration/HTTP
status, backend-agent tool roster, account-deletion result/call boundary,
generated Firestore index manifest, Settings search catalog, local tool
manifest/execution, GRDB artifact lifecycle, and named-bundle UI/bridge actions.
Tests must drive those seams. Source inspection may supplement residue closure
only when labelled `static tripwire`; it cannot be a cycle's behavioral RED.

### General stop gates

1. A GREEN may not add a server fallback, upload outbox, provider interface with
   one implementation, disabled compatibility module, or local-to-cloud replay.
2. No Mac Rewind production file may change except `SettingsSidebar.swift`, its
   focused contract test, or a strictly necessary truthful doc/changelog entry.
   If backend deletion appears to require changing capture, OCR, storage,
   timeline, embedding, or local tools, stop and diagnose the boundary error.
3. Do not edit historical migrations or import inherited Omi cloud data. This
   fork is unreleased; there is no legacy-user compatibility migration.
4. Repository closure and live data/infrastructure closure are separate. A
   passing PR never authorizes Firestore, Pinecone, index, log, or deployment
   deletion.

## 6. Verified current production codeflow

### Local capture, persistence, and search

1. `ProactiveAssistantsPlugin` owns ScreenCaptureKit admission, privacy and idle
   gates, capture health/backpressure, assistant fan-out, and the call to
   `RewindIndexer.shared.processFrame`.
2. `RewindIndexer` initializes `RewindDatabase` and `RewindStorage`, sends frames
   through `VideoChunkEncoder`, performs OCR/dedup, inserts local screenshot rows
   with video offsets into GRDB, queues embeddings, notifies the UI, runs
   retention, recovers abandoned chunks, and suspends across owner transitions.
3. `RewindStorage` owns local video/JPEG readback, extraction, recovery, cleanup,
   and size. `RewindDatabase` owns screenshots, FTS, embedding BLOBs, selected-day
   queries/sampling, recovery, and retention in the owner-scoped local store.
4. `OCREmbeddingService` batches up to 100 OCR documents on a 60-second window,
   calls `EmbeddingService`, writes returned vectors to `RewindDatabase`, runs
   local vDSP similarity, backfills missing vectors, and generation-fences owner
   switches. This is the retained local vector authority.
5. `EmbeddingService` calls authenticated
   `/v1/proxy/gemini/models/gemini-embedding-001:embedContent` and
   `:batchEmbedContents`; `backend/routers/desktop_proxy.py` performs transient
   managed-model proxying. It is distinct from the deletable backend-agent
   helper `utils.llm.clients.gemini_embed_query`.
6. `RewindViewModel` opens on today, samples at most 500 ordinary frames, and on
   search combines local FTS (100) with local semantic results (50), keeps text
   first, dedupes, applies the reviewed threshold, and fails open to text when
   semantic compute fails.

### Local PTT grounding and recap

1. The canonical agent manifest declares `semantic_search`, alias
   `search_screen_history`, and `get_daily_recap`; generated Swift and the checked
   fixture preserve those names.
2. `ChatToolExecutor` resolves `search_screen_history` to `.semanticSearch`,
   defaults to seven days and 15 results, fetches the exact local screenshot row,
   and returns date/time, app, title, internal ID, similarity, and at most 300 OCR
   characters. The public maximum remains 50; the reviewed shared default remains
   15.
3. `get_daily_recap` lower-clamps `days_ago` to zero and executes six local GRDB
   queries. Conversations and tasks are intentionally unbounded; only some other
   formatted sections use their current display prefixes.
4. Both tool paths owner-fence before/after awaits. No backend screen-activity
   tool is needed for PTT.

### Remaining cloud writer and copy

1. `backend/routers/desktop_screen_activity.py` owns authenticated/paywall-gated
   `POST /v1/screen-activity/sync`, a 100-row request contract, Firestore writes,
   Pinecone writes, and a dev parity capture source
   `desktop_screen_activity_sync`.
2. Both `backend/main.py` and `backend/desktop_backend.py` mount that router;
   `backend/route_policy_manifest.yaml` lists it. The Mac
   `ScreenActivitySyncService` and every in-tree request to this endpoint are
   already absent, so this is an uncalled writer entrance, not an authority to
   preserve.
3. `backend/database/screen_activity.py` writes and reads
   `users/{uid}/screen_activity`, summarizes rows, and enumerates IDs for account
   deletion.
4. `backend/database/vector_db.py` owns `SCREEN_ACTIVITY_NAMESPACE = "ns3"` and
   screen-only upsert/search/delete functions. The module, Pinecone client,
   other namespaces, environment variables, dependencies, deploy settings, and
   secrets still have non-S-15 callers and remain for S-24.

### Remaining cloud readers and lifecycle residue

1. `backend/utils/retrieval/tools/screen_activity_tools.py` defines backend-agent
   summary and semantic readers over Firestore/Pinecone.
2. `backend/utils/retrieval/tools/__init__.py` exports them and
   `backend/utils/retrieval/agentic.py` includes both in `CORE_TOOLS` and display
   status mapping, exposing old cloud copies to normal backend agentic Chat.
3. `backend/utils/llm/clients.py::gemini_embed_query` exists only to embed this
   cloud reader's query directly; its
   `gemini_screen_activity_query_embedding` inventory entry is exclusive. Delete
   both without touching the retained desktop proxy.
4. `backend/services/users/account_deletion.py` enumerates Firestore screen IDs,
   requires Pinecone, deletes `ns3`, counts the vectors, and treats failure as
   required. Generic recursive Firestore deletion in
   `backend/database/users.py` will still remove any subcollection documents and
   remains; only its stale named example is adapted.
5. `backend/database/firestore_index_registry.py` and generated
   `firestore.indexes.json` retain the `screen_activity` app/timestamp composite.
6. `backend/AGENTS.md`, `backend/testing/parity_pack_v0/README.md`,
   `backend/docs/llm/model_endpoint_inventory.yaml`, tests, and
   `desktop/macos/test.sh` describe or invoke the cloud surface.

### Confirmed absent or shared surfaces

- Agent-VM screenshot mirroring is already gone under S-01.
- Hosted/public MCP screen history is already gone under S-06.
- No generated non-Windows app-client binding names the route at this baseline.
- No Typesense, GCS, Redis, job, worker, workflow, chart, alert, metric, or
  screen-specific secret/config path was found.
- Shared `SurfaceParityCapture` remains useful for other surfaces; only its
  screen-specific fixture/docs/call site are removed or retargeted.
- Historical changelog/provenance and bootstrap-scaffold research remain. They
  are records, not live entrances.

## 7. Complete caller and dependency inventory at the pinned baseline

### Mac retained and adapted surfaces

| Current file / symbol | Current role/callers | S-15 disposition |
|---|---|---|
| `Desktop/Sources/ProactiveAssistants/ProactiveAssistantsPlugin.swift` | ScreenCaptureKit owner and `RewindIndexer` producer | KEEP AS IS |
| `Desktop/Sources/Rewind/Services/RewindIndexer.swift` | Capture-to-video/OCR/GRDB/embedding pipeline, recovery, cleanup | KEEP AS IS |
| `Desktop/Sources/Rewind/Core/RewindDatabase.swift` and models | Owner-local screenshots, FTS, embedding BLOBs, sampling, queries, statistics | KEEP AS IS; do not rename schema/store |
| `Desktop/Sources/Rewind/Core/RewindStorage.swift`, `VideoChunkEncoder.swift`, recovery helpers | Local artifact files, frame readback, rebuild and cleanup | KEEP AS IS |
| `Desktop/Sources/Rewind/Services/OCREmbeddingService.swift` | Transient embedding calls, local vector writes and similarity | KEEP AS IS |
| `Desktop/Sources/ProactiveAssistants/Services/EmbeddingService.swift` and `ModelQoS.swift` | Authenticated Gemini desktop-proxy transport/model | KEEP AS IS |
| `Desktop/Sources/Rewind/UI/RewindPage.swift`, `RewindViewModel.swift`, bars/timeline/dormant components | Reviewed full-page, selected-day, search, grouping, frame navigation and quirks | KEEP AS IS, including dormant/stale behavior |
| `Desktop/Sources/Providers/ChatToolExecutor.swift` | Local `semantic_search` and six-query daily recap | KEEP AS IS |
| `agent/src/runtime/omi-tool-manifest.ts`, generated tool files, fixture, agent tests | Canonical tools, alias, capability, relay contract | KEEP AS IS and regenerate only if unexpected drift requires it; S-15 should produce no diff |
| `Desktop/Sources/MainWindow/SettingsSidebar.swift` | Search catalog includes nine rejected phantom/stale IDs | ADAPT exact IDs in Cycle 1 |
| `Desktop/Sources/MainWindow/Pages/Settings/Sections/SettingsContentView+Rewind.swift` | Storage, Excluded Apps, Battery, Retention cards | KEEP AS IS |
| `Desktop/Tests/SettingsSearchContractTests.swift` | Current external-surface absence only | ADAPT with exact S-15 absence/presence contract |
| Rewind/permission/privacy/embedding/tool tests named in Section 5 | Existing local behavioral fences | KEEP and run; do not rewrite expectations to accommodate deletion |
| `e2e/flows/rewind*.yaml`, `screen-recording-permission.yaml` | Real page/settings and artifact recovery flows | KEEP, including stale overlay language required by IR-906 |
| `desktop/macos/test.sh` | Hardcodes deleted backend upload test | ADAPT to the new route-retirement test path |
| `desktop/macos/CHANGELOG.json`, release fragments/docs | Historical Rewind/screen-history mentions | KEEP historical records; add one new truthful fragment, do not rewrite old releases |

### Backend production/config/docs surfaces

| Current file / symbol | Current role/callers | S-15 disposition |
|---|---|---|
| `backend/routers/desktop_screen_activity.py` | Uncalled Firestore/Pinecone upload route and screen parity capture | DELETE whole after Cycle 2 RED |
| `backend/main.py`, `backend/desktop_backend.py` | Import and mount upload router alongside retained proxy | ADAPT exact import/registration only |
| `backend/route_policy_manifest.yaml` | Active POST policy row | DELETE row; rerun inventory generator/check |
| `backend/database/screen_activity.py` | Firestore writer/readers/summary/ID enumeration | DELETE after writer, reader, and deletion callers leave |
| `backend/database/vector_db.py` screen section | `ns3` upsert/search/delete | DELETE exact section only; retain module and all other namespaces |
| `backend/utils/retrieval/tools/screen_activity_tools.py` | Backend-agent Firestore/Pinecone readers | DELETE whole in Cycle 3 |
| `backend/utils/retrieval/tools/__init__.py` | Imports/exports screen tools among retained tools | ADAPT exact two tools only |
| `backend/utils/retrieval/agentic.py` | Registers screen tools in model-visible `CORE_TOOLS` and status map | ADAPT exact two tools; preserve order of remaining prompt-cache prefix |
| `backend/utils/llm/clients.py::gemini_embed_query` | Exclusive direct query embedding for deleted cloud reader | DELETE function only; retain general embedding/model clients |
| `backend/docs/llm/model_endpoint_inventory.yaml` | Exclusive out-of-scope screen query surface | DELETE entry; retain desktop proxy/model config docs elsewhere |
| `backend/services/users/account_deletion.py` | Treats screen `ns3` cleanup as required before Firestore wipe | ADAPT away screen imports/branch while preserving every other required purge |
| `backend/database/users.py` generic recursive deletion | Deletes all user subcollections including any old screen docs | KEEP generic behavior; remove or generalize stale screen example only |
| `backend/database/firestore_index_registry.py` | Declares screen app/timestamp index | DELETE exact requirement |
| `firestore.indexes.json` | Generated screen composite | REGENERATE after registry deletion; do not hand-edit |
| `backend/testing/parity_pack_v0/README.md` | Documents screen route capture | DELETE screen row only; retain shared adapter docs |
| `backend/AGENTS.md` | Calls screen activity a retained retrieval domain | ADAPT service map truthfully |
| `PRODUCT.md` and `FORK.md` | Already say persisted Rewind OCR/video/vector state is local | KEEP unless final diff makes an adjacent sentence inaccurate |

### Backend test and contract surfaces

| Current file | S-15 treatment |
|---|---|
| `tests/unit/test_desktop_screen_activity.py` | Replace upload-success contract with **new** `tests/unit/test_s15_screen_history_retirement.py` against both production app objects; delete old file. |
| `tests/unit/test_screen_activity_search_utc.py`, `test_screen_activity_tool_result_bound.py` | Delete with exclusive cloud readers; do not port them to local Rewind, whose reviewed contract differs. |
| `tests/unit/test_prompt_cache_integration.py` | Adapt expected public tool roster/order to omit only the two cloud screen tools; cite IR-011 as the external expectation source. |
| `tests/services/users/test_account_deletion.py` | Adapt call/result/failure expectations to prove retained purges still fail closed while no screen-vector branch exists. |
| `tests/unit/test_delete_account_purge_storage.py` | Remove screen fake/import/call expectations; preserve ordering, isolation, GCS, Firestore and other Pinecone behavior. |
| `tests/unit/test_delete_account_stripe_cancel.py`, `test_desktop_transcribe.py` | Remove `database.screen_activity` import stubs if no remaining import needs them. |
| `tests/unit/test_firestore_index_config.py` | Replace presence expectation with a labelled generated-manifest static tripwire asserting no `screen_activity` index. |
| `tests/unit/test_surface_parity_capture.py` | Retarget shared adapter coverage to a retained dev capture surface or delete only duplicate screen-specific fixtures; do not delete `SurfaceParityCapture`. |
| Route policy/OpenAPI/generator and test-discovery suites | Run unchanged; generated app-client output is expected to stay unchanged because no binding exists now. |

## 8. Behavior classification

| Classification | Surface | Required treatment |
|---|---|---|
| KEEP AS IS | ScreenCaptureKit, privacy/idle gates, capture health/backpressure, video/OCR/GRDB pipeline | No production edit. Prove real capture plus hermetic artifact lifecycle. |
| KEEP AS IS | Local FTS, embedding BLOBs, local vDSP similarity, combined search | No fallback to Python product-data readers or Pinecone. |
| KEEP AS IS | Authenticated Gemini embedding desktop proxy | Protect registration, auth/paywall/rate behavior and response-shape tests. It is transient compute, not a copy. |
| KEEP AS IS | Selected-day UI, 500 sampling, grouping, list/timeline, navigation, recovery, retention, permissions | Run existing tests and named bundle; preserve exact reviewed quirks. |
| KEEP AS IS | `search_screen_history`/`semantic_search`, payload, owner fence, `get_daily_recap` | Keep canonical manifest/generated Swift/executor unchanged. |
| KEEP AS IS | Four real Rewind settings cards and real General/Transcription/Floating Bar controls | Cycle 1 presence assertions prevent collateral catalog deletion. |
| KEEP AS IS | Dormant Rewind components/helpers/state and stale overlay/shortcut behavior | Do not simplify merely because unreachable or incorrect. |
| ADAPT | Settings search catalog | Delete exactly nine assigned stale IDs, subject to IR-240 predecessor gate. |
| ADAPT | Both Python app registries and route policy | Unmount upload route; neighboring proxy/desktop routes remain. |
| ADAPT | Backend-agent tool exports/registry/prompt-cache expectation | Remove exactly two cloud screen tools. |
| ADAPT | Account deletion and tests | Remove obsolete screen-specific Pinecone prerequisite; preserve all real remaining deletion guarantees. |
| ADAPT | Firestore index source/generated manifest and docs | Remove exact screen index/claims and regenerate deterministically. |
| DELETE | `desktop_screen_activity.py` and its success/paywall/batch tests | No producer and rejected authority. |
| DELETE | `database/screen_activity.py` | No writer/reader/enumerator after Cycles 2–4. |
| DELETE | `screen_activity_tools.py` and exclusive reader tests | Backend agent must not read local Rewind copies from cloud. |
| DELETE | Pinecone `ns3` constants/functions and exclusive direct query embedder/inventory | Screen-only cloud vector authority. |
| DELETE | Screen route parity-pack row/fixture and route runner residue | Remove only exclusive branch, retain shared adapter. |
| SIMPLIFY AFTER | Screen-specific imports, display strings, stubs, comments, test runner entries | Delete only after the owning behavioral GREEN and `rg` proof. |
| SIMPLIFY AFTER | Generic Firestore deletion comment | Make generic; do not weaken recursive deletion of unknown/old subcollections. |
| OUT OF SCOPE / DEFERRED | Whole Pinecone client, dependency, credentials, env, deploy config, other namespaces | S-24 after all retained domains are local. |
| OUT OF SCOPE / DEFERRED | Whole Typesense stack | S-24; no S-15-specific path exists now. |
| OUT OF SCOPE / DEFERRED | Conversation-audio Privacy cards/state | S-10 / IR-122. S-15 owns only the two search IDs after integration. |
| OUT OF SCOPE / DEFERRED | Final shell/navigation and storage namespace/installation identity | S-21 and S-28. Do not rename Rewind stores or routes. |
| OUT OF SCOPE / DEFERRED | Windows | Explicitly excluded. |

## 9. Retained behavioral invariants

1. **One persistent authority:** screenshot images/video, OCR, metadata, FTS, and
   vectors persist only in the current owner's local Rewind store.
2. **Transient compute is not authority:** Gemini receives only a request needed
   to compute an embedding, returns it to the Mac, and the product stores no
   server-side screen row/vector. Failure remains truthful and retry/backfill
   semantics remain current.
3. **Owner isolation:** capture, embedding queue/in-flight result, search, frame
   load, PTT tool result, and database pool may not cross authorization
   generations.
4. **Capture before projection:** accepted frames commit through the current local
   video/OCR/SQLite path before UI/tool discovery; synthetic gauntlet success is
   not a substitute for live ScreenCaptureKit acceptance.
5. **Search combination:** UI text search reads up to 100, semantic reads up to
   50, text comes first, duplicates collapse, >0.5 semantic matches enter, and
   semantic failure does not erase text matches.
6. **PTT shared contract:** alias remains; default is at most 15 results; every
   rendered match retains date/time, app, title, internal screenshot ID, score,
   and at most 300 OCR characters.
7. **Daily recap:** six local queries, arbitrary numeric period with lower clamp
   only, and unbounded conversation/task rows remain unchanged.
8. **Local lifecycle:** active chunks, abandoned chunks, readback, DB reopen,
   rebuild, retention, excluded apps, privacy admission, permission reset, and
   recovery remain functional and data-preserving where currently promised.
9. **Exact presentation:** all IR-683–699 and IR-899–921 behavior is a contract,
   including stale, dormant, broad, reversed, spinner, request-order, shortcut,
   whitespace, and overlay quirks. S-15 is not a repair pass.
10. **Settings truth:** the nine rejected catalog IDs are absent only as assigned;
    four real Rewind entries and concrete retained controls remain searchable.
11. **No backend entrance:** both production Python apps genuinely lack POST
    `/v1/screen-activity/sync`; no deprecated/no-op handler replaces it.
12. **No backend consumer:** the model-visible backend agent roster cannot select
    a Firestore/Pinecone screen tool; local Mac tools remain distinct and intact.
13. **Deletion stays safe:** removing the obsolete screen-vector branch cannot
    make other Pinecone/GCS/canonical purges best-effort, skip them, or allow
    Firestore wipe after their required failure.
14. **No speculative compatibility:** no migration, alias, disabled provider,
    empty namespace, or feature flag survives for inherited Omi users. Historical
    records may remain labelled as history.

## 10. Target authority and ownership model

| Data / behavior | Sole durable owner | Read/mutation seam | Transient/presentation seam | Forbidden after S-15 |
|---|---|---|---|---|
| Raw screen artifacts | Owner-scoped local `RewindStorage` video/JPEG tree | `RewindIndexer`/`VideoChunkEncoder`/recovery commands | ScreenCaptureKit and Rewind frame presentation | Cloud audio/object store, upload replay, shared-backend screenshot copy |
| OCR and metadata | Owner-scoped `RewindDatabase` screenshots/FTS rows | Local GRDB queries/transactions | Rewind UI, local tools, local statistics | Firestore `screen_activity`, remote summary query |
| Embeddings | BLOB on the local screenshot row | `OCREmbeddingService` queue/backfill/write/search | Authenticated Gemini proxy returns vector only | Pinecone `ns3`, server repair/index lifecycle, direct backend-agent query embedder |
| Rewind search | Local FTS plus local vector similarity | `RewindViewModel` and `OCREmbeddingService` | List/timeline/frame loader | Backend agent/MCP search or server fallback |
| PTT screen grounding | Local Rewind DB and embedding service | `ChatToolExecutor` via canonical alias | Realtime voice model receives formatted result | Python screen tool or copied payload authority |
| Daily recap | Current owner's local GRDB tables | `ChatToolExecutor.executeDailyRecap` | Realtime voice response | Backend activity-summary product |
| Rewind preferences | Existing local settings owners/UserDefaults | Rewind Settings cards | Settings UI/search catalog | Cloud settings mirror or phantom result |
| Backend route/tool surface | No screen-history owner | Absent route and absent backend-agent tools | Genuine 404 / unavailable tool | Compatibility shell, disabled registration, hidden Firestore/Pinecone branch |

There is no new “Rewind repository” abstraction in this plan. Existing deep
local modules already own the behavior. The target design gets simpler by
removing an uncalled parallel graph, not by wrapping the surviving modules.

## 11. Ordered RED/GREEN TDD cycles

### Cycle 1 — Settings search truth without Rewind regressions

- **Behavioral RED:** Extend `SettingsSearchContractTests` through the public
  `SettingsSearchItem.allSearchableItems` catalog. Assert absence of
  `rewind.rewind`, `rewind.screencapture`, `rewind.audiorecording`,
  `transcription.settings`, `general.rewind`, `general.askomi`,
  `general.resetwindow`, `privacy.storerecordings`, and `privacy.cloudsync`.
  Assert presence of `rewind.storage`, `rewind.excludedapps`, `rewind.battery`,
  `rewind.retention`, all four concrete transcription entries, General System
  Audio/Notifications/Font Size, and the real Floating Bar visibility entry.
  Observe failure because the nine rejected IDs are currently present.
- **Why it fails now:** the static catalog still indexes phantom page-level
  labels and rejected cloud-audio controls even though the real behavior lives
  under concrete cards or another slice deletes it.
- **Minimum GREEN:** Delete only the authorized catalog items from
  `SettingsSidebar.swift`. For IR-240, do so only after the integrated S-10/IR-122
  card deletion is present; otherwise leave those two assertions/cuts to the
  recorded handoff and close this cycle only for the other seven.
- **Protected retained behavior:** Rewind page/capture/audio behavior, four
  Rewind cards, actual transcription controls, General controls, Floating Bar,
  font size, working reset command outside the stale search ID, transient STT,
  local transcripts, and PTT.
- **Expected files/tests/docs:** `Desktop/Sources/MainWindow/SettingsSidebar.swift`,
  `Desktop/Tests/SettingsSearchContractTests.swift`, and later one changelog
  fragment. Do not edit Settings content owners.
- **Focused verification:** `cd desktop/macos && xcrun swift test --package-path Desktop --filter SettingsSearchContractTests`.
- **Deletion/simplification enabled:** nine stale search records and no runtime
  implementation.
- **Stop condition:** an asserted retained ID is not present at the integrated
  HEAD, an ID maps to real behavior not covered by the IR, or IR-122's cards are
  still live for the two Privacy results.

### Cycle 2 — Retire the cloud upload entrance and writer vertically

- **Behavioral RED:** Add **new**
  `backend/tests/unit/test_s15_screen_history_retirement.py` using `TestClient`
  against the real `main.app` and `desktop_backend.app`. POST the retired path
  and require genuine 404 from both. At the same public route surface assert the
  neighboring Gemini proxy route remains registered in both apps and retains
  auth behavior, plus retained desktop health/chat/realtime routes keep their
  existing status contracts. Observe failure because both apps mount the upload.
- **Why it fails now:** `desktop_screen_activity.router` remains registered and
  still writes Firestore/Pinecone despite having no Mac producer.
- **Minimum GREEN:** Remove the router import/registration from both apps, delete
  `backend/routers/desktop_screen_activity.py`, remove its route-policy row and
  screen parity-pack call/documentation, replace the old upload-success test,
  and update `desktop/macos/test.sh`. Keep `desktop_proxy.router`, its Gemini
  actions/models/auth/rate/paywall behavior, and shared `SurfaceParityCapture`.
- **Protected retained behavior:** authenticated single/batch embedding proxy,
  all local embedding storage/similarity, desktop health/chat/realtime routes,
  and shared parity capture for surviving surfaces.
- **Expected files/tests/contracts/docs:** both app entrypoints, route policy,
  router deletion, old/new tests, test runner, parity-pack README and possibly
  retargeted shared adapter test. App-client OpenAPI/generated Swift should have
  no content diff; run checks to prove it.
- **Focused verification:** `cd backend && .venv/bin/python -m pytest -q tests/unit/test_s15_screen_history_retirement.py tests/unit/test_desktop_proxy.py tests/unit/test_surface_parity_capture.py` plus route-policy/OpenAPI checks in Section 14.
- **Deletion/simplification enabled:** the only upload entrance, request models,
  paywall wrapper used only by it, parity source label, route manifest row, and
  exclusive upload tests.
- **Stop condition:** a supported released client or refreshed production caller
  still sends the route, or the route cannot be removed without altering the
  retained Gemini proxy.

### Cycle 3 — Remove every backend-agent/cloud read path

- **Behavioral RED:** Change the public model-visible tool-roster expectation in
  `test_prompt_cache_integration.py` to omit exactly
  `get_screen_activity_tool` and `search_screen_activity_tool` while preserving
  the exact remaining cached order. Add/extend a focused backend-agent contract
  asserting neither tool can be resolved or receives a display status. Observe
  failure because both are in `CORE_TOOLS` and exports. Separately run the
  unchanged Mac manifest/alias tests as the retained fence.
- **Why it fails now:** normal backend agentic Chat can still select Firestore/
  Pinecone screen readers even though the Mac owns Rewind and has its own tools.
- **Minimum GREEN:** Delete `screen_activity_tools.py`; remove its two imports,
  exports, `CORE_TOOLS` registrations, and display entries; delete its exclusive
  timezone/result-bound tests; delete `gemini_embed_query` and its exclusive
  model-inventory entry. Remove only now-dead imports/helpers.
- **Protected retained behavior:** remaining backend-agent tools and prompt-cache
  order; backend web/file/memory/conversation/task tools; local Mac
  `search_screen_history` alias, `semantic_search`, `get_daily_recap`, generated
  executors/capabilities, owner fencing, and transient desktop proxy.
- **Expected files/tests/contracts/docs:** retrieval tool module deletion,
  `tools/__init__.py`, `agentic.py`, `clients.py`, model inventory, prompt-cache
  tests, exclusive screen tool tests, and `backend/AGENTS.md` retrieval list.
  Because the tool expectation changes with code, the implementation PR must
  cite IR-011/deletion-map as its external source as required by test policy.
- **Focused verification:** `cd backend && .venv/bin/python -m pytest -q tests/unit/test_prompt_cache_integration.py tests/unit/test_llm_gateway_coverage_guardrails.py` and `cd ../desktop/macos && ./scripts/test-tool-surfaces.sh && ./scripts/agent-logic-harness.sh && xcrun swift test --package-path Desktop --filter AuthorizedToolExecutionTests`.
- **Deletion/simplification enabled:** backend reader module, Firestore/Pinecone
  lookup formatting, direct Gemini query embedder, model-purpose inventory,
  reader-only tests, exports, and status labels.
- **Stop condition:** any non-screen tool depends on an exclusive helper being
  deleted, or the Mac local tool contract changes in the diff.

### Cycle 4 — Delete stored-copy/index/deletion-hook ownership and close residue

- **Behavioral RED:** Adapt `test_account_deletion.py` and
  `test_delete_account_purge_storage.py` at the public purge result/call seam:
  screen rows/vectors are no longer enumerated or required, no
  `screen_activity_vectors` failure is reported when the Pinecone index is
  unavailable, while conversation/transcript/memory/action-item vectors,
  recordings, canonical data, and Firestore-wipe fail-closed ordering remain
  exact. Observe failure because the current service calls the screen branch.
  Supplement this with a labelled static manifest tripwire requiring the
  generated Firestore index list to contain no `screen_activity` collection;
  that tripwire fails now but is not the behavioral RED.
- **Why it fails now:** account deletion and manifests still treat the rejected
  Firestore/Pinecone copy as live product data, which keeps the database module,
  `ns3`, composite index, stubs, and docs alive.
- **Minimum GREEN:** Remove the screen imports/try block from account deletion,
  delete `database/screen_activity.py`, delete only the screen section and `ns3`
  constant/functions from `vector_db.py`, remove the Firestore registry
  requirement, regenerate `firestore.indexes.json`, adapt import-isolation
  stubs/comments/tests, and remove remaining current docs/config references.
  Preserve generic recursive subcollection deletion so any old document still
  disappears during a full user wipe.
- **Protected retained behavior:** all other required account-deletion purges and
  their failure isolation/order; other Pinecone namespaces/client/config;
  generic Firestore user deletion; local Rewind retention/deletion/rebuild;
  local vectors; Typesense/Pinecone shared ownership reserved for S-24.
- **Expected files/tests/contracts/docs:** account-deletion service/tests,
  screen database deletion, exact `vector_db.py` section, registry and generated
  JSON, Firestore manifest test, broad import-stub tests, `backend/AGENTS.md`,
  `backend/database/users.py` comment, changelog fragment, and residue-only docs.
- **Focused verification:** account-deletion tests plus
  `python3 backend/scripts/generate_firestore_indexes.py`,
  `test_firestore_index_config.py`, and residue searches from Section 13.
- **Deletion/simplification enabled:** last repository copy/read/delete/index
  owners, `ns3`, stale import stubs/comments, and exclusive docs/tests.
- **Stop condition:** another current caller uses `database.screen_activity` or
  the screen vector functions; another domain uses `ns3`; generated index output
  diverges beyond the one registry removal; or a proposed edit deletes shared
  Pinecone/Typesense configuration assigned to S-24.

After each cycle: record the observed RED output, make the minimum GREEN, run
its focused command, inspect `git diff`, run its residue subset, and commit that
vertical surface before beginning the next RED. Existing green keep fences do
not count as RED. After Cycle 4, perform a separate simplification/review pass;
it may delete newly dead imports/comments/tests but may not introduce behavior.

## 12. Cross-slice ownership and handoffs

| Slice | S-15 consumes or hands off |
|---|---|
| S-01 | Consumes deletion of VM screenshots/AgentSync. Any reappearance returns to S-01; S-15 does not own VM lifecycle. |
| S-06 | Consumes hosted/public MCP deletion and preserves the private local runtime/tool transport. |
| S-10 | Consumes IR-122 deletion before removing IR-240's two Privacy search entries. Conversation audio, Store Recordings, Private Cloud Sync state/routes/fields are S-10. |
| S-14 | Publishes unchanged local screenshot/context and canonical capture-health seams for proactive assistants. S-15 does not change them. |
| S-19 | Hands off a proven local `search_screen_history` and `get_daily_recap` contract for final PTT reconnection/closure; S-19 must not restore a backend screen tool. |
| S-21 | Hands off seven/nine exact removed search IDs and otherwise unchanged Rewind settings/navigation. S-21 owns later shell convergence, not S-15 Rewind redesign. |
| S-22 | Hands off retained transient Gemini embedding proxy/model purpose as explicit managed compute with no product-data persistence. |
| S-23 | Hands off zero screen-history route/schema owner. Generic rejected product-data cleanup must not recreate screen-specific enumeration. |
| S-24 | S-15 removes only screen-specific Pinecone `ns3`; S-24 removes the remaining shared Pinecone/Typesense dependencies, env, secrets, repair paths, alerts, and infrastructure after final callers leave. |
| S-28 | Hands off unchanged owner-local Rewind schema/files. S-28 owns installation/storage namespace migration; S-15 must not rename or move local stores. |
| S-30 | Hands off truthful local/transient/cloud boundary and historical-copy classification for final privacy/legal copy. |
| S-31 | Hands off repository residue proof, named-bundle evidence, and separately tracked live Firestore/Pinecone closure. |

Shared-file collision rules: rebase before editing `SettingsSidebar.swift`, both
backend app registries, `vector_db.py`, account deletion, Firestore registry,
route policy, prompt-cache expectations, and component guides. Remove only the
S-15 rows/branches. If another slice has already removed one, record it as
integrated predecessor work and do not reintroduce it for a ceremonial diff.

## 13. Exact repository residue-search strategy

Run at entry, after the owning GREEN, and at final closure. Use `git grep` for
tracked closure and `rg` for working-tree discovery. Every final hit must be
classified as retained local behavior, shared later-slice infrastructure,
historical release/provenance, bootstrap planning, or a defect.

```bash
# Live Python upload, persistence, readers, namespace, and deletion hook
git grep -n -I -E 'desktop_screen_activity|/v1/screen-activity/sync|desktop_screen_activity_sync|database\.screen_activity' -- . ':(exclude)bootstrap-scaffold/**' ':(exclude)desktop/windows/**'
git grep -n -I -E 'SCREEN_ACTIVITY_NAMESPACE|upsert_screen_activity_vectors|search_screen_activity_vectors|delete_screen_activity_vectors|screen_activity_vectors' -- backend firestore.indexes.json ':!backend/tests/unit/test_s15_screen_history_retirement.py'
git grep -n -I -E 'get_screen_activity_tool|search_screen_activity_tool|gemini_embed_query|gemini_screen_activity_query_embedding' -- backend ':!bootstrap-scaffold/**'
git grep -n -I -E 'collectionGroup.*screen_activity|collection\("screen_activity"\)|screen_activity_app_timestamp' -- backend firestore.indexes.json

# Tool/config/deploy surfaces that must be absent or explicitly handed off
rg -n -i 'screen.?activity|screen history|ns3' backend .github firestore.indexes.json --glob '!tests/**' --glob '!**/changelog/**'
rg -n -i 'screen.?activity|screen history|ns3' backend/deploy backend/charts .github/workflows 2>/dev/null
rg -n -i 'typesense|pinecone|PINECONE' backend .github --glob '!**/tests/**'

# Mac upload must stay absent; local results are expected and classified
git grep -n -I -E 'ScreenActivitySyncService|/v1/screen-activity/sync|desktop_screen_activity_sync' -- desktop/macos ':!desktop/macos/CHANGELOG.json' ':!desktop/macos/changelog/releases/**'
rg -n 'search_screen_history|semantic_search|get_daily_recap|RewindDatabase|OCREmbeddingService' desktop/macos/Desktop desktop/macos/agent

# Exact Settings-search closure and retained catalog
rg -n 'general\.(rewind|askomi|resetwindow)|rewind\.(rewind|screencapture|audiorecording)|transcription\.settings|privacy\.(storerecordings|cloudsync)' desktop/macos/Desktop desktop/macos/Desktop/Tests
rg -n 'rewind\.(storage|excludedapps|battery|retention)|transcription\.(languagemode|voicelanguages|vocabulary|vadgate)' desktop/macos/Desktop/Sources/MainWindow/SettingsSidebar.swift desktop/macos/Desktop/Tests/SettingsSearchContractTests.swift

# Generated/released contract and repository scope
git grep -n -I '/v1/screen-activity/sync' -- backend/docs desktop/macos/Desktop/Sources/Generated
git status --short
git diff --name-only origin/main...HEAD
git diff --check
```

Expected retained results:

- Mac `screen history`, `semantic_search`, `search_screen_history`, local
  screenshot tables, OCR, `RewindDatabase`, and embedding proxy references;
- shared Pinecone/Typesense infrastructure with named S-24 owners, but no
  screen-specific `ns3` branch;
- `backend/database/users.py` generic recursive deletion without a live screen
  module dependency;
- historical files under changelog/releases, `FORK.md`, git history, and the
  bootstrap requirements/deletion plans. Do not falsify history or “fix” the
  stale Rewind overlay docs protected by IR-906;
- the new route-retirement test may contain the retired literal so absence stays
  guarded. Its name/comment must label why it remains.

No current production/config/test hit may be dismissed as “known residue.” The
final implementation PR includes a small ledger mapping every nonempty hit to
one of the allowed owners above.

## 14. Focused and component verification commands

### Focused macOS and local-agent tests

```bash
cd desktop/macos
xcrun swift test --package-path Desktop --filter SettingsSearchContractTests
xcrun swift test --package-path Desktop --filter RewindArtifactGauntletTests
xcrun swift test --package-path Desktop --filter RewindAbandonedChunkRecoveryTests
xcrun swift test --package-path Desktop --filter RewindDatabaseLifecycleTests
xcrun swift test --package-path Desktop --filter RewindRetentionCleanupTests
xcrun swift test --package-path Desktop --filter RewindSearchQueryExpansionTests
xcrun swift test --package-path Desktop --filter OCREmbeddingServiceOwnerResetTests
xcrun swift test --package-path Desktop --filter ScreenPrivacyExclusionTests
xcrun swift test --package-path Desktop --filter ScreenRecordingPermissionPolicyTests
xcrun swift test --package-path Desktop --filter AuthorizedToolExecutionTests
./scripts/test-tool-surfaces.sh
./scripts/agent-logic-harness.sh
```

### Focused backend and generated-contract tests

```bash
cd backend
.venv/bin/python -m pytest -q \
  tests/unit/test_s15_screen_history_retirement.py \
  tests/unit/test_desktop_proxy.py \
  tests/unit/test_prompt_cache_integration.py \
  tests/services/users/test_account_deletion.py \
  tests/unit/test_delete_account_purge_storage.py \
  tests/unit/test_delete_account_stripe_cancel.py \
  tests/unit/test_desktop_transcribe.py \
  tests/unit/test_firestore_index_config.py \
  tests/unit/test_surface_parity_capture.py

python3 scripts/generate_firestore_indexes.py
scripts/openapi_runner.sh scripts/route_policy_inventory.py \
  --manifest route_policy_manifest.yaml --check --enforce-missing-baseline
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
```

If the Firestore registry change is made, run
`python3 backend/scripts/generate_firestore_indexes.py --write` once from the
repository root, inspect the exact JSON diff, then use the no-flag check above.
Never hand-edit generated index JSON. The **new** route-retirement test path
becomes valid in Cycle 2; remove the old hardcoded test runner path in the same
GREEN.

### Component and repository gates

```bash
cd desktop/macos
xcrun swift build -c debug --package-path Desktop
bash test.sh

cd ../../backend
bash test-preflight.sh
bash test.sh

cd ..
python3 bootstrap-scaffold/validate-requirements-ledger.py
make preflight
scripts/pr-preflight --suggest
git diff --check
```

Before drafting any `fix:` PR, follow the failure-class declaration from
`scripts/pr-preflight --suggest`, write the PR body to a file, and run
`scripts/pr-preflight --pr-body-file <file>`. S-15 is planned as architectural
deletion around a local authority; do not call it a bug fix merely to avoid
describing the deletion. Verification evidence records commands and results in
the commit/PR description.

## 15. Named-bundle user-path acceptance

Never run, stop, or restart `/Applications/Omi.app` or `Omi Beta.app`. Use one
isolated non-production named bundle and its isolated local store:

```bash
cd desktop/macos
OMI_APP_NAME=omi-s15-rewind-local OMI_SKIP_TUNNEL=1 ./run.sh --full
./scripts/omi-macos-dev doctor
./scripts/omi-ctl wait-ready
./scripts/omi-ctl health
./scripts/omi-ctl screens
./scripts/omi-ctl state
```

Acceptance records both hermetic and real behavior:

1. Run `./scripts/omi-ctl action rewind_artifact_recovery_gauntlet`. Require
   protected frame blocked, zero protected rows, two persisted frames, red/green
   readback, database reopen, row survival, two-row cleanup, and artifact-file
   removal. Label this synthetic persistence/recovery evidence, not live capture.
2. Run `./scripts/omi-ctl navigate rewind` and
   `./scripts/omi-ctl action rewind_settings_snapshot`. Verify full-page Rewind,
   selected today, exact permission/empty/error state for current environment,
   Storage/Excluded Apps/Battery/Retention, gear navigation, Capture toggle,
   health, and the reviewed advertised shortcut mismatch. Do not “correct” stale
   overlay wording.
3. With Screen Recording permission granted in the named bundle, produce real
   ScreenCaptureKit activity in two safe test apps. Wait for capture/OCR/video,
   confirm new local timeline frames, drag/scroll/arrow navigation, selected
   frame preservation during a new capture, app/window grouping, and video frame
   readback. Avoid sensitive windows and record sanitized evidence only.
4. Search a unique visible test phrase. Verify grouped list first, switch to
   timeline and back, open by mouse, and verify the expected local result. Search
   a phrase that has text matches while the Gemini proxy is deliberately
   unavailable; text results must remain. A new semantic embedding may fail
   truthfully, but no Python screen-history reader may answer.
5. Exercise zero results, whitespace-only input, past/future date, inclusive-day
   behavior, quiet refresh, thumbnail/frame failure, and recovery/rebuild screens
   only through safe test fixtures/bridge controls. Record the current reviewed
   behavior; do not turn acceptance into a repair task.
6. Through an authenticated natural PTT utterance, ask what was visible in the
   unique test app/phrase. Inspect tool evidence to prove alias
   `search_screen_history` resolved locally and the result includes date/time,
   app, title, internal ID, score, and no more than 300 OCR characters, with no
   more than 15 default matches.
7. Ask PTT for today and a multi-day recap. Verify the local six-section result
   from current GRDB data and exercise a large numeric `days_ago` through the
   authorized tool harness to prove no maximum clamp and unbounded conversation/
   task rows.
8. Restart the same named bundle with `./scripts/omi-ctl action quit_and_reopen`.
   Prove timeline/search/local embeddings/settings persist and recovery remains
   clean. Switch between two development accounts and prove no row/result leaks.
9. Point the product-data backend to a controlled unavailable endpoint while
   preserving cached auth/local database access. Timeline, text search, stored
   vector search, retention and existing artifacts must remain local. New
   embedding compute may report unavailable; there must be no attempt to POST
   `/v1/screen-activity/sync` or call a backend screen tool.
10. Capture the named bundle log path with `./scripts/omi-ctl log-path` and search
    the bounded acceptance interval for the retired route/tool names. Record only
    sanitized counts/paths; never attach OCR/private content.

Where available, run the existing e2e runner for
`rewind-artifact-recovery.yaml`, `rewind-settings.yaml`, `rewind.yaml`, and
`screen-recording-permission.yaml` using the procedures in
`desktop/macos/e2e/SKILL.md`. Manual `rewind.yaml` remains manual. The real PTT
and ScreenCaptureKit paths are mandatory because compilation and the synthetic
gauntlet cannot prove them.

## 16. Repository closure versus live operational closure

### Repository closure required in the implementation PR

- both Python app objects lack the upload route and retain the embedding proxy;
- backend agent roster lacks both cloud screen tools while the local Mac manifest
  and generated tool contract retain local search/recap;
- Firestore/Pinecone screen writer, reader, `ns3`, index, deletion hook, direct
  query embedder, route policy, exclusive tests/docs/config are absent;
- app-client OpenAPI and generated non-Windows Swift are checked and show no
  binding/residue; no compatibility route is added;
- shared Pinecone/Typesense infrastructure is explicitly handed to S-24 and not
  deleted early;
- Settings search exact removals/presence checks are green with IR-122 ordering;
- focused, component, preflight, residue, named-bundle, real capture, and PTT
  evidence is recorded;
- `backend/AGENTS.md` moves with the service-map change and one valid JSON
  fragment under `desktop/macos/changelog/unreleased/` describes the user-visible
  truth. `PRODUCT.md` already states local Rewind; edit it only if the final diff
  makes it incomplete.

### Live operational closure — separately authorized and evidenced

The planning and implementation tasks do not authorize any external mutation.
Before any delete/deploy, a named operator must identify the exact owned dev and
production projects/services from current deployment configuration, then record
read-only evidence for:

1. request counts, principals, versions, and last-seen traffic for
   `POST /v1/screen-activity/sync` in every live Python service/revision;
2. Firestore counts/owners/retention for every
   `users/{uid}/screen_activity/{document}` collection and whether any document
   belongs to this unreleased fork's controlled test population;
3. Pinecone index identity, namespace statistics and vector count for `ns3`,
   plus confirmation that no other workload shares that namespace;
4. deployed Firestore composite index state and the approved index-removal
   mechanism;
5. any dev parity-pack cassettes, backups/exports, logs, dashboards, alerts, or
   data-retention systems that captured screen-activity payloads;
6. current deployed backend-agent tool roster and current Mac-client version
   population, even though the repository has no producer.

After explicit data-deletion/deploy authorization and policy review, close in
this order: stop/remove producer and reader code by deploying the merged commit;
verify route 404 and tool absence on the deployed revision; observe a defined
quiet window; delete only the confirmed `ns3` vectors and owned Firestore screen
documents; remove the live composite index; apply approved log/cassette retention
actions; verify zero remaining copy/read path. Never delete an entire Pinecone
index or Firestore user tree in S-15. Do not guess project, service, index, backup,
or scheduler names from repository strings.

Repository closure may be ready while live closure remains an explicitly owned
follow-up. The final status must say which one is complete. “No current Mac
producer” is useful evidence, not proof that old cloud copies are absent.

## 17. Risks, gates, and explicit stop points

| Risk | Gate / mitigation | Stop when |
|---|---|---|
| Baseline trails `origin/main` or shared Wave 2 files | Rebase, record execution SHA, rerun exact ledger and callers | A path/owner differs and the plan would overwrite another slice |
| S-01/S-06 predecessor regression | Route/MCP/VM residue audit before Cycle 2 | VM or hosted MCP screen path exists; return it to predecessor owner |
| IR-240 races IR-122 | Check underlying Privacy cards/state first | Search removal would hide a still-live owned control or S-15 would need to delete conversation-audio behavior |
| Released client still uploads | Compare released OpenAPI/tags and traffic; no compatibility shell | Any supported client contract still contains the route without an adopted sunset/version decision |
| Local vs cloud tool name confusion | Treat Mac manifest/executor and Python agent registry as separate public surfaces | A diff removes `search_screen_history`, `semantic_search`, or `get_daily_recap` from Mac |
| Transient proxy mistaken for cloud authority | Protect `desktop_proxy` route/model/auth tests and local vector write evidence | A change removes proxy compute or persists its request/result server-side |
| Local Rewind redesign sneaks into deletion | No Mac production edits beyond search catalog; exact IR keep ledger | Capture/OCR/storage/search/UI code needs modification |
| Pinecone over-deletion | Delete only `ns3` functions/constants; inventory all namespaces/callers | Shared client/dependency/env/secret is touched before S-24 |
| Account deletion is weakened | Behavioral required-failure/order tests for all surviving stores | Another purge becomes best-effort, is skipped, or Firestore wipe proceeds after failure |
| Generic old Firestore docs become undeletable | Preserve recursive subcollection deletion | Removal requires special-casing or weakening generic account wipe |
| Firestore manifest is hand-edited | Registry first, deterministic generator, exact diff | Generated JSON differs beyond expected registry output |
| Static residue test masquerades as behavior | Label manifest/source scans and supplement with route/purge/tool tests | A cycle's only RED is source text/order |
| Dormant/stale reviewed behavior is “cleaned up” | IR-691–695 and IR-899–921 explicit no-edit list | Review proposes fixing or deleting a protected quirk |
| Synthetic gauntlet mistaken for E2E | Separate real ScreenCaptureKit and PTT named-bundle evidence | Real user path was not exercised |
| Old cloud data is assumed absent | Separate live inventory/quiet window/operator evidence | Anyone claims full closure from repository search alone |
| Sensitive OCR leaks into evidence | Use safe test apps/phrases, sanitized logs/counts only | Evidence contains screenshots, raw OCR, tokens, user IDs, or API responses |
| Scope expands to whole Typesense/Pinecone or storage identity | Explicit S-24/S-28 handoff | Shared infra or local directory names enter the diff |
| Live mutation exceeds authorization | Section 16 is proposal-only until explicit approval | A command would deploy, delete data/indexes/backups/logs, or change traffic |

## 18. Final completion checklist

### Requirements and scope

- [ ] All 57 assigned IRs have implementation or protection evidence in this
  plan, the execution ledger, and the PR.
- [ ] Execution SHA, `origin/main` merge-base, S-01/S-06 and IR-122 dependency
  state, requirements-validator output, released-contract check, and caller
  inventory are recorded.
- [ ] No Windows edit, migration for inherited Omi users, compatibility shell,
  deprecated alias, upload outbox, cloud fallback, or speculative abstraction
  was added.
- [ ] Only S-15-owned behavior changed; shared Pinecone/Typesense, audio controls,
  shell, local namespace, and final privacy/release work have named handoffs.

### Retained local Rewind

- [ ] Real ScreenCaptureKit capture reaches local video/OCR/GRDB and survives
  restart; the hermetic artifact/recovery gauntlet is separately green.
- [ ] Owner switching/in-flight embedding cannot cross-write or cross-read.
- [ ] Selected day, 500 sampling, text+semantic combination/fail-open, grouping,
  list/timeline, navigation, frame failure, rebuild, retention, exclusions,
  battery, Storage, permission, recovery, and exact empty/error states remain.
- [ ] Every reachable/dormant/stale quirk in IR-683–699 and IR-899–921 is
  unchanged, including shortcut/overlay mismatch and developer exports.
- [ ] Gemini single/batch embedding proxy remains authenticated/transient;
  returned vectors and similarity remain local only.
- [ ] `search_screen_history` alias and default 15-result/300-character payload
  are proven through real PTT; `get_daily_recap` remains six-query, arbitrary-
  period, and unbounded for conversations/tasks.

### Cloud deletion

- [ ] Both Python app objects return genuine 404 for the upload and keep the
  retained proxy/health/chat/realtime contracts.
- [ ] Firestore writer/reader/summary/ID enumeration and Pinecone `ns3`
  upsert/search/delete are absent from current code.
- [ ] Backend-agent tool roster, exports, display text, direct query embedder,
  model inventory, exclusive tests, and docs contain no cloud screen reader.
- [ ] Account deletion has no screen-vector prerequisite and still fails closed
  for every surviving required store in the correct order.
- [ ] Firestore index registry/generated JSON, route policy, parity screen row,
  test runner, stubs, comments, generated clients, and component guide are clean.
- [ ] No current hosted MCP, VM, Typesense screen path, GCS/Redis copy, job,
  workflow, alert, metric, or exclusive secret/config exists.

### Settings, verification, and closure

- [ ] Exact S-15 search IDs are absent and all named retained IDs are present;
  IR-240 landed only after IR-122's underlying controls.
- [ ] Every cycle's intended behavioral RED was observed before minimum GREEN;
  static tripwires are labelled and not used as behavioral substitutes.
- [ ] Focused desktop/backend tests, tool generation/harness, Firestore generator,
  route policy, OpenAPI/generated Swift checks, desktop debug build/component
  suite, backend preflight/component suite, requirements validator,
  `make preflight`, PR preflight, and `git diff --check` are green.
- [ ] Named bundle `omi-s15-rewind-local` exercised real capture, local search,
  semantic-failure text fallback, settings, recovery, retention, restart,
  two-owner isolation, backend-unavailable behavior, and natural PTT without
  touching production bundles or leaking private evidence.
- [ ] Section 13 searches are empty or every hit has a precise retained/shared/
  historical/planning owner; no unexplained current residue remains.
- [ ] `backend/AGENTS.md`, generated contracts/manifests, and one valid desktop
  changelog fragment moved with behavior; protected historical/stale docs remain.
- [ ] Independent Standards and Spec Compliance review found no actionable issue,
  and all resulting fixes/checks were rerun.
- [ ] Repository closure and live operational closure are reported separately;
  live route traffic, Firestore documents, Pinecone `ns3`, deployed index,
  backups/logs/cassettes, and deletion approvals each have a named owner/evidence.
- [ ] Final `git status --short` and fixed-point diff prove the implementation PR
  contains intentional S-15 files only; for this planning task, only
  `bootstrap-scaffold/wave-2/s-15 tdd.md` changed.
