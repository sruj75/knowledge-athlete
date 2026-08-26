# Wave 4 / S-24 TDD Plan — Delete hosted search, vector, and product-object authority

## 1. Slice identity

| Field | Value |
|---|---|
| Wave | 4 — delete cloud products that have lost their final callers |
| Slice | S-24 |
| Type | Infrastructure deletion after local search authority |
| Plan name | Delete hosted search, vector, and product-object authority |
| Future acceptance bundle | `omi-wave4-s24` (`com.omi.omi-wave4-s24`) |
| Primary decisions | IR-011, IR-044, IR-053, IR-093, IR-095, IR-256, IR-291, IR-806, IR-807, IR-808, IR-809 |
| Implementation order | After S-19 and closed S-23 are integrated; before S-25. S-23 may leave only the exact Pinecone account-purge handoff owned here. |

This is an implementation-ready deletion plan, not implementation. It deliberately
splits Typesense, Pinecone, OpenAI Files/cloud attachments, transient voice-object
staging, and the remaining product-data GCS surface into independently provable
cycles. Windows is excluded.

## 2. Planning status and pinned baseline

Planning was performed on 2026-08-21 against the exact completed Wave 2 closeout:

| Evidence | Observed planning state |
|---|---|
| Required ancestor | `git merge-base --is-ancestor 711269baf5e653bd62132688998732207f11dd3c HEAD` exited 0 |
| `HEAD` | `711269baf5e653bd62132688998732207f11dd3c` |
| Branch | `audit-wave-2-slices...origin/audit-wave-2-slices` |
| Product delta after closeout | none: both `git log 711269..HEAD` and `git diff --stat 711269..HEAD` were empty |
| Worktree before planning | clean |
| Requirements proof | `python3 bootstrap-scaffold/validate-requirements-ledger.py` passed: 714 indexed rows, 714 detailed sections, all reviewed |

No conflict was found between the assigned detailed decisions in
`requirements-challenge.md` and the S-24 brief in `deletion-map.md`. The current
tree is intentionally a **pre-S-19/pre-S-23 inventory**. It proves the deletion
targets and retained siblings, but it is not an executable starting point for
the cycles below.

**Status:** per-slice repository acceptance is closed by section 19; the stricter
combined Waves 3–4 closeout remains open. The text
below preserves the historical planning baseline; section 19 owns the final
implementation and acceptance evidence.

## 3. Outcome

After repository implementation:

1. Conversation, Memory, task, and Rewind search execute only against their
   owner-scoped Mac stores, FTS indexes, and local vectors. Deleting or replacing
   a local record updates the corresponding local index atomically.
2. The backend supplies only bounded transient compute whose result owner is a
   local Mac store. It owns no private search corpus, vector index, graph, Chat
   attachment, audio corpus, or other product-object store.
3. Typesense, its conversation collection/search adapter, local development
   runtime, dependencies, variables, secrets, tests, docs, and deployment
   residue are absent.
4. Pinecone, every remaining namespace (`ns1`, `ns_tchunks`, and any refreshed
   orphan such as `ns_x`), repair/index lifecycle, dependencies, variables,
   secrets, tests, docs, and deployment residue are absent.
5. `POST /v1/files`, `FileChatTool`, OpenAI Files/Assistants/file-search state,
   Firestore file metadata, and GCS thumbnails are absent. The route is genuinely
   unregistered, not a 410/no-op/compatibility response.
6. Retained voice-message transcription sends validated request bytes directly
   to the fixed managed pre-recorded STT adapter; it does not upload a temporary
   customer-audio object to GCS.
7. No private product-data GCS code/config remains. The signed desktop
   update/preview bucket and its release workflows remain the sole retained GCS
   product boundary; S-24 does not rename it.
8. Account deletion and export retain their authoritative durable lifecycle and
   fail-closed guarantees without enumerating already-deleted Pinecone, hosted
   file, recording, or product-object copies.
9. Redis remains only for ephemeral OAuth, rate/fair-use enforcement, locks,
   and bounded caches. S-24 neither deletes Redis nor permits product content or
   synchronization state to move into it.

Repository closure is distinct from deleting live provider resources or data.

## 4. Authorizing requirements

The live detailed decisions, not historical implementation, authorize the plan:

| Decision | Required S-24 interpretation and proof |
|---|---|
| IR-011 | The local Rewind GRDB/OCR/vector authority remains. The already-deleted Firestore/Pinecone screen copy must not reappear; global Pinecone removal must not touch local Rewind. |
| IR-044 | Ordinary Chat attachments remain explicit, app-managed, owner/chat-scoped local files with the four-file limit, durable managed URIs, previews, source-file safety, and reference-aware GC. Delete cloud upload/OpenAI Files/GCS/Firestore copies. |
| IR-053 | Keep the authenticated Gemini embedding proxy as bounded transient compute. Persist vectors and run similarity only in local owners; never store text/vector product authority in the backend. |
| IR-093 | Preserve semantic conversation recall by consuming S-19's local keyword-plus-vector implementation: title/overview keyword match, local conversation vectors, keyword-first dedupe, date bounds, limit/result shape, and no cloud fallback. |
| IR-095 | Preserve semantic Memory recall through `MemorySemanticRecall` and owner-local `memory_embeddings`; the backend embedding response is transient only. |
| IR-256 | Brain Map and the complete knowledge-graph product remain deleted. Any refreshed hosted graph/vector consumer is deletion residue, not authorization to create a local graph generator. |
| IR-291 | Preserve the exact nullable local `MemoryRecord.screenshotId` relationship/index and its `ON DELETE SET NULL` behavior. It is not UI, cloud sync, or a second Rewind authority. |
| IR-806 | Delete Typesense completely while retaining local FTS5 and local vectors. |
| IR-807 | Delete Pinecone completely, including all namespaces, configuration, credentials, and lifecycle/repair behavior. |
| IR-808 | Keep one Redis only for ephemeral control-plane state: OAuth, rate/fair-use enforcement, locks, and bounded caches. Do not delete it and do not relocate product content/search/sync into it. |
| IR-809 | Delete product-data GCS paths. Keep one desktop update/preview bucket; S-29 later re-owns/rebrands release identity. |

The test expectation changes in this slice must cite these decisions and the
deletion map as the external contract required when code and tests change in the
same PR.

## 5. Dependencies and execution entry gates

### Gate 0 — mandatory rebase and predecessor proof

Before Cycle 1, the implementer must:

1. Run the repository-required setup on the implementation worktree, fetch the
   current `origin/main`, rebase/fast-forward the feature work onto the revision
   containing S-19 and closed S-23, and record their merge commits. Never reproduce a
   predecessor in S-24 and never add a temporary remote fallback.
2. Rerun the ledger validator and baseline/status commands. Stop on an
   unreviewed requirement, a decision-map conflict, or unrelated dirty files.
3. Read the integrated S-19 and S-23 plans, PR evidence, changed tests, and
   component guides. Refresh every search in sections 6, 7, and 13.
4. Produce a checked-in/PR-body caller matrix with one row per remaining
   Typesense, Pinecone, OpenAI Files, and GCS symbol/config key. Each row must be
   retained, deleted in a named S-24 cycle, or handed to a named later owner.

### Required predecessor shape

| Predecessor | Shape S-24 consumes | Blocking evidence |
|---|---|---|
| S-10 | `omi.db`/GRDB is conversation/transcript authority; local deletion is atomic; public hosted conversation CRUD/playback is gone or explicitly handed onward. | Local query, restart, archive, delete-cascade, and owner-isolation tests pass. |
| S-11 | Ordinary Chat journal/catalog and attachment bytes are owner-local; `/v2/files` and cloud upload waits are gone; only the explicitly handed-off `/v1/files` family may remain for S-24. | `LocalChatAttachmentStoreTests` and journal restart/GC tests pass without backend object IDs. |
| S-12 | Memory lifecycle, literal search, semantic vectors, and deletes are local; backend Memory compute is proposal-only. | Local Memory offline/restart/owner-generation tests pass. |
| S-13 | Task vectors/index lifecycle are local. | Local task semantic/dedup/delete tests pass without Pinecone. |
| S-15 | Rewind OCR, FTS, screenshot vectors, and search are local; Pinecone `ns3` and cloud readers are already absent. | Rewind artifact/search and screenshot-link tests pass. |
| S-19 | `get_conversations`, `search_conversations`, and transcript retrieval used by PTT execute through the final local conversation owner, preserving both realtime providers and the reviewed tool contract. | A natural authenticated PTT search works with backend product-search endpoints unavailable; actual integrated local symbols/tests are inventoried rather than guessed from this baseline. |
| S-23 | Rejected hosted products, writers/readers, schemas, and product-specific jobs are gone. Conversation vector writers, cloud audio/playback, speech identity, hosted Chat/file consumers, and graph consumers leave no live workload. The only permitted provider cleanup is the exact Pinecone account purge/counter seam handed to S-24. | Route/storage/job matrix and genuine-absence tests pass; the account-deletion contract names only the exact Pinecone handoff. Any S-25-only deployment remains content-free and imports no product-object helper. |

