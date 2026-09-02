# S-30 TDD plan — perform the final product-identity, copy, privacy, and legal truth pass

## 1. Title and slice identity

| Field | Value |
|---|---|
| Wave | **6 — final reownership, release, and truth closeout** |
| Slice | **S-30** |
| Name | **Perform the final product-identity, copy, privacy, and legal truth pass** |
| Type | Final cross-surface identity and factual-copy convergence |
| Primary decisions | **IR-115, IR-126, IR-165, IR-174, IR-204 through IR-207, IR-247 through IR-253, IR-269, IR-287, IR-514, IR-521, IR-858, IR-887, IR-892 through IR-896, IR-927 through IR-931** |
| Roadmap authority | [`../deletion-map.md`](../deletion-map.md), S-30 and the shared closeout contract |
| Product authority | [`../../PRODUCT.md`](../../PRODUCT.md) plus the concrete behavioral tests owned by each changed source |
| Provenance authority | [`../../FORK.md`](../../FORK.md); preserve license, attribution, and history |
| Future named development bundle | **`omi-wave6-s30`**; use only this non-production bundle during acceptance |
| Planned implementation shape | **11 ordered TDD cycles** after mandatory predecessor and identity-input gates |

This is a planning-only document. It does not select the final product or company name, approve legal language, alter product behavior, create infrastructure, rotate provider credentials, change a live URL, build a release, or authorize deployment. Its special boundary is deliberately narrow: make the architecture already selected by earlier slices truthfully named and described everywhere it is visible or operationally external, while preserving retained behavior, historical changelogs, the neutral no-purple rule, and S-29's release mechanics.

## 2. Planning status and pinned baseline

**Status:** plan ready; implementation is **blocked at the production-edit gate** until integrated S-27, S-28, and S-29 outputs and the approved identity/legal input packet in §5 are present. Earlier owner seams from S-09, S-17, and S-21 must also remain integrated. Inventory and characterization may be refreshed before those gates; product identity, copy, URL, analytics, service-name, and legal edits may not.

The exact inspected repository baseline is both `HEAD` and `origin/main`:

```text
22ad2f16ff8d63fd761c918b92f4c5d961814624
```

Planning-time checks run from the repository root:

```bash
git fetch origin
git merge-base --is-ancestor 22ad2f16ff8d63fd761c918b92f4c5d961814624 HEAD
git rev-parse HEAD
git rev-parse origin/main
python3 bootstrap-scaffold/validate-requirements-ledger.py
git status --short --branch
```

The ancestry check passed; both revisions resolved to the pinned SHA. The requirements validator reported:

```text
Requirements ledger validation: PASS (714 indexed rows, 714 detailed sections, all reviewed)
```

The worktree was clean on branch `plan-waves-5-6-slices` when planning began. No component test suite, named desktop bundle, backend process, provider request, live URL, or release path was exercised while authoring this plan. Every implementation and acceptance command below is future work unless explicitly identified as planning-time evidence above.

Planning authorities inspected were root [`../../AGENTS.md`](../../AGENTS.md), [`../../backend/AGENTS.md`](../../backend/AGENTS.md), [`../../desktop/macos/AGENTS.md`](../../desktop/macos/AGENTS.md), [`../../desktop/macos/e2e/SKILL.md`](../../desktop/macos/e2e/SKILL.md), `PRODUCT.md`, `FORK.md`, `BACKLOG.md`, the requirements/deletion/research/Dodo authorities in `bootstrap-scaffold/`, the Waves 3–4 closeout, and the relevant S-09, S-17, S-20, S-21, S-22, and S-25 plans and handoffs. Current source, tests, workflows, release scripts, resources, and operator documentation were then inspected to distinguish implemented behavior from future-owner plans.

### 2.1 Execution-context refresh — 2026-08-29

This refresh changes S-30's entry facts, not its scope or completion status. The
historical planning baseline above remains provenance; implementation must use a
fresh execution head.

- S-26 through S-29 are now integrated on `origin/main` through merge
  `2a966c29f27e7604a129df3a9f595ff055d391a5`. The current setup branch is
  `98ff1714b125b09b17d3ca741d090232be95901c`; neither SHA is S-30 acceptance
  evidence.
- The approved identity packet now fixes product/app name `Intentive`, shared
  slug `heyintentive`, domain `heyintentive.com`, bundle family
  `com.heyintentive.intentive{,.beta,.dev}`, repository
  `sruj75/knowledge-athlete`, and Apple team `24D6NXS6H7`. Legal text, effective
  dates, working support/privacy contacts, and final public pages remain
  unapproved/unpublished and still block their owning cycles.
- Firebase Development, Beta, and Stable apps exist in the owner-approved MVP
  project `knowledge-athlete`; Google Firebase Auth is configured. Apple remains
  enabled in Firebase but cannot be accepted until the Apple membership and
  identifiers/capabilities are restored.
- The owned `knowledge-athlete-dev` Cloud Run revision now serves an immutable
  image from the `knowledge-athlete/us-west1/intentive` registry with Upstash
  Redis, Firestore runtime identity, Firebase API key, and Google OAuth wired.
  Health and the Google authorize-to-provider boundary passed. This is
  development infrastructure, not production or final S-31 deployment proof.
- Codemagic is connected to the owned repository; the repository workflows,
  new Sparkle keypair, Stable/Beta Firebase inputs, and Sentry symbol-upload
  credential are configured. Apple signing/notarization values, preview
  resources, production URLs/origin, release GitHub App, trusted runner, and a
  real candidate remain open.
- Provider inventory must be derived from retained callers rather than copied
  from Omi's deployment YAML. Gemini owns managed text, embeddings, and
  realtime voice; OpenAI is retained only for TTS; Modulate is retained for
  managed batch STT but intentionally postponed; Langfuse owns model tracing
  and prompt management; and PostHog owns product telemetry. Anthropic,
  Artificial Analysis, Calendar credentials, the legacy desktop Anthropic key,
  provider selection, OpenAI text/realtime, and Vertex inference are deleted
  requirements. The active development Cloud Run revision still lacks exact
  Gemini and Langfuse secret bindings, so neither has live-provider evidence
  yet. PostHog's owned project identity and all truthful provider disclosures
  remain S-30 inputs.

Accordingly, the production-edit gate is no longer blocked by missing S-27,
S-28, or S-29 repository integration. It remains blocked by the unfinished
identity/legal/public-contact packet and by unowned PostHog/managed-provider
inputs where a final visible or public claim depends on them. Do not recreate
deleted provider accounts merely to make the inherited manifest look complete.

### 2.2 Gemini-first provider refresh — 2026-09-01

The governing provider decisions now supersede the retained-provider inventory
in §2.1. Normal Chat and every retained managed text workload use Gemini 3.7
Flash; Gemini Live is the only realtime voice provider; and OpenAI remains only
for the unchanged `gpt-4o-mini-tts` route. Auto, Artificial Analysis, Anthropic,
OpenAI text/embeddings/realtime, and the omni relay are deleted. Modulate remains
the postponed batch-STT credential. Langfuse tracing and prompt management are
implemented in repository code; only exact development secret binding and live
trace proof remain. S-30 disclosure and PostHog acceptance must describe this
final map, not the superseded Omi inventory.

## 3. Outcome

S-30 closes the gap between the final architecture and what the product says about itself. On one integrated execution head:

- every current user-facing product name, icon, wordmark, image, window/menu title, permission explanation, sign-in and onboarding sentence, Home/Memory string, notification, error, update message, About row, external URL, support email, Terms/Privacy link, and provider disclosure belongs to the final approved identity and tells the literal truth;
- PostHog, Sentry, and Langfuse retain their selected jobs under owned project identities, accurate event/release/service names, and the already-decided consent boundaries;
- backend and operator-facing current documentation describes one `us-west1` Cloud Run backend per environment, local product-data authority, transient managed compute, fixed Modulate STT, disabled billing, owned S-29 release lanes, and S-28 clean namespaces without reviving deleted products or services;
- the S-29 public product, Terms, Privacy, release-note, manifest, preview, Beta, and Stable destinations exist and agree with the app and operator documents;
- broad residue searches find no current Omi/BasedHardware identity or false local/cloud/privacy promise in shipping macOS, non-Windows release, backend/operator, analytics/log/service, or current public/legal surfaces;
- every remaining old-name match is explicitly classified as protected history/provenance, an internal-only implementation symbol with no external identity effect, a Windows exclusion, a test fixture that proves migration/absence, or a named temporary development-bundle contract.

This slice does **not** redesign storage, networking, transcription, authentication, billing, telemetry, notifications, navigation, updater mechanics, release promotion, or deployment topology. If truthful copy would require changing behavior, the copy must describe the behavior that actually shipped or execution stops for the owning slice; S-30 does not make a false statement true by quietly inventing a new subsystem.

## 4. Authorizing requirements

The detailed requirement sections and indexed rows were read. The current ledger outranks older research prose and plans. Any execution-time change or contradiction is a stop point.

