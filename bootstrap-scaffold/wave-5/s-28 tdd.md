# S-28 TDD plan — establish clean Mac storage namespaces and installation identity

## 1. Slice identity

| Field | Value |
|---|---|
| Wave | 5 |
| Slice | S-28 |
| Name | Establish clean Mac storage namespaces and installation identity |
| Type | Local identity migration without inherited-data takeover |
| Primary requirement decisions | IR-929 and IR-931 |
| Required baseline | `22ad2f16ff8d63fd761c918b92f4c5d961814624` |
| Target branch | `origin/main` |
| Future development acceptance bundle | `omi-wave5-s28` |
| Repository output | This planning document only |

This slice owns the Mac's technical installation and persistence identity: bundle-family classification, Application Support, Cache, Log, temporary/runtime, database, UserDefaults, Keychain, login-item, updater, TCC, app-group, and local test-bundle namespaces. It preserves the retained local store behavior and owner fences delivered by S-10 through S-15. It does **not** inherit the right to inspect or migrate an Omi installation merely because this repository was forked from Omi.

Visible final product naming, artwork, general copy, privacy/legal claims, and broad rebrand residue belong to S-30. Signed artifact construction, Developer ID/notarization, Sparkle feeds and keys, preview publication, release infrastructure, and public destinations belong to S-29.

## 2. Planning status and pinned baseline

This is an implementation-ready TDD plan, not an implementation or closeout record. It was prepared on 2026-08-26 from the exact required baseline.

Current planning evidence:

- `git fetch origin` completed before analysis.
- `git merge-base --is-ancestor 22ad2f16ff8d63fd761c918b92f4c5d961814624 HEAD` succeeded.
- `git rev-parse HEAD` and `git rev-parse origin/main` both resolved to `22ad2f16ff8d63fd761c918b92f4c5d961814624`.
- `git status --short --branch` showed only `## plan-waves-5-6-slices` before this document was created.
- `python3 bootstrap-scaffold/validate-requirements-ledger.py` passed before drafting with `714 indexed rows, 714 detailed sections, all reviewed`.
- The combined Waves 3–4 closeout explicitly permits S-28 to begin from the complete repair tree while keeping final all-waves live qualification open under BL-001. That deferral is not evidence that provider, physical-device, hosted-CI, release, or operational lanes passed.

No product code, tests, configuration, installed app, UserDefaults domain, Keychain item, login item, TCC record, local database, release system, or external service is changed by this plan. Future commands in this document are required execution commands; they are not claims of results already obtained.

At implementation time, pin the new execution SHA in the PR evidence. If `origin/main` has advanced, consume it in the current worktree without switching or renaming the branch, repeat the inventories in Sections 6, 7, and 13, and update this plan if the ownership or behavior has materially changed.

## 3. Outcome

S-28 is complete when a Mac build of this product has one explicit, internally consistent technical identity and all retained local state starts inside that identity. Stable, Beta, canonical development, named development, and preview builds must be classified deliberately and must never fall into an Omi storage or service namespace.

The completed behavior is:

1. A first build under the new identity creates only its own bundle-scoped defaults, services, directories, databases, logs, locks, tokens, and runtime state.
2. A later build under that same owned identity upgrades in place and preserves its own retained local stores, owner boundaries, crash recovery, auth continuity, installation ID, and user choices.
3. Reset and sign-out retain the narrowed S-17 semantics. They clear only their approved state, stop capture as already required, and never turn into a broad storage or TCC reset.
4. Switching from owner A to owner B closes and retargets every owner-scoped store without exposing, overwriting, or merging the other owner's records.
5. Removing and reinstalling the disposable app bundle does not claim or mutate Omi state. Unless the user explicitly chooses a product-data deletion action owned by another requirement, the product's own Application Support data remains available to its reinstalled same identity.
6. Runtime self-install from a mounted DMG or App Translocation retains the exact IR-929 safety contract, but derives its destination, guidance, logs, and guard identity from the current product bundle rather than hard-coded Omi names.
7. The Omi Rewind importer and the `Omi Computer.app` takeover path no longer exist. Nothing replaces them with a generic legacy importer, process killer, deleter, trash helper, or “helpful” first-run scan.
8. A disposable `omi-wave5-s28` bundle exercises the real local path without launching, stopping, deleting, resetting, seeding from, or otherwise changing `/Applications/Omi.app`, `/Applications/Omi Beta.app`, their processes, or any Omi-owned local data.

“Preserve local stores” means preserve the approved store implementations and lifecycle contracts inside the new product's namespace. It does not mean copy the current `Omi` directory into the new root. This product has no released predecessor population at S-28, so the correct first-run migration from Omi is no migration at all.

## 4. Authorizing requirements

| Authority | S-28 interpretation | Proof owner |
|---|---|---|
| IR-929 | Keep mounted-volume/App-Translocation detection, the explicit skip gate, current-bundle filename destination under `/Applications`, numeric no-downgrade behavior, same-volume staging, atomic replacement, quarantine clearing, delayed relaunch, termination only after relaunch scheduling, two-attempt loop guard, manual fallback, and running-in-place failure behavior. Make product identity data-driven. | Cycles 9 and 12 |
| IR-931 | Create owned stable/Beta/dev/named/preview identities and owned persistence/service namespaces. Delete every automatic Omi database/media import and every Omi app/process takeover. Do not access Omi data. | Cycles 1–12 |
| S-08 retained auth handoff | Keep hosted auth/session behavior, Team ID plus bundle-ID Keychain fencing, silent Keychain failure, transactional same-product defaults-to-Keychain migration, both sign-out entries, and ordinary local-data preservation. Consume only approved OAuth/Firebase bundle registrations. | Cycles 4 and 7 |
| S-10 through S-15 retained local authorities | Preserve owner-scoped Conversations/Rewind GRDB, Chat journal and attachments, Memory, Tasks, Goals/Focus/Home projections, Rewind media/backups, and their existing effective-owner retargeting and deletion semantics. | Cycles 5, 6, and 12 |
| S-17 retained lifecycle handoff | Preserve the narrowed onboarding/reset key allowlist, capture-stop ordering, local setup-journal cleanup, completion-controlled login policy, and the rule that non-production bundles never register `SMAppService.mainApp`. | Cycles 7, 8, and 12 |
| `PRODUCT.md` | Local memory remains the durable authority; the agent runtime is a subordinate local execution layer; privacy and owner isolation do not change because names change. | Every cycle |
| Root and desktop `AGENTS.md` | Test changed behavior through production seams, use a named dev bundle, never automate production apps, record evidence, update technical docs with changed commands, and keep S-29/S-30 boundaries intact. | Execution and closeout |

No other requirement authorizes an Omi import. In particular, an Omi-to-Omi compatibility migration is not transformed into a fork-to-new-product migration by renaming its destination.

## 5. Dependencies and entry gates

### G0 — mandatory execution setup and fresh inventory

Before the first implementation commit, run `make setup`, verify the linked-worktree-safe pre-commit hook, fetch `origin`, integrate the current target branch without switching branches, record the exact SHA, and repeat the current-caller and residue searches. Do not continue from a stale path list. If a new predecessor has changed a store owner, bundle classifier, or reset/sign-out boundary, reconcile that public seam before editing.

### G1 — predecessor and baseline gate

S-08, S-10 through S-15, and S-17 are hard functional predecessors. Baseline `22ad2f16ff8d63fd761c918b92f4c5d961814624` contains their complete repair tree and is authorized to start S-28. BL-001 remains the later all-waves provider/continuity qualification gate; it does not authorize claims about unrun live lanes and it does not require S-28 to call a provider.

Cycles 1 and 2 can proceed from this gate because deleting foreign takeover behavior does not require a final product name or external credential.

### G2 — exact technical identity tuple, required before Cycle 3

Do not infer the new reverse-DNS owner or technical storage token from `support@heyintentive.com`, provisional UI copy, the repository name, or a planned S-30 brand. Before Cycle 3, the product owner must provide one reviewed tuple containing:

- the reverse-DNS owner and exact stable, Beta, canonical-dev, named-dev-prefix, and preview-prefix bundle identifiers;
- the technical Application Support and Cache root components;
- database, agent-runtime database, log, lock, automation-token, archive-cache, and runtime-manifest names/prefixes;
- the two Keychain base service identifiers while preserving Team ID plus bundle-ID scoping;
- the new runtime self-install skip-variable name and any other environment/config prefix that is part of persistent or cross-process identity;
- the stable/dev/named URL schemes, or an explicit handoff to the S-08 registered schemes;
- whether an app group is intentionally absent or, only with a demonstrated current consumer, the exact owned app-group identifier; and
- the exact technical display-independent app filename used by installer acceptance if S-30 has not yet selected final visible naming.

The current checkout has `app-sandbox=false` and no `com.apple.security.application-groups` or `keychain-access-groups` entitlement. The default S-28 target is therefore an explicit `appGroupIdentifier = nil`, tested as absence. Do not add an unused app group. If S-29 later demonstrates a real signed capability consumer, stop and revise the tuple before adding it.

### G3 — S-08 external auth registration gate

`GoogleService-Info.plist`, `GoogleService-Info-Dev.plist`, `GoogleService-Info-Local.plist`, and the OAuth callback schemes currently carry Omi bundle identities. S-28 may wire only bundle IDs and callback schemes that S-08's owned Firebase/Google/Apple registration actually supports. If those values are unavailable, finish configuration-independent Cycles 1 and 2, but stop Cycle 4. Do not retain an Omi registration behind a fallback alias and do not create unregistered-looking placeholder production credentials.

### G4 — clean-first-build and no-import gate

The first build under the approved new identity is the only valid migration origin for the “upgrade from our own first build” acceptance case. No fixture, seed script, defaults mirror, Keychain fallback, database helper, or launch code may use an Omi product root as the source. Hermetic tests use test-owned temporary roots containing clearly synthetic foreign sentinels; live acceptance never creates, hashes, enumerates, or opens a real Omi store to prove non-access.

### G5 — S-29 release boundary

S-28 defines the bundle-family and local identity contract that S-29 consumes. S-29 owns Developer ID identities, provisioning, entitlements that truly require signing, notarization, release DMGs, Sparkle appcast/public keys, update hosting, Stable/Beta promotion, preview publication, release caches, and public URLs. S-28 must not edit those systems merely to make an identity test green. A disposable locally produced DMG may exercise IR-929 for `omi-wave5-s28`; it is not a signed candidate or release proof.

### G6 — S-30 visible truth boundary

S-28 removes hard-coded product names from technical identity decisions and makes installer/path copy derive from the current bundle or an approved technical identity. It does not choose final marketing copy, icons, menu labels, repository links, privacy/legal language, or broad prose replacements. If a functional path description must change in S-28, make it derive from the actual resolved path so S-30 can replace visible names without reopening storage logic.

### G7 — non-mutation safety gate

All implementation and acceptance commands must target test-owned temporary roots or the exact disposable bundle selected through `OMI_APP_NAME=omi-wave5-s28`. Never run cleanup, `defaults delete`, `security delete-generic-password`, `tccutil reset`, process termination, app removal, database migration, or filesystem repair against an Omi stable/Beta bundle, domain, service, root, process, or TCC identity. Any proposed test that needs a real Omi path is invalid and must be redesigned around an injected external boundary.