All eight cycles are blocked until S-19 and closed S-23 are integrated. If S-23
leaves a product writer, reader, job, schema, hosted-file consumer, or cleanup branch
other than the exact Pinecone purge/counter seam, stop: S-24 may not break a live
workload, keep a drain-only compatibility shell, or absorb another product owner.

### Released-contract and external-input gates

- Recheck checked-in OpenAPI, generated non-Windows clients, release tags, and
  supported-client policy for `/v1/files` and hosted tool search. This fork is
  unreleased, but evidence must establish that no supported contract needs a
  sunset. Stop rather than returning fake success or adding a deprecated alias.
- Live provider/project identity, resource names, retention/legal obligations,
  and current contents are unknown by design. They block only the separately
  authorized operational phase, not repository deletion.
- `BILLING_MODE=disabled` remains fixed. No Dodo/Stripe transaction, entitlement,
  paywall, or S-18 acceptance belongs here.

## 6. Verified current production codeflow

This section describes the pinned **predecessor-unintegrated** baseline. Paths
that must disappear under S-19/S-23 are evidence leads, not work S-24 may copy.

### Retained local owners and the remaining PTT gap

1. `ConversationRepository` reads/writes the local conversation owner;
   `ConversationLocalQueryTests` proves current title/overview local search and
   `ConversationDeletionCascadeTests` proves exact descendant deletion. At this
   baseline that search is not yet the full IR-093 semantic PTT contract.
2. `ChatToolExecutor.swift` handles `search_memories` through
   `MemorySemanticRecall.shared`, whose query vector comes from transient
   `EmbeddingService` compute and whose similarity executes in
   `MemoryStorage+Semantic.swift` over local `memory_embeddings`.
3. `ChatToolExecutor.swift` still handles `search_conversations` by calling
   `APIClient+Tools.swift::toolSearchConversations`; S-19 owns replacing that
   backend product-data hop with the final local hybrid search.
4. Rewind owns OCR/metadata/embeddings locally in `RewindDatabase` and local
   files in `RewindStorage`; task embeddings likewise remain local. The
   authenticated embedding proxy returns vectors only.
5. `LocalChatAttachmentStore` materializes ordinary Chat files beneath the
   owner/chat local profile, protects sources, and deletes only unreferenced
   managed copies.

### Typesense path

```text
PTT search_conversations
  -> ChatToolExecutor
  -> APIClient.toolSearchConversations
  -> POST /v1/tools/conversations/search
  -> routers/tools.py
  -> retrieval/tool_services/conversations.search_conversations_text
  -> conversations/search.keyword_search_conversation_ids
  -> Typesense collection `conversations`
  + database/vector_db.query_vectors (Pinecone ns1)
  -> keyword-first ID merge
  -> Firestore hydration/formatting
```

`backend/utils/retrieval/tools/conversation_tools.py` duplicates the hosted
agent-tool reader. `backend/utils/conversations/search.py` owns the lazy
Typesense client, host/port/protocol/API-key variables, date/filter conversion,
250-hit clamp, fail-soft keyword lookup, and merge helper. Hosted conversation
processing currently supplies the associated Firestore/vector product paths;
S-23/S-19 must remove their final authority/callers before S-24 deletes the
provider family.

### Pinecone path

`backend/database/vector_db.py` constructs `Pinecone` from
`PINECONE_API_KEY`/`PINECONE_INDEX_NAME` and currently owns:

- `ns1`: conversation-summary upsert/query/update/delete and bulk account purge;
- `ns_tchunks`: transcript-chunk upsert/search/delete and bulk account purge;
- `ns_x`: X-post upsert/search functions with no production caller found at the
  pinned baseline, expected to disappear with S-23;
- no `ns3`: S-15 already deleted the Rewind cloud namespace.

`process_conversation.py` writes summary and transcript vectors;
`tool_services/conversations.py`, `conversation_tools.py`, and `routers/tools.py`
read them; `merge_conversations.py` deletes summary vectors; and
`services/users/account_deletion.py::purge_derived_user_data` treats `ns1` and
`ns_tchunks` cleanup as required before the authoritative Firestore wipe.

### Hosted file and object path

`backend/routers/chat.py` still registers authenticated multipart
`POST /v1/files`. It calls `FileChatTool.upload`, creates an OpenAI Files object,
may produce an image thumbnail through `storage.upload_multi_chat_files`, and
writes a `FileChat(openai_file_id=...)` document through `database/chat.py`.
`backend/utils/other/chat_file.py` also owns OpenAI file content reads,
Assistants/thread/file-search/vision execution, and deletion of OpenAI files,
threads, assistants, and Firestore metadata. The path is absent from the current
generated Mac client but remains in `route_policy_legacy_missing_routes.txt`.

### GCS object families and retained sibling

`backend/utils/other/storage.py` currently combines seven unrelated bucket
families behind one import-time module:

1. `BUCKET_SPEECH_PROFILES`: user/profile/person speech samples;
2. `BUCKET_POSTPROCESSING`: prerecorded conversation postprocessing input;
3. `BUCKET_MEMORIES_RECORDINGS`: retained-at-baseline conversation recordings;
4. `BUCKET_PRIVATE_CLOUD_SYNC`: audio chunks, merged WAV/MP3, playback artifacts,
   unavailable markers, and conversation playback;
5. `BUCKET_TEMPORAL_SYNC_LOCAL`: temporary signed voice-message input plus a
   deferred-delete janitor;
6. `BUCKET_CHAT_FILES`: cloud Chat thumbnails;
7. `BUCKET_DESKTOP_UPDATES`: an uncalled generic signing helper.

The first six are private product-data or transient customer-audio object paths.
Speech/profile routers, conversation processing, Pusher, sync playback, the
internal `/v2/audio-merge-jobs/run` handler, account deletion, and voice-message
transcription call them today. S-23 must remove rejected product callers/jobs.
S-24 itself must remove the remaining temporal voice-object hop because the
retained fixed Modulate adapter already implements `transcribe_bytes` via
`prerecorded_from_bytes`.

The protected update/preview boundary does **not** depend on that generic helper:
`.github/workflows/desktop_promote_prod.yml` and
`desktop_release_doctor.yml` use `GCS_DESKTOP_UPDATES_BUCKET` (current fallback
`gs://omi_macos_updates`); `database/desktop_previews.py`, `routers/updates.py`,
and tests validate immutable update/preview URLs in that bucket. S-29, not S-24,
owns its later brand/provider re-ownership.

### Configuration, harness, generated contracts, and lifecycle

- `typesense`, `pinecone`, and `google-cloud-storage` occur in runtime,
  OpenAPI-runner, and Pusher requirements plus generated `pylock*.toml` files.
- Provider/bucket variables flow through backend env templates, Helm values,
  `deploy/runtime_env.yaml`, deploy scripts, backend workflows, OpenAPI hermetic
  env setup, and import-side-effect guards.
- The dev harness currently starts/probes/stops an isolated Docker/native
  Typesense runtime and exposes provider secrets/ports. Desktop core and beta
  qualification documents/scripts expect it.
- The backend e2e harness installs a Pinecone-like in-memory fake, dummy
  Typesense variables, and fake GCS buckets. Several unrelated unit tests stub
  these providers only to make broad imports succeed; they must be narrowed, not
  mechanically deleted.
- Account deletion is a durable, queued, retryable, fail-closed workflow.
  S-24 removes only rejected external purge branches and obsolete counters;
  S-25 later retargets the task/reconciler/service topology.
- `data_export.py` currently composes canonical account data rather than
  exporting Typesense/Pinecone indexes. After S-23, its retained output must
  remain unchanged and must not add a cloud-object export fallback.

## 7. Complete caller and dependency inventory

