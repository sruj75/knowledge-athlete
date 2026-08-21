# S-23 TDD plan — delete rejected hosted products and their product-data schemas

## 1. Title and slice identity

| Field | Value |
|---|---|
| Slice | **S-23** |
| Wave | **4 — delete rejected cloud products and infrastructure** |
| Name | **Delete rejected hosted products and their product-data schemas** |
| Type | Backend product teardown, split by product owner |
| Primary decisions | **IR-039, IR-043, IR-121, IR-122, IR-123, IR-186, IR-187, IR-289, IR-290, IR-310, IR-338, IR-359, IR-369 through IR-383, IR-714 through IR-725, IR-805, and IR-814 through IR-835** |
| Required implementation predecessors | **S-20 and S-22 integrated; cycle-local S-19 handoff where PTT retrieval still calls hosted conversations** |
| Named development bundle | **`omi-wave4-s23`** |
| Output boundary | This file only: `bootstrap-scaffold/wave-4/s-23 tdd.md` |
| Roadmap authority | [`../deletion-map.md`](../deletion-map.md), S-23 |
| Decision authority | [`../requirements-challenge.md`](../requirements-challenge.md) |

This is an implementation plan, not implementation or verification evidence. Writing it changes no product code, test, generated contract, schema, migration, configuration, workflow, application bundle, cloud resource, or external provider.

## 2. Planning status and pinned baseline

**Status:** blocked. The repository plan is complete, but implementation waits for the mandatory predecessor and execution-time inventory gates in §5. Repository deletion and live-resource decommissioning remain separately authorized activities.

The inspected tree is exactly the required Wave 2 closeout commit:

```text
HEAD 711269baf5e653bd62132688998732207f11dd3c
     711269ba docs: finalize Wave 2 closeout evidence
branch audit-wave-2-slices...origin/audit-wave-2-slices
additional commits after baseline: none
additional product diff after baseline: none
```

The required ancestry check passed during planning:

```bash
git merge-base --is-ancestor 711269baf5e653bd62132688998732207f11dd3c HEAD
```

The requirements validator passed during planning:

```text
Requirements ledger validation: PASS (714 indexed rows, 714 detailed sections, all reviewed)
```

Untracked S-19 through S-22 and S-24/S-25 planning documents appeared in the shared workspace during this planning pass. They are coordination evidence only: they are not product changes, integrated predecessors, or authorization to alter those files. S-23 must rebase onto the actual integrated implementation commits, not these planning artifacts.

No product test, generated-contract command, named bundle, user path, production query, or cloud operation was run while writing this plan. Every command below, except the baseline and ledger checks explicitly reported above, is future implementation evidence.

## 3. Outcome

The canonical Mac owns durable conversations/transcripts, Memories, Tasks, Goals, Chat history, Focus/Insights/Profile state, notification preferences, and relevant settings. The backend owns retained account/authentication, billing/subscription/quota/usage facts, durable account deletion, updates/previews, sanitized observability, and bounded transient managed compute. S-23 removes the rejected hosted product layer between those two authorities.

The completed repository has:

- no customer-facing route, handler, model, service, schema, generated operation, or documentation for cloud recordings/playback/training, People or persistent voice identity, public sharing/persona/shared Chat, Twilio, Wrapped, announcements, Trends, Daily Summary, Joan, cloud ratings/scores, FCM, detailed usage, wearable/glasses/Limitless products, or rejected model-specific product routes;
- no new write path into rejected Firestore product collections, product-specific Redis namespaces, conversation/audio GCS paths, or rejected schema fields;
- genuine 404s for removed routes, without aliases, no-op handlers, ignored fields, or fake-success responses;
- one simple, offline Mac **Export My Data** path for local-authoritative product content and a narrowed server export for genuine retained account/control metadata;
- the durable account-deletion lifecycle with every S-23-owned product cleanup removed, while one exact Pinecone purge/counter seam remains explicitly owned by S-24 until S-24 deletes it; Dodo cancellation, Firebase Auth deletion, retained Firestore account/control cleanup, retries/reconciliation, and privacy-bounded telemetry remain;
- retained local notifications and What's New, Sparkle updates/previews, normal Chat/PTT/realtime, local search, managed quota totals, `/v1/tts/synthesize`, pinned Gemini Flash/Lite/embeddings behavior, LangSmith, Prompt Hub, Sentry, PostHog, and account/billing behavior unchanged.

S-23 stops new product authority and removes repository product schemas. S-24 separately owns physical Typesense, Pinecone—including its deletion-worker purge—and OpenAI Files/cloud attachments/product-data GCS teardown while preserving update/preview storage. S-25 separately owns audio-merge/finalization routes and queues, Pusher, duplicate services, images, workflows, secrets, and GKE/service-topology deletion. S-23 must leave exact zero-product-caller handoffs for those slices, not empty deployments.

## 4. Authorizing requirements

The live detailed decisions were re-read. The table names every assigned decision explicitly; a changed detailed decision stops its affected cycle.

| Decision | Required S-23 result | Cycle(s) |
|---|---|---|
| **IR-039** | Daily Summary remains completely absent; delete any returned scheduler, settings, history, sharing, model, FCM, schema, or documentation residue while preserving local Insights/Focus/Profile and local notifications. | 12, 18 |
| **IR-043** | Delete cloud user ratings; retain operator LangSmith evaluation. | 7, 14 |
| **IR-121** | Delete cloud raw chunks, recording/audio-file/playback authority and associated product schema; preserve live mic/System Audio STT, local transcripts, PTT/TTS, and Rewind. | 1, 2 |
| **IR-122** | Delete Store Recordings and Private Cloud Sync state, APIs, Firestore fields, Pusher product branches, generated contracts, and UI residue. | 1, 2 |
| **IR-123** | Delete training opt-in state, routes, submission notification, and storage/config residue. | 1 |
| **IR-186** | Remove S-23-owned Twilio, product GCS recording, cloud-memory, and Stripe-specific cleanup in Cycle 16; preserve one exact Pinecone purge handoff for S-24, which removes it under IR-807. Keep Dodo/Firebase/retained Firestore/reliability/telemetry. | 16; S-24 C3–C4 |
| **IR-187** | Keep the current bodyless delete-account contract and ensure `reason`/`reason_details` stay absent; do not weaken durable deletion. | 16 |
| **IR-289** | Delete `reviewed`, `userReview`, and scoring from live Memory API/schema/cache/product behavior; preserve confidence/read/dismiss/lifecycle. | 7 |
| **IR-290** | Never persist a durable Memory headline; preserve transient Insight headline presentation and local notification fallback. | 7 |
| **IR-310** | Keep Copy Transcript; keep public sharing/Copy Link and reciprocal hosted links absent. | 6, 8 |
| **IR-338** | Delete per-conversation billing lock/redact/unlock semantics; enforce before paid compute and never hide a local transcript. | 5 |
| **IR-359** | Delete wearable conversation photos and `image_chunk`; preserve PTT screenshot, Rewind, and Chat image attachments. | 4 |
| **IR-369** | Delete hosted product-content protection levels, `ENCRYPTION_SECRET` content helpers, migrations, and fields; do not claim local database encryption. | 5 |
| **IR-370** | Delete conversation/Memory `client_device_id` and `client_platform`; preserve narrowly proven auth/abuse/update/metrics device identity. | 5 |
| **IR-371** | Delete model-extracted People/topics/entities/dates and hosted filter catalogs; preserve local FTS, local embeddings, and date search. S-24 owns physical vector/search teardown. | 6 |
| **IR-372** | Delete whole-recording postprocess/retranscription/provider comparison; preserve live STT, generic diarization, local labels, PTT, and retained file transcription. | 2, 4 |
| **IR-373** | Delete Firestore transcript compression and hosted parity cases; preserve local segment rows and the mixed `desktop-core-e2e-t0` self-check. | 2, 5 |
| **IR-374** | Delete hosted processing IDs and memory aliases/events; preserve local lifecycle authority. | 5 |
| **IR-375** | Delete Google Calendar event linking and hosted meeting context; preserve local model-extracted commitments without external calendar writes. | 6 |
| **IR-376** | Delete hosted summary PATCH request/model. | 6 |
| **IR-377** | Delete hosted transcript-text PATCH request/model. | 6 |
| **IR-378** | Delete hosted speaker analytics. | 3, 6 |
| **IR-379** | Delete hosted test-prompt endpoint/model. | 6 |
| **IR-380** | Delete hosted `speaker_id` search. | 3, 6 |
| **IR-381** | Delete the broad hosted `ConversationSource` enum; preserve local input-device name, STT diagnostics, location, and typed merge provenance. | 5 |
| **IR-382** | Delete `speech_profile_processed` and `current_session_segments`; preserve generic diarization and local manual speaker names. | 3 |
| **IR-383** | Delete unused `ImprovedTranscriptSegment` and `ImprovedTranscript`. | 3 |
| **IR-714** | Consume S-22's deletion of callerless ElevenLabs `/v2/tts/synthesize`; preserve OpenAI `/v1/tts/synthesize` and its shared Redis limiter. | 15, 18 |
| **IR-715** | Consume S-22's deletion of Perplexity/Sonar and exclusive support. | 15 |
| **IR-716** | Consume S-22's public-web deletion; leave its separate failure-class dormancy PR/history intact. | 15 |
| **IR-717** | Consume deletion of Gemini Pro admission and soft downgrade; preserve Flash/Lite/embeddings. | 15 |
| **IR-718** | Consume deletion of `/v1/proxy/gemini-stream/{path}` and `streamGenerateContent`; preserve normal non-stream generation and embeddings. | 15 |
| **IR-719** | Preserve the legacy `gemini-3-flash-preview` to `gemini-2.5-flash` request rewrite. | 15 |
| **IR-720** | Delete OpenRouter only after Wrapped is deleted and no retained caller remains. | 10, 15 |
| **IR-721** | Preserve Gemini Flash-Lite transient Chat title compute with local commit. | 15 |
| **IR-722** | Preserve GPT-5.4-mini transient greeting compute with local commit. | 15 |
| **IR-723** | Keep cloud Mentor/App proactive models absent; preserve local assistants using the retained Gemini path. | 13, 15 |
| **IR-724** | Delete GPT-personalized FCM copy; expose structured authoritative state and present fixed truthful Mac-local copy. | 13 |
| **IR-725** | Keep OpenGlass/smart-glasses compute absent; delete product image residue while preserving Mac image surfaces. | 4, 15 |
| **IR-805** | Keep Sentry diagnostics/reporting/symbolication; keep the Sentry-to-cloud-Task bridge absent. | 14, 18 |
| **IR-814** | Accept S-14's Notifications-job deletion; preserve local reminders and retained warnings. S-25 owns any independently deployed residue. | 13, 18 |
| **IR-815** | Accept S-12's memory-maintenance-job deletion; preserve local Memory lifecycle. S-25 owns deployed residue. | 18 |
| **IR-816** | Keep public Persona/clone product absent; preserve private local AI Profile. S-25 owns deployed site/service residue. | 8, 18 |
| **IR-817** | Keep `backend-integration` product API/source absent; preserve canonical auth/webhooks/compute. S-25 owns duplicate-service residue. | 18 |
| **IR-818** | Keep hosted Plugins workflow/service/source absent; preserve local managed Pi/plugin behavior. S-25 owns deployed residue. | 18 |
| **IR-819** | Delete Twilio routes, verified-number records, call quota/config/usage, `call_id`, credentials/dependency, and deletion cleanup; preserve meeting capture/PTT. | 9, 16 |
| **IR-820** | Delete Wrapped routes, status/data/generator/model caller and exclusive support. | 10 |
| **IR-821** | Delete cloud announcements; preserve repository changelog, local What's New, Sparkle, and version comparison needed by app-review policy. | 11 |
| **IR-822** | Delete Trends route/data/model residue. | 12 |
| **IR-823** | Keep wearable firmware route/source absent; preserve Sparkle desktop update behavior. | 18 |
| **IR-824** | Keep hosted Limitless import absent; do not invent a cloud compatibility importer. | 18 |
| **IR-825** | Keep task productivity/daily-score routes and schema absent; preserve local Tasks/Goals without numeric productivity scoring. | 14, 18 |
| **IR-826** | Delete FCM endpoints/token stores/builders/batching and adapt surviving fair-use/usage warnings to authenticated Mac state plus local `UNUserNotificationCenter`. | 13 |
| **IR-827** | Preserve LangSmith tracing/evaluation under its retained privacy boundary. | 14, 15 |
| **IR-828** | Preserve Prompt Hub with its repository fallback. | 15 |
| **IR-829** | Keep hosted mentor-notification settings absent; preserve local proactive controls. | 13, 18 |
| **IR-830** | Add complete offline local Export My Data and narrow server export to genuine retained account/control metadata. | 17 |
| **IR-831** | Keep detailed LLM/product-usage reader/self-report routes absent; preserve server writers and totals required by quota, support, Account, and fair use. | 14 |
| **IR-832** | Preserve LangSmith website/operator evaluation without restoring user ratings. | 7, 14 |
| **IR-833** | Delete summary-rating routes, analytics documents/helpers, generated operations, and exclusive tests. | 7 |
| **IR-834** | Delete Joan follow-up route/helper/model caller and exclusive data/tests. | 12, 15 |
| **IR-835** | Keep authoritative subscription/quota/usage-total/fair-use/account-card behavior; keep detailed `/v1/users/me/usage` absent. | 14 |

