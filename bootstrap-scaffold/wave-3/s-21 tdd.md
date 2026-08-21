# S-21 — Simplify navigation, Settings, and the surviving Home shell — TDD plan

## 1. Title and slice identity

| Field | Value |
|---|---|
| Wave | **3** |
| Slice | **S-21** |
| Name | **Simplify navigation, Settings, and the surviving Home shell** |
| Type | UI convergence after product deletion; not a UI redesign |
| Planning baseline | Wave 2 closeout `711269baf5e653bd62132688998732207f11dd3c` |
| Product authority | [`PRODUCT.md`](../../PRODUCT.md) and the concrete tests beside each retained owner |
| Roadmap authority | [`../deletion-map.md`](../deletion-map.md) |
| Requirements authority | [`../requirements-challenge.md`](../requirements-challenge.md) |
| Assigned requirements | IR-191 through IR-255, IR-500 through IR-530, IR-616, IR-659, IR-681, IR-930, IR-933 |
| Future acceptance bundle | `omi-wave3-s21` (`com.omi.omi-wave3-s21` at the current pre-S-28 bundle scheme) |
| Primary code owner | macOS shell, Settings presentation/search, Home presentation/lifecycle, and local desktop automation |

This document plans one implementation slice. It does not authorize product code, provider, deployment, or live-resource changes while the plan is being written.

## 2. Planning status and pinned baseline

**Status:** blocked. The plan is source-grounded, but implementation waits for S-20 and the predecessor shapes in §5. S-09 gates only Cycle 4's Privacy/Settings acceptance; its live owned-project proof does not block unrelated S-21 cycles. Do not implement a temporary shell around a missing result.

The planning workspace was checked with the required commands:

```text
git merge-base --is-ancestor 711269baf5e653bd62132688998732207f11dd3c HEAD
  -> exit 0
git rev-parse HEAD
  -> 711269baf5e653bd62132688998732207f11dd3c
git status --short --branch
  -> ## audit-wave-2-slices...origin/audit-wave-2-slices
```

`HEAD` is exactly the Wave 2 closeout: `git diff 711269baf5e653bd62132688998732207f11dd3c..HEAD` is empty and no additional product change was present before this plan was created. The requirements validator passed at planning time with **714 indexed rows and 714 detailed sections**.

Current baseline facts that matter to execution:

- S-10, S-11, S-15, S-16, and S-17 are repository-integrated. The Wave 2 closeout completed the S-12, S-13, and S-14 repository dependency for Wave 3.
- S-06 and S-07 repository deletion is integrated. Apps, Brain Map, broad indexing, connector UI, and BYOK must stay gone.
- S-18 is deliberately at `BILLING_MODE=disabled`. That checkpoint permits S-21 repository work but does not authorize Dodo credentials, provider construction, checkout, a paid release, or a transaction.
- S-20 remains a hard predecessor. Its local-GRDB evidence path, retained transient GPT-5.1 classifier, and content-free durable enforcement result must be integrated before S-21 consumes the final Plan/Usage shell.
- S-09's repository consent/Privacy seam is a predecessor only for Cycle 4. The baseline still contains an inaccurate hard-coded Privacy status, stale disclosure content, no production consent control in the visible view, and an inverted PostHog automation projection. Those are S-09 work, not an invitation for S-21 to create another telemetry owner. S-09's live owned-project proof is separate operational acceptance.
- The closeout truthfully records 19 inherited Swift-suite failures and ten red Tier-2 integration flows. Establish an execution-HEAD baseline to diagnose them, but close that debt before S-21 closure: the official affected component suite must pass.

Before Cycle 1, run `make setup`, fetch the integrated predecessor head, rebase the current feature worktree without switching branches, rerun the ledger validator, and refresh every inventory in §§6, 7, and 13. If the tree is materially different, update this plan's execution notes in the PR rather than following stale line-level assumptions.

## 3. Outcome

S-21 leaves one understandable Mac shell over the already-decided product:

```text
primary navigation
  -> Home
  -> Memory (Memories + Conversations)
  -> Tasks
  -> Insights (Insights + Focus)

persistent or utility reachability
  -> Capture and Listening controls
  -> Settings
  -> Rewind (retained global command and product routes)
  -> Permissions when the owning flow requires it
```

Home remains the default and the sole ordinary Chat host. Settings exposes only real retained controls. Every search result reaches a mounted control. Every retained counter comes from the current owner's local authority. Deleted products cannot be reached through UI, menus, numbered commands, notification routes, raw indices, local automation, stale preferences, or restored state.

The slice succeeds when:

1. the current top-bar/Home design is the only shell implementation;
2. Feature Tiers and every tier-driven redirect, lock, migration, statistic, and event are gone;
3. semantic **Chat** navigation opens Home's real Chat stage while obsolete raw route `2` fails closed;
4. Home observes only surviving owner-scoped stores and performs no rejected dashboard work;
5. Settings and About preserve all retained behavior while rejected cards, broken search rows, Help Center, and stale shell aliases are absent;
6. **Your Stats** is owner-fenced and entirely local for every retained count;
7. the exact retained navigation, shortcut, Escape, compact-layout, offline, restart, and account-switch behavior passes in `omi-wave3-s21`; and
8. `BILLING_MODE=disabled` remains literal and transaction-free.

This slice does **not** redesign Home, Settings, Tasks, Focus, Insights, Rewind, billing, telemetry, update behavior, onboarding, Chat semantics, PTT, or model behavior.

## 4. Authorizing requirements

The following register accounts for every assigned decision. A predecessor-owned decision is an entry/acceptance fence; S-21 changes it only where the decision explicitly assigns shell, search, About, stats, or convergence residue to this slice.

| Decisions | S-21 interpretation and owning cycle |
|---|---|
| IR-191, IR-192, IR-193, IR-194, IR-195, IR-196, IR-197, IR-198, IR-199, IR-200, IR-201, IR-202, IR-203 | Consume S-18/S-20's Account & Plan and quota result. Preserve trial/card/catalog/hosted-flow/usage behavior; verify rejected legacy/promotion/simulator/custom-change/reactivation/fallback/overage UI residue is absent. No provider work. Cycles 4 and 7. |
| IR-204, IR-205, IR-206, IR-207, IR-208, IR-209, IR-210, IR-211 | Consume S-09's truthful data-location card, retained disclosure, PostHog-only toggle, separate Sentry, Enhanced Diagnostics, Report Issue entrances, and Save Diagnostics. Delete only convergence/search residue after S-09 is green. Cycles 4 and 7. |
| IR-212, IR-213, IR-214, IR-215, IR-216, IR-217 | Verify predecessor deletion of Rescan Files, Browser Extension, Dev Mode, Workspace/project config, global CLAUDE.md, and Claude skills. Remove any surviving Settings/search shell only; do not recreate S-05/S-06 work. Cycle 4. |
| IR-218, IR-219, IR-220, IR-221, IR-222, IR-223, IR-224, IR-225, IR-226, IR-227, IR-228 | Keep Ask/Act, floating-bar visibility/background/drag/typed voice/screen sharing/voice/speed, font scale, reset-window action, and VAD behavior exactly. Ask Mode must be reachable under **Advanced AI Setup**; only the retired provider noun changes in the predecessor-owned transcription copy. Cycles 1, 4, and 7. |
| IR-229, IR-230, IR-231, IR-232, IR-233, IR-234, IR-235, IR-236 | Keep local notification controls and all reviewed Rewind settings/mode quirks; Daily Summary stays deleted. Cycles 4 and 7. |
| IR-237, IR-238, IR-239, IR-240, IR-241, IR-242 | Keep predecessor removal of phantom Rewind, generic Transcription, generic General, and rejected cloud-recording search entries; delete the still-broken **Sign Out** and generic **Plan and Usage** search rows. Cycle 4. |
| IR-243, IR-244, IR-245, IR-246, IR-247, IR-248, IR-249, IR-250 | Preserve manual/automatic/immediate Sparkle behavior, the authoritative retained activity gate, local update-channel choice, identity/version card, release link, post-update toast, and website row. S-29/S-30 own infrastructure, destinations, and rebrand. Cycles 4 and 7. |
| IR-251, IR-252, IR-253, IR-254, IR-255 | Delete external Help Center; rename the local shortcut to **Privacy & Data**; keep the simple Terms link; keep Crisp gone; delete the old Home/legacy sidebar compatibility family and audit the surviving shell. Cycles 2 and 4. |
| IR-500, IR-501, IR-502, IR-503, IR-504, IR-505, IR-506, IR-507 | Preserve Home default/history-aware resting state, local greeting, exact Focus/task brief, stable typed list, working local Insight actions, real Task navigation/presentation-only hide, and contextual editable fallback. Remove the baseline's duplicate list rendering. Cycles 3 and 7. |
| IR-508, IR-509, IR-510, IR-511, IR-512, IR-513, IR-514 | Preserve once-daily owner-local questions, canonical shared composer, explicit local attachments, and static welcome; goals strip, Connect, Dashboard Intelligence, and duplicate owners stay gone. Cycle 3. |
| IR-515, IR-516, IR-517, IR-518, IR-519, IR-520, IR-521 | Preserve Capture, Listening, explicit mode choice, responsive single-column stage, exact Ask widths, reduced motion, and neutral shared-theme palette. No purple. Cycles 2, 3, and 7. |
| IR-522, IR-523, IR-524, IR-525, IR-526, IR-527, IR-528, IR-529, IR-530 | Narrow local automation; narrow startup/foreground work; remove hidden raw Chat route; preserve compact local Chats catalog and all error forms; keep obsolete page modals/counters gone; retain exact Escape subset and compact navigation. Cycles 1, 3, 6, and 7. |
| IR-616 | Keep the grouped Tasks list and verify the unreachable Board family remains deleted. Cycles 1 and 7. |
| IR-659 | Keep one visible Insights item opening the combined Insights/Focus hub. Cycles 1, 6, and 7. |
| IR-681 | Command-number navigation is exactly Home, Memory, Tasks, Insights; numbered Rewind/Apps commands do not exist, while Command-Option-R and Command-comma remain. Cycles 1, 6, and 7. |
| IR-930 | Keep hidden-until-requested Profile & Stats; load every retained count from owner-local stores; include AI Chat Messages; delete Apps Installed. Cycle 5. |
| IR-933 | Delete Feature Tiers, migrations, thresholds, locks, redirects, analytics, hidden UI, defaults, and exclusive tests without touching billing/quota/fair use. Cycle 2. |

