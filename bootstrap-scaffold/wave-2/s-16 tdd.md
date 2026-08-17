# S-16 — Keep `/v4/listen` as transient STT and delete server conversation ownership

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | S-16 |
| Wave | Wave 2 — establish local authority before deleting remote authority |
| Assigned output | `bootstrap-scaffold/wave-2/s-16 tdd.md` |
| Assigned decisions | IR-017 through IR-023, IR-384 through IR-405, IR-726, IR-887 through IR-889, IR-898 |
| Product boundary | Continuous Mac capture, transient managed cloud STT, generic diarization, transient translation, listen admission/status, and deletion of server conversation/session/speaker-identity ownership |
| Implementation rule | Consume S-10's local conversation authority. `/v4/listen` may authenticate, meter, transcribe, diarize, translate, and report truthful transport state; it may not create, identify, reconcile, roll over, persist, or finalize a conversation. No compatibility route, ignored field, alias, or no-op lifecycle remains. |

This is the execution-grade TDD plan for S-16. Producing it does not authorize product-code changes, repository publication, deployment, or live-resource mutation.

## 2. Planning status and pinned baseline

| Evidence | Verified planning state on 2026-08-16 |
|---|---|
| Checkout | `/Users/srujanu/conductor/workspaces/knowledge-athlete/honiara` |
| Branch | `review-wave-1-deletions` |
| Pinned code baseline | `0d9934c9d2ed61bd02ac8784e50f56ee816257c3` |
| Required ancestry | `git merge-base --is-ancestor 0d9934c HEAD` returned success |
| Planning-time `origin/main` | `3aab1026357fb0be6bcf567c24df84684ba6198e` |
| Requirements proof | `python3 bootstrap-scaffold/validate-requirements-ledger.py` passes with 714 indexed rows, 714 detailed sections, all reviewed |
| Source grounding | Current paths, symbols, routes, tests, workflows, manifests, and documentation named as existing below were found in this checkout. Planned names are marked **new**. |
| Readiness | Research complete. Implementation is blocked until S-10 is integrated, the execution branch is rebased, and the caller/residue inventory is refreshed. |

The pinned baseline is planning evidence, not an execution SHA. S-10 is presently available only as an untracked planning document in this worktree, not as integrated production code. Starting S-16 against the pre-S-10 Mac would either delete a still-live cloud authority or require a forbidden temporary compatibility path. Before the first RED, record a new immutable execution SHA that contains S-02, S-03, and S-10, and verify the predecessor shapes in Section 5.

The planning checkout also contains unrelated untracked Wave 2 plans. They are not S-16 inputs to edit and must remain untouched.

## 3. Outcome

At repository completion:

1. The signed-in Mac owns recording/conversation identity, boundaries, stable segment UUIDs, transcript normalization, local speaker labels, GRDB persistence, local finalization, and display.
2. `/v4/listen` is one authenticated transient WebSocket. It accepts only the immutable session configuration plus fixed mono 16 kHz signed 16-bit little-endian PCM, streams that audio to managed Modulate, and returns transient segments, translations, `ready`, `stt_failed`, and the retained structured subscription signal.
3. The listen server does not read or write a Firestore conversation, Redis in-progress conversation ID, recording-session lifecycle, transcript array, People/speech-profile identity, Pusher conversation channel, Cloud Task finalizer, audio object, or local-to-cloud reconciliation key.
4. A transient cloud segment has one required `segmentId` UUID, one numeric `speakerId`, text, start/end time, and any transient translation. Provider-formatted speaker strings, `person_id`, provider identity, speech-profile flags, and backend-conversation identity are absent.
5. Apple Silicon local Parakeet and Intel/forced/failure managed cloud STT feed the same S-10 local ingestion transaction. Provider choice does not change durable schema, joining, boundary repair, punctuation, formatting, naming, or completion.
6. Language, automatic detection, translation target, and vocabulary are snapshotted locally per recording and supplied explicitly for that listen session. The backend does not hydrate or overwrite them from `users/{uid}`.
7. Managed Modulate is the only hosted listen STT provider. Backend-configured in-process VAD remains fail-open; the client cannot override it. Live translation uses Gemini 2.5 Flash-Lite only and returns directly to the Mac; NLLB and its entire repository control plane are gone.
8. Mic plus System Audio, automatic meeting gating, the exact three System Audio modes, local meeting/Stop/Finish-and-Continue/four-hour boundaries, WebSocket reconnect/watchdog, ready/failure truth, and generic diarization remain user-visible behavior.

Repository closure is not live-cloud closure. Deleting NLLB charts/workflow/runtime declarations and removing listen's Pusher/Firestore callers does not authorize deleting deployed services, Kubernetes objects, Cloud Run revisions, secrets, Redis/Firestore data, queues, or alerts.

## 4. Authorizing requirements

Every assigned decision is mapped individually. Requirements that S-10 materializes locally remain authorizing invariants for S-16 but are not reimplemented here.

| IR | S-16 materialization | Plan coverage |
|---|---|---|
| IR-017 | Keep microphone plus System Audio capture and the Mac mono mix sent to the retained STT path. | Entry characterization; Cycles 2, 8; named-bundle acceptance |
| IR-018 | Keep automatic meeting detection and its local recording boundary. Python never substitutes a silence timeout. | Entry characterization; Cycles 1, 8 |
| IR-019 | Keep Apple Silicon local Parakeet and managed `/v4/listen` for Intel/forced/failure fallback, generic diarization, and both directions of availability. | Cycles 1, 4, 8 |
| IR-020 | Make cloud listen transient only; Mac owns ID, boundary, persistence, completion, and display. Delete server conversation creation, duplication, lifecycle, reconciliation, and finalization. | Cycle 1; residue closure |
| IR-021 | Delete listen-time persistent voice recognition while retaining generic within-conversation diarization and local manual labels. | Cycle 7; S-23 handoff |
| IR-022 | Delete reusable People from listen; retain conversation-local `You`/custom names in S-10's local label table. | Cycle 7; S-10/S-23 handoff |
| IR-023 | Keep language/auto-detect/vocabulary local and send an immutable session snapshot; remove listen Firestore hydration and `GET/PATCH /v1/users/transcription-preferences` after callers migrate. | Cycle 3 |
| IR-384 | Delete custom-STT query state, suggested-transcript injection, custom usage stamp, durable per-segment provider identity, and provider merge fences. | Cycle 6 |
| IR-385 | Emit one numeric `speakerId`; convert Modulate's 1-indexed speaker once at the adapter boundary and discard provider formatting. | Cycle 4 |
| IR-386 | Require one stable `segmentId` UUID for each cloud segment; keep the GRDB integer row ID internal and let S-10 remove aliases/fallback identity. | Cycle 4 |
| IR-387 | Preserve live Name Speaker through S-10's local `You`/Add Name flow; remove listen People/suggestion behavior. | Cycle 7 |
| IR-388 | Preserve same-speaker joining locally for both providers; server must not re-run it. | Cycle 4 protection test; S-10-owned implementation |
| IR-389 | Preserve local atomic cross-speaker boundary repair and any resulting segment update/delete; server emits raw transient utterances rather than conversation mutations. | Cycle 4 protection test; S-10-owned implementation |
| IR-390 | Preserve one local punctuation-spacing cleanup before persistence. | Cycle 4 protection test; S-10-owned implementation |
| IR-391 | Preserve one local formatter for retained models using local numeric speakers and labels; delete listen/People formatting dependencies. | Cycles 4, 7; S-10-owned implementation |
| IR-392 | Preserve authenticated first name from Firebase/local auth, fallback `User`, visible `You`; never reintroduce a listen Firestore-profile fallback. | Cycles 3, 4 protection test; S-10-owned implementation |
| IR-393 | Preserve optional timestamps and overlap guard in the local formatter. | Cycle 4 protection test; S-10-owned implementation |
| IR-394 | Delete server timeout, polling, rollover, stale recovery, and finalization; keep local meeting, Stop, Finish-and-Continue, four-hour rotation, watchdog, and reconnect. | Cycles 1, 8 |
| IR-395 | Delete Python spoken-question onboarding mode, synthetic speaker 99, skip input, and onboarding events; keep native Mac onboarding. | Cycle 6 |
| IR-396 | Delete listen `call_id` and its hosted association. | Cycle 6 |
| IR-397 | Delete `client_conversation_id`, recording-session identity, `conversation_session`, rotated backend IDs, and cloud reconciliation; keep local generation fencing across reconnect. | Cycles 1, 6, 8 |
| IR-398 | Delete `/v4/web/listen`, first-message auth/device metadata, `auth_response`, fixtures, and route-policy entry; retain normal Firebase upgrade auth on `/v4/listen`. | Cycle 6 |
| IR-399 | Delete special multichannel protocol/phone channel map while retaining Mac mic/System Audio capture mixed to one mono stream. | Cycles 2, 6 |
| IR-400 | Delete client listen provider hints. Server policy remains fixed managed Modulate. | Cycles 2, 6 |
| IR-401 | Keep server-configured VAD plus fail-open behavior; delete client override and do not conflate it with the disconnected Mac Local VAD setting. | Cycle 2 |
| IR-402 | Keep cloud live translation as transient compute with explicit session target and local SQLite result authority; original transcript survives translation failure. | Cycle 5 |
| IR-403 | Fix listen to mono 16 kHz signed 16-bit little-endian PCM and delete listen-only PCM8/Opus/AAC/LC3/format compatibility. Do not alter PTT codecs. | Cycle 2 |
| IR-404 | Remove listen's stable device hash and app-version headers/state; retain `X-App-Platform: macos` for coarse diagnostics. Other endpoints remain untouched. | Cycle 2 |
| IR-405 | Keep `ready`, `stt_failed`, and retained structured subscription truth; delete initiating, STT-initiating, processing, last-memory, and cloud lifecycle statuses. | Cycles 1, 6 |
| IR-726 | Use Gemini 2.5 Flash-Lite alone for retained translation; preserve detection/target validation, splitting, batching/cardinality, empty handling, dedup/cache, failure, metrics, original-on-failure, and local output. Delete NLLB service/code/chart/workflow/runtime configuration/tests/docs and one-item provider-list policy. | Cycle 5 |
| IR-887 | Preserve Modulate as current managed STT. | Entry gate; Cycles 1, 3, 4 |
| IR-888 | Preserve Mac-local Parakeet and do not restore hosted GPU Parakeet already removed by S-03. | Entry gate; Cycles 4, 8 |
| IR-889 | Do not restore Deepgram branches already removed by S-03. | Entry gate; residue closure |
| IR-898 | Preserve exactly Always, Only During Meetings, Never; default to meetings; header shortcut cycles only meetings/always; Never keeps continuous microphone-only transcription. | Entry characterization; Cycle 8; named-bundle acceptance |

There is no conflict between the detailed requirements and the S-16 deletion-map brief at this baseline. The detailed requirements control if a conflict appears after rebase.

