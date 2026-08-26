# Wave 5 / S-27 TDD plan — Re-own the retained Cloud Run, Redis, Firestore, GCS, and deployment foundation

## 1. Title and slice identity

| Field | Value |
|---|---|
| Wave | 5 |
| Slice | S-27 |
| Type | Infrastructure adaptation |
| Name | Re-own the retained Cloud Run, Redis, Firestore, GCS, and deployment foundation |
| Future named development bundle | `omi-wave5-s27` (`com.omi.omi-wave5-s27`) |
| Required predecessor | Integrated S-26, not merely its planning document |
| Primary decisions | IR-808, IR-809, IR-838 through IR-886, IR-890, IR-891 |
| Special boundary | Consume S-26's canonical Python application; own development/production cloud identity, region, IAM/WIF, Secret Manager, Redis, Firestore indexes, retained GCS, account-deletion queue, Artifact Registry, deployment, observability, budgets, rollback, and break-glass contracts. Do not activate Dodo, perform unapproved live mutations, or absorb S-29's Mac signing/update/release system. |

This is the implementation plan. It is not implementation evidence and it does not authorize a cloud mutation, payment operation, release, or production-app operation.

## 2. Planning status and pinned baseline

Planning was grounded on 2026-08-26 at the required commit:

```text
HEAD        22ad2f16ff8d63fd761c918b92f4c5d961814624
origin/main 22ad2f16ff8d63fd761c918b92f4c5d961814624
branch      plan-waves-5-6-slices
```

`git merge-base --is-ancestor 22ad2f16ff8d63fd761c918b92f4c5d961814624 HEAD` succeeded. The checkout had no product changes beyond the baseline. The requirements-ledger validator passed before planning with 714 indexed rows and 714 detailed sections, all reviewed.

The inspected tree is deliberately pre-S-26. It still has `backend/main.py` and `backend/desktop_backend.py`, two runtime-image records, Omi/based-hardware cloud identities, global JSON-key credentials, GCR image names, and pre-consolidation runtime/deployment contracts. Those are evidence of the current flow, not the shape S-27 may implement against. At execution time the implementer must:

1. rebase a fresh worktree on then-current `origin/main` without switching the task branch mid-work;
2. prove S-26 is integrated and its closeout evidence is present;
3. rerun every inventory in sections 7 and 13 against that commit;
4. record the new baseline SHA and every material delta from this plan;
5. stop rather than recreate a second app, compatibility service, or temporary pre-S-26 path.

BL-001 and BL-002 remain open. The S-25 handoff contains a sanitized inventory whose live classifications are `unknown`; repository absence is not live-resource absence. `BILLING_MODE=disabled` remains mandatory through Wave 6, and neither Dodo nor Stripe test/live activity is part of this slice.

## 3. Outcome

After repository implementation, one S-26 canonical Python application has one development and one production Cloud Run service, each in an owned project in `us-west1`, and one stable `run.app` URL per environment. The repository declares and validates the following foundation without retaining Omi/based-hardware authority:

- environment-scoped GitHub WIF and distinct least-privilege deploy, runtime, Firestore-index, and account-deletion task identities;
- ADC in hosted runtime, exact Secret Manager version bindings, and no hosted service-account JSON;
- Cloud Run generation, capacity, timeout, probe, billing, shutdown, networking, IAM, CORS, and public-route contracts;
- one private Memorystore instance per environment with AUTH and verified TLS, retaining each caller's explicit failure policy;
- only S-26's survivor Firestore indexes, managed by safe create-only checks and a separately authorized writer lane;
- one retained product-owned GCS bucket for desktop updates/previews, with the bucket boundary ready for S-29 but no S-29 release behavior absorbed;
- one account-deletion queue per environment targeting the canonical service with the dedicated signer and the retained Firestore reconciler;
- a regional Artifact Registry repository using full commit identity and an immutable digest, never `latest`;
- exact-main development deployment, production candidate/promotion/rollback, repair, and break-glass contracts;
- sanitized Cloud Logging, 30-day `_Default` retention, two production alerts, and alert-only environment budgets at 50/80/100 percent;
- local/offline and named-bundle proof that auth, health, streaming, fair-use, free billing, update reads, and durable deletion behavior remain intact.

Repository closure means the declarations, behavior, tests, workflows, and evidence surfaces agree. Operational closure additionally requires verified identities, read-only inventory, explicit mutation authority, successful development/production acceptance, and retained rollback evidence as separated in section 16.

## 4. Authorizing requirements

The detailed requirement sections, not this summary, remain authoritative.

| Decision | Authority used by this slice |
|---|---|
| IR-808 | Retain narrow Redis coordination/cache behavior; re-own its managed foundation. |
| IR-809 | Retain exactly the desktop update/preview GCS use after private product-data storage is deleted. |
| IR-838 | Keep the canonical unauthenticated health contract. |
| IR-839 | Deploy one canonical Python backend per environment after S-26 consolidation. |
| IR-840 | Separate owned development and production projects/configuration/credentials. |
| IR-841 | Keep automatic development deployment after an admitted exact-main Release Eligibility proof. |
| IR-842 | Keep candidate-first deployment, exact promotion, verification, rollback, and recovery. |
| IR-843 | Replace long-lived GitHub JSON keys with environment-scoped WIF and service-account impersonation. |
| IR-844 | Delete the OpenTofu foundation/pilot/probe and their workflows/checks; use a direct narrow v1 WIF configuration, not a replacement IaC platform. |
| IR-845 | Bind every source-derived deploy step to the currently admitted exact `main` SHA. |
| IR-846 | Retain narrowly scoped traffic repair and disclosed break-glass paths. |
| IR-847 | Pin an official controlled Python 3.11 slim base by immutable identity. |
| IR-848 | Use Secret Manager for retained runtime secrets with least-privilege access. |
| IR-849 | Keep one authoritative environment manifest and deterministic validation/rendering. |
| IR-850 | Run non-root with only necessary writable temporary paths. |
| IR-851 | Keep managed dependencies on an owned private network path. |
| IR-852 | Keep the service internet reachable while enforcing authentication at each retained route. |
| IR-853 | Keep empty, default-deny CORS and reject wildcard configuration. |
| IR-854 | Remove `latest` as a build, deploy, promotion, rollback, or evidence identity. |
| IR-855 | Declare CPU, memory, concurrency, timeout, min/max instances, execution generation, and CPU policy rather than accepting platform defaults. |
| IR-856 | Use a 3,600-second request timeout and prove Mac streaming reconnect/continuity. |
| IR-857 | Set development minimum instances to 0 and production to 1. |
| IR-858 | Own the complete retained backend/dependency foundation in `us-west1`. |
| IR-859 | Set each canonical service to 2 vCPU and 4 GiB. |
| IR-860 | Set request concurrency to 20. |
| IR-861 | Cap development at 3 and production at 10 instances. |
| IR-862 | Disable session affinity. |
| IR-863 | Attach a dedicated least-privilege runtime service account. |
| IR-864 | Use ADC in hosted runtime and preserve explicit credentials/emulators only for local tooling. |
| IR-865 | Use `/v1/health` for startup and liveness probes. |
| IR-866 | Use instance-based CPU/billing so the retained five-minute account-deletion reconciler can run while an instance exists. |
| IR-867 | Use regional Artifact Registry in `us-west1`. |
| IR-868 | Use a dedicated Cloud Tasks OIDC signer and exact handler audience. |
| IR-869 | Bind exact enabled Secret Manager versions; rotate by deploying a new candidate revision. |
| IR-870 | Disable startup CPU boost. |
| IR-871 | Use stable development and production `run.app` URLs; do not add a custom backend domain. |
| IR-872 | Use the second-generation Cloud Run execution environment. |
| IR-873 | Set startup probe GET `/v1/health` to period 10s, timeout 5s, failure threshold 24; set liveness to period 10s, timeout 5s, failure threshold 5. |
| IR-874 | Finish application shutdown in about 8 seconds inside Cloud Run's 10-second termination window. |
| IR-875 | Use separate 1 GiB development Basic and production Standard-HA Memorystore instances. |
| IR-876 | Require Redis AUTH plus verified TLS, with no plaintext fallback. |
| IR-877 | Keep one account-deletion queue per environment with concurrency 1, attempts 5, and 1,500-second dispatch deadline. |
| IR-878 | Keep Firestore durable deletion state plus the in-service reconciler; do not add a DLQ. |
| IR-879 | Keep sanitized Cloud Run request/system/stdout/stderr logging and the already retained external telemetry owners. |
| IR-880 | Add only production health-unreachable and Cloud Run 5xx alerts with an owned notification channel. |
| IR-881 | Add alert-only monthly development and production budgets at 50/80/100 percent; do not automate shutdown. |
| IR-882 | Keep zero-traffic Cloud Run revisions; do not add a custom revision-deletion job. |
| IR-883 | Tag with the full commit SHA, capture the resulting `sha256` digest, and use that digest for smoke, deploy, promote, recovery, and evidence. |
| IR-884 | Retain an environment-scoped build cache whose failure safely falls back to a full build. |
| IR-885 | Limit artifact cleanup to untagged artifacts older than 30 days, with dry-run evidence first, while retaining exact release images. |
| IR-886 | Set `_Default` log retention to 30 days with no external log archive. |
| IR-890 | Keep Firestore index control safe, create-only, project-matched, WIF-authenticated, and isolated from serving deployment. |
| IR-891 | Adapt S-26's local/offline harness to the final Firebase, Redis, provider/Dodo-disabled, STT, account-deletion, runtime, and deployment seams. |

Related constraints are S-08's Firebase/account lifecycle ownership, S-09's telemetry and sanitization ownership, S-18's `BILLING_MODE=disabled` Dodo boundary, S-20's fair-use facts, S-25's canonical account-deletion topology and still-open BL-002 inventory, S-26's one-app/harness output, S-29's exclusive signing/update/release-system ownership, S-31's final BL-001/BL-002/provider/Dodo composition, `PRODUCT.md`, and the protected behavior register in `deletion-map.md`.

## 5. Dependencies and entry gates

### Repository gates

| Gate | Affected cycles | Safe work before it opens | Evidence that opens it | Owner / authorization |
|---|---|---|---|---|
| Integrated S-26 on current `origin/main` | All; Cycles 1-19 are blocked without it | Rebase, read-only inventory, compare the S-26 closeout to sections 6-7 | One canonical app/URL contract; survivor routers, runtime images, index registry, OpenAPI/generated client, and offline harness green on one committed SHA | S-26 owner; no live authority required |
| S-08, S-09, S-18, S-20 retained owners integrated | Cycles 1, 4, 6-9, 14-19 | Characterize only; do not reimplement their behavior | Their guard tests pass at the execution SHA and no conflicting owner appears | Predecessor owners |
| BL-002 read-only live inventory refreshed | Operational deletion/rename/creation decisions | All repository RED/GREEN work that does not claim live closure | Sanitized `gcloud`/Firebase inventory captured using a verified operator principal; every S-25/S-27 resource classified | Cloud operator; read-only identity required |
| BL-001 final provider qualification | Final all-waves closure only | All S-27 repository work and scoped development qualification | S-31 evidence on one final committed SHA | S-31 owner |