## 6. Current production codeflow

### 6.1 Launch ordering and same-product installation

`AppDelegate.applicationWillFinishLaunching` installs the bundle-ID plus launch-mode `SingleInstanceGuard` before ordinary state opens. `applicationDidFinishLaunching` then handles exporter/canary modes and calls `AppInstaller.moveToApplicationsIfNeeded()` before bundle environment loading, automation, runtime-manifest publication, databases, capture, agents, or normal background services. That early placement is correct and retained.

`AppInstaller` detects only `/Volumes/...` and App Translocation origins unless `OMI_SKIP_INSTALL_GATE` is set. It uses `/Applications/<running bundle filename>`, compares numeric builds, stages on the destination volume, atomically moves/replaces, clears quarantine, schedules a delayed `open`, and exits only after scheduling. Its retry counter and guidance still carry inherited identity and must become target-derived without changing the state machine.

Later startup calls `runStartupSystemMaintenance()`, which calls `migrateAppName()`. That reaches `cleanupLegacyAppBundles()`: on the stable Omi identity it searches two `Omi Computer.app` paths, enumerates `com.omi.computer-macos` processes, force-terminates them, delays, deletes the old app, and falls back to Trash. This entire path is foreign takeover behavior and is deleted in Cycle 2. It is not part of IR-929.

### 6.2 Bundle family and writable roots

`AppBuild` separately hard-codes stable `com.omi.computer-macos`, Beta `com.omi.computer-macos.beta`, dev `com.omi.desktop-dev`, and preview prefix `com.omi.preview.`. It derives production/non-production, local automation, named development, preview validity, login/update eligibility, channel behavior, and external-preview restrictions from those strings.

`DesktopStorageIdentity` separately hard-codes the named prefix `com.omi.omi-` and Beta identifier. It maps stable/default and canonical dev to `Omi`, Beta to `Omi Beta`, named development to `Omi Dev Bundles/<bundle-id>`, and an optional harness local profile to its configured root. `DesktopLocalProfile.applicationSupportURL()` and `.cachesURL()` apply the same path components under two system base directories. The duplicated identity constants can drift and currently point the new product at Omi-owned locations.

### 6.3 Owner-scoped database and local artifacts

`RewindDatabase` resolves `DesktopLocalProfile.applicationSupportURL()/users/<effective-owner>/`, creates it, and then calls `migrateFromLegacyPathIfNeeded` before opening `omi.db`. For a non-isolated profile that importer searches the shared `Application Support/Omi` root and `users/anonymous`, checkpoints source/destination WALs, moves or merges `omi.db`, Screenshots, Videos, and backups, and removes migration-only WAL/SHM/running files. The implementation is careful for an Omi lineage migration but unauthorized for this product.

After that importer, the retained flow detects an unclean shutdown through `.omi_running`, cleans stale WAL files for the selected database, opens GRDB, applies migrations, verifies the owner generation before publishing the pool, and keeps `poolEpoch` distinct from initialization generation. `RewindStorage` and the retained local-domain modules use the same owner root for media, memory, tasks, goals/focus, and conversation authority. Those behaviors remain; only identity and importer ownership change.

`LocalChatAttachmentStore` uses `Application Support/<current-root>/ChatAttachments/v1`. `AgentRuntimeProcess` supplies an agent state directory under the current profile; the Node runtime nevertheless has an `Application Support/Omi/agent` fallback and owns `omi-agentd.sqlite3`. The automation bridge reports that database path for continuity evidence. All of these must resolve through the new identity contract.

### 6.4 Defaults, Keychain, and installation identity

macOS supplies `UserDefaults.standard` under the current bundle identifier, so replacing the bundle family naturally starts a clean defaults domain. Internal defaults keys need not be renamed merely for style, but no explicit suite, dump/seed default, cleanup tool, or migration may address an Omi domain.

`DesktopKeychainStore` correctly scopes services as `<base>.v2.team.<TeamID>.bundle.<bundleID>` and deliberately avoids querying unscoped legacy entries. Its bases remain `com.omi.desktop.firebase-rest-session` and `com.omi.client-device-id`. `AuthService` uses the scoped auth service and permits a transactional token migration only from the running bundle's own defaults domain. `ClientDeviceService` uses defaults for non-production and a Team+bundle Keychain item plus same-domain mirror for production-family installation identity. The scoping, silent failure, and same-product continuity are retained; the Omi base services and Omi bundle classifier are not.

### 6.5 Login item, TCC, updater, logs, and transient identity

`LaunchAtLoginManager` uses `SMAppService.mainApp`; the OS binds that login item to the signed bundle. S-17 correctly refuses registration for non-production bundles and ties production registration to genuine onboarding completion/settings. TCC is likewise bundle/signature scoped. Changing the bundle identity intentionally creates fresh grants; S-28 must not reset or import Omi grants.

`AppBuild` controls Sparkle eligibility and Beta/stable channel behavior. The local classifier must move to the new identity in S-28, but feed URLs, signing keys, release artifacts, public download links, and preview infrastructure remain S-29.

`Logger` uses `/tmp/omi.log`, `/tmp/omi-beta.log`, and `/private/tmp/omi-dev-<bundle>-<pid>.log`. The single-instance guard, automation-token helpers, Node archive cache, qualification cache, runtime manifest, cleanup tools, and harness evidence use additional `omi-*`, `com.omi.*`, or `OmiDesktop` path/identity prefixes. These are technical namespaces even when their command filenames remain temporarily visible for operator continuity.

### 6.6 Development and test seeding

`scripts/app-config.sh` maps `OMI_APP_NAME` to Omi bundle IDs and URL schemes. `run.sh` installs named bundles into `/Applications` and currently auto-seeds auth, selected defaults, and a consistent Rewind snapshot from Omi Dev. `omi-rewind-seed.sh` defaults its source to `~/Library/Application Support/Omi`, while auth/settings seed helpers default to `com.omi.desktop-dev` and Omi Keychain service bases. Cleanup and TCC scripts guard Omi prefixes.

The named-bundle isolation mechanics are worth retaining, but after S-28 they may seed only from the canonical development identity of this product and may delete only this product's explicitly disposable named bundles. A clean-profile option must never consult the old Omi locations as a fallback.

## 7. Complete caller and dependency inventory

Refresh this table at execution time. “Expected owner” names the slice that may change the surface; it is not permission to edit every textual `Omi` occurrence.

| Surface | Current owners/callers | S-28 action | Expected owner / boundary |
|---|---|---|---|
| Bundle-family constants and capabilities | `Desktop/Sources/AppBuild.swift`; `AppBuildBetaIdentityTests`, `ExternalPreviewBuildTests`, updater/login/automation callers | Replace Omi literals with one approved typed family contract; retain behavior per family. | S-28; feed/signing values stay S-29. |
| Storage-family resolver | `Desktop/Sources/OmiSupport/DesktopLocalProfile.swift`; `DesktopLocalProfileTests`, `DesktopStorageIdentityTests` | Make the new product identity authoritative for stable/Beta/dev/named/preview and roots. | S-28. |
| Build-time dev/named identity | `scripts/app-config.sh`, `run.sh`, `Tests/test-app-config.sh`, launch-env/signing tests, `scripts/dev-instance.sh` callers | Map the requested `omi-wave5-s28` app name to the approved new bundle prefix and owned URL scheme; no Omi domain fallback. | S-28 consumes S-08 values; S-29 owns release variants. |
| Bundle plists and OAuth registration | `Desktop/Info.plist`; three `GoogleService-Info*.plist`; OAuth callback code | Replace only with registered owned bundle/scheme inputs; keep Info placeholders/data flow. | S-08 input, S-28 wiring, S-30 visible name, S-29 signing. |
| App-group/keychain entitlements | `Desktop/Omi-Release.entitlements`; signing prep/tests | Record/test no app group and no Keychain access group today; do not add an unused capability. | S-28 identity decision; S-29 owns any later signed entitlement change. |
| Runtime self-install | `Desktop/Sources/Startup/AppInstaller.swift`; `OmiApp.swift`; `AppInstallerTests` | Retain IR-929 state machine; derive name/destination/guidance/log/skip key. | S-28 behavior; S-29 artifact production. |
| Historical app takeover | `OmiApp.migrateAppName`, `cleanupLegacyAppBundles`; `AppBuild.mayRunLegacyStableAppCleanup`; related tests | Delete call, policy, process enumeration, app search, force termination, delete/Trash fallback, and exclusive tests. | S-28. |
| Rewind importer | `Rewind/Core/RewindDatabase.swift`; `DesktopStorageIdentityTests` and migration-specific tests | Behaviorally fence non-access, then delete legacy-root/anonymous import and exclusive WAL/move/merge code. | S-28; retain ordinary current-database WAL recovery. |
| Owner database root/file/flag | `RewindDatabase`, `RewindStorage`, `LocalMemoryLifecycleRunner`, conversation/memory/task/goal/focus stores and tests | Resolve approved root/file/flag through one namespace; preserve owner ID and generation fencing. | S-28 identity over S-10–S-15 behavior. |
| Rewind assets and path presentation | Screenshots, Videos, backups, graph layout, `RewindOnlyView`, Chat tool descriptions/generated capability text | Move only new writes to target-derived paths/names; update truthful resolved-path descriptions. Never migrate old assets. | S-28 functional path; S-30 broad copy. |
| Agent runtime | `Chat/AgentRuntimeProcess.swift`, `agent/src/index.ts`, `runtime/sqlite-store.ts`, `artifact-storage.ts`, automation bridge, runtime tests | Remove Omi fallback; pass/require approved state root and database filename; keep owner runtime/journal authority. | S-28 over S-11. |
| Chat attachments | `Chat/LocalChatAttachmentStore.swift` and journal/attachment tests | Put materialized attachments beneath the approved product and owner/chat root; preserve source-file non-deletion. | S-28 over S-11. |
| UserDefaults domain | Bundle ID, `DefaultsKey`, reset/sign-out/onboarding/update callers, seed/cleanup tests | New bundle domains start clean; preserve internal keys and exact S-17 allowlists; remove explicit Omi domain reads/writes. | S-28 identity over S-08/S-17 behavior. |
| Auth Keychain | `DesktopKeychainStore`, `AuthService`, `AuthStorageCanary`, auth dump/seed scripts/tests | Replace base service; retain Team+bundle scope, silent no-prompt behavior, and own-domain transactional migration. | S-28 consumes S-08. |
| Installation/device identity | `ClientDeviceService` and tests | Replace Omi classifier/base; create fresh identity for the new product; retain it across own upgrades and same-identity reinstall. | S-28. |
| Login/relaunch identity | `LaunchAtLoginManager`, `OmiApp` AppKit relaunch policy, S-17 lifecycle tests | Use target production family; keep non-production refusal and onboarding/settings state transitions. | S-28 identity over S-17 behavior; signed proof S-29. |
| TCC identity and cleanup | Bundle identifiers; `cleanup-omi-tcc.sh`, qualification/self-clean scripts and tests | Make cleanup accept only approved disposable target prefixes and refuse Omi identities. Never reset real Omi TCC. | S-28 local tooling; signed grant proof S-29/S-31. |
| Updater identity | `AppBuild`, `UpdaterViewModel`, Sparkle callers/tests, update defaults | Reclassify owned stable/Beta/dev/named/preview; retain channel and activity gates. | S-28 identity; URLs/keys/workflows S-29. |
| Logs and query tracing | `Logger.swift`, `QueryTracer`, diagnostics/harness log readers, component guide/tests | Resolve target log namespace, bundle, PID, permissions; keep PII sanitization and 0600 behavior. | S-28 technical paths; S-30 broad prose. |
| Locks and automation tokens | `SingleInstanceGuard`, `DesktopAutomationBridge`, `automation-token-path.sh`, `automation_token_lib.py`, `omi-ctl`, harness/qualification tests | Use target technical prefix plus bundle/launch mode or port; preserve fail-closed authentication and per-bundle/process isolation. | S-28 local/test namespace. |
| Shared development caches | `run.sh`, `prepare-agent-runtime.sh`, `qualification-swift-cache.sh`, `qualification-runner-self-clean.py`, `omi-macos-dev` | Rename OmiDesktop/cache roots and guard cleanup by target provenance; never inherit or erase Omi caches. | S-28 local cache; S-29 owns release cache semantics. |
| Named-bundle seeding and cleanup | `run.sh`; `omi-auth-*`, `omi-settings-seed.sh`, `omi-rewind-seed.sh`, `omi-macos-dev`; shell tests and e2e guide | Source only from owned canonical dev identity, support explicit clean start, and manage only approved disposable target bundle IDs/profiles. | S-28; visible tool rename may wait for S-30 if it is not a persisted identity. |
| In-process technical labels | Dispatch queue labels, `Notification.Name` values, internal fault bundle IDs, diagnostic domain filters | Replace persistent/cross-process Omi identity and adapt touched internal labels from the approved technical prefix; do not churn unrelated private labels for style. | S-28 residue closeout, with S-30 broad text sweep. |
| Release-only identity | Beta variant creation, signed smoke, qualification/release scripts, Codemagic, Sparkle feed/key, release URLs, notarization, GitHub/GCS | Provide the new identity contract as input; do not implement release ownership here. | S-29. |
| Visible product identity | App display strings, icon/resource names, menu/settings prose, final docs, privacy/legal copy | Keep replaceable/derived seams; do not choose final truth in S-28. | S-30. |
| Historical evidence | Changelogs, bootstrap requirements/plans, incident fixtures intentionally describing Omi | Preserve and classify; do not rewrite history to make residue searches empty. | KEEP / documented exception. |

