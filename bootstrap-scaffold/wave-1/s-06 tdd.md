# S-06 TDD plan — remove external product surfaces and keep one local assistant

## Plan record

| Field | Value |
|---|---|
| Status | `repository implementation complete; closeout repaired` — all product-deletion cycles landed in `ff528f8`; the fork's never-released evidence satisfies the route-removal gate, and the closeout removes generated file-scan/email dispatch plus the hosted-MCP-exclusive failure-class record that survived the product deletion |
| Wave | 1 |
| Slice | S-06 |
| Authorizing decisions | IR-015, IR-045 through IR-047, IR-050, IR-051, IR-106, IR-135, IR-141, IR-142, IR-212, IR-213, IR-256, IR-258 through IR-261, IR-310, IR-375, IR-512, IR-637, IR-816 through IR-818, IR-824, IR-938 |
| Protecting decisions | IR-002, IR-024, IR-025, IR-038, IR-041, IR-044, IR-052, IR-257, IR-260, IR-263 through IR-271, IR-311 through IR-315, IR-357 |
| Dependencies | None at the roadmap level. Coordinate the private tool-transport boundary with S-05; S-05 deletes `omi-tools-stdio` and `LocalAgentAPIServer`, while S-06 must preserve Pi's `OMI_BRIDGE_PIPE` path. |
| Coordinated owners | S-02 for direct wearable/Limitless hardware deletion; S-04 for repository-zombie cleanup that is not S-06-exclusive; S-05 for managed-Pi/private transport and Playwright; S-12 through S-16 for local-authority migrations; S-17 for remaining onboarding; S-18 for product billing migration; S-21 for broader shell/navigation; S-25 for shared worker and deployment closure |
| Target baseline | `origin/main`; implementation must fetch it and record the exact merge-base before the first RED |
| Research snapshot | Current checkout at `5ecb5e17aeab01955aff150a22054a957e15a48e`; re-run the inventory if the merge-base changes |
| Postcondition | The Mac presents one personalized assistant with explicit local attachments and keeps the existing Memory, Task, and Conversation behavior usable for their later local-authority slices; its managed-Pi bridge can still call the retained scoped tools, while Apps/marketplace, connector import/export, remote MCP, Calendar creation, public persona/sharing, broad indexing/FDA, Brain Map/knowledge graph, and their backend and deployment control planes have no live owner or executable residue. |

### Research baseline

- `python3 bootstrap-scaffold/validate-requirements-ledger.py` passes: 714 indexed rows, 714 detailed sections, all reviewed.
- This plan follows the current S-06 assignment in `deletion-map.md`. Older scaffold research treated sharing/persona as downstream; the live map now assigns IR-310, IR-637, IR-816, and IR-824 directly to S-06, so this plan includes them.
- The live managed-Pi path is `ChatProvider -> AgentRuntimeProcess -> Node kernel -> Pi adapter -> pi-mono-extension -> OMI_BRIDGE_PIPE -> ChatToolExecutor`. S-05's completed caller audit assigns the unused `omi-tools-stdio` path to deletion; S-06 protects only this verified Pi bridge.
- `DesktopAutomationBridge` is the non-production UI verification bridge on port 47777. It is not the Apple Events Automation permission and is not hosted MCP. Keep the bridge while deleting only actions/screens belonging exclusively to rejected products.
- `LimitlessDeviceConnection` is direct third-party wearable support rejected by IR-014 and owned for deletion by S-02. S-06 separately deletes only the hosted Limitless ZIP importer/job/push path under IR-824; it must neither preserve nor duplicate the hardware adapter.
- No tracked `web/**` or `plugins/**` source exists in this checkout, but workflows, public-build contracts, runtime-image manifests, deploy checks, and monitoring still name the old app/persona/plugins products. Treat those as live operational residue; do not recreate missing source merely to delete it.
- No product implementation or component suite was run while researching this plan. `engineering:implement` must establish the clean baseline before the first RED.

### Cycle-local released-contract gate — satisfied

S-06 removes app-client endpoints inherited from the upstream snapshot. This
fork has never shipped an application build or public API contract and has no
existing product users, as recorded in `FORK.md`. The upstream source tag is
provenance, not a released-client population for this product. Therefore the
removed S-06 operations were never released by this product and need no
version sunset, client migration, compatibility handler, or inherited baseline.

The satisfied boundary still enforces both requirements:

1. the rejected route and remote schema actually disappear — no dead 200/410 handler, deprecated compatibility shell, or stale generated client remains; and
2. the ordinary compatibility gate remains strict for retained APIs — no one-off S-06 allowlist or globally weakened comparison.

The retained contract starts at the post-S-06 app-client snapshot. Current
OpenAPI generation, generated Swift freshness, route-policy checks, compile
checks, and behavior tests remain strict for every retained operation. After
this product's first release, removing a released retained operation again
requires the normal explicit version/sunset transition.

`FC-denial-rendered-as-empty-success` guarded the deleted hosted MCP read
surface. Its canonical prevention module, behavioral test, and every scope
hint disappeared with that rejected product, so the closeout deletes the
exclusive registry definition instead of recreating a hosted MCP seam or
weakening generic failure-class validation. Git history retains the upstream
incident provenance.

## How this plan is executed

1. Start with [engineering:implement](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/implement/SKILL.md), using this file as the implementation spec. Begin with `make setup`, fetch `origin/main`, record the merge-base, revalidate the adopted public seam table, and build an exact tracked-file/caller inventory. Reopen planning only if a controlling IR or production seam changed. Work on the current branch; do not push or open a PR without a separate user request.
2. Use [engineering:tdd](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/tdd/SKILL.md) for every cycle. Write one behavioral test at an approved public seam, observe the intended RED, implement only enough GREEN for that tracer bullet, and only then continue. Do not write all tests first.
3. Apply [engineering:codebase-design](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/codebase-design/SKILL.md) to the surviving seams: one small local-assistant interface, explicit local authorities, and adapters only where a real external/system boundary remains. Do not preserve deleted products as generic registries, compatibility aliases, empty tabs, ignored fields, or future-facing extension points.
4. Refactor only after the deletion cycles are green. Commit locally in coherent, independently testable vertical slices and record the command/evidence for each.
5. Finish with [engineering:code-review](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/code-review/SKILL.md). Fetch and pin `origin/main`, use the three-dot diff and this plan as the spec, run Standards and Spec Compliance reviews separately, fix valid findings, and rerun affected checks.

