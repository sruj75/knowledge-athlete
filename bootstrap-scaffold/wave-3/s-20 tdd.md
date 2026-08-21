# S-20 TDD plan — move fair-use evidence local and keep only enforcement facts in cloud

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | **S-20** |
| Wave | **3 — reconnect retained cross-domain behavior to local owners** |
| Name | **Move fair-use evidence local and keep only enforcement facts in cloud** |
| Type | Split-authority adaptation |
| Primary decisions | **IR-610 through IR-615 and IR-700 through IR-709** |
| Required predecessors | **S-10 local Conversations, S-16 transient `/v4/listen`, S-18 normalized `bounded\|unlimited` entitlement** |
| Named development bundle | **`omi-wave3-s20`** |
| Roadmap authority | [`../deletion-map.md`](../deletion-map.md), S-20 |
| Decision authority | [`../requirements-challenge.md`](../requirements-challenge.md) |

This is an execution plan, not implementation or verification evidence. Writing it changes no product code, test, schema, generated client, configuration, deployment, application bundle, or external resource.

## 2. Planning status and pinned baseline

**Status:** ready to start. Gate 0 is resolved: conversation evidence is locally authoritative in owner-scoped GRDB, while the existing backend GPT-5.1 classifier remains transient managed compute. Implementation must preserve the current classifier and enforcement behavior; it must not introduce an on-device model, alternate classifier, new setup, or hosted conversation authority.

The required Wave 2 closeout commit remains an ancestor of the inspected planning baseline:

```text
HEAD 56b29a41ad095625456e3e00f4f980b15701d8a2
branch audit-wave-2-slices...origin/audit-wave-2-slices
Wave 2 closeout ancestor: 711269baf5e653bd62132688998732207f11dd3c
additional commits after closeout: Wave 3/4 plan commit 56b29a41
additional product diff after baseline: none
```

Planning-time checks actually run:

```bash
git merge-base --is-ancestor 711269baf5e653bd62132688998732207f11dd3c HEAD
git rev-parse HEAD
git status --short --branch
git log --oneline 711269baf5e653bd62132688998732207f11dd3c..HEAD
git diff --stat 711269baf5e653bd62132688998732207f11dd3c..HEAD
python3 bootstrap-scaffold/validate-requirements-ledger.py
```

The requirements validator reported:

```text
Requirements ledger validation: PASS (714 indexed rows, 714 detailed sections, all reviewed)
```

The validator proves ledger structure, not semantic freshness. Detailed `### Decision` sections govern this plan. In particular, the detailed IR-615 decision retains the synthetic `free_exhausted = 1.0` path even if an older checkpoint summary suggests separating quota and fair use.

No product test, model run, named bundle, user path, or cloud operation was executed while planning. All later commands and acceptance statements in this document are future implementation requirements.

## 3. Outcome

The end state preserves the current fair-use classifier and policy while moving only durable conversation authority to the owner-authorized Mac:

```text
authenticated `/v4/listen`
  -> backend meters actual live speech in Redis
  -> exact entitlement band crosses a soft cap
  -> backend creates one content-free, UID-bound review request
  -> typed event reaches the authenticated Mac
  -> Mac captures one RuntimeOwnerAuthorizationSnapshot
  -> canonical TranscriptionStorage reads <= 30 conversations from the last 7 days
  -> authenticated POST submits the same bounded classifier evidence transiently
  -> backend validates principal, request, expiry, evidence bounds, and idempotency
  -> existing GPT-5.1 runs the exact retained prompt/recipes/schema/parser
  -> request content and detailed model output are discarded after classification
  -> Firestore records content-free event/support history
  -> backend alone applies warning -> throttle/final warning -> restrict
  -> notification carries truthful stage/timer/allowance, case code, and support path
```

The Mac is authoritative for the durable conversation evidence. GPT-5.1 remains the existing transient classifier and is not a data store or product authority. The backend remains authoritative for speech usage, trigger/cooldown request state, entitlement band, the 30-hour deterministic ceiling, strike counting, enforcement state/timers, the restricted 30-minute UTC-day managed-cloud allowance, notifications, case references, and protected support operations.

Only the existing title, first 200 overview characters, category, duration, source, time, and opaque request-local evidence token for at most thirty conversations may cross the Mac boundary in the authenticated classifier request. Raw audio, transcript, screenshot, person/name, other content, and canonical local conversation IDs never cross. Request content, prompt payloads, selected evidence, and detailed reasoning must not enter backend logs, metrics, Redis, Firestore, notifications, support responses, or any hosted conversation store.

The repository must finish without server-side hosted-conversation reads, content-bearing Firestore case fields, anonymous case-status route, signed-in own-status route, false Settings direction, or generated methods for removed routes. It must retain the backend GPT-5.1 classifier workload, six `X-Admin-Key` support operations, random `FU-...` case references, account-lifetime content-free event history, and account-deletion subtree removal.

`BILLING_MODE=disabled` remains the Wave 3 state. S-20 consumes the already-landed normalized `PlanType.bounded|unlimited`; it does not activate Dodo, create transactions, infer commercial plans, or reopen S-18.

## 4. Authorizing requirements

The detailed decision section for each row is authoritative. A changed decision stops execution and requires this plan to be refreshed.

| Decision | Required S-20 result | Planned cycles |
|---|---|---|
| IR-610 | Keep conservative classification, rolling review, graduated enforcement, explanation/appeal code, support controls, and 30-hour ceiling; adapt the evidence/inference boundary. | 1-12 |
| IR-611 | Read at most 30 local-authoritative conversations from the previous seven days and preserve generated title, first 200 overview characters, category, duration, source, and time as the bounded classifier input. | 1-2, 4 |
| IR-612 | Keep the existing backend GPT-5.1 model, prompt, recipe selection, strict output schema, parser/clamping, timeout/error handling, and fail-open result; change only the durable evidence source from hosted Firestore to local GRDB. | Gate 0, 1, 4-5, 10-12 |
| IR-613 | Allow bounded content only in the transient authenticated GPT-5.1 request. Store only UID-bound usage/threshold facts, classifier/prompt version, score, the existing coarse type, confidence, stage/action/timestamps, and case reference; add no reason-code taxonomy. | 1, 4-5, 10-12 |
| IR-614 | Keep `throttle` internally as notify-only final warning, remove quality-reduction claims, and normalize an automatically timed final warning to `warning` after seven clean days. | 6, 8 |
| IR-615 | Retain the separate server-side synthetic `misuse_score=1.0`, `usage_type=free_exhausted` shortcut, normal quota/paywall response, fair-use events/notifications/restriction, and paid-upgrade cleanup. | 9 |
| IR-700 | Consume normalized entitlement: bounded is exactly 2/8/10 speech hours; unlimited is 4/16/20; any one crossing requests review; keep 12-hour cooldown and separate 30-hour ceiling. | 3, 9 |
| IR-701 | Keep 30-day restriction and 1,800,000 ms managed-cloud allowance per UTC day; emit a typed event instead of silent disposal; use local Parakeet if available or show truthful blocked-until-reset/support state. Keep the live socket stable. | 7 |
| IR-702 | Route every automatic enforcement read through one normalizer: expired restrict -> final warning with a new seven-day timer -> warning. | 6-7, 9 |
| IR-703 | Delete only unauthenticated `GET /v1/fair-use/case/{case_ref}/status` and exclusive model/rate-limit/test/generated/policy residue; retain case codes and protected support lookup/index. | 8, 10 |
| IR-704 | Do not add a Settings card. Delete signed-in `GET /v1/fair-use/status`, its response/generated method/tests, and false Settings direction; notifications plus support remain. | 8, 10 |
| IR-705 | Retain exactly six API-only support operations behind `X-Admin-Key`; rebrand copy/runbook; do not build a dashboard, staff accounts, RBAC, or ship the key to Mac. | 8 |
| IR-706 | Preserve raw manual set-stage exactly: only `none` clears timers; manually selected throttle/restrict without timers do not auto-expire until support changes stage or resets. | 6, 8 |
| IR-707 | Count only stored scores `>= 0.7` created after the latest `reset_at`; retain low-score and older events as history; synthetic free exhaustion still qualifies. | 5-6, 9 |
| IR-708 | Retain content-free event/support history for account lifetime with no TTL, cap, or cleanup job; recursive account deletion remains the deletion boundary. | 5, 8, 11 |
| IR-709 | Preserve the accepted partial kill-switch/exempt behavior exactly, including already-restricted accounts still being subject to the managed-cloud budget/audio gate. | 7, 9 |

## 5. Dependencies and entry gates

### Gate 0A — local-authority/transient-GPT-5.1 contract (resolved)

The product decision is final: “local” means local durable authority, not on-device inference. The existing cloud GPT-5.1 classifier remains the transient compute seam. This deliberately matches the established local-owner/transient-cloud-compute pattern and avoids a second model migration.

The implementation contract is locked:

- keep GPT-5.1 and the exact existing system prompt, user-message construction, recipe-selection rules, JSON output, parser/clamping, evidence cap, prompt version, threshold, timeout/error handling, and fail-open behavior;
- keep the same 12-hour cadence, newest 30 conversations from seven days, and title/overview/category/duration/source/time inputs;
- keep the same warning -> final warning -> restriction progression, classifier-failure fail-open behavior, and backend authority over usage, strikes, restrictions, and the 30-hour hard ceiling;
- read canonical evidence only from owner-scoped local GRDB and send it only in the bounded authenticated classification request;
- create no hosted conversation copy and durably store no title, overview, local ID, selected evidence, prompt payload, or content-specific reasoning;
- use `support@heyintentive.com` on retained support and notification surfaces;
- do not add Qwen, llama.cpp, another model, a bundled/downloaded model, a hardware-specific classifier path, a new user setup, or an alternate rules engine.

Cycle 1 may start immediately. Any proposal to change the model, prompt, recipes, threshold, cadence, evidence window/fields, output, fail-open behavior, or enforcement is a hard stop and requires a separate reviewed product decision.

### Gate 0B — exact local evidence-shape reconciliation (resolved contract)

IR-611 requires `category` and `source`. The canonical S-10 `LocalConversationSummary`, `ConversationStructureComputeResponse`, and current `transcription_sessions` authority contain title, overview, times, status, and segment count, but no category or capture source. The exact existing producers are nevertheless source-grounded:

- `backend/routers/conversation_compute.py::compute_structure_candidate` delegates to `backend/utils/llm/conversation_processing.py::get_transcript_structure`, which already computes `Structured.category` using the closed `CategoryEnum`; `backend/routers/conversation_compute.py::compute_structure` currently drops that field while projecting the local candidate response. Add `category: CategoryEnum` to `ConversationStructureResponse`, add the matching response-only Swift string to `ConversationStructureComputeResponse`, validate the existing enum through the backend DTO, and write it with title/overview in `TranscriptionStorage.completeStructureWork`. Add a nullable classifier-only `category` column to `transcription_sessions`; existing rows remain `NULL`, and the evidence projection maps `NULL` to the exact current classifier fallback `""` from `structured.get('category', '') or ''`. Do not re-run a model to backfill or expose category in Conversation UI/list/detail.
- `TranscriptionStorage.beginConversation` has one production caller, `AppState+Transcription.swift`; new local captures at that boundary use the existing source value `"desktop"`. Add a nullable classifier-only `source` column, write the literal `"desktop"` for new captures, and leave retained legacy rows `NULL` because S-10 intentionally dropped their broader source provenance and it cannot now be reconstructed truthfully. The evidence projection maps legacy `NULL` to the exact current classifier fallback `""` from `conv.get('source', '')`. Do not infer source from device names, STT provider, Memory source, or unrelated state.

Duration remains `finishedAt - startedAt`; time is the local conversation `createdAt`; title is the existing generated value; overview remains `prefix(200)`. The narrow fair-use query reads these columns directly and does not broaden `LocalConversationSummary` or any user-visible taxonomy. Migration, response, commit, and projection tests pin every value.

Affected cycles: 1-2, 4, 10, and 12. Stop if implementation invents a new category/source taxonomy, product UI, or unrelated inference.

### Gate 0C — rebranded support destination and copy boundary (resolved)

The approved support destination is exactly `support@heyintentive.com`.

Preserve the current notification stages, delivery timing, ` Reference: {case_ref}` suffix, and support behavior. Make only the copy corrections already required by IR-614/IR-701. These strings are literal contract fixtures; `throttle` remains the internal stage name and maps to the final-warning copy:

| State | Title | Body |
|---|---|---|
| `warning` | `Fair Use Notice` | `Your speech usage is unusually high. This service is designed for personal conversations. If this continues, you may receive a final fair-use warning. Contact support@heyintentive.com if you believe this is an error. Quote your case reference when contacting support.{ref_suffix}` |
| `throttle` / final warning | `Final Fair Use Warning` | `Due to high non-conversational usage, this is your final fair-use warning. Transcription quality and access have not changed. This warning resets after seven days without another qualifying violation. Contact support@heyintentive.com if you believe this is an error. Quote your case reference when contacting support.{ref_suffix}` |
| `restrict` | `Transcription Limit Reached` | `Your managed cloud transcription is temporarily limited for 30 days due to repeated fair-use violations. Up to 30 minutes of managed cloud transcription remains available each UTC day. On-device transcription continues only when it is available on this Mac. Contact support@heyintentive.com to discuss your usage. Quote your case reference when contacting support.{ref_suffix}` |
| restricted allowance exhausted with no local STT | `Managed Transcription Paused` | `Today's 30-minute managed cloud transcription allowance has been used. On-device transcription is unavailable on this Mac, so transcription is paused until {reset_at}. Contact support@heyintentive.com to discuss your usage. Quote your case reference when contacting support.{ref_suffix}` |

`ref_suffix` is empty when there is no case reference and otherwise remains exactly ` Reference: {case_ref}`. `reset_at` uses the existing truthful UTC-day reset projection. Do not add a Settings card, dashboard, appeal flow, new stage, or extra notification.

### Gate 1 — execution-time rebase, predecessor, and inventory refresh

Before the first RED:

1. Run `make setup` as required before the first commit, fetch the target branch, keep the current branch name, and integrate current `origin/main` without losing `711269ba` ancestry.
2. Record `HEAD`, `origin/main`, ancestry, status, and the exact diff. Rerun the ledger validator.
3. Re-read IR-610 through IR-615 and IR-700 through IR-709 plus S-10/S-16/S-18 closeout seams.
4. Rerun the §7 inventory and §13 residue searches. Record new callers instead of guessing them away.
5. Run the existing focused fair-use, transient-listen, owner-fence, local-conversation, quota, and account-deletion tests to separate pre-existing failures from intended REDs.
6. Stop if `TranscriptionStorage.conversationPage`, immutable `/v4/listen`, or normalized `PlanType.bounded|unlimited` is absent or materially changed. Rebase onto the owner; do not create compatibility aliases.

All three direct predecessors are integrated at the planning baseline. S-18 is only at its approved disabled checkpoint, which the Wave 2 closeout explicitly permits for Wave 3 source work. Final Dodo activation remains post-Wave-6 and is not an S-20 blocker.

### Gate 2 — protocol and privacy review before wire freeze

Before adding the proposed review endpoint/event, freeze a short contract fixture that proves:

- the authenticated websocket review request contains only opaque request ID, trigger/window/threshold facts, classifier contract version, request/expiry timestamps;
- the authenticated classification request contains only the exact existing title, 200-character overview, category, duration, source, time, and request-local evidence-token fields for at most thirty conversations, plus opaque review ID;
- UID, entitlement, usage snapshot, thresholds, stage, action, timestamps, and case reference are server-derived rather than trusted from the client;
- unknown/additional or unbounded keys fail validation rather than being ignored or stored;
- request IDs are owner-bound, single-use/idempotent, expire with the retained 12-hour review window, and cannot be replayed by another Firebase principal;
- GPT-5.1 receives the current byte-for-byte prompt/recipe/output contract; and
- logs, telemetry, durable cases, support responses, and response DTOs use only the shared sanitized/content-free fields.

The planned endpoint is `POST /v1/fair-use/reviews/{review_id}/classify`; the planned websocket event is `fair_use_review_requested`. The endpoint invokes the existing GPT-5.1 classifier and atomically applies the resulting content-free enforcement facts; the client never supplies a score, type, confidence, strike, stage, or action. These are new exact transport contracts, not new product behavior or compatibility routes. If a refreshed architecture owns a different authenticated first-party submit seam, stop and revise this document before adding both.

## 6. Current production codeflow

### Meter, classify, and escalate

```text
`/v4/listen` VAD-gated managed speech
  -> routers/listen/runtime.py periodically flushes actual speech milliseconds
  -> utils/fair_use.record_speech_ms -> Redis minute buckets
     fair_use:v2:speech:{source}:{uid}
     fair_use:v2:bucket:{source}:{uid}
  -> every five minutes `_refresh_fair_use`
  -> load subscription.entitlement_policy
  -> get rolling 24h / 3d / 7d totals
  -> exact PlanType band + 30-hour ceiling
  -> `trigger_classifier_if_needed` background task
     -> raw cached stage read
     -> Redis `fair_use:classifier_lock:{uid}` for 12 hours
     -> if Free credits exhausted: synthetic score 1.0/free_exhausted
     -> else backend `classify_user_purpose(uid)`
        -> Firestore hosted `database.conversations.get_conversations`
        -> up to 30 rows after now-7d
        -> title / overview[:200] / category / duration / source / created_at
        -> managed fair_use GPT route + usage tracking
     -> `escalate_enforcement`
     -> Firestore event and state mutation
     -> FCM/in-app push notification
```

The violation is the classifier's current hosted Firestore evidence dependency and durable storage of its content-bearing result—not the transient GPT-5.1 computation itself. The classifier returns conversation IDs, titles, and content-specific reasons, and `escalate_enforcement` currently nests that entire object into `fair_use_events`.

### Current state and strike behavior

`users/{uid}/fair_use_state/current` holds stage, rolling counts, last score/type, timers, reset metadata, and last case reference. `users/{uid}/fair_use_events/{event_id}` holds usage/threshold snapshots, classifier content, action/stages, case reference, and support resolution metadata.

Current defects that assigned decisions require S-20 to repair:

- `get_violation_counts` counts every recent review, including scores below 0.7 and reviews before `reset_at`;
- event threshold snapshots always use the bounded constants even when the trigger used unlimited thresholds;
- the ordinary cached stage reader does not normalize expiry;
- `normalize_expired_restriction_state` only does expired restrict -> throttle, does not start a seven-day `throttle_until`, and never does expired throttle -> warning;
- review trigger skips an account based on the raw cached `restrict` stage;
- automatic and manual states are not distinguished when expiry is normalized, although IR-706 requires raw manual no-timer states to remain indefinitely.

### Restricted managed-cloud allowance

At listen bootstrap and refresh, raw `restrict` makes the session track a Redis UTC-day managed-STT budget. The limit is `FAIR_USE_RESTRICT_DAILY_MANAGED_STT_MS=1800000`. When exhausted, `ListenReceiver._flush_stt_buffer` clears audio and returns. It does not close the websocket, but it emits no event, so the Mac can remain visibly recording without new cloud transcript.

The Mac's `TranscriptionService.ListenEvent` currently recognizes only `service_status`, `translation`, and `freemium_threshold_reached`. `AppState.handleListenEvent` has no fair-use branch. The existing cloud-to-local fallback is triggered only after reconnect exhaustion and uses a stop/restart choreography; restriction handoff needs a dedicated same-conversation transition so it does not manufacture a socket reconnect loop or finalize the recording.

### Customer and support routes

`backend/routers/fair_use_admin.py` currently exposes:

```text
KEEP, protected by X-Admin-Key
  GET  /v1/admin/fair-use/flagged
  GET  /v1/admin/fair-use/user/{uid}
  GET  /v1/admin/fair-use/case/{case_ref}
  POST /v1/admin/fair-use/user/{uid}/resolve-event/{event_id}
  POST /v1/admin/fair-use/user/{uid}/reset
  POST /v1/admin/fair-use/user/{uid}/set-stage

DELETE
  GET  /v1/fair-use/case/{case_ref}/status
  GET  /v1/fair-use/status
```

The two deleted routes appear in the route-policy legacy baseline and the generated Swift client, but have no handwritten Mac caller. The protected case lookup still needs `case_ref` and its collection-group query; public-route deletion does not authorize removing the support query/index.

### Local authority and owner fencing

S-10's `TranscriptionStorage.conversationPage(query:offset:limit:)` reads `transcription_sessions` in newest-first order from the owner-scoped `omi.db`, clamps limit to 200, and accepts date/status filters through `ConversationLocalQuery`. `RuntimeOwnerAuthorizationSnapshot` captures both owner ID and generation, so signing out and back into the same UID revokes old work.