### Missing external inputs

None of these may be guessed from Omi/based-hardware names or the retired OpenTofu pilot.

| Missing input | Affected cycles | Safe work that can proceed | Reopen evidence | Expected owner / extra authority |
|---|---|---|---|---|
| Owned development/production GCP project IDs, project numbers, and billing-account mapping | 2-19 | Schemas, fake-backed tests, placeholder rejection, local renders | Written environment values verified with read-only `gcloud projects describe` and billing association evidence | Product/cloud owner; mutation separately authorized |
| GitHub repository numeric ID, owner numeric ID, exact workflow refs, GitHub environments, WIF pool/provider names, and service-account emails | 2, 11-14 | WIF claim-policy tests and fail-closed render logic | GitHub/GCP identity record plus successful no-secret WIF token/impersonation probe | Repository and cloud owner; provider/IAM creation authorized separately |
| Least-privilege capability matrix for deploy, runtime, Firestore reader/writer, task signer, bucket publisher, alert/budget operator | 2-10, 14-18 | Map current API calls and write denial tests | Role bindings reviewed against exact retained operations; denied negative probes | Cloud/security owner; IAM changes separately authorized |
| Owned VPC, subnet, private-service-access range, VPC connector/direct-egress decision, and DNS/private-path coordinates in `us-west1` | 5-7 | Client TLS tests and manifest validation | Network inventory plus approved, non-overlapping CIDR/private-service-access plan | Cloud/network owner; network mutation separately authorized |
| Memorystore instance names/IP or DNS, server CA material, AUTH secret container/version, and rotation procedure for each environment | 6-7 | Hermetic TLS/AUTH/failure-policy tests | Instance describe plus verified CA chain and exact secret-version metadata, never values in evidence | Cloud/security owner; Redis creation/rotation authorized separately |
| Exact retained Secret Manager names and enabled version numbers, including provider, auth, metrics, update/preview, and Redis values | 3, 7-14 | Secret-reference schema and fake rotation tests | Sanitized secret metadata inventory and consumer/role mapping | Secret owners; binding/rotation separately authorized |
| Product-owned GCS bucket name, location, public-access policy, retention/lifecycle, runtime-reader and future S-29 publisher identities | 9, 15, 19 | Storage adapter/config tests and deny-by-default policy checks | Bucket/IAM/lifecycle decision and read-only describe evidence | Cloud owner plus S-29 handoff owner; bucket/IAM mutation separately authorized |
| Artifact Registry repository name and cleanup policy target | 10-19 | Digest/lineage/cache/cleanup dry-run tests | Repository describe and reviewed dry-run deletion candidates | Cloud/release owner; creation/deletion separately authorized |
| Stable Cloud Run service names/`run.app` URLs, runtime/deploy service accounts, task queue/signer names | 4-14, 19 | Local route, config, URL-resolution, and fake task tests | Development then production service/IAM/queue describe evidence | Cloud owner; create/deploy/traffic changes separately authorized |
| Alert notification channel ID, budget monthly amounts/currency, and recipients per environment | 15-16 | Threshold/schema tests and redacted render | Owned channel, billing scopes, approved amounts and recipients | Finance/on-call owner; creation separately authorized |
| Disposable owned development account and explicit permission for destructive deletion acceptance | Cycle 19 only | Fake-backed and emulator deletion tests | Account ownership proof and one-run mutation approval | Test/account owner; explicit destructive authorization required |

If an external gate stays closed, commit only the independently verifiable repository cycles before it, leave the blocked cycle open, and do not weaken validation, copy a production secret, use an Omi identity, or describe the slice as operationally closed.

## 6. Current production codeflow

The following is the pinned pre-S-26 flow and must be refreshed after S-26 integrates.

1. **Source admission and build.** `release-eligibility.yml` emits exact-main evidence. `gcp_backend_auto_dev.yml` consumes a successful first-attempt same-repository proof; `gcp_backend.yml` admits an exact main SHA for manual deploy. Both authenticate with `GCP_CREDENTIALS`, build `backend/Dockerfile`, and publish `gcr.io/<project>/backend:latest`, a seven-character SHA tag, and `:buildcache`.
2. **Runtime rendering.** `backend/deploy/runtime_env.yaml` declares two based-hardware environments in `us-central1`. `render_backend_runtime_env.py`, `validate-backend-runtime-env.py`, durable-dispatch checks, preflight scripts, workflow contracts, and release-vector scripts validate or consume it. The manifest does not yet declare all required capacity, probe, execution-generation, service-account, CPU-policy, or exact-secret-version fields.
3. **Candidate and traffic.** Backend workflows deploy a no-traffic revision with a 1,500-second timeout, run health/candidate checks, snapshot traffic, promote an exact revision, verify the serving vector, remove temporary tags, and restore the prior split on failure. Manual traffic repair and break-glass already exist but use inherited identity and image conventions.
4. **Application startup/shutdown.** `backend/main.py` loads environment variables, prepares Google credentials, initializes Firebase, mounts retained routers, validates account-deletion configuration, and starts the five-minute deletion reconciler. Shutdown drains background work with a ten-second timeout before closing clients. `backend/desktop_backend.py` is still a second app with wildcard CORS; S-26 must remove that split before S-27 starts.
5. **Public routes.** `/v1/health` supports GET/HEAD and returns `{"status":"ok"}`. S-26 deletes the service-specific `/health` and `/ready` aliases after migrating their callers, while retaining any required dependency-admission check in a canonical non-route deploy/validation seam. `/metrics` requires `METRICS_SECRET`; retained auth, fair-use/quota, model, STT, `/v4/listen`, update/preview, and account routes enforce their current policies. `main.py` has empty default CORS and rejects `*`; the second app does not.
6. **Google credentials.** `database/google_credentials.py` writes `SERVICE_ACCOUNT_JSON` or inline `GOOGLE_APPLICATION_CREDENTIALS` to `/tmp/omi-google-credentials.json`, otherwise uses ADC. That explicit path remains valid for local tools/emulators but not hosted Cloud Run after a runtime service account exists.
7. **Redis.** `database/redis_db.py` constructs a plaintext global `redis.Redis` client at import from host/port/password and registers Lua scripts immediately. `utils/translation_core/cache.py` constructs another client. Cache, OAuth session/code, limits, locks, invalidation, pub/sub, VAD, fair-use, update, and signed-URL callers have different fail-open/fail-closed behavior that must not be homogenized.
8. **Firestore.** `database/firestore_index_registry.py` and `firestore.indexes.json` currently list stale-conversation, starred-session, and fair-use indexes. S-26 owns pruning this to actual survivors. Deploy readiness runs a create-only check with `GCP_FIRESTORE_READONLY_CREDENTIALS`; the manual writer uses the same project lock and waits for provisioning.
9. **GCS.** `utils/other/storage.py` lazily builds a Storage client, signs update URLs, and caches them in Redis using `BUCKET_DESKTOP_UPDATES`. `database/desktop_previews.py` hard-codes `omi_macos_updates` and a storage URL. S-24 authorizes only update/preview storage; S-29 owns artifact publication, signing, feeds, preview lifecycle, and channel release behavior.
10. **Account deletion.** `utils/cloud_tasks.py` enqueues an opaque job ID under a deterministic task name, with a 1,500-second per-task dispatch deadline, exact handler URL/audience, and OIDC signer. Firestore owns durable state; a five-minute reconciler repairs dispatch; queue config is attempts 5/concurrency 1. The legacy signer/audience branch cannot disappear until S-25's live drain proof exists.
11. **Observability and cost.** Cloud Run emits request/system/application logs, while Sentry/PostHog/LangSmith retain their own owners and sensitive log content is supposed to be sanitized. The repository does not yet own the required 30-day `_Default` retention, production health and 5xx alert pair, notification channel, or two monthly alert-only budgets.

## 7. Complete caller and dependency inventory

This is the planning-baseline ledger. Cycle 0 must regenerate it from integrated S-26 and classify additions before edits.

### Deployment, identity, and image surfaces

| Surface | Current callers/owners | S-27 disposition |
|---|---|---|
| `backend/main.py`, `backend/desktop_backend.py` | Runtime entrypoints and local harness | Consume S-26's one app; never merge them in S-27. |
| `backend/runtime_images.json`, `backend/Dockerfile`, `backend/Dockerfile.desktop_backend` | Runtime-image closure and build workflows | Consume S-26's single image; adapt surviving Dockerfile/base/user/filesystem contract. |
| `backend/deploy/runtime_env.yaml` | Render, validate, deploy, task, release-vector, test and documentation consumers | Make this the one environment declaration for retained foundation coordinates and policy; never store secret values. |
| `gcp_backend.yml`, `gcp_backend_auto_dev.yml`, `release-eligibility.yml` | Manual production/dev deploy, automatic dev, exact-source admission | Adapt WIF, regional registry, digest lineage, capacity/probes/network/IAM, promotion/rollback. |
| `gcp_firestore_indexes.yml` | Isolated check/proposal/manual index apply | Adapt to environment-scoped WIF reader/writer while preserving create-only/project-match rules. |
| Deployment helpers/tests | `preflight-cloud-run-deploy.py`, env render/validate, health/candidate/tagged-URL/traffic-snapshot/release-vector/deploy-status/repair scripts and tests | Extend shared primitives; do not add a parallel deploy framework. |
| Workflow policy | `.github/AGENTS.md`, `.github/checks-manifest.yaml`, deployment-concurrency/admission/secret-boundary/workflow-contract checks | Update the existing deterministic lanes and `backend/testing/workflow_contracts.json`. |
| OpenTofu pilot/foundation | `infrastructure/opentofu/**`, two OpenTofu workflows, pilot/foundation checkers and tests | Delete in Cycle 2 after the direct WIF contract has RED/GREEN coverage. |

### Redis callers and policies