| Decision | S-30 obligation | Cycle(s) |
|---|---|---|
| **IR-115** | Retain Sentry and PostHog with owned project identities, existing release/health value, dev suppression, bounded fields, and privacy filtering. Replace Omi project/release/service identity everywhere. | 0, 5, 8, 10 |
| **IR-126** | Preserve the first onboarding promise/trust structure and setup action while replacing inherited branding, repository link, and architecture claims with exact approved truth. | 3 |
| **IR-165** | Preserve one shared sign-in/onboarding backdrop and replace `signin_bg.png` with owned artwork. | 2 |
| **IR-174** | Preserve sign-in headline/support/footer positions while fact-checking product, capture, follow-up, open-source, on-Mac, and pause claims. | 2 |
| **IR-204** | Keep the Privacy data-location/security explanation, delete the fake `Active` security state, and distinguish local data, minimal account/billing data, transient managed compute, and only verifiable protections. | 5 |
| **IR-205** | Keep expandable **What We Track** with exact final PostHog/Sentry categories and raw-content exclusions. | 5 |
| **IR-206** | Delete the duplicate **Privacy Guarantees** card and its four false absolutes. | 5 |
| **IR-207** | Consume S-09's local default-on PostHog preference applied before setup/identify; off stops capture and detaches identity. Keep Sentry and Enhanced Diagnostics separate. | 5 |
| **IR-247** | Keep About identity/version/build and beta indication, rebranded to the approved product. | 6 |
| **IR-248** | Keep exact-tag release-note behavior at `v<version>+<build>-macos`, pointing to the S-29 owned repository with existing fallback semantics. | 6 |
| **IR-249** | Keep the automatic post-update toast and its behavior; rebrand only its current copy/assets/destination. | 7 |
| **IR-250** | Keep **Visit Website** and point it to the S-29 owned product URL. | 6 |
| **IR-251** | Preserve S-21's deletion of the Help Center row; do not add a replacement support destination. | 6, 10 |
| **IR-252** | Preserve the local **Privacy & Data** shortcut and its routing behavior. | 5, 6 |
| **IR-253** | Keep the simple Terms browser link under the owned URL; add no consent ledger. | 6, 9 |
| **IR-269** | Preserve the exact Memory empty-state sentence: “Memories you add and insights learned from your conversations and activity will appear here.” | 4 |
| **IR-287** | Preserve the exact Memory subtitle: “Memories and insights saved on this Mac.” | 4 |
| **IR-514** | Keep the static empty-Chat welcome, rebrand it, and describe only available local memories/conversations. Preserve onboarding-opener priority and no generated/journaled greeting. | 4 |
| **IR-521** | Preserve the neutral dark Home presentation and no-purple rule; use the existing shared theme owner without visual redesign. | 4, 10 |
| **IR-858** | State the final one-region truth: one canonical Cloud Run backend per environment in `us-west1`; no multi-region or retired-service implication. | 8, 9 |
| **IR-887** | Keep managed Modulate as the fixed live/PTT and prerecorded-overflow STT provider under an owned account and disclose it truthfully; it is not a persistence authority. | 5, 8, 9 |
| **IR-892** | Consume S-29's owned Codemagic/signing/notarization/Sparkle/publication identities; S-30 names and documents them but does not redesign them. | 6, 7, 9 |
| **IR-893** | Describe the actual manual `workflow_dispatch` candidate path and dedicated M1 builder after S-29 reconciles code and component guidance. | 8, 9 |
| **IR-894** | Keep server-owned signed manifests/pointers and candidate/Beta/Stable rings; make their names, URLs, artifacts, and operator prose consistent. | 6, 7, 9 |
| **IR-895** | Keep signed branch previews and owned preview URLs; align visible and operator identity without changing preview mechanics. | 6, 9 |
| **IR-896** | Complete the small external product/Terms/Privacy site and GitHub release-note destinations. Privacy must disclose local authority, Firebase, Dodo, PostHog, Sentry, Langfuse, AI providers, and Modulate accurately. | 5, 6, 9 |
| **IR-927** | Keep the update policy and blocker while correcting product/backend/Firestore/download/operator wording after S-29. | 7, 8 |
| **IR-928** | Keep RAM remediation and extreme relaunch behavior, with obsolete AgentSync already absent; rebrand current guidance and logs only. | 7, 8 |
| **IR-929** | Keep guarded runtime DMG self-install behavior; consume S-28/S-29 app/bundle/environment identity and update current messages, logs, and tests. | 7 |
| **IR-930** | Preserve S-21's local stats and absence of **Apps Installed**; change only identity-bearing surrounding copy if needed. | 4 |
| **IR-931** | Consume S-28's owned storage/bundle namespaces and no-Omi-import/no-takeover contract; never add legacy migration as part of rebranding. | 1, 7, 8, 10 |

Related guard decisions constrain the plan: IR-802 forbids a redundant provider-disclosure card; IR-804 keeps backend compatibility without `backend_required`; IR-808 keeps Redis ephemeral; IR-809 keeps the update/preview bucket; IR-821 keeps local What’s New without cloud announcement storage; IR-827/828/832 retain Langfuse, Prompt Hub, and website evaluation with truthful disclosure; IR-839–849 assign infrastructure to S-26/S-27; IR-868/877 retain durable account deletion; IR-871 permits stable `run.app` API URLs for v1 rather than requiring a custom API domain; IR-879/886 retain sanitized Cloud Logging for 30 days without a separate archive; IR-890 retains required indexes; IR-891 retains the offline harness; IR-897 keeps rejected source controls absent; IR-939 belongs to S-29's release cache. [`../dodo-integration.md`](../dodo-integration.md) keeps `BILLING_MODE=disabled` through all six waves; S-30 must neither activate Dodo nor imply that checkout is available.

## 5. Dependencies and entry gates

### G0 — required execution setup and fresh inventory

Before the first implementation RED, run `make setup`, verify the linked-worktree-safe pre-commit hook, fetch `origin/main`, integrate it without renaming or switching the current branch, and record `HEAD`, `origin/main`, merge base, status, commits beyond the pinned baseline, validator output, and focused inherited test status. Repeat §§6–7 and §13 against that execution head.

Stop if the pinned SHA is no longer an ancestor, assigned decisions changed, unrelated changes overlap the target files, or a current owner contradicts this plan. Do not preserve a stale name with an in-repo compatibility alias.

### G1 — mandatory predecessor integration

Planning artifacts alone do not satisfy this gate. Production cycles require integrated, tested outputs from:

- **S-09:** one startup-authoritative PostHog preference, identity detach on opt-out, separate Sentry and Enhanced Diagnostics, truthful tracking inventory, and owned PostHog/Sentry/Langfuse configuration;
- **S-17:** retained onboarding/permission state machine, explicit capture choices, truthful functional permission behavior, local/Firebase answer authority, and deleted AI-onboarding residue;
- **S-21:** canonical Home/Memory/Tasks/Insights shell, local Privacy & Data routing, no Help Center, local stats, and no Apps count;
- **S-27:** exactly one canonical backend per environment in `us-west1` under verified owned Google Cloud/Firebase/Redis/Firestore/GCS/Cloud Tasks/WIF/secret identities;
- **S-28:** final bundle/app-group/Keychain/defaults/database/log/cache/update/test namespaces, clean first launch, and no inherited Omi import/takeover;
- **S-29:** owned signing/notarization/build provider, manual candidate workflow, Sparkle manifests/pointers, preview/Beta/Stable URLs and artifacts, rollback, GitHub release repository, and public product/Terms/Privacy hosting/destination mechanics with the exact versioned S-29 publication packet revision recorded for this final truth pass.

The planning baseline contains the earlier S-21 integration but not S-27, S-28, or S-29 plans or implementations. Every production cycle is therefore blocked today. Safe pre-gate work is limited to read-only inventory and behavioral characterization; do not land temporary old-name-to-new-name adapters that S-28/S-29 must immediately delete.

### G2 — approved product identity and legal truth packet

The repository does not authorize a final name merely because its fork is named `knowledge-athlete`, and the existing `support@heyintentive.com` address does not by itself establish the final company or product. Before Cycle 1 GREEN, the accountable owner must provide one versioned, reviewable packet containing:

1. exact product display name, short name, company/legal-entity name, capitalization, possessives, and allowed generic references;
2. approved app icon, wordmark, monochrome menu/notch marks, sign-in/onboarding backdrop, accessibility labels, and asset licenses/provenance;
3. final stable/Beta display names, S-28 bundle/app-group/Keychain/storage/default/log/cache/update namespaces, URL schemes, and S-29 artifact filenames;
4. canonical product, Terms, Privacy, support, GitHub repository/release, appcast/manifest, preview, Beta, and Stable URLs plus the support email and accountable mailbox owner;
5. owned PostHog project/token/host, Sentry org/project/DSN/release convention, Langfuse project/workspace, Cloud Run service/project names, and approved external service labels—secret values delivered through existing secret/config owners, never copied into prose;
6. a fact-reviewed data-flow matrix covering local stores, Firebase Auth/minimal account metadata, Dodo's disabled/current role, PostHog, Sentry, Enhanced Diagnostics, Langfuse, OpenAI TTS, Gemini, Modulate, Redis, Firestore, GCS update/preview assets, retention, purpose, content categories, opt-out/control, and deletion/export behavior;
7. approved public Privacy and Terms text, effective date, jurisdiction/contact details, and evidence for every security, encryption, retention, deletion, and “on this Mac” claim.

Product and legal owners approve literal copy; engineering proves it matches shipped code. Missing, placeholder, redirect-only, inaccessible, or mutually inconsistent inputs block the affected GREEN. Never invent encryption, sale/sharing, retention, regionality, compliance, open-source, provider, or deletion promises.

The handoff from S-29 is sequential, not circular. S-29 establishes and verifies the owned hosting, routing, redirect/cache, destination, and publication mechanics using its versioned owner-approved current-content packet. After that implementation is integrated, S-30 owns the final literal page content and architecture-wide privacy/legal truth reconciliation against this G2 packet, using S-29's existing publication path. S-30 must not redesign release/site mechanics, and a prior S-29 content revision does not count as S-30's final approval.

### G3 — release-guide authority conflict must close in S-29

At the planning baseline, `.github/workflows/desktop_auto_release.yml` and IR-893 describe a manual `workflow_dispatch` path, while `desktop/macos/AGENTS.md` still describes automatic push/schedule behavior in parts of its release guide. S-29 must resolve code, tests, and component documentation to one implemented authority before S-30 edits operator prose. S-30 may verify and rebrand that result; it must not choose or alter release mechanics.

### G4 — no live/provider mutation authorization

This plan authorizes future repository implementation only. It does not authorize DNS, redirect, website publication, provider-project creation, credential rotation, Cloud Run rename/deploy, bucket/object mutation, appcast/pointer promotion, code-signing/notarization, release publication, analytics migration, production-app launch, or customer-data change. Those operations require the owning S-27/S-29 runbook and explicit authorization. Repository closure can be earned with verified destinations and non-production evidence; §16 keeps live activation and final release separate.

## 6. Current production codeflow

This section records the pinned pre-S-27/S-28/S-29 baseline and must be refreshed after G1.

### 6.1 Launch, sign-in, and onboarding identity

`desktop/macos/Desktop/Info.plist`, `AppBuild.swift`, `OmiApp.swift`, build/run scripts, entitlements, URL types, and resource packaging still expose Omi names, `com.omi.*` identities, Omi permission strings, an Omi auth callback, and `api.omi.me` appcast. `SignInView.swift` renders Omi art/name and inherited product promises. `Auth/OAuthLoopbackCallbackServer.swift` emits Omi browser titles, return guidance, button labels, and DOM identifiers. The shared `signin_bg.png` remains inherited.

The retained S-17 onboarding state machine lives in `Onboarding/SecondBrain/SBOnboardingModel.swift`, `SBOnboardingModel+Steps.swift`, and `SBOnboardingView.swift`. Its current visible strings still include “Set up Omi,” “Hey, I'm Omi,” “What language should Omi listen and reply in?”, and a BasedHardware GitHub link. Functional capture/permission behavior is owned by S-17; S-30 replaces final identity and fact-checks the prose without changing its transitions.

### 6.2 Surviving desktop shell and product copy

