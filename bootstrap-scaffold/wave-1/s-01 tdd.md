# S-01 TDD plan — remove the cloud Agent VM and local-database mirroring

## Plan record

| Field | Value |
|---|---|
| Status | `ready to start` — repository Cycles 0-4 are executable; released-client compatibility is checked at its named boundary and live-cloud Cycle 5 remains separately gated |
| Wave | 1 |
| Slice | S-01 |
| Authorizing decisions | IR-001, the VM half of IR-002, and IR-934 |
| Protecting and scope-partition decisions | IR-003, IR-011, IR-113, IR-125, IR-127, IR-143, IR-806 through IR-809, IR-923, and IR-928 |
| Coordinated owners | S-05 for deletion of `LocalAgentAPIServer` and `omi-tools-stdio`; S-11 for normal-chat backend journal projection; S-15 for shared cloud screen-history deletion; S-23 and later backend cleanup for product data that remains after its final caller disappears |
| Dependencies | None |
| Unblocks | S-15 and an accurate post-VM canonical-backend/deployment inventory |
| Target baseline | `origin/main`; re-fetch and record the exact merge-base when implementation starts |
| Research snapshot | Current checkout at `5ecb5e17aeab01955aff150a22054a957e15a48e`; requirements and source must be rechecked if the merge-base changes |
| Postcondition | Signing in, completing either onboarding, entering signed-in Home, sleeping, changing owner, or handling memory pressure cannot provision or manage a per-user GCE VM and cannot upload or poll local Mac databases for one; the VM API, runtime, proxy, reaper, deploy control plane, and active operational residue are gone, while local chat, local journals, retained local tools, managed Pi, Agent Pills, Rewind, and desktop automation still work. |

### Known research baseline

- The requirements ledger passes: 714 indexed rows, 714 detailed sections, all reviewed.
- The structural validator proves ledger/detail shape, ordering, review status, one `### Decision` per IR, graph markers, and balanced fences. It does not prove semantic currency, so this plan also traced every Agent VM reference to later owning decisions and current source.
- S-01's current product flow matches the deletion map: both onboarding variants and signed-in Home can start `AgentVMService`; that actor provisions/status-polls a GCE VM, gzips and uploads `omi.db`, starts `AgentSyncService`, and sends a Firebase token; AgentSync polls nine GRDB table families every three seconds and posts deltas to VM `/sync`.
- `AgentSyncService` is additionally coupled to sleep, owner transition, and memory-pressure remediation. Those lifecycle owners remain; only their AgentSync calls disappear.
- Both routers are exclusive to the rejected product in this checkout. `desktop_agent_vm.py` owns `/v2/agent/provision` and `/v2/agent/status`. All five routes in `agent_tools.py` serve the VM/runtime/proxy path; the separate retained general tool router is `backend/routers/tools.py`.
- The remote product is independently operable today through `backend/agent_vm/`, `backend/agent-proxy/`, the proxy and reaper charts, two proxy workflows, VM-building sections in both desktop-backend workflows, runtime-image registration, GCE/Firestore/GKE/GCS/IAM state, and their checks/tests/docs.
- `desktop/macos/agent-cloud/` contains 22 files in the live tree, not the 21-file count recorded in IR-934. It is still an incomplete, unreferenced snapshot and is deleted whole.
- `PRODUCT.md` still describes optional Agent-VM SQLite mirroring and therefore moves with the code. Historical changelog records remain historical and are not rewritten.
- The current worktree already contains user-owned edits to `bootstrap-scaffold/deletion-map.md` and untracked Wave directories/plans. Implementation must inventory and preserve them rather than cleaning or overwriting them.
- No live GCP/GKE/Firestore inventory was performed while researching this plan. Repository deletion does not prove deployed resources are absent; destructive decommission is a separately approved operator phase below.
- The snapshot excludes some normal release-contract sources, including the checked-in app-client OpenAPI compatibility artifact and product-invariant documents referenced by preflight. Do not weaken checks or invent missing baselines in S-01. Restore/use the normal source when available and report any pre-existing scaffold limitation exactly.

### Two repository-contract gates

1. **Released app-client compatibility.** The backend guide normally forbids removing a released app-client endpoint. S-01 deliberately retires the complete rejected Agent VM product and the root guide forbids an in-repo no-op compatibility shell. Remove the seven endpoints from the current route/export/generated-client surfaces. If the restored released OpenAPI contract proves a shipped client still depends on them, do not add fake-success or dead forwarding handlers and do not bypass the check: stop the merge, attach the exact compatibility diff, and obtain an explicit contract-sunset decision under the repository release policy.
2. **Failure-class lifecycle.** The deletion map asks for exclusive failure-class residue to disappear, but the repository requires registry lifecycle transitions in separate PRs and preserves incident history. Keep `FC-agent-vm-stop-retains-disk` unchanged in the implementation PR. After code is deployed and live resources are retired, a separate lifecycle PR marks it dormant with `dormant_since`; it is never silently deleted.

## How this plan is executed