## Outcome boundary and non-goals

S-06 removes six joined product families:

```text
marketplace
  Apps UI -> install/review/creator/admin -> app runtime hooks -> paid-app billing

connectors
  Home Connect/onboarding -> local connector automation -> OAuth/credentials
  -> backend integration routes/workers -> external providers

external task export
  backend task/conversation creation -> task_sync -> default provider
  -> Todoist / Asana / Google Tasks / ClickUp API or Apple Reminders mobile push

remote MCP
  hosted MCP/OAuth/API keys/SSE + outbound marketplace MCP
  (not the verified private managed-Pi bridge)

broad context products
  FDA -> broad file scan/index -> onboarding exploration -> Brain Map/KG

hosted publication/import
  public Persona + conversation/task sharing + Limitless ZIP importer

duplicate control planes
  backend-integration + plugins + persona public-build/deployment residues
```

The target retained path is deliberately smaller:

```text
one Mac assistant
  -> local AI Profile + local Memories/Tasks/Conversations
  -> explicit user-selected attachments
  -> managed Pi extension over OMI_BRIDGE_PIPE
  -> ChatToolExecutor
  -> retained scoped local tools
```

This slice does **not**:

- alter Windows code;
- delete `omi-tools-stdio`, `LocalAgentAPIServer`, or redesign managed Pi, Playwright, shell/file execution, or agent provider policy (S-05 owns those changes and has already classified both transports for deletion);
- delete the S-06 Browser Extension Settings/setup entry together with the underlying Playwright runtime; only the entry/setup surface is S-06, while runtime deletion is S-05;
- move all Memories, Tasks, Conversations, greeting, attachment, or lifecycle authority to the Mac (their later local-authority slices); it protects those target contracts and removes only S-06-owned obstacles;
- delete ordinary Firebase/product authentication, the canonical backend, managed STT/model routes, or product subscription billing;
- perform the Stripe-to-Dodo product-billing migration (S-18);
- redesign the surviving top navigation beyond removing S-06 entries (S-21);
- delete shared jobs or deployments merely because their names contain `integration`, `app`, or `plugin`; ownership must be proven;
- delete Limitless or other direct wearable hardware support (S-02 owns that already-approved deletion);
- delete Rewind foreground-application filtering, Rewind OCR/vector indexes, FTS indexes for retained local data, or `ProactiveAssistantsPlugin` merely because their names collide with Apps/plugins/indexing;
- create a replacement local knowledge graph, local connector framework, local marketplace, persona catalog, or generic plugin API;
- decommission a live cloud service without an inventory/traffic check and explicit user authorization.

## Action ledger

Before the first RED, expand each grouped row into exact tracked files and runtime resources at the pinned merge-base. Every discovered hit must be assigned to this ledger or recorded as a protected, shared, historical, generated, Windows, or adjacent-slice exception.

| Required stage | Exact behavior and source boundary |
|---|---|
| **KEEP AS IS** | The verified managed-Pi extension/`OMI_BRIDGE_PIPE`/`ChatToolExecutor` path; retained scoped tools; one personalized assistant; local AI Profile inputs; explicit local attachments; existing Memories/Tasks/Conversations and their relationships pending their later local-authority slices; Short-term/Long-term/Archive lifecycle; Memory grouping after Brain Map removal; Copy Transcript; automatic local commitment detection; Accessibility, Screen Recording, microphone, and notification permissions; `DesktopAutomationBridge`; canonical backend/auth; product subscription scaffold |
| **ADAPT** | Mac navigation and home modes to surviving destinations; Chat/session/draft/request state from app-selected to one-assistant; shared conversation/finalization/notification pipelines to remove app/connector hooks; tool manifest and generated Swift surfaces to retained tools/permissions; onboarding stage transitions to the retained permission/product path; local GRDB schema through forward drop migrations; shared payment router to remove paid-app/creator branches while preserving product billing; deployment/check manifests to the retained service graph |
| **DELETE** | Apps tab/catalog/install/review/creator/admin/persona/marketplace APIs and caches; paid-app billing and marketplace charges; first-party imports/exports and connector automation/OAuth/status/credentials/workers; complete Todoist/Asana/Google Tasks/ClickUp/Apple Reminders task export and automatic sync; external-agent setup writers; Calendar creation and hosted calendar links; Apple Events Automation setup; Full Disk Access and broad file indexing; Brain Map and local/hosted KG; hosted/public MCP/OAuth/API keys/SSE and outbound MCP; public Persona; public conversation/task sharing; Limitless ZIP import; S-06-exclusive backend-integration/plugins/persona deployment resources |
| **SIMPLIFY / OPTIMIZE AFTER** | After all RED/GREEN cycles pass, remove orphan identifiers, registries, models, compatibility decoders, empty states, dead caches, generic selectors with one surviving choice, and duplicate adapters. Historical migrations stay registered; only a new forward migration drops rejected tables. |
| **ACCELERATE AFTER** | `none` planned. Record focused-loop timing from `dev-feedback.py` and backend focused tests. Propose acceleration only if S-06 produces a measured local bottleneck. |
| **AUTOMATE LAST** | `none` new planned. Adapt existing route/OpenAPI/tool-surface/runtime-image/workflow checks in their enforced lanes. Do not add a permanent residue scraper without a real escaped defect and an existing CI audience. |
| **OUT OF SCOPE / DEFERRED** | Windows; S-02 direct wearable/Limitless hardware deletion; S-05 runtime/transport/Playwright work; later local-authority implementations; remaining onboarding; Dodo migration; unrelated shell redesign; shared-worker consolidation; product rebrand; unrelated providers and hardware |

### Important mixed-file rules