| Caller family | Production surfaces | Retained policy to characterize before client changes |
|---|---|---|
| Shared client and scripts | `database/redis_db.py` | Lazy, injected client; TLS/AUTH mandatory hosted; no import I/O; preserve wrapper return semantics. |
| Generic/user/update/tool caches | `database/auth.py`, `database/users.py`, `routers/updates.py`, `utils/subscription.py`, `utils/desktop_update_resolver.py`, `utils/github_releases.py`, `utils/other/storage.py`, `utils/retrieval/tools/omi_tools.py`, `utils/stt/vad.py` | Cache loss must follow each current fallback; it must not silently change correctness. |
| OAuth | `routers/auth.py`, auth-session and auth-code functions in `redis_db.py` | Explicitly fail closed where a one-time session/code is authoritative. |
| Request/fair-use limits | `routers/chat.py`, `routers/desktop_chat.py`, `routers/desktop_proxy.py`, `routers/desktop_tts_updates.py`, `utils/other/endpoints.py`, `utils/fair_use.py`, `utils/fair_use_reviews.py`, `utils/voice_duration_limiter.py`, TTS and listen locks in `redis_db.py` | Preserve each current allow/deny/fallback and `record_fallback` behavior; do not invent one global fail-open rule. |
| Locks/invalidation | `database/job_run_locks.py`, `routers/listen/runtime.py`, `utils/billing/service.py`, listen/device/platform locks and credit invalidation in `redis_db.py` | Atomic Lua/NX/expiry semantics remain; account-deletion idempotency and billing-to-listen invalidation must not weaken. |
| Firestore cache/pub-sub | `database/firestore_cache.py`, `database/cache.py`, `database/redis_pubsub.py` | Cache/pub-sub outage must preserve authoritative Firestore reads and current observability. |
| Translation cache | `utils/translation_core/cache.py` | Converge its separate Redis construction on the same verified connection factory without changing key/fallback behavior. |
| Canonical dependency admission | S-26's non-route deploy/validation seam after `/ready` deletion | Required Redis/TLS/auth checks run through the canonical deployment owner and must not report ready on failure; they do not recreate a public readiness alias. |
| Harness | `testing/e2e/fakes/redis.py`, `testing/e2e/conftest.py`, unit/integration Redis tests | Extend fake boundary to exercise TLS configuration separately from hermetic functional behavior. |

Any Redis caller surviving S-26 but absent above is a Cycle 0 stop condition, not permission to inherit a default policy.

### Firestore, GCS, tasks, and runtime callers

| Dependency | Current retained owners/callers | S-27 boundary |
|---|---|---|
| Firestore runtime data | Firebase users/account-deletion jobs; billing/subscription/usage; fair-use facts/events/reviews; desktop release/update/pointers/admission; previews | Own project/runtime IAM and ADC only. Do not redesign collections, migrate product behavior, or restore S-23/S-24 data. |
| Firestore indexes | `firestore_index_registry.py`, `firestore.indexes.json`, generator, query-coverage ratchet, reconciler, readiness/writer workflow | Consume S-26 survivor registry; keep exact create-only, project-matched, read-only readiness and manual writer. |
| GCS runtime read/sign | `utils/other/storage.py`, `database/desktop_previews.py`, `routers/updates.py`, update/preview unit tests | Own bucket coordinate, runtime access, TLS URL/config seam, and minimum IAM. S-29 owns publisher/release/signing identities and artifact lifecycle. |
| Cloud Tasks enqueue/auth | `utils/cloud_tasks.py`, account-deletion route/service tests, runtime env durable-dispatch contract | Own queue, signer, invoker binding, canonical URL/region, attempts/concurrency/deadline; retain opaque payload and exact auth. |
| Deletion durability | Firestore account-deletion state, `database/job_run_locks.py`, startup reconciler in canonical app | Preserve persist-before-success, retry, duplicate delivery, terminal state, cancellation semantics, and five-minute repair. No DLQ. |
| Runtime routes | health, metrics, auth, fair-use/quota, model, STT/listen, update/preview, account lifecycle | Public ingress does not make routes anonymous; retain current route auth and empty CORS. |
| Mac consumers | generated app client/API URL selection, WebSocket listen/reconnect, auth, typed chat/model/STT, update reads, account lifecycle | S-27 may validate and narrowly repair reconnect/config behavior required by IR-856; no bundle/signing/feed/promotion ownership. |
| Telemetry | Cloud Run logs/metrics, sanitizer, Sentry, PostHog, LangSmith, fallback helpers | Own provider-native log/alert configuration; preserve S-09 tools and never log secret values, tokens, raw payloads, or PII. |

## 8. Behavior classification

| Classification | S-27 work |
|---|---|
| KEEP AS IS | Canonical route semantics and auth; `/v1/health`; authenticated `/metrics`; STT/listen protocol and Mac reconnect intent; model/provider choices; quota/fair-use behavior; free MVP with `BILLING_MODE=disabled`; Firestore durable deletion plus reconciler; exact task payload/auth/idempotency; safe create-only Firestore index control; update/preview read semantics; candidate/promotion/rollback/repair/break-glass intent; sanitized Sentry/PostHog/LangSmith ownership. |
| ADAPT | Owned project/region/service coordinates; WIF and service accounts; ADC; exact secret versions; Cloud Run capacity/probes/generation/billing/network; Redis TLS/AUTH and topology; survivor Firestore index environment identity; retained GCS bucket/IAM/config; task queue/signer; regional registry/digest lineage; workflows; logging retention; alerts; budgets; local/offline harness. |
| DELETE | Based-hardware/Omi cloud names after owned replacements are proven; `GCP_CREDENTIALS`, `GCP_FIRESTORE_READONLY_CREDENTIALS`, hosted `SERVICE_ACCOUNT_JSON`; GCR, `latest`, seven-character image identity; plaintext Redis path; wildcard CORS inherited from any pre-S-26 app; OpenTofu foundation/pilot/probe/workflows/checkers/tests/docs; stale S-26-deleted index/config/service residue. Historical changelogs remain. |
| SIMPLIFY AFTER | One environment manifest, one image lineage, one Redis connection factory, one canonical service URL per environment, direct WIF configuration, one set of shared deployment primitives, and survivor-only IAM/secret/index/bucket matrices—but only after callers and live state are proven. |
| ACCELERATE AFTER | Measure focused runtime-env/workflow tests, image build/cache hit rate, candidate readiness, deploy-to-health, rollback, and named-bundle reconnect time. Shorten only a measured bottleneck; cache failure must remain a safe full build. |
| AUTOMATE LAST | Automatic exact-main development deploy remains only after identity/resource contracts are stable. Cleanup may become a bounded registry policy after a reviewed dry run. Do not invent scheduled resource reconciliation, revision deletion, shutdown-on-budget, or a replacement IaC platform. |
| OUT OF SCOPE / DEFERRED | S-29 signing/notarization/Sparkle/feed/channel/candidate-publication system; S-28 storage/bundle identity; S-30 public/legal/brand work; S-31 final provider continuity, BL-001/BL-002 closure, Dodo test/live activation; custom backend domain; private product-data GCS; external log archive; Redis/task/per-route paging; DLQ; production app operation; live resource decommission without explicit authority. |

## 9. Retained behavioral invariants

1. The S-26 app is the sole Python product/runtime authority; S-27 must not add a second app, service URL, compatibility router, alias, or fake-success path.
2. Public Cloud Run reachability does not bypass Firebase/admin/OIDC/metrics authorization. `/v1/health` alone retains its unauthenticated GET/HEAD contract. CORS stays empty/default-deny and rejects wildcard input.
3. `/v4/listen` keeps authentication, transcript wire shape, STT/provider semantics, VAD, fair-use/accounting, disconnect/reconnect, late-result owner fencing, and local Mac ownership. A 60-minute server timeout does not promise an immortal socket.
4. Billing remains disabled and the MVP remains free. Dodo configuration may remain a validated disabled seam, but no checkout, portal, transaction, webhook replay, or provider resource is activated here.
5. Redis is coordination/cache, not a new product authority. Every caller keeps its documented fail-open, fail-closed, retry, idempotency, TTL, atomicity, and fallback-telemetry behavior.
6. Firestore keeps only retained shared-backend facts. S-27 changes identity/index operations, not collection meaning, user ownership, account isolation, or local authorities.
7. Account deletion persists intent before reporting success, sends only an opaque job ID, authenticates exact signer/audience, runs at most one worker per job, retries safely, handles duplicate delivery, and reconciles stranded work without a DLQ.
8. The GCS bucket contains only update/preview artifacts. Runtime reads/signing and future S-29 publication use least privilege; private recordings, attachments, screenshots, transcripts, or user data never return.
9. Image admission, smoke, candidate, promotion, rollback, recovery, and evidence all name one captured digest produced from one full admitted commit SHA. Tags cannot substitute for digest equality.
10. A failed candidate leaves serving traffic unchanged; a failed promotion restores the exact prior traffic split; repair and break-glass are disclosed, bounded, source-independent where promised, and produce redacted evidence.
11. Production minimum 1 plus instance-based CPU permits the reconciler to run; development minimum 0 explicitly does not promise continuous reconciliation while scaled to zero.
12. Logs and evidence contain no secret values, bearer/Firebase tokens, raw provider payloads, audio/transcripts, email addresses, or other PII. Existing sanitization and fallback telemetry stay in force.
13. No production Omi/Omi Beta process or bundle is launched, stopped, replaced, or automated. All Mac acceptance uses `omi-wave5-s27` or an S-29-owned artifact later.
14. Repository work, read-only live inventory, and live mutation are separate authorities. A green manifest is not proof a resource exists; a `gcloud describe` is not permission to change it.

### Pre-agreed public seams for TDD

The user-authorized requirement decisions establish these seams: assembled FastAPI requests/WebSockets; `RuntimeEnvironment` render/validation output; lazy Redis/Google/Storage/Tasks provider factories with injected fakes; generated Firestore index proposal; immutable image/release-vector records; workflow event/input contracts; Cloud Run/Redis/Firestore/GCS/Tasks read-only describe JSON; and named-bundle health/listen/account actions. Tests should assert results at these seams. Source searches are only labelled static tripwires.

## 10. Target authority, ownership, identity, and topology model

### Environment topology