1. Start with [engineering:implement](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/implement/SKILL.md), using this file as the implementation spec. Its first setup operation is `make setup`, followed by a fresh `origin/main` fetch, exact merge-base/start-SHA capture, and clean baselines in the documented desktop/backend environments. Work on the current branch; do not rename it. Commit locally in testable vertical slices. Do not push, open a PR, merge, deploy, or delete live resources without the corresponding separate user authorization.
2. Use [engineering:tdd](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/tdd/SKILL.md) for each changed behavior. Add one failing test at an approved public seam, observe the intended RED, implement only enough for GREEN, and then move to the next cycle. Existing green tests are keep fences, not retroactively labelled RED tests. Do not write every test first.
3. Apply [engineering:codebase-design](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/codebase-design/SKILL.md) at the boundary audit and final simplification stage. The fixed design outcome is zero cloud-VM compatibility module: reuse the existing HTTP app, deployment registry, local runtime, Pi bridge, and automation boundaries as test surfaces. Do not introduce a no-op `AgentVMService`, a one-implementation provider registry, or an abstraction used only to make source deletion easier to assert.
4. After every RED/GREEN cycle, real-path exercise, and full check is green, finish with [engineering:code-review](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/code-review/SKILL.md). Use the recorded start SHA/merge-base as the fixed point and this plan plus the controlling IRs as the specification. Review Standards and Spec Compliance separately, fix all actionable findings, and rerun affected and final checks before the local commit is considered ready.

## Decision summary and non-goals

“Agent” names several unrelated systems in this repository. S-01 deletes only the cloud Agent VM product and its database-mirroring/control-plane path.

The resulting boundary is:

```text
Main / floating desktop Chat
  -> ChatProvider
  -> local AgentRuntimeProcess
  -> desktop/macos/agent local Node kernel
  -> omi-agentd.sqlite3 local journal
  -> managed Pi adapter / OMI_BRIDGE_PIPE
  -> ChatToolExecutor authorized local tools

No branch from onboarding, Home, sleep, owner transition, or memory pressure
  -> AgentVMService
  -> AgentSyncService
  -> /v2/agent/*
  -> per-user GCE VM
  -> agent-proxy
```

This slice does **not**:

- remove or replace `desktop/macos/agent/`, the local Node kernel, `omi-agentd.sqlite3`, managed Pi, or foreground/background Agent Pill behavior;
- delete `ChatToolExecutor`, local SQL, semantic search, daily recap, local Rewind, local embeddings, tasks, goals, memories, or other reviewed local tools;
- remove the local conversation journal, its visible local turn projection, or the normal-chat backend projection/outbox assigned to S-11;
- remove `DesktopAutomationBridge`, which is the retained test-only automation boundary;
- remove or redesign `LocalAgentAPIServer`; IR-922 and S-05 own deletion of that rejected local-program entrance;
- remove or redesign `omi-tools-stdio`; S-05's completed caller audit assigns that unused transport to deletion while preserving Pi's `OMI_BRIDGE_PIPE` path;
- remove general screen-activity/Firestore/Pinecone/MCP history merely because AgentSync mirrored screenshots to the VM; S-01 deletes only the VM copy, while S-15 owns the later shared cloud-copy deletion;
- remove general GCS, Redis, Pinecone, Firestore, or GKE support that still has a non-VM owner;
- redesign onboarding, account identity, sleep/wake, memory remediation, Rewind locking, Chat, tools, or deployment architecture beyond the minimum removal;
- edit Windows or rewrite historical changelogs;
- perform a production deploy or destructive cloud cleanup under implementation authorization alone.

## Current codeflow and ownership inventory

### 1. Mac provisioning producers

- Legacy onboarding completes local journal transition and UI state, then a `Task` starts both `AgentVMService.shared.startPipeline()` and retained `GoalGenerationService.shared.generateNow()`.
- Second Brain onboarding has the same mixed task after its own retained cleanup, opener, completion, and journal work.
- `DesktopHomeView` schedules `.agentVMProvisioning` after `StartupWarmupPolicy.agentVMProvisioningDelay` while also scheduling retained conversation, indexing, and proactive-assistant warmups.
- `StartupWarmupPolicyTests` contains VM-specific delay coverage and a source-string assertion. Delete those VM assertions; preserve the remaining warmup/session-scope behavior. Do not replace them with another source scrape and call it behavioral coverage.

### 2. Desktop VM and mirror owners

- `AgentVMService.swift` checks status, provisions on absence or failed status checks, polls until ready, pauses sync, gzips the current owner's `omi.db`, uploads it directly to `http://<vm-ip>:8080`, starts AgentSync, and sends the Firebase token.
- `AgentSyncService.swift` polls transcription sessions, action items, memories, staged tasks, live notes, screenshots, transcription segments, focus sessions, and observations every three seconds, owns per-user cursors, refreshes auth, retries/reuploads, and posts to VM `/sync`.
- `AppState` stops AgentSync before sleep; wake/restart behavior that belongs to transcription remains.
- `RuntimeOwnerIdentity` stops AgentSync during owner transition; local database/credential fencing remains.
- `ResourceMonitor` pauses/resumes AgentSync around remediation; all other cleanup thresholds and extreme-memory relaunch behavior remain under IR-928.
- `APIClient+ChatSessions.swift`, generated API code, environment comments, and Rewind comments/tests retain VM-only models, calls, or concurrency explanations. Adapt shared owners rather than deleting their retained behavior.

### 3. Backend entrances and state