| Mixed owner | Required treatment |
|---|---|
| `ChatToolExecutor` and `omi-tool-manifest.ts` | Remove only `fill_cloud_connector_form`, `create_calendar_event`, `scan_files`, `save_knowledge_graph`, rejected permission kinds, prompts, and exclusive handlers. Preserve the file, retained tools, and generated-source workflow. Never hand-edit `Desktop/Sources/Generated/**`. |
| `DesktopAutomationBridge.swift` | Preserve the bridge and its health/control contract. Delete only S-06 screen/action cases after their production surface disappears; retain actions for Memories, Tasks, Conversations, attachments, onboarding, and other accepted paths. |
| `ChatProvider` | Delete app selection/catalog identity and app-partitioned draft/session/message/file behavior. Preserve the one-assistant chat path and local agent request, greeting, journal, attachments, and retained tool flow. |
| `DashboardPage` / `HomeStatusStore` | Delete Connect tray/popup/status/probe actions. Preserve Home hub/chat and unrelated health/account/status behavior. |
| `RewindDatabase` | Do not rewrite or remove applied `createIndexedFiles` or `createLocalKnowledgeGraph` migration identities. Add a forward idempotent migration that drops only `indexed_files`, `local_kg_edges`, and `local_kg_nodes`; prove retained tables and data survive. |
| `payment.py` | Remove app subscription, marketplace charge, creator/Connect, and app-specific webhook branches. Preserve the ordinary product subscription and account entitlement scaffold until S-18. |
| conversation/finalization/notification jobs | Remove app integration, connector, public-share, and importer branches only. Preserve normal retained processing owned by other slices; do not delete a shared worker until its remaining callers are inventoried. |
| `task_integrations.py`, `task_integrations_ops.py`, `task_sync.py`, action-item sync routes/storage, candidate integration outbox/drain machinery, and user integration storage | Delete the complete four-provider OAuth/write path, default-integration state, automatic single/batch export, candidate integration outbox/lease/drain path, and Apple Reminders push plus bidirectional pending/batch-sync branch under IR-938. Preserve ordinary local task and candidate creation/acceptance plus later S-13 authority work; do not create a generic replacement integration seam. |
| `backend-integration`, `plugins`, persona public build | Delete repo definitions and live services only when their owners are exclusively rejected. Shared release, account-deletion, monitoring, and traffic scripts must be narrowed rather than blindly deleted. Live decommission is a separate explicit sign-off gate. |

## Current codeflow and ownership inventory

### 1. Apps, marketplace, and persona identity

1. `SidebarNavItem.apps`, `DesktopTopBar`, `TopNavigationRoutes`, and `DesktopHomeView` make Apps a first-class Mac destination.
2. `AppProvider`, `AppsPage`, `AppsPageHeaderControls`, and `APIClient+Apps` fetch/catalog/filter/install/test/review Apps and load state at startup.
3. `ChatProvider.selectedAppId` partitions sessions, messages, files, drafts, greetings, and UI identity even though normal managed-Pi execution already uses the local agent path.
4. `backend/routers/apps.py`, `database/apps.py`, app models/utilities, app API keys/grants, app-generation prompts, caches, admin/creator routes, and app hooks in shared chat/conversation/notification pipelines keep the marketplace executable.
5. `payment.py` mixes paid-app/creator billing with retained product subscription behavior, so it must be split by behavior rather than deleted wholesale.

### 2. Connectors and external setup

1. `HomeStageMode.connect`, the Dashboard Connect tray, `HomeStatusStore`, and non-production bridge actions expose connector setup/status.
2. Onboarding data-source/export steps and local readers/exporters/import runners automate Apple Notes, Gmail, Google Calendar, Notion, X, and other external systems.
3. Backend `integrations`, `integration`, `task_integrations`, `google_calendar`, `calendar_onboarding`, `x_connector`, and related OAuth/status/credential code provide the hosted half.
4. App/connector hooks also enter normal chat, conversation processing/finalization, listen/pusher, and notification jobs. Those shared owners must survive minus the rejected hook.
5. IR-938 makes `task_integrations` exact rather than a generic connector label: its four OAuth providers, user/default metadata, task-write APIs, automatic action-item/task-intelligence/conversation export, Apple Reminders push, `/v1/action-items/pending-sync`, `/v1/action-items/sync-batch`, export fields, database helpers, and exclusive tests/contracts all delete. Candidate acceptance also writes an integration-only `candidate_integration_outbox`; `candidate_service` leases/retries it, `/v1/candidates/integrations/drain` schedules it, and a Firestore index, generated binding, tests, and `task_candidate_lifecycle` invariant cover it. Delete that side-effect machinery while preserving ordinary local Tasks and candidate acceptance for S-13.

### 3. Hosted/public MCP versus the private Pi bridge

1. Backend `mcp.py`, `mcp_sse.py`, OAuth templates/tables, API-key/scopes/data adapters, `.well-known`, `/authorize`, `/token`, and SSE make remote MCP a public product.
2. Marketplace Apps can register outbound MCP and third-party API surfaces.
3. The retained managed Pi does not call those hosted routes. It uses the packaged Pi extension and `OMI_BRIDGE_PIPE` to reach Swift `ChatToolExecutor`.
4. `omi-tools-stdio.ts` still exists, but S-05's caller audit found no retained production consumer and assigns it to deletion. S-06 must leave that work to S-05 and protect the different `OMI_BRIDGE_PIPE` path. A raw `mcp` residue search is therefore insufficient proof.

### 4. Calendar creation and Apple Events Automation

1. The canonical tool manifest publishes `create_calendar_event`; generated Swift surfaces, capability prompts, executor/client code, and backend `/v1/tools/calendar-events` complete the route.
2. Conversation details also retain hosted Google Calendar links.
3. Apple Events permission UI/state/probes, `NSAppleEventsUsageDescription`, and the Apple-events entitlement survive from external app automation. Accessibility is separately required and must remain.
4. `DesktopAutomationBridge` is unrelated test/dev infrastructure and remains.

### 5. FDA, indexing, and Brain Map/KG