The live requirements challenge and deletion-map product decisions agree. The shared-owner order is resolved mechanically in §5 and §12: S-22 closes with one exact Wrapped/OpenRouter handoff; S-23 deletes both together; S-24 owns Pinecone including its deletion purge; and S-25—not S-23—owns operational worker/service teardown.

## 5. Dependencies and entry gates

### G0 — execution-time rebase and fresh inventory

Before the first RED:

1. Run `make setup` before the first commit, fetch the target branch, keep the current branch name, and integrate current `origin/main` while preserving `711269ba` ancestry.
2. Record `HEAD`, `origin/main`, status, and `git diff origin/main...HEAD`; rerun the requirements validator.
3. Require the actual S-20 and S-22 implementation commits—not planning files—to be ancestors. Reread their closeout evidence and rerun every inventory in §§6, 7, and 13.
4. Run current focused backend, Swift, Node, OpenAPI, route-policy, account-deletion, and export tests to separate pre-existing failures from intended REDs.
5. Run `scripts/pr-preflight --suggest` after the intended diff exists. A `fix:` commit must declare and validate its failure class; a new static guard needs a real incident/merged-PR citation.

Stop if the Wave 2 baseline is missing, a requirements decision changed, an unclassified retained caller exists, or a released external client is proven. This unreleased fork does not get a compatibility shell.

### G1 — S-20 fair-use/notification handoff

S-20 must first establish content-free enforcement state and its authenticated Mac interaction. Cycle 13 consumes that exact structured state; it must not recreate the classifier, alter thresholds/strikes/restriction timers, or continue sending FCM because local delivery is unfinished. Before FCM deletion, prove a retained Mac can receive or fetch every authoritative fair-use and managed-usage transition needed for in-app copy and local OS notification, including restart/reconnect and deduplication. If S-20 exposes no stable authenticated delivery/read seam, Cycle 13 stops for a cross-slice contract correction; it may not add a second shadow status API.

### G2 — S-22 model portfolio handoff and Wrapped/OpenRouter order

S-22 must integrate every independent retained-model and provider change first: explicit retained callers/result owners, Flash/Lite/embedding proxy, direct Chat/greeting/title/conversation/Memory/translation compute, deletion of Perplexity/public web/ElevenLabs/Pro/streaming/gateway application mediation, and LangSmith/Prompt Hub fences.

Wrapped still calls `get_llm('wrapped_analysis')` through OpenRouter. The deletion map fixes the integration shape:

1. S-22 closes its owned portfolio and records OpenRouter as the single live Wrapped-only handoff.
2. S-23 Cycle 10 deletes Wrapped vertically and removes the now-exclusive `wrapped_analysis`/OpenRouter application binding under IR-720.
3. S-23 runs S-22's retained-provider regression suite and proves OpenRouter has no remaining caller. S-22 is not reopened.

No temporary provider adapter, dormant alias, or no-op Wrapped route is permitted.

### G3 — S-19 PTT hosted-conversation callers

The Wave 2 closeout intentionally leaves `/v1/tools/conversations`, `/search`, and `/search-chunks` for S-19. S-23 is not allowed to remove their hosted conversation/search dependencies while PTT still calls them. Cycles 3 and 6 may proceed only after S-19 has moved retained PTT listing/search/tool behavior to local owners and supplied its caller-absence proof. Other S-23 families are not blocked by this gate. If the routes remain live at rebase, leave them owned by S-19 and do not claim final S-23 closure.

### G4 — account lifecycle and export handoff

S-08 owns the auth/session, durable deletion admission/worker contract, and final cross-domain export acceptance; S-18 supplies the retained Dodo cancellation seam while `BILLING_MODE=disabled` remains the repository state. S-23 owns removal of rejected product cleanup/readers and implements the dependency-gated S-08 acceptance contracts in Cycles 16-17. Stop if Dodo cancellation is not available at the retained interface, if the current recursive Firestore deletion allowlist is unresolved, or if a local domain lacks a complete owner-scoped export reader. Do not weaken deletion or dump raw databases to make export appear complete.

### G5 — S-24/S-25 boundary

- S-23 removes product callers, model/schema fields, database modules, product-path helpers, generated contracts, exclusive configuration, and new-write authority.
- S-24 removes physical Typesense/Pinecone/OpenAI Files/cloud-attachment/product-data GCS authority and the exact Pinecone purge/counter seam handed off from S-23. The GCS update/preview bucket is protected.
- S-25 removes `/v2/audio-merge-jobs/run`, `/v1/conversation-finalization-jobs/run`, their queues/reconcilers/timeouts, Pusher, hosted VAD/speech-profile service, standalone diarizer, duplicate services, images, workflows, secrets, and GKE/control-plane residue.

S-23 may make S-25 routes/services callerless, but must not replace them with no-ops or delete their independently deployed topology. A worker that cannot safely remain functional until S-25 is a stop requiring coordinated owner order, not permission to absorb S-25.

There is no staged-close loop. S-23 Cycle 16 removes every S-23-owned cleanup branch after its product writers/stores are gone and preserves one typed, tested Pinecone purge/counter seam as an exact S-24 handoff. S-23 then closes without reopening. S-24 consumes the closed S-23 result and deletes Pinecone plus that deletion-only seam under IR-807. S-25 executes after both. An additional product cleanup or a generic provider abstraction is a closure defect, not a permitted handoff.

### G6 — repository versus live state

The checkout cannot prove current Firestore documents, Redis keys, GCS objects, queues, revisions, Secret Manager values/bindings, IAM, provider accounts, or retention/legal obligations. Repository cycles may land after their code gates. Live inventory is read-only and separately authorized; any mutation requires explicit authorization and the procedure in §16.

## 6. Current production codeflow

This is the verified pre-S-20/S-22 flow at `711269ba`; it must be refreshed after G0.

### 6.1 Mixed FastAPI entrypoint and generated surface

```text
backend/main.py
  -> mounts retained auth/payment/update/metrics/listen/realtime/Chat/TTS/compute
  -> also mounts notifications, speech_profile, trends, sync,
     calendar_meetings, wrapped, announcements, phone_calls, legacy tts,
     hosted Chat report, Joan and memory-summary rating
  -> starts account-deletion reconciliation (KEEP)
  -> starts listen-finalization/stale-processing reconciliation (S-25 later)

FastAPI app-client schema
  -> docs/api-reference/app-client-openapi.json
  -> Desktop/Sources/Generated/OmiApi.generated.swift
```

The committed app-client schema still exposes announcements, Twilio phone routes, FCM token, summary rating, Wrapped, `/v2/tts/synthesize`, and v3/v4 speech-profile operations. `route_policy_manifest.yaml` still contains Gemini streaming and retained/shared route records. Generated Swift is non-Windows and in S-23 scope; Windows code and `pylock.windows.toml` are not.

### 6.2 Cloud recording, playback, training, and hosted conversation lifecycle

```text
legacy settings/profile fields
  -> users.store_recording_permission / private_cloud_sync_enabled /
     training_data_opt_in / data_protection_level
  -> Pusher/listen/finalization branches
  -> utils.other.storage upload_audio_chunk(s)
  -> private-cloud GCS chunks + ENCRYPTION_SECRET branch
  -> Firestore users/{uid}/conversations/{id}
       transcript_segments_compressed, audio_files, conversation_audio,
       processing_memory_id/processing_conversation_id, status, lock,
       protection, source, device, external data
  -> audio-merge/finalization jobs
  -> playback artifacts and notifications
```

`models/conversation.py`, `database/conversations.py`, `utils/conversations/**`, `services/conversation_finalization.py`, `database/conversation_finalization_jobs.py`, `routers/sync.py`, `utils/sync/playback.py`, `routers/pusher.py`, and `utils/other/storage.py` still form a hosted product graph. S-10 already removed ordinary Mac conversation callers and made GRDB authoritative; current server callers are legacy product/tool/worker paths. S-23 deletes product authority and fields. S-24 owns physical object/search stores. S-25 owns finalizer/audio-merge/Pusher route, queue, deployment, and service removal.

### 6.3 Persistent People and voice identity

```text
/v3/speech-profile, /v4/speech-profile, /v3/upload-audio,
/v3/speech-profile/expand
  -> database.users People/speaker embedding/sample helpers
  -> utils.other.storage speech_profile.wav,
     additional_profile_recordings/, people_profiles/
  -> Redis users:{uid}:speech_profile_duration
  -> Modal speech-profile classifier / Pusher speaker paths
  -> TranscriptSegment.person_id, speaker_id, speech_profile_processed
```

The Mac already owns conversation-scoped generic labels and local manual names. S-10/S-16 removed listen's reusable identity dependency. Hosted speech-profile routes, People storage, embeddings, samples, matching, and generated DTOs remain real current residue. S-25 later deletes the independently deployed hosted VAD/speech-profile and diarizer services while preserving in-process VAD and provider-returned generic labels.

### 6.4 Conversation metadata, retrieval, mutation, and Calendar residue

`ConversationSource` still enumerates Omi devices, phone, OpenGlass, Limitless, workflow, onboarding, and other rejected origins. `ConversationMetadata` still has People/topics/entities/dates. Hosted models still include `UpdateSegmentTextRequest`, `UpdateSummaryRequest`, `SearchRequest.speaker_id`, `TestPromptRequest`, `SpeakerAnalytics`, `ImprovedTranscript*`, and calendar/external-data fields. Redis still carries in-progress-memory aliases, meeting links, metadata filter catalogs, migrated retrieval IDs, lock/notification keys, and protection-level cache.

`calendar_meetings.py` currently writes external calendar event identity, participant data, links, notes, and times to `users/{uid}/meetings`; `process_conversation.py` can attach that context through `external_data`. The exact manual Google link/unlink routes described by IR-375 are already absent, but this remaining hosted meeting context is the same rejected product authority and has no Mac caller.

S-19 still owns current PTT hosted conversation tool calls. S-24 owns physical Typesense/Pinecone deletion after those callers migrate.

### 6.5 Memory feedback and cloud Chat residue

The live Mac `memories` table has already been rebuilt without visibility/review/scoring/headline authority; historical migration source strings remain only to construct and transform inherited schemas. `InsightModels`/`InsightAssistant` still use a transient headline for local presentation and local notification fallback, which is required.

The backend still mounts GET/POST `/v1/users/analytics/memory_summary` and writes an `analytics` document. Generated Swift exposes both operations. Hosted Chat persistence is otherwise removed from normal Mac use, but `/v1/messages/{message_id}/report`, `/v2/messages/{message_id}/report`, `database.chat.get_message/report_message`, and `iter_all_messages` for server export remain. These are S-11's explicit S-23 handoffs.

### 6.6 Independent hosted products

