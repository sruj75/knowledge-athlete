# S-07 TDD Plan — Remove Customer BYOK and Preserve Managed Access

Status: researched — awaiting human agreement on the public seams and legacy-data transition below
Owning subagent: S-07
Wave: 1
Authorizing and protecting decisions: IR-007, IR-058, IR-062, IR-606,
IR-712, and IR-937
Depends on: none
Coordinates with: S-03 for Deepgram provider residue; S-05 for shared managed-Pi
files; S-18 for later Dodo billing adaptation; S-22 for later managed-model
portfolio narrowing

Postcondition: every signed-in customer uses the product-managed subscription,
entitlement, quota, and provider-credential path; no customer-supplied model key
can change access, leave the Mac, reach a provider, or survive as a live product
surface.

## Workflow contract

Implementation starts by invoking `engineering:implement` with this plan. That
workflow must use `engineering:tdd` at the approved seams, work one red-green
cycle at a time, run focused typechecking/tests continuously and the complete
component suites once at the end, and commit the work to the current branch. It
must not rename the branch, push, open a PR, or edit Windows.

After all cycles and verification are green, invoke `engineering:code-review`
with fixed point `origin/main`. Use this file plus the authoritative IR
sections listed above as the Spec source, and use `AGENTS.md`, `backend/AGENTS.md`, and
`desktop/macos/AGENTS.md` as the Standards sources. Resolve both review axes,
rerun affected tests, and only then call the slice closed.

No product test may be written before the human agrees to the public seams in
this plan. Source-string scans below are closure evidence, not behavioral test
coverage.

## Evidence and snapshot

- The live requirements ledger passes:
  `Requirements ledger validation: PASS (714 indexed rows, 714 detailed
  sections, all reviewed)`.
- Product source was inspected at `f293b62603145af15ce230a230f88017dce95f4a`.
  Current `HEAD` is `5ecb5e17aeab01955aff150a22054a957e15a48e`;
  intervening changes add planning/guardrail documents and do not change the
  product codeflow described here.
- IR-058 deletes PTT personal-key selection, direct-key eligibility and
  connection, BYOK-specific fallback, and usage-report bypass while protecting
  the managed short-lived credential path
  (`../requirements-challenge.md`, IR-058).
- IR-062 deletes the complete four-provider customer access plan: UI, local
  storage, validation, headers, runtime propagation, enrollment state,
  provider overrides, and entitlement/quota bypasses
  (`../requirements-challenge.md`, IR-062).
- IR-937 keeps the packaged managed-Pi extension and its managed provider plus
  typed-tool interface, while deleting only its BYOK environment/header path
  in this slice (`../requirements-challenge.md`, IR-937).
- The live storage is four `UserDefaults` values, not Keychain:
  `dev_openai_api_key`, `dev_anthropic_api_key`, `dev_gemini_api_key`, and
  `dev_deepgram_api_key`
  (`desktop/macos/Desktop/Sources/APIKeyService.swift`). The
  implementation must remove the real reads and writes and must not invent a
  Keychain migration for a record that source research did not find.
- S-28 later gives the new product a clean storage namespace and explicitly
  rejects inherited Omi-data takeover. S-07 therefore removes the live storage
  interface now; it does not add a permanent compatibility reader merely to
  purge an unshipped predecessor namespace.
- Two durable backend shapes need an ordered retirement, not only code
  deletion: `users/{uid}.byok` stores activation/fingerprints, while
  conversation-finalization jobs can be `blocked_byok` with
  `requires_byok=true`. The checkout proves those schemas and writers exist;
  it does not prove current production cardinality.

