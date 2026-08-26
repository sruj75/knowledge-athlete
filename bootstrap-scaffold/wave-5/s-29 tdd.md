# S-29 TDD plan — re-own Mac build, signing, updates, previews, and public/legal release destinations

## 1. Title and slice identity

| Field | Value |
|---|---|
| Wave | **5 — re-own and simplify the surviving platform** |
| Slice | **S-29** |
| Name | **Re-own Mac build, signing, updates, previews, and public/legal release destinations** |
| Type | Release-system adaptation |
| Primary decisions | **IR-010, IR-243 through IR-253, IR-804, IR-821, IR-892 through IR-897, IR-927 through IR-929, IR-939** |
| Roadmap authority | [`../deletion-map.md`](../deletion-map.md), S-29 and the shared closure contract |
| Decision authority | [`../requirements-challenge.md`](../requirements-challenge.md), indexed rows and full detailed decisions |
| Research lead | [`../deletion-slice-research.md`](../deletion-slice-research.md), release/signing/update/preview/public-hosting split |
| Required predecessors | **Integrated S-26, S-27, and S-28**, in addition to S-04 and S-09 |
| Future named development bundle | **`omi-wave5-s29`**; its post-S-28 bundle identifier and URL scheme are predecessor outputs, not values to guess here |
| Planned implementation shape | **11 ordered TDD cycles (0–10)** |

This is the implementation plan, not implementation evidence or operational authorization. Preparing it changes no product source, test, workflow, schema, signing material, provider account, hosted runner, cloud resource, public site, release channel, or production application.

S-29 owns the complete retained Mac release system: the checked-in Codemagic definition; Developer ID and notarization contract; stable, Beta, preview, Sparkle, feed, and signing identities; manual candidate intake; trusted M1 qualification; immutable evidence; Beta/Stable publication, recovery, rollback, and break glass; signed previews; public release/product/legal destinations; and the release consumer/provenance contract for the universal libwebp/libsharpyuv binaries. It consumes S-27's cloud identities and S-28's application identities. S-30, not S-29, owns the repository-wide visible copy, privacy-claim, and product-identity sweep.

## 2. Planning status and pinned baseline

**Planning status:** source-grounded and ready as a plan; implementation is blocked on integrated S-26, S-27, and S-28 plus the external inputs in §5. No later planning document or expected predecessor shape counts as integrated implementation.

The required and inspected planning baseline is:

```text
22ad2f16ff8d63fd761c918b92f4c5d961814624
```

Planning-time checks established:

```text
git merge-base --is-ancestor 22ad2f16ff8d63fd761c918b92f4c5d961814624 HEAD  # exit 0
git rev-parse HEAD                                                    # 22ad2f16...
git rev-parse origin/main                                             # 22ad2f16...
git status --short --branch                                           # plan-waves-5-6-slices, clean
```

`git fetch origin` completed before inspection. The current branch was not renamed or switched. The initial requirements-ledger validator passed:

```text
Requirements ledger validation: PASS
714 indexed rows, 714 detailed sections, all reviewed
```

The baseline contains the complete Waves 3–4 repository repair tree, but neither BL-001 nor BL-002 is closed:

- [`../../BACKLOG.md`](../../BACKLOG.md) **BL-001** still defers final all-waves live-provider continuity and qualification. It does not block this planning work, but it blocks the final release claim.
- **BL-002** still records S-25's live resource classification as unknown. Repository absence is not live-resource absence; it blocks destructive operational cleanup and any claim that inherited live release resources are gone.
- `BILLING_MODE=disabled` remains mandatory through Wave 6. No Dodo or Stripe resource is part of S-29. Post-Wave-6 Dodo work remains governed by [`../dodo-integration.md`](../dodo-integration.md).

The current tree is deliberately a **pre-predecessor** view. It still contains Omi release identities, a dormant `backend_required` manifest variant, a separate `desktop-backend` health assumption in qualification/promotion, Omi buckets/domains/bot/runner labels, and no root `codemagic.yaml`. Those are observations to refresh after integration, not permission for S-29 to reproduce S-26, S-27, or S-28.

No component suite, app bundle, backend process, provider path, signed artifact, cloud inventory, or live release operation was run while creating this plan. Commands and evidence in §§11, 14, and 15 are future requirements unless explicitly marked as planning-time evidence above.

## 3. Outcome

S-29 closes the repository release boundary when this single path is true:

```text
manual candidate request for exact admitted main SHA
  -> immutable product-owned macOS tag
  -> checked-in owned Codemagic release workflow
  -> exact universal app + dSYM
  -> product-owned Developer ID + hardened runtime + entitlements
  -> Apple notarization + staple
  -> Sparkle EdDSA-signed ZIP + signed/notarized DMG
  -> signed-artifact smoke, including auth-storage canary
  -> immutable GitHub candidate assets and provider-intake evidence
  -> exact-tag trusted M1 Studio qualification
  -> immutable qualification evidence
  -> canonical Python backend admits the same artifact to Beta
  -> manual Stable promotion of that already-qualified artifact
  -> appcast/download/policy readers resolve product-owned state
  -> recovery, rollback, and break glass retain CAS/audit boundaries
```

The separately retained preview path is:

```text
manual preview/<slug> request
  -> full immutable source SHA + protected approval
  -> separate owned Codemagic preview workflow
  -> branch-derived S-28 product preview identity
  -> signed/notarized co-installable DMG with no shared Sparkle updater
  -> immutable preview manifest + compare-and-set current pointer
  -> owned current and immutable public landing pages
  -> authorized replacement or delisting without deleting immutable evidence
```

The release client retains manual **Check Now**, forced automatic checks/downloads for published builds, ten-minute Stable and two-minute Beta polling, local Stable/Beta preference, exact GitHub release notes, local post-update toast, fail-open server update policy, guarded immediate install/relaunch, and runtime self-install. Named development and external preview bundles remain isolated from the shared production updater.

The end state has no Omi Codemagic assumption, Developer ID/team, Sparkle key, bundle/feed identity, bot, runner label, GitHub repository, service URL, Firestore/GCS namespace, bucket, domain, preview URL, website, Terms, Privacy Policy, support destination, or `backend_required` release mode in the non-Windows release graph. Historical changelogs are not rewritten. S-30 receives a truthful, owned destination/identity map and performs the final visible-copy sweep.

## 4. Authorizing requirements

The detailed decisions below were read, not inferred from indexed rows. A changed decision at execution time is a stop condition.

| Decision | S-29 obligation | Cycle(s) |
|---|---|---|
| **IR-010** | Re-own the retained release, update, telemetry handoff, feedback/support destination, and public boundary without restoring rejected products. | 0–10 |
| **IR-243** | Keep manual Sparkle checking, status-menu access, in-progress/last-check UI, classified recovery, manual download, and named/preview isolation; repoint owned infrastructure. | 1, 10 |
| **IR-244** | Keep forced release auto-check/download, immediate launch check, Stable 10-minute/Beta 2-minute cadence, disabled explanatory switches, telemetry, and dev isolation. | 1, 10 |
| **IR-245** | Keep immediate published-build install/relaunch but replace the ineffective VAD-only decision with one authoritative local admission seam for ambient transcription, PTT/realtime voice, and active Chat/model/tool work. Preserve window restoration and target-build verification. Do not repair Local VAD. | 3, 10 |
| **IR-246** | Keep the complete local-authoritative Stable/Beta choice and Beta-bundle pinning; consume predecessor deletion of the per-user Firestore field and preserve the separate backend release-channel documents. | 1, 7, 10 |
| **IR-247** | Preserve About identity/version/build/Beta presentation and search reachability. S-28 supplies bundle identity; S-30 owns final visible name/artwork/copy. | 1, 9, 10 |
| **IR-248** | Keep exact running-version GitHub release notes and the non-production releases-list fallback; point both to the owned repository. | 1, 9, 10 |
| **IR-249** | Keep local build-keyed post-update toast, suppression state, click-through, background-window behavior, and telemetry; repoint the release destination. | 1, 9, 10 |
| **IR-250** | Keep **Visit Website** behavior and point it to an owned public product page. S-30 owns final row copy. | 9, 10 |
| **IR-251** | Consume S-21's deletion of Help Center and prove it is not recreated as a release-support dependency. | 0, 9, 10 |
| **IR-252** | Preserve the in-app **Privacy & Data** navigation as practical settings/disclosure; separately provide a real owned hosted Privacy Policy. Never conflate the two. | 9, 10 |
| **IR-253** | Keep the simple browser Terms link under owned hosting; add no checkbox, versioned acceptance state, or cloud consent ledger. | 9, 10 |
| **IR-804** | Consume S-26's single canonical Python backend and deletion of dormant exact-SHA `backend_required`; keep independent backend deploy plus fail-closed live health/readiness and explicit compatibility-version qualification. | 0, 2, 6, 7, 10 |
| **IR-821** | Consume deletion of Firestore announcements; preserve only local release notes and the local post-update toast. | 0, 10 |
| **IR-892** | Add a complete root `codemagic.yaml` for exact-source universal build, owned Developer ID signing, hardened runtime/entitlements, notarization/stapling, Sparkle EdDSA, ZIP/DMG, dSYM/Sentry, publication, and downstream evidence. | 4, 5, 10 |
| **IR-893** | Keep deliberate manual candidate publication, exact tag/source binding, provider intake, one trusted M1 lane, hygiene/capacity, immutable evidence, recovery/retry, and manual Stable promotion under owned identities. Correct automatic-release documentation drift. | 6, 10 |
| **IR-894** | Keep immutable release manifests, reservation/admission, Beta/Stable pointers, appcast/download, qualification binding, recovery, rollback, break glass, idempotency, and conflict-safe transactions in the canonical backend under owned infrastructure. | 2, 7, 10 |
| **IR-895** | Keep manual exact-SHA signed branch previews with separate identity/state, backend compatibility mode, immutable manifests, mutable CAS pointers, landing pages, replacement, and delisting. | 5, 8, 10 |
| **IR-896** | Point product, Terms, real Privacy Policy, support/contact, download, preview, and exact GitHub release-note behavior at one small owned external static site plus the owned GitHub repository. Do not restore the absent web estate. | 9, 10 |
| **IR-897** | Preserve present Mac/backend controls and Windows untouched; consume S-04 absent-source deletion; add only the missing owned Codemagic definition and its current-owner validation. | 0, 5, 10 |
| **IR-927** | Keep the existing separate update-policy reader and `none`/`banner`/`required` behavior, targeting, local dismissal, required overlay, five-minute refresh, URL validation, stable fallback, and fail-open telemetry; re-own the document, endpoint, operator control, and URLs. | 2, 7, 10 |
| **IR-928** | Preserve retained ResourceMonitor sampling, remediation, and production extreme-memory relaunch after predecessor deletion of the rejected AgentSync pause. S-29 adds no second restart/update gate and proves update work does not regress it. | 0, 10 |
| **IR-929** | Consume S-28's rebranded runtime self-install identity; preserve DMG/translocation-only gate, no downgrade, staging/atomic replacement, quarantine clearing, delayed relaunch, two-attempt loop guard, and fail-open manual recovery. Exercise it on S-29's signed artifact; do not create another installer. | 5, 10 |
| **IR-939** | Retain libwebp 1.5.0 `libwebp.7.dylib` and `libsharpyuv.0.dylib`; make their checksums, two architectures, `@rpath` install names, compatible minimum OS, nested signing, and from-source fallback executable inputs to the owned provider. | 4, 5, 10 |

Related fences:

- **IR-009:** Windows and Windows-only workflows are outside this audit. Searches must exclude them; no Windows file is opened or changed during implementation.
- **IR-809:** the retained update/preview GCS bucket is protected product infrastructure, not rejected product-data storage.
- **IR-838/IR-839:** live health/readiness and one canonical backend service remain release prerequisites; S-29 does not create a second backend.
- **IR-001/IR-928:** no Agent VM synchronization pause or replacement is introduced.
- **IR-228/IR-245:** the disconnected Local VAD preference stays unchanged; it is not made authoritative for update admission.
- **IR-931/S-28:** no Omi local takeover, process cleanup, storage import, or old namespace compatibility is introduced.
- **IR-940/S-04:** the undiscoverable nested install workflow remains deleted; signed install acceptance must use a real discoverable/local S-29 path.

## 5. Dependencies and entry gates

### G0 — mandatory execution-time setup, rebase, and inventory refresh

Before the first implementation RED:

1. run `make setup` and verify the linked-worktree-safe pre-commit hook;
2. fetch `origin`, integrate current `origin/main` into the current branch without renaming/switching it, and record `HEAD`, `origin/main`, merge base, status, and every post-baseline commit;
3. rerun `python3 bootstrap-scaffold/validate-requirements-ledger.py`;
4. rerun every inventory in §§6, 7, and 13, including generated contracts and all non-Windows workflows;
5. inspect recent fixes in each touched subsystem and run `scripts/pr-preflight --suggest` before drafting any `fix:` commit/PR body;
6. run focused characterization before editing so inherited failures are recorded rather than hidden.

Stop if the pinned baseline is no longer ancestral, an assigned decision changed, a successor took ownership, unrelated local edits overlap the target files, or a current authoritative guide contradicts the intended release semantics. Never bridge an unintegrated owner with an Omi alias, temporary URL, duplicate feed, or compatibility mode.

### G1 — integrated predecessor outputs are mandatory

Every production/configuration mutation cycle (1–10) is blocked on all three predecessor results. Cycle 0's read-only refresh and drafting of hermetic REDs are the only safe actions on the present baseline.

| Predecessor | Exact output S-29 expects to consume | S-29 must not reproduce |
|---|---|---|
| **S-26** | One canonical Python application and URL contract; Mac update/release routes mounted there; independent backend deploy semantics; health/readiness plus explicit compatibility version; dormant `backend_required`, desktop-backend image/source/digest fields, fixtures, schema branches, and release callers absent; one retained local/offline harness. | Python entrypoint/service consolidation, rejected harness pruning, route-policy consolidation, or temporary `desktop-backend` compatibility. |
| **S-27** | Owned development/production GCP project IDs; one Cloud Run service per environment in `us-west1`; canonical URLs; WIF/deploy/runtime identities; Artifact Registry; Secret Manager resources; Redis/Firestore ownership; retained update/preview GCS bucket and public-serving contract; deploy/rollback evidence; exact runtime env manifests. | Project/region/service/network/Redis/Firestore/GCS creation, backend deployment redesign, or inferred cloud identifiers. |
| **S-28** | Exact product stable/Beta/dev/preview bundle IDs, URL schemes, app-group/Keychain/login-item/defaults/cache/log/Application Support namespaces, app/binary/DMG names, self-install behavior, and clean product-owned upgrade boundary. The named `omi-wave5-s29` bundle must derive a non-production identity from that implementation. | Omi local-data import/takeover, namespace migration, old-app process termination/deletion, or guessed stable/Beta/preview identifiers. |

After integration, run a complete inventory rather than mechanically applying the pre-predecessor file list. If S-26 already deleted every `backend_required` surface, S-29 records a verified no-op for that deletion. If any predecessor output is incomplete, return it to that owner; do not absorb it into S-29 unless the requirements authority is explicitly changed.

### G2 — documentation/current-code conflict

The inspected `.github/workflows/desktop_auto_release.yml` is manual-only and IR-893 explicitly keeps deliberate candidate creation. `desktop/macos/AGENTS.md` and `desktop/macos/docs/release.md` still describe automatic candidate creation on Mac-affecting merges/schedules. At execution time:

- if the post-rebase workflow remains manual-only, correct both guides in Cycle 6;
- if an integrated change restored automatic triggers, stop and resolve the conflict against IR-893 before coding;
- do not silently reinterpret “auto release” filenames/comments as product authority.

### G3 — missing external inputs

No secret value belongs in Git, logs, artifacts, or this plan. Exact non-secret identifiers and public keys must be known before repository configuration is written; live installation/mutation requires separate user authorization.

| Missing input | Affected cycles | Safe work before it exists | Evidence that reopens work | Expected owner | Explicit user authorization for live setup/use? |
|---|---|---|---|---|---|
| Integrated S-26/S-27/S-28 merge SHAs and handoff evidence | 1–10 | Cycle 0 inventory/RED design only | All SHAs ancestral to implementation `HEAD`; predecessor suites/handoffs recorded | Predecessor implementers | No external authorization; integration must be in scope |
| S-28 exact stable/Beta/dev/preview identities, app names, URL schemes, filenames, namespace contract | 1, 4–10 | Activity-gate RED design; current libwebp verification | Committed typed/scripts identity contract and clean S-28 acceptance | S-28 | No for repository use; yes for certificate/profile registration if external |
| S-27 dev/prod project IDs, canonical backend URLs/service identity, Firestore database/namespace, update bucket/public origin, WIF and Secret Manager resource names | 1–2, 5–10 | Hermetic activity/libwebp work | Committed runtime/deploy manifest plus successful authorized S-27 evidence | S-27/cloud owner | Yes for any live cloud change |
| Owned GitHub organization/repository, GitHub App ID/installation, bot display identity, permitted environments/reviewers | 1, 5–10 | Local Swift/backend tests without remote URLs | Repository exists; exact app installation and protected environments are documented/readable | Repository administrator | Yes |
| Codemagic application ID and exact release/preview workflow IDs; secret-variable names and API-token placement | 5, 6, 8, 10 | Provider-independent scripts and config-schema tests | Owned Codemagic app visible; documented API result; protected secret names configured | Release administrator | Yes |
| Apple Team ID, Developer ID Application certificate/common name and private key packaging, notarization issuer/key/private key or accepted notary profile | 4–6, 8, 10 | Unsigned local build and library provenance tests | `security find-identity`, signing dry run, and authorized notarization history identify only owned material | Apple Developer account owner | Yes |
| Sparkle EdDSA keypair and rotation/cutover decision; only the public key may enter the bundle | 1, 5, 7, 10 | Feed/client behavior with test keys in hermetic fixtures | Public key fingerprint approved; private key present only in provider secret store; signed fixture validates | Release administrator | Yes |
| Exact M1 Studio runner name/labels, capacity owner, cleanup roots, GitHub runner group, and escalation contact | 6, 10 | Hermetic qualification scripts/fixtures | Owned runner is online, scoped, labeled, capacity checked, and can upload immutable evidence | Release/runner administrator | Yes |
| Product-owned Sentry organization/project and upload-token secret name | 5, 10 | dSYM generation/UUID matching tests | S-09 handoff plus owned project read access and secret configuration | Observability owner | Yes for secret/provider setup |
| Product, download, preview, Terms, Privacy Policy, support/contact domains/URLs and static-site repository/hosting owner | 1, 8–10 | Local destination type/tests with no production default; hosted-content drafting outside this repo if separately assigned | Pages resolve over HTTPS under owned DNS; destination, redirect, cache and publication ownership are documented | Product/legal/site owner | Yes for DNS/hosting/publication |
| Versioned S-29 publication packet: approved current product/Terms/Privacy/support content, company/contact/jurisdiction, processor/retention list, and accountable approvers | 9–10 | Preserve **Privacy & Data**, implement destination/content fixtures, and add no legal claim | Product/legal approval sufficient for truthful current S-29 publication; exact packet revision is recorded for S-30's final architecture-wide truth reconciliation | Product/legal owner | Yes for publication |
| Verified BL-002 read-only live inventory and operator identity | 7–10 operational close | Repository and hermetic/local verification | Sanitized inventory with identity, project, timestamp, and resource classification | Cloud/release operator | Read-only inventory needs verified identity; any mutation requires separate explicit authorization |

Missing credentials do not justify committing Omi defaults, placeholders that can ship, unsigned “temporary” releases, local hand-built release artifacts, alternate GitHub Actions builders, or hand-edited appcasts.

The public/legal handoff is deliberately sequential. S-29 owns hosting, DNS/redirect/cache ownership, destination mechanics, and publication of the versioned owner-approved S-29 packet. It records the exact content revision and hands the live/rendered surfaces to S-30. S-30 then owns the final literal copy and architecture-wide privacy/legal truth reconciliation after S-29 is integrated; it may update content through S-29's established publication path but must not redesign that path. S-29 must not claim S-30's final truth pass, and S-30 must not wait for S-29 to author its final copy.

### G4 — three authorization layers

1. **Repository/local layer:** implement code, tests, checked-in provider definition, docs, and local/named-bundle evidence after G1. This layer can never claim a signed release exists.
2. **Read-only inventory layer:** with a verified operator identity, inspect provider/cloud/release state and capture sanitized evidence. This layer changes nothing.
3. **Separately authorized mutation/release layer:** provision/rotate secrets or certificates, configure provider accounts/runners/environments/DNS, publish artifacts, mutate Firestore/GCS pointers, promote/roll back channels, or publish/delist previews. No repository merge or plan authorizes this layer.

## 6. Current production codeflow

This is the exact inspected pre-predecessor flow and must be refreshed after G1.

### 6.1 Sparkle client and local release behavior

`desktop/macos/Desktop/Info.plist` embeds Omi's `SUFeedURL` and `SUPublicEDKey`. `AppBuild.swift` classifies Omi stable, Beta, named-development, and external-preview bundles; owns the shared Omi appcast, GitHub releases base, manual-download URL, local `update_channel`, first-launch channel inference, Beta pinning, and production-family checks. `UpdaterViewModel.swift` starts Sparkle only where `AppBuild.allowsSparkleUpdates` is true, forces published auto-check/download, uses a 600-second Stable or 120-second Beta interval, supplies manual **Check Now**, classifies recovery failures, and records bounded telemetry.

`SettingsContentView+Controls.swift`, the status menu, `WhatsNewToast.swift`, and `OmiApp.swift` expose the manual check, Stable/Beta picker, last-check/recovery UI, exact release link, and local post-update toast. `DesktopUpdatePolicyManager.swift` independently fetches the server policy, renders a dismissible banner or non-dismissible required overlay, refreshes on launch/activation, and clears/falls back on failure.

### 6.2 Broken update-install admission boundary

After an automatic download, `UpdaterDelegate.updater(...willInstallUpdateOnQuit...immediateInstallationBlock:)` invokes the install block immediately in a published build unless `VADGateService.lastSpeechAt` is within 120 seconds. No retained production owner normally writes that timestamp. Meanwhile, live owners already expose the necessary state:

- ambient/meeting transcription: `AppState.current?.isTranscribing` and its authoritative local finalization lifecycle;
- PTT/realtime voice: `VoiceTurnCoordinator.shared.activeTurn`, `RealtimeHubController.lifecycleSnapshot` (capture, provider response, native playback, pending tools, coordinator turn, token mint), plus retained app-voice playback;
- Chat/model/tool: `ChatProvider.mainInstance?.isSending` and streaming-message state.

`DeferredUpdateInstall` currently tests time arithmetic, not the real authorization to interrupt these production activities. `UpdateRelaunchWindowPolicy` and next-launch build verification are separate retained behavior.

### 6.3 Missing artifact-building owner

The repository has no root `codemagic.yaml`. Downstream GitHub workflows expect the external workflow ID `omi-desktop-swift-release`, and previews call `omi-desktop-swift-preview`, but the code that builds a universal app/dSYM, injects identities, bundles nested runtimes/libraries, signs, notarizes/staples, signs the Sparkle archive, constructs ZIP/DMG, uploads dSYMs, runs signed smoke, and publishes assets is absent.