| Contract | Development | Production |
|---|---|---|
| Project | Owned project ID/number supplied externally | Separate owned project ID/number supplied externally |
| Region | `us-west1` | `us-west1` |
| Cloud Run | One canonical S-26 service, stable `run.app` URL | One canonical S-26 service, separate stable `run.app` URL |
| Compute | gen2, 2 vCPU, 4 GiB, concurrency 20, timeout 3600s, min 0, max 3, no affinity, instance-based billing, startup boost off | Same except min 1, max 10 |
| Probes | Startup GET `/v1/health`: 10s/5s/24; liveness GET `/v1/health`: 10s/5s/5 | Same |
| Network | Public service ingress plus route auth; private path to dependencies in owned VPC/subnet/range | Separate owned network coordinates with the same policy |
| Redis | 1 GiB Basic, AUTH, verified TLS, no plaintext fallback | 1 GiB Standard HA, AUTH, verified TLS, no plaintext fallback |
| Firestore | Retained S-26 collections/indexes only; runtime ADC; isolated WIF index check/writer | Same, strictly separate project |
| Cloud Tasks | One account-deletion queue; concurrency 1; attempts 5; deadline 1500s; dedicated signer | Separate queue/signer with the same contract |
| GCS | Product-owned update/preview bucket coordinate and minimum IAM; environment choice must be explicit | Product-owned retained bucket coordinate; S-29 publication handoff explicit |
| Registry | Regional Artifact Registry; full SHA tag + captured digest; environment cache | Separate environment repository or explicitly partitioned repository, decided from owned inputs |
| Logging/alerts/budget | 30-day `_Default`; no paging; alert-only budget 50/80/100 | 30-day `_Default`; health and 5xx alerts; alert-only budget 50/80/100 |

### Identity and capability model

| Principal | Allowed | Explicitly not allowed |
|---|---|---|
| GitHub deploy principal per environment | WIF from exact repository/workflow/environment/main; build/push candidate; deploy no traffic; inspect/promote/restore this service; configure declared queue/IAM only in an authorized lane | Cross-environment impersonation, arbitrary repository refs, secret-value read unless strictly required, Firestore data mutation |
| Cloud Run runtime service account | Read required exact secret versions through bindings, retained Firestore operations, enqueue account-deletion tasks, required GCS reads/signing, Redis network/auth use | Deploy/traffic/IAM mutation, index creation, Artifact Registry deletion, cross-environment access |
| Firestore readiness principal | Read index metadata and generate redacted create-only proposal in exact project | Index writes or document reads/writes beyond required metadata |
| Firestore writer principal | Manual, admitted-main, create-only index application in exact project | Serving deploy, destructive index deletion, cross-project apply |
| Account-deletion task signer | Mint OIDC for exact canonical handler audience; be admitted only by that route | Invoke unrelated authenticated routes, deploy, inspect data |
| Future S-29 publisher | Write only approved update/preview object prefixes and required metadata | Runtime/project administration, backend traffic, private product data |
| Read-only inventory operator | Describe projects/resources/IAM metadata with sanitized output | Any create/update/delete/traffic/secret-value/data action |

`backend/deploy/runtime_env.yaml` remains the environment contract unless integrated S-26 establishes a deeper shared primitive. Values known only after resource creation must be explicit required inputs or captured sanitized outputs; defaults must not silently point at based-hardware, Omi, `us-central1`, GCR, or `latest`.

## 11. Ordered TDD cycles

All tests and source/config changes below are future implementation work. “Static tripwire” means a source/config residue assertion, not behavioral coverage. Each cycle is a separate testable commit candidate unless a smaller adjacent pair cannot be verified independently.

### Cycle 0 — execution-time rebase, predecessor gate, and authoritative inventory

- **Intended RED:** An extended topology characterization rejects any unclassified app, route, image, workflow, identity, secret binding, Redis client/caller, Firestore collection/index/query, GCS prefix/caller, task queue/signer, region, alert, budget, or live-resource name; assembled-app and offline-harness characterization cover every invariant in section 9.
- **Why it fails now:** the pinned tree predates S-26, has two Python apps/images, inherited cloud names, three Firestore indexes, JSON credentials, and BL-002 `unknown` live classifications.
- **Minimum GREEN:** rebase, prove S-26 integrated, rerun repository and sanitized read-only inventories, classify every hit as retained/S-27/predecessor/successor/unknown-live/already absent, capture baseline failures, and make no product/config mutation.
- **Retained behavior:** all predecessor output and every section 9 invariant.
- **Expected surfaces:** new/extended S-27 characterization tests and execution notes; no production file in this cycle.
- **Exact focused verification:** requirements validator; S-26 assembled app, route-policy/OpenAPI/runtime-image/index/harness checks; section 13 searches; `git diff --check`.
- **Deletion/simplification enabled:** freezes the actual survivor set and exact safe ordering.
- **Stop:** S-26 absent, any requirement conflict, unclassified caller, non-clean worktree overlap, or inability to distinguish repository state from live state.

### Cycle 1 — protect health, route auth, CORS, streaming, and free-mode behavior

- **Intended RED:** Through S-26's assembled FastAPI app and fake external boundaries, GET/HEAD `/v1/health` retains its exact behavior, `/health` and `/ready` return 404, required Redis/dependency admission fails closed through the canonical non-route deploy/validation seam, `/metrics` and retained product routes enforce their exact auth, wildcard origins are rejected and no CORS allow-origin is emitted, and listen streaming/reconnect plus `BILLING_MODE=disabled` work when infrastructure identities are absent.
- **Why it fails now:** no single post-S-26 assembled seam exists at this baseline, and the second current app has wildcard CORS; infrastructure changes could otherwise mask product regressions.
- **Minimum GREEN:** add/extend behavior tests and only the narrow S-26 integration fixes needed to make one app's route policy authoritative; do not change endpoint semantics.
- **Retained behavior:** health, metrics secrecy, auth, STT/listen wire behavior, quota/fair-use, free MVP, provider semantics.
- **Expected surfaces:** assembled-app/offline tests, route policy/OpenAPI only if S-26 output is inconsistent, `backend/testing/workflow_contracts.json` if a covered high-risk path changes.
- **Exact focused verification:** focused health/metrics/CORS/listen/billing tests through `desktop/macos/scripts/dev-feedback.py --once python ...`; `backend/testing/e2e/run.sh`; route-policy and OpenAPI runner.
- **Deletion/simplification enabled:** permits public Cloud Run ingress and one service without relying on network obscurity or a second app.
- **Stop:** any retained route lacks an authoritative authentication policy or behavior differs from S-26/predecessor guards.

### Cycle 2 — replace GitHub JSON keys with direct environment-scoped WIF and delete the OpenTofu experiment

- **Intended RED:** Workflow-event tests exchange an exact repository/workflow/environment/main OIDC claim for only the matching deploy or index principal; branch, fork, environment, workflow, owner/repository ID, and cross-environment mutations are denied. Static tripwires reject `GCP_CREDENTIALS`, `GCP_FIRESTORE_READONLY_CREDENTIALS`, and the entire OpenTofu pilot/foundation/probe surface.
- **Why it fails now:** backend and index workflows decode long-lived JSON keys; the development WIF pilot hard-codes based-hardware/Omi claims and only grants a read probe; OpenTofu foundation scaffolding remains.
- **Minimum GREEN:** add direct narrow WIF authentication to existing workflows, require exact external claim/resource inputs, keep deploy/index principals distinct, test negative claims, then delete `infrastructure/opentofu/**`, its workflows, checkers, tests, docs, and check-manifest registrations.
- **Retained behavior:** exact-main admission, environment separation, deploy concurrency, source-independent traffic repair, isolated Firestore readiness/writer.
- **Expected surfaces:** `gcp_backend*.yml`, `gcp_firestore_indexes.yml`, release admission helpers/tests, deployment-secret boundary, workflow contracts/check manifest, deletion of OpenTofu surfaces; matching `.github/AGENTS.md`/backend guide updates.
- **Exact focused verification:** workflow unit tests, deployment-secret-boundary tests, workflow contracts, actionlint via `make preflight`, and an authorized no-secret development WIF read/impersonation probe.
- **Deletion/simplification enabled:** removes long-lived GitHub cloud keys and the provisional IaC platform.
- **Stop:** exact numeric GitHub claims, environment protection, GCP provider/service-account resources, or negative cross-environment proof are unavailable; live WIF/IAM creation needs separate authorization.

### Cycle 3 — attach dedicated runtime identity, ADC, and exact secret versions

- **Intended RED:** A rendered candidate names one environment runtime service account and exact enabled secret versions; the production Google/Storage/Firestore/Tasks factories use ADC without writing a credential file; local explicit credentials/emulators still work; a missing/disabled/latest secret binding fails before traffic.
- **Why it fails now:** workflows bind `:latest`; runtime config carries `SERVICE_ACCOUNT_JSON`; `google_credentials.py` can write `/tmp/omi-google-credentials.json`; no Cloud Run runtime service account/capability contract is declared.
- **Minimum GREEN:** add runtime-service-account and exact-version schema/rendering, attach it at deploy, grant only the current retained capability matrix, make hosted mode ADC-only, and keep explicit local credential seams gated to local/test profiles.
- **Retained behavior:** Firebase auth, Firestore data access, task enqueue, update/preview reads/signing, provider access, local harness/emulators, rotation by new candidate.
- **Expected surfaces:** runtime manifest/render/validator; Google/Storage/Firestore/Tasks factories; deployment workflows; secret-boundary/runtime-env tests; docs.
- **Exact focused verification:** Google credential and runtime-env render/validator tests; injected ADC/storage/task behavior; missing/wrong-version candidate preflight; authorized IAM/secret-version metadata describe and negative permission probes.
- **Deletion/simplification enabled:** removes hosted JSON file credentials and floating secret versions.
- **Stop:** secret names/versions or least-privilege roles are unknown, signing a GCS URL needs an unreviewed token-creator grant, or any runtime principal spans both environments.

### Cycle 4 — harden the one runtime image and bounded shutdown

- **Intended RED:** The runtime-image smoke launches the S-26 app from an official Python 3.11 slim base pinned by immutable identity, as UID/GID 10001, with read-only application code and only declared temp/cache paths writable; SIGTERM finishes intake stop, background drain, reconciler/task/client closure, and process exit in about 8 seconds.
- **Why it fails now:** the base is `gcr.io/based-hardware-dev/...`; the image recursively owns `/app`; runtime-image records still include two images; application drain allows 10 seconds before other closure.
- **Minimum GREEN:** consume S-26's single image, pin the owned official base digest, copy code with restrictive ownership/mode, declare only needed temp paths, and budget shutdown phases to complete by roughly 8 seconds while preserving safe cancellation.
- **Retained behavior:** ffmpeg/ONNX/runtime dependencies, health/startup, listen disconnect semantics, background task supervision, account-deletion reconciliation.
- **Expected surfaces:** surviving Dockerfile, runtime-image registry/lock data, lifecycle/executor code, image and shutdown tests, backend guide.
- **Exact focused verification:** `make runtime-image-source-closure`; `make runtime-image-smoke SERVICE=backend`; container UID/write-denial probes; focused lifecycle tests with controllable clocks/tasks; local SIGTERM smoke.
- **Deletion/simplification enabled:** deletes inherited base/image and broad writable application tree.
- **Stop:** official base digest/provenance is unverified, a retained dependency cannot run non-root, or forced timing would abandon durable work rather than leave it retryable.

### Cycle 5 — declare and render the canonical Cloud Run contract

