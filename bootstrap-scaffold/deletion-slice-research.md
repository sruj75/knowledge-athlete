# Deletion Slice Source Cross-Check

## Question

Are the dependency slices in [`deletion-map.md`](./deletion-map.md) detailed and
code-grounded enough to implement rapidly without deleting retained behavior,
leaving half a cloud path alive, or hiding a migration behind a no-op adapter?

## Method

- Primary sources are the live source, tests, manifests, component guides, and
  reviewed IR sections in this checkout.
- A slice is implementation-ready only after its entry points, authority owner,
  downstream dependencies, shared seams, deletion/adaptation order, and closure
  proof are explicit.
- A directory name or matching symbol is evidence of a candidate owner, not
  proof that the whole file is exclusive. Mixed files require call-site tracing.
- Windows is not inspected or used as a dependency argument.
- This is planning research only. No product code is changed.

## Status legend

- **Ready:** the codeflow and retained boundary are sufficiently concrete for a
  dependency-ordered implementation brief.
- **Split:** the `S-XX` combines independent codeflows, so its one owning TDD
  plan must divide them into ordered vertical tracer bullets before
  implementation. This does not create another subagent or another TDD plan.
- **Reopen:** current source contradicts or materially weakens the product
  premise used for the recorded decision.
- **Pending:** source cross-check not completed yet.

## Research log

### Keep one managed-Pi local agent and delete every alternate entrance (S-05)

**Research status: REOPEN + SPLIT**

#### Verified current runtime path

```text
Swift ChatProvider
  -> AgentRuntimeProcess
  -> bundled desktop/macos/agent Node kernel
  -> PiMonoRuntimeAdapter / PiMonoAdapter
  -> bundled pi-coding-agent subprocess
  -> pi-mono-extension/index.ts
  -> extension registers canonical pi-mono tools
  -> OMI_BRIDGE_PIPE
  -> Swift ChatToolExecutor
  -> local stores / retained managed backend calls
```

Primary evidence:

- `desktop/macos/agent/src/adapters/pi-mono.ts:153-162` says desktop Pi disables
  Pi's built-in tools and relies on the Omi provider extension.
- `desktop/macos/agent/src/adapters/pi-mono.ts:205-212` resolves the bundled
  `pi-mono-extension/index.ts` path.
- `desktop/macos/agent/src/adapters/pi-mono.ts:619-642` creates the Pi session
  and starts the process but does not consume `SessionOpts.mcpServers`.
- `desktop/macos/pi-mono-extension/index.ts:752-787` builds the `pi-mono` tool
  projection, connects to `OMI_BRIDGE_PIPE`, and registers every tool with Pi.
- `desktop/macos/agent/src/adapters/interface.ts:23-29` allows `mcpServers` in the
  common adapter shape, but that does not make Pi consume them.

#### Corrected `omi-tools-stdio` finding

`desktop/macos/agent/src/index.ts:1089-1124` can build an `omi-tools-stdio`
MCP child configuration. That configuration is passed through the generic
kernel binding shape, but the retained Pi adapter's session creation ignores the
MCP list and uses the extension path above. The stdio transport is therefore not
the actual managed-Pi tool bridge in the current code.

This contradicts the premise in the current map and IR-015 that retaining
managed Pi necessarily retains `omi-tools-stdio`. After deleting ACP, Hermes,
and OpenClaw, the stdio process may have no production consumer. Do not decide
that from names alone; run a final adapter/session caller audit, then reopen the
requirement with the user.

Likely choices:

1. Delete `omi-tools-stdio` if the caller audit confirms only rejected adapters
   consume it, keeping Pi extension -> bridge -> `ChatToolExecutor`.
2. Rewire Pi to stdio. This would be a new transport migration with no proven
   product benefit and is not recommended merely to preserve the old decision.

#### Independent deletion paths currently bundled together

1. **Adapter portfolio:** `AIProvider.swift`, the Node adapter registry and
   `adapters/acp.ts`, `hermes.ts`, `openclaw.ts`, shared capability/profile
   policy, model-selection UI/state, and `desktop/macos/acp-bridge/`.
   Evidence: `desktop/macos/Desktop/Sources/Providers/AIProvider.swift:44-64`,
   `desktop/macos/agent/src/adapters/interface.ts:222-284`, and
   `desktop/macos/agent/src/index.ts:1250-1351`.