## 5. Dependencies and entry gates

### Required predecessor shapes

| Dependency | Exact shape S-16 consumes | Gate and stop condition |
|---|---|---|
| S-02 | Per-effective-owner GRDB/WAL ownership and generation-aware authorization from `RewindDatabase`; no shared-owner fallback. | Already integrated at the planning baseline. Stop if S-16 would need a new owner/database mechanism. |
| S-03 | Managed listen STT fixed to Modulate, hosted Parakeet/Deepgram branches removed, Mac-local Parakeet retained, `MODULATE_API_KEY` as the managed binding. | Already integrated. Stop if execution HEAD reintroduces provider selection or hosted Parakeet. |
| S-10 | `TranscriptionStorage` is the only durable conversation writer; required local conversation/segment UUIDs, one numeric speaker ID, provider-independent local normalizer/formatter, local labels, local settings snapshots, local finalization/recovery, and no Mac cloud conversation binding. | Mandatory before Cycle 1 production work. Stop if the Mac still depends on `conversation_session`, backend IDs, server finalization, cloud preferences, People, or server transcript persistence. Do not reproduce S-10 or bridge old/new shapes. |

S-10's current plan names expected seams, not released APIs. At execution, replace plan-level names with the integrated symbols and update the implementation PR's inventory. S-16 may make the final wire adaptation in `TranscriptionService.swift` and `AppState+ListenEvents.swift`; it must not rebuild S-10's schema, local normalizer, labels, formatter, finalizer, or settings store.

### Mandatory execution entry sequence

Run in a new S-16 worktree/feature branch; do not rename or reuse this planning branch:

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

Then repeat every Section 13 search, verify S-10's integrated tests/seams, and record the immutable execution SHA and caller ledger in the implementation PR.

### Entry gates

1. **S-10 authority gate:** no production RED begins until local identity, ingestion, labels, finalization, settings, offline/restart behavior, and Mac removal of cloud lifecycle are integrated and green.
2. **Retained-behavior characterization gate:** run the integrated S-10 tests for local/cloud ingestion, reconnect/generation fencing, translation attachment, meeting boundaries, System Audio modes, and local finalization before deleting backend behavior.
3. **Public wire gate:** freeze a single explicit `/v4/listen` contract. The allowed session query is `language`, optional `translation_target`, and repeated `vocabulary` terms; audio parameters are fixed by the route. Firebase upgrade auth and `X-App-Platform` are headers. Unknown/retired listen parameters fail closed instead of being ignored.
4. **Provider-contract gate:** recheck Modulate's official streaming AsyncAPI at execution. As of planning, [`velma_2_stt_streaming.yaml`](https://docs.modulate.ai/api/velma_2_stt_streaming.yaml) defines an optional first JSON config frame with `language` and `custom_terms` (up to 1,000 entries/8,000 serialized term characters), finalized `utterance_uuid`, and a 1-indexed numeric speaker. If that contract changed or the configured commercial API does not accept it, Cycle 3/4 stops; do not accept and ignore vocabulary.
5. **No-dual-path gate:** the first transient GREEN replaces the conversation-owned route path. Do not retain a hidden legacy flag, second runtime, fallback conversation write, deprecated alias, or no-op finalization callback.
6. **Billing/entitlement gate:** structured subscription/fair-use admission and usage accounting remain until S-20 or another assigned slice changes them. They may use account state, but may not write product conversation/transcript state.
7. **Shared-file gate:** S-14 also changes `backend/routers/listen/runtime.py` to remove personalized credit-limit pushes while retaining the structured signal. Rebase over its integrated result if present; S-16 must not recreate or independently own IR-724.
8. **Route-removal gate:** `/v4/web/listen` has no in-repo product caller, but live external-client removal still requires the API owner/deployment inventory described in Section 16. Repository code must not keep it as compatibility after authorization.
9. **Behavioral-test gate:** every cycle begins with an executable public-seam failure. Source residue checks are supplementary static tripwires only.
10. **Operational gate:** no live NLLB/Pusher/backend-listen/diarizer/Firestore/Redis/secret deletion occurs in this slice without separate explicit authorization and live inventory.

## 6. Current production codeflow

### 6.1 Mac capture and local/cloud selection before S-10

1. `AppState+Transcription.swift` starts continuous capture, owns microphone/System Audio sources, meeting gating, Stop/Finish-and-Continue, four-hour rotation, and selects `LocalTranscriptionService` on Apple Silicon unless forced/failing; Intel and fallback use `TranscriptionService` in `.conversation` mode.
2. System Audio and microphone remain distinct Mac capture sources, but the cloud path mixes them into mono. `TranscriptionService` already buffers 100 ms chunks of 16 kHz signed 16-bit audio.
3. The current conversation URL still sends `language`, `sample_rate`, `codec=linear16`, `channels`, `include_speech_profile`, `source`, `speaker_auto_assign`, and optional `client_conversation_id`. It sends Authorization plus `X-App-Platform`, `X-Device-Id-Hash`, and `X-App-Version`.
4. The service parses arrays of `BackendSegment` with optional ID, duplicate string/numeric speaker, `person_id`, and translations, or arbitrary event objects. It retains reconnect backoff, a 30-second watchdog check, and a 60-second stale threshold.
5. `AppState+ListenEvents.swift` binds backend conversation IDs, converts optional/provider-shaped segment fields, writes cache-shaped GRDB rows, applies `segments_deleted`, handles People/speaker suggestions, translation batches, conversation/memory lifecycle, and ready/failure/freemium events. `ConversationFinalizationService` and `TranscriptionRetryService` reconcile/upload/finalize the server copy.
6. S-10 is assigned to replace steps 3–5's authority with stable local conversation/segment identity, common normalization, local labels/settings/finalization, and a narrow transient event consumer. S-16 consumes that integrated result and finalizes the wire.

### 6.2 WebSocket admission and session bootstrap

1. `backend/routers/transcribe.py` exposes `/v4/listen`, `/v4/web/listen`, `_listen`, and the historical `_stream_handler` facade. Normal listen authenticates during upgrade through `get_current_user_uid_ws_listen`; web listen accepts first, waits five seconds for an auth/device message, emits `auth_response`, then calls the same runtime.
2. `ListenRequest` in `backend/routers/listen/contracts.py` currently defaults to 8 kHz PCM8 and carries channel count, speech-profile inclusion, server timeout, custom STT, onboarding, speaker auto-assignment/creation, VAD override, call ID, client conversation ID, and device context.
3. `ListenSessionRuntime._admit` checks UID, trial/credit admission, and variable audio format. `_bootstrap` reads user existence, entitlement/fair-use state, transcription preferences/language/vocabulary, private-cloud sync, speech-profile state, and custom-STT usage from Firestore/Redis-backed helpers.
4. The runtime generates session and recording IDs, normalizes the client conversation UUID, resolves device identity, chooses language/translation from backend preferences, constructs speaker/translation/conversation components, and can construct `OnboardingHandler`.

### 6.3 Managed STT, VAD, and receiver

1. `ListenReceiver` initializes optional decoders, channel configuration, managed STT sockets, STT death monitoring, buffering, text-control messages, and the receive loop.
2. It accepts PCM8/PCM16 and optional Opus/AAC branches, supports special multichannel splitting/mixing, custom `suggested_transcript`, onboarding `skip_question`, `speaker_assigned`, and client VAD override behavior.
3. `process_audio_modulate` in `backend/utils/stt/streaming.py` connects to Modulate with `speaker_diarization=true`, `partial_results=true`, raw `s16le`, sample rate, mono, and optional language. The current adapter converts Modulate's numeric speaker to `SPEAKER_N`, discards `utterance_uuid`, and does not send the already-loaded vocabulary.
4. `utils/stt/vad_gate.py` owns the retained server-configured VAD and fail-open wrapper. `receiver.py` must keep that server configuration but lose the client override and noncanonical listen formats.

### 6.4 Server conversation, transcript, speaker, and finalization ownership

1. `LiveConversationController` creates/reuses Firestore in-progress conversations, maps recording sessions, emits conversation lifecycle, polls every five seconds for timeout rollover, recovers stale rows, sends last conversation, invokes Pusher/Cloud Task finalization, and removes Redis in-progress IDs.
2. `TranscriptProcessor` uses `ConversationCache` to load Firestore conversation state, converts provider fragments into `TranscriptSegment`, performs combining/boundary/punctuation logic, writes updated transcript arrays/finished times, sends deleted-segment and translation events, invokes Pusher, onboarding, and speaker matching, and flushes translation/speaker assignment.
3. `SpeakerMatcher` loads speech profiles and People embeddings, samples ring-buffer audio, matches persistent voices, and emits `SpeakerLabelSuggestionEvent`. The broader People/speech-profile product also has other routes/services owned by S-23; only listen's dependency is S-16.
4. `ListenPusherSession` sends audio/transcripts/conversation IDs and processing callbacks to Pusher. The runtime teardown flushes translations/usage, reads/finalizes the current conversation, removes Redis identity, drains multichannel/Pusher/onboarding, and clears components.
5. `ListenPersistence` is a generic executor wrapper used by both rejected conversation operations and retained account/usage operations. It cannot be blanket-deleted until its final caller inventory is split.

### 6.5 Translation and NLLB control plane

1. The current listen bootstrap derives a translation target from server-synced language/single-language preferences. `TranscriptProcessor` starts `TranslationCoordinator`, persists each result into the Firestore transcript, and then emits translated segments.
2. `config/translation.py` resolves a list from `TRANSLATION_SERVICE_MODELS`, accepts Gemini/legacy Google and NLLB, and combines it with `HOSTED_TRANSLATION_API_URL`.
3. `utils/translation.py`, `translation_core/{planner,engine,providers,cache,metrics}.py`, `translation_cache.py`, `translation_coordinator.py`, and `translation_language.py` own validation, splitting, batching, dedup/cache, provider execution, failure, and metrics.
4. NLLB has a complete GPU service and control plane: `backend/nllb_translation/`, `backend/charts/nllb-translation/`, `.github/workflows/gcp_nllb_translation.yml`, runtime-image/runtime-env registration, backend-listen env values, deployment validation/concurrency/pre-push/check-manifest/workflow-contract references, benchmarks, tests, README/TUNING, and `backend/docs/translation-architecture.md`.

### 6.6 Preferences, route policy, contracts, tests, and docs

