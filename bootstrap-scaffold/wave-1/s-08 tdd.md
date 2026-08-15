# S-08 TDD Plan — Re-own account identity without weakening lifecycle, deletion, or export

Status: **config-independent Wave 1 repository tranche implemented on 2026-08-15; the released-client transition for Cycles 2-3 is recorded, the locked macOS session blocked the final live acquisition click, and owned-identity/auth-invariant gates plus later cycles remain dependency-gated**
Slice: **S-08**
Wave: **1**
Authorizing and protecting decisions: **IR-006, IR-120, IR-124, IR-170 through IR-190, IR-830, IR-868, IR-877, IR-878**
Roadmap entry: [`deletion-map.md`](../deletion-map.md), section **S-08 — Re-own Firebase identity and narrow account lifecycle/data export**
Primary requirement source: [`requirements-challenge.md`](../requirements-challenge.md) lines 5189-6223, 18118-18140, 18720-18889, 19282-19535, and 19987-20069
Research note: the source-grounded findings are incorporated into this tracked plan; no gitignored `.context` note is required for implementation
Fixed review point: **`origin/main`**

Postcondition: Apple and Google sign-in use our Firebase/OAuth control plane with the existing fail-closed Mac session lifecycle intact; Firestore contains only retained account-control data; account deletion remains durably queued, idempotent, retryable, and scoped to retained cloud account data; the Mac can write a complete offline export from the final local authorities; and the server export contains genuine account metadata rather than private Mac product content.

## How to execute this plan

Start with **`engineering:implement`** using this file as the spec. Revalidate the active public seam against the authorizing decisions and check only the gate named by that cycle. Keep the S-08 boundary intact, use the `engineering:tdd` red-to-green discipline at the named seams, and commit each independently green behavior on the current branch. Do not rename the branch, push, open a PR, deploy, or merge without the separate authorization required by the repository guide.

Use **`engineering:codebase-design`** during intake only if source discovery forces a change to one of the public seams below. Apply it to keep authentication, deletion orchestration, account-metadata export, and local-product export as deep modules with small interfaces; do not use it to create speculative adapters or compatibility shells.

At the end, use **`engineering:code-review`** against **`origin/main`**. Its Standards axis must use the root, backend, desktop, and `.github` `AGENTS.md` files; its Spec axis must use this plan plus the authorizing IR sections above. Fix every accepted finding, rerun the affected verification, and repeat the review if the diff changed materially.

## Adopted delivery boundary and cycle-local gates

The original roadmap said S-08 depended on no other slice. The live deletion map
now adopts a narrow early tranche and assigns the later closure dependencies
explicitly; complete S-08 closure still waits for those named dependencies.

| Gate | Evidence and consequence | Unblocks when |
|---|---|---|
| **G1 — owned identity inputs** | Production-family Firebase and backend workflow configuration still names `based-hardware`; the desktop auth guide still names Apple Services ID `me.omi.web`; the Mac plists, backend OAuth, service-account signer, provider callbacks, and release probe must move as one environment-consistent identity. Guessing project IDs, OAuth redirect URIs, signer emails, API keys, or secrets would create an unauthenticatable app. | Environment-owned development and production Firebase project IDs/numbers, Mac Firebase plist values for each bundle family, Google OAuth clients, Apple Services ID/team/key, callback URLs, Firebase Admin/runtime identities, and intended backend hosts are available from their owned configuration sources. Secrets stay in the environment and never enter this file or Git. |
| **G2 — complete local export authorities** | `ConversationRepository`, `MemoryStorage`, `TasksStore`/`ActionItemStorage`, `GoalStorage`, and Focus/Insight stores still reconcile with remote owners or incomplete caches. Exporting them now can silently omit data, which violates IR-830. | S-10, S-11, S-12, S-13, and S-14 have closed their local-authority contracts. S-14 transitively carries its S-15 dependency. Each owner exposes or confirms a complete owner-scoped read interface. |
| **G3 — safe deletion-worker narrowing** | `account_deletion.py` still purges Twilio, Pinecone, cloud recordings, canonical memory derivatives, and Stripe because those systems can still hold live user data. Removing those cleanup steps before their writers/data are retired would make Delete Account incomplete. | S-18 has installed the retained Dodo cancellation seam and S-23/S-24 have removed the rejected hosted products, object data, and vector data, with migration/deletion evidence. |
| **G4 — queue/service topology** | The account-deletion task currently targets `backend-sync`, shares stale `SYNC_TASKS_*` identity, assumes the queue already exists, and deploys in the current `us-central1` stack. IR-120/868/877 require the canonical backend, a dedicated signer, explicit queue shape, and the future `us-west1` owned platform. | S-25 has established the canonical service target and S-27 has established the owned development/production Cloud Run, IAM, region, and queue foundation. |
| **G5 — delivery boundary** | One atomic S-08 PR cannot safely land in Wave 1 while G2-G4 remain open. Making S-08 depend on S-23 would create a roadmap cycle because S-23 already depends on S-08. | **Resolved:** deliver the narrow tranche below; retain Cycles 6-9 as dependency-gated acceptance contracts with their named owners. Do not create S-08A/S-08B slices or extra TDD plans. |
| **G6 — invariant and released-API authority** | The live desktop tests refer to `INV-AUTH-1`, but the authoritative `docs/product/invariants/auth-session.md` is absent in this checkout. The released-client half is resolved for Cycles 2-3: `/v1/users/onboarding` is deliberately removed with its retained Mac caller in the same release, so an old client receives 404 rather than a compatibility shell; account deletion is bodyless, while arbitrary legacy JSON remains accepted and ignored by the retained endpoint. | Restore or deliberately replace the authoritative auth invariant before Cycle 4. The released-client/API transition no longer gates Cycles 2-3. Run `scripts/pr-preflight --suggest` against the intended diff before RED. |