- **Twilio:** six `/v1/phone/**` operations, verified-number/pending-verification Firestore state, phone-call Redis monthly usage, plan-specific call config/quota, `PhoneCallQuota` in subscription, `Conversation.call_id`, Twilio credentials/dependency/tests, and account-deletion caller-ID cleanup.
- **Wrapped:** GET/POST `/v1/wrapped/{year}`, Firestore status/progress/result, background generation, `utils/wrapped/generate_2025.py`, and `wrapped_analysis` through OpenRouter.
- **Announcements:** public/user/admin CRUD and dismiss routes, `announcements` plus `dismissed_announcements` Firestore data, models/tests, app-client operations. `database.app_review_config` imports announcement `compare_versions`, so semantic comparison is a retained shared primitive that must move before the product module is deleted.
- **Trends/Joan:** `/v1/trends`, trends database/model/extractor residue, `/v1/joan/{memory_id}/followup-question`, and a retained-model `followup` caller. Daily Summary routes are already absent and protected by S-14.
- **FCM:** `/v1/users/fcm-token`, arbitrary `/v1/notification`, `users/{uid}/fcm_tokens` plus legacy migration, Firebase Admin message builders/batching/invalid-token cleanup, cloud notification helpers, generated method, tests, and product callers including fair-use and managed usage.

### 6.7 Account deletion and export

```text
DELETE /v1/users/delete-account
  -> durable intent + Cloud Task + OIDC worker + retry/reconciler
  -> Dodo/legacy billing cancellation
  -> Firebase Auth deletion
  -> Twilio caller IDs
  -> Pinecone/vector + GCS recordings + cloud-memory derived purge
  -> recursive retained/rejected Firestore subcollections
  -> completion/failure telemetry with vector/recording counters

GET /v1/users/export
  -> iter_user_data_export
  -> profile + hosted conversations + People + hosted Chat messages
  -> streamed omi-export.json
```

The request body is already removed and legacy JSON is ignored, satisfying IR-187's public shape. The worker reliability boundary is retained; its rejected cleanup composition is not. The server export is incomplete for a local-authoritative product. The Mac has no Export My Data action, although `TranscriptionStorage.conversationArchivePage`, `MemoryStorage.list`, `ActionItemStorage.getLocalExportPage`, `GoalStorage.getLocalExportPage`, `ProactiveStorage.getFocusSessions`, `MemoryStorage.listInsights`, and kernel catalog/journal list operations provide most required owner-scoped seams.

### 6.8 Already-absent families

Current executable source has no Daily Summary router, Persona router, firmware router, Limitless importer, daily/task score router, hosted Memories router, Notifications job source, memory-maintenance job source, `gcp_backend_integration.yml`, or `gcp_plugins.yml`. Existing S-06/S-10/S-12/S-13/S-14 tests protect much of that absence. S-23 accepts these as negative predecessor evidence, deletes only reintroduced/exclusive residue, and does not create no-op replacement cycles. S-25 owns any separately deployed live/service residue.

## 7. Complete caller and dependency inventory

The inventory below is complete for the pinned source tree. G0 must refresh it because S-20/S-22 will materially change shared files.

| Family/layer | Current confirmed owners and callers | S-23 disposition / successor |
|---|---|---|
| Main route registration | `backend/main.py`; `routers/{notifications,speech_profile,trends,sync,calendar_meetings,wrapped,announcements,phone_calls,tts,desktop_proxy,users,chat}.py` | DELETE customer product mounts; S-25 owns operational worker mounts and startup loops |
| Recording settings/state | `database/users.py` store/private/training/protection helpers; `UserProfileResponse`; Pusher/listen callers | DELETE fields/helpers/callers after local-authority proof |
| Audio/product objects | `utils/other/storage.py`; `models/audio_file.py`; `models/sync_audio.py`; `utils/sync/playback.py`; recording-session and playback tests | DELETE product-path calls/schema; S-24 physical GCS; S-25 queue/worker |
| Hosted conversation persistence | `database/conversations.py`, folders/cache helpers, lifecycle/live-content/render/factory/search/analytics/transcript-chunks/process/postprocess/merge/finalizer modules | DELETE product authority as callers vanish; preserve only independently proven transient compute primitives |
| Finalization/audio merge | `routers/conversation_finalization.py`, `services/conversation_finalization.py`, `database/conversation_finalization_jobs.py`, `routers/sync.py`, timeouts/startup loops/cloud-task config | Make callerless and hand to S-25; do not no-op or delete topology here |
| Pusher/listen side effects | `routers/pusher.py`, `pusher/**`, `listen_pusher_session.py`, `pusher_protocol.py`, `pusher_finalization.py`, charts/workflows | Remove S-23-owned product branches only when separable; S-25 deletes protocol/service/deploy |
| People/voice identity | `routers/speech_profile.py`; `database/users.py` People/embedding/sample helpers; `utils/stt/speech_profile.py`; speaker-identification/assignment/sample modules; Modal; storage paths; Redis; tests/generated | DELETE product route/data/schema; S-25 hosted service/deploy |
| Generic diarization/local names | transient STT segments, provider generic labels, local Mac speaker naming | KEEP AS IS; never delete with People |
| Conversation schemas | `models/conversation.py`, `conversation_enums.py`, `conversation_metadata.py`, `transcript_segment.py`, `structured.py`, `conversation_summary.py` and deserializers/tests | DELETE rejected fields/types after caller proof; keep transient compute request/response shapes with retained owners |
| Hosted retrieval | `/v1/tools/conversations*`, retrieval tool services, `database/vector_db.py`, metadata/filter Redis | CONSUME S-19 caller migration; delete product metadata/readers; S-24 physical search/vector |
| Calendar context | `backend/routers/calendar_meetings.py`, `backend/database/calendar_meetings.py`, `models/calendar_context.py`, document ID helper, process/finalization prompt context/tests | DELETE hosted routes/data/schema; preserve local commitments only |
| Memory feedback | user summary-rating routes/models/helpers; analytics documents; generated client/tests | DELETE; preserve Mac confidence/read/dismiss/lifecycle and LangSmith eval |
| Memory live migration history | `RewindDatabase.swift`, `RewindDatabase+MemoryLocalAuthority.swift`, migration tests | KEEP historical migration bodies only where tests prove final live columns absent |
| Shared Chat report/export | two message-report routes, `database/chat.py` report/read/export helpers, report tests | DELETE after no retained caller; S-24 separately owns hosted files/OpenAI Files |
| Twilio | phone router/database/config/usage/utils, `models/users.py`, subscription response, `Conversation.call_id`, requirements/env, tests, account deletion | DELETE vertically; keep PTT/meeting capture |
| Wrapped | router/database/generator/model config/OpenRouter/app-client/tests | DELETE vertically; coordinate OpenRouter with S-22 |
| Announcements | router/database/model, app review config import, Firestore collections, generated/tests/docs | Move version compare to retained owner, then DELETE cloud product; keep local changelog/What's New/Sparkle |
| Trends/Daily Summary/Joan | trends route/database/model/LLM helper; Joan route/followup; S-14 negative Daily Summary tests | DELETE live Trends/Joan; preserve Daily Summary absence and local siblings |
| FCM/cloud copy | notifications router/db/utils/model, Redis notification keys, fair-use and product callers, integration/unit tests, generated | ADAPT retained warnings to Mac, then DELETE FCM |
| Scores/Sentry bridge | negative route tests, dashboard E2E denied network paths; retained Sentry SDK/reporting | Preserve absence; delete only residue; keep local Tasks/Goals and Sentry |
| Usage | subscription/usage-quota/trial/paywall/LLM total and their stores/callers; detailed route already absent | KEEP retained totals/admission; preserve detailed-reader absence |
| Account deletion | route, durable service, `database/users.py`, Cloud Tasks config/reconciler/tests | ADAPT composition only; S-24 removes physical vector/object cleanup; S-25 retargets task/topology |
| Local export | local GRDB stores, kernel catalog/journal, Account Settings, save-panel pattern in `FeedbackView` | ADD one deep owner-fenced exporter and UI; do not reuse diagnostics or rejected `MemoryExportService` |
| Server export | users route/model, `services/users/data_export.py`, conversations/People/Chat readers/tests/generated | NARROW to retained metadata; delete product readers |
| OpenAPI/generated policy | `docs/api-reference/app-client-openapi.json`, `Generated/OmiApi.generated.swift`, route-policy manifest/baseline, exporter/generator/response-model checks | Regenerate after every route family; no Windows generated client changes |
| Firestore registry | `firestore.indexes.json` conversation indexes; `firestore.rules`; database collection strings; recursive account deletion | Remove exclusive repository indexes/rules/schema references; retain generic recursive deletion and retained fair-use/account/billing indexes |
| Redis namespaces | recording/phone/speech-profile/notification/conversation metadata/protection keys plus retained auth/rate-limit/quota/fair-use/TTS keys | DELETE only exclusive namespaces; retain shared limiter and account/control keys |
| Runtime/config/dependencies | env templates, `runtime_env.yaml`, charts, requirements/locks, test selectors/typecheck/fixtures, docs | Remove S-23-exclusive application bindings; S-24/S-25 own physical/deploy bindings |
| Observability | Sentry/PostHog/LangSmith/Prompt Hub, product-specific analytics/logs/metrics | KEEP retained tools; DELETE rejected product events/counters without logging raw PII |
| macOS retained paths | conversations, Memory, Tasks/Goals, Chat, Focus/Insights/Profile, local notifications, PTT/realtime, Rewind, Settings, updates | KEEP behavior; add export only; generated-client deletions must not break handwritten callers |

## 8. Behavior classification table

| Category | Behavior |
|---|---|
| **KEEP AS IS** | Local Mac authority and user behavior for conversations/transcripts, Memories, Tasks/Goals, Chat, Focus/Insights/Profile, search, notifications/preferences, PTT/realtime, Rewind, local speaker names, offline/restart/account-switch behavior; retained backend auth/account, disabled billing, subscription/quota/usage totals/fair use, durable account deletion, managed STT/models, `/v1/tts/synthesize`, non-stream Flash/Lite/embeddings, exact `gemini-3-flash-preview` rewrite, updates/previews/Sparkle, Sentry/PostHog/LangSmith/Prompt Hub, generic rate limiting, sanitized logs. |
| **ADAPT** | Surviving fair-use/managed-usage warnings from FCM to authenticated structured state plus fixed Mac in-app/local OS delivery; account-deletion cleanup to retained Dodo/Firebase/Firestore plus one exact S-24-owned Pinecone purge handoff; user product-data export to a complete owner-fenced offline Mac file and server metadata-only response; retained app-review semantic version comparison out of the announcements module; shared registries narrowed as owners disappear. |
| **DELETE** | Every complete rejected product family named in §3 and its route, handler, service, model, product schema, collection/index, product-path helper, Redis namespace, generated operation, exclusive dependency/config/test/fixture/analytics/runbook/docs; server product-content export readers; rejected cleanup branches/counters. |
| **SIMPLIFY AFTER** | Once family tests are green, collapse shallow hosted conversation/People/notification/data-export modules that have no retained caller; narrow shared storage/Redis/user models and imports; remove compatibility aliases and duplicate response shapes; keep only deep retained compute/account modules. No performance rewrite is required. |
| **ACCELERATE AFTER** | Measure family-focused backend tests, generated-contract refresh, and named-bundle retained-path checks after each product GREEN. Improve only a repeated measured bottleneck; otherwise `none`. |
| **AUTOMATE LAST** | After the product-owner matrix is stable, add only a deterministic recurring route/schema/residue check to an existing local and CI lane with a cited real failure; otherwise `none`. |
| **OUT OF SCOPE / DEFERRED** | S-19 PTT lifecycle/tool migration; S-20 classifier semantics/thresholds/state machine; S-21 shell; S-22 retained model/provider semantics except the explicit Wrapped/OpenRouter handoff; S-24 physical Typesense/Pinecone/OpenAI Files/product-data GCS deletion and update/preview protection; S-25 jobs/workers/services/images/workflows/queues/secrets/GKE; S-26 entrypoint consolidation; S-27 live platform; S-28 namespaces; S-29 release infrastructure; S-30 rebrand/copy; S-31 release acceptance; Dodo activation; Windows; live-resource mutation. |

## 9. Retained behavioral invariants