Before implementation, re-run:

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py
git rev-parse HEAD origin/main
```

If any referenced IR has changed, refresh this plan before writing a test.

### Implementation start gates

Do not invoke `engineering:implement` until both gates are resolved:

1. The human approves or amends the six public behavior seams below.
2. An authorized operator runs a read-only cardinality dry run for
   `users/{uid}.byok` and `blocked_byok`/`requires_byok` finalization jobs, then
   records the chosen transition. Old finalization jobs must either be requeued
   for normal managed processing after the ordinary entitlement boundary, or
   terminalized with an explicit BYOK-retirement reason. The plan must not
   silently strand them, hide them from projections, or guess between those
   policies. The same decision records whether `users.byok` is purged or
   tombstoned after its last reader is retired.

Any one-time migration artifact must carry the repository-required
`LIFECYCLE: one-time` and `DELETE-AFTER:` header. Test the chosen transition on
representative legacy documents before deleting the readers or status values.
The dry run is read-only; executing the write pass is a separate,
hard-to-reverse production action and requires explicit user sign-off after
the counts and proposed policy are visible.
Also locate the authoritative OpenAPI-to-Swift generation command before
editing API contracts; generated Swift is output, not the hand-edited owner.

## Classified behavior boundary

| Action | Exact behavior and source boundary |
|---|---|
| KEEP AS IS | Firebase sign-in/session invalidation; product-managed subscription, entitlement, usage and quota; server-owned provider credentials; short-lived managed OpenAI/Gemini PTT credentials; both retained realtime providers and their failover/relay/batch recovery; managed Pi, local kernel, typed tools and journal; ordinary environment/Secret Manager credentials for development, tests and retained deployments. |
| ADAPT | Shrink `APIKeyService` to retained managed configuration only; shrink `OmiHTTPTransport`/`APIClient` to normal auth and request metadata; make realtime session authentication managed-only; remove customer-key cases from credential-health classification; make subscription/quota and provider adapters consult only managed account and platform configuration; narrow route-policy and model/gateway schemas to the credential modes that still exist. |
| DELETE | Customer Developer Keys UI and billing promo; four raw-key `UserDefaults` fields; `BYOKProvider`, `BYOKValidator`, activation/deactivation calls; `X-BYOK-*`, `X-Omi-Byok-*-Key`, and `OMI_BYOK_*` propagation; PTT direct-key authentication; local paywall/usage bypasses; backend middleware/context/cache/fingerprint peppering; `/v1/users/me/byok-active`; Firestore `users/{uid}.byok`; BYOK subscription/quota responses; BYOK provider clients, gateway envelopes, model-QoS route, sync/finalization special cases, errors, metrics, tests, generated non-Windows contracts, configuration and live docs. |
| SIMPLIFY / OPTIMIZE AFTER | Once every green behavior passes, delete obsolete parameters such as `includeBYOK`, collapse managed-vs-BYOK enums and switches, remove BYOK-only modules/tests, reduce route and credential schemas, and rename comments/errors that still promise a second access model. Do not perform this refactoring inside a red-green cycle. |
| ACCELERATE AFTER | No new acceleration is pre-authorized. Record focused-cycle timings with `scripts/dev-feedback.py`; use the existing Swift, Node and pytest selectors. Change the loop only if measured S-07 friction has a small, verifiable fix. |
| AUTOMATE LAST | None planned. Existing tests, route/OpenAPI checks, test-quality checks and residue searches cover closure. Do not add a new CI guard without a real merged incident/PR it would have caught. |
| OUT OF SCOPE / DEFERRED | Deleting the Deepgram product/provider itself (S-03); other managed-Pi adapters, skills, shell/file tools, Opus and Omi identity (S-05); historical `onboardingBYOKStepInserted`/`onboardingBYOKStepRemoved` migration state unless S-17 proves its migration horizon expired; Stripe-to-Dodo migration (S-18); final managed model/vendor/workload selection and full LLM-gateway deletion (S-22/S-25); clean product namespaces (S-28); general rebrand/privacy copy (S-30); Windows; moving or deleting product-owned secrets merely because their names contain a provider. |

`KEEP AS IS` is a regression fence, not permission to redesign the retained
path. In particular, removing BYOK must not choose between OpenAI Realtime and
Gemini Live, remove managed PTT usage reporting, or convert a provider 401 into
a Firebase-session logout.

## Current codeflow

```text
Advanced Settings > Developer Keys / Account & Plan BYOK promo
  -> four @AppStorage/UserDefaults raw keys
  -> BYOKValidator calls four public provider endpoints
  -> APIClient POST / DELETE /v1/users/me/byok-active
  -> Firestore users/{uid}.byok fingerprints + active heartbeat