Every row is revalidated at Gate 0. “Expected predecessor deletion” is a stop
gate if the symbol survives with a real caller.

| Surface | Current files/symbols/callers | S-24 treatment |
|---|---|---|
| Local conversation reads | `ConversationRepository`, local query/storage tests | KEEP; consume S-19 final semantic/FTS/vector seam without renaming it. |
| PTT conversation bridge | `ChatToolExecutor.search_conversations`, `APIClient+Tools.toolSearchConversations` | S-19 owns migration; S-24 only proves no remote fallback/caller remains. |
| Local Memory vectors | `MemorySemanticRecall`, `MemoryStorage+Semantic`, lifecycle runner | KEEP AS IS; provider deletion must not edit authority semantics. |
| Local Rewind vectors | `RewindDatabase`, `OCREmbeddingService`, `RewindStorage` | KEEP AS IS; protect IR-011/IR-291. |
| Local task vectors | `EmbeddingService`, `ActionItemStorage` | KEEP AS IS; run predecessor contract. |
| Local Chat files | `LocalChatAttachmentStore`, `ChatAttachment`, `ChatResource`, journal | KEEP AS IS; protect restart, owner isolation, source safety, and GC. |
| Typesense adapter | `backend/utils/conversations/search.py` | DELETE after S-19/S-23 caller proof. |
| Typesense readers | `tool_services/conversations.py`, `tools/conversation_tools.py`, `routers/tools.py` | Expected predecessor deletion/adaptation; delete only residual provider branches, never local tool semantics. |
| Typesense deps | `requirements.txt`, `openapi-requirements.txt`, `pusher/requirements.txt`, `pylock*.toml` | DELETE direct/transitive residue; regenerate locks with `backend/scripts/update-python-lock.sh`. |
| Typesense harness | `scripts/dev-harness/dev_harness/{cli,config,providers,qualification,safety}.py`, tests, desktop harness/qualification docs | ADAPT to boot/probe the retained stack without Typesense; delete provider-specific safety/lease tests only. |
| Typesense deploy/config | backend env templates, charts, runtime env, workflows, deploy config, OpenAPI env, README/docs | DELETE exact variables/secrets/claims; retain unrelated service configuration. |
| Pinecone module | `backend/database/vector_db.py` and `ns1`, `ns_tchunks`, `ns_x` functions | DELETE after all callers disappear; refreshed unknown namespace is an explicit stop/inventory item. |
| Pinecone writers/readers | `process_conversation.py`, `transcript_chunks.py`, hosted retrieval tools, `routers/tools.py`, merge path | Expected S-19/S-23 deletion; S-24 removes only proven residue. |
| Pinecone account purge | Exact S-23 handoff in `account_deletion.py`, plus `database/conversations.get_conversation_ids` comment/helper | DELETE the Pinecone purge/counters while preserving durable wipe ordering and generic canonical deletion. Delete IDs-only helper only if caller-free. |
| Pinecone fake/tests | e2e `fakes/vector_search.py`, conftest, hybrid/vector/account-deletion/tool tests | DELETE exclusive fakes/tests; rewrite surviving behavior at local or retained service seam. |
| Pinecone deploy/config/deps | env templates, charts, runtime env, workflows, release-policy checks, docs, requirements/locks | DELETE exact provider residue; preserve general secret/removal safety checks. |
| `/v1/files` entrance | `routers/chat.py`, `FileChat` response, multipart policy, route baseline | DELETE route and model branch; prove unauthenticated and authenticated requests both see genuine 404. |
| Hosted file service | `utils/other/chat_file.py`, `retrieval/tools/file_tools.py`, exports/registry | DELETE after S-23 hosted Chat consumer proof. |
| Hosted file data | `database/chat.py` file helpers, `openai_file_id`, assistant/thread IDs, `BUCKET_CHAT_FILES` thumbnails | DELETE exact fields/helpers/config after per-symbol caller search. |
| File tests/docs | upload security/multipart/malformed/stream tests; model endpoint inventory | Delete exclusive tests; preserve multipart bounds for retained routes and retained gateway observability. |
| Speech/profile objects | storage speech/profile functions, speech-profile router/services/scripts | Expected S-23 product deletion; S-24 removes residual shared bucket/client/config only. |
| Postprocessing/recording objects | storage functions, `postprocess_conversation.py`, account purge | Expected S-23 deletion; remove residual purge/config/docs in S-24. |
| Private sync/playback objects | Pusher, database audio enumeration, merge/process, `utils/sync/playback.py`, `routers/sync.py` | Expected S-23 workload deletion. S-25 owns remaining deployment/queue/service topology, not product objects. Stop if it still imports product storage. |
| Temporal voice object | `utils/chat.py::_prepare_voice_message_url`, multipart and legacy voice routes, deferred-delete helper | ADAPT in Cycle 6 to direct bytes; then delete bucket/janitor branch. |
| Shared GCS module/dependency | `utils/other/storage.py`, Google storage client, runtime requirements/locks, e2e fake | SIMPLIFY AFTER all product families: delete if refreshed caller search is empty. |
| Retained update/preview bucket | desktop promotion/doctor workflows, `desktop_previews.py`, `updates.py`, release guards/tests | KEEP AS IS; do not rename current `omi_macos_updates`, public URLs, variables, or workflow semantics. |
| Redis | auth/rate/fair-use/locks/caches under current owners | KEEP AS IS; verify no product documents/vector/search corpus migrate into it. |
| Embedding compute | authenticated desktop embedding proxy and Gemini adapter | KEEP AS IS; request content/vector remain transient and local owner validates/commits. |
| OpenAPI/generated Swift | `docs/api-reference/app-client-openapi.json`, `OmiApi.generated.swift`, route policy | ADAPT/regenerate only when actual retained app-client routes/models change; no Windows generation. |
| Docs/guards | root/component guides, e2e docs, qualification docs, import scanner, check manifest | ADAPT truthful surviving stack; delete provider-specific assertions and keep shared guardrails. |
| Live resources | actual Typesense/Pinecone/OpenAI/GCS resources, secrets, alerts | OUT OF SCOPE without later inventory and explicit mutation authorization. |

No current production Brain Map/knowledge-graph code was found outside historical
changelogs and retained absence E2E assertions. A refreshed live graph/vector
consumer is a Gate 0 stop for S-23 ownership; historical release notes are kept
as history, not scrubbed as runtime residue.

## 8. Behavior classification

| Classification | Surfaces | Required treatment |
|---|---|---|
| KEEP AS IS | Local GRDB/FTS5/vector authorities; local conversation, Memory, task, and Rewind record/index lifecycle; local Chat attachments; owner authorization snapshots; authenticated transient embedding compute; fixed managed STT/provider semantics; Redis ephemeral control state; account deletion/export contracts; desktop update/preview bucket/workflows | No fallback, duplicate store, prompt/model change, search semantic drift, quota drift, or release rename. |
| ADAPT | Voice multipart/legacy file transcription from signed GCS URL to existing byte adapter; account-deletion purge/result model; app registries/route policy/OpenAPI; requirements/locks; dev/e2e harness; provider env/workflow/chart/docs; shared tests/stubs | Smallest change that removes the rejected dependency while preserving public behavior. |
| DELETE | Typesense adapter/runtime/dependency/config and all search/sync residue; Pinecone module/all namespaces/dependency/config/repair and account-purge residue; `/v1/files`; `FileChatTool`; OpenAI Files/Assistants/thread/file-search state; hosted file metadata/thumbnails; every private product-data GCS helper/variable/test/doc; exclusive graph/vector consumers | Delete vertically only after caller proof. No disabled/no-op shell. |
| SIMPLIFY AFTER | Duplicate hosted search merge/format helpers; generic vector/storage abstractions; provider-only fakes; broad import stubs; stale counters/comments/docs; Google storage runtime dependency if no caller remains | Simplify only after the owning GREEN and exact `rg` proof. |
| ACCELERATE AFTER | Measure provider-free bootstrap, focused local-search/account-deletion tests, and named-bundle search checks after GREEN; improve only a demonstrated recurring delay, otherwise `none`. | Preserve the official component gates and record before/after timing. |
| AUTOMATE LAST | Once provider ownership is stable, register only a deterministic Typesense/Pinecone/object residue or retained-bucket check in an existing local and CI lane with a real failure citation; otherwise `none`. | Automation follows the final manual inventory, never replaces it. |
| OUT OF SCOPE / DEFERRED | S-19 local PTT migration; S-23 product/schema/job teardown; S-25 queue/worker/service/image/GKE deletion and account-task retarget; S-26 canonical app; S-27 retained Cloud Run/Redis/Firestore/GCS re-ownership; S-28 storage names; S-29 update bucket/release identity; S-30 copy; Windows; billing activation; live resource mutation | Record handoff or stop. Do not absorb it. |