2. **Browser/general execution:** Playwright MCP construction and settings,
   broad shell/file/native-app tools, permissions, manifests, tests, and
   extension packaging. Evidence:
   `desktop/macos/agent/src/index.ts:1089-1151`.
3. **Claude compatibility:** workspace/global prompt readers, Skills catalog,
   `search_skills`/`load_skill`, Settings cards, prompt injection, fixtures, and
   the same tools duplicated in both stdio and the Pi extension. Evidence:
   `desktop/macos/agent/src/omi-tools-stdio.ts:318-334` and
   `desktop/macos/pi-mono-extension/index.ts:693-754`.
4. **External Local Agent HTTP API:** app startup, loopback listener, settings,
   Keychain token, tool projection, Memory Export setup/test UI, and API-only
   wrappers. Evidence: `desktop/macos/Desktop/Sources/OmiApp.swift:309`,
   `LocalAgentAPIServer.swift:16-103,133-180`, and
   `MainWindow/Pages/MemoryExportDestinationSheet.swift:232-286`.
5. **Retained managed-Pi lifecycle:** the adapter, packaged extension, local
   kernel/journal, Agent Pills, completion-to-voice bridge, and
   `DesktopAutomationBridge` are regression fences, not deletion targets.

#### Research correction

The one S-05 TDD plan must separately sequence at least the four deletion paths
above plus one retained Pi boundary verification. Treating them as one red-green
cycle would mix a transport decision, provider removal, tool-surface deletion,
UI cleanup, and a loopback API deletion in one high-risk change. They remain one
S-05 owner and one plan.

### Delete Apps, marketplace, connectors, remote MCP, and broad indexing (S-06)

**Research status: SPLIT**

#### Verified independent product paths

1. **Apps/marketplace platform**
   - Mac entry: `DesktopHomeView.swift:1567` constructs `AppsPage`.
   - Backend entry: `backend/main.py:169` registers `apps.router`; the same
     entrypoint also registers integration, OAuth, developer, and payment
     surfaces around it (`backend/main.py:157,173,177,181-182`).
   - The deletion must trace catalog/install/review/creator/paid-app state,
     marketplace billing, developer keys/webhooks, jobs, metrics, and UI.
2. **First-party import/export connectors**
   - Home owns an `ImportConnectorStatusStore` and refreshes connector state at
     startup/foreground (`HomeStatusStore.swift:30-37,78-115,234`).
   - Memory Export owns destination status, external-agent connection tests,
     cloud grant state, Notion MCP, and Local Agent API setup
     (`MemoryExportDestinationSheet.swift:205-340,460-544`).
   - Backend connector/import routes are independently registered, including
     integrations, Google Calendar, calendar onboarding, and imports
     (`backend/main.py:145,150-151,170-173,183`).
3. **Hosted/public MCP product**
   - `backend/main.py:178-180` registers MCP API-key, REST, and SSE/OAuth routers.
   - `backend/routers/mcp.py:103-283` exposes OAuth grants and memory/profile
     reads/writes.
   - `backend/routers/mcp_sse.py:29-79,158-225` imports cloud product stores,
     validates MCP API keys/OAuth, and owns remote authorization discovery.
4. **File indexing and Brain Map / knowledge graph**
   - The local file product is a distinct tree under
     `Desktop/Sources/FileIndexing/`.
   - Full Disk Access probing is owned by
     `AppState/AppState+Permissions.swift:443-466` and is also exposed through
     `ChatToolExecutor.swift:1727-2003`.
   - The live Home shell constructs both canonical and legacy Brain Map views
     (`DesktopHomeView.swift:1335-1402`).
   - Backend graph CRUD/model work is separately owned by
     `backend/routers/knowledge_graph.py:88-125`,
     `backend/database/knowledge_graph.py`, and
     `backend/utils/llm/knowledge_graph.py`.
5. **Hosted sharing/persona**
   - Conversation/task sharing and public Persona depend on cloud product data
     but are not the same runtime as Apps or connectors. They should close with
     the owning local-data/backend-product slices, not be hidden here.

#### Shared seams that prevent blind deletion

- `backend/main.py` is a mixed route registry; delete registrations one product
  at a time, then remove imports. Never delete the entrypoint wholesale.
- OAuth, auth, payment, Redis, Firestore, and generic HTTP helpers also have
  retained account/billing callers. Only marketplace/connector-specific
  branches can leave with this product.
