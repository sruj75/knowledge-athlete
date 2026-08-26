# Wave 5 / S-26 TDD plan — Consolidate one canonical Python backend and its development harness

## 1. Title and slice identity

| Field | Value |
|---|---|
| Wave | 5 |
| Slice | S-26 |
| Name | Consolidate one canonical Python backend and its development harness |
| Type | Backend boundary adaptation |
| Required planning baseline | `22ad2f16ff8d63fd761c918b92f4c5d961814624` |
| Target branch | `origin/main` |
| Future named development bundle | `omi-wave5-s26` / `com.omi.omi-wave5-s26` |
| Primary decisions | IR-008, IR-803, IR-804, IR-808, IR-839 through IR-849, IR-890, IR-891 |

This slice owns consolidation of the Python source entrypoint, route and runtime configuration, repository manifests, Firestore index registry, and local/offline development harness. It consumes S-25's canonical retained service topology. It does **not** absorb S-27's live cloud-project, IAM, Workload Identity Federation (WIF), networking, deployment-identity, Secret Manager ownership, Artifact Registry ownership, or regional infrastructure reownership.

## 2. Planning status and pinned baseline

**Planning status: READY TO START REPOSITORY IMPLEMENTATION, subject to the execution-time gates in section 5.** The baseline contains the complete Waves 3–4 repository repair tree required by the deletion map. BL-001 and BL-002 remain open; neither blocks the repository cycles in this plan, but both block final live-continuity or live-resource-closure claims.

The required baseline check was run on 2026-08-26:

```text
git fetch origin
git merge-base --is-ancestor 22ad2f16ff8d63fd761c918b92f4c5d961814624 HEAD
git rev-parse HEAD
git rev-parse origin/main
git status --short --branch
git diff --stat 22ad2f16ff8d63fd761c918b92f4c5d961814624..HEAD
```

Observed planning state:

- required baseline is an ancestor of `HEAD`;
- `HEAD` = `origin/main` = `22ad2f16ff8d63fd761c918b92f4c5d961814624`;
- current branch is `plan-waves-5-6-slices` and was not renamed or switched;
- the worktree was clean and there were no product changes beyond the pinned baseline before this document was created;
- `python3 bootstrap-scaffold/validate-requirements-ledger.py` passed with 714 indexed rows and 714 detailed sections.

This document records future RED/GREEN work. It is not implementation, deployment, provider, release, or live-inventory evidence.

## 3. Outcome

At repository closure, one assembled FastAPI application, `backend/main.py:app`, owns every retained backend route and lifecycle hook. Each environment has one canonical backend URL. The Mac, local launchers, offline harness, generated API contract, route policy, runtime image registry, runtime-environment manifest, Firestore index manifest, and deployment/release controls all name and exercise that one boundary.

The surviving local stack is:

```text
named Mac bundle
       |
       | one canonical backend URL
       v
backend/main.py:app
       |-- retained auth, quota, fair-use, STT, model/TTS, updates,
       |   account-deletion, health and authenticated metrics routes
       |-- Firebase Auth + Firestore (emulators in local/offline mode)
       |-- one Redis coordination service
       `-- authorized provider adapters (offline fakes by default)