The S-21 shell is Home, Memory, Tasks, and Insights with Rewind separate and Settings/Permissions retained. Current identity-bearing strings span `DesktopHomeView.swift`, Dashboard/Home presentation, Chat/floating-bar surfaces, Settings sections, permission guidance, status/menu items, Rewind, feedback/fair-use surfaces, notification formatters, error presentations, and automation descriptions. Internal Swift types and modules also contain `Omi*`; those are not automatically user-facing identity.

The exact IR-269 empty-state and IR-287 Memory subtitle are already present and guarded. Home's static empty welcome still needs final identity/capability wording under IR-514. The neutral theme is already a retained owner; S-30 must not use identity work to redesign layout or introduce purple.

### 6.3 Privacy, tracking, and managed-provider truth

`SettingsContentView+NotificationsPrivacy.swift` still presents an asserted `Active` local-database protection state, a duplicate Privacy Guarantees card with absolutes, and a stale What We Track inventory. `PostHogManager.swift` and `AnalyticsManager.swift` retain product analytics; `OmiApp.swift`, `Observability/SentryBeforeSendPolicy.swift`, feedback, diagnostics, and release scripts retain Sentry; backend model paths retain Langfuse where selected.

At this baseline, PostHog configuration includes an inherited project token/host and Sentry configuration/release upload still carries inherited OmiApp identity. S-09 owns consent mechanics and provider-project configuration. S-30 consumes that seam to make the final in-app and public disclosures agree with observed event/payload categories. Sentry remains independent from the PostHog toggle; Enhanced Diagnostics remains a separate explicit control.

The architecture to describe is local product-data authority plus transient managed computation: fixed PCM goes through authenticated `/v4/listen` to managed Modulate; optional translation uses Gemini; selected stateless model work uses its declared managed AI provider; local conversations, Memory, tasks/goals, Focus, AI Profile, Chat catalog/journal, and local vectors remain on the Mac. Firebase retains authentication and minimal account/server metadata. Redis is ephemeral. Dodo remains disabled during all six waves. No redundant provider card is added.

### 6.4 About, links, notifications, and updater

About/Settings retains product identity, version/build selection, beta indication, exact-tag release notes, Visit Website, Privacy & Data, and Terms. The Help Center row is already deleted. Current destinations still include inherited Omi URLs. `WhatsNewToast.swift` retains automatic post-update presentation. `Startup/AppInstaller.swift`, `ManualInstallationDisclosure.swift`, update services, repair-installer HTML, permission/relaunch messages, notifications, and fair-use warnings contain current app-name or support language.

S-28 owns runtime/bundle/storage identities; S-29 owns signing, artifact, appcast, manifest, release-note, preview/Beta/Stable, website, Terms, and Privacy destinations. S-30 replaces current copy and cross-checks links only after those owners exist.

### 6.5 Backend, service, log, analytics, and operator identity

Backend and deployment documentation still contains Omi/BasedHardware names, inherited domains, resource examples, and historical topology. Current workflow/scripts also contain release, service, artifact, Firebase, GCP, and bucket identities that S-27/S-29 must first replace functionally. Desktop event names such as `floating_bar_ask_omi_opened`, automation actions such as `open_omi`, Omi-auth log prefixes, service labels, process names, and support diagnostics can escape into dashboards, logs, test APIs, release evidence, or operator procedures even when they are not rendered on screen.

S-30 must distinguish current external/operational identity from compiler-local symbols. A public event, log category, service label, appcast/artifact, environment variable shown to operators, accessibility label, automation protocol, or diagnostics payload is in scope. A private Swift type or module name can remain if it is truly implementation-only, renaming it adds no truthful external boundary, and S-28/S-29 do not already replace it. No compatibility alias is added for this unreleased fork.

### 6.6 Protected historical and excluded surfaces

`desktop/macos/CHANGELOG.json`, historical release notes, merged incident/PR/failure-class records, and provenance references legitimately describe Omi/BasedHardware history. `LICENSE` and `FORK.md` must retain legally required attribution and an accurate explanation of the fork. Windows is not part of this macOS final-identity slice. Test fixtures may retain an old name only when they deliberately prove rejection/migration/absence and label that purpose.

## 7. Complete caller and dependency inventory

The inventory is by externally meaningful surface, not merely by string. Paths are current owners or search roots; refresh them after predecessor integration and follow every match to its renderer, payload, deploy consumer, or documentation audience.

| Surface | Current owners/callers | Upstream dependency | Planned disposition |
|---|---|---|---|
| Product/bundle identity | `Desktop/Info.plist`, `AppBuild.swift`, `OmiApp.swift`, `Package.swift`, entitlements, `run.sh`, build/install/dev-instance scripts | S-28 namespaces; S-29 signed artifacts | **ADAPT** current external identity; **KEEP** internal symbols only after classification |
| Icons/wordmarks/backdrop/media | `Desktop/Sources/Resources/**`, asset lookup call sites, package resources | Approved owned asset pack and licenses | **ADAPT/DELETE** inherited assets after caller proof; preserve non-brand functional media |
| Sign-in | `SignInView.swift`, auth-provider controls, footer/support links | S-08 auth; approved identity/truth packet | **ADAPT** copy/art; keep auth behavior and layout |
| OAuth callback browser page | `Auth/OAuthLoopbackCallbackServer.swift`, URL-scheme owner, auth tests | S-28 scheme/bundle; S-08 auth | **ADAPT** visible/DOM identity without changing callback security |
| Onboarding | Second Brain model/view/steps, opener composer/view, permission guidance, onboarding tests | S-17 state machine; approved copy/assets | **ADAPT** identity and facts; keep flow and capture semantics |
| Permission surfaces | `Info.plist`, `PermissionsPage.swift`, `AppState+Permissions`, screen/audio/mic/accessibility helpers, automation QA strings | Actual TCC/capture behavior from S-17 | **ADAPT** literal explanations; no new permission or capture behavior |
| Home/Chat/floating bar | `DesktopHomeView.swift`, Home/Dashboard components, Chat components, FloatingControlBar, shortcut/status/menu/error copy | S-19/S-21 shell, retained Chat/PTT | **ADAPT** visible product/capability nouns; **KEEP** behavior/layout |
| Memory/Tasks/Insights/Rewind | page/view-model/provenance/settings sources and tests | Local authorities in PRODUCT.md | **KEEP AS IS** exact approved copy; adapt only remaining false identity |
| Privacy & tracking UI | `SettingsContentView+NotificationsPrivacy.swift`, `PostHogManager.swift`, `AnalyticsManager.swift`, Sentry policy, diagnostics/feedback | S-09 consent/config plus fact-reviewed data matrix | **ADAPT/DELETE** false cards and stale disclosures; keep provider roles |
| About/Settings destinations | Settings General/About rows, `SettingsViewModel`, sidebar/search contracts | S-21 route; S-29 URLs/repo | **ADAPT** destinations/copy; keep Help Center absent and Privacy & Data local |
| What’s New | `WhatsNewToast.swift`, local changelog reader, `CHANGELOG.json` | S-29 release notes; IR-821 local delivery | **ADAPT** current identity; preserve historical entries and presentation behavior |
| Notifications and fair-use | notification service/plugin, local warning and callback bridge, FairUse sources, formatter/policy tests | S-20 exact notification semantics and accepted support path | **ADAPT** identity only; do not change timing, action, or severity semantics |
| Updater/self-install/repair | update services, `Startup/AppInstaller.swift`, Manual Installation disclosure, repair HTML/scripts/tests | S-28 namespace; S-29 manifest/artifacts/signing | **ADAPT** messages, filenames, URLs, logs after mechanics integrate |
| Analytics events/properties | Analytics/PostHog call sites, event enums/strings, consent tests, dashboards named in docs | S-09 owned projects and migration decision | **ADAPT** brand-bearing names atomically; keep meanings/schema unless approved migration says otherwise |
| Sentry releases/services | app startup, before-send policy, feedback, release upload/workflows, release docs | S-09 owned Sentry; S-29 build/release | **ADAPT** org/project/release/service identity; keep filtering and issue value |
| Langfuse/model trace identity | backend model client/config, Prompt Hub/eval docs/workflows | S-09/S-22 retained trace owners | **ADAPT** project/workspace/current service name; preserve content boundaries |
| Backend providers and API truth | `backend/AGENTS.md`, `backend/README.md`, route/service docs, OpenAPI descriptions, environment templates | S-22/S-26/S-27 integrated runtime | **ADAPT** current descriptions; do not change routes/providers/topology |
| Cloud/deploy service names | runtime env, workflow/script/config/OpenTofu outputs, probes, logging labels, runbooks | S-27 canonical owned infrastructure | **VERIFY/ADAPT** residual external names; no live rename in S-30 |
| Release/publication names | workflows/scripts/schemas/fixtures/docs, GitHub tags/assets, appcast/manifests/pointers/previews | S-29 release implementation | **VERIFY/ADAPT** identity and prose; mechanics remain S-29 |
| Public product/legal site | S-29 site source/assets/routes/tests and app destinations | Approved legal copy and owned domain | **ADAPT** final content; no telemetry or consent mechanism invented |
| Support URL/email | sign-in/footer/About/fair-use/errors/repair/public Privacy and Terms | Approved mailbox, domain, accountable owner | **ADAPT** consistently; do not infer from `support@heyintentive.com` |
| Documentation | root/component guides, README/runbooks, PRODUCT, FORK, release/deploy/privacy docs | Actual integrated code and approved packet | **ADAPT** current instructions; **KEEP** provenance/history |
| Generated contracts | app-client OpenAPI, generated non-Windows Swift, release manifests/schemas | Owning source/generator | **REGENERATE only if source contract changed**; never hand-edit |
| Historical/provenance | `CHANGELOG.json`, LICENSE, FORK, archived incident/PR/failure-class evidence | Legal/history authority | **KEEP AS IS** except a current-vs-history clarification |
| Windows | `desktop/windows/**`, Windows workflows/docs/assets | Separate product boundary | **OUT OF SCOPE / DEFERRED**; classify, do not edit |

The implementation PR must attach a machine-readable or tabular match ledger for all candidate terms and promises. Each row records path, line/symbol, audience, runtime reachability, authority, disposition, cycle/commit, test/evidence, and any protected exception. A naked “zero matches” count is insufficient because some old-name history must remain and some false claims do not contain the old name.

## 8. Behavior classification