1. Onboarding requests Full Disk Access, calls `scan_files`, populates `indexed_files`, and starts a parallel exploration prompt.
2. `FileIndexerService`, indexing views/records, SQL annotations, status/analytics, rescan settings, and prompts maintain broad machine indexing.
3. The manifest publishes `save_knowledge_graph`; `KnowledgeGraphStorage`, `local_kg_nodes`, and `local_kg_edges` feed Brain Map/Memory Atlas views and navigation.
4. Backend `routers/knowledge_graph.py`, database/LLM graph modules, jobs, routes, generated API clients, gateway config, tests, and deployment/config assets preserve a second hosted graph.
5. Local Memories and Conversations are independent retained products; they are not permission to invent a replacement memory-to-graph generator.

### 6. Hosted sharing and import

1. Conversation Copy Link/visibility/token UI and backend conversation/public-chat routes create the hosted conversation-sharing product.
2. Task share tokens, public preview/import, recipients, Redis state, and notification paths create task sharing.
3. Public Persona/clone/website/workflow paths publish assistant identity outside the retained private AI Profile.
4. The Limitless ZIP upload/parser/job/cancel/delete/push path imports hosted conversations. It is distinct from direct Limitless device support, which is rejected and belongs to S-02.

### 7. Duplicate deployments

1. `gcp_backend.yml`, `gcp_backend_auto_dev.yml`, runtime environment manifests, release-vector/preflight/traffic scripts, monitoring, OpenAPI, and account-deletion lists still treat `backend-integration` as a deployable service.
2. `gcp_plugins.yml`, `runtime_images.json`, deployment concurrency checks, and monitoring preserve the zombie plugins service even where its image source is absent.
3. `gcp_personas.yml`, public-build contracts, and persona configs preserve a public persona deployment whose product is rejected.

## Requirements-backed public seams

These observable seams are the adopted trace to the authorizing and protecting
decisions. Revalidate them at the pinned baseline; tests exercise production
behavior through these interfaces, not source-string order.

| Seam | Contract to prove | Primary test/real-path surface |
|---|---|---|
| Mac destination model | Main navigation contains the retained destinations but no Apps; Memory grouping contains Memories and Conversations but no Brain Map; Home has hub/chat but no Connect. Removed deep links/actions fail closed to an existing retained destination. | `SidebarNavItem.mainItems`, `TopNavigationRoutes`, `MemoryHubDestination`, `HomeStageMode`, bridge screen/action registries, existing layout/routing tests, named bundle |
| One-assistant chat | A new local chat has one personalized assistant, can attach an explicitly selected local file, and sends the normal agent request without an app/persona/marketplace identifier. Draft/session behavior is not partitioned by a deleted app. | `ChatProvider`/`AgentClient` public request and state behavior; local-agent hermetic flow; named-bundle Chat with `home_attach` |
| Retained local tool bridge | A retained tool call travels through packaged Pi extension -> `OMI_BRIDGE_PIPE` -> `ChatToolExecutor` and returns a typed result. The public manifest does not expose Calendar creation, broad scanning, KG writes, or rejected permissions. | canonical TypeScript manifest, generator check, Pi extension tests, agent logic harness, one real retained tool call |
| Onboarding/permission state | Onboarding advances, resumes, skips, and reports progress without connector, Automation, FDA, file-scan, or KG stages. Accessibility and other retained permissions still work. | onboarding coordinator/state-machine behavior plus named-bundle first-run/bridge exercise |
| Local data continuity | Memories, Tasks, and Conversations remain navigable and related; Memory lifecycle/category/filter behavior retained by protecting decisions still works; Copy Transcript works; local commitment metadata remains without Calendar creation. | public view-model/storage APIs, GRDB migration test, existing Memory/Task/Conversation flows |
| Canonical backend route surface | Removed marketplace, connector, task-integration/export, remote-MCP, KG, sharing, Calendar-creation, and Limitless-import endpoints are absent from FastAPI/OpenAPI and return 404; retained auth, product subscription, model/STT, and ordinary product routes remain registered. | real `app.routes`/OpenAPI/TestClient boundary and retained endpoint smoke tests |
| Deployment graph | Retained services render and pass release checks; `backend-integration`, plugins, and persona-public-build have no deployable workflow/image/config/monitoring/secret owner after exclusive ownership is proven. | existing workflow, runtime-env, runtime-image, release-vector, deployment-concurrency, monitoring, and public-build contract checks |

The same requirements trace establishes these design choices:

- “one assistant” removes `selectedAppId` and app/persona partitioning rather than replacing them with a constant default app ID;
- hosted routes are removed rather than returning a compatibility payload or feature-disabled response;
- historical GRDB migrations remain, followed by a forward drop migration; fresh and upgraded databases converge to the same retained schema;
- retained private tool transport is protected by behavior, not by assuming every file named MCP is retained;
- route absence and manifest contents are legitimate public interfaces; source-string/order checks are only supplemental residue evidence.

## Interface design after deletion

- **Chat** exposes one local-assistant session/request model. Personalization comes from the local AI Profile and Memories; an App or Persona identity is not an input.
- **Attachments** expose explicitly user-selected local resources through the retained agent boundary. There is no background disk crawler or connector import behind the interface.
- **Tools** have one canonical manifest in `agent/src/runtime/omi-tool-manifest.ts`. Generated Swift enums/capabilities/executors are outputs. A real retained external/system boundary or test fake may implement the interface; rejected tools do not remain as disabled cases.
- **Data** keeps separate deep local modules for Memories, Tasks, and Conversations. S-06 removes KG/share/connector projections without merging these authorities into a broad generic “context” store.
- **Backend** keeps a small canonical route set. It does not keep a generic marketplace/integration/MCP registry for hypothetical future products.
- **Permissions** name the OS capability actually retained. Accessibility is not Automation; explicit file selection is not Full Disk Access.
- **Deployment** lists services that still have live product callers. An empty workflow, orphan image record, monitoring-only service name, or compatibility environment variable is not a retained interface.

## Ordered TDD implementation cycles

### Cycle 0 — pin the baseline and exact inventory

This is setup, not a passing characterization-test substitute.