1. `GET/PATCH /v1/users/transcription-preferences` in `backend/routers/users.py` reads/writes `users/{uid}.transcription_preferences` through `backend/database/users.py`. `PATCH /v1/users/language` also mutates `single_language_mode`; the general language route/field has sibling callers and cannot be deleted wholesale.
2. Mac `APIClient+Settings.swift`, transcription Settings helpers, onboarding/automation, and generated `OmiApi.generated.swift` currently expose or call these preferences. S-10 is expected to remove Mac cloud authority; S-16 deletes remaining backend route/helper/contract residue only after that proof.
3. `backend/route_policy_legacy_missing_routes.txt` lists both listen WebSockets and both transcription-preference methods. WebSocket routes are not ordinary OpenAPI client operations, but the preference DTOs are app-client generated contracts.
4. Existing tests assert server conversations, `/v4/web/listen`, custom STT, multichannel audio, Pusher, People/speaker identity, variable codecs, Firestore translation persistence, NLLB selection, and lifecycle statuses. They must be rewritten or deleted with the rejected behavior; retained auth, VAD, STT death, heartbeat, usage, local capture, and ready/failure tests remain.

## 7. Complete caller and dependency inventory

This inventory covers non-Windows in-repository production callers and exclusive tests/control-plane residue at the pinned baseline. Re-run it after S-10 integration because many Mac rows should disappear or change ownership.

### 7.1 Mac production and tests

| Current file / seam | Current dependency | S-16 disposition |
|---|---|---|
| `desktop/macos/Desktop/Sources/AppState/AppState+Transcription.swift` | Provider selection, mic/System Audio mix, capture boundaries, generated client conversation ID, cloud/local finalization choice | Adapt only final transient transport wiring; preserve capture/provider/boundary behavior; consume S-10 local authority. |
| `desktop/macos/Desktop/Sources/TranscriptionService.swift` | `/v4/listen` URL/query/headers, provider-shaped `BackendSegment`, event parser, buffering, reconnect/watchdog; also owns separately retained PTT modes | Adapt conversation mode only. Do not alter `/v2/voice-message/*` PTT contracts/codecs/provider diagnostics. |
| `desktop/macos/Desktop/Sources/AppState/AppState+ListenEvents.swift` | Segment conversion/persistence plus conversation, memory, People, translation, ready/failure/freemium events | After S-10, narrow to required segment/translation/status events and local ingestion; delete rejected handlers. |
| `desktop/macos/Desktop/Sources/LocalTranscriptionService.swift` | Produces `TranscriptionService.BackendSegment` for local Parakeet | Keep; adapt only to S-10's common required segment shape. |
| `desktop/macos/Desktop/Sources/Rewind/Core/TranscriptionModels.swift`, `TranscriptionStorage.swift` | Cache-shaped session/segment authority at baseline | S-10 owns migration. S-16 reads the integrated public ingestion seam; no schema changes unless S-10 leaves an explicitly documented final wire rename. |
| `desktop/macos/Desktop/Sources/ConversationFinalizationService.swift`, `TranscriptionRetryService.swift` | Upload/cloud reconcile and retry at baseline | S-10 owns replacement. S-16 must verify no listen/server lifecycle caller remains, not recreate it. |
| `desktop/macos/Desktop/Sources/MainWindow/Components/LiveNameSpeakerSheet.swift` and live transcript views | Cloud People and temporary live map at baseline | S-10 owns local labels. S-16 removes server suggestion/People events only. |
| `desktop/macos/Desktop/Sources/Services/APIClient/APIClient+Settings.swift`, Settings transcription helpers, onboarding/automation settings callers | Cloud transcription preference GET/PATCH | S-10 removes calls. S-16 removes final backend/generated route contract after zero-caller proof. |
| `desktop/macos/Desktop/Tests/ListenProtocolTests.swift` | Optional IDs, duplicate speakers, deleted/speaker-label/lifecycle events, reconnect | Rewrite around required transient segment/translation/status contract; retain reconnect behavior. |
| `LiveTranscriptionFailureStateTests.swift`, `TranscriptionConnectionStateTests.swift` | Visible terminal failure/ready and connection state | Keep/adapt; ready clears failure, terminal failure remains truthful. |
| `MeetingGatedSystemAudioTests.swift`, `SystemAudioConverterFormatTests.swift` | Meeting boundaries, exact mode persistence/default, mono conversion | Keep unchanged or add protection only; named-bundle acceptance covers real capture. |
| S-10's planned `ConversationIngestionTests`, `LocalTranscriptFormatterTests`, finalization/recovery/owner tests | Common local/cloud durable shape and local authority | Required entry/retention suite; S-16 must not duplicate its implementation. |

### 7.2 Listen backend production

| Current file / seam | Current responsibility / callers | S-16 disposition |
|---|---|---|
| `backend/routers/transcribe.py` | `/v4/listen`, `/v4/web/listen`, `_listen`, `_stream_handler` | Keep one `/v4/listen`; delete web route and historical facade; parse/fail-close exact session config. |
| `backend/routers/listen/contracts.py` | `CustomSttMode`, broad `ListenRequest`, conversation/speaker fields in `ListenSessionState`, limits | Replace with narrow immutable session config and transient state; retain only actual transport/usage limits. |
| `backend/routers/listen/runtime.py` | Admission, bootstrap, components, statuses, conversation/Pusher/speaker ownership, usage/fair use, heartbeat/teardown | Deepen as transient orchestrator. Delete product-data dependencies; retain auth/admission, usage, heartbeat, truthful status, managed STT supervision. |
| `backend/routers/listen/receiver.py` | Decoders, STT, variable/multichannel/custom/onboarding/control input, VAD, death monitor | Narrow to fixed binary PCM + heartbeat/close, managed Modulate, server VAD, failure; delete rejected protocols. |
| `backend/routers/listen/transcripts.py` | Firestore conversation cache/update, normalization, translation persistence, speaker/Pusher/onboarding, client delivery | Replace with a small transient delivery/translation coordinator or delete/split if the runtime can own it cleanly; no server normalization/persistence. |
| `backend/routers/listen/conversations.py` | Entire server conversation identity/lifecycle/finalization | Delete when Cycle 1 route is green. |
| `backend/routers/listen/speakers.py` | Persistent speech profile/People matching/suggestions | Delete listen component in Cycle 7; shared embedding services remain for S-23/S-25 inventory. |
| `backend/routers/listen/persistence.py` | Executor wrapper for mixed account and product-data calls | Simplify/rename around retained account/usage boundary or delete if direct typed seams replace it; never keep as a generic product-data escape hatch. |
| `backend/routers/listen/parity_capture.py`, `parity_pack_export.py` | Optional local diagnostic capture around listen | Keep only if it records bounded transient provider/audio diagnostics without conversation/PII authority and has a current test/owner; otherwise delete exclusive server-conversation fields in the owning cycle. |
| `backend/utils/listen_session_bootstrap.py` | Firestore prefs plus user/credits/fair-use bootstrap | Adapt to account/admission only; session config comes from request. |
| `backend/utils/transcribe_decisions.py` | Language plus custom/profile/multichannel/codec/timeout/session/speaker/VAD decisions | Retain validated language/VAD/account decisions; delete rejected helpers after caller migration. |
| `backend/utils/transcribe_store.py` | Convenience imports for conversations/Redis/users | Remove from listen. Delete module only if no independent caller remains. |
| `backend/utils/stt/streaming.py` | Managed Modulate adapter used by listen and possibly retained prerecorded/PTT paths | Adapt shared adapter deliberately: preserve other callers, add optional typed stream config/custom terms, emit UUID/numeric speaker at boundary. |
| `backend/utils/stt/vad_gate.py`, `backend/utils/stt/vad.py` | Server configured VAD and timing remap | Keep fail-open listen behavior; remove only client override. Audit other callers before any simplification. |
| `backend/utils/listen_audio.py`, `backend/utils/audio.py` | Channel config, resampling/mixing helpers | Delete listen-only multichannel/variable-format callers; retain helpers with PTT/other callers. |
| `backend/utils/listen_pusher_session.py`, `pusher.py`, `pusher_protocol.py`, `pusher_finalization.py` | Listen-to-Pusher conversation/audio/finalization plus other service callers | Remove listen caller/config. S-25 owns final service/control-plane deletion; do not absorb it. |
| `backend/utils/onboarding.py` | Python spoken interview | Delete if repository search confirms listen is the last production caller. Native Mac onboarding is untouched. |
| `backend/models/transcript_segment.py` | Duplicate speaker/provider/person fields, server combination/formatter, many non-listen callers | Remove listen reliance and only delete fields/helpers when S-10/later owner has migrated every caller. Do not broad-delete shared conversation model work assigned elsewhere. |
| `backend/models/message_event.py` | Conversation/memory/status/speaker/subscription event models | Delete listen-exclusive rejected event classes after global caller search; retain structured freemium and any independently used models. |
| `backend/utils/client_device.py` | Stable device/version parsing shared across endpoints | Stop using it in listen. Keep for retained task/notification endpoints; do not global-delete. |
| `backend/utils/observability/transcription.py`, `backend/utils/analytics.py`, fair-use/subscription helpers | Provider outcome, metering, entitlement | Keep privacy-bounded transient operational truth; ensure no conversation ID/raw transcript is logged. S-20 owns later fair-use redesign. |

### 7.3 Preferences, translation, deployment, contracts, tests, and docs

| Current surface | S-16 action |
|---|---|
| `backend/routers/users.py` transcription-preference models/routes and `backend/database/users.py` getters/setters/custom stamp/cache | Delete after S-10 caller proof. Remove the transcription side effect from general language update, but retain general language APIs/data if another owner uses them. |
| `backend/config/translation.py` | Replace provider-list/alias/NLLB resolution with one explicit Gemini route/config; no one-item provider list. |
| `backend/utils/translation*.py`, `backend/utils/translation_core/*.py` | Keep target/language validation, batching/cardinality, empty handling, dedup/cache, failure, metrics, and Gemini execution; delete NLLB provider/URL/list logic and Firestore persistence assumptions. |
| `backend/nllb_translation/**`, `backend/charts/nllb-translation/**`, `.github/workflows/gcp_nllb_translation.yml` | Delete entire repository service/control plane in Cycle 5. |
| `backend/runtime_images.json`, `backend/deploy/runtime_env.yaml`, backend-listen dev/prod values | Remove NLLB image/release/env and `HOSTED_TRANSLATION_API_URL`/`TRANSLATION_SERVICE_MODELS`; retain backend-listen itself until S-25. |
| `.github/checks-manifest.yaml`, `.github/scripts/check-deployment-concurrency.py`, `backend/scripts/validate_rendered_deployment_contract.py`, `scripts/pre-push`, `backend/testing/workflow_contracts.json`, `backend/tests/.single_process_safe_subset` | Remove or adapt NLLB/listen registrations atomically; do not leave dead checks. |
| `backend/scripts/benchmark_nllb_performance.py`, `tune_nllb_performance.py`; NLLB-only branches in `benchmark_translation.py` | Delete NLLB-only scripts/branches; keep a generic benchmark only if it still executes retained Gemini behavior and is wired/owned. |
| `backend/route_policy_legacy_missing_routes.txt` and route-policy/OpenAPI/generated-client tests | Remove web listen and transcription-preference entries; retain normal listen. Regenerate `OmiApi.generated.swift` after preference route/model deletion. |
| `backend/testing/e2e/test_listen_stt.py`, `test_core_flow_expansion.py`, `test_boundary_contract_compatibility.py`, `test_listen_pusher_wire_contract.py`, helpers/fakes | Rewrite around the single transient route or delete rejected scenarios. No test-only `/v4/web/listen` compatibility runtime remains. |
| `backend/tests/integration/test_listen_ws_live.py`, `test_listen_features_e2e.py`, `test_listen_chaos.py`, `test_listen_pusher_e2e.py`, speaker identity live/e2e tests | Retain/auth/failure/transient provider cases only; delete server conversation/Pusher/persistent-speaker assertions. Live tests remain outside CI and are recorded as manual evidence. |
| Unit tests named `test_listen_*`, `test_transcribe_*`, `test_optional_audio_codecs.py`, `test_validate_audio_format.py`, `test_vad_gate.py`, `test_translation_*`, `test_nllb_service_metrics.py`, route/runtime-image/deploy tests | Rewrite/delete with owning cycle; preserve retained heartbeat, STT-death, VAD fail-open, usage, translation behavior, and route presence. |
| `backend/testing/listen_pusher_stack/**` and listen lifecycle emulator wiring | Remove only if no retained non-S-16 owner/caller after server conversation deletion. S-25 may own service-level Pusher test stack; record exact handoff rather than silently deleting it. |
| `backend/AGENTS.md`, `PRODUCT.md`, `FORK.md`, `backend/docs/translation-architecture.md`, `backend/testing/e2e/README.md`, listen runbooks/parity docs, `desktop/macos/AGENTS.md`, `desktop/macos/CHANGELOG.json` | Update truth with code. Do not rewrite historical changelog entries merely because they mention old providers. |