## Adopted roadmap repair

The deletion map adopts a narrow Wave 1 S-08 delivery rather than blocking the
wave on later infrastructure and local-authority slices. S-08 owns:

1. behavioral fences for the retained Mac authentication/session/sign-out contract;
2. owned Firebase/Apple/Google/backend configuration once G1 is supplied;
3. removal of the backend acquisition-source mirror while keeping local + bounded analytics behavior;
4. removal of unused account-deletion reason fields without changing durable execution; and
5. an explicit retained deletion-orchestration boundary and documented account-metadata allowlist for downstream owners.

The remaining closure work stays with its actual owner: S-10 through S-14 expose
complete export readers; S-18 installs Dodo cancellation; S-23/S-24 remove
rejected writers, data, and their cleanup; S-25 retargets the task to the
canonical backend; and S-27 provisions and validates the owned `us-west1`
queue/signer/platform. Those slices must satisfy the S-08 handoff seams recorded
here. S-08 retains final export composition and acceptance after its reader
dependencies close.

The narrow tranche leaves current product-data export, provider cleanup, queue
target, and legacy task-drain compatibility intact until their named dependency
gates close.

## Decision classification

| Action | Exact behavior and source boundary |
|---|---|
| **KEEP AS IS** | Both **Continue with Apple** and **Continue with Google**, the hosted browser/backend/Redis OAuth exchange, state + PKCE, loopback callback with custom-scheme fallback, one-time Firebase custom-token exchange, duplicate-start lock, Cancel, timeout, inline sanitized errors, blocking launch restore, recoverable session screen, fail-closed foreground refresh, both one-click Sign Out entrances, current capture-stop ordering, unsent-draft clearing, PostHog/Sentry detach calls, Delete Account confirmation/loading/error UI, immediate ordinary Sign Out after durable deletion acceptance, **no owner-local data wipe**, the unreachable native Apple alternative and its entitlement/support test, the fixed 1.4-second reveal and 0.5-second transition, the sign-in copy layout, and indefinite completed deletion tombstones. These are explicit IR-170-through-190 regression fences even where the implementation looks redundant or the copy is surprising. |
| **ADAPT** | Replace Omi Firebase/Apple/Google/backend/Redis identity with environment-owned identity without redesigning auth; narrow Firestore to account mapping, entitlement/subscription, quota/usage, and deletion-job state; give account-deletion Cloud Tasks truthful dedicated configuration and the canonical backend target; expose one local, owner-scoped Export My Data flow; narrow the server export to retained account metadata. |
| **DELETE** | The additional backend onboarding write and its unused GET/PATCH routes, Firestore onboarding helpers/fields, generated bindings, exclusive tests/docs; `reason` and `reason_details` from the delete-account request/service/storage contract; old server export readers for cloud conversations, memories, people, action items, and chat; after G3, Twilio/Pinecone/cloud-recording/canonical-memory deletion-only dependencies; after the verified queue drain, account-deletion use of stale sync identity and the legacy UID/audience branch tracked by `#9760`. |
| **SIMPLIFY / OPTIMIZE AFTER** | Only after all green cycles: keep one deep account-deletion module behind request/worker interfaces, remove deletion-only counters and result fields for retired purges, keep one explicit account metadata exporter, remove obsolete imports/models/tests/config/docs, and delete compatibility code whose live producer and retry window are proven gone. Do not refactor the AuthService state machine or local domain stores as S-08 cleanup. |
| **ACCELERATE AFTER** | `none` until cycle timing is measured. Record focused test, named-bundle build, local backend, and dev-cloud proof times. Improve only a verified S-08 bottleneck within touched tooling. |
| **AUTOMATE LAST** | Extend existing runtime-env, production-routing, release-probe, route-policy, OpenAPI, and workflow-contract checks only after the owned identity and queue shape work manually. Automation must run in an existing local and CI lane; do not add an orphan script or scheduled job. |
| **OUT OF SCOPE / DEFERRED** | Dodo product/API mapping and Stripe removal (S-18); telemetry project/consent policy (S-09); onboarding screens/permissions (S-17); local-authority migrations (S-10 through S-15); rejected hosted product and data-store teardown (S-23/S-24); backend service collapse (S-25/S-26); the `us-west1` platform migration and production deployment (S-27); bundle/storage namespace migration (S-28); release/signing/public-site ownership (S-29); rebrand and sign-in copy rewrite (S-30); new auth providers, guest/password accounts, direct-provider auth redesign, native-Apple removal, local data deletion on account deletion, polling for wipe completion, tombstone TTL, a dead-letter queue, and Windows. |

## Requirement guard ledger

| Decisions | Required outcome in S-08 |
|---|---|
| IR-006 | Keep Firebase account/entitlement/quota architecture. Re-own identity only. Dodo replacement remains S-18. |
| IR-120 | Keep durable intent, opaque job ID, OIDC task, run lock, retries, terminal-attempt handling, reconciliation, timeout, and telemetry; eventually point the task to the canonical main backend. |
| IR-124 | Keep the acquisition answer in local storage and bounded analytics; remove the backend onboarding record only. Do not touch the `/v4/listen` `OnboardingHandler`. |
| IR-170-176 | Preserve visible provider choices and all hosted OAuth UX/security/recovery behavior. Keep the native Apple alternative despite its lack of a caller. Rebrand copy later. |
| IR-177-183 | Preserve blocking restore, recoverable invalidation, foreground validation, both sign-out entries, capture behavior, draft clearing, and telemetry detach. |
| IR-184-190 | Preserve confirmation, no local wipe, narrowed server cleanup, no feedback fields, minimal Firestore control plane, immediate sign-out, and indefinite completed tombstones. |
| IR-830 | Add complete owner-local product export; the backend must not claim authority for local content. |
| IR-868 | Use a dedicated least-privilege account-deletion task signer per environment with exact email/audience verification; do not reuse runtime or GitHub deploy identity. |
| IR-877 | Provision one `account-deletion` queue per environment: concurrency 1, attempts 5, dispatch deadline 1,500 seconds, stable canonical handler URL, exact signer/audience, and live shape validation. |
| IR-878 | Keep Firestore failure state and the five-minute transactional reconciler; no dead-letter queue or second worker. |