1. Run `make setup`, fetch `origin/main`, and record `git merge-base HEAD origin/main`.
2. Run the existing focused keep-boundary tests for normal Chat, attachments, Pi bridge/tools, onboarding, Memories, Tasks, Conversations, product billing, auth, and deployment manifests.
3. Expand the ledger into an exact file/caller/resource inventory. Classify ambiguous tokens (`app`, `integration`, `automation`, `mcp`, `Limitless`, `graph`) before deletion.
4. If a keep boundary lacks a behavioral test, make the first deletion at that seam produce the RED and then restore only the retained behavior; do not add a test that already passes and call it TDD.
5. Compare every S-06 route operation with the merge-base released app-client contract and in-tree client callers. Record never-released operations or prepare the adopted release-level version/sunset predecessor change before Cycle 3; do not delay safe Mac-only Cycles 1-2 while that evidence is assembled.

### Cycle 1 — one-assistant Chat and explicit attachments

**RED:** Through the public Chat request/state seam, start a new session, attach an explicit local file, and assert that the local-agent request preserves that attachment and personalized greeting without an app/persona/marketplace identifier or app-partitioned draft/session. Observe failure on the current `selectedAppId` contract.

**GREEN:** Remove app selection from `ChatProvider`, request/session/message/file/draft identity, startup catalog fetch, greeting forks, and related persistence/defaults. Preserve the normal agent request, local greeting, journal, explicit attachment, failure presentation, and retained tool path.

**Verify before continuing:** focused ChatProvider/agent request/attachment tests, local agent hermetic chat flow, Swift compile, and a scoped residue search for app IDs in the normal Chat path.

### Cycle 2 — remove the Mac Apps destination and marketplace UI

**RED:** At the navigation surface, assert the retained main destinations and deep-link behavior with no Apps route. A stale Apps route/action must fail closed to a retained destination rather than opening an empty shell.

**GREEN:** Remove `SidebarNavItem.apps`, top-bar route/case, `AppsPage`, `AppsPageHeaderControls`, `AppProvider`, `APIClient+Apps`, catalog/startup loading, install/review/test/admin UI, notification names, assets used only there, and Apps e2e flows. Delete exclusive Apps tests; keep the new navigation behavior test.

**Verify before continuing:** `TopNavigationBarLayoutTests`, affected window/routing tests, bridge registry checks, Swift compile, and a named-bundle navigation smoke.

### Cycle 3 — remove backend marketplace, third-party App APIs, and paid-app billing

**Precondition:** the approved released-OpenAPI product-sunset mechanism is recorded in this plan and has a passing contract test. Do not preserve dead routes or weaken the general compatibility check to get this cycle green.

**RED:** At the FastAPI route/OpenAPI boundary, assert that the complete Apps/developer-marketplace endpoint families are absent while retained auth, ordinary Chat, and product subscription routes remain. Add one retained conversation/finalization assertion showing no app callback is invoked.

**GREEN:** Unregister/delete Apps routers, database/models/utilities, App/developer API keys and grants, creator/admin/review/install/generation/manifest surfaces, outbound marketplace MCP, app caches, app callbacks in shared pipelines, and marketplace-only tests/docs. Preserve the public-Persona closure for Cycle 15. Split `payment.py`: remove paid-app, Connect/creator, app-subscription, and app-specific webhook behavior; preserve product billing/entitlement code for S-18.

**Verify before continuing:** focused route/OpenAPI, payment, auth, ordinary chat/conversation/finalization, notification, and import-boundary tests; backend type/import checks; route residue inventory.

### Cycle 4 — remove Home Connect without harming Home hub/chat

**RED:** Through `HomeStageMode` and bridge actions, assert that hub and chat still render/navigate, `home_attach` still attaches a local file, and Connect is neither selectable nor addressable.

**GREEN:** Remove `.connect`, Connect tray/card/popup/status/probe state and actions from Dashboard, `HomeStatusStore`, `DesktopHomeView`, and bridge registries. Preserve unrelated Home status/account/runtime data and the hub/chat layout.

**Verify before continuing:** Home presentation/regression tests, `home-stage` e2e adapted to hub/chat, attachment flow, bridge action inventory, and named-bundle Home exercise.

### Cycle 5 — remove connector onboarding stages

**RED:** Drive the onboarding state machine through the public coordinator and prove forward/back/skip/resume/progress behavior with no data-source, connector, import/export, or external-agent setup stage. At the Settings navigation surface, prove the Browser Extension setup card is absent while unrelated retained settings remain. The test must fail on the current stage/settings graph.

**GREEN:** Remove connector/export/data-source screens, coordinator cases, `fill_cloud_connector_form`, prompt/tool calls, persisted progress keys, setup writers, status probes, the Browser Extension Settings card/setup copy, and exclusive assets/tests. Preserve the retained onboarding lifecycle, timing, progress, auth, name/profile inputs, and retained OS permissions. Do not delete the S-05-owned Playwright runtime in this cycle.

**Verify before continuing:** focused onboarding coordinator and persistence tests plus non-production named-bundle onboarding smoke. Do not add sleeps or live providers to CI.

### Cycle 6 — delete connector runtimes, OAuth, credentials, and hosted workers

**RED:** At public backend route and retained-auth seams, assert that first-party connector/OAuth/status routes, every `/v1/task-integrations` plus `/v2/integrations/*/callback` route, `/v1/action-items/pending-sync`, `/v1/action-items/sync-batch`, and `/v1/candidates/integrations/drain` are absent while ordinary product sign-in/auth and local Task behavior remain. Through retained action-item, conversation-processing, and candidate-acceptance seams, prove task creation/finalization/candidate acceptance succeeds without external task export, sync-request state, candidate integration outbox rows, or Apple Reminders push.