## 8. Behavior classification

| Category | Exact S-16 classification |
|---|---|
| **KEEP AS IS** | Mac microphone and System Audio capture; automatic meeting detection; exact Always / Only During Meetings / Never behavior and default; header cycling only meetings/always; Never's continuous mic-only transcription; Apple Silicon local Parakeet; explicit Stop, Finish-and-Continue, four-hour rotation; WebSocket watchdog/reconnect intent; normal Firebase listen auth; managed Modulate; generic within-session diarization; server-configured VAD/fail-open; subscription/fair-use admission and structured signal; native Mac onboarding; PTT endpoints/codecs/provider diagnostics; original transcript on translation failure. |
| **ADAPT** | `/v4/listen` into a fixed transient wire; `ListenRequest`/runtime/receiver; Modulate adapter into typed session config and canonical UUID/numeric segment output; Mac conversation-mode request/parser into the final allowlist; translation into direct segment-keyed output/local commit; listen bootstrap into account-only admission; existing tests/contracts/docs; parity/observability into bounded transient diagnostics. |
| **DELETE** | Firestore/Redis conversation creation/reuse/poll/rollover/finalization; conversation/recording/client IDs and lifecycle events; listen Pusher ownership; transcript persistence/cache/server normalization; People/speech-profile matching and suggestions from listen; cloud preference hydration/sync endpoints/helpers; custom STT/suggested transcript/provider field; Python onboarding; `call_id`; `/v4/web/listen`; multichannel/legacy listen codecs; client VAD/provider hints; listen device hash/app version; initiating/processing/last-memory statuses; NLLB code/image/chart/workflow/config/tests/docs; exclusive fixtures/checks/metrics/alerts/config after caller removal. |
| **SIMPLIFY AFTER** | Collapse runtime components/state/limits after deletion; replace generic persistence wrapper with narrow account/usage seams; collapse translation provider list/aliases to explicit Gemini; remove adapter speaker-string formatting; delete dead helper branches/imports/task supervision; collapse event parser to typed transient events; remove dead tests and compatibility comments only after behavioral GREEN. |
| **OUT OF SCOPE / DEFERRED** | S-10 local schema/normalizer/formatter/labels/finalization/settings implementation; S-14 personalized credit-push removal; S-20 fair-use redesign; S-22 broader model policy; S-23 full People/speech-profile/hosted product-data deletion; S-25 Pusher/diarizer/backend-listen/finalizer deployed-service teardown; production data retention/deletion; live Kubernetes/Cloud Run/secrets/queues/alerts; PTT and realtime voice; general language fields/routes with surviving callers; historical changelog text. |

## 9. Retained behavioral invariants

1. A Mac local conversation UUID exists before capture output is admitted; reconnect never changes it and late callbacks from an old local generation cannot write into a new recording.
2. `/v4/listen` never creates or mutates a conversation/transcript/product row or emits an identifier for one. Test spies must cover Firestore, Redis, Pusher, Cloud Tasks, and object/audio storage boundaries.
3. The public listen route has one contract: Firebase upgrade auth; coarse `X-App-Platform`; `language`, optional `translation_target`, repeated `vocabulary`; binary mono 16 kHz s16le audio. Unknown/retired parameters fail closed.
4. The Mac sends a frozen local session snapshot. Mid-session Settings changes affect the next connection/reconnect policy defined by S-10, never mutate server state.
5. Each finalized cloud utterance delivered to the Mac has a required stable UUID and one nonnegative numeric speaker ID. Invalid/missing provider identity is handled at the adapter boundary, never by optional ID/order/speaker-time fallback in the Mac.
6. Provider speaker numbering is normalized once. Modulate's documented 1-indexed speaker becomes the integrated S-10 zero-based numeric domain (`providerSpeaker - 1`); if S-10 integrated a different explicit numeric base, stop and align one boundary rather than double-convert.
7. Local and cloud segments enter the same S-10 normalizer and store transaction. Same-speaker joining, cross-speaker repair, punctuation, label lookup, timestamps, and model formatting run once locally, not in Python.
8. Translation is keyed by `segmentId`, target validated from the frozen session, and committed only to the matching authorized local row. Missing/stale segment, owner change, or old generation rejects the result. Translation failure preserves original text and does not close STT.
9. Modulate vocabulary is actually sent as upstream `custom_terms`; it is bounded/deduplicated before connect. There is no accepted-but-unused vocabulary field.
10. Server-configured VAD remains active/fail-open exactly as tested. The client cannot select enabled/disabled/shadow. The unrelated Mac Local VAD setting is not renamed or deleted here.
11. Ready means the managed STT socket is usable. `stt_failed` is terminal and visible. Disconnect/cancel is not reported as successful transcription. Retained freemium/subscription truth remains structured.
12. Heartbeat, receiver, provider, translation, and usage tasks drain/cancel without leaking a session, writing product data, or turning teardown into a finalization request.
13. Mic plus System Audio is mixed to one mono stream before cloud delivery. Special server multichannel phone semantics are absent.
14. Only `/v4/listen` remains. `/v4/web/listen` cannot authenticate or connect and no first-message auth parser remains.
15. Local Parakeet works without the Python listen service. Managed listen works without NLLB, Pusher, People, speech profiles, or a Firestore conversation. Both persist the same local shape after S-10.
16. System Audio modes, meeting boundaries, Stop, Finish-and-Continue, four-hour rotation, local crash recovery, Name Speaker, and native onboarding preserve their assigned visible behavior.
17. No raw transcript/audio/People identity is added to logs, metrics, parity artifacts, or failure telemetry. Coarse platform/provider/model/outcome and bounded usage remain acceptable.
18. Removing listen headers is scoped: `X-Device-Id-Hash`/`X-App-Version` may remain on independently retained HTTP endpoints. A global transport deletion would violate IR-404's listen-only boundary.
19. NLLB removal preserves translation splitting, batching and output cardinality, target/detected-language rules, empty validation, dedup/cache, failure isolation, metrics, and original-on-failure behavior under Gemini.
20. No deprecated alias, compatibility facade, one-item provider list, ignored query, fake-success event, empty implementation, or dual-write survives final GREEN.

## 10. Target authority and ownership model

### 10.1 Authority boundary

```text
Mac recording owner (S-10)
  capture boundary + local conversationId
  immutable language/auto/translation/vocabulary snapshot
  mic + System Audio -> mono 16 kHz s16le
  local Parakeet -------------------------------+
                                                  |
  managed fallback -> authenticated /v4/listen  | transient compute only
                       -> server VAD             |
                       -> Modulate               |
                       -> optional Gemini translate
                       -> segmentId/speakerId/text/time/translation
                                                  v
  one S-10 local normalizer -> one GRDB transaction -> UI/models/finalization

Forbidden server arrows:
  -> Firestore conversation/transcript/People/preferences
  -> Redis in-progress conversation
  -> Pusher conversation/finalizer/audio archive
  -> Cloud Task finalization
  -> local/cloud identity reconciliation
```

The backend retains an account-scoped admission/usage boundary, not a product-data authority. `uid` is used to authenticate, check entitlement/fair use, and meter managed compute; it is not a conversation owner key.

### 10.2 Final public listen contract

The implementation should introduce one typed `ListenSessionConfig` **(new exact name may change before code lands)** at route admission:

- `language`: normalized supported BCP-47/ISO hint or the existing explicit auto sentinel resolved to no Modulate language hint;
- `translationTarget`: optional validated language target; nil means no translation;
- `vocabulary`: repeated query values, order-preserving dedup, current product maximum 100 unless a separately reviewed UI requirement changes it, also bounded by Modulate's documented 1,000/8,000-character ceiling;
- fixed transport: 16,000 Hz, mono, signed 16-bit little-endian PCM, not client-selectable;
- headers: Firebase Authorization and `X-App-Platform: macos`; no stable device/app-version listen identity.

After auth, unknown query keys or retired keys close with a policy/unsupported-contract code and a bounded reason. Do not silently ignore them. The backend sends Modulate's first JSON config frame before audio with the validated language and nonempty `custom_terms`, then sends binary audio. If vocabulary cannot be forwarded, reject the session truthfully rather than pretend it is active.

### 10.3 Final outbound segment/events

Use a small typed payload rather than `TranscriptSegment`'s hosted conversation model:

```json
{
  "type": "segments",
  "segments": [
    {
      "segmentId": "uuid",
      "speakerId": 0,
      "text": "...",
      "start": 1.25,
      "end": 2.75
    }
  ]
}
```

Translation is a typed update keyed by the same `segmentId`, with target language and translated text; it never repeats or replaces conversation state. Whether segments remain an envelope or use the current top-level array is decided by the integrated S-10 public parser test before Cycle 1; there must be one form at closure, not both. The allowed nonsegment events are `ready`, `stt_failed`, the retained freemium/subscription signal, and heartbeat text if the existing transport still needs it.

Modulate `utterance_uuid` is the preferred finalized segment UUID after validation. Any synthetic flush of a final partial receives one UUID once at the adapter boundary. Re-emission of the same provider utterance keeps the same UUID. The adapter converts documented 1-indexed speakers to the local numeric domain and emits no `speaker`, `person_id`, `is_user`, `stt_provider`, `speech_profile_processed`, or conversation ID. `isUser` is local routing/label state owned by S-10, not provider identity supplied by this socket.

