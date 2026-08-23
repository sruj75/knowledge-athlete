# S-25 TDD plan — delete jobs, workers, duplicate services, and GKE control planes

## 1. Slice identity

| Field | Value |
|---|---|
| Wave | **4 — delete rejected cloud products and infrastructure** |
| Slice | **S-25** |
| Name | **Delete jobs, workers, duplicate services, and GKE control planes** |
| Type | Service-topology collapse |
| Primary decisions | **IR-016, IR-120, IR-608, IR-810 through IR-818, IR-836, IR-839, IR-868** |
| Roadmap authority | [`../deletion-map.md`](../deletion-map.md), **S-25** and its shared closure contract |
| Decision authority | [`../requirements-challenge.md`](../requirements-challenge.md), indexed rows and full decision sections |
| Research lead | [`../deletion-slice-research.md`](../deletion-slice-research.md), service/job and deployment topology inventories |
| Named future acceptance bundle | **`omi-wave4-s25`** (`com.omi.omi-wave4-s25`) |
| Planned implementation shape | **21 ordered TDD cycles**, each closing one retained boundary or independently deployed family |

This document is a source-grounded implementation plan. It is not implementation or operational authorization. Creating it changes no product code, tests, generated contracts, deployment configuration, live service, queue, secret, IAM binding, image, monitoring system, or GKE resource.

## 2. Planning status and pinned baseline

**Status:** repository-closed on the integrated Wave 3–4 repair tree. The text below preserves the historical planning baseline; section 19 owns the final implementation and acceptance evidence. Live traffic changes, drains, deployments, and decommissioning remain separately authorized operational work.

The required Wave 2 closeout is both the planning baseline and the exact inspected `HEAD`:

```text
711269baf5e653bd62132688998732207f11dd3c
```

The planning-time ancestry check passed:

```bash
git merge-base --is-ancestor 711269baf5e653bd62132688998732207f11dd3c HEAD
```

Planning-time `git rev-parse HEAD` returned the same full commit. `git status --short --branch` showed branch `audit-wave-2-slices` tracking `origin/audit-wave-2-slices` and no product changes beyond the pinned baseline. The requirements-ledger validator passed during planning:

```text
Requirements ledger validation: PASS (714 indexed rows, 714 detailed sections, all reviewed)
```

No component suite, desktop bundle, backend service, or live user path was run while preparing this plan. All other commands and acceptance evidence below are future implementation requirements unless explicitly labelled as planning-time evidence.

## 3. Outcome

S-25 leaves one deployable Python product backend per environment and removes every rejected duplicate job, worker, service, image, workflow, queue, secret binding, alert, and GKE workload/control-plane reference. The one retained asynchronous destructive workflow remains durable:

```text
DELETE /v1/users/delete-account
  -> persist deletion intent and opaque wipe-job ID
  -> account-deletion Cloud Tasks queue
  -> dedicated least-privilege OIDC signer
  -> POST /v1/users/account-deletion-wipes/run on canonical backend/main.py
  -> transactional claim + run lock + provider cleanup
  -> terminal-attempt state or completion
  -> five-minute reconciler can safely re-dispatch durable failed/stale work
```

The end state has no `backend-sync`, `backend-sync-backfill`, audio-merge worker, conversation-finalization worker, Pusher, separate `backend-listen`, hosted VAD/speech-profile service, standalone diarizer, Notifications job, memory-maintenance job, Persona deployment, `backend-integration`, hosted Plugins deployment, standalone LLM gateway, or Omi self-hosted monitoring/GKE platform.

The surviving Mac product and backend behavior does not change: local Mac product stores remain authoritative; `/v4/listen` remains authenticated transient managed transcription; in-process `VADStreamingGate` remains; the selected STT provider returns generic conversation-scoped speaker labels; retained Python model calls go directly through their owning in-process client; account deletion remains durable and retryable; authenticated `/metrics`, `/v1/health`, privacy-sanitized logs, Sentry, PostHog, and LangSmith remain.

The repository's five-step approach is applied literally:

1. Revalidate all assigned decisions and predecessor outputs at execution time.
2. Delete unnecessary behavior and dependencies one deployable family at a time.
3. Simplify the surviving deployment registries only after each family is absent.
4. Measure edit/test/run latency through focused official runners before changing the feedback loop.
5. Extend existing manifest/contract automation only for stable recurring closure checks; add no orphan check or scheduled job.

## 4. Authorizing requirements

The detailed decision sections below were read in addition to their indexed ledger rows. The live requirements challenge wins over research prose or an older plan. A changed or conflicting decision is an execution stop, not permission to choose silently.

| Decision | S-25 obligation | Planned cycle(s) |
|---|---|---|
| **IR-016** | Delete both `backend-sync` and `backend-sync-backfill`, their service-specific IAM/config/workflow/release/monitoring references, after every workload is gone. Keep only account deletion, retargeted to main. | 4–7, 20 |
| **IR-120** | Keep the durable deletion intent, opaque job, queue, OIDC handler, lock, retries, terminal-attempt state, reconciliation, timeout, billing cancellation, and privacy-bounded telemetry; target the existing handler on canonical main. Never run the wipe inline. | 1–3 |
| **IR-608** | Consume S-22's explicit direct route for every surviving Python model workload; delete gateway service, extra hop, auth, auto-lanes, route artifacts, shadow/promotion, GKE/VPC/ingress, probes, and exclusive tests. Preserve typed Chat, managed providers, quota/usage, workload timeout/retry/fallback, and native realtime provider switching. | 1, 12 |
| **IR-810** | Delete the Pusher service and binary side-effect protocol because every consumer is rejected. Preserve direct `/v4/listen` STT and Mac reconnect/watchdog behavior. | 1, 8 |
| **IR-811** | Serve `/v4/listen` from the canonical backend and delete only the separate `backend-listen` GKE deployment/control plane. | 1, 9 |
| **IR-812** | Delete hosted completed-recording VAD/speech-profile service and callers; keep in-process Silero `VADStreamingGate`, `VAD_GATE_MODE`, pre-roll/hangover/timestamp mapping, keepalives, metrics, fail-open policy, and fair-use speech accounting. Do not change the Mac Local VAD Gate card. | 1, 10 |
| **IR-813** | Delete standalone GPU diarizer/vector endpoints and fallback. Require the S-22-selected cloud STT route to return stable generic labels within one connection; preserve local manual names and reject persistent voice identity. | 1, 11 |
| **IR-814** | Accept S-14's deletion of the Notifications Cloud Run job and remove only any reintroduced job/image/workflow/scheduler/secret residue. Preserve local reminders, proactive overlay, retained account/billing notices, Sentry, PostHog, and proven generic notification helpers. | 13 |
| **IR-815** | Accept S-12's deletion of the cloud memory-maintenance job and remove only reintroduced job/image/workflow/scheduler/secret residue. Preserve local memory CRUD/search/vector/lifecycle, local AI Profile, and transient compute. | 14 |
| **IR-816** | After S-23 deletes the public Persona/clone product, delete independently deployed website/service/image/workflow/config/monitoring residue only. Preserve private local AI Profile and the unrelated public product/legal website. | 15 |
| **IR-817** | After S-23 deletes the external App API, delete the duplicate `backend-integration` Cloud Run service and its independent release surface. Preserve canonical auth, Dodo webhooks, model/STT/TTS routes, and local managed Pi. | 16 |
| **IR-818** | Delete zombie hosted Plugins workflow/service residue; do not recreate missing `plugins/` source. Preserve managed Pi, local Node tools, typed Swift tools, and `ProactiveAssistantsPlugin`. | 17 |
| **IR-836** | Delete Prometheus/Grafana/Loki/Alloy/Alertmanager, exporters/adapters, storage/config/workflows/dashboards/alerts exclusive to Omi's GKE stack. Preserve authenticated lightweight metrics and retained observability authorities. | 18–19 |
| **IR-839** | Keep one canonical `backend/main.py` Cloud Run service per environment. S-25 deletes duplicates; it does not perform S-26's source-entrypoint consolidation or S-27's region/project reownership. | 1, 6–20 |
| **IR-868** | Keep one dedicated account-deletion OIDC caller per environment with exact signer-email/audience/HTTPS verification and fail-closed configuration. Remove stale `SYNC_TASKS_*` ownership, finalization identity, and reuse of runtime/deploy identities. | 2–5 |

Related child decisions are part of the closure proof even though they are not the primary index: IR-020/394/397 authorize conversation-finalization deletion; IR-121 authorizes cloud recording/audio-merge deletion; IR-837 retains `/metrics`; IR-838 retains `/v1/health`; IR-868/877/878 define the signer, queue shape, and reconciler; IR-879/880 retain sanitized Cloud Logging and only minimal managed production alerts. Billing remains `BILLING_MODE=disabled` and S-18's post-Wave-6 Dodo gate remains untouched.

## 5. Dependencies and entry gates

### G0 — mandatory setup, rebase, and current-tree inventory

Before the first RED, run the repository's required setup, fetch the target branch, and integrate the current `origin/main` without renaming or switching the current branch mid-task. Record `HEAD`, `origin/main`, the merge base, status, and commits beyond the pinned baseline. Rerun the requirements validator and all inventories in §§6–7 and §13. Run focused characterization before modifying code so inherited failures are not attributed to S-25.

Stop if `711269ba` is no longer an ancestor, the assigned decisions changed, a newer owner document contradicts this plan, or unrelated local changes overlap the target files. Do not patch around an unintegrated owner with a compatibility route or duplicate deployment.

### G1 — mandatory S-22, S-23, and S-24 integration

The pinned baseline contains no integrated S-22, S-23, or S-24 implementation. Coexisting planning artifacts do not satisfy this gate. S-25 executes only after all three implementation results are integrated:

- **S-22** must choose and behavior-test one explicit direct managed-provider route for every retained Python model caller and preserve both realtime voice providers. S-25 consumes that caller map; it does not choose models or reproduce gateway migration.
- **S-23** must delete rejected hosted products, public routes, schemas, storage ownership, and generated contracts family by family. S-25 consumes the absence of Persona, Apps/integrations/webhooks, server conversation finalization ownership, and voice identity; it deletes only independently deployed residue.
- **S-24** must remove Typesense, Pinecone, OpenAI Files/cloud attachments, and product-data GCS while preserving the update/preview bucket. S-25 consumes the absence of product-data storage callers before removing audio-merge, Pusher, related secrets/IAM, and cleanup branches.

Every implementation cycle except Cycle 0 is blocked until G1 passes. After integration, refresh every path/symbol/resource inventory: do not assume the Wave 2 file list survives unchanged.

### G2 — account-deletion composition and target are first

Before deleting a worker or `backend-sync`, prove that the post-S-23/S-24 account-deletion composition enumerates only retained account/billing/auth/server metadata and that its hidden OIDC route remains registered on `backend/main.py`. Retarget the durable queue to the canonical backend and give it dedicated truthful configuration first. The initial request must still return success only after intent persistence and durable enqueue.

Stop if a deleted product store/provider is still in the wipe composition, if the main route is not present, if the queue cannot be bounded at concurrency 1 / attempts 5 / deadline 1,500 seconds, or if signer and audience cannot be specified independently from runtime and deploy identities.