- `backend/main.py` registers both VM routers. `backend/desktop_backend.py` registers the provisioning/status router.
- `backend/routers/desktop_agent_vm.py` owns GCE provisioning/status repair and Firestore `agentVm` state for `/v2/agent/provision` and `/v2/agent/status`.
- `backend/routers/agent_tools.py` exposes VM status/ensure/keepalive plus tool listing/execution to the VM runtime. Current production caller tracing leads only to `backend/agent_vm/main.py` and the rejected proxy/VM flow. Delete the router whole after a final merge-base caller check.
- `backend/database/users.py::get_agent_vm` becomes dead after the routers/proxy disappear and is deleted. Do not delete unrelated user helpers or generic tools.
- `backend/route_policy_manifest.yaml`, the legacy missing-route inventory, the OpenAPI export prefix, generated Swift methods, readiness tooling, rate-limit tests, and response-shape tests contain mixed contract residue that must be updated with the endpoint removal.
- `/v1/agents/hume/callback` is a separate retained route whose name happens to match a broad `/v1/agent` search. It is not S-01 scope.

### 4. Remote runtime and proxy

- `backend/agent_vm/` is the per-user Python runtime copied to GCE. It consumes the VM tool bridge and copied SQLite data.
- `backend/agent-proxy/` is the WebSocket mobile/remote bridge. It authenticates, reads and repairs `agentVm`, starts/resets GCE instances, proxies messages to VM port 8080, and persists remote chat behavior.
- `backend/charts/agent-proxy/` deploys the proxy, ingress, HPA, service account, backend config, and environment-specific values.
- `backend/charts/agent-vm-reaper/` plus `agent_vm_reaper.py` and its apply script clean only terminated VMs. Running instances are intentionally retained today, so deleting the reaper before the fleet would create unowned billable resources.
- `desktop/macos/agent-cloud/` is a rejected, incomplete Node snapshot with its own experiments, data tools, routing, fixtures, and tests. It is not the retained `desktop/macos/agent/` runtime.

### 5. Deployment and operational control plane

- `backend/runtime_images.json` registers `agent-vm` in both desktop-backend workflows and `agent-proxy` in its two proxy workflows.
- The development and production desktop-backend workflows build the VM image, render/upload `startup.sh` to `AGENT_GCS_BUCKET`, and pass that setting to the service.
- Two proxy workflows build, smoke, deploy, and inspect the GKE proxy release.
- Shared deployment concurrency, release-policy, rendered-deployment, status-report, workflow-contract, change-detection, async-scanner, Python-lock, type-check, and source-closure surfaces name the VM/proxy.
- `AGENT_GCS_BUCKET`, proxy GCP credentials, service accounts/IAM, ingress/static IP/certificate, VM image/startup objects, Firestore `agentVm`, GCE instances/disks, reaper resources, metrics, and alerts can outlive the repository. They require the gated inventory and deletion sequence below.

### 6. Existing regression fences

- Local chat/journal: `KernelTurnRecordedProjectionTests`, `ChatTimelineContinuityTests`, local runtime contract tests, and the agent runtime harness.
- Local tool path: `ChatToolExecutorSQLTests`, `PiMonoWiringTests`, `AgentRuntimeBridgeLifecycleTests`, and the `pi-mono-extension` package tests.
- Background Pi and automation: `AgentPillLifecycleTests`, `RealtimeHubSpawnAgentTests`, runtime status tests, cross-surface smoke, and `DesktopAutomationBridgeRouteTests`.
- Lifecycle neighbors: `StartupWarmupPolicyTests`, `AuthSessionCoordinatorTests`, owner-identity tests, Rewind lifecycle/concurrency tests, and resource-monitor tests.
- Backend/deploy: FastAPI route tests, runtime-image contracts, workflow contracts, release-policy tests, deployment concurrency, rendered deployment validation, async-blocker scanning, and preflight.
- Some existing tests are source-inspection tripwires. Preserve useful ones only where they still guard a stable static rule, label them honestly, and never use them as the sole proof of retained runtime behavior.

## Requirements-backed public seams

The requirements ledger establishes all three retained desktop seams and the
VM-only scope. Live decommission remains separately gated. Tests and real-path
evidence target these observable outcomes rather than private call order.

| Seam | Contract to prove | Primary evidence |
|---|---|---|
| Desktop lifecycle egress | Completing either onboarding, entering signed-in Home, sleeping, changing owner, and running memory remediation emits no `/v2/agent/*` request and no direct VM `:8080` health, upload, auth, or sync traffic. Adjacent retained lifecycle effects still occur. | Focused lifecycle tests plus request/log capture from isolated named bundles for longer than the former 20-second warmup window |
| Local chat, journal, and tool | A normal typed desktop turn is handled by the local runtime, appears in the local journal, survives restart, and can execute one retained local tool such as `execute_sql` through `ChatToolExecutor`. | Local runtime/journal/SQL behavioral tests, agent logic harness, and named-bundle exercise |
| Managed-Pi background work and automation | A managed-Pi background run reaches the Agent Pill's terminal state through the retained bridge, and `DesktopAutomationBridge` continues reporting a healthy local runtime/protocol identity. | Agent Pill/Pi wiring/runtime lifecycle/cross-surface tests plus named-bundle automation proof |
| Backend retirement | The applicable FastAPI apps return a genuine 404 for all seven retired routes. Retained desktop health/chat/realtime and `/v1/tools/*` routes remain mounted and preserve their auth/validation behavior. | `TestClient` requests against production app objects and existing retained-router tests |
| Deployment retirement | No active runtime-image registry, workflow, chart, rendered deployment, secret classification, or deploy/status contract can build or deploy Agent VM, proxy, or reaper. Retained services still satisfy their existing contracts. | Runtime-image/workflow/release/deployment contract tests and final manifest residue audit |