There is no conflict between the live requirements challenge and the deletion map. There is one current-code drift to correct: `DesktopHomeView.navigateHomeOnEscapeIfNeeded()` presently includes `.insights`, while IR-529's decided exact subset is Conversations, Memories, Tasks, and Rewind. S-21 must remove the extra Insights jump and preserve child-owned Escape precedence; it must not reinterpret this as permission to redesign Escape behavior.

## 5. Dependencies and entry gates

### Mandatory and cycle-specific predecessor gates

S-20 and the domain/shell owners below are mandatory before S-21 production work. S-09 is different: only Cycle 4 consumes its repository consent/Privacy seam, and its separately owned live-project proof does not block Cycles 1–3 or 5–7.

| Predecessor | Required consumed shape | Gate evidence |
|---|---|---|
| S-05 | Managed Pi is the only product agent; provider/browser/workspace/skills entrances are gone; Ask Mode is default-off under Advanced AI Setup with unchanged semantics. | S-05 focused Settings and normal/background-agent acceptance. |
| S-06 | Apps, Brain Map/knowledge graph, Connect, connectors, marketplace, remote MCP, broad indexing, and their navigation/search/startup owners are absent. | Route/tool/generated-contract residue plus named Memory/Home navigation. |
| S-07 | Customer BYOK UI/defaults/propagation and quota bypass are absent. | Managed credential and Settings negative contract. |
| S-09 | One local default-on PostHog consent owner applies before setup/identity; Sentry remains separate; Privacy copy/disclosure is truthful; duplicate card/fake status and Crisp are gone. | Cycle 4 requires repository consent startup/runtime/identity tests and truthful Privacy presentation. Owned-development-project evidence remains S-09 operational acceptance and is not an S-21 source gate. |
| S-10 | Conversations and transcript counts are owner-local; Memory grouping and detail navigation use the public local repository. | Offline/restart/count/owner tests. |
| S-11 | Home owns ordinary Chat and local catalog; hidden `ChatPage`, app/persona UI, Home goals/intelligence/connect/counters, and legacy voice import are gone. | Home/Chat/navigation and local catalog tests. S-21 removes only residue that remains after this handoff. |
| S-12 | Memories have one owner-scoped local read/stat surface. | Local stats/read and owner-isolation tests. |
| S-13 | Tasks/Goals have one owner-scoped local read/stat surface; Board is gone. | Tasks/Goals local-authority and grouped-list acceptance. |
| S-14 | Insights/Focus hub, local settings/notifications, local profile, and once-daily questions are integrated; numbered navigation result is final. | Insights hub, local settings, owner-switch, and shortcut tests. |
| S-15 | Rewind remains local and exact; its rejected cloud/search entries are gone. | Rewind behavior plus exact search-ID handoff. |
| S-17 | Narrowed onboarding/reset/permission state is integrated and has no deleted Settings entrances. | Onboarding/reset named-bundle evidence. |
| S-18 | Disabled checkpoint is integrated; Account & Plan consumes the normalized projection; no Stripe/Dodo transaction can occur in disabled mode. | `plan-usage.yaml`, zero-provider-call evidence, and `dodo-integration.md` handoff. Final Dodo activation is not required or authorized. |
| S-20 | Local-GRDB fair-use evidence, transient GPT-5.1 classification, and content-free durable backend enforcement are integrated; Settings/usage consumes only the final presentation/result seam. | S-20 Gate 0 parity, threshold/restriction tests, and no-durable-content backend proof. |

If a predecessor is unmet, stop only the cycle that consumes its public seam and continue independently safe cycles. A missing S-20 result blocks all S-21 production cycles; a missing S-09 repository seam blocks only Cycle 4. Do not reproduce a predecessor, add a fallback API, retain a dead page, or introduce a temporary compatibility route. Reopen the affected cycle when the missing owner's public seam and tests are on the execution head.

### Shared-file and execution gates

1. Re-run `git diff origin/main...HEAD` and inventory every current caller before editing `DesktopHomeView.swift`, `OmiApp.swift`, `DesktopAutomationBridge.swift`, Settings sources, `StartupWarmupCoordinator.swift`, `ViewModelContainer.swift`, or E2E flows; these are shared by several predecessors.
2. Preserve explicit current raw values for retained destinations during the migration. Do not renumber Memories `3`, Tasks `4`, Insights `5`, Rewind `7`, Settings `9`, or Permissions `10` merely because rejected gaps are deleted.
3. Extend a predecessor's owner-scoped read seam when a retained stats count lacks one. Do not read a mutable global owner after an `await`, reach into a UI singleton, or create another cache/table to make stats convenient.
4. The S-09 repository Privacy/consent seam must be integrated before Cycle 4. A hard-coded provider token, inverted consent projection, fake **Active** state, or incomplete identity detach blocks that cycle. Live owned-project inspection remains S-09 operational evidence, not an S-21 code gate.
5. The S-20 presentation contract must be closed before Account & Plan acceptance. Do not infer fair-use state from local Chat content or add Settings classifier controls.
6. Keep `BILLING_MODE=disabled`. Any code path constructing a Dodo/Stripe client, offering checkout/portal, granting entitlement, or clearing quota in this slice is a stop condition.
7. Run `scripts/pr-preflight --suggest` before choosing future commit types. If any commit uses `fix:`, declare and validate its failure class exactly as repository policy requires; do not invent a new guard without a real merged instance.

## 6. Current production codeflow

This is the verified pre-convergence flow at the pinned baseline. It must be refreshed after the predecessor rebase.

### Main shell and routes

```text
OMIApp commands
  -> PrimaryNavigationShortcut.destination
  -> Notification.navigateToSidebarItem(rawValue)
  -> DesktopHomeView validates SidebarNavItem
  -> Memory items normalize through MemoryHubDestination
  -> PageContentView switches on selectedIndex

DesktopTopBar
  -> Home(0), Memory(1), Tasks(4), Insights(5)
  -> compact menu uses the same TopNavigationRoutes
  -> Capture/Listening + Settings remain persistent

semantic automation / notifications
  -> DesktopHomeView.resolvedAutomationTarget
  -> "chat" requests MainChatNavigationRequestStore and selects Home
  -> focus/insight request a typed InsightsHub segment
```

The visible top bar already has the desired four primary items and no Apps. Command 1-4 already maps to Home/Memories/Tasks/Insights. The combined Insights hub and Memory grouping exist. However, the route model still lives in `SidebarView.swift`, a file dominated by the unreachable old sidebar. `PageContentView` still has a raw `case 2` that constructs Home and redirects to Chat, even though `SidebarNavItem(rawValue: 2)` is nil. Default routing silently constructs Home for any unknown integer. These are compatibility paths, not valid customer destinations.

IR-529 drift is visible in `navigateHomeOnEscapeIfNeeded`: it includes Insights in addition to the four decided destinations. The shell must restore the exact decided set while leaving Home's own empty-Chat collapse and child-owned Escape behavior untouched.

### Legacy sidebar and Feature Tiers

`MainWindow/SidebarView.swift` is 1,655 lines. It contains the still-needed route enum next to the unreachable `SidebarView`, tier locks, quick capture controls, update/permission/profile UI, `NavItemView`, `NavItemWithStatusView`, `AppNavRail`, and other exclusive components. `DesktopHomeView.showsPrimarySidebar` is hard-coded false, yet the hidden sidebar branches, `isSidebarCollapsed`, sizing exceptions, and automation snapshot fields remain compiled.

`TierManager.swift` is an explicit eligibility no-op, but startup still runs migrations/checks and writes `currentTierLevel`, `lastSeenTierLevel`, and `userShowAllFeatures`. Nonzero defaults can still trigger real page redirects and sidebar locks. Settings retains `currentTierLevel`, tier row builders, the unmounted Feature Tiers card, and tier analytics wrappers. This is distinct from Dodo entitlements, managed usage quota, and S-20 fair-use enforcement.

### Home and startup

`DashboardPage` is the canonical Home/Chat host and already consumes the local `ChatProvider`, `HomeSuggestionsStore`, `FocusStorage`, `InsightStorage`, and Task/Insight navigation stores. It preserves hub/chat history policy, greeting/brief, task/Insight/Focus/question rows, composer, attachments, catalog, errors, static welcome, local citations, and owner reset.

Two convergence defects remain visible:

- `homeHub` renders `homeKnowsList` twice, once unconstrained and once with a 560-point cap. One retained list therefore has two presentation sites.
- `DashboardViewModel` remains a second Home-specific Task projection and count over `ActionItemStorage`. `ViewModelContainer` and `StartupWarmupCoordinator` retain cached/dashboard “network” refresh naming and duplicate task reads even though `TasksStore` is the canonical owner. The app-activation path still carries broad `refreshConversations` behavior from the old shell. At execution, retain only work with a surviving consumer and move it to that consumer's owner.

The local owner contract already exists in `RuntimeOwnerAuthorizationSnapshot`, `TasksStore`, owner-authorized GRDB read extensions, `ChatProvider`/Agent runtime, and local Focus/Insight/Home stores. S-21 must pass one captured snapshot through every newly composed asynchronous stats or refresh read and revalidate before UI publication.

### Settings and About

`SettingsSidebar` exposes nine visible grouped sections: General, Account & Plan, Transcription, Floating Bar, Notifications & Privacy, Rewind, Shortcuts, Advanced, and About. Legacy `.planUsage` and `.privacy` section cases remain useful internal/automation destinations inside the grouped pages.

Most predecessor-owned rejected search rows are already absent. Two assigned broken rows remain:

- **Sign Out** targets `account.signout`, but no such scroll anchor exists;
- generic **Plan and Usage** targets `planusage.overview`, but no such anchor exists.

The generic Privacy row targets `privacy.privacy`, the duplicate card that S-09 must delete, so its final destination/name must be reconciled with S-09's truthful retained data-location card. Ask Mode is already visible under **Advanced AI Setup** and must remain default-off and behaviorally unchanged.

The current About card still renders **Help Center** to `https://help.omi.me` and labels its local Privacy button **Privacy Policy**. S-21 deletes the former and renames the latter **Privacy & Data**. It does not guess the final website, Terms, changelog, app identity, or update infrastructure owned by S-29/S-30.

### Privacy and retained Settings domains

The baseline Privacy card displays a green **Local database protection — Active** claim, stale **What We Track** categories, and a duplicate **Privacy Guarantees** card. `PostHogManager.hasOptedOut` returns enabled state under an inverted name, and `settings_privacy_snapshot` repeats it. Those are S-09's incomplete result. S-21 accepts S-09's one consent controller and factual presentation; it never calls the SDK directly or creates another preference.