Current read methods can manufacture their own authorization. S-20's multi-await pipeline must instead capture once at review admission, derive one `LocalMutationAuthorization`, and recheck that same snapshot before/after the local read and immediately before the authenticated classification submission, telemetry, and any handoff UI. Owner change cancels unsubmitted work and retargets the database; it must never send owner A's evidence with owner B's credential. Backend acceptance is bound to the authenticated UID and opaque pending review established at admission; no classifier result is published back into owner-local product state.

S-08 explicitly retains **no owner-local data wipe** on account deletion/sign-out. Backend account deletion recursively deletes every Firestore user subcollection, including `fair_use_state` and `fair_use_events`. S-20 must not silently redesign the S-08 local lifecycle and adds no durable local classifier-result store. Source conversations remain owner-scoped and inaccessible after owner transition.

## 7. Complete caller and dependency inventory

Refresh this table at execution time. “Expected action” is the planned owner boundary, not proof that a future file must have that exact shape.

| Current surface | Current responsibility/callers | Expected S-20 action |
|---|---|---|
| `backend/utils/fair_use.py` | Redis meters/cooldown/cache/budget; exact caps/ceiling; free-exhausted; classifier trigger; stage/event/notification | Split into deep request/enforcement seams; retain meters/caps/budget/free shortcut/partial overrides and GPT-5.1 classifier invocation; fix counts/recovery/copy |
| `backend/utils/llm/fair_use_classifier.py` | Hosted conversation query, exact prompt/recipes, GPT-5.1 call, parser/clamps/content evidence | Retain the classifier behavior byte-for-byte; replace only the hosted query with a strict supplied-evidence argument; keep content transient |
| `backend/models/fair_use.py` | Stages, triggers, usage types, content-bearing classifier/event models | Retain enums/policy facts; add strict bounded evidence request and content-free event/response DTOs; remove durable evidence/title/reasoning shapes |
| `backend/database/fair_use.py` | Firestore state/events, case refs, counts, reset, support queries | Retain state/history/support; make event schema content-free, positive-post-reset counts, atomic/idempotent classification application where required |
| `backend/routers/fair_use_admin.py` | Six support operations plus two customer/public routes and false copy | Keep six protected operations/raw manual semantics; add authenticated classify submit at an app-client seam (or narrow router); delete two routes/models/rate limit/copy |
| `backend/main.py` | Registers the fair-use router | Keep retained router; no duplicate service/router |
| `backend/routers/listen/runtime.py` | Five-minute entitlement/cap refresh, server classifier task, raw stage/budget flags | Emit/replay content-free review request; use authoritative normalized automatic stage; keep metering/ceiling/budget |
| `backend/routers/listen/contracts.py` | Session state flags; no review/handoff event state | Add content-free request and one-shot allowance event state |
| `backend/routers/listen/receiver.py` | Provider socket/audio flush; silently drops exhausted restricted audio | Emit typed exhaustion event exactly once, preserve socket, then stop provider-funded forwarding |
| `backend/utils/listen_session_bootstrap.py` | Reads raw stage and daily budget before audio | Consume authoritative normalized automatic state while preserving partial kill/exempt semantics |
| `backend/models/message_event.py` and listen response helpers | Existing typed service/translation/freemium events | Add/validate review-request and cloud-allowance-exhausted envelopes if this remains the owning event module |
| `backend/utils/billing/service.py` | Calls `clear_fair_use_on_upgrade` after paid projection | Retain `free_exhausted`-only cleanup; consume S-18 normalized paid state; no Dodo activation |
| `backend/database/users.py:delete_user_data` | Recursively deletes all `users/{uid}` subcollections | Retain as backend fair-use deletion boundary; add regression proof, no special fair-use TTL/job |
| `backend/utils/llm/model_config.py` | Registers managed `fair_use` as OpenAI `gpt-5.1`, currently with an env override | Pin the explicit GPT-5.1 workload so S-22 can remove generic gateway/profile/model selection without changing this model |
| `backend/llm_gateway/config/generated_route_overrides.yaml` | Generated gateway override currently risks changing the fair-use model | S-22 removes the gateway binding and preserves the direct explicit GPT-5.1 route; S-20 owns classifier parity |
| `backend/docs/llm/model_endpoint_inventory.yaml`, `utils/llm/ARCHITECTURE.md` | Documents hosted fair-use compute | Update to local-authoritative evidence plus transient GPT-5.1 compute; preserve the retained workload |
| `backend/charts/backend-listen/{dev,prod}_omi_backend_listen_values.yaml` | Enables fair use and binds thresholds, model/lookback, cooldown, exempt, budget | Keep enforcement/caps/cooldown/override/budget; replace model selection with fixed GPT-5.1 and move the fixed seven-day lookback into the local evidence contract |
| `backend/route_policy_legacy_missing_routes.txt` | Lists six admin plus two deleted customer routes as legacy missing | Remove only the two deleted entries; add new authenticated route to the canonical manifest if required by refreshed policy |
| `backend/scripts/export_openapi.py` | Includes `/v1/fair-use` in app-client surface | Keep prefix for classify route; removed customer operations disappear; regenerate/check Swift |
| `desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift` | Contains only the two dead fair-use GET methods today | Regenerate: delete both GETs, add typed authenticated bounded-evidence classify DTO/method; never hand-edit |
| `desktop/macos/Desktop/Sources/TranscriptionService.swift` | Strict `/v4/listen` event decoder/domain | Add exact review-request and allowance-exhausted cases; reject malformed envelopes without content logging |
| `desktop/macos/Desktop/Sources/AppState/AppState+ListenEvents.swift` | Session-fenced listen event handling | Admit review coordinator and dedicated allowance handoff only for expected session/owner |
| `desktop/macos/Desktop/Sources/AppState/AppState+Transcription.swift`, `STTSessionState.swift` | Local/cloud selection and failure fallback | Add dedicated restriction handoff preserving conversation/authorization; do not reuse reconnect-failure semantics blindly |
| `desktop/macos/Desktop/Sources/LocalTranscriptionService.swift` | FluidAudio Parakeet availability/load/failure | Reuse availability for IR-701 only; not the semantic fair-use model |
| `desktop/macos/Desktop/Sources/Rewind/Core/TranscriptionStorage+LocalAuthority.swift` | Canonical local Conversation read/mutation seam | Add narrow owner-authorized fair-use evidence read; no backend/storage fallback and no duplicate classifier-result store |
| `backend/routers/conversation_compute.py`, `backend/utils/llm/conversation_processing.py`, `APIClient+ConversationCompute.swift`, `RewindDatabase+ConversationLocalAuthority.swift`, `TranscriptionStorage+LocalAuthority.swift` | The structure helper already produces category but the backend/Swift response DTOs drop it; local session schema lacks category/source | Project existing `CategoryEnum` into a nullable classifier-only column; write source `"desktop"` only for new desktop captures; preserve legacy category/source as NULL and project each as the current `""` fallback; add narrow migration/commit/evidence tests without broadening Conversation UI models |
| `OwnerAuthorizedStorageReads.swift`, `Chat/RuntimeOwnerIdentity.swift`, `RewindDatabase+OwnerAuthorization.swift` | Established single-snapshot authorization patterns | Reuse unchanged public authorization contract; no second owner-token system |
| `desktop/macos/Desktop/Sources/DesktopDiagnosticsManager.swift` | Shared `recordFallback` helper | Record classifier request/failure fail-open and cloud-STT -> local/blocked handoff using bounded fields only |
| `desktop/macos/Desktop/Sources/DesktopAutomationBridge.swift`, `desktop/macos/e2e/` | No fair-use semantic acceptance today | Add non-production semantic state/action/flow only if wired into existing E2E lane and content-redacted |
| `backend/tests/unit/test_fair_use_{engine,async,classifier,classifier_null_fields,classifier_offload,free_tier,models,plan_aware,upgrade}.py` | Current policy/model regressions | Preserve classifier/policy tests; characterize exact GPT-5.1 prompt/recipes/output/fail-open before changing the evidence source; delete only hosted-query-exclusive tests |
| `backend/tests/integration/test_fair_use_{api,live,level1_live}.py` | Routes, Redis/state lifecycle, live path | Rewrite behaviorally for new request/classification/events; remove tests exclusive to deleted GET routes; keep live policy/budget coverage hermetic in CI |
| `backend/tests/unit/test_listen_session_bootstrap.py`, `test_listen_transient_contract.py` | Listen admission/protocol regression | Extend for normalized state and typed events without durable conversation authority |
| `desktop/macos/Desktop/Tests/ConversationLocalQueryTests.swift`, owner-fence suites, `ListenProtocolTests.swift`, `LiveTranscriptionFailureStateTests.swift` | Local query, owner generation, event parsing, failure UI | Extend public seams; add focused fair-use evidence/coordinator/handoff tests |
| `backend/docs/runbooks/reset-transcription-usage.md` | Names protected fair-use reset | Keep command; rebrand support text and explain raw manual exception/recovery |
| `firestore.indexes.json`, `backend/database/firestore_index_registry.py` | Registry currently has no declared fair-use composite despite comments naming support requirements | Do not delete support index/query. During Cycle 8, prove whether single-field automatic indexes suffice and register only a genuinely required compound query; no speculative index |

Other current namespaces reviewed and retained: `fair_use:v2:speech:*`, `fair_use:v2:bucket:*`, transitional live meter keys until their existing TTL expires, `fair_use:stage:{uid}`, the classifier cooldown/lock namespace to be renamed only if migration is atomic, and the UTC-day managed-STT budget/once marker. Names must be re-inventoried from helpers rather than copied from old live-test literals.

## 8. Behavior classification