| Class | S-30 meaning | Examples |
|---|---|---|
| **KEEP AS IS** | Already-decided behavior or exact copy that must not move during the truth pass. | IR-269/287 Memory strings; sign-in layout; onboarding transitions; Home dark layout; Privacy & Data route; About version selection; update toast timing; local notifications; Sentry/PostHog/Langfuse jobs; `BILLING_MODE=disabled`; historical changelog/provenance. |
| **ADAPT** | Replace current externally meaningful identity, destination, or statement with approved truth at the existing owner. | Icons/wordmarks, product nouns, permission descriptions, Privacy/What We Track, provider/service/release names, URLs, support email, About, updater/repair text, operator docs. |
| **DELETE** | Remove inherited content or duplicate assertions that have no retained product role. | Old current-use art, fake `Active` security status, four Privacy Guarantees absolutes, stale Help Center references, current Omi/BasedHardware destinations, obsolete service/provider claims. |
| **SIMPLIFY AFTER** | Only after GREEN and caller proof, consolidate duplicate literal strings or delete obsolete test/docs helpers without changing behavior. | Repeated product-display copy at an existing narrow owner; duplicate URL constants already superseded by S-28/S-29; stale snapshot fixtures. No new global copy framework. |
| **ACCELERATE AFTER** | Once focused GREEN is stable, use existing generators/formatters and parallel search lanes to close mechanical residue. | Generated non-Windows clients, release fixtures, asset references, scoped spelling scans. Never bulk-replace before behavior tests. |
| **AUTOMATE LAST** | Add or extend a deterministic current-identity/truth gate only after the final pattern is known and only if it would catch a cited real merged defect/incident under repository guard rules. | Existing brand-UI or release-identity check extension. If no qualifying real instance exists, keep the reviewed match ledger and do not add a new gate. |
| **OUT OF SCOPE / DEFERRED** | Work owned elsewhere or requiring separate authority. | Architecture redesign, live provider/cloud/DNS mutation, billing activation, S-29 mechanics, S-28 migration, Windows, production release, legal judgment, customer-data changes. |

## 9. Retained behavioral invariants

1. Local Mac stores remain authoritative for conversations, Memory, tasks/goals, Focus, AI Profile, local Chat catalog/journal, and local vectors. S-30 changes descriptions, not ownership.
2. `/v4/listen` remains authenticated transient fixed-PCM streaming to managed Modulate with canonical transient segments; no conversation persistence or People/voice-identity authority is implied.
3. Optional translation and retained model workloads use only the providers selected by current product/runtime authorities. Copy never promises “fully local” computation.
4. Firebase authentication and minimal retained server metadata remain; Redis stays ephemeral; Dodo stays disabled; export and account deletion retain their selected compositions.
5. PostHog remains local default-on and user-controllable only through S-09's owner. Off applies before setup/identify, stops PostHog capture, and detaches identity. Sentry and Enhanced Diagnostics stay separate.
6. Sentry retains crash/diagnostic value and privacy filtering. Langfuse retains only reviewed model trace/evaluation roles. Raw sensitive content is never added to logs or analytics while renaming.
7. The onboarding state machine, permission request timing, explicit listening choice, Skip/completion semantics, and local opener behavior remain as integrated from S-17.
8. The Home/Memory/Tasks/Insights/Rewind routes, local stores, Stats behavior, static-welcome priority, and exact IR-269/287 text remain as integrated from S-19/S-21.
9. The neutral dark design stays visually equivalent. No icon, asset, accent, glow, gradient, or generated art introduces purple.
10. About keeps version/build selection, beta indication, exact-tag release notes, Visit Website, Privacy & Data, and Terms; Help Center stays absent.
11. What’s New, local notifications, fair-use warnings, support escalation, update checks, RAM remediation, relaunch, DMG self-install, signing, notarization, candidate/Beta/Stable promotion, preview, and rollback mechanics do not change.
12. S-28's clean namespaces remain clean: no Omi storage/keychain/defaults/log/cache import, takeover, migration, or compatibility path is introduced.
13. One backend per environment remains in `us-west1`. S-30 does not rename live resources or add a second service to make prose easier.
14. Historical changelogs, release facts, LICENSE, and fork provenance remain accurate. Current copy does not rewrite history.
15. No generated file is hand-edited; no new TODO/FIXME/HACK lacks a tracking issue; no new static source scrape is presented as behavioral coverage.

## 10. Target authority, ownership, identity, and topology model

S-30 does not create a runtime “brand service.” It converges existing owners around an approved input packet and the actual architecture:

```text
Approved identity/legal packet (human authority, versioned evidence)
  + PRODUCT.md and requirements (product/data-flow authority)
  + integrated S-09/S-17/S-21/S-27/S-28/S-29 production behavior
                                  |
                                  v
Existing narrow owners
  S-28 app/bundle/storage identity ----> Info.plist, app display, URL scheme, local namespaces
  S-29 release/public identity --------> artifacts, tags, appcast/manifests, website/Terms/Privacy URLs
  S-09 telemetry owners --------------> PostHog preference/project, Sentry project/release, Langfuse
  App/UI source owners ----------------> sign-in, onboarding, Home, Settings, About, notifications, errors
  Backend/deploy owners ---------------> provider/service/log labels and operator documentation
                                  |
                                  v
Cross-surface truth matrix + behavioral tests + classified residue ledger
```

The implementation should prefer an existing typed/configured authority—`AppBuild`, S-28 namespace configuration, S-29 release metadata, the S-09 telemetry configuration—when the same value already has multiple operational consumers. It may extract a small compiler-visible value object only when one existing owner otherwise duplicates the same external fact across three or more direct callers. It must not create a general localization/content-management framework, runtime remote copy service, fallback old-name alias, redirect dependency, or new environment-variable family solely for S-30.

The truth matrix is the review authority for claims. Each statement maps to: visible text; actual production owner; local/cloud/provider data category; purpose; persistence/retention; control/opt-out; deletion/export treatment; evidence test/doc; legal approval status. “On this Mac” applies only to the named local authority, not to transient managed computation. “Private,” “secure,” “encrypted,” “anonymous,” “never,” and “only” require concrete evidence or are removed.

## 11. Ordered TDD cycles

Each cycle is one vertical tracer bullet. Add its behavioral RED through a production seam, observe the expected failure, make the minimum GREEN, run focused proof, then commit that independently green surface. Tests that only inspect source/resources are labelled **static tripwire** and never count as behavioral coverage.

When an existing test's literal copy or destination expectation changes in the same PR, its cycle/PR evidence must cite the applicable requirement and exact approved G2 packet field as the external source for the new expected value. A rewritten test cannot self-authorize the new truth.

### Cycle 0 — rebase, characterize, and freeze the approved truth inputs

**Intended RED:** Build the execution-head identity/truth matrix and run existing UI, telemetry, release, provider, and documentation contract tests unchanged. Add no production assertion yet; record current failures and candidate matches. The gate is RED while any G1 predecessor is absent, G2 field is unapproved/unreachable, or code/docs disagree on release topology.

**Why current fails:** S-27/S-28/S-29 are absent at the pinned baseline; current Omi assets/names/URLs/provider projects remain; no final product/company/legal packet exists; release guidance conflicts with the manual workflow.

**Minimum GREEN:** Integrated predecessor SHAs and evidence are recorded, the approved packet is complete and versioned, all external destinations pass read-only reachability/TLS checks, the current data-flow/service/release inventories agree, and inherited focused failures are assigned. This GREEN changes no product behavior.

**Retained behavior:** every invariant in §9; the pinned baseline remains historical planning evidence.

**Expected source/tests/contracts/docs/config:** plan/PR evidence, approved packet reference outside secrets, current match ledger, predecessor closeout links, and no production source unless a predecessor integration conflict is fixed by its owner.

**Exact verification:** commands in §14 under baseline, requirements, identity input, URL, and predecessor checks; `git diff --check`; existing focused characterization filters.

**Deletion/simplification enabled:** none. It only prevents guessing and establishes the exact worklist.

**Stop conditions:** any missing identity/legal/provider owner, placeholder/redirect loop, predecessor behavior mismatch, unexplained test failure, or live mutation requirement.

### Cycle 1 — converge the shipping desktop identity and owned assets on S-28/S-29

**Intended RED:** Through `Bundle`/`AppBuild` production seams and rendered icon/accessibility snapshots, assert exact approved stable/Beta/dev display identity, URL scheme, permission-app name, appcast/release owner, and resource identifiers. Assert every required icon/wordmark/menu/notch/backdrop variant resolves and no purple pixel/token is introduced. Add a labelled static resource-reference tripwire for inherited current-use assets.

**Why current fails:** `Info.plist`, `AppBuild`, resources, entitlements, and scripts still expose Omi, `com.omi.*`, Omi URLs, and inherited art on the pinned baseline.

**Minimum GREEN:** Consume S-28's final namespaces and S-29's release metadata, install the approved asset pack at existing renderers, update current accessibility/permission identity, migrate all in-tree callers atomically, and delete caller-free inherited current-use assets. Do not rename internal `Omi*` modules/types solely for aesthetics.

**Retained behavior:** bundle-family safety, named-bundle isolation, permission entitlements, appcast selection, resource loading, neutral appearance, and no legacy data import.

**Expected source/tests/contracts/docs/config:** `Info.plist`, `AppBuild.swift`, app entry/menu/status sources, resource call sites/assets, package resource declarations, S-28/S-29 config, build-identity tests, brand-UI checker/tests, and asset-license record.

**Exact verification:** focused `AppBuild`/bundle identity tests; `python3 .github/scripts/check_brand_ui.py`; its unit tests; Swift debug build; named-bundle icon/menu/window inspection; scoped asset-reference searches from §13.

**Deletion/simplification enabled:** old current-use Omi icons/wordmarks/background/media and duplicate product-display literals once every caller uses its existing owner.

**Stop conditions:** an asset lacks provenance/licence/required size, S-28/S-29 identity differs from the packet, a rename would import/take over old storage, or a replacement changes layout/contrast/brand into purple.

### Cycle 2 — make sign-in and the OAuth return surface exactly truthful

**Intended RED:** Render sign-in before/after its reveal and drive OAuth callback success/failure/invalid results through the real loopback renderer. Assert approved identity/art, preserved headline/support/footer positions, exact return/open-app copy, escaped owned URL scheme, and no unsupported capture/follow-up/open-source/on-Mac/pause claim. Exercise keyboard and accessibility labels.

**Why current fails:** `SignInView.swift`, `signin_bg.png`, and the callback HTML still use Omi and inherited claims; browser titles/buttons explicitly say Omi.

**Minimum GREEN:** Replace the shared backdrop and visible identity, rewrite only claims disproved or unapproved by the final architecture, and update callback DOM/accessibility identifiers where they are externally meaningful. Preserve auth providers, state/nonce/callback validation, escaping, timing, focus, and layout.

**Retained behavior:** S-08 authentication/session ownership, sign-in animation, provider buttons, support/footer positions, callback security and app-opening behavior.