General, Floating Bar, Notifications, Rewind, Account & Plan, updates, diagnostics, and Report Issue already have concrete production owners. S-21 treats their exact retained behaviors as regression fences. Daily Summary, Browser Extension, Dev Mode, Workspace/project config, Claude cards, Brain Map, Apps, and Board are already absent from the visible code and must stay absent after the rebase.

### Your Stats

`SettingsContentView.loadAdvancedStats()` concurrently reads local Conversations, Focus, Tasks, Goals, Memories, and Rewind screenshots, but it does not capture one authorization snapshot or fence late publication. `UserStats` has no AI Chat message field. Success omits **AI Chat Messages**, while the loading state still includes it and the rejected **Apps Installed** row. The local Chat catalog already carries per-session `messageCount`; S-11's runtime owns that catalog. S-21 must consume an explicit owner-authorized catalog read rather than `ChatProvider` UI state.

### Automation and acceptance drift

`DesktopAutomationSnapshot` still publishes `usesLegacyHomeDesign`, `showsPrimarySidebar`, and `isSidebarCollapsed`. `omi-ctl screens` correctly retains semantic **chat** but several E2E contracts still expect raw tab `2`. `desktop-responsiveness-benchmark.yaml` and `chat-fault-5xx.yaml` navigate semantic Chat then wait for `selectedTabIndex: 2`. `keyboard-shortcuts.yaml` describes Cmd+1..5 and currently sends shortcut `3` while expecting the Memories raw value. `settings-basic.yaml` still requires Help Center and Privacy Policy. These flows currently exercise or describe deleted behavior and must be corrected only after the production route graph is green.

## 7. Complete caller and dependency inventory

| Surface | Verified current paths/symbols | S-21 action |
|---|---|---|
| Route identity | `MainWindow/SidebarView.swift` — `SidebarNavItem`; `DesktopHomeView.selectedIndex`; `PageContentView` | Extract/rename one typed surviving destination model; preserve retained raw values; remove rejected/default compatibility cases. No deprecated alias. |
| Visible primary navigation | `DesktopTopBar.swift` — `TopNavigationRoutes`, compact menu, Memory dropdown, persistent controls | KEEP exact order/layout/compact behavior; consume the typed route model. |
| Commands | `OmiApp.navigate(using:)`, `PrimaryNavigationShortcut` in `InsightsHubNavigation.swift`; global Rewind path | KEEP Cmd+1/2/3/4, Cmd+comma, Cmd+Option-R; remove no retained command. |
| Memory grouping | `MemoryHubDestination.swift`; `MemoryHubPage`; `ConversationsPageHost` | KEEP Memories + Conversations and local persisted subgroup; no Brain Map. |
| Insights grouping | `InsightsHubNavigation.swift`; `InsightsHubPage`; `FocusPage`; `InsightPage` | KEEP one top item and typed segment/owner request; correct Escape only. |
| Rewind | `RewindPage`, `RewindOnlyView`, `.navigateToRewind`, `.navigateToRewindSettings` | KEEP exact full and command-line Rewind behavior; no redesign. |
| Settings route | `SettingsSidebar.swift`; `SettingsPage.swift`; `SettingsContentView.SettingsSection` | KEEP nine visible groups and internal merged destinations; remove only dead results/rows/state. |
| Legacy shell | `SidebarView.swift`; `ClickThroughView.swift`; hidden branches and sizing comments in `DesktopHomeView.swift` | DELETE after top-bar keep fence is green; preserve shared capture/update/permission owners, not their dead duplicate presentation. |
| Feature Tiers | `TierManager.swift`; `OmiApp.swift`; `DesktopHomeView.swift`; Settings Advanced/Controls/Page; Analytics/PostHog tier methods | DELETE completely. Keep billing, quota, and fair use. |
| Home presentation | `DashboardPage.swift`; `HomeStagePresentation.swift`; `HomeKnowsListComposer`; Home catalog/error/navigation stores | KEEP decided UI/behavior; remove duplicate list call and residue only. |
| Home Task projection | `DashboardViewModel`; `ViewModelContainer.dashboardViewModel`; `StartupWarmupCoordinator.dashboardViewModel`; `TasksStore` | Move Home observation/read to `TasksStore`; delete the duplicate view model and dashboard-named warmups. |
| Home Chat | `ChatProvider`; `AgentClient`/`AgentBridge`/`AgentRuntimeProcess`; `LocalChatCatalog`; `MainChatNavigationRequestStore` | KEEP local catalog/journal and semantic Chat-to-Home; reject raw page `2`. |
| Home suggestions/Insights | `HomeSuggestionsStore`; `FocusStorage`; `InsightStorage`; `InsightsHubNavigationStore` | KEEP owner/day and stable-record behavior; do not change prompt/model/actions. |
| Capture/Listening | `CaptureListeningControls.swift`; `CaptureListeningLogic.swift`; `AppState`; `ProactiveAssistantsPlugin` | KEEP exact status/toggle/mode and persisted-intent reconciliation; verify deletion of sidebar duplicate does not remove the owners. |
| Settings search | `SettingsSearchItem.allSearchableItems`; search filter/result row; `SettingHighlightModifier` and card `settingId`s | Introduce/consume one typed destination contract; remove broken/deleted entries; prove every remaining result mounts a real anchor. |
| Privacy/telemetry | Privacy Settings source; `ProductAnalyticsConsentController` expected from S-09; `AnalyticsManager`; `PostHogManager`; `DesktopDiagnosticsManager`; `FeedbackView` | CONSUME S-09; preserve separate Sentry/Enhanced Diagnostics/report/export. No direct SDK redesign in S-21. |
| Account & Plan | Account/Billing Settings files; `BillingWebFlow`; `UsageLimitPopupView`; billing projection and S-20 result | CONSUME S-18/S-20; disabled remains Skip/no transaction. Remove only shell/search residue. |
| Your Stats local owners | `TranscriptionStorage`, Chat catalog, `RewindDatabase`, `ProactiveStorage`/final Focus owner, `ActionItemStorage`, `GoalStorage`, `MemoryStorage` | ADAPT presentation loader to one owner snapshot and local reads; delete Apps metric. |
| Tasks | `TasksPage.swift`; `TasksStore`; `TaskNavigationRequestStore` | KEEP grouped list and Task navigation; prove Board remains absent. |
| About | Settings Controls; `UpdaterViewModel`; `AppBuild.changelogURLString`; `WhatsNewToast` | Delete Help Center, rename local Privacy row; preserve update/link behavior pending S-29/S-30. |
| Local automation | `DesktopAutomationBridge`; `DesktopAutomationSnapshot`; `omi-ctl`; notification names | Route through production destination policy; keep semantic Chat alias; delete legacy state and fail closed for rejected targets. |
| Tests | navigation/Home/Settings/automation/startup/billing/owner tests under `Desktop/Tests` | Prefer behavioral public seams; retain static residue checks only as labelled tripwires. Remove obsolete source-string expectations. |
| E2E and docs | `e2e/flows/{navigation,keyboard-shortcuts,home-stage,settings-basic,privacy-settings,about-settings,desktop-responsiveness-benchmark,chat-fault-5xx}.yaml`, `CORE_E2E.md`, `feature-vector.md`, `e2e/SKILL.md` | Update to real route/settings contract and named-bundle acceptance. Do not weaken unrelated flows. |
| Product/docs | `PRODUCT.md`, `desktop/macos/AGENTS.md`, changelog fragments | Update only if implementation changes the documented shell/test boundary; add the required unreleased fragment. Do not rebrand. |

No backend route, schema, OpenAPI operation, generated client, cloud collection, bucket, queue, or deployment is owned by S-21. Backend and provider code is inspected only to verify the consumed S-09/S-18/S-20 contracts and absence of a new authority.

## 8. Behavior classification table

| Category | Classified behavior |
|---|---|
| **KEEP AS IS** | Home's history-aware hub/Chat policy; greeting, Focus/task brief, stable mixed list, Insight/Task actions, contextual tip, once-daily questions, composer/send/stop, local attachments, static welcome, errors, local catalog; Capture/Listening controls and explicit modes; responsive width/reduced motion/neutral palette; Memory grouping; grouped Tasks list; combined Insights/Focus hub; Rewind and Rewind-only mode; nine Settings groups; Ask Mode and all retained General/Floating/Notification/Rewind/Advanced controls; Account & Plan disabled behavior; PostHog/Sentry separation after S-09; Enhanced Diagnostics, Report Issue, Save Diagnostics; update behavior; website/Terms/release-note rows pending their later owner. |
| **ADAPT** | One typed destination policy for UI/commands/automation; exact Cmd-number map and Escape subset; Settings search destinations to real typed anchors; About local Privacy label; Home Task observation/startup to `TasksStore`; local owner-fenced Your Stats including Chat messages; local automation and E2E expectations to canonical Home Chat. |
| **DELETE** | Old sidebar/AppNavRail/click-through wrapper and exclusive components; raw/hidden Chat route `2` and unknown-index fallback; old Home/legacy automation state; Feature Tiers and every key/migration/threshold/lock/redirect/event/test; duplicate Home knows-list render; `DashboardViewModel` after handoff; Apps Installed; broken Sign Out and generic Plan search rows plus any predecessor-owned phantom residue still present; Help Center; dead page-only modals/counters and stale docs/flows. |
| **SIMPLIFY AFTER** | Only after behavioral GREENs: remove raw-int switches where typed routing replaces them, dashboard/network naming with no network owner, duplicate refresh observers, dead imports/comments/helpers, source-scrape tests that can become behavioral tests, and obsolete automation snapshot fields. Measure the focused loop before changing tooling; if there is no material repeated bottleneck, tooling automation is `none`. |
| **ACCELERATE AFTER** | Measure focused destination/Home/Settings Swift filters and named-bundle relaunch time after the shell is GREEN. Change the feedback loop only for a demonstrated repeated delay; otherwise `none`. |
| **AUTOMATE LAST** | Extend the existing navigation/Settings flow or manifest lane only after the final destination graph is stable and a real recurring gap is identified; otherwise `none`. |
| **OUT OF SCOPE / DEFERRED** | S-05 runtime/provider/tool work; S-09 telemetry/provider configuration and identity proof; S-10 through S-15 domain authority; S-17 onboarding; Dodo activation and billing provider transactions; S-20 classifier/enforcement; S-22 models; S-23/S-24 product/storage deletion; service/deployment work; S-28 namespaces; S-29 signing/update infrastructure/legal destinations; S-30 rebrand/final copy; S-31 release acceptance; Windows; live resource mutation. |