Generic `omi.db` test fixtures that construct a temporary database are not automatically foreign-data access, but the production database filename and any user-facing path description are S-28 identity. Test fixture names should follow the approved database contract when they exercise production path resolution; isolated low-level GRDB tests may keep an arbitrary temporary filename if the filename is irrelevant to the behavior under test.

## 8. Behavior classification

### KEEP AS IS

- The retained S-10–S-15 local domain models, schemas, mutations, source links, deletion cascades, crash recovery, and effective-owner generation fences.
- Team ID plus bundle-ID Keychain scoping, noninteractive Keychain access, preservation on transient write failure, and no query of foreign/pre-scope service names.
- S-08 sign-in/restore/refresh/sign-out ordering and S-17 reset/onboarding cleanup boundaries.
- `SMAppService.mainApp` with non-production refusal and completion/settings control.
- Single-instance separation by exact bundle and launch mode.
- IR-929 mounted-volume/App-Translocation install state machine, no-downgrade rule, atomicity, relaunch ordering, loop guard, and fail-open/manual fallback.
- Stable/Beta/named/preview capability distinctions, local automation restrictions, and update channel semantics, after their identity inputs are replaced.

### ADAPT

- Bundle identifiers and family predicates for stable, Beta, canonical dev, named dev, preview, and the `omi-wave5-s28` acceptance bundle.
- Application Support, Cache, Log, temporary, runtime, archive-cache, test-profile, database, attachment, lock, token, and manifest names/roots.
- UserDefaults domains through new bundle identities and every explicit script/tool domain reference.
- Keychain base services while retaining the current scope suffix and security behavior.
- Client installation identity so the new product starts fresh and later upgrades itself without rotation.
- Login-item, updater, TCC, automation, and cleanup classifiers that derive from the owned bundle family.
- Runtime installer identity, including its skip variable, current-bundle destination, derived guidance, tests, and sanitized logs.
- Technical path descriptions and test/operator docs required to use the new resolved roots.

### DELETE

- `RewindDatabase.migrateFromLegacyPathIfNeeded`, `shouldMigrateLegacyStorage`, the Omi root/anonymous selection, migration-only WAL checkpointing, source/destination merge/move, and exclusive tests/comments.
- `migrateAppName`, `cleanupLegacyAppBundles`, `mayRunLegacyStableAppCleanup`, `Omi Computer.app` searches, `com.omi.computer-macos` process enumeration, force termination, delayed deletion, Trash fallback, and exclusive compatibility tests.
- Omi-root seeding defaults and any fallback that imports auth, settings, Rewind, databases, defaults, caches, logs, tokens, or TCC state from Omi.
- Omi bundle IDs or roots accepted by product cleanup tools as mutable targets.
- Mixed old/new compatibility aliases added solely to preserve the retired namespace for in-tree callers.

### SIMPLIFY AFTER

- After all target identity tests are green, remove duplicated bundle classifiers and make `AppBuild` and `DesktopLocalProfile` consume one Swift identity authority.
- Collapse migration-only filesystem helpers, comments, and fixtures once the importer is gone, while retaining ordinary current-database recovery helpers.
- Remove obsolete seed flags/options whose only purpose was Omi-to-named copying; retain one explicit own-dev-source path and one clean-start path.
- Normalize test fixtures and technical docs only after every production caller has moved; do not combine this with unrelated UI or storage refactoring.

### ACCELERATE AFTER

No performance work is authorized until the behavioral slice is green and measured. If namespace resolution or named-bundle setup becomes a demonstrated bottleneck, improve only the measured path without caching owner identity across account transitions or weakening path/provenance validation.

### AUTOMATE LAST

Add or extend deterministic residue/contract checks only after the manual inventory and real behavior work. Any new checker must be registered in the existing local and CI manifest, identify IR-931 and the real Omi takeover paths it would have caught, and remain supplemental to behavioral tests. Do not add an orphan script, scheduled job, source-order assertion, or text scan presented as runtime proof.

### OUT OF SCOPE / DEFERRED

- Final app/product naming, icon/assets, broad UI prose, privacy/legal copy, repository links, and visible rebrand truth: S-30.
- Developer ID, signing identity, notarization, universal release dependencies, Codemagic, release DMG construction, Sparkle feed/key/hosting, preview lifecycle, Stable/Beta promotion/rollback, release URLs, and public destinations: S-29.
- Production deployment, provider qualification, billing, cloud/IAM changes, and final all-waves continuity: S-31/BL-001 and other owners.
- Any import wizard, opt-in Omi migration, cross-product account linking, cloud sync, app-group sharing without a consumer, or generic legacy-app cleanup framework.
- Windows, iOS, Android, backend data schema, and hosted service work.

## 9. Retained behavioral invariants

1. **Foreign-product non-access:** production code has no path that opens, enumerates, reads, moves, merges, deletes, checkpoints, defaults-queries, Keychain-queries, launches, terminates, trashes, or resets an Omi installation or its data.
2. **Clean identity:** every new stable/Beta/dev/named/preview identity resolves to an approved product namespace or fails closed before writable state opens. An unknown bundle never falls back to the stable product or Omi root.
3. **One typed family:** bundle classification used for storage, automation, login, updates, TCC/test cleanup, and Keychain decisions is consistent. No duplicated prefix predicate may silently disagree.
4. **Owner fence:** every durable user-content path remains beneath the effective owner and validates generation/owner before publishing results. Account switching never merges directories or reuses stale pools/actors.
5. **Own-data continuity:** build B of an owned identity opens build A's store with normal schema migration and no identity rotation. It does not call a cross-product importer.
6. **Sign-out/reset scope:** sign-out and onboarding reset preserve ordinary local content and system TCC grants, clear only their approved state, and stop capture before replay exactly as S-08/S-17 require.
7. **Uninstall/reinstall scope:** removing a disposable `.app` does not imply deleting its Application Support, defaults, Keychain, caches, or TCC. Any explicit test cleanup is target-derived, provenance-checked, and limited to the assigned named bundle.
8. **Keychain isolation:** auth and installation-ID services retain Team+bundle scope, never query an Omi base service, never show a password prompt, and do not delete an inaccessible existing item after a transient failure.
9. **Defaults isolation:** only the current target bundle's domain is read/written. Same-domain token migration can preserve an owned upgrade; no Omi domain is a fallback source.
10. **App-group absence:** without a current retained consumer and approved identifier, the product has no app-group entitlement or group-container access. Absence is an intentional owned state.
11. **Login/TCC isolation:** non-production login registration remains refused; production login/TCC identity follows the owned signed bundle later supplied by S-29. S-28 never resets or copies Omi permission records.
12. **Updater boundary:** named dev and preview builds remain unable to consume the shared update channel; stable/Beta behavior remains distinct. S-28 changes identity classification, not feeds, keys, or release policy.
13. **Installer safety:** only mounted/translocated launches enter installation; normal downloads/dev locations and the approved skip variable remain untouched; equal/older builds do not overwrite; a failed stage preserves the installed app; exit occurs only after relaunch is scheduled.
14. **Log/test hygiene:** technical paths are target-derived, logs remain private and sanitized, automation tokens remain authenticated, cleanup refuses ambiguous/protected identities, and evidence contains no tokens, raw user IDs, local content, or real Omi-path inspection.
15. **No compatibility shell:** all in-tree callers migrate in the same change. No deprecated alias, dual-write, old-root fallback, one-time Omi importer, or “temporary” generic killer lands.

## 10. Target identity, namespace, and installation model

### 10.1 One deep Swift authority

Create or deepen one `OmiSupport`-level value type, provisionally called `DesktopProductIdentity`, initialized from the exact signed bundle identifier plus explicit harness configuration. The name is provisional; its responsibilities are not. It returns:

- `family`: `.stable`, `.beta`, `.development`, `.namedDevelopment(slug)`, `.externalPreview(id)`, or `.invalid`;
- the exact bundle identifier and whether it is production-family, named, preview, locally automatable, Sparkle-eligible, or login-eligible;
- Application Support and Cache path components;
- owner database filename/running flag, agent state directory/database, attachment root, runtime manifest, log, lock, token, and cache components;
- Keychain auth and installation-ID base services, to which the existing Team+bundle scope is applied;
- an explicit optional app-group identifier, expected to be `nil` for the current retained architecture; and
- the installer guard identity and derived current-bundle installation destination.