| Category | S-20 classification |
|---|---|
| **KEEP AS IS** | Actual-speech rolling meters; exact 2/8/10 and 4/16/20 bands; 12-hour dedupe; 30-hour daily ceiling; score threshold 0.7; conservative semantic recipes; three-stage progression; synthetic `free_exhausted=1.0`; paid-upgrade cleanup; 30-day restriction; 30-minute UTC-day managed-cloud allowance; random case code; six protected support operations; raw manual override exception; account-lifetime content-free history; recursive account deletion; normal partial kill/exempt behavior; stable `/v4/listen`; local Parakeet outside restriction. |
| **ADAPT** | Trigger becomes a content-free Mac review request; evidence reads local GRDB and crosses only in one bounded transient request; the existing backend GPT-5.1 performs the exact classifier work; durable events become content-free; strike count becomes positive/post-reset; automatic state reads normalize both timers; throttle copy becomes final warning; budget exhaustion emits typed handoff; notifications use truthful timer/allowance/support; bounded/unlimited comes only from S-18. |
| **DELETE** | Hosted Firestore conversation read/copy, content-bearing durable backend evidence/reasoning, public case lookup, signed-in own-status route, exclusive response/rate-limit/tests/policy/generated methods, false Settings direction, “quality reduced,” unconditional “on-device continues,” and Omi/BasedHardware fair-use copy. |
| **SIMPLIFY AFTER** | Once parity passes: one backend fair-use classifier/policy/request module, one authoritative state reader, one strict bounded-evidence DTO, one Mac evidence coordinator, one shared typed listen event decoder, and one bounded fallback telemetry path. Remove transitional locks/helpers/tests only after no caller remains. |
| **ACCELERATE AFTER** | Measure the existing GPT-5.1 golden suite, focused state-machine tests, and named-bundle review loop after the retained path is GREEN. Improve only a measured repeated bottleneck; otherwise `none`. |
| **AUTOMATE LAST** | After the wire/privacy contract is stable, register only a recurring deterministic parity or residue check in an existing local and CI lane; otherwise `none`. |
| **OUT OF SCOPE / DEFERRED** | S-19 PTT data/tools; S-21 shell redesign; S-22 general managed-model portfolio and realtime providers; S-23 FCM/hosted product-data families; S-25 service/GKE deletion; S-27 live resources/deploy; S-28 storage namespace; S-30 whole-product copy/legal truth pass; Dodo activation; Windows; a support dashboard/RBAC; remote attestation; new quotas/thresholds; local account-data wipe; a public appeal/tracking page. |

## 9. Retained behavioral invariants

1. Crossing a soft cap requests review; it is not itself a semantic misuse verdict, except the explicitly retained Free-exhausted shortcut.
2. Bounded and missing/malformed entitlement use 2/8/10; normalized unlimited uses 4/16/20. No legacy plan-name inference returns.
3. The 30-hour actual-audio daily ceiling remains server-side for every plan and cannot depend on classifier availability.
4. Reviews use no more than 30 newest eligible conversations from the previous seven days and the exact retained evidence recipe.
5. Title and overview are generated local fields; overview is capped at 200 characters before inference; no raw transcript/audio/screenshot enters the semantic prompt.
6. The prompt remains extremely conservative: legitimate meetings, calls, live classes/events and high-volume personal use score low; 0.7+ requires a repeated high-volume wrong-purpose pattern.
7. Output scores/confidence are clamped to 0...1, usage type is a closed enum, detailed evidence is capped at 10, and invalid/unavailable inference fails open to no strike.
8. Bounded evidence leaves the Mac only in the authenticated transient GPT-5.1 request. It and all content-specific reasoning are absent from durable storage, error text, logs, telemetry, crash reports, response DTOs, notification data, and support APIs.
9. One owner authorization snapshot survives every suspension and side effect. Same-UID reauthentication revokes old work.
10. Failure to read or project the local evidence creates no backend event/stage/notification; GPT-5.1 failure preserves the existing fail-open result.
11. Classification-request retry is idempotent; a duplicate cannot create a second model application, event, strike, case code, notification, or state transition.
12. An expired, unknown, wrong-owner, or already-consumed request cannot mutate enforcement.
13. Backend derives UID, usage, thresholds, entitlement, prior stage, timers, action, timestamps, and case reference; the client cannot choose them.
14. Only `misuse_score >= 0.7` and created after latest `reset_at` counts as a strike. Low-score and pre-reset rows remain support history.
15. Automatic progression remains first positive -> warning, second qualifying positive -> notify-only final warning, third qualifying positive -> restrict.
16. Automatically created final warning expires to warning after seven clean days.
17. Automatically created restriction expires after 30 days to final warning with a fresh seven-day timer, then warning.
18. Manual `set-stage` is an explicit exception: only manual `none` clears timers; a manually selected timerless throttle/restrict never auto-expires.
19. Reset clears active enforcement/count fields and writes the counting boundary without deleting event history. Resolve-event does not reset active enforcement.
20. Restricted cloud use is 1,800,000 ms per UTC day. The websocket remains stable when the budget is exhausted and emits the typed event once.
21. If local Parakeet is usable, handoff preserves the current local conversation and owner authorization. If it is not usable, the app visibly stops claiming transcription and presents reset/support truth.
22. Warning and final warning do not change provider, quality, transcript, speed, or allowance.
23. Partial kill-switch/exempt behavior remains exactly as accepted: new triggers/ceiling/hard lookup bypass where they do now, but an already-stored restriction may still hit the cloud budget/audio gate.
24. The six support routes require `X-Admin-Key` using constant-time validation. That key never reaches the Mac.
25. Case references remain random and support-queryable, but neither public nor signed-in status GET exists.
26. Backend content-free history has no TTL/cap/job and is removed by recursive account deletion.
27. `BILLING_MODE=disabled` remains unchanged; S-20 neither grants paid state nor calls Dodo.
28. PTT/realtime voice, Chat, Memory, Tasks, Focus, Rewind, conversation UI/search, and general model routes do not change because of S-20.

## 10. Target authority, result ownership, and service-topology model

### Boundary map

| Fact/data | Authoritative owner | Persistence | Allowed boundary |
|---|---|---|---|
| Conversation titles/overviews/category/source/time | Owner-scoped Mac | Canonical local GRDB rows only | Bounded authenticated classifier request only |
| Exact prompt, recipes, parser, output schema, model ID, and prompt version | Backend fair-use source/config | Durable repository/config contract with parity tests | Used unchanged by the transient GPT-5.1 call |
| Bounded evidence request and detailed GPT-5.1 result | Backend transient classifier | Request memory only; no durable storage/logs/telemetry | Detailed result is projected to content-free facts and never returned to Mac |
| Content-free classifier/enforcement facts | Backend | Firestore event/state | Protected support/notification surfaces only |
| Actual speech totals and trigger/threshold snapshot | Backend | Redis rolling meter; bounded facts in Firestore event | Content-free request/event |
| Pending review request/cooldown/idempotency | Backend | Redis content-free state for retained 12-hour window; durable receipt/event on acceptance | Authenticated websocket/classify POST |
| Entitlement band | S-18 backend projection | Existing retained account entitlement state | Server internally; content-free band/threshold facts may be in request/event |
| Strike count and stage/timers | Backend fair-use policy | Firestore state/events + short Redis stage cache | Notification/support/typed allowance event only |
| Case reference/support audit | Backend | Firestore content-free event/history | Notification and protected operator API |
| Restricted daily cloud budget | Backend listen runtime | Redis UTC-day budget | Typed exhaustion event with reset/support facts |

### Proposed strict contracts

`fair_use_review_requested` websocket envelope:

```text
type
review_id                 opaque random server ID
trigger                    daily | 3day | weekly
window_speech_ms           exact server snapshot
thresholds_ms              entitlement-correct server snapshot
classifier_contract        approved local contract version
requested_at / expires_at  UTC timestamps
```

It contains no UID (the websocket is already principal-bound), plan name, stage recommendation, conversation content, prompt, or provider choice. `classifier_contract` identifies the retained GPT-5.1/prompt-v2 contract; it does not select a client model.

`POST /v1/fair-use/reviews/{review_id}/classify` body:

```text
conversations[]            maximum 30, newest first, within seven days
  conversation_id          opaque request-local token, not canonical GRDB ID
  title                    existing generated title value; no new truncation
  overview                 existing 200-character bound
  category                 existing classifier value
  duration_minutes         existing one-decimal derivation
  source                   existing classifier value
  created_at               existing time representation
```

The client supplies no score, type, confidence, reason, stage, action, usage, entitlement, or `free_exhausted`; only the server may run the classifier and synthesize policy facts. Unknown keys and oversized values are forbidden at this privacy boundary. The response is a content-free acknowledgement with review ID, accepted/idempotent disposition, resulting action/stage, and case reference when one exists. It is not a replacement status API and does not return the detailed GPT output.

### Local authorization and late-result rule

The Mac coordinator captures one `RuntimeOwnerAuthorizationSnapshot` when admitting the websocket request. It reads and bounds evidence under that same snapshot, then revalidates immediately before requesting a Firebase token and before submitting. A token refresh must still match the captured owner/generation. No detailed classifier result is written or published locally.

On quit/offline/transport failure, the backend retains only the content-free pending review until `expires_at` and replays it to the same authenticated owner; the Mac re-reads its canonical local evidence rather than maintaining a second review store. On owner change, cancel unsubmitted work and release UI; owner A's database remains isolated. A late HTTP response after revocation is discarded before telemetry or UI publication. An already-admitted backend request remains UID-bound and can mutate only that UID's backend enforcement transaction.

### Backend acceptance transaction

The backend looks up the pending review using authenticated UID + opaque ID, validates expiry and the bounded evidence, invokes the existing GPT-5.1 classifier with the unchanged prompt/recipes/parser, derives the current classifier facts, then creates exactly one content-free event and applies policy using authoritative current state/counts. The request payload and detailed result are discarded after this transaction. Request consumption, event identity, stage update, last case reference, and notification disposition must be idempotent under retry. Where Firestore cannot commit all documents in the current helper abstraction, define a transactional helper and retryable receipt before GREEN; do not use a check-then-write race.

## 11. Ordered TDD cycles

Each cycle introduces one behavioral RED through a production seam, reaches the minimum GREEN, and deletes/simplifies only what that GREEN makes obsolete. Static residue assertions are labelled tripwires and never substitute for behavior.

### Cycle 1 — characterize and lock the existing GPT-5.1 classifier contract

- **Behavioral RED:** Through the production Python classifier with an injected deterministic GPT seam, pass representative bounded evidence directly and snapshot the current system prompt, recipe selection, user-message construction, strict JSON output, clamping/null/error behavior, maximum-ten evidence cap, `openai/gpt-5.1`, prompt version, and fail-open default. Compare this supplied-evidence path against the current hosted-query path for identical evidence.
- **Why RED now:** Evidence fetching and classifier compute are coupled in `fair_use_classifier.py`, so moving the source could accidentally rewrite the model behavior.
- **Minimum GREEN:** Split only evidence acquisition from classification: add a strict `classify_fair_use_evidence(uid, evidence)` production seam using the current prompt/recipes/parser and explicit GPT-5.1 route. Keep the current hosted query temporarily as a wrapper until cutover.
- **Retained protection:** IR-610/612 classifier meaning, exact prompt text, recipe triggers, strict result shape, model, threshold input, existing timeout/error handling, and failure-open behavior.
- **Authority before/after:** Backend remains semantic compute and enforcement owner; only the evidence-acquisition parameter becomes injectable.
- **Expected changes:** Narrow Python classifier refactor and behavioral parity tests; no Swift model code, package, artifact, download, or product behavior change.
- **Focused verification:** Existing classifier/null/offload tests plus new prompt/message/recipe/model/output parity fixtures and invalid/null/timeout fixtures.
- **Deletion/simplification enabled:** Makes the hosted Firestore query independently removable after the local evidence transport is GREEN.
- **Stop condition:** Any fixture changes GPT-5.1, prompt bytes, recipe trigger, output/parser, threshold, timeout, or fail-open behavior.