1. Mac-local product records remain authoritative and owner-scoped. Deleting cloud products never uploads, mirrors, or rehydrates local content.
2. Every async local export read uses one captured `RuntimeOwnerAuthorizationSnapshot`; owner change, sign-out, or same-UID generation change rejects late work and leaves no partial destination.
3. `/v4/listen`, PTT/file transcription, both realtime providers, generic speaker labels, translation, Chat, TTS, and retained compute keep their current input/output and failure semantics.
4. Removing People/voice identity never removes conversation-scoped generic diarization or local manual names.
5. Removing cloud recording/playback never removes live mic/System Audio capture, local transcript rows, PTT audio, TTS playback, Rewind media, or Chat image attachments.
6. Quota/fair-use/billing admission happens before paid compute; a local transcript is never hidden, locked, redacted, or made conditional on entitlement.
7. FCM deletion happens only after every retained warning has an authenticated structured state seam and deterministic Mac in-app/local OS delivery. No LLM personalizes warning copy.
8. Local task reminders, proactive overlay notifications, and local What's New remain distinct from FCM/cloud announcements.
9. `/v1/users/me/subscription`, `/usage-quota`, trial/paywall, total managed-cost, and server-side usage writers remain authoritative; detailed self-report/readers stay absent.
10. Disabled billing remains incapable of provider transactions or entitlement grants. S-23 does not activate Dodo or restore Stripe.
11. Account deletion remains durable, idempotent, OIDC-protected, retryable, reconciled, and observable. A cleanup failure cannot be marked complete.
12. Recursive Firestore deletion remains the retained account-control safety net; rejected product modules are not retained merely for cleanup.
13. The server export never claims Mac-local content authority. Local export works without product network access and server failure cannot block it.
14. Export is versioned, deterministic, paged/bounded-memory, atomically replaced, and excludes tokens, Keychain, provider secrets, raw logs/diagnostics, caches, internal sync flags, temporary files, and unrelated binaries.
15. Historical local migration strings may remain only when they build an inherited schema and a behavioral migration test proves the final live schema excludes the retired field. They are not live compatibility APIs.
16. Deleted HTTP operations genuinely return 404 from the assembled production app and disappear from OpenAPI/generated Swift/route policy. Authentication failure is not accepted as proof of deletion.
17. Shared primitives stay only with an enumerated retained caller. `firebase-admin`, Redis, Firestore, GCS update/preview publication, semantic version comparison, TTS limiter, metrics, and observability are not deleted by name alone.
18. Product-specific fallback/fail-open branches use existing `record_fallback`/`recordFallback` only if a retained behavior still changes correctness/provider/mode; dead product counters are deleted.
19. No raw sensitive product content, phone number, transcript, participant, export bytes, provider response, secret, or token enters logs/telemetry.
20. Repository deletion never implies live data/resource deletion, and no production Omi app or production account is used for acceptance.

## 10. Target authority, result ownership, and service-topology model

```text
OWNER MAC (durable product data)
  omi.db / GRDB                 kernel SQLite + local files/preferences
  conversations + segments     Chat sessions + turns + attachments
  Memories + local vectors     Focus / Insights / Profile
  Tasks + Goals                notification preferences/history
  relevant settings            versioned Export My Data JSON

                         bounded authenticated requests/results
                                      <->

OWNER CANONICAL BACKEND (retained control + transient compute)
  Firebase auth/account metadata       Dodo-disabled billing projection
  subscription/quota/usage/fair-use    durable account deletion
  transient STT/model/TTS/realtime     updates/previews
  Sentry/PostHog/LangSmith/metrics      no durable private product content

ZERO PRODUCT OWNER
  recordings/playback/training, People/voice identity, public sharing/persona,
  Twilio, Wrapped, announcements, Trends/Daily Summary/Joan, FCM, ratings/scores,
  wearable/glasses/Limitless, detailed usage, rejected model routes

SUCCESSOR HANDOFFS
  S-24: physical search/vector/file/product-object storage
  S-25: workers/queues/Pusher/duplicate services/images/workflows/secrets/GKE
```

Result ownership is explicit:

- transient conversation/Memory/Chat proposals return to the Mac and become durable only through their canonical local store;
- fair-use and managed-usage facts remain server-authoritative, while presentation and OS notification are Mac-local;
- account metadata/subscription/usage export remains server-owned, while product-content export remains Mac-owned;
- deletion intent/job/tombstone remains Firestore-owned until S-25/S-27 retarget and platform acceptance;
- a product with no owner has no route, schema, bucket path, Redis key, generated method, or service compatibility layer.

During S-23 the source topology may still contain functional operational drain workers owned by S-25. They are enumerated handoffs, not surviving product authorities and not S-23 closure exceptions hidden in a generic “legacy” bucket.

## 11. Ordered TDD cycles

All cycles begin after G0; cycle-local gates are named explicitly. Each static residue assertion supplements, but never substitutes for, the behavioral RED.

### Cycle 1 — delete recording consent, private sync, and training opt-in

- **Intended behavioral RED:** Through the assembled FastAPI app and user/profile serialization, assert recording/private-sync/training routes are 404, the user profile has no corresponding product fields, and transient `/v4/listen` plus local capture remain usable. Strict database substitutes must fail the test if any request reads/writes `store_recording_permission`, `private_cloud_sync_enabled`, `training_data_opt_in`, or a training-submission notification.
- **Why it fails before implementation:** route removal from S-10 did not remove `database/users.py` helpers, profile/config fields, Pusher branches, notification helper, storage/config/tests, or indirect schema readers.
- **Minimum GREEN:** delete the complete settings/state/caller branch and generated/exclusive support without altering capture or STT.
- **Retained behavior protected:** local microphone/System Audio capture, local transcripts, PTT, local notification preferences, consent truth, and transient listen failure behavior.
- **Owner before -> after:** Firestore user fields/Pusher product branches -> no hosted owner; Mac local capture settings remain owner.
- **Expected change:** user database/profile models, Pusher product call sites where separable, notification helper, env/docs/tests/generated output; new behavioral `test_s23_recording_preferences_retirement.py`; existing S-10/listen/capture tests.
- **Focused verification:** focused new backend test, `test_s10_conversation_surface_retirement.py`, listen transient tests, and named-bundle local capture smoke.
- **Deletion/simplification enabled:** training-only notification/config and dead user-profile fields disappear; audio artifact code becomes isolated for Cycle 2.
- **Stop:** any retained caller still needs a field, S-20 warning state is confused with training notification, or removing a Pusher branch requires deleting S-25-owned service topology.

### Cycle 2 — delete cloud recording/playback data authority and product writers

- **Intended behavioral RED:** A real local capture/finalize path completes with product network unavailable and creates a local conversation, while strict backend fakes observe no Firestore conversation/audio write, GCS chunk/recording/playback upload, transcript compression, or new audio-merge/finalization task. A removed playback/product operation is genuine 404.
- **Why it fails before implementation:** hosted conversation/audio models, storage helpers, processing/finalization writers, playback artifacts, compression, recording sessions, and task producers still exist even though ordinary Mac authority moved local.
- **Minimum GREEN:** remove new-write/product-read paths, audio fields/models, product GCS helper calls, playback construction, compression compatibility, and exclusive tests/config. Leave any still-functional S-25 drain route/queue explicitly owned and callerless; do not turn it into a no-op.
- **Retained behavior protected:** local capture/finalization/list/detail/search, PTT/file STT, TTS, Rewind, generic live segments, provider timeout/failure, and S-25 rollback/drain safety.
- **Owner before -> after:** Firestore/GCS recording product -> local `TranscriptionStorage`; operational route/queue ownership -> S-25 pending deletion.
- **Expected change:** conversation/audio/sync/storage/finalization product modules and tests, Firestore indexes, runtime product bindings, docs; behavioral `test_s23_recording_product_retirement.py`; retained Swift conversation/capture tests. Physical bucket/IAM is not changed.
- **Focused verification:** recording/playback/storage tests rewritten as absence plus local-path behavior; `recording-finalization.yaml`, `capture-lifecycle.yaml`, backend listen/transcription tests.
- **Deletion/simplification enabled:** product audio schemas and object writers disappear; S-24 gets exact paths and S-25 gets zero-producer queues/workers.
- **Stop:** a retained non-product caller uses an audio helper, a live backlog/rollback requirement is unassessed, or completing GREEN would require deleting the S-25 worker route/service.

### Cycle 3 — delete People, speech profiles, and persistent speaker identity

- **Gate:** G3 if hosted PTT conversation tools still resolve People/speaker identity.
- **Intended behavioral RED:** v3/v4 speech-profile/upload/expand operations and People identity access are 404; one live STT fixture still returns generic conversation-scoped speakers and the named Mac can rename them locally. Strict fakes detect any Firestore People/embedding/sample or speech-profile GCS/Redis access.
- **Why it fails before implementation:** routes, People helpers, speech samples/embeddings, matching/assignment/migration modules, transcript fields, Modal/Pusher callers, generated operations, config, and tests remain.
- **Minimum GREEN:** delete the hosted product route/data/model/storage/caller graph, `speech_profile_processed`, persistent person IDs/embeddings, `ImprovedTranscript*`, and exclusive support. Preserve shared VAD assets and generic speaker fields actually required by transient STT.
- **Retained behavior protected:** generic diarization, stable segment IDs, local manual speaker naming, listen/PTT/file STT, and in-process VAD.
- **Owner before -> after:** Firestore People/GCS voice biometrics -> no reusable identity owner; local conversation name mapping remains owner.
- **Expected change:** speech-profile router/storage/Redis/user helpers, speaker modules/models/tests/generated/config; behavioral `test_s23_voice_identity_retirement.py`; existing speaker naming/listen tests. S-25 owns Modal/service/chart/image deletion.
- **Focused verification:** backend generic-speaker contract, `speaker-naming.yaml`, listen tests, local speaker-name Swift tests, genuine 404 and OpenAPI absence.
- **Deletion/simplification enabled:** speech-profile credentials/bucket application bindings and People schema disappear; hosted VAD/diarizer become S-25 zero-caller handoffs.
- **Stop:** a retained provider needs a shared generic diarization primitive, S-19 still uses hosted People, or a shared VAD asset is mistaken for persistent identity.

### Cycle 4 — delete wearable photos, glasses, and whole-recording comparison pipelines

- **Intended behavioral RED:** rejected `image_chunk`/OpenGlass/wearable photo and whole-recording retranscription/provider-comparison inputs cannot create a hosted record or model call, while a Mac PTT screenshot, Chat image attachment, Rewind image, and retained prerecorded transcription still work.
- **Why it fails before implementation:** broad ConversationSource values, postprocess/retranscription helpers, recording artifacts/tests, and product-image strings remain even though model routes are mostly absent.
- **Minimum GREEN:** delete only product photo/image-chunk and whole-recording comparison/postprocess branches plus exclusive models/config/tests/docs; consume S-22's negative model proof.
- **Retained behavior protected:** screen-aware PTT, Chat images, Rewind OCR/media, transient prerecorded STT, and generic provider diagnostics.
- **Owner before -> after:** hosted wearable/photo/conversation pipeline -> no owner; Mac image surfaces and transient STT retain their existing owners.
- **Expected change:** postprocess/process/source/storage/model residues and tests; behavioral `test_s23_wearable_recording_retirement.py`; existing `test_wearable_surface_retirement.py` and Mac image-path tests.
- **Focused verification:** wearable negative route/model tests plus PTT screenshot, Chat attachment, Rewind, and prerecorded STT focused suites.
- **Deletion/simplification enabled:** product-specific image/audio schemas/config are removed and S-25 hosted model services become more isolated.
- **Stop:** a hit belongs to retained Mac vision or file transcription, or S-22 has not proven the model caller absent.

### Cycle 5 — remove the hosted conversation envelope and protection protocol