`desktop/macos/scripts/smoke-signed-desktop-artifact.sh` already verifies bundle/version identity, signing/entitlements, Sparkle/feed metadata, backend routing, helper/runtime packaging, local schema resources, ZIP/DMG alignment, launch/network/auth/chat/permissions/storage probes, quarantine behavior, a notification callback, and the required signed Keychain canary. `publish-desktop-debug-symbols.sh` generates a dSYM, matches executable UUIDs, archives it, and uploads it to Sentry. The new provider must call these production scripts; it must not reimplement weaker checks in YAML.

### 6.4 Candidate intake and qualification

`.github/workflows/desktop_auto_release.yml` is actually manual-only. It plans the release, serializes tag creation on the trusted M1 label, authenticates as Omi Bot, handles changelog consolidation by normal PR merge, binds the exact source, requires pre-tag readiness, creates the immutable tag, and proves Codemagic accepted that tag. It never calls the provider build endpoint directly.

`.github/workflows/desktop_qualify_beta.yml` is manual and globally non-canceling on the dedicated Omi M1 Studio labels. It creates a run-isolated exact-tag checkout, verifies an inherited separate `desktop-backend` health/service contract, downloads Omi-named candidate assets, runs the real qualification harness, creates immutable evidence, uploads it as a run artifact, and adds a content-addressed release asset. The post-success `desktop_promote_beta.yml` calls the canonical backend promotion API. Retry/recovery, capacity, lease, cache, watchdog, and cleanup scripts preserve the same exact-tag/evidence boundary.

### 6.5 Backend release authority

`backend/routers/updates.py` serves appcast, stable/Beta downloads, update policy, preview landing/publish/delist, release registration/read, candidate reservation, admission pause/resume, qualified Beta promotion, Beta break glass, and Stable channel promotion. `desktop_update_channels.py`, `desktop_beta_breakglass.py`, `desktop_previews.py`, and `desktop_update_policy.py` own Firestore operational state. `desktop_update_resolver.py`, `qualified_beta_promotion.py`, and `beta_breakglass_evidence.py` validate cached/persisted/GitHub evidence and record established fallbacks.

The release manifest executable/schema contract still admits `app_only` and dormant `backend_required`. The latter requires an exact separate desktop-backend source SHA and OCI index/platform digests and is represented in fixtures/tests despite having no normal producer. S-26 must remove that branch. The surviving manifest still needs the exact app source, ZIP/DMG URLs and hashes, EdDSA signature, qualification evidence, environment/compatibility version, timestamps, changelog/mandatory state, and immutable digest/signature semantics.

Current Stable promotion also bridges a legacy separate `desktop-backend` release endpoint, hard-codes `us-central1`, Omi API/feed/bucket/GitHub identities, then verifies the Stable pointer/appcast. The post-S-26/S-27 flow must have one canonical backend authority and no duplicate bridge.

### 6.6 Preview control plane

`.github/workflows/desktop_publish_preview.yml` accepts only `preview/<slug>`, resolves a full source SHA, requires `desktop-preview-publish` approval, derives a preview ID, supports production-compatible or explicit preview-backend URLs, directly starts the missing Omi Codemagic preview workflow, and reports an Omi landing URL. `desktop_previews.py` enforces Omi bundle/URL schemes, bucket host/name/path, stapled notarization, immutable per-SHA manifest, and compare-and-set pointer. Preview public GETs are separate from Beta/Stable; authorized DELETE removes only the pointer.

`AppBuild` and signed smoke correctly prevent a configured external preview from using local automation or the shared Sparkle feed. That safety must survive identity adaptation.

### 6.7 Install and public destinations

`AppInstaller.swift` runs before databases/capture/agents, installs only from DMG/translocation into `/Applications/<current app name>`, prevents downgrade, stages before atomic replacement, clears quarantine, schedules delayed relaunch, and fails open after at most two loop attempts. S-28 owns its identity adaptation; S-29 owns constructing and exercising the signed DMG that enters it.

About currently points **What's New** to `BasedHardware/omi` releases, **Visit Website** to `omi.me`, **Terms of Service** to `omi.me/terms`, and Stable manual download to `macos.omi.me`/`api.omi.me`. S-21 already removed Help Center and renamed the local shortcut **Privacy & Data**. There is no product/legal web source tree in this checkout, so owned static-site publication is an external boundary rather than permission to recreate the deleted web monorepo.

### 6.8 Universal WebP release input

`desktop/macos/vendor/libwebp/` contains libwebp 1.5.0:

| File | Planning-time SHA-256 | Architectures | Install name | `LC_BUILD_VERSION` minimum | Current signature |
|---|---|---|---|---|---|
| `libwebp.7.dylib` | `3515af9fc46957cbd3f879ee36b9bbc0283cf6e2bbd51032a943ec8a9e64b2ff` | `x86_64 arm64` | `@rpath/libwebp.7.dylib` | `13.0` on both slices | ad hoc/linker-signed |
| `libsharpyuv.0.dylib` | `5a92b18c7deee56b134d1079712e41e77d151584c20e894a3a9c176e9f9ed119` | `x86_64 arm64` | `@rpath/libsharpyuv.0.dylib` | `13.0` on both slices | ad hoc/linker-signed |

The app's declared floor is macOS 14, so a 13.0 library minimum is load-compatible; the release check should enforce “not newer than the app target,” not invent equality. Local `run.sh` intentionally continues to use Homebrew/pkg-config. The owned release provider must verify/copy these universal inputs or execute the documented two-architecture source rebuild, then sign the nested copies with the candidate identity before signing the outer app.

## 7. Complete caller and dependency inventory

This is a post-baseline refresh checklist, not a promise that every path survives predecessor integration.

| Boundary | Current owners/callers | Tests/contracts/docs | S-29 disposition |
|---|---|---|---|
| Bundle/update identity | `Desktop/Info.plist`; `AppBuild.swift`; `APIClient+Settings.swift`; `DesktopBackendEnvironment.swift`; S-28 app-config/run scripts | `AppBuildBetaIdentityTests`, `ExternalPreviewBuildTests`, API routing tests, app-config shell tests | **ADAPT** by consuming S-27/S-28 exact values; one typed release identity, no Omi fallback |
| Manual/automatic Sparkle | `UpdaterViewModel.swift`; Settings controls; status menu; `OmiApp.swift` | `UpdaterViewModelTests`, `UpdateFailureDiagnosticsTests`, Settings contracts | **KEEP + REPOINT**; preserve 10m/2m and dev isolation |
| Install activity admission | `UpdaterDelegate`, `DeferredUpdateInstall`, disconnected `VADGateService.lastSpeechAt`; `AppState`; `VoiceTurnCoordinator`; `RealtimeHubController`; `ChatProvider` | current helper tests plus future production-seam admission tests | **REPAIR** one local policy/seam; no VAD redesign |
| Relaunch/install recovery | `UpdateRelaunchWindowPolicy`; `OmiApp`; `AppInstaller.swift` | `UpdateRelaunchWindowPolicyTests`, `AppInstallerTests`, update relaunch E2E | **KEEP**; consume S-28 identity and exercise signed artifact |
| Update-policy client | `DesktopUpdatePolicyManager`; `DesktopHomeView`; `APIClient+Settings` | `DesktopUpdatePolicyManagerTests` | **KEEP + REPOINT**, fail open unchanged |
| Candidate planning/tag | `desktop_auto_release.yml`; plan/source-identity/changelog/pre-tag/tag-intake/observer scripts | corresponding Python/shell tests; checks manifest | **ADAPT** bot/repo/labels/names; keep manual exact-source shape |
| Provider build | root `codemagic.yaml` absent; downstream assumes two Omi workflow IDs | S-04 release guards intentionally stopped opening absent file | **ADD OWNED DEFINITION** and extend existing release-process guard, not a second builder |
| App packaging/signing | `Package.swift`; entitlements; `create-omi-beta-variant.sh`; `run.sh`; signed smoke; dSYM script; DMG assets | signed-smoke and symbol tests; package/resource guards | **ADAPT** exact stable/Beta identities and filenames; build universal |
| libwebp | `vendor/libwebp/**`; `CWebP` system target; local Homebrew bundling; screen capture consumers | README only for release fallback today | **KEEP + MAKE EXECUTABLE** in provider preparation, with behavioral script tests |
| M1 qualification | `desktop_qualify_beta.yml`; `qualify-desktop-beta.sh/service.py`; stage/profile/cache/reclaim/self-clean/watchdog/lease scripts | qualification contract, flow contract, cache/runner/pretag tests | **ADAPT** labels/roots/bot/assets/backend contract; preserve one M1 lane |
| Immutable evidence | `desktop_qualification_evidence.py`; candidate gate; release manifest/evidence schemas; GitHub assets | manifest/evidence/candidate tests, doctor | **KEEP + ADAPT** names/repo and remove predecessor-deleted backend mode |
| Beta promotion/recovery | `desktop_promote_beta`, `desktop_recover_beta`, retry, rollback, breakglass, admission-control workflows; backend routes/utils/db | release-flow, backend desktop update/channel/breakglass/promotion tests; Firestore contention harness | **KEEP + ADAPT** environment/URL/auth/project/namespace |
| Stable promotion | `desktop_promote_prod.yml`; stable precondition, repair installer, appcast verifier; release editing | stable verifier and prod-promotion-policy tests | **SIMPLIFY AFTER S-26** to one canonical backend and owned bucket/feed/repo |
| Backend release state | `routers/updates.py`; `desktop_update_channels.py`; `desktop_beta_breakglass.py`; resolver/promotion/evidence helpers | `test_desktop_updates`, channel/resolver/qualified-promotion tests; route policy | **KEEP + RE-OWN**; no customer product data |
| Dormant backend binding | manifest Python/schema/fixtures/tests, qualification/stable separate desktop-backend checks, backend release policy scripts/workflows | manifest and desktop-backend release-boundary checks | **VERIFY S-26 DELETION**; remove only residual release callers, never re-add mode |
| Update-policy server/operator | `desktop_update_policy.py`; GET route; Firestore `desktop_update_policy/current`; no checked-in owned operator mutation lane found | backend unit/route-policy tests | **KEEP + RE-OWN** document/credentials/fallback and establish one audited operator path, not a second policy system |
| Preview dispatcher/build | `desktop_publish_preview.yml`; missing Codemagic preview workflow; signed smoke `--preview` | release-process guard, backend release-script tests | **ADAPT** exact repo/provider/approval/backend URLs |
| Preview registry/public pages | `desktop_previews.py`; preview routes/HTML; runtime secret binding; GCS helper | `test_desktop_previews`, `test_desktop_updates`, route policy | **KEEP SEPARATE** from Beta/Stable; re-own namespace/bucket/domain/auth |
| Public/legal destinations | `AppBuild`, Settings controls, update policy defaults, workflow summaries, preview/backend landing HTML, README download entry where still product-owned | Settings/destination tests and real HTTPS acceptance | **ADAPT** exact owned destinations; site source remains external |
| Local release communication | `WhatsNewToast`, local defaults, About links | toast/Settings/app-build tests | **KEEP**; prove cloud announcements remain absent |
| Release telemetry | Sentry init/release tags; PostHog update events; release health metrics; dSYM upload | S-09 owners, Sentry scrub/symbol tests | **KEEP + REPOINT** only identities/destination; no new telemetry system |
| Runtime/deploy contracts | `backend/deploy/runtime_env.yaml`; route policy; OpenAPI; generated non-Windows Swift; runtime image/workflow/check manifests | backend route/OpenAPI/runtime/deploy tests | **ADAPT** only release-owned entries after S-26/S-27; no Windows changes |
| Operator documentation | root/backend/Mac guides; `docs/release.md`; qualification environment; release-health metrics; `FORK.md`; changelog fragment | agent-doc/check manifests | **UPDATE WITH CODE**; state manual candidate truth and exact owned boundaries |
| Protected siblings | ResourceMonitor, ambient capture/finalization, PTT/realtime, Chat/model/tool, owner switch/local stores, billing-disabled startup | their focused tests/Tier-2 paths | **KEEP AS IS**, except read-only activity snapshots consumed by the gate |