subsequent customer work
  -> generic HTTP X-BYOK-* headers
  -> listen / relay WebSocket X-BYOK-* headers
  -> PTT .byokKey direct provider authentication
  -> AgentRuntimeProcess OMI_BYOK_* environment
  -> pi-mono-extension X-BYOK-* headers
  -> backend BYOK middleware / WebSocket extraction / validation
  -> BYOK request context
  -> subscription, paywall, chat quota and transcription quota bypass
  -> Chat, Gemini proxy, embeddings, TTS, STT and LLM-gateway key override
  -> sync/finalization special routing because keys cannot enter Cloud Tasks
```

### Confirmed source owners

| Layer | Live owners to inspect and change |
|---|---|
| Customer UI and local state | `desktop/macos/Desktop/Sources/MainWindow/Pages/SettingsPage.swift`; `desktop/macos/Desktop/Sources/MainWindow/Pages/Settings/Sections/SettingsContentView+DeveloperKeys.swift`; `desktop/macos/Desktop/Sources/MainWindow/Pages/Settings/Sections/SettingsContentView+AccountBilling.swift`; `desktop/macos/Desktop/Sources/MainWindow/Pages/Settings/Components/SettingsContentView+BillingHelpers.swift`; `desktop/macos/Desktop/Sources/APIKeyService.swift`; `desktop/macos/Desktop/Sources/BYOKValidator.swift`; `desktop/macos/Desktop/Sources/Services/APIClient/APIClient+People.swift` |
| Generic desktop request/access policy | `desktop/macos/Desktop/Sources/APIClient.swift`; `desktop/macos/Desktop/Sources/Services/OmiHTTPTransport.swift`; `desktop/macos/Desktop/Sources/AppState/AppState+TrialPaywall.swift`; `desktop/macos/Desktop/Sources/AppState/AppState+ListenEvents.swift`; `desktop/macos/Desktop/Sources/Providers/ChatProvider.swift`; `desktop/macos/Desktop/Sources/FloatingControlBar/FloatingBarUsageLimiter.swift`; `desktop/macos/Desktop/Sources/FloatingControlBar/PushToTalkManager.swift`; `desktop/macos/Desktop/Sources/ProactiveAssistants/ProactiveAssistantsPlugin.swift` |
| PTT, STT and TTS | `desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubSettings.swift`; `desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController.swift`; `desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController+SessionLifecycle.swift`; `desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController+SessionDelegate.swift`; `desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubSession.swift`; `desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubTestHarness.swift`; `desktop/macos/Desktop/Sources/RealtimeOmni/RealtimeOmniService.swift`; `desktop/macos/Desktop/Sources/TranscriptionService.swift`; `desktop/macos/Desktop/Sources/FloatingControlBar/FloatingBarVoicePlaybackService.swift`; the TTS portion of `desktop/macos/Desktop/Sources/Services/APIClient/APIClient+People.swift`; `desktop/macos/Desktop/Sources/CredentialHealthManager.swift` and error classifiers |
| Managed Pi | `desktop/macos/Desktop/Sources/Chat/AgentRuntimeProcess.swift`; `desktop/macos/pi-mono-extension/index.ts`; matching Swift and package tests; environment allowlists in `desktop/macos/agent/tests/` |
| Backend entrance and state | `backend/main.py`; `backend/utils/byok.py`; `backend/utils/other/endpoints.py`; `backend/routers/users.py`; `backend/database/users.py`; `.env.template`; route-policy manifest, inventory code, missing-route baseline and tests |
| Entitlement and workload routing | `backend/utils/subscription.py`; desktop Chat/Gemini/TTS routes; listen/relay/sync/conversation-finalization routes and helpers; `backend/utils/stt/pre_recorded.py`; `backend/utils/llm/clients.py`, `model_config.py`, `gateway_byok.py`, `byok_errors.py`, conversation-processing and shadow paths |
| LLM gateway | `backend/llm_gateway/gateway/{schemas,credentials,executor,providers,resolver}.py`; OpenAI-compatible and Anthropic routers; `config/lanes.yaml`; `config/route_artifacts.yaml`; gateway tests and docs |
| Contracts, tests and docs | `desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift` via its generator/contract owner; BYOK-named Swift/backend/gateway tests; onboarding/e2e expectations; `backend/utils/llm/ARCHITECTURE.md`; `backend/AGENTS.md`; `desktop/macos/AGENTS.md`; live runbooks/configuration. Historical changelog entries remain history. |

This is a starting owner inventory, not permission to bulk-delete every file
that contains the word `key`. At each cycle, trace imports and callers and
classify the occurrence as customer BYOK, retained product credential, ordinary
test/development secret, historical record, or unrelated provider work.

## Module design after deletion

S-07 deepens existing modules by deleting a second access interface. It does
not add a new port or adapter.

| Module | Smaller retained interface | Hidden implementation after S-07 |
|---|---|---|
| Managed desktop configuration | fetch/wait/clear retained backend configuration and report readiness | key fetching/retry/environment compatibility still required by retained callers; no customer storage, fingerprints or provider enumeration |
| Desktop HTTP transport | Firebase auth, owner fencing, device/app metadata, JSON verbs | normal retry/session handling; no `includeBYOK` parameter or customer-header assembly |
| Realtime voice session | signed-in managed mint, provider choice, failover, relay and batch recovery | token acquisition and provider protocol; no direct customer-key auth mode |
| Managed-Pi adapter | authenticated managed provider registration plus scoped typed-tool bridge | request correlation/reasoning headers and tool relay; no customer-key environment/header map |
| Backend account access | Firebase identity plus subscription/entitlement/quota | managed account checks and usage ledgers; no BYOK middleware, request context, Firestore heartbeat or bypass |
| Managed provider routing | one product-owned credential policy per retained workload | provider-specific adapters and true external-provider mocks; no request-supplied override or BYOK QoS profile |

The deletion test is decisive here: if BYOK modules disappear, their complexity
must disappear rather than reappearing as booleans or compatibility branches in
each caller.

## Proposed public seams — human approval required

Approve or amend these before Cycle 1. Tests must call these interfaces and
observe outcomes; they must not mock our own internal modules or assert only on
source text.

1. **Settings and persisted-customer-secret seam.** A customer cannot find a
   Developer Keys/BYOK/free-forever control in Settings or Account & Plan. Old
   `dev_*_api_key` values, if present in the test preferences domain, have no
   effect on visible state or any request/runtime behavior.
2. **Desktop managed-access seam.** The public desktop request interface emits
   Firebase/device/app headers only. Local customer-key values cannot suppress
   a paywall, mark a plan paid/unlimited, or make Chat/capture eligible.
3. **PTT session seam.** A signed-in entitled user obtains a short-lived managed
   credential and can use either retained realtime provider plus existing
   failover/relay/batch recovery. A signed-out user or denied entitlement cannot
   become eligible by supplying a legacy key.
4. **Managed-Pi process seam.** Starting the real managed-Pi adapter produces a
   child environment/request with no `OMI_BYOK_*` or `X-BYOK-*` data and still
   completes a managed Sonnet-class turn with scoped tools.
5. **Backend account/route seam.** Through FastAPI HTTP/WebSocket interfaces,
   legacy BYOK headers and an old Firestore `byok` field cannot change
   authentication, subscription, trial, quota, dispatch or usage accounting.
   The activation/deactivation routes no longer exist.
6. **Managed-provider seam.** At true external-provider adapters, Chat, Gemini,
   embeddings, TTS, continuous/batch STT and retained gateway calls receive only
   product-owned credentials. A legacy customer header never selects a client,
   changes a route, disables metering or falls back from customer-paid to
   product-paid compute.

Human seam decision: **pending**.

Legacy-data transition decision: **pending read-only cardinality dry run and
operator choice between managed requeue or explicit terminalization**.

## Ordered TDD cycles

Every cycle is sequential: add one failing behavior at one approved seam, run
it red for the expected reason, write only enough production code to make it
green, and run the named sibling tests/typecheck. Do not write later-cycle
tests early. Do not refactor during red-green.

### Cycle 1 — Customer BYOK is absent from Settings

- **RED:** through the Settings presentation/semantic snapshot interface, prove
  that Account & Plan and Advanced Settings expose no free-BYOK promo, key
  fields, validation status, activation error or clear action, even when the
  isolated preferences domain contains all four legacy values.
- **GREEN:** remove the BYOK promo/navigation, Developer Keys subsection and
  view state. Remove `BYOKValidator` and activation/deactivation client calls
  once no live UI caller remains. Preserve unrelated Advanced Settings and plan
  controls.
- **Focused proof:** the new Settings behavior test plus Settings search/e2e
  coverage; replace/delete `BYOKIncompleteHintTests` only after the new seam is
  green.

### Cycle 2 — Local keys cannot change plan, paywall or eligibility

- **RED:** at the public access-decision interface, preseed all four legacy
  values and prove a server-paywalled customer remains blocked while a managed
  entitled customer remains allowed.
- **GREEN:** remove BYOK branches from `AppState` trial/paywall/listen events,
  `FloatingBarUsageLimiter`, Chat/PTT eligibility, proactive monitoring and plan
  title/feature mapping. Retain server-authoritative managed entitlement and
  existing fail-open/fail-closed behavior not owned by BYOK.
- **Focused proof:** replace `BYOKPaywallTests` with managed-access behavior
  coverage; keep independent paywall, quota and resume-on-clear tests.

### Cycle 3 — Desktop HTTP never emits customer keys

- **RED:** build representative GET, POST, DELETE and data requests through the
  production request interface with legacy values present; assert the outgoing
  request has no `X-BYOK-*` header while auth/owner/device headers remain.
- **GREEN:** remove BYOK assembly and health suppression from
  `OmiHTTPTransport`, then remove `includeBYOK` from `APIClient` and every
  in-tree caller. Do not change Firebase refresh/session behavior.
- **Focused proof:** transport/auth retry suites and the existing memory bulk
  request safety seam; a static residue scan may supplement but not replace the
  behavioral request test.

### Cycle 4 — PTT always uses managed authentication

- **RED:** at the realtime controller/session seam, preseed a legacy OpenAI or
  Gemini value and prove an entitled signed-in user calls managed minting rather
  than `.byokKey`; also prove the same value cannot make a signed-out user
  connect.
- **GREEN:** delete direct-key eligibility/authentication, fingerprints,
  BYOK-specific failover, usage-report bypass, relay forwarding and recovery
  copy. Replace the overloaded auth representation with production
  managed-ephemeral auth plus a DEBUG-only `hermeticStub` mode, or an equally
  explicit orthogonal `reportsUsage` property: every production managed turn
  reports usage, while the hermetic local-profile stub reports none. Narrow
  credential-health cases to managed provider vs Firebase-session failures
  while preserving two-provider switching, failover, barge-in, warm sessions,
  relay and batch recovery.
- **Focused proof:** realtime hub policy/lifecycle/close-classifier suites and a
  natural authenticated PTT turn later in real-path verification.

### Cycle 5 — Continuous and batch STT use managed policy and quota

- **RED:** through `/v4/listen` and the retained batch-transcription interface,
  send legacy Deepgram/customer headers and prove they neither select a
  provider nor bypass trial/transcription quota; a valid managed user still
  receives transcript events.
- **GREEN:** remove desktop WebSocket/batch header forwarding, backend
  extraction/context dependencies, per-request Deepgram client selection and
  BYOK-only live listen/sync dispatch branches. Preserve legacy durable-job
  readers until Cycle 8 has executed the approved transition. Preserve
  S-03-owned provider-neutral framing and whichever managed STT providers
  still exist at this point.
- **Focused proof:** listen lifecycle/WS auth, prerecorded STT, transcription
  quota, sync dispatch and finalization tests. Do not delete the Deepgram
  provider/control plane; S-03 owns that separate deletion.

### Cycle 6 — TTS and remaining desktop model proxies use product credentials

- **RED:** call retained TTS and Gemini proxy interfaces with legacy OpenAI and
  Gemini headers and assert the true external adapter receives the configured
  product credential, normal metering runs, and customer-key recovery copy is
  absent.
- **GREEN:** remove BYOK selection/meter skips from desktop TTS, desktop Chat,
  Gemini proxy, embeddings and other retained request-bound model helpers.
  Preserve platform-key AI Studio and explicitly configured Vertex routing
  protected by IR-712.
- **Focused proof:** `test_desktop_chat.py`, `test_desktop_proxy.py`,
  `test_desktop_tts_updates.py`, managed usage tests and their Swift error
  normalization/credential-health counterparts.

### Cycle 7 — Managed Pi cannot receive or forward customer keys

- **RED:** start the managed-Pi adapter through its subprocess/package seam
  with both stale inherited `OMI_BYOK_*` variables and legacy local values;
  assert the child/provider request contains none of them and managed provider
  registration/tool relay still succeeds.
- **GREEN:** remove BYOK environment construction from `AgentRuntimeProcess`
  and the four-provider environment-to-header map from
  `pi-mono-extension/index.ts`. Keep and rename the small child-boundary
  sanitizer that strips inherited retired `OMI_BYOK_*` variables; this is a
  secret-egress guard, not a compatibility reader. S-05 owns all non-BYOK
  extension changes.
- **Focused proof:** `AgentRuntimeProcessTests`, extension package tests,
  `desktop/macos/agent` environment allowlist tests, then
  `./scripts/agent-logic-harness.sh`.

### Cycle 8 — Retire durable legacy BYOK state without stranding work

- **RED:** using representative `users.byok` and `blocked_byok` /
  `requires_byok` documents, prove the operator-approved transition produces
  its declared result: each legacy job becomes normally processable after the
  ordinary entitlement boundary or reaches an explicit terminal retirement
  state, and projections/metrics still account for it. Prove the user field is
  purged or tombstoned exactly as approved.
- **GREEN:** implement and run the reviewed one-time transition with dry-run,
  bounded execution, idempotency and post-run counts. Only after its behavioral
  test and explicitly approved execution evidence are green may Cycles 9 and
  11 remove production readers/writers, `blocked_byok`, `requires_byok`, resume
  functions and BYOK-specific projections.
- **Focused proof:** conversation-finalization repository/claim/projection and
  sync/backfill tests, the one-time migration test, dry-run output, execution
  output and zero-unhandled-residue post-check. Do not infer production
  cardinality from fixtures.

### Cycle 9 — Managed entitlement and usage ignore old BYOK state

- **RED:** through subscription, trial, chat-quota and transcription-quota
  interfaces, seed an old Firestore `byok` field and send legacy headers;
  assert they cannot return `Free (BYOK)`/unlimited, bypass a denial, skip
  managed usage, or change dispatch. A valid managed paid subscription remains
  allowed.
- **GREEN:** delete BYOK branches from subscription, usage, paywall, overage,
  conversation processing, sync/finalization and related response models/copy.
  Retain account plans and Dodo migration seams without deciding their final
  names or prices.
- **Focused proof:** subscription/plan/chat-quota/trial/paywall/sync/finalizer
  suites through production interfaces. Delete BYOK-only tests; do not retain
  mocks of functions that no longer exist.

### Cycle 10 — Backend and LLM gateway cannot accept customer credentials

- **RED:** at the backend/gateway HTTP interface, send both legacy
  `X-BYOK-*` and internal `X-Omi-Byok-*-Key` headers; prove retained workloads
  use the managed credential policy, preserve metering, and never expose the
  supplied key to a provider adapter.
- **GREEN:** remove BYOK client selection/caches/error wrappers/profile maps
  from `utils/llm`; remove forwarded-key credential modes, failure classes,
  schema fields, router extraction and provider branches from `llm_gateway`;
  simplify existing managed route artifacts without deleting the gateway
  itself. S-22/S-25 own later workload/provider/gateway deletion.
- **Focused proof:** LLM client/model-config tests plus gateway credential,
  resolver, executor, provider and OpenAI/Anthropic route tests. External
  provider calls may use mocks because they are true external seams.

### Cycle 11 — Delete enrollment, fingerprint and route-policy control planes

- **RED:** through the assembled FastAPI app, prove `POST` and `DELETE
  /v1/users/me/byok-active` are absent and normal authenticated routes ignore
  arbitrary legacy headers. Prove the route/OpenAPI inventory contains neither
  endpoint nor a BYOK policy dimension.
- **GREEN:** delete `utils/byok.py`, middleware registration, special auth
  dependencies, WebSocket validation, Firestore state helpers/cache, pepper
  configuration, route models/handlers, legacy route-baseline entries and
  generated non-Windows client methods. Update the owning API schema and
  route-policy inventory, then run the discovered generator/checker; do not
  hand-edit generated Swift as the source of truth.
- **Focused proof:** assembled-app route tests, auth/WS tests, route-policy
  inventory check, OpenAPI/client contract check and generated-source build.

### Cycle 12 — Remove the last customer-key source interface

- **RED:** through the retained managed-configuration interface, prove legacy
  `dev_*_api_key` values cannot override product-managed Gemini/configuration
  or appear in any child/request behavior.
- **GREEN:** remove `BYOKProvider`, fingerprint/snapshot/key access, the
  developer Gemini override and all four customer storage reads/writes from
  `APIKeyService`; remove now-dead credential-health cases and BYOK-only
  tests/files. Preserve verified Firebase/Calendar/product-managed
  configuration consumers. Do not add a permanent legacy-preference reader;
  inert predecessor values are handled by S-28's clean namespace unless a
  separately owned one-time purge is explicitly approved.
- **Focused proof:** managed configuration/auth bootstrap tests, desktop build
  and the focused consumer suites changed by the smaller interface.

## IR-606 conditional cleanup gate

IR-606 authorizes deleting `ModelQoS.Claude.synthesis`, `chatLabQuery`, and
`chatLabGrade` only after their connector/ChatLab/Agent-Pill callers have been
removed by their owning S-05/S-06 work. Those product deletions are not S-07
scope.

- This is not an S-07 start dependency.
- At final cleanup, re-run the caller search.
- If no caller remains, delete the orphaned constants and exclusive tests.
- If a live caller remains, do not broaden S-07 to delete that product. Record
  the exact caller as a Wave 1 coordination blocker and let its owning slice
  close it before claiming IR-606 complete.

## Review and simplify after green

Only after Cycles 1–12 are green:

1. Apply the module-deepening table: remove dead interface surface rather than
   layering a managed-only wrapper over BYOK-aware implementations.
2. Delete superseded BYOK unit tests and replace only the durable user behavior
   at the approved seams. Keep unrelated auth, paywall, quota, PTT, STT, TTS,
   managed Pi and gateway tests.
3. Remove stale comments, error strings, diagnostics, metrics, architecture
   entries, runbooks and current BYOK onboarding/e2e expectations. Preserve
   S-17-owned historical onboarding migration tests unless that owner proves
   their migration horizon expired. Add one user-facing changelog fragment for
   removal of the free-BYOK/key Settings path.
4. Do not add aliases, no-op endpoints, dormant enum cases, fake-success
   responses or a hidden developer-key Settings switch.
5. Run `engineering:code-review` against `origin/main` with separate Standards
   and Spec axes. Fix findings without reranking one axis over the other.

## Verification

### Focused loop while editing

Use the smallest selector for the active cycle, for example:

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift '<approved S-07 XCTest filter>'
./scripts/agent-logic-harness.sh

cd ../../backend
python3 -m pytest -q <approved focused test files>
```