## Current codeflow and ownership

### 1. Hosted Firebase sign-in and Mac session lifecycle

```text
SignInView
  -> AuthService.signInWithApple / signInWithGoogle
  -> local OAuthLoopbackCallbackServer + state + PKCE
  -> GET backend /v1/auth/authorize
  -> Redis five-minute authorization session
  -> Apple or Google callback
  -> one-time backend /v1/auth/token exchange
  -> Firebase custom token
  -> Mac Firebase/REST token exchange
  -> AuthState authenticated owner

launch / foreground
  -> saved-session hint
  -> forced refresh through AuthSessionCoordinator single flight
  -> authenticated OR recoveryRequired (never optimistic owner UI)

explicit sign out
  -> stop the entrance-specific active work
  -> clear drafts / detach telemetry identity
  -> invalidate owner-scoped projections
  -> retain ordinary owner-local product data
```

Primary owners:

- `desktop/macos/Desktop/Sources/SignInView.swift:5-190`
- `desktop/macos/Desktop/Sources/AuthService.swift:278-678,681-1165,1300-1501,2150-2380,2468-2525`
- `desktop/macos/Desktop/Sources/AuthSessionCoordinator.swift`
- `desktop/macos/Desktop/Sources/OmiApp.swift`
- `backend/routers/auth.py:60-214,286-704`
- `backend/database/redis_db.py` authorization-session/code helpers
- `desktop/macos/Desktop/Sources/GoogleService-Info-Dev.plist`
- `desktop/macos/Desktop/Sources/GoogleService-Info-Local.plist`
- `backend/deploy/runtime_env.yaml`, backend environment templates, `codemagic.yaml`, and desktop/backend deploy workflows

Existing behavioral fences include `AuthSessionCoordinatorTests`, `AuthSessionAttemptFenceTests`, `AuthRefreshResilienceTests`, `AuthTokenStorageTests`, `AuthStorageCanaryTests`, `OAuthLoopbackCallbackServerTests`, `SignOutStorageInvalidationTests`, backend auth redirect/PKCE/token tests, and the Firebase release-probe tests. Preserve and run them; do not replace them with source-string checks.

### 2. Redundant backend onboarding record

```text
user chooses "How did you hear?"
  -> UserDefaults onboardingHowDidYouHearSource
  -> AnalyticsManager.onboardingHowDidYouHear
  -> APIClient.updateOnboardingAcquisitionSource
  -> PATCH /v1/users/onboarding
  -> users/{uid}.onboarding.acquisition_source
```

Owners are `OnboardingHowDidYouHearStepView.swift`, `SBOnboardingModel.swift:511-519`, `APIClient+Settings.swift:77-98`, `backend/routers/users.py:558-587`, and `backend/database/users.py:1434-1448`. `OnboardingAcquisitionSourceTests.swift` currently protects the backend write; replace it with a behavioral test of the retained local + analytics outcome. The similarly named `/v4/listen` questionnaire handler is not this record.

### 3. Durable account deletion

```text
Account Settings -> Delete Account & Data -> confirm
  -> APIClient.deleteAccount (bodyless request)
  -> DELETE /v1/users/delete-account
  -> start_account_deletion
  -> account_deletions/{uid}: deleting_auth + opaque wipe_job_id
  -> transactionally promote to pending
  -> Cloud Tasks account-deletion queue
  -> OIDC POST /v1/users/account-deletion-wipes/run
  -> resolve opaque job id + Redis run lock + Firestore claim
  -> billing cancellation
  -> Firebase Auth deletion
  -> rejected-product purge dependencies
  -> recursive retained Firestore account deletion
  -> completed tombstone

failure
  -> failed/terminal marker
  -> queue retry or five-minute transactional reconciler
  -> re-enqueue with the same durable authority
```

Primary owners are `SettingsContentView+AccountBilling.swift`, `APIClient+Settings.swift`, `backend/routers/users.py:315-424`, `backend/services/users/account_deletion.py`, `backend/database/users.py:301-752,1167-1219`, `backend/utils/cloud_tasks.py`, `backend/main.py:240-282`, `backend/deploy/runtime_env.yaml`, and `.github/workflows/gcp_backend.yml`.

The current worker still imports Stripe, Twilio, Pinecone, cloud recordings, and canonical cloud-memory cleanup. The workflow resolves the account-deletion handler from `backend-sync`, reuses `SYNC_TASKS_INVOKER_SA`, provisions only the conversation-finalization queue, and runs the current stack in `us-central1`. These are real dependencies, not residue that Wave 1 may delete optimistically.

### 4. Product-data export

```text
no current Mac Export My Data action

GET /v1/users/export
  -> iter_user_data_export(uid)
  -> cloud profile
  -> cloud conversations
  -> cloud memories
  -> cloud people
  -> cloud action items
  -> cloud chat messages
  -> streamed omi-export.json
```