`DesktopLocalProfile` consumes this value for paths. `AppBuild` consumes the same family/capabilities instead of repeating literals. Owner-specific stores consume the resolved root but keep their own deep public interfaces and state machines. Unknown/malformed production-looking identifiers are `.invalid` and cannot acquire stable privileges or a writable stable root.

The shell build must know identity before Swift runs, so `scripts/app-config.sh` remains the build-time boundary. It must implement the same approved tuple and is checked behaviorally against exact family fixtures. Do not introduce a runtime compatibility alias. Prefer a small generated constant only if the existing build can consume it mechanically and the matching generation check is placed in an existing CI lane; otherwise keep the shell mapping small and test its outputs against the reviewed tuple.

### 10.2 Path model

All durable paths start from a system-provided user directory plus approved target components. No production path is constructed from a raw `HOME` string, a final UI label, or a hard-coded Omi component.

```text
<Application Support>/<approved product root>/
├── users/<effective-owner>/
│   ├── <approved primary database>
│   ├── <approved running flag>
│   ├── Screenshots/                 # retained artifact role; exact naming from G2
│   ├── Videos/
│   └── backups/
├── agent/
│   └── <approved agent database>
├── attachments/<owner>/<chat>/...
└── runtime/<bundle>/manifest.json

<Caches>/<approved product root>/<family-or-bundle>/...
<private temporary root>/<approved technical prefix>/<bundle>/<pid-or-port>/...
```

The exact components come from G2. The diagram expresses ownership, not final literals. A named build remains isolated by exact bundle identifier even when launched later by Finder without `run.sh`. Owner ID remains a child boundary inside the product root; bundle identity and account identity are not interchangeable.

### 10.3 Installation and persistence state model

The startup state machine is:

```text
bundle starts
  -> single-instance fence for exact bundle + launch mode
  -> exporter/canary side-effect-free modes
  -> IR-929 same-product install gate
       -> relaunch scheduled: current process exits before storage
       -> failure/manual fallback: current process continues in place
       -> not applicable: continue
  -> resolve valid target identity
       -> invalid: fail before writable product state
  -> open current target defaults/services/paths
  -> bind effective owner and open only that owner's stores
```

There is no “legacy scan” state. The new product's first launch and later own upgrade follow the same resolver; schema migration happens inside the selected target database, not by searching another product's root.

### 10.4 External-boundary test seams

Behavior tests may substitute only true external boundaries: filesystem operations, bundle metadata, process/workspace launch/termination, UserDefaults suite, Keychain adapter, `SMAppService`, system directories, clock, and relaunch scheduling. Tests drive the production identity/installer/store/startup interfaces through those adapters. They do not assert private call order or source-string position. Static forbidden-pattern checks are secondary residue tripwires.

## 11. Ordered TDD cycles

Cycles are sequential unless a gate explicitly stops them. Commit each independently testable behavior surface separately; do not write all RED tests in bulk. Cycles 1 and 2 are safe before G2. Cycle 3 and later require the exact approved identity tuple, and Cycle 4 additionally requires S-08 registration inputs.

### Cycle 1 — delete automatic Omi database and media takeover

- **RED:** Through the production Rewind initialization seam with injected user directories/filesystem, create a clean target owner root and a separate synthetic foreign root shaped like the current Omi root, including database, WAL, Screenshots, Videos, backups, and anonymous-owner sentinels. Initialize the target owner and assert a fresh target store, zero read/write/move/remove/checkpoint calls against the foreign root, and byte-for-byte untouched sentinels.
- **Why it fails now:** `performInitialization` calls `migrateFromLegacyPathIfNeeded`; the current non-isolated path selects `Application Support/Omi` or `users/anonymous`, checkpoints and moves/merges its contents, and removes migration-only files.
- **Minimum GREEN:** Delete the migration call, source selection, `shouldMigrateLegacyStorage`, migration-only checkpoint/merge/move/cleanup helpers, and exclusive expectations. Initialize only the already-resolved current owner directory. Add the smallest filesystem/root injection needed to observe production behavior; do not create a generic import-policy abstraction.
- **Retained behavior:** Target-directory creation, current-database WAL cleanup and retry, corruption recovery, GRDB schema migration, `.running` crash detection, pool epoch, initialization generation, and effective-owner checks.
- **Expected change surface:** `Rewind/Core/RewindDatabase.swift`, directly related Rewind/Desktop storage tests, and migration-exclusive comments/tests only.
- **Exact focused verification:** from `desktop/macos`, run `./scripts/dev-feedback.py --once swift 'OmiTakeoverIsolationTests'`, `./scripts/dev-feedback.py --once swift 'RewindDatabaseLifecycleTests'`, and `./scripts/dev-feedback.py --once swift 'DesktopStorageIdentityTests'`; run the retained effective-owner and Rewind recovery filters named by the refreshed inventory through the same focused runner.
- **Deletion/simplification enabled:** Remove every Omi/anonymous importer branch and the helper surface that exists only to make that import data-safe; keep ordinary WAL helpers that serve the current selected database.
- **Stop conditions:** Stop if a refreshed supported-version contract proves this new product already shipped a store under an owned predecessor identity, if deletion would remove ordinary same-database schema migration/recovery, or if the test needs a real Omi path rather than a synthetic injected boundary.

### Cycle 2 — delete Omi app/process takeover while retaining startup maintenance

- **RED:** Drive the production startup-maintenance seam with a recording workspace, process catalog, scheduler, and filesystem containing synthetic `Omi Computer.app` sentinels and foreign bundle processes. Assert startup makes zero enumerate, terminate, delay, delete, or Trash requests for them while retained unrelated startup maintenance still runs.
- **Why it fails now:** `runStartupSystemMaintenance` calls `migrateAppName`, whose stable-only cleanup enumerates `com.omi.computer-macos`, force-terminates other processes, and deletes/trashes two `Omi Computer.app` paths after a delay.
- **Minimum GREEN:** Remove the `migrateAppName` call and implementation, `cleanupLegacyAppBundles`, `AppBuild.mayRunLegacyStableAppCleanup`, old bundle constants, and exclusive tests. Do not replace them with a product-neutral legacy app cleaner.
- **Retained behavior:** The IR-929 current-bundle installer, single-instance guard, startup log hygiene, updater first-launch channel synchronization, and every unrelated `runStartupSystemMaintenance` action.
- **Expected change surface:** `OmiApp.swift`, `AppBuild.swift`, startup/AppBuild tests, and no generic process/filesystem utility beyond a minimal behavioral recording seam if one is required.
- **Exact focused verification:** from `desktop/macos`, run `./scripts/dev-feedback.py --once swift 'LegacyAppTakeoverIsolationTests'`, `./scripts/dev-feedback.py --once swift 'AppBuildBetaIdentityTests'`, and `./scripts/dev-feedback.py --once swift 'AppInstallerTests'`; run the refreshed startup-maintenance filters through the same focused runner.
- **Deletion/simplification enabled:** Delete old-app search/process/delete/Trash code and compatibility tests; simplify stable-family classification after Cycle 3 absorbs the remaining valid uses.
- **Stop conditions:** Stop if a proposed deletion reaches the current running bundle, the normal DMG installation path, updater relaunch, or any non-exclusive startup action. No real process may be spawned or terminated by the test.

### Cycle 3 — establish one approved bundle-family and namespace authority

- **RED:** At `DesktopProductIdentity`'s public value interface, table-drive the approved G2 stable, Beta, canonical-dev, named-dev, preview, malformed, unknown, and nil identifiers. Assert exact family/capability/path/service outputs, explicit nil app group, named-bundle isolation, and fail-closed invalid identity. Assert no target output equals or falls beneath an Omi bundle/service/path namespace.
- **Why it fails now:** `AppBuild` and `DesktopStorageIdentity` separately hard-code `com.omi.*`, disagree by construction risk, and fall stable/default storage back to `Omi`.
- **Minimum GREEN:** Add/deepen one typed identity authority in `OmiSupport`, migrate `DesktopLocalProfile` and `AppBuild` to it, and remove duplicated Omi family constants. Keep APIs narrow: callers ask for family/capability/resolved namespace, not raw naming rules.
- **Retained behavior:** Stable/Beta distinction, named bundle isolation across Finder relaunch, preview fail-closed validation, local automation only for local non-production, Sparkle eligibility boundaries, and optional harness local-profile isolation.
- **Expected change surface:** `OmiSupport/DesktopLocalProfile.swift` or a nearby focused identity file, `AppBuild.swift`, their Swift tests, and package documentation only if the package boundary changes.
- **Exact focused verification:** from `desktop/macos`, run `./scripts/dev-feedback.py --once swift 'DesktopProductIdentityTests'`, `./scripts/dev-feedback.py --once swift 'DesktopLocalProfileTests'`, `./scripts/dev-feedback.py --once swift 'DesktopStorageIdentityTests'`, `./scripts/dev-feedback.py --once swift 'AppBuildBetaIdentityTests'`, and `./scripts/dev-feedback.py --once swift 'ExternalPreviewBuildTests'`.
- **Deletion/simplification enabled:** Delete duplicate bundle constants and Omi default-root fallback; later cycles can consume one resolver rather than add more prefix tests.
- **Stop conditions:** Stop if G2 is incomplete, if an unknown identity would need a writable stable fallback, if a new package would exceed architecture-guide guardrails without its guide, or if implementation requires choosing S-30 visible copy.

### Cycle 4 — re-own build-time dev/named/preview configuration and callback identity

- **RED:** Source `scripts/app-config.sh` in a hermetic shell test and assert the approved canonical-dev mapping plus `OMI_APP_NAME=omi-wave5-s28` yield the exact G2 named bundle ID and S-08-approved URL scheme. Assert mismatched overrides, Omi bundle IDs, missing slugs, production IDs in local automation, and unregistered callback tuples fail closed. Assert all three Firebase plist selections match their approved bundle family.
- **Why it fails now:** The script derives `com.omi.desktop-dev`, `com.omi.<slug>`, and Omi URL schemes; Firebase plists contain Omi bundle IDs; preview and fault fixtures also use Omi prefixes.
- **Minimum GREEN:** Replace build-time mappings and directly related fixtures with the approved tuple, migrate all in-tree callers in the same cycle, and validate plist/bundle/scheme parity. Preserve `OMI_APP_NAME=omi-wave5-s28` as the requested local operator input even though its resulting bundle ID belongs to the new reverse-DNS namespace. Do not add an Omi-compatible override.
- **Retained behavior:** Slug validation, named bundle uniqueness, per-worktree automatic naming/ports, preview marker/backend restrictions, non-production automation, and local-auth-emulator routing.
- **Expected change surface:** `scripts/app-config.sh`, `run.sh` identity derivation only, Google service plists when G3 is satisfied, preview/fault identity fixtures, app-config/launch-env/Firebase tests.
- **Exact focused verification:** from `desktop/macos`, run `bash tests/test-app-config.sh`, `bash tests/test-launch-env-forwarding.sh`, `./scripts/dev-feedback.py --once swift 'FirebaseAuthAvailabilityTests'`, and `./scripts/dev-feedback.py --once swift 'ExternalPreviewBuildTests'`; print the derived configuration for `omi-wave5-s28` without launching it and record only non-secret identity fields.
- **Deletion/simplification enabled:** Remove old build-ID/scheme branches and test-only Omi bundle aliases; later harness cycles can consume the new mapping.
- **Stop conditions:** Stop if G2 or G3 is missing, if a plist would contain fabricated credentials/registration, if a production bundle becomes locally automatable, or if work crosses into S-29 preview publication/signing.