Generated client handling is evidence-driven: public appcast/download/update-policy/preview/release routes remain in route policy. Regenerate non-Windows clients only if the post-S-26 authoritative generator includes a changed retained DTO/route. Do not hand-edit generated output or touch Windows to make a generator diff disappear.

## 8. Behavior classification

| Category | Concrete S-29 behavior |
|---|---|
| **KEEP AS IS** | Manual Check Now/status menu/last-check/recovery; forced published automatic check/download; Stable 10-minute/Beta 2-minute cadence; local Stable/Beta preference and Beta pinning; exact release notes and local post-update toast; separate fail-open update policy; immediate install/relaunch, window restoration, target-build verification; runtime self-install/no downgrade/atomic replace/two-attempt fail-open; manual candidate, exact tag/source, one M1 qualification lane, immutable evidence; Beta/Stable reservation/admission/pointers/promotion/recovery/rollback/break glass; separate signed previews; local data authority/owner fencing; ResourceMonitor; Sentry/PostHog boundaries; `BILLING_MODE=disabled`. |
| **ADAPT** | S-27 backend/project/Firestore/GCS/WIF/secret/domain identities; S-28 stable/Beta/dev/preview identity and filenames; root Codemagic release/preview workflows; Developer ID/notary/Sparkle signing; GitHub bot/repo/environments; M1 labels/cache roots; artifact and dSYM publication; update/feed/manual-download URLs; backend release namespaces/auth; preview lifecycle/public URLs; website/Terms/Privacy/support/release-note destinations; one real update-activity admission seam; libwebp provider consumer/provenance. |
| **DELETE** | Omi release/provider/project/domain/bucket/bot/runner/bundle/feed/signing defaults and duplicate bridge; dormant `backend_required` release residue only if not already removed by S-26; cloud announcements residue; inherited external Help Center; impossible absent-source release controls reintroduced after S-04; direct release dependency on separate `desktop-backend`. |
| **SIMPLIFY AFTER** | Once GREEN: one typed Mac release identity/destination source; one canonical backend compatibility check; one provider build authority; one manifest state machine; one signed-smoke command; one documentation truth (manual candidate); remove empty compatibility branches, duplicate URL assembly, Omi-only asset aliases, and dead check clauses. |
| **ACCELERATE AFTER** | Measure Codemagic build, universal Swift build, dSYM, notarization, signed-smoke, and M1 qualification phases after correctness. Reuse the retained libwebp cache and existing Swift/cache/runner primitives only where measurements show the repeated cost. Otherwise `none`. |
| **AUTOMATE LAST** | Extend the existing release-process/check-manifest lanes after real-path proof. The Codemagic-presence/ownership regression would have caught merged subset snapshot PR #14 (`81b5b889`) omitting the provider definition while retaining consumers; use the existing shared release guard rather than a new checker. Add no scheduled/on-demand orphan automation. |
| **OUT OF SCOPE / DEFERRED** | S-26 canonical backend consolidation; S-27 cloud foundation/provisioning; S-28 local namespace/identity migration; S-30 global brand/copy/privacy/legal truth sweep; S-31 final all-waves release; BL-001 provider continuity; BL-002 destructive live cleanup; Dodo test/live activation; Windows; App Store distribution; new updater/installer framework; Local VAD repair; product-feature/model/prompt redesign; historical changelog cleanup. |

## 9. Retained behavioral invariants

1. **One artifact authority.** Codemagic builds the exact immutable candidate source. GitHub workflows may plan/tag/admit/promote but do not locally rebuild or call an alternate provider path. Stable is the same already-qualified artifact, not a rebuild.
2. **Independent backend authority.** The canonical Python backend deploys independently. Qualification and promotion fail closed on its live health/readiness and explicit compatibility version; unrelated Mac releases do not rebuild Python or require an exact shared source SHA.
3. **No dormant compatibility.** `backend_required` and separate desktop-backend image/digest binding are absent after S-26. No alias, ignored field, dual schema, migration shell, or default-to-Omi fallback preserves them.
4. **Signed identity is coherent.** Stable, Beta, named dev, and preview identities come from S-28. Developer ID Team ID, entitlements, nested code, app bundle, URL scheme, Sparkle public key/feed, artifact names, GitHub metadata, and signed smoke must agree.
5. **Private keys stay private.** Certificate private material, notarization keys, Sparkle private key, API tokens, GitHub App private key, admin/release/preview keys, Sentry token, and cloud credentials remain in approved provider stores. Evidence contains fingerprints/identities/digests, never secret bytes.
6. **Published artifacts are universal and immutable.** The app executable, required helpers, libwebp, and libsharpyuv have both required architectures; artifacts and evidence are content-addressed/exact-tag bound; mutable channel/preview pointers never overwrite immutable manifests/assets.
7. **Notarization is artifact-specific.** The distributed app/DMG is Developer ID signed with hardened runtime, successfully notarized, stapled, Gatekeeper-valid, and smoke-tested after final packaging. A successful compile or ad hoc signature is not equivalent.
8. **Updates remain safe and fast.** Published builds auto-check/download and install promptly, but never invoke the immediate installer while authoritative ambient transcription, PTT/realtime provider/playback/tool/mint, or Chat/model/tool state is active. The gate waits for idle without a time-based fail-open interruption.
9. **Development isolation remains absolute.** `omi-wave5-s29` and other named bundles never consume the production Sparkle feed or mutate production-family installs/data. External previews also disable shared Sparkle and local automation. Production Omi/Omi Beta bundles are never launched, stopped, deleted, or altered.
10. **Channel semantics stay local/server-separated.** The user's Stable/Beta preference is Mac-local. Firestore release pointers decide which immutable artifacts each channel serves. No per-user cloud preference or GitHub prerelease-label inference becomes an authority.
11. **Update policy is separate and fail open.** `none`/`banner`/`required` is a server operational document layered over Sparkle, not a replacement feed. Read failure clears the policy and records the existing fallback; a stale blocker never strands the app.
12. **Beta/Stable transitions remain fenced.** Reservation, admission generation, qualification evidence, CAS pointer transitions, idempotent retry, recovery, rollback, and audited emergency rollout preserve their current separation. Break glass relaxes evidence only where authorized; it never silently promotes Stable.
13. **Previews never become channels.** A signed preview has its own branch-derived identity, manifest, pointer, backend mode, URL, approval, and delisting lifecycle. It cannot enter Beta/Stable state because it is signed.
14. **Install behavior remains one system.** S-29's DMG exercises S-28's `AppInstaller`; there is no second bootstrapper. Equal/newer builds do not downgrade, failed staging preserves the installed copy, and relaunch failure leaves the current process alive.
15. **Public/legal destinations are truthful and owned.** **Privacy & Data** stays local; the legal Privacy Policy is hosted separately. Terms adds no acceptance ledger. Exact version notes use the owned GitHub release. No Omi redirect is accepted as owned closure.
16. **Local release communication survives cloud-announcement deletion.** The build-keyed toast and manual release notes remain; no Firestore announcement collection, dismissal, CTA, firmware notice, or generated caller is reintroduced.
17. **Operational release state is not customer product data.** Firestore release/policy/preview documents may persist operational metadata only. No conversation, recording, prompt, Memory, Task, or user content enters this ledger or release evidence.
18. **Billing remains disabled.** No release cycle creates Dodo/Stripe resources, enables checkout/entitlement, or changes the free-MVP boundary.
19. **Fallback telemetry uses existing owners.** Feed/policy/provider fail-open or mode change uses the existing component `record_fallback`/`recordFallback`; no one-off counter or raw sensitive response is logged.
20. **Windows and history remain untouched.** Non-Windows release reownership neither inspects nor edits Windows; historical changelogs may retain historical Omi references.

## 10. Target authority, ownership, identity, and topology model

```text
S-28 typed application identity
  stable bundle / beta bundle / named-dev pattern / preview pattern
  URL schemes / app groups / Keychain / filenames / install namespaces
                         |
                         v
root codemagic.yaml (sole macOS artifact builder)
  release workflow                      preview workflow
  exact immutable tag                   exact preview source SHA
  universal app + dSYM                  branch-derived co-installable app
  vendored/rebuilt universal WebP        no shared Sparkle updater
  nested signing -> outer signing        separate signed/notarized DMG
  notarize + staple
  Sparkle EdDSA ZIP + DMG
  signed smoke + auth-storage canary
            |                                      |
            v                                      v
owned GitHub immutable candidate assets      owned GCS immutable preview object
            |                                      |
            v                                      v
trusted owned M1 qualification               canonical backend preview manifest
  exact tag + live canonical backend          + compare-and-set slug pointer
  immutable evidence                          + public current/immutable landing
            |
            v
canonical Python backend in S-27 prod project
  one live health/readiness + compatibility contract
  Firestore operational release namespace
    immutable app-only manifests
    Beta reservation/admission/pointer
    Stable pointer
    update-policy/current
  appcast + manual download + recovery
  rollback / break glass / cache repair
            |
            v
owned HTTPS download/feed domains
            |
            v
published S-28 stable/Beta apps
  local Stable/Beta preference
  manual + automatic Sparkle
  one local activity admission gate
  S-28 runtime self-install
```

Identity rules:

- S-29 reads public release identity from one post-S-28 typed/build configuration. It must not independently derive another bundle/URL namespace in Swift, shell, Codemagic, GitHub Actions, backend validation, or docs.
- The Sparkle public key and feed URL are signed bundle metadata; the matching private key exists only in Codemagic. Key rotation requires an explicit old/new client cutover plan and cannot be smuggled into a routine URL change.
- Candidate assets, qualification evidence, backend manifests, and pointers use the exact S-28 product artifact names and the same source/tag identity. Omi filename aliases are not retained.
- The backend's collection names and GCS paths use the owned namespace supplied by S-27/S-28. Because this fork is unreleased and has no inherited Omi customers, it starts clean rather than importing Omi release state.
- Public product/legal site hosting is externally owned and minimal. This repository stores only destinations/contracts it consumes; it does not recreate an absent application/web backend.

## 11. Ordered TDD cycles

### Cycle 0 — rebase, predecessor contract, and complete release inventory

- **Intended contract RED:** On the integrated execution tree, a machine-readable/manual inventory proves all S-26/S-27/S-28 outputs in G1 are present and the non-Windows release graph has exactly one provider-build gap to fill. It rejects dormant backend binding, separate backend release authority, Omi release identities, and reintroduced absent-source controls while preserving every retained release owner.
- **Why it fails now:** none of S-26/S-27/S-28 is integrated; `backend_required`, separate `desktop-backend` checks, Omi values, and missing `codemagic.yaml` are current facts.
- **Minimum GREEN:** rebase/integrate predecessors, rerun the full inventory, classify every hit as retained/adapt/delete/handoff/history, and write the implementation ledger before editing. Accept S-26/S-04/S-21/S-23 deletions as no-ops only after current proof.
- **Protected behavior:** all §9 invariants; especially Windows exclusion, local release communication, canonical backend, and S-28 identity ownership.
- **Expected surfaces:** no product change; implementation notes/PR evidence only. If a predecessor miss is found, its owner changes it before S-29 resumes.
- **Focused verification:** ledger validator; `git diff origin/main...`; inventories in §13; existing release-process, manifest, route-policy, AppBuild, update-policy, and installer characterization.
- **Deletion/simplification enabled:** eliminates stale assumptions and prevents duplicate predecessor work.
- **Stop:** any predecessor is absent/incomplete, a retained caller produces `backend_required`, an external released contract requires Omi identity, or an authority document changed.