- `ChatToolExecutor` mixes rejected Full Disk Access/connector tools with
  retained Screen Recording, Microphone, Notifications, Accessibility, tasks,
  memory, Rewind, and managed-Pi tools.
- `LocalAgentAPIServer` setup appears in Memory Export, but its runtime deletion
  belongs to the dedicated S-05 successor path.

#### Research correction

The one S-06 TDD plan must sequence four vertical areas: Apps/marketplace;
first-party connectors; hosted/public MCP; file indexing + Brain Map. Hosted
sharing/Persona remain downstream of the owning Conversation/Task/Memory and
backend-product slices. Each path has a different UI entrance, backend API,
storage, credential, and closure proof, but all stay under the S-06 subagent.

### Delete the customer BYOK plan and all key propagation (S-07)

**Research status: READY after dependency expansion**

#### Verified end-to-end codeflow

```text
Settings Developer Keys
  -> APIKeyService stores four keys and computes fingerprints
  -> BYOKValidator / users byok-active enrollment endpoints
  -> Firestore BYOK state becomes server source of truth
  -> APIClient headers + realtime WebSocket headers
  -> AgentRuntimeProcess OMI_BYOK_* environment
  -> pi-mono-extension converts env to X-BYOK-* headers
  -> backend BYOKMiddleware / WebSocket validation
  -> subscription, paywall, quota, provider, STT, TTS, sync, and error paths
```

Primary evidence:

- Settings state: `MainWindow/Pages/SettingsPage.swift:451-458` and
  `Settings/Sections/SettingsContentView+DeveloperKeys.swift`.
- Local key/fingerprint authority: `APIKeyService.swift:18-38,202-228`.
- Local paywall bypass: `AppState/AppState+TrialPaywall.swift:21-26,47-85`.
- Realtime forwarding: `RealtimeOmniService.swift:341-343` and
  `FloatingControlBar/RealtimeHubSettings.swift:43-82`.
- Agent forwarding: `Chat/AgentRuntimeProcess.swift:2591-2607,2786-2814` and
  `pi-mono-extension/index.ts:803-822`.
- HTTP middleware and validation: `backend/main.py:233-235` and
  `backend/utils/byok.py:97-275`.
- Enrollment and BYOK quota responses:
  `backend/routers/users.py:1086-1163,1369-1438`.
- Subscription/STT bypass is spread through
  `backend/utils/subscription.py:113-318,824-849,1210-1247`.

#### Required deletion order

1. Protect managed subscriber Chat/PTT/STT/TTS and normal development-key paths.
2. Remove BYOK as an entitlement/paywall/quota mode in the Mac and backend.
3. Stop all clients/runtimes from attaching keys or fingerprints.
4. Remove enrollment/deactivation APIs, Firestore fields/cache, middleware,
   HTTP/WebSocket validation, provider key resolution, and error notification.
5. Remove Settings/Keychain/UserDefaults state and credential-health branches.
6. Remove sync/finalization, usage, tests, docs, metrics, secrets, and model-QoS
   residue that only exists for BYOK.

#### Closure proof

- A paying subscriber completes managed Chat, PTT, continuous cloud STT, batch
  recovery, TTS, and transient model calls without any user key.
- Adding old `X-BYOK-*` headers cannot bypass entitlement or select a provider.
- Repository searches find no BYOK enrollment, fingerprint, header, environment,
  quota, notification, or plan branch outside historical records.

### Local product data, Rewind, listen, and PTT (S-10 through S-16 and S-19)

**Research status: SPLIT, except the narrow Rewind cloud-copy deletion**

#### Local stores are caches today, not complete authorities

The source does not support a one-step instruction such as "remove the API
calls and use SQLite." The three most important local stores all contain useful
battle-tested behavior, but their current contracts still assume a remote
authority:

- `MainWindow/Conversations/ConversationRepository.swift` explicitly owns
  cache/server reconciliation. `LiveConversationRemoteDataSource` performs
  list, count, detail, search, star, title, folder, and delete through
  `APIClient`, while `LiveConversationLocalDataSource` stores server-shaped
  results in `TranscriptionStorage`.
- `Rewind/Core/TranscriptionStorage.swift` still uses `backendId`,
  `backendSynced`, `pendingUpload`, `cloudReconcile`, server revisions, and
  `syncServerConversation`. It is crash-safe local recording storage plus a
  server cache, not yet the complete Conversations product authority.