## 9. Retained behavioral invariants

1. **Owner-local authority:** only the active owner generation may read, mutate,
   index, notify, or publish local product data. Same-UID reauthentication still
   creates a new generation; a suspended old result is rejected.
2. **Conversation search:** preserve S-19's final keyword-plus-vector semantics,
   keyword-first stable dedupe, date interval, bound/limit, result fields, and
   recent-vs-semantic distinction. Offline search and restart work without the
   backend; deleting/merging a conversation atomically removes/updates every
   local index row.
3. **Memory search:** `MemorySemanticRecall` captures one authorization snapshot,
   obtains only a transient query vector, revalidates ownership, and searches
   current local revisions. Delete/expiry/consolidation leaves no stale match.
4. **Task/Rewind search:** their existing local vector and FTS behavior remains
   unchanged. Rewind capture, OCR, retention, privacy exclusions, and PTT tools
   never gain a Python/Pinecone fallback.
5. **Screenshot relation:** deleting a Rewind screenshot sets a linked Memory's
   nullable `screenshotId` to null without deleting the Memory or creating a
   remote copy.
6. **Local attachments:** four-file limit, materialize-before-journal, MIME/name/
   URI/presentation, restart durability, first-image bytes, owner/chat isolation,
   source preservation, failed-send behavior, and reference-aware GC remain.
7. **Removed file route:** `/v1/files` is absent in both Python app surfaces,
   policy, OpenAPI, and generated non-Windows clients. There is no 410, fake ID,
   empty upload, deprecated alias, or hidden OpenAI/GCS side effect.
8. **Voice transcription:** authentication/rate limit, trial paywall, request
   size and filename checks, decoding/VAD, daily budget, Modulate model/provider,
   retry/timeout/failure mapping, language result, telemetry, and response shape
   remain exact. Only the intermediate object transport disappears.
9. **Transient compute:** embeddings and managed model/STT calls do not persist
   input, output, vector, file, or product identity on the backend. Failures
   create no phantom local state.
10. **Account lifecycle:** deletion remains durable, retryable, fail closed, and
    ordered before the canonical Firestore/Auth completion markers. Removing an
    already-rejected purge cannot make a real remaining purge best effort.
11. **Export:** retained local/canonical export behavior and truthful omissions
    remain; there is no provider-index or cloud-file export/backfill.
12. **Redis:** content-free ephemeral uses remain; provider deletion neither
    removes rate/fair-use enforcement nor puts product content into Redis.
13. **Updates/previews:** immutable preview publication/delisting, signed update
    artifacts, Stable/Beta policy, and current bucket URLs/workflow variables
    remain. S-24 does not claim S-29's identity work.
14. **No billing activation:** `BILLING_MODE=disabled` and the Dodo post-Wave-6
    gate are untouched.

## 10. Target authority, result ownership, and service topology

| Data/behavior | Authoritative owner after S-24 | Allowed backend role | Forbidden authority |
|---|---|---|---|
| Conversations/transcripts/search vectors | Owner-scoped `omi.db` plus S-19 local FTS/vector rows | Bounded compute only; no product retrieval | Firestore search corpus, Typesense, Pinecone, Redis corpus |
| Memories and Memory vectors | Local Memory tables/`memory_embeddings` at current revision | Return bounded normalization/embedding proposals | Hosted Memory store/vector/graph |
| Tasks and task vectors | Local task store/index | Bounded compute proposal | Pinecone/task cloud index |
| Rewind OCR/screens/vectors | Rewind GRDB and local artifact tree | Transient embedding vector | Firestore/Pinecone/object copy |
| Ordinary Chat attachment bytes | Owner/chat local managed directory and journal reference | Transient model request bytes only | `/v1/files`, OpenAI Files, Firestore file doc, GCS thumbnail |
| Voice upload | Request-local temp file/bytes until response cleanup | Direct byte call to retained managed STT | Temporary GCS object or durable transcript |
| Account deletion state | Durable canonical deletion marker/job plus remaining canonical owners | Execute/retry real remaining cleanup | Provider purge for an authority that no longer exists |
| Redis state | Existing bounded control-plane keys | OAuth/rate/fair-use/locks/cache | Product document, vector, attachment, sync queue payload content |
| Desktop update/preview artifacts | Retained update/preview bucket plus release registry/workflows | Publish/sign/delist under existing release controls | Private product data or general attachment/audio storage |

The repository topology after S-24 may still contain S-25-owned deployment
objects, including the duplicate `backend-sync` target required temporarily by
account deletion. They must have no search/vector/product-object workload.
S-25 retargets the durable deletion task and removes queues/workers/services;
S-24 does not leave an empty service or alter deployment topology to anticipate
that work.

## 11. Ordered TDD cycles

### Cycle 1 — Remove the Typesense conversation-search behavior

- **Behavioral RED:** through S-19's production local PTT tool seam, search by an
  exact title/overview term and a semantic term with date/limit bounds while a
  fail-on-touch Typesense transport is installed. Assert keyword-first dedupe,
  local result ownership, deletion removes the result, and both realtime
  providers receive the same formatted tool result. Add a labelled static
  closure assertion that no registered Python reader/writer imports the
  Typesense adapter. It fails on the residual adapter/readers at cycle entry.
- **Why RED before implementation:** today PTT calls the backend hybrid reader,
  and `conversations/search.py` queries Typesense. After S-19, the behavior is
  local but the provider code/config may remain reachable or orphaned.
- **Minimum GREEN:** delete `conversations/search.py` and only the proven-dead
  Typesense imports/merge branches in hosted retrieval code; delete any residual
  conversation sync/index creation/update/delete path. Do not reimplement local
  search in Python or alter S-19's Swift owner.
- **Protected behavior:** IR-093 search/date/limit/result semantics, offline and
  restart behavior, owner-generation rejection, atomic local index deletion,
  both realtime providers, and ordinary recent-conversation behavior.
- **Owner before/after:** before, S-19 local search is authority but orphaned or
  callable Typesense is a second path; after, only S-19's local owner is callable.
- **Expected changes:** provider adapter and residual backend imports; focused
  hosted search tests replaced by production local-tool tests; truthful docs and
  route/tool registry assertions. No Mac production change unless Gate 0 finds
  an S-19 integration defect, which must return to S-19.
- **Focused verification:** actual integrated S-19 Swift filters for local hybrid
  search/tool execution plus backend hosted-tool/route tests with Typesense
  fail-on-touch; run `ConversationLocalQueryTests`,
  `ConversationDeletionCascadeTests`, and the integrated PTT tool tests.
- **Deletion enabled:** conversation collection/search/sync code and exclusive
  timeout/pagination/UTC tests; not the provider dependency/config yet.
- **Stop condition:** any retained non-Windows caller still needs the Typesense
  result, S-19 lacks local semantic/date/limit behavior, or a supported client
  still calls the hosted route. Fix/land the predecessor; add no fallback.

### Cycle 2 — Delete the Typesense runtime, harness, and control-plane residue

- **Behavioral RED:** boot the real hermetic backend apps and the supported local
  dev harness with no `TYPESENSE_*` variables, binary, Docker image, port, or
  secret. Exercise retained auth, compute, voice, route-policy inventory, and
  local desktop harness readiness. The current harness requires/starts/probes
  Typesense and provider dependencies remain installed.
- **Why RED before implementation:** harness config/qualification/safety, backend
  env/charts/workflows, requirements, import fakes, and docs still model
  Typesense as required infrastructure.
- **Minimum GREEN:** remove Typesense from all three direct requirements and
  regenerate locks; remove exact env/secret/chart/runtime/workflow/deploy/OpenAPI
  fake entries; remove the dev-harness service, port, lifecycle/lease cleanup,
  provider-secret and qualification expectations; adapt shared safety tests and
  desktop qualification/docs to the smaller stack.
- **Protected behavior:** hermetic offline backend boot, Redis/Firestore/auth
  ownership and cleanup safety, per-worktree isolation, exact-process cleanup,
  release qualification, and no import-time network/IO.