### 10.4 Translation owner

Gemini 2.5 Flash-Lite remains the sole translation executor behind the current validated coordinator/engine. The coordinator may retain bounded cache/dedup/metrics but receives no conversation ID and writes no Firestore. It emits a result callback containing only session generation, segment ID, source/detected language, target language, and translated text. The Mac validates owner/conversation generation and commits locally.

### 10.5 Deletion ownership

S-16 deletes code exclusively supporting server-owned listen conversations and NLLB. It disconnects shared systems but leaves their broader deletion to owners:

- remove listen's Pusher calls; S-25 deletes the deployed Pusher/backend-listen/finalizer topology;
- remove listen's People/speech-profile calls; S-23 deletes the broader hosted identity/data product;
- remove NLLB repository declarations under IR-726; separate operational authorization removes deployed NLLB resources;
- remove cloud transcription preferences after S-10; preserve unrelated general user language/account data with live callers.

## 11. Ordered TDD cycles

Run one cycle at a time. Write the RED first, confirm the intended failure, implement only the minimum GREEN, refactor while green, and do not begin the next cycle while the current focused suite is red.

### Cycle 1 — One transient `/v4/listen` spine with zero conversation side effects

- **Behavioral RED:** Add `test_listen_transient_contract.py` **(new)** through the real FastAPI WebSocket route with normal auth, a controllable Modulate socket, and strict spies at Firestore/Redis/Pusher/Cloud Task/object-storage boundaries. Send valid PCM and assert `ready` then a transcript; disconnect/reconnect and assert no conversation/session ID event and zero product-data calls/writes/finalization. Add provider-init failure asserting `stt_failed`, no `ready`, no fake transcript, and zero writes.
- **Why RED now:** the route generates recording/client session IDs, reads/reuses/creates Firestore conversations, writes transcript arrays, touches Redis/Pusher/finalization, and emits lifecycle state.
- **Minimum GREEN:** replace `ListenSessionRuntime`'s conversation-owned composition with one transient receiver/delivery loop; retain account admission, heartbeat, task supervision, usage, provider observability, and truthful failure. Delete `LiveConversationController` and remove current-conversation/Pusher/finalization teardown calls when no caller remains. The new normal route is the only production path immediately—no feature flag or fallback runtime.
- **Retained behavior:** Firebase listen auth, managed Modulate startup, audio receipt, heartbeat, reconnect at the Mac, STT death monitoring, usage/fair-use accounting, structured subscription signal.
- **Expected code:** `backend/routers/transcribe.py`, `routers/listen/{contracts,runtime,receiver,transcripts,persistence}.py`; delete `routers/listen/conversations.py`; remove listen-only imports/callbacks from `utils/listen_pusher_session.py` only after global caller proof. `AppState+ListenEvents.swift` changes only if integrated S-10 still expects a server lifecycle event.
- **Expected tests/contracts/docs:** new transient route test; rewrite `test_listen_runtime_regressions.py`, `test_listen_persistence.py`, `test_transcribe_teardown_flush.py`, `test_listen_process_pending_shutdown.py`, relevant E2E helpers; remove tests whose only assertion is Firestore conversation ownership. Update no broad docs yet beyond an adjacent contract comment needed to keep code truthful.
- **Focused verification:** `cd backend && pytest -q tests/unit/test_listen_transient_contract.py tests/unit/test_listen_runtime_regressions.py tests/unit/test_listen_stt_death_monitor.py tests/unit/test_listen_persistence.py`.
- **Deletion/simplification unlocked:** server IDs, lifecycle poll, pending/stale conversation recovery, last-conversation emission, teardown finalization, listen Pusher binding, conversation-specific state/limits.
- **Stop condition:** integrated S-10 still consumes any server conversation/lifecycle event; entitlement cannot be separated from a conversation write; or a real retained non-listen caller of `LiveConversationController` is found.

### Cycle 2 — Fixed PCM, exact admission allowlist, coarse platform, and server-owned VAD

- **Behavioral RED:** Through `/v4/listen`, prove valid binary mono 16 kHz s16le reaches the fake Modulate socket byte-for-byte; each retired/unknown query (`sample_rate`, `codec`, `channels`, `source`, `vad_gate`, `include_speech_profile`, `conversation_timeout`, `speaker_auto_assign`, device/provider fields) fails closed; client text control/audio-format frames are rejected; the backend VAD active path gates speech, and an injected VAD failure records the existing fallback then passes audio through. In Swift, assert conversation mode sends only the allowed session query plus Authorization/`X-App-Platform`, never device hash/app version, while PTT requests remain unchanged.
- **Why RED now:** FastAPI accepts many old fields, defaults to 8 kHz PCM8, decoders/multichannel/control frames remain, client VAD override is honored, and the Mac sends rejected fields/headers.
- **Minimum GREEN:** parse request query keys against an allowlist; hard-code transport constants in the listen domain; remove decoder/multichannel/control setup and `ClientDeviceContext` from listen; derive coarse platform/admission source without stable identity; preserve existing server VAD construction/fail-open helper. Adapt only `TranscriptionService.StreamingMode.conversation`.
- **Retained behavior:** Mac mic/System Audio mono mix; fixed 100 ms buffering; watchdog/reconnect; VAD metrics/fail-open; PTT codecs/routes and stable headers on unrelated HTTP endpoints.
- **Expected code:** `transcribe.py`, `listen/contracts.py`, `listen/receiver.py`, `listen/runtime.py`, `utils/transcribe_decisions.py`, `utils/listen_audio.py`/`audio.py` only after caller audit, `TranscriptionService.swift`.
- **Expected tests/contracts/docs:** new route admission cases in the Cycle 1 test; adapt `test_validate_audio_format.py`, `test_optional_audio_codecs.py`, `test_listen_receiver_opus_frame_capacity.py`, `test_listen_multichannel_mix_buffer_leak.py`, `test_vad_gate.py`, `ListenProtocolTests.swift`, `VoiceTurnDomainTests/TranscriptionTransportTests.swift`. Delete only listen-specific codec tests; retain PTT tests.
- **Focused verification:** `cd backend && pytest -q tests/unit/test_listen_transient_contract.py tests/unit/test_vad_gate.py tests/unit/test_listen_receiver_frame_recovery.py tests/unit/test_ws_auth_handshake.py`; `cd desktop/macos && ./scripts/dev-feedback.py --once swift 'ListenProtocolTests|TranscriptionTransportTests|SystemAudioConverterFormatTests'`.
- **Deletion/simplification unlocked:** `CustomSttMode` audio branches, codec normalizers/decoders with no other caller, channel configs/tails, listen device parser/fields, VAD override helpers, variable-format comments/tests.
- **Stop condition:** Mac output is not actually mono 16 kHz s16le after S-10; a shared helper is required by PTT/other endpoints; or server VAD cannot fail open under a controllable test.

### Cycle 3 — Immutable local language/translation/vocabulary session config

- **Behavioral RED:** Start two authenticated sessions for the same test user while Firestore holds contradictory transcription preferences. Assert the requested local snapshot alone chooses Modulate language/auto mode, translation target, and ordered vocabulary; change local settings during session one and prove its upstream config does not change, while session two uses the new snapshot. Capture the fake Modulate first frame and assert exact nonempty `custom_terms`; invalid/oversized terms fail before audio. Assert the backend performs no transcription-preference/profile read/write.
- **Why RED now:** bootstrap reads Firestore preferences/language, derives single-language/translation server-side, stamps custom usage, and the Modulate adapter ignores loaded vocabulary.
- **Minimum GREEN:** add the narrow typed session fields and validation; map auto to no upstream language hint; send Modulate's documented first config frame before audio; reduce `listen_session_bootstrap.py` to user/credits/fair-use state; remove Mac preference API calls left after S-10; delete transcription-preference routes/database projection/cache/custom stamp after global zero-caller proof; remove only the transcription side effect from the general language route.
- **Retained behavior:** local language and automatic detection UI, ordered vocabulary with `Omi` behavior established by S-10, unsupported-language truth, entitlement/fair use, general language/account behavior with other callers.
- **Expected code:** backend `transcribe.py`, listen contracts/runtime, `utils/listen_session_bootstrap.py`, `utils/stt/streaming.py`, language decisions, `routers/users.py`, `database/users.py`; Mac `TranscriptionService.swift` and any remaining `APIClient+Settings.swift`/Settings/onboarding/automation preference calls; generated client only after route deletion.
- **Expected tests/contracts/docs:** new upstream config test in `test_listen_transient_contract.py`; rewrite `test_listen_session_bootstrap.py`, `test_transcribe_decisions.py`, `test_users.py`, Mac settings/listen tests; regenerate app-client DTOs and update route-policy/OpenAPI generator tests. Cite Modulate's AsyncAPI in the implementation PR as the external wire source.
- **Focused verification:** `cd backend && pytest -q tests/unit/test_listen_transient_contract.py tests/unit/test_listen_session_bootstrap.py tests/unit/test_transcribe_decisions.py tests/routers/test_users.py tests/unit/test_openapi_contract.py`; `cd desktop/macos && ./scripts/dev-feedback.py --once swift 'ListenProtocolTests|AssistantSettingsLanguageTests|AssistantSettingsVocabularyTests|SettingsResponseTests'`.
- **Deletion/simplification unlocked:** backend transcription preferences, sync/cache/custom usage stamp, `uses_custom_stt` fields, server preference merge, unused generated DTOs/methods, list-to-session ambiguity.
- **Stop condition:** official/commercial Modulate streaming cannot accept `custom_terms`; integrated S-10 lacks a complete immutable local snapshot; another retained product caller still requires the preference route; or vocabulary would be accepted but not consumed.

### Cycle 4 — Required UUID/numeric transient segments into one local ingestion path