- `Rewind/Core/MemoryStorage.swift` describes itself as a bidirectional-sync
  cache. It supports valuable local reads, search, soft delete, Undo, lifecycle
  fields, and local-only placeholder IDs, but canonical mutations still flow
  through `/v3/memories` and are reconciled from server receipts.
- `Rewind/Core/ActionItemStorage.swift` and `Stores/TasksStore.swift` already
  supply much of the desired local task behavior, but normal UI, tool, task
  assistant, recurrence, ordering, workstream, and automation callers mix
  local writes with backend refresh/retry paths.

Therefore every local-authority TDD plan needs two independently verifiable
stages composed of smaller red-green tracer bullets:

1. **Adapt authority:** give the local repository complete stable identity,
   CRUD, lifecycle, pagination/search, owner fencing, restart behavior, and
   model-result admission; migrate every retained caller.
2. **Delete projection:** only after the first step passes with the network
   unavailable, delete server sync/reconciliation, backend routes, collections,
   indexes, jobs, and cloud-specific fields.

Combining these into a single "delete sync" tracer bullet would make it easy to
preserve only the cache fallback while silently losing mutations.

#### Required concerns for the owning S-XX TDD plans

- **S-10 Conversations:** split local catalog/detail/folder CRUD, local
  recording finalization and merge, local enrichment commits, and deletion of
  cloud conversation/audio/People authority.
- **S-11 Chat:** split kernel-journal projection removal, local chat-session
  metadata, local greeting/title commits, local attachments, and rejected
  rating/app/persona UI. Evidence includes
  `Chat/KernelJournalBackendSyncDriver.swift`, the Node
  `backend_turn_outbox`/reconcile machinery in
  `agent/src/runtime/conversation-journal.ts`, cloud session CRUD in
  `ChatProvider.swift:2154-2386`, and upload/rating callers in
  `ChatProvider.swift:3460-3605,5823-5843`.
- **S-12 Memories:** split local lifecycle/CRUD, local semantic indexing,
  model-result admission, and cloud authority teardown. Retained
  `DesktopAutomationBridge`, Chat, PTT, proactive, Focus, Insight, and profile
  callers must all move before `/v3/memories` disappears.
- **S-13 Tasks/Goals:** split core task authority, recurrence/reminders/order,
  Task Assistant localization, simple Goals localization, task-agent/workstream
  deletion, and rejected task-intelligence/UI deletion. IR-651 is not an open
  contradiction: its deletion was explicitly superseded by IR-652, so the
  extraction-interval control stays exactly as implemented while only its cloud
  sync is removed.
- **S-14 Focus/Insights/profile:** split Focus persistence, Insight/advisor
  persistence, AI Profile inputs/output, assistant settings localization, and
  Daily Summary deletion. `FocusAssistant`, `InsightAssistant`, and
  `MemoryAssistantTelemetry` currently write local records and then create
  backend Memories; `InsightStorage` and `FocusStorage` still mutate those
  backend records.
- **S-16 listen:** split the transient `/v4/listen` wire contract, Mac-local
  session finalization, removal of persistent speaker identity/People,
  localization of transcription preferences, and deletion of rejected listen
  modes/statuses. The current server path mixes STT, translation, diarization,
  speaker assignment, conversation creation, Redis session state, and
  finalization.
- **S-19 PTT tools:** split local Conversation, Memory, Task, and Rewind/recap
  tool migrations from rejected-tool deletion and from the final lifecycle
  regression pass. `ChatToolExecutor.swift:2755-2922` still dispatches the rich
  product-data tools to backend APIs, while the realtime controller has a large
  independent activation/transport/journal/vision lifecycle that the ledger
  explicitly protects.

#### Rewind boundary is narrower and ready

S-15 can remain one narrow deletion plan after its dependency checks:

- retain `RewindDatabase`, `RewindStorage`, `RewindIndexer`, OCR, local video,
  `OCREmbeddingService`, local vector similarity, capture health, recovery,
  retention, UI, and PTT local retrieval;
- delete only verified cloud screen-activity/Pinecone/backend-agent/hosted-MCP
  readers, writers, indexes, routes, configuration, and tests;
- treat the already-deleted `ScreenActivitySyncService` as the missing producer
  that triggered the audit, not proof that all downstream readers vanished.

The transient embedding call is not a cloud data authority: embeddings return
to the Mac and are written by `OCREmbeddingService` into local SQLite.