```

The slice deletes the second FastAPI entrypoint and URL, the second local backend process/port, the second container and deployment plane, stale Rust/desktop-service terminology, dormant `backend_required` release-manifest fields, rejected Redis residue, and Firestore index specifications without production callers.

This is not a product redesign. It does not change prompts, models, STT semantics, provider selection/failover, local data authority, billing state, account-deletion durability, update channels, or user-visible workflows. It does not deploy or rename live infrastructure.

## 4. Authorizing requirements

| Decision | Binding implementation meaning for S-26 | Ownership qualification |
|---|---|---|
| IR-008 | Keep the retained Python backend and narrowed managed dependencies; make the local/offline harness represent exactly that system. | S-26 repository owner. |
| IR-803 | Merge `backend/main.py` and `backend/desktop_backend.py` into one deployed application and URL; remove stale Rust naming after every caller moves. | S-26 source, routing, and harness owner. |
| IR-804 | Keep backend deployment independent from Mac release and retain fail-closed live compatibility checks; delete dormant `backend_required` exact-image coupling. | S-26 deletes manifest coupling; S-29 later reowns signed release operation. |
| IR-808 | Keep one Redis service only for surviving ephemeral sessions, counters, locks, rate limits, caches, and invalidation signals; delete rejected-product keys/helpers. | S-26 prunes code/contracts; S-27 reowns live Memorystore/network/security. |
| IR-839 | Keep one canonical Python backend on Cloud Run and delete the duplicate backend service plane from repository source/config. | S-26 collapses repository topology; live service inventory/deletion remains separate. |
| IR-840 | Preserve distinct development and production backend environments. | S-26 keeps the two-environment manifest shape; S-27 supplies owned identities. |
| IR-841 | Keep exact-main automatic development deployment, simplified to one service after checks. | S-26 consolidates workflow behavior; no workflow is run by this slice plan. |
| IR-842 | Keep exact-commit candidate validation, health/compatibility gates, controlled promotion, and rollback for the single service. | S-26 preserves/merges controls; S-27 proves them against owned infrastructure. |
| IR-843 | Use environment-scoped GitHub-to-Google WIF, never permanent service-account JSON keys. | S-27 owns actual pools/providers/accounts; S-26 must not add or perpetuate a new key path. |
| IR-844 | Delete the Omi-specific OpenTofu pilot/scaffold and configure only the narrow retained WIF path. | S-27 owns this infrastructure deletion; S-26 records the handoff and does not edit it. |
| IR-845 | Keep Release Eligibility bound to the exact admitted `main` commit. | S-26 preserves this in the consolidated workflow. |
| IR-846 | Keep audited break-glass deployment and traffic repair for the one service, including exact-main scope, explicit confirmation, reason, and evidence. | S-26 preserves the repository control; live use needs separate authorization. |
| IR-847 | Replace inherited private base images with a controlled, specifically pinned Python 3.11 slim base. | S-27 owns base-image provenance/registry change; S-26 keeps the canonical Docker contract ready for it. |
| IR-848 | Keep genuine retained secrets in owned Secret Manager and delete rejected-product secrets; never place values in repository manifests. | S-26 defines the retained secret-name union only; S-27 owns projects, bindings, versions, and values. |
| IR-849 | Keep one validated runtime-environment manifest with one backend service in each of two environments and only retained settings/secrets. | S-26 manifest owner; S-27 replaces provisional/inherited live identities. |
| IR-890 | Keep the repository index registry and human-approved create-only reconciliation, pruned to serving queries; authenticate the eventual operation through WIF. | S-26 owns registry/manifest/pruning; S-27 owns WIF and live check/create. |
| IR-891 | Keep the isolated harness, Firebase emulators, Redis, provider modes/fakes, synthetic profiles, and lifecycle commands, collapsed to one canonical backend. | S-26 harness owner. |

Related retained requirements are applied as regression fences rather than re-decided here:

- the deletion map's protected backend/release family, IR-838 through IR-895, controls health, readiness, candidate admission, rollback, emergency access, logging, and security;
- S-04's route-policy/OpenAPI/non-Windows generated-client contract is consumed, not recreated;
- S-08's authenticated account-deletion intent, queue dispatch, reconciler, and disabled-billing behavior remain authoritative;
- S-10 through S-20 retain Mac-local conversation, Memory, Tasks, Focus/Insights, Rewind, ownership fencing, account isolation, and offline/restart behavior;
- S-19/S-22 retain both Gemini Live and OpenAI Realtime, direct model/STT/TTS semantics, and authorized failover;
- S-25 retains only the canonical backend plus explicit managed dependencies, but its live resource classifications remain `unknown` under BL-002;
- Dodo remains disabled through Wave 6 under `bootstrap-scaffold/dodo-integration.md`; no Dodo or Stripe resource is created or contacted.

## 5. Dependencies and entry gates

### Required predecessor shape

S-26 depends on integrated S-04, S-08, S-10 through S-20, and S-25. The pinned baseline contains those repository implementations plus the Waves 3–4 closeout commits. S-25 deliberately leaves `desktop_backend.py`, its image/workflows, and the dual-URL harness as S-26 work; that temporary repository state is not evidence that two services should survive.

Before Cycle 1, the implementer must:

1. work in a git worktree and run the repository's required `make setup` flow before the first commit;
2. fetch `origin`, rebase/refresh from the then-current `origin/main` without switching the current task branch mid-work, and record the new exact SHA;
3. rerun the complete inventories in sections 6, 7, and 13 because another Wave 5 implementation may have changed callers;
4. run the ledger validator and baseline component tests before writing the first RED;
5. stop if a predecessor-owned retained route, service, local owner, or deployment contract is absent or materially different—repair or consume that predecessor rather than inventing a compatibility adapter.

### External inputs and gates

| Missing or unresolved input | Affected cycles | Safe work that may proceed | Evidence required to reopen blocked work | Owner / authorization |
|---|---|---|---|---|
| BL-001 final provider/continuity qualification | Real-provider and final all-waves claims in sections 15–16 | All hermetic/offline repository cycles and named-bundle paths that do not call paid/live providers | Final committed SHA, authorized provider credentials, provider-path and physical-device evidence | S-31 / provider owner; external calls require the appropriate authorization and budget |
| BL-002 verified live-resource inventory | Any assertion that `desktop-backend`, its image, IAM, secrets, URLs, or traffic are absent/deletable live | Delete repository callers/config only after local and workflow contracts are green | Verified operator identity plus sanitized read-only inventory of both environments | S-27/S-31 operator; mutation separately authorized |
| Owned dev/prod project IDs, regions, service names/URLs, WIF pool/provider, deploy/runtime accounts | Live validation and S-27 reownership; not Cycles 1–11 local GREEN | Use current manifest fields as explicitly inherited/provisional inputs; do not guess replacements | Integrated S-27 environment manifest and verified cloud identity | S-27; live changes require explicit user authorization |
| Owned Artifact Registry and controlled Python 3.11 base digest | IR-847 operational completion | Keep one canonical Dockerfile/registry entry and test its source closure | Pinned source/digest, provenance and owned registry | S-27 |
| Owned Redis endpoint/TLS/auth and Secret Manager secret names/versions/bindings | Live deployed acceptance | Keep typed required configuration and hermetic Redis/provider fakes; never copy values into source | S-27 manifest and read-only binding proof; secret values are never evidence | S-27; mutation separately authorized |
| Legacy account-deletion queue audience/signer may still have tasks | Deletion of legacy audience/signer acceptance, live topology closure | Preserve the bounded canonical-plus-legacy acceptance already handed off by S-25; consolidate its code into `main:app` | Verified queue drain, no legacy dispatch/traffic, rollback-window expiry | S-27/account-deletion operator; live mutation separately authorized |
| Signed preview/candidate identities and public release destinations | Signed release acceptance | Consolidate local manifest schema and preview URL inputs; run schema/workflow tests only | Integrated S-28/S-29 identities and signed-candidate evidence | S-29; publishing/release separately authorized |

No missing live input blocks Cycles 1–11 as repository work. It blocks only the corresponding operational claim. A repository absence, local fake, health response, or static workflow test is never substituted for live evidence.

## 6. Current production codeflow

The pinned checkout has a deliberate transitional split:

1. `backend/main.py` creates the broad FastAPI `app`, initializes Firebase, installs default-deny CORS, mounts the retained product routers, and owns timeout/account-deletion startup and shutdown. It already mounts `desktop_core`, `auth`, `desktop_chat`, `desktop_proxy`, `desktop_realtime`, and `desktop_tts_updates` alongside `/v4/listen`, model/STT, update, quota/fair-use, account-deletion, `/v1/health`, and authenticated metrics routes.
2. `backend/desktop_backend.py` creates a second FastAPI `app`, initializes Firebase a second time, uses wildcard CORS, and mounts only the six desktop router families plus `desktop_deprecated`.
3. `backend/routers/desktop_deprecated.py` is a 410 compatibility shell. The unreleased fork has no inherited customer population, and `main.py` does not mount it. It has no target role.
4. `backend/routers/desktop_core.py` owns `/`, `/health`, `/ready`, API-key configuration, and Apple well-known responses. `/ready` probes Redis. Its health identity still reports `omi-desktop-backend`; `backend/routers/other.py` separately owns `/v1/health`.
5. `backend/scripts/export_openapi.py` and `backend/scripts/route_policy_inventory.py` already assemble/import `main:app`; the generated Swift client comes from that live application. The route-policy manifest names the `backend-main` surface but includes the desktop routes now mounted by `main.py`.
6. `DesktopBackendEnvironment.swift` exposes separate production/development Python and falsely named Rust URLs. `APIClient`, account/API-key/TTS calls, realtime usage/minting, Pi agent runtime, Gemini/embedding clients, automation health, previews, launch scripts, and E2E use one resolver or the other.
7. `desktop/macos/run.sh` and `scripts/dev-instance.sh` still start/manage `desktop_backend:app` on a second `RUST_PORT`/10201 path; `backend/scripts/dev-serve.sh` is the existing canonical `main:app` launcher.
8. `scripts/dev-harness/dev_harness/config.py` allocates `backend` port 8000 and `desktop_backend` port 10201. The CLI starts and monitors both. Offline mode has both `offline_backend_app.py` and `offline_desktop_backend_app.py`; the desktop child adds `OMI_LLM_STUB=1`.
9. The local desktop profile exports both `OMI_PYTHON_API_URL` and `OMI_DESKTOP_API_URL`, while retaining Firebase Auth/Firestore emulator identity, Redis, synthetic users, loopback safety, and named-bundle isolation.
10. `backend/runtime_images.json` declares `backend`/`backend/Dockerfile` and `desktop-backend`/`backend/Dockerfile.desktop_backend`. Canonical and desktop-specific dev/prod/recovery workflows independently build, probe, promote, and roll back those images.
11. `backend/deploy/runtime_env.yaml` already models one `backend` service in dev and prod, but it contains inherited project/region/network inputs and lacks the full retained secret/config union currently bound by the desktop workflows. Those identity values are S-27 inputs, not S-26 guesses.
12. The canonical workflows already enforce Release Eligibility, exact-main source, no-traffic candidates, runtime-image checks, promotion, traffic snapshots, rollback, repair traffic, and break glass. The desktop workflows separately enforce `/health`/`/ready`, release SHA, Chat contract, voice-provider probes, image lineage, and promotion/rollback.
13. The desktop release manifest admits `app_only` and dormant `backend_required`, the latter carrying three desktop-backend image/source fields. Production promotion currently emits `app_only`; previews still accept two backend URLs.
14. `backend/database/redis_db.py` is the retained short-lived coordination adapter. `get_cached_user_geolocation()` and its deserializer have no production caller and explicitly describe S-23 residue. All other retained key families must be proven from callers, not inferred by name.
15. `backend/database/firestore_index_registry.py` declares conversation-finalization, starred-chat, and fair-use query/index specs. Only `FAIR_USE_FLAGGED_STATES_QUERY` has a production caller (`backend/database/fair_use.py`); the first two are referenced only by registry/tests after earlier local-authority deletions.

## 7. Complete caller and dependency inventory

Refresh this table at execution time. “Current role” describes the pinned checkout, not the desired result.

| Surface | Current owners/callers/contracts | S-26 treatment |
|---|---|---|
| Assembled Python app | `backend/main.py`; `backend/tests/unit/test_s25_retired_worker_routes.py`; assembled-app retirement tests; `backend/scripts/export_openapi.py`; route inventory | Make sole app/entrypoint and add behavioral route/lifecycle parity coverage. |
| Duplicate Python app | `backend/desktop_backend.py`; `backend/routers/desktop_deprecated.py`; `Dockerfile.desktop_backend`; runtime image registry; desktop workflows; harness/local launcher | Delete only after all callers and controls move. |
| Desktop routers | `desktop_core.py`, `auth.py`, `desktop_chat.py`, `desktop_proxy.py`, `desktop_realtime.py`, `desktop_tts_updates.py`; their unit/router tests | Keep retained product routes mounted once by `main:app`; preserve auth, failover, rate limits and result semantics, retain only canonical `/v1/health`, and remove service-specific `/health`/`/ready` routes after their callers move. |
| Canonical product routers/lifecycle | `main.py`, `routers/listen`, Chat/transcribe/users/payment/fair-use/metrics/update routers, account-deletion service/reconciler | Keep as is except shared app identity/config adaptation. |
| Mac URL authority | `DesktopBackendEnvironment.swift`, `APIClient.swift`, `APIClient+Account.swift`, `APIKeyService.swift`, `AgentRuntimeProcess.swift`, `GeminiClient.swift`, `EmbeddingService.swift`, `OmiHTTPTransport.swift`, `TranscriptionService.swift`, automation bridge | Route every retained call through one canonical resolver; keep auth callback exception explicit rather than recreating a data-plane split. |
| Routing tests/diagnostics | `APIClientRoutingTests.swift`, `APIClientAuthRetryTests.swift`, `omi-macos-dev`, automation health payload, `.env.example`, local-profile/fault/signed-artifact tests | Adapt expected one-URL behavior and truthful names. |
| Local backend ownership | `desktop/macos/run.sh`, `python-desktop-backend-dev.sh`, `scripts/dev-instance.sh`, `backend/scripts/dev-serve.sh`, `dev-feedback.py` | Reuse one owned canonical `main:app` process/port; preserve PID/process-group/foreign-port safety. |
| Harness topology | `Makefile` `dev-*`; `scripts/dev-harness/dev_harness/{config,cli,desktop_profile,providers,safety,synthetic_profiles,qualification}.py`; shell wrappers | Keep Firestore Auth emulator, Firestore emulator, Redis, one backend, profiles, status/log/reset/down. |
| Offline provider boundary | `backend/testing/e2e/offline_backend_app.py`, `offline_desktop_backend_app.py`, E2E `conftest.py`, provider specs, `desktop_llm_stub.py` | Install all retained fakes/stubs in one offline app; no network, Dodo, durable cloud state, or hidden second process. |
| Harness tests | `scripts/dev-harness/tests/test_cli.py`, `test_env_stage.py`, `test_providers.py`, `test_desktop_profile.py`, safety/synthetic/qualification tests; `backend/testing/e2e` | Rewrite behavior around one process/URL while retaining isolation and fail-closed safety. |
| Redis | `redis_db.py`; auth/session/code, signed URL, generic cache, rate-limit/TTS, listen/device/platform locks, credit invalidation; direct `r` users in cache/job/fair-use/duration helpers | Preserve production-called ephemeral families; delete geolocation residue/deserializer and any newly proven no-caller rejected namespace. |
| Firestore indexes | `firestore_index_registry.py`, `generate_firestore_indexes.py`, `firestore.indexes.json`, query coverage, reconciler, runtime validator/workflows, tests | Keep fair-use serving spec; delete two test-only retired specs; preserve generated and create-only controls. |
| Runtime environment | `backend/deploy/runtime_env.yaml`, renderer/validator, `backend/tests/unit/test_backend_runtime_env_validator.py` | Merge the retained config/secret-name union into one service/two env without changing live identity values. |
| Runtime image | `runtime_images.json`, two Dockerfiles, runtime-image scripts/tests, `runtime_image_contracts.yml`, changed-files selection | End with one registered Python image/entrypoint; keep exact source/image closure. |
| Deployment lifecycle | `gcp_backend_auto_dev.yml`, `gcp_backend.yml`, three `desktop_backend_*` workflows; candidate/lineage/release scripts; concurrency and release-ring checks | Move retained compatibility/provider probes into canonical lanes, then delete duplicate mutation plane. |
| Workflow contracts | `backend/testing/workflow_contracts.json`, `WORKFLOW_CONTRACTS.md`, `test_workflow_contracts.py`, `.github/checks-manifest.yaml`, `desktop-backend-contracts.yml` | Retarget real high-risk paths and keep them in local+CI lanes; remove extinct entries only after canonical coverage. |
| Desktop release manifest | schema, validator, fixtures, doctor, promotion/break-glass utilities, backend update-channel tests | Collapse to app-only object; preserve immutable app artifact and live backend compatibility as independent evidence. |
| Preview routing | `desktop_publish_preview.yml`, signed `AppBuild.externalPreviewBackend`, preview tests and stored single `backend_url` | Accept/emit one backend URL and retain production-family fail-closed routing. |
| Generated/contracts/docs | route policy YAML/docs, app-client OpenAPI, generated Swift, backend/desktop AGENTS, FORK, README, E2E docs/skill, qualification docs | Regenerate and make service maps/commands truthful; no Windows client work. |

## 8. Behavior classification

| Classification | Exact S-26 contents |
|---|---|
| **KEEP AS IS** | User workflows and local ownership; auth and OAuth semantics; quota/fair-use; direct STT/model/TTS/provider selection and authorized failover; `/v4/listen`; updates/previews; account-deletion durability/reconciliation; `/v1/health`; authenticated metrics; free MVP with `BILLING_MODE=disabled`; Firebase Auth/Firestore emulators; Redis as ephemeral coordination; synthetic-user isolation; exact-main Release Eligibility; candidate/promotion/rollback/repair/break-glass; one development and one production environment. |
| **ADAPT** | `main:app` route/lifecycle identity; canonical `/v1/health` probe callers and internal dependency-validation seams; Mac URL resolver and all callers; local launcher; harness config/CLI/profile/offline fake installation; runtime env retained config/secret-name union; canonical candidate acceptance; route policy/OpenAPI/generated Swift; Firestore registry/manifest; release schema/previews; component guides. |
| **DELETE** | `desktop_backend.py`; `desktop_deprecated.py`; service-specific `/health` and `/ready` routes/identity after callers migrate; second URL/env var/port/process; `RUST_PORT` and false Rust naming; `offline_desktop_backend_app.py`; `Dockerfile.desktop_backend`; desktop-backend runtime-image entry and independent deploy/recovery workflows after controls move; dormant `backend_required` mode/fields/fixture; test-only retired Firestore conversation/chat specs/indexes; `get_cached_user_geolocation` and its now-unused deserializer; rejected scenarios and checks with no retained owner. |
| **SIMPLIFY AFTER** | After one-URL tests are green, collapse URL/environment APIs rather than leaving aliases. After canonical workflow parity is green, delete duplicate controls rather than wrap them. After query/key caller proof, reduce registries and fixtures to production owners. After source deletion, collapse changed-file and image matrices to one entry. |
| **ACCELERATE AFTER** | Measure clean `make dev-up`, one-save Python test, one-save Swift routing test, named-bundle relaunch, and shutdown/reset duration. Reuse `dev-feedback.py`, the harness lifecycle, and existing check manifest first. Add no new automation unless repeated measurements identify a stable bottleneck and an existing primitive cannot address it. |
| **OUT OF SCOPE / DEFERRED** | S-27 project/region/IAM/WIF/network/Artifact Registry/base-image/Secret Manager/Memorystore/live Cloud Run work; live resource query/drain/delete/deploy; S-28 namespaces; S-29 signing/notarization/update/public destinations; S-30 rebrand/copy; S-31 final qualification; Windows; Dodo activation; historical changelog erasure; new product behavior. |

## 9. Retained behavioral invariants

1. The assembled app preserves the same authenticated route semantics, response contracts, WebSocket behavior, timeout policy, startup/reconciler ownership, and sanitized logging. Removed routes genuinely 404/fail closed; there is no 410 compatibility shell.
2. Continuous listening remains transient cloud compute with local conversation persistence. No server conversation/audio/finalization ownership returns.
3. Typed Chat, Gemini Live, OpenAI Realtime, STT, TTS, API-key proxying, usage, and provider fallback keep their selected providers, model semantics, tool/approval/result ownership, telemetry, and error behavior.
4. Auth callback routing remains explicitly constrained by the registered Services ID; consolidating the data plane must not let a production-family app accept launch-environment endpoint overrides.
5. `BILLING_MODE=disabled` remains in dev/prod manifests and local/offline tests. There are no Dodo/Stripe calls, resources, fake-success payment paths, or activation claims.
6. Account deletion still persists intent before dispatch, sends opaque tasks to the canonical handler, accepts only the bounded canonical/legacy identities handed from S-25, retries/reconciles durably, and reaches completion. S-26 does not infer that the legacy queue is drained.
7. Redis loss preserves each existing fail-open/fail-closed decision. Redis stores only short-lived coordination/cache data, never authoritative product records.
8. Firestore composite indexes correspond to real serving compound queries. Runtime deploy lanes may check state and create an approved missing index; they do not auto-delete a live index.
9. One canonical development URL and one canonical production URL are selected from signed/bundle identity. Named/local bundles can use explicit loopback overrides; production-family bundles cannot be switched by launch environment.
10. Local/offline mode uses loopback-only Firebase emulators, Redis, one backend, synthetic identities, offline provider fakes by default, and instance-owned processes. It refuses production projects, endpoints, bundles, foreign PIDs/ports, and provider credentials in offline children.
11. Backend deployment remains independent of desktop artifacts. Candidate health and live compatibility protect release without embedding an optional same-SHA backend image into a Mac manifest.
12. Dev auto-deploy, manual dev/prod deploy, candidate acceptance, controlled traffic promotion, traffic rollback, exact-main eligibility, repair-only, and audited break glass remain for one service.
13. Mac local data, owner-generation fencing, account switching, restart/offline behavior, Home, Conversations, Memory, Tasks, Focus/Insights, Rewind, notifications, previews, Sparkle channels, and installation behavior are unchanged.
14. Neither `/Applications/Omi.app`, `/Applications/Omi Beta.app`, `com.omi.computer-macos`, nor `com.omi.computer-macos.beta` is built over, launched, stopped, restarted, or modified.

## 10. Target authority, ownership, identity, and topology model

| Concern | Sole repository authority after S-26 | Contract |
|---|---|---|
| Python application | `backend/main.py:app` | One lifecycle and route assembly; no second FastAPI app. |
| Backend URL selection | `DesktopBackendEnvironment` single canonical backend resolver | One URL per environment; explicit auth callback rule remains separate from data-plane topology. |
| Local backend process | Harness/launcher-owned `main:app` child | One loopback port, PID record, log and health target. |
| Offline app | `backend/testing/e2e/offline_backend_app.py` | Installs all retained fakes before importing canonical `main:app`. |
| Redis authority | `backend/database/redis_db.py` plus production callers | Ephemeral coordination only; no rejected key namespace. |
| Firestore index truth | `firestore_index_registry.py` → generated `firestore.indexes.json` | Only real serving compound queries; human-approved create-only live reconciliation. |
| Runtime configuration | `backend/deploy/runtime_env.yaml` | One `backend` service in dev and prod, retained vars/secret references only; no secret values. |
| Runtime image | `backend/Dockerfile` + one `runtime_images.json` entry | Exact source closure and immutable image evidence; S-27 later reowns base/registry. |
| Deploy mutation domain | `gcp_backend_auto_dev.yml` and `gcp_backend.yml` | One service, one environment-scoped concurrency domain, exact-main/candidate/promotion/rollback/repair/break-glass. |
| Backend compatibility | Canonical candidate probe + live health/compatibility evidence | Independent from desktop release manifest; fail closed. |
| Desktop artifact manifest | One app-artifact release schema | No `backend_required` mode or backend image digest fields. |
| Route/client contracts | assembled route policy + app-client OpenAPI + generated Swift | All generated from `main:app`; Windows excluded. |

The word “canonical” does not authorize a guessed hostname. During S-26, code has one semantic URL slot. S-27 supplies owned dev/prod identities and the final `us-west1` live topology. Existing inherited names in untouched infrastructure inputs remain explicitly provisional until then.

## 11. Ordered TDD cycles

There are **11 planned TDD cycles**. Before Cycle 1, perform the execution-time rebase/inventory gate from section 5. A RED must exercise production behavior through a controllable seam wherever behavior is involved. Source scans, manifest/schema checks, and workflow YAML inspection are labelled static contract checks and do not replace behavioral tests.

For focused backend tests, use the official runner from `backend/`: create a temporary newline-delimited list of the named current/new test files and run `BACKEND_UNIT_TEST_FILE_LIST="$s26_tests" bash test.sh`. Run test discovery after adding, moving, or deleting any test file.

### Cycle 1 — Make the assembled canonical app prove desktop-route and lifecycle parity

- **Intended behavioral or contract RED:** Add an assembled-`main.app` test that drives retained GET/HEAD `/v1/health`, authenticated desktop config/Chat/proxy/realtime/TTS boundaries, `/v4/listen`, account deletion and metrics registration; verifies service-specific `/health`, `/ready`, and other rejected compatibility routes return 404; and proves Redis/dependency failures through their retained controllable production seams rather than a public readiness alias. Assert one truthful canonical service identity and default-deny CORS.
- **Why it fails now:** `main.app` already mounts the six retained desktop router families, but health constants still say `omi-desktop-backend`; the only second-app-only router is a 410 compatibility shell; existing `desktop_core` tests assemble a tiny router-only app and do not prove the full production lifecycle/route intersection.
- **Minimum production change for GREEN:** Keep `/v1/health` unchanged as the sole public process-health endpoint; move any still-required Redis/dependency admission check into the canonical deploy/validation owner; delete `/health` and `/ready` once their in-tree callers are migrated; preserve the single Firebase/account-deletion lifespan; and ensure every retained desktop product route behaves on `main:app`. If a refreshed inventory proves an external `/health` or `/ready` caller, stop for an explicit coordinated cutover rather than adding a compatibility alias. Do not yet delete the second entrypoint until all other external/in-tree callers move.
- **Retained behavior protected:** Auth, Redis failure policy through actual operations and deployment validation, Chat/model/STT/TTS/realtime semantics, `/v1/health`, `/v4/listen`, update/account deletion/metrics, sanitized errors, and genuine absence of deleted routes.
- **Expected files:** `backend/main.py`, `backend/routers/desktop_core.py`; existing router tests; new `backend/tests/unit/test_s26_canonical_backend_app.py`; route policy only if the truthful health contract changes metadata.
- **Exact focused verification:** From `backend/`, run the official selector for `tests/unit/test_s26_canonical_backend_app.py`, `tests/unit/test_desktop_core.py`, `tests/unit/test_s25_retired_worker_routes.py`, `tests/unit/test_route_policy_inventory.py`, and `tests/unit/test_openapi_contract.py`; then run `scripts/openapi_runner.sh scripts/route_policy_inventory.py --manifest route_policy_manifest.yaml --check --report-only`.
- **Deletion/simplification enabled:** Establishes `main:app` as the only behaviorally complete target, allowing Mac/harness/workflow callers to migrate without a compatibility layer.
- **Stop conditions:** Stop if a retained route exists only in `desktop_backend.py`, if auth/CORS behavior conflicts between apps, or if a predecessor route is missing. Resolve the authoritative owner before proceeding; do not mount the deprecated shell in `main.app`.

### Cycle 2 — Route every Mac backend call through one fail-closed URL authority

- **Intended behavioral or contract RED:** Extend `APIClientRoutingTests` to prove all retained REST/WebSocket/provider/API-key/TTS/usage call families resolve the same canonical base for production, development, named bundle, and signed external preview; production-family launch overrides remain ignored; malformed preview metadata fails to production.
- **Why it fails now:** `DesktopBackendEnvironment` exposes Python and falsely named Rust URL families, `OMI_PYTHON_API_URL` and `OMI_DESKTOP_API_URL`; APIClient, account services, Pi runtime, Gemini/embedding clients and automation diagnostics call different resolvers.
- **Minimum production change for GREEN:** Introduce one backend base resolver/environment variable, migrate every Swift caller and diagnostic to it, retain the explicit auth callback rule, and remove the second URL API instead of keeping a deprecated alias.
- **Retained behavior protected:** Production endpoint immutability, named-bundle loopback overrides, preview fail-closed behavior, auth retry, Realtime/Chat/provider behavior, and existing transport error semantics.
- **Expected files:** `DesktopBackendEnvironment.swift`, `APIClient.swift`, `APIClient+Account.swift`, `APIKeyService.swift`, `AgentRuntimeProcess.swift`, `GeminiClient.swift`, `EmbeddingService.swift`, `OmiHTTPTransport.swift`, `TranscriptionService.swift`, `DesktopAutomationBridge.swift`, `APIClientRoutingTests.swift`, `APIClientAuthRetryTests.swift` and adjacent routing tests.
- **Exact focused verification:** From `desktop/macos/`, run `python3 scripts/dev-feedback.py --once swift 'APIClientRoutingTests'`, `python3 scripts/dev-feedback.py --once swift 'APIClientAuthRetryTests'`, then the affected per-suite filters discovered in `Desktop/Tests`; run `./scripts/desktop-core-harness.sh --self-check` after diagnostics change.
- **Deletion/simplification enabled:** Deletes `productionRustBackendURL`, `developmentRustBackendURL`, `rustBackendURL`, `OMI_DESKTOP_API_URL`, `rustBackendURL` diagnostics, and dual-base call-site branching once no caller remains.
- **Stop conditions:** Stop if a current endpoint is not mounted by `main.app`, if signed preview metadata cannot express the one environment choice, or if consolidation would let a production-family app honor an environment override.

### Cycle 3 — Collapse the owned local backend launcher to one canonical process

- **Intended behavioral or contract RED:** Add shell/Python behavior tests that launch a fake/controlled canonical server target and prove `run.sh`, instance allocation, health, restart, PID metadata, foreign-port refusal, and cleanup own exactly one backend process and one port.
- **Why it fails now:** `run.sh` sources `python-desktop-backend-dev.sh` and launches `desktop_backend:app`; `scripts/dev-instance.sh` allocates `RUST_PORT`; `dev-feedback.py` watches `backend/desktop_backend.py`; `backend/scripts/dev-serve.sh` separately knows the canonical entrypoint.
- **Minimum production change for GREEN:** Reuse/adapt one canonical `main:app` launcher with the existing process-start/PID/process-group safety, one `PYTHON_PORT`/backend port, and truthful naming. Keep tunnel/auth-seed opt-outs and named-bundle safety.
- **Retained behavior protected:** Fast local launch, restart-on-source/config-change, foreign process refusal, owned cleanup, logs, `OMI_SKIP_BACKEND`, `OMI_SKIP_TUNNEL`, and no interaction with production bundles.
- **Expected files:** `desktop/macos/run.sh`, launcher helper (rename/adapt or replace `python-desktop-backend-dev.sh`), `scripts/dev-instance.sh`, `backend/scripts/dev-serve.sh` if a shared seam is needed, `desktop/macos/scripts/dev-feedback.py`, `test-fast-dev-bundle.sh`, `test-yolo-dev-backend.sh`, `test-dev-feedback.py` and launcher contract tests.
- **Exact focused verification:** From repo root run `bash desktop/macos/tests/test-fast-dev-bundle.sh`, `bash desktop/macos/tests/test-yolo-dev-backend.sh`, and `python3 desktop/macos/tests/test-dev-feedback.py`; from `desktop/macos/` run `python3 scripts/dev-feedback.py --once python 'tests/unit/test_s26_canonical_backend_app.py'` after the watch target moves.
- **Deletion/simplification enabled:** Removes `RUST_PORT`, second-backend PID/log metadata and the falsely named helper after its safety logic is retained under the canonical owner.
- **Stop conditions:** Stop if the launcher might kill a foreign process, reuse a production bundle ID, or bind a non-loopback interface in the local profile. Do not weaken ownership validation to make consolidation pass.

### Cycle 4 — Make one harness process exercise every retained offline/local boundary

- **Intended behavioral or contract RED:** Rewrite harness behavior tests so `make dev-up` starts Auth emulator, Firestore emulator, Redis and exactly one canonical backend; its profile exports one URL; offline child credentials are stripped; the single offline app provides OpenAI/Modulate fakes plus `OMI_LLM_STUB=1`; status/summary/log/reset/down and two synthetic accounts still work.
- **Why it fails now:** Harness config/CLI/profile/summary contain `backend` and `desktop_backend` ports, processes and URLs, and fake installation is split between two offline app modules.
- **Minimum production change for GREEN:** Remove the second port/service config and CLI lifecycle, merge retained fake setup into `offline_backend_app.py`, supply the full canonical child environment, and point the desktop profile at the one loopback URL.
- **Retained behavior protected:** `local`/`offline` stage identity, Firebase project/database safety, Redis, provider preflight/budgets, no-network offline behavior, synthetic-user isolation, account-deletion Cloud Tasks fake, `BILLING_MODE=disabled`, session evidence watermark, and owned reset/cleanup.
- **Expected files:** `scripts/dev-harness/dev_harness/config.py`, `cli.py`, `desktop_profile.py`, providers/qualification only if their endpoint list changes, `desktop-core-harness.sh`, `local-profile-env.sh`, `verify-desktop-local-launch.sh`, `backend/testing/e2e/offline_backend_app.py`, delete `offline_desktop_backend_app.py`, harness tests and relevant backend E2E tests.
- **Exact focused verification:** From repo root run `bash scripts/dev-harness/run-tests.sh`; from `backend/`, select `testing/e2e/test_harness_guards.py`, account-deletion harness tests and retained offline route tests with their documented hermetic runner; then run `PROVIDER_MODE=offline OMI_LOCAL_INSTANCE=s26-contract OMI_APP_NAME=omi-wave5-s26 make dev-check`, `make dev-up`, `make dev-status`, `make dev-summary`, `make dev-down` using that isolated instance.
- **Deletion/simplification enabled:** Deletes `DESKTOP_BACKEND_PORT`, `OMI_HARNESS_DESKTOP_BACKEND_PORT`, `desktop_backend_url/host`, second service records/health, dual endpoint evidence and the second offline app.
- **Stop conditions:** Stop if offline mode attempts network/provider/payment/cloud access, if account-deletion fake no longer exercises the production dispatcher seam, if a synthetic profile can target an Omi production endpoint/project/bundle, or if cleanup cannot prove process ownership.

### Cycle 5 — Narrow Redis to production-called ephemeral coordination

- **Intended behavioral or contract RED:** Add behavior tests that enumerate the allowed Redis adapter operations through fake Redis, exercise retained session/code expiry, rate limits, locks, caches and invalidation, and reject durable product ownership. Add a labelled static caller tripwire for every exported key helper.
- **Why it fails now:** `get_cached_user_geolocation()` reads `users:{uid}:geolocation`, explicitly calls itself S-23 residue, and has no production caller; `_deserialize_cache_value()` exists only for it. Historical tests also monkeypatch deleted Redis symbols, obscuring the actual surface.
- **Minimum production change for GREEN:** Delete the geolocation helper, its private deserializer/imports, stale comments/test monkeypatches, and any additional no-production-caller rejected key discovered by the refreshed inventory. Keep all proven production-called ephemeral helpers with current TTL and failure behavior.
- **Retained behavior protected:** Auth sessions/codes, signed URL and generic caches, rate-limit/TTS counters, listen/device/platform locks, credit invalidation, update/subscription/provider caches, Redis connectivity/failure semantics through their production owners, and each current fail-open/fail-closed branch.
- **Expected files:** `backend/database/redis_db.py`, `backend/tests/unit/test_redis_db_cache_serialization.py`, rate-limit/auth/fair-use/listen/update tests, `backend/testing/e2e/conftest.py`, and a narrow Redis surface contract test/static checker only if an existing import/caller primitive cannot enforce it.
- **Exact focused verification:** From `backend/`, use the official selector for `tests/unit/test_redis_db_cache_serialization.py`, `tests/unit/test_rate_limiting.py`, `tests/unit/test_firestore_read_ops_cache.py`, auth/TTS/desktop-proxy/listen/fair-use tests selected from current callers, and the new Redis surface test; rerun `testing/e2e/test_harness_guards.py` through its hermetic runner.
- **Deletion/simplification enabled:** Removes `users:*:geolocation`, `_deserialize_cache_value`, stale deleted-symbol monkeypatches and any newly proven rejected namespace. It does not delete live Redis keys or change Memorystore.
- **Stop conditions:** Stop when a candidate helper has any production caller, unclear TTL/authority, or a failure-mode dependency. Classify it KEEP until production behavior proves deletion safe; do not use a source zero as sole proof.

### Cycle 6 — Prune Firestore indexes to surviving serving queries

- **Intended behavioral or contract RED:** Change query/index contract tests to require every registered spec to have a production serving caller and require the generated manifest to contain only surviving compound queries. Retain a behavior test building the fair-use query and reconciliation tests proving check-only and approved create-only operation.
- **Why it fails now:** `STALE_IN_PROGRESS_CONVERSATIONS_QUERY` and `STARRED_CHAT_SESSIONS_QUERY` are referenced only by registry/tests after earlier authority deletion; only `FAIR_USE_FLAGGED_STATES_QUERY` is called from `database/fair_use.py`. Current tests preserve the retired shapes.
- **Minimum production change for GREEN:** Delete the two test-only query specs, update `QUERY_SPECS`, regenerate `firestore.indexes.json`, update query-coverage baseline/tests only from the real inventory, and retain fair-use plus safe reconciliation.
- **Retained behavior protected:** Fair-use review query semantics, deterministic manifest generation, no raw unregistered serving compound query, read-only state checks, signed proposal validation, human-approved create-only provisioning, and no automatic deletion.
- **Expected files:** `backend/database/firestore_index_registry.py`, `firestore.indexes.json`, `backend/scripts/firestore_query_coverage_baseline.json`, `test_firestore_query_contract.py`, `test_reconcile_firestore_indexes.py`, runtime validator/workflow tests if expected counts change.
- **Exact focused verification:** From repo root run `python3 backend/scripts/generate_firestore_indexes.py` (check mode). From `backend/`, select `tests/unit/test_firestore_query_contract.py`, `tests/unit/test_reconcile_firestore_indexes.py`, `tests/unit/test_backend_runtime_env_validator.py`, and fair-use query tests with `test.sh`. Do not run a live `--check-only` or `--provision-missing` command in S-26.
- **Deletion/simplification enabled:** Removes the conversation and starred-chat registry entries, generated composite indexes, fixtures and count assumptions. Live index deletion is not enabled or authorized.
- **Stop conditions:** Stop if execution-time query coverage finds a production caller for either spec, a new surviving compound query lacks a registered spec, or manifest regeneration would remove an index still used outside the scanned source. Mark live state `unknown` under BL-002.

### Cycle 7 — Make one runtime manifest describe the full retained app

- **Intended behavioral or contract RED:** Extend runtime-manifest behavioral/render tests so dev and prod each contain exactly one `backend` service with the union of required retained route configuration and secret references, including providers, Redis, Firebase/auth, account deletion, updates/previews, telemetry and disabled billing; reject a second service and literal secret values.
- **Why it fails now:** `runtime_env.yaml` has one service but the desktop workflows independently inject retained Gemini/OpenAI/Anthropic/Firebase/Redis settings not represented in that manifest. Its project/region/network fields remain inherited and provisional for S-27.
- **Minimum production change for GREEN:** Merge retained variable/secret-name declarations into the one service, update renderer/validator fixtures, preserve typed required/provisional categories, and leave project/region/network/identity values untouched and explicitly successor-owned.
- **Retained behavior protected:** Two environments, `BILLING_MODE=disabled`, account-deletion canonical/legacy bounded inputs, provider fail-closed config, update/preview controls, sanitized telemetry, Redis readiness, and absence of secret values from Git.
- **Expected files:** `backend/deploy/runtime_env.yaml`, render/validate scripts only if their one-service schema needs simplification, `test_backend_runtime_env_validator.py`, `test_render_backend_runtime_env.py`, environment docs; no live secret/IAM files.
- **Exact focused verification:** From repo root run `python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-workflows`, the same for `prod`, and both with `--check-rendered-cloud-run`; from `backend/`, select the two runtime-env test files with `test.sh`.
- **Deletion/simplification enabled:** Eliminates desktop-workflow-only runtime configuration and makes later duplicate workflow deletion safe. It does not delete inherited project/region fields or create S-27 identities.
- **Stop conditions:** Stop if a retained router reads an undeclared required value, if a secret value would need to enter source, if the validator requires a guessed live identity, or if deleting legacy account-deletion inputs lacks drain evidence.

### Cycle 8 — Merge candidate, deploy, rollback and recovery safety into one workflow plane

- **Intended behavioral or contract RED:** Through controllable fake command/API seams, require the canonical dev/prod workflows to admit exact main, build one candidate image, validate unchanged `/v1/health`, verify required Redis/dependency readiness through canonical non-route deploy checks, verify release SHA and Chat/provider compatibility, promote one revision, verify serving identity, restore the traffic snapshot on failure, and retain repair-only/break-glass evidence. Assert the workflow no longer probes `/health` or `/ready`.
- **Why it fails now:** canonical workflows own exact-main release/promotion/rollback while `desktop_backend_*` workflows separately own desktop health/readiness, Chat contract, voice-provider probes, image lineage and a second traffic mutation domain.
- **Minimum production change for GREEN:** Adapt the reusable candidate probe/lineage controls to target the canonical service and invoke them from `gcp_backend_auto_dev.yml`/`gcp_backend.yml`; retarget `workflow_contracts.json`; preserve one environment-scoped concurrency group and the existing release/traffic recovery primitives. Keep the old workflows until the canonical static and behavioral contracts are green.
- **Retained behavior protected:** IR-841 through IR-846: check-gated dev auto-deploy, exact-main Release Eligibility, no-traffic candidate, compatibility/provider checks, controlled promotion, post-promotion identity, rollback, repair-only, and audited break glass.
- **Expected files:** canonical workflows; candidate/lineage scripts (truthfully renamed if retained); their tests; `workflow_contracts.json`; `test_workflow_contracts.py`; release-ring/concurrency/runtime validators; `.github/checks-manifest.yaml` only to retarget an existing real guard.
- **Exact focused verification:** Run `python3 backend/scripts/check_workflow_contracts.py`, `python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-workflows`, the prod equivalent, candidate-probe/lineage script tests, `.github/scripts/test_check_release_rings.py`, deployment concurrency tests, and the official backend selector for `test_workflow_contracts.py`/runtime image/env tests. No workflow dispatch or cloud call.
- **Deletion/simplification enabled:** Once canonical parity is green, the second deploy/prod/recover workflow plane and desktop-only workflow contract can be removed in Cycle 10.
- **Stop conditions:** Stop if tests cannot prove rollback from an observed traffic snapshot, if a provider probe requires unavailable live credentials during repository checks, if exact-main scope weakens, or if implementation crosses into WIF/service-account/project/region/network mutation. A new gate may land only if it cites the real merged incident/PR it would catch and explains why existing shared primitives cannot enforce it.

### Cycle 9 — Decouple desktop artifacts and previews from a second backend image/URL

- **Intended behavioral or contract RED:** Make manifest validator/schema/doctor/promotion tests accept exactly the app-artifact object and reject `backend_required` and all desktop-backend digest/source fields. Make preview workflow tests prove one signed backend environment/URL reaches the bundle and malformed/production override attempts fail closed.
- **Why it fails now:** schema/validator/fixtures still admit `backend_required`; preview dispatch accepts and exports `python_api_url` plus `desktop_api_url`; release tooling carries compatibility code even though current promotion emits `app_only`.
- **Minimum production change for GREEN:** Remove the optional backend mode and fields from schema, validator, fixtures and consumers; simplify preview inputs/payload to one canonical backend URL/environment; retain live compatibility evidence as an independent qualification input, not an app-manifest artifact.
- **Retained behavior protected:** Immutable app artifact identity, signed preview metadata, production-family route safety, backend-independent Mac release, candidate qualification, Beta/Stable promotion/rollback/break glass, and preview storage's single optional backend URL.
- **Expected files:** desktop release schema/validator/fixtures/tests/doctor/promotion utilities as needed; `desktop_publish_preview.yml`; preview/routing/release-flow contract tests; related backend update-channel fixtures/tests and qualification docs.
- **Exact focused verification:** From repo root run `.github/scripts/test_desktop_release_manifest.py`, `test_desktop_release_manifest_schema.py`, `test_desktop_release_doctor.py`, `test_desktop_release_flow_contract.py`, `scripts/run-release-process-guards.sh`, and focused preview/routing workflow tests listed in `.github/checks-manifest.yaml`; select `backend/tests/unit/test_desktop_release_scripts.py` and update-channel tests with `backend/test.sh`.
- **Deletion/simplification enabled:** Deletes `backend_required`, its fixture, three backend image identity fields, dual preview URL inputs/payload and their compatibility branches.
- **Stop conditions:** Stop before changing signing, notarization, channels, public destinations, release identities, Codemagic, Sparkle feed ownership, or publishing a preview. Those are S-29/external operations.

### Cycle 10 — Delete the duplicate entrypoint, image and workflow topology

- **Intended behavioral or contract RED:** Turn runtime-image, changed-file, workflow-policy and import tests into a one-entrypoint contract: exactly `backend/main.py:app`, one Dockerfile/image registry entry, and canonical deployment workflows. Assert imports/routes have no compatibility shell or duplicate app.
- **Why it fails now:** `desktop_backend.py`, `desktop_deprecated.py`, `Dockerfile.desktop_backend`, the `desktop-backend` registry entry, three deploy/recovery workflows, desktop-only candidate/lineage naming and checks remain after callers are migrated.
- **Minimum production change for GREEN:** Delete the second source/router/Docker/workflows and all now-orphaned controls/tests; collapse runtime image and change-selection matrices; update canonical Docker source closure and dependency smoke. Preserve any reusable probe under a canonical name only if Cycle 8 proves it is still needed.
- **Retained behavior protected:** All Cycle 1 route/lifecycle behavior, exact image/source closure, canonical workflow safety, app release behavior and offline/local harness acceptance.
- **Expected files:** the deletion targets above; `runtime_images.json`; runtime image scripts/tests/workflow; changed-files detection tests; workflow policy/check manifest entries; backend/desktop guides and FORK service inventory in Cycle 11.
- **Exact focused verification:** From repo root run `python3 backend/scripts/runtime_image_contracts.py check`, `make runtime-image-source-closure`, `python3 backend/scripts/check_workflow_contracts.py`, changed-files/check-manifest tests, and exact residue scans from section 13; from `backend/`, select runtime-image, workflow, route and canonical-app tests with `test.sh`.
- **Deletion/simplification enabled:** This GREEN performs the physical repository deletion of the duplicate backend plane and leaves no deprecated alias, adapter, fallback URL, second image or second mutation workflow.
- **Stop conditions:** Stop if any in-tree caller, generated artifact, local profile, release check or retained candidate probe still depends on a deletion target. Do not infer that similarly named live Cloud Run revisions/images/secrets can be deleted.

### Cycle 11 — Regenerate contracts, make documentation truthful, measure, and accept the surviving loop

- **Intended behavioral or contract RED:** Final contract checks require route policy, OpenAPI, generated Swift, runtime/image/index/workflow manifests, E2E instructions, component guides and FORK inventory to describe one backend; Tier 2 and named-bundle acceptance exercise the one-URL stack. Every residue hit must have a retained owner or deletion.
- **Why it fails now:** docs/E2E still teach two overrides and a “Rust backend”; generated/manifests reflect transitional source; the measured feedback loop watches `desktop_backend.py`; no S-26 named-bundle evidence exists.
- **Minimum production change for GREEN:** Regenerate from `main.app`, update owning docs and checks, remove stale names, correct only closure defects found by real tests, and record durations for clean harness start, focused Python/Swift rerun, named-bundle launch and teardown. Prefer existing commands; introduce automation only for a measured stable repetition and under the repository new-guard rules.
- **Retained behavior protected:** Complete product behavior register, Mac isolation, app-client wire compatibility, route auth/data policies, exact deploy/release safety, account lifecycle, offline/restart behavior, and truthful operator setup.
- **Expected files:** `backend/route_policy_manifest.yaml`, app-client OpenAPI, generated macOS Swift, `backend/AGENTS.md`, `desktop/macos/AGENTS.md`, `FORK.md`, backend README/docs, desktop E2E `SKILL.md`/`CORE_E2E.md`, qualification/local-profile docs, `.env.example`, affected tests and manifest controls. Historical changelogs remain untouched.
- **Exact focused verification:** Run all commands in sections 14 and 15, including the ledger validator, component suites, Tier 2 with `omi-wave5-s26`, named-bundle canonical health and retained user paths, `make preflight`, `git diff --check`, and classified residue searches.
- **Deletion/simplification enabled:** Deletes final stale terminology/docs/fixtures and closes the repository topology. Measured acceleration findings with no safe in-slice change are recorded for S-31 rather than converted into speculative automation.
- **Stop conditions:** Stop closure on any unexplained rejected hit, stale generated file, hidden second service dependency, production-bundle risk, failed retained path, or missing external input. Repository GREEN does not upgrade BL-001/BL-002 or authorize live mutation.

## 12. Cross-slice ownership and handoffs

| Slice / owner | S-26 consumes | S-26 hands off / must not absorb |
|---|---|---|
| S-04 | Assembled route-policy/OpenAPI/generated-client discipline and current Mac backend boundary | One truthful `main.app` surface and regenerated non-Windows client; no route compatibility shell. |
| S-08 | Canonical auth/account lifecycle, persisted deletion intent, durable task/reconciler and disabled billing | Same behavior mounted once; legacy identity retained until verified drain. |
| S-10–S-20 | Local product authorities, account/owner fencing, retained Chat/PTT/realtime paths | One URL with no change to their storage/result/product semantics. |
| S-22 | Direct provider/STT/model/TTS routes and provider failover | One canonical candidate/harness probe; no provider re-selection. |
| S-24 | Local search/storage and removal of hosted product-data stores | Harness/index/key inventories with no deleted cloud store reintroduced. |
| S-25 | Canonical retained service topology and repository-deleted workers/GKE paths; live state remains unknown | Delete the temporary duplicate Python app/image/workflows. Never claim live S-25 resources absent. |
| S-27 | None—S-27 depends on integrated S-26 | One service/two-environment manifest, canonical workflows, retained secret/config names, index registry and Redis dependency ready for owned projects, `us-west1`, WIF, IAM, networking, Memorystore, Secret Manager, Artifact Registry and controlled base image. |
| S-28 | Independent; no namespace work consumed | Named-bundle proof only. Do not rename production bundle/app group/Keychain/storage identity. |
| S-29 | None until it consumes S-26/S-27/S-28 | App-only release manifest, one preview/backend URL, live compatibility contract independent of Mac artifact. Do not reown signing/notarization/channels/public destinations. |
| S-30 | No rebrand work | Truthful topology terminology only; product identity/copy/legal pass remains S-30. |
| S-31 | No final qualification claim | Cycle-time measurements, open BL-001/BL-002 gates, repository acceptance and exact remaining operational evidence. |

Shared IR-808, IR-843 through IR-849, IR-890 and IR-891 are divided by authority: S-26 owns the repository application's dependency/configuration shape; S-27 owns real infrastructure identities and deployment. No temporary alias is added to bridge the slices.

## 13. Repository residue-search strategy

Run before Cycle 1, after each deletion cycle, and at closure. Search exclusions prevent the roadmap itself and Git history from becoming false positives:

```bash
rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'desktop_backend|desktop-backend|Dockerfile\.desktop_backend|omi-desktop-backend' \
  backend desktop/macos scripts .github Makefile FORK.md

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'OMI_DESKTOP_API_URL|RUST_PORT|rustBackendURL|Rust backend|productionRustBackendURL|developmentRustBackendURL' \
  backend desktop/macos scripts .github Makefile FORK.md

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'backend_required|backend-required|desktop_backend_source_sha|desktop_backend_oci_index_digest|desktop_backend_platform_digest' \
  backend desktop/macos .github

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'get_cached_user_geolocation|users:.*:geolocation|STALE_IN_PROGRESS_CONVERSATIONS_QUERY|STARRED_CHAT_SESSIONS_QUERY|conversations_in_progress_by_finished_at|chat_sessions_starred_by_updated_at' \
  backend firestore.indexes.json