Use the repository Python 3.11 environment once dependencies are synced. Run
`python3 desktop/macos/scripts/check_desktop_test_quality.py` after Swift test
changes. Run the route inventory from `backend/` with the repository's Python
path and its documented `--check`/baseline arguments.

### Component and repository gates

```bash
cd desktop/macos && bash test.sh
cd ../../backend && bash test.sh
cd ..
python3 bootstrap-scaffold/validate-requirements-ledger.py
make preflight
```

Before any future PR is opened, draft its body, run
`scripts/pr-preflight --suggest`, then run
`scripts/pr-preflight --pr-body-file <body-file>`. This slice is a product
deletion, not automatically a `fix:`; do not invent a failure class. Record all
commands and outcomes in the commit/PR evidence.

### Real retained-path exercise

Use a named non-production bundle such as `omi-s07-managed-access`; never touch
Omi or Omi Beta.

1. Launch with a signed-in managed test account and verify Account & Plan and
   Advanced Settings expose no BYOK/key path.
2. Complete a normal managed Chat turn and a managed-Pi tool turn.
3. Complete natural authenticated PTT turns through both explicit retained
   realtime provider choices; verify managed minting/usage and existing
   failover semantics in logs without exposing tokens.
4. Exercise one managed continuous-cloud STT session and the retained batch
   recovery path, plus cloud TTS fallback where configured.