- **Intended RED:** Given development or production manifest input, the deployment command model emits exactly the section 10 Cloud Run region/capacity/generation/probe/billing/network/service-account settings and rejects absent/default/drifted values, wildcard CORS, custom-domain, affinity, request-based CPU, or startup boost.
- **Why it fails now:** current workflows hard-code `us-central1`, timeout 1500s, and omit several required settings; current manifest cannot express the target contract.
- **Minimum GREEN:** extend the authoritative runtime manifest and shared renderer/preflight; make both deployment workflows consume the same typed output; keep stable `run.app` URL discovery and route-level auth.
- **Retained behavior:** one S-26 app, candidate-no-traffic, health, 60-minute listen ceiling, Mac reconnect, private dependency access, exact environment isolation.
- **Expected surfaces:** runtime manifest/schema/render/validator, preflight/deploy helpers, both backend workflows, Cloud Run tests/contracts, service documentation.
- **Exact focused verification:** runtime-env renderer/validator and preflight tests for both environments and every negative drift; workflow contracts; local assembled health/listen; authorized `gcloud run services describe` comparison only after deployment approval.
- **Deletion/simplification enabled:** removes hard-coded region/service flags and platform-default ambiguity.
- **Stop:** S-26 service name, owned projects/network coordinates, service account, or stable URL is unknown; any planned setting conflicts with a measured retained path.

### Cycle 6 — make Redis a lazy shared TLS/AUTH boundary without changing caller policy

- **Intended RED:** Through one injected production Redis factory, correct CA+AUTH establishes a verified TLS connection; missing CA/password, hostname mismatch, certificate failure, or plaintext URL fails closed at connection setup. Caller-specific tests separately prove existing cache/lock/OAuth/limit/fair-use/pub-sub/translation failure policies.
- **Why it fails now:** `redis_db.py` creates plaintext Redis and Lua scripts at import, while translation constructs a second client; current tests do not cover verified TLS configuration across the caller matrix.
- **Minimum GREEN:** introduce one lazy environment-aware client/factory, pass TLS CA and AUTH from validated config/secret version, move Lua registration behind initialization, converge translation/pub-sub/cache callers, and retain each wrapper's exact return/telemetry behavior.
- **Retained behavior:** keys, TTLs, atomic scripts, rate limits, locks, OAuth single use, cache fallbacks, Firestore authority, fair-use decisions, update/VAD/translation results.
- **Expected surfaces:** Redis/cache/pub-sub/translation/fair-use/limit modules, runtime config, harness fake adapter, focused unit/integration tests, architecture docs.
- **Exact focused verification:** Redis serialization/cache/Firestore-cache/rate-limit/voice/fair-use/auth/translation tests; import-purity scan; hermetic fake Redis E2E; local TLS test server or container with bad-CA/hostname/plaintext negatives.
- **Deletion/simplification enabled:** removes global import-time client, plaintext fallback, and duplicate translation client construction.
- **Stop:** any S-26 survivor caller is unclassified, a caller's outage policy is ambiguous, or CA/secret material would be embedded or logged.

### Cycle 7 — own separate private Memorystore foundations

- **Intended RED:** A development/production resource-contract render requires `us-west1`, 1 GiB, private-service access, AUTH, in-transit encryption, dev Basic versus prod Standard HA, and environment-unique instance/network/secret coordinates; sanitized describe comparison rejects any drift.
- **Why it fails now:** no authoritative instance topology exists, current network is inherited `us-central1`, and runtime Redis config has no verified TLS/CA contract.
- **Minimum GREEN:** add validated Redis/network declarations to the existing environment manifest and authorized deploy/resource lane, thread sanitized outputs into Cycle 6 config, and add rollback that leaves the previous reachable instance/secret binding intact until candidate proof.
- **Retained behavior:** all Cycle 6 caller policies and environment isolation.
- **Expected surfaces:** runtime manifest/render/validator, existing backend deployment/resource workflow and contracts, Redis readiness probe, docs; no replacement IaC platform.
- **Exact focused verification:** deterministic render tests; fake `gcloud redis instances describe` drift tests; authorized dev describe/connect/read-write-expire/Lua/TLS proof; separate prod describe/HA proof when authorized.
- **Deletion/simplification enabled:** allows removal of inherited Redis/network bindings only after read-only inventory and rollback proof.
- **Stop:** project/network/private range/CA/AUTH inputs are missing, CIDRs overlap, dev/prod share a Redis instance or secret, or live mutation has not been authorized.

### Cycle 8 — bind survivor Firestore indexes to owned projects and WIF

- **Intended RED:** S-26's real query registry generates exactly the committed survivor index file; an isolated WIF readiness principal can only read index state in the selected project; mismatched project, delete/change proposal, missing query coverage, or unadmitted writer fails closed.
- **Why it fails now:** the baseline registry still has pre-S-26 conversation indexes, and the workflow uses a JSON credential; the safe primitive is not yet bound to owned identities/projects.
- **Minimum GREEN:** consume—not redo—S-26's survivor registry, bind project IDs and distinct WIF reader/writer, retain redacted create-only proposals and manual main-only provisioning, and update workflow-contract coverage.
- **Retained behavior:** Firestore query semantics, no serving-deploy schema writes, no destructive index reconcile, fair-use/account/update/deletion queries.
- **Expected surfaces:** Firestore registry/generated JSON only for S-26-consumption drift; generator/query-coverage/reconciler; index workflow; runtime manifest; tests/contracts/docs.
- **Exact focused verification:** `python3 backend/scripts/generate_firestore_indexes.py`; `python3 backend/scripts/firestore_query_coverage.py --check-ratchet`; focused registry/reconciler/workflow tests; authorized read-only exact-project check and separately authorized manual create-only apply/wait.
- **Deletion/simplification enabled:** removes stale indexes/config only when S-26 proved their callers gone; removes read-only JSON key.
- **Stop:** S-26 registry is incomplete, a query has no authoritative owner, proposal includes delete/modify, project IDs mismatch, or writer authorization is absent.

### Cycle 9 — re-own the retained update/preview GCS boundary

- **Intended RED:** With an injected Storage client and declared bucket, retained update/preview reads and signed URLs use only approved prefixes; absent/wrong bucket or cross-environment/private-product path fails closed; runtime cannot publish/delete and future S-29 publisher cannot administer the project.
- **Why it fails now:** storage uses an optional env name while previews hard-code `omi_macos_updates`; IAM, location, public-access, lifecycle, and publisher handoff are undeclared.
- **Minimum GREEN:** introduce one validated bucket coordinate seam, remove the hard-coded Omi bucket, grant minimum runtime read/sign access, declare prefix/public-access/lifecycle policy, and document the distinct future S-29 writer. Do not implement signing, notarization, feeds, channels, or publication.
- **Retained behavior:** current update/preview endpoint responses, signed-URL caching/expiry, no private product-data storage, S-29 release ownership.
- **Expected surfaces:** storage/preview adapters, updates router only for configuration injection, runtime manifest/deploy IAM, storage fakes/tests, backend/S-29 handoff docs.
- **Exact focused verification:** focused desktop update/preview/storage tests with allowed/denied prefixes; offline harness Storage fake; authorized bucket/IAM/lifecycle read-only describe and a disposable dev object read/sign denial matrix.
- **Deletion/simplification enabled:** removes `omi_macos_updates`, hidden default bucket identity, and excessive runtime/publisher permissions after replacement proof.
- **Stop:** bucket name/location/IAM/lifecycle is undecided, S-29 publisher boundary is disputed, or a discovered prefix contains private product data.

### Cycle 10 — re-own account-deletion queue, signer, and reconciler runtime

- **Intended RED:** Fake Cloud Tasks captures one environment queue, canonical stable `run.app` handler/audience, dedicated signer, opaque job ID, deterministic name, 1,500-second deadline, five attempts, and queue concurrency 1; wrong signer/audience/project/region fails; persisted jobs reconcile after enqueue failure and duplicate delivery executes once.
- **Why it fails now:** coordinates and IAM use inherited identities/region, deploy scripts create/update the queue imperatively, and legacy signer/audience cannot yet be removed without S-25 drain evidence.
- **Minimum GREEN:** bind exact owned queue/signer/service URL/region, preserve Firestore state and five-minute in-service reconciler, attach invoker narrowly, validate queue drift, and keep legacy acceptance only while BL-002 proves queued legacy work may remain.
- **Retained behavior:** complete account deletion/cancellation semantics, retry/idempotency, fail-closed production config, privacy logging, no DLQ.
- **Expected surfaces:** task helper, account-deletion auth/config, runtime manifest/durable-dispatch validator, deployment workflow, unit/service/E2E tests, workflow contracts/docs.
- **Exact focused verification:** account-deletion identity/service/E2E tests and queue-render tests; offline backend harness; authorized dev queue describe/enqueue/delivery/duplicate/reconcile proof using a disposable job that does not delete a real account.
- **Deletion/simplification enabled:** after verified drain/rollback evidence, delete legacy sync audience/signer/config and inherited queue/IAM.
- **Stop:** canonical URL or signer is unknown, S-25 legacy drain remains `unknown`, runtime min/CPU cannot support reconciliation, or actual account deletion lacks explicit destructive authorization.

### Cycle 11 — move builds to regional Artifact Registry with immutable digest lineage

- **Intended RED:** Given admitted full SHA `S`, build output records `us-west1-docker.pkg.dev/...:<S>` and a captured `sha256` digest; smoke/deploy/promotion/rollback/recovery reject `latest`, short tags, digest mismatch, wrong project/region, or a mutable tag-only input.
- **Why it fails now:** workflows push GCR `latest`, seven-character SHA, and GCR build cache; revision suffix and release proof are not consistently separated from image identity.
- **Minimum GREEN:** authenticate through Cycle 2 WIF, build/push the full-SHA tag, capture and validate digest once, pass digest to all later phases, keep a clearly environment-scoped cache with full-build fallback, and use a shortened SHA only for Cloud Run revision naming.
- **Retained behavior:** one source SHA, runtime smoke before traffic, source closure, candidate isolation, exact rollback/recovery.
- **Expected surfaces:** build/deploy workflows, runtime-image registry/contracts, release-vector/candidate/traffic/status helpers and tests, docs.
- **Exact focused verification:** runtime-image closure/smoke; workflow and release-vector tests with tag mutation/digest mismatch negatives; authorized development build proving full SHA tag and one digest across smoke and candidate.
- **Deletion/simplification enabled:** deletes GCR, `latest`, seven-character image tags, and ambiguous tag-to-digest resolution.
- **Stop:** registry/repository/IAM unknown, base digest unverified, built digest cannot be propagated losslessly, or cache corruption prevents safe full-build fallback.