- **Owner before/after:** before, Typesense runtime/config is treated as a shared
  dev/deploy prerequisite; after, there is no Typesense owner or lifecycle.
- **Expected changes:** requirements and generated locks; env templates; charts;
  runtime manifests; workflows; deploy/import scripts; `scripts/dev-harness`;
  desktop core/qualification docs/scripts; e2e conftest/docs; exclusive tests;
  `.github/checks-manifest.yaml` only where its Typesense-specific reason or
  trigger must be truthfully narrowed.
- **Focused verification:** dev-harness unit tests, backend hermetic e2e boot,
  import-side-effect scanner, runtime-image contracts, desktop core-harness
  self-check, and Typesense residue searches. Use the existing check manifest;
  do not create an on-demand unregistered checker.
- **Deletion enabled:** `typesense` package/transitives, local image/runtime,
  secrets/variables, provider docs, and exclusive harness tests.
- **Stop condition:** a surviving workload imports the SDK, the smaller harness
  cannot exercise a retained service, or removing a workflow secret would
  affect a non-Typesense owner. Resolve the caller/owner first.

### Cycle 3 — Remove Pinecone conversation-summary authority and account purge

- **Behavioral RED:** exercise local PTT conversation search, update/merge, delete,
  restart, and account deletion with a fail-on-touch Pinecone client. Assert
  local summary-vector results update atomically and account deletion proceeds
  through its real remaining required cleanup without requiring `ns1`. A static
  namespace assertion fails while `ns1` functions remain.
- **Why RED before implementation:** `vector_db.py` still owns summary upsert,
  query, metadata update, delete, and bulk delete; hosted processing/readers and
  account deletion call them on this baseline.
- **Minimum GREEN:** after S-19/S-23 caller proof, delete all `ns1` functions and
  imports; remove conversation-vector enumeration and the exact required purge,
  counter, failure label, tests, and stale comments from account deletion. Keep
  canonical Firestore/Auth wipe order and all genuine remaining failure gates.
- **Protected behavior:** local hybrid ranking/filters, merge/delete index
  lifecycle, offline/restart/owner isolation, durable deletion marker/queue,
  billing cancellation mode, Twilio/canonical cleanup only if still retained by
  predecessors, and fail-closed ordering.
- **Owner before/after:** before, local conversation search plus Pinecone `ns1`;
  after, local store/index only, with no external vector purge owner.
- **Expected changes:** `database/vector_db.py`, proven residual callers,
  `account_deletion.py`, maybe caller-free `get_conversation_ids`, local and
  account-deletion tests, e2e vector fake scope, docs.
- **Focused verification:** integrated S-19 search/delete tests;
  `tests/services/users/test_account_deletion.py`,
  `tests/unit/test_delete_account_purge_storage.py`, and deletion retry/marker
  tests after adapting expectations to real remaining authorities.
- **Deletion enabled:** the complete `ns1` surface and its fake/test branches.
- **Stop condition:** any production summary-vector writer/reader remains after
  S-23, the local delete/index contract is missing, or account deletion would
  skip another real required owner. Stop and repair predecessor ownership.

### Cycle 4 — Delete remaining Pinecone namespaces, SDK, and configuration

- **Behavioral RED:** exercise the retained local transcript/conversation tool
  paths and authenticated Gemini embedding proxy with Pinecone unavailable;
  boot both backend apps without `PINECONE_*`. Assert no transcript tool or
  account purge reaches `ns_tchunks`, no `ns_x`/unknown namespace is registered,
  and the embedding response is still transient. Current `vector_db.py`, fakes,
  requirements, and deploy settings violate closure.
- **Why RED before implementation:** transcript chunk upsert/search/delete,
  orphan X-post helpers, global client construction, SDK requirements, provider
  fakes, variables/secrets, and docs remain.
- **Minimum GREEN:** delete all remaining namespace functions and
  `database/vector_db.py`; remove proven-dead hosted chunk helpers/readers and
  account purges; delete Pinecone direct requirements and regenerate locks;
  remove provider variables/secrets/chart/runtime/workflow/release-policy/import
  fake/docs; delete or narrow provider-only tests and e2e fake.
- **Protected behavior:** S-19 local transcript/conversation retrieval, Rewind/
  Memory/task local vectors, Gemini embedding auth/paywall/rate/shape, hermetic
  boot, deploy secret-removal safety, and account deletion/export.
- **Owner before/after:** before, `vector_db.py` owns remaining hosted vectors;
  after, no Pinecone owner exists and each local domain owns its index.
- **Expected changes:** provider module/callers; requirements/locks; e2e fakes;
  env templates; charts; runtime/deploy/workflows; release-policy checks;
  import scanner; backend/component docs and exclusive vector tests.
- **Focused verification:** local Swift search/vector suites, embedding proxy
  route tests, hermetic backend e2e, account deletion/export tests, runtime-image
  contracts, lock freshness, and exact Pinecone/namespace residue search.
- **Deletion enabled:** Pinecone SDK/plugins/transitives, every namespace and
  fake, secrets/config, repair/index lifecycle, and provider documentation.
- **Stop condition:** a namespace/caller not assigned to S-24 is discovered, an
  embedding route imports `vector_db.py`, or a generated runtime image still
  requires the package. Classify and resolve it; never retain an empty index.

### Cycle 5 — Delete OpenAI Files and cloud attachment authority

- **Behavioral RED:** through real Python app instances, authenticated and
  unauthenticated `POST /v1/files` requests must both resolve to genuine 404,
  while local Chat select/paste/send/reopen/delete flows operate with OpenAI and
  GCS fail-on-touch. Assert retained voice/report/multipart routes keep their
  current auth/size contracts. The route and `FileChatTool` currently exist.
- **Why RED before implementation:** `/v1/files` creates OpenAI file identity,
  GCS thumbnails, Firestore metadata, and Assistants/thread/file-search state.
- **Minimum GREEN:** unmount/delete the exact route; remove `FileChat` and
  file-specific database helpers/fields only after caller proof; delete
  `chat_file.py`, dead file retrieval tool exports, OpenAI Files/Assistants
  inventory, chat-thumbnail storage branch/config, and exclusive tests/docs;
  remove the stale route-policy baseline row and regenerate contracts.
- **Protected behavior:** IR-044 local attachment durability/limits/preview/GC;
  retained `/v2/chat/completions`, greeting/title compute, message reporting,
  voice routes, general OpenAI/gateway uses authorized by S-22, multipart limits
  on surviving routes, and account deletion/export.
- **Owner before/after:** before, local attachments coexist with backend file
  identities; after, `LocalChatAttachmentStore`/journal is sole durable owner and
  provider input is request-transient.
- **Expected changes:** `routers/chat.py`, `models/chat.py`, `database/chat.py`,
  `utils/other/chat_file.py`, file tool exports, storage thumbnail branch, route
  policy/OpenAPI/generated Swift if affected, model inventory, tests/stubs/docs.
- **Focused verification:** `LocalChatAttachmentStoreTests` plus journal
  restart/switch/GC tests; retained chat/voice/report route tests;
  `test_s11_chat_route_absence.py` adapted to assert 404; route-policy and
  OpenAPI checks; exact OpenAI/file residue searches.
- **Deletion enabled:** OpenAI file/assistant/thread IDs and cleanup, Firestore
  file docs, GCS thumbnails, upload security tests whose endpoint no longer
  exists, and direct-model file-chat inventory.
- **Stop condition:** S-23 leaves a supported hosted-file consumer, a supported
  released client requires the route, or a shared Chat model/helper cannot be
  separated safely. Resolve the owner; add no deprecated endpoint.

### Cycle 6 — Remove transient GCS from retained voice-message transcription

- **Behavioral RED:** run real multipart and legacy voice-message production
  handlers with valid WAV/decoded fixtures while the GCS client is fail-on-touch.
  Assert success/silence/language, invalid input, provider timeout/error, quota,
  cleanup, and telemetry are unchanged. Current
  `transcribe_voice_message_segment` calls `_prepare_voice_message_url`, so valid
  multipart input touches `BUCKET_TEMPORAL_SYNC_LOCAL`.
- **Why RED before implementation:** the fixed Modulate provider already accepts
  bytes, but file-based routes upload a signed temporary object and schedule a
  deferred GCS delete before invoking the URL adapter.