### G3 — legacy queue and traffic evidence

Repository evidence shows a legacy `AccountDeletionTaskAuthentication.legacy_sync` branch and stale `SYNC_TASKS_*` names. Removing that compatibility requires a later read-only development and production inventory proving:

- no task targets `backend-sync` or uses the old audience/signer;
- no queued or retrying legacy UID payload remains;
- the documented drain window has elapsed;
- the canonical queue has accepted and completed the opaque-job payload contract;
- rollback evidence no longer depends on the old target.

Safe work without this evidence: add/retain the dedicated canonical path and test both identity contracts. Blocked work: deletion of the legacy audience/payload branch, old signer binding, and final `backend-sync` operational decommission. Do not guess that an empty repository means an empty queue.

### G4 — repository work is not live-resource authorization

Repository manifests and code can be changed after the preceding gates. No execution step in this plan authorizes deployment, traffic mutation, queue purge/deletion, service deletion, IAM/secret mutation, image deletion, scheduler deletion, or GKE mutation. §16 defines the separate read-only inventory and explicitly authorized operational closeout.

## 6. Current production codeflow

This is the exact pre-migration Wave 2 baseline. It must be refreshed after G1.

### 6.1 Canonical backend and duplicate `backend-sync`

`backend/main.py` builds the broad FastAPI application and registers `backend/routers/transcribe.py`, `backend/routers/users.py`, `backend/routers/sync.py`, `backend/routers/conversation_finalization.py`, metrics, and other product routers. The same backend image is deployed as both `backend` and `backend-sync` by `.github/workflows/gcp_backend.yml` and `.github/workflows/gcp_backend_auto_dev.yml` using `backend/deploy/runtime_env.yaml`.

```text
Mac Settings
  -> DELETE /v1/users/delete-account on backend
  -> services/users/account_deletion.py persists intent/job
  -> utils/cloud_tasks.py enqueues account-deletion using mixed ACCOUNT_DELETION_* and SYNC_TASKS_* config
  -> Cloud Task OIDC calls POST /v1/users/account-deletion-wipes/run on backend-sync
  -> transactional claim/run lock/provider cleanup/terminal state
  -> main startup reconciler re-dispatches pending, failed, or stale work
```

`backend-sync` also hosts two rejected hidden workers:

```text
/v2/audio-merge-jobs/run
  -> backend/utils/sync/playback.py
  -> cloud recording chunks / derived playback artifacts

/v1/conversation-finalization-jobs/run
  -> database/conversation_finalization_jobs.py
  -> services/conversation_finalization.py
  -> cloud conversation persistence/finalization
```

The repository already contains neither the old `/v2/sync-jobs/run` wearable/offline-sync worker nor an active `backend-sync-backfill` source/deploy manifest on this baseline. Their absence is inherited from the wearable/offline-sync deletion and must be revalidated rather than reimplemented.

### 6.2 Continuous listening and Pusher

The canonical app already mounts authenticated WebSocket `/v4/listen` from `backend/routers/transcribe.py`. The current listen session streams audio to managed STT and also opens a second Pusher socket through `backend/utils/listen_pusher_session.py`. `backend/utils/pusher_protocol.py` duplicates audio, transcript batches, conversation identity, and lifecycle frames. The separate Pusher app (`backend/pusher/main.py`, `backend/routers/pusher.py`) performs rejected webhook/App dispatch, cloud audio buffering/upload, voice-sample work, and conversation-finalization side effects.

The same backend image is separately deployed into GKE as `backend-listen` through `backend/charts/backend-listen/**`, `.github/workflows/gcp_backend_listen_helm.yml`, and the normal backend deploy workflows. That chart adds Deployment, Service/NEG/ingress, HPA, PDB/drain, service account, and scheduled scale controls, but not a distinct transcription implementation.

### 6.3 VAD and speaker labels

The retained live gate is `backend/utils/stt/vad_gate.py::VADStreamingGate`, using in-process Silero ONNX. Separately, `backend/modal/main.py`, `vad_modal.py`, and `speech_profile_modal.py` expose completed-recording VAD and speech-profile work behind `HOSTED_VAD_API_URL` / `HOSTED_SPEECH_PROFILE_API_URL`; `.github/workflows/gcp_models.yml` deploys the `backend/modal/Dockerfile` image through `backend/charts/vad/**`.

`backend/diarizer/main.py` separately exposes `/v1/diarization`, `/v1/embedding`, and `/v2/embedding` using the standalone Pyannote/WeSpeaker image and `backend/charts/diarizer/**`; `backend/utils/stt/speaker_embedding.py` is a caller. This is persistent/cross-recording identity infrastructure. The retained contract is only stable generic speaker labels inside the current STT connection plus optional local manual names.

### 6.4 Model gateway

Retained normal Chat and Python workloads currently can cross `backend/llm_gateway/**` through `backend/utils/llm/gateway_*`, service-token authentication, generated auto-lanes, route artifacts, provider adapters, shadow/promotion flags, and gateway-specific telemetry. The service has its own chart, internal ingress/static address, VPC probes, workflow (`gcp_llm_gateway.yml`), and steps in the automatic backend deployment. S-22 must first replace every retained caller with an explicit in-process route.

### 6.5 Already-absent deployment families

At the inspected baseline, production source/deploy inventories already show no active Notifications job entry/image/workflow, memory-maintenance job entry/image/workflow, `backend-integration` service workflow, Persona website/service workflow, `gcp_plugins.yml`, `plugins/` source, or `backend/charts/monitoring/**`. S-14 carries a negative behavioral/static retirement test for the Notifications job. Earlier slice plans and `FORK.md` document the inherited handoffs. These are not permission to invent no-op replacement cycles: after G1, S-25 accepts a family as a verified no-op when its complete repository inventory remains absent.

### 6.6 Shared deployment registries

`backend/deploy/runtime_env.yaml`, `backend/runtime_images.json`, `backend/testing/workflow_contracts.json`, `.github/checks-manifest.yaml`, `.github/scripts/check-deployment-concurrency.py`, change-detection/pre-push scripts, backend deploy/repair/status/release-vector scripts, charts, route policy, OpenAPI, generated Swift, service maps, and runbooks cross-cut multiple families. They must be narrowed as each owner disappears, never deleted wholesale while a retained target still consumes them.

## 7. Complete caller and dependency inventory

The action column describes the planning-baseline disposition. Every row is re-earned after G1.

| Family / boundary | Current concrete owners and callers | Deployable assets / config | Shared or retained dependency | S-25 action |
|---|---|---|---|---|
| Canonical backend | `backend/main.py`; retained routers/services | Backend Dockerfile; `backend` Cloud Run lanes in `gcp_backend*.yml`; runtime env | Firebase auth, Dodo-disabled billing projection, managed providers, Redis/Firestore/GCS only where retained, health/metrics | **KEEP**; narrow only rejected registrations/config |
| Account deletion | `routers/users.py`; `services/users/account_deletion.py`; `database/account_deletion_projection_fence.py`; `utils/cloud_tasks.py`; startup reconciler; unit/E2E tests | `account-deletion` Cloud Tasks queue; handler URL/audience; signer; long route timeout | Durable Firestore state, auth/billing cleanup, retries/lock/reconciliation | **ADAPT first** to main and truthful dedicated identity |
| Legacy account-deletion acceptance | `AccountDeletionTaskAuthentication.legacy_sync`; legacy UID payload/TODO `#9760`; shared `SYNC_TASKS_*` | Old audience/signer/target may exist live | Only retained until verified drain | **DELETE after evidence**, never by assumption |
| Audio merge / playback | `routers/sync.py`; `utils/sync/playback.py`; `utils/cloud_tasks.py`; audio-merge tests | `audio-merge` queue/handler/env and backend-sync target; product-data GCS artifacts | Live capture, local transcripts, PTT/TTS, and Rewind do not use it | **DELETE** after S-24 |
| Conversation finalization | `routers/conversation_finalization.py`; `services/conversation_finalization.py`; `database/conversation_finalization_jobs.py`; `utils/conversations/finalizer.py`; `utils/pusher_finalization.py`; startup loops | `conversation-finalization` queue, signer/audience/env, worker route and timeouts | Transient listen and local conversation commit must remain | **DELETE** after S-23/Pusher caller proof |
| `backend-sync` | Same `backend/main.py` image; deploy/status/repair/release scripts assume two Cloud Run services | Cloud Run service, revisions/traffic/IAM/env/URL, workflow branches, probes/alerts/docs | None after account retarget + audio/finalization removal | **DELETE** as its own family |
| Wearable sync / `backend-sync-backfill` | `/v2/sync-jobs/run` and active backfill source/deploy owner are absent; historical wearable lane only | Possible live backfill Cloud Run/image/IAM/alerts unknown | Mac capture, ordinary Bluetooth audio and SQLite WAL are unrelated retained paths | **VERIFY ABSENCE** in repo; later inventory/decommission separately |
| Pusher | `pusher/main.py`; `routers/pusher.py`; `listen_pusher_session.py`; `pusher_protocol.py`; `pusher.py`; `pusher_finalization.py` | Pusher Dockerfile/deps; chart; manual/auto workflows; `HOSTED_PUSHER_API_URL`; rollout scripts/checks/secrets/metrics | Direct `/v4/listen`, provider STT, Mac watchdog/reconnect | **DELETE vertically** |
| `backend-listen` | Same `backend/main.py`; no unique route implementation | Chart Deployment/Service/NEG/ingress/HPA/PDB/SA/scale controls; manual and main deploy workflow branches | `/v4/listen` stays on canonical Cloud Run | **DELETE control plane only** |
| Hosted VAD / speech profile | `modal/main.py`; `vad_modal.py`; `speech_profile_modal.py`; completed-recording callers | Modal/models Dockerfile/deps; `vad` chart; `gcp_models.yml`; hosted URL/secret/metrics | `VADStreamingGate`, Silero model, live accounting/keepalive | **DELETE hosted family** |
| Standalone diarizer | `diarizer/main.py`, `diarization.py`, `embedding.py`; `stt/speaker_embedding.py` | Diarizer Dockerfile/deps; chart; `gcp_diarizer.yml`; hosted URL/GPU/metrics | Generic provider labels and local manual naming | **DELETE deployed family** |
| LLM gateway | `llm_gateway/**`; `utils/llm/gateway_*`; gateway mode/auto-lane call sites; replay harness | Gateway chart, image/entrypoint, workflow, shared token, internal ingress/static IP, VPC, route artifacts, probes/metrics | S-22 direct provider clients; quota/usage; native realtime OpenAI/Gemini | **DELETE after S-22** |
| Notifications job | No active current source/image/workflow; `test_s14_notifications_job_retirement.py` protects absence | Live scheduler/job/image/secrets unknown | Local reminders/proactive/account paths | **ACCEPT NO-OP or delete reintroduced residue** |
| Memory-maintenance job | No active current source/image/workflow found | Live scheduler/job/image/secrets unknown | Local GRDB/FTS/vector/lifecycle and transient compute | **ACCEPT NO-OP or delete reintroduced residue** |
| Persona deployment | No current public web deploy asset found; S-23 owns any surviving product routes/schemas | Live Cloud Run/site/image/domain/secrets unknown | Private local AI Profile; public product/legal website | **DELETE deployment residue only after S-23** |
| `backend-integration` | No current standalone workflow found; S-23/S-06 own external API removal | Possible duplicate Cloud Run/release/IAM/alerts unknown | Canonical auth, Dodo webhook, models/STT/TTS, Pi | **DELETE deployment residue only** |
| Hosted Plugins | `plugins/` and `gcp_plugins.yml` currently absent | Possible live service/image/IAM/alerts unknown | Managed Pi/local Node/Swift proactive plugin | **VERIFY ABSENCE / delete residue**, no replacement |
| Self-hosted monitoring | No current `backend/charts/monitoring/**`; service-specific monitoring references remain | Possible Prometheus/Grafana/Loki/Alloy/Alertmanager releases, storage, secrets, domains unknown | `/metrics`, `/v1/health`, Cloud Logging, Sentry/PostHog/LangSmith, minimal managed alerts | **DELETE platform and extinct-service references** |
| Shared GKE secrets/cluster | `backend/charts/backend-secrets/**`; shared workflow/deploy locking and GKE probes | GKE namespace/cluster/node pools, Workload Identity, ingress/static IPs, shared secrets chart | None after all S-25 GKE workloads; Secret Manager values used by Cloud Run may remain | **DELETE only proven GKE-exclusive layer** |
| `desktop-backend` | Separate desktop backend source/image/workflows | `desktop_backend.py`, image and dev workflows | S-26 owns consolidation after S-25 | **OUT OF SCOPE** |
| Owned cloud foundation | Current projects/regions/domains still carry Omi identifiers | Cloud Run, Cloud Tasks, IAM, Artifact Registry, Redis/Firestore/GCS | S-27 owns project/region/URL/release reownership | **OUT OF SCOPE except deleting extinct target references** |