### Cycle 5 — move retained owner stores into the clean product root

- **RED:** With system base directories injected to temporary roots, resolve every family and two owners. Initialize the real Rewind/Conversation database path and retained Memory/Task/Goal/Focus/Rewind artifact callers. Assert exact approved root/database/flag components, distinct owners and bundle families, no foreign lookup, and ordinary build-A-to-build-B schema/data continuity within the same owned identity.
- **Why it fails now:** Production/default storage resolves to `Omi`, Beta to `Omi Beta`, named dev to `Omi Dev Bundles/<com.omi...>`, the primary database is `omi.db`, and path copy/comments/tests encode those names.
- **Minimum GREEN:** Route production store construction through the Cycle 3 resolver, adopt the G2 database/runtime components, update owner-path callers and truthful resolved-path presentation, and migrate all in-tree tests to injected target roots. Do not add a migration from the old Omi root; a target store absent at first launch is created fresh.
- **Retained behavior:** Existing schemas and schema migrations, effective-owner directory boundary, retarget cancellation/generation, source-linked cascades, crash/WAL recovery, media relative paths, retention, and local-only authority.
- **Expected change surface:** `RewindDatabase`, `RewindStorage`, owner-path consumers in Conversations/Memory/Tasks/Goals/Focus, `RewindOnlyView` path presentation, generated/tool database descriptions if filename-visible, and focused tests/docs.
- **Exact focused verification:** from `desktop/macos`, run `./scripts/dev-feedback.py --once swift 'DesktopStorageIdentityTests'`, `./scripts/dev-feedback.py --once swift 'EffectiveOwnerDatabaseBoundaryTests'`, and `./scripts/dev-feedback.py --once swift 'RewindDatabaseLifecycleTests'`; run the S-10–S-15 owner-switch, local-authority, mutation, cascade, and recovery filters listed by the refreshed caller inventory through the same focused runner.
- **Deletion/simplification enabled:** Remove inherited absolute paths, database-name duplication, and Omi-specific comments/fixtures from live path resolution. Keep arbitrary low-level temporary SQLite fixture names only when filename identity is irrelevant.
- **Stop conditions:** Stop if any store lacks an effective-owner contract, if a change would merge existing Omi bytes, if a schema is redesigned rather than relocated, or if a test changes expected domain behavior solely to follow implementation.

### Cycle 6 — re-own agent runtime, attachment, manifest, and artifact namespaces

- **RED:** Launch the production agent-runtime constructor with an injected target root and two owners, then exercise the Node SQLite/artifact store and attachment materialization. Assert the approved state/database/attachment/manifest paths, owner/chat isolation, restart continuity, source-attachment preservation, and hard failure or explicit injected root when the cross-process state variable is absent. Assert no `Application Support/Omi/agent` fallback exists behaviorally.
- **Why it fails now:** Swift passes `OMI_AGENT_STATE_DIR`, Node falls back to `Application Support/Omi/agent`, the runtime database is `omi-agentd.sqlite3`, attachments use a product-root child without a shared identity contract, and automation evidence hard-codes the database name.
- **Minimum GREEN:** Make Swift pass the approved state directory/environment identity, require or resolve the approved target root in Node, change the runtime database/artifact/attachment/manifest components from G2, and update automation evidence to ask the resolver/store for the path. Migrate every in-tree environment caller; no old-variable alias.
- **Retained behavior:** S-11 journal authority, `default` chat identity, owner-generation fencing, artifact limits and cleanup, source-file non-deletion, agent restart/crash continuity, and authenticated automation evidence.
- **Expected change surface:** `AgentRuntimeProcess.swift`, `LocalChatAttachmentStore.swift`, `DesktopAutomationBridge.swift`, `agent/src/index.ts`, `runtime/sqlite-store.ts`, `artifact-storage.ts`, runtime preparation scripts, and corresponding Swift/TypeScript tests.
- **Exact focused verification:** from `desktop/macos`, run `./scripts/dev-feedback.py --once swift 'AgentRuntimeProcessTests'` and the attachment/runtime-owner Swift filters through the same focused runner; then run `cd agent && npm test -- sqlite-store.test.ts artifact-storage.test.ts chat-continuity-invariant.test.ts` and `npm run build`.
- **Deletion/simplification enabled:** Delete Node's Omi fallback, duplicate database literals, and manifest-path reconstruction. One owner/root contract becomes the cross-language boundary.
- **Stop conditions:** Stop if runtime state can open before effective owner is known, if absence of the new environment silently selects another product root, if source attachments would be moved/deleted, or if S-11 journal semantics change.

### Cycle 7 — create clean defaults, Keychain, auth, and installation identity

- **RED:** Using isolated UserDefaults suites and a recording Keychain adapter, instantiate stable, Beta, dev, and named target identities. Assert new owned service bases with Team+bundle suffixes, no Omi service query/delete, fresh first-install device identity, stable same-identity readback across build versions/reinstall, distinct bundle identity separation, silent unavailable-Keychain fallback, and exact S-08/S-17 sign-out/reset effects with ordinary owner data untouched.
- **Why it fails now:** Keychain bases and non-production bundle predicates contain `com.omi`; seed/dump tools default to Omi domains/services; a renamed app could otherwise retain explicit Omi service identity even with a new bundle domain.
- **Minimum GREEN:** Replace the two Keychain service bases and product-family predicate through `DesktopProductIdentity`; keep the scope format and own-domain defaults mirror; adapt canary and seed/dump callers to target services; ensure first new stable launch creates a new installation ID and later same-identity builds reuse it. Preserve auth token migration only from the running target bundle's own defaults.
- **Retained behavior:** No Keychain UI, Team+bundle ACL isolation, write-failure preservation, token refresh/session authority, dev no-prompt behavior, both sign-out paths, setup reset allowlist, and ordinary data preservation.
- **Expected change surface:** `DesktopKeychainStore.swift`, `AuthService.swift`, `AuthStorageCanary.swift`, `ClientDeviceService.swift`, auth/defaults tests, and identity portions of auth dump/seed scripts.
- **Exact focused verification:** from `desktop/macos`, run `./scripts/dev-feedback.py --once swift 'AuthTokenStorageTests'`, `./scripts/dev-feedback.py --once swift 'ClientDeviceServiceTests'`, and `./scripts/dev-feedback.py --once swift 'AuthSessionAttemptFenceTests'`; run S-08 sign-out and S-17 persistence-clearing filters through the same focused runner; run `bash tests/test-omi-auth-seed-acl.sh` and `bash tests/test-local-profile-keychain-reset.sh` against test-owned services only.
- **Deletion/simplification enabled:** Remove old base constants, Omi domain/service defaults, and bundle-prefix branches. Do not delete real legacy Keychain items; leaving them untouched is the requirement.
- **Stop conditions:** Stop if a test would call the real login Keychain without a test service, if a migration reads an Omi defaults domain/service, if sign-out starts deleting ordinary content, or if Beta/stable sharing semantics differ from the approved G2/S-08 contract.

### Cycle 8 — re-own logs, locks, automation tokens, caches, TCC cleanup, and test profiles

- **RED:** Table-drive target families through log, lock, token, runtime-manifest, archive-cache, qualification-cache, and cleanup-path resolvers. Assert exact target-derived paths, bundle/PID/port isolation, private permissions, protected-family refusal, and that Omi bundle IDs/paths are rejected as non-target rather than accepted cleanup candidates. Use temporary homes and a synthetic TCC database; never call `tccutil` on the host.
- **Why it fails now:** Logger paths use `omi*`, locks and tokens use `omi-*`, caches use `OmiDesktop`, cleanup tools accept `com.omi.*`, and harness fixtures reconstruct those names independently.
- **Minimum GREEN:** Centralize target technical components, adapt consumers/tests and cleanup provenance checks, keep logs sanitized/0600 and tokens authenticated, and make destructive local helpers accept only exact approved disposable named identities. Preserve command filenames if renaming them is only S-30-visible churn; their mutable targets and persisted paths must nevertheless be clean.
- **Retained behavior:** Per-process non-production logs, stable/Beta separation, single-instance bundle+mode fence, automation-token fail-closed behavior, cache checksum/revalidation, worktree port isolation, and cleanup dry-run/status/provenance protections.
- **Expected change surface:** `Logger.swift`, `SingleInstanceGuard.swift`, automation token helpers/bridge/ctl, runtime/cache preparation scripts, `omi-macos-dev`, TCC cleanup and qualification self-clean logic, shell/Python/Swift tests, and technical sections of `desktop/macos/AGENTS.md`/e2e docs.
- **Exact focused verification:** from `desktop/macos`, run `./scripts/dev-feedback.py --once swift 'LoggerPermissionsTests'`, `./scripts/dev-feedback.py --once swift 'SingleInstanceGuardTests'`, `bash tests/test-automation-token-path.sh`, `bash tests/test-omi-macos-dev.sh`, `bash tests/test-cleanup-omi-tcc.sh`, and `python3 -m pytest tests/test_qualification_runner_self_clean.py`; run cache and harness contract tests from the refreshed inventory.
- **Deletion/simplification enabled:** Delete duplicated Omi path constructors and dangerous Omi cleanup acceptance. One target resolver feeds runtime and test tools; static Omi sentinels remain only as explicit rejection fixtures.
- **Stop conditions:** Stop if any test touches host TCC, real Omi cache/log/defaults, a production app, or an unproven cleanup path; if a log includes raw owner/content/token data; or if a cleanup helper cannot prove exact target provenance.

### Cycle 9 — bind login, TCC, updater, and runtime self-install to the owned identity