### Cycle 12 — deploy exact-main automatically to development

- **Intended RED:** A successful first-attempt same-repository Release Eligibility event for current `main` deploys exactly its captured digest to the development canonical service as no traffic, validates config/secrets/Redis/Firestore/GCS/tasks, health and retained synthetics, then promotes; rerun, fork, stale SHA, non-main, failed proof, or wrong environment is rejected.
- **Why it fails now:** auto-dev uses inherited JSON identity, GCR/latest/short tags, old region/manifest, and pre-S-26 topology.
- **Minimum GREEN:** compose Cycles 2-11 in the existing auto-dev workflow, preserve concurrency and fresh-main checks, deploy one service, produce redacted evidence, and restore the prior traffic split on failed promotion verification.
- **Retained behavior:** automatic dev feedback, exact source admission, candidate-first rollout, service health, retained API/listen behavior, no production mutation.
- **Expected surfaces:** auto-dev workflow, source-admission/deployment helpers, runtime manifest, candidate/release-vector/smoke tests, workflow contracts/docs.
- **Exact focused verification:** event-mutation and workflow-contract tests; local render/preflight; authorized exact-main development workflow with candidate, serving digest, stable URL, and rollback evidence.
- **Deletion/simplification enabled:** removes old development service/image/identity branches after successful replacement and read-only inventory.
- **Stop:** merge-triggered mutation has not been authorized, any dependency is absent, retained synthetic fails, or workflow cannot restore prior traffic exactly.

### Cycle 13 — retain manual production candidate, promotion, and rollback

- **Intended RED:** Manual deploy accepts only an exact current-main SHA with successful Release Eligibility proof, uses that SHA's captured digest, deploys no traffic, exercises production-safe health/capability probes, snapshots traffic, promotes one exact revision, verifies serving digest, and restores the exact snapshot on failure.
- **Why it fails now:** manual production has inherited credentials/region/GCR identity and does not yet compose the final S-27 capacity/dependency contracts.
- **Minimum GREEN:** compose the shared primitives for production without copying the dev workflow, require environment approval and all production inputs, preserve no-traffic candidate and transactional restore, and redact all evidence.
- **Retained behavior:** production eligibility, health, provider capability probes, traffic integrity, immutable release lineage, no automatic stable release implication.
- **Expected surfaces:** manual backend workflow and shared deploy/status/traffic/release scripts, production-boundary/workflow tests, docs.
- **Exact focused verification:** manual-input/eligibility/digest/traffic mutation tests; dry render; separately authorized production candidate, promotion, serving-vector, and rollback drill on one SHA.
- **Deletion/simplification enabled:** replaces inherited production authority and permits later operational retirement of old revisions/resources while retaining zero-traffic revisions.
- **Stop:** explicit production deploy/traffic authority absent, BL-002 resources unclassified, provider probe inputs unavailable, serving digest differs, or rollback snapshot is incomplete.

### Cycle 14 — preserve narrow traffic repair and break-glass

- **Intended RED:** Traffic-only repair requires no source checkout/image build and may only restore a validated prior revision/split; deploy-without-eligibility requires exact confirm plus nonempty issue-linked reason, environment approval, immutable digest, and redacted audit. Neither path changes schema, secrets, IAM, queue, Redis, bucket, alert, or budget.
- **Why it fails now:** the lanes exist but are tied to inherited identities/names and have not been bounded against the full S-27 foundation.
- **Minimum GREEN:** retarget existing repair/break-glass primitives and tests to owned service/WIF/digest coordinates, preserve deployment concurrency, and make scope/audit failures fail closed.
- **Retained behavior:** recoverability when evidence infrastructure is broken, exact traffic ownership, full disclosure, no relaxation of main-before-prod.
- **Expected surfaces:** manual workflow, repair/traffic/status helpers, failure-class/workflow contract tests, `.github/AGENTS.md` and runbook.
- **Exact focused verification:** focused repair and production-boundary tests; actionlint/preflight; separately authorized non-production repair drill and, only when genuinely necessary, break-glass drill.
- **Deletion/simplification enabled:** removes broad credential-based emergency access and duplicate recovery logic.
- **Stop:** operation cannot be bounded/audited, target revision/digest is ambiguous, or the request is actually a schema/IAM/data/resource mutation.

### Cycle 15 — own sanitized Cloud Logging and 30-day retention

- **Intended RED:** Representative request, provider error, Redis/TLS failure, task rejection, candidate failure, and rollback logs contain structured low-cardinality metadata but no tokens, secret values, PII, raw API bodies, audio, or transcripts; environment log-bucket metadata requires `_Default` retention 30 days and no external sink.
- **Why it fails now:** application sanitizers exist, but the full retained failure matrix and owned project retention/sink policy are not one validated contract.
- **Minimum GREEN:** extend S-09's existing sanitizer/log tests and deployment metadata validation, set/verify 30-day `_Default` retention in an authorized lane, and explicitly reject external archive/sink creation.
- **Retained behavior:** actionable Cloud Run request/system/stdout/stderr logs, Sentry/PostHog/LangSmith separation, fallback telemetry.
- **Expected surfaces:** logging call sites only where leaks are proven, sanitizer tests, runtime/resource workflow, manifest/contracts/docs.
- **Exact focused verification:** sanitizer/fallback tests with canary secrets/PII; fake log-bucket describe drift tests; authorized read-only log bucket/sink describe and post-deploy canary query.
- **Deletion/simplification enabled:** removes extinct-service/self-hosted logging assumptions and any external-archive configuration discovered after rebase.
- **Stop:** a useful failure cannot be observed without sensitive payloads, notification/log owner is unclear, or retention mutation lacks authorization.

### Cycle 16 — add only the production health and 5xx alerts

- **Intended RED:** The alert contract renders exactly two enabled production conditions—stable `/v1/health` unreachable and canonical Cloud Run 5xx—against the owned service/project and owned notification channel; development paging, per-route/Redis/task alerts, missing channel, or inherited service names fail.
- **Why it fails now:** no repository-owned pair/channel contract exists; extinct-service monitoring residue may still appear after rebase.
- **Minimum GREEN:** add the two conditions through the existing deploy/resource lane, share service identity from the runtime manifest, include no-data/threshold behavior from the detailed decisions, and verify notification delivery in an authorized non-sensitive test.
- **Retained behavior:** minimal production outage detection, sanitized metadata, Sentry/PostHog/LangSmith, no self-hosted monitoring stack.
- **Expected surfaces:** runtime/resource declaration, deploy workflow/helpers, alert contract tests, workflow contracts/runbook.
- **Exact focused verification:** deterministic alert render and negative tests; authorized read-only policy/channel describe; separately authorized synthetic health failure/notification proof with rollback.
- **Deletion/simplification enabled:** deletes extinct-service alert residue without replacing it with noisy per-route paging.
- **Stop:** owned channel/recipient unavailable, alert points at a candidate/tag URL rather than stable service, or test would impact real users without approval.

### Cycle 17 — add alert-only development and production budgets

- **Intended RED:** Each owned environment renders one monthly budget with externally supplied amount/currency/recipients and thresholds exactly 50/80/100 percent; zero/guessed amounts, inherited billing account, shared environment scope, shutdown automation, or secret recipient output fails.
- **Why it fails now:** ordinary GCP budget ownership is absent and required amounts/recipients/billing scopes are external.
- **Minimum GREEN:** add validated budget declarations to the existing narrow resource lane, require explicit values, create only notifications, and retain redacted evidence.
- **Retained behavior:** workloads continue serving regardless of threshold; costs become visible without changing product behavior.
- **Expected surfaces:** environment manifest/resource workflow/helpers, budget contract tests, operator docs.
- **Exact focused verification:** deterministic threshold/scope/redaction tests; authorized read-only billing-budget describe and separately authorized notification test.
- **Deletion/simplification enabled:** replaces informal cost assumptions; enables later removal of inherited budget recipients only after inventory.
- **Stop:** billing account, amount, currency, recipient, or budget-admin authority is missing; any proposal can suspend/delete resources.

### Cycle 18 — constrain artifact cleanup and preserve Cloud Run rollback history

- **Intended RED:** Cleanup dry-run selects only untagged Artifact Registry versions older than 30 days, excludes every exact release/candidate/rollback digest and build-cache object still needed, and cannot select Cloud Run revisions; repository contracts reject a custom revision-deletion job.
- **Why it fails now:** GCR/latest conventions are ambiguous, no owned regional cleanup contract exists, and retained image/revision evidence is not yet unified by digest.
- **Minimum GREEN:** after Cycle 11 lineage is stable, implement a registry cleanup policy or existing-lane operation with reviewed dry-run evidence first; leave zero-traffic revisions to platform retention and remove temporary candidate tags only after serving verification.
- **Retained behavior:** exact-image rollback/recovery, cache fallback, candidate evidence, zero-traffic revisions.
- **Expected surfaces:** Artifact Registry cleanup declaration/workflow helper, digest inventory tests, deployment tag cleanup, docs; no custom Cloud Run cleanup service/job.
- **Exact focused verification:** time-controlled cleanup selection tests; dry-run fixture containing tagged/untagged/release/cache digests; authorized Artifact Registry dry-run/read-only inventory before any deletion policy is enabled.
- **Deletion/simplification enabled:** bounded old untagged artifact removal without a custom cleanup platform.
- **Stop:** any selected digest appears in release/traffic/rollback evidence, cleanup cannot dry-run, or destructive policy enablement lacks explicit authorization.

### Cycle 19 — aggregate repository closure and real retained-path acceptance

- **Intended RED:** One aggregate suite and acceptance ledger require one S-26 app/service per environment; owned/WIF/ADC/exact-secret identity; declared Cloud Run/Redis/Firestore/GCS/tasks/registry/log/alert/budget shape; immutable deployment/rollback; no forbidden residue; offline harness and `omi-wave5-s27` retained paths green on the exact implementation SHA.
- **Why it fails now:** every baseline infrastructure identity and several runtime contracts are inherited or incomplete, and focused cycles can leave cross-surface drift.
- **Minimum GREEN:** regenerate contracts, update component guides/service maps, run all section 14 checks, classify section 13 hits, execute section 15 in layers, and record repository versus operational evidence without appending an integrated closeout section to this plan until implementation truly completes.
- **Retained behavior:** every section 9 invariant and every predecessor/successor boundary.
- **Expected surfaces:** aggregate tests, runtime/image/index/workflow/OpenAPI/generated-client artifacts only where their owning sources changed, `backend/AGENTS.md`, `.github/AGENTS.md`, `FORK.md`, architecture/runbooks; no S-29 release files unless a shared backend coordinate consumer must be updated under its owner's review.
- **Exact focused verification:** all commands in section 14, exact residue classification, named-bundle and authorized development acceptance in section 15, final diff/preflight/PR preflight and failure-class declarations.
- **Deletion/simplification enabled:** repository completion and a precise read-only/live-operations handoff to S-29/S-31.
- **Stop:** any unexplained hit/failure, unverified external input, absent rollback, product behavior drift, unauthorized live mutation, or attempt to claim BL-001/BL-002/Dodo/S-29 closure.