Owners are `backend/routers/users.py:1893-1902`, `backend/services/users/data_export.py`, `backend/tests/services/users/test_data_export.py`, and generated client code. This response cannot represent the eventual Mac-local conversations/transcripts, memories, Tasks, Goals, kernel-journal Chat history, Focus/Insight data, or local settings.

The future local sources are currently split across `TranscriptionStorage`, `MemoryStorage`, `ActionItemStorage`/`TasksStore`, `GoalStorage`, `ProactiveStorage`/Focus/Insight stores, and the owner-bound kernel conversation journal. Their completeness contract belongs to S-10 through S-14; S-08 consumes those final interfaces rather than reaching around them into tables or UI caches.

## Module and seam design

### Preserve the existing deep auth module

`AuthService` plus `AuthSessionCoordinator` remains the module. Its interface is the complete sign-in/restore/recovery/refresh/sign-out state contract, not just method signatures. Do not introduce provider-specific public interfaces, a second token store, a second owner authority, or a new direct-Firebase path. Configuration and release validation change underneath the existing interface.

### Keep account deletion behind one interface

The external account-deletion interface remains:

- authenticated `DELETE /v1/users/delete-account` -> durable acceptance;
- OIDC-only `POST /v1/users/account-deletion-wipes/run` -> retry/ack outcome; and
- the `account_deletions/{uid}` Firestore state machine as the durable authority.

Firebase Admin, the retained billing provider, Cloud Tasks, and Firestore are true external dependencies. Tests may substitute those boundaries. Do not mock internal deletion functions or add per-call-site deletion exceptions. The request path must never perform destructive work inline in production.

### Add one local export module

After G2, add a feature-scoped module under a directory such as `Desktop/Sources/Account/Export/`, not directly under `Desktop/Sources/`. Its small interface is:

```swift
export(ownerID: String, to destination: URL) async throws -> LocalUserDataExportReceipt
```

The implementation owns completeness, deterministic schema/versioning, owner fencing, bounded-memory encoding, atomic file replacement, and cleanup of a failed partial file. It consumes the public owner-scoped read interfaces of the local domain modules and the existing kernel journal control seam. The Settings UI owns `NSSavePanel`; the export module owns bytes. Do not reuse `MemoryExportService`, which belongs to rejected connector/MCP flows.

The initial versioned JSON document contains exactly these top-level sections:

- `schema_version`, `exported_at`, and the authenticated owner identity needed to interpret the export;
- complete local conversations and transcript segments;
- complete local memories;
- complete local Tasks and Goals;
- complete owner-bound kernel Chat sessions/turns, including structured resources that are part of the journal contract;
- complete retained Focus and Insight history;
- an explicit allowlist of product preferences supplied by the final local owner modules.

Exclude Firebase refresh/ID tokens, Keychain items, customer/provider keys, service secrets, raw diagnostics/logs, telemetry identifiers, caches, sync/reconciliation flags, temporary files, and unrelated Application Support contents. Do not scan arbitrary UserDefaults or dump raw SQLite files. Attachments, Rewind screenshots/video, and other binary files are outside IR-830 unless a later reviewed requirement explicitly adds them.

The local export must work with product network access disabled. The authenticated server route remains separate and returns only genuine server-held account/control metadata; a server failure must not prevent the local export. Combining the two into one file is deferred unless a reviewed requirement explicitly expands the seam.

## Requirements-backed public seams

1. **Identity configuration seam:** for a named environment and signed artifact, Mac Firebase project, token audience, backend verifier project, Firebase Admin signer project, Apple/Google callback host, and backend URL are one consistent owned tuple. A mismatch fails before traffic/publish; no secret value is printed.
2. **Mac authentication seam:** Apple and Google each reach the same authenticated Firebase owner through the hosted flow; restore blocks owner UI until validation; transient failure reaches Retry/Sign In Again without deleting owner data; foreground refresh fails closed; explicit Sign Out clears only the already-approved session/draft/projection state.
3. **Onboarding acquisition seam:** choosing a source persists it locally and emits the bounded analytics event even when the product backend is unreachable; it performs no account-backend write.
4. **Delete-account admission seam:** a bodyless authenticated DELETE returns success only after an actionable durable marker exists. The Mac immediately performs its existing ordinary Sign Out and does not wipe owner-local data or poll the worker.
5. **Deletion-worker seam:** only an exactly authenticated task with an opaque job ID can claim work; one claim performs retained billing cancellation, Firebase Auth deletion, and retained Firestore account cleanup once; retryable failure stays visible/recoverable; completed redelivery is a no-op; the completed tombstone remains.
6. **Local export seam:** with one record seeded in each final local authority and a known kernel journal, Export My Data writes one independently specified versioned JSON file while offline. A read/write failure reports an error and leaves no partial destination.
7. **Server export seam:** authenticated `GET /v1/users/export` contains only the approved account/control metadata allowlist and never calls a product-content database reader.
8. **Queue/platform seam:** each owned environment has exactly one queue with concurrency 1, max attempts 5, 1,500-second dispatch deadline, stable canonical-backend URL, exact dedicated signer/audience, and fail-closed runtime configuration. Firestore remains the exhausted-work inventory; there is no dead-letter queue.

## Ordered vertical TDD cycles

Every cycle is one tracer bullet: write only the named failing behavioral/contract test, observe the expected failure, add the smallest production change that passes, rerun the focused file, and commit the green state. Do not write tests for later cycles in advance. Refactoring waits until the review stage.

Wave 1 uses this safe execution order when external inputs are not yet available:

1. Cycle 0 intake;
2. Cycle 1 authentication/session fences;
3. Cycle 5 retained deletion-orchestration fence;
4. Cycles 2 and 3 after the applicable G6 released-contract check;
5. Cycle 4 after G1 and G6; and
6. stop before Cycles 6-9 until their named later owners close G2-G4.