### Cycle 1 — consume one release identity and preserve Mac update semantics

- **Intended behavioral RED:** Through production `AppBuild`/updater/destination seams with injected bundle metadata/defaults, assert the post-S-28 Stable, Beta, named `omi-wave5-s29`, and preview identities; owned feed/manual-download/GitHub release URLs; Stable/Beta local preference and Beta pinning; production updater enablement; named/preview disablement; 600/120-second cadence; exact-tag What's New; and no Omi fallback. Main-error cases—missing/malformed release metadata or an identity/feed mismatch—fail closed before a published build starts Sparkle.
- **Why it fails now:** Info.plist, AppBuild, API fallback DTO, tests, and Settings download paths embed Omi bundle/feed/repo/domain values; S-28/S-27 values are unavailable.
- **Minimum GREEN:** consume S-28's typed identity and S-27's public backend origin; make signed bundle metadata the feed/public-key authority; centralize only release destination assembly needed by existing callers; migrate every in-tree non-Windows caller in the same change. Preserve local `update_channel`; do not reintroduce its deleted Firestore sync.
- **Protected behavior:** IR-243/244/246/247/248/249; manual recovery; forced auto update; first-launch inference; Beta warning; telemetry; Settings/status menu/toast; dev/preview isolation.
- **Expected surfaces:** post-S-28 identity source; `Info.plist`; `AppBuild.swift`; `UpdaterViewModel.swift` only if configuration plumbing requires; `APIClient+Settings.swift`; About/update Settings; AppBuild/update/destination tests; package/build scripts that stamp metadata; `PRODUCT.md`/Mac guide if the documented contract moves.
- **Focused verification:** `desktop/macos/scripts/dev-feedback.py --once swift 'AppBuildBetaIdentityTests|ExternalPreviewBuildTests|UpdaterViewModelTests|UpdateFailureDiagnosticsTests|DesktopUpdatePolicyManagerTests|SettingsDestinationContractTests'`; `bash desktop/macos/tests/test-app-config.sh` or its post-S-28 successor.
- **Deletion/simplification enabled:** Omi Swift/plist URL and bundle defaults, duplicated release URL assembly, stale per-user channel residue found after rebase.
- **Stop:** exact S-27/S-28 values/public Sparkle key are missing, a named/preview bundle can start shared Sparkle, or the change requires guessing S-30 copy.

### Cycle 2 — one app-only release contract on the canonical backend

- **Intended behavioral RED:** Using the production manifest validator, FastAPI app, strict Firestore fake, route policy, and resolver, prove the post-S-26 manifest accepts only an exact app artifact/evidence/compatibility contract, rejects every `backend_required`/desktop-backend field, persists immutable idempotent manifests, resolves owned Stable/Beta pointers, serves owned appcast/download URLs, and returns fail-open update-policy defaults under the S-27 namespace.
- **Why it fails now:** the manifest/schema/fixtures admit `backend_required`; backend defaults and release asset URL validation require BasedHardware/Omi and api.omi.me; Firestore collection names/policy defaults/preview storage use Omi ownership.
- **Minimum GREEN:** consume S-26's app-only schema (or finish only a proven S-29-owned residual), bind release asset validation to the owned GitHub repository, bind public URLs/collections to S-27/S-28 release configuration, preserve immutable digest/signature and current transactions, update route/OpenAPI/generated non-Windows contracts only where authoritative output changes.
- **Protected behavior:** independent backend deployment; exact app source; qualification evidence; appcast/download; immutable manifests; CAS/idempotency; policy fail-open; sanitized fallback telemetry.
- **Expected surfaces:** manifest executable/schema/fixtures only if still present post-S-26; backend update router/database/resolver/promotion helpers; release config/runtime env; backend tests; route policy/OpenAPI/generated Swift; backend guide.
- **Focused verification:** `cd backend && .venv/bin/python -m pytest -q tests/unit/test_desktop_updates.py tests/unit/test_desktop_update_channels.py tests/unit/test_desktop_update_resolver.py tests/unit/test_qualified_beta_promotion.py tests/unit/test_desktop_previews.py tests/unit/test_route_policy_inventory.py`; manifest/schema tests; pinned OpenAPI runner if the public contract changes.
- **Deletion/simplification enabled:** dormant mode/fields/fixtures/lineage branch if S-26 did not already remove them; Omi repo/domain/collection defaults; separate backend release bridge inputs.
- **Stop:** S-26 canonical contract is absent; a real producer of dormant mode appears; S-27 namespace/URLs are unknown; generated Windows changes would be required.

### Cycle 3 — repair immediate-install admission through authoritative local activity

- **Intended behavioral RED:** Drive `UpdaterDelegate`'s production immediate-install callback through an injected `@MainActor` activity snapshot and controllable rescheduler. The install block must remain uncalled while any of these is true: ambient/meeting transcription, active voice turn/capture/provider response/playback, pending voice tool, realtime mint, Chat send, or streaming Chat message. Transition each owner to idle and prove the block runs exactly once. Prove a published idle app installs immediately; a development build remains install-on-quit; deallocation/cancellation never double-installs.
- **Why it fails now:** the production decision reads only normally-nil `VADGateService.lastSpeechAt`; current tests cover silence math rather than live owners.
- **Minimum GREEN:** introduce one small typed `UpdateInstallationAdmission`/snapshot policy at the updater boundary; adapt authoritative owners through read-only closures/snapshots; replace the exclusive VAD/timer coupling; retain the Sparkle block and resample until idle. Do not add an interruption timeout, restore Local VAD, or let individual call sites decide.
- **Protected behavior:** immediate published update; dev install-on-quit; main-window restoration; target-build verification/telemetry; ambient/PTT/Chat state ownership; no persistence or prompt/model changes.
- **Expected surfaces:** `UpdaterViewModel.swift`; one narrow production activity-policy source if needed; tests such as `UpdateInstallationAdmissionTests.swift`; existing relaunch tests; `PRODUCT.md`, Mac guide, and one unreleased changelog fragment because behavior changes.
- **Focused verification:** `desktop/macos/scripts/dev-feedback.py --once swift 'UpdateInstallationAdmissionTests|UpdaterViewModelTests|UpdateRelaunchWindowPolicyTests|VoiceTurn|RealtimeHubLifecycle|ChatProvider'`; run `scripts/pr-preflight --suggest` before a `fix:` PR body and declare the resulting failure class without guessing it.
- **Deletion/simplification enabled:** `VADGateService.lastSpeechAt` as update authority, obsolete `DeferredUpdateInstall` silence math/exclusive tests, duplicate activity observers.
- **Stop:** an activity owner lacks a safe main-actor snapshot; installing can race active state after the final sample; a timeout/fail-open interruption would be required; the change expands into VAD/PTT/Chat redesign.

### Cycle 4 — make universal libwebp provenance a production build input

- **Intended behavioral RED:** Invoke a production release-preparation script against the real vendored files and hermetic bad/missing fixtures. It must verify version/checksums, `x86_64 arm64`, exact `@rpath` install names, minimum OS not newer than the app target, dependency closure, destination names, and fallback invocation. Corrupt/wrong-arch/wrong-install-name inputs fail before app signing. The final nested copies must be signed with the supplied candidate identity and verified after signing.
- **Why it fails now:** the files and README exist, but no checked-in release consumer executes the contract; local `run.sh` uses Homebrew and must continue doing so.
- **Minimum GREEN:** add one narrow reusable release library-preparation script consumed by Codemagic; verify the retained cache first, perform the documented pinned two-arch source rebuild only as fallback, compare rebuilt outputs to the same structural contract, copy to the app, rewrite only proven required load paths, and sign nested dylibs before the outer bundle.
- **Protected behavior:** CWebP typed screen capture and consumers; local Homebrew/pkg-config loop; exact two retained binaries; macOS 14 app floor; reproducible fallback.
- **Expected surfaces:** `vendor/libwebp/README.md`; new/extended release-preparation script and behavioral shell test; `codemagic.yaml` consumer in Cycle 5; signed smoke library checks if absent.
- **Focused verification:** future `bash desktop/macos/tests/test-release-libwebp.sh`; `shasum -a 256`, `lipo -archs`, `otool -D/-L/-l`, and `codesign -dv` against vendor and packaged copies; existing screen-capture/WebP tests.
- **Deletion/simplification enabled:** README-only ownership and any provider-local duplicate compile/copy logic; no deletion of the cache or CWebP.
- **Stop:** version/source tarball provenance cannot be verified, either architecture is missing, the deployment target becomes incompatible, signing order is ambiguous, or the fallback needs an unpinned source/toolchain.

### Cycle 5 — add the owned Codemagic release and preview build workflows

- **Intended contract RED:** Parse and execute helper boundaries from the checked-in root `codemagic.yaml`. The release workflow must reject a noncanonical tag or source mismatch and, with injected command/provider fakes, prove ordered universal build/dSYM -> library preparation -> nested/outer signing -> archive -> notarization/staple -> Sparkle signing -> ZIP/DMG alignment -> Sentry symbol upload -> signed smoke with `--auth-storage-canary` -> immutable publication/evidence. The preview workflow must bind full SHA/preview identity, omit shared Sparkle, sign/notarize, smoke with `--preview`, and publish only preview artifacts. Missing identity/secret names fail before publication.
- **Why it fails now:** root `codemagic.yaml` is absent and consumers reference uninspectable Omi workflows.
- **Minimum GREEN:** add one auditable provider document with owned release and preview workflows using exact G2/G3 values; call repository scripts rather than duplicating logic; use product-owned Developer ID/notary/Sparkle/Sentry/provider secret names; publish S-28 exact filenames and `desktop-smoke-result.json`; keep candidate and preview entry conditions separate.
- **Protected behavior:** one build authority; exact source; hardened entitlements; universal app; dSYM UUID match; notarization/staple; Sparkle signature; signed smoke; preview isolation; no production publication from preview.
- **Expected surfaces:** root `codemagic.yaml`; packaging/signing/smoke/symbol/helper scripts and tests; `check-release-process-guards.py` plus its existing test lane and checks-manifest triggers; `FORK.md`; Mac release docs/guides; no GitHub workflow becomes a second builder.
- **Focused verification:** provider config validator available in the pinned Codemagic environment; helper behavioral tests; `bash desktop/macos/tests/test-signed-artifact-smoke.sh`; `bash desktop/macos/scripts/tests/test-publish-desktop-debug-symbols.sh`; `bash scripts/run-release-process-guards.sh`; `python3 .github/scripts/test_run_checks.py`.
- **Deletion/simplification enabled:** inherited missing-provider assumptions, Omi workflow/app IDs, team/feed/key/bucket/artifact defaults, duplicate YAML shell logic.
- **Stop:** any exact provider/Apple/Sparkle/Sentry identity is unknown; a secret would be committed; preview can reach production channel publication; provider validation cannot bind the checked-out SHA; signed smoke is skipped.

### Cycle 6 — re-own deliberate candidate intake and trusted M1 qualification