## Action ledger

Every relevant hit at the freshly pinned baseline must be assigned to this ledger, a named coordinated slice, or a historical/Windows exclusion. “Agent” by itself is not a deletion key.

| Action | Exact behavior and source boundary |
|---|---|
| **KEEP AS IS** | `desktop/macos/agent/`, the local Node kernel, `omi-agentd.sqlite3`, `ChatProvider`'s local runtime path, and normal main/floating Chat behavior. |
| **KEEP AS IS** | Managed Pi foreground/background execution, `pi-mono-extension -> OMI_BRIDGE_PIPE -> ChatToolExecutor`, Agent Pill lifecycle, local runtime status, and local runtime contract fixtures. |
| **KEEP AS IS** | Swift `ChatToolExecutor` and retained local SQL, semantic-search, daily-recap, Rewind, task, goal, memory, and other reviewed local tools. Delete only copied VM implementations. |
| **KEEP AS IS** | Local conversation journal and visible local turn projection. Preserve the normal backend projection/outbox until S-11 changes its authority. |
| **KEEP AS IS** | Local Rewind database, embeddings, screenshot OCR data, file locking, and current-user ownership behavior. Remove VM writer assumptions/comments without weakening concurrency guarantees. |
| **KEEP AS IS** | `DesktopAutomationBridge`, general `/v1/tools/*`, `/v1/agents/hume/callback`, and all non-VM desktop health/chat/realtime routes. |
| **ADAPT** | Both onboarding completions: remove only VM startup and keep completion callbacks, journal finish, goal generation, launch-at-login, monitoring, indexing, opener, and draft cleanup behavior. |
| **ADAPT** | Signed-in Home/startup warmup: delete VM-only state, task ID, delay, scheduler, cancellation/reset state, and tests while retaining every other warmup and session-scope rule. |
| **ADAPT** | Sleep, owner transition, and memory remediation: remove only AgentSync calls. Keep transcription restart, storage/credential fencing, cleanup, thresholds, delayed resume for retained owners, and extreme-memory relaunch. |
| **ADAPT** | Shared API/generated/route-policy/test files: remove the retired seven-route surface and VM models without changing retained tool/chat/health contracts. |
| **ADAPT** | Shared deployment/workflow/check files: remove only VM/proxy/reaper image, path, env, workflow, service, and source-root entries. Preserve checks for all retained services. |
| **ADAPT** | Current docs and comments: make local-only behavior truthful in `PRODUCT.md`, current `FORK.md` architecture, component guides, README, environment templates, and operational docs. Keep historical records intact. |
| **DELETE** | `AgentVMService.swift`, `AgentSyncService.swift`, their exclusive tests, VM status/provision Swift models and methods, and all exclusive lifecycle/UI state. |
| **DELETE** | `backend/routers/desktop_agent_vm.py`, `backend/routers/agent_tools.py`, their registrations, exclusive `get_agent_vm`/`agentVm` helpers and policies, and exclusive tests/fixtures/readiness probes. |
| **DELETE** | Complete `backend/agent_vm/`, `backend/agent-proxy/`, `backend/charts/agent-proxy/`, `backend/charts/agent-vm-reaper/`, reaper scripts, and `desktop/macos/agent-cloud/` trees. |
| **DELETE** | VM/proxy workflows, runtime-image entries, VM build/upload workflow sections, `AGENT_GCS_BUCKET` binding, proxy/reaper deployment contracts, exclusive metrics/alerts/runbooks, generated route methods, and active current-doc claims. |
| **DELETE, GATED LIVE** | After producer removal is deployed and a recoverable inventory is captured: all `omi-agent-*` instances/disks, proxy Helm releases/workloads/ingress, reaper CronJob/config/script, VM image/startup objects, exclusive IAM/service accounts/secrets/static IP/certificate/DNS, Firestore `agentVm` fields, and exclusive monitoring resources. |
| **SIMPLIFY / OPTIMIZE AFTER** | After all repository RED/GREEN cycles are green, remove dead imports, empty extensions, stale retry/cursor types, obsolete workflow branches, duplicate comments, and now-single-purpose check parameters. Do not redesign retained Chat, tools, Rewind, lifecycle, or deployment modules. |
| **ACCELERATE AFTER** | `none` planned. Record focused backend/desktop loop durations if available, but do not invent a performance objective for a deletion slice. |
| **AUTOMATE LAST** | Adapt existing route, runtime-image, workflow, and deploy contract tests in their current CI lanes. Add no standalone source scraper or one-time cleanup script to the repository. A permanent new guard requires the repository's real-incident justification; otherwise the final classified residue command is evidence only. |
| **OUT OF SCOPE / DEFERRED** | S-05 deletion of the local API and stdio transports; S-11 journal projection; S-15 shared screen-history cloud deletion; broader backend product-data removal; Windows; historical changelogs; unrelated cloud providers/resources; production deployment/release without authorization. |

## Interface design after deletion

### The absence is structural, not configurable

There is no replacement `CloudAgentProvider`, feature flag, disabled router, no-op actor, or deprecated alias. The Mac no longer owns a cloud-VM lifecycle interface; the backend no longer exposes a VM control/tool bridge; deployment registries no longer describe these services. The compiler, route table, and deployment registry make the deleted ownership impossible.