This is the sole exception to numeric cycle order. It allows independent keep
fences to land without guessing identity configuration or deleting a released
shape. Within each listed step, tracer bullets remain sequential.

### Cycle 0 — implementation intake and immutable baseline

This is a start gate, not a code cycle.

1. Invoke `engineering:implement` with this plan.
2. Run `make setup`, fetch `origin`, confirm the current branch without renaming/switching, and record `git rev-parse origin/main`.
3. Confirm the gates applicable to the active cycle, the adopted roadmap repair,
   the IR-830 ownership handoffs, and the public-seam requirements trace. If an
   applicable gate remains open, stop that cycle rather than implementing a
   partial implicit contract.
4. Run focused existing auth, onboarding, deletion, export, runtime-env, workflow, and OpenAPI tests. Record pre-existing failures separately.
5. Run `scripts/pr-preflight --suggest` after the first intended diff exists; record matched invariants and failure-class guidance. The identity guard should cite `FC-customer-data-plane-divergence` and `FC-release-probe-signer-identity` where applicable.

### Cycle 1 — CHARACTERIZE: fence the retained Mac lifecycle before configuration changes

Write one public behavior at a time at the Mac authentication seam: provider choices and attempt cancellation; blocking restore and recoverable validation failure; debounced fail-closed foreground refresh; and the exact effects of each sign-out entrance, including draft/identity cleanup and preservation of ordinary owner-local data. Exercise production state transitions and substitute only true external boundaries such as hosted OAuth, Firebase/token transport, Keychain, and analytics.

If a new test passes on the untouched baseline, record it as a characterization fence and do not invent a production change. If it fails because behavior has drifted, stop and reconcile the failure with IR-170 through IR-183 before changing production. If a controllable seam is genuinely missing, make the smallest interface-preserving extraction, rerun the focused test, and commit only when green. Do not alter native Apple, animation timing/copy, recovery semantics, sign-out timing, or local-data retention.

**Focused proof:** `AuthSessionAttemptFenceTests`, `AuthRefreshResilienceTests`, `OAuthLoopbackCallbackServerTests`, `FirebaseAuthAvailabilityTests`, sign-out/storage tests, and the new per-entry-point behavior fence.

### Cycle 2 — RED/GREEN: acquisition stays local and analytics-bounded

**Gate:** safe early checkpoint.

**RED:** Replace the current request-capture test with a behavioral test that drives the production acquisition-answer action using isolated defaults and a controlled analytics boundary. Assert the selected value is locally readable, the approved analytics event is emitted once, onboarding advances, and a URL protocol that fails on any request observes no network call.

**GREEN:** Remove `updateOnboardingAcquisitionSource` from both onboarding call sites and delete the Mac API helper. Remove backend GET/PATCH onboarding routes, request/response models, Firestore `get/set_user_onboarding_state`, route-policy/OpenAPI/generated-client entries, and exclusive tests/docs. Preserve local onboarding completion/resume, the source value, PostHog event, and the unrelated `/v4/listen` `OnboardingHandler`.

**Focused proof:** the new Swift behavior test, relevant onboarding model tests, backend route inventory/OpenAPI checks, and a named-bundle onboarding pass with the local backend unavailable at the acquisition step.

### Cycle 3 — RED/GREEN: delete unused deletion feedback without touching job state

**Gate:** safe early checkpoint.

**RED:** Through the real delete-account route with fake/strict Firestore and the strict Cloud Tasks substitute, assert a bodyless request creates/joins exactly one durable wipe authority and that the resulting `account_deletions/{uid}` record contains operational job fields but no deletion-survey fields. If a legacy arbitrary JSON body is sent, it must not create feedback state or change the durable outcome.

**GREEN:** Remove `DeleteAccountRequest.reason`, `reason_details`, service parameters/branch, and `set_user_deletion_feedback`; regenerate affected contracts instead of hand-editing generated code. Preserve the accepted response, marker schema, billing-failure state, retry queries, and completed/failed lifecycle. Check released-client OpenAPI compatibility before deleting a published request shape; if the directional compatibility gate proves it is published, stop for an explicit endpoint-version decision rather than adding a silent compatibility shell.

**Focused proof:** router, account-deletion service, strict Firestore transaction, generated contract, OpenAPI compatibility, and Mac delete-confirmation/cancel E2E tests.

### Cycle 4 — RED/GREEN: one owned identity tuple, unchanged auth behavior

**Gates:** G1 and G6.

**RED:** Extend the existing production-routing/release-probe contract with mutation cases that reject:

- an inherited or arbitrary Firebase project in any production-family Mac plist/workflow;
- a dev/prod cross-project token verifier or service-account signer;
- an Apple/Google callback or API host outside the environment's declared tuple;
- missing owned identity for either retained provider; and
- a signed-artifact Firebase project different from the backend token audience.

This is a static configuration contract alongside, not instead of, Cycle 1's production-behavior fences. It reports paths/field names and never secret values.

**GREEN:** Replace only the declared identity/configuration surfaces with supplied owned values and approved secret references. Update environment templates and component guides in the same change. Preserve `AuthService`, hosted backend OAuth, Redis exchange, native Apple fallback, PKCE/state/single-use/timeout/cancel fences, and session behavior.

**Focused proof:** mutation tests, backend OAuth/PKCE/token tests, Firebase release-probe signer tests, every Cycle 1 fence, local Auth emulator where applicable, and real Apple plus Google sign-in against the owned development project.

### Cycle 5 — RED/GREEN: make retained deletion orchestration explicit without premature cleanup