**Expected source/tests/contracts/docs/config:** `SignInView.swift`, `OAuthLoopbackCallbackServer.swift`, approved backdrop asset, sign-in/auth callback tests, accessibility/render snapshots, and support-link fixture.

**Exact verification:** focused sign-in and OAuth callback behavioral tests, Swift build, local callback success/failure in `omi-wave6-s30`, screenshot/accessibility review at normal and reduced motion, and link check without submitting credentials.

**Deletion/simplification enabled:** inherited backdrop and false sign-in statements; no auth adapter.

**Stop conditions:** approved copy implies unavailable behavior, callback scheme differs from S-28, support destination is unowned, or testing would require a production identity.

### Cycle 3 — rebrand onboarding without changing its retained state machine

**Intended RED:** Drive every retained S-17 stage, Back/resume, permission Skip, global Skip, completion, both listening choices, and opener through production model/actions. Assert approved product nouns and repository link, exact fact-reviewed promise, truthful permission/capture language, no old visible identity, and unchanged state/effects. Keep static layout/source checks labelled as tripwires.

**Why current fails:** the current model/view still says “Set up Omi,” introduces Omi as a second brain that hears/remembers everything, asks how users heard about Omi, and links to BasedHardware.

**Minimum GREEN:** Replace visible identity and factual sentences at their existing model/view owners, point the repository link to the approved S-29 destination if the product remains public-source, and keep copy replaceable. Do not reorder stages, add a consent screen, change permission effects, or reintroduce an AI onboarding engine.

**Retained behavior:** all S-17 transition, permission, capture, Skip/completion, opener-priority, journal, PTT demo, and owner-isolation contracts; IR-126's first promise/trust structure.

**Expected source/tests/contracts/docs/config:** Second Brain model/view/steps, permission guidance, opener composer/view, onboarding language/layout/behavior/repository tests, and current product docs.

**Exact verification:** the complete focused onboarding suite from §14, test-quality checker, offline relaunch/resume, and named-bundle visual pass through every stage.

**Deletion/simplification enabled:** inherited visible onboarding nouns, old repository destination, and false absolutes; no transitional old-name alias.

**Stop conditions:** a wording change requires a state/effect change, repository/public-source status is unapproved, a retained test exposes predecessor regression, or legal review rejects the claim.

### Cycle 4 — converge the surviving shell copy while protecting local authority and exact strings

**Intended RED:** Render empty and populated Home/Chat, Memory, Tasks, Insights, Focus, Rewind, floating bar, settings search, and local Stats from real owner fixtures. Assert the exact IR-269/287 strings, approved static welcome/capability wording, no old visible identity, no deleted product implication, and no purple/layout drift. Assert the static welcome is not generated or journaled and yields to the onboarding opener.

**Why current fails:** current Home/floating/error/shortcut/status surfaces still include Ask Omi and related identity; the final static welcome is not yet approved. Broad replacement could corrupt internal symbols or the already-correct Memory text.

**Minimum GREEN:** Change only rendered identity/capability copy and accessibility names at existing owners. Preserve exact Memory strings, local-source labels, Stats values/no Apps row, routing, layout, and static-welcome semantics. Keep `OmiTheme`/`OmiSupport` or other internal types when they have no external identity effect and S-28 did not rename them.

**Retained behavior:** all S-19/S-21 Home/Chat/navigation/local-store behavior, exact IR-269/287, IR-514 welcome priority, IR-521 appearance, IR-930 Stats.

**Expected source/tests/contracts/docs/config:** Home/Dashboard/Chat/floating/status/menu/error/accessibility sources, Memory and Stats guard tests, Home shell/catalog/welcome tests, navigation/settings tests, and changed snapshots/E2E copy expectations.

**Exact verification:** focused Home/Memory/Stats/navigation/shortcut tests, `check_brand_ui.py`, Swift build, `navigation.yaml`, `home-stage.yaml`, settings flow, screenshots at supported widths and reduced motion.

**Deletion/simplification enabled:** caller-free old UI literals and obsolete snapshot fixtures after behavioral GREEN.

**Stop conditions:** an edit changes route/state/storage ownership, the exact Memory strings drift, a source-only scan is proposed as the behavior test, or visual identity alters the approved neutral layout.

### Cycle 5 — make Privacy, tracking controls, and provider disclosure match observed behavior

**Intended RED:** Through the production Privacy view and injected PostHog/Sentry/diagnostics seams, assert: no fake `Active`; no duplicate Guarantees card; What We Track lists observed bounded categories; PostHog default/setup/identify/opt-out/detach behavior is exact; Sentry remains separate; Enhanced Diagnostics remains separate; raw-content exclusions hold. Render the same fact matrix on the public Privacy page and assert every retained provider/purpose/control is present without adding an IR-802 provider card.

**Why current fails:** the pinned Privacy UI contains a fake active-security state, false absolutes, stale categories, and inherited provider/project identity; the final public Privacy page does not yet exist in this checkout.

**Minimum GREEN:** Consume S-09's tested control/config owners, delete the fake/duplicate cards, rewrite data-location and What We Track from the observed payload matrix, and update public Privacy content for local authorities, Firebase, disabled/current Dodo role, PostHog, Sentry, Langfuse, managed AI providers, Modulate, retention/control/export/deletion boundaries. Never claim raw content is excluded unless payload tests prove it for that provider.

**Retained behavior:** PostHog-only preference, independent Sentry, explicit Enhanced Diagnostics, local product authority, transient managed compute, Report Issue, Export My Data, account deletion, no redundant disclosure card.

**Expected source/tests/contracts/docs/config:** Privacy Settings section, PostHog/Analytics/Sentry/diagnostics seams and tests, S-29 public Privacy source/tests, PRODUCT/FORK only where current claims change, and the reviewed truth matrix.

**Exact verification:** focused consent/startup/identity-detach/privacy-render/payload-redaction tests; offline network-recorder test; public page rendered-content/link tests; secret/PII scan; named-bundle toggle and restart acceptance.

**Deletion/simplification enabled:** fake Active row, Privacy Guarantees card/four absolutes, stale categories, duplicate provider prose, inherited provider identity.

**Stop conditions:** S-09 mechanics or owned provider projects are absent, payload behavior contradicts proposed text, retention/security evidence is missing, legal approval is absent, or the page implies billing activation.

### Cycle 6 — bind About and every external destination to S-29's owned authority

**Intended RED:** Through the About/Settings destination resolver and an injected URL opener, assert approved identity/version/build/beta display, exact-tag release URL, existing fallback, Visit Website, local Privacy & Data route, simple Terms browser link, and no Help Center. Assert every environment/ring URL comes from S-29 authority and no inherited domain/repository is opened.

**Why current fails:** About and onboarding still reference Omi/BasedHardware destinations; S-29 destinations are absent at the planning baseline.

**Minimum GREEN:** Consume the existing S-29 release/public metadata owner in About and settings, replace current links and labels, preserve exact-tag/fallback behavior, retain the local Privacy & Data route, and keep Terms as a simple browser link with no consent ledger.

**Retained behavior:** version/build selection, beta badge, release-note fallback, Visit Website, Privacy & Data routing, Terms browser behavior, no Help Center.

**Expected source/tests/contracts/docs/config:** About/General/settings destination source, `SettingsDestinationContractTests`, `AboutUserCardTests` where relevant, S-29 metadata/config/tests, onboarding repository link, public-route tests, and docs.

**Exact verification:** focused About/settings destination tests, exact-tag fixture, injected opener assertions, read-only HTTP/TLS/content checks for product/Terms/Privacy/release URLs, and `about-settings.yaml` in the named bundle.

**Deletion/simplification enabled:** hard-coded inherited URLs/repository slug, stale Help Center references, duplicate destination constants superseded by S-29.

**Stop conditions:** S-29 has no single authority, a destination redirects to inherited ownership, a Terms/Privacy page lacks approved content, or changing behavior—not identity—is required.

### Cycle 7 — rebrand notifications, errors, What’s New, update, repair, and relaunch guidance

**Intended RED:** Drive local notifications, fair-use warning/actions, user-facing errors, What’s New after a simulated version transition, update blocker/remediation, extreme RAM relaunch, and guarded DMG self-install through production policies/adapters. Assert exact retained semantics plus approved product/artifact/support identity in UI, accessibility labels, local notifications, HTML repair page, and logs.

**Why current fails:** these surfaces contain Omi product names, inherited filenames/URLs, or old operator guidance; mechanical search-and-replace could alter S-20 notification semantics or S-29 updater mechanics.

**Minimum GREEN:** Replace only current identity, artifact names, destination, support address, and factually stale explanation. Consume S-28/S-29 bundle/artifact/appcast owners. Preserve notification timing/actions, changelog delivery, update policy/blocker, RAM thresholds, relaunch guard, signature verification, install guard, and fallback behavior.

**Retained behavior:** IR-249 and IR-927–929 in full; S-20 exact support/fair-use notification semantics; IR-821 local What’s New; production-family safety.

**Expected source/tests/contracts/docs/config:** notification/fair-use/error sources and tests, `WhatsNewToast.swift`, update services, `AppInstaller.swift`, `ManualInstallationDisclosure.swift`, repair-installer script/HTML/tests, S-29 release fixtures, and current user guidance.

**Exact verification:** focused notification/What’s New/AppInstaller/update policy tests, repair-installer unit tests, signed-fixture verification from S-29, Swift build, named-bundle notification/update simulations, and exact log-path inspection.

**Deletion/simplification enabled:** inherited current app/artifact/support literals and stale AgentSync/operator language. Historical changelog entries stay.

**Stop conditions:** an edit alters updater/install security, a support mailbox is unverified, S-29 artifact names are unstable, production bundle access is required, or a historical entry would be rewritten.

### Cycle 8 — migrate externally meaningful analytics, release, log, and service identity atomically

**Intended RED:** At telemetry/log/release/deploy adapters, emit representative events, Sentry envelopes/releases, Langfuse trace metadata, fallback telemetry, backend logs, Cloud Run labels, and release evidence. Assert approved project/service/release identity, unchanged bounded semantic fields, sanitized content, and no old externally visible name. Use labelled static tripwires for caller-free retired event/service strings only after behavioral payload tests exist.

**Why current fails:** inherited PostHog/Sentry configuration, brand-bearing event/action names, Omi auth/log prefixes, release org/project names, service examples, and operator labels remain. Blind renaming could split dashboards or break automation protocols.