### Retained local agent boundary

```text
Desktop Chat / Agent Pill
        │
        ▼
ChatProvider / DesktopCoordinatorService
        │
        ▼
AgentRuntimeProcess + local Node kernel
        │
        ├─ local journal (`omi-agentd.sqlite3`)
        └─ managed Pi extension (`OMI_BRIDGE_PIPE`)
                    │
                    ▼
             ChatToolExecutor
```

- Do not route retained managed Pi through `omi-tools-stdio` merely because the VM bridge is deleted.
- Do not make `LocalAgentAPIServer` the replacement for removed remote access.
- Do not copy VM SQL/semantic/daily-recap code into the local runtime; retain the already-owned local implementations.
- The local runtime has production and harness/recording adapters already. Reuse them rather than creating an S-01-only fake boundary.

### Backend public surface

The public test boundary is the real FastAPI app/router surface. Test the seven removed paths with HTTP requests against `backend.main.app` and, where mounted, `desktop_backend.app`. Assert genuine 404s. Separately exercise representative retained `/v1/tools/*` and desktop health/chat routes so a broad prefix deletion cannot pass by removing unrelated routes.

The endpoint deletion is intentionally breaking because the complete product is retired. Do not return 200/410 from compatibility handlers, retain response models with no caller, or leave route-policy tombstones. The release-contract gate above is the only acceptable stop point if a shipped client contract is proven.

### Deployment surface

`backend/runtime_images.json` remains the single deployment-image registry. Delete the `agent-vm` and `agent-proxy` records and adapt existing source-closure/workflow contracts; do not create a second deletion registry. Shared workflows continue to build and deploy retained desktop-backend artifacts without `AGENT_GCS_BUCKET` or VM startup upload steps.

### Firestore and screen-data partition

- Delete `users/{uid}.agentVm` readers/writers only after all repository callers are removed.
- The live cleanup removes existing `agentVm` fields only after a recoverable inventory and explicit destructive approval.
- Delete AgentSync screenshot mirroring because it is one of the nine VM-copy tables.
- Preserve local Rewind and embeddings. Leave generic cloud screen-activity storage/search/MCP routes to S-15 unless final caller tracing proves an item is exclusively nested inside the VM runtime being deleted.

## Ordered TDD implementation cycles

### Cycle 0 — pin the baseline and freeze retained paths

This is setup/research, not a passing “characterization test” presented as TDD.

1. Run `make setup`, fetch `origin/main`, record the exact merge-base/start SHA, and save `git status --short` so pre-existing scaffold changes remain identifiable.
2. Re-run `python3 bootstrap-scaffold/validate-requirements-ledger.py` and re-read the controlling IR sections if either requirements file changed.
3. Produce exact current inventories for:
   - every `AgentVMService.shared`, `AgentSyncService.shared`, `.agentVMProvisioning`, `/v1/agent`, `/v2/agent`, `agentVm`, `agent-vm`, `agent_vm`, `agent-proxy`, `AGENT_GCS_BUCKET`, and `omi-agent-*` hit;
   - all five exclusive source trees and every external reference to them;
   - generated clients, route manifests, release/deploy contracts, workflow inputs, secret/config classification, metrics/alerts, current docs, and failure-class references;
   - screen-activity helpers, classifying VM mirror versus retained local/S-15 ownership;
   - similarly named retained `desktop/macos/agent`, `/v1/agents/hume/callback`, `LocalAgentAPIServer`, automation, Pi, and general tool hits.
4. Run existing green keep fences for local journal/chat, SQL tools, Pi wiring, runtime lifecycle, Agent Pills, automation, startup/session scope, owner transitions, Rewind concurrency, and backend retained routes.
5. Record a read-only live-resource inventory if credentials are available. Do not mutate GCP, GKE, Firestore, GCS, IAM, DNS, certificates, secrets, or alerts in Cycle 0.
6. If a retained outcome lacks coverage, add a focused behavioral fence before touching its owner and label it as baseline characterization. Do not claim a test that was green against old code as the RED for a deletion cycle.

### Cycle 1 — retire the public VM path and disconnect every Mac producer

**RED:** Add a focused backend HTTP route-retirement test against the production FastAPI app objects. It must fail because the applicable apps still mount the seven retired paths. The expected final result is 404 for all seven, while representative `/v1/tools/*`, desktop health/chat, and `/v1/agents/hume/callback` routes remain mounted and preserve their existing auth/validation response rather than becoming 404. Cite the approved deletion map and IRs as the external source for the changed route expectation.

**GREEN:** Make one vertical cut so no intermediate commit leaves a live Mac producer calling a deliberately removed backend:

1. Remove VM start from both onboarding completion tasks, preserving `GoalGenerationService.generateNow()` and every neighboring completion effect.
2. Remove Home's VM scheduling call, state, reset/cancellation state, task ID, delay, and VM-only startup tests while leaving every other warmup untouched.
3. Remove AgentSync-only sleep, owner-transition, and memory-pressure hooks; retain all adjacent lifecycle behavior.
4. Remove VM API models/methods and non-generated desktop client references.
5. Unregister and delete `desktop_agent_vm.py` and `agent_tools.py` from the applicable apps; delete exclusive `get_agent_vm` and related state helpers after final caller proof.
6. Make the HTTP route test green with genuine absence, then update mixed retained-route/rate-limit/readiness/response tests without weakening them.