**GREEN:** Delete local connector readers/exporters/import runners and automation for Apple Notes, Gmail, Google Calendar, Notion, X, and equivalent sources; remove backend integration/calendar-onboarding/X routes, registries, OAuth grants, credential stores, webhooks, connector status, and exclusive workers/tests/config. Under IR-938, delete `task_integrations` routes/registration, `task_integrations_ops.py`, `task_sync.py`, provider credentials/default/list/project state, automatic action-item/task-intelligence/conversation export hooks, and the complete Apple Reminders push/pending-sync/sync-batch path. Remove its `SyncBatch*`/`PendingSyncResponse` models, database helpers, `sync_requested`/`exported`/`export_date`/`export_platform`/`apple_reminder_id` fields where exclusive, generated bindings, route-policy entries, mobile-lifecycle cases, and focused tests/docs. Delete integration-only outbox writes in both candidate/task and workstream acceptance, `candidate_integration_outbox`, its claim/complete/list helpers and exports, `candidate_service` dispatch/drain code, `/v1/candidates/integrations/drain`, its Firestore index/registry entry, generated binding, focused lifecycle/workstream/router tests, and only the corresponding workflow-invariant clause. Preserve candidate acceptance without that side effect. Narrow shared notification/finalization/listen/pusher jobs rather than deleting them.

**Verify before continuing:** route/OpenAPI/auth tests, ordinary local task creation and candidate acceptance, ordinary finalization/notification behavior, import isolation, updated workflow contracts, and no unexplained live connector/task-provider credential, automatic-sync, candidate integration outbox/index/drain, or Apple Reminders export residue.

### Cycle 7 — remove Calendar creation and hosted calendar links

**RED:** Assert through the canonical tool manifest that `create_calendar_event` is unavailable while retained Task tools/date fields work. At Conversation Detail, prove locally detected commitment metadata remains but no hosted Google Calendar link/action appears. At FastAPI, assert Calendar-creation routes are absent.

**GREEN:** Remove the manifest entry, prompts, executor/client handlers, backend tool and calendar models/routes, hosted-link UI/state, OAuth residue exclusive to calendar creation, generated clients, and exclusive tests. Regenerate tool surfaces from the TypeScript manifest. Preserve local Tasks, their due dates/reminders, meeting detection, conversation commitment metadata, and unrelated Calendar-derived system behavior if separately retained.

**Verify before continuing:** tool-surface generator/check, Pi extension tests, Task and Conversation Detail tests, backend route tests, Swift compile, and a retained Task tool call.

### Cycle 8 — remove Apple Events Automation permission

**Precondition:** the Cycle 6/7 inventory and S-05 coordination prove no retained product caller requires Apple Events. `DesktopAutomationBridge` is explicitly excluded.

**RED:** Through the permission public seam, assert that Automation is not a requestable/status capability and Accessibility still reports/requests normally. Exercise the retained microphone recovery behavior without AppleScript.

**GREEN:** Remove Automation permission enum/state/UI/probes/tool-manifest cases, external-app setup usage, `NSAppleEventsUsageDescription`, and the Apple-events entitlement. Replace any retained microphone-reset guidance with the direct supported Settings/instruction path selected by IR-050. Do not touch `DesktopAutomationBridge`.

**Verify before continuing:** permission behavior tests, onboarding/settings flows, entitlements/plist inspection, app signing/build checks, and named-bundle Accessibility/microphone exercise.

### Cycle 9 — remove Full Disk Access and broad file indexing

**RED:** Through the permission and attachment seams, assert that FDA/`scan_files` is unavailable while an explicitly selected file remains attachable. Through an upgraded-database test, assert the rejected index table disappears while retained Memory/Task/Conversation rows survive.

**GREEN:** Remove FDA enum/state/UI/probes/copy, file-scanning startup/onboarding/settings paths, `FileIndexerService`, records/views/policies, `scan_files`, prompts/SQL annotations, rescan/backfill/analytics, and exclusive tests/assets. Add an idempotent forward GRDB migration dropping `indexed_files`; keep historical migration registration.

**Verify before continuing:** permission, attachment, tool-manifest, migration/retained-row, onboarding, and Swift tests; named-bundle explicit attachment; no background scan/file access in logs.

### Cycle 10 — remove Brain Map and the complete knowledge graph

**RED:** At `MemoryHubDestination`, assert the retained Memories/Conversations grouping and existing selection persistence without Brain Map. At local DB upgrade, assert KG tables are dropped and retained Memory lifecycle data survives. At backend routes, assert KG endpoints are absent while retained memory/task/conversation routes selected by other owners remain unchanged.

**GREEN:** Remove Brain Map/Atlas navigation/rendering/interaction/assets/analytics, `KnowledgeGraphStorage` and records, `save_knowledge_graph`, onboarding exploration prompts, backend KG router/database/LLM/jobs/gateway config/generated clients, and exclusive tests. Add the forward drop of `local_kg_edges` then `local_kg_nodes`; do not add a replacement graph producer.

**Verify before continuing:** navigation, Memory hub, retained Memory lifecycle/category/search, migration, route/OpenAPI, generator/tool-surface, and ordinary conversation tests; named-bundle Memories/Conversations navigation.

### Cycle 11 — simplify retained Memories without deleting their lifecycle

**RED:** Through production Memory navigation/filter/category/layer APIs, assert that the grouped destination contains Memories and Conversations, categories omit Workflow, and no This device or Public/Private visibility action can be produced, while Short-term/Long-term/Archive, retained category multi-selection/search, delete/Undo, and source-conversation navigation still work.

**GREEN:** Remove device-scope state/query/header/capability/retry/telemetry, memory visibility controls/mutations/public projection, and the Workflow category from Mac UI/models, backend routes/fields owned exclusively by those products, generated clients, automation actions, and exclusive tests. Preserve provenance needed for local source relationships and every IR-260 lifecycle type/transition/audit/recovery surface. Do not implement S-12's local authority migration here.

**Verify before continuing:** Memory hub/destination, category/filter/search, lifecycle/layer, deletion/Undo, source-conversation navigation, route/OpenAPI, generated-client, and migration tests; named-bundle Memory exercise.

### Cycle 12 — remove hosted/public MCP while proving the private Pi tool path

**RED:** At the backend route/OpenAPI surface, assert that `.well-known`, MCP OAuth, API-key, SSE, and hosted data/tool routes are absent. In the same cycle, drive one retained tool call through Pi extension -> `OMI_BRIDGE_PIPE` -> `ChatToolExecutor` so a mistaken private-bridge deletion fails the test.