**Gate:** safe early checkpoint.

**RED:** Through admission -> queued task -> worker -> redelivery, prove opaque-job authority, exact task authentication, one claim, retry/lock fencing, durable failed/terminal state, five-minute reconciliation, completed-redelivery no-op, and indefinite tombstone retention. Make every currently required provider cleanup operation observable through strict external substitutes and prove that a required cleanup failure prevents false completion.

**GREEN:** Refactor only enough to make the durable state-machine orchestration distinct from provider-specific external cleanup composition. Keep the public DELETE/task/state interfaces unchanged, keep every still-required cleanup operation live, and avoid a generic compatibility layer or per-call-site exception. Record the explicit retained account/control metadata allowlist that later Firestore cleanup and server export must use.

**Focused proof:** account-deletion service/router tests, strict Firestore transaction tests, hermetic Cloud Tasks E2E for completion/redelivery/retry/reconciliation, and sanitized bounded telemetry checks.

### Gated Cycle 6 — RED/GREEN: prune provider cleanup only after its owners retire data

**Gate:** G3. Under the adopted roadmap repair, S-18/S-23/S-24 own this code
change and use this cycle as their acceptance contract; it is not part of the
narrow Wave 1 S-08 tranche.

**RED:** Seed retained account/control data and execute admission -> task -> worker -> redelivery using strict substitutes only for Firebase Admin and the S-18 Dodo cancellation seam. Assert cancellation and Firebase deletion occur once, retained Firestore data is removed according to the allowlist, the completed tombstone remains, and no Twilio/Pinecone/recording/canonical-memory cleanup adapter is invoked. Add the provider-failure/reconciler error path only after the core path is green.

**GREEN:** After each source owner proves its writer and historical data are gone, remove Stripe/Twilio/Pinecone/GCS/canonical-memory branches, imports, counters, secret/config bindings, tests, and docs. Preserve Firebase Auth deletion, final retained Firestore cleanup, opaque jobs, claims, locks, retry interpretation, reconciliation, and tombstones.

**Focused proof:** service/router tests, strict Firestore tests, hermetic workflow E2E, terminal/exhausted recovery, privacy/log-sanitizer checks, residue proof, and one disposable owned-development account deletion.

### Gated Cycle 7 — RED/GREEN: dedicated task identity, canonical target, and exact queue shape

**Gates:** G4 and explicit authorization for deployment-pipeline changes.

**RED:** Add hermetic runtime-env/workflow contract cases that require truthful `ACCOUNT_DELETION_TASKS_*` ownership, the canonical main-backend handler URL, a dedicated signer distinct from runtime/deploy identities, exact email/audience verification, queue concurrency 1, attempts 5, deadline 1,500 seconds, and provisioning/validation in both development and production. Add the required legacy-principal case: old audience + old UID is accepted only during the declared drain window, while old audience + new opaque job ID and new audience + old UID fail closed.

**GREEN:** Retarget the task to the canonical backend and split account-deletion signer/project/location/queue/handler/audience/max-attempt variables from sync variables. Provision-or-update the queue in the owned platform region, bind only the dedicated signer as invoker, validate live shape, and keep the handler registered on the single FastAPI app. Do not delete `backend-sync` or other queues here; S-25 owns their final removal.

**Cutover rule:** retain the `#9760` legacy delivery branch until live queue/task evidence proves the old maximum retry window has elapsed. Remove it only in the later simplify stage with a behavioral denial test and residue proof.

**Focused proof:** `test_account_deletion_cloud_tasks.py`, cloud-task unit tests, router task-auth tests, runtime-env validator/render tests, workflow contract/actionlint, route policy, pre-deploy check, and read-only live development queue/IAM/Cloud Run inspection. Mutating or deploying development/production requires the separate authorization in the repo guide.

### Gated Cycle 8 — RED/GREEN: complete offline local export document

**Gate:** G2. Under the adopted roadmap repair, S-10 through S-14 supply the
complete readers and S-08 retains the cross-domain composer after those reader
dependencies close.

**RED:** At the proposed `LocalUserDataExport.export(ownerID:to:)` interface, create a temporary owner database and kernel journal with one independently specified record in every approved section. Disable product network access. Assert one exact normalized JSON document, stable schema version, owner fencing, complete pagination, deterministic ordering, and absence of credentials/internal sync fields. Use known literal expectations rather than re-encoding with the production implementation.

**GREEN:** Implement the deep local exporter by calling the final public owner-scoped read interfaces. Page rather than load unbounded histories, encode to a sibling temporary file, atomically replace the chosen destination only after success, and delete the temporary file on failure. Add only the explicit safe settings snapshot agreed at the seam; never dump UserDefaults or databases wholesale.

**Main error-path tracer bullet:** make one local source or destination write fail and assert a user-presentable error plus no partial destination. Then add only enough cleanup/error mapping to pass.

**Focused proof:** local export tests on a temporary owner, kernel journal paging tests if its existing interface needs extension, owner-switch/ABA fence tests, offline execution, and JSON validation with `jq`.

### Gated Cycle 9 — RED/GREEN: expose Export My Data and narrow server metadata export

**Gate:** Cycle 8 green and rejected cloud product readers retired by their owner slices.

**RED A — Mac surface:** drive Account Settings through its public UI/automation seam, choose **Export My Data**, select a temporary destination, and assert the service receipt/file plus accessible success or error state. Canceling the save panel must make no file and no error.

**GREEN A:** add one Account Settings row and `NSSavePanel` orchestration. Reuse the local exporter, not connector Memory Export or Diagnostics Export. Keep Delete Account and Sign Out behavior unchanged. Add a user-facing changelog fragment.