- **Intended behavioral RED:** Run the real planning/tag/intake/qualification orchestration against disposable Git/GitHub/provider fakes. Only manual dispatch for an admitted main SHA may produce one immutable tag; provider intake must match tag/SHA/workflow; one owned M1 Studio label holds a global non-canceling lease; qualification checks out the exact tag into run isolation, verifies the canonical S-26/S-27 backend contract, downloads exact S-28 artifacts, produces immutable evidence, and never promotes inside the qualification run. Wrong repo/bot/runner/backend identity/artifact/digest/evidence fails closed.
- **Why it fails now:** bot, runner labels, repo, provider workflow ID, artifact names, and live backend host/service are Omi/separate-desktop-backend values; docs incorrectly say candidates are automatic.
- **Minimum GREEN:** adapt workflows/scripts/fixtures to G2/G3 identities and S-26 health/compatibility; preserve existing reservation, source identity, readiness, lease/cache/capacity/self-clean/watchdog, evidence, retry/recovery, and post-success promotion separation. Correct both release guides to manual-only truth.
- **Protected behavior:** deliberate candidate control; normal PR merge for changelog; exact source/tag; no duplicate candidate; M1-only qualification; immutable evidence; no ordinary CI substitute; no production-app cleanup.
- **Expected surfaces:** auto-release/qualify/promote-beta/retry/recover workflows; candidate/intake/observer/evidence/readiness/qualification scripts and tests; qualification environment, release docs, Mac guide, checks manifest.
- **Focused verification:** candidate planning/source/tag/intake/observer Python tests; `bash desktop/macos/tests/test-pre-tag-readiness-contract.sh`; `python3 desktop/macos/tests/test_pre_tag_readiness_behavior.py`; `bash desktop/macos/tests/test-qualify-desktop-beta-contract.sh`; `python3 .github/scripts/test_desktop_release_flow_contract.py`; runner/cache/lease/self-clean tests from the checks manifest.
- **Deletion/simplification enabled:** Omi Bot/app/runner/cache/lease/artifact/service identities; false automatic-release documentation; separate desktop-backend compatibility files.
- **Stop:** M1 owner/labels are unavailable; canonical live contract is undefined; the workflow would mutate a tag before readiness; retry can promote; cleanup can target any production-family app.

### Cycle 7 — re-own Beta/Stable publication, update policy, recovery, rollback, and break glass

- **Intended behavioral RED:** Through the real backend route/database functions with strict Firestore transactions and disposable workflow/API fakes, prove: reservation precedes candidate publication; stale/paused admission cannot promote; immutable T2 evidence admits only Beta; Stable promotes the exact current qualified Beta with CAS; idempotent lost-response retry is safe; recovery/rollback targets retained manifests; emergency rollout requires explicit reason/evidence and stays Beta-only; appcast/download/cache repair resolve owned URLs; update-policy mutation/read is authenticated/audited, and read failure returns inactive/fallback. Wrong project/namespace/backend/repo/digest/generation/secret fails closed.
- **Why it fails now:** workflows and validators hard-code Omi URL/bucket/repo/bot/project/service/region; Stable bridges a second backend; no checked-in owned operator path for `desktop_update_policy/current` was found.
- **Minimum GREEN:** consume S-27 identities/WIF/secret resources; remove the duplicate backend bridge; adapt existing backend state machine and workflows, not replace it; establish one protected audited operator path for the existing policy document (prefer the canonical backend validation/CAS owner over direct console edits); preserve public GET/fail-open client behavior; keep break glass separate and documented.
- **Protected behavior:** all IR-894 transitions/evidence; Stable manual-only; Beta post-qualification; appcast/download; policy severities/targeting/dismissal/fail-open; release repair; rollback/break glass audit; fallback telemetry.
- **Expected surfaces:** backend update router/database/utils/runtime config/tests; promote/recover/rollback/breakglass/admission/stable/doctor workflows and scripts; route policy/OpenAPI if operator method changes; release docs; checks-manifest existing lanes.
- **Focused verification:** focused backend tests from Cycle 2 plus Firestore contention `bash backend/testing/desktop_beta_admission/run.sh`; stable verifier/promotion policy tests; release doctor; release-flow and backend production/deploy boundary checks; hermetic workflow API fakes.
- **Deletion/simplification enabled:** Omi API/GCS/repo/project/bot/Cloud Run bridge; direct unvalidated policy console ownership; redundant backend release vector.
- **Stop:** BL-002 inventory is being treated as mutation authority; any transition lacks CAS/evidence; policy operator auth is weaker than existing admin controls; Stable can accept a rebuild/preview/emergency artifact; live mutation lacks explicit authorization.

### Cycle 8 — re-own signed preview create, replace, serve, and delist

- **Intended behavioral RED:** Use a disposable canonical `preview/<slug>` remote, provider fake, production preview registry, strict Firestore fake, and HTTP app to prove full-SHA resolution, protected approval, deterministic S-28 preview identity, production-compatible vs explicit-preview-backend validation, signed/notarized immutable DMG URL/digest, idempotent immutable manifest, generation-fenced pointer replacement, current/immutable landing pages, and compare-and-delete delisting. Prove no preview changes Beta/Stable or enables Sparkle/local automation.
- **Why it fails now:** dispatcher, provider IDs, bundle/scheme validation, bucket/path, backend URLs, repository, landing URLs, and public host are Omi-owned; provider definition is missing.
- **Minimum GREEN:** consume Cycles 1/5 plus S-27/S-28 exact preview values; adapt dispatcher, backend registry, runtime secret, GCS path, landing construction, and tests; keep immutable objects/evidence after delisting; document cleanup/retention and operator owner.
- **Protected behavior:** manual-only preview approval; exact source; co-installability; separate backend mode; signed/notarized DMG; immutable/current URLs; CAS replacement; pointer-only delist; strict channel isolation.
- **Expected surfaces:** preview workflow; Codemagic preview definition; backend preview db/router/storage/runtime env; AppBuild/smoke preview classification; tests, route policy, docs.
- **Focused verification:** `cd backend && .venv/bin/python -m pytest -q tests/unit/test_desktop_previews.py tests/unit/test_desktop_updates.py tests/unit/test_desktop_release_scripts.py`; external preview Swift tests; signed-smoke shell tests; release-process guard; disposable dispatcher tests.
- **Deletion/simplification enabled:** Omi preview IDs/schemes/bucket/domain/repo/provider/secret assumptions; any shared-channel shortcut.
- **Stop:** preview identity is not an S-28 output; exact SHA cannot be proven; public object permissions/retention are unknown; delist would delete immutable evidence; production credentials are reachable from an unapproved preview.

### Cycle 9 — publish and consume owned public/legal destinations

- **Intended behavioral RED:** Through the production destination resolver/Settings actions/backend landing output plus rendered-content fixtures and read-only HTTPS probes, prove owned product, stable download, preview, Terms, real Privacy Policy, support/contact, and exact GitHub release URLs. Bind the rendered pages to the versioned, owner-approved S-29 publication packet and record that revision for S-30. **Privacy & Data** must still navigate locally; Terms must only open the document; exact version notes must encode the tag; missing/unowned/redirect-to-Omi destinations fail release acceptance. Static source searches are only tripwires.
- **Why it fails now:** current consumers point to Omi/BasedHardware; no owned static site/destinations are supplied in this checkout.
- **Minimum GREEN:** after the versioned S-29 packet is approved, publish it through the externally owned minimal site, place exact owned URLs in the smallest release/product destination authority, and migrate in-tree callers, workflow summaries, backend landing/download defaults, docs, and tests. Record the content revision and rendered/link evidence as S-30's input; S-30 owns the later final literal truth reconciliation and may republish through this established path. Add an external legal Privacy link only at the requirements-authorized discoverable surface without replacing local **Privacy & Data**. Do not create a web tree here.
- **Protected behavior:** About rows and browser behavior; exact release-note tag; local toast; local Privacy navigation; no consent ledger; preview current/immutable distinction; support remains bounded to owned contact/report surfaces.
- **Expected surfaces:** post-S-28 product-link/AppBuild authority; Settings controls/tests; backend update/preview landing/default URL configuration/tests; workflows/docs/FORK/README only where currently a retained Mac product destination; external site evidence, not source in this repo.
- **Focused verification:** Swift destination/Settings tests; backend landing/appcast/download/update-policy tests; `curl -fsSIL`/`curl -fsS` read-only probes against exact pages; GitHub release URL fixture tests; residue search §13.
- **Deletion/simplification enabled:** Omi/BasedHardware release/product/legal/support/download/preview destinations in S-29-owned surfaces; no deletion of historical changelogs or S-30-owned unrelated copy.
- **Stop:** page ownership, the versioned S-29 publication packet, company/legal text, processor disclosures, HTTPS/DNS, redirect destination, support owner, or GitHub repo is unapproved; completing the work would require inventing legal claims or absorbing S-30's final copy/truth reconciliation.

### Cycle 10 — integrated release-system acceptance, docs, residue, and closure evidence

- **Intended behavioral/operational RED:** On one exact committed SHA, the repository/local layer passes §14 and the named bundle passes §15.1. Under separately authorized owned infrastructure, one clean signed candidate then proves provider build, Developer ID/notarization/Sparkle, M1 evidence, clean DMG self-install, idle and busy update behavior, Beta/Stable promotion, recovery/rollback/break glass drill, preview publish/replace/delist, public links, and immutable evidence. Every result is bound to the same identities/digests; no Omi production app or state is touched.
- **Why it fails before implementation:** predecessors and external identities are absent, provider definition is absent, current release graph is Omi-owned, and BL-001/BL-002 remain open.
- **Minimum GREEN:** fix only integration defects revealed by real paths; update `FORK.md`, component guides, release/qualification/health docs, `PRODUCT.md` where behavior changed, and a valid unreleased desktop changelog fragment. Run `make preflight`, PR-body preflight, component suites, residue classification, and record exact commands/evidence. Measure build/smoke/qualification timings before any acceleration change.
- **Protected behavior:** complete §9 plus clean install/upgrade/reset/sign-out/account-switch/reinstall ownership from S-28; no product feature redesign; billing disabled.
- **Expected surfaces:** only integration fixes within prior cycle owners; docs/check-manifest updates coupled to real changes. No standalone “closeout” checker or integrated closeout section is added to this plan.
- **Focused verification:** all §14 commands; §15 acceptance; `git diff --check`; final residue searches; `scripts/pr-preflight --pr-body-file /tmp/pr-body.md`; independent agent review if later requested/available under repository policy.
- **Deletion/simplification enabled:** final S-29-owned Omi release residue, temporary diagnostic code, dead provider aliases, stale automatic-release docs. Tooling acceleration only after recorded repeated bottleneck.
- **Stop:** any mandatory gate/input/evidence is missing; a provider path was not really exercised; live state is unknown; rollback is unproven; a public/legal URL is not owned; BL-001 is being declared closed; mutation lacks explicit authorization.

## 12. Cross-slice ownership and handoffs

| Slice/owner | What S-29 consumes or hands off | Boundary |
|---|---|---|
| **S-04** | Consumes absent-source control deletion and protected vendor dylibs; adds the fresh owned Codemagic document and extends existing release guard only. | Do not restore public-build/web/mobile/plugin/SDK controls or touch Windows. |
| **S-09** | Consumes owned Sentry/PostHog/LangSmith configuration and dSYM destination. | Repoint release identity/symbol upload only; do not redesign privacy/telemetry controls. |
| **S-21** | Consumes About/Settings graph, Help Center absence, and local **Privacy & Data**. | Do not recreate Help Center or turn local settings into legal policy. |
| **S-23/S-24** | Consumes cloud-announcement deletion and protected update/preview bucket. | No cloud announcement replacement; no product data in release storage. |
| **S-25** | Consumes one-backend topology handoff and BL-002 operational separation. | Repository absence never authorizes deleting live release resources. |
| **S-26** | Consumes one canonical Python backend and app-only compatibility contract. | S-29 adapts release callers only; no service/entrypoint compatibility. |
| **S-27** | Consumes exact cloud foundation, WIF/secrets, canonical URLs, Firestore, update bucket, and deployment/rollback identity. | S-29 owns release state/use, not cloud foundation provisioning. |
| **S-28** | Consumes exact bundle/update/preview identity and runtime self-install. | S-29 never invents namespaces or Omi takeover; it builds/exercises S-28's artifact. |
| **S-30** | Receives owned URLs, release names/identities, hosting boundaries, operator docs, and remaining classified visible Omi hits. | S-30 owns the global name/artwork/copy/privacy/legal truth sweep; S-29 changes only release-functional destinations/identity. |
| **S-31** | Receives repository suites, named-bundle evidence, signed candidate/evidence chain, live release drills, open BL-001/BL-002 facts, and unresolved credentials. | S-29 cannot mark final all-waves/provider/billing release green. |
| **External product/legal/site owner** | Supplies/publishes approved product, Terms, Privacy, support pages and DNS. | No web estate is recreated in this repository. |
| **Release/cloud/Apple administrators** | Supply exact identifiers, configure secrets/runners/provider, authorize live operations, retain rollback evidence. | Repository code never contains or creates credentials by itself. |