```

Positive retained searches must find owners and tests:

```bash
rg -n 'FAIR_USE_FLAGGED_STATES_QUERY|fair_use_flagged_states_by_updated_at' backend firestore.indexes.json
rg -n 'set_auth_session|check_rate_limit|check_tts_rate_limit|try_acquire_.*lock|credits_invalidated|cache:' backend
rg -n '/v4/listen|/v1/health|/health|/ready|/metrics|account-deletion|BILLING_MODE' backend desktop/macos .github
rg -n 'Release Eligibility|repair-traffic-only|skip_eligibility_proof|break_glass_reason|traffic.*snapshot|rollback' .github backend
rg -n 'OMI_PYTHON_API_URL|backendBaseURL|main:app|runtime_env.yaml|firestore.indexes.json' backend desktop/macos scripts .github Makefile FORK.md
```

Classify every hit as retained owner, generated/history/test fixture that must adapt, successor-owned provisional input, or rejected residue. A zero-count is paired with a behavioral or manifest test. Generic words such as `backend`, `cache`, `preview`, `sync`, or `rust` are never bulk-deleted without reviewing context. Historical changelog references remain history.

## 14. Focused and component-level verification commands

No command in this section is claimed green by the plan. Refresh file filters against the execution-time checkout.

### Backend and harness inner loop

```bash
cd backend
s26_tests="$(mktemp)"
printf '%s\n' \
  tests/unit/test_s26_canonical_backend_app.py \
  tests/unit/test_desktop_core.py \
  tests/unit/test_route_policy_inventory.py \
  tests/unit/test_openapi_contract.py \
  tests/unit/test_backend_runtime_env_validator.py \
  tests/unit/test_render_backend_runtime_env.py \
  tests/unit/test_runtime_image_contracts.py \
  tests/unit/test_workflow_contracts.py \
  tests/unit/test_firestore_query_contract.py \
  tests/unit/test_reconcile_firestore_indexes.py \
  tests/unit/test_redis_db_cache_serialization.py \
  > "$s26_tests"