### Cycle 2 — owner-authorized local evidence projection

- **Behavioral RED:** Seed owner A's canonical GRDB with more than 30 conversations across the seven-day boundary and assert the S-20 evidence read returns exactly the newest 30 eligible rows with title, `overview.prefix(200)`, category, duration, source, and time. Encoded `conversation_id` values are opaque request-local tokens rather than canonical GRDB IDs. Owner B sees none; owner change or same-UID generation revocation before completion returns no payload.
- **Why RED now:** `conversationPage` has most data and ordering, but no fair-use projection; `compute_structure` drops its already-computed category and the local schema has no category/source columns.
- **Minimum GREEN:** Implement Gate 0B exactly: carry the existing backend `CategoryEnum` through the response DTOs into a nullable classifier-only session column, map legacy category/source NULL to `""`, write `source="desktop"` only at the sole production local capture boundary, and add one owner-authorized `TranscriptionStorage` evidence read. Do not fabricate legacy source provenance, add a classifier-result table, add a durable evidence outbox, broaden summary fields, or run a model backfill.
- **Retained protection:** S-10 local Conversation authority, exact date/order/limit/field recipe, no hosted fallback, owner isolation, and no product UI/category resurrection.
- **Authority before/after:** Hosted Firestore stops being the prospective evidence owner; canonical GRDB supplies the exact bounded projection.
- **Expected changes:** `backend/routers/conversation_compute.py`, `APIClient+ConversationCompute.swift`, `RewindDatabase+ConversationLocalAuthority.swift`, `TranscriptionStorage+LocalAuthority.swift`, generated contract fixtures only where the app-client surface requires them, and focused tests; no Conversation UI/list/detail model change.
- **Focused verification:** New `FairUseEvidenceLocalAuthorityTests`, existing `ConversationLocalQueryTests`, local migration tests, `EffectiveOwnerDatabaseBoundaryTests`, and `LocalMutationAuthorizationTests`.
- **Deletion/simplification enabled:** Enables hosted conversation evidence removal after live cutover.
- **Stop condition:** Evidence fields/order/bounds differ, category/source are fabricated, canonical IDs cross, logs capture content, or any read bypasses the captured authorization.

### Cycle 3 — server-owned content-free review request and typed listen event

- **Behavioral RED:** Through real `/v4/listen` runtime with fake Redis/clock/subscription, crossing each exact entitlement cap creates at most one UID-bound 12-hour request and emits one `fair_use_review_requested` envelope. Below cap, kill-switch/exempt, already-active automatic restriction, duplicate refresh, wrong session, and malformed entitlement behave exactly as retained. Free-exhausted stays server-synthetic and does not ask the Mac to classify content.
- **Why RED now:** Runtime directly spawns the backend classifier and no typed review event or pending request exists.
- **Minimum GREEN:** Replace only the non-Free semantic trigger with content-free pending request/cooldown state and event emission/replay on the authenticated listen session; keep authoritative meters/caps/ceiling and async non-blocking behavior.
- **Retained protection:** Actual-speech accounting, exact bands, 12-hour dedupe, 30-hour ceiling, partial overrides, socket/segment behavior, and Free shortcut.
- **Authority before/after:** Backend continues to own trigger and inference; Mac becomes the pending request's evidence supplier.
- **Expected changes:** `utils/fair_use.py`, listen runtime/contracts/event helpers, Python tests, protocol fixture/docs. Do not add content to Redis.
- **Focused verification:** New request-state tests plus `test_fair_use_plan_aware.py`, `test_fair_use_free_tier.py`, `test_listen_session_bootstrap.py`, and production-route `test_listen_transient_contract.py` with controllable clock/Redis.
- **Deletion/simplification enabled:** Removes server classifier spawn from listen after Cycle 5 is GREEN; preserves old call only behind the test cutover until then, never as runtime compatibility after merge.
- **Stop condition:** Request carries content/UID unnecessarily, event blocks transcript delivery, cooldown changes, or a second classifier path would be required at merge.

### Cycle 4 — owner-fenced Mac evidence coordinator and bounded submission

- **Behavioral RED:** Feed a typed request through `TranscriptionService` and `AppState.handleListenEvent`; assert one captured authorization crosses local evidence read -> bounds/projection -> token refresh -> authenticated classify POST. Body capture proves exactly the retained evidence fields and bounds, with no transcript/audio/screenshot/name/canonical local ID/server-owned policy field. Test offline/replay, duplicate event, expiry, cancellation, local read failure, HTTP failure, owner A->B, and same-UID reauth with late reads/HTTP responses.
- **Why RED now:** The Mac ignores the event, has no evidence coordinator/API DTO, and generated API has only the dead status GETs.
- **Minimum GREEN:** Add one coordinator, strict event decoder, bounded evidence API domain adapter, and shared fallback telemetry. Generate the authenticated POST client from OpenAPI; never manually construct a second API path or store a duplicate review result.
- **Retained protection:** Current segment/service/translation/freemium handling, owner generation, offline conversations, sanitized diagnostics, and no phantom local product state.
- **Authority before/after:** Mac supplies bounded evidence from its canonical local owner; backend remains classifier and enforcement owner.
- **Expected changes:** `TranscriptionService.swift`, `AppState+ListenEvents.swift`, new coordinator, API wrapper/generated DTO, owner/fallback tests, and desktop component guide.
- **Focused verification:** `ListenProtocolTests`, new `FairUseReviewCoordinatorTests`, owner-fence suites, `APIClientAuthRecoveryTests`, generated DTO encode tests, and exact body-capture/privacy assertions.
- **Deletion/simplification enabled:** Enables the backend to reject hosted evidence lookup and durable content fields after Cycle 5.
- **Stop condition:** Any await recaptures authority, stale work submits/publishes, payload exceeds the exact bounded recipe, or a second classifier/result store is introduced.

### Cycle 5 — backend GPT-5.1 classification, idempotent enforcement, and content-free events

- **Behavioral RED:** Through the authenticated production FastAPI route, a valid pending request and bounded evidence invokes the existing GPT-5.1 classifier contract once, creates one content-free event, and applies the expected stage. Duplicate returns the same disposition without another model call. Wrong principal/expired/unknown/already-consumed/malformed/oversized/extra-key requests fail closed. Model timeout/invalid JSON/exception produces the same fail-open default. Low score remains history but not a strike; only scores >=0.7 after latest `reset_at` count; persistence failure creates no partial state/case/notification.
- **Why RED now:** No classify route accepts local evidence; the classifier owns the hosted query; events embed the detailed classifier dictionary; counts include every row and ignore reset.
- **Minimum GREEN:** Add the strict bounded-evidence route, invoke Cycle 1's unchanged GPT-5.1 seam, bind the request to UID/expiry/idempotency, discard request/detailed output after projecting content-free facts, and transactionally apply event/state with post-reset qualifying counts. Server derives usage/threshold/stage/action/time/case. Keep low-score events and current fail-open behavior.
- **Retained protection:** GPT-5.1, exact prompt/recipes/output/parser, score 0.7, three-stage policy, case format, support history, reset/resolve separation, account lifetime, and Free synthetic score.
- **Authority before/after:** Local GRDB is evidence authority; GPT-5.1 is transient compute; backend alone owns classification admission and enforcement.
- **Expected changes:** fair-use classifier/models/database/router/policy, route policy/OpenAPI/generated Swift, unit/integration tests, and account-deletion regression. Firestore gets no content migration/backfill for this unreleased fork; test fixtures become content-free.
- **Focused verification:** New `test_fair_use_classify_api.py`, prompt/model parity fixtures, event-schema forbidden-field tests, current engine/live/API tests rewritten behaviorally, concurrent duplicate, reset boundary, account deletion subtree, and sanitizer/log capture.
- **Deletion/simplification enabled:** Deletes backend `ClassifierEvidence` and nested content-bearing durable `classifier`; enables hosted query removal in Cycle 10.
- **Stop condition:** GPT-5.1/prompt behavior changes, request content persists/logs, event write and stage transition diverge, duplicate calls GPT/notifies twice, client supplies server-owned fields, or admin responses expose evidence.

### Cycle 6 — one authoritative automatic recovery reader with raw manual exception

- **Behavioral RED:** With an injected clock, every automatic enforcement consumer observes active state, expired restrict -> final warning with fresh seven-day timer, and expired automatic final warning -> warning. A new positive inside final-warning re-restricts. Protected manual timerless throttle/restrict remains indefinitely; manual `none` alone clears both timers. Cache reflects committed normalized state once.
- **Why RED now:** The hot reader returns raw cached stage; normalizer is partial; listen can remain restricted forever; manual provenance/timer absence is not explicitly protected.
- **Minimum GREEN:** Create one authoritative automatic-state read/normalize transaction used by trigger, listen bootstrap/runtime, ceiling/hard restriction and support reads where appropriate. Distinguish automatic timer-owned state from the deliberate manual timerless override without changing the raw support command.
- **Retained protection:** Exact seven-/thirty-day durations, three stages, raw `set-stage`, reset, resolve, short cache, no dependency on opening a status route.
- **Authority before/after:** Firestore remains authority; cache becomes a projection of normalized state rather than an alternative owner.
- **Expected changes:** fair-use policy/database helpers, listen bootstrap/runtime, admin tests/runbook; no Mac product change.
- **Focused verification:** Clocked state-machine tests for every boundary millisecond, cache miss/hit/invalidation, concurrent reads, raw manual stages, reset and repeat violation.
- **Deletion/simplification enabled:** Deletes `normalize_expired_restriction_state`/raw-reader split and dead status-route-driven normalization.
- **Stop condition:** Manual timerless state auto-expires, two readers disagree, a failed normalization write is cached, or expiry depends on a customer route.