**RED B — server surface:** through authenticated `GET /v1/users/export`, assert the versioned response contains only the agreed account/control allowlist and that product-content readers are never called. The independent expected payload must cover empty optional metadata.

**GREEN B:** replace `iter_user_data_export` with a small account metadata exporter, delete cloud conversation/memory/people/task/chat readers and exclusive streaming assumptions, update response model/content disposition to the owned product name when S-30 supplies it (use a neutral filename until then), and regenerate contracts/docs. Do not make the local export call this endpoint.

**Focused proof:** Swift service/UI tests, named-bundle offline export, backend data-export/router tests, route-policy/OpenAPI/generated-client checks, and repository searches showing server export has no product-content dependency.

## Review and simplify after all green cycles

This is the separate refactoring/review stage required by `engineering:tdd`; it is not another speculative red-green cycle.

1. Re-run the whole-path inventory. Every live reference must be classified as retained, owned by another slice, historical, or erroneous.
2. Remove obsolete result fields (`vectors_deleted`, `recordings_deleted`, retired failure-operation labels) only after worker tests and telemetry consumers are migrated.
3. Remove the legacy task audience/UID branch only after recorded queue-drain evidence satisfies the cutover rule.
4. Delete exclusive generated contracts, route policy, env vars, secrets bindings, tests, metrics, alerts, and docs with their retired owner. Do not delete shared Firebase, Firestore, Redis, auth, telemetry, or billing primitives with proven retained callers.
5. Apply the deletion test: removing the auth or deletion module should make its complexity reappear across callers; the exporter should hide completeness/encoding/atomic-write complexity behind one call. Remove any shallow pass-through introduced during implementation.
6. Record measured edit-to-test, edit-to-named-bundle, and dev-cloud proof times. Set ACCELERATE/AUTOMATE to `none` if there is no stable measured opportunity.
7. Update `backend/AGENTS.md`, `desktop/macos/AGENTS.md`, `.github/AGENTS.md` only where setup, test, service ownership, environment, or queue behavior changed. Update user/developer docs and product invariants if `scripts/pr-preflight --suggest` requires them.

## Verification matrix

### Focused automated checks while iterating

```bash
# Requirements integrity
python3 bootstrap-scaffold/validate-requirements-ledger.py

# Desktop behavior (run one exact production-behavior filter at a time)
cd desktop/macos
./scripts/dev-feedback.py --once swift 'AuthSessionCoordinatorTests'
./scripts/dev-feedback.py --once swift 'AuthSessionAttemptFenceTests'
./scripts/dev-feedback.py --once swift 'AuthRefreshResilienceTests'
./scripts/dev-feedback.py --once swift 'OAuthLoopbackCallbackServerTests'
./scripts/dev-feedback.py --once swift 'SignOutStorageInvalidationTests'
./scripts/dev-feedback.py --once swift 'OnboardingAcquisitionSourceTests'
python3 scripts/check_desktop_test_quality.py

# Backend focused files; backend/test.sh is the full-suite runner and ignores paths
cd ../../backend
.venv/bin/python -m pytest -q tests/unit/test_auth_redirect_uri.py
.venv/bin/python -m pytest -q tests/routers/test_users.py
.venv/bin/python -m pytest -q tests/services/users/test_account_deletion.py
.venv/bin/python -m pytest -q tests/services/users/test_data_export.py
.venv/bin/python -m pytest -q tests/unit/test_sync_cloud_tasks.py
.venv/bin/python -m pytest -q tests/unit/test_backend_runtime_env_validator.py
.venv/bin/python -m pytest -q testing/e2e/test_account_deletion_cloud_tasks.py
```

Run typechecking and the focused test after every cycle, as required by `engineering:implement`.

### Whole component and contract checks before review

```bash
cd backend
bash test-preflight.sh
bash test.sh
scripts/pre-deploy-check.sh

cd ../desktop/macos
./test.sh
./scripts/omi-macos-dev doctor

cd ../..
make preflight
```

Also run the existing OpenAPI compatibility/generation lane, route-policy inventory, runtime-env renderer/validator, workflow contract tests, actionlint, source-root/layout checks, formatter checks, and `scripts/pr-preflight --pr-body-file /tmp/pr-body.md` selected by the diff. New checks must be registered in `.github/checks-manifest.yaml` with local and CI lanes.

### Real user-facing and external-boundary proof

1. Build the first identity/resource change with a named non-production bundle and the full path:

   ```bash
   cd desktop/macos
   OMI_APP_NAME="omi-s08-account" ./run.sh
   ./scripts/omi-ctl health
   ./scripts/omi-ctl navigate settings account
   ```

2. Against the owned development project, exercise Apple sign-in, explicit Sign Out, Google sign-in, relaunch restore, transient validation recovery, foreground refresh failure/retry, and final Sign Out. Use `agent-swift` for the app surface and the system browser for the hosted provider flow. Never automate or stop the production Omi apps.
3. With the backend unavailable at the acquisition step, confirm onboarding persists and advances locally and the bounded analytics behavior matches the approved S-09 configuration.
4. Seed a disposable account in owned development, request deletion, verify immediate Mac Sign Out/no local wipe, inspect the opaque queued task and Firestore state transitions, run/redeliver the worker, and confirm the indefinite completed tombstone. Never use a real user account.
5. Seed at least one record in every final local export section, disconnect product network access, save through **Export My Data**, validate the JSON and record counts, then inject one read/write failure and prove no partial file remains.
6. After separately authorized dev deployment, read back the Cloud Run handler URL, queue shape, IAM binding, OIDC signer/audience, runtime configuration, and five-minute recovery behavior. Production deployment and queue mutation are not implied by this plan.