- **Behavioral RED:** Feed the fake Modulate adapter a finalized utterance with documented UUID/speaker/timing and assert the real route emits one required stable `segmentId`, zero-based numeric `speakerId`, text/start/end and no hosted fields. Re-emit the utterance and prove stable identity. Feed equivalent local Parakeet and cloud batches through S-10's public ingestion seam and assert identical durable rows, idempotent upsert, one normalization pass, same-speaker join/boundary/punctuation parity, local label/formatter/timestamp behavior, and no server `segments_deleted` dependency.
- **Why RED now:** the adapter discards `utterance_uuid`, formats `SPEAKER_N`, hosted models carry duplicate/optional IDs/person/provider fields, Python normalizes/persists, and Mac decoding accepts aliases/fallbacks.
- **Minimum GREEN:** introduce a narrow transient segment DTO at the adapter/route; validate/preserve provider UUID, generate once only for an unavoidable final partial, convert speaker once, emit typed fields, and pass directly into S-10's local ingestion. Remove server combine/boundary/punctuation and hosted `TranscriptSegment` use from listen; narrow Mac decoding to required fields.
- **Retained behavior:** generic diarization, stable live updates, local translation attachment, local/cloud equivalence, S-10 joining/repair/punctuation/labels/formatter/auth name/timestamps.
- **Expected code:** `utils/stt/streaming.py`, `listen/transcripts.py` or its replacement, `listen/runtime.py`, shared segment models only where caller audit permits; Mac `TranscriptionService.swift`, `AppState+ListenEvents.swift`; no S-10 schema rewrite.
- **Expected tests/contracts/docs:** new adapter unit cases plus route/Swift decode cases; adapt `test_transcript_segment.py`, `test_transcribe_conversation_cache.py`, `test_transcribe_speaker_id_queue_pii.py`, `ListenProtocolTests.swift`; run integrated S-10 ingestion/formatter tests. Static golden vectors remain parity tripwires, not the behavioral RED.
- **Focused verification:** `cd backend && pytest -q tests/unit/test_listen_transient_contract.py tests/unit/test_stt_provider_policy.py tests/unit/test_transcript_segment.py`; `cd desktop/macos && ./scripts/dev-feedback.py --once swift 'ListenProtocolTests|ConversationIngestionTests|LocalTranscriptFormatterTests|TranscriptSpeakerAssignmentTests'`.
- **Deletion/simplification unlocked:** provider speaker strings, optional/alias ID parsing, `person_id`/provider/speech-profile listen fields, server `ConversationCache`, server normalization and segment-deletion event path.
- **Stop condition:** S-10's integrated canonical numeric base is undefined/inconsistent; a provider event lacks stable identity without a deterministic one-time boundary; or local/cloud inputs still require different durable shapes.

### Cycle 5 — Direct local-authority translation and Gemini-only NLLB removal

- **Behavioral RED:** With a requested target, stream a segment and assert Gemini translation is emitted once keyed by `segmentId`, the Mac commits it only to that local row, and no Firestore/Redis conversation write occurs. Cover unsupported/empty target, split/batch cardinality, dedup/cache hit, provider error/timeout/partial mismatch, stale local generation, and original transcript retention. Add runtime/deployment contract tests asserting Gemini works with no NLLB URL/list and no NLLB image/workflow/chart registration.
- **Why RED now:** translation target comes from cloud preferences, callbacks persist Firestore transcripts before delivery, provider policy supports NLLB/list/legacy Google aliases, and the NLLB service/control plane is registered.
- **Minimum GREEN:** make translation coordinator conversation-free and callback-only; preserve validated planner/cache/metrics/failure behavior; select Gemini 2.5 Flash-Lite explicitly; delete NLLB provider/config/service/chart/workflow/image/env/check/script/test/doc residue; remove backend-listen NLLB env values. Do not replace the provider list with a one-element list.
- **Retained behavior:** transient live translation only for cloud STT, direct local SQLite output, language detection/target validation, splitting/batching/cardinality, empty validation, dedup/cache, metrics, failure isolation, original transcript on failure; no local-Parakeet upload for translation.
- **Expected code:** `listen/transcripts.py`/replacement, `translation_coordinator.py`, `translation.py`, `translation_cache.py`, `translation_core/**`, `config/translation.py`; delete NLLB directories/workflow/scripts; adapt runtime env/images/charts/checks/workflow contracts; Mac local translation handler.
- **Expected tests/contracts/docs:** rewrite translation unit tests and `test_listen_features_e2e.py`; delete NLLB service/provider tests; adapt runtime-image/env/backend-listen Helm/concurrency/check-manifest tests; update `backend/AGENTS.md` service map and translation docs truthfully.
- **Focused verification:** `cd backend && pytest -q tests/unit/test_listen_transient_contract.py tests/unit/test_translation_optimization.py tests/unit/test_translation_cost_optimization.py tests/unit/test_translation_dedup_edge_cases.py tests/unit/test_translation_negative_cache_detection.py tests/unit/test_runtime_image_contracts.py tests/unit/test_backend_runtime_env_validator.py tests/unit/test_backend_listen_helm_defaults.py`; `make runtime-image-source-closure`; Swift S-10 ingestion/listen tests.
- **Deletion/simplification unlocked:** Firestore translation persistence guard, NLLB provider/URL/list/alias, NLLB metrics/alerts/image/release/docs, translation `conversation_id` arguments, one-provider abstraction branches with no remaining value.
- **Stop condition:** retained Gemini implementation cannot prove cardinality/original-on-failure; cache requires a durable conversation ID; a non-S-16 live caller of NLLB is found; or deleting repository deployment declarations would break a still-authorized deployment lane without an owner decision.

### Cycle 6 — Delete alternate listen entrances, modes, identity, and lifecycle statuses

- **Behavioral RED:** Assert `/v4/web/listen` has no route; first-message auth cannot enter listen; every rejected legacy query/control input fails closed; custom suggested transcripts cannot be injected; no onboarding/call/multichannel/provider/client-conversation/device fields exist; only ready/failure/subscription/heartbeat events decode. Retain a normal invalid-token `/v4/listen` rejection test through upgrade auth.
- **Why RED now:** the web route/facade, custom/onboarding/call/client-ID fields, text controls, lifecycle/status models, tests, route-policy rows, and compatibility comments remain executable.
- **Minimum GREEN:** delete `/v4/web/listen` and `_stream_handler`; delete rejected request/state/control/event models and handlers; remove custom usage and lifecycle status emitters; update route policy, test helpers, fixture URLs, E2E docs, and generated/hand-written Mac parser. Remove exclusive code rather than leave empty handlers.
- **Retained behavior:** normal auth, native Mac onboarding, local conversation generation fencing, ready/stt_failed/freemium truth, heartbeat/reconnect, PTT endpoints.
- **Expected code:** `transcribe.py`, listen contracts/runtime/receiver, `models/message_event.py`, auth/device utilities only if exclusive, Mac listener parser; route-policy and testing helpers/docs.
- **Expected tests/contracts/docs:** replace `test_ws_auth_handshake.py` source scrapes with behavioral route/auth tests; rewrite/delete `/v4/web/listen` E2E suites and custom/multichannel lifecycle fixtures; update route-policy/non-active/openapi checks as applicable.
- **Focused verification:** `cd backend && pytest -q tests/unit/test_listen_transient_contract.py tests/unit/test_ws_auth_handshake.py tests/unit/test_route_policy_inventory.py tests/unit/test_openapi_contract.py testing/e2e/test_listen_stt.py`; `cd desktop/macos && ./scripts/dev-feedback.py --once swift 'ListenProtocolTests|LiveTranscriptionFailureStateTests|TranscriptionConnectionStateTests'`.
- **Deletion/simplification unlocked:** historical route facade, first-message auth/device parser, synthetic custom/onboarding fixtures, event aliases/status text, compatibility-only query parsing and route documentation.
- **Stop condition:** a non-test in-tree caller of web/custom/onboarding/call/multichannel remains; external route owner has not authorized live removal (repository removal may be prepared but not deployed); or normal upgrade auth cannot be exercised hermetically.

### Cycle 7 — Remove listen persistent speaker identity while preserving local naming

- **Behavioral RED:** Through the real transient route, stream multiple Modulate speakers and assert numeric diarization arrives without speech-profile/People reads, ring-buffer embedding, speaker-sample/Pusher request, suggestion event, person ID, or automatic match. Through S-10's public local label seam, label one speaker `You` and another custom name; assert existing/future segments update locally, survive finalization/restart, remain conversation-local, and never issue a People request.
- **Why RED now:** runtime loads private-cloud/speech-profile state, `SpeakerMatcher` reads People/embeddings and emits suggestions, transcript processing invokes matching, and baseline Mac UI uses a People map.
- **Minimum GREEN:** remove `SpeakerMatcher`, listen ring-buffer/sample queues/profile/bootstrap branches/suggestion event; delete `routers/listen/speakers.py` if exclusive; remove listen imports of People/speech-profile/Pusher speaker helpers. Consume S-10 local naming unchanged.
- **Retained behavior:** Modulate generic diarization, numeric speaker grouping, local live Name Speaker preview/Save/Cancel, `You`/Add Name, persistence for the current conversation, local formatter labels.
- **Expected code:** listen runtime/receiver/transcript/contracts and exclusive speaker event models/tests; no broad People route/storage deletion. Mac changes only if a stale suggestion handler survived S-10.
- **Expected tests/contracts/docs:** rewrite `test_transcribe_speaker_id_queue_pii.py`, `test_speaker_person_embedding_recovery.py`, speaker integration/e2e cases; run S-10 Name Speaker/storage/formatter tests; update service map only for the removed listen-to-diarizer/People edge.
- **Focused verification:** `cd backend && pytest -q tests/unit/test_listen_transient_contract.py tests/unit/test_transcribe_speaker_id_queue_pii.py tests/unit/test_vad_gate.py`; `cd desktop/macos && ./scripts/dev-feedback.py --once swift 'TranscriptSpeakerAssignmentTests|ConversationIngestionTests|LocalTranscriptFormatterTests|ListenProtocolTests'`.
- **Deletion/simplification unlocked:** speech-profile/private-cloud bootstrap for listen, audio ring buffer, speaker match task/queues/events, People/person map fields, embedding recovery paths exclusive to listen.
- **Stop condition:** S-10 local labels are not integrated/persistent; generic diarization depends on persistent embedding rather than Modulate speaker numbers; or a shared speaker helper has another retained caller.

### Cycle 8 — Integrated retained-path proof, contracts/docs, and repository closure

- **Behavioral RED:** Add/finish an integrated hermetic journey that runs (a) local Parakeet and (b) managed fake-Modulate fallback into the same owner-local store, then asserts equal durable shape, local meeting/Stop/Finish-and-Continue/four-hour boundaries, reconnect generation fencing, ready/failure truth, translation, restart, owner switch, exact System Audio modes/default/shortcut behavior, and no Python product-data dependency. Add route/deployment executable contracts showing only `/v4/listen` remains and NLLB/server-conversation registrations are absent.
- **Why RED now:** earlier focused GREENs do not by themselves prove both provider paths, local lifecycle, contract generation, docs, and full residue closure together; current broad tests/docs still describe the hosted pipeline.
- **Minimum GREEN:** migrate final callers; regenerate app-client output; remove exclusive tests/fixtures/scripts/check registrations/metrics/alerts/config/secrets references/docs; update `PRODUCT.md`, root/component guides, `FORK.md`, E2E/runbook docs, and changelog for the user-visible change. Keep explicit later-slice allowlists, not hidden residue.
- **Retained behavior:** every invariant in Section 9, especially Apple Silicon local independence, Intel/fallback managed STT, capture modes/boundaries, local durability, owner isolation, PTT adjacency, billing truth.
- **Expected code:** any final file in Section 7 with a proven caller; no new architecture. Generated `OmiApi.generated.swift` only from the repository generator.
- **Expected tests/contracts/docs:** integrated backend/desktop journey **(new name chosen with S-10 tests)**; route-policy/OpenAPI/runtime-image/workflow/check-manifest tests; all affected docs and service maps.
- **Focused verification:** all Section 13 searches and Section 14 focused/component commands, followed by Section 15 named-bundle acceptance.
- **Deletion/simplification unlocked:** remaining compatibility comments/types, unused imports/dependencies, exclusive fixtures and docs, temporary implementation scaffolding. Refactor only while all prior cycles are green.
- **Stop condition:** any non-Windows in-tree caller/residue is unexplained; a retained adjacent path regresses; generated/route/deploy contracts are stale; real capture cannot be exercised; or closure would take S-20/S-22/S-23/S-25 work.