### Cycle 7 — explicit restricted-cloud allowance event and same-conversation local handoff

- **Behavioral RED:** Exhaust the exact 1,800,000 ms UTC-day budget through production listen receiver. Assert the server emits one typed `fair_use_managed_cloud_exhausted` event, forwards no additional provider-funded audio, keeps the websocket alive, and reports reset/case facts without content. On Mac, usable Parakeet switches within the same local conversation/authorization; unavailable/failed Parakeet shows a truthful blocked state. No reconnect loop, silent “recording,” transcript loss, or paywall mutation occurs.
- **Why RED now:** Receiver silently clears audio; Mac has no event; existing reconnect fallback stop/restarts rather than owning this policy transition.
- **Minimum GREEN:** Add one-shot server event state and a dedicated Mac restriction handoff in `STTSessionState`/AppState. Quiesce cloud audio, start local sinks without finalizing/rotating the conversation when available, otherwise visibly terminalize transcription while preserving reset/support information. Record shared fallback telemetry with bounded reason/outcome.
- **Retained protection:** 30-day restriction, 30-minute UTC budget, stable socket, existing Parakeet availability/load policy, local recording authority, partial kill/exempt behavior, unrelated provider failure fallback.
- **Authority before/after:** Backend owns budget/exhaustion; Mac owns local/blocked presentation and local engine transition.
- **Expected changes:** listen receiver/contracts/runtime tests; `TranscriptionService`, `AppState+ListenEvents`, `AppState+Transcription`, `STTSessionState`, focused Swift tests and E2E flow.
- **Focused verification:** Backend receiver/socket/UTC rollover/once tests; Swift protocol, Apple Silicon-ready, forced Parakeet fail, Intel/no-local, owner-switch, session-stale, conversation-ID continuity, telemetry and no-reconnect tests.
- **Deletion/simplification enabled:** Deletes silent buffer-drop-only behavior and any unconditional “on-device continues” assertion.
- **Stop condition:** Socket is closed/reconnected by policy, handoff finalizes/duplicates the conversation, no-local path still looks active, or override behavior is “fixed” beyond IR-709.

### Cycle 8 — truthful notifications and protected support-only surface

- **Behavioral RED:** Through stage-change production notification and FastAPI routes, assert warning/final-warning/restrict messages carry correct semantic stage, applicable timer/allowance, case code, and approved support destination; none mention quality reduction, Settings, Omi/BasedHardware, or guaranteed local continuation. Both deleted GETs return genuine 404. All six support operations reject missing/bad key and retain behavior; raw manual set-stage exception remains.
- **Why RED now:** Copy is false/legacy; two customer routes exist; tests protect them; support and public lookup share case query.
- **Minimum GREEN:** Apply Gate 0C's literal titles/bodies in the existing backend stage-notification owner and the restricted/no-local Mac presentation, update the runbook, remove both customer handlers/models/rate-limit dependency/exclusive tests and route-policy entries, and preserve six admin handlers plus the case query.
- **Retained protection:** Stage-change notification, random case code, support appeal, constant-time `X-Admin-Key`, bounded list limit, resolve/reset/raw set-stage semantics, content-free admin response.
- **Authority before/after:** Backend remains notification/support owner; Settings never becomes a fair-use owner.
- **Expected changes:** fair-use router/notification helper/models/tests, route policy, runbook, generated client via Cycle 10 generation; no new dashboard/UI card.
- **Focused verification:** FastAPI 404/auth/operation tests, notification payload/copy semantics, admin case lookup with content-free event, limit clamp, reset/cache tests.
- **Deletion/simplification enabled:** Public/signed-in response types, rate-limit registration, false `_user_facing_message`, exclusive tests and generated operations.
- **Stop condition:** Support destination is not approved, a retained admin operation disappears, public lookup remains reachable via alias, or copy claims behavior the app cannot perform.

### Cycle 9 — exact entitlement, Free shortcut, ceiling, upgrade cleanup, and partial overrides

- **Behavioral RED:** Drive production policy with bounded/unlimited/missing entitlement, Free exhausted/not-exhausted, paid upgrade, kill switch, exempt UID, and already-restricted state. Assert exact bands, threshold snapshot, 12-hour behavior, server-only synthetic score 1.0, normal freemium response plus fair-use event, upgrade cleanup only for `free_exhausted`, 30-hour ceiling, and the intentionally partial budget gate.
- **Why RED now:** Most behavior exists, but event thresholds are always bounded, raw stage paths conflict with recovery, and the classify contract could accidentally accept/synthesize Free exhaustion.
- **Minimum GREEN:** Route every semantic trigger through the normalized entitlement/request contract, snapshot the actual active thresholds, keep Free shortcut before the Mac evidence request, keep upgrade cleanup, and pin partial override branches with behavioral tests.
- **Retained protection:** IR-615, IR-700, IR-709 and S-18 disabled entitlement boundary; existing quota/paywall event is not absorbed into fair use.
- **Authority before/after:** S-18 remains entitlement owner; fair-use backend consumes only normalized class; Mac never decides plan/free exhaustion/ceiling/override.
- **Expected changes:** fair-use policy/runtime/billing seam tests and docs only as required; no catalog or Dodo code.
- **Focused verification:** Existing `test_fair_use_plan_aware.py`, `test_fair_use_free_tier.py`, `test_fair_use_upgrade.py`, listen admission/receiver tests, and new active-threshold snapshot cases.
- **Deletion/simplification enabled:** Removes any legacy plan inference or duplicated threshold selection discovered during refreshed inventory.
- **Stop condition:** Implementation needs Dodo activation/commercial names, sends `free_exhausted` through the evidence/classifier request, completes the kill-switch bypass, or changes ordinary freemium handling.

### Cycle 10 — delete hosted conversation reads and durable classifier-content residue

- **Behavioral RED:** End-to-end hermetic review from listen trigger -> typed Mac event -> local GRDB projection -> classify POST -> injected GPT-5.1 seam -> content-free event/stage passes. A hosted-conversation database spy sees zero reads, while a model spy sees exactly the retained fair-use call and prompt. Labelled static tripwires still find hosted query imports and durable content fields before deletion.
- **Why RED now:** `fair_use_classifier.py` still imports and queries hosted conversations, and backend event/support shapes still contain classifier evidence/reasoning.
- **Minimum GREEN:** Cut over without dual evidence authority: retain `fair_use_classifier.py` as the GPT-5.1 compute owner, delete only its hosted conversation acquisition/import and query-exclusive tests, and remove content-bearing event/support/config claims. Pin the explicit GPT-5.1 route, keep prompt/recipe/parser and usage tracking, enforce the seven-day/30-row contract at the local projection, remove obsolete model/lookback deployment selection, and keep all enforcement config.
- **Retained protection:** Exact semantic fixtures/model/prompt, request retry, Free shortcut, thresholds, stage/support/budget, and unrelated S-22 model routes/usage tracking.
- **Authority before/after:** Mac GRDB is the sole durable evidence owner; backend GPT-5.1 remains transient semantic compute with no hosted conversation authority.
- **Expected changes:** Exact query/content schema/docs/tests discovered in §7/§13; `backend/utils/llm/ARCHITECTURE.md` and component guides updated; no unrelated gateway deletion.
- **Focused verification:** Cross-component hermetic contract, hosted-database denial, exact backend model/prompt spy, related fair-use/listen tests, and static residue review.
- **Deletion/simplification enabled:** Final removal of hosted conversation evidence and durable classifier-content storage.
- **Stop condition:** Any production path reads hosted conversation data, any GPT-5.1/prompt/output behavior changes, a retained test depends on hosted conversation documents, or deletion touches an S-22-owned model without preserving fair-use GPT-5.1.

### Cycle 11 — route/generated/schema/config closure and deep-module simplification

- **Behavioral RED:** App-client OpenAPI contains the bounded-evidence classify POST but neither deleted GET; generated Swift compiles with only retained DTOs; backend event/admin/account-deletion tests reject every forbidden durable content field; route policy and test discovery pass. Labelled residue tripwires find no deleted route/client operation or hosted conversation query.
- **Why RED now:** Current generated Swift has both dead GETs, route-policy baseline lists them, backend event schema is broad, and documentation/config still claim hosted inference.
- **Minimum GREEN:** Regenerate app-client OpenAPI/Swift, update route policy, test discovery lists, guides, runbook, model inventory and index documentation; consolidate one backend classifier/policy/request module and one Mac coordinator after all behavioral tests remain GREEN. Register no speculative Firestore index.
- **Retained protection:** Six support routes/case lookup, recursive account deletion, app-client classify route, GPT-5.1 workload, listen protocol, all unrelated generated methods, and no Windows changes.
- **Authority before/after:** No ownership change; this cycle proves and simplifies the final boundaries.
- **Expected changes:** Route policy/OpenAPI generated Swift, fair-use docs/config/tests, component guides, optional Firestore registry only if a real compound support query proves it.
- **Focused verification:** Generation/check commands in §14, route absence, generated compile, backend account-deletion tests, Firestore manifest check, content-field denylist through serialization/support response.
- **Deletion/simplification enabled:** Removes obsolete types/helpers/fixtures and duplicate adapters made unreachable by Cycles 1-10.
- **Stop condition:** Generator changes Windows, protected support lookup loses its required query/index, content can enter an extra-allow model, or simplification broadens into S-21/S-22/S-23.

### Cycle 12 — named-bundle retained-path acceptance and repository closure

- **Behavioral RED:** The `omi-wave3-s20` bundle against an owned local backend and non-production test account cannot yet demonstrate: local-GRDB evidence with one bounded GPT-5.1 request, owner-safe replay, no durable cloud content copy, content-free backend event, exact three strikes/recovery/reset/manual exception, typed restricted allowance handoff, truthful no-local-STT blocked state, deleted-route 404s, and retained ambient transcript behavior.
- **Why RED now:** No integrated local-evidence/transient-classifier E2E exists.
- **Minimum GREEN:** Add only stable semantic automation/actions needed by the registered fair-use E2E flow, run the real named-bundle path, fix integration defects, and remove remaining transitional code after evidence passes. Automation output is content-redacted and calls production coordinators.
- **Retained protection:** All S-20 invariants plus ordinary local/cloud ambient capture, freemium limit, account switch, relaunch, notification/support, and no PTT/model-portfolio changes.
- **Authority before/after:** Final proof only; local evidence/transient GPT-5.1/backend enforcement split is unchanged.
- **Expected changes:** Existing E2E flow registry/bridge/tests only if needed and component docs/evidence in PR; no ad-hoc dead script or production resource.
- **Focused verification:** §14 suites/preflight and §15 named-bundle matrix, logs/network inspection, residue searches, `git diff --check`.
- **Deletion/simplification enabled:** Removes final temporary diagnostics/old hosted-evidence path; closes repository S-20 once GPT-5.1 parity and privacy evidence pass.
- **Stop condition:** GPT-5.1 parity cannot be proved, a test needs production Omi resources/apps, request content appears in durable backend state/logs/automation, or any retained adjacent path regresses.

