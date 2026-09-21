# Intentive repository brief

This authored brief sets scope, priorities and current working constraints. Read the
applicable sections before changing code; use [quickstart](quickstart.md) for source-backed
explanations. Full decisions and dated records remain in [Git history](#accepted-requirements).

## Scope

- Use unmodified OpenWiki 0.5.2, its project-scoped Codex integration and Node 22.22.0.
- Document active macOS, its Node runtime, the canonical Python backend, tests and delivery
  under `codebase/`, organized by systems/workflows. `codebase/` is the complete wiki scope
  and the default destination for generated pages.
- Windows is paused: exclude `desktop/windows/` and Windows-only surfaces from research/changes.
- Honor `.openwikiignore`; exclude credentials, private state, dependencies and build outputs.
- Generate implemented behavior from source/tests. Authored decisions and dated observations
  are not mechanically verified Claims or proof of deployment, acceptance or release readiness.

## Wiki maintenance

- Install `openwiki@0.5.2` under the pinned Node, then run
  `openwiki integrations install codex --project .` and restart Codex for discovery.
  Use its existing authenticated model session; no separate provider account or tracing service.
- After source/tests stabilize, complete the native skill's begin → plan → page queue → finish
  lifecycle. Include affected wiki changes with code; use `force: true` for brief-only changes.
- Resume interrupted runs. Never hand-edit Claims, generated indexes, checkpoints or completion metadata.
- Init preserves this brief; other wiki content is generated state. Remove any scaffolded scheduled
  workflow before committing. Updates happen during Codex work.
- Keep only active instructions here. Generated pages own source-backed explanations/commands;
  Git owns full decision histories, old tutorials and dated receipts. Do not copy the archive back in.
- Use standard OKF Markdown and package `resource: repo://<package-path>` metadata. Keep link,
  agent-size and architecture checks in the shared local/CI manifest, not a parallel validator.
- Change authored policy only with user authorization. Documentation edits close no open obligations.
- The tracked product map is `docs/architecture/intentive-codeflow.mmd`. Maintain it through
  reviewed edits when relevant product flows change; no automatic graph refresh is required.

### PR closeout

- Finish source/tests and the native OpenWiki update in this feature PR so the next Conductor
  workspace inherits the code and documentation together.
- Review the Mermaid product map when affected flows change. Commit intended source, tests and
  documentation, then run the required PR preflights. Integrate newer main and revalidate before merge.
- Publish only when requested. Report check results and any failures. Create PR does not merge
  or archive the workspace.

## Engineering rules

- Behavior changes need production-seam regression tests or core/error-path tests. Exercise the real
  path, run affected component suites and record commands, outcomes and unexercised boundaries.
  A nonzero runner remains a failure even when its assertions passed.
- Use the current worktree/branch; run `make setup` before the first commit and inspect upstream
  changes before integration. Revalidate overlapping rebases. Commit locally by default;
  do not rename/switch branches, push, open PRs or merge without explicit authorization.
- Land through regular-merge PRs only. The established revert/verified-peer-review exceptions remain
  in the [archived engineering rules][engineering]; migrations, release/CI, schema, access control
  and data deletion still require explicit sign-off. Approval does not carry into later changes.
- Never stop, replace, delete or automate production Omi/Intentive Stable or Beta apps.
  Testing targets a named development bundle and exact owned processes.
- Fix the violated owner/identity/state-transition contract. Inspect recent related fixes;
  repeated causes need a reusable guard backed by a real incident/merged PR. Prefer typed APIs,
  target dependencies and access control. Explain why a new guard is not a shared primitive.
- Migrate all in-tree callers together: no compatibility aliases, duplicate adapters, fallback flags
  or second mutable authority preserving a retired shape. Keep related opportunistic repairs small,
  independently verified and separately committed; track larger work instead.
- New TODO/FIXME/HACK markers need issue references. Designated rollout scaffolding needs LIFECYCLE
  and, when one-time, DELETE-AFTER. Oversized packages need substantive wiki architecture maps.
- Hermetic CI has no live services, network, sleeps or ordering dependency. Label narrow source
  tripwires honestly; new fail-closed gates need legacy-principal coverage. Rewritten expectations
  need an external contract. Fix/delete obsolete flaky tests rather than weakening confidence.
- Before PRs run `make preflight` and `scripts/pr-preflight --pr-body-file <body>`.
  Before a `fix:` description run `scripts/pr-preflight --suggest`; fix commits declare and validate
  `Failure-Class: FC-<slug> | new | none` with `scripts/failure-class`.
- Wire checks into both lanes of `.github/checks-manifest.yaml`; repair manifest omissions rather
  than adding one-off workflow gates. Pre-push remains bounded to 40 broadly selected backend files
  and desktop debug compilation; full suites/release builds retain their existing CI/acceptance lanes.
- Keep rules mechanical. A guidance-caused defect needs corrected guidance or a guard in the same
  fix PR. Product/operational docs move with code. Ratchet baselines only decrease.
- Use the installed formatting wrappers; retain Black's `--skip-string-normalization` and exclude
  generated Swift sources. No unrelated formatting/refactoring.
- Never log sensitive content/credentials. Use component sanitizers and bounded metric dimensions;
  provider/mode/correctness changes and fail-open paths use existing `record_fallback`/`recordFallback`.
- Report completion in the originating channel. No inherited sender or guessed support identity is approved.

## Product constraints

- Protect Capture → Understand → Remember → Retrieve → Act through reliable ownership, recovery,
  grounding and durable harnesses. Use neutral/white UI; purple is forbidden (`INV-UI-1`).
- Primary navigation is Home, Memory, Tasks and Insights. Chat is a Home stage; Memory contains
  Memories/Conversations and Insights contains Insights/Focus. No hosted dashboard fallback.
- Conversations, Rewind OCR/video/vectors, Memory, tasks, simple goals, Focus, Insights and AI Profile
  remain owner-local. Never restore hosted product-data authority, reconciliation or fallback stores.
  Conversation IDs originate locally; recovery selects rows before the fixed app-launch cutoff.
- Node SQLite owns the Chat catalog/journal; Swift owns drafts/attachment bytes. Home/floating Chat
  share one accepted journal projection (`INV-6`), including proactive-notification continuity.
  Backend greeting/title/assistant work is bounded transient compute, not a hosted catalog.
- Normal Chat/background work uses managed Gemini 3.7 Flash, preserving native tool/image/thinking
  payloads and signatures. No account-unavailable background 2.5 defaults or public provider/model/
  working-directory selector. Segment translation remains Gemini 2.5 Flash-Lite.
- Realtime is Gemini Live: same-provider reconnect first, then bounded PCM and existing silence-gated
  batch STT → Chat → OpenAI TTS recovery. OpenAI is spoken output only with system-voice fallback.
  Ambient STT, voice-message STT and physical PTT remain distinct.
- Speech is Mac-local Parakeet or managed Modulate. `/v4/listen` is one Firebase-authenticated,
  transient fixed mono 16 kHz signed PCM stream with snapshotted language/translation/vocabulary,
  stable UUID segments and numeric speakers. The backend never creates/finalizes a stored conversation.
- Live and saved transcripts use spoken start time, then original arrival order for ties, before
  adjacent-speaker normalization. Same-ID corrections preserve that tie and translations; reopening
  the local store must agree with the live projection (#70).
- Conversation operations and three Memory compute operations return bounded untrusted candidates;
  commit locally only with current captured owner/input revision. Embedding compute may be remote,
  vectors/search stay local. Fair-use compute retains only content-free enforcement facts.
- New Memory begins Short-term; normal reads show active Short-term/Long-term rows. Preserve Archive,
  expiry, dismissal, pending deletion, provenance, Undo and revision-bound lifecycle receipts.
  Insights are `tips` Memory records, not another authority.
- Tasks keep local CRUD/order/reminders/recurrence/source linkage/five-second Undo; simple goals keep
  local identity and active/completed state. No ranking/staging/productivity-score/task-chat system.
  Focus keeps current/today/recent state; AI Profile keeps five prior profiles.
- Assistant/notification controls stay local. Cloud FCM, hosted Focus/Profile/assistant settings,
  Daily Summary, People/voice identity, cloud recordings/playback and public sharing remain retired.
  Quota/fair-use facts remain server-authoritative with truthful owner-local presentation.
- Export deterministic owner-generation-fenced JSON from local authorities and approved settings,
  without network or raw databases/secrets/caches. Backend export is retained account metadata only.
  Durable account deletion confirms billing cancellation before irreversible identity/data deletion.
- Deletion acceptance requires confirmed durable queue handoff or observed delivery of the same job,
  not intent persistence alone. Unconfirmed enqueue failure preserves signed-in retry; dispatch-attempt
  fencing protects newer attempts and claimed workers. Immediate sign-out follows genuine acceptance
  without a polling screen (IR-189/S-25); a process-local timer is not a scale-to-zero guarantee.
- Hosted Beta admits configured one-to-five Firebase participants plus the reserved release probe;
  unlisted authenticated accounts retain export/deletion. Dev is isolated, billing disabled, and
  customer provider keys are forbidden. No paid/public launch is implied by implementation approval.
- Downloaded updates relaunch only when the authoritative activity snapshot is idle. Capture,
  finalization, voice/provider/playback/tool/token and Chat work defer installation; never force idle
  with a timeout. Development builds install on quit.
- Before changing a boundary, locate owning code/tests and its applicable archived IR decision.
  Cite the applicable principle or concrete guard when declining a product change.

## Backend guidance

Read [backend architecture](codebase/architecture/backend.md), [development](codebase/operations/development.md)
and [test contracts](codebase/testing/contracts.md) for current commands and mechanisms.

- Use the backend-owned Python 3.11 interpreter/lock and existing dependency scripts; avoid incidental
  upgrades. Keep local/offline and hosted configuration separate. Hosted auth uses runtime ADC,
  rejects credential files/admin impersonation and fails closed on invalid participant configuration.
- Classify typed failures by reason/provider/route/status/retryability. Provider 401s and
  session-preserving polls must not invalidate Firebase identity.
- Async HTTP uses shared pools/semaphores/circuit breakers; blocking leaf work uses purpose-specific
  executors through `run_blocking`. Keep orchestration async; no cross-pool worker waits, ad-hoc threads,
  unowned background tasks or thread slots held across long pipelines. Preserve shutdown/transport bounds.
- WebSockets use supervised named tasks, bounded drain, `gather_safe`, receive timeouts and
  disconnect-interruptible waits. Snapshot mutable state before spawning; balance gauges in finally,
  bound caches and keep metric labels static. Run the existing async-blocker scan after boundary changes.
- D4 (2026-07-04): database modules return domain dictionaries without wire-model imports;
  normalizers coerce native values and router response models validate/serialize the wire boundary.
- Type public APIs/config; receive dynamic input as `object`, validate/narrow it, confine `Any` to
  external edges and explain rule-specific ignores. Preserve callable types and timezone-aware dates.
  Zero errors/warnings is the target; report warning debt separately from runner success.
- Imports perform no I/O/client construction/global mutation. Use lazy getters/startup and dependency
  overrides, not arbitrary in-function imports. No test-module `sys.modules` mutation; scoped pre-import
  fakes use the isolation helper. Shrink allowlists and enroll repaired files in the single-process-safe subset.
- Use strict Firestore transaction fakes for supported operations; uncovered ordering/retry/contention
  needs emulator proof. Route policy identity is service/type/method/parameterized path; never grow its legacy list.
- DD-007/#29: cache approved projections only; security/privacy/entitlement fields need separate review.
  Firestore stays authoritative on cache failure; invalidate after writes. No sensitive keys/labels;
  begin disabled with shadow/mismatch evidence and disable/namespace-version rollback.
- Use `sanitize`/`sanitize_pii`; omit OAuth query strings and raw response/error bodies from logs.
  Live-journey metrics exclude synthetic traffic, emit idle zeros and never replace durable workflow state.
  Required failed steps cannot report success; STT success is the first nonempty sent payload, not UI rendering.
- High-risk workflows live in `backend/testing/workflow_contracts.json` with first-run, partial failure/retry,
  completed resume, idempotent skip and side-effect-failure coverage. Retain runner-based test discovery.
- Use the runtime-image registry and pinned OpenAPI runner; generated Swift DTOs validate against the
  live app-client schema. Keep secrets/private state outside image contexts; smoke the deployed digest.
- Support resets need operator intent, dry-run/reason/before-after totals/audit. No real-user apply in CI,
  guessed support endpoint or automatic goodwill credit. Chat-quota reset awaits retained-counter tests.

## Desktop guidance

Read [runtime architecture](codebase/architecture/desktop-agent.md), [development](codebase/operations/development.md)
and [desktop E2E](codebase/testing/desktop-e2e.md) for implementation and operating commands.

- Use SwiftPM through `xcrun`; honor the deployment floor with working availability fallbacks.
  New Swift files belong in feature directories; extract leaf modules bottom-up with explicit APIs.
- Use the owned launcher and unique `omi-<task>` bundles, never overwrite canonical Dev or manufacture
  Stable/Beta locally. Per-worktree locks and machine-global app names are separate boundaries.
  Prefer semantic bridge actions; verify health, negotiated runtime capabilities and exact log path.
- Routine Dev uses local emulators/Redis/synthetic users; hosted `--yolo` is explicit. Opt-in seeding
  comes from canonical Intentive Dev only, never Beta/Omi. No cloud administration in local defaults.
  Private state stays on protected storage; preserve profiles/evidence/caches during archive.
- `AuthSessionCoordinator` owns session death (`INV-AUTH-1`): revoked credentials use `invalidateSession`.
  Provider health/realtime failure has a separate owner and must not sign out a valid Firebase session.
- Reducer publication is atomic; synchronous callbacks enqueue FIFO without recursive reduction.
  Dictionary construction needs explicit non-trapping merge policy unless uniqueness is statically proven.
- INV-6: one main Chat provider/replaceable turn handler/opaque turn idempotency key; journal acceptance
  before visibility, ordered replay/upsert by canonical ID. Floating views/pills are derived: no second
  transcript, text-based identity or suppression boolean. Resources stay on their producing message;
  agent previews use the prompt. Extend schemas, cross-surface decode and behavioral tests together.
- Kernel capability policy and immutable execution profiles authorize tools; request IDs only correlate.
  Keep context/capability fingerprints distinct, DDL store-owned and generated protocol surfaces synchronized.
  Realtime owns the voice session, not Chat routing; tool effects still require kernel authorization.
- Telemetry emits one terminal outcome; Stop/supersession is cancellation. Chat latency ends at visible
  answer, voice latency at playback drain. Later persistence failure cannot rewrite delivered output.
  Authority never depends on telemetry; PostHog/traces are shape-only with protected diagnostic storage.
- Await fixture restoration in teardown. Prefer clocks/callbacks to sleeps and production behavior to
  source-string assertions; narrow static tripwires require the established justification annotation.
- User-visible changes need a changelog fragment; automation owns CHANGELOG.json. Cleanup requires
  exact identity/token/sentinel and current plan, never a process-name match.

### Runtime reliability boundaries

- Background Gemini uses `ModelQoS`'s account-available Flash route (#102); deploy proxy/shipped-client
  mapping before a candidate requiring it and retain authenticated routing tests.
- `SystemCaptureModeProbe` uses one off-main window query and monotonic bounded cache (#103).
  Keep capture nonblocking and permission/owner/lock-screen gates independent.
- `AudioLevelDelivery` allows one pending latest-value MainActor meter delivery. Stop invalidates samples;
  activate the next generation only on the serial audio queue after old HAL work quiesces. No extra caller
  hop; PCM is separate and never coalesced.
- Playback owns AVFoundation on a serial worker. SDK acknowledgement gates progress/final text/completion;
  Stop invalidates callbacks and recovery replays only the current unplayed tail. Retain stalled-hardware,
  recovery and acknowledgement-order tests.
- Aged idle voice resets use the existing rewarm policy. Active/fast failures and failed mints remain
  observable; idle-close classification is not proof of recovery.

## Desktop testing guidance

Use the [tier commands and evidence boundaries](codebase/testing/desktop-e2e.md).

| Changed surface | Minimum evidence |
| --- | --- |
| Transcription/audio; Rewind persistence/recovery/privacy | T2 |
| Chat provider/runtime | T0 + T3; agent-logic harness |
| Primary navigation | T1 |
| Home stage; Memories/tasks CRUD | T2 (Home includes home-stage flow) |
| Secondary detail/vocabulary/goals/billing/privacy | T2 + Live P2 for manual-only paths |
| Beta promotion | Exact signed-artifact digest gate + T0 + T2 + Fault |

- Acceptance runs affected component suites: `backend/test.sh`, `desktop/macos/test.sh` and Node build/tests.
- Continuity/write-path changes need hermetic INV-6 tests and the named-bundle continuity gauntlet.
  Prompt/gateway changes need prompt gauntlets; RC uses all. CI uses hermetic self-checks only.
- Voice UX proof is natural authenticated physical PTT with nonzero capture; controller/injected-PCM
  probes are diagnostic only. Provider mint/payload changes also need the deploy-inline probe.
- Green QA evidence binds clean full source SHA and matching backend/harness fingerprint. Preserve
  hash/size-only gauntlet receipts, no raw content/media/secrets and no model-wrongness retries.
- Test auth/onboarding through their real flows. Destructive account actions remain manual: automated
  deletion checks stop before confirmation, and logout tests use the emulator.
- Review UI screenshots visually. Bundle-size acceptance needs before/after bytes and runtime smoke;
  prune through packaging scripts, not installed development dependencies.

## Delivery guidance

Read [release operations](codebase/operations/releases.md) and [qualification](codebase/operations/qualification.md).

- Normal code lands through regular-merge PRs with the repository's retained checks. Remote
  protection settings must be verified separately; local implementation is not proof of enforcement.
- The weekly guardrail report may append its history directly to main through the dedicated
  `Intentive Guardrail Pulse` App. Install it only on this repository with Contents write and
  Metadata read, and keep its credentials in the `guardrail-pulse-publisher` environment restricted
  to main (`GUARDRAIL_PULSE_APP_CLIENT_ID` variable and `GUARDRAIL_PULSE_APP_PRIVATE_KEY` secret).
  Only that App receives an audited `always` ruleset bypass; never grant the shared GitHub Actions
  or release App this exception. GitHub cannot scope an App bypass to one file, so the publisher
  must enforce append-only changes to `.github/guardrail-pulse-history.jsonl`, validate the complete
  candidate, retry competing pushes at most three times from fresh main and never force-push.
  Report-only changes are outside the UA scope and require no model refresh. Preserve issue updates
  using the existing `GITHUB_TOKEN`. Provisioning, publication, merge and rule activation belong to
  the explicitly requested publication rollout.

- Main eligibility is automatic; shared Dev deployment is manual through protected `gcp_backend.yml`.
  Resolve `BACKEND_CLOUD_RUN_SERVICE`; never default to the logical image label `backend`.
  Dispatch uses the approved environment, `mode=deploy` and exact merged `release_sha`, not `branch`;
  merging or the RELEASEWITHBACKEND shorthand never implies production approval.
- Persistent mutations share exact target/environment concurrency with `cancel-in-progress: false`.
  Backend traffic/Firestore migrations share the backend-stack lock; GitHub does not guarantee FIFO.
- Backend deploys use manifest-owned WIF and exact repository/owner/main/environment/workflow claims,
  never JSON keys. Deploy full-SHA tags at their smoked digest; install the whole staged workflow-control tree.
- Preserve candidate/no-traffic validation → snapshot/promotion → serving-vector verification → conditional
  rollback, mandatory status reporting and exact canonical release-vector checks.
- Firestore readiness is read-only on the approved candidate; writes use the separate protected manual
  writer workflow. Proposals are validated/redacted; foundation declarations are not live evidence.
- Codemagic builds Mac artifacts; GitHub selects/observes/qualifies/promotes. Require owned signing,
  Firebase/Sparkle/analytics/endpoints, nested libwebp validation before outer signing, exact signed
  ZIP/DMG bytes/smoke hashes and owner-uploaded qualification. Never substitute upstream identities.
- Qualification is owner-manual; never register the everyday Mac as an Actions runner. Readiness,
  T2/Fault, source identity, admission generation, owner upload and pointer state must agree before mutation.
- Stable promotion is explicit/manual from qualified Beta. Rollback cannot downgrade installed clients.
  Break-glass relaxes only its documented evidence gate, never merged-source or promotion authority.
- Preserve the 32 GiB/65,536-inode runner floor, bounded 16-entry/128 GiB reclaim and exact process owner.
  Do not skip UX gates for the 1,200-second target; stale qualification-helper cleanup is manual.
- Release-health semantics are versioned: terminal-only numerators, exclusions, matching windows and
  minimum samples; insufficient data is unknown. Preserve [schema 4 query definitions/thresholds][health]
  while excluding the explicitly superseded OpenAI-realtime and hosted-Memory examples.

## Provenance and ownership

- BasedHardware/omi source: `99e0e60be67a4f727ddfab4858184d75da2494a5`, tag `v0.12.147+12147-macos`,
  snapshot 2026-07-30. Preserve MIT/vendor notices; upstream releases do not prove this fork shipped.
- Owned names: Intentive / `heyintentive` / `heyintentive.com`; bundles `com.heyintentive.intentive`,
  `.beta`, `.dev`, `.dev.<name>`, `.preview.<name>`. No `intentive.life`/`intuitive.life` or inherited
  Omi branding, plists, credentials, prompt content or sender defaults.
- Keep `sruj75/knowledge-athlete`, Firebase/GCP `knowledge-athlete`, Apple Team `24D6NXS6H7`, Codemagic
  app `6a8ff0296fc70d39540cb56a` and the existing Intentive website. Google operator is
  `srujan@heyintentive.com`, Apple account `22btrsn071@gmail.com`, GitHub owner `sruj75`.
- Preserve the permanent-Free-Tier operating constraint: no Google Memorystore, budget increase or
  prepaid auto-reload by implication. Never invent business identity/documents. Reverify external state
  against the [dated owner/provider handoff][ownership] before acting; old resource snapshots are not current proof.

### September 14 owner-Beta checkpoint

- The owner installed signed/notarized `v0.0.4+4-macos`, source `80475aab8488d226fffca2025ba96f1a3183294a`,
  and completed the real 0.0.3 → 0.0.4 Sparkle update on September 12. Populated Chat/recording data
  survived; other populated stores, natural managed voice and friend qualification remain unproven.
- Owner Beta uses the existing shared `knowledge-athlete-dev` service. Its historical name is not
  permission for routine Dev to use everyday accounts or modify shared data; use local emulators
  and synthetic owners. The owned local database is `heyintentive.db`, not an inherited-profile import.
- Apple signing/notarization, Codemagic owner-Beta inputs, owner-manual qualification and published
  product/Terms/Privacy/Support destinations were exercised. Stable/Preview and public-launch legal
  work remain separate; no permanent everyday-Mac runner is required for owner qualification.
- At that checkpoint, the last successful backend deployment was source `4a6e943cce0d512c462d381c9483ae478a816e47`;
  repair source `97c88ba2db3117a112b562c62fc38f9aecf68f1b` was pushed but not merged, deployed or installed.
  These are dated receipts, not a live inventory or permission to combine different-SHA evidence.
  Preserve the [reconciled owner handoff][repair-ownership] and [fork evidence][repair-provenance].

## Asset provenance

Owner approval (2026-09-03) covers the canonical monochrome icon, moss-garden source and DMG composition.
Preserve mark geometry, complete square backdrop source and neutral styling; the rejected grass icon
must not ship. [Pinned asset provenance][assets] retains exact hashes, derivatives and generation records;
product-use approval does not assert an additional third-party license.

## Security policy

- Report privately through this repository's Security tab when available, otherwise obtain a private
  maintainer channel. Include affected commit/surface, impact, reproduction and sanitized evidence.
- Use owned accounts/data; stop on another user's data, avoid disruption and coordinate disclosure.
  Do not post unpatched exploit details publicly.
- The [inherited policy][security] is provenance; its upstream address, product scope and response-time
  promise are not new Intentive commitments.

## Unresolved commitments

These are carried-forward obligations, not current live-status claims. Documentation cleanup closes none.
Dates identify recorded evidence; owners must reconcile later evidence before claiming closure.

| Obligation / owner | Closure requirement |
| --- | --- |
| BL-001 — desktop/backend release owners | One final SHA: component/agent suites, full T2, natural PTT, Gemini reconnect/tools, OpenAI TTS, buffered Modulate, typed→PTT→blind recall, deploy-inline mint and direct-provider probes. Provider availability on 2026-09-04 did not close qualification. [Full record][bl001] |
| BL-002 — infrastructure/operator owner | Foundation-readiness inventory and retained/rejected/shared/absent/unknown classification, then separately authorized behavioral/denial probes and before/after/rollback evidence. The 2026-09-04 inventory was not operational closure. [Full record][bl002] |
| BL-003 — backend/CI owner | Reconcile local/hosted checks on one final pushed SHA; keep 2026-09-05 CPU-ratchet failures distinct from passing assertions. Do not combine different-SHA receipts. [Full record][bl003] |
| G6 — desktop runtime owner | Establish the release shipping the platonic refactor, then retire legacy_client_scope/legacy_session_key two desktop releases later; no shipping date is inferred. [Record][additional] |
| E2E/import isolation — backend owner | Finish deterministic retained LLM clients, 500/timeout and Redis-down coverage with socket guard/no dynamic installs. Closure needs empty import allowlists, one-process suite safety and obsolete-helper retirement. [Record][additional] |
| Dev/Beta — desktop/release owner | Actual signed Beta retains login/history/settings through same-account Dev restarts. Named test builds are insufficient. Inventory stale qualification helpers before manual cleanup. [Record][desktop] |
| S-18 — product/billing/release owners | Disabled billing scaffolding is not acceptance; finish the separately authorized test/live handoff below. [Record][billing] |
| Release inputs — release/infrastructure owner | Reverify registrations/capabilities, protected Beta/Preview inputs, artifact origins/buckets/documents, main protection, exact signed/notarized candidate and update/coexistence/recovery proof. Production/publication needs fresh authorization. [Dated checklist][ownership] |

## Identity and legal handoff

Product/design owns any future Figma destination. Product/legal/release owns download/preview URLs,
`www` TLS repair and public-release Terms/Privacy/operator identity. The 2026-09-05 development-policy
publication used the existing individual contact; it did not create support/privacy aliases or approve
public Mac release. Never invent company content/legal promises/senders. Consult the [identity record][identity]
and later [owner/website reconciliation][ownership] before external action.

## Billing activation handoff

- Keep `BILLING_MODE=disabled`: no catalog/checkout/portal provider calls. Skip dismisses usage UI
  without granting entitlement or clearing quota/fair-use state.
- After the planned waves, test resources need explicit approval and isolated credentials/products/
  catalog/webhook/disposable customer. Live resources and activation need separate authorization.
- Preserve server-owned opaque offers, hosted checkout/portal, signed/idempotent/ordered webhook
  entitlement authority, bounded reconciliation, cancellation/access-end, quota/fair-use and deletion
  safety. Redirects do not grant access; do not add an onboarding paywall.
- Complete every row of the [original acceptance sequence][billing]: startup denial, checkout,
  invalid/duplicate/stale webhooks, portal/plan change, renewal/failure/restart/reconciliation,
  active-subscription deletion, Mac presentation, redacted receipts and test-resource cleanup.
- Live proof is one authorized bounded transaction/cancellation with monitoring and rollback ownership.
  Roll back to disabled without losing receipts, orphaning billing or fabricating entitlement.

## Accepted requirements

The 714 final IR decisions, acceptance groups, owners, dates and rationale remain in the
[pinned full register][requirements] and [original per-decision acceptance matrix][acceptance].
Read the relevant IR before changing its boundary. Old implementation proposals are historical,
not instructions to repeat completed work or restore retired products.

REQ reconciles applicable final decisions with current product constraints and code/tests; the planning
ledger validator is retired. REP retains [S-31 source-residue searches][residue], classification of every hit,
retained-owner existence/behavioral proof, `git diff --check`, `make preflight` and PR-body preflight.
Wiki validation does not replace per-slice BE/MAC, PROV, INV, REL or BILL evidence. Compacting this brief
neither supersedes an accepted decision nor waives an unresolved commitment.

[engineering]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#engineering-rules
[desktop]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#dev-and-beta-coexistence
[ownership]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#owned-identities-and-release-prerequisites
[health]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#release-health-evidence-contract
[assets]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#asset-provenance
[security]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#security-policy
[bl001]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#bl-001-final-all-waves-provider-and-continuity-qualification
[bl002]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#bl-002-s-25-verified-live-resource-inventory-and-operational-handoff
[bl003]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#bl-003-s-27-deferred-broad-verification
[additional]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#additional-retained-commitments
[identity]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#identity-and-legal-handoff
[billing]: https://github.com/sruj75/knowledge-athlete/blob/65575837b1f1a18fe9e23eb8bb65071089aed270/openwiki/INSTRUCTIONS.md#billing-activation-handoff
[requirements]: https://github.com/sruj75/knowledge-athlete/blob/97c88ba2db3117a112b562c62fc38f9aecf68f1b/bootstrap-scaffold/requirements-challenge.md
[acceptance]: https://github.com/sruj75/knowledge-athlete/blob/97c88ba2db3117a112b562c62fc38f9aecf68f1b/bootstrap-scaffold/wave-6/s-31-acceptance-matrix.md
[residue]: https://github.com/sruj75/knowledge-athlete/blob/ee48ed972ab0eb33a09261cc001ece0fcdc96aaa/bootstrap-scaffold/wave-6/s-31%20tdd.md#13-repository-residue-search-strategy
[repair-ownership]: https://github.com/sruj75/knowledge-athlete/blob/97c88ba2db3117a112b562c62fc38f9aecf68f1b/OWNER-PROVIDER-DECISIONS.md
[repair-provenance]: https://github.com/sruj75/knowledge-athlete/blob/97c88ba2db3117a112b562c62fc38f9aecf68f1b/FORK.md