## 12. Cross-slice ownership and handoffs

| Slice | S-16 consumes/provides | S-16 must not absorb |
|---|---|---|
| S-02 | Consume owner-scoped GRDB/generation authorization. | New database/owner identity or shared fallback. |
| S-03 | Consume fixed managed Modulate and retained Mac-local Parakeet; protect their provider boundary. | Recreate provider selection, hosted Parakeet, Deepgram, or S-03 control-plane deletion. |
| S-10 | Consume sole local conversation writer, stable IDs, numeric speakers, common normalizer/formatter, local labels/preferences/finalization. Provide final transient `/v4/listen` DTO/events and zero-cloud-authority proof. | Local conversation schema/migration/UI/search/merge/enrichment/finalization redesign. |
| S-14 | Rebase over its removal of personalized credit-limit notification calls from listen; preserve structured freemium truth. | Notification product/job/settings deletion. |
| S-19 | Provide local authoritative transcripts unaffected by listen server ownership. | Local agent tools or PTT tool surface. |
| S-20 | Preserve current account/fair-use admission and usage seams with no product-data writes; hand off a smaller transient runtime. | Fair-use policy/private evidence redesign. |
| S-22 | Provide Gemini-only translation and fixed Modulate transport; consume its later explicit managed-model policy if integrated. | Broader model/profile/gateway policy or conversation enrichment compute. |
| S-23 | Remove listen callers of People/speech profile/audio identity and identify remaining service/storage callers. | Whole People APIs, profile training/storage, account product-data deletion, live data wipe. |
| S-25 | Remove listen-to-Pusher/conversation-finalizer dependencies and NLLB repository declaration; provide deployment inventory. | Live or repository-wide Pusher/diarizer/backend-listen/finalizer teardown beyond S-16's exclusive caller, unless S-25 is integrated and explicitly hands it back. |
| S-26 | Provide a canonical backend with a narrow retained listen route and truthful service map. | Canonical backend-wide restructuring. |

Shared-file conflict hot spots are `backend/routers/listen/runtime.py`, `backend/AGENTS.md`, `PRODUCT.md`, `FORK.md`, runtime env/image/check manifests, Mac `TranscriptionService.swift`, `AppState+ListenEvents.swift`, Settings API code, and generated Swift. Sequence/rebase and resolve semantically; do not copy another untracked plan's edits or combine unrelated slice commits.

## 13. Repository residue-search strategy

Run before the first RED to refresh the inventory, after each deletion cycle, and at final closure. Hits are classified as retained caller, historical record, later-slice handoff, generated stale output, or defect. Do not declare clean by excluding inconvenient directories.

### Server conversation/session ownership

```bash
rg -n 'LiveConversationController|current_conversation_id|recording_session_id|client_conversation_id|conversation_session|conversation_timeout|in_progress_conversation|last_memory|memory_processing|memory_created|request_conversation_processing' \
  backend desktop/macos .github scripts --hidden --glob '!.git/**'

rg -n 'ListenPusherSession|HOSTED_PUSHER_API_URL|pusher_(close|receive|heartbeat)|process_conversation|conversation-finalization' \
  backend/routers/listen backend/utils backend/tests backend/testing
```

Expected final S-16 result: no listen production/test dependency on conversation IDs, Firestore transcript persistence, Pusher, or finalization. Shared Pusher/finalizer terms outside listen are explicitly handed to S-25.

### Rejected listen protocol and events

```bash
rg -n '/v4/web/listen|_stream_handler|custom_stt|suggested_transcript|include_speech_profile|speaker_auto_assign|create_speakers|vad_gate|call_id|onboarding|channels|pcm8|opus|aac|lc3|stt_provider' \
  backend/routers/transcribe.py backend/routers/listen backend/testing/e2e backend/tests desktop/macos/Desktop/Sources/TranscriptionService.swift desktop/macos/Desktop/Tests

rg -n 'initiating|stt_initiating|in_progress_conversations_processing|segments_deleted|speaker_label|auth_response|service_status' \
  backend/routers/listen backend/models/message_event.py backend/tests backend/testing/e2e desktop/macos/Desktop/Sources/AppState desktop/macos/Desktop/Tests
```

Final allowed hits are separately retained PTT/general codec code and explicit `ready`/`stt_failed`/subscription behavior, not listen compatibility.

### Speaker/People and stable identity

```bash
rg -n 'SpeakerMatcher|speech_profile|person_id|SpeakerLabelSuggestion|speaker_map|speakerLabel|SPEAKER_[0-9]|backendSegmentId|backendId' \
  backend/routers/listen backend/utils/stt backend/tests desktop/macos/Desktop/Sources/AppState desktop/macos/Desktop/Sources/TranscriptionService.swift desktop/macos/Desktop/Tests

rg -n 'X-Device-Id-Hash|X-App-Version|ClientDeviceContext|resolve_client_device' \
  backend/routers/transcribe.py backend/routers/listen desktop/macos/Desktop/Sources/TranscriptionService.swift desktop/macos/Desktop/Tests/ListenProtocolTests.swift
```

Do not require these headers/People terms to vanish from unrelated retained endpoints or historical changelog.

### Preferences and transient wire

```bash
rg -n '/v1/users/transcription-preferences|getTranscriptionPreferences|updateTranscriptionPreferences|get_user_transcription_preferences|set_user_transcription_preferences|set_user_custom_stt_usage|uses_custom_stt|custom_stt_since' \
  backend desktop/macos .github --hidden --glob '!.git/**'

rg -n 'segmentId|speakerId|translation_target|vocabulary|custom_terms|X-App-Platform|/v4/listen' \
  backend/routers backend/utils/stt desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests backend/tests
```

The second search proves positive ownership as well as deletion. A residue scan that only searches rejected names is incomplete.

### NLLB and managed provider closure

```bash
rg --hidden -n 'nllb|NLLB|HOSTED_TRANSLATION_API_URL|TRANSLATION_SERVICE_MODELS|gcp_nllb_translation' \
  . --glob '!.git/**' --glob '!bootstrap-scaffold/**'

rg --hidden -n 'deepgram|Deepgram|HOSTED_STT|STT_SERVICE_MODELS|hosted.*parakeet|parakeet.*host|stt_service' \
  backend desktop/macos .github --glob '!.git/**'
```

Final NLLB production/config/test/doc hits are zero outside historical roadmap/requirements material. Deepgram/history/general People BYOK hits are classified by owner; no S-16 managed listen branch may remain.

### Control-plane, generated, and documentation closure

```bash
git ls-files | rg 'nllb|listen|transcri|translation|pusher|speaker|route_policy|openapi|runtime_image|workflow_contract'

rg --hidden -n '/v4/listen|/v4/web/listen|nllb-translation|server conversation|conversation lifecycle|transcription preferences' \
  AGENTS.md PRODUCT.md FORK.md backend desktop/macos .github scripts --glob '!.git/**'

git diff --check
git status --short
```

Historical requirements/Wave plans and changelog entries may truthfully describe the old system. Current guides/runbooks/service maps may not.

## 14. Focused and component-level verification commands

These are future execution commands, not claims that product behavior passed while planning.

### Focused Python loop

```bash
cd backend
bash test-preflight.sh
pytest -q tests/unit/test_listen_transient_contract.py
pytest -q \
  tests/unit/test_listen_runtime_regressions.py \
  tests/unit/test_listen_stt_death_monitor.py \
  tests/unit/test_listen_receiver_frame_recovery.py \
  tests/unit/test_vad_gate.py \
  tests/unit/test_listen_session_bootstrap.py
pytest -q \
  tests/unit/test_translation_optimization.py \
  tests/unit/test_translation_cost_optimization.py \
  tests/unit/test_translation_dedup_edge_cases.py \
  tests/unit/test_translation_negative_cache_detection.py
pytest -q \
  tests/unit/test_ws_auth_handshake.py \
  tests/unit/test_route_policy_inventory.py \
  tests/unit/test_openapi_contract.py \
  tests/unit/test_runtime_image_contracts.py \
  tests/unit/test_backend_runtime_env_validator.py \
  tests/unit/test_backend_listen_helm_defaults.py
```

Use the repository's selector once files exist rather than inventing a second test runner:

```bash
cd backend
bash test.sh
```

Tests needing real Firebase/Redis/Modulate remain in `backend/tests/integration/`, outside CI. Run only with authorized development credentials and record exact evidence; never turn live-service tests into nominal CI success.