## 13. Repository residue-search strategy

Run after G1, after each relevant GREEN, and at final closure. Exclude Windows, `.git`, build products, planning documents, historical changelogs, and fixtures deliberately testing rejection; classify every remaining hit rather than demanding blind zero.

```bash
# Missing/duplicate backend release mode and separate-backend authority
rg -n 'backend_required|desktop_backend_(source_sha|oci_index_digest|platform_digest)|desktop-backend' \
  .github backend desktop/macos \
  --glob '!desktop/windows/**' --glob '!**/.build/**' --glob '!**/CHANGELOG*'

# Inherited release/provider identities and destinations
rg -n 'BasedHardware/omi|api\.omi\.me|macos\.omi\.me|omi_macos_updates|com\.omi\.|omi-desktop|OMI_BOT|Omi Bot|9536L8KLMP|omi-desktop-swift-(release|preview)' \
  .github backend desktop/macos README.md FORK.md AGENTS.md \
  --glob '!desktop/windows/**' --glob '!**/.build/**' --glob '!**/CHANGELOG*'

# Release credential/config names: retained hits need one documented owned provider
rg -n 'CODEMAGIC_|SUPublicEDKey|SUFeedURL|Developer ID Application|notary|notariz|stapl|SPARKLE|SENTRY_(ORG|PROJECT|AUTH_TOKEN)|GCS_DESKTOP_UPDATES_BUCKET|DESKTOP_PREVIEW_PUBLISH_KEY|RELEASE_SECRET|ADMIN_KEY' \
  codemagic.yaml .github backend desktop/macos \
  --glob '!desktop/windows/**' --glob '!**/.build/**'

# Candidate/qualification trigger truth
rg -n 'automatic candidate|every.*merge|push:|schedule:|workflow_dispatch:|omi-qual|desktop-beta-qualification|cancel-in-progress' \
  .github/workflows/desktop_* desktop/macos/AGENTS.md desktop/macos/docs

# Public/legal/support destinations and local-vs-hosted privacy boundary
rg -ni 'Help Center|Privacy Policy|Privacy & Data|Terms of Service|Visit Website|What.?s New|support|releases/download|preview/' \
  desktop/macos/Desktop/Sources backend/routers/updates.py backend/database/desktop_update_policy.py \
  .github/workflows/desktop_* README.md FORK.md

# Cloud announcements must remain gone; local toast/release notes are retained
rg -n 'announcements|Announcement|WhatsNewToast|changelogURLString' backend desktop/macos \
  --glob '!desktop/windows/**' --glob '!**/.build/**'

# Update activity gate and rejected VAD coupling
rg -n 'lastSpeechAt|DeferredUpdateInstall|UpdateInstallationAdmission|isTranscribing|activeTurnID|lifecycleSnapshot|isSending|isStreaming' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests

# Preview/channel separation and identity
rg -n 'desktop_preview_|desktop_update_channels|preview/<slug>|externalPreview|allowsSparkleUpdates|allowsLocalAutomation|identity=beta' \
  .github backend desktop/macos --glob '!desktop/windows/**' --glob '!**/.build/**'
```

Binary provenance is checked separately because `rg` is not evidence:

```bash
shasum -a 256 desktop/macos/vendor/libwebp/libwebp.7.dylib \
  desktop/macos/vendor/libwebp/libsharpyuv.0.dylib
lipo -archs desktop/macos/vendor/libwebp/libwebp.7.dylib
lipo -archs desktop/macos/vendor/libwebp/libsharpyuv.0.dylib
otool -D desktop/macos/vendor/libwebp/libwebp.7.dylib
otool -D desktop/macos/vendor/libwebp/libsharpyuv.0.dylib
otool -l desktop/macos/vendor/libwebp/libwebp.7.dylib
otool -l desktop/macos/vendor/libwebp/libsharpyuv.0.dylib
```

Expected retained hits include generic “Omi” outside S-29-owned release-functional surfaces pending S-30, historical changelogs, test fixtures containing deliberately rejected values, S-28's migration evidence where historically necessary, and generic `ADMIN_KEY` use with another retained owner. Each exception needs path, owner, and reason. No executable/configured Omi release default is an acceptable exception.

## 14. Focused and component-level verification commands

All commands are future implementation requirements and must be rechecked after G1.

### 14.1 Requirements and Git hygiene

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py
test -x "$(git rev-parse --git-path hooks)/pre-commit" && echo OK
scripts/pr-preflight --suggest
git diff --check
git status --short
```

Before opening any later PR:

```bash
make preflight
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
```

### 14.2 Focused Mac behavior

```bash
desktop/macos/scripts/dev-feedback.py --once swift 'AppBuildBetaIdentityTests|ExternalPreviewBuildTests|UpdaterViewModelTests|UpdateInstallationAdmissionTests|UpdateRelaunchWindowPolicyTests|UpdateFailureDiagnosticsTests|DesktopUpdatePolicyManagerTests|AppInstallerTests|SettingsDestinationContractTests'
bash desktop/macos/tests/test-app-config.sh
bash desktop/macos/tests/test-signed-artifact-smoke.sh
bash desktop/macos/scripts/tests/test-publish-desktop-debug-symbols.sh
```

Use the post-S-28 test names if identity files are renamed. The new update-admission test must invoke production policy/delegate behavior with injected snapshots; a source scrape is not coverage.

### 14.3 Focused backend release authority

```bash
cd backend
.venv/bin/python -m pytest -q \
  tests/unit/test_desktop_updates.py \
  tests/unit/test_desktop_update_channels.py \
  tests/unit/test_desktop_update_resolver.py \
  tests/unit/test_desktop_previews.py \
  tests/unit/test_qualified_beta_promotion.py \
  tests/unit/test_desktop_release_scripts.py \
  tests/unit/test_route_policy_inventory.py
cd ..
```

If route/DTO output changes:

```bash
cd backend
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
scripts/openapi_runner.sh scripts/route_policy_inventory.py \
  --manifest route_policy_manifest.yaml --check --report-only