## 9. Retained behavioral invariants

1. Home is the default route and the only ordinary Chat presentation. Existing history rests in Chat; empty history rests in the hub. Semantic **Chat** means “open Home and request its Chat stage,” never raw page `2`.
2. Retained route raw values do not change during this slice. Invalid or deleted raw values do not construct Home as a silent compatibility success.
3. Primary navigation is exactly Home, Memory, Tasks, Insights in both wide and compact presentations. Memory exposes Memories and Conversations; Insights exposes Insights and Focus.
4. Cmd+1/2/3/4 maps to Home/Memories/Tasks/Insights. Cmd+comma opens Settings. Cmd+Option-R keeps Rewind. There is no numbered Rewind/Apps command.
5. Child-owned Escape closes the child first. Only an otherwise-unhandled Escape from Conversations, Memories, Tasks, or Rewind goes Home. Insights, Home, Settings, and Permissions do not gain that shell jump.
6. Capture and Listening status, start/stop, Meetings Only/Always choice, permission truth, floating bar behavior, PTT, and persisted-intent restoration do not change when the dead sidebar is deleted.
7. Home renders one stable mixed list. Hiding a Task is presentation-only; dismissing an Insight calls its local owner. No rotation, goals strip, Connect, cloud intelligence, aggregate counter, or duplicate list returns.
8. Home startup/foreground work is limited to surviving owners. A view model may project local state but never become a second product authority.
9. Every asynchronous read or publication introduced here captures one `RuntimeOwnerAuthorizationSnapshot` before work, carries it across every suspension, uses owner-aware store/runtime reads, and revalidates immediately before publishing. A-to-B and same-UID ABA late results disappear.
10. **Your Stats** remains hidden until requested; shows Conversations, AI Chat Messages, Screenshots, Focus Sessions, Tasks To Do/Done/Removed, Goals, and Memories; preserves loading/formatting/failure behavior; and has no Apps metric or backend product-data read.
11. Settings retains exact reviewed controls and copy/quirks unless an assigned decision explicitly changes a row. Search semantics stay word-AND across name/subtitle/keywords; only the destination registry is made truthful.
12. Ask Mode remains default-off and unrepaired. S-21 only proves it is reachable under Advanced AI Setup and that no retired AI Chat/provider entrance remains.
13. PostHog consent controls PostHog only; Sentry, Enhanced Diagnostics, Report Issue, and Save Diagnostics remain separate. S-21 never directly initializes, identifies, opts, or resets a provider.
14. `BILLING_MODE=disabled` requires no credentials, builds no provider client, performs no checkout/portal transaction, grants no entitlement, clears no quota, and renders literal **Skip** where S-18 specifies it.
15. Feature Tiers never return under another name. Paid plans, quota, and fair use are separate retained policies and are not simplified by deleting engagement tiers.
16. Tasks remains the grouped list; Board stays absent. Rewind's reviewed UI, storage, retention, excluded apps, battery behavior, and command-line mode remain exact.
17. No purple is introduced. Home keeps shared neutral tokens and all retained narrow-window controls remain reachable without overlap.
18. Local automation stays non-production, loopback/token protected, and routed through the same production functions as UI. It does not mutate provider or view-model state directly.

## 10. Target authority, result ownership, and service-topology model

### Target shell ownership

```text
DesktopDestination / DesktopNavigationPolicy
  owns: valid top-level destinations, retained raw IDs, command mapping,
        semantic target resolution, Escape eligibility, invalid-target result
  does not own: page data, subgroup state, Chat state, billing, permissions

DesktopHomeView
  owns: selected top-level destination and composition only
  delegates:
    Memory subgroup       -> MemoryHubDestination + local Conversation/Memory owners
    Insights subgroup     -> InsightsHubNavigationStore + local Insight/Focus owners
    Home task projection  -> TasksStore
    Home Chat             -> ChatProvider + local agent journal/catalog
    Settings              -> SettingsContentView and domain owners
    Rewind                -> retained local Rewind owner
```

The route type should live in an accurately named small source, not inside a deleted 1,655-line `SidebarView`. Every in-tree caller moves in the same change. Do not retain `typealias SidebarNavItem = DesktopDestination`, a deprecated wrapper, or an ignored raw-page shim.

### Settings search ownership

Use one typed `SettingsDestination` (or equivalently small existing production type discovered at rebase) shared by the searchable catalog and mounted setting anchors. A search result carries a section and real control identity; its route selects the grouped page, scrolls to that anchor, and exposes highlight state. Deleted controls have no enum/case/catalog entry. Do not build a dynamic screen scraper, global Settings registry, or duplicate backend-owned settings model.

### Home and stats ownership

```text
Home task rows/count       -> TasksStore -> ActionItemStorage/GRDB
Conversations count        -> TranscriptionStorage/GRDB
AI Chat message count      -> Agent runtime local Chat catalog/journal metadata
Screenshots count          -> RewindDatabase/GRDB
Focus count                -> final S-14 local Focus store
Task status counts         -> ActionItemStorage/GRDB
Goals count                -> GoalStorage/GRDB
Memories count             -> MemoryStorage/GRDB
```

`YourStatsLoader` (name may follow local convention) is a presentation reader, not an authority. It receives owner-aware collaborators and one captured authorization snapshot, performs bounded concurrent local reads, preserves the current fallback rules, and returns one immutable projection only if the snapshot is still current. It creates no table, cache, sync, endpoint, or telemetry payload.

`TasksStore` owns the Home task projection. If its current public API cannot provide the exact list and count, extend that owner with a narrowly named Home snapshot method and tests. Do not keep `DashboardViewModel` as an adapter once no other live caller remains.

### Backend and provider topology

S-21 adds no backend product-data path:

```text
Mac local stores (durable authority)
  -> optional predecessor-owned bounded managed compute
  -> validated result
  -> same owning Mac store commits

backend retained control plane
  -> auth, disabled billing projection, quota/fair-use facts, update/config
  -> never supplies Home/Stats product-data authority
```

Any backend product-data read added for navigation, Settings search, Home refresh, or Your Stats fails the slice. S-09 provider observation and post-Wave-6 Dodo acceptance remain separate external proof.

## 11. Ordered TDD cycles

Every RED below must fail for the stated behavioral reason before its GREEN is implemented. Source-residue assertions are supplemental static tripwires only.

### Cycle 1 — One typed surviving destination graph

- **Intended behavioral RED:** Through a production navigation policy/reducer, assert: the only primary routes are Home/Memory/Tasks/Insights in order; Memory resolves Memories and Conversations; Insights defaults to Insights and accepts an owner-fenced Focus request; Cmd+1/2/3/4/comma and the retained Rewind command resolve exactly; invalid raw values `2`, `6`, and `8` are rejected without changing selection; unknown automation targets return an explicit unsupported result; and unhandled Escape goes Home only from Conversations, Memories, Tasks, and Rewind. Exercise the same policy from `OmiApp` commands, top-bar selection, notification routing, and `DesktopHomeView` page composition.
- **Why it fails before implementation:** route identity is embedded in `SidebarView.swift`; page composition is a raw integer switch with a silent default-to-Home and a live `case 2`; automation has a separate string switch; and the current Escape set wrongly includes Insights. Existing tests mostly inspect source strings or isolated arrays rather than executing one production decision seam.
- **Minimum production change for GREEN:** Introduce one accurately named `DesktopDestination` plus `DesktopNavigationPolicy` (or deepen an equivalent current type discovered after rebase). Preserve retained raw IDs. Route top bar, compact menu, commands, notifications, page selection, settings/back behavior, and automation resolution through it. Make invalid raw/semantic targets explicit no-ops/errors, not Home success. Remove Insights from the shell Escape set while retaining child precedence. Do not alter subgroup data or page UI.
- **Retained behavior protected:** default Home, Memory/Insights grouping, Rewind, Settings, Permissions, exact shortcuts, compact layout, Analytics tab-name reporting, Home's own Chat collapse, and all page-local Escape handlers.
- **Authoritative owner before / after:** before, raw `selectedIndex` plus several switches; after, one typed navigation policy owns route validity while each page continues owning its data and presentation.
- **Expected change inventory:** new or renamed small MainWindow navigation source; `SidebarView.swift` route enum extraction; `DesktopHomeView.swift`; `DesktopTopBar.swift`; `OmiApp.swift`; `MemoryHubDestination.swift`; `InsightsHubNavigation.swift`; `DesktopAutomationBridge.swift`; behavioral navigation tests; adapt `TopNavigationBarLayoutTests`, `InsightsHubNavigationTests`, and `DashboardCaptureStateTests` away from source scrapes where possible.
- **Focused verification:** `DesktopNavigationPolicyTests`, `TopNavigationBarLayoutTests`, `InsightsHubNavigationTests`, `MemoryHubDestinationTests` if present, `DashboardCaptureStateTests`, and a debug Swift build.
- **Deletion/simplification enabled:** raw switch duplication, default unknown-route Home fallback, misnamed route ownership in the legacy sidebar, the raw page-2 compatibility branch, and duplicate automation resolution become removable in later cycles.
- **Stop condition:** a predecessor introduces a new visible destination, a retained raw value cannot remain stable, or a child Escape owner cannot be separated from shell navigation. Stop and reconcile the product authority; do not add an alias or broaden Escape.

### Cycle 2 — Delete the old sidebar and Feature Tiers without deleting real controls