## 12. Cross-slice ownership and handoffs

| Slice/owner | S-27 consumes | S-27 returns | Boundary that must not move |
|---|---|---|---|
| S-08 | Owned Firebase identity, account lifecycle/export, exact deletion behavior | Runtime IAM/ADC and queue foundation for those paths | No Firebase/account redesign or data backfill |
| S-09 | Sanitization, diagnostics, Sentry/PostHog/LangSmith/fallback ownership | Cloud Run logs, retention, minimal managed alerts | No new telemetry payloads or self-hosted monitoring |
| S-18 | Dodo adapter/config with free-mode guard | Exact secret/config foundation while keeping `BILLING_MODE=disabled` | No Dodo/Stripe account, transaction, webhook, price, or live activation |
| S-20 | Retained cloud fair-use facts and enforcement behavior | Firestore/Redis identity and availability foundation | No return of deleted detailed cloud evidence |
| S-25 | One canonical service topology and canonical account-deletion target; BL-002 handoff | Owned resource inventory and operational disposition evidence | No claim that repository absence closes unknown live resources; no legacy deletion before drain proof |
| S-26 | One app, one URL/environment contract, one image, survivor routes/indexes/config/OpenAPI/generated client, retained secret/config-name union, unchanged canonical `/v1/health`, deleted `/health`/`/ready` aliases, non-route dependency validation, exact offline harness | Hosted foundation and adapted infrastructure seams | S-27 replaces provisional infrastructure coordinates but does not perform entrypoint merge, route/index product pruning, compatibility scaffolding, or reshape the retained config union |
| S-28 | Future clean Mac bundle/storage identity | Stable backend coordinates usable by non-production bundle | No Mac namespace migration |
| S-29 | Needs retained bucket coordinates/IAM handoff and stable backend deployment foundation | Bucket boundary, runtime service URLs, immutable backend image/deploy evidence | S-29 exclusively owns Developer ID, notarization, Sparkle, feeds, app artifacts, previews, Beta/Stable promotion/rollback, public/legal links |
| S-30 | Needs owned deployed/public destinations | Backend and cloud coordinates only | No product/legal/brand completion |
| S-31 | Needs one final SHA plus repository/operational evidence | Open gates, exact identities, live inventory, deploy/rollback/retained-path evidence | BL-001, BL-002, final provider qualification, Dodo test-mode/live activation remain S-31 work |

If an implementation touches a shared S-29 workflow solely to replace a backend URL/bucket input, the change must be a narrow consumer update with S-29 ownership called out; it must not alter signing, channel, artifact, preview, or release behavior.

## 13. Repository residue-search strategy

Run after the execution-time rebase, after each owning cycle, and at aggregate closeout. These are static tripwires; each hit must be classified against a real caller or historical exception, not blindly deleted.

```bash
# Inherited projects, services, regions, credentials, registries, images.
rg -n -i 'based-hardware|omi[_-]macos[_-]updates|us-central1|gcr\.io|GCP_CREDENTIALS|GCP_FIRESTORE_READONLY_CREDENTIALS|SERVICE_ACCOUNT_JSON|:latest|short[_ -]?sha' \
  backend .github infrastructure firestore.indexes.json desktop/macos \
  --glob '!**/CHANGELOG*' --glob '!bootstrap-scaffold/**'

# WIF/OpenTofu residue after Cycle 2.
rg -n -i 'opentofu|terraform|development-wif-plan|development-project-read|workload_identity_provider|credentials_json' \
  infrastructure .github backend scripts

# Cloud Run shape and URL consumers.
rg -n 'run\.app|--region|--cpu|--memory|--concurrency|--timeout|--min|--max|execution-environment|session-affinity|cpu-boost|cpu-throttling|startup-probe|liveness-probe|service-account' \
  backend .github desktop/macos --glob '!**/CHANGELOG*'

# Redis clients and every environment/key caller.
rg -n 'redis\.Redis|from database import redis_db|from database\.redis_db|REDIS_[A-Z_]+|auth_session:|auth_code:|listen_rate_limit|credits_invalidated|run_lock|buildcache' \
  backend .github

# Firestore query/index/project control.
rg -n 'firestore\.indexes|firestore_index_registry|reconcile_firestore_indexes|RUNTIME_GCP_PROJECT_ID|collection\(|collection_group|account_deletion|fair_use|desktop_(release|preview|update)' \
  backend .github firestore.indexes.json

# Retained GCS and forbidden private-product prefixes.
rg -n -i 'BUCKET_DESKTOP_UPDATES|PREVIEW_BUCKET_NAME|storage\.googleapis\.com|gs://|recording|transcript|attachment|screenshot|audio|openai.*file' \
  backend .github desktop/macos --glob '!**/CHANGELOG*'

# Account-deletion topology and legacy drain-only names.
rg -n 'ACCOUNT_DELETION_TASKS_|SYNC_TASKS_|account-deletion|legacy_sync|oidc|dispatch_deadline|task.*signer|run\.invoker' \
  backend .github

# Observability, budget, cleanup, and forbidden automation.
rg -n -i 'prometheus|grafana|loki|alloy|alertmanager|log.*retention|notification.*channel|budget|cleanup|delete.*revision|external.*(sink|archive)' \
  backend .github infrastructure

# Dodo/Stripe remains disabled and S-29 remains outside this slice.
rg -n 'BILLING_MODE|DODO_|STRIPE_|Developer ID|notar|Sparkle|appcast|Codemagic|Beta|Stable' \
  backend .github desktop/macos bootstrap-scaffold/dodo-integration.md
```

Retained hits must be annotated in the execution ledger:

- historical changelog/reference evidence: retain;
- disabled Dodo/provider contract: retain without transaction;
- S-29 release consumer: hand off, do not absorb;
- local explicit credentials/emulator: retain behind local/test gate;
- task legacy audience: retain only while queue/drain evidence is unresolved;
- `latest` in a third-party API meaning or prose: retain if unrelated; image identity use is forbidden;
- Omi product names in historical research/plans: do not rewrite; active source/config/runtime ownership must be replaced or explicitly classified.

## 14. Focused and component-level verification commands

Commands are future implementation checks and are not claimed to have passed in this planning turn.

### Fast RED/GREEN loop

From `desktop/macos`, select one exact Python test path at a time:

```bash
./scripts/dev-feedback.py --once python 'tests/unit/test_backend_runtime_env_validator.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_render_backend_runtime_env.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_preflight_cloud_run_deploy.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_redis_db_cache_serialization.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_reconcile_firestore_indexes.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_account_deletion_task_identity.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_verify_backend_release_vector.py'
./scripts/dev-feedback.py --once python 'tests/unit/test_repair_cloud_run_traffic.py'
```

Add new focused tests under discoverable `backend/tests/unit/`, `backend/tests/services/`, or `backend/tests/routers/` paths for S-27 WIF claims, Redis TLS, Cloud Run shape, Artifact Registry digest, alerts, budgets, and cleanup. Extend existing shared test files when they own the seam. Do not introduce a source-string test as behavioral coverage; label any necessary absence check “static tripwire.”

### Backend, contracts, and harness

```bash
cd backend
bash test-preflight.sh
bash test.sh
bash testing/e2e/run.sh
python3 scripts/generate_firestore_indexes.py
python3 scripts/firestore_query_coverage.py --check-ratchet
python3 scripts/runtime_image_contracts.py check
python3 scripts/check_workflow_contracts.py
bash scripts/openapi_runner.sh scripts/route_policy_inventory.py --manifest route_policy_manifest.yaml --check --report-only
bash scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
cd ..
make runtime-image-source-closure
make runtime-image-smoke SERVICE=backend
```

Use `gcp_firestore_indexes.yml` for the future isolated read-only check and separately authorized manual create-only writer; do not substitute an ad hoc live command for that owner.

### Desktop continuity affected by the 60-minute runtime/network boundary

```bash
cd desktop/macos
./scripts/agent-logic-harness.sh --cross-surface-smoke
./scripts/desktop-core-harness.sh --self-check
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-wave5-s27
```

Run the official `desktop/macos/test.sh` only if S-27 legitimately changes Swift or a generated Swift client. S-29 signing/release suites are not S-27 verification.