### Residue searches

Run scoped searches; broad Omi-name searches belong to S-30 and broad sync searches belong to S-25.

```bash
# Backend onboarding mirror is gone, but /v4/listen OnboardingHandler remains explained
rg -n 'updateOnboardingAcquisitionSource|/v1/users/onboarding|get_user_onboarding_state|set_user_onboarding_state' desktop/macos backend

# Deletion survey state is gone; operational reason fields elsewhere are not false positives
rg -n 'set_user_deletion_feedback|reason_details|DeleteAccountRequest' backend desktop/macos

# Account deletion no longer owns rejected-product cleanup after G3
rg -n 'delete_user_caller_ids|purge_derived_user_data|delete_all_conversation_recordings|purge_canonical_derived_user_data|delete_.*vectors' backend/services/users/account_deletion.py

# Account deletion no longer borrows sync identity after G4; sync jobs may still use SYNC_TASKS_*
rg -n 'SYNC_TASKS_' backend/services/users/account_deletion.py backend/utils/cloud_tasks.py backend/deploy/runtime_env.yaml .github/workflows/gcp_backend.yml

# Server export has no private product-content readers
rg -n 'iter_all_conversations|get_non_filtered_memories|get_people|get_.*action_items|iter_all_messages' backend/services/users/data_export.py
```

Every non-zero result must be explained in the closure evidence; do not weaken the search merely to make it green.

## Commit and delivery evidence

- Keep commits aligned to green cycles or another independently testable surface, not individual files.
- Before any `fix:` commit, run `scripts/pr-preflight --suggest` and add the required `Failure-Class: FC-... | new | none` trailer. Identity drift should reuse the existing failure class where the tool confirms it.
- Record RED failure, GREEN command/result, real-path evidence, external configuration used by name (never secret), and residue results in commit messages or the eventual PR body.
- Do not push or open a PR without a new explicit request. Do not deploy or mutate persistent cloud state without the separate authorization required for risky infrastructure.

## Final independent review

When implementation and all authorized live proof are complete:

1. Resolve the fixed point: `git rev-parse origin/main`.
2. Confirm `git diff origin/main...HEAD` is non-empty and record `git log origin/main..HEAD --oneline`.
3. Invoke **`engineering:code-review`** with fixed point **`origin/main`** and this file as the spec.
4. Keep Standards and Spec findings separate. Standards must include the repository guides and smell baseline; Spec must quote this plan/IR source for every finding.
5. Fix accepted findings, rerun proportionate checks and real-path proof, and review again if fixes materially changed the diff.
6. A closed S-08 records commit(s), exact verification evidence, queue/project readback, export fixture counts, residue explanations, and any remaining downstream owner in `deletion-map.md`; rerun the requirements validator.

S-08 is not closed by compiling, by repointing a Firebase plist alone, by deleting the Settings row's sibling API, by returning a smaller server export before the local export exists, or by removing deletion cleanup while rejected systems can still hold user data.

## 2026-08-15 implementation record

The configuration-independent repository tranche is implemented without
crossing G1-G4 or Cycles 6-9:

- the retained Apple/Google auth, restore, refresh, and sign-out suite remains
  unchanged and green;
- both Mac acquisition call sites now use one local-persistence plus analytics
  owner, and the behavioral test installs a fail-on-any-request URL protocol;
- the backend onboarding GET/PATCH routes and Firestore helpers are removed,
  with the unrelated `/v4/listen` onboarding handler retained;
- delete-account admission is bodyless, arbitrary legacy JSON cannot create
  survey state, and reason/feedback storage is removed; and
- account-deletion cleanup composition is separated from its durable claim/job
  state machine, while the downstream account/control metadata allowlist remains
  a documented contract until its real cleanup/export consumers land.

The released-client transition is an intentional same-release hard removal for
the Mac and backend `/v1/users/onboarding` surface: old clients receive 404 and
no in-repo compatibility route is retained. `DELETE /v1/users/delete-account`
now emits a bodyless request, but its server admission remains tolerant of and
ignores arbitrary legacy JSON while joining the same durable deletion intent.
The retained app-client Swift contract was regenerated. The Windows client is
outside this slice, and the missing auth invariant still gates Cycle 4.

Focused evidence:

- `swift test --filter OnboardingAcquisitionSourceTests`: 1 passed;
- retained auth/onboarding/sign-out Swift filter: 32 passed;
- account-deletion service file: 39 passed;
- onboarding-route E2E and Cloud Tasks deletion lifecycle E2E: 1 passed each;
- strict desktop E2E flow coverage: 8 changed Swift files covered, 0 uncovered;
- Swift OpenAPI generation check, route-policy baseline, requirements validator,
  formatters, full Swift test-bundle compile, and `git diff --check`: passed.

The full component runners were also attempted. The backend runner passed the
S-08 service file before an unrelated `test_audio_merge_tasks.py` 0.12-second
timing ratchet failed. The desktop runner passed launcher contracts, 33 desktop
backend tests, and the full Swift compile before the unrelated Memory Atlas
performance suite exceeded its 120-second process-isolation budget. Those broad
runs were stopped rather than expanding this slice into unrelated test debt.

A disposable `com.omi.omi-s08-calgary` bundle built, launched against the
hermetic local Auth emulator, and reached signed-in onboarding as synthetic
`alice`. The final acquisition control could not be clicked because the Mac was
at its lock screen and macOS exposed no application windows to Accessibility.
The bundle was stopped and moved to Trash; the local harness and Colima were
stopped. Provider cleanup, queue/service retargeting, export composition, and
owned identity configuration remain intentionally assigned to their existing
gates.