- **Intended behavioral RED:** Launch a production-composed test shell with `currentTierLevel`, `lastSeenTierLevel`, and `userShowAllFeatures` seeded to every legacy/nonzero combination. Assert all retained destinations remain reachable and never lock/redirect, Advanced has no Feature Tiers, and the current top bar still controls Capture, Listening, Settings, Rewind, updates, and permissions. Assert the single shell renders no old rail even when stale legacy preferences exist.
- **Why it fails before implementation:** tier migrations/checks still run; nonzero `currentTierLevel` still redirects and locks; the unmounted tier card/helpers/events remain; the dead `SidebarView` family and click-through wrapper remain compiled; and automation still describes sidebar/legacy state.
- **Minimum production change for GREEN:** After Cycle 1 owns routes, delete `TierManager`, all tier reads/default writes/migrations/checks, `requiredTier`, visible-item/lock/unlock logic, tier analytics, Settings picker/progress/card/state, and exclusive tests/docs. Delete the old `SidebarView`/`AppNavRail` presentation and exclusive helper types, `ClickThroughView.swift` if refreshed callers remain empty, hidden sidebar branches, collapse state, and sizing exceptions. Remove `useLegacyHomeDesign` from the named-bundle settings seed. Preserve the actual top-bar capture/listening implementation and About updater.
- **Retained behavior protected:** every first-release feature is visible; billing/quota/fair-use remains independent; capture/listening permission and auto-recovery behavior remains owned by current services; Rewind-only launch remains; narrow layout and Settings back behavior remain.
- **Authoritative owner before / after:** before, top bar is visible but an unreachable sidebar and dormant tier state can still decide presentation; after, Cycle 1's destination policy and current top bar are the only navigation owner.
- **Expected change inventory:** `SidebarView.swift` deletion after route extraction; possible `ClickThroughView.swift` deletion; `TierManager.swift`; `OmiApp.swift`; `DesktopHomeView.swift`; `SettingsPage.swift`; Settings Advanced/Controls; `AnalyticsManager.swift`; `PostHogManager.swift`; settings seed; E2E cover lists; tier/sidebar tests and static contracts; one changelog fragment.
- **Focused verification:** new `DesktopShellVisibilityTests` and `FeatureTierRetirementTests`; existing top-navigation, capture/listening, update, settings, permissions, billing-availability, and Rewind launch tests; Swift debug compile.
- **Deletion/simplification enabled:** the 1,655-line duplicate sidebar family, engagement thresholds/stats reads, stale keys, locks, redirects, events, hidden UI, migration code, click-through layout exception, and legacy snapshot fields can no longer influence the product.
- **Stop condition:** refreshed source proves a legacy component is still the only reachable owner of a retained control. First move that control through its already-authorized current owner and obtain behavioral parity; do not retain the entire rail or copy its state machine.

### Cycle 3 — Canonical Home uses surviving owners once

- **Intended behavioral RED:** With controllable production Home collaborators and real local stores, assert one Home mount renders exactly one mixed list; exact local Task rows/count update after add/complete/reopen; semantic Chat opens Home's real Chat stage; invalid raw route `2` does not mount a page; startup/foreground triggers only the surviving Tasks, Home suggestions, Chat restoration/catalog, capture/permission, and independently owned Memory-hub refreshes; and A-to-B plus same-UID ABA during a suspended task/suggestion refresh publishes nothing for A. Preserve all IR-500–IR-530 Home keep tests, including errors, catalog, attachments, widths, reduced motion, and capture/listening.
- **Why it fails before implementation:** `homeKnowsList` is invoked twice; `DashboardViewModel` duplicates Task state/count; `ViewModelContainer` and `StartupWarmupCoordinator` retain dashboard-specific cached/network refresh work; the raw case-2 page alias remains; and current lifecycle naming/observers make surviving ownership hard to prove.
- **Minimum production change for GREEN:** Render the list once. Give Home a narrow `TasksStore` projection/read, extending that owner with an authorization-snapshot-aware Home snapshot only if needed for exact count/list behavior. Delete `DashboardViewModel` and its container/warmup/reset wiring after all callers move. Rename/remove dashboard network refresh tasks that now perform only local owner work. Remove raw case `2`. Keep Memory-hub conversation/folder warmup only under its surviving owner. Revalidate the captured owner immediately before every publish; do not add a new Home coordinator.
- **Retained behavior protected:** complete decided Home behavior, local journal/catalog, Task and Insight actions, Focus wording, suggestions policy, Chat send/stop/attachments/errors/citations, capture/listening, normal App activation, database retry, memory lifecycle, and Task reminder maintenance.
- **Authoritative owner before / after:** before, `ActionItemStorage` is durable but `DashboardViewModel` and `TasksStore` independently project Home task state; after, `TasksStore` is the sole observable Task projection and GRDB remains durable authority. Other Home data stays with its existing owner.
- **Expected change inventory:** `DashboardPage.swift`; `TasksStore.swift`; `ViewModelContainer.swift`; `StartupWarmupCoordinator.swift` and its task IDs/policy only where names/work are exclusive; `DesktopHomeView.swift`; Home/startup/owner tests; stale dashboard source-string tests; relevant Home E2E flow.
- **Focused verification:** new `HomeShellOwnerTests`; `HomeKnowsComposerTests`; `HomeStageCloseSemanticsTests`; `HomeSuggestionsStoreTests`; `HomeChatCatalogTests`; `ChatErrorStateTests`; `StartupWarmupPolicyTests`; Task owner-boundary tests; `agent-logic-harness.sh` for retained Chat continuity.
- **Deletion/simplification enabled:** duplicate list site, `DashboardViewModel`, duplicate task reads/reset state, dashboard-network terminology/work with no network owner, raw page-2 alias, and exclusive static tests/comments.
- **Stop condition:** exact Home task behavior cannot be supplied by `TasksStore`, or removing a broad warmup would make a retained Memory/Chat/capture owner stale. Extend/move the narrow owner first; never keep the umbrella as a compatibility adapter or delete required refresh behavior to satisfy a residue search.

### Cycle 4 — Settings search, About, and predecessor-owned surfaces converge

- **Intended behavioral RED:** Drive the production Settings search/catalog and grouped navigation. For every remaining search item, select it and assert the correct visible section mounts and the real target anchor highlights. Assert the nine groups and every retained decision fence in §9; Ask Mode appears only under Advanced AI Setup and remains default-off; Privacy consumes S-09's real data-location/disclosure/PostHog preference; Account & Plan consumes S-18/S-20; Rewind settings remain exact; Report Issue is reachable from About and Advanced; Help Center, old Privacy Policy label, broken Sign Out/generic Plan search, predecessor phantom rows, and every rejected card are absent. Search word-AND semantics must be unchanged.
- **Why it fails before implementation:** `account.signout` and `planusage.overview` have no anchors; generic Privacy points at S-09's to-be-deleted duplicate card; About still exposes Help Center and the wrong local label; S-09/S-20 are not yet integrated on the planning baseline; and catalog/anchor identity is untyped.
- **Minimum production change for GREEN:** After S-09/S-20 integration, use one small typed Settings destination contract shared by search items and mounted anchors. Remove the broken rows and any refreshed predecessor-owned residue—never the real Account Sign Out button or Account & Plan page. Retarget/rename the generic Privacy search to S-09's factual data-location surface only if its content matches IR-204; keep What We Track. Delete Help Center and rename the local About action **Privacy & Data**. Remove only shell/search state left by deleted cards. Do not change domain persistence, provider SDKs, prompts, notification behavior, Rewind, billing, or update infrastructure.
- **Retained behavior protected:** search matching; nine groups; General, Transcription/VAD, Floating Bar, Shortcuts, local Notifications, Rewind, Ask Mode, AI Profile, diagnostics/report/export, Account & Plan, disabled Skip, Sparkle, website/release/Terms links, and local Privacy navigation.
- **Authoritative owner before / after:** before, each domain owner is authoritative but search carries unchecked string anchors; after, domain ownership is unchanged and a typed presentation contract owns only Settings reachability.
- **Expected change inventory:** `SettingsSidebar.swift`; `SettingsPage.swift`; Settings section/component files only for destination typing and assigned row changes; About Controls; S-09/S-18/S-20 presentation tests consumed, not duplicated; new `SettingsDestinationContractTests`; adapt `SettingsSearchContractTests`, `AutomationSettingsSectionTests`, `DailySummaryRetirementTests`, and relevant E2E flows/docs.
- **Focused verification:** `SettingsDestinationContractTests`; `SettingsSearchContractTests`; `AutomationSettingsSectionTests`; S-09 consent/privacy tests; Enhanced Diagnostics and feedback/export tests; `BillingAvailabilityTests`; `DailySummaryRetirementTests`; Rewind Settings tests; settings navigation smoke.
- **Deletion/simplification enabled:** dangling string anchors, broken/phantom search entries, Help Center, the misleading local label, and any predecessor-deleted card shell that survives the rebase.
- **Stop condition:** S-09 or S-20 is incomplete; a search result has no retained owner; final website/legal/release destination is unknown; or making an anchor real would require restoring a deleted control. Delete/hand off according to the ledger—never create a placeholder.

### Cycle 5 — Your Stats is an owner-fenced local projection

- **Intended behavioral RED:** Seed distinct owner-A local counts for Conversations, Chat messages across default/named chats, Screenshots, Focus Sessions, Tasks To Do/Done/Removed, Goals, and Memories. Reveal Profile & Stats and assert the exact formatted rows, loading placeholders, and card failure behavior; **Apps Installed** is absent. Run offline and after restart. Suspend each reader, perform A-to-B and same-UID ABA, then resume and assert no A projection publishes. Prove a Chat-catalog or screenshot-count failure yields the already-decided zero fallback while a required combined-reader failure preserves **Unable to load stats**. Assert no backend API or product-data client is invoked.
- **Why it fails before implementation:** `UserStats` omits Chat count, successful UI omits the row, loading still includes Apps, and `loadAdvancedStats()` starts concurrent singleton reads without one authorization snapshot or a late-publication fence.
- **Minimum production change for GREEN:** Add one narrow immutable stats projection and loader with injected local-owner collaborators. Capture one `RuntimeOwnerAuthorizationSnapshot` before starting, pass it to owner-aware GRDB and local Chat catalog reads, revalidate after each suspension and before assignment, and cancel/reset on owner change. Sum authoritative local catalog message counts without starting model work. Add the Chat row, remove Apps and every marketplace fetch/state contribution, and preserve current visibility, number formatting, per-row loading, zero fallbacks, and card-level failure semantics.
- **Retained behavior protected:** hidden Profile & Stats wrapper, AI User Profile sibling, all retained rows, local database isolation, offline/restart behavior, and existing failure presentation. No count becomes telemetry or cloud authority.
- **Authoritative owner before / after:** before, underlying stores are local but the Settings aggregation is unfenced/incomplete; after, each local store remains authority and one ephemeral owner-fenced reader composes a presentation snapshot.
- **Expected change inventory:** Settings `UserStats` model, loader/control/Advanced view; explicit owner-aware read overloads in the owning stores/runtime only where missing; `DesktopAutomationBridge` stats snapshot only if needed for repeated named-bundle proof; new `YourStatsLocalAuthorityTests`; owner fixture tests; delete Apps-only tests/state.
- **Focused verification:** `YourStatsLocalAuthorityTests`; local Conversation/Chat catalog/Rewind/Focus/Task/Goal/Memory owner tests; same-UID ABA tests; Settings presentation test; offline restart fixture.
- **Deletion/simplification enabled:** Apps Installed row/loading/state/fetch, backend counts, mutable-global owner lookups, duplicated formatting/loading state, and tier-exclusive stats reads after Cycle 2.
- **Stop condition:** S-11's local catalog or another domain owner lacks a safe explicit read seam, a count would require starting a remote product-data API, or exact fallback behavior cannot be characterized. Extend the owner or stop; do not count UI arrays, query another account, or return a fabricated success.