### Repository and PR contracts

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py
python3 backend/scripts/generate_firestore_indexes.py
python3 backend/scripts/firestore_query_coverage.py --check-ratchet
make preflight
scripts/pr-preflight --suggest
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
git diff --check
git status --short
```

Before any future `fix:` commit/PR, follow the current failure-class contract. A new fail-closed gate must include its legacy-principal test. Prefer extending the runtime-env, deployment-secret, workflow-contract, release-admission, runtime-image, Firestore, or preflight shared primitive. A brand-new repository guard may land only if its PR cites a real merged PR/incident it would have caught and explains why no existing shared primitive can enforce it.

## 15. Real named-bundle, backend, infrastructure, or release acceptance

Acceptance is layered. Record exact commit SHA, image digest, environment, service revision, sanitized command/result, start/end time, operator principal identifier, and rollback target. Never place secrets or PII in the record.

### A. Local/offline acceptance — no cloud mutation

1. From the repository root, run `PROVIDER_MODE=offline make dev-up` to start the complete surviving S-26 stack with offline fakes. Prove Redis unavailable/bad TLS, Firestore error, Storage error, task enqueue error, and provider/Dodo-disabled cases retain their explicit behavior.
2. In shell 1, run `OMI_FORCE_FULL_BUNDLE=1 make desktop-run-local DESKTOP_APP_NAME=omi-wave5-s27 DESKTOP_USER=alice` for the first installation and keep that foreground launcher running. It must resolve only loopback/emulator endpoints and create only the launcher-reported current `omi-wave5-s27` non-production app/bundle/profile. If S-28 is already integrated, consume its identity mapping; S-28 is not an S-27 predecessor and is never required to begin this acceptance. Do not use bare `OMI_APP_NAME=... ./run.sh`: named bundles default to remote development services unless a local profile or explicit local URLs override them, and those services currently use production Firebase identities.
3. After the local-profile launcher reports readiness, use shell 2 for `./desktop/macos/scripts/omi-ctl health` and the local automation bridge. Read the actual current non-production bundle identifier from the launcher, connect `agent-swift` to that identifier, and check authenticated app startup, typed Chat/model route, update read, and a natural authenticated listen/PTT path where the owning guide requires it.
4. Fault the local canonical backend during an active listen session and prove reconnect/continuation without duplicate transcript ownership or local-state loss. A forced transcript is not natural voice-path proof.
5. Exercise fake-backed account-deletion enqueue failure, reconciliation, duplicate delivery, and terminal state. Do not delete an external account.
6. Stop only the named development bundle through its normal harness lifecycle; never touch Omi or Omi Beta.

### B. Read-only owned-environment inventory — verified principal, no mutation

For both environments, capture sanitized describes of project/region, WIF/provider/service accounts and IAM, VPC/subnet/private-service range, Cloud Run service/revisions/traffic, Secret Manager metadata/versions, Redis topology/TLS/AUTH metadata, Firestore indexes, GCS bucket/IAM/lifecycle, Tasks queue/IAM, Artifact Registry repository/images/policies, log bucket/sinks, alerts/channels, and budgets. Compare them mechanically with the rendered manifest. Unknown/missing/drifted resources keep the affected cycle open.

### C. Separately authorized development mutation and backend acceptance

1. Provision or reconcile only the reviewed development resources through the owning workflow/lane; capture rollback for each mutable resource.
2. Prove WIF without JSON keys and negative wrong-branch/repo/workflow/environment impersonation.
3. Build the admitted full SHA, capture one digest, deploy it no-traffic with the target Cloud Run shape, verify unchanged `/v1/health`, assert `/health` and `/ready` are absent, and verify config plus dependency readiness through S-26's canonical non-route deploy/validation seam before promotion.
4. Point `omi-wave5-s27` explicitly at the stable development `run.app` URL. Prove health, authenticated typed Chat/model, a natural authenticated `/v4/listen` stream lasting across a forced candidate revision restart/reconnect, free billing/fair-use, update/preview reads, Redis TTL/Lua/lock behavior, and Firestore survivor queries.
5. Enqueue a non-destructive development deletion fixture to prove queue signer/audience/deadline/retry/reconciler. Actual deletion uses only the separately approved disposable owned account.
6. Promote the exact candidate, prove the serving digest, then conduct an authorized rollback drill restoring the exact prior split and retained paths.
7. Prove log sanitization/retention metadata, alert configuration and notification, budget thresholds, registry cleanup dry-run, cache fallback, and preservation of rollback digests/revisions.

### D. Separately authorized production acceptance

Production is not implied by development GREEN. On an explicitly approved exact-main SHA, repeat WIF/manifest/dependency preflight, no-traffic candidate, health/provider-safe synthetics, promotion, serving-digest verification, and rollback drill. Use a non-destructive task fixture unless a disposable production-scoped account and destructive approval are both supplied. Do not test Dodo transactions and do not publish or alter a Mac Beta/Stable channel.

### E. Evidence/failure rules

- A failed check leaves traffic/resources at the documented prior state and keeps the cycle open.
- Development min 0 means background reconciliation while scaled to zero is not an acceptance promise; a request or controlled min-instance window must start an instance for the test.
- Production health and 5xx alert tests must be bounded and approved; no user-impacting outage may be induced casually.
- “Workflow dispatched,” “revision ready,” a mutable tag, or a passing curl alone is insufficient. Evidence must join admitted SHA, digest, revision, traffic, public path, dependency identity, and rollback.
- Signed/notarized candidate, Sparkle feed, preview publication, Beta/Stable promotion, public links, and release rollback remain S-29 acceptance.

## 16. Repository closure versus separately authorized operational closure

### Layer 1 — repository implementation and local verification

S-27 can be repository-green when all cycles' code/config/tests/docs are complete; S-26/predecessor tests and section 14 pass; the offline/named-bundle layer passes; one manifest describes both owned environments without secret values; forbidden active residue is absent/classified; and the diff/PR records exact evidence. This layer may use placeholders only when validation fails closed and names the missing external input. It cannot claim any resource exists or was removed.

### Layer 2 — read-only inventory

A verified operator identity compares live development and production metadata with the manifest and refreshes BL-002 classifications. Sanitized describes may establish `ours-retain`, `ours-delete`, `external`, `already absent`, or `unknown`; they may not read secret values or user data. Any `unknown` keeps the dependent operational item open. Inventory does not authorize mutation.

### Layer 3 — separately authorized mutation/release

Creation/update of projects, IAM/WIF, networks, Redis, secret bindings/versions, Cloud Run, traffic, Firestore indexes, bucket/IAM/lifecycle, queues, registries/policies, log retention, alerts/channels, budgets, or deletion of inherited resources requires explicit scoped authority and a rollback/evidence record. Production deploy/traffic needs its own approval under repository rules. Destructive cleanup needs exact resolved targets and dry-run evidence.

Operational S-27 closure requires both environments to match the manifest and pass section 15, with exact SHA/digest/rollback evidence and no retained resource pointing at Omi/based-hardware authority. It still does not close BL-001, final BL-002 composition, S-29 release, S-31, or Dodo activation. If legacy account-deletion tasks or old rollback targets remain, retain the minimum old signer/resource until drain/rollback expiry is proven and record the open item rather than declaring false closure.

## 17. Risks, ambiguities, and explicit stop points

| Risk/ambiguity | Required response |
|---|---|
| Planning baseline is pre-S-26 | Mandatory rebase/inventory; never implement against two apps or repeat S-26 consolidation. |
| Owned identities and project numbers are not in the repository | Fail closed with named inputs; do not derive from labels or copy pilot constants. |
| S-25 live state is `unknown` | Read-only inventory first; repository deletion never proves cloud deletion. |
| WIF roles become broad to make deploy easy | Stop and derive the capability matrix from exact API calls; separate deploy/runtime/index/task/publisher principals. |
| GCS signed URLs appear to require runtime self-impersonation | Review the exact signing mechanism and minimum token-creation permission; do not grant project-wide Token Creator by convenience. |
| Cloud Run `run.app` URL is known only after service creation | Treat it as captured sanitized output validated back into the environment record; do not invent a custom domain or circular default. |
| Region migration crosses network, Redis, queues, registry, and service URLs | Land/verify per cycle with old-path rollback; do not delete the prior resource until callers and traffic are proven. |
| Redis outage policies are mixed | Characterize every survivor; no global “Redis optional/required” boolean. |
| Redis CA rotation and exact secret version rotate independently | New version means new candidate and connection proof before traffic; no `latest` or plaintext fallback. |
| Firestore index pruning collides with S-26 | S-26 owns survivor selection; S-27 only owns project/WIF/safe apply. Rebase conflict stops the cycle. |
| GCS update bucket overlaps S-29 | S-27 owns bucket foundation/runtime access; S-29 owns app artifacts, publisher, signing, feeds, previews, channels. Escalate any broader change. |
| Legacy account-deletion signer/audience still has queued work | Keep bounded compatibility until verified drain and rollback expiry; do not guess from code absence. |
| Dev min 0 and five-minute reconciler | Document the availability tradeoff; do not add a separate scheduler/job/DLQ without a new decision. |
| 3,600-second requests and termination timing expose Mac gaps | Fix only the narrow reconnect behavior authorized by IR-856 and its tests; do not absorb S-29 or redesign streaming. |
| Image cache or cleanup threatens rollback digest | Full build fallback; cleanup dry-run; exclude every release/candidate/traffic/rollback digest. |
| Alert or budget inputs are missing | Repository schema tests may land; resource creation and operational closure remain blocked. Never guess amounts/recipients. |
| New check has no real incident/merged PR | Extend an existing shared primitive or omit the check; do not land an ungrounded gate. |
| A test rewrite changes expected behavior with the code | Cite the external platform/wire source in the PR or retain the old guard. |
| Dodo credentials exist in Secret Manager | Keep disabled and do not invoke them; presence is not authorization. |
| Production, data deletion, IAM, or cleanup action is proposed | Resolve exact target read-only, obtain explicit authority, record rollback, then act only through the owning lane. |

## 18. Final completion checklist

### Planning artifact

- [x] Baseline commit is an ancestor of HEAD; HEAD and `origin/main` were the pinned SHA during planning.
- [x] All primary decisions IR-808, IR-809, IR-838 through IR-886, IR-890, and IR-891 are mapped.
- [x] Current pre-S-26 codeflow, complete known callers, dependency gates, external inputs, classifications, invariants, topology, TDD cycles, residue searches, verification, and operational separation are recorded.
- [x] No integrated closeout/evidence is claimed.

### Future repository implementation

- [ ] Fresh execution baseline and integrated S-26 are recorded; all inventories are regenerated.
- [ ] Every RED is observed through its public/operational seam before GREEN; static tripwires are labelled.
- [ ] Each cycle makes the minimum production change and preserves its listed behavior.
- [ ] Tests execute production behavior with injected external boundaries; no internal mocks or import-time clients are added.
- [ ] Every survivor Redis caller has an explicit failure policy and TLS/AUTH proof.
- [ ] Firestore survivor indexes exactly match S-26 query owners and remain create-only/project-matched.
- [ ] GCS contains only the retained update/preview boundary and the S-29 handoff is explicit.
- [ ] Account deletion retains durable state, exact OIDC, retry/idempotency, reconciliation, and drain-gated legacy removal.
- [ ] One manifest drives WIF/ADC/secrets/Cloud Run/network/Redis/Firestore/GCS/tasks/registry/logs/alerts/budgets without secret values.
- [ ] Full SHA and one captured digest join build, smoke, deploy, promotion, rollback, recovery, and evidence; `latest` is absent from image identity.
- [ ] S-29 release/signing/update behavior and Dodo activation were not absorbed.
- [ ] Focused tests, backend suite, offline harness, runtime-image/index/workflow/OpenAPI/generated contracts, named bundle, residue classification, `make preflight`, PR preflight, and `git diff --check` are green as applicable.
- [ ] Behavior/config/docs move together; new TODO/FIXME/HACK markers have issue links; failure-class declarations are valid.

### Future operational closure

- [ ] A verified read-only operator inventory classifies every live S-25/S-27 resource; no `unknown` is silently treated as absent.
- [ ] Exact project/identity/network/secret/bucket/registry/channel/budget inputs are approved and recorded without values leaking.
- [ ] Each live mutation has separate scope authorization, exact target resolution, rollback, and sanitized evidence.
- [ ] Development and production each match section 10 and pass their applicable section 15 acceptance on an exact SHA/digest.
- [ ] Legacy account-deletion and rollback resources are removed only after verified drain/expiry and separate destructive approval.
- [ ] No Omi/Omi Beta app, payment resource, Dodo transaction, S-29 channel, or private user data was operated by S-27.
- [ ] Open BL-001, BL-002, S-29, and S-31 work is handed off truthfully rather than marked green.