**GREEN:** Delete hosted MCP routers, OAuth templates/tables/validators, API key/scopes/grants/data adapters, SSE, public schemas, smoke scripts, environment/deployment config, outbound MCP clients already orphaned by marketplace deletion, generated contracts, and exclusive tests/docs. Preserve the verified Pi bridge. Leave S-05's already-decided `omi-tools-stdio` and `LocalAgentAPIServer` deletions to S-05 with exact handoff files.

**Verify before continuing:** route/OpenAPI absence, agent tool-surface suite, Pi extension tests, agent-logic harness, retained tool real path, and classified `mcp` residue report.

### Cycle 13 — remove public conversation sharing

**RED:** Through Conversation row/detail actions, assert Copy Transcript still resolves local detail and copies text, while Copy Link/public visibility/share actions are unavailable. At FastAPI, assert share/public-chat/token routes are absent.

**GREEN:** Remove Copy Link/public visibility/token UI, public shared chat/conversation routes, Redis/share persistence, public models, gateway lane/config/benchmarks, generated clients, notifications, and exclusive tests. Preserve local Conversation navigation/edit/delete, source-linked Task cascade, and Copy Transcript.

**Verify before continuing:** Conversation row/detail behavior, Copy Transcript, route/OpenAPI, gateway configuration, and local deletion-cascade tests; named-bundle Copy Transcript exercise.

### Cycle 14 — remove task sharing and public task import

**RED:** Through the local Task surface, create/edit/complete a Task and assert no Share/public-preview/import action is offered. At FastAPI, assert task-share/token/public-import routes are absent while retained local Task behavior remains green.

**GREEN:** Remove share tokens, public preview/import, recipient state, Redis records, share notifications, generated clients, UI/actions, and exclusive tests. Preserve local Task CRUD, due dates, reminders, recurrence, and conversation-source relationships.

**Verify before continuing:** Task CRUD/source-cascade tests, route/OpenAPI, notification behavior, Swift compile, and named-bundle Tasks flow.

### Cycle 15 — remove public Persona and Limitless ZIP import

**RED:** At the route/navigation/import-job surfaces, assert that Persona clone/public/workflow and Limitless ZIP upload/job/cancel/delete endpoints are absent while private AI Profile personalization and ordinary local Conversations remain green. Do not use direct Limitless hardware parsing as an S-06 keep fence; S-02 deletes it.

**GREEN:** Delete public Persona models/routes/UI/web assets/workflows and Limitless ZIP parser/import jobs/Firestore/push/generated clients/no-op Mac bindings/exclusive tests. Keep local AI Profile history/editor/consumers, one assistant, and ordinary local conversation creation. Leave deletion of hardware `LimitlessDeviceConnection` to S-02.

**Verify before continuing:** AI Profile/personalized greeting, local Conversations, route/OpenAPI/import-isolation, push/notification, and generated-client tests; classify direct Limitless hardware residue to S-02 and hosted import residue to S-06.

### Cycle 16 — close duplicate deployment and operator surfaces

**RED:** Adapt existing enforced deployment-manifest tests to expect only retained service owners. Prove that `backend-integration`, plugins, and persona public-build cannot render, deploy, receive traffic, require secrets, or appear as current monitored services after their product owners are gone.

**GREEN:** Remove S-06-exclusive entries from backend deploy workflows, auto-dev workflows, runtime env/image manifests, release-vector/preflight/traffic/account-deletion scripts, OpenAPI/config generators, monitoring dashboards/alerts, public-build configs, concurrency checks, and docs. Delete whole workflows/images only when no retained owner remains; narrow shared scripts otherwise.

**Live decommission gate:** repository cleanup may be implemented and tested locally. Before deleting or redirecting a live Cloud Run service, image, secret, domain, OAuth client, collection, or traffic target, capture live inventory/traffic/retention evidence and obtain explicit user authorization. Code merge is not live-deletion approval.

**Verify before review:** runtime-env render/validation, runtime-image closure, workflow/deployment-concurrency, release-vector, public-build, monitoring/config, OpenAPI, and pre-deploy checks; no unexplained service/secret/config residue.

## Review and simplification — only after GREEN

Do not refactor while a cycle is RED. After Cycle 16 is green:

1. Remove empty registries, one-case selectors, retired IDs, compatibility decoders, notification names, cache keys, feature flags, generic connector/MCP adapters, and dead models left by the vertical deletions.
2. Apply the deletion test from `engineering:codebase-design`: the one-assistant/attachment/tool interfaces should remain understandable without any deleted product vocabulary. If an interface exists only for a hypothetical future marketplace, connector, persona, or graph, remove it.
3. Check locality: local Profile/Memories/Tasks/Conversations own their data; explicit attachments own file access; Pi owns agent orchestration; `ChatToolExecutor` owns retained Swift tools; the canonical backend owns only retained hosted capabilities.
4. Delete tests whose sole subject was removed. Keep/adapt tests at surviving public seams. Label any unavoidable static residue check as supplemental, not behavioral coverage.
5. Update `desktop/macos/AGENTS.md`, `backend/AGENTS.md`, architecture docs, setup/env/service maps, API docs, tool docs, and a desktop changelog fragment for user-visible removals. Do not restore unrelated absent docs merely to satisfy this slice; report baseline repository blockers explicitly.
6. Invoke `engineering:code-review` with the freshly pinned `origin/main` fixed point and this file as the specification. Run independent Standards and Spec Compliance reviews, preserve their separate findings, fix valid issues, and repeat until both are clear.

## Verification and closure evidence

Implementation is not complete until the PR/commit evidence records commands, exit codes, and concise results. A skipped real path is a disclosed blocker, not an implied pass.

### Focused loops

Use the repository runners so tests are discovered by their enforced lanes. Exact filters/files follow the tests selected during each RED cycle.

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py

cd desktop/macos
./scripts/dev-feedback.py --once swift '<approved XCTest suite or method>'
./scripts/test-tool-surfaces.sh
./scripts/agent-logic-harness.sh --node-only
./scripts/agent-logic-harness.sh --swift-only
xcrun swift build -c debug --package-path Desktop