### Cycle 6 — Automation, shortcuts, raw inputs, and restored state fail closed

- **Intended behavioral RED:** Through the real local bridge/controller, verify every listed screen and action against Cycle 1's policy. Home/dashboard selects Home hub; semantic Chat selects Home and requests its Chat stage; Conversations/Memories choose the correct Memory subgroup; Focus/Insights choose the correct hub segment; Tasks/Rewind/Settings/Permissions select their real page. Apps, Brain Map, raw `2/6/8`, unknown settings sections, and unknown targets return explicit unsupported/unchanged results. Cmd-equivalent actions exactly match real commands. Stale tier/legacy defaults and invalid persisted Memory subgroup data cannot reveal deleted UI. The state snapshot contains no legacy-design/sidebar fields.
- **Why it fails before implementation:** bridge target resolution and raw notification routing are separate; unknown targets can be acknowledged without a route; stale snapshot fields remain; `omi-ctl`/flows describe deleted raw Chat behavior; and two flows wait for tab `2` after semantic Chat.
- **Minimum production change for GREEN:** Make bridge navigation call the same production policy and return an explicit error for unsupported targets before posting. Keep `chat` as a semantic alias to canonical Home, not a page compatibility route. Validate generic raw notifications through the typed policy. Remove `usesLegacyHomeDesign`, `showsPrimarySidebar`, and `isSidebarCollapsed` from snapshot construction/defaults/consumers. Update `omi-ctl screens` wording and the stale Chat/shortcut flow expectations. Preserve local-only capability and token boundary.
- **Retained behavior protected:** all accepted semantic automation, conversation detail opening, Home actions, settings subsection routing, readiness/health, screenshots, local Chat fault flow, and non-production isolation.
- **Authoritative owner before / after:** before, bridge and UI each infer navigation; after, Cycle 1's policy owns validity and the bridge is only a local transport into production behavior.
- **Expected change inventory:** `DesktopAutomationBridge.swift`; `DesktopHomeView.swift`; notification payload handling; `scripts/omi-ctl`; automation tests; `keyboard-shortcuts.yaml`; `desktop-responsiveness-benchmark.yaml`; `chat-fault-5xx.yaml`; snapshots and E2E docs. Do not expose a production port or add a remote API.
- **Focused verification:** `DesktopAutomationSecondaryActionTests`; new bridge navigation contract tests; `AutomationSettingsSectionTests`; `HomeStageCloseSemanticsTests`; flow lint/self-check; run the corrected shortcut, Home, navigation, and fault flows in a named non-production bundle.
- **Deletion/simplification enabled:** separate target switch, silent unknown success, legacy snapshot schema, raw-page automation expectations, stale screen help, and raw restored compatibility assumptions.
- **Stop condition:** a retained harness requires direct state mutation or an old raw route to pass. Update the harness to the customer path; do not keep customer-inaccessible product UI for tests.

### Cycle 7 — Close the complete surviving shell and automate only its stable paths

- **Intended behavioral RED:** Run one integrated shell-convergence flow plus the existing navigation, Home, Settings, privacy, About, plan, task, Rewind, shortcut, responsiveness, and Chat-fault flows against `omi-wave3-s21`. Assert every visible destination/search target has a surviving local/control owner; deleted products are absent from UI/menu/shortcut/automation/restored state; narrow and wide layouts retain controls; offline/restart and owner-switch behavior pass; and disabled billing makes zero transaction calls. Run exact residue searches and prove only classified history/operator/Windows matches remain.
- **Why it fails before implementation:** current flows contain raw-2, wrong shortcut, Help Center/Privacy Policy, old-sidebar cover, and stale feature-vector descriptions; current source contains tier/sidebar/Home/search/stats residue. The Wave 2 closeout also records inherited integration debt that must be re-baselined rather than hidden.
- **Minimum production change for GREEN:** Fix only integration defects exposed by the full real path. Update/add the smallest stable typed flow needed to cover the final destination graph and Settings anchors; update `CORE_E2E.md`, `feature-vector.md`, component guidance, `PRODUCT.md` if the documented route contract changed, and one unreleased changelog fragment. Remove dead imports/comments/tests after all behavior passes. Measure the repeated focused loop; change no tooling if existing `dev-feedback.py`, Swift filters, and harness flows are already sufficient.
- **Retained behavior protected:** the entire §9 invariant set and every predecessor keep suite. This cycle is acceptance, not a late redesign or broad refactor.
- **Authoritative owner before / after:** unchanged; this cycle proves the route/presentation layers expose the already-established local/control owners and no rejected authority reappears.
- **Expected change inventory:** affected E2E flows/snapshots/docs; shell/Settings/Home tests; component/product docs and changelog; production code only for a demonstrated integration defect. No backend, schema, infrastructure, or generated client change is expected.
- **Focused verification:** all commands in §14 and the user paths in §15, with before/after timing and inherited-failure classification.
- **Deletion/simplification enabled:** obsolete source-scrape tests, stale E2E descriptions/snapshots, dead comments/imports, and any final exclusive residue with no surviving caller. No separate automation is justified beyond the stable flow updates; otherwise **automate last: none**.
- **Stop condition:** a deleted destination still has a live owner, a retained path regresses, a failure cannot be separated from the target baseline, full acceptance needs production credentials/apps, or the only way to pass is weakening a test. Stop, record exact evidence, and return to the owning cycle/slice.

## 12. Cross-slice ownership and handoffs

| Slice | S-21 consumes | S-21 owns / hands forward |
|---|---|---|
| S-05 | Final managed Pi and Ask Mode location/semantics | Verifies reachability; removes no runtime/provider code. Hands final Settings route to S-30 truth pass. |
| S-06 | Apps/Brain Map/Connect/indexing/connector deletion | Deletes only leftover shell/search/automation references; never restores an empty destination. |
| S-07 | BYOK deletion and managed credential boundary | Verifies no Settings/navigation residue; leaves model/provider policy to S-22. |
| S-09 | Consent controller, truthful Privacy, separate Sentry, diagnostics/report/export, Crisp deletion | Makes the final Privacy destination searchable/reachable; deletes only dangling shell/search. S-27 retains live observability proof. |
| S-10 | Local Conversation repository/count and Memory subgroup | Preserves grouped reachability; consumes count for stats. No schema or transcript change. |
| S-11 | Canonical Home Chat, local catalog, Home feature deletion | Removes remaining raw route/lifecycle/shell residue and duplicate presentation; preserves journal/catalog semantics. |
| S-12 | Local Memory authority/stats | Consumes stats and Memory navigation only. |
| S-13 | Local Tasks/Goals, grouped list, Board deletion | Moves Home projection to `TasksStore`, consumes local counts, keeps Board gone. |
| S-14 | Local Focus/Insights/Profile/settings/questions and combined hub | Preserves hub/segment/owner behavior and final shortcut map; corrects shell Escape drift only. |
| S-15 | Exact Rewind behavior and deleted search-ID handoff | Preserves Rewind UI/mode/command/settings; removes only final shell/search residue. |
| S-17 | Narrow onboarding/reset/permission result | Preserves reset and permission routes; removes no onboarding state. |
| S-18 | Account & Plan, disabled billing, future Dodo architecture | Preserves the target and disabled Skip; final Dodo remains post-Wave-6 under `dodo-integration.md`. |
| S-20 | Final local-evidence/transient-GPT-5.1/content-free-enforcement presentation | Consumes only final usage/fair-use state. No classifier logic or content handling in S-21. |
| S-22/S-23/S-24 | Later model/product/storage deletion | Receives a shell with no rejected caller; S-21 does not delete backend families or model routes. |
| S-28 | Later clean product namespaces | Receives the final retained preferences/routes. S-21 deletes tier/legacy keys but does not rename bundle/storage roots. |
| S-29 | Signing, Sparkle/release infrastructure, website/legal destinations | Receives retained update/link rows. S-21 deletes Help Center and does not guess replacement URLs. |
| S-30 | Final product identity and truthful copy | Receives one shell/Settings graph. S-21 does not rebrand provisional Omi strings outside its exact Help/Privacy decisions. |
| S-31 | Final cross-product release acceptance | Receives S-21 named-bundle evidence plus green official affected-suite evidence; production-family proof remains separate. |

Shared-file rule: if a predecessor changes a shared source during the mandatory rebase, preserve its public owner and behavior, update the inventory, and integrate through that seam. Never resolve a merge by reintroducing `DashboardViewModel`, raw page `2`, provider Settings, a tier key, a cloud stats fallback, or a deprecated alias.

## 13. Repository residue-search strategy

Run these before Cycle 1, after the owning GREEN, and at closure. Save classified output in PR evidence. Static absence supports, but never substitutes for, the behavioral tests above.