**Minimum GREEN:** Consume S-09/S-27/S-28/S-29 identities, rename externally meaningful event/action/log/service/release labels with an explicit old-to-new dashboard/protocol migration ledger, migrate all in-tree producers/consumers/tests in the same commit, and retain event meaning/fields/privacy. Delete old aliases because this fork is unreleased; if an external retained consumer is proven, stop for an explicit coordinated cutover rather than adding compatibility.

**Retained behavior:** telemetry consent, diagnostics, fallback semantics, release health, provider traces, log sanitizer, one-backend topology, automation behavior, and operational observability.

**Expected source/tests/contracts/docs/config:** Analytics/PostHog/Sentry/Langfuse owners and tests, automation bridge/client/action names if externally consumed, backend logging config/sanitizer tests, S-27 service config, S-29 workflows/scripts/schemas/fixtures/docs, dashboards/runbooks referenced by the migration ledger.

**Exact verification:** representative payload snapshot tests, opt-out/no-network test, Sentry before-send/release tests, Langfuse config tests, backend logging/sanitizer tests, release-process guards, automation harness, and exact old/new event/service residue searches.

**Deletion/simplification enabled:** old project/release/service/event/log identifiers and caller-free aliases; duplicated docs after one current authority exists.

**Stop conditions:** provider ownership/IDs are unverified, a downstream dashboard/automation consumer lacks a cutover, a rename changes event meaning, a secret would enter source/evidence, or S-27 live-resource rename is required.

### Cycle 9 — publish one truthful current product, privacy, legal, provider, and operator story

**Intended RED:** Render the S-29 product/Terms/Privacy pages and run current-doc contract checks against the integrated runtime/deploy/release manifests. Assert consistent identity/contact/effective-date links and literal architecture: local authorities; Firebase; Dodo disabled/current role; PostHog/Sentry/Langfuse; selected AI providers; Modulate; one `us-west1` backend; manual candidate publication; signed preview/candidate/Beta/Stable and rollback. Assert no retired product/service/storage/provider or automatic-release claim.

**Why current fails:** the public site is absent at the planning baseline; root/backend/desktop/release docs still contain inherited brand, domains, resources, and stale topology; desktop release guidance currently conflicts with the workflow.

**Minimum GREEN:** Update only current product/operator/legal pages and component guides to match integrated code and the approved packet. Preserve historical/provenance documents, clearly label local/dev/example values, state Dodo's disabled status without hiding its retained future integration, and make release/operator instructions executable under S-29 without modifying mechanics.

**Retained behavior:** PRODUCT architecture, FORK provenance, S-27 topology, S-29 release flow, all provider roles, legal approval authority, no billing activation.

**Expected source/tests/contracts/docs/config:** S-29 site source/routes/content tests, `PRODUCT.md`, `FORK.md` only for current-vs-history clarity, root/backend/desktop guides, release/deploy/health docs, env-template comments, OpenAPI descriptions only if current external prose is wrong, and docs/link tests.

**Exact verification:** rendered public-site tests, internal/external link checker, requirements validator, current-doc-to-manifest checks, backend route/deploy policy tests, release-flow contracts, and manual read-through by engineering plus product/legal approvers.

**Deletion/simplification enabled:** current stale setup links, retired topology/provider claims, duplicate operator identity examples, and false automatic-release prose. Historical evidence remains.

**Stop conditions:** legal text is unapproved, runtime manifests disagree, S-29 release authority remains conflicted, a provider/data-flow cannot be evidenced, or updating prose would conceal an unclosed predecessor defect.

### Cycle 10 — close residue, regenerate only owned outputs, and accept the real named bundle

**Intended RED:** Run the complete current-identity/promise residue matrix, affected component suites, release/deploy gates, public-site checks, and named-bundle flows. The cycle is RED for any unclassified current Omi/BasedHardware identity, false local/cloud/privacy/security/billing/provider/release claim, dead link, missing asset, purple increase, ungenerated drift, or behavior regression.

**Why current fails:** the pinned tree contains broad current identity residue and the predecessors/final destinations are absent; scoped earlier GREENs cannot prove cross-surface agreement.

**Minimum GREEN:** Regenerate non-Windows outputs only from changed authorities, classify every remaining match in the ledger, remove caller-free current residue, run component and repository gates, complete the `omi-wave6-s30` acceptance ledger, and obtain product/legal/engineering review of the exact final strings and pages. Add no new gate unless the repository's real-instance rule is satisfied.

**Retained behavior:** all §9 invariants and predecessor acceptance. No production or live-provider action is needed for repository GREEN.

**Expected source/tests/contracts/docs/config:** only files reached by Cycles 1–9 plus generated outputs from their owners, final match/truth evidence in the PR, and existing gate manifests if a justified existing check must be extended.

**Exact verification:** all §14 commands, all §15 named-bundle flows and manual screen/link inventory, `make preflight`, PR preflight/failure-class handling, `git diff --check`, and final changed-file/status proof.

**Deletion/simplification enabled:** final caller-free current residue and temporary test fixtures; no historical/provenance/Windows deletion.

**Stop conditions:** any unexplained match, component/E2E/preflight failure, unavailable required owned destination, unapproved literal copy, production-app interaction, or live mutation requirement. Do not report partial coverage as final truth.

## 12. Cross-slice ownership and handoffs

| Owner | S-30 consumes | S-30 must not absorb | S-30 hands off |
|---|---|---|---|
| **S-08** | Firebase auth/session/export/account-deletion boundaries | Auth redesign or new identity provider | Truthful auth/minimal-account disclosure |
| **S-09** | PostHog preference/project, Sentry separation, Langfuse and diagnostics boundaries | Consent redesign, raw-content telemetry expansion, live project creation | Final provider names, in-app/public disclosure, event/release identity ledger |
| **S-17** | Retained onboarding/permission/capture behavior | Flow/state-machine redesign | Final brand/art/copy and repository link |
| **S-19/S-20/S-21** | Home shell, Chat/PTT, local notifications/fair-use, Privacy & Data route, local Stats | Navigation, notification semantics, or product behavior changes | Final visible identity and fact-checked wording |
| **S-22/S-26** | Selected managed-provider callers and one source/runtime shape | Model/provider or backend architecture selection | Truthful provider/capability/operator prose |
| **S-27** | Owned one-service `us-west1` infrastructure and verified resource names | Cloud migration, live rename, IAM/secret mutation, deploy | Final external service/log/operator identity validation |
| **S-28** | Clean bundle/storage/keychain/default/log/cache/update/test namespaces | Legacy import/takeover or another namespace migration | Consistent user-facing names over the final namespaces |
| **S-29** | Signing/notarization, artifact/release metadata, previews/rings/rollback, site and legal destinations | Release-mechanics redesign or publication/promotion | Final current copy/content/link truth over those destinations |
| **Post-Wave-6 Dodo gate** | Accurate disabled/current disclosure and retained integration fact | `dodo_test`/`dodo_live` activation or checkout acceptance | A truth matrix ready for separately authorized activation review |
| **Final all-waves closeout** | S-30 repository and named-bundle evidence | Real-provider/physical/release evidence owned by [`../../BACKLOG.md`](../../BACKLOG.md) BL-001 | One committed-SHA product/copy/legal evidence row |

If a predecessor surface is missing or contradicts the final architecture, return it to that owner or stop. S-30 may repair only a small directly related defect in a file already being changed, with its own regression test and separate commit, under the repository's Leave It Better rule. It may not hide an unclosed architecture problem behind carefully worded copy.

## 13. Repository residue-search strategy

Run searches from the repository root after each relevant GREEN and once at final head. Capture complete output in the match ledger; do not use `head` for final evidence. Search current non-Windows shipping/operator surfaces first, then classify protected history and internals.

```bash
# Current product/company/domain/repository/support identity.
rg -n -i --hidden \
  --glob '!desktop/windows/**' --glob '!desktop/macos/CHANGELOG.json' \
  --glob '!LICENSE*' --glob '!.git/**' \
  'Omi|BasedHardware|based-hardware|omi\.me|api\.omi\.me|discord\.omi\.me|support@heyintentive\.com|com\.omi|OmiApp' \
  desktop/macos backend .github scripts Makefile PRODUCT.md FORK.md README.md

# User-visible and operational identity-bearing assets/filenames.
find desktop/macos/Desktop/Sources/Resources -maxdepth 1 -type f -print | sort
rg -n --hidden --glob '!desktop/windows/**' \
  'OmiIcon|omi_(app|menu|notch|text)|herologo|signin_bg|Omi\.zip|omi\.dmg|Omi Beta|Omi Dev' \
  desktop/macos .github backend scripts

# Truth claims: every result is reviewed in context, not automatically deleted.
rg -n -i --hidden --glob '!desktop/windows/**' \
  'fully local|only on (your|this) Mac|never leaves|never stored|we never|100%|anonymous|anonymized|encrypted|secure|private|Active|privacy guarantees|remember everything|always listening|cloud sync|multi-region|automatic(ally)? release|scheduled release|checkout|subscription|Apps Installed' \
  desktop/macos backend .github PRODUCT.md README.md

# Provider, telemetry, service, region, and release identity.
rg -n --hidden --glob '!desktop/windows/**' \
  'PostHog|Sentry|Langfuse|Modulate|OpenAI|Gemini|Anthropic|Firebase|Firestore|Redis|Dodo|GCS|Cloud Run|us-west1|workflow_dispatch|appcast|candidate|preview|Beta|Stable' \
  desktop/macos backend .github scripts PRODUCT.md

# Visible/error/notification/accessibility/automation candidates in Swift.
rg -n --glob '*.swift' \
  'Text\(|Label\(|Button\(|alert\(|title:|message:|summary:|accessibility(Label|Hint)|notification|event|log|Logger' \
  desktop/macos/Desktop/Sources

# Exact retained fences must stay non-empty.
rg -n -F 'Memories you add and insights learned from your conversations and activity will appear here.' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests
rg -n -F 'Memories and insights saved on this Mac.' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests
rg -n -i --glob '*.swift' --glob '*.py' --glob '*.js' --glob '*.mjs' \
  'PostHog|Sentry|Langfuse|Modulate|Privacy & Data|Visit Website|Terms' \
  desktop/macos backend .github

# Protected/excluded matches are inventoried separately, never scrubbed blindly.
rg -n -i 'Omi|BasedHardware|based-hardware' \
  desktop/macos/CHANGELOG.json LICENSE* FORK.md .github/failure-classes desktop/windows
```

For every old-name internal symbol, run callers before classifying it:

```bash
rg -n '<ExactSymbolOrKey>' desktop/macos backend .github scripts
rg -n '<ExactOldURLOrIdentifier>' . --hidden --glob '!.git/**'
```