- **Minimum GREEN:** read validated request-local WAV bytes on the existing
  storage executor and call the existing `prerecorded_from_bytes`/provider byte
  seam with the same language/diarization/result processing; preserve VAD and
  guaranteed local temp cleanup. Then delete `_prepare_voice_message_url`, the
  temporal bucket upload/delete functions, janitor instance/config, and only
  deferred-delete code/tests proven caller-free.
- **Protected behavior:** exact routes, auth/rate/trial/budget semantics,
  multipart/PCM limits and decoding, fixed Modulate model, attempts/timeouts,
  silence and detected-language behavior, public response/error mapping,
  fallback telemetry, and no durable transcript.
- **Owner before/after:** before, request-local temp plus transient GCS object;
  after, request-local bytes only, consumed by bounded managed STT.
- **Expected changes:** `utils/chat.py`, voice branches in `routers/chat.py` only
  if needed to pass bytes safely, temporal block in `storage.py`, env/config,
  voice/decode/janitor/async-blocker tests and docs.
- **Focused verification:** current voice message language, filename, PCM/Opus
  decode, multipart, outcome/failure, fair-use, gateway observability, and
  release transcription-capability tests; a fail-on-touch GCS integration test;
  backend async-blocker and thread/executor checks.
- **Deletion enabled:** `BUCKET_TEMPORAL_SYNC_LOCAL`, signed temporal blobs,
  lifecycle-rule dependency, and exclusive deferred-blob janitor residue.
- **Stop condition:** the integrated S-22 provider does not support byte input
  with equivalent semantics, any retained caller needs signed URL input, or
  memory bounds cannot be preserved. Return the transport problem to S-22 or
  define a reviewed bounded seam; do not keep silent dual paths.

### Cycle 7 — Delete every remaining private product-data GCS family

- **Behavioral RED:** boot the real backend with a fail-on-touch GCS client and
  exercise retained compute, account deletion, export, and auth/voice routes.
  Assert no speech profile, postprocessing recording, private sync chunk,
  playback artifact, cloud Chat thumbnail, or product deletion branch is
  reachable. Static bucket/function searches identify any surviving residue.
- **Why RED before implementation:** the baseline shared storage module and its
  callers own speech/profile, postprocessing, recording, private-sync/playback,
  and chat object paths; S-23 should remove workloads but shared helpers/config/
  tests may remain.
- **Minimum GREEN:** after predecessor proof, delete residual product bucket
  variables and complete function families; remove obsolete account purges,
  app imports, fake buckets, environment/chart/runtime/workflow settings,
  metrics/tests/docs, and product-specific GCS permissions. Do not delete a
  S-25 deployment definition or the update/preview workflow.
- **Protected behavior:** retained transient compute, content-free account
  deletion/export, auth, voice after Cycle 6, Redis controls, and update/preview
  publication. Generic recursive canonical deletion remains able to remove
  unknown old Firestore subcollections without naming deleted cloud products.
- **Owner before/after:** before, GCS is a product-data owner for several
  rejected families; after, none of those families has a repository object
  owner and only release artifacts remain in GCS.
- **Expected changes:** residual portions of `storage.py`; app/service imports;
  account deletion/result counters; e2e storage fake/tests; env templates;
  charts/runtime/workflows/deploy docs; provider IAM references if repository
  owned; component service map/guide.
- **Focused verification:** account-deletion and export suites, hermetic backend
  e2e, voice/compute routes, app import/startup tests, workflow/runtime contract
  checks, and exact bucket/function/caller searches.
- **Deletion enabled:** all private product-data GCS code/config/test/doc paths.
- **Stop condition:** a real retained workload or S-25-owned worker still reads
  product objects; a bucket name maps to both product data and updates; or S-23
  left a product route/schema. Stop and resolve ownership—do not hide it behind
  a nullable config or fake-success worker.

### Cycle 8 — Collapse the shared storage/provider scaffolding and prove the retained bucket

- **Behavioral RED:** boot/test the surviving backend stack with no Google
  Storage runtime dependency or product bucket variables, then execute preview
  registry/update route and release-workflow contract tests against fixtures.
  Assert the current update/preview bucket path remains accepted while a private
  product-data URL/path is not introduced. At cycle entry, the generic storage
  module/dependency/fakes and stale env may remain.
- **Why RED before implementation:** after Cycles 5–7 the generic Google storage
  client may be caller-free, but requirements, locks, OpenAPI env, e2e fakes, and
  shared documentation can still make GCS look like a backend product store.
- **Minimum GREEN:** delete `utils/other/storage.py` and `google-cloud-storage`
  runtime/OpenAPI/Pusher requirements only if refreshed production caller search
  is empty; regenerate locks and remove exclusive fake/env/import residue.
  Preserve `GCS_DESKTOP_UPDATES_BUCKET`, promotion/doctor workflows,
  `desktop_previews.py`, update routes, release guards, and current URL/bucket
  identity exactly. If a retained update signer is actually callable after the
  rebase, extract only that narrow release-owned primitive instead of deleting it.
- **Protected behavior:** immutable preview publication/delisting, update feed/
  download behavior, signed artifact promotion/doctor checks, no private data in
  release storage, hermetic backend boot, and S-29 ownership of rebranding.
- **Owner before/after:** before, one generic module conflates product and release
  storage; after, GCS is represented only by the release/update boundary and no
  runtime product-object client exists unless proven necessary.
- **Expected changes:** shared storage module, Google storage requirements/locks,
  OpenAPI/e2e fakes, import docs; retained release files only for expectation
  updates required by dependency removal, never bucket rename or workflow redesign.
- **Focused verification:** `test_desktop_previews.py`,
  `test_desktop_updates.py`, `test_desktop_release_scripts.py`, release-process
  guards, hermetic backend boot, runtime-image contracts, dependency/lock checks,
  plus the final residue matrix.
- **Deletion enabled:** generic GCS client scaffolding and the last misleading
  product-storage dependency/configuration.
- **Stop condition:** any retained runtime caller of Google Storage is found,
  release tests require an owned signing helper not yet separated, or the live
  update bucket identity/authorization is unknown for operational closure.
  Repository code may proceed only with the proven narrow retained primitive;
  live mutation remains blocked.

## 12. Cross-slice ownership and handoffs

| Slice | S-24 consumes or preserves | S-24 hands off / must not absorb |
|---|---|---|
| S-08 | Durable account deletion and identity-generation semantics | Do not redesign auth/export or weaken canonical wipe. |
| S-10 | Local conversation authority/delete semantics | Do not rebuild conversation storage or cloud import. |
| S-11 | Local journal and attachment store; `/v1/files` handoff | Delete hosted file family; do not change local attachment UX. |
| S-12 | Local Memory vectors/search | Do not alter prompts, lifecycle, or consolidation. |
| S-13 | Local task vectors/index lifecycle | Do not redesign task search/dedup. |
| S-15 | Local Rewind and absence of `ns3` | Do not touch Rewind storage/search or reintroduce screen cloud paths. |
| S-18 | Billing remains disabled; deletion cancellation seam retained | Dodo acceptance remains post-Wave-6. |
| S-19 | Final local PTT conversation tools and both realtime providers | S-24 deletes the hosted search/vector siblings only after proof. |
| S-20 | Local fair-use evidence authority, transient GPT-5.1 request, and content-free durable enforcement | Preserve classifier and Redis/rate/quota semantics; do not treat transient request content as a hosted data index. |
| S-22 | Fixed retained model/STT portfolio and byte-capable managed adapters | Do not change provider/model/failover decisions. Return missing byte equivalence to S-22. |
| S-23 | Rejected product routes/schemas/writers/readers/product jobs are gone; one exact Pinecone purge/counter seam is handed off | If any other product caller/cleanup survives, S-23 fixes it; S-24 deletes Pinecone and shared provider/object infrastructure. |
| S-25 | Receives a content-free topology: no search/vector/product-object workload | Owns job/queue/worker/service/image/GKE deletion and account-task retarget. S-24 must not leave an empty compatibility service or delete its topology. |
| S-26 | Receives backend/harness without deleted providers | Owns canonical app/URL consolidation. |
| S-27 | Receives retained Redis/Firestore/account queue and update GCS boundary | Owns projects, IAM, regions, runtime accounts, retained infrastructure and live proof. |
| S-28 | Receives stable local schemas | Owns storage namespace/installation identity. |
| S-29 | Receives the untouched current update/preview release boundary | Owns rebrand, signing, preview, promotion, bucket identity, website/legal release system. |
| S-30/S-31 | Receive truthful reduced product and closure evidence | Own final copy/truth and end-to-end release closure. |