```bash
# Legacy shell and compatibility state
rg -n 'SidebarView|AppNavRail|NavItemWithStatusView|BottomNavItemView|SidebarToggle|ClickThroughView|useLegacyHomeDesign|usesLegacyHomeDesign|showsPrimarySidebar|isSidebarCollapsed' \
  desktop/macos/Desktop desktop/macos/Desktop/Tests desktop/macos/e2e desktop/macos/scripts \
  --glob '!**/windows/**'

# Feature Tiers only; do not confuse billing/model QoS tiers with this product
rg -n 'TierManager|currentTierLevel|lastSeenTierLevel|userShowAllFeatures|Feature Tiers|requiredTier|tierChanged|Unlocks at Tier' \
  desktop/macos/Desktop desktop/macos/Desktop/Tests desktop/macos/e2e desktop/macos/scripts docs \
  --glob '!**/windows/**'

# Raw deleted page and stale E2E expectations, limited to navigation owners
rg -n 'case 2:|selectedTabIndex: 2|rawValue: 2|rawValue\) == 2|page.index.2' \
  desktop/macos/Desktop/Sources/MainWindow desktop/macos/Desktop/Sources/OmiApp.swift \
  desktop/macos/Desktop/Sources/DesktopAutomationBridge.swift desktop/macos/Desktop/Tests \
  desktop/macos/e2e desktop/macos/scripts/omi-ctl

# Home-only duplicate owners/residue
rg -n 'DashboardViewModel|dashboardViewModel|dashboardNetworkRefresh|home_connect|DashboardIntelligenceStore|HomeStatusStore|homeKnowsList' \
  desktop/macos/Desktop desktop/macos/Desktop/Tests desktop/macos/e2e \
  --glob '!**/windows/**'

# Deleted product destinations in live shell/Settings only
rg -ni 'Apps Installed|AppsPage|Brain Map|Browser Extension|Rescan Files|Dev Mode|Plan Retiring|Daily Summary|Help Center|Privacy Policy|Store Recording|Private Cloud Sync' \
  desktop/macos/Desktop/Sources/MainWindow desktop/macos/Desktop/Tests desktop/macos/e2e desktop/macos/scripts \
  --glob '!**/windows/**'

# Settings search items and real anchors: inspect both sides, then compare via tests
rg -n 'SettingsSearchItem\(|settingId:|settingsCard\(settingId:|SettingHighlightModifier' \
  desktop/macos/Desktop/Sources/MainWindow/SettingsSidebar.swift \
  desktop/macos/Desktop/Sources/MainWindow/Pages/Settings
rg -n 'account\.signout|planusage\.overview|privacy\.privacy' \
  desktop/macos/Desktop/Sources/MainWindow desktop/macos/Desktop/Tests desktop/macos/e2e

# Your Stats authority and rejected cloud/Apps counts
rg -n 'UserStats|loadAdvancedStats|Apps Installed|AI Chat Messages|conversationCount|getScreenshotCount|getTotalFocusSessionCount|getFilterCounts|getLocalGoals|getStats|listChatCatalog' \
  desktop/macos/Desktop/Sources/MainWindow/Pages/Settings desktop/macos/Desktop/Sources/Chat \
  desktop/macos/Desktop/Sources/Rewind desktop/macos/Desktop/Tests
rg -n 'getApps|getInstalledApps|getGoals\(|getConversations\(|getMessages\(' \
  desktop/macos/Desktop/Sources/MainWindow/Pages/Settings desktop/macos/Desktop/Tests

# Exact primary navigation/shortcuts and automation catalog
rg -n 'TopNavigationRoutes|PrimaryNavigationShortcut|navigateToSidebarItem|resolvedAutomationTarget|navigate_via_shortcut|keyboardShortcut\("[1-6]"|Cmd\+1\.\.5|Cmd\+1\.\.4' \
  desktop/macos/Desktop desktop/macos/Desktop/Tests desktop/macos/e2e desktop/macos/scripts \
  --glob '!**/windows/**'

# Purple regression in changed UI
rg -ni 'purple|#([Aa]020[Ff]0|[89][Bb]5[Cc][Ff]6|[67][Ee]5[Cc][Ff]Ff)' \
  desktop/macos/Desktop/Sources/MainWindow desktop/macos/Desktop/Sources/Theme
```

Classification rules:

- Matches in current product source, active tests, E2E flows, scripts, configuration, or component docs need an owner or deletion.
- Historical changelog/planning text may remain when accurately historical.
- `NSWorkspace`, task “promotion,” model-quality tiers, billing plan tiers, and generic user content are not Feature Tier/Workspace-card residue.
- Semantic automation target `chat` is retained because it opens canonical Home Chat. Raw destination `2` is deleted.
- Windows matches are recorded and ignored; do not inspect or edit Windows code.
- A Settings search row is not proven merely because an ID string occurs somewhere. Its click must mount and highlight the real production control.

## 14. Focused and component-level verification commands

These are future implementation commands. Only the baseline and ledger checks in §2 were run while writing this plan.

### Focused Swift inner loop

From `desktop/macos`:

```bash
python3 scripts/dev-feedback.py --once swift 'DesktopNavigationPolicyTests'
python3 scripts/dev-feedback.py --once swift 'DesktopShellVisibilityTests'
python3 scripts/dev-feedback.py --once swift 'FeatureTierRetirementTests'
python3 scripts/dev-feedback.py --once swift 'HomeShellOwnerTests'
python3 scripts/dev-feedback.py --once swift 'SettingsDestinationContractTests'
python3 scripts/dev-feedback.py --once swift 'YourStatsLocalAuthorityTests'

xcrun swift test --package-path Desktop --filter TopNavigationBarLayoutTests
xcrun swift test --package-path Desktop --filter InsightsHubNavigationTests
xcrun swift test --package-path Desktop --filter HomeKnowsComposerTests
xcrun swift test --package-path Desktop --filter HomeStageCloseSemanticsTests
xcrun swift test --package-path Desktop --filter HomeSuggestionsStoreTests
xcrun swift test --package-path Desktop --filter HomeChatCatalogTests
xcrun swift test --package-path Desktop --filter ChatErrorStateTests
xcrun swift test --package-path Desktop --filter StartupWarmupPolicyTests
xcrun swift test --package-path Desktop --filter SettingsSearchContractTests
xcrun swift test --package-path Desktop --filter AutomationSettingsSectionTests
xcrun swift test --package-path Desktop --filter DesktopAutomationSecondaryActionTests
xcrun swift test --package-path Desktop --filter BillingAvailabilityTests
xcrun swift test --package-path Desktop --filter DailySummaryRetirementTests
xcrun swift build -c debug --package-path Desktop
```

The first six filters are planned new behavioral suites and become valid only after their files join the existing `Desktop/Tests` target. Use `dev-feedback.py --watch` while editing only after the first RED is captured. Prefer real temporary local databases, owner fixtures, production policies, and recording external adapters. Label any unavoidable source-inspection test as a static tripwire.

Run affected predecessor keep suites selected by the execution diff, including local Conversation/Memory/Task/Focus/Insight/Chat owner tests, S-09 consent/feedback/diagnostics tests, S-18/S-20 presentation tests, Rewind tests, capture/listening tests, shortcut tests, and same-UID ABA tests. Run:

```bash
./scripts/agent-logic-harness.sh
./scripts/desktop-core-harness.sh --self-check --skip-backend-contracts
./test.sh
```

`./test.sh` is the official component runner and must pass before S-21 closes. Baseline comparison may diagnose ownership, but it cannot waive an inherited red suite. Fix S-21-owned regressions here; close independently owned suite debt separately before this slice is marked closed.

### Repository gates

From the repository root:

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
make preflight
scripts/pr-preflight --suggest
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
```

Before a future first commit, verify the installed linked-worktree-safe hook:

```bash
test -x "$(git rev-parse --git-path hooks)/pre-commit" && echo OK
```

Format only changed Swift files with `desktop/macos/scripts/swift-format-wrapper.sh format -i <files>`. If a `fix:` commit is justified, add the required `Failure-Class` trailer and run `scripts/failure-class validate --pr-body-file /tmp/pr-body.md --base origin/main --head HEAD`; otherwise declare `Failure-Class: none` in the PR evidence if preflight selects that outcome.

No OpenAPI regeneration, backend route policy, generated app client, schema migration, deployment check, or backend suite is expected from S-21. If the diff unexpectedly requires one, stop and identify the predecessor/owner conflict rather than silently expanding scope.

## 15. Real named-bundle and retained user-path acceptance

Use only the assigned non-production bundle. Never launch, stop, overwrite, or inspect `/Applications/Omi.app`, `/Applications/Omi Beta.app`, `com.omi.computer-macos`, or `com.omi.computer-macos.beta`.

Start the repository's offline local stack and bundle using the current documented harness:

```bash
make dev-up
make desktop-run-local DESKTOP_APP_NAME=omi-wave3-s21 DESKTOP_USER=alice
```

Use the worktree-specific port printed by the launcher. From `desktop/macos` in another shell:

```bash
OMI_AUTOMATION_PORT=<PORT> ./scripts/omi-ctl wait-ready 90
OMI_AUTOMATION_PORT=<PORT> ./scripts/omi-ctl health
OMI_AUTOMATION_PORT=<PORT> ./scripts/omi-ctl state

python3 scripts/omi-harness run e2e/flows/navigation.yaml \
  --lane bridge --port <PORT> --bundle-id com.omi.omi-wave3-s21
python3 scripts/omi-harness run e2e/flows/home-stage.yaml \
  --lane bridge --port <PORT> --bundle-id com.omi.omi-wave3-s21
python3 scripts/omi-harness run e2e/flows/keyboard-shortcuts.yaml \
  --lane bridge --port <PORT> --bundle-id com.omi.omi-wave3-s21
python3 scripts/omi-harness run e2e/flows/privacy-settings.yaml \
  --lane bridge --port <PORT> --bundle-id com.omi.omi-wave3-s21
python3 scripts/omi-harness run e2e/flows/about-settings.yaml \
  --lane bridge --port <PORT> --bundle-id com.omi.omi-wave3-s21
python3 scripts/omi-harness run e2e/flows/plan-usage.yaml \
  --lane bridge --port <PORT> --bundle-id com.omi.omi-wave3-s21