Account deletion and export enumeration must be rerun after S-23/S-24: no rejected product-data reader may remain merely because it was reachable only from a destructive path. Conversely, do not delete a retained billing/auth/account metadata cleanup or exported account field just because a service family is disappearing.

## 8. Behavior classification

| Category | Concrete S-25 behavior |
|---|---|
| **KEEP AS IS** | Local Mac authority for conversations, Memories, Tasks/Goals, Chat history, Focus, Rewind, search, notifications, updates, and exports; Firebase-authenticated account/session boundary; durable account-deletion job/queue/lock/retry/reconciler and provider cleanup; `/v4/listen` authentication, direct managed STT, transcript protocol, fair-use/quota accounting, translation, watchdog/reconnect; in-process `VADStreamingGate`; generic within-connection speaker labels and local manual names; selected direct model calls, normal Chat and tools, both native realtime voice providers; `/v1/health`; authenticated `/metrics`; sanitized logs, Sentry, PostHog, LangSmith; `BILLING_MODE=disabled`. |
| **ADAPT** | Account-deletion handler target from `backend-sync` to canonical `backend`; split `ACCOUNT_DELETION_*` project/location/queue/handler/audience/signer configuration from `SYNC_TASKS_*`; deployment/release/status scripts from multi-service to canonical-service topology; `/v4/listen` public routing to canonical Cloud Run; retained model callers consume S-22 direct clients; provider speaker output normalized to existing generic transcript contract; shared registries narrowed as owners disappear. |
| **DELETE** | Audio-merge and conversation-finalization routes/workers/queues/reconcilers/config; `backend-sync` and backfill; Pusher; `backend-listen`; hosted VAD/speech profile; diarizer; LLM gateway; Notifications and memory-maintenance jobs; Persona, backend-integration and hosted Plugins deployment residue; self-hosted monitoring; exclusive images/workflows/charts/services/IAM/secrets/metrics/alerts/docs/tests; old task audience/payload only after drain proof. |
| **SIMPLIFY AFTER** | After all family GREENs: one backend service list and release vector, one task identity vocabulary, one retained runtime-image set, one deployment concurrency model, one service map, and removal of empty generic helpers/check clauses whose final caller disappeared. Do not refactor retained application behavior for style. |
| **ACCELERATE AFTER** | Measure family-specific deployment-contract tests, runtime-image checks, and local canonical-backend startup after GREEN. Improve only a demonstrated repeated bottleneck; otherwise `none`. |
| **AUTOMATE LAST** | After the one-time topology collapse is manually proven, register only stable recurring service-map/runtime-image/task-target validation in existing local and CI lanes with a cited real failure; otherwise `none`. |
| **OUT OF SCOPE / DEFERRED** | S-22 provider/model selection and caller migration; S-23 product/route/schema deletion; S-24 data-store deletion and update/preview-bucket protection; S-26 `backend/main.py` / `desktop_backend.py` source consolidation; S-27 project, `us-west1`, domain, Artifact Registry, retained Cloud Run/Redis/Firestore/GCS ownership; S-18 post-Wave-6 Dodo activation; production capacity redesign; live cloud mutation; new local recording playback; Mac Local VAD preference redesign. |

## 9. Retained behavioral invariants

1. **One local product authority.** Deleting cloud infrastructure never moves Mac-owned product records into the surviving backend. Backend work is bounded transient compute unless account/billing/usage/deletion metadata is explicitly retained.
2. **Account deletion is durable.** The initiating request persists an opaque job before enqueue success; the handler is OIDC-only; transaction fencing, run locks, attempt interpretation, long timeout, terminal failure, five-minute reconciliation, and safe redelivery survive. There is no inline wipe or fake-success fallback.
3. **Identity is least privilege and exact.** One dedicated signer per environment has exact email and canonical handler audience. It is not the Cloud Run runtime or GitHub deploy identity. Wrong signer, audience, scheme, payload, or missing configuration fails closed.
4. **Continuous listening survives without Pusher/GKE.** Firebase upgrade auth, audio receipt, direct managed STT, transcript messages, generic speaker labels, translations, fair-use/usage, keepalives, provider timeout/failure behavior, and Mac watchdog/reconnect remain. No server conversation, raw-audio upload, voice profile, webhook, or finalizer is reintroduced.
5. **VAD meanings remain separate.** Python in-process live Silero gating survives; hosted completed-recording VAD/speech matching is deleted; the Mac Local VAD Gate card stays behaviorally unchanged.
6. **Speaker identity stays generic.** The retained provider supplies stable conversation-scoped labels. No cross-recording embedding, speech profile, persistent voice sample, or automatic named-person authority remains. Local manual naming is unchanged.
7. **Model semantics stay with S-22 owners.** S-25 deletes only the gateway hop after caller parity. It does not change selected models, prompts, result validation, quota, usage, workload retries/fallback, tool execution, or the OpenAI Realtime/Gemini Live switch.
8. **Removed routes truly disappear.** Deleted HTTP routes return genuine route-not-found; deleted WebSocket upgrade paths fail closed. Do not add 410 shells, deprecated aliases, empty services, ignored payloads, or no-op queues.
9. **Shared primitives require a live caller.** Retain Secret Manager, Cloud Tasks, Firebase, Redis, Firestore, GCS update/preview publication, generic notification helpers, metrics, or deploy utilities only where an enumerated surviving owner consumes them. Delete family-exclusive branches with their owner.
10. **Observability remains privacy bounded.** No raw transcript, audio, prompt, token, secret, or PII is added to logs/metrics. Retain Sentry/PostHog/LangSmith and sanitized platform logs; delete only rejected-service labels, dashboards, sinks, and counters.
11. **Failure is visible.** Provider suspension, timeout, deployment restart, enqueue failure, persistence failure, auth loss, owner switch, and late result cannot create phantom local data, silently acknowledge deletion, or switch to a rejected service.
12. **Billing stays disabled.** No Dodo/Stripe transaction, entitlement grant, checkout, paywall, or provider side effect is added by topology collapse.

## 10. Target authority, result ownership, and service-topology model

```text
Mac local authorities
  GRDB / SQLite / FTS / local vectors / files / owner-scoped preferences
  conversations, Memories, Tasks/Goals, Chat history, Focus, Rewind, notifications
       |
       | authenticated bounded request; authorization snapshot survives async work
       v
one canonical backend/main.py Cloud Run service per environment
  /v1/health                       process reachability
  /metrics                         authenticated bounded technical counters
  /v4/listen                       transient managed STT + in-process VAD
  retained model/account/billing   direct owning-provider adapters
  DELETE /v1/users/delete-account  persist intent and enqueue opaque job
  POST /v1/users/account-deletion-wipes/run  OIDC-only durable worker
       ^
       |
account-deletion queue (concurrency 1, attempts 5, deadline 1,500 seconds)
  dedicated environment signer + exact canonical audience

retained managed dependencies only
  Firebase/Auth, retained Firestore/Redis/account metadata,
  retained provider APIs, Secret Manager, Cloud Logging,
  update/preview publication storage, Sentry/PostHog/LangSmith
```

The Mac validates transient compute results and commits them through the owning local store. The backend owns only retained account, subscription/usage/quota, deletion-job, and operational state. Account deletion's Firestore job record—not Cloud Tasks and not a Cloud Run instance—is the durable workflow authority. The task is an authenticated delivery mechanism; the handler's transaction claim/run lock determines execution ownership.

There is no surviving GKE data/control plane in S-25's target. The canonical Cloud Run source split remains temporarily `backend/main.py` plus the S-26-owned `desktop_backend.py` boundary; S-25 must not preempt S-26 by merging entrypoints.

## 11. Ordered TDD cycles

All tests described as “new” are future implementation work. Behavioral tests execute production seams with faked providers/queues or the assembled app; residue searches are explicitly static tripwires. Each independently deployed family has a separate cycle and commit candidate. A no-op acceptance cycle makes no production edit when the post-rebase family is already absent.

### Cycle 0 — execution gate and authoritative topology characterization

- **Intended RED:** A new/extended topology contract enumerates every retained caller and deployable target and rejects any unclassified job, worker, service, image, workflow, queue, signer, secret binding, alert, or GKE owner. Characterization tests exercise canonical health, metrics auth, `/v4/listen` setup, direct model seams, and durable account-deletion enqueue before deletion begins.
- **Why RED now:** the baseline still advertises multiple Cloud Run/GKE services, gateway/Pusher/model charts, three background worker routes, shared sync/finalization task config, and broad deployment registries; S-22/S-23/S-24 are not integrated.
- **Minimum GREEN:** rebase, rerun ledger/current inventories, classify each discovered target as retained, S-25-owned, predecessor-owned, successor-owned, already absent, or unknown-live-only; record baseline failures and freeze retained behavior through controllable seams. No product deletion in this cycle.
- **Protected behavior:** all invariants in §9 and predecessor ownership.
- **Owner before → after:** distributed roadmap/research assumptions → current-source caller ledger owned by S-25 for topology only.
- **Expected surfaces:** new/extended backend topology/contract tests and implementation notes; no production/config change.
- **Focused verification:** requirements validator; account-deletion, listen/VAD, direct model, health/metrics, runtime-env, runtime-image, workflow-contract characterization selected through `backend/test.sh`; desktop core T0 self-check.
- **Deletion/simplification enabled:** establishes safe order and exact family stop conditions.
- **Stop:** any changed decision, missing predecessor, unclassified retained caller, conflicting local change, or materially different target topology.