5. In isolated local/offline backend tests, add old customer headers and an old
   Firestore `byok` field and prove neither changes entitlement, quota, route,
   provider credential or dispatch.
6. Run `./scripts/omi-ctl health`, read the named bundle/backend logs, and
   confirm no raw credential was logged.

Compiling alone is not real-path evidence. If live provider credentials are
unavailable, record the exact unexercised path; do not relabel a hermetic test as
a live PTT/STT/provider run.

### Closure residue search

Run after tests, excluding Windows and preserving accurate historical
changelogs/requirements as history:

```bash
rg -n -i \
  --glob '!**/windows/**' \
  --glob '!**/changelog/**' \
  --glob '!bootstrap-scaffold/requirements-challenge.md' \
  'BYOK|byok-active|x-byok|x-omi-byok|OMI_BYOK|dev_(openai|anthropic|gemini|deepgram)_api_key|BYOK_FINGERPRINT_PEPPER' \
  desktop/macos backend config .github scripts .envrc.example
```

Expected result: no unexplained live product, configuration, contract, test or
operator reference. Protected historical changelog entries and the S-17-owned
`onboardingBYOKStepInserted` / `onboardingBYOKStepRemoved` migration names may
remain when their owner confirms they still protect released in-progress
users. Separately search provider secrets and classify them; do not delete
retained `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,
`MODULATE_API_KEY`, Firebase credentials, Secret Manager bindings or test
fixtures merely because BYOK used the same vendor.

## Closure checklist

- [ ] Human approved all six public seams.
- [ ] Read-only production cardinality is recorded and the legacy user/job transition is approved, tested, executed and reconciled before readers disappear.
- [ ] Live IR sections still authorize this exact boundary; ledger validator is green.
- [ ] Every TDD cycle went red for the intended behavior before its minimum green.
- [ ] Managed Chat, PTT, STT, TTS, Gemini/embedding work and managed Pi remain functional.
- [ ] Customer UI, storage access, headers, environment variables, endpoints, Firestore state, bypasses and provider overrides are gone.
- [ ] Production PTT reports usage; DEBUG hermetic PTT does not; neither uses a customer-direct auth case.
- [ ] Retired `OMI_BYOK_*` names remain scrubbed at the child-process boundary while all constructors/forwarders are gone.
- [ ] S-03/S-05 shared-file ownership was coordinated without duplicate or conflicting edits.
- [ ] IR-606 caller gate is resolved or reported as an exact Wave 1 blocker.
- [ ] Focused tests, desktop/backend component suites, ledger validation and `make preflight` pass.
- [ ] Named-bundle and backend real-path evidence is recorded accurately.
- [ ] Residue searches contain only explained historical records and retained product-owned credentials.
- [ ] `engineering:code-review` reports both Standards and Spec axes; findings are fixed and reverified.
- [ ] Changes are committed locally to the current branch; no push/PR/main action occurred without a separate request.