- **Intended behavioral RED:** Deserialize a minimal retained transient-compute request and inspect the assembled product app: no live type accepts or emits transcript compression, processing aliases, protection/lock/deferred state, broad source, call/device provenance, or generic `external_data`; retained compute still validates bounded local input and returns the same candidate result. Separately migrate a historical local database and prove its final live schema remains correct.
- **Why it fails before implementation:** `Conversation`/`CreateConversation`, database serializers, Redis protection/alias keys, encryption helpers/migration, merge/factory/render/lifecycle code, user profile fields, and tests still depend on those names.
- **Minimum GREEN:** delete the hosted envelope fields and their persistence/cache/encryption/compatibility branches after callers are gone; use compiler/type errors to migrate in-tree callers. Keep only narrower request/result types owned by retained transient compute.
- **Retained behavior protected:** local conversation schema evolution, input-device name, location, typed merge provenance, STT provider diagnostics, candidate compute behavior, operational device identity in auth/abuse/update/metrics, and local transcript visibility.
- **Owner before -> after:** broad Firestore Conversation document -> no backend product document; local GRDB types plus narrowly typed transient compute own surviving facts.
- **Expected change:** conversation/user models, enum/serialization/database/cache/encryption/merge/render tests, env docs; behavioral `test_s23_conversation_schema_retirement.py`; local migration tests. Historical migration bodies are changed only if their tested forward transform requires it.
- **Focused verification:** conversation compute tests, schema/model tests, local migration tests, operational client-device tests, quota/paywall tests.
- **Deletion/simplification enabled:** `ENCRYPTION_SECRET` product-content use, compatibility aliases, Redis protection/migration keys, and broad source enum disappear if no other retained caller exists.
- **Stop:** `ENCRYPTION_SECRET` or a field has another proven retained security owner, a local historical migration would be broken, or an operational device identifier is being deleted by name rather than ownership.

### Cycle 6 — delete hosted conversation metadata, mutation, retrieval, sharing, and Calendar context

- **Gate:** G3.
- **Intended behavioral RED:** summary/text PATCH, test-prompt, speaker analytics/search, Calendar meeting/context, public/share/link, and metadata-filter operations are 404 or absent; PTT/local search still returns equivalent retained local results; local commitment extraction remains local and performs no external calendar write.
- **Why it fails before implementation:** request/analytics/metadata/calendar models, calendar routes/database/document IDs, processing prompt context, Redis filter/meeting keys, hosted retrieval services, tests, and stale share/link strings remain.
- **Minimum GREEN:** after S-19's caller migration, delete complete hosted operations and data schemas, including People/topics/entities/dates and meeting/attendee/link storage. Remove generated operations and exclusive indexes/config/docs. Do not delete local FTS/vector/date search or commitments.
- **Retained behavior protected:** local conversation list/detail/edit/merge/search/date filtering, Copy Transcript, PTT tools, local summary/action-item proposals, location, and local commitments.
- **Owner before -> after:** hosted Firestore/search/Calendar context -> local GRDB/search owners; external calendar has no writer.
- **Expected change:** conversation/calendar/retrieval routers, models, database/utils, Redis, Firestore indexes, generated/tests/docs; behavioral `test_s23_conversation_operation_retirement.py`; S-19 PTT and local-search tests.
- **Focused verification:** 404 matrix against `main.app`, PTT tool tests, local conversation/search/merge tests, OpenAPI generation, no-external-calendar-call fake.
- **Deletion/simplification enabled:** hosted metadata catalogs, Calendar collections, mutation DTOs, sharing residue, and product-specific indexes disappear; S-24 gets a zero-caller search handoff.
- **Stop:** S-19 remains on hosted tools, a route is a retained transient compute endpoint, or a search/index hit belongs to local FTS/embeddings.

### Cycle 7 — delete Memory feedback/scoring and durable headline residue

- **Intended behavioral RED:** GET/POST `/v1/users/analytics/memory_summary` are genuine 404 and cannot write `analytics`; a temporary local Memory database proves final live columns omit review/scoring/headline while confidence/read/dismiss/lifecycle and an Insight transient headline still work.
- **Why it fails before implementation:** two routes, response model, Firestore helpers/document schema, generated methods, and exclusive tests remain; historical Mac migration strings require classification.
- **Minimum GREEN:** remove the cloud rating product and live schema/cache references; keep historical migrations only where behavioral migration tests require them; keep LangSmith operator evaluation and transient Insight headline.
- **Retained behavior protected:** local Memory CRUD/search/lifecycle/provenance, read/dismiss, Insight UI/local notification, LangSmith/Prompt Hub.
- **Owner before -> after:** cloud analytics/user rating -> no product rating owner; local Memory and Insight retain distinct owners.
- **Expected change:** users router/database/models/generated/tests; Memory schema assertions and migration allowlist; behavioral `test_s23_memory_feedback_retirement.py` plus `ChatDiscoverabilityTests`/Memory migration tests.
- **Focused verification:** genuine 404, strict no-Firestore fake, local live-schema migration, Insight headline behavior, LangSmith tests.
- **Deletion/simplification enabled:** rating analytics collection contract and response DTO disappear.
- **Stop:** a proposed deletion removes confidence/read/dismiss, changes an old migration without fixture proof, or treats LangSmith evaluation as user rating.

### Cycle 8 — close public sharing, Persona, and hosted Chat report residue

- **Intended behavioral RED:** all public sharing/persona/shared-Chat and both hosted message-report operations are 404 from the assembled app, while Copy Transcript, local main Chat, local AI Profile, in-app Report Issue, and local attachments still work.
- **Why it fails before implementation:** S-06/S-11 removed most product routes but hosted message report/database helpers/tests remain; generated/docs/deploy registries may still reference removed families.
- **Minimum GREEN:** delete remaining hosted report/read/product helpers and reintroduced sharing/persona schema/config/docs. Preserve S-24-owned hosted-file code until its own caller/file teardown and S-25-owned deployment residue.
- **Retained behavior protected:** local Chat catalog/journal, explicit attachments, Copy Transcript, private AI Profile, Sentry-backed Report Issue.
- **Owner before -> after:** hosted message/share/persona records -> no owner; local Chat/Profile/reporting retain owners.
- **Expected change:** Chat route/database report helpers, tests/generated/docs, product registry residue; behavioral `test_s23_sharing_persona_chat_retirement.py`; existing S-06/S-11 negative tests.
- **Focused verification:** 404 matrix plus local Chat/Profile/Report Issue tests and named-bundle smoke.
- **Deletion/simplification enabled:** `database.chat` hosted report/export portion shrinks; S-24 owns remaining file helpers and S-25 owns Persona deploy residue.
- **Stop:** a report helper is used by retained abuse/security workflow, a file helper is S-24-owned, or Sentry user reporting is conflated with Sentry-to-Tasks.

### Cycle 9 — delete Twilio calls vertically

- **Intended behavioral RED:** all six `/v1/phone/**` operations are 404; subscription response has no phone quota; strict fakes observe no Twilio client, verified-number Firestore, pending verification, Redis phone usage, or conversation `call_id`; normal PTT and meeting capture still work.
- **Why it fails before implementation:** phone router/database/config/usage/utils, Twilio dependency/credentials, plan response, models, tests, and account-deletion cleanup remain.
- **Minimum GREEN:** delete complete Twilio product code/data/config/dependency/generated/docs and its subscription/call schema. Defer only the now-dead deletion-worker branch to Cycle 16 so the durable worker is changed under one behavioral fence.
- **Retained behavior protected:** mic/System Audio meeting capture, PTT/realtime voice, subscription/quota data unrelated to calls, account deletion reliability.
- **Owner before -> after:** Twilio/Firestore/Redis phone product -> no owner.
- **Expected change:** phone modules, user/conversation models, subscription response, requirements/locks/env, generated/tests/docs; behavioral `test_s23_twilio_retirement.py`; account-deletion tests updated in Cycle 16.
- **Focused verification:** 404/no-client/no-storage assertions, subscription wire tests, PTT/capture tests, dependency/import closure.
- **Deletion/simplification enabled:** Twilio credential/dependency and phone Redis/Firestore schemas become removable; deletion cleanup becomes provably deletion-only.
- **Stop:** any retained telecom requirement/caller appears, or Dodo/account usage is coupled to `PhoneCallQuota` beyond presentation.

### Cycle 10 — delete Wrapped and release its OpenRouter dependency

- **Gate:** G2.
- **Intended behavioral RED:** GET/POST Wrapped operations are 404 and no generation/status/progress/result/model call/storage occurs; S-22's caller inventory then shows zero retained OpenRouter/`wrapped_analysis` callers while retained direct OpenAI/Anthropic/Gemini workloads pass.
- **Why it fails before implementation:** Wrapped router/database/generator/background task and OpenRouter model/config remain live by deliberate owner order.
- **Minimum GREEN:** delete Wrapped vertically, then remove only its proven-exclusive `wrapped_analysis` and OpenRouter application bindings/tests/config under IR-720. Run S-22's retained-provider regression suite; do not modify or reopen S-22.
- **Retained behavior protected:** normal Chat, greeting/title, conversation/Memory compute, translation/embeddings, both realtime providers, LangSmith/Prompt Hub.
- **Owner before -> after:** Firestore Wrapped plus OpenRouter generation -> no owner.
- **Expected change:** wrapped router/database/utils, model config/provider bindings, generated/tests/env/docs; behavioral `test_s23_wrapped_retirement.py`; S-22 caller/model contracts.
- **Focused verification:** 404, strict no-background/model/storage fakes, S-22 direct-provider suite, model residue search.
- **Deletion/simplification enabled:** OpenRouter application dependency/config disappears if the inventory is zero.
- **Stop:** any non-Wrapped retained OpenRouter caller exists or S-22's retained portfolio is not integrated.

### Cycle 11 — delete cloud announcements while preserving local release communication

- **Intended behavioral RED:** every public/user/admin announcement operation is 404 and cannot read/write `announcements` or `dismissed_announcements`; local What's New, repository changelog parsing, Sparkle checks, and app-review version policy still behave exactly as before.
- **Why it fails before implementation:** announcement routes/database/models/collections/generated/tests remain, and retained `app_review_config.py` imports `compare_versions` from the product module.
- **Minimum GREEN:** first move semantic version comparison and its tests to a narrow retained update/app-review owner with no behavior change; then delete cloud announcement product code/data/contracts/config/docs.
- **Retained behavior protected:** local one-time post-update toast/suppression, manual What's New, Sparkle feed/update behavior, app-review hide-subscription policy.
- **Owner before -> after:** Firestore cloud announcements -> no owner; repository changelog/Sparkle/app-review policy retain separate owners.
- **Expected change:** announcement modules, app-review import, generated/tests/docs/collection references; behavioral `test_s23_announcements_retirement.py`; retained update/changelog/app-review tests.
- **Focused verification:** full 404 matrix, strict Firestore fake, app-review semantic version tests, update and named-bundle What's New smoke.
- **Deletion/simplification enabled:** announcement collections/admin secrets/product analytics disappear without duplicating version comparison.
- **Stop:** version comparison semantics would change, a retained update flow reads cloud announcements, or local changelog is mistaken for cloud product residue.

### Cycle 12 — delete Trends and Joan; accept Daily Summary absence

- **Intended behavioral RED:** `/v1/trends` and `/v1/joan/{memory_id}/followup-question` are 404 and cause no hosted conversation/Memory/model/storage reads; Daily Summary routes remain 404. Local Insights/Focus/Profile/questions and automatic Chat greeting/title continue to work.
- **Why it fails before implementation:** Trends route/database/model/helper and Joan route/followup caller remain; Daily Summary is already absent.
- **Minimum GREEN:** delete Trends and Joan vertically plus exclusive model/storage/config/generated/tests/docs; accept Daily Summary as a verified negative family and delete only reintroduced residue.
- **Retained behavior protected:** local Insights/Focus/Profile, once-daily local questions, Chat greeting/title, local notifications.
- **Owner before -> after:** hosted Trends/Joan -> no owner; local proactive/Chat owners remain.
- **Expected change:** trends and users followup modules/helpers/generated/tests/config/docs; behavioral `test_s23_trends_joan_retirement.py`; extend S-14 negative contract.
- **Focused verification:** genuine 404/no-read/no-model assertions, S-14 local-authority tests, local proactive/Chat tests.
- **Deletion/simplification enabled:** trends collection/model profile and Joan response/helper disappear.
- **Stop:** a `followup` model call belongs to another retained workload, or deleting a generic helper would change Chat/onboarding behavior.

### Cycle 13 — replace surviving cloud warning delivery, then delete FCM