./scripts/desktop-core-harness.sh --tier 2 --bundle omi-wave3-s21 --port <PORT>
```

Acceptance ledger:

1. **Clean and stale-default launch:** launch once clean, then with old Home/tier keys seeded. Both land on identical Home; no migration, lock, rail, hidden page, or redirect appears.
2. **Primary routes:** wide and minimum-width top bars expose Home, Memory, Tasks, Insights with persistent Capture/Listening/Settings and no overlap. Memory exposes Memories/Conversations. Insights defaults to Insights and switches to Focus. Rewind opens through the retained menu/global command.
3. **Commands and Escape:** real Cmd+1/2/3/4, Cmd+comma, Cmd+Option-R and bridge equivalents agree. Child Escape closes local presentations first. Unhandled Escape from Conversations/Memories/Tasks/Rewind goes Home; Insights/Home/Settings/Permissions remain.
4. **Deleted routes:** Apps, Brain Map, Board, standalone Chat raw `2`, old Home/sidebar, Feature Tiers, and rejected Settings cards are absent. Unsupported local automation/raw input is explicit and does not change pages. Semantic `chat` opens Home with `selectedTabIndex == 0` and `homeMode == chat`.
5. **Home:** verify empty and history-aware resting modes, one mixed list only, exact greeting/brief, Task open/hide, Insight open/read/dismiss, questions/tip, catalog CRUD/search/star, composer/send/stop, attachment with text, all error forms, static welcome, citations, capture/listening, explicit mode choice, reduced motion, and narrow/wide Ask widths.
6. **Lifecycle:** start offline, return foreground repeatedly, restart same bundle, and prove only surviving owners refresh. There is no cloud Dashboard/connector/goal/intelligence/count work and no duplicate Task fetch/publication.
7. **Settings search:** query and activate every catalog item. Each result selects the correct grouped section, reaches a real control, and highlights it. Confirm the exact deleted rows and preserved word-AND matching/no-results state.
8. **Retained Settings:** exercise General/font/window reset, Transcription/VAD, Floating Bar/PTT/voice/screen sharing, local notifications, Rewind settings, Ask Mode default-off and toggle behavior, AI Profile, Enhanced Diagnostics, Report Issue from both entrances, offline Save Diagnostics, updates, and reset/onboarding handoff without changing their decided behavior.
9. **Privacy/About:** verify S-09's factual data-location card, What We Track, PostHog-only preference and separate Sentry behavior; no duplicate guarantees/fake Active. About has no Help Center, local **Privacy & Data** opens the retained Privacy page, and update/website/release/Terms rows retain their current pre-S-29 destinations and behavior.
10. **Your Stats:** seed distinct local values and verify every retained row and no Apps Installed. Disable the network and restart; counts persist. Suspend reads across Alice-to-Bob and Alice-to-nil-to-Alice, prove no late Alice projection under Bob/new Alice, then return to the original Alice database and verify its counts.
11. **Tasks/Rewind:** exercise grouped Task create/edit/complete/reopen/delete/Undo and verify no Board. Exercise Rewind capture/search/navigation/settings/restart so sidebar deletion cannot remove its only controls.
12. **Disabled billing/fair use:** `BILLING_MODE=disabled` shows the retained Account & Plan/usage projection and literal Skip where appropriate. Inspect local logs and bridge snapshots for zero checkout/portal/provider calls and no entitlement/quota mutation. Do not run Dodo test/live acceptance.
13. **Logs and isolation:** read the exact bundle log through `./scripts/omi-ctl log-path`. Confirm no unsupported route success, stale-owner publication, provider transaction, Crisp poll, Apps/indexing startup, or tier evaluation. Sign out Alice and use a synthetic Bob owner without touching production identity.

Retain screenshots/flow summaries, exact commands, bundle/PID/port/log identity, local store fixtures, and before/after failure classification as PR evidence. The required Tier-2 flows and official affected desktop suite must actually pass before closure.

## 16. Repository closure versus separately authorized live operational closure

### Repository closure owned by S-21

- one compiled navigation shell and one canonical Home Chat route;
- no tier/legacy/sidebar/deleted-destination caller in current source;
- truthful Settings search and assigned About rows;
- owner-local stats with no Apps/backend product-data count;
- current tests, E2E flows, docs, and changelog aligned with the surviving shell;
- exact residue searches classified;
- named-bundle acceptance and repository gates recorded.

### Live operational closure not authorized by S-21

S-21 owns no live Firestore document, Redis key, GCS object, Typesense/Pinecone index, Cloud Run/GKE service, Cloud Task, secret, IAM binding, provider project, webhook, Dodo customer/product, or release channel. Repository cleanup does not authorize any external mutation.

- S-09 separately inventories and proves the owned PostHog/Sentry projects. Missing live-project proof keeps S-09 operational acceptance open but does not block S-21 repository closure after the tested consent/Privacy seam is integrated.
- Post-Wave-6 S-18 separately activates Dodo test mode, then—under new explicit authorization—live mode according to `dodo-integration.md`.
- S-27/S-29 separately own infrastructure, deploy, signing, Sparkle, website/legal destinations, and production-family evidence.
- S-28 separately owns clean bundle/storage namespaces. The current named-bundle ID is test evidence, not a final shipping identity.

No backup, retention, legal, rollback, or resource-deletion plan is necessary for S-21 because it performs no live-resource mutation. If execution discovers an apparently exclusive live resource, record a read-only evidence request with its verified owner and stop; never guess its project ID or delete it from this slice.

## 17. Risks, ambiguities, and explicit stop points

| Risk or ambiguity | Safe work that can proceed | Evidence required to reopen / stop point |
|---|---|---|
| S-20 absent | Read-only inventory and unchanged keep tests only | Integrated local-GRDB/transient-GPT-5.1 classifier path, content-free durable enforcement, and final Settings projection. All production cycles stop until present. |
| S-09 repository consent/Privacy seam not integrated | Cycles 1–3 and 5–7 after other gates; inventory current Privacy/search without editing it | One startup-safe PostHog owner, separate Sentry, truthful final cards, and fixed semantic snapshot. Cycle 4 stops; owned-project proof remains S-09 operational evidence. |
| S-18 disabled vs final Dodo | Preserve disabled UI and run zero-call tests | No additional input for S-21. Any request to activate provider is out of scope and stops. |
| Future website/Terms/changelog/product identity unknown | Delete Help Center and rename local Privacy exactly | S-29/S-30 provide owned destinations/identity. S-21 must not guess or remove retained rows. |
| Raw values are used by tests/automation | Keep explicit retained values and migrate all in-tree callers | A proven released external contract requiring deleted raw `2` triggers a stop and explicit sunset decision; never a compatibility page. |
| Escape current source conflicts with exact IR-529 set | Add behavioral RED and remove only Insights | If a later authoritative decision explicitly changes the set. Current code alone is not authority. |
| Local stats owner APIs are incomplete | Add narrow explicit authorization-aware read to the owning store/runtime | Stop if only a cloud read, UI-array count, or mutable global owner is available. Do not fabricate/duplicate. |
| Deleting sidebar removes a hidden retained control | Trace each sidebar child to the current top bar/Settings/About/Permissions owner and test it | Stop before deletion if a retained behavior has no reachable current owner; move that behavior narrowly first. |
| Home refresh removal causes stale Memory/Chat/Tasks | Observe invocation and user-visible state through real owners | Stop if a retained owner lacks its own lifecycle seam. Do not preserve the broad dashboard wrapper by habit. |
| Settings anchor typing expands into a framework rewrite | Type only searchable/mounted destinations | Stop if the design becomes a dynamic registry or forces unrelated Settings refactors; use the smallest compiler-first contract. |
| S-21 deletion exceeds PR size warning due to 1,655-line sidebar | Report size and keep commits/cycles independently reviewable inside one coherent PR | Split only if a piece is independently verifiable and leaves no temporary dual shell. Never split into a compatibility stage. |
| Inherited 19 Swift and ten T2 failures | Baseline execution head; run focused/component checks to assign ownership | The official affected component suite and required flows must be green before S-21 closes; independently owned debt closes first rather than being waived. |
| A deleted term matches history, Windows, model/billing tier, or `NSWorkspace` | Classify exact caller/context | Do not edit unrelated/historical/Windows code to make `rg` empty. |
| Full acceptance needs production app/provider credentials | Use only local stack, synthetic users, and named bundle | Stop. Production apps and external credentials are prohibited for this slice. |

No genuine unresolved product choice remains inside S-21. The missing inputs are predecessor integration/evidence and later owned destinations, all with named owners above.

## 18. Final completion checklist

### Entry and ownership

- [ ] Execution head contains Wave 2 closeout plus integrated S-05–S-07, S-09–S-15, S-17, disabled S-18, and S-20.
- [ ] `make setup`, hook check, ledger validator, rebase/inventory refresh, and unchanged execution-head test baseline are recorded.
- [ ] Shared-file changes consume predecessor public seams and do not recreate compatibility paths.
- [ ] One `RuntimeOwnerAuthorizationSnapshot` crosses every new asynchronous local read/publication boundary.

### Navigation and legacy deletion

- [ ] One typed destination policy owns visible routes, commands, raw input validation, Escape eligibility, and automation resolution.
- [ ] Home/Memory/Tasks/Insights order, subgroup behavior, retained raw values, Settings, Permissions, and Rewind are exact.
- [ ] Cmd+1/2/3/4, Cmd+comma, Cmd+Option-R, and exact four-destination Escape behavior pass.
- [ ] Raw `2/6/8`, Apps, Brain Map, old Home, old sidebar/AppNavRail, and unknown routes fail closed.
- [ ] Feature Tiers, keys, migrations, thresholds, reads, locks, redirects, UI, analytics, docs, and exclusive tests are gone; billing/quota/fair use remain.

### Home and local owners

- [ ] Home renders one mixed list and preserves every IR-500–IR-530 retained behavior.
- [ ] `TasksStore` is the only Home Task projection; `DashboardViewModel` and exclusive warmup/reset state are gone.
- [ ] Startup/foreground work belongs only to surviving owners; offline/restart and owner-switch tests pass.
- [ ] Semantic Chat opens canonical Home; no hidden/raw page or duplicate presenter remains.
- [ ] Capture/Listening, explicit mode, responsive layout, exact widths, reduced motion, errors, catalog, attachments, and neutral/no-purple presentation pass.

### Settings and stats

- [ ] Nine Settings groups and all retained controls are reachable; Ask Mode is default-off under Advanced AI Setup.
- [ ] Every search result selects and highlights a real mounted control; all assigned broken/phantom entries are absent without changing word-AND semantics.
- [ ] S-09 Privacy/PostHog/Sentry/diagnostic/report/export result is consumed once, not reimplemented.
- [ ] Account & Plan consumes disabled S-18 and S-20 result; no provider transaction or entitlement mutation exists.
- [ ] Help Center is absent; **Privacy & Data** is a local shortcut; website/Terms/update/release behavior is preserved for S-29/S-30.
- [ ] Your Stats is hidden until requested, owner-local, offline/restart safe, ABA-fenced, includes AI Chat Messages, and has no Apps Installed/backend product-data read.
- [ ] Grouped Tasks remains and Board is absent; Rewind's exact retained behavior remains.

### Automation, proof, and closure

- [ ] Local automation calls production navigation behavior, keeps semantic Chat-to-Home, rejects unsupported targets explicitly, and exposes no legacy/sidebar snapshot state.
- [ ] Corrected navigation/Home/shortcut/Settings/privacy/About/plan/responsiveness/fault flows pass on `omi-wave3-s21` with exact bundle/PID/port/log evidence.
- [ ] Requirements-ledger validator passes 714/714; focused tests, debug build, agent harness, flow self-check, official desktop suite, residue searches, `git diff --check`, `make preflight`, and PR preflight all pass.
- [ ] Previously inherited suite/flow failures are closed by their owner; no red official affected suite is waived or disguised as baseline debt.
- [ ] Product/component docs and one valid unreleased changelog fragment move with the code where required; no orphan TODO/FIXME/HACK is added.
- [ ] No backend route/schema/generated client, Windows file, production app, external infrastructure, provider credential, transaction, deployment, push, PR, or merge is part of planning. Future landing follows repository authorization rules.
- [ ] Repository closure and later S-09/S-18/S-27/S-29/S-31 live/release closure remain explicitly separate.