cd ../../../backend
BACKEND_UNIT_TEST_FILE_LIST=/tmp/s06-backend-tests.txt bash test.sh
```

The focused backend list must contain only discovered S-06 public-contract and retained-path test files, one repo-relative path per line. Do not bypass `backend/test.sh` with an undiscovered test location.

Record the per-cycle time reported by `dev-feedback.py` and the backend focused run. S-06 has no preselected speed target; the measurements decide whether any later acceleration work is justified.

### Full component and repository checks

```bash
cd desktop/macos
bash test.sh

cd ../../../backend
bash test-preflight.sh
bash test.sh

# After the approved sunset mechanism restores/updates the released contract:
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check ../docs/api-reference/app-client-openapi.json
python scripts/generate_ts_openapi_types.py --check
python scripts/generate_swift_openapi_types.py --check
python scripts/validate-backend-runtime-env.py --env dev --check-workflows
python scripts/validate-backend-runtime-env.py --env prod --check-workflows

cd ..
make runtime-image-source-closure
python3 .github/scripts/check-deployment-concurrency.py
python3 .github/scripts/check_public_build_contract.py
make preflight
scripts/pr-preflight --suggest
```

Before a `fix:` commit or PR body, follow the repository Failure-Class and invariant rules. Before a PR, draft its body and run `scripts/pr-preflight --pr-body-file /tmp/pr-body.md`. Do not weaken a failing manifest check; distinguish a pre-existing baseline failure from an S-06 regression.

### Named-bundle real-path proof

Never launch or restart `/Applications/Omi.app` or `Omi Beta.app`.

```bash
cd desktop/macos
OMI_APP_NAME=omi-s06 ./run.sh --yolo --fast-only
./scripts/omi-ctl health
./scripts/omi-ctl screens
./scripts/omi-ctl actions
./scripts/omi-ctl state
```

Exercise and capture evidence that:

1. Home opens with hub/chat and no Connect surface.
2. Main navigation has no Apps; Memory grouping has Memories/Conversations and no Brain Map.
3. A new one-assistant Chat receives its personalized greeting.
4. `home_attach` or the visible attachment picker attaches one explicitly selected local file and the agent can use it.
5. One retained scoped tool call completes through managed Pi and `ChatToolExecutor`.
6. Onboarding has no connector/import/export/Automation/FDA/scan/KG stage; retained Accessibility and other required permissions still behave correctly.
7. Memories, Tasks, and Conversations open; retained lifecycle/filter/category behavior under protecting IRs still works, and creating a task does not call an external task provider.
8. Copy Transcript works; no conversation/task public-share action exists.
9. A locally detected commitment remains readable without Calendar creation.
10. Logs show no background broad file scan, connector status loop, marketplace fetch, or hosted MCP call.

### Backend/offline proof

- Start the documented local backend or hermetic app fixture with network providers replaced only at real external boundaries.
- Query the OpenAPI/route table and representative removed families; they must be absent/404, not compatibility responses.
- Exercise representative retained auth, product subscription/entitlement, ordinary chat/conversation processing, and required model/STT health contracts.
- Run without third-party connector credentials and without network access to former connector/marketplace/MCP services. Startup and retained local flows must not wait for or probe them.
- Confirm no live OAuth grant, webhook, queue/task, collection, Redis namespace, bucket/object prefix, API key, marketplace charge, remote MCP schema, indexer, image, service, metric, or alert remains owned solely by S-06.

### Residue search and classification

Search tracked source, generated artifacts, workflow/configuration, tests/fixtures, and current docs. Do not declare closure from a raw zero count; classify ambiguous survivors.

```bash
git grep -n -i -E 'apps marketplace|selectedAppId|persona|connector|notion|gmail|x_connector|task_integrations|task_sync|todoist|asana|google.tasks|clickup|apple.reminders|pending-sync|sync-batch|sync_requested|apple_reminder_id|export_platform|export_date|candidate_integration_outbox|candidates/integrations/drain|calendar[_ -]?event|copy link|public[_ -]?share|limitless.*(zip|import)|knowledge[_ -]?graph|brain map|indexed_files|full disk access|apple events|mcp|backend-integration|gcp_plugins|gcp_personas'
```

Expected legitimate classes include:

- ordinary macOS/application uses of “app”;
- `DesktopAutomationBridge` despite removal of Apple Events Automation;
- the S-05-owned private transport files until S-05 resolves them;
- direct Limitless hardware support only while the S-02 branch has not yet landed; it is an explicit S-02 deletion handoff, never a retained product exception;
- retained local relationship/semantic-search concepts that are not a KG product;
- historical changelogs and immutable migration names, with the new drop migration making the live schema clean;
- shared scripts narrowed to retained services, with an explicit reason for each surviving generic term.

There may be no unexplained live S-06 UI, route, collection, OAuth grant, webhook, worker, marketplace charge, connector credential, remote MCP schema, indexer, deployment, test fixture, metric, alert, or current product claim.

## Closure checklist

- [ ] Every adopted public seam and the five design choices below the seam table were revalidated at the pinned baseline.
- [ ] Exact merge-base and complete caller/resource inventory recorded.
- [ ] Each cycle showed an intended behavioral RED before its minimum GREEN.
- [ ] Kept one-assistant, attachment, Pi/tool, local-data, permission, backend, billing, and hardware paths pass.
- [x] All S-06 product owners and every exclusive downstream artifact are removed, including stale generated file-scan/email dispatch and the hosted-MCP-only failure-class record.
- [ ] Historical DB migrations remain and forward migration tests prove retained data survives rejected-table drops.
- [ ] No compatibility shell, ignored field, empty destination, disabled route, or speculative replacement framework remains.
- [ ] Focused and full Desktop/backend/repository checks pass, or exact baseline blockers are disclosed.
- [ ] Named-bundle user path and retained Pi tool call were exercised without touching production bundles.
- [ ] Offline/credential-free startup and removed-route behavior were exercised.
- [ ] Residue and live-resource inventories are classified with no unexplained S-06 owner.
- [ ] Docs and desktop changelog fragment match the surviving product.
- [ ] Risky live decommission actions received explicit user authorization and have live evidence.
- [ ] `engineering:code-review` completed separate Standards and Spec Compliance reviews against pinned `origin/main`; all valid findings are resolved and checks rerun.