- **RED:** Through injected bundle metadata, `SMAppService`, update policy, filesystem, clock/defaults, and relaunch scheduler, assert: only approved stable/Beta identities can register login; named/preview cannot; TCC identity equals the current target bundle with no import/reset; named/preview cannot update; Beta remains Beta; and every IR-929 mounted/translocated, same/newer, newer, staging-failure, quarantine, retry-loop, and relaunch-scheduling case uses the current target bundle filename and approved guard identity.
- **Why it fails now:** Family predicates and installer copy/log/skip identities are Omi-derived; current focused tests use Omi bundle filenames/IDs; update/login decisions depend on duplicated Omi classification.
- **Minimum GREEN:** Route login/update/installer decisions through the Cycle 3 identity; make installer destination and guidance derive from `Bundle.main.bundleURL.lastPathComponent`/resolved display seam; replace the skip variable from G2; preserve the existing state machine exactly. Keep app-group absent and expose no TCC migration API.
- **Retained behavior:** S-17 completion/settings login policy and non-production refusal; update channel and activity gates; all IR-929 install/no-downgrade/atomicity/quarantine/relaunch/loop/fallback behavior; current-process termination only after a scheduled relaunch.
- **Expected change surface:** `LaunchAtLoginManager.swift`, `AppBuild.swift`, updater callers/tests, `AppInstaller` owning file/tests, `OmiApp` launch comments/callers, Info/config keys needed for derived identity, and technical guidance.
- **Exact focused verification:** from `desktop/macos`, run `./scripts/dev-feedback.py --once swift 'SBOnboardingLaunchAtLoginCompletionTests'`, `./scripts/dev-feedback.py --once swift 'RestartRelaunchCommandTests'`, and `./scripts/dev-feedback.py --once swift 'UpdateRelaunchWindowPolicyTests'`; run other refreshed S-17 login/relaunch policy filters; then run `./scripts/dev-feedback.py --once swift 'DesktopUpdatePolicyManagerTests'`, `./scripts/dev-feedback.py --once swift 'AppBuildBetaIdentityTests'`, `./scripts/dev-feedback.py --once swift 'ExternalPreviewBuildTests'`, and `./scripts/dev-feedback.py --once swift 'AppInstallerTests'`.
- **Deletion/simplification enabled:** Remove installer Omi literals, the old skip key, duplicated update/login prefix checks, and any app-group placeholder. S-29 can later supply signed values without reopening behavior.
- **Stop conditions:** Stop if a named build can register login or consume Sparkle, if a failure exits the running app, if an existing installed target is removed before staging succeeds, if visible final copy must be chosen, or if the change enters feed/sign/notarization/release infrastructure.

### Cycle 10 — make named-bundle seeding and cleanup target-local only

- **RED:** Under a temporary HOME and fake installed-app catalog, run the real app-config/run seed decisions for `omi-wave5-s28`. Provide both an owned canonical-dev profile and synthetic Omi sentinels. Assert clean-start performs no source reads; optional parity seeding reads only the owned canonical-dev bundle/domain/services/root; auth/settings/Rewind snapshots land only in the target named profile; and cleanup can remove only the exact disposable target while leaving foreign/protected fixtures untouched.
- **Why it fails now:** `run.sh` and seed helpers default to Omi Dev, `com.omi.desktop-dev`, Omi Keychain bases, and `Application Support/Omi`; `omi-rewind-seed.sh` explicitly reads that root; cleanup/TCC tools guard Omi prefixes.
- **Minimum GREEN:** Make the Cycle 3/4 target identity the only default source/target, make clean start explicit and first-class, adapt seed service/database/root names, and fail closed when owned source provenance cannot be proven. Delete Omi fallback searches. Preserve consistent SQLite snapshotting for opt-in seeding between two identities of this product.
- **Retained behavior:** Per-worktree/named isolation, no production-bundle seeding, curated defaults allowlist, Keychain ACL-safe token handoff, coherent SQLite backup, target-exists protection, forced-seed preservation, status/dry-run, and source attachment/data preservation.
- **Expected change surface:** `run.sh`, app-config consumers, `omi-auth-dump.sh`, `omi-auth-seed.sh`, `omi-settings-seed.sh`, `omi-rewind-seed.sh`, `omi-macos-dev`, e2e technical instructions, and their shell tests. Script filenames can remain until S-30 unless they are themselves persisted/mutable identity.
- **Exact focused verification:** `cd desktop/macos && bash tests/test-app-config.sh`; `bash tests/test-omi-auth-seed-acl.sh`; `bash tests/test-settings-seed.sh`; `bash tests/test-rewind-seed.sh`; `bash tests/test-omi-macos-dev.sh`; run `run.sh` decision tests with temporary HOME and no app launch.
- **Deletion/simplification enabled:** Remove Omi source discovery/defaults, Omi root fallback, and legacy seed flags that have no target-local meaning. Keep one clean mode and one explicitly owned source-to-named mode.
- **Stop conditions:** Stop if any script invokes `mdfind`, `defaults`, `security`, SQLite, filesystem copy, or cleanup against an Omi identity; if clean mode reads any seed source; or if a destructive target is derived from a loose prefix rather than exact target metadata.

### Cycle 11 — prove reset, sign-out, owner switch, and same-identity reinstall preservation

- **RED:** In a temporary target namespace, create owner A and B fixtures across every retained S-10–S-15 store plus defaults/Keychain/install ID. Drive Settings reset, status-menu reset, automation reset, both sign-out entries, A→B→A switching, app-process quit/reopen, and simulated same-bundle uninstall/reinstall. Assert exact setup/auth effects, stopped capture, ordinary data preservation, owner isolation, stable target installation ID across own reinstall, and zero external-boundary calls carrying an Omi identity.
- **Why it fails now:** The combined lifecycle has never been asserted against a clean new identity; path/default/service construction is Omi-derived, and seed/cleanup helpers can read or target Omi even though individual owner/reset tests are green.
- **Minimum GREEN:** Fix only integration seams revealed by the RED test: ensure every store re-resolves target identity and effective owner, keep reset/sign-out allowlists exact, and make reinstall reopen the same owned root without an import step. Do not add a broad “clear all product data” helper.
- **Retained behavior:** S-08 immediate sign-out and token cleanup, S-17 setup-journal/reset behavior, all ordinary owner-local data, TCC grants, store schemas, capture-stop ordering, runtime-owner notifications, and account-switch generation fencing.
- **Expected change surface:** Cross-domain lifecycle integration tests first; production changes only in a proven stale identity/owner cache or duplicated path consumer identified by the failing behavior.
- **Exact focused verification:** Run the new `CleanInstallationLifecycleTests`; `EffectiveOwnerDatabaseBoundaryTests`; S-08 sign-out lifecycle filters; S-17 `OnboardingPersistenceClearingTests`/reset filters; agent runtime-owner, Chat attachment, Memory, Task, Goal/Focus, and Rewind owner-switch filters from the current inventory.
- **Deletion/simplification enabled:** Remove stale cached root/domain constructors and redundant per-store reset branches only after the integrated test proves the shared owner/identity seam.
- **Stop conditions:** Stop if green requires deleting ordinary user data, rotating an owned same-install identity, resetting TCC/login items, weakening owner generations, changing account-deletion behavior, or constructing a real Omi fixture.

### Cycle 12 — close repository residue and exercise `omi-wave5-s28`

- **RED:** Run the complete Section 13 forbidden-residue classification and Section 15 acceptance matrix on the exact final tree. The initial red condition is any unclassified live Omi namespace, any target identity mismatch, any named-bundle lifecycle failure, any foreign-boundary call in hermetic evidence, or any retained component regression—not a raw count of the word `Omi`.
- **Why it fails now:** The current tree contains live Omi bundle/storage/Keychain/log/cache/test identifiers, two takeover paths, Omi seed defaults, and no new-identity install/upgrade/reinstall evidence.
- **Minimum GREEN:** Migrate the remaining S-28-owned callers, regenerate only affected generated outputs, update technical component/e2e documentation and behavior tests, classify legitimate S-29/S-30/history residue, then exercise the real named bundle and disposable local DMG without touching production apps or foreign data.
- **Retained behavior:** Every invariant in Section 9, full desktop component behavior, exact S-29/S-30 deferrals, no provider transaction, and no production app/data mutation.
- **Expected change surface:** Residual S-28-owned technical identity callers, generated descriptions/tests, `desktop/macos/AGENTS.md`, relevant e2e technical docs, and one user-visible changelog fragment only if implementation changes a user-facing behavior before S-30.
- **Exact focused verification:** Run all commands in Section 14, then the full matrix in Section 15 using `OMI_APP_NAME=omi-wave5-s28`; rerun the requirements validator and `git diff --check` at the final commit.
- **Deletion/simplification enabled:** Delete obsolete compatibility tests/helpers and close every unclassified live S-28 residue. Do not rewrite historical artifacts or absorb release/rebrand work just to make a search empty.
- **Stop conditions:** Stop on any production Omi target, real Omi path/service/domain read, missing G2/G3 input, unowned S-29/S-30 residue, sensitive evidence, stale SHA, component/preflight failure, or inability to exercise the real named-bundle path safely.

## 12. Cross-slice ownership and handoffs

| Slice / owner | Input consumed by S-28 | Output or boundary handed onward |
|---|---|---|
| S-08 | Final auth/session/sign-out contract; approved Firebase/Apple/Google bundle and callback registrations; Team+bundle Keychain behavior. | New bundle/defaults/Keychain identity without changing auth UX or server authority. If registrations are missing, G3 remains blocked. |
| S-10 | Owner-scoped local Conversation/Rewind GRDB authority and effective-owner fence. | Same schemas/behavior beneath target root; no cloud or Omi data migration. |
| S-11 | Local Chat journal, agent runtime, attachments, owner switching, and continuity semantics. | Clean runtime/database/attachment paths and cross-process identity contract. |
| S-12 | Local Memory authority and database lifecycle. | Same Memory records/cascades under the target owner database. |
| S-13 | Local Task/action-item authority and source links. | Same Task behavior under the target owner database; no reset wipe. |
| S-14 | Local Goals/Focus/profile/notification/Home-cache authorities. | Clean target paths/default domain while preserving owner and presentation contracts. |
| S-15 | Local Rewind capture/media/search authority and cloud-copy retirement. | Clean database/media roots; the Omi importer is removed while current-database recovery remains. |
| S-17 | Narrow onboarding/defaults/reset/sign-out and login-item policy. | New defaults/login identity; non-production refusal retained. Signed registration evidence stays later. |
| S-29 | No release implementation is consumed. It may supply the exact signed app-group/Team/provider values if genuinely required. | One approved identity tuple/API, exact stable/Beta/dev/named/preview bundle contract, local paths/services, installer behavior, and named-bundle evidence. S-29 must use these rather than recreate namespace logic. |
| S-30 | No final visible product name is assumed. | Bundle/path-derived copy seams and a classified list of visible/historical Omi residue for the final truth pass. |
| S-31 / BL-001 | No provider or production qualification is needed for repository work. | Exact final SHA, local component proof, named-bundle evidence, and explicit open release/provider/physical/operational lanes. |

Shared-file rule: `OmiApp.swift`, `AppBuild.swift`, `DesktopLocalProfile.swift`, `AuthService.swift`, `DesktopKeychainStore.swift`, `ClientDeviceService.swift`, `RewindDatabase.swift`, `AgentRuntimeProcess.swift`, `run.sh`, Info/plist/entitlement files, updater/login code, automation/qualification scripts, and component guides are high-collision trunks. Refresh every caller after predecessor integration, preserve already-landed authority, and avoid an old/new adapter. If S-29 or S-30 has already edited one of these files when execution begins, rebase and split ownership by behavior rather than overwrite their work.

## 13. Repository residue-search strategy

Residue closure is classification, not a blind zero-result goal. Run searches against production sources, scripts, tests, e2e docs, configuration, and generated surfaces. For every result, record file/symbol, runtime reachability, namespace kind, owner, and disposition in the PR evidence.

### 13.1 Forbidden live behavior searches