### Cycle 1 — protect the one-backend retained path before deletion

- **Intended RED:** Through the assembled `backend/main.py` app and fake external seams, require `/v1/health`, authenticated `/metrics`, authenticated `/v4/listen`, in-process VAD, generic speaker transcript events, retained direct model behavior, and both account-deletion routes to work without `backend-sync`, Pusher, gateway, hosted VAD, or diarizer availability.
- **Why RED now:** listen still creates a Pusher side channel; production model mode can require the gateway; account-deletion target config still resolves the duplicate service; provider-label and canonical-listener deployment contracts have not yet been asserted together.
- **Minimum GREEN:** add only the behavioral characterization/fault seams needed to prove the post-S-22/S-23/S-24 retained path; consume predecessor implementations without duplicating them.
- **Protected behavior:** auth, transcript protocol, VAD timing/fail-open, usage/fair use, model semantics/fallback, metrics secrecy, health, deletion durability.
- **Owner before → after:** multiple service-specific operational assumptions → canonical backend is the explicit retained host; local stores and workflow-specific owners remain unchanged.
- **Expected surfaces:** assembled-app and provider-fake tests; listen/model/account service contracts; no deployment deletion yet.
- **Focused verification:** `test_vad_gate.py`, `test_vad_onnx.py`, retained listen/transcription tests, S-22 direct-caller tests, account-deletion unit/E2E, health/metrics route tests.
- **Deletion/simplification enabled:** all later family deletions have a behavioral safety net.
- **Stop:** a retained path still genuinely requires any service scheduled for deletion.

### Cycle 2 — retarget durable account deletion to canonical main with truthful identity

- **Intended RED:** Fake Cloud Tasks captures an opaque job payload whose HTTPS URL and OIDC audience are the canonical backend handler and whose signer is the dedicated account-deletion identity; wrong signer/audience/config fails closed; enqueue failure leaves durable retryable state; duplicate delivery executes once.
- **Why RED now:** `utils/cloud_tasks.py`, runtime env, and workflows mix `ACCOUNT_DELETION_*` with `SYNC_TASKS_PROJECT`, `SYNC_TASKS_LOCATION`, `SYNC_TASKS_INVOKER_SA`, and old sync handler ownership; deploy workflows resolve the target from `backend-sync`.
- **Minimum GREEN:** introduce complete truthful account-deletion project/location/queue/handler/audience/signer configuration, point to main, keep concurrency/attempt/deadline contract, update validation/render/deploy/probe code, and preserve OIDC route/timeouts/reconciler. No live queue mutation in repository work.
- **Protected behavior:** persisted intent before success, opaque IDs, exact auth, run lock, billing cancellation, retries, terminal state, reconciliation, privacy telemetry.
- **Owner before → after:** `backend-sync` URL plus shared sync signer → canonical main route plus dedicated account-deletion signer; Firestore deletion job remains durable owner.
- **Expected surfaces:** `utils/cloud_tasks.py`, user route/service/startup if naming leaks, `deploy/runtime_env.yaml`, backend workflows and render/validation scripts, account-deletion/runtime-env/workflow tests, service docs and `backend/AGENTS.md`.
- **Focused verification:** `testing/e2e/test_account_deletion_cloud_tasks.py`, `tests/services/users/test_account_deletion.py`, relevant Cloud Tasks/router/runtime-env/workflow tests through the official runner; no-network task client fake.
- **Deletion/simplification enabled:** account deletion ceases to justify `backend-sync`; stale sync identity can later drain and disappear.
- **Stop:** S-23/S-24 deletion composition is not clean, canonical stable URL is unknown, dedicated signer cannot be distinct, or queue shape cannot be validated.

### Cycle 3 — retire the legacy sync audience and UID payload after drain proof

- **Intended RED:** Handler behavior accepts only the opaque deletion-job payload and exact new signer/audience; old sync audience, legacy UID body, and mixed-name configuration are rejected. Reconciler creates only the new task shape.
- **Why RED now:** `AccountDeletionTaskAuthentication.legacy_sync`, TODO `#9760`, and compatibility tests intentionally accept old deliveries because a post-deploy drain was not proven.
- **Minimum GREEN:** only after G3 evidence, delete legacy payload/auth branches, old config fields, old signer/audience wiring and exclusive tests/docs; keep the canonical path unchanged.
- **Protected behavior:** already-persisted canonical jobs, safe duplicate/retry handling, terminal state, and no user-ID exposure in new task payloads.
- **Owner before → after:** temporary dual audience/payload acceptance → one exact account-deletion contract.
- **Expected surfaces:** users route task-auth model, `utils/cloud_tasks.py`, account-deletion tests/E2E, runtime env and deployment validation, docs.
- **Focused verification:** new wrong/old audience and legacy-payload rejection cases plus canonical completion/redelivery/reconciliation cases.
- **Deletion/simplification enabled:** removal of `SYNC_TASKS_*`, old IAM binding, and final operational dependency on legacy target.
- **Stop:** no verified live inventory/drain evidence, any queued legacy task, or rollback still targets old service. Keep bounded compatibility rather than guessing.

### Cycle 4 — delete the audio-merge worker and queue contract

- **Intended RED:** The assembled canonical app returns genuine 404 for `POST /v2/audio-merge-jobs/run`; task dispatch cannot enqueue `audio-merge`; retained live capture, local transcripts, PTT/TTS audio, and Rewind behavior still pass through their real owners.
- **Why RED now:** `routers/sync.py`, `utils/sync/playback.py`, Cloud Tasks helpers, tests, route registration, timeouts/config, and stored-artifact assumptions remain.
- **Minimum GREEN:** after S-24 removes product-audio storage/callers, delete the handler, enqueue path, playback merge/transcode helpers, queue config/validation/metrics/docs, exclusive tests, and account-deletion/export cleanup mentions for already-rejected artifacts.
- **Protected behavior:** transient microphone/system capture, local conversation transcripts, realtime response audio/TTS, Rewind, update/preview bucket.
- **Owner before → after:** backend-sync worker plus product-data GCS artifacts → no owner; retained audio behaviors stay with their existing local/realtime owners.
- **Expected surfaces:** `routers/sync.py`, `utils/sync/playback.py`, `utils/cloud_tasks.py`, `main.py`, tests, runtime env/workflows/scripts, route-policy/OpenAPI/generated client only if post-S-24 still exposes a contract, `FORK.md`/backend guide.
- **Focused verification:** `test_audio_merge_tasks.py`, `test_sync_playback_service.py` rewritten to route absence/retained-neighbor behavior; assembled-app 404; S-24 storage and account-deletion/export enumeration tests.
- **Deletion/simplification enabled:** delete `audio-merge` queue references and one `backend-sync` workload.
- **Stop:** any retained non-generated caller, stored artifact requiring authorized retention/drain, or S-24 is incomplete.

### Cycle 5 — delete conversation-finalization worker, queue, and reconcilers

- **Intended RED:** The assembled app returns genuine 404 for `POST /v1/conversation-finalization-jobs/run`; a completed/disconnected listen session has no finalization enqueue or cloud conversation mutation, while the Mac still receives and locally commits transcript results.
- **Why RED now:** the router, job database, service, finalizer helpers, Pusher finalization bridge, startup recovery loops, queue config/timeouts/identity, and tests remain registered.
- **Minimum GREEN:** after S-23 removes server conversation ownership and Cycle 8 removes the final caller, delete route/service/database/helper/reconcilers, queue dispatch/auth/env/workflow/metrics/docs, and exclusive tests. Remove only finalization clauses from shared lifecycle utilities.
- **Protected behavior:** transient `/v4/listen`, local commit, disconnect/reconnect, late-result owner fencing, account-deletion reconciler, and generic provider labels.
- **Owner before → after:** durable Firestore finalization job + backend-sync worker → no server finalization owner; local conversation store remains authoritative.
- **Expected surfaces:** `routers/conversation_finalization.py`, `services/conversation_finalization.py`, `database/conversation_finalization_jobs.py`, conversation finalizer/lifecycle/Pusher helpers, `main.py`, Cloud Tasks/runtime env/workflows, tests/docs.
- **Focused verification:** finalization tests rewritten to assert absence and local/listen retained path; account-deletion reconciler regression; assembled-app 404; no enqueue under disconnect/failure.
- **Deletion/simplification enabled:** deletes `conversation-finalization` queue/signer/audience and the last non-account worker on `backend-sync`.
- **Stop:** S-23 has not removed cloud conversation ownership, a retained caller exists, or local commit behavior is not proven under disconnect/restart/late result.

### Cycle 6 — delete the `backend-sync` Cloud Run deployment

- **Intended RED:** Runtime-env/deployment/release-vector contracts require exactly one canonical backend service and reject `backend-sync` revisions, traffic, URL, IAM, probes, repair/status entries, or workflow branches; retained account deletion still reaches main under fake and authorized-development acceptance.
- **Why RED now:** both backend deployment workflows and multiple shared scripts render/deploy/smoke/promote/repair `backend-sync`; service-specific env and documentation remain.
- **Minimum GREEN:** after Cycles 2, 4, and 5, delete `backend-sync` entries and branches from runtime env, workflows, deploy/status/repair/traffic/release scripts, service-specific IAM/URL/metrics/docs/tests. Keep shared backend image and canonical lanes.
- **Protected behavior:** canonical candidate/traffic/rollback integrity, immutable image identity, account deletion, backend health, retained routes, deployment locking.
- **Owner before → after:** two Cloud Run deployments of `main.py` → one canonical Cloud Run deployment per environment.
- **Expected surfaces:** `deploy/runtime_env.yaml`, `gcp_backend.yml`, `gcp_backend_auto_dev.yml`, backend deploy/traffic/status/release scripts, workflow/runtime tests, service map/docs.
- **Focused verification:** runtime env render/validator tests, workflow contracts, deployment concurrency/admission tests, runtime-image source closure, candidate/release-vector unit tests, account-deletion target tests.
- **Deletion/simplification enabled:** repository closure for the ordinary duplicate service; live service/IAM/image cleanup remains §16.
- **Stop:** any route/queue still targets `backend-sync`, candidate/rollback proof would become ambiguous, or canonical backend has not passed retained-path acceptance.

### Cycle 7 — close the wearable sync worker and `backend-sync-backfill` independently