### Identity, billing, onboarding, fair use, telemetry, and shell (S-08, S-09, S-17, S-18, S-20, S-21)

**Research status: SPLIT; Dodo and local fair-use inference have explicit start gates**

#### Identity/account boundary

`AuthService.swift` owns Firebase restore, native Apple/Google sign-in,
custom-token exchange, blocking recovery, foreground validation, and sign-out.
`backend/routers/users.py` mixes retained account routes with rejected
onboarding, cloud-sync, People, webhook, BYOK, and product-data routes.
`backend/services/users/account_deletion.py` preserves a strong durable deletion
state machine but currently imports Stripe cancellation plus purge functions for
Pinecone, recordings, speech samples, Twilio, and other rejected products.

The one S-08 TDD plan must sequence separate tracer-bullet groups for:

1. re-owning Firebase/OAuth project identity without changing auth behavior;
2. preserving the Mac auth/recovery/sign-out lifecycle;
3. pruning and retargeting durable account deletion after each product-data
   owner is removed; and
4. creating the approved local product-data export while narrowing the server
   export to genuine account/control metadata.

#### Billing provider migration

The repository currently implements Stripe throughout `backend/routers/payment.py`,
`backend/utils/stripe.py`, `backend/utils/subscription.py`, user/subscription
models, account deletion, Mac API models, checkout UI, tests, secrets, and
startup validation. There is no Dodo implementation to "turn on."

The one S-18 TDD plan therefore needs three ordered stages:

1. document the exact Dodo checkout, portal, webhook signature, customer,
   subscription, price, cancellation, and entitlement mapping contract;
2. implement Dodo behind the retained Mac-visible billing behavior and prove
   webhook/reconciliation/quota parity; and
3. only then delete Stripe code, identifiers, secrets, tests, and migration
   residue.

The first is a required research/start gate, not permission to invent Dodo's API
from the current Stripe shapes.

#### Onboarding and permissions

The retained onboarding is a real multi-screen state machine, not one screen.
The source under `Desktop/Sources/Onboarding/` mixes the reviewed conversational
flow with superseded paged onboarding, Full Disk Access scanning, Automation,
external connectors, backend writes, local stage recovery, shortcut rehearsal,
Launch at Login, and capture startup.

S-17 must split screen selection/copy wiring, permissions, local lifecycle
state, and removal of backend onboarding writes. The final product claims and
branding remain a later truth pass; this slice must not casually rewrite
retained timing, Back/Skip, reset, resume, Return-key, layout, or cleanup
behavior.

#### Fair-use dependency that cannot be hidden

IR-612 explicitly requires a genuinely local semantic model for the retained
classifier. The repository does not currently ship that general-purpose local
model. The existing local Agent runtime still calls managed Claude, so routing
the evidence through it would violate the reviewed privacy boundary.

S-20 must therefore start with a named local-inference-adapter tracer bullet.
Until its model/runtime choice and strict input/output contract are decided, the content
classification migration is approved product direction but not
implementation-ready. Backend-only work can still preserve the content-free
enforcement state machine, timers, thresholds, support API, and Dodo entitlement
mapping, but it cannot pretend that local classification exists.

#### Observability and UI convergence

- S-09 combines independent owned services. Split Sentry/PostHog re-ownership,
  local diagnostics/report export, LangSmith plus Prompt Hub retention, and
  deletion of Crisp/self-hosted monitoring/deprecated events. `AnalyticsManager`
  contains both retained and rejected events; delete events individually.
- S-21 is a convergence plan only after its feature owners land. The live
  shell still constructs `AppsPage` and Brain Map in `DesktopHomeView.swift`,
  starts file indexing, performs settings sync, exposes old/new Home states,
  and has automation/deep-link routes. Navigation, Settings search/cards, and
  Home startup refresh need separate tracer bullets or review stages in the
  owning TDD plans so deleted destinations do not leave hidden entry points.

### Models, backend products, topology, infrastructure, identity, and release (S-22 through S-30)

**Research status: SPLIT inside their one-owner TDD plans**

#### Model portfolio

The retained and rejected model calls are distributed across
`backend/routers/auto_model.py`, `desktop_chat.py`, `desktop_proxy.py`,
`desktop_realtime.py`, `desktop_tts_updates.py`, `chat.py`, memory/product
routers, `utils/llm/`, the independent `llm_gateway/`, Mac `ModelQoS`, and the
realtime relay. S-22 must not be treated as one search-and-delete operation.

Required order:

1. create one tested caller -> model route -> result owner inventory;
2. protect retained managed Chat, realtime providers, transient embeddings,
   translation, conversation enrichment, memory/task/proactive calls, and
   LangSmith/Prompt Hub;
3. adapt every retained personal-data result to a validated local commit;
4. delete callerless/rejected routes one family at a time; and
5. delete the independent gateway only after no retained route uses it.

The Gemini Live versus OpenAI Realtime decision remains deferred; both paths are
protected. This is distinct from the unresolved local model needed by S-20.

#### Hosted product and storage teardown

`backend/main.py:142-210` currently registers dozens of routers in one mixed
application. S-23 cannot safely delete "backend products" as one tracer bullet.
Each rejected product family needs its own ordered route/storage/job/config/test
closure inside the one S-23 plan:

- cloud recordings/training and persistent speech identity;
- sharing/public persona and shared Chat;
- Daily Summary/Joan/Trends;
- Twilio calls, Wrapped, announcements, firmware/glasses/Limitless;
- cloud ratings/scores/FCM/detailed product usage;
- any remaining rejected model-specific product route.

S-24 similarly splits Typesense, Pinecone, and product-data object/file storage.
The update/preview bucket is a protected sibling, not deletion residue.

#### Service topology and canonical backend

The live repository has separate backend-sync/backfill/integration Cloud Run
services, backend-listen GKE, Pusher, VAD, diarizer, Parakeet, NLLB, notifications
and memory-maintenance jobs, LLM gateway, monitoring charts, dedicated images,
workflows, runtime manifests, secrets, tests, and alerts. These are independent
decommission paths inside the one S-25 TDD plan, not one bulk deletion cycle.

Only after their workloads are gone should S-26 prune `backend/main.py`, merge
the surviving desktop/product entrypoint and image/configuration, then narrow
the local/offline harness to the exact surviving stack. Removing a deployment
before its caller or merging entrypoints before route ownership is clear would
make failures harder to localize.

#### Infrastructure re-ownership

S-27 contains at least five separately verifiable changes: canonical Cloud Run
service/deploy, IAM/WIF/secrets/container hardening, Redis/networking, retained
Firestore/GCS/Cloud Tasks, and artifact promotion/rollback/observability/cost.
The approved target region is `us-west1`; current workflows and charts still
contain `us-central1`, so the region change is an explicit migration rather than
cosmetic renaming.

#### Mac identity and release

- S-28 is one coherent local namespace migration: bundle/app-group/Keychain,
  Application Support, databases/defaults/login item/caches/logs/update identity,
  test bundles, and clean-install isolation from Omi.
- S-29 must split Mac signing/notarization/build, Sparkle/update policy,
  preview/candidate promotion, and public site/legal destinations. The current
  repository has Sparkle policy and installer code plus release workflows, but
  the owned certificates, feeds, buckets, domains, and Codemagic contract are
  external configuration inputs.
- S-30 is a final truth pass only after those boundaries land. It must not be
  used early to make inherited claims look correct while the underlying code is
  still wrong.

## Cross-check conclusion

The 31 entries in the current map are the stable subagent ownership slices and
each receives exactly one TDD plan. The plan must still distinguish:

- **KEEP AS IS:** regression fence; changing or simplifying it is forbidden;
- **ADAPT:** preserve the existing behavior while changing authority/provider/
  ownership;
- **DELETE:** remove the complete named path after its retained dependency is
  proven;
- **SIMPLIFY AFTER:** remove duplication or stale shape only after adaptation and
  deletion pass. This is Step 3 of the five-step algorithm, not merely a final
  residue cleanup;
- **ACCELERATE AFTER:** improve a measured edit/test/run/release bottleneck only
  after the correct retained shape works;
- **AUTOMATE LAST:** automate only a stable repeated path, and explicitly record
  `none` when a small slice has nothing worth automating; and
- **OUT OF SCOPE / DEFERRED:** never inferred as permission to delete.

Each `S-XX` TDD plan needs one working postcondition, its own source anchors,
dependencies, keep/adapt/delete/simplify/out-of-scope table, pre-agreed public
seams, ordered red-green tracer bullets, behavioral proof, and residue search.
The number of tracer bullets is discovered per plan rather than inherited from
the discarded 86-packet draft. A final cross-cutting cleanup may remove only
residue that every owning slice has already made dead; it may not make product
decisions or perform unfinished migrations.