**Verify before the next cycle:** focused backend HTTP tests; Swift startup, onboarding-adjacent, owner, resource-monitor, Rewind, journal, SQL, Pi, Agent Pill, and automation tests; debug compile; and an isolated named-bundle request capture proving signed-in Home stays quiet beyond the former 20-second delay. Any surviving VM request is a failed cycle, even if the backend returns 404.

### Cycle 2 — delete desktop VM/mirror implementation without harming local durability

**RED:** Through existing production-behavior tests, make the first implementation deletion expose any accidental reliance on VM actors: compile and run the retained local journal, SQL tool, runtime bridge, owner-transition, Rewind lifecycle/concurrency, and memory-remediation selections immediately after removing VM references. A failure must be resolved at the retained owner, not by restoring a VM shim. If current coverage cannot observe the agreed retained outcome, first add the smallest behavioral test at that existing seam and observe it fail against the deletion work before repairing the retained path.

**GREEN:** Delete `AgentVMService.swift`, `AgentSyncService.swift`, their exclusive tests, cursor/reupload/auth/sync types, and stale comments. Adapt Rewind comments/tests to describe the actual retained multi-writer/locking contract without weakening it. Remove hard-coded VM test-runner and e2e coverage-manifest entries. Do not delete or rename local database tables merely because AgentSync used to poll them.

**Verify before the next cycle:** the focused retained-path selection, `xcrun swift build --package-path Desktop`, `./scripts/agent-logic-harness.sh --cross-surface-smoke`, and then the full agent logic harness. Inspect the compiled app and local logs for zero `AgentVMService`/`AgentSyncService` startup, owner, sleep, or remediation activity.

### Cycle 3 — retire VM runtime, proxy, reaper, and deploy ownership

**RED:** Adapt the existing runtime-image/workflow/rendered-deployment/release-policy tests to assert that `agent-vm`, `agent-proxy`, the reaper, `AGENT_GCS_BUCKET`, VM startup upload, and proxy workflows are absent while every retained service contract still validates. Run the focused selection and observe failure against the current registries/workflows.

**GREEN:**

1. Delete `backend/agent_vm/`, `backend/agent-proxy/`, `backend/charts/agent-proxy/`, `backend/charts/agent-vm-reaper/`, both reaper scripts, and their exclusive tests.
2. Delete both proxy workflows. Remove only the VM image build/render/upload steps, triggers, environment, and source registration from development and production desktop-backend workflows.
3. Delete `agent-vm` and `agent-proxy` from `runtime_images.json`; remove proxy/reaper from rendered-deployment, status-report, concurrency, workflow-contract, change-detection, async-scanner, type-check, Python-lock, inventory-whitelist, and release-policy surfaces.
4. Remove exclusive proxy credentials/IAM/Helm/config classification and monitoring declarations from repository contracts. Preserve shared GKE/GCP/Firestore support owned by retained services.
5. Make every adapted deployment contract green. Do not weaken a check globally because its VM assertion disappeared.

**Verify before the next cycle:** focused workflow/runtime/deployment tests, `make runtime-image-source-closure`, retained service smoke/import checks selected by the registry, backend type/import checks, and a classified search of all active workflow/chart/config references.

### Cycle 4 — delete the orphan cloud snapshot and close active contract residue

**RED:** Update the existing generated-client/route-policy/current-inventory contracts to describe the post-retirement surface and run them against the still-dirty tree. They must fail for actual remaining `/v1/agent`, `/v2/agent`, VM/proxy/reaper, or `agent-cloud` ownership. Where no stable existing CI contract owns a residue category, use a temporary classified search and do not commit a new source scraper merely to manufacture RED.

**GREEN:**

1. Delete the complete 22-file `desktop/macos/agent-cloud/` snapshot and its experiments/tests/scripts.
2. Remove `/v1/agent` from the app-client export prefix and regenerate `OmiApi.generated.swift` from the post-deletion production app surface. Delete VM-only response/request models and methods; do not hand-maintain a stale generated fragment.
3. Remove the seven endpoints from route policy and legacy route inventories, readiness/inventory tools, e2e coverage manifests, component runners, and all exclusive tests/fixtures.
4. Update `PRODUCT.md`, current `FORK.md` inventory, backend/desktop/GitHub guides, README, environment comments, type-safety/service-map docs, and current operational documentation. Preserve historical changelog entries.
5. Remove stale “Agent VM writer” comments without deleting the real Rewind locking behavior they once explained.
6. Classify every remaining search hit as retained local agent, coordinated later owner, historical record, failure-class history, or false positive. Any unclassified live hit keeps Cycle 4 red.

**Verify before review:** generated-client freshness/compatibility checks available in the restored normal checkout, route-policy validation, backend/desktop component suites, documentation/guide checks, requirements validator, and final classified residue inventory.

### Cycle 5 — gated live-cloud decommission

This is an operator cycle after the repository change has landed and the producer/control-plane removal is deployed. It is not authorized by ordinary implementation, commit, push, or PR approval.

**Precondition:** explicit destructive approval naming the environment(s) and resource inventory; confirmed deployment of the Mac/backend producer cut; recoverable export of inventory and Firestore fields; an owner and rollback/incident channel for the maintenance window.

**Inventory before deletion:**