## 12. Cross-slice ownership and handoffs

| Slice | S-20 consumes/hands off | Owner rule |
|---|---|---|
| S-10 | Consumes `TranscriptionStorage`, owner-scoped `omi.db`, local conversation query and owner authorization. | S-20 adds a narrow evidence projection; it does not recreate cloud Conversation authority, broad category/source UI, search, finalization, or sync. |
| S-16 | Consumes immutable transient `/v4/listen`, typed event delivery, actual speech metering and no durable conversation owner. | S-20 adds two content-free event types and enforcement reads; it does not restore listen persistence/lifecycle fields. |
| S-18 | Consumes one normalized `PlanType.bounded|unlimited` property and retained Free/paid cleanup seam. | S-20 never reconstructs catalog/plan names, activates Dodo, changes quota, or adds transactions. |
| S-19 | May concurrently touch `AppState`, local owners and PTT surfaces. | S-20 owns ambient listen fair-use only. It must not change PTT/realtime lifecycle, tools, providers, prompts, usage or UI. Rebase shared AppState edits deliberately. |
| S-21 | Executes after S-20 and consumes absence of fair-use Settings route/card plus truthful notification/support path. | S-20 removes false Settings direction/domain route; S-21 owns shell convergence and must not redesign fair-use state. |
| S-22 | Owns general retained managed-model inventory/gateway deletion. | S-20 owns the fair-use classifier contract and requires direct OpenAI GPT-5.1 transient compute. S-22 removes generic gateway residue without changing/deleting that workload. Shared model config/docs require rebase. |
| S-23 | Executes only after S-20/S-22; owns rejected hosted products, including wider FCM/product-data deletion. | S-20 retains notification behavior and content-free state/events, and hands off proof that no hosted conversation evidence remains. S-23 may remove shared notification transport only under its own retained-notification decision. |
| S-25/S-26/S-27 | Later service/backend/deployment collapse. | S-20 edits repository application/listen config only; no service/GKE/Redis/Firestore live deletion. It hands off final namespaces, route, state collections, and runtime ownership. |
| S-28/S-30/S-31 | Later storage namespace, whole-product copy/legal truth, and final E2E. | S-20 uses current owner DB/bundle naming and exact approved support copy; later slices may rename/migrate without changing policy. |

Shared files with conflict risk: `backend/utils/fair_use.py`, listen runtime/contracts/receiver, fair-use router/models/database, `backend/main.py`, model config/inventory/architecture, listen charts, route policy/OpenAPI/generated Swift, `TranscriptionService.swift`, `AppState+ListenEvents.swift`, `AppState+Transcription.swift`, `STTSessionState.swift`, local conversation schema/storage/authorization, `DesktopDiagnosticsManager.swift`, automation bridge/E2E registry, and component guides.

At implementation start and before each shared-file commit, compare the target branch and preserve landed owners. Never resolve a conflict by adding a parallel endpoint, second entitlement mapping, duplicate owner token, alternate/fallback classifier, compatibility model, or ignored legacy field.

## 13. Repository residue-search strategy

Run before edits, after the owning cycle, and at final closure. Review every hit; comments in this plan, requirements history, and changelog history are evidence, not executable residue. These are labelled **static tripwires**, not behavioral tests.

```bash
# Hosted evidence/durable-content residue; the GPT-5.1 classifier itself is retained
rg -n 'database\.conversations|get_conversations\(|ClassifierEvidence|selected_evidence|reasoning' \
  backend/utils/fair_use.py backend/utils/llm/fair_use_classifier.py backend/models/fair_use.py \
  backend/database/fair_use.py backend/routers/fair_use_admin.py
rg -n "get_llm\('fair_use'\)|get_provider\('fair_use'\)|get_model\('fair_use'\)|FAIR_USE_CLASSIFIER_MODEL|FAIR_USE_CLASSIFIER_LOOKBACK_DAYS" backend
rg -n 'database\.conversations|conversation_id|title|overview|reasoning|ClassifierEvidence' \
  backend/utils/fair_use.py backend/utils/llm backend/models/fair_use.py backend/database/fair_use.py backend/routers/fair_use_admin.py

# Removed routes and generated operations
rg -n '/v1/fair-use/status|/v1/fair-use/case/.*/status|getMyFairUseStatus|getPublicCaseStatus' \
  backend desktop/macos docs .github
rg -n 'fair-use' backend/route_policy_legacy_missing_routes.txt docs/api-reference/app-client-openapi.json \
  desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift

# Retained route/state/operational controls must still have callers and tests
rg -n '/v1/admin/fair-use|X-Admin-Key|fair_use_state|fair_use_events|case_ref' backend
rg -n 'FAIR_USE_(ENABLED|KILL_SWITCH|EXEMPT_UIDS|DAILY_SPEECH_MS|3DAY_SPEECH_MS|WEEKLY_SPEECH_MS|CLASSIFIER_ABUSE_SCORE_THRESHOLD|CLASSIFIER_COOLDOWN_SECONDS|CHECK_INTERVAL_SECONDS|RESTRICT_DAILY_MANAGED_STT_MS)' \
  backend
rg -n 'free_exhausted|clear_fair_use_on_upgrade|MAX_DAILY_AUDIO_MS' backend

# Mac privacy/authority and protocol
rg -n 'fair_use_review_requested|fair_use_managed_cloud_exhausted|FairUseEvidence|FairUseReview' \
  desktop/macos backend
rg -n 'RuntimeOwnerAuthorizationSnapshot|LocalMutationAuthorization|isAuthorizationCurrent' \
  desktop/macos/Desktop/Sources

# Legacy branding/false claims in executable fair-use surfaces
rg -n 'team@basedhardware\.com|Settings > Plan & Usage|Transcription Quality Reduced|quality has been temporarily reduced|On-device transcription continues normally' \
  backend desktop/macos
```

Final interpretation:

- Any hosted conversation evidence read/copy, content field in durable backend event/support serialization, request-content logging, alternate model call, or removed route/generated method blocks closure.
- The explicit `openai/gpt-5.1` fair-use call, unchanged prompt/recipes/parser, bounded classify request DTO, and local evidence projection are required retained hits. `FAIR_USE_CLASSIFIER_MODEL` and server-side lookback selection are obsolete after the exact route/window are pinned. Tests must prove request content is transient and absent from backend state/logging.
- General Conversation titles/overviews, unrelated `reason` fields, historical docs/changelogs, and the text of this plan are reviewed allowlisted hits, not blindly deleted.
- All six protected routes, state/events, case reference, retained enforcement config, Free cleanup, and partial overrides must remain.
- No Windows source/generated/lock artifact is changed.

## 14. Focused and component-level verification commands

Use the repository-supported runners. Exact new test names may be adjusted to match the final package, but the PR must record the discovered production-seam tests rather than claiming nonexistent commands passed.

### Fast backend loop

```bash
cd desktop/macos
./scripts/dev-feedback.py --once python 'tests/unit/test_fair_use_engine.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_fair_use_plan_aware.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_fair_use_free_tier.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_fair_use_upgrade.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_fair_use_review_requests.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_fair_use_classify_requests.py'
./scripts/dev-feedback.py --once python 'tests/integration/test_fair_use_api.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_listen_session_bootstrap.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_listen_transient_contract.py'
```