Shared-file rule: `backend/main.py`, `routers/chat.py`, `account_deletion.py`,
`utils/other/storage.py`, requirements/locks, route policy/OpenAPI, runtime env,
workflows, dev harness, component guides, and broad import tests are edited only
for the exact S-24 branch. Preserve integrated predecessor edits and separate
independently testable family commits.

## 13. Repository residue-search strategy

Run after Gate 0, after each owning GREEN, and once over the final tree. Inspect
every hit; historical changelogs, this plan, requirements evidence, and explicit
absence tests may remain only when labelled truthful history/guards.

```bash
# Production callers and provider identities
rg -n -i 'typesense|TYPESENSE_|pinecone|PINECONE_|ns1|ns3|ns_tchunks|ns_x' \
  backend desktop/macos .github scripts \
  --glob '!desktop/windows/**' --glob '!**/.build/**' --glob '!**/pylock*.toml'

# Hosted file/object authority
rg -n 'openai_file_id|OpenAI Files|files\.(create|content|delete)|file_search|beta\.assistants|BUCKET_CHAT_FILES|upload_multi_chat_files|/v1/files' \
  backend desktop/macos .github scripts \
  --glob '!desktop/windows/**' --glob '!**/.build/**'

# Every rejected product-object path and generic storage caller
rg -n 'BUCKET_(SPEECH_PROFILES|POSTPROCESSING|MEMORIES_RECORDINGS|PRIVATE_CLOUD_SYNC|TEMPORAL_SYNC_LOCAL)|speech_profiles_bucket|postprocessing_audio_bucket|memories_recordings_bucket|private_cloud_sync_bucket|syncing_local_bucket|get_syncing_file_temporal_signed_url|conversation_playback|playback_artifact|audio_chunks' \
  backend desktop/macos .github scripts \
  --glob '!desktop/windows/**' --glob '!**/.build/**'
rg -n 'utils\.other\.storage|from google\.cloud import storage|google-cloud-storage' \
  backend .github scripts --glob '!**/pylock*.toml'

# Protected retained siblings
rg -n 'GCS_DESKTOP_UPDATES_BUCKET|BUCKET_DESKTOP_UPDATES|omi_macos_updates|desktop_previews|MemorySemanticRecall|memory_embeddings|screenshotId|LocalChatAttachmentStore' \
  backend desktop/macos .github scripts --glob '!desktop/windows/**' --glob '!**/.build/**'

# Removed entrances and generated contracts
rg -n '/v1/files|/v1/tools/conversations/(search|search-chunks)|toolSearchConversations' \
  backend desktop/macos docs .github scripts \
  --glob '!desktop/windows/**' --glob '!**/.build/**'

# Rejected graph/product data must not migrate into retained stores
rg -n -i 'brain.?map|knowledge.?graph|graph.*(vector|index)|redis.*(conversation|memory|attachment|transcript)|product.*bucket' \
  backend desktop/macos .github scripts --glob '!desktop/windows/**' --glob '!**/.build/**'
```

Also use symbol-specific `rg` before deleting each helper and inspect generated
locks separately to confirm the provider is absent after regeneration. Do not
make a new static checker unless repeated real incidents justify a registered
manifest guard; these searches are execution/PR evidence, not behavioral tests.

## 14. Focused and component-level verification

Commands below are future implementation evidence. Test filenames created by a
cycle use the repository's discovered backend/Swift test locations and must be
registered/discovered by existing runners.

### Planning/baseline and generated contracts

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py

cd backend
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
scripts/openapi_runner.sh scripts/route_policy_inventory.py \
  --manifest route_policy_manifest.yaml --check --enforce-missing-baseline
cd ..
python3 backend/scripts/check_route_policy_baseline.py --base-ref origin/main
```

Regenerate Python locks with the verified repository command after dependency
deletion:

```bash
backend/scripts/update-python-lock.sh
```

### Focused backend behavior

```bash
cd backend
.venv/bin/python -m pytest -q \
  tests/services/users/test_account_deletion.py \
  tests/unit/test_delete_account_purge_storage.py \
  tests/services/users/test_data_export.py \
  tests/unit/test_s11_chat_route_absence.py \
  tests/unit/test_voice_message_language.py \
  tests/unit/test_voice_message_filename_none.py \
  tests/unit/test_sync_pcm_decode.py \
  tests/unit/test_sync_opus_decode.py \
  tests/unit/test_desktop_previews.py \
  tests/unit/test_desktop_updates.py \
  tests/unit/test_desktop_release_scripts.py