A remaining current match is allowed only with a reviewable reason. Valid reasons are: legally required provenance/history; Windows exclusion; internal compiler-only symbol with no renderer, payload, bundle/resource, service, log, analytics, accessibility, automation, or operator effect; explicit old-value rejection/migration test; or the assignment's temporary `omi-wave6-s30` bundle name. Comments describing current behavior are not protected history and must be truthful.

## 14. Focused and component-level verification commands

These are future implementation commands except for the planning-time commands in §2. Exact new test class names may be adjusted to the smallest names that join existing runners; document the final mapping in the PR.

### Baseline, requirements, hook, and diff integrity

```bash
make setup
git fetch origin
git merge-base --is-ancestor 22ad2f16ff8d63fd761c918b92f4c5d961814624 HEAD
git rev-parse HEAD origin/main
git status --short --branch
python3 bootstrap-scaffold/validate-requirements-ledger.py
test -x "$(git rev-parse --git-path hooks)/pre-commit" && echo OK
git diff --check
```

### Focused desktop behavioral loop

From `desktop/macos`:

```bash
python3 scripts/dev-feedback.py --once swift 'AppBuildIdentityTests'
python3 scripts/dev-feedback.py --once swift 'SignInIdentityPresentationTests'
python3 scripts/dev-feedback.py --once swift 'OAuthLoopbackCallbackServerTests'
python3 scripts/dev-feedback.py --once swift 'ProductIdentityPresentationTests'
python3 scripts/dev-feedback.py --once swift 'PrivacyTruthPresentationTests'
python3 scripts/dev-feedback.py --once swift 'AboutDestinationTruthTests'
python3 scripts/dev-feedback.py --once swift 'NotificationUpdateIdentityTests'
python3 scripts/dev-feedback.py --once swift 'TelemetryIdentityContractTests'

xcrun swift test --package-path Desktop --filter SBOnboardingLanguageCopyTests
xcrun swift test --package-path Desktop --filter SBOnboardingLayoutTests
xcrun swift test --package-path Desktop --filter SBOnboardingRepositoryTests
xcrun swift test --package-path Desktop --filter OnboardingFlowTests
xcrun swift test --package-path Desktop --filter OnboardingSkipBehaviorTests
xcrun swift test --package-path Desktop --filter OnboardingCompletionBehaviorTests
xcrun swift test --package-path Desktop --filter HomeRedesignRegressionTests
xcrun swift test --package-path Desktop --filter HomeShellOwnerTests
xcrun swift test --package-path Desktop --filter HomeChatCatalogTests
xcrun swift test --package-path Desktop --filter MemoriesViewModelOwnerFenceTests
xcrun swift test --package-path Desktop --filter SettingsDestinationContractTests
xcrun swift test --package-path Desktop --filter SettingsSearchContractTests
xcrun swift test --package-path Desktop --filter AboutUserCardTests
xcrun swift test --package-path Desktop --filter LocalWarningNotificationTests
xcrun swift test --package-path Desktop --filter ProactiveNotificationContinuityTests
xcrun swift test --package-path Desktop --filter AppInstallerTests
xcrun swift test --package-path Desktop --filter ScreenPrivacyExclusionTests

python3 scripts/check_desktop_test_quality.py
./scripts/agent-logic-harness.sh
./scripts/desktop-core-harness.sh --self-check --skip-backend-contracts
xcrun swift build -c debug --package-path Desktop
./test.sh
```

The first eight names are planned behavioral suites/seams and become valid only when their tests join `Desktop/Tests`. Prefer actual `Bundle` fixtures, view models/rendered accessibility state, injected URL openers/provider clients/log handlers, temporary local stores, and existing production policies. A resource-name/source search is a **static tripwire**, never the proof that the user sees correct copy or that telemetry honors consent.

### Brand, backend, provider, release, and public-site contracts

From the repository root, adjusted only to the final S-27/S-29 documented runners:

```bash
python3 .github/scripts/check_brand_ui.py
python3 .github/scripts/test_check_brand_ui.py

cd backend
bash test-preflight.sh
.venv/bin/python -m pytest -q tests/unit/test_logging_config.py tests/unit/test_log_sanitizer.py
.venv/bin/python -m pytest -q tests/unit/test_openapi_contract.py
scripts/openapi_runner.sh scripts/route_policy_inventory.py \
  --manifest route_policy_manifest.yaml --check --report-only
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
bash test.sh
cd ..

python3 .github/scripts/test_desktop_release_source_identity.py
python3 .github/scripts/test_desktop_release_flow_contract.py
python3 .github/scripts/test_desktop_release_manifest.py
python3 .github/scripts/test_desktop_release_doctor.py
python3 .github/scripts/test_check_release_rings.py
python3 .github/scripts/test_check_release_process_guards.py
scripts/run-release-process-guards.sh
```

Run S-29's actual public-site test/build/link commands exactly as documented after integration; do not invent a package manager or path before its files exist. If OpenAPI source descriptions change, run the owning generators/checkers and commit generated non-Windows output. If no source contract changes, do not churn generated clients.

### Whole-repository and PR contracts

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
make preflight
scripts/pr-preflight --suggest
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
git status --short --branch
```

Before a future `fix:` PR body, follow the suggested failure class, include `Failure-Class: FC-<slug> | new | none`, and run `scripts/failure-class` as directed. A newly proposed deterministic identity/truth check must cite the real merged PR or incident it would have caught and join `.github/checks-manifest.yaml` with local and CI lanes. With no real instance, no new gate lands.

## 15. Real named-bundle, backend, infrastructure, and release acceptance

Never launch, stop, overwrite, inspect, or automate `/Applications/Omi.app`, `/Applications/Omi Beta.app`, `com.omi.computer-macos`, or `com.omi.computer-macos.beta`. Use only the assignment's future non-production bundle `omi-wave6-s30`, consuming whatever safe namespace mapping S-28 establishes for named bundles.

### Named-bundle launch

From the repository root after focused/component GREEN:

```bash
PROVIDER_MODE=offline make dev-up
make desktop-run-local DESKTOP_APP_NAME=omi-wave6-s30 DESKTOP_USER=alice
```

Keep the foreground local-profile launcher running. Use the worktree-specific automation port printed by the launcher. From `desktop/macos` in another shell:

```bash
OMI_AUTOMATION_PORT=<PORT> ./scripts/omi-ctl wait-ready 90
OMI_AUTOMATION_PORT=<PORT> ./scripts/omi-ctl health
OMI_AUTOMATION_PORT=<PORT> ./scripts/omi-ctl state

python3 scripts/omi-harness run e2e/flows/navigation.yaml \
  --lane bridge --port <PORT> --bundle-id <S-28-NAMED-BUNDLE-ID>
python3 scripts/omi-harness run e2e/flows/home-stage.yaml \
  --lane bridge --port <PORT> --bundle-id <S-28-NAMED-BUNDLE-ID>
python3 scripts/omi-harness run e2e/flows/privacy-settings.yaml \
  --lane bridge --port <PORT> --bundle-id <S-28-NAMED-BUNDLE-ID>