- every GCE instance and disk matching the exact Agent VM naming/labels in each project/zone, including running, stopped, and terminated states;
- development/production proxy Helm releases, deployments, services, HPAs, ingress/backend configs, static IPs, certificates, DNS, namespaces, secrets, KSAs/GSAs, and IAM bindings;
- VM reaper CronJob, ConfigMap/script, KSA/GSA, schedule, logs, and alerts;
- GCS startup script/image artifacts and any image registry tags exclusively owned by Agent VM;
- every Firestore `users/{uid}.agentVm` field and exclusive monitoring/dashboard/alert resource;
- any unexpected active connection or creation event after the producer removal deployment.

**Destructive order:**

1. Prove no new provisioning requests or VM creations occur for an agreed observation window.
2. Delete Agent VM instances and attached/persistent disks first. Running VMs must not be left behind when the reaper is removed.
3. Remove proxy Helm releases/workloads/services/ingress and their exclusive network/certificate/DNS resources after confirming no retained traffic.
4. Remove the reaper only after the fleet is zero.
5. Delete exclusive GCS/image artifacts, service accounts/IAM, secrets, and monitoring resources.
6. Delete Firestore `agentVm` fields from the captured exact document set; do not broad-delete user documents or unrelated fields.
7. Verify zero fleet, zero proxy/reaper workload, zero VM artifacts/state, zero provisioning traffic, no unexpected billing, and healthy retained desktop behavior.

**After live GREEN:** open the separate failure-class lifecycle PR that marks `FC-agent-vm-stop-retains-disk` dormant with `dormant_since` and cites the completed decommission evidence. Do not delete the historical failure record.

## Review and simplification — only after GREEN

Run this stage after Cycles 1 through 4 are green; run the live-specific review again after Cycle 5 if/when authorized.

- Delete dead imports, empty files/extensions, obsolete VM retry/cursor/model types, unused environment plumbing, and deployment parameters whose only consumer disappeared.
- Collapse shared checks only where their interface is now needlessly VM-specific. Preserve multi-service registries and checks that still have multiple real consumers.
- Ensure no generic “agent” rename obscures the retained managed-Pi/local-agent vocabulary.
- Ensure current docs explain the local runtime and no longer imply remote/mobile VM chat or SQLite mirroring.
- Re-run final caller tracing for `agent_tools.py`, `get_agent_vm`, all Firestore `agentVm` writes, screen activity, and `AGENT_GCS_BUCKET` before accepting deletion completeness.
- Confirm no new `TODO`/`FIXME`/`HACK`, no compatibility shell, no fake success route, no dormant deployment switch, and no one-off cleanup script landed.
- Run `engineering:code-review` from the recorded fixed point with two independent axes:
  - **Standards:** root/component guides, test quality, generated-code policy, deployment contracts, failure-class lifecycle, documentation, and safety.
  - **Spec Compliance:** every keep/adapt/delete/defer row, approved seam, IR partition, route list, live gate, and closure proof in this file.
- Resolve every actionable finding, rerun affected focused tests, then rerun the final component/repository checks. Record any disagreement with evidence rather than silently dismissing it.

## Verification and closure evidence

### Focused desktop loop while editing

```bash
cd desktop/macos

xcrun swift test --package-path Desktop \
  --filter 'StartupWarmupPolicyTests|AuthSessionCoordinatorTests|RuntimeOwnerIdentityTests|RewindDatabaseLifecycleTests|RewindDatabaseCurrentUserIdConcurrencyTests|KernelTurnRecordedProjectionTests|ChatTimelineContinuityTests|ChatToolExecutorSQLTests|AgentRuntimeBridgeLifecycleTests|PiMonoWiringTests|AgentPillLifecycleTests|DesktopAutomationBridgeRouteTests'

./scripts/agent-logic-harness.sh --cross-surface-smoke
./scripts/agent-logic-harness.sh
xcrun swift build --package-path Desktop
```

- Remove VM-exclusive test files from `desktop/macos/test.sh` only when their production owners are deleted.
- A compile is not user-path proof. The harness and named-bundle exercises below remain mandatory.
- Source-string tests may support a static invariant but cannot substitute for journal/tool/Pi/lifecycle behavior.

### Focused backend and deployment loop

Use the documented backend environment created by `make setup`. Run one exact changed-file selection at a time through the component runner or pytest only when the guide permits, then run the complete component suite.

Required behavior/contract groups:

- new seven-route retirement tests against `backend.main.app` and `desktop_backend.app`;
- retained general tools, health/chat/realtime, authentication, rate-limit, route-policy, and inventory tests;
- runtime-image contracts and source closure;
- desktop-backend release policy and its tests;
- deployment concurrency and rendered-deployment contracts;
- workflow-contract, change-detection, async-scanner, type/import, Python-lock, and deploy-status tests;
- generated app-client export/freshness/compatibility checks available in the normal checkout.

```bash
cd backend
bash test-preflight.sh
bash test.sh

cd ../
make runtime-image-source-closure
```

### Named-bundle real-path proof

Never stop or overwrite production Omi/Omi Beta. Use isolated `omi-` prefixed bundles and worktree-owned local backend/logs.

1. Build a clean named bundle such as:

   ```bash
   cd desktop/macos
   OMI_APP_NAME=omi-s01-no-agent-vm OMI_SKIP_TUNNEL=1 ./run.sh --full
   ```