BACKEND_UNIT_TEST_FILE_LIST="$s26_tests" bash test.sh
```

Add current auth, Chat, realtime, STT/TTS, listen, fair-use and account-deletion tests to the list during the owning cycle. Run `backend/test.sh` discovery checks whenever tests move/delete. For the harness:

```bash
cd ..
bash scripts/dev-harness/run-tests.sh
PROVIDER_MODE=offline OMI_LOCAL_INSTANCE=s26-verify OMI_APP_NAME=omi-wave5-s26 make dev-check
PROVIDER_MODE=offline OMI_LOCAL_INSTANCE=s26-verify OMI_APP_NAME=omi-wave5-s26 make dev-up
OMI_LOCAL_INSTANCE=s26-verify make dev-status
OMI_LOCAL_INSTANCE=s26-verify make dev-summary
OMI_LOCAL_INSTANCE=s26-verify make dev-down
```

### Generated routes, runtime, images, indexes and workflows

From `backend/`:

```bash
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
scripts/openapi_runner.sh scripts/route_policy_inventory.py --manifest route_policy_manifest.yaml --check --report-only
```

From repository root:

```bash
python3 backend/scripts/generate_firestore_indexes.py
python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-workflows
python3 backend/scripts/validate-backend-runtime-env.py --env prod --check-workflows
python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-rendered-cloud-run
python3 backend/scripts/validate-backend-runtime-env.py --env prod --check-rendered-cloud-run
python3 backend/scripts/runtime_image_contracts.py check
make runtime-image-source-closure
python3 backend/scripts/check_workflow_contracts.py
bash scripts/dev-harness/run-tests.sh
```

`reconcile_firestore_indexes.py --check-only` and `--provision-missing` require a verified project/operator and are not repository validation commands for S-26. Unit tests with fake command runners prove their control behavior; S-27 performs authorized live proof.

### Desktop and complete repository gates

```bash
cd desktop/macos
python3 scripts/dev-feedback.py --once swift 'APIClientRoutingTests'
./scripts/desktop-core-harness.sh --self-check
./test.sh