- **Gate:** G1.
- **Intended behavioral RED:** Trigger one controlled retained fair-use or managed-usage transition through S-20's production seam. The authenticated Mac receives the structured state once, presents fixed truthful in-app copy and (where required) one local `UNUserNotificationCenter` notification across reconnect/restart, while strict backend fakes observe no FCM token/message/personalization call. Invalid owner, stale transition, duplicate event, notification denial, and app-closed/reopen cases follow the decided state rather than fabricating success.
- **Why it fails before implementation:** backend still owns FCM registration/storage/builders/batching and fair-use notification calls; Mac has local notification infrastructure but no FCM receiver and S-20 intentionally leaves transport to S-23.
- **Minimum GREEN:** consume one S-20 authenticated state interaction; add the smallest deterministic Mac presentation/dedup seam using existing `NotificationService`; remove GPT-personalized copy and every FCM endpoint/token collection/builder/batch/invalid-token/admin-push/product caller/config/test/generated method. Delete notification-only Redis keys after caller proof.
- **Retained behavior protected:** exact S-20 thresholds/stages/timers/case/support facts, quota/paywall behavior, local reminders/proactive notifications/preferences, billing UI/reconciliation, Sentry/PostHog.
- **Owner before -> after:** Firebase Cloud Messaging -> backend owns facts; Mac owns presentation/local OS delivery.
- **Expected change:** backend notification router/database/utils/model/callers/Redis/generated/dependencies/tests/docs; Mac state/event handler/local notification tests and a typed E2E flow. S-25 separately accepts Notifications-job absence.
- **Focused verification:** S-20 behavioral state tests, new `test_s23_fcm_retirement.py`, Swift local notification/dedup/owner tests, named-bundle warning flow, genuine 404.
- **Deletion/simplification enabled:** FCM token schema, mobile/web compatibility, arbitrary push route, Firebase messaging imports, and exclusive tests/config disappear.
- **Stop:** no stable S-20 authenticated state seam, offline/app-closed behavior lacks a product decision, notification copy/semantics would change, or a local reminder is reached through a shared helper being deleted.

### Cycle 14 — close ratings/scores/Sentry bridge/detailed-usage families

- **Intended behavioral RED:** user rating, task/daily-score, Sentry-to-Task, detailed `/v1/users/me/usage`, detailed LLM self-report, and top-feature routes are 404/absent, while authenticated subscription, usage quota, total managed cost, fair-use/support reads, local Tasks/Goals, in-app Sentry report, symbols, and LangSmith evaluation work.
- **Why it fails before implementation:** summary rating remains live; other families are mostly negative predecessor state, but generated/schema/test/config residue and total-vs-detailed usage names require classification.
- **Minimum GREEN:** delete remaining rating and any reintroduced/exclusive score/bridge/detailed-reader residue. Keep server-side writers/counters and narrow total projections with retained callers; preserve existing negative route tests.
- **Retained behavior protected:** local tasks/goals, account usage card, quota admission, fair-use, support, Sentry diagnostics/reporting, LangSmith operator evaluation.
- **Owner before -> after:** rejected feedback/score/detailed self-report -> no product owner; retained control/observability owners remain.
- **Expected change:** user analytics/usage route models/generated/tests/docs and only proven-exclusive helpers; behavioral `test_s23_feedback_score_usage_retirement.py`; existing desktop-core/S13/usage/Sentry/LangSmith tests.
- **Focused verification:** assembled-app 404s, strict no-product-read fakes, subscription/quota/total tests, Sentry report and LangSmith tests.
- **Deletion/simplification enabled:** detailed response schemas and dead analytics collection branches disappear.
- **Stop:** a usage store is needed for admission/account/support, an endpoint is total rather than detailed, or a Sentry SDK path is confused with the rejected task bridge.

### Cycle 15 — consume and close rejected model-specific product residue

- **Gate:** G2 and Cycle 10.
- **Intended behavioral RED:** the assembled app has no ElevenLabs `/v2`, Perplexity/public-web, Gemini Pro/streaming, OpenRouter, cloud Mentor/proactive, glasses, old persona/Memory/Chat model operation or config; retained non-stream Flash/Lite/embeddings, exact preview rewrite, greeting/title, Memory/conversation compute, normal Chat, realtime providers, LangSmith, and Prompt Hub execute through their explicit seams.
- **Why it fails before implementation:** S-22 is absent at the planning baseline and deliberately hands Wrapped/OpenRouter order to S-23; stale application/docs/test registries may remain after integration.
- **Minimum GREEN:** consume S-22 rather than reimplement it, remove only S-23 product-owned caller/config residue and the proven Wrapped-exclusive provider binding, regenerate contracts, and run the retained S-22 caller/result-owner tests without reopening that slice.
- **Retained behavior protected:** every model invariant listed in IR-719/721/722/827/828 and S-22's tests, including bounded transient inputs and local commits.
- **Owner before -> after:** rejected model product routes -> no owner; explicit retained model registry/callers remain backend-owned for transient compute.
- **Expected change:** post-S-22 product caller/model registry leftovers, generated/policy/docs/tests; behavioral integrated model-route contract, not a source-string-only guard.
- **Focused verification:** S-22 focused/model suites, retained Chat/PTT/Memory/conversation/TTS tests, route/OpenAPI checks, named-bundle managed compute smoke.
- **Deletion/simplification enabled:** zero rejected model/provider application surface and a precise S-25 gateway/deployment handoff.
- **Stop:** a model/provider lacks a named caller/result owner, a prompt/semantic change is proposed, or the public-web failure-class history would be altered in this PR.

### Cycle 16 — remove S-23 product cleanup and hand Pinecone purge to S-24

- **Gate:** G4; Cycles 1–15 are green and every S-23-owned product writer/store is closed. S-24 need not be integrated.
- **Intended behavioral RED:** Through admission -> durable task -> claimed worker -> retry/reconciliation -> redelivery, strict substitutes allow Dodo cancellation, Firebase Auth deletion, recursive retained Firestore cleanup, telemetry, and one exact Pinecone purge interface owned by S-24. Assert no Twilio/product-recording/cloud-memory/Stripe-specific adapter or product counter is invoked; a retained failure, including Pinecone purge failure, stays failed/retryable and completed redelivery is a no-op.
- **Why it fails before implementation:** `account_deletion.py` mixes Twilio, recording, cloud-memory-derived, and Pinecone purge work and reports mixed vector/recording counters, so no exact provider handoff exists yet.
- **Minimum GREEN:** remove every S-23-owned cleanup composition/import/counter/test/config after its writer/store is closed. Preserve Dodo, Firebase, generic recursive Firestore cleanup, job claim/lock/status/retry/reconciler/tombstone, sanitizer, privacy-bounded telemetry, bodyless endpoint behavior, and only the smallest explicit Pinecone purge/counter seam required for S-24 C3–C4 to delete.
- **Retained behavior protected:** durable deletion reliability, disabled-billing behavior, OIDC auth, idempotency, retry/exhaustion, and retained account/entitlement/usage deletion.
- **Owner before -> after:** deletion worker enumerates rejected product stores -> retained account-control deletion plus one exact S-24-owned Pinecone purge handoff.
- **Expected change:** account-deletion service/tests, S-23 product purge helpers, telemetry fields, docs/config; S-24 deletes the Pinecone branch later and S-25 owns task target/topology.
- **Focused verification:** account-deletion service/router/claim/reconcile tests, strict Firestore tests, Dodo-disabled tests, sanitizer tests, hermetic Cloud Tasks E2E.
- **Deletion/simplification enabled:** deletion-only product dependencies no longer keep Twilio/GCS/cloud-memory code alive; S-24 receives a bounded Pinecone deletion seam rather than a product-cleanup knot.
- **Stop:** an S-23-owned rejected store still has a writer, the remaining handoff is broader than Pinecone purge/counters, the Dodo seam is absent, recursive Firestore scope would delete the tombstone too early, or queue/target work drifts into S-25.

### Cycle 17 — ship complete offline local export and narrow server export

- **Gate:** G4 and complete S-10 through S-14 readers; S-11 kernel catalog/journal paging available.
- **Intended behavioral RED:** Seed one independently specified record in each approved local section, disable product network, and call `LocalUserDataExport.export(ownerID:to:)`. Assert exact versioned JSON, complete pagination/deterministic ordering, one captured owner fence, and exclusion list. Inject a read and destination-write failure and assert a user-presentable error with no partial file. Through Account Settings, canceling the save panel writes nothing; success writes the same file. Separately assert authenticated server export contains only an independent retained metadata allowlist and never invokes a product-content reader.
- **Why it fails before implementation:** no Mac action/composer exists; some owner readers need a final complete paging seam; server exporter streams hosted conversations/People/Chat and claims product completeness.
- **Minimum GREEN:** add the deep feature-scoped local exporter behind the S-08 interface, page owner-scoped stores/kernel journal, write a sibling temp file and atomically replace, expose one Account Settings row using `NSSavePanel`, and narrow server export/model/filename/docs to retained account/subscription/billing/entitlement/usage metadata. Server metadata may be separate; a server failure cannot block local export.
- **Retained behavior protected:** Sign Out/Delete Account/Account & Plan, owner isolation, local domain storage behavior, Save Diagnostics as a distinct feature, server account metadata, and disabled billing.
- **Owner before -> after:** incomplete hosted exporter -> Mac owns product-content export; backend owns metadata-only export.
- **Expected change:** new small `Desktop/Sources/Account/Export/` module and tests, owner read interfaces only where incomplete, kernel protocol/tests, Account Settings/automation/E2E/changelog, server exporter/router/model/tests/generated/docs. Do not reuse `MemoryExportService` or dump UserDefaults/SQLite.
- **Focused verification:** Swift exporter/UI/owner-switch/offline/failure tests, Node journal paging tests, backend data-export/router tests, `jq` validation, named-bundle `export-my-data.yaml`.
- **Deletion/simplification enabled:** hosted conversation/People/Chat export readers and streaming product response assumptions disappear; local serialization complexity is hidden behind one interface.
- **Stop:** a required domain lacks complete owner-scoped paging, allowed settings are not explicitly reviewed, binary attachment/Rewind media scope expands, or auth/account owner would be read after an `await` instead of using the captured snapshot.

### Cycle 18 — integrated route/schema/registry closure and accepted negative families

- **Intended behavioral RED:** One production-app contract enumerates every rejected HTTP/WebSocket operation and proves genuine 404/absence while enumerating retained neighboring operations. A second repository closure check classifies every Firestore collection/index, Redis namespace, GCS product path, account-deletion/export entry, generated operation, dependency/config/test/doc, and S-24/S-25 handoff; any unclassified product owner fails. Already-absent Daily Summary, Persona, firmware, Limitless, scores, jobs, integration, and Plugins remain absent.
- **Why it fails before implementation:** the pinned app still mounts many rejected products, generated contracts expose them, registries contain product schemas, and predecessor/successor planning artifacts are not implementations.
- **Minimum GREEN:** regenerate OpenAPI/Swift, update route policy/legacy baseline/response-model coverage/test discovery/docs, delete only final classified residue, and record exact S-24/S-25 operational handoffs. Do not add a new feature or generic bulk deletion script.
- **Retained behavior protected:** the complete §9 invariant set and all predecessor closeout tests.
- **Owner before -> after:** mixed unclassified registry -> every retained entry has a named owner; every rejected entry is absent or explicitly successor-owned operational topology.
- **Expected change:** integrated behavioral route test, registry/static tripwires, OpenAPI/generated client, route policy, Firestore indexes/rules, dependency/config/docs/check manifests only where their owned entries changed.
- **Focused verification:** all §14 commands, named-bundle §15 matrix, exact residue review, `git diff --check`, `make preflight`, PR preflight.
- **Deletion/simplification enabled:** S-23 repository closure and clean, finite S-24/S-25 inputs.
- **Stop:** any product family is merely hidden/unmounted but still owns data, any static tripwire substitutes for behavior, any retained route disappears, or live-resource absence is being inferred from repository source.

After every GREEN, run a separate simplify review: remove only newly callerless shallow modules/imports/schema branches and measure the focused edit/test loop time. No additional automation is justified beyond extending the stable OpenAPI/route-policy/requirements/preflight and typed named-bundle harnesses already in the repository.

## 12. Cross-slice ownership and handoffs