2. Use disposable named profiles to exercise both legacy and Second Brain onboarding completion. For each, prove the retained completion/UI/journal/goal-generation behavior and capture requests/logs beyond the former 20-second VM warmup delay.
3. Enter signed-in Home, wait beyond the old warmup, sleep/wake, switch owner through the supported test path, and exercise memory remediation through its controlled seam. Assert no `/v2/agent/*`, direct VM `:8080`, upload, auth, or `/sync` traffic and no VM lifecycle logs.
4. Send a normal typed Chat turn. Prove it reaches the local runtime, renders once, is recorded in the local journal, and survives app restart.
5. Execute one retained local SQL tool through the real `ChatToolExecutor` path and inspect the bounded result.
6. Start one managed-Pi background run and prove its Agent Pill reaches the canonical terminal state through the retained local bridge.
7. Query `DesktopAutomationBridge` health/runtime protocol identity and retain its evidence.
8. Record bundle name, backend/log paths, timestamps, semantic snapshots, commands, and outcomes. Remove the disposable named bundles only through the documented safe cleanup path after evidence is captured.

### Residue closure

Run searches from the repository root after code generation and documentation updates. Classify results; do not blindly delete substring matches.

```bash
rg -n -i \
  'AgentVMService|AgentSyncService|agentVMProvisioning|/v2/agent/(provision|status)|/v1/agent/(vm-status|vm-ensure|keepalive|tools|execute-tool)|agentVm|agent-vm|agent_vm|agent-proxy|AGENT_GCS_BUCKET|omi-agent-' \
  desktop/macos backend .github config PRODUCT.md FORK.md \
  --glob '!**/CHANGELOG*' \
  --glob '!**/node_modules/**' \
  --glob '!**/.build/**'
```

Allowed final categories are only:

- this S-01 plan, requirements/deletion research, or an accurate historical record;
- the still-active failure-class record pending its separate post-decommission dormant transition;
- an exact S-05/S-11/S-15/later-owner handoff named in this plan;
- a similarly named retained local-agent or `/v1/agents/hume/callback` surface with evidence;
- live-decommission evidence retained outside product source according to operator policy.

Any live producer, consumer, route, helper, model, state field, service tree, workflow, image, chart, secret/config binding, metric/alert, generated method, test, fixture, current doc, or unidentified hit means S-01 is not closed.

### Full repository and delivery proof

Before a local commit is handed off:

1. Run the requirements validator, full desktop suite, full backend suite, agent logic harness, runtime-image source closure, generated-client checks, and every diff-scoped manifest check.
2. Run `scripts/pr-preflight --suggest` and `make preflight`. If the scaffold snapshot still lacks normal invariant/OpenAPI sources, report the exact baseline failure and restore/route it to the correct owner; do not weaken checks or claim success.
3. Draft the eventual PR body with all matched invariant IDs, the deliberate Agent API retirement, test rewrites' external decision source, exact verification commands/results, named-bundle evidence, PR size advisory, compatibility status, and deferred destructive decommission gate. Validate it with `scripts/pr-preflight --pr-body-file` before any later PR request.
4. Use individual local commits per testable vertical surface, not per file. Keep the plan/document update separate when that improves review provenance.
5. Re-fetch before final review/commit, compare against the exact fixed point, and rerun checks for overlapping upstream changes.
6. Do not push, open a PR, merge, deploy, or execute Cycle 5 unless the user separately authorizes that action.

## Completion checklist

- [ ] Exact merge-base/start SHA and pre-existing worktree ledger recorded.
- [ ] Requirements ledger revalidated and every discovered hit classified.
- [ ] Approved desktop lifecycle, local chat/journal/tool, and managed-Pi/automation seams protected.
- [ ] Both onboarding variants and signed-in Home have no VM producer while adjacent behavior remains.
- [ ] Sleep, owner transition, and memory remediation contain no AgentSync coupling.
- [ ] `AgentVMService`, `AgentSyncService`, exclusive client models/methods, and exclusive tests are deleted.
- [ ] All seven retired HTTP routes return 404; retained tools/health/chat/realtime routes still behave correctly.
- [ ] Both VM-only routers, registrations, Firestore helpers, and exclusive backend tests are deleted.
- [ ] VM runtime, proxy, charts, reaper, scripts, workflows, runtime-image entries, and orphan cloud snapshot are deleted.
- [ ] Shared workflow/deployment/check files remain green for retained services.
- [ ] Generated client, route policy, environment/config, current docs, and active operational residue are closed.
- [ ] Local journal persistence, one local SQL tool, one background managed-Pi Agent Pill, and automation health are exercised in a named bundle.
- [ ] Focused loops, desktop/backend full suites, harness, source closure, preflight, and final classified residue search are recorded.
- [ ] `engineering:code-review` Standards and Spec Compliance findings are resolved from the pinned fixed point.
- [ ] No compatibility shell, fake success, dormant provider switch, new orphaned deferral, or unowned screen/cloud-data deletion landed.
- [ ] Released-client compatibility is either green or explicitly stopped for a contract-sunset decision; it is never bypassed.
- [ ] Live resources remain untouched until explicit destructive approval; after approval, fleet/proxy/reaper/storage/IAM/state are removed in the safe order and zero-state evidence is captured.
- [ ] The Agent-VM failure class is marked dormant only in its separate post-decommission lifecycle PR.