cd ..
```

These are the current post-S-26 contract arguments. Refresh them from `backend/AGENTS.md` and the owning scripts at execution time if S-26 changes the runner contract; never invoke `scripts/openapi_runner.sh` without a target and do not invent or hand-edit generated clients.

### 14.4 Release/provider/workflow contracts

```bash
python3 .github/scripts/test_desktop_release_manifest.py
python3 .github/scripts/test_desktop_release_manifest_schema.py
python3 .github/scripts/test_desktop_release_doctor.py
python3 .github/scripts/test_plan_desktop_release.py
python3 .github/scripts/test_desktop_release_source_identity.py
python3 .github/scripts/test_publish_desktop_candidate_tag.py
python3 .github/scripts/test_check_codemagic_tag_intake.py
python3 .github/scripts/test_observe_codemagic_tag_build.py
python3 .github/scripts/test_check_desktop_auto_beta_candidate.py
python3 .github/scripts/test_stable_promotion_verifiers.py
python3 .github/scripts/test_desktop_release_flow_contract.py
bash scripts/run-release-process-guards.sh
bash desktop/macos/tests/test-pre-tag-readiness-contract.sh
python3 desktop/macos/tests/test_pre_tag_readiness_behavior.py
bash desktop/macos/tests/test-qualify-desktop-beta-contract.sh
python3 desktop/macos/tests/test_qualification_cache_reclaim.py
python3 desktop/macos/tests/test_qualification_runner_self_clean.py
bash backend/testing/desktop_beta_admission/run.sh
```

Also run the exact provider configuration validator documented for the pinned Codemagic version. Its result is a static/configuration check; it does not prove signing/notarization or a published artifact.

### 14.5 Deploy/runtime contracts

```bash
python3 .github/scripts/check_release_rings.py
python3 .github/scripts/check-gcp-backend-production-boundary.py
python3 .github/scripts/test_check_gcp_backend_production_boundary.py
python3 .github/scripts/check_backend_deploy_source_admission.py
python3 .github/scripts/test_check_backend_deploy_source_admission.py
python3 .github/scripts/test_run_checks.py
make runtime-image-source-closure
```

If S-29 changes `backend/deploy/runtime_env.yaml` or a deploy workflow, also run:

```bash
bash backend/scripts/pre-deploy-check.sh
```

### 14.6 Official component suites and local harness

```bash
BACKEND_PYTEST_WORKERS=1 bash backend/test.sh
bash desktop/macos/test.sh
PROVIDER_MODE=offline make dev-up
make dev-status
make dev-down
```

The local/offline harness must exercise the post-S-26 canonical backend without production credentials. Full suites are required before commit/PR; focused checks are the edit loop, not a replacement.

## 15. Real named-bundle, backend, infrastructure, or release acceptance

### 15.1 Repository/local named-bundle acceptance

Use only the named non-production bundle requested for this slice:

```bash
cd <repository-root>
PROVIDER_MODE=offline make dev-up
OMI_FORCE_FULL_BUNDLE=1 make desktop-run-local DESKTOP_APP_NAME=omi-wave5-s29 DESKTOP_USER=alice
```

Keep that foreground launcher running in shell 1. After it reports the resolved loopback/emulator profile and bundle readiness, run the harness from shell 2:

```bash
cd <repository-root>/desktop/macos
./scripts/omi-ctl health
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-wave5-s29 --port <reported-port> --keep-stack
```

Do not use bare `OMI_APP_NAME=... ./run.sh` for this local acceptance: named bundles default to remote development services unless an explicit local profile/URL overrides them, and those services currently use production Firebase identities. Read the actual post-S-28 bundle identifier, profile root, and URLs from the local-profile launcher rather than hard-coding the planning baseline namespace.

If S-28 renames the environment variable or harness command, use its committed successor while retaining the literal bundle name `omi-wave5-s29`. Record the derived bundle ID, URL scheme, app path, profile root, backend URL, source SHA, and whether the bundle is signed ad hoc. Prove:

1. it launches without touching either production Omi bundle/application;
2. it cannot start the shared Sparkle updater and does not read production release defaults;
3. About/update controls render their development-safe state and owned destinations;
4. canonical offline/local backend health works;
5. ambient transcription, PTT/tool/playback, and Chat streaming independently hold the update-admission policy busy; after idle, the injected/local acceptance installer canary fires once without actually replacing an app;
6. update policy `none`, `banner`, `required`, dismiss, and backend-failure clear/fallback work through the real local API/UI path;
7. restart, sign-out, account switch, reset, and reinstall remain in S-28's named profile and never discover/import an Omi namespace;
8. ResourceMonitor and ordinary termination/relaunch siblings remain green.

### 15.2 Read-only owned-infrastructure acceptance

Using a verified operator identity and no mutations, capture sanitized evidence of:

- exact Codemagic app/workflow IDs and last build source identity;
- Apple certificate Team ID/common name/expiration and notarization issuer identity (never private material);
- GitHub App installation, environments/reviewers, runner labels/status/capacity, and release repository;
- S-27 canonical dev/prod backend URLs, region/service/revision digest, Firestore database, update/preview bucket generation/public-origin policy, WIF identities, and relevant Secret Manager resource names/versions (not values);
- current Beta/Stable/update-policy/preview operational state and whether it is inherited, empty, or product-owned;
- public DNS/TLS/redirect/cache ownership for product/download/feed/preview/Terms/Privacy/support pages.

An unknown classification keeps operational closure open. Do not infer that an empty repository implies no Omi provider/cloud resource.

### 15.3 Separately authorized signed-candidate acceptance

Only after explicit authorization and G3 completion, on one exact main SHA:

1. manually dispatch candidate planning; prove no push/schedule created it;
2. verify the immutable tag and source-identity evidence before provider intake;
3. observe the owned Codemagic release workflow accept that exact tag and no other ref;
4. verify universal executable/helpers/libwebp libraries; dSYM UUIDs; S-28 stable/Beta identifiers; entitlements/hardened runtime; Developer ID chain; notarization/staple; Gatekeeper; DMG/ZIP contents; Sparkle EdDSA signature/public key/feed; artifact hashes; Sentry symbol upload; and final `desktop-smoke-result.json` including `--auth-storage-canary`;
5. on the dedicated owned M1 Studio, qualify the exact downloaded artifacts and live S-27 canonical backend contract; retain immutable evidence tied to run ID/attempt/tag/SHA/digests;
6. install the DMG from a clean non-Omi state and prove S-28 self-install into `/Applications`, no downgrade, quarantine clearing, atomic replacement, delayed relaunch, two-attempt protection, and manual fail-open path. Never target `/Applications/Omi.app` or `/Applications/Omi Beta.app`;
7. promote to Beta through the backend admission path; verify pointer, appcast, manual download, two-minute client propagation, exact release notes/toast, and authenticated product path;
8. from an older owned build, prove automatic download waits through live ambient, PTT/provider/playback/tool, and Chat streaming activity, then installs/relaunches once idle with correct window behavior and target-build telemetry;
9. promote the same qualified artifact to Stable manually; verify CAS, appcast, stable repair, ten-minute cadence, and no rebuild;
10. perform authorized recovery/idempotent retry, qualified rollback, and a controlled Beta-only break-glass drill with audit evidence; prove Stable cannot use the emergency lane;
11. publish a canonical `preview/<slug>` exact SHA, verify co-installable identity/no Sparkle/no automation, immutable/current landing pages and explicit backend mode, replace its pointer with a later SHA, then delist the pointer while immutable evidence remains;
12. open product, exact release, Terms, real Privacy Policy, support/contact, stable download, and preview links; verify owned HTTPS endpoints and no redirect to Omi.

No step claims success from workflow YAML, compile, a mock, or an artifact list alone. Capture command/output, provider run URLs/IDs, source SHA, artifact and manifest digests, certificate/public-key fingerprints, notarization ID/status, M1 evidence asset/digest, pointer generations, and rollback result without secrets or user data.

## 16. Repository closure versus separately authorized operational closure

### Layer 1 — repository closure

S-29 repository closure requires Cycles 0–10 implemented, focused and official suites green, real `omi-wave5-s29` acceptance, checked-in owned provider definition, current docs, classified residue, clean diff, and no unresolved repository-owned placeholder/default. It can close while live release operations remain unexecuted only if the plan/PR says so explicitly; in that case S-29's **operational** close is still open and S-31 cannot accept it as released.

### Layer 2 — read-only inventory closure

A verified operator must produce the sanitized inventory in §15.2 and resolve BL-002 classifications relevant to release/update/preview/public hosting. Read-only evidence must state operator identity, project/provider/account, timestamp, commands/API, and exact resources. It authorizes no change.

### Layer 3 — mutation/release closure

Separate explicit authorization is required for:

- creating/configuring Codemagic apps/workflows/secrets;
- installing/rotating Apple certificates, notarization credentials, Sparkle keys, GitHub Apps/tokens, Sentry tokens, runner configuration, WIF/IAM, Secret Manager bindings, DNS/TLS, bucket permissions, or site deployments;
- pushing a candidate tag/release asset, publishing a signed artifact, writing release/policy/preview documents, mutating a pointer/channel, promotion, rollback, break glass, cache repair, preview publish/replace/delist, or public site release;
- deleting or changing any inherited resource discovered by BL-002.

Operational order is dependency-safe: verify backups/retention and rollback -> configure non-serving identities/secrets -> build/verify immutable artifact -> qualify -> register immutable state -> mutate Beta -> observe -> mutate Stable -> verify -> only then retire a proven unused inherited release resource under separate authorization. No plan or code merge supplies that authorization.

BL-001 remains open until S-31 composes final provider/continuity evidence on the final all-waves SHA. Dodo test/live activation remains outside this slice. Do not describe either backlog item, Waves 3–4, billing, or final release as closed from S-29 evidence alone.

## 17. Risks, ambiguities, and explicit stop points

| Risk/ambiguity | Required response |
|---|---|
| S-26/S-27/S-28 plans exist but code is not integrated | Stop all mutation cycles; planning files are not implementation evidence. |
| Manual workflow vs automatic-release docs | Follow IR-893 and current manual workflow only after rebase confirms it; correct docs. A restored automatic trigger requires decision resolution. |
| `backend_required` remains after S-26 | Return the dormant-mode deletion to S-26 unless only a clearly S-29-owned release caller/fixture remains; never keep a dual schema. |
| Separate `desktop-backend` host/service remains in qualification | Stop until S-26/S-27 expose the one canonical backend health/compatibility contract. Do not hard-code a transitional host. |
| Exact bundle, file, feed, team, repo, project, bucket, domain, workflow, runner, or key identity is unknown | Block the affected cycle; no Omi default or shipping placeholder. |
| Sparkle key rotation is required for already-built owned clients | Stop for an explicit cutover/rollback design; never replace the public key and feed signature independently. |
| Certificate/notarization/private-key handling would leak into source/log/artifact | Stop and redesign secret placement/evidence redaction before any build. |
| Provider YAML validates but signed path has not run | Repository/config only; do not claim release closure. |
| M1 runner is offline, capacity-constrained, or cleanup ownership is ambiguous | Qualification remains blocked; ordinary CI/Codemagic is not an allowed substitute. |
| Update gate cannot read an owner without coupling to its mutable internals | Add the narrow read-only snapshot at the authoritative owner; do not add scattered observers/fallback booleans or interrupt anyway. |
| Activity never becomes idle | Leave Sparkle scheduled for quit and surface bounded diagnostics; do not install through activity or invent a timeout without a new decision. |
| Firestore/GCS state looks like Omi or ownership is unknown | Do not read as product authority, migrate, overwrite, promote, or delete. Start clean under S-27/S-28 only after authorization. |
| Preview deletion would remove immutable evidence/object | Stop; delisting removes only the mutable pointer. Retention/deletion of immutable evidence needs a separate policy. |
| Public page exists but redirects to Omi or legal content is provisional/false | Keep Cycle 9/operational closure red. Do not ship the link or invent copy. |
| S-29 change becomes a global visual/text rebrand | Limit functional release identity/destination work and hand the full sweep to S-30. |
| A route/schema change rewrites tests without external contract basis | Cite Apple/Sparkle/Codemagic/GitHub/GCP primary docs or measured artifact behavior in the PR; otherwise the rewritten guard is suspect. |
| New guard lacks a real failure or existing CI lane | Do not land it. Prefer the existing release-process/check-manifest primitive; cite snapshot PR #14 for the absent-provider regression. |
| Windows or historical changelogs appear in residue | Exclude and classify; do not inspect/edit them for S-29 cleanup. |
| Any step enables billing or requires Dodo/Stripe state | Stop; `BILLING_MODE=disabled` is invariant through Wave 6. |
| Live mutation is proposed from repository or read-only authority | Stop and obtain explicit user authorization for the exact operation/targets. |

## 18. Final completion checklist

- [ ] Execution `HEAD` contains integrated, verified S-26, S-27, and S-28; inventories were refreshed after rebase.
- [ ] All primary decisions IR-010, IR-243–253, IR-804, IR-821, IR-892–897, IR-927–929, and IR-939 were re-read and mapped to tests/evidence.
- [ ] S-26's canonical backend/app-only contract is consumed; no `backend_required` or separate desktop-backend release authority remains.
- [ ] S-27 cloud identities and S-28 app identities are consumed from committed authorities; no identifier was guessed.
- [ ] Manual Check Now/recovery, forced auto updates, 10m/2m cadence, local Stable/Beta, exact release notes/toast, and dev/preview isolation are behaviorally green.
- [ ] One production update-admission seam covers ambient transcription, PTT/realtime capture/provider/playback/tools/mint, and Chat/model/tool streaming; install occurs exactly once after idle.
- [ ] `VADGateService.lastSpeechAt` is no longer the sole update authority, and Local VAD behavior was not redesigned.
- [ ] Root `codemagic.yaml` owns exact-source universal release and preview workflows; no second builder exists.
- [ ] Developer ID, hardened runtime/entitlements, nested signing, notarization/stapling, Sparkle signing, ZIP/DMG, dSYM/Sentry, signed smoke, and auth-storage canary have repository contracts and real authorized evidence.
- [ ] Vendored libwebp/libsharpyuv checksums, architectures, install names, compatible min OS, fallback, packaged paths, and final candidate signing are proven.
- [ ] Candidate creation is manual-only; provider intake, trusted owned M1 qualification, hygiene/capacity, immutable evidence, retry/recovery, and promotion separation remain exact.
- [ ] Backend manifests/pointers/admission/appcast/download/policy/recovery/rollback/break glass retain CAS, evidence, idempotency, auth, and fallback behavior under owned state.
- [ ] Signed previews use separate identity/state, exact SHA, approval, backend mode, immutable/current pages, CAS replace, and pointer-only delist; they cannot promote.
- [ ] Runtime DMG self-install/no downgrade/atomic replace/quarantine/relaunch/two-attempt fail-open is exercised with the signed S-28 artifact, not an Omi app.
- [ ] Help Center and cloud announcements remain absent; local **Privacy & Data**, release notes, and toast remain.
- [ ] Product, release, download, preview, Terms, real Privacy Policy, and support/contact URLs are HTTPS, owned, approved, and do not redirect to Omi; no consent ledger or web monorepo was added.
- [ ] S-30 receives a classified list of remaining visible copy/identity/privacy/legal hits; S-29 did not absorb the global sweep.
- [ ] Windows and historical changelogs were untouched.
- [ ] `BILLING_MODE=disabled` remained true; no Dodo/Stripe resource or transaction was created.
- [ ] Focused backend/Swift/workflow/provider-helper tests, official `backend/test.sh` and `desktop/macos/test.sh`, offline harness, runtime/deploy contracts, `make preflight`, and PR-body preflight passed with commands/results recorded.
- [ ] Real `omi-wave5-s29` acceptance passed without touching production Omi/Omi Beta bundles or namespaces.
- [ ] Repository closure, read-only inventory, and separately authorized live mutation/release evidence are reported independently; unknown live state remains open.
- [ ] BL-001 and BL-002 remain accurately open unless their own later acceptance requirements are genuinely satisfied; S-31 final closeout is not claimed.
- [ ] `git diff --check` passes, `git status --short` contains only intended implementation files, every deferred-work marker cites a tracking issue, and docs/changelog moved with changed behavior.
- [ ] No commit, push, PR, merge, deployment, release, provider mutation, production-app operation, or external-state change is implied by this planning document.