- **Intended RED:** The assembled app has no `/v2/sync-jobs/run`, and a deployment inventory contract rejects `backend-sync-backfill`, its image/build path, service URL, allowance alerts, IAM, repair/release entries, and scheduler/backfill references while retained Mac capture and backend deployment checks remain green.
- **Why RED now:** active source/deploy residue was not found at the planning baseline, but live existence is unknown and historical/shared alert/check references can recur after rebasing predecessors.
- **Minimum GREEN:** rerun the complete inventory. If residue exists, delete it without touching retained deployment primitives. If none exists, keep predecessor behavioral proof and record this cycle as a verified no-op—do not create a new test solely to restate an already-enforced absence.
- **Protected behavior:** canonical backend release, account deletion, and any shared immutable-image or alert primitive with a live target.
- **Owner before → after:** rejected wearable backfill service or inherited absence → explicit repository absence owned by S-25 closure.
- **Expected surfaces:** only discovered backfill-specific workflow/config/scripts/tests/docs; likely no production edit on the inspected tree.
- **Focused verification:** exact residue search, runtime-env/runtime-image/workflow contracts, managed-alert checks, predecessor wearable retirement tests.
- **Deletion/simplification enabled:** one independent Cloud Run/image/IAM family removed from operational inventory.
- **Stop:** a caller appears that is not already rejected, or live mutation would be required to claim repository GREEN.

### Cycle 8 — delete Pusher protocol, service, image, and rollout plane

- **Intended RED:** A real `/v4/listen` session against fake managed STT emits the same transcript/lifecycle result with Pusher unavailable and produces no second socket, duplicated audio/transcript frame, upload, webhook, speaker sample, or finalization task; `/v1/trigger/listen` fails closed.
- **Why RED now:** listen constructs `ListenPusherSession`; Pusher protocol/router/app, image/dependencies, charts, two workflows, rollout/drain/capacity/config scripts, secrets/env, metrics, tests, and docs remain.
- **Minimum GREEN:** delete caller and protocol first, then the Pusher app/router/helpers/image/chart/workflows and every exclusive rollout/config/monitoring/check entry. Delete `HOSTED_PUSHER_API_URL`; narrow shared metrics/readiness only where retained.
- **Protected behavior:** Firebase listen auth, direct audio-to-provider streaming, transcript events, generic speaker labels, usage/fair-use, translation, Mac watchdog/reconnect, privacy diagnostics.
- **Owner before → after:** Pusher owns rejected side effects beside STT → no side-effect owner; canonical listen owns only transient transcription.
- **Expected surfaces:** Pusher and listen utility/router/source trees, runtime image/env, charts, workflows, check manifest/workflow contracts, rollout scripts/tests/runbooks, main/listen tests.
- **Focused verification:** rewritten `test_listen_pusher_session.py` and Pusher protocol tests as retained-listen/no-side-effect behavior; listen E2E with Pusher unreachable; WebSocket route absence; runtime/workflow checks.
- **Deletion/simplification enabled:** Pusher image/release/secret/alerts and one GKE workload disappear; finalizer caller disappears for Cycle 5.
- **Stop:** any accepted webhook/App/raw-audio/voice-profile consumer remains, or retained transcript output differs without Pusher.

### Cycle 9 — delete the separate `backend-listen` GKE control plane

- **Intended RED:** Deployment contracts expose `/v4/listen` only through the canonical backend and reject the `backend-listen` release, Service/NEG/ingress, HPA, PDB, scale scheduler, service account, workflow and release identity; a forced canonical backend restart makes the named Mac bundle reconnect without product-state loss.
- **Why RED now:** the chart, standalone Helm workflow, main backend workflow branches, runtime env, GKE status/probe scripts and tests still deploy and reason about `backend-listen`.
- **Minimum GREEN:** retain the router in `main.py`; delete the chart and all listener-specific deployment/rollback/scaling/IAM/config/alert/doc/test branches; make canonical routing/probes truthful without a compatibility service.
- **Protected behavior:** continuous managed transcription, Intel Mac path, local-model fallback, in-process VAD, generic diarization, translation, fair use, watchdog/reconnect.
- **Owner before → after:** same FastAPI image in GKE listener deployment → canonical Cloud Run service only.
- **Expected surfaces:** `backend/charts/backend-listen/**`, `gcp_backend_listen_helm.yml`, `gcp_backend*.yml`, runtime env, deploy/status/probe/concurrency scripts, chart/deployment tests, backend guide.
- **Focused verification:** listen route/contract and reconnect fault tests, `test_backend_listen_helm_defaults.py` replaced with canonical-routing assertion or deleted if exclusive, runtime/workflow checks, named-bundle reconnect acceptance.
- **Deletion/simplification enabled:** removes listener GKE workload, scaling adapter and dedicated network boundary.
- **Stop:** canonical public routing is not verifiable, long-lived socket failure/reconnect regresses, or capacity evidence requires a separate decision rather than speculative preservation.

### Cycle 10 — delete hosted completed-recording VAD and speech-profile service

- **Intended RED:** Live listen silence gating runs with hosted VAD/speech-profile endpoints unavailable; retained pre-roll/hangover/timestamp/keepalive/fair-use cases pass; no completed-recording or speech-profile production caller remains.
- **Why RED now:** `backend/modal/**`, hosted URL callers/config, the models image, VAD chart/workflow and tests remain, even though the retained live gate is in process.
- **Minimum GREEN:** after S-23/S-24 caller deletion, remove hosted VAD/speech-profile route and external client/fallback branches, Modal/models image/dependencies, VAD chart, `gcp_models.yml`, exclusive secrets/env/metrics/scripts/tests/docs. Preserve shared Silero assets imported by `VADStreamingGate`.
- **Protected behavior:** in-process VAD algorithm and fail-open policy, server control, timestamps, provider keepalive, accounting, Mac Local VAD Gate UI.
- **Owner before → after:** hosted file-processing service plus in-process gate → in-process gate only for live listening.
- **Expected surfaces:** `modal/main.py`, `vad_modal.py`, `speech_profile_modal.py`, hosted VAD/speech callers, Docker/deps, chart/workflow, runtime image/env/checks/tests/docs.
- **Focused verification:** `test_vad_gate.py`, `test_vad_onnx.py`, listen provider fake with hosted URLs unset/unreachable, runtime-image/workflow contracts, Local VAD desktop guard tests.
- **Deletion/simplification enabled:** VAD image, chart, workflow, secrets and GKE workload disappear.
- **Stop:** any retained completed-recording consumer exists, or the shared Silero model boundary cannot be separated safely.

### Cycle 11 — delete standalone GPU diarizer and vector service

- **Intended RED:** For the exact S-22-selected STT route, a multi-speaker fixture returns deterministic generic speaker IDs in the retained transcript shape with the standalone diarizer URL absent; local manual renaming still applies; diarizer endpoints are unavailable.
- **Why RED now:** diarizer source/image/chart/workflow and `speaker_embedding.py` external calls remain; provider eligibility has not yet been consumed from S-22.
- **Minimum GREEN:** delete `/v1/diarization`, `/v1/embedding`, `/v2/embedding` service source, Pyannote/WeSpeaker image/deps/chart/GPU workflow, external URL/fallback/vector helpers and exclusive config/metrics/benchmarks/tests/docs after all callers are gone.
- **Protected behavior:** generic within-conversation labels, transcript segment normalization, optional local manual names, no persistent voice identity.
- **Owner before → after:** external diarizer/vector service → selected STT provider owns generic labels; local store owns manual names.
- **Expected surfaces:** `backend/diarizer/**`, `utils/stt/speaker_embedding.py`, charts/workflow/runtime image/env, provider adapters, tests/docs.
- **Focused verification:** selected provider contract fixture, speaker normalization/local-name tests, rewritten `test_user_speaker_embedding.py`, runtime-image/workflow contracts, route absence.
- **Deletion/simplification enabled:** diarizer GPU image/release/secrets/alerts and GKE workload disappear.
- **Stop:** S-22 provider cannot supply stable generic labels, a retained cross-recording caller exists, or provider wire evidence is missing.

### Cycle 12 — delete standalone LLM gateway and its control plane

- **Intended RED:** Every S-22 retained Python model caller and normal typed Chat produces the same validated result/failure through its explicit direct provider fake while gateway URL/token/route artifacts are absent; gateway health/model endpoints fail closed; native OpenAI Realtime and Gemini Live switching still passes.
- **Why RED now:** gateway-mode clients, auto lanes, service auth, route/profile overrides, shadow/promotion, gateway source/image/chart/workflow, internal ingress/static address, VPC probes, metrics/accounting/replay tests and config remain.
- **Minimum GREEN:** verify S-22 caller ledger has zero gateway-dependent retained paths, then delete gateway adapters and all standalone source/deploy/auth/network/config/probe/metric/doc/test residue. Narrow shared `utils/llm` only to actual direct callers and keep workload-owned retry/fallback.
- **Protected behavior:** model/prompt/result semantics selected by S-22, normal Chat and tools, managed credentials, quota/usage, timeout/retry/fallback, native realtime provider switch.
- **Owner before → after:** gateway resolver/forwarder can override route → each owning Python workload uses its explicit in-process provider adapter.
- **Expected surfaces:** `backend/llm_gateway/**`, `utils/llm/gateway_*` and call sites, gateway chart/workflows/scripts, runtime env/image/workflow/check registries, replay harness, tests/docs.
- **Focused verification:** S-22 per-caller model contract suite; normal Chat provider fake; realtime voice tests; gateway endpoints/entrypoint absence; runtime/workflow/OpenAPI checks.
- **Deletion/simplification enabled:** gateway image, service token, GKE release, ingress/static IP, VPC connector use if exclusive, and deploy workflow disappear.
- **Stop:** any retained caller lacks an explicit direct route, behavior/fallback differs, or S-22 is not integrated.

### Cycle 13 — accept the independently deleted Notifications job

- **Intended RED:** The retained S-14 behavior test proves no Notifications job orchestration can run while local task reminders, proactive overlay, retained account/billing notification paths, and generic live callers still work; a static deployment tripwire rejects its job/image/scheduler/workflow/secret names.
- **Why RED now:** production source is already absent on the inspected baseline, so only a post-rebase reintroduction or unclassified shared registry reference should fail. Live job state remains unknown.
- **Minimum GREEN:** rerun S-14 tests and complete inventory. Delete only discovered job-specific residue. If none exists, record a verified no-op and make no production/test churn.
- **Protected behavior:** all local notification switches/frequencies/delivery, task reminders, proactive behavior, Sentry/PostHog, retained request-path notifications.
- **Owner before → after:** S-14's inherited repository absence → S-25 accepts deployment-family closure; retained notification owners stay separate.
- **Expected surfaces:** likely none; only reintroduced notification-job registry/config/docs if found.
- **Focused verification:** `test_s14_notifications_job_retirement.py`, retained notification behavior tests, runtime image/workflow/residue checks.
- **Deletion/simplification enabled:** job/scheduler/image/secret can be removed from later live inventory without coupling to local notifications.
- **Stop:** any proven retained caller or a missing S-14 behavioral guard.

### Cycle 14 — accept the independently deleted memory-maintenance job