python scripts/scan_import_time_side_effects.py
python scripts/check_module_stub_pollution.py
cd ..
python3 -m pytest -q scripts/dev-harness/tests
make runtime-image-source-closure
```

The implementer adds focused behavioral tests for provider fail-on-touch,
genuine route absence, byte-only multipart voice, and post-deletion backend boot;
the exact final file names enter the ledger/PR evidence after test discovery is
verified. Exclusive Typesense/Pinecone/OpenAI/GCS tests are deleted only after
their adjacent retained replacement tests pass.

### Focused Swift/local-authority behavior

From `desktop/macos`:

```bash
xcrun swift test --package-path Desktop --filter ConversationLocalQueryTests
xcrun swift test --package-path Desktop --filter ConversationDeletionCascadeTests
xcrun swift test --package-path Desktop --filter ConversationRepositoryTests
xcrun swift test --package-path Desktop --filter MemoryLocalAuthorityTests
xcrun swift test --package-path Desktop --filter LocalMemoryLifecycleRunnerTests
xcrun swift test --package-path Desktop --filter LocalChatAttachmentStoreTests
xcrun swift test --package-path Desktop --filter RewindDatabaseLifecycleTests
xcrun swift test --package-path Desktop --filter RewindScreenshotDeletionSafetyTests
xcrun swift test --package-path Desktop --filter ExternalPreviewBuildTests
```

Add the actual integrated S-19 local PTT conversation-search/tool filters after
Gate 0 inventory. Exercise offline, restart, record deletion/index cleanup,
account switch, same-UID new generation, authorization loss before/after compute,
late result, provider timeout, and persistence failure with no phantom state.

### Component and repository gates

```bash
cd backend && bash test.sh
cd ../desktop/macos && ./test.sh
cd ../..
make preflight
git diff --check
scripts/pr-preflight --suggest
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
```

Before a `fix:` commit/PR, follow the repository failure-class declaration
rules. Record every command and result in commit/PR evidence; do not claim a
real path passed from a compile, static search, or this plan.

## 15. Named-bundle and retained user-path acceptance

Use only the disposable named bundle; never touch Omi/Omi Beta production
bundles or IDs.

```bash
cd desktop/macos
OMI_APP_NAME=omi-wave4-s24 ./run.sh --full
agent-swift connect --bundle-id com.omi.omi-wave4-s24
./scripts/omi-ctl health
```

Against isolated development backends that contain the S-24 candidate:

1. Verify bundle identity/environment in `omi-ctl health`; stop on a production
   URL, wrong bundle ID, or missing agent-runtime handshake.
2. Search Conversations by an exact title/overview term and semantic concept;
   validate date/limit behavior, delete one disposable conversation, repeat the
   search, restart, and confirm no stale match or cloud dependency.
3. Perform a natural authenticated PTT turn with each retained realtime provider
   asking about a seeded conversation. Forced transcripts/reducer-only tests do
   not count. Capture tool trace showing local conversation ownership and no
   backend product-search operation.
4. Search Memories semantically, Tasks semantically, and Rewind OCR/fuzzy history;
   temporarily make the development search/vector providers unavailable and
   prove these local paths still work. Delete disposable rows and prove their
   local index results disappear.
5. Open a Memory linked to a disposable Rewind screenshot, delete the screenshot,
   and verify the Memory remains with the link cleared.
6. Select and paste local Chat files up to the four-file limit, send, reopen after
   restart, inspect preview/name/MIME, delete the chat, and verify reference-aware
   managed-file GC without deleting the original source. Backend/OpenAI/GCS file
   storage must be unavailable throughout.
7. Exercise multipart voice transcription with valid, silent, invalid, and
   provider-failure fixtures through the development backend. Confirm exact
   response/error/telemetry semantics and no temporal GCS object call.
8. Exercise account switch and same-UID reauthentication during a suspended
   embedding/search result; confirm no old-generation read, write, index,
   notification, or publication.
9. Exercise update/preview presentation sufficiently to prove the bundle keeps
   its non-production update policy; use backend preview/update contract tests
   for publication/delisting. S-24 does not publish a live artifact.
10. Inspect sanitized logs and route traces: no Typesense, Pinecone, OpenAI Files,
    product GCS, raw transcript, attachment bytes, or PII appears.

Acceptance evidence includes semantic snapshots, sanitized logs/tool traces,
the exact backend candidate identity, restart evidence, and commands/results.
It is repository/user-path proof, not authorization to deploy or decommission.

## 16. Repository closure versus live operational closure

### Repository/PR closure

The PR may close only when all eight cycles pass, all callers are classified,
removed routes are genuinely absent, retained paths pass, requirements/locks/
OpenAPI/generated non-Windows clients are fresh, residue searches are reviewed,
component suites/preflight pass, and named-bundle evidence is recorded. A clean
repository proves no new code can use the rejected authorities.

### Separately authorized live closure

No repository command or merge authorizes provider mutation. A later operator,
with explicit user approval, must first perform read-only inventories using
verified project/account identifiers for:

- Typesense clusters/collections/API keys, sync jobs, alerts, dashboards, DNS,
  and contracts;
- Pinecone projects/indexes/namespaces/API keys, backups/collections, alerts,
  and billing;
- OpenAI Files, Assistants, threads/vector stores, retention settings, service
  credentials, and commercial obligations;
- GCS buckets/objects/lifecycle rules/IAM/service accounts/log sinks/alerts,
  explicitly separating private product buckets from the retained desktop
  update/preview bucket;
- Secret Manager values, workflow variables, Helm/runtime secrets, images, and
  any job/worker still referencing them.

Classify each resource as retained, rejected, shared, unknown, or already absent.
For rejected data record cutoff/deployed revision, owner, backup and legal/
retention decision, restore/rollback boundary, deletion order, and immutable
evidence. Remove application traffic/credentials before data/index/bucket
deletion; verify absence after mutation. Never guess a project, account, index,
bucket, key, customer, or live state.

S-25 and S-27 own later service/task topology and retained infrastructure. S-29
owns the update/preview release system. Live closure can remain open while the
repository PR closes, but its owner and blocked authorization must be named.

## 17. Risks, ambiguities, and explicit stop points

| Risk or missing input | Affected cycles | Safe work | Evidence required to reopen / owner |
|---|---|---|---|
| S-19 not integrated or lacks local IR-093 parity | 1–4, acceptance | Inventory and retained local tests only | S-19 merge/PR plus local PTT semantic/date/limit/delete/realtime proof; S-19 owner |
| S-23 leaves a product writer/reader/job/schema or cleanup beyond the exact Pinecone handoff | 1, 3–5, 7–8 | Provider-independent characterization only | Closed S-23 route/storage/job/account-cleanup matrix and tests; S-23 owner |
| S-25-owned service still imports private object helpers | 7–8 | Delete unrelated families only | Boundary decision showing product workload removed without empty shell; S-23/S-25 owners |
| Integrated managed STT byte adapter differs from current Modulate semantics | 6 | Keep characterization RED; do not dual-path | S-22 provider contract proving byte equivalence, bounded memory and failure mapping; S-22 owner |
| Supported released client uses `/v1/files` or hosted search | 1, 5 | Local/internal cleanup not involving entrance | Version/sunset evidence and product authorization; release/product owner |
| Unknown Pinecone namespace or hosted graph consumer | 3–4 | Known namespaces only after classification | Current caller/data-owner proof and assignment; S-23 if product, S-24 if pure provider residue |
| Generic storage helper has a retained non-update caller | 7–8 | Delete proven independent families | Concrete retained behavior/owner and narrow primitive design; owning slice |
| Update/preview bucket shares private objects or IAM | 7–8, live closure | Preserve the entire bucket boundary in repository | Read-only inventory and separation plan; S-27/S-29 plus explicit authorization |
| Live provider/resource IDs, contents, retention, contracts unknown | Operational only | Complete repository work | Verified read-only inventory, legal/backup/rollback decision, explicit mutation approval; operator/user |
| Broad import tests stub providers incidentally | 2, 4, 8 | Narrow stubs after production import graph is proven | Hermetic boot and module-pollution/import scanner evidence; backend owner |
| Account purge removal masks a real remaining authority | 3, 7 | Preserve fail-closed workflow and other purges | Complete authoritative-data matrix and failure tests; S-08/S-23/S-24 owners |

Additional absolute stops:

- a requirements-challenge/deletion-map conflict;
- a dirty or materially different implementation baseline not understood;
- a proposal to keep a disabled provider, empty namespace, no-op service,
  deprecated alias, ignored field, fake-success route, or compatibility shell;
- a proposal to migrate product data into Redis, Firestore, another bucket, or a
  new local graph rather than delete the rejected authority;
- any attempt to query/mutate production resources, activate billing, deploy,
  or touch production Mac bundles without separate authorization.

## 18. Final completion checklist

### Entry and authority

- [ ] Implementation is rebased onto integrated S-19 and S-23; exact merge
  commits and refreshed caller matrix are recorded.
- [ ] Ledger validator passes and every assigned IR is mapped to a cycle/guard.
- [ ] No decision conflict, unrelated dirty change, or supported-client sunset
  question remains unresolved.

### Retained behavior

- [ ] Local conversation hybrid search preserves keyword-first semantic/date/
  limit/result behavior, offline/restart, owner isolation, and delete/index
  maintenance for both realtime providers.
- [ ] Local Memory/task/Rewind search and transient embedding compute pass with
  hosted providers fail-on-touch.
- [ ] IR-291 screenshot deletion clears only the local link.
- [ ] Local Chat attachments preserve all IR-044 behavior with cloud files
  unavailable.
- [ ] Voice multipart/legacy/PCM behavior is unchanged and uses no GCS object.
- [ ] Account deletion, export, Redis control state, auth/quota/fair use, and
  billing-disabled behavior remain correct.
- [ ] Desktop update/preview bucket/workflows and current identity remain intact.

### Deleted authority

- [ ] Typesense production code, collection/sync, SDK, runtime/harness, config,
  credentials, tests, docs, metrics, and deployment residue are absent.
- [ ] Pinecone client, every namespace/repair path, SDK, fakes, config,
  credentials, tests, docs, metrics, and deployment residue are absent.
- [ ] `/v1/files` is genuinely 404 and absent from policy/OpenAPI/generated
  non-Windows clients; OpenAI Files/Assistants/thread/file-search and cloud
  metadata/thumbnails are absent.
- [ ] No speech/profile, postprocessing/recording, private-sync/playback,
  temporal voice, or other private product-data GCS path remains.
- [ ] No hosted graph/vector consumer or product-content Redis replacement exists.
- [ ] Shared vector/storage scaffolding is simplified only after caller proof.

### Verification and handoff

- [ ] Focused Swift/Python tests, backend/desktop component suites, hermetic boot,
  runtime-image checks, lock freshness, route policy, OpenAPI/generated Swift,
  backend test discovery, `make preflight`, and `git diff --check` pass.
- [ ] All residue searches are reviewed and intentional historical/absence hits
  are labelled.
- [ ] `omi-wave4-s24` acceptance is exercised against isolated development
  backends with semantic snapshots, restart, owner-switch, PTT, local files,
  voice, and sanitized trace evidence.
- [ ] Verification commands/results and failure-class declaration are in the
  commit/PR evidence; individual family commits remain reviewable.
- [ ] S-25 receives content-free worker/service topology and S-27/S-29 receive
  the retained Redis/account-queue/update-bucket boundaries without absorbed work.
- [ ] Live provider decommission remains a separate, named, explicitly
  authorized operational action with inventory/retention/rollback evidence.
- [ ] No Windows code, billing provider, production infrastructure, or
  production Omi/Omi Beta bundle was touched.

## 19. Integrated closeout record — 2026-08-23

S-24 implementation merged in PR #43 at `ac3ba541`. Closeout commit `a57b3f8d`
removed the remaining parity-pack GCS exporter/runtime/deployment residue while
retaining local redacted capture/replay and update/preview storage support. Its
focused behavioral and classification tests, full component suites, official
hermetic E2E runner, and complete 31/31 Tier-2 matrix are green. S-24 is
**repository-closed**. See
[`wave-3-4-closeout tdd.md`](wave-3-4-closeout%20tdd.md).