### Fast macOS loop

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'FairUseEvidenceLocalAuthorityTests'
./scripts/dev-feedback.py --once swift 'FairUseReviewCoordinatorTests'
./scripts/dev-feedback.py --once swift 'FairUseRestrictedHandoffTests'
./scripts/dev-feedback.py --once swift 'ListenProtocolTests'
./scripts/dev-feedback.py --once swift 'ConversationLocalQueryTests'
./scripts/dev-feedback.py --once swift 'RuntimeOwnerIdentityTests'
./scripts/dev-feedback.py --once swift 'LocalMutationAuthorizationTests'
./scripts/dev-feedback.py --once swift 'EffectiveOwnerDatabaseBoundaryTests'
```

Tests must drive production public seams with injected model/clock/Redis/Firestore/network boundaries. No live service, sleep, order dependence, source-string state-machine assertion, or real customer data belongs in CI. Golden prompt/wire snapshots are contract fixtures backed by the ledger and current classifier; they complement, not replace, behavioral adapter tests.

### Route policy, OpenAPI, generated Swift, and Firestore manifest

```bash
python3 backend/scripts/check_route_policy_baseline.py --base-ref origin/main
backend/scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
backend/scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
backend/scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
backend/scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
python3 backend/scripts/generate_firestore_indexes.py
```

Use `--write` for `generate_firestore_indexes.py` only if Cycle 8 proves a required registry change. Do not generate or edit Windows clients.

### Component and repository gates

```bash
(cd backend && bash test.sh)
(cd desktop/macos && ./test.sh)
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
make preflight
scripts/pr-preflight --suggest
```

Before a `fix:` PR body, follow the repository failure-class declaration/validation contract. Run `scripts/pr-preflight --pr-body-file /tmp/pr-body.md` against the drafted body. Record real commands/results in commit/PR evidence. Do not open/push/merge without the authorization rules in `AGENTS.md`.

## 15. Real named-bundle and retained user-path acceptance

Use only the disposable named development bundle. Never launch, stop, restart, overwrite, or inspect state by mutating `/Applications/Omi.app`, `/Applications/Omi Beta.app`, `com.omi.computer-macos`, or `com.omi.computer-macos.beta`.

```bash
cd desktop/macos
OMI_APP_NAME=omi-wave3-s20 OMI_SKIP_TUNNEL=1 ./run.sh
./scripts/omi-ctl health
./scripts/omi-ctl log-path
```

The local backend uses owned development Firebase/Redis/Firestore substitutes or an explicitly owned development account, never production. Use test-only threshold/time seams or seeded local state so acceptance does not wait hours/days; the production helpers must still be exercised and the exact real constants separately asserted.

Required named-bundle matrix:

1. Seed more than 30 owner-local conversations spanning the seven-day boundary and confirm the backend GPT-5.1 request receives only the correct newest 30 bounded fields from GRDB and no canonical local IDs.
2. Exercise at least one legitimate power-user fixture and each retained abuse recipe through the retained GPT-5.1 seam; prove the exact prompt/recipe/output/parser behavior against the characterized baseline.
3. Cross bounded and unlimited soft caps through the local backend and observe one typed request per 12-hour window; no request under cap or for partial override cases where current behavior bypasses.
4. Confirm a completed review creates no local classifier-result record and exactly one content-free backend event/case; inspect the bounded serialized request and Redis/Firestore substitute, support response, logs, analytics and crash breadcrumbs to prove content is transient only.
5. Disconnect before classification acknowledgement, relaunch, and prove same-owner replay/retry is idempotent. Expiry yields no backend event; local evidence-read failure yields no submit; GPT failure follows the existing fail-open result.
6. Switch A -> B during evidence read, token refresh, POST, response, telemetry and UI publication. Repeat sign-out/sign-in for the same UID. No stale evidence is submitted under another owner and no late response publishes locally.
7. Produce low-score, first/second/third positive, support reset, post-reset positive, event resolve, automatic seven-day final-warning expiry, automatic 30-day restrict expiry/recovery, and raw manual timerless override. Verify exact state/count/history.
8. Exhaust the 30-minute UTC-day managed-cloud allowance using a clock/budget seam. Verify one typed event, stable websocket, no further paid audio, same-conversation local Parakeet continuation when usable, and truthful blocked state when forced unavailable.
9. Verify warning/final-warning/restrict notifications show approved stage/timer/allowance, random case code, and support destination, with no Settings/quality/Omi/BasedHardware/guaranteed-local claim.
10. Call all six protected support operations with valid/invalid keys. Confirm public and signed-in removed routes return genuine 404 and no generated caller exists.
11. Exhaust Free quota and prove both normal freemium UI/stop behavior and server synthetic fair-use event; then exercise paid-upgrade cleanup without enabling Dodo or granting a transaction.
12. Capture ordinary local ambient transcription, forced cloud ambient transcription, cloud provider failure fallback, stop/finalize/relaunch, and conversation list/detail to prove S-10/S-16 behavior remains. PTT/realtime is smoke-tested only for non-regression, not redesigned.

Add one `fair-use-local-enforcement.yaml` flow and redacted semantic automation actions only if they are registered in the existing E2E lane and invoke the production coordinator/state. A read action may expose request ID, status, score band, coarse type, stage, timer and case code; it must never expose a title, overview, local conversation ID, detailed reason, prompt, token, UID, or raw audio.

## 16. Repository closure versus separately authorized live operational closure

### Repository closure

S-20 repository closure requires all 12 cycles GREEN, Gate 0 GPT-5.1 parity evidence, focused/component/preflight checks, named-bundle acceptance, fresh generated contracts, content-free durable backend serialization, deleted-route 404s, and reviewed residue searches. It may modify repository code/config for the retained runtime but does not deploy it.

Repository closure specifically retains:

- Firestore `users/{uid}/fair_use_state/current` and content-free `fair_use_events`;
- Redis speech meters, cooldown/request state, stage cache and restricted daily budget;
- case reference support query/index actually required by retained admin lookup;
- six protected API operations and account-deletion enumeration;
- fair-use enabled/kill switch/exempt/threshold/cooldown/check/budget environment controls;
- the explicit OpenAI GPT-5.1 fair-use compute route and exact prompt/recipes/parser/output contract;
- canonical backend/listen service topology until later slices.

### Separately authorized live closure

No repository change authorizes reading or mutating live Firestore, Redis, Firebase, GCP, notifications, secrets, service accounts, images, charts/releases, Dodo, or customer accounts. A later operator must first perform a read-only inventory with verified project/environment identifiers and classify each resource as retained, rejected, shared, unknown, or absent.

Any authorized deployment/live validation must separately document:

1. backup/rollback and retention/legal boundaries for existing fair-use documents;
2. schema compatibility for content-free events in an unreleased fork, with no invented customer backfill;
3. Redis request/cooldown rollover and rollback behavior;
4. retained GPT-5.1 route/model/prompt parity and timeout/fail-open evidence;
5. retained Firestore queries/index readiness and protected admin access;
6. sanitized notifications/logs/metrics and zero private evidence;
7. staged development then production evidence with explicit authorization;
8. no live resource deletion until S-23/S-25/S-27 owns and authorizes it.

`BILLING_MODE=disabled` stays disabled throughout. No provider transaction or entitlement grant is part of operational fair-use closure.

## 17. Risks, ambiguities, and explicit stop points

| Risk or missing input | Affected cycles | Safe work that can proceed | Evidence required to reopen / owner |
|---|---|---|---|
| GPT-5.1/prompt/recipe/output drift during transport refactor | 1, 5, 10, 12 | Evidence projection and backend state work | Characterization fixtures prove byte-for-byte prompt and behavioral parity; S-20 owner |
| Canonical conversation category/source projection is not truthful | 1-2, 4, 10, 12 | Date/limit/title/overview/duration read and backend work | Gate 0B migration/projection evidence or changed decision; Conversation/requirements owner |
| Notification edits expand beyond required truth/rebrand correction | 8, 12 | Route deletion and current-copy characterization | `support@heyintentive.com` plus IR-614/IR-701 semantic assertions; product/brand owner |
| Client-supplied evidence can be tampered with | 3-5, 9 | Strict auth, bounds, request binding, backend model/policy, 30-hour ceiling | Accepted local-authority trust model; do not invent attestation or a second classifier |
| GPT-5.1 is unavailable or times out | 1, 5, 12 | Server ceiling and all non-classifier enforcement | Preserve the current fail-open result and fallback telemetry; no local/alternate model |
| Cross-process idempotent event/state transaction | 5 | Model/DTO/request tests | Transactional receipt/event/state design proves duplicate and failure behavior; backend owner |
| Restriction handoff could split/finalize a conversation | 7 | Backend typed event/once tests | Same-session ID/authorization and restart-free local engine proof; desktop owner |
| FCM is later rejected by S-23 while notification behavior is retained now | 8, 11 | Preserve current notification call and content-free payload | S-23 provides replacement/deletion decision; S-20 must not pre-delete transport |
| Firestore registry does not declare named fair-use queries | 8, 11 | Preserve current queries and generated manifest | Emulator/documented query proof of a composite requirement; add only with real caller, otherwise no speculative index |
| S-19/S-22 concurrent shared-file drift | all shared files | Rebase and refresh inventories | Integrated owner seams and passing adjacent tests; no duplicate adapter |
| Dodo final activation absent | 3, 9, 12 | Consume normalized disabled entitlement | Not an S-20 stop; no transactions or catalog decisions allowed |
| Existing live fair-use data/resource state unknown | operational only | Repository implementation and hermetic tests | Verified read-only inventory plus explicit mutation/deploy authorization |

Any bounded evidence observation outside the single authenticated in-memory GPT-5.1 request, or any durable/logged content copy, is a hard stop. Any requirement conflict is recorded and escalated; no implementation picks a preferred source silently.

## 18. Final completion checklist

- [ ] `711269ba` remains an ancestor after execution-time rebase; exact target diff and refreshed inventory are recorded.
- [ ] The requirements validator passes and every detailed IR-610..615/IR-700..709 decision is mapped to behavioral evidence.
- [ ] Gate 0A preserves explicit GPT-5.1 plus the byte-for-byte current prompt, recipes, output/parser, timeout/error handling, and fail-open behavior; no on-device/alternate model exists.
- [ ] Gate 0B projects category/source truthfully without restoring deleted broad Conversation metadata or product UI.
- [ ] Gate 0C uses `support@heyintentive.com` and changes only the legacy/false wording required by IR-614/IR-701.
- [ ] Local evidence uses at most 30 newest seven-day conversations and exact title/overview/category/duration/source/time recipe.
- [ ] One authorization snapshot fences local read, token acquisition, bounded upload, telemetry and UI, including same-UID reauth.
- [ ] Backend pending-review replay and classify retry are bounded/idempotent; local read and classifier failures preserve current no-phantom/fail-open behavior.
- [ ] The classify request permits only bounded title/overview/category/duration/source/time plus opaque request-local tokens; transcript/audio/screenshot/name/canonical local ID/server policy fields are forbidden, and all durable logs/metrics/support/event state remain content-free.
- [ ] Backend derives UID, usage, thresholds, entitlement, stages/actions/timers/timestamps and case reference; request ownership/expiry/idempotency fail closed.
- [ ] Only score >=0.7 after latest reset counts; low/pre-reset events remain history; event/state commit is race-safe.
- [ ] Automatic restrict -> seven-day final warning -> warning recovery is authoritative for every enforcement consumer.
- [ ] Manual set-stage remains raw and timerless stages remain until manual change/reset; only manual none clears timers.
- [ ] Exact bounded/unlimited bands, 12-hour cooldown, Free synthetic score/normal quota, paid cleanup, 30-hour ceiling and partial kill/exempt behavior pass.
- [ ] Restricted 1,800,000 ms UTC-day allowance emits one typed event, keeps socket stable, and produces same-conversation local handoff or truthful blocked state.
- [ ] Notifications retain case/support path with truthful stage/timer/allowance and no quality/Settings/legacy/guaranteed-local claim.
- [ ] Six `X-Admin-Key` operations pass; public and signed-in status GETs are absent; case lookup/index remains.
- [ ] Content-free history has no TTL/cap/job and recursive backend account deletion removes the user subtree.
- [ ] Hosted conversation query/import and durable content fields are gone; the explicit pinned GPT-5.1 classifier, prompt/recipes/parser, usage tracking, and enforcement config remain, while obsolete model/lookback selectors are absent.
- [ ] OpenAPI, route policy and generated Swift are fresh; no Windows artifact changed.
- [ ] Focused Python/Swift tests, backend suite, desktop suite, Firestore manifest check, residue review, ledger validator, `git diff --check`, `make preflight`, and PR preflight pass.
- [ ] Named bundle `omi-wave3-s20` passes the full local-evidence/transient-GPT-5.1/privacy/state/handoff/owner/restart/adjacent-path matrix without touching production apps.
- [ ] Repository closure and separately authorized live inventory/deploy/resource closure are reported separately.
- [ ] `BILLING_MODE=disabled` stayed disabled; no Dodo call, paid grant, external mutation, commit, push, PR, merge, or deploy was smuggled into planning or implementation.