| Owner | S-23 consumes | S-23 owns | S-23 must not absorb / handoff |
|---|---|---|---|
| **S-01/S-02/S-06** | External device/integration/share/Persona/Limitless negative surfaces | Delete only returned hosted product residue | Do not restore connectors, firmware, public site, or compatibility routes |
| **S-08** | Auth/session fences, durable deletion contract, export acceptance contract | Rejected cleanup/readers and dependency-gated exporter implementation | Identity provider config, queue/IAM/region, auth redesign remain elsewhere |
| **S-09** | Sentry/PostHog/LangSmith/Prompt Hub retained boundaries; Sentry-to-Tasks absence | Remove only rejected bridge/rating/product events | Do not delete retained SDKs, tracing, Report Issue, diagnostics |
| **S-10** | Local conversations and negative public projection | Hosted product schema/data/callers | Do not change local behavior; S-25 owns worker topology |
| **S-11** | Local Chat catalog/journal and message report/export handoff | Hosted report/export reader deletion | S-24 owns files/OpenAI Files; normal Chat stays local |
| **S-12** | Local Memory schema/readers and maintenance-job absence | Rating/headline/product residue | Historical migration transforms remain when required; S-25 owns deployed job residue |
| **S-13/S-14** | Local Tasks/Goals/Focus/Insights/Profile/notifications and score/job negative proof | Rejected hosted schema/product callers | Do not redesign local proactive/task behavior; S-25 owns deploy residue |
| **S-17/S-18** | Narrow onboarding and disabled Dodo/account projection | No onboarding/billing redesign; account cleanup consumes Dodo seam | Dodo activation stays post-Wave-6 |
| **S-19** | Final local PTT tools/search and hosted-caller absence | Remove hosted conversation metadata/readers only afterward | Never recreate PTT tools or alter realtime lifecycle |
| **S-20** | Content-free enforcement facts/authenticated Mac interaction | Mac warning presentation + FCM deletion | Classifier, thresholds, strike/timer/support semantics stay S-20 |
| **S-21** | Final shell has no rejected navigation/caller | Backend product deletion only | Do not converge Settings/navigation here except Export My Data row |
| **S-22** | Explicit retained model portfolio plus the exact Wrapped/OpenRouter handoff | Delete Wrapped and its exclusive OpenRouter binding; run retained-provider tests | Do not alter prompts/models/failover or reopen S-22 |
| **S-24** | Receives zero product callers, exact object/search paths, and one explicit Pinecone purge/counter seam | Repository product schema/caller and non-Pinecone cleanup deletion | Typesense/Pinecone—including account purge—OpenAI Files/product GCS resources and update/preview fence belong to S-24 |
| **S-25** | Receives callerless audio/finalization/Pusher/model services and absent product APIs | No independent deployment deletion | Workers/routes/queues/reconcilers/services/images/workflows/secrets/GKE and account-task retarget belong to S-25 |
| **S-26/S-27** | Receive truthful retained app/platform registry | No entrypoint/platform convergence | Canonical source merge, region/projects/domains/live platform remain later |
| **S-28 through S-31** | Receive functional retained Mac product | No namespace/rebrand/release work | Bundle/storage migration, release infra, copy/brand, final acceptance remain later |

Shared files requiring rebase-owner review before editing include `backend/main.py`, `routers/users.py`, `database/users.py`, `services/users/account_deletion.py`, `utils/other/storage.py`, `database/redis_db.py`, `utils/llm/model_config.py`, route/OpenAPI generators, `runtime_env.yaml`, `firestore.indexes.json`, Account Settings sources, `DesktopAutomationBridge.swift`, generated Swift, and desktop E2E flows.

## 13. Repository residue-search strategy

Residue searches are labelled static tripwires. Run them after behavioral GREEN, inspect every hit, and classify it as retained executable code, tested local migration history, negative test, roadmap/history, S-24/S-25 handoff, or defect. Exclude `bootstrap-scaffold/**`, `.git/**`, historical changelogs, and `desktop/windows/**` only for executable closure; never erase decision history to make a search empty.

```bash
# Routes and complete product families
rg -n -i 'daily.?summary|speech.?profile|people_profiles|private.?cloud|training.?data|/v1/phone|twilio|wrapped|announcement|/v1/trends|/v1/joan|fcm|firebase.*messag|memory_summary|daily.?score|productivity.?score|persona|limitless|firmware|image_chunk|openglass|smart.?glasses' \
  backend desktop/macos docs firestore.rules firestore.indexes.json .github config scripts \
  --glob '!desktop/windows/**' --glob '!**/*.lock'

# Hosted conversation/product schema
rg -n 'transcript_segments_compressed|audio_files|conversation_audio|private_cloud_sync_enabled|processing_memory_id|processing_conversation_id|data_protection_level|is_locked|client_device_id|client_platform|speech_profile_processed|ImprovedTranscript|ConversationMetadata|speaker_id|CalendarMeetingContext|calendar_event_id|external_data' \
  backend desktop/macos docs firestore.rules firestore.indexes.json \
  --glob '!desktop/windows/**' --glob '!**/*.lock'

# Rejected models/providers; every retained hit must be named by S-22
rg -n -i 'elevenlabs|/v2/tts/synthesize|perplexity|sonar-pro|openrouter|gemini-stream|streamGenerateContent|gemini-2\.5-pro|wrapped_analysis|web_search|proactive_notification|chat_extraction|chat_graph|openglass|image_chunk' \
  backend desktop/macos docs scripts --glob '!desktop/windows/**' --glob '!**/*.lock'

# Account deletion/export may not retain product readers
rg -n 'delete_user_caller_ids|delete_all_conversation_recordings|delete_conversation_vectors|delete_transcript_chunk_vectors|purge_derived_user_data|vectors_deleted|recordings_deleted|iter_all_conversations|get_people|iter_all_messages' \
  backend/services/users backend/routers/users.py backend/tests/services/users

# Firestore/Redis/GCS product ownership
rg -n 'collection\(.?(announcements|analytics|trends|wrapped).?\)|collection\(.?(people|fcm_tokens|meetings|conversations).?\)|phone_call_usage:|speech_profile_duration|silent_notification_sent|important_conv_notif|in_progress_memory_id|BUCKET_(SPEECH_PROFILES|POSTPROCESSING|MEMORIES_RECORDINGS|PRIVATE_CLOUD_SYNC|TEMPORAL_SYNC_LOCAL)' \
  backend firestore.rules firestore.indexes.json .github

# Protected siblings must remain
rg -n '/v1/tts/synthesize|gemini-3-flash-preview|gemini-2\.5-flash-lite|gemini-embedding-001|/v1/users/me/subscription|/v1/users/me/usage-quota|/v1/users/me/llm-usage/total|account-deletion-wipes|appcast|desktop.*preview|LangSmith|Prompt Hub|Sentry|PostHog' \
  backend desktop/macos docs

# Successor operational handoffs: non-empty is expected and must be exact
rg -n '/v2/audio-merge-jobs/run|conversation-finalization-jobs|ListenPusherSession|HOSTED_PUSHER_API_URL|backend-sync|backend-listen|omi-pusher|diarizer|llm-gateway' \
  backend .github infrastructure docs
```

Also inspect `git grep` over deleted symbols against the index, run `git diff --name-status --diff-filter=D`, and confirm each deleted family loses tests/docs/config with its code while retained negative tests stay meaningful.

## 14. Focused and component-level verification commands

Commands are future implementation requirements and run from the repository root unless a subshell says otherwise.

### Baseline, requirements, and failure-class gates

```bash
make setup
git fetch origin --prune
git merge-base --is-ancestor 711269baf5e653bd62132688998732207f11dd3c HEAD
git rev-parse HEAD origin/main
git status --short --branch
git diff --stat origin/main...HEAD
python3 bootstrap-scaffold/validate-requirements-ledger.py
scripts/pr-preflight --suggest
```

If a `fix:` commit is used, run the exact `scripts/failure-class` command suggested by preflight and record `Failure-Class: FC-<slug> | new | none` in the commit/PR evidence.

### Focused backend feedback

Use the documented selector from `desktop/macos` after each RED/GREEN. Run the files that exist in the implementation; the names below are the planned regression surfaces:

```bash
cd desktop/macos
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_recording_preferences_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_recording_product_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_voice_identity_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_conversation_schema_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_conversation_operation_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_memory_feedback_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_twilio_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_wrapped_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_announcements_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_trends_joan_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_fcm_retirement.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_s23_feedback_score_usage_retirement.py'
./scripts/dev-feedback.py --once python 'tests/services/users/test_account_deletion.py'
./scripts/dev-feedback.py --once python 'tests/services/users/test_data_export.py'
```

Run retained/current contracts alongside the new tests: S-06/S-10/S-11/S-12/S-13/S-14 route-retirement tests; listen/transcription/conversation-compute/memory-compute/TTS/desktop-proxy/model tests; subscription/quota/fair-use tests; account-deletion claim/reconciliation tests; route-policy/OpenAPI/test-discovery tests; and strict logging/sanitizer tests.

### Focused Swift and Node feedback