cd ../..
cd backend && bash test.sh
cd ../desktop/macos && ./test.sh
cd ../..
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
scripts/pr-preflight --suggest
make preflight
scripts/pr-preflight --pr-body-file /tmp/s26-pr-body.md
```

The implementation PR must list commands, durations and outcomes; run `scripts/pr-preflight --suggest` before any `fix:` PR body and declare/validate each required failure class. A new deterministic check must be registered in `.github/checks-manifest.yaml` with local and CI lanes, cite a real merged PR/incident it would have caught, and explain why an existing shared primitive cannot enforce it.

## 15. Real named-bundle, backend, infrastructure, or release acceptance

### Hermetic and named-bundle repository acceptance

Use the repository E2E confidence ladder and only the assigned non-production bundle. Run the hermetic Tier-2 harness first:

```bash
cd desktop/macos
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-wave5-s26
```

For the interactive named-bundle path, start the offline stack and keep the launcher running in shell 1:

```bash
cd <repository-root>
PROVIDER_MODE=offline make dev-up
make desktop-run-local DESKTOP_APP_NAME=omi-wave5-s26 DESKTOP_USER=alice
```

After the named bundle is ready, run the semantic/native checks from shell 2:

```bash
cd <repository-root>/desktop/macos
./scripts/omi-ctl health
agent-swift connect --bundle-id com.omi.omi-wave5-s26
```

Do not place commands after foreground `run.sh`/`make desktop-run-local` in the same shell. Read the post-S-28 bundle identifier from the launcher if the current `com.omi.*` development mapping has changed, and use that reported non-production identifier for `agent-swift`.

Record exact source SHA, bundle ID, backend URL, harness instance/provider mode, command duration and sanitized result. Use `omi-ctl` semantic state/actions first and `agent-swift` for native UI/permission inspection. Required future evidence:

1. Tier 2 proves startup, auth fixture boundaries, Home, local Conversations, Memory, Tasks, Rewind, notifications, offline/restart/restoration, account switching, same-UID reauthentication, owner isolation, persistence failure, auth loss and late-result rejection.
2. `omi-wave5-s26` launches without touching either production bundle and reports exactly one canonical loopback/development backend URL.
3. Offline typed Chat, realtime-provider selection/failover, TTS/API-key proxying and a synthetic continuous-listen session reach the canonical app with normal success/error semantics and no external network call.
4. Continuous listen produces transient transcripts/generic speaker labels and one local conversation commit, with no server conversation/audio/finalization side effect.
5. Controlled Redis unavailability, backend restart, provider timeout/suspension and late results exercise retained failure/reconnect/fencing behavior without duplicate commits or a deleted-service fallback.
6. Canonical account-deletion dispatch/retry/reconciliation is proven first through the hermetic production seam with a fake queue and opaque payload. No ordinary seeded account is deleted.
7. Removed routes return real 404/WebSocket rejection; health/readiness, authenticated metrics, updates/previews, export/account/usage and `BILLING_MODE=disabled` remain.
8. `make dev-reset`, sign-out, account switch and reinstall of the named bundle do not weaken local authority or touch production identities.

### Separately gated backend/infrastructure/release evidence

S-26 repository acceptance does not run a Cloud Run deploy, Firestore reconciliation, provider-paid call, signed candidate, preview publication, promotion, rollback, or account deletion against a real identity.

After S-27 supplies verified owned identities, its acceptance must deploy the one-service dev candidate from an exact admitted main SHA, prove both health surfaces, streaming/Chat/provider compatibility, account-deletion queue identity, Redis connectivity, promotion, serving revision, rollback and repair-only/break-glass evidence. After S-28/S-29, signed candidate/update/preview/release acceptance consumes the app-only manifest and one canonical URL. Those operations require their own authorization and evidence; failure leaves the corresponding row open.

## 16. Repository closure versus separately authorized operational closure

### Repository implementation closure

Repository closure means all 11 cycles are green; only `main:app`, one Mac URL seam, one local backend process, one offline app, one image entry and canonical deployment workflows remain; route/OpenAPI/generated Swift/runtime/image/index/workflow/release manifests agree; retained component suites and `omi-wave5-s26` pass; docs are truthful; and every residue hit is classified.

It does **not** mean a live service/image/key/index/secret/IAM binding/queue/URL is absent, drained, deleted, deployed or healthy. It does not close BL-001, BL-002, S-27, S-29 or S-31.

### Read-only live inventory after identity verification

Using S-27's verified environment/project identity, an authorized operator later records sanitized read-only evidence for:

- canonical and any `desktop-backend` Cloud Run services, revisions, URLs, ingress, traffic and runtime/deploy accounts;
- image digests/tags and every revision/rollback reference;
- Redis/network endpoints and consumers without reading values/product data;
- Secret Manager/IAM reference graphs without reading secrets;
- Firestore live index names/states versus the pruned manifest;
- account-deletion queue target/audience/signer, task counts/age/retry state without payload content;
- provider, health, metrics/alerts and deployment workflow identity.

Classify each resource independently as retained, rejected, shared, unknown or already absent. Unknown ownership, traffic, retention, rollback, legal or project identity stops that resource's closure.

### Separately authorized mutation

Only a later explicit authorization for named resources/environment may permit deploy, traffic shift, queue drain, live index deletion, service/image/secret/IAM cleanup or release. The operator must capture pre-state/rollback evidence, deploy and accept the canonical service first, stop new producers, observe zero traffic/work, mutate one dependency family at a time, verify rollback or completion, and rerun sanitized inventory. A merged S-26 PR is not deploy or teardown approval.

## 17. Risks, ambiguities, and explicit stop points

| Risk / ambiguity | Affected cycles | Required response |
|---|---|---|
| `main.app` mounts `/health` and `/ready` beside the retained `/v1/health` | 1, 8, 11 | Migrate in-tree probes and dependency validation to their canonical owners, keep `/v1/health` unchanged, delete `/health`/`/ready`, and assert both return 404. Stop for an explicit coordinated cutover if a refreshed inventory proves an external caller; do not add a compatibility alias. |
| Auth callback uses `api.omi.me` because of a registered Services ID | 2, 9 | Keep auth callback policy explicit; do not mistake it for permission to retain two data-plane backends. S-29/S-30 later reown identity/domain. |
| Provider routes currently receive config only in desktop workflows | 7–8 | Merge names, not values; use fake/strict missing-config tests. Stop before guessing Secret Manager bindings. |
| Candidate probes are split and some require provider credentials | 8 | Separate hermetic control behavior from authorized deployed probe evidence; do not weaken a provider gate or claim it passed locally. |
| Legacy account-deletion audience may have live queued tasks | 1, 7–8, 16 | Preserve bounded legacy acceptance until verified drain; no source cleanup based only on repository callers. |
| Firestore specs appear “registered” because tests manufacture their only callers | 6 | Use production-source serving caller inventory plus behavioral fair-use test; tests cannot justify a production index alone. |
| Generic Redis cache has many dynamic key paths | 5 | Delete only exact helper/key families proven rejected; classify dynamic production callers and retain TTL/failure semantics. |
| S-26 and S-29 both reference `backend_required` deletion | 9 | S-26 owns schema/manifest/one-URL consolidation; S-29 consumes the app-only shape and reowns external signed release. Do not duplicate release-identity work. |
| S-26 primary decisions include WIF/base/secrets while special boundary assigns infrastructure to S-27 | 7–8, 12, 16 | S-26 preserves required repository interfaces and forbids permanent keys; S-27 implements live identities, controlled base/registry and bindings. This is an explicit ownership split, not a requirement conflict. |
| BL-001/BL-002 remain open | 15–16 | Keep repository and operational status separate. Do not write “fully closed,” “production verified,” or “resource absent.” |
| Existing test expectations must change with topology | All | Every rewrite cites the reviewed IR/deletion-map wire contract in the PR; production behavior is exercised through a seam. Static string checks are labelled tripwires. |
| New check temptation during broad residue cleanup | 5–11 | Prefer existing route, image, workflow, manifest and check primitives. A new guard requires a real incident/merged PR and CI wiring in the same change. |
| Scope expansion into rebrand, namespaces, release or cloud foundation | All | Stop and hand off to S-27 through S-30. Do not create aliases or temporary infrastructure to bridge the gap. |

Any conflict between current source, the detailed requirements decisions and deletion map is an execution gate. Record it and return to the product/authority owner; do not silently resolve it in code.

## 18. Final completion checklist

### Repository implementation and behavior

- [ ] Execution-time `origin/main` rebase and complete caller/resource inventory are recorded on the implementation SHA.
- [ ] All 17 primary decisions—IR-008, IR-803, IR-804, IR-808, IR-839 through IR-849, IR-890 and IR-891—are mapped to implementation evidence or an explicit S-27/S-29 handoff.
- [ ] `backend/main.py:app` is the sole application/entrypoint and owns one lifecycle.
- [ ] Every retained desktop/product route is behaviorally tested through the assembled app; deleted compatibility routes 404/fail closed.
- [ ] Every Mac call family and preview uses one fail-closed canonical URL authority.
- [ ] Local launch and `make dev-up` own exactly one backend process/port with existing process safety.
- [ ] Offline/local harness retains Firebase Auth/Firestore emulators, Redis, provider fakes/modes, synthetic users, account-deletion fake, lifecycle commands and disabled billing.
- [ ] Redis exports correspond to production-called ephemeral coordination; rejected geolocation/other proven residue is deleted.
- [ ] Firestore registry/manifest contains only production serving queries; fair-use and safe create-only reconciliation remain.
- [ ] Runtime environment has one service in each of dev/prod and only retained settings/secret references, with no values committed.
- [ ] Canonical workflows retain exact-main eligibility, candidate/compatibility/provider checks, promotion, rollback, repair-only and break glass for one service.
- [ ] Desktop release schema is app-only and previews carry one backend URL/environment.
- [ ] Duplicate entrypoint, deprecated router, image, Dockerfile, workflows, ports, env vars, fixtures and false Rust/service terminology are absent.
- [ ] Route policy, OpenAPI, generated macOS Swift, runtime image, runtime env, Firestore index and workflow contracts are fresh and green.
- [ ] Backend and desktop suites, harness tests, Tier 2, `omi-wave5-s26`, residue searches, ledger validator, PR preflight and `make preflight` are recorded with exact outcomes/durations.
- [ ] Setup, component guides, FORK, E2E/qualification docs and examples describe the actual one-backend system; historical changelogs are unchanged.
- [ ] `git diff --check` passes and the implementation PR contains test/user-path evidence plus failure-class declarations required by repository rules.

### Scope and operational separation

- [ ] No compatibility alias, duplicate adapter, no-op service, fake-success response or ignored retired field was added.
- [ ] No product prompt/model/STT/provider/local-authority/update/payment behavior changed outside explicit authorization.
- [ ] `BILLING_MODE=disabled` remains; no Dodo/Stripe resource or call was created.
- [ ] No production Omi/Omi Beta bundle was operated or modified.
- [ ] No project/region/IAM/WIF/network/Artifact Registry/base-image/Secret Manager/Memorystore identity was guessed or reowned by S-26.
- [ ] BL-001 and BL-002 remain explicitly open until their later evidence; repository success is not described as live closure.
- [ ] No live query, deploy, index reconciliation, traffic shift, queue drain, resource deletion, preview publish or release occurred without separate authorization.
- [ ] S-27 receives one-service/two-environment repository inputs; S-29 receives the app-only manifest/one-URL contract; S-31 receives measurements and open operational evidence.
- [ ] No integrated closeout record is appended until implementation actually completes.
