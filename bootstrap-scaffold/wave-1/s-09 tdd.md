# S-09 TDD plan — re-own observability without coupling consent, diagnostics, and model traces

## Plan record

| Field | Value |
|---|---|
| Status | Researched; **blocked on S-08 identity semantics, owned development-project configuration, and human approval of the public seams below** |
| Wave | 1 |
| Owner | S-09 |
| Authorizing and protecting decisions | IR-114, IR-115, IR-116, IR-117, IR-183, IR-204, IR-205, IR-206, IR-207, IR-208, IR-209, IR-210, IR-211, IR-254, IR-805, IR-827, IR-828, IR-832, IR-836, IR-837, IR-879, IR-886 |
| Depends on | S-08 for the canonical account identity and explicit sign-out transition |
| Coordinated owners | S-11 and S-23 for deletion of the surviving cloud Chat-message/rating storage and routes; S-15 for the non-Crisp cloud screen-history remainder; service-owning slices for later removal of their own metric counters and chart fragments; S-27 for live Cloud Logging deployment and the 30-day bucket policy; S-30 for final product name and final local/cloud/compute disclosure copy |
| Target baseline | `origin/main`; fetch it and record one immutable merge-base SHA when implementation starts |
| Research snapshot | Current checkout `5ecb5e17aeab01955aff150a22054a957e15a48e`; requirements and live source must be rechecked if the implementation merge-base differs |
| Postcondition | The product sends optional product analytics only to its owned PostHog project under a local, startup-safe consent choice; sends privacy-bounded crash and incident diagnostics to its separate owned Sentry project; retains local diagnostics, issue reporting, LangSmith prompt/trace observability, authenticated metrics, sanitized Cloud Logging, and the declared 30-day/no-archive policy for S-27; and contains no in-app rating flow, Crisp, Sentry-to-Task bridge, legacy PTT analytics events, fake privacy state, or deployable self-hosted monitoring product. |

## How this plan is executed

1. Do not implement from this draft until the human agrees to every public seam in the approval table and S-08 has published its identity/sign-out contract.
2. Then start with [engineering:implement](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/implement/SKILL.md), using this file as the implementation spec. Work on the current branch, keep the branch name unchanged, and commit locally in independently testable vertical slices. Do not push or open a PR without a separate user request.
3. Use [engineering:tdd](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/tdd/SKILL.md) throughout implementation: observe one test fail for the intended behavioral reason, add only enough production code to make that outcome pass, and then move to the next tracer bullet. Do not write all tests first and do not refactor during RED → GREEN.
4. Apply [engineering:codebase-design](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/codebase-design/SKILL.md) only to the new product-analytics consent boundary. It should become one small, deep module around PostHog. Sentry, local diagnostics, LangSmith, metrics, and logging remain separate systems rather than implementations of a universal “observability provider” interface.
5. After all cycles and full verification are green, finish with [engineering:code-review](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/code-review/SKILL.md). Use the immutable merge-base recorded at implementation start as the fixed point, this file as the spec, and the root/component `AGENTS.md`, `PRODUCT.md`, matched invariants, and requirements decisions as standards. Review Standards and Spec Compliance separately, fix valid findings, and rerun affected checks.

## Decision partition

“Telemetry” is not one permission or one substitutable service in this slice. The retained systems have different jobs and different authority:

| System | Retained job | User control / authority |
|---|---|---|
| PostHog | Product-usage analytics and bounded lifecycle events | Local **Share product analytics** preference, default on; applied before SDK initialization, capture, or identity attachment |
| Sentry | Crash, hang, error, user-report, and privacy-bounded PTT incident diagnostics | Retained separately; not disabled by the PostHog preference or beta Enhanced Diagnostics preference |
| QueryTracer + app logs | Local timing, query continuity, and local troubleshooting evidence | Existing production redaction, owner-only file permissions, rotation, and offline export boundaries |
| Enhanced Diagnostics | Extra beta typed diagnostic trail attached to a report | Existing separate local toggle, default on; off substitutes the existing strictly filtered log tail |
| Report an Issue | User-triggered generic Sentry report with bounded diagnostics | Existing explicit submission action; typed description/name/email remain discarded |
| LangSmith | Model prompt, run, tool, trace, and operator-side evaluation evidence | Backend configuration in this product's LangSmith account/project; disclosed separately because model content/metadata can be sent |
| Prompt Hub | Remotely versioned agentic system prompt | Remote prompt when successfully fetched; repository prompt is the availability fallback; five-minute default TTL retained |
| `/metrics` | Small authenticated, low-cardinality backend operational counters | `METRICS_SECRET`; no requirement to operate a Prometheus consumer |
| Python logging / Cloud Logging | Sanitized operational stdout/stderr captured by Cloud Run | S-09 preserves sanitizer/correlation behavior and removes self-hosted collection; S-27 owns deployment proof of default 30-day retention and no archive |

The deletion work is similarly partitioned. Removing Crisp, the Sentry feedback-to-Task bridge, or the self-hosted monitoring deployment must not remove their retained neighbors from mixed files. `AnalyticsManager` also contains both accepted and rejected events; S-09 deletes only the two deprecated PTT helpers and their callers.

## Research-backed start gates

S-09 stays blocked until these facts are supplied or proven at the pinned implementation baseline. Missing values must not be guessed or copied from Omi:

1. **S-08 identity contract:** canonical account ID, successful sign-in attachment point, explicit sign-out ordering, and account-switch behavior. IR-183 protects the outcome “record Signed Out for the departing account, then detach PostHog identity and clear Sentry identity.”
2. **Owned PostHog development project:** project token, ingestion host, allowed environments, session/screen-capture policy, and a way to inspect the development project during verification. The token is configuration even if the provider treats it as public; it must not remain an Omi literal in source.
3. **Owned Sentry development project:** DSN, organization, project, environment/release naming, source-map or dSYM upload destination, and a development credential for verification. Authentication tokens remain secret and must never be committed or logged.
4. **Owned LangSmith development project:** endpoint, project, prompt name, API key injection, and access to inspect a development run. The plan records identifiers, never secret values.
5. **Owned Google Cloud development project:** Cloud Run service/log view needed to prove that retained Python logs stay sanitized after self-hosted collection is removed. If S-27 has not yet deployed the owned foundation, record the exact handoff for live `_Default` 30-day retention/no-archive proof rather than claiming S-09 configured it.
6. **Configuration placement:** trace existing build/runtime injection mechanisms at the implementation merge-base and select the smallest owned configuration surface. Do not invent a second secret system or embed a production credential in Swift, Python, Helm, tests, or docs.
7. **Current third-party contract:** `Desktop/Package.resolved` pins `posthog-ios` 3.65.0 at revision `33145b13ffa1135623e6a2624e29234288a52258`. Before coding, re-verify the exact pinned SDK. The upstream config supports initial opt-out and runtime opt-in/out, but its own persisted state participates in setup. The product preference therefore becomes authoritative by **not setting up PostHog at all when the saved choice is off**, rather than trusting a post-setup call to race automatic capture. Primary references: [PostHogConfig at the pinned revision](https://github.com/PostHog/posthog-ios/blob/33145b13ffa1135623e6a2624e29234288a52258/PostHog/PostHogConfig.swift#L179-L184) and [PostHogSDK setup at the pinned revision](https://github.com/PostHog/posthog-ios/blob/33145b13ffa1135623e6a2624e29234288a52258/PostHog/PostHogSDK.swift#L164-L229).

## Current codeflow and failure boundary

### Product analytics, crash diagnostics, and identity

1. `desktop/macos/Desktop/Sources/OmiApp.swift` starts Sentry with an Omi DSN, release tags, privacy filtering, crash/hang policy, and breadcrumbs. It later initializes `AnalyticsManager`, emits launch events, and identifies an already-signed-in account.
2. `desktop/macos/Desktop/Sources/PostHogManager.swift` embeds an Omi PostHog token and host. It directly wraps the SDK for setup, capture, screen events, feature flags, identity, reset, and opt-in/out. `hasOptedOut` currently returns the inverse of the SDK value.
3. `desktop/macos/Desktop/Sources/AnalyticsManager.swift` suppresses development capture and is the broad event facade. It also still exposes `floatingBarPTTStarted` and `floatingBarPTTEnded` even though `PTTAttemptLifecycleRecorder` is the authoritative PTT diagnostic.
4. `desktop/macos/Desktop/Sources/AuthService.swift` currently records explicit sign-out, resets PostHog, and clears Sentry identity. S-09 must adapt to S-08's final identity seam without adding a second auth observer or account cache.
5. `DesktopAutomationBridge.settings_privacy_snapshot` projects the inverted PostHog helper as tracking state. `MainWindow/Pages/Settings/Sections/SettingsContentView+NotificationsPrivacy.swift` has no local PostHog preference and still contains a fake green **Active** encryption state, stale disclosure copy, and a duplicate **Privacy Guarantees** card; `SettingsSidebar.swift` carries the coupled search entries.

The failure-class boundary is ownership plus ordering: one local preference must decide whether PostHog is allowed to start before `AnalyticsManager.initialize`, launch events, screen capture, feature-flag preload, or identity attachment. Sentry must not inherit that decision.

### PTT and local support evidence

1. `PushToTalkManager.swift` still calls the two deprecated PostHog start/end helpers at several lifecycle branches.
2. `FloatingControlBar/PTTAttemptLifecycleRecorder.swift` already owns the accepted privacy-bounded lifecycle event. Its tests cover bounded phases/outcomes and exclude audio, transcript, prompt, raw device identity, and free-form errors.
3. `DesktopDiagnosticsManager`, `BetaEnhancedDiagnosticsConfiguration`, and their tests retain the typed diagnostic trail and the 50-entry bound. Enhanced Diagnostics off uses the existing filtered log-tail substitution.
4. `FeedbackView.swift`, `FeedbackPayloadDryRunTests`, and the desktop bridge dry-run assemble a generic `User Report` Sentry message plus `desktop_diagnostics.json`. The typed description, name, and email are deliberately not transmitted.
5. `DiagnosticsExportTests` protect the offline, user-chosen, bounded export and redaction. `QueryTracer.swift` protects the local rotating JSONL trace, owner-only directory/file modes, production redaction, development detail, and continuity/statistics scripts.

These are KEEP fences. S-09 is not authorized to “improve” their payloads, turn the PostHog preference into a general diagnostics opt-out, or merge Enhanced Diagnostics with Sentry enablement.

### Crisp and Sentry-to-Task mixed seams

1. `MainWindow/CrispManager.swift`, `HelpPage.swift`, `DesktopHomeView.swift`, `SidebarView.swift`, automation routing, tests, notifications, and startup/polling form the Mac Crisp product.
2. `backend/routers/desktop_screen_crisp.py` mixes rejected `/v1/crisp/unread` helpers with screen-history code owned by S-15. S-09 deletes only Crisp and leaves the exact non-Crisp remainder untouched for S-15; it does not classify cloud screen-history synchronization as retained. Local Rewind is the protected product.
3. `backend/routers/desktop_core.py` mixes retained health/config behavior with rejected Sentry webhook/poll/transform/deduplicate-to-cloud-Task behavior. Only the Sentry bridge is deleted.
4. `MainWindow/Pages/TaskDetailViews.swift` has Sentry-feedback-specific Task presentation and metadata. Generic Task detail behavior remains.

Deletion must be observed through public routes/startup/navigation and surviving sibling behavior, not by asserting the textual order of source strings.

### LangSmith and Prompt Hub

1. `backend/utils/observability/langsmith.py` owns tracing configuration/status, scoped/global tracer callbacks, run IDs, metadata, and a feedback-submission helper whose current callers belong to the rejected in-app rating flow.
2. `backend/utils/observability/langsmith_prompts.py` owns the prompt name, five-minute default TTL, remote fetch, version metadata, safe template extraction/rendering, and the complete repository fallback.
3. `backend/utils/retrieval/graph.py`, agentic Chat, Chat storage/model code, and startup status connect a run to its prompt metadata and persisted Chat association.
4. Environment templates and runtime manifests still contain Omi-named defaults or inconsistent legacy LangChain/LangSmith keys.
5. IR-832 retains operator-side annotation/evaluation but forbids the end-user thumbs flow. The current Mac still renders thumbs in normal and floating Chat, calls the desktop rating endpoint, stores a message rating field, and emits a rating event. S-09 deletes the complete user-facing/client codeflow and the rating-only LangSmith helper. S-11 and S-23 own later deletion of the shared local/cloud Chat rating fields, backend routes, analytics storage, and schemas as part of their larger authority teardown; S-09 must not widen into that work.

The live Mac rating path crosses `MainWindow/Components/ChatBubble.swift`, `FloatingControlBar/AIResponseView.swift`, `Providers/ChatProvider.swift`, and `Services/APIClient/APIClient+Messages.swift`; `MainWindow/Pages/ChatLabView.swift` also reads production ratings. Shared backend rating routes currently exist in `routers/chat.py`, `routers/users.py`, and related Chat/storage models. The former set is S-09 deletion scope; the latter set is the exact S-11/S-23 handoff.

### Self-hosted monitoring, metrics, and logging

1. `backend/charts/monitoring/**` contains the standalone Prometheus/Grafana/Loki/Alloy/Alertmanager/exporter deployment, Omi dashboards, rules, values, and docs.
2. Monitoring-specific contracts extend outside that directory into `.github/checks-manifest.yaml`, `backend/scripts/verify_pusher_dev_observability.py`, its tests, alert/workflow/deploy tests, workflow contract registry, backend guides, and runbooks. Each mixed reference must be classified before deletion.
3. `backend/routers/metrics.py` and `backend/utils/metrics.py` expose the retained authenticated low-cardinality metrics surface. `main.py` registers it and runtime manifests carry `METRICS_SECRET`.
4. `backend/utils/log_sanitizer.py` and its tests protect ordinary Python logs. Cloud Run already captures stdout/stderr into Cloud Logging.
5. Other service charts still contain service-owned `ServiceMonitor`, Prometheus annotations, counters, and autoscaling inputs. Their owners remove them when those services disappear. S-09 deletes the standalone monitoring product, not every occurrence of the word `metrics` or `prometheus` across future slices.

## Proposed public seams — human approval gate

The human must agree to the following observable contracts before any new test is written. “Public” means a user, authenticated client, operator, or neighboring domain can observe it; it does not require Swift `public` access control.

| Seam | Observable success and main error behavior | TDD surface |
|---|---|---|
| Product-analytics consent | Default-on first run may start owned PostHog. A saved-off launch performs no PostHog setup, screen/lifecycle capture, feature-flag preload, or identify. Turning off at runtime detaches analytics identity and blocks future capture; turning on starts/resumes capture. Sentry remains initialized throughout. | Small `ProductAnalyticsConsentController` with injected preference store and PostHog SDK adapter; Settings toggle and semantic bridge exercise through a named bundle |
| Account identity lifecycle | Successful S-08 sign-in attaches only the canonical account to allowed services. Explicit sign-out records `Signed Out` for the departing account, then resets PostHog identity and clears Sentry identity. Saved-off PostHog never identifies; account switching cannot leak the prior identity. | S-08 auth transition seam with PostHog/Sentry recording fakes; no Firebase observer or source-order assertion |
| Privacy and support UI | Privacy shows one truthful data-location card, one factual tracking disclosure, a real PostHog-only preference, and no fake **Active** or duplicate guarantee card. Enhanced Diagnostics, Report Issue entry points, and offline Save Diagnostics retain their existing separate behavior. | Pure privacy presentation model plus Settings/automation semantic snapshot; existing feedback/export behavioral tests and named-bundle UI exercise |
| PTT incident evidence | One PTT attempt emits the authoritative privacy-bounded lifecycle diagnostic and never emits the two deprecated start/end events. Remote properties remain allow-listed; local QueryTracer timing remains available. | `PTTAttemptLifecycleRecorder`/diagnostics emit seam and a PostHog recording adapter; natural authenticated PTT exercise for the retained real path |
| Crisp deletion | The Crisp help destination, startup poller, unread notification, automation target, and `/v1/crisp/unread` route are absent, while local Rewind, generic notifications, Report Issue, and Save Diagnostics still work. The non-Crisp cloud screen-history remainder is left to S-15 without being declared retained. | Router test through the real FastAPI app plus Mac navigation/startup semantic seams; sibling behavior tests |
| Sentry-to-Task deletion | Sentry webhook/poll endpoints cannot create or expose a product Task and Sentry-specific Task presentation is absent. Desktop health/config routes and direct Mac Sentry issue submission remain functional. | Router test through the real FastAPI app, Task projection test, existing feedback payload test, owned-dev Sentry exercise |
| In-app rating deletion | Normal and floating Chat offer copy/info/timestamp behavior but no thumbs, rating state mutation, rating API request, rating event, or rating-backed Chat Lab production view. LangSmith traces remain inspectable and evaluable by operators without this product flow. | Normal/floating Chat action presentation plus recording API/analytics seams; no source-order assertion; exact backend/storage residue handed to S-11/S-23 |
| Model observability | With owned configuration, one agentic Chat run records the selected prompt source/version and trace/run correlation. Remote Prompt Hub success is cached for the TTL; missing key/network/invalid template uses the complete repository fallback. No in-app rating product is needed. | Existing LangSmith/Prompt Hub functions with injected fake client and clock; public agentic Chat boundary for correlation; no live network in CI |
| Backend operations | `/metrics` rejects missing/wrong credentials and returns retained low-cardinality counters for the right secret. Sanitized application logs reach owned Cloud Logging without raw sensitive payloads. No self-hosted monitoring release, dashboard, collector, log agent, or external archive is deployable. | FastAPI HTTP test, sanitizer behavior test, existing deploy/workflow manifest contracts, and owned-dev Cloud Run inspection |

### Approval consequences

Approval means these seams—not private class names or the exact proposed file split—are the stable contract for TDD. If S-08's public transition differs, adapt the test seam before writing tests. If the owned service identifiers or access needed for live verification are unavailable, hermetic cycles may be developed but S-09 cannot be declared closed and production identifiers must not be installed.

## Action ledger

Every tracked file/hit discovered at the pinned baseline must be assigned to this ledger or an exact coordinated owner. No generic residue bucket is allowed.

| Action | Exact behavior and source boundary |
|---|---|
| **KEEP AS IS** | Sentry crash/hang/error capture, release/environment/bundle tags, incident breadcrumbs, privacy scrub/drop policy, development native-handler suppression, and privacy-bounded PTT diagnostics. Repoint configuration, but do not turn Sentry into optional PostHog analytics. |
| **KEEP AS IS** | `PTTAttemptLifecycleRecorder`, its bounded properties, typed lifecycle/outcome diagnostics, test-injected emit/clock seam, and the corresponding bounded diagnostic attachment. |
| **KEEP AS IS** | `QueryTracer` local JSONL behavior: production redaction, richer development details, 5 MB rotation plus backup, owner-only directory/file modes, finalization, trace statistics, and continuity evidence. Product-name path changes belong to final identity work unless required by an owned path in this slice. |
| **KEEP AS IS** | Beta Enhanced Diagnostics toggle exactly as implemented: separate, default on, a maximum of 50 typed entries, and the existing strictly filtered log-tail substitute when off. It never enables/disables baseline Sentry. |
| **KEEP AS IS** | Report an Issue behavior: typed description/name/email are discarded; the remote title stays generic; only description length may be a bounded product event; the Sentry event gets the bounded diagnostics attachment. Keep About, Advanced Troubleshooting, status-menu, and both search entry points. |
| **KEEP AS IS** | Offline Save Diagnostics: explicit user-chosen file, bounded snapshots and log tail, current secret redaction, 512 KB/500-line bounds, no upload, and Finder reveal. |
| **KEEP AS IS** | LangSmith tracing/runs/metadata, Prompt Hub remote prompt/version metadata, five-minute default TTL, safe rendering, startup visibility, and complete repository fallback. Keep provider-side operator annotation, datasets, and evaluation; that does not require a product feedback endpoint. |
| **KEEP AS IS** | Authenticated `/metrics`, `METRICS_SECRET`, useful low-cardinality counters, sanitized stdout/stderr logging, and Cloud Run's built-in Cloud Logging ingestion. Preserve the 30-day/no-archive requirement as an explicit S-27 handoff; do not pretend S-09 owns its live infrastructure setting. |
| **ADAPT** | Replace hard-coded Omi PostHog token/host and Sentry DSN/org/project with product-owned build/runtime configuration. Align retained backend PostHog, Sentry, LangSmith, and Cloud environment/project names. Remove or fail clearly on inherited Omi defaults; never log secret values. |
| **ADAPT** | Introduce one local **Share product analytics** preference, default on, and one narrow controller that reads it before deciding whether PostHog is set up. Off-at-launch means no SDK setup. Runtime off resets/detaches identity and opts out; runtime on initializes/resumes. Fix or remove inverted `hasOptedOut` and make automation report the authoritative preference. |
| **ADAPT** | Route S-08 sign-in, explicit sign-out, and account switching through the agreed identity seam. Preserve exact sign-out ordering and keep Sentry identity separate from PostHog capture consent. |
| **ADAPT** | Rewrite the retained Privacy data-location card and **What We Track** disclosure from the final retained inventory. Make the distinction between optional PostHog analytics, always-on privacy-bounded Sentry diagnostics, beta Enhanced Diagnostics, local traces, and LangSmith model tracing explicit and factual. |
| **ADAPT** | Repoint LangSmith endpoint/project/prompt defaults and runtime environment keys to owned resources; preserve the current two-level prompt authority and run/prompt correlation. Normalize legacy key naming only after tracing every current deployment consumer. |
| **ADAPT** | Split mixed backend modules only as far as needed to delete Crisp or Sentry bridge code while leaving S-15's non-Crisp screen-history remainder untouched and preserving desktop health/config ownership. Update route policy, OpenAPI/generated clients if applicable, tests, docs, and environment templates with the deletion. |
| **DELETE** | `floating_bar_ptt_started` and `floating_bar_ptt_ended` helpers, every call site, stale comments, fixtures, expected event inventories, dashboards, and docs. Do not delete PostHog or the authoritative PTT lifecycle diagnostic. |
| **DELETE** | Complete Crisp slice: `CrispManager`, `HelpPage`, help destination/navigation/presentation, startup/start/stop/poll/read state, unread notifications, automation target, `/v1/crisp/unread`, backend cache/helpers/env, exclusive tests, and current docs. Preserve local Rewind, generic notifications, Report Issue, Save Diagnostics, and external legal/help links owned elsewhere; hand the non-Crisp cloud screen-history remainder to S-15. |
| **DELETE** | Complete Sentry-to-cloud-Task bridge: webhook/poll routes, request/response models, transforms, dedupe/cache, hard-coded project assumptions, cloud Task creation, route-policy entries, environment/config, Sentry-specific Task presentation/metadata, exclusive tests, and current docs. Preserve Sentry itself and generic Tasks. |
| **DELETE** | Fake green **Active** state and unsupported server-encryption claim; duplicate **Privacy Guarantees** card and all four absolute bullets. Do not move the same unsupported claims elsewhere. |
| **DELETE** | Complete standalone self-hosted monitoring product under `backend/charts/monitoring/**`: Prometheus, Grafana, Loki, Alloy, Alertmanager, Prometheus Adapter, Stackdriver exporter, Omi dashboards/rules/config/releases, exclusive deploy/check scripts, tests, workflow registrations, current runbooks, and secrets. Preserve `/metrics`, useful counters, Cloud Logging, and service-owned chart fragments assigned to later owners. |
| **DELETE** | Complete in-app rating/client flow: normal and floating Chat thumbs/actions and `onRate` plumbing, `ChatProvider.rateMessage`, `APIClient+Messages.rateMessage`, rating-only PostHog event, Chat Lab's production-rating reader/presentation, and `submit_langsmith_feedback` if the baseline audit confirms all callers are rating-only. Preserve copy/info/timestamp actions and LangSmith operator evaluation. |
| **COORDINATE / DEFER** | Message `rating` fields in shared local/backend models, desktop/mobile rating routes, Firestore analytics/storage, generated clients, and shared Chat tests are deleted by S-11/S-23 with their local-authority/backend-product work. Record exact files/routes as a handoff; do not leave an unowned caller from S-09 and do not add a compatibility alias. |
| **SIMPLIFY / OPTIMIZE AFTER** | After all deletion cycles are green, shrink the PostHog controller to the minimum preference/start/identify/reset/capture interface; remove redundant opt-out wrappers, inverted projections, duplicate configuration readers, dead PTT event helpers, Crisp/Sentry bridge support types, and self-hosted-monitoring-only contracts. Do not create a generic observability registry. |
| **ACCELERATE AFTER** | Measure the focused desktop telemetry/privacy test loop and backend observability test selection before and after. Only if the median repeated loop materially improves, add or tune named `dev-feedback.py` selectors/manifest mapping without reducing coverage. Record the measurements; otherwise `none`. |
| **AUTOMATE LAST** | Extend an existing CI/deploy contract—never an unwired script—only for stable repeated closure checks: no inherited Omi telemetry defaults, no standalone monitoring deployment, and required owned-config placeholders. The check must cite the real removed surface and run in both local and CI lanes. If existing type/config/deploy contracts already make recurrence impossible, `none`. |
| **OUT OF SCOPE / DEFERRED** | Final product name/legal wording (S-30); shared local Chat/message authority and backend rating schema/route/storage deletion (S-11/S-23) after S-09 removes every Mac caller; non-Crisp cloud screen-history deletion (S-15); live Cloud Logging bucket/deploy ownership (S-27); global account redesign beyond consuming S-08; new telemetry vendors or Langfuse dual delivery; a customer-facing Sentry master switch; redesign of Enhanced Diagnostics/report/export payloads; broader Task redesign; removal of service-owned metrics/HPA/chart fragments; production deployment/release; Windows and historical changelogs. |

## Interface design

### One deep module for optional product analytics

The current `PostHogManager` exposes the entire SDK shape and lets startup, identity, consent, and event wrappers share mutable singleton state. S-09 should deepen only this boundary:

```text
Settings / S-08 identity / AnalyticsManager event facade
                         │
                         ▼
          ProductAnalyticsConsentController
          ├─ reads/writes one local preference
          ├─ decides whether SDK setup is allowed
          ├─ owns attach/detach ordering
          └─ accepts bounded product events
                         │
                         ▼
              PostHog SDK adapter
              ├─ production: pinned SDK
              └─ tests: recording fake
```

The exact names may change, but the responsibilities may not leak back out:

- The controller's small interface is startup, set sharing enabled, identify/detach, and capture. Callers do not query SDK persistence or call `setup`, `optIn`, `optOut`, or `reset` independently.
- The local preference is the authority. On a saved-off launch the production adapter is not set up, so automatic capture cannot get ahead of consent. On runtime off, detach/reset occurs before opt-out completes the stop boundary. On runtime on, setup/resume happens before later product events.
- `AnalyticsManager` can remain the product-event facade, but it must delegate the actual capture decision. Do not duplicate the preference in every call site.
- Production and test adapters are justified because PostHog is an external service. Do not mock internal Settings or auth logic; invoke their production seams and record what reaches the external adapter.
- Sentry does not conform to this interface. Its independent setup and identity controller remain explicit.
- Configuration loading may be a separate small value type if one existing build/runtime injection surface can own it. Do not make consent code parse five unrelated provider environments.
- The settings view renders a small factual presentation model so tests can assert labels/state without scraping the Swift source. The semantic bridge reports the same authoritative value and supports a non-production toggle action for real-path verification.

### Keep the other boundaries concrete

- Continue using `PTTAttemptLifecycleRecorder` and `DesktopDiagnosticsManager` rather than adding a generic diagnostic event bus.
- Continue using the existing LangSmith and Prompt Hub modules. Add a controllable external-client/clock seam only where needed to make TTL, fallback, and correlation behavioral tests deterministic.
- Continue using the FastAPI router and sanitizer as `/metrics` and logging test seams. A deleted Prometheus deployment does not justify wrapping all counters in a new platform abstraction.
- Split mixed Crisp/screen-sync and Sentry/desktop-core files only if it improves ownership after deletion. A file move is not required merely to make the diff look symmetric.

## Ordered TDD implementation cycles

### Cycle 0 — pin the baseline and keep fences

This is research/setup, not a passing “characterization test” presented as TDD.

1. Run the requirements-ledger validator and record the immutable merge-base with freshly fetched `origin/main`.
2. Produce exact inventories for PostHog/Sentry/LangSmith identifiers; Crisp callers/routes/cache/env; Sentry bridge routes/Task fields/env; all 44 currently tracked `backend/charts/monitoring/**` files and every external reference; PTT legacy event callers; retained diagnostics; metrics; and logging.
3. Assign each hit to the action ledger or exact coordinated owner. In particular, distinguish standalone monitoring assets from service-owned metrics; remove all Mac rating callers here while handing exact shared model/backend storage residue to S-11/S-23; and hand live log-retention configuration to S-27.
4. Run existing keep tests for PTT lifecycle, diagnostics bounds, Sentry scrubbing, feedback payload, diagnostic export, QueryTracer rotation/permissions, auth sign-out, LangSmith prompt fallback, metrics, and log sanitizer.
5. Record focused-loop timing before the edit. If a keep outcome lacks coverage, do not add a test that passes against old code and call it TDD. Make the first relevant production change produce a real RED at the agreed public seam.

### Cycle 1 — owned telemetry configuration

**RED:** Through the production configuration loader, prove that a development/release build resolves product-owned PostHog host/token, Sentry DSN/environment/org/project, and LangSmith endpoint/project/prompt identifiers without accepting the current Omi literals as defaults. Cover the main error path: missing required configuration disables that external integration with a sanitized, actionable local status rather than crashing launch, logging a secret, or silently sending to Omi. For the dSYM upload script, prove missing organization/project/token fails before upload and that no Omi org/project default is selected.

**GREEN:** Move the current literals to the existing owned build/runtime injection surfaces, remove inherited Omi defaults, and wire Swift, backend templates/manifests, and the Sentry debug-symbol script. Add only the configuration value types needed by this cycle; do not yet add the Privacy toggle or rewrite every disclosure.

**Verify before next cycle:** focused configuration/script tests, sanitized missing-config logs, debug Swift compile, backend environment-render/validator tests, and a residue inventory of provider/account literals.

### Cycle 2 — PostHog preference has startup authority

**RED:** At the agreed consent controller seam, start twice with a recording PostHog adapter: saved on and saved off. Saved on may perform one setup and capture a later launch event. Saved off must perform no setup, capture, screen call, feature-flag preload, or identify. Assert the Sentry recording seam starts in both cases. Make this fail against the current unconditional initialization.

**GREEN:** Add the default-on local preference and the smallest controller/adapter. Read the preference before `AnalyticsManager.initialize`; do not initialize PostHog when off. Route product-event capture through the controller and leave Sentry startup independent. Do not rewrite event names or properties in this cycle.

**Verify before next cycle:** focused startup-on/off controller tests, one compile, and a non-production semantic snapshot showing the saved preference before any toggle action.

### Cycle 3 — runtime toggle and truthful Privacy control

**RED:** Exercise the Settings/consent production seam with the recording adapter. Turning off after identification must reset/detach the analytics identity and stop later events; turning on must initialize/resume and permit later events. The semantic privacy snapshot must report the same local state. Sentry identity/capture and Enhanced Diagnostics must be unchanged in both transitions. Include the main error path: unavailable PostHog configuration keeps the preference visible but reports that sharing cannot start without falsely reporting success.

**GREEN:** Add **Share product analytics** to Privacy, persist it locally, route its setter through the controller, and fix/remove `hasOptedOut` plus the inverted automation projection. Add one non-production semantic bridge action if the existing bridge cannot exercise the real setter. Reset/detach before opt-out, and never call Sentry from the PostHog toggle.

**Verify before next cycle:** focused controller/Settings/automation tests and a named-bundle on→off→restart→on exercise against the owned PostHog development project. Inspect the project to prove events/identity stop while off; inspect Sentry to prove it remains separate.

### Cycle 4 — S-08 identity lifecycle

**RED:** Through S-08's public auth transition seam, prove: sign-in attaches the canonical account to enabled PostHog and Sentry; saved-off PostHog does not identify; explicit sign-out records `Signed Out` while the departed PostHog identity is still present, then resets PostHog and clears Sentry; account switch cannot emit for the prior identity. Observe the current direct singleton wiring fail at least one agreed outcome rather than testing private call order.

**GREEN:** Consume S-08's owner/state transition and remove duplicate identity discovery from the consent boundary. Preserve IR-183 ordering and Sentry's opaque user ID policy. Do not add another Firebase listener, stale local account cache, or call-site exception.

**Verify before next cycle:** focused S-08 auth/identity tests, saved-off cases, explicit sign-out in a named development bundle, and owned PostHog/Sentry project inspection.

### Cycle 5 — truthful privacy presentation

**RED:** Through the Privacy presentation model and Settings semantic snapshot, assert that the page describes the actual final local/cloud/compute boundary, lists the retained PostHog/Sentry/LangSmith/local-diagnostics categories, explains the PostHog-only control, and contains neither a green **Active** server-encryption state nor the four absolute **Privacy Guarantees** claims. Assert Enhanced Diagnostics and Report/Save actions remain discoverable.

**GREEN:** Remove the fake status and duplicate card, rewrite the retained data-location and **What We Track** content from the actual inventory, and update search titles/keywords/targets coupled to those cards. Use S-30 placeholders only where the final product name or legal URL is genuinely unknown; do not invent architecture claims.

**Verify before next cycle:** focused presentation/search/automation tests, Settings navigation in the named bundle, accessibility/keyboard behavior, no purple regression, and factual comparison against the current retained services.

### Cycle 6 — one authoritative PTT diagnostic

**RED:** Drive one PTT attempt through the production lifecycle recorder with recording diagnostic and PostHog adapters. Prove the authoritative bounded lifecycle event is emitted with allowed phase/outcome dimensions and the two deprecated events are not emitted. Include a failure/recovery path and assert raw audio, transcript, prompt, device identity, and free-form error are absent.

**GREEN:** Delete `floatingBarPTTStarted`, `floatingBarPTTEnded`, every call site in `PushToTalkManager`, and exclusive comments/tests/docs/expected inventories. Keep `PTTAttemptLifecycleRecorder`, breadcrumbs, diagnostic attachment, and QueryTracer untouched.

**Verify before next cycle:** `PTTAttemptLifecycleRecorderTests`, relevant `DesktopDiagnosticsManagerTests`, Sentry scrub tests, QueryTracer tests, Swift compile, and one natural authenticated PTT turn in the named bundle. A forced transcript or reducer-only test is not real-path evidence.

### Cycle 7 — retain issue reporting and local diagnostics

This cycle changes production code only if Cycles 1–6 expose a real ownership/configuration adaptation. It must not manufacture churn in keep-as-is paths.

**RED:** Make the smallest necessary integration change first—for example, repoint the Sentry adapter used by Report Issue—and observe an existing or newly agreed public-seam test fail because the report no longer reaches the bounded owned-development destination. The test must assert outcomes: generic title, discarded typed fields, bounded attachment, enhanced/off substitution, or offline export. A source-string assertion is not behavioral coverage.

**GREEN:** Restore only the retained behavior through the owned Sentry configuration. Do not enlarge payloads or merge local export with remote submission.

**Verify before next cycle:** `FeedbackPayloadDryRunTests`, `DesktopDiagnosticsManagerTests`, `BetaEnhancedDiagnosticsConfigurationTests`, `DiagnosticsExportTests`, `QueryTracerTests`, the non-production payload dry-run plus secret scan, an actual owned-dev Sentry report, and an offline Save Diagnostics export opened from Finder. If no production adaptation is required, record this as a verified KEEP fence with no new test/code commit.

### Cycle 8 — delete Crisp without deleting support

**RED:** Through the real FastAPI app and Mac startup/navigation seams, assert `/v1/crisp/unread` is absent, no startup poll/read-state notification occurs, and the rejected Help/Crisp automation destination cannot open. In the same tracer, assert local Rewind and generic notification/report/save-diagnostics siblings still function. Do not add a keep assertion for the cloud screen-history path owned for deletion by S-15. Make the test fail on the current Crisp route/poller.

**GREEN:** Delete `CrispManager`, `HelpPage`, sidebar/home destination and presentation, startup/lifecycle calls, automation target, unread notifications, backend Crisp route/helpers/cache/env, route-policy entry, exclusive tests, and current docs. Split `desktop_screen_crisp.py` only as far as needed to leave its non-Crisp remainder clearly handed to S-15; update imports atomically without a compatibility alias and do not rename that remainder as a retained product.

**Verify before next cycle:** focused Mac navigation/startup/notification tests, `test_desktop_screen_crisp.py` narrowed to the Crisp removal and unaffected sibling boundary, local Rewind tests, route policy/OpenAPI contracts, Report Issue and Save Diagnostics tests, named-bundle startup log with no Crisp poll, and an exact S-15 residue handoff.

### Cycle 9 — delete the Sentry-to-cloud-Task bridge

**RED:** Through the public FastAPI app and generic Task presentation seam, assert the Sentry webhook/poll endpoints are absent and Sentry feedback cannot create a product Task or render Sentry-specific Task details. In the same tracer, assert desktop health/config routes and direct Mac Sentry Report Issue remain available. Make the test fail on the current bridge routes/presentation.

**GREEN:** Remove the Sentry feedback request/response models, route handlers, transform/dedupe/cache, hard-coded cloud project, Task bridge, route policy, Sentry-specific Task metadata/presentation, environment/config, exclusive tests, and docs. Keep the mixed desktop health/config router and generic Task surfaces.

**Verify before next cycle:** adapted `test_desktop_core.py`, route policy/OpenAPI contracts, generic Task projection tests, desktop health probe, `FeedbackPayloadDryRunTests`, owned-dev Sentry report, and residue search for `sentry_feedback` plus old project identity.

### Cycle 10 — delete the in-app rating product without deleting model observability

**RED:** Through normal-Chat and floating-Chat action presentation with recording API/analytics adapters, assert that assistant messages retain copy, info, and timestamp behavior but expose no thumbs action, cannot mutate a rating, call no rating endpoint, and emit no `Message Rated` product event. Assert Chat Lab does not fetch or present production rating aggregates. In the same tracer, prove an agentic Chat run still produces the LangSmith trace/run correlation needed for website-side operator evaluation. Make the test fail on the current `ChatBubble`, `AIResponseView`, `ChatProvider.rateMessage`, and `APIClient+Messages.rateMessage` flow.

**GREEN:** Delete the normal/floating thumbs UI, `onRate` plumbing, dedupe shadow state, desktop rating client method, provider mutation/rollback, rating event helper/call, and Chat Lab production-rating reader/presentation. Remove `submit_langsmith_feedback` and imports only after the caller inventory proves they are rating-only. Keep generic message rendering/actions and LangSmith tracing. Do not remove shared message rating fields or backend/mobile routes/storage in this cycle; write the exact S-11/S-23 handoff and leave no Mac caller.

**Verify before next cycle:** focused normal/floating Chat presentation and action tests, API recording test, Chat Lab tests, Swift compile, agentic Chat trace test, named-bundle normal/floating message inspection, and a residue inventory split between “must be absent now” and exact S-11/S-23-owned files/routes/fields.

### Cycle 11 — owned LangSmith trace and Prompt Hub lifecycle

**RED:** At the production LangSmith/Prompt Hub seams with an injected external client and clock, prove:

1. an owned remote prompt success returns template plus source/commit/version metadata;
2. repeated access inside the five-minute default TTL does not refetch;
3. expiry refetches;
4. missing key, network error, missing prompt, or invalid template uses the complete repository fallback with truthful source metadata; and
5. one public agentic Chat run carries the chosen prompt metadata and a correlatable LangSmith run ID into the retained trace/Chat association.

Also assert that no Mac thumbs control or cloud rating call is required for operator annotation/evaluation. The error path must be non-fatal and sanitized.

**GREEN:** Repoint endpoint/project/prompt defaults and environment/runtime manifests to owned resources, normalize configuration consumption, and add only the client/clock injection needed for deterministic tests. Preserve global/scoped tracing, callbacks, startup status, operator-side evaluation, and fallback prompt. Keep the rating-only product feedback helper deleted from Cycle 10; do not replace it with another in-app or cloud rating path. Do not delete S-11/S-23's shared Chat/rating storage in this slice.

**Verify before next cycle:** focused LangSmith and prompt-cache tests, agentic Chat correlation test, backend startup status with key absent, one owned-dev remote-prompt run, one forced fallback run, and inspection in the LangSmith project. No live service is used in CI.

### Cycle 12 — delete the standalone monitoring product, retain operations

**RED:** Extend existing deploy/workflow/manifest contracts so the rendered deployment graph cannot install `backend/charts/monitoring/**`, Grafana, Loki, Alloy, Alertmanager, Prometheus Adapter, or the Stackdriver exporter. Separately, through the real FastAPI app, assert `/metrics` returns unauthorized for missing/wrong `METRICS_SECRET` and a bounded low-cardinality payload for the correct secret; through the sanitizer, assert representative API key/token/email/transcript-like content does not reach emitted logs. Label file/deploy absence checks as static/deployment contracts, not behavioral user tests.

**GREEN:** Delete all standalone monitoring files and exclusive workflow/check/script/test/runbook/env/secret references. Adapt mixed workflow and deployment contracts to managed observability without removing unrelated service checks. Preserve the `/metrics` router, secret, useful counters, sanitizer, ordinary logs, Cloud Logging, and service-owned chart fragments assigned to later slices. Add no replacement collector, dashboard stack, log agent, sink, or archive.

**Verify before review:** focused metrics/auth/sanitizer tests; monitoring alert/workflow/deploy contract tests after removing obsolete cases; runtime-env render/validator; backend test discovery; owned-dev Cloud Run request/log inspection when the S-27 foundation is available; an explicit S-27 handoff for live 30-day/no-archive proof; and a deployment residue inventory distinguishing later-owner chart fragments from forbidden standalone monitoring.

## Review and simplify after GREEN

Do not perform this work while any cycle is RED.

1. Remove unnecessary PostHog SDK exposure, duplicate preference/config readers, inverted booleans, obsolete wrappers, compatibility aliases, dead event helpers, orphaned cache keys, and mixed-module names left by deletion.
2. Inspect the dependency direction. Settings, auth, and event callers may depend on the narrow product-analytics controller; the controller may depend on the external SDK adapter and preference store. PostHog must not depend on Settings/Auth singletons, and Sentry must not conform to the PostHog consent interface.
3. Review every remaining event/property category against IR-205 and privacy boundaries. This is not authorization to redesign unrelated analytics; record out-of-scope questionable events for their owner.
4. Review deletion residue by product, not by filename: Crisp route plus client plus startup plus notification; Sentry bridge route plus transform plus Task projection; monitoring chart plus workflow plus tests plus docs plus secrets; PTT helper plus all callers and inventories.
5. Re-measure the focused loops. Keep any acceleration only if recorded timings improve without weakening the full-suite or CI contract.
6. Decide whether a stable recurring check is still needed. Wire it into `.github/checks-manifest.yaml` with local and CI lanes only if ordinary compilation/config/deploy contracts cannot prevent recurrence, and cite the actual removed surface it would have caught.
7. Invoke `engineering:code-review` against the immutable implementation merge-base. Run independent Standards and Spec Compliance reviews, present findings by axis, fix all valid findings, and rerun each affected focused and full check.

## Verification and closure evidence

Implementation is not complete until commands, exit status, short results, and real-path observations are recorded. Adjust selectors to the current component guide if filenames move; do not silently omit the protected behavior.

### Focused and full automated checks

```bash
# Repository/requirements integrity
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check

# Swift feedback loops and contract quality
cd desktop/macos
./scripts/dev-feedback.py --once swift 'ProductAnalytics|Privacy|Auth|PTTAttemptLifecycle|DesktopDiagnostics|Feedback|DiagnosticsExport|QueryTracer|Crisp|ChatBubble|AIResponse|Rating'
python3 scripts/check_desktop_test_quality.py
xcrun swift build -c debug --package-path Desktop
./scripts/agent-logic-harness.sh --swift-only

# Backend focused behavior/deploy contracts; exact paths follow the pinned baseline
cd ../../backend
python3 -m pytest \
  tests/unit/test_desktop_screen_crisp.py \
  tests/unit/test_desktop_core.py \
  tests/unit/test_log_sanitizer.py \
  tests/unit/test_monitoring_alert_rule_contract.py \
  tests/unit/test_verify_pusher_dev_observability.py \
  tests/unit/test_workflow_contracts.py
bash test-preflight.sh
bash test.sh

# Whole-repository PR contract after all review fixes
cd ..
scripts/pr-preflight --suggest
make preflight
```

New test files must live where the component runners discover them. Hermetic tests use recording fakes for PostHog, Sentry, LangSmith, clocks, and external delivery; they must not call live services, sleep, or rely on ordering. Static deletion/deploy checks must carry the repository's static-contract label and are not substitutes for behavioral tests.

### Residue closure

Run scoped, case-insensitive searches over production source, tests, package manifests/locks, workflows, runtime/deploy configuration, current docs, generated clients, route policy, fixtures, and scripts. At minimum classify:

- current Omi PostHog token/host, Sentry DSN/org/project, LangSmith project/prompt defaults, hard-coded GCP project names, and inherited environment names;
- `floating_bar_ptt_started`, `floating_bar_ptt_ended`, and their Swift helper names;
- `Crisp`, website ID, unread route/cache/poll/notification/help destination;
- Sentry feedback webhook/poll/task names, `sentry_feedback` metadata, and Task presentation;
- `backend/charts/monitoring`, Grafana, Loki, Alloy, Alertmanager, Prometheus Adapter, Stackdriver exporter, Omi dashboards/rules/releases;
- Mac thumbs/rating controls, API calls, analytics, Chat Lab production-rating views, or product feedback helpers used as a LangSmith dependency;
- fake **Active**, **Privacy Guarantees**, and stale tracking/disclosure copy.

Every remaining match must be one of:

1. a retained owned service/configuration and current factual doc;
2. an immutable historical changelog or requirement artifact;
3. a service-owned metric/chart/counter with an exact later slice owner;
4. a shared model or backend/mobile Chat/rating surface handed exactly to S-11/S-23, with no remaining Mac caller;
5. Windows/out-of-scope code.

There may be no unexplained live credential/default, UI, event, route, startup job, cache, notification, Task projection, deployable monitoring asset, current doc, test, fixture, or secret reference.

### Real user/operator exercises

Use a unique development bundle such as `omi-s09-observability`; never stop, replace, attach to, or modify `/Applications/Omi.app` or `/Applications/Omi Beta.app`.

1. Build and launch the named bundle with owned development PostHog/Sentry configuration. Use the semantic bridge to open Privacy and prove the default-on state.
2. Sign in through the S-08 path, emit one bounded product event, and observe the canonical owned identity in PostHog. Turn sharing off, emit another event, restart, and prove no off-period event/screen/identify reached PostHog. Prove Sentry remained enabled. Turn sharing back on and prove subsequent capture resumes without the old identity leaking.
3. Explicitly sign out and inspect both owned projects: `Signed Out` belongs to the departed PostHog identity, then PostHog is reset and Sentry user identity is cleared.
4. Run one natural authenticated PTT success and one controlled failure/recovery. Inspect local diagnostics and owned remote events for the authoritative lifecycle only and secret/content bounds. Confirm QueryTracer still rotates/writes locally.
5. Submit Report Issue from a retained entry point. Inspect the owned Sentry project for the generic title, release/environment tags, breadcrumbs, and bounded attachment. Use the dry-run/secret scan. Then turn Enhanced Diagnostics off and prove the existing filtered substitute, not a disabled Sentry client.
6. Save Diagnostics to a chosen local file, inspect the size/line/redaction bounds, and confirm no network upload. Reveal it in Finder.
7. Restart/navigate the bundle and inspect app/backend logs: no Crisp poll, Help destination, unread notification, or Sentry-to-Task request occurs. Confirm local Rewind, health/config, generic notifications, generic Tasks, and support/export siblings still work; record the non-Crisp cloud screen-history remainder for S-15 without exercising it as a retained path.
8. Inspect normal and floating assistant messages: copy/info/timestamp behavior remains, but no thumbs action exists and no rating network/event traffic is emitted. Inspect Chat Lab to confirm it no longer reads production rating data. Then run an agentic Chat query against the development backend with owned LangSmith configuration, inspect prompt source/version plus correlated run, and use the provider website for operator evaluation. Force Prompt Hub failure and prove the repository prompt completes the path with truthful fallback metadata.
9. Call development `/metrics` with no, wrong, and correct secret. Trigger representative sanitized logs and, when S-27's development Cloud Run foundation exists, inspect Cloud Logging for correlation without raw secrets/content. Record the exact S-27 acceptance handoff for live `_Default` 30-day retention and no archive/sink; S-09 must not claim that infrastructure proof early.
10. Render/inspect the development deploy graph and prove the standalone monitoring release cannot be installed. Do not treat the continued existence of later-owner service counters or chart fragments as a failure if the handoff is exact and non-deployable without the deleted stack.

If owned credentials, project access, or a safe development backend are unavailable, name the exact blocker and leave S-09 open. Hermetic tests cannot substitute for the map's requirement to verify owned development projects before production configuration is installed.

### Final repository proof

- Re-fetch `origin/main` for drift awareness, but keep the review fixed point at the immutable merge-base recorded before implementation.
- Run `scripts/pr-preflight --suggest` and name every matched invariant/failure-class requirement before drafting a PR body. Any `fix:` commit requires the repository's `Failure-Class` declaration; do not label this planned simplification as a bug fix unless a real failure is repaired.
- Run `make preflight`, full affected component suites, and all named-bundle/owned-project exercises after review fixes.
- Inspect `git diff <fixed-point>...HEAD`, `git status --short`, and the commit series for unrelated or user-owned changes.
- Confirm component guides, current docs, environment templates, runtime manifests, generated clients, and package locks changed with their owned code.
- Record verification evidence in commits/PR description. Stop at local commits unless the user separately authorizes push/PR creation.

## Completion checklist

- [ ] The nine public seams were approved before tests were written.
- [ ] S-08's canonical identity/sign-out contract was available and consumed without a second authority.
- [ ] Owned PostHog, Sentry, LangSmith, and Google Cloud development identifiers/access were available; no Omi default remained on a live path.
- [ ] Every production change began with one observed behavioral or deploy-contract RED and the minimum GREEN; no bulk tests-first phase occurred.
- [ ] Saved-off startup performed no PostHog setup/capture/identify, runtime toggle worked, and Sentry remained independent.
- [ ] Sign-in, account switch, and explicit sign-out passed hermetic and owned-project identity verification in the required order.
- [ ] Privacy copy/state matched the retained architecture; fake **Active** and duplicate guarantees were gone.
- [ ] The authoritative PTT lifecycle, QueryTracer, Enhanced Diagnostics, Report Issue, entry points, and offline export passed unchanged boundaries.
- [ ] Both deprecated PTT PostHog events and every live caller/inventory were gone.
- [ ] Crisp and the Sentry-to-cloud-Task bridge were deleted as complete codeflows without harming their retained siblings.
- [ ] Normal/floating Chat rating controls, client calls, rating analytics, Chat Lab production-rating view, and rating-only LangSmith helper were gone; shared backend/model residue had an exact S-11/S-23 owner and no Mac caller.
- [ ] LangSmith prompt source/version/run correlation, TTL, fallback, and website-side operator evaluation worked in the owned project without an in-app rating dependency.
- [ ] The standalone self-hosted monitoring product was undeployable and absent; authenticated metrics, useful counters, sanitizer, and Cloud Logging remained, and S-27 owned explicit 30-day/no-archive deployment proof.
- [ ] All remaining residue was classified to a retained system, immutable history, Windows, or an exact S-11/S-23/later-service owner.
- [ ] Focused tests, full affected component suites, named-bundle exercises, owned-project inspections, `make preflight`, and `git diff --check` passed with recorded evidence.
- [ ] `engineering:code-review` completed both Standards and Spec Compliance axes against the immutable fixed point; valid findings were fixed and checks rerun.