Select the exact current XCTest filters after G0. At minimum cover local conversation migration/authority/search/speaker naming; Memory live-schema/lifecycle/Insight headline; Tasks/Goals/Focus; Chat catalog/journal; local notification delivery/dedup/owner fencing; Account Settings/export; TTS/model routing; auth/account switch/same-UID reauthentication.

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'ConversationLocalAuthorityMigrationTests'
./scripts/dev-feedback.py --once swift 'ChatDiscoverabilityTests'
./scripts/dev-feedback.py --once swift 'InsightLocalAuthorityTests'
./scripts/dev-feedback.py --once swift 'LocalUserDataExportTests'
./scripts/dev-feedback.py --once swift 'LocalUserDataExportOwnerIsolationTests'
./scripts/dev-feedback.py --once swift 'LocalWarningNotificationTests'
pnpm --dir agent test
```

Planned test names must be reconciled to the implemented test targets; do not record a nonexistent filter as passed.

### OpenAPI, generated client, route policy, and discovery

```bash
cd backend
./scripts/openapi_runner.sh scripts/route_policy_inventory.py --check
./scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
./scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
./scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
./scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
bash test-preflight.sh
```

Review the generated diff. Removed operations must disappear; retained operations must not churn semantically. Never hand-edit generated Swift.

### Component and repository acceptance

```bash
(cd backend && bash test.sh)
(cd desktop/macos && ./test.sh)
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
make preflight
```

Draft the final PR body in a temporary file and run:

```bash
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
```

The PR evidence must list actual commands/results, green required component suites, named-bundle observations, intended 404s, retained siblings, and the exact S-24/S-25 handoffs. No push/PR/merge is implied by this plan.

## 15. Real named-bundle and retained user-path acceptance

Use only the assigned non-production bundle and the local/emulated backend. Never touch `/Applications/Omi.app`, `/Applications/Omi Beta.app`, `com.omi.computer-macos`, or `com.omi.computer-macos.beta`.

```bash
make dev-up
cd desktop/macos
OMI_APP_NAME=omi-wave4-s23 OMI_SKIP_TUNNEL=1 ./run.sh --full
```

Drive semantic state/actions with `omi-ctl` and typed flows through:

```bash
cd desktop/macos
./scripts/omi-harness run e2e/flows/capture-lifecycle.yaml --lane bridge
./scripts/omi-harness run e2e/flows/speaker-naming.yaml --lane bridge
./scripts/omi-harness run e2e/flows/memories.yaml --lane bridge
./scripts/omi-harness run e2e/flows/tasks-crud.yaml --lane bridge
./scripts/omi-harness run e2e/flows/goals-dashboard.yaml --lane bridge
./scripts/omi-harness run e2e/flows/focus.yaml --lane bridge
./scripts/omi-harness run e2e/flows/plan-usage.yaml --lane bridge
./scripts/omi-harness run e2e/flows/export-my-data.yaml --lane bridge
```

`export-my-data.yaml` is a planned S-23 typed flow. Its stable bridge seam may inject a temporary destination for the service result, but it must not replace the Account Settings UI test. Use native UI automation once for the actual **Export My Data** row, save-panel cancel, and save success.

Acceptance matrix:

1. **Local conversation:** record a short fixture, observe live transcript, stop/finalize locally, reopen detail, search, star/folder/merge as applicable, restart the named bundle, and verify no cloud conversation/audio/product write.
2. **Speakers:** generic labels and local rename work; no reusable profile/upload/People operation is available.
3. **PTT/realtime/TTS/images:** both retained realtime providers, PTT/file transcription, OpenAI `/v1/tts`, screen-aware PTT, Chat image attachment, and Rewind image behavior remain. ElevenLabs/Pro/streaming/OpenRouter/rejected image products are unavailable.
4. **Memories/Tasks/Goals/Focus/Insights/Profile:** create/read/update/delete/restart paths remain local; no rating/score/headline persistence or cloud product call appears.
5. **Chat:** create/switch/reopen local Chat and use an explicit local attachment; no hosted message report/export storage call occurs.
6. **Notifications:** trigger a hermetic S-20 warning state. Verify fixed truthful in-app copy and required local OS notification exactly once; denial/reconnect/restart/duplicate/owner-switch cases remain truthful; no FCM token/message call occurs.
7. **Updates:** local What's New and Sparkle check remain; cloud announcements are absent. Do not install/relaunch a production-family update.
8. **Account/usage:** Sign Out, disabled Account & Plan, subscription/usage quota/total and paywall/fair-use presentation remain. Logs show zero billing provider transaction.
9. **Export:** seed one record per approved local section, disable product network, save through Account Settings, validate schema/counts/order with `jq`, then inject failure and prove no partial file. Server metadata failure does not block local export.
10. **Owner boundaries:** switch A -> B and same-UID reauthenticate while export/notification/model work is suspended; no A data/result/file/notification commits as B and no late result survives generation change.
11. **Removed routes:** direct requests against the local assembled backend return 404, not 401/403/fake success, for every deleted operation. Retained neighbors still return their normal authenticated behavior.
12. **Restart/offline/failures:** local product paths survive backend unavailability; provider timeout/suspension has existing failure behavior and no phantom local state; persistence failure leaves no phantom product/file/notification.

Clean up only the named bundle and disposable local fixture state through documented harness controls. Do not use broad kill/delete commands and do not use production identities.

## 16. Repository closure versus separately authorized live operational closure

The S-23 PR can prove code/contract/schema ownership and prevent new rejected writes. It cannot prove or perform live deletion. After repository closure, prepare a read-only inventory using verified environment/project identifiers supplied by the platform owner. Do not guess identifiers or read secret values.

| External system | S-23 expected classification | Required later read-only evidence / owner |
|---|---|---|
| Firestore | Rejected product collections/subcollections and analytics schemas have no writers; retained account/billing/quota/fair-use/deletion/update data remains | Collection/index/rule reference graph, document counts/age only where privacy-approved, retention/legal/backup requirements; S-24/S-27/data owner |
| Redis | Product phone/speech/notification/conversation keys have no writers; auth/rate-limit/quota/fair-use/TTS retained | Namespace scan by prefix/count/TTL without values, last writer/traffic, rollback need; S-24/S-25/S-27 |
| GCS | Recording/speech/private-sync/postprocess/product paths have no writers; update/preview bucket protected | Bucket/object-prefix/IAM/lifecycle/retention/legal/reference inventory without content download; S-24 |
| Typesense/Pinecone/OpenAI Files | No S-23 product caller; physical resources unknown | Collection/index/namespace/file reference and retention inventory; S-24 |
| Cloud Tasks | Audio merge/finalization should be zero-producer; account deletion retained | Queue/task counts, oldest age, retry/target/signer/audience; S-25/S-27 |
| Cloud Run/GKE/jobs/images | Product routes may be gone while workers/services still exist | Revisions/traffic/workloads/images/workflows/rollback/alerts/reference graph; S-25 |
| Secret Manager/IAM | Product credential bindings become candidates; values never read | Retained revision/workload reference graph, last-use and rollback window; S-24/S-25/S-27 |
| Twilio/OpenRouter/ElevenLabs/Perplexity/FCM | Repository caller/config absent; external account/resource state unknown | Provider resource, contract, retention, webhook/credential-use inventory; authorized provider/platform owner |
| Billing | `BILLING_MODE=disabled`; Dodo activation remains closed | No transaction or activation in S-23; follow `dodo-integration.md` after Wave 6 |

Operational procedure, only after explicit authorization:

1. verify environment/project/account identifiers and operator authority;
2. export sanitized inventory evidence and classify each resource retained/rejected/shared/unknown/already absent;
3. resolve legal, retention, backup, customer-data, contract, rollback, and incident-hold requirements;
4. stop new writers in the already-merged repository/deployment and observe the agreed quiet/drain window;
5. disable/revoke or quarantine before irreversible deletion where the provider supports recovery;
6. mutate one independently owned family at a time, with rollback and health evidence;
7. let S-24 delete data/search/object resources and S-25 delete queues/services/images/secrets/GKE in their authorized order;
8. rerun inventory and named-bundle retained-path acceptance, then attach sanitized evidence.

Repository merge does not authorize deployment, traffic changes, queue purge, provider cancellation, IAM/secret mutation, data deletion, image deletion, or infrastructure teardown.

## 17. Risks, ambiguities, and explicit stop points

| Risk / missing input | Affected cycles | Safe work now | Evidence required to reopen / owner |
|---|---|---|---|
| S-20 local-GRDB/transient-GPT-5.1 implementation is not integrated | 13, 18 | Inventory and retained notification characterization | Integrated S-20 commit, bounded authenticated evidence contract, content-free durable state, and warning acceptance; S-20/product owner |
| S-20 currently plans FCM for retained warnings | 13 | Preserve semantics; define no second API | Stable authenticated Mac state interaction covering required transitions/restart/dedup; S-20/S-23 owners |
| S-22 implementation is absent or its OpenRouter handoff is not Wrapped-only | 10, 15, 18 | Delete no provider; record current caller | Closed S-22 result with exact Wrapped-only handoff; S-23 owner stops on any additional caller |
| S-19 hosted conversation tools may still be live | 3, 6, 18 | Other product families | Integrated local PTT tool/search caller-absence proof; S-19 owner |
| Finalizer/audio-merge/Pusher code still needs S-25 operational order | 1-4, 18 | Remove product ingress/schema only where worker remains functional | Exact zero-producer handoff plus queue/backlog/rollback inventory; S-25/platform owner |
| Physical product data may exist in Firestore/Redis/GCS/search/vector/files | 2-8, 16, operational | Stop new repository writers; no live query/mutation | Authorized read-only inventory, retention/legal/backup decision; S-24/data owner |
| Account deletion still needs Dodo and provider cleanup sequencing | 16 | Remove only S-23-owned cleanup after product closure; preserve exact Pinecone failure semantics | Retained Dodo seam, exact Pinecone handoff, and strict lifecycle tests; S-08/S-18/S-23, then S-24 deletes Pinecone |
| Local export settings allowlist is not yet encoded | 17 | Conversations/Memories/Tasks/Goals/Chat/Focus/Insights readers can be characterized | Product/privacy owner approves exact preference keys; S-08/S-23 |
| Kernel journal or local domain reader is not complete/paged | 17 | Add no table scan or cache dump | Owner module exposes tested owner-scoped paging; S-10 through S-14/S-11 |
| IR-830 does not include binary attachments/Rewind media | 17 | Export the decided JSON sections only | New reviewed requirement before expansion; product/privacy owner |
| Announcement version helper has retained app-review caller | 11 | Characterize exact semantics | Behavioral parity tests and narrow retained module owner; backend/update owner |
| Operational device ID shares rejected field names | 5 | Delete only Conversation/Memory provenance fields | Caller/owner proof for auth/abuse/update/metrics; security/backend owner |
| Historical local migration strings trigger residue searches | 5, 7, 18 | Keep tested history and classify it | Migration fixture proves final live schema exclusion; local-store owner |
| Live external provider/project/resource identifiers are absent | §16 | Repository-only work; no guessing | Verified identifiers and explicit read/mutation authorization; platform/provider owner |
| Released client or contractual compatibility population appears | all route cycles | Stop route deletion; continue unrelated families | Evidence and reviewed transition decision; product/API owner |

Stop the affected cycle whenever:

- passing GREEN would change a retained prompt, classifier threshold, quota band, warning cadence/copy meaning, PTT/realtime behavior, local search semantics, update behavior, or account lifecycle;
- a deleted route would become an alias/no-op/fake success or an ignored-field compatibility shell;
- a source-string check is offered instead of a behavioral production-seam test;
- a shared helper has an unclassified retained caller;
- a successor-owned queue/service/store/resource would be deleted without its owner and authorization;
- the implementation requires a new product decision, external secret/model/provider choice, or live mutation.

## 18. Final completion checklist

- [ ] G0 recorded current `HEAD`, `origin/main`, diff, clean ownership, requirements validation, and integrated predecessor commits.
- [ ] S-20 and S-22 implementation results are integrated; the S-19 cycle-local PTT gate is satisfied where required.
- [ ] Every assigned decision—IR-039, IR-043, IR-121, IR-122, IR-123, IR-186, IR-187, IR-289, IR-290, IR-310, IR-338, IR-359, IR-369 through IR-383, IR-714 through IR-725, IR-805, and IR-814 through IR-835—has behavioral evidence and a closure disposition.
- [ ] All 18 cycles have independent RED/GREEN evidence, retained sibling proof, deletion evidence, and no unresolved stop.
- [ ] Cloud recording/private sync/training and product audio writers/schemas are gone; local capture/transcripts/PTT/TTS/Rewind remain.
- [ ] People/speech profiles/persistent speaker identity are gone; generic diarization and local names remain.
- [ ] Wearable/glasses/whole-recording product paths are gone; Mac image and prerecorded STT paths remain.
- [ ] Hosted conversation protection/provenance/processing/metadata/mutation/search/Calendar/share schemas are gone; local behavior remains.
- [ ] Memory ratings/scoring/durable headline and summary-rating routes are gone; local lifecycle/Insight headline/LangSmith eval remain.
- [ ] Public sharing/Persona/hosted Chat report residue is gone; local Chat/Profile/Copy Transcript/Report Issue remain.
- [ ] Twilio, Wrapped/OpenRouter, announcements, Trends, Joan, FCM, ratings/scores/detailed usage, and rejected model product residue are each closed independently.
- [ ] Daily Summary, firmware, Limitless, Notifications job, memory-maintenance job, backend-integration, Plugins, and other already-absent families remain absent without no-op replacements.
- [ ] Retained `/v1/tts/synthesize`, Flash/Lite/embeddings, preview rewrite, greeting/title, managed Chat/realtime, LangSmith, Prompt Hub, Sentry/PostHog, updates/previews, subscription/quota/usage totals, and disabled billing are green.
- [ ] Account deletion invokes retained Dodo/Firebase/Firestore plus only the exact S-24-owned Pinecone purge handoff; durable OIDC/job/retry/reconcile/tombstone behavior remains.
- [ ] Export My Data works offline, owner-fenced and atomically; server export is metadata-only and has no product-content reader.
- [ ] Removed operations return genuine 404 and are absent from app-client OpenAPI, generated Swift, route policy, docs, and exclusive tests.
- [ ] Firestore index/rule, Redis namespace, GCS product-path, account-deletion/export, dependency/config/analytics/docs inventories contain no unclassified S-23 product owner.
- [ ] Every remaining audio/finalization/Pusher/search/vector/object/service/deploy hit is an exact S-24 or S-25 handoff, not a generic legacy exception.
- [ ] Focused backend/Swift/Node tests, OpenAPI generation/check, route policy, test discovery, official affected backend/desktop suites, ledger validator, `git diff --check`, and `make preflight` all pass.
- [ ] `omi-wave4-s23` acceptance covers retained local paths, notification delivery, export, offline/restart/failure/account-switch/same-UID/late-result behavior, and deleted-route 404s.
- [ ] PR preflight passes with failure-class declaration/evidence where required; verification commands and real user-path observations are written down.
- [ ] No new `TODO`/`FIXME`/`HACK` lacks a tracking issue; docs and component guides move with changed ownership/config.
- [ ] Repository closure and separately authorized live inventory/decommission remain distinct; no deploy or external mutation is inferred.
- [ ] No production Omi app, production account, production data, external infrastructure, or Windows source was touched.