```bash
git grep -n -I -E 'Application Support/Omi|Application Support", "Omi|Omi Dev Bundles|OmiDesktop|/private/tmp/omi|/tmp/omi' -- desktop/macos ':!desktop/macos/CHANGELOG.json' ':!desktop/macos/changelog/**'
git grep -n -I -E 'com\.omi\.(computer-macos|desktop-dev|preview|desktop\.firebase-rest-session|client-device-id)|group\.com\.omi|me\.omi\.' -- desktop/macos ':!desktop/macos/CHANGELOG.json' ':!desktop/macos/changelog/**'
git grep -n -I -E 'Omi Computer\.app|cleanupLegacyAppBundles|migrateAppName|mayRunLegacyStableAppCleanup|shouldMigrateLegacyStorage|migrateFromLegacyPathIfNeeded' -- desktop/macos
git grep -n -I -E 'omi-agentd\.sqlite3|omi\.db|\.omi_running|omi-single-instance|omi-automation-|OMI_SKIP_INSTALL_GATE' -- desktop/macos
git grep -n -I -E 'defaults (read|write|delete|export|import).*com\.omi|security .*com\.omi|tccutil .*com\.omi|runningApplications.*com\.omi' -- desktop/macos
rg -n 'DesktopLocalProfile\.(applicationSupportURL|cachesURL)|UserDefaults\(suiteName:|SecItem(CopyMatching|Add|Update|Delete)|SMAppService|SUFeedURL|SUPublicEDKey' desktop/macos/Desktop desktop/macos/scripts desktop/macos/run.sh
```

Expected live result policy after S-28:

- No production source may construct or access an Omi bundle, root, defaults, Keychain, process, login, TCC, log, cache, database, or runtime identity.
- No mutable cleanup/seed helper may accept an Omi identity. A clearly synthetic Omi literal is allowed in a hermetic rejection test only.
- Database/log/test strings must resolve through the approved target contract where identity matters. Low-level temporary fixture names are allowed when they do not model a production namespace.
- S-29-owned feed/sign/release values and S-30-owned visible copy remain classified, not silently changed.

### 13.2 New-identity consistency searches

After G2 supplies exact literals, search each approved bundle prefix, storage component, Keychain base, database filename, log/token/cache prefix, and installer skip key. Every intended production consumer must either call the typed resolver or be a necessary build-time input covered by parity tests. Flag duplicated family predicates such as ad hoc `hasPrefix`, manual Application Support construction, raw `$HOME`, or reconstructed automation/database paths.

### 13.3 Allowed residue classes

1. Bootstrap requirements, deletion maps, and this plan describing the source system or forbidden sentinel.
2. Historical changelogs, release notes, and provenance that must remain truthful.
3. Hermetic tests whose explicit purpose is to prove Omi identities are rejected/untouched; they use injected temporary roots, never host paths.
4. S-29 release/sign/feed/public infrastructure awaiting its owned cycle.
5. S-30 visible naming, icon/resource filenames, product prose, privacy/legal truth, and broad operator command naming.
6. The requested local app name `omi-wave5-s28` in S-28 plan/evidence; its resulting bundle/storage identity must still be the approved new namespace.

No unexplained result is accepted. If a live result's owner cannot be determined, stop rather than delete it opportunistically.

### 13.4 Static guard policy

A narrow static checker may prevent reintroduction of the two real takeover classes or direct Omi production roots. Before such a checker may land, its PR must cite the real merged PR or incident whose recurrence it would have caught and explain why no existing shared primitive, target dependency, access-control boundary, typed API, or behavioral contract can enforce the rule. IR-931 and the current `RewindDatabase`/`OmiApp` violations provide source grounding but do not by themselves satisfy the repository's real-instance eligibility rule. An eligible checker must say it is a static tripwire, have both local and CI lanes in `.github/checks-manifest.yaml`, and ship with behavioral tests from Cycles 1 and 2. If no qualifying merged PR/incident exists, omit the checker. Do not assert source line order or require the historical word `Omi` to disappear repository-wide.

## 14. Focused and component-level verification commands

These commands are required during implementation and closeout. Record their exact output, duration where useful, and final SHA. None is claimed to have passed in this planning turn.

### 14.1 Focused Swift RED/GREEN loop

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'OmiTakeoverIsolationTests'
./scripts/dev-feedback.py --once swift 'LegacyAppTakeoverIsolationTests'
./scripts/dev-feedback.py --once swift 'DesktopProductIdentityTests'
./scripts/dev-feedback.py --once swift 'DesktopLocalProfileTests'
./scripts/dev-feedback.py --once swift 'DesktopStorageIdentityTests'
./scripts/dev-feedback.py --once swift 'AppBuildBetaIdentityTests'
./scripts/dev-feedback.py --once swift 'ExternalPreviewBuildTests'
./scripts/dev-feedback.py --once swift 'AppInstallerTests'
./scripts/dev-feedback.py --once swift 'SBOnboardingLaunchAtLoginCompletionTests'
./scripts/dev-feedback.py --once swift 'RestartRelaunchCommandTests'
./scripts/dev-feedback.py --once swift 'UpdateRelaunchWindowPolicyTests'
./scripts/dev-feedback.py --once swift 'AuthTokenStorageTests'
./scripts/dev-feedback.py --once swift 'ClientDeviceServiceTests'
./scripts/dev-feedback.py --once swift 'EffectiveOwnerDatabaseBoundaryTests'
./scripts/dev-feedback.py --once swift 'RewindDatabaseLifecycleTests'
./scripts/dev-feedback.py --once swift 'AgentRuntimeProcessTests'
./scripts/dev-feedback.py --once swift 'LoggerPermissionsTests'
./scripts/dev-feedback.py --once swift 'SingleInstanceGuardTests'
./scripts/dev-feedback.py --once swift 'CleanInstallationLifecycleTests'
```

Add the exact existing S-08, S-10–S-15, and S-17 sign-out/reset/owner-switch/recovery filters identified by the refreshed caller inventory. Run one failing behavior, make the minimum change, rerun it green, then run the adjacent retained filters before moving to the next cycle.

### 14.2 Shell, Python, and agent-runtime contracts

```bash
cd desktop/macos
bash tests/test-app-config.sh
bash tests/test-launch-env-forwarding.sh
bash tests/test-automation-token-path.sh
bash tests/test-omi-auth-seed-acl.sh
bash tests/test-settings-seed.sh
bash tests/test-rewind-seed.sh
bash tests/test-omi-macos-dev.sh
bash tests/test-cleanup-omi-tcc.sh
python3 -m pytest tests/test_qualification_runner_self_clean.py