### Focused Swift loop

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'ListenProtocolTests|LiveTranscriptionFailureStateTests|TranscriptionConnectionStateTests|TranscriptionTransportTests'
./scripts/dev-feedback.py --once swift 'ConversationIngestionTests|LocalTranscriptFormatterTests|TranscriptSpeakerAssignmentTests'
./scripts/dev-feedback.py --once swift 'MeetingGatedSystemAudioTests|SystemAudioConverterFormatTests|TranscriptionFinalizationStateMachineTests|TranscriptionStorageRecoveryTests'
xcrun swift build -c debug --package-path Desktop
```

Replace planned S-10 test names with their actual integrated names. Do not create duplicate suites solely to satisfy this plan.

### Generated/client/route/deployment contracts

```bash
cd backend
./scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
cd ..
make runtime-image-source-closure
python3 .github/scripts/check-deployment-concurrency.py
python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-workflows
python3 backend/scripts/validate-backend-runtime-env.py --env prod
python3 backend/scripts/validate_rendered_deployment_contract.py
python3 bootstrap-scaffold/validate-requirements-ledger.py
```

If the generator's current CLI differs after rebase, use its checked-in `--help`/AGENTS guidance; do not claim the literal placeholder command passed until verified.

### Component and repository acceptance

```bash
cd backend && bash test.sh
cd ../desktop/macos && ./test.sh
cd ../..
scripts/pr-preflight --suggest
make preflight
git diff --check
git status --short
```

Before a future `fix:` commit/PR, follow the root failure-class and PR-body preflight requirements. This planning task does not commit or publish anything.

## 15. Real named-bundle and user-path acceptance

After all hermetic/component gates pass, build and run only an isolated development bundle; never stop, replace, or restart `/Applications/Omi.app` or `Omi Beta.app`:

```bash
cd desktop/macos
OMI_APP_NAME="omi-s16-transient-listen" ./run.sh --full
./scripts/omi-ctl health
./scripts/omi-ctl log-path
agent-swift connect --bundle-id com.omi.omi-s16-transient-listen
```

Use an authorized development backend and test account. Capture logs from the named bundle and its worktree backend. Acceptance must exercise, not merely compile:

1. **Apple Silicon local path:** record speech with local Parakeet, see live transcript, Stop, reopen after app restart, and verify local transcript/finalization without `/v4/listen` or Python availability.
2. **Managed path:** force the supported test seam for cloud STT (and exercise Intel on available hardware if possible), record mic-only and mic+System Audio, see `ready`, transcript, diarized speakers, optional translation, Stop, restart, and verify the same local GRDB/UI shape with no server conversation ID.
3. **Fallback:** inject local-model failure and confirm managed STT takes over truthfully; inject managed failure and confirm visible `stt_failed`/retained local capture rather than fake success or data loss.
4. **Reconnect:** interrupt only the development backend/provider connection, let watchdog/reconnect occur, continue the same local recording, and prove no duplicate segment/cross-generation write or new server conversation.
5. **Boundaries:** exercise meeting start/end, manual Stop, Finish-and-Continue, and an accelerated/testable four-hour rotation seam; each boundary is local and survives provider disconnect.
6. **System Audio modes:** verify exact default Only During Meetings; header shortcut alternates only Only During Meetings/Always; Always records System Audio outside meetings; Never excludes System Audio while microphone transcription continues.
7. **Speaker labels:** label current speaker as You/custom name, verify existing/future segments and completed/restarted conversation, and confirm no People/network request.
8. **Translation:** select auto-detect plus target/vocabulary locally; confirm upstream config in development logs without raw terms, local translation attachment, and original text on injected Gemini failure.
9. **Owner isolation:** switch test accounts during/in between sessions and confirm old-owner segments/translations/events cannot appear or commit under the new owner.
10. **Adjacent PTT:** exercise one retained PTT request to prove `/v2/voice-message/*` transport/codecs/provider diagnostics were not narrowed with conversation listen.

Use semantic automation actions from the integrated S-10 harness where available. If a real Intel Mac, development Modulate credential, or development Gemini credential is unavailable, record that acceptance row as `NOT_RUN` with the exact blocker; hermetic fakes may prove code contracts but may not be reported as live provider evidence.

## 16. Repository closure versus separately authorized live operational closure

### Repository closure authorized by an S-16 implementation PR

- remove server conversation/session/transcript/finalization/Pusher/People dependencies exclusive to listen;
- remove `/v4/web/listen`, rejected query/event modes, cloud transcription preferences after callers leave, and stale generated/route-policy contracts;
- remove NLLB source, image registry, chart, workflow, runtime env/config, checks/tests/scripts/current docs;
- update current service maps/runbooks and preserve explicit later-slice handoffs;
- run tests, generation/check manifests, preflight, and named development-bundle acceptance.

### Live operational closure requiring separate explicit authorization and fresh inventory

- delete deployed NLLB Kubernetes namespace/deployment/service/ingress/HPA/ServiceMonitor/PrometheusRule/image/artifacts or revoke its DNS/IAM;
- delete or rotate `HOSTED_TRANSLATION_API_URL`, NLLB secrets, credentials, dashboards, alerts, budgets, or container registry images;
- remove deployed `/v4/web/listen` traffic or external-client support before owner/client inventory and rollout approval;
- delete Firestore conversations/transcripts/People/preferences, Redis in-progress/session/cache keys, stored audio, Pusher data, Cloud Tasks, or user cloud history;
- delete deployed Pusher, diarizer, backend-listen, finalizer, VAD, or their service accounts/secrets/alerts;
- deploy backend or desktop releases, move beta/stable/prod pointers, or mutate production traffic.

Operational runbook after separate approval must inventory exact project/cluster/namespace/service/DNS/secret/alert owners, capture before/after evidence, verify retained Gemini/listen traffic, define rollback for traffic/config changes, and coordinate S-23/S-25 data/service retention. Repository removal must not fabricate a live-deletion success signal.

## 17. Risks, ambiguities, and explicit stop points

| Risk / ambiguity | Evidence and response |
|---|---|
| S-10 is not integrated | Hard blocker for product implementation. Safe work before it: inventory refresh and hermetic characterization only. Reopen when execution HEAD contains the local authority/test seams in Section 5. |
| Modulate vocabulary contract can drift | Current official AsyncAPI supports `custom_terms`; revalidate before Cycle 3. Stop if commercial endpoint differs. Required evidence: captured fake plus one authorized development connection accepting the config. Never ignore vocabulary. |
| Segment speaker base is not stated explicitly by IR-385 | Current adapter maps Modulate speaker 1 to `SPEAKER_00`, so local behavior is zero-based; consume S-10's tested canonical base. Stop if integrated code disagrees rather than adding dual conversion. |
| Modulate partials versus stable UUID | Final utterances document `utterance_uuid`; current adapter buffers partials. Prefer finalized UUID. If a final partial must be emitted, generate once in adapter state and test stable re-emission; do not create a new UUID on every update. |
| Entitlement/fair-use code is interwoven with conversation runtime | Split by authority, not by file: retain account/usage calls, forbid product-data calls. Stop if a billing contract actually requires conversation persistence and hand that conflict to S-20/product owner. |
| S-14 shares listen runtime | Rebase/sequence and preserve its structured signal outcome. Do not restore personalized push calls or claim them as S-16. |
| Translation cache may currently key by conversation | Refactor to target/text/language/provider-safe keys with existing privacy bounds. Stop if correctness cannot be proven without a conversation ID; never retain Firestore authority for cache convenience. |
| NLLB may be deployed/live despite repository deletion | Repository work can proceed, but live teardown is blocked until authorized inventory. No fallback provider list or dead env is retained merely because the deployment exists. |
| `/v4/web/listen` may have external clients absent from repo | In-repo route deletion is required by IR-398; live rollout requires API-owner confirmation. Stop deployment, not local authority work, if inventory is unavailable. |
| Shared `TranscriptSegment` has many callers | Remove listen dependency first. Delete shared fields/helpers only after complete callers migrate in their owning slices. Stop broad model cleanup rather than absorbing S-10/S-23/S-26. |
| Pusher/diarizer helpers have other callers | Remove the listen edge; leave explicit S-25/S-23 handoff. Do not delete a shared service because its listen caller is gone. |
| Codec helpers are shared with PTT | Narrow only `/v4/listen`; test PTT adjacency. Stop any deletion whose only proof is a name match rather than caller trace. |
| Device headers are shared globally | Remove them only from conversation WebSocket request/context. Preserve retained HTTP endpoint device scoping. |
| Translation model label/config after S-22 | IR-726 fixes Gemini 2.5 Flash-Lite for this retained translation. If integrated S-22 defines a different explicit feature key that resolves to the same authorized model, consume it; stop on a true decision conflict and follow the live requirements ledger. |
| Hermetic route test could mock internals instead of behavior | Use FastAPI route, real runtime composition, injected provider/system-boundary fakes, strict write spies. Source scrapes remain tripwires only. |
| Real Intel hardware/credentials may be unavailable | Run fake/forced-path tests and Apple Silicon named bundle; record Intel/live provider rows `NOT_RUN`, never fake pass. Hardware/credential absence blocks corresponding live evidence, not repository TDD. |
| Existing cloud data retention is undecided | Do not migrate, backfill, or wipe it in S-16. The unreleased fork needs correct local schema evolution, not an Omni compatibility layer. Live data closure belongs to S-23/S-25 plus explicit policy. |

## 18. Final completion checklist

### Requirements and authority

- [ ] Execution SHA includes required baseline plus integrated S-02, S-03, and S-10; inventory is refreshed.
- [ ] IR-017 through IR-023, IR-384 through IR-405, IR-726, IR-887 through IR-889, and IR-898 are each evidenced in tests/PR notes.
- [ ] Mac/GRDB is the sole durable conversation/transcript/label/finalization authority.
- [ ] `/v4/listen` has zero Firestore/Redis/Pusher/Cloud Task/object-storage conversation side effects.
- [ ] Account admission/usage is retained without becoming product-data authority.

### Retained behavior

- [ ] Local Parakeet and managed Modulate persist the same local shape.
- [ ] Mic + System Audio, meeting gating, exact three modes/default/header cycle/Never mic-only behavior pass.
- [ ] Stop, Finish-and-Continue, four-hour rotation, reconnect/watchdog, restart, owner isolation pass.
- [ ] Generic numeric diarization and local live/completed Name Speaker pass without People/speech profile.
- [ ] Ready/failure/subscription truth and VAD fail-open pass.
- [ ] Translation attaches locally by stable segment ID and preserves original text on failure.
- [ ] PTT adjacency passes unchanged.

### Deletion and simplification

- [ ] One authenticated `/v4/listen` route remains; `/v4/web/listen` and `_stream_handler` are absent.
- [ ] Fixed mono 16 kHz s16le transport and query allowlist fail closed on retired/unknown fields.
- [ ] No client/server conversation ID, session lifecycle, timeout/rollover/finalization, custom STT, onboarding, call, multichannel, provider hint, client VAD override, stable listen device/app identity, or cloud lifecycle status remains.
- [ ] No listen transcript persistence/server normalization/Pusher/People/speech-profile dependency remains.
- [ ] Cloud transcription preference routes/helpers/generated DTOs are gone after caller proof; unrelated language/account fields remain where owned.
- [ ] NLLB source/chart/workflow/image/env/check/test/script/current-doc residue is absent; Gemini is explicit without a one-item provider list.
- [ ] No no-op, deprecated alias, duplicate DTO, ignored field, fake success, or compatibility path remains.
- [ ] Shared/later-slice residue is named with owner and reason rather than hidden.

### Verification and closure

- [ ] Every cycle's RED failed for the intended reason and its GREEN focused tests pass.
- [ ] Backend and desktop component suites, generated-client checks, runtime/deployment contracts, residue searches, and `make preflight` pass.
- [ ] Real named development-bundle paths were exercised; unavailable hardware/provider rows are explicitly `NOT_RUN`.
- [ ] `PRODUCT.md`, root/component `AGENTS.md`, `FORK.md`, service maps, runbooks, E2E docs, and changelog are truthful.
- [ ] `python3 bootstrap-scaffold/validate-requirements-ledger.py` passes at completion.
- [ ] `git diff --check` passes and the implementation PR contains verification evidence/failure-class declaration required by root `AGENTS.md`.
- [ ] Repository closure is distinguished from unperformed live operational deletion; no deploy or data/resource deletion is implied.
- [ ] No work owned by S-10, S-14, S-20, S-22, S-23, or S-25 was silently absorbed.