- **Intended RED:** Local Memory CRUD/search/vector/lifecycle and transient compute pass with no hosted maintenance runner; a static deployment tripwire rejects maintenance job/image/scheduler/workflow/runtime-mode/secret residue.
- **Why RED now:** no active job deploy surface was found on the inspected baseline; only post-rebase residue or a hidden caller should fail. Live state is unknown.
- **Minimum GREEN:** rerun S-12 ownership tests/inventory; delete only discovered job-exclusive residue. If fully absent, close as verified no-op without manufacturing a replacement check.
- **Protected behavior:** local GRDB/FTS/vector authority, lifecycle/category behavior, private AI Profile, transient model compute.
- **Owner before → after:** S-12 inherited repository absence → explicit S-25 deployment closure; local Memory owner unchanged.
- **Expected surfaces:** likely none; discovered maintenance-specific registry/config/docs only.
- **Focused verification:** S-12 local Memory offline/restart/owner isolation tests, backend compute tests, runtime image/workflow searches.
- **Deletion/simplification enabled:** job/scheduler/image/secrets removed from live decommission inventory.
- **Stop:** any hosted authority caller survives or local Memory behavior is not green.

### Cycle 15 — delete public Persona/clone deployment residue independently

- **Intended RED:** The post-S-23 assembled app and Mac navigation expose no public Persona/clone route or creation surface, while private local AI Profile works; deployment contracts reject Persona site/service/image/workflow/domain/secrets/alerts.
- **Why RED now:** current deploy assets appear absent, but S-23 is not integrated and may change shared public-build/runtime registries; live site/service state is unknown.
- **Minimum GREEN:** consume S-23's product deletion, then remove only remaining Persona deploy/release/config/monitoring/docs residue. Preserve reusable public product/legal site machinery with a live owner.
- **Protected behavior:** private local AI Profile, local Memories/personalization, primary assistant, unrelated public website.
- **Owner before → after:** rejected public clone product/deployment → no clone owner; private profile remains local.
- **Expected surfaces:** only post-S-23 Persona workflow/site/runtime/build/check/docs hits; likely a repository no-op on current baseline.
- **Focused verification:** S-23 Persona route/navigation 404/absence and local-profile tests, workflow/runtime/residue checks.
- **Deletion/simplification enabled:** independently deployed Persona service/site/image/domain operational closure.
- **Stop:** S-23 incomplete, shared public site ownership unclear, or live contractual/retention input is missing.

### Cycle 16 — delete `backend-integration` deployment residue independently

- **Intended RED:** Canonical auth, Dodo webhook, retained model/STT/TTS routes, and local Pi work without an integration service; deployment/release-vector contracts reject `backend-integration` URL/revision/traffic/IAM/env/probes/alerts/public-integration OpenAPI.
- **Why RED now:** standalone workflow is absent on the baseline, but S-23 has not yet removed all external App API product surfaces and shared release scripts may regain references after integration.
- **Minimum GREEN:** after S-23 route/schema/client deletion, remove remaining duplicate-service deployment/traffic/repair/readiness/secret/monitoring/docs entries. Keep generic OAuth/auth and webhook primitives with retained callers.
- **Protected behavior:** canonical Firebase account auth, Dodo-disabled boundary/webhook shape, model/STT/TTS, managed Pi/local tools.
- **Owner before → after:** external App API on duplicate `main.py` service → no integration service; retained APIs remain on canonical main.
- **Expected surfaces:** post-S-23 runtime env/workflows/release scripts/OpenAPI/checks/docs hits; likely no standalone source edit on current baseline.
- **Focused verification:** S-23 external route 404s, canonical neighboring route tests, runtime env/workflow/release-vector/OpenAPI checks.
- **Deletion/simplification enabled:** independent Cloud Run service/IAM/revision/alerts live closure.
- **Stop:** S-23 incomplete or any released/retained external caller is proven.

### Cycle 17 — close source-less hosted Plugins deployment residue

- **Intended RED:** Deployment manifests and workflows cannot build or deploy a hosted Plugins service and contain no reference to missing `plugins/Dockerfile`; managed Pi, local Node transport, Swift typed tools and `ProactiveAssistantsPlugin` behavior pass.
- **Why RED now:** both `plugins/` and `gcp_plugins.yml` are absent in this snapshot, but shared manifest/baseline failures and live resource state may still carry historical residue.
- **Minimum GREEN:** after S-23 marketplace closure, delete any discovered service-only workflow/check/release/alert/docs reference. If none, accept no-op; never recreate source or an empty compatibility service.
- **Protected behavior:** local managed Pi agent loop, tool approvals/execution, Node bridge, proactive plugin.
- **Owner before → after:** missing hosted plugin runtime or inherited absence → explicit absence; local tool owners unchanged.
- **Expected surfaces:** only discovered zombie references in workflow/check/runtime/service catalogs/docs.
- **Focused verification:** existing local agent/tool tests and desktop core harness; exact missing-source/deploy residue search; workflow/check manifest validation.
- **Deletion/simplification enabled:** possible live Plugins service/image/IAM/alerts become independent decommission targets.
- **Stop:** a hit belongs to local Pi/Node/Swift plugin behavior or another shared live target.

### Cycle 18 — delete the self-hosted monitoring platform and extinct-service telemetry

- **Intended RED:** Retained backend errors, product analytics, model traces, sanitized logs, `/v1/health`, and authenticated `/metrics` work with no Prometheus/Grafana/Loki/Alloy/Alertmanager endpoint; deployment contracts reject monitoring releases/storage/domains/secrets/workflows and deleted-service dashboards/alerts.
- **Why RED now:** the full monitoring chart is already absent in this checkout, but Pusher/gateway/GKE-specific metrics, rollout gates and check registrations remain, and live stack state is unknown.
- **Minimum GREEN:** remove remaining self-hosted-platform and extinct-service scrape/exporter/dashboard/alert/config/docs branches as their service owners disappear; keep useful low-cardinality counters and managed Cloud Run health/5xx alerts only under their retained owners.
- **Protected behavior:** Sentry, PostHog, LangSmith, Cloud Logging, privacy sanitizer, `/metrics` token auth, `/v1/health`, minimal managed production outage alert contract.
- **Owner before → after:** Omi GKE monitoring platform plus service-specific telemetry → provider-native logs/metrics and retained observability tools; no self-hosted collector.
- **Expected surfaces:** shared metrics/readiness modules only for dead counters, service charts/scripts/check manifest/workflow contracts/docs/tests; likely no monitoring chart deletion on current tree.
- **Focused verification:** metrics authentication/PII tests, health tests, logging sanitizer tests, managed-alert tests, deleted-service metric residue searches.
- **Deletion/simplification enabled:** monitoring GKE workloads, storage, secrets, domains and exclusive service alerts can close operationally.
- **Stop:** removal would make a retained fallback/correctness branch unobservable or delete a managed alert authorized by IR-880.

### Cycle 19 — delete the shared GKE-only secrets and control-plane layer

- **Intended RED:** The deployment inventory contains no Helm release, namespace workload, GKE service account, Workload Identity binding, ingress/static IP, HPA/adapter, node/GPU pool, `backend-secrets` chart application, kubectl/Helm probe, or GKE deploy lock; canonical Cloud Run still receives each retained secret through its own validated binding.
- **Why RED now:** Pusher, listener, VAD, diarizer, gateway and `backend-secrets` charts/workflow branches share the current GKE namespace/control plane. Shared deployment admission, status and concurrency code still recognizes them.
- **Minimum GREEN:** after Cycles 8–12 and 18, delete the GKE-exclusive secrets chart and remaining shared GKE deployment/probe/config/check/docs code. Narrow shared scripts rather than weakening canonical Cloud Run safety. Do not delete Secret Manager secrets still consumed by Cloud Run.
- **Protected behavior:** retained Cloud Run secret validation, immutable revisions, candidate/traffic/rollback, deployment concurrency, provider credentials, metrics auth, account task signer.
- **Owner before → after:** shared Omi GKE runtime/control plane → no repository GKE owner; canonical Cloud Run deployment owns retained runtime config.
- **Expected surfaces:** `backend/charts/backend-secrets/**`, remaining GKE workflow branches/scripts/checks/runtime-env entries, docs/tests; service charts already deleted in their cycles.
- **Focused verification:** runtime-env render/validator, workflow/concurrency/admission tests, runtime-image contracts, canonical deployment dry render, exact GKE/Helm/kubectl residue search.
- **Deletion/simplification enabled:** later whole-cluster/namespace/node-pool/network/IAM decommission can be evaluated without mixed ownership.
- **Stop:** any retained workload, secret binding, release probe, or successor-owned S-27 prerequisite still requires GKE.

### Cycle 20 — regenerate contracts, close residue, and accept retained user paths

- **Intended RED:** One aggregate closure suite requires exactly the canonical backend plus retained managed dependencies; deleted HTTP/WS routes fail closed; route policy/OpenAPI/generated Swift contain no retired operation; runtime image/workflow/deploy registries contain no retired target; named-bundle retained flows pass offline and against authorized development seams.
- **Why RED now:** shared registries/docs/checks still name current retired services, and earlier cycles can leave cross-family residue even when their focused tests pass.
- **Minimum GREEN:** regenerate app-client OpenAPI and Swift from the live assembled surface, update route policy/service maps/architecture/docs, delete orphaned exclusive checks and dependencies, run exact residue classification, full suites/preflight, and named-bundle acceptance. Extend an existing manifest lane only if a stable gap remains.
- **Protected behavior:** every invariant in §9, all predecessor output, S-26/S-27 handoffs, and `BILLING_MODE=disabled` with zero provider transactions.
- **Owner before → after:** scattered service registries and stale documentation → one truthful canonical topology contract.
- **Expected surfaces:** route policy/OpenAPI/generated Swift only where the live surface changed; runtime image/env/workflow/check registries; `backend/AGENTS.md`, `FORK.md`, architecture/runbooks; focused aggregate tests. No Windows client work.
- **Focused verification:** all commands in §14, residue searches in §13, named acceptance in §15, requirements validator, diff check, full component suites, preflight and PR preflight.
- **Deletion/simplification enabled:** repository completion; produces the exact read-only inventory inputs for §16 and handoff to S-26/S-27.
- **Stop:** any unexplained residue, failed retained path, unclassified suite failure, missing generated contract, predecessor-owned conflict, or attempted live mutation.

## 12. Cross-slice ownership and handoffs