cd agent
npm test -- sqlite-store.test.ts artifact-storage.test.ts chat-continuity-invariant.test.ts
npm run build
```

Use temporary HOME/system-directory injections supplied by the tests. A shell test is invalid if it invokes host `defaults`, `security`, TCC, `/Applications`, or an Omi root without a fake command/path boundary.

### 14.3 Formatting, generated outputs, and full component gate

```bash
test -x "$(git rev-parse --git-path hooks)/pre-commit" && echo OK
desktop/macos/scripts/swift-format-wrapper.sh format -i <changed-swift-files>
cd desktop/macos && ./test.sh
```

Run any existing generated-capability, plist, e2e-flow-coverage, shell formatting/lint, and package tests affected by the final diff. Do not hand-edit a generated file without running its owning generator/check.

### 14.4 Repository gates

```bash
cd <repository-root>
make preflight
scripts/pr-preflight --suggest
scripts/pr-preflight --pr-body-file /tmp/s28-pr-body.md
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
git status --short --branch
git diff --stat origin/main...
```

If the intended commit/PR uses `fix:`, declare and validate the suggested `Failure-Class` exactly as root guidance requires. A new guard must be registered in `.github/checks-manifest.yaml` rather than added to a one-off workflow.

Final ledger expectation remains exactly `714 indexed rows, 714 detailed sections, all reviewed`. Any other count or validation failure is a stop, not a plan-doc edit to force the count.

## 15. Named-bundle and installation-lifecycle acceptance

### 15.1 Safety setup

Acceptance uses only the disposable app name `omi-wave5-s28`, its G2-derived bundle ID, an S-28-owned canonical dev source when optional seeding is being tested, test accounts, synthetic content, and test-owned directories. Derive and record the bundle ID through `scripts/app-config.sh`; do not hard-code an unapproved value into this plan.

Before launch, prove the selected app path and bundle ID are disposable and accepted by the re-owned named-bundle manager. Do not list, open, hash, snapshot, copy, or mutate real Omi data as a “before” measurement. Non-access is proven by hermetic recording adapters plus target-local runtime evidence, not by reading the foreign store.

Never launch, kill, quit, reset, seed from, remove, or automate `/Applications/Omi.app`, `/Applications/Omi Beta.app`, bundle IDs `com.omi.computer-macos` / `.beta`, or their data. Cleanup after acceptance removes only the exact assigned named `.app`, process, log/token files, and test-owned profile when the plan step explicitly calls for it and provenance is revalidated.

### 15.2 Required matrix

| Case | Real action | Required evidence |
|---|---|---|
| Clean named install | Build and launch with `OMI_APP_NAME=omi-wave5-s28` and clean-start seeding disabled/empty. | Exact SHA/bundle/path; runtime manifest shows only target roots; fresh defaults/install ID/database; no foreign-boundary call in hermetic companion proof. |
| Finder quit/reopen | Quit only the named bundle and reopen the installed `/Applications/omi-wave5-s28.app`. | Same bundle, resolved root, owner, install ID, and retained records without launcher env; single-instance behavior correct. |
| Own first-build upgrade | Preserve a test fixture made by build A of the approved identity, build/install later build B of the same named identity, and reopen. | Schema upgrade succeeds; ordinary records/media/journal survive; install ID remains stable; no import scan. |
| Same/newer no downgrade | Launch an equal/older disposable local-DMG copy while a same/newer named copy is installed. | Existing target remains byte/version authoritative; quarantine clear/relaunch path selects it; no overwrite. |
| Newer atomic install | Launch a newer disposable local-DMG copy. | Same-volume stage precedes atomic replace; destination is current bundle filename; relaunch is scheduled before source exit. |
| Install failure/loop | Inject copy/replace/relaunch failures and third gate attempt in focused behavior tests; use real UI only where safe. | Existing install preserved, current app remains running on failure, manual guidance is path-derived, counter resets/caps at two. |
| Reset | Exercise Settings, status-menu, and non-production automation reset on the named bundle. | Only approved setup state clears; capture stops; ordinary owner stores, install ID, Keychain auth boundary, and TCC remain. |
| Sign-out | Exercise both retained sign-out entries. | Session/drafts/telemetry cleanup remains exact; ordinary owner local stores remain; no foreign defaults/Keychain access. |
| Account switch | Sign in as test owner A, create one fixture per retained store, switch to B and create distinct fixtures, then switch back. | No cross-owner visibility/commit; A records return intact; database/runtime actors retarget at generation boundaries. |
| Uninstall/reinstall | Remove only `/Applications/omi-wave5-s28.app` through the provenance-safe named tool, leave its target data, reinstall the same identity, and relaunch. | Own retained data/install identity reopen as specified; no Omi path/process/service/default/TCC activity. |
| Optional target-local seed | Explicitly seed from the owned canonical development identity into the disposable target. | Curated auth/settings and coherent Rewind snapshot only; source and target are both approved product identities; target isolation after copy. |
| Clean-start no seed | Repeat with every seed disabled. | No `mdfind`, defaults, Keychain, SQLite, or filesystem source lookup for Omi or any other app; empty target starts normally. |

### 15.3 Disposable local-DMG installer exercise

After focused `AppInstallerTests` are green, package the already built `omi-wave5-s28.app` into a disposable local read-only disk image solely to exercise mounted-volume first launch. This does not use or modify S-29's release DMG workflow and proves nothing about signing/notarization. Validate the mounted source and `/Applications` destination both carry the exact approved named bundle ID before opening. Exercise equal/older and newer build cases using synthetic numeric versions; remove only the assigned disposable artifacts afterward.

App Translocation is covered behaviorally through injected bundle paths unless a safe OS-supported disposable exercise is available. Do not weaken Gatekeeper, production TCC, or system security settings to force translocation.

### 15.4 Evidence bundle

Record final SHA, build versions, derived bundle ID, app path, resolved target paths, test owner aliases (not raw IDs), relevant sanitized log excerpts, test command outputs, and cleanup receipt. Evidence must not include auth tokens, API responses, raw content, real Omi path metadata, Keychain values, or user-identifying data. Named-bundle evidence is local S-28 proof only; it is not signed-candidate, provider, release, or final all-waves proof.

## 16. Repository closure versus later release and operational closure

### 16.1 S-28 repository closure

S-28 may be reported repository-closed only when:

- all twelve cycles are green on the exact final commit;
- the approved identity tuple and S-08 registrations used by the code are recorded without secrets;
- the full desktop component suite, repository preflight, ledger validator, formatting/diff checks, and classified residue pass;
- `omi-wave5-s28` completes the clean/upgrade/reset/sign-out/account-switch/reinstall matrix;
- the disposable local-DMG IR-929 path is exercised or any OS-only limitation is named without implying success;
- technical docs/tests move with changed commands and paths;
- an independent review approves the final diff if the team intends to use the repository's peer-approved auto-merge exception; and
- the report explicitly states that no production Omi app/data and no external release/provider state was touched.

Execution evidence belongs in commits/PR description and the later combined closeout artifact owned by the roadmap; this planning document ends with its completion checklist.

### 16.2 S-29 release closure

S-29 later proves the owned stable/Beta/preview identities in signed/notarized artifacts, correct entitlements and Team ID, Sparkle feed/key/update behavior, public download destinations, preview publish/replace/pointer delist with immutable evidence retained, promotion/rollback, and release pipeline. A signed production-family login-item/TCC exercise also belongs there or S-31. S-28 hands S-29 a stable identity contract; it does not pre-claim those results.

### 16.3 S-30 truth closure

S-30 replaces remaining visible product copy, icon/resource identity, broad docs, privacy/legal claims, and public-facing paths after S-28 and S-29 make the underlying behavior true. S-28 must leave those surfaces replaceable and must not hard-code a provisional brand into layout or storage logic.

### 16.4 S-31 / operational closure

BL-001's final provider/continuity matrix, physical-device evidence, hosted CI, signed release acceptance, deployment, and any external operational change remain separate. BL-002/live-resource work is unrelated to the local namespace mutation and remains separately authorized. No deploy, production-app action, customer-data action, billing change, IAM change, update promotion, or external deletion is authorized by this document.

## 17. Risks, ambiguities, gates, and explicit stop points

| Risk or ambiguity | Required control | Stop when |
|---|---|---|
| Exact new identity is absent from the current checkout | G2 reviewed tuple; never infer from copy/email/repo name. | Any production literal would be guessed. |
| Firebase/OAuth bundle registrations do not match new IDs | Consume S-08 owned values and plist/scheme parity tests. | G3 values are absent or credentials would be fabricated. |
| “Preserve stores” is misread as “copy Omi” | Preserve code/schema/lifecycle under a fresh target root; Cycle 1 foreign sentinel test. | Any path reads or migrates Omi bytes. |
| A no-touch test itself touches Omi | Inject filesystem/process/defaults/Keychain/TCC boundaries and temporary roots. | Test proposes a real Omi snapshot, hash, query, or cleanup. |
| Installer and takeover deletion are conflated | Separate Cycles 2 and 9; retain IR-929 tests before removing old-app code. | Normal current-bundle installation/relaunch would be weakened. |
| Bundle classifiers drift | One Swift identity authority plus shell parity tests; unknown fails closed. | A caller reimplements a prefix or stable fallback. |
| New bundle loses auth/TCC/login continuity | Fresh identity is intended; own-build continuity is tested; S-29 owns signed proof. | Someone proposes importing Omi grants/Keychain/defaults to hide the fresh identity. |
| App group is added “for completeness” | Explicit nil and entitlement-absence test until a real consumer exists. | No retained consumer and approved ID can be named. |
| Owner switch leaks stale store/runtime state | Retain generation fencing and integrated A→B→A test. | Any store cannot bind its reads/writes to effective owner. |
| Database filename/root rename broadens into schema redesign | Change resolution and fixtures only; keep schemas/migrations. | Expected domain data behavior changes without an independent requirement. |
| Cleanup tools can target protected apps/data | Exact derived target, bundle metadata, dry-run, and provenance checks. | Target is ambiguous, foreign, stable Omi, or broader than the assigned named bundle. |
| Seed scripts silently import foreign state | Clean start first; optional seed only from approved canonical dev identity. | A fallback invokes Omi path/domain/service discovery. |
| UserDefaults/Keychain compatibility layer sneaks in | Same target-domain migration only; no old base/domain query. | Proposed old/new alias or dual-read is needed for an unreleased population. |
| Update identity crosses into release infrastructure | S-28 changes classifier only; S-29 owns feeds/keys/artifacts. | Work needs Codemagic, Developer ID, notarization, appcast, GCS/GitHub release, or promotion changes. |
| Visible rebrand expands scope | Derive functional paths/guidance; classify remaining copy for S-30. | Final name, icon, privacy/legal, or broad copy decision is required. |
| Static residue is mistaken for behavior | Behavioral RED first; static guard only supplemental and manifest-wired. | A cycle's only evidence is text/source order. |
| Shared trunks changed after planning | Rebase/integrate, repeat inventory, preserve user changes and predecessor authority. | Ownership has materially changed or conflicts cannot be resolved surgically. |
| Evidence leaks sensitive state | Synthetic data, aliases, sanitized logs, no real Keychain/content dumps. | Artifact contains tokens, raw user IDs/content, API responses, or foreign path metadata. |
| Named bundle is mistaken for release proof | Report evidence lanes separately. | Anyone uses it to claim signed/notarized/provider/production closure. |

## 18. Final completion checklist

### Baseline and authority

- [ ] Execution ran `make setup`, verified the pre-commit hook, integrated current `origin/main` without switching/renaming branches, recorded exact SHA, and refreshed all inventories.
- [ ] IR-929, IR-931, `PRODUCT.md`, deletion-map S-28, Waves 3–4 closeout, and S-08/S-10–S-15/S-17 handoffs were rechecked against the final tree.
- [ ] G2 exact technical identity tuple and G3 registered auth/callback values are recorded; no literal was inferred.
- [ ] App-group absence is explicit and tested, or a real consumer plus approved owned identifier caused the plan to be revised before implementation.

### Foreign non-access and clean identity

- [ ] Behavioral tests prove zero foreign filesystem/process/defaults/Keychain/TCC calls using synthetic recording boundaries.
- [ ] The Rewind Omi/anonymous importer and all migration-only move/merge/checkpoint cleanup are deleted; ordinary selected-database WAL/crash recovery remains.
- [ ] The Omi old-app search, process enumeration/termination, delayed delete, Trash fallback, policy, and exclusive tests are deleted.
- [ ] No production fallback, seed, cleanup, defaults, service, log, cache, database, runtime, or bundle path can resolve into an Omi namespace.
- [ ] No compatibility alias, dual read/write, import wizard, generic killer, or inherited data migration was added.

### Owned namespace model

- [ ] One typed Swift authority classifies stable, Beta, dev, named, preview, invalid, and app-group state; `AppBuild` and storage use it.
- [ ] Shell build configuration matches the reviewed tuple and derives the exact approved bundle/scheme for `omi-wave5-s28`.
- [ ] Application Support, caches, databases, runtime, attachments, defaults, Keychain, logs, locks, tokens, manifests, login/update/TCC, and test profiles use the owned identity.
- [ ] Unknown/malformed identities fail before acquiring stable privileges or writable stable roots.
- [ ] Keychain retains Team+bundle scope and silent behavior; installation identity starts fresh and survives own upgrades/reinstall.

### Retained behavior

- [ ] S-10–S-15 schemas, store behavior, artifacts, crash recovery, and owner-generation fences remain green under the new paths.
- [ ] Agent runtime/journal and attachments retain S-11 continuity, owner isolation, and source-file preservation.
- [ ] S-08 auth/session/sign-out and S-17 reset/login behavior remain exact; ordinary data and system TCC survive reset/sign-out.
- [ ] IR-929 detection, no-downgrade, staging/atomic replace, quarantine, relaunch ordering, two-attempt guard, manual fallback, and failure preservation all pass.
- [ ] Named/preview automation/update/login restrictions and stable/Beta channel distinctions remain exact.

### Harness and real acceptance

- [ ] Named seeding defaults only to this product's approved canonical dev identity; clean start performs no source discovery.
- [ ] Cleanup/TCC/profile tools accept only exact approved disposable target identities and refuse Omi/protected/ambiguous targets.
- [ ] `omi-wave5-s28` passed clean install, Finder reopen, own-build upgrade, reset, sign-out, A→B→A switch, uninstall/reinstall, clean-start, and optional own-source seed cases.
- [ ] A disposable local DMG exercised the safe IR-929 path, with any App-Translocation OS limitation reported precisely.
- [ ] Acceptance never launched, terminated, deleted, reset, enumerated for data, or otherwise mutated a production Omi app or its local state.

### Verification, residue, and handoff

- [ ] Every cycle captured genuine RED, minimum GREEN, and adjacent retained proof; mocks/fakes were limited to true external boundaries.
- [ ] Focused Swift, shell/Python, agent-runtime, generated, component, formatting, `make preflight`, and PR-preflight gates passed at the final SHA.
- [ ] `python3 bootstrap-scaffold/validate-requirements-ledger.py` passed with exactly 714/714 and `git diff --check` passed.
- [ ] Every live identity residue is migrated or assigned to S-29/S-30/history with no unexplained result; any static guard is behavioral-test-backed and manifest-wired.
- [ ] Technical component/e2e docs and any required changelog moved with behavior; no broad S-30 copy rewrite landed.
- [ ] S-29 received the exact identity contract and open signed/release gates; S-30 received the visible residue list; S-31 received exact-SHA local/named evidence and open qualification lanes.
- [ ] Final reporting separates repository, named-bundle, signed-release, provider/physical, hosted-CI, and operational evidence; no unrun lane is implied green.
- [ ] No commit, push, PR, merge, production app action, deploy, customer-data mutation, billing/IAM change, or external release mutation occurred without its separate authorization.