python3 scripts/omi-harness run e2e/flows/about-settings.yaml \
  --lane bridge --port <PORT> --bundle-id <S-28-NAMED-BUNDLE-ID>
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-wave6-s30 --port <PORT>
```

`<S-28-NAMED-BUNDLE-ID>` is intentionally unresolved in this planning baseline. Execution must substitute the integrated S-28 truth; retaining `com.omi.omi-wave6-s30` by assumption would violate the slice.

### Manual screen, copy, and interaction ledger

Record screenshots/accessibility trees, exact strings, action outcomes, bundle/PID/port/log path, and links for:

1. clean first launch under S-28 namespaces with no inherited app data, identity, permissions, Keychain session, defaults, logs, caches, or updater state;
2. sign-in initial/revealed/reduced-motion states and OAuth success/failure/invalid browser pages, including support/footer and return-to-app behavior;
3. every onboarding stage, Back/resume, each permission Skip, global Skip, both capture choices, completion, and opener; behavior must match S-17;
4. Home empty/history/static welcome/onboarding-opener priority, Memory exact IR-269/287 text, Tasks/Insights/Focus/Rewind, floating bar, menu/status, settings search, and local Stats/no Apps;
5. Privacy & Data: data-location card, What We Track expansion, PostHog default state, opt-out before restart, identity detachment, re-enable, independent Sentry, independent Enhanced Diagnostics, Report Issue, export, and account-deletion explanation;
6. About: exact identity/version/build/beta, exact-tag release URL and fallback, Visit Website, Privacy & Data local route, Terms browser link, and absent Help Center;
7. local notification and fair-use surfaces, errors, permission guidance, What’s New after simulated version change, update blocker/remediation, RAM/relaunch guidance, and safe non-production self-install simulation supported by S-29 fixtures;
8. all icons/wordmarks/menu/notch/backdrop at light/dark or relevant appearance, common scaling, minimum supported window, reduced motion, and accessibility; no purple and no inherited art;
9. offline/restart/owner-switch behavior to prove identity edits did not alter local authority or leak one synthetic user's telemetry/store into another;
10. exact bundle log and representative debug-only telemetry dry runs, confirming approved event/release/service identity, content sanitization, and PostHog silence while opted out.

### Backend and infrastructure truth acceptance

Use the offline/local backend and S-27's read-only non-production inventory/probes. Record:

- `/v1/health`, authenticated `/metrics`, and representative retained routes resolve through the one canonical backend;
- runtime/deploy manifests and actual non-production revision metadata say `us-west1`, the owned project/service identity, retained Firebase/Redis/Firestore/GCS/Cloud Tasks roles, and no retired duplicate service;
- `/v4/listen` disclosure matches managed Modulate transport and transient segments; model/translation disclosures match configured providers without sending user content merely to test copy;
- sanitized logs, Sentry dry-run payloads, PostHog debug recorder, and Langfuse configuration use approved projects/service/release names and no secrets/PII;
- `BILLING_MODE=disabled` produces zero Dodo checkout/portal/provider calls and every UI/public statement remains truthful about that state.

Live provider success is not required to prove a copy string. Final all-waves real-provider continuity remains BL-001. If a claim can only be proven by an authorized real non-production probe, leave its row open rather than asserting it.

### Release and public-destination acceptance

Using S-29's signed fixtures/dry-run/non-production lanes only:

- resolve and validate product, Terms, Privacy, support, GitHub exact-tag release, appcast/manifest, preview, candidate, Beta, Stable, and rollback destinations;
- verify TLS, final ownership after redirects, status/content type, product identity, cross-links, accessibility metadata, no secret indexing, and correct Privacy/Terms effective content;
- prove manual `workflow_dispatch`, dedicated builder identity, signed manifest/pointer verification, artifact filenames, release-note fallback, and update/repair copy through S-29 tests;
- retain immutable evidence without publishing, promoting, notarizing, signing with production credentials, or changing DNS/live pointers under S-30 authority.

## 16. Repository closure versus separate operational closure

### Repository closure owned by S-30

- approved identity/legal packet is referenced and every used value has an accountable owner;
- integrated code, rendered macOS surfaces, current non-Windows release/public sources, provider disclosure, logs/analytics/service labels, and operator docs agree;
- false Privacy/security/local/cloud/billing/provider/release claims and duplicate guarantees are gone;
- inherited current-use assets, URLs, emails, names, events, logs, and service labels are gone or replaced at their owning seams;
- protected history/provenance, internal symbols, tests, temporary bundle name, and Windows matches are classified rather than blindly scrubbed;
- affected component suites, public-site/release/backend contracts, named-bundle acceptance, residue ledger, and repository gates pass on one committed SHA;
- product/legal approvers have reviewed the literal final public/in-app copy, while engineering has reviewed its production evidence.

### Separately authorized operational closure

S-30 repository work does not itself:

- create/rename/delete PostHog, Sentry, Langfuse, Modulate, AI-provider, Firebase, Google Cloud, Redis, Dodo, GitHub, DNS, email, or website accounts/resources;
- rotate or distribute secrets, migrate analytics history/dashboards, rename a live Cloud Run service, deploy backend/site code, mutate IAM, or change retention settings;
- sign, notarize, publish, promote, roll back, or update a production desktop build or appcast/manifest pointer;
- launch or alter production Omi/Omi Beta bundles, import legacy user data, or change customer data;
- activate `dodo_test` or `dodo_live`, run checkout, or claim billing acceptance;
- close BL-001 real-provider/physical/final-release qualification or BL-002 live-resource inventory merely because repository copy is correct.

Those operations use S-27/S-29/post-Wave-6 runbooks under explicit authorization, with exact environment/resource identity, owner, before/after evidence, rollback, retention, and customer-impact review. A redirect can support a separately planned transition, but S-30 repository closure requires the app and current docs to use the owned canonical destination rather than depend indefinitely on inherited URLs.

## 17. Risks, ambiguities, and explicit stop points

| Risk or ambiguity | Safe action | Stop/evidence boundary |
|---|---|---|
| Final product/company name is not specified | Complete inventory and tests; wait at Cycle 0 | Approved G2 packet. Never infer from repository/workspace name or support email. |
| S-27/S-28/S-29 are not integrated | Read-only inventory/characterization only | All three integrated with acceptance evidence before product GREENs. |
| Release guide conflicts with manual workflow | Record exact conflict for S-29 | S-29 must reconcile code/tests/docs; S-30 does not choose mechanics. |
| Legal/security claim lacks evidence | Remove an unnecessary marketing absolute or leave row open for approval | Legal owner and production evidence required before publishing any affirmative claim. |
| “On this Mac” can be overgeneralized | Name the exact local authority and separately disclose transient provider compute | Stop if wording suggests all processing is local. |
| Provider inventory changes after integration | Regenerate fact matrix from current config/callers/payload tests | Any unclassified provider, purpose, retention, or content category blocks Privacy GREEN. |
| Dodo exists in code but is disabled | State disabled/current retained role and prove zero calls | Any activation or paid-product claim is post-Wave-6 and separately authorized. |
| Support email currently says `support@heyintentive.com` | Preserve until G2 decides the owned canonical address | Do not infer final corporate identity; unverified mailbox blocks link/copy replacement. |
| Broad Omi replacement breaks internal code | Classify call sites; rename only external identity or S-28/S-29-owned operational symbols | No blind repository-wide replacement or compatibility aliases. |
| Analytics/event rename breaks dashboards | Atomic producer/consumer/test migration with explicit mapping | Proven external consumer without coordinated cutover stops; no dual emission by default. |
| Asset replacement alters UI or introduces purple | Keep layout, run visual/accessibility/no-purple tests | Missing provenance, sizes, contrast, or neutral variant blocks GREEN. |
| Historical names remain | Keep and classify historical changelog/provenance/incident evidence | Never rewrite history to make a search count zero. |
| Current comments/docs describe old behavior | Update them because they are current guidance, not protected history | Stop if actual integrated behavior is unclear; do not choose the prettier story. |
| S-20 exact notification/support semantics collide with copy | Change nouns/contact only and retain behavior tests | Any timing/action/severity change returns to S-20 or needs a separate decision. |
| S-29 URLs exist only as placeholders or inherited redirects | Run ownership/TLS/content checks | Canonical owned destinations are required; redirect-only inherited ownership does not close S-30. |
| A new guard seems useful | Use existing tests/match ledger first | New gate requires a real merged PR/incident, shared-primitive explanation, and local+CI manifest lanes. |
| Test proves strings by source scraping | Label it static tripwire and add rendered/payload behavior proof | Static occurrence/order never counts as behavioral coverage. |
| Production credentials/app are needed | Use named bundle, offline/dry-run fixtures, read-only non-prod evidence | Stop; S-30 does not authorize production access or live mutation. |
| Full suites expose inherited failures | Baseline, assign, and fix only S-30-owned regressions | Official affected suites and required E2E must be green; inherited red is not waived. |

The genuine unresolved choices are external identity/legal inputs and predecessor outputs, not engineering discretion. Once those are supplied, the implementation should make narrow evidence-backed changes rather than reopen product architecture.

## 18. Final completion checklist

### Entry and authority

- [ ] `make setup`, hook verification, current `origin/main` integration, ancestry, status, validator, and inherited-test baseline are recorded.
- [ ] Integrated S-09, S-17, S-21, S-27, S-28, and S-29 outputs satisfy G1 on the execution SHA.
- [ ] S-29 resolved the manual-release documentation/workflow conflict.
- [ ] The complete versioned G2 identity/legal truth packet is approved, reachable, internally consistent, and contains no source-controlled secrets.
- [ ] The execution-head match ledger and data-flow truth matrix cover every §7 and §13 surface.

### Product identity and assets

- [ ] Stable/Beta/dev product identity, bundle family, URL scheme, artifacts, appcast, resources, and accessibility names agree with S-28/S-29.
- [ ] Approved icons, wordmarks, menu/notch marks, and shared sign-in/onboarding backdrop resolve at every size/state with recorded provenance.
- [ ] No current inherited Omi/BasedHardware visual/name/domain/repository/support identity remains outside classified exceptions.
- [ ] No purple or layout/contrast/accessibility regression is introduced.
- [ ] No old storage/Keychain/default/log/cache import, takeover, migration, or compatibility alias exists.

### Sign-in, onboarding, and shell truth

- [ ] Sign-in and OAuth callback identity/copy/links are exact while S-08 auth security and layout remain unchanged.
- [ ] Every S-17 onboarding stage and opener uses approved factual copy and owned repository link without state/effect changes.
- [ ] Home/Chat/floating/menu/status/errors use final identity and available-capability wording without navigation or behavior drift.
- [ ] IR-269 and IR-287 exact Memory strings remain byte-for-byte guarded.
- [ ] IR-514 static welcome remains static, local-capability bounded, opener-subordinate, and unjournaled.
- [ ] IR-521 neutral dark/no-purple and IR-930 local Stats/no Apps remain intact.

### Privacy, providers, and telemetry

- [ ] Fake `Active` security state, Privacy Guarantees card, and four false absolutes are deleted.
- [ ] What We Track matches observed PostHog/Sentry fields/categories and raw-content exclusions.
- [ ] PostHog default/setup/identify/opt-out/detach/re-enable behavior passes; Sentry and Enhanced Diagnostics remain independent.
- [ ] In-app and public Privacy accurately distinguish local authority, Firebase/minimal server data, Dodo disabled/current role, PostHog, Sentry, Langfuse, retained AI providers, Modulate, retention, controls, export, and deletion.
- [ ] No IR-802 redundant provider card is added.
- [ ] Owned PostHog/Sentry/Langfuse project/release/service identities are configured through existing secret/config owners; no secret/PII enters source, logs, analytics, or evidence.

### Links, updates, release, and operator truth

- [ ] About preserves identity/version/build/beta, exact-tag release/fallback, Visit Website, Privacy & Data, and simple Terms behavior; Help Center remains absent.
- [ ] Product, Terms, Privacy, support, repository/release, preview, appcast/manifest, candidate, Beta, Stable, and rollback destinations pass ownership/TLS/content/cross-link checks.
- [ ] Notifications, fair-use, errors, What’s New, update blocker, RAM/relaunch, self-install, and repair guidance use final identity without semantic/mechanical changes.
- [ ] Brand-bearing analytics/action/log/service/release labels are atomically migrated with producers, consumers, tests, and dashboard/protocol ledger; no dual compatibility names remain.
- [ ] Current docs describe one owned `us-west1` backend, retained provider roles, local authority, disabled billing, manual candidate workflow, signed S-29 rings/previews/rollback, and no retired service/product.
- [ ] Historical changelog, release, incident, failure-class, LICENSE, and FORK provenance remains accurate and classified.
- [ ] Windows remains untouched.

### Verification and closure

- [ ] Every cycle captured the intended RED before its minimum GREEN and recorded focused commands/results.
- [ ] All affected desktop/backend/public-site/release/provider tests and official component runners pass.
- [ ] `omi-wave6-s30` acceptance covers every §15 screen/action/link/log row without touching production bundles.
- [ ] Offline and synthetic-owner checks show no storage, auth, telemetry, or presentation cross-owner leakage.
- [ ] Final residue searches have no unexplained current identity or false-promise match; every protected/internal/Windows/test exception has evidence.
- [ ] Generated non-Windows outputs, if any, were regenerated from their owner; no generated file was hand-edited.
- [ ] `python3 bootstrap-scaffold/validate-requirements-ledger.py`, `git diff --check`, `make preflight`, PR preflight, failure-class handling, and final status all pass.
- [ ] Product/legal approved the literal final copy and pages; engineering approved their code/data-flow evidence.
- [ ] PR evidence declares named bundle, execution SHA, commands/results, screenshots/link report, identity/truth ledgers, retained history, unresolved operational rows, and `BILLING_MODE=disabled`.
- [ ] No deploy, live provider/cloud/DNS/email mutation, production app interaction, signing/notarization/publication/promotion, billing activation, or customer-data mutation is implied by repository closure.

S-30 is complete only when one final execution SHA is simultaneously behaviorally unchanged, externally reowned, visually neutral, operationally consistent, and literally truthful. A polished screen with a false claim, a correct Privacy page with inherited provider identity, an owned bundle with stale release/operator names, or an empty old-name search achieved by rewriting history is not completion.