| Owner | S-25 consumes | S-25 owns | S-25 must not absorb / handoff |
|---|---|---|---|
| **S-01–S-03, S-06** | Cloud Agent VM, wearable/backfill, rejected hosted STT, Apps/integrations caller removals and protected local Pi/STT boundaries | Deployment residue that still names their rejected hosted targets | Never delete local agent runtime, Mac capture, `/v4/listen`, or a retained integration primitive with a proved caller |
| **S-08** | Durable account deletion, account/session safety, opaque job, handler, lock/retry/reconciler and deletion composition | Canonical task target, truthful dedicated identity/config; retirement of stale sync audience after drain | S-08 owns account semantics/export; S-27 owns final queue/IAM/region foundation |
| **S-10/S-16** | Local conversation authority and transient listen behavior; public playback rejected | Audio-merge/finalizer/Pusher/listener infrastructure teardown | Do not change local transcript schema, listen protocol, reconnect semantics or capture |
| **S-12/S-14** | Proven absence of memory-maintenance and Notifications jobs plus retained local behaviors | Accept/decommission their independently deployed residue | Do not redo Memory/notification product deletion or mutate local behavior |
| **S-18** | Disabled billing and retained deletion billing-cancellation seam | Nothing in billing product behavior | Dodo activation remains post-Wave-6 and separately authorized |
| **S-22** | Complete retained model caller ledger, explicit direct routes, generic-label-capable STT provider, both realtime voice providers | Delete gateway/diarizer/VAD deployment residue after parity | Do not select providers/models or change prompt/fallback semantics |
| **S-23** | Persona, Apps/integration API, server conversation/finalization, voice-identity product deletion | Duplicate service/site/workflow/runtime residue | Do not repeat route/schema/storage deletion; resolve shared-file conflicts from current owner |
| **S-24** | Product-data GCS/audio, vector/index, attachment deletion; update/preview bucket fence | Audio-merge/Pusher/storage-dependent worker and secret/IAM residue | Never delete update/preview publication storage or reimplement data deletion |
| **S-26** | Receives one-service topology and truthful registries | S-25 documents temporary source boundary | `desktop_backend.py`/`main.py` source consolidation and dev harness belong to S-26 |
| **S-27** | Receives no-rejected-service manifest plus live inventory template | S-25 deletes extinct target references only | Project/region/domain/Artifact Registry/retained Cloud Run/Redis/Firestore/GCS ownership, `us-west1`, and final release foundation belong to S-27 |

Shared-file conflicts are expected in `backend/main.py`, `utils/cloud_tasks.py`, `deploy/runtime_env.yaml`, `runtime_images.json`, workflow contracts, `.github/checks-manifest.yaml`, backend deploy workflows/scripts, route policy, generated Swift, `backend/AGENTS.md`, and `FORK.md`. At execution, rebase on the current integrated owner and make the smallest current-shape edit. Never restore a deleted predecessor branch to make an old S-25 path compile.

## 13. Repository residue-search strategy

Residue checks are static tripwires after behavioral GREEN, not substitutes for tests. Run from repository root, inspect every hit, and classify it as retained code, S-26/S-27 handoff, historical/requirements evidence, a negative test, or defect. Exclude `bootstrap-scaffold/**` only for the executable-repository closure pass; the roadmap must continue documenting what was deleted.

```bash
git ls-files ':!bootstrap-scaffold/**' | rg 'backend-sync|backend_sync|sync-backfill|backend-integration|gcp_plugins|personas-open-source'

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'backend-sync|backend_sync|backend-sync-backfill|SYNC_TASKS_|/v2/sync-jobs/run|/v2/audio-merge-jobs/run|audio-merge|/v1/conversation-finalization-jobs/run|conversation-finalization' .

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'HOSTED_PUSHER_API_URL|ListenPusherSession|/v1/trigger/listen|pusher_protocol|pusher-finalization|omi-pusher' .

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'backend-listen|omi-backend-listen|gcp_backend_listen_helm|active.connection|scheduled.scale' .

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'HOSTED_VAD_API_URL|HOSTED_SPEECH_PROFILE_API_URL|speech_profile_modal|vad_modal|omi-vad|gcp_models' .

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'HOSTED_SPEAKER_EMBEDDING_API_URL|/v1/diarization|/v1/embedding|/v2/embedding|omi-diarizer|gcp_diarizer|pyannote|wespeaker' .

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'OMI_LLM_GATEWAY|llm[_-]gateway|omi:auto:|generated_route_overrides|probe-llm-gateway|gcp_llm_gateway' .

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'notifications-job|memory-maintenance-job|gcp_personas|backend-integration|gcp_plugins|plugins/Dockerfile' .

rg -n --hidden --glob '!bootstrap-scaffold/**' --glob '!.git/**' \
  'Prometheus|Grafana|Loki|Alloy|Alertmanager|charts/monitoring|backend-secrets|kubectl|helm upgrade' \
  backend .github scripts FORK.md Makefile
```

Positive retained searches must still find and be reviewed:

```bash
rg -n 'VADStreamingGate|VAD_GATE_MODE|/v4/listen|/v1/health|/metrics' backend
rg -n 'ACCOUNT_DELETION_|account-deletion-wipes|account-deletion' backend .github
rg -n 'Sentry|PostHog|LangSmith|record_fallback|log_sanitizer' backend desktop/macos
rg -n 'desktop_backend|update|preview|BILLING_MODE' backend desktop/macos .github
```

No closure claim may rely on a zero-count alone. For example, `pusher` can mean the rejected service or unrelated prose; `plugin` can mean the retained local proactive/Pi integration; `vad` can mean the retained in-process gate; `diarization` can mean retained generic provider labels; `sync` can mean unrelated state synchronization. Each non-zero hit needs an owner and each zero must be paired with the relevant behavioral test.

## 14. Focused and component-level verification commands

Use the repository's official runners. The implementation PR records duration and result for every command; no command below is claimed green by this planning document.

### 14.1 Focused backend loop

Create a temporary runner list containing only current post-rebase test paths. The initial candidates are:

```bash
cd backend
s25_test_list="$(mktemp)"
printf '%s\n' \
  tests/services/users/test_account_deletion.py \
  tests/unit/test_audio_merge_tasks.py \
  tests/unit/test_sync_playback_service.py \
  tests/unit/test_conversation_finalization_jobs.py \
  tests/unit/test_listen_finalization_cloud_tasks.py \
  tests/unit/utils/test_listen_pusher_session.py \
  tests/unit/test_vad_gate.py \
  tests/unit/test_vad_onnx.py \
  tests/unit/test_user_speaker_embedding.py \
  tests/unit/test_backend_runtime_env_validator.py \
  tests/unit/test_runtime_image_contracts.py \
  tests/unit/test_workflow_contracts.py \
  tests/unit/test_route_policy_inventory.py \
  tests/unit/test_openapi_contract.py \
  > "$s25_test_list"
BACKEND_UNIT_TEST_FILE_LIST="$s25_test_list" bash test.sh
.venv/bin/python -m pytest -q testing/e2e/test_account_deletion_cloud_tasks.py
```

Refresh the list after predecessor integration and delete obsolete test paths when their production owner is deleted. New behavioral closure tests must live where `backend/test.sh` discovers them. The direct pytest command is only for the hermetic account-deletion E2E file that `test.sh` intentionally excludes; selector-discovered unit/service/router tests stay on `test.sh`. If the selected parallel set saturates the machine, use the runner's documented `BACKEND_PYTEST_WORKERS=1`.

Run family-specific provider/listen/model tests after each relevant cycle, including S-22's exact direct-caller suite and current assembled-app route tests. Run test discovery whenever files are added, moved, or deleted.

### 14.2 Generated contracts, route policy, deployment contracts

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
python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-workflows
python3 backend/scripts/validate-backend-runtime-env.py --env prod --check-workflows
python3 backend/scripts/check_workflow_contracts.py
make runtime-image-source-closure
```

Deleted internal handlers that were intentionally excluded from OpenAPI still require assembled-app 404/fail-closed tests. Do not add them to a deprecated or legacy-missing list. Generated output is refreshed from the live app surface; there is no Windows-client work.

### 14.3 Desktop and retained behavior

```bash
cd desktop/macos
./scripts/desktop-core-harness.sh --self-check
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-wave4-s25
./test.sh
```

Also run focused Swift tests selected by the component's documented `dev-feedback.py --once swift` flow for current listen/transcription reconnect, speaker normalization/manual naming, Auth/account deletion UI, typed Chat/realtime voice, local conversation commit, Memory/Tasks/Rewind, notifications, offline/restart, account switch, and same-UID reauthentication. Choose the exact current test filters after G1; do not paste stale names into implementation evidence.

### 14.4 Full repository gates

```bash
cd backend && bash test.sh
cd ../desktop/macos && ./test.sh
cd ../..
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
scripts/pr-preflight --suggest
make preflight
scripts/pr-preflight --pr-body-file /tmp/s25-pr-body.md
```

The future PR body must declare the failure class for every `fix:` commit and cite commands plus real user-path evidence. Any new deterministic check is registered in `.github/checks-manifest.yaml` with both local and CI lanes. Delete extinct family-specific checks; never weaken a shared retained gate merely to make removal pass.

## 15. Real named-bundle and retained user-path acceptance

Use the repository desktop E2E confidence ladder and only the assigned bundle. Never build over, launch, stop, restart, or inspect `/Applications/Omi.app`, `/Applications/Omi Beta.app`, `com.omi.computer-macos`, or `com.omi.computer-macos.beta`.

### 15.1 Hermetic acceptance

```bash
cd desktop/macos
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-wave4-s25
```

The hermetic matrix must prove startup, signed-out/signed-in fixture boundaries, Home, locally persisted conversations, Memory, Tasks, Rewind, notifications, offline behavior, restart/restoration, account switching, same-UID reauthentication, owner isolation, persistence failure with no phantom state, auth loss around async completion, and late-result rejection. Topology deletion must not alter those paths.

### 15.2 Named development-bundle acceptance

```bash
cd desktop/macos
OMI_APP_NAME="omi-wave4-s25" OMI_SKIP_TUNNEL=1 ./run.sh
./scripts/omi-ctl health
agent-swift connect --bundle-id com.omi.omi-wave4-s25
```

Use `omi-ctl` semantic actions/state/snapshots first and `agent-swift` for native UI/permission inspection. Record bundle identity and backend target before each run. Required development evidence is:

1. the named bundle launches and reports healthy without touching either production bundle;
2. a development-authenticated continuous-listen session reaches canonical `/v4/listen`, produces transcripts and generic speaker labels, writes through the local conversation owner, and creates no server conversation/audio/finalization side effect;
3. provider suspension/timeout and a controlled canonical-backend restart surface normal failure/reconnect behavior, with no Pusher/gateway/hosted-VAD/diarizer fallback and no duplicate/late local commit;
4. normal typed Chat reaches the S-22 direct provider path with tools/approval/result ownership unchanged, while both retained realtime voice providers keep their native switching/failover behavior;
5. Local VAD Gate presentation/behavior, local manual speaker naming, Memories, Tasks, Rewind, notification controls, updates/previews, export, account/usage and `BILLING_MODE=disabled` behavior remain unchanged;
6. deleted HTTP worker/model routes produce genuine 404 and deleted WebSocket upgrades fail closed against the development candidate; health and authenticated metrics remain available;
7. canonical account-deletion dispatch is proven hermetically first. A real Settings deletion is exercised only on a disposable, owned development identity after separate authorization for the external mutation; evidence must show persisted intent, opaque queue payload, canonical audience/signer, retry/reconciliation and eventual completion without using the legacy target. Never delete the ordinary seeded account or use production.

Do not treat a compile, health response, screenshot, or static residue count as full user-path acceptance.

## 16. Repository closure versus separately authorized live operational closure

### 16.1 Repository closure

Repository closure means all cycles are green; only canonical deployment targets remain in source/config/contracts; removed routes fail closed; retained suites and named bundle pass; exact residue hits are classified; docs/service maps are truthful; and a read-only operational inventory manifest can be produced. It does **not** mean a live resource was queried, drained, deployed, stopped, or deleted.

### 16.2 Later read-only inventory

Using verified environment/project identifiers from the then-current S-27/deployment authority—not guesses from old Omi names—inventory each resource independently and classify it **retained**, **rejected**, **shared**, **unknown**, or **already absent**:

| Resource class | Likely logical targets from repository evidence | Required read-only evidence before mutation |
|---|---|---|
| Cloud Run | `backend-sync`, `backend-sync-backfill`, `backend-integration`, hosted Plugins, Persona/clone; canonical `backend` retained | Service/revision URLs, traffic, ingress, runtime/deploy identities, env/secret refs, metrics, callers and rollback target |
| Cloud Tasks | `audio-merge` and `conversation-finalization` rejected; `account-deletion` retained | Queue location/shape, task counts/oldest age/retry state, target URL, payload generation, signer/audience, last dispatch/completion; no payload content copied into evidence |
| GKE/Helm/network | Pusher, `backend-listen`, VAD, diarizer, LLM gateway, monitoring, `backend-secrets`, namespaces/cluster/node pools/ingress/static IP/VPC/Workload Identity | Helm releases, workloads, Services/NEGs/ingress, traffic/DNS, HPA/adapters, shared users, credentials, retention/rollback dependencies |
| Jobs/schedulers | Notifications and memory maintenance | Job/scheduler existence, enabled state, last/next executions, image, service account, secrets and downstream side effects |
| Images | Sync/backfill/Pusher/models/diarizer/gateway/job/Persona/integration/Plugins images | Digests/tags referenced by any revision/workload/rollback; retention/security/legal policy; canonical image clearly separated |
| Secret Manager/IAM | Pusher/gateway/hosted-model/finalization/sync/job/site bindings | Reference graph from retained revisions and queues, signer/runtime/deploy identity separation, last-use evidence; never read secret values |
| Monitoring/storage | Prometheus/Grafana/Loki/Alloy/Alertmanager, monitoring buckets/domains, deleted-service dashboards/alerts | Retention/legal/incident evidence, shared consumers, export/backup need, provider-native replacements actually active |
| Product data | audio/playback artifacts or stores handed from S-24 | S-24 inventory/retention/legal/backup proof and zero retained callers; update/preview bucket explicitly protected |

The inventory must not expose credentials, raw PII, transcript/audio content, task payloads, or customer IDs. If project identity, resource ownership, retention law, contract obligation, or current traffic cannot be verified, classify **unknown** and stop that resource's closure.

### 16.3 Explicitly authorized mutation sequence

Only after fresh explicit authorization for the named environment and resources:

1. capture configuration/traffic/queue/IAM/image evidence and approved backup/retention/legal/rollback boundaries;
2. deploy and accept the canonical target first, including account-deletion queue shape and named-bundle paths;
3. stop new producers for one retired family and observe zero new work/traffic;
4. drain or safely terminalize its queue/tasks according to the authoritative product decision—never purge blindly;
5. shift/verify zero traffic and retain an explicit rollback window/image digest where policy requires it;
6. delete the service/job/Helm release, then exclusive scheduler/queue, then exclusive image/secret/IAM/network/alert resources in dependency order;
7. delete a shared GKE namespace/cluster/control plane only after every workload and shared consumer is proven absent;
8. rerun live inventory, canonical health/5xx alerts, account-deletion acceptance and named-bundle retained paths; attach sanitized evidence.

A failed operational step rolls back or stops within that one family; it does not authorize bulk teardown. Repository success is not a drain signal. A merged PR is not deploy approval. S-27 owns final retained foundation reownership and region changes.

## 17. Risks, ambiguities, and explicit stop points

| Risk / missing input | Affected cycles | Safe work | Evidence needed to reopen / later owner |
|---|---|---|---|
| S-22/S-23/S-24 implementations are absent from the pinned baseline | 1–20 | Cycle 0 inventory and plan only | Integrated commits, current tests/docs, rebase and fresh inventory; respective slice owners |
| Legacy account-deletion tasks/audience may still exist | 3, 6, operational closure | Keep canonical and bounded legacy acceptance; test both | Verified queue/task/traffic drain and rollback-window expiry; account/deploy operator |
| Exact canonical URL, signer and future `us-west1` queue foundation are successor-owned | 2–3, operational closure | Use typed required config with hermetic fake values; no guessed defaults | S-27 verified environment manifest plus separately authorized queue/IAM deployment |
| Current provider may not satisfy generic speaker labels without diarizer | 11 | Keep diarizer until exact contract passes; other family work can proceed | S-22 provider wire fixture and production-behavior test; model/STT owner |
| Direct model caller parity may be incomplete | 12 | All non-gateway cycles after other gates | S-22 complete caller ledger and passing direct-provider behavior/failure suite |
| Canonical Cloud Run socket capacity/routing may differ from GKE | 9, operational closure | Repository chart removal can be prepared after contract tests; do not claim live closure | Development load/restart/reconnect evidence, stable routing and explicit capacity owner decision |
| Pusher/finalizer/audio queues or stored artifacts may have live backlog | 4–8, operational closure | Delete no live resource; keep code until required rollback/drain boundary is known | Sanitized queue age/count/traffic/storage retention inventory and authorization |
| Shared GKE secret/network/monitoring primitive may have another live consumer | 18–19 | Delete family-exclusive references only | Complete cluster/namespace/secret/IAM/network reference graph |
| “Already absent” repo family may still exist live | 7, 13–18 | Record repository no-op honestly | Verified live inventory; explicit mutation authorization |
| Route deletion could be hidden from OpenAPI | 4–5, 8, 10–12, 20 | Assembled-app HTTP/WS negative tests | Genuine route-not-found/fail-closed result plus route-policy/OpenAPI regeneration |
| S-26/S-27 shared file changes conflict | 19–20 | Keep current source split and only delete extinct target branches | Rebase on current owner; handoff ledger accepted by successor |
| Billing/provider calls accidentally activate | all | Keep `BILLING_MODE=disabled`, hermetic provider fakes, zero transaction assertions | Separate post-Wave-6 S-18 authorization; never part of S-25 |

Additional stop conditions apply globally:

- a retained caller, released contract, legal/retention duty, or product-data owner is discovered for a deletion target;
- a behavioral RED can pass only by source-string assertion, no-op handler, alias, 410 shell, or compatibility deployment;
- deletion weakens auth, owner isolation, task durability, privacy sanitization, provider failure reporting, local persistence, or update/release safety;
- a command would touch a production Mac bundle or mutate external resources without the required authority;
- component/full preflight failure cannot be classified as intended RED, pre-existing debt, or fixed in-scope defect;
- closure would require changing a primary decision or absorbing S-22/S-23/S-24/S-26/S-27 work.

## 18. Final completion checklist

### Baseline and authority

- [ ] `711269baf5e653bd62132688998732207f11dd3c` remains an ancestor and execution rebased on current `origin/main` without branch rename.
- [ ] Requirements ledger passes and all 15 assigned detailed decisions remain unchanged and conflict-free with the deletion map.
- [ ] S-22, S-23 and S-24 are integrated; their exact outputs and shared-file ownership are refreshed.

### Retained behavior

- [ ] Canonical `backend/main.py` serves all retained backend routes, `/v1/health`, authenticated `/metrics`, and `/v4/listen` with no deleted-service availability dependency.
- [ ] Account deletion persists intent, enqueues opaque work to main, verifies a dedicated signer/audience, fences duplicate execution, retries/reconciles safely, and retains billing/auth/account cleanup.
- [ ] Legacy task payload/audience is removed only after verified drain evidence.
- [ ] In-process VAD, generic provider speaker labels, local manual names, direct managed model behavior, normal Chat/tools, and both realtime providers pass retained behavior/failure tests.
- [ ] Local conversations, Memories, Tasks/Goals, Chat history, Focus, Rewind, search, notifications, updates/previews, export, offline/restart/account-switch/late-result behavior remain green.
- [ ] `BILLING_MODE=disabled` remains; no billing transaction or entitlement change occurred.

### Independent deletion families

- [ ] Audio merge and conversation finalization each have genuine route absence and no producer/queue/config residue.
- [ ] `backend-sync`, the wearable `/v2/sync-jobs/run` worker, and `backend-sync-backfill` are independently absent from code, deployment registries, workflows, release/status/repair paths and docs.
- [ ] Pusher, `backend-listen`, hosted VAD/speech profile, diarizer and LLM gateway each have their own behavioral GREEN, image/workflow/chart/queue/secret/alert residue proof and operational target record.
- [ ] Notifications job, memory-maintenance job, Persona deployment, `backend-integration`, and hosted Plugins are each independently accepted as a verified no-op or have only their discovered residue deleted.
- [ ] Self-hosted monitoring and shared GKE-only secrets/control-plane references are gone; retained metrics/logging/alerts and Cloud Run secret bindings remain.
- [ ] `desktop-backend` and S-27 foundation work were not silently absorbed.

### Contracts, verification, and acceptance

- [ ] Removed HTTP routes are genuine 404s and removed WebSocket routes fail closed; no 410/no-op/alias/empty deployment remains.
- [ ] Route policy, app-client OpenAPI and generated Swift are regenerated and current; test discovery passes.
- [ ] Runtime env/image/workflow/deployment-concurrency/release-vector/check-manifest contracts describe one canonical backend and retained dependencies only.
- [ ] Focused tests, `backend/test.sh`, `desktop/macos/test.sh`, requirements validator, `git diff --check`, `make preflight`, and PR preflight pass with evidence.
- [ ] Every §13 residue hit is classified and positive retained-owner searches still find the protected paths.
- [ ] `omi-wave4-s25` hermetic and development acceptance passes; production bundles were never touched.
- [ ] Real account deletion, if exercised, used only a disposable owned development account under separate external-mutation authorization.

### Repository versus operations

- [ ] Repository closure is recorded separately from live-resource state.
- [ ] A sanitized read-only resource inventory classifies retained/rejected/shared/unknown/already-absent resources using verified project identities.
- [ ] No deploy, traffic change, drain, deletion, IAM/secret/image/network/GKE mutation is inferred from the repository PR.
- [ ] Every later operational mutation has explicit named-resource/environment authorization, backup/retention/legal/rollback boundaries, ordered drain evidence, and post-change acceptance.
- [ ] S-26 receives the source-consolidation handoff and S-27 receives the truthful retained-foundation/live-inventory handoff.

## 19. Integrated closeout record — 2026-08-23

S-25 implementation merged in PR #44 at `fbdb339f`. Closeout commit `a57b3f8d`
removed parity export settings and deployment classification left after topology
collapse. The four-line Windows diagnostic cleanup remains a retrospective scope
exception because reverting it would advertise retired `backend-listen`; this
closeout changes no Windows file. Canonical health/metrics/listen, removed-worker
routes, hermetic account-deletion dispatch, full component suites, official E2E,
complete Tier-2, and all 40 selected preflight checks are green. S-25 is
**repository-closed**. S-26 is ready after this closeout tree lands on `main`.
Legacy deletion-task audience/payload acceptance remains until verified
queue-drain proof; live resource inventory/decommission remains separately
authorized. See
[`wave-3-4-closeout tdd.md`](wave-3-4-closeout%20tdd.md).
