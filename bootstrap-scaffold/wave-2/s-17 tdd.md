# S-17 TDD plan — narrow onboarding and macOS permissions to the retained product

## 1. Slice identity

| Field | Value |
|---|---|
| Slice | **S-17** |
| Wave | **2 — make retained Mac behavior authoritative** |
| Type | User-flow adaptation and dead-flow deletion |
| Primary decisions | **IR-050 through IR-052, IR-124 through IR-169, IR-733 through IR-735** |
| Roadmap source | [`../deletion-map.md`](../deletion-map.md), **S-17 — Narrow onboarding and macOS permissions to the retained product** |
| Decision authority | [`../requirements-challenge.md`](../requirements-challenge.md) |
| Research lead | [`../deletion-slice-research.md`](../deletion-slice-research.md), **Onboarding and permissions** |
| Delivery boundary | One S-17 issue/PR and one closure proof. The eleven behavioral cycles below remain sequential. |

This is an implementation plan, not implementation evidence. Creating this file changes no product code, test, generated contract, configuration, workflow, documentation outside this plan, or external system.

## 2. Planning status and pinned baseline

**Planning status:** ready for repository implementation after the execution-time entry gate in §5. The repository work has no missing product decision. Final proof that a signed production-family app is actually registered and launched by macOS at login is a later signed-candidate/live-operation gate shared with S-29 and S-31; it does not justify a temporary S-17 compatibility path.

The inspected baseline is:

```text
HEAD 0d9934c9d2ed61bd02ac8784e50f56ee816257c3
     docs(wave1): record S07 closeout evidence
```

The required ancestry check passed during planning:

```bash
git merge-base --is-ancestor 0d9934c HEAD
```

The requirements-ledger validator also passed during planning:

```text
Requirements ledger validation: PASS (714 indexed rows, 714 detailed sections, all reviewed)
```

At this snapshot, `origin/main` is behind the integrated Wave 1 follow-up baseline. Do not reset the implementation to that older tree. Before RED, fetch the target branch and integrate its latest work while preserving `0d9934c` as an ancestor; then repeat the inventories and tests named below. Untracked Wave 2 plans in the planning workspace are not integrated predecessor code and are not inputs to S-17.

No product tests or user paths were run while writing this plan. Commands outside the two read-only checks above are future execution requirements.

## 3. Outcome

Ship one fixed conversational first-run flow with this exact retained sequence:

```text
promise/trust
  -> name
  -> acquisition source
  -> spoken language
  -> microphone
  -> System Audio
  -> Screen Recording
  -> Accessibility
  -> open-Omi shortcut
  -> PTT shortcut
  -> real screen-aware PTT demo
  -> meeting-only or continuous listening
```

The flow has two deliberately different exits:

- **Genuine completion** records completion, enables Launch at Login, enables permission-gated proactive screen monitoring, arms listening in the chosen local mode, shows the local completion opener, finishes and clears the setup-only journal, and lands on Home.
- **Global Skip** records a skipped outcome, explicitly leaves Launch at Login, transcription, and screen monitoring off, shows no “set up and listening” opener, finishes and clears the setup-only journal, and lands neutrally on Home.

Permission grants are consent only. Granting Microphone, System Audio, Screen Recording, or Accessibility must not itself start audio capture, transcription, or ongoing screen monitoring. Accessibility is requested and described only for global PTT plus precise Rewind/Focus window detection; the existing CGWindow path remains the fallback.

Name is local plus Firebase Auth display name. Acquisition is local plus one bounded PostHog event. Spoken language is local voice-assistant state. There is no role answer, backend onboarding document, backend/Firestore name duplicate, onboarding language synchronization, Calendar enrichment, Full Disk Access/file scan, Apple Events Automation setup, connector setup, stored post-onboarding suggestions, or AI-driven/model-controlled onboarding engine.

## 4. Authorizing requirements

The live ledger and deletion map agree on the S-17 boundary. The detailed decision sections were re-read, not inferred from their index summaries.

| Decisions | Required S-17 outcome | Protecting cycle(s) |
|---|---|---|
| IR-050, IR-137 | Delete the Apple Events Automation permission/setup lifecycle. Preserve the differently named non-production `DesktopAutomationBridge`. | 4, 11 |
| IR-051, IR-135 | Delete Full Disk Access setup, broad file scanning, and profile-memory formation. Preserve historical changelogs and the terminal-host TCC diagnostic note as non-product history/tooling. | 4 |
| IR-052, IR-136 | Keep Accessibility only for global PTT and precise Rewind/Focus window detection, with CGWindow as fallback; remove click/type claims. | 4 |
| IR-124 | Keep acquisition local plus bounded PostHog and keep the existing negative backend onboarding-route contract. The separate `/v4/listen` `OnboardingHandler` belongs to IR-395/S-16: S-17 neither edits nor retains it and must not restore it after S-16 deletes it. | 2, 3 |
| IR-125 | Keep the narrowed fixed conversational setup as the sole active onboarding flow. | 1-11 |
| IR-126 | Keep the opening trust screen and Setup/Skip presentation. Defer identity and broad promise truth to S-30. | 1 |
| IR-127 | Keep global Skip on every active screen and report **skipped**, not completed. | 6 |
| IR-128 | Keep the name screen, local name, and Firebase Auth display name; delete Mac backend reads/writes and the Firestore/profile duplicate. | 2, 3 |
| IR-129 | Keep acquisition screen, local answer, and bounded PostHog event; no backend persistence. | 2 |
| IR-130 | Keep spoken-language screen and local `voiceLanguages`; delete only onboarding's cloud-language write. Retained Settings/Chat language behavior is not deleted. | 2 |
| IR-131 | Delete the role screen, `onboardingRole`, copy, drafts, navigation, and tests. | 1 |
| IR-132 | Keep optional Microphone permission; a grant alone never starts recording. | 4 |
| IR-133 | Keep optional System Audio verification through a real process tap; recording waits for the final choice. | 4 |
| IR-134 | Keep optional Screen Recording setup and the discarded prime capture; grant alone never enables monitoring. | 4 |
| IR-138 | Keep open-Omi shortcut choices, persistence, registration suspension, and rehearsal unchanged. | 1, 4 |
| IR-139 | Keep Fn/Option/Control PTT selection and persistence unchanged. | 1, 4 |
| IR-140 | Keep the skippable production-path screen-aware PTT demo and isolated temporary history. | 4, 10 |
| IR-141, IR-142 | Keep S-06's deletion of agent/context connector screens. Preserve local managed Pi, the private bridge, explicit attachments, and the onboarding journal. | 1, 10 |
| IR-143 | Keep meeting-only as primary and continuous as secondary; meeting-only arms a session whose mic/System Audio remain idle outside a detected call; replace the false Calendar explanation. | 5 |
| IR-144 | Show a local opener after genuine completion only. Delete Calendar enrichment and skipped-flow listening claims. | 6-8 |
| IR-145 | Genuine completion explicitly enables Launch at Login and discloses it; Skip leaves it off; Settings retains its off switch. | 6, 8, 9 |
| IR-146 | Delete the already-onboarded Omi login-item migration, its call, marker, copy, and tests. | 9 |
| IR-147 | Keep the separate onboarding-aware AppKit relaunch-at-logout policy unchanged. | 9 |
| IR-148 | Genuine completion enables permission-gated screen-monitoring intent in both listening modes; Skip does not. | 6, 8 |
| IR-149 | Keep local stage resume, draft restoration, and permission recheck. Correctly evolve the local marker across role deletion. | 1, 11 |
| IR-150 | Keep one-step Back and editable revision behavior; grants remain truthful. | 1, 2 |
| IR-151 | Keep simulated typing, delayed controls, and cancellation lifecycle. | 1 |
| IR-152 | Keep no progress count/dots/finish line. | 1 |
| IR-153 | Keep the current in-memory transcript and old bubbles after Back. | 1 |
| IR-154 | Keep S-06's deletion of the 18-page wizard and page-only state; preserve only live helpers. | 1, 11 |
| IR-155 | Keep one shared sign-out/reset cleanup helper, narrowed to retained conversational state. | 11 |
| IR-156 | Keep confirmed Advanced Settings reset. | 11 |
| IR-157 | Keep immediate signed-in status-menu reset. | 11 |
| IR-158 | Keep `reset_onboarding` on non-production bundles only; never expose it in beta/stable. | 11 |
| IR-159 | Keep ordered async writes only for Firebase name revisions; delete acquisition/language cloud-write branches. | 2 |
| IR-160 | Delete the orphaned suggestion store, popup/banner/view/notification wiring, and dead readers; keep `HomeSuggestionsStore` and the completion opener. | 7 |
| IR-161 | Delete the unreachable AI onboarding persistence, callbacks, tools, generated dispatch, policy, fixture, and exclusive tests. Preserve generic permission tools, normal Chat/PTT, local managed Pi, onboarding journal isolation, and live demo. | 10 |
| IR-162 | Keep Return as the default action on retained primary controls. | 1 |
| IR-163 | Keep onboarding auto-scroll unchanged. | 1 |
| IR-164 | Keep the centered 540 x 640 conversational panel unchanged. | 1 |
| IR-165 | Keep the shared sign-in/onboarding backdrop seam. S-30 replaces its identity/artwork. | 1 |
| IR-166 | Keep `SBWallpaper` animated fallback unchanged. | 1 |
| IR-167 | Keep on-disappear shortcut cleanup unchanged. | 1, 4 |
| IR-168 | Keep the existing partial unexpected-disappearance cleanup; do not broaden it into an unreviewed teardown. | 1, 4 |
| IR-169 | Keep horizontal-first `ViewThatFits` with vertical Back/Skip fallback. | 1 |
| IR-733 | Keep `--skip-onboarding` as the exact direct completion-flag bypass in all builds. It must not call either visible Skip or completion policy. | 9 |
| IR-734 | Closing the last pre-completion window terminates the process; after completion the menu-bar process remains. | 9 |
| IR-735 | Keep the completion flag as UI winner and emit content-free disagreement diagnostics for resume/journal conflict. | 9 |

Revalidation rule: if any detailed decision changes before implementation, stop the affected cycle, update the roadmap/plan through the requirements process, and do not silently select a competing interpretation.

## 5. Dependencies and entry gates

### Predecessor state

| Owner | Current integrated evidence consumed by S-17 | S-17 stop condition |
|---|---|---|
| S-06 | The paged wizard, connector stages, Full Disk Access stage, and Automation stage are absent from the active `SBOnboardingModel.Step` graph. Local managed Pi, the private `OMI_BRIDGE_PIPE`, explicit attachments, `DesktopAutomationBridge`, and the local onboarding journal remain. | Stop if the refreshed tree restores a second active onboarding renderer/connector stage or makes the old AI flow reachable; resolve owner order rather than deleting a live predecessor path opportunistically. |
| S-07 | Customer BYOK is absent from active setup and managed-provider behavior is retained. | Stop if a setup stage again requires a customer key; do not recreate BYOK or change managed provider selection in S-17. |
| S-08 | `/v1/users/onboarding` GET/PATCH and the acquisition writer are gone; `test_backend_onboarding_state_is_not_exposed` protects 404. The current acquisition recorder is local plus analytics. | Stop if the negative route contract regresses or if acquisition again depends on a backend. Preserve S-08 auth/session/sign-out ordering. |

All three relevant predecessor repository tranches are present at `0d9934c`. S-17 has no Wave 2 predecessor. S-08's later export/deletion/platform gates do not block the S-17 user flow, but S-17 must hand the filtered account-profile/export name boundary back to S-08's final export acceptance.

### Mandatory execution-time entry gate G0

Before the first RED:

1. Run `make setup` as required before the first commit, fetch `origin`, keep the current branch name, and integrate current target-branch work without losing the Wave 1 baseline.
2. Require `git merge-base --is-ancestor 0d9934c HEAD` to pass and record `git rev-parse HEAD origin/main`.
3. Rerun the requirements validator and re-read all assigned detailed decisions.
4. Rerun the inventories in §§6-7 and residue commands in §13. New callers are classified, not guessed away.
5. Run the existing focused onboarding, permission, auth/profile, generated-tool, journal, and lifecycle tests to separate pre-existing failures from the intended RED.
6. Run `scripts/pr-preflight --suggest` after an intended diff exists. If a `fix:` commit is used, declare and validate the required failure class.

Stop if `0d9934c` is absent, a live ledger conflict appears, the old wizard or backend onboarding record has returned, a released external client is proven to require a contract being removed, or a retained name/profile consumer cannot move to Firebase without a new product decision. No no-op, deprecated alias, ignored field, or fake-success response may bridge a stop.

### Live/signed-candidate gate G1

`LaunchAtLoginManager` deliberately refuses registration for named non-production bundles. Hermetic tests can prove the exact `setEnabled(true/false)` decisions, and a named bundle can prove completion/relaunch/capture restoration, but actual macOS login-item registration plus login/reboot launch requires S-29's owned signed production-family candidate and separate release-machine authorization. Record that proof for S-31. Never automate or restart `/Applications/Omi.app` or `/Applications/Omi Beta.app` for S-17.

## 6. Current production codeflow

### Active entry and resume

```text
OmiApp.shouldSkipOnboarding()
  -> DesktopHomeView auth/onboarding gate
     -> direct --skip-onboarding flag sets hasCompletedOnboarding only
     OR
     -> SBOnboardingView
        -> SBOnboardingModel.init
           -> beginOnboardingJournal() on local-only AgentSurfaceReference.onboarding()
           -> loadNameFromBackendIfNeeded()
           -> begin() reads sbOnboardingResumeStep
           -> streamMessage() -> showWidget -> per-step live hook
```

`SBOnboardingModel.Step` currently contains `role`; `pickLanguage` advances to it, `goBack` assumes adjacent integer raw values, and `OnboardingFlow.persistedStateKeys` still includes role plus old paged/permission-trigger/goal keys. The in-memory `thread`, typing task, Return shortcuts, layout, backdrop, wallpaper, `ViewThatFits`, shortcut rehearsal, and PTT demo are live retained behavior.

### Answers and backend profile residue

```text
name
  -> OnboardingAnswerWriteGate(.name)
  -> AuthService.updateGivenName
     -> local givenName/familyName
     -> Firebase profile change request
     -> APIClient.updateUserProfile (PATCH /v1/users/profile; no live backend PATCH route)

model init
  -> AuthService.loadNameFromBackendIfNeeded
  -> GET /v1/users/profile
  -> users/{uid}.name, then Firebase fallback

acquisition
  -> OnboardingAcquisitionSourceRecorder
  -> UserDefaults + bounded PostHog (already narrowed by S-08)

spoken language
  -> AssistantSettings.voiceLanguages
  -> OnboardingAnswerWriteGate(.language)
  -> PATCH /v1/users/language
```

The profile GET still returns the entire Firestore profile through `UserProfileResponse(extra='allow')`, including `name`. Backend name fallbacks also read `users/{uid}.name`; conversation export enrichment reads the same duplicate. Firebase already carries Google/Apple display name, including first-Apple-auth repair. S-17 removes the duplicate reader/exposure, not the retained Firebase identity or the whole account metadata route. Settings and generic Chat still call `/v1/users/language`; only the onboarding call is rejected.

### Permissions

```text
permission widget
  -> requestPerm(key)
  -> native permission request / System Settings
  -> bounded poll and truthful recheck
  -> set checkmark and advance
```

Microphone uses `AudioCaptureService.requestPermission`; System Audio waits for Screen Recording and proves consent with `primeSystemAudioPermission`; Screen Recording primes and discards one capture; Accessibility uses AX trust/functional checks. These steps do not currently call capture start directly. The live defect is at the later Home/default restoration boundary and in false Accessibility copy. `AppState.openAutomationPreferences()` is an orphan. There is no current product Full Disk Access stage or Apple Events usage description. Historical release changelogs and the terminal-host FDA note in `cleanup-omi-tcc.sh` are not live product support.

### Listening, Skip, and completion

```text
capture(selection)
  -> persist systemAudioCaptureMode
  -> complete(startListening: continuous only)

skip()/complete()
  -> teardown tasks/monitors
  -> both emit Onboarding Completed
  -> both set onboardingJustCompleted
  -> both present completion opener
  -> both finish setup journal and set completion flag

complete only
  -> GoalGenerationService.generateNow()
  -> preserve stale launchAtLogin snapshot rather than force true
  -> enable/start screen monitoring except lazy-dev branch
  -> start transcription immediately only for continuous
  -> reconcile capture
```

`AssistantSettings` registers both `transcriptionEnabled` and `screenAnalysisEnabled` as true. `DesktopHomeView` additionally runs `screenAnalysisAutoStartFixed_v2` and named-bundle `v3` migrations before restoring persisted capture. Therefore visible Skip can enter Home with both intents/defaults true and start retained services even though `skip()` contains no direct start call.

`reconcileCapture()` already implements the retained meeting-only behavior correctly once a transcription session exists: it runs the meeting detector, leaves mic/System Audio idle outside a call, and starts/stops them as call state changes. The target is to make onboarding choose the persisted intent explicitly and reuse this owner, not duplicate meeting detection.

### Journal, opener, and obsolete AI support

The retained setup journal is `ChatProvider+OnboardingJournal.swift` -> `KernelTurnProjection` -> Node conversation journal/SQLite, with `surface_kind=onboarding` local-only and no backend outbox. It is used by the live PTT demo and must stay.

The different `OnboardingChatPersistence` stores two AI-engine booleans. The generated dispatch special-cases `set_user_preferences`, `ask_followup`, and `complete_onboarding`; `ChatToolExecutor` owns callbacks and completion logic; the agent manifest/policy/fixture and tests retain the unreachable tool family. Those are deleted while `request_permission` and `check_permission_status` remain normal Chat/realtime tools.

`PostOnboardingPromptSuggestions` has no live writer but stale defaults can still feed `ChatProvider.presentOnboardingOpener`, Dashboard suggestions/banner, and the Try Asking popup. `OnboardingOpenerComposer` still models meetings even though its live caller supplies `[]`. These are dead alternate inputs, not keep boundaries.

### Reset, sign-out, and app lifecycle

- Advanced Settings calls the confirmed reset; the signed-in status menu and non-production `reset_onboarding` action call immediate `AppState.resetOnboardingAndRestart()`.
- Reset and sign-out call `OnboardingFlow.clearPersistedState`; both also clear the obsolete AI persistence. Reset clears the real setup journal and restarts the same bundle.
- `migrateLaunchAtLoginDefault()` still runs at launch with `didMigrateLaunchAtLoginV1`; this is the rejected Omi-profile migration.
- `applicationShouldTerminateAfterLastWindowClosed` uses the completion flag exactly as IR-734 requires.
- `updateOnboardingLifecyclePolicy` separately controls AppKit relaunch-at-logout and must stay.
- `DesktopHomeView.hasCompletedOnboardingAtAuthorityRead` and `SBOnboardingModel.begin()` emit content-free authority disagreement signals while the completion flag wins.

## 7. Complete caller and dependency inventory

The table records the verified live S-17 surface. Before S-16 lands, broad `onboarding` searches also match the separately owned `/v4/listen` questionnaire; after S-16 lands, that branch must be absent. Normal analytics words, historical changelogs, Windows, and local journal schema are classified rather than bulk-deleted.

| Area | Current owners/callers | Planned disposition |
|---|---|---|
| Active flow/model/view | `Onboarding/SecondBrain/SBOnboardingModel.swift`, `SBOnboardingModel+Steps.swift`, `SBOnboardingView.swift`, `SBOnboardingLanguageCopy`, `OnboardingAnswerWriteGate.swift`, `OnboardingAcquisitionSourceRecorder.swift` | Keep one flow; remove role/cloud answer branches; establish explicit outcome/effect seams; preserve retained UI/lifecycle details. |
| Entry/Home | `OmiApp.swift`, `MainWindow/DesktopHomeView.swift`, `ViewModelContainer`, `MainWindow/OnboardingOpenerView.swift` | Keep auth/completion gate, direct CLI bypass, Home landing, and main provider; delete legacy capture/login migrations and distinguish completion from Skip. |
| Local settings/capture | `AssistantSettings.swift`, `AppState+Transcription.swift`, `SystemAudioCaptureService.swift`, `ProactiveAssistantsPlugin`, `MeetingDetector`, `PersistedCaptureLaunchPolicy` | Make outcome persist explicit intent; reuse the existing capture/meeting/monitor owners. No second coordinator. |
| Permission owners | `AppState+SystemActions.swift`, `AppState+Permissions.swift`, `ScreenCaptureService.swift`, `PermissionGuidanceOverlay.swift`, `OverlayService.swift`, `GlobalShortcutManager.swift`, `PushToTalkManager.swift` | Retain Microphone/System Audio/Screen/Accessibility behavior and AX->CGWindow fallback; delete only Automation opener and false onboarding claims. |
| Login/lifecycle | `LaunchAtLoginManager.swift`, `OmiApp.AppDelegate`, Settings General/Advanced sections | Genuine completion always requests enable; Skip requests disable; keep Settings toggle and AppKit relaunch policy; delete legacy migration. |
| Local persistence | `OnboardingFlow.swift`, `DefaultsKey.swift`, `ChatDraftStore`, `ChatProvider+OnboardingJournal.swift`, `KernelTurnProjection`, `AgentRuntimeStatusStore`, agent `conversation-journal.ts`/`sqlite-store.ts` | Keep acquisition, resume, completion landing marker where needed, drafts, and local-only setup journal. Remove old wizard/role/goal/trigger keys and AI booleans. No GRDB schema migration is needed beyond retained local journal behavior. |
| Auth/name Mac | `AuthService.updateGivenName`, `loadNameFromBackendIfNeeded`, `APIClient+Settings.get/updateUserProfile`, `UserProfileResponse` | Firebase plus local only; keep owner/ABA fencing and serialized revisions; remove onboarding profile network calls and hand-written DTO if caller-free. |
| Auth/name backend | `routers/users.py::UserProfileResponse/get_user_profile_endpoint`, `database/auth.py::_get_firestore_user_name`, `utils/conversations/render.py::populate_speaker_names`, `services/users/data_export.py` | Remove `users.name` as reader/response/export authority; use Firebase name at retained backend call sites; retain other account metadata and hand final export composition to S-08. No live Firestore mutation in this slice. |
| Backend onboarding negative contract | `backend/testing/e2e/test_user_auth_profile.py` | Keep GET/PATCH `/v1/users/onboarding` failing 404. Do not restore a deprecated handler. |
| Backend language | `/v1/users/language`, `APIClient.updateUserLanguage`, Settings update code, generic Chat `set_user_preferences` predecessor residue | Remove only the onboarding writer; preserve route/Settings until their owning decisions say otherwise. The AI-only tool is deleted in Cycle 10. |
| Completion opener | `OnboardingOpenerComposer.swift`, `ChatProvider.presentOnboardingOpener`, `OnboardingOpenerView`, `HomeSuggestionsStore` | Keep a local completion-only greeting/listening summary and normal local starter questions; delete meeting input and orphan suggestion input. |
| Orphan suggestions | `OnboardingPromptSuggestions.swift`, `PostOnboardingPromptViews.swift`, `DashboardPage`, `DesktopHomeView.showTryAskingPopup`, `.showTryAskingPopup`, `ChatProvider` | Delete complete family after behavior test proves stale values are ignored. |
| AI onboarding engine | `OnboardingChatPersistence.swift`, `ChatToolExecutor` onboarding callbacks/executors, `ChatProvider` ask-followup formatting, `omi-tool-manifest.ts`, `desktop-tool-policy.ts`, `generate-tool-surfaces.mjs`, generated Swift, fixture, manifest/tool tests | Delete the three onboarding-only tools and exclusive support. Regenerate, do not hand-edit generated output. Preserve generic permission tools and local journal. |
| Analytics | `AnalyticsManager`, `PostHogManager`, acquisition recorder, model exits | Add one bounded skipped event; keep completed/acquisition and content-free live-demo/journal telemetry; remove only tool events made exclusive by deleted AI tools. S-09 owns provider/project/consent redesign. |
| Reset callers | `SettingsContentView+Assistants`, Omi status menu, `DesktopAutomationBridge.reset_onboarding`, `AuthService.signOut`, `AppState+SystemActions` | Keep all three reset entrances and sign-out ordering; make one narrowed cleanup boundary and stop both capture services before replay/sign-out. |
| Tests | `OnboardingFlowTests`, `SBOnboarding*Tests`, `OnboardingAcquisitionSourceTests`, `OnboardingAnswerWriteGateTests`, `OnboardingPermissionToolTests`, `PersistedCaptureLaunchPolicyTests`, `OnboardingPersistenceClearingTests`, `OnboardingQuerySurfaceIsolationTests`, API/profile tests, journal/agent tests | Replace implementation-string assertions with behavioral calls where possible; keep labelled static tripwires only for forbidden generated/routes/residue contracts. |
| E2E/docs | `e2e/flows/onboarding-flow.yaml`, `onboarding-smoke.yaml`, `e2e/SKILL.md`, `CORE_E2E.md`, component guides, changelog fragments | Rewrite stale Goal/Tasks flow to the real sequence and both exits; retain reset/restart safety; update component docs only for changed behavior/commands and add one user-visible changelog fragment. |
| Historical/non-owner matches | `changelog/releases/**`, `cleanup-omi-tcc.sh` terminal-host FDA note, pre-S-16 `/v4/listen` `OnboardingHandler`, `DesktopAutomationBridge`, Windows | Preserve/classify the historical/tooling matches. Treat `OnboardingHandler` only as an IR-395/S-16 handoff when S-16 is not integrated; never restore it after S-16. |

No S-17-exclusive Redis key, object/vector storage, background job, deployed service, secret, alert, or infrastructure manifest was found. The only durable backend duplicate in scope is the Firestore profile-name field as a current reader/response/export input; repository authority removal precedes any separately authorized historical-data cleanup.

## 8. Behavior classification

| Category | Exact S-17 boundary |
|---|---|
| **KEEP AS IS** | Conversational shell; trust opener; Setup and global Skip controls; name/acquisition/language screens; optional Microphone/System Audio/Screen Recording/Accessibility screens; bounded polling; real System Audio tap; discarded ScreenCaptureKit prime; open/PTT shortcut selection and rehearsal; real screen-aware PTT demo; meeting-only and continuous choices; local setup journal isolation; resume, Back, typing, no-progress, memory-only transcript, auto-scroll, Return actions, 540 x 640 centered layout, shared backdrop seam, animated fallback, shortcut cleanup, current partial unexpected cleanup, `ViewThatFits`; confirmed Settings reset, immediate status reset, non-production automation reset; `--skip-onboarding`; pre-completion quit; AppKit relaunch policy; completion-flag UI authority and content-free diagnostics; Settings Launch at Login off switch; generic permission tools; retained managed Pi/Chat/PTT/Rewind/Focus behavior. |
| **ADAPT** | Remove role from the ordered graph and evolve the local resume marker; make name local + Firebase only, acquisition local + bounded PostHog, and spoken language local only; describe Accessibility precisely; replace Calendar listening copy with call detection; establish one explicit local exit policy for `.skipped` versus `.completed(mode)`; explicitly persist capture intents; genuine completion requests login-item enablement and discloses it; Firebase becomes backend name authority and retained account metadata excludes Firestore name. |
| **DELETE** | Role screen/copy/drafts/default; Automation preference opener/setup lifecycle; any live Full Disk Access/file-scan onboarding residue; backend profile name read/write/response/export duplicate; onboarding language PATCH; false Calendar enrichment/claims; `GoalGenerationService.generateNow()` completion side effect; login-item legacy migration/marker; screen auto-start migration branches that override Skip; orphaned suggestion store/popups/banner/view/notification/readers; `OnboardingChatPersistence`; `set_user_preferences`, `ask_followup`, `complete_onboarding` and exclusive callbacks/dispatch/policy/generated fixtures/tests; stale old-wizard/goal/trigger defaults and comments/docs/tests. |
| **SIMPLIFY AFTER** | After all behavioral GREENs, collapse duplicate `skip()`/`complete()` teardown/journal code behind one outcome executor; keep one ordered name-write gate; keep one retained onboarding defaults list; remove unused imports/enums/DTOs/analytics methods; regenerate tool/OpenAPI outputs; update stale flow coverage and docs. Do not refactor normal Chat, capture, AuthSessionCoordinator, Rewind/Focus, or Settings architecture for style. |
| **OUT OF SCOPE / DEFERRED** | Final product/repository name, artwork, BasedHardware link, and broad privacy/memory/cloud promises (S-30); navigation/Settings shell convergence (S-21); local domain-authority work (S-10 through S-15); transient listen protocol and `/v4/listen` questionnaire deletion (S-16); billing/quota (S-18/S-20); model/provider portfolio (S-22); deletion of rejected hosted products and historical Firestore data (S-23); service/platform/storage namespaces (S-25 through S-28); signing/release/login-item proof on a production-family candidate (S-29/S-31); telemetry project/consent redesign (S-09); Windows. |
| **ACCELERATE AFTER** | `none` preselected. Record focused Swift, backend, generated-tool, full component, named-bundle build, and real-flow timings. Improve only measured S-17 friction after correctness. |
| **AUTOMATE LAST** | Rewrite the existing onboarding typed/manual flows around the stable two-exit policy. Use existing bridge/reset/state/log/defaults seams; extend the existing content-free non-production snapshot only if a repeated assertion cannot be expressed otherwise. Register any new check in an existing local and CI lane in the same PR. |

## 9. Retained behavioral invariants

1. `hasCompletedOnboarding` remains the only UI gate. Resume stage and local setup journal may diagnose disagreement but never defeat it.
2. Visible global Skip and `--skip-onboarding` are different public behaviors. The command-line flag remains a direct flag write and invokes no visible exit effects.
3. A native permission result changes permission state only. It does not change capture intent or start audio/screen work.
4. Meeting-only starts a transcription session/meeting detector but mic and System Audio remain off until the detector reports a call. Continuous starts immediately. Both genuine completion modes enable permission-gated proactive monitoring.
5. Skip leaves transcription intent false, screen-analysis intent false, Launch at Login disabled, no opener, no monitoring, and no active transcription across immediate Home entry, app activation, settings sync, and relaunch.
6. Genuine completion always requests Launch at Login enabled. Settings remains the only later user-controlled off switch. A non-production refusal is test-environment behavior, not a changed policy.
7. Name revisions are owner-fenced and serialized; stale completion from a pre-Back answer or previous owner cannot win. No backend profile request participates.
8. Acquisition and spoken language remain usable with network unavailable. Acquisition emits only its bounded approved event.
9. The live PTT demo's local-only onboarding journal is never confused with the deleted two-boolean `OnboardingChatPersistence` or a backend chat record.
10. Back changes one retained step at a time, preserves submitted bubbles and saved editable answers, cancels only the departed permission poll/step work, and never reverses real macOS grants.
11. Reset/sign-out clear only retained setup-owned local state and the local setup journal, stop capture, and never mutate normal main-chat history or backend content.
12. `DesktopAutomationBridge`, `request_permission`, `check_permission_status`, AX/CGWindow logic, explicit attachments, and normal Chat/PTT remain callable after dead onboarding-engine deletion. S-17 does not edit the separate `/v4/listen` questionnaire: it remains an S-16 handoff before S-16 and remains absent after S-16.
13. No current product copy claims Calendar enrichment, click/type Automation, Full Disk Access, or completed/listening status after Skip. S-30 still owns global brand/trust wording.
14. No compatibility shell returns success for a deleted route/tool/field. Removed generated dispatch resolves as unhandled/absent and removed backend routes fail closed.

## 10. Target authority and ownership model

### Small public policy seam

Introduce one feature-scoped, pure decision surface beside the active onboarding model, not in `Desktop/Sources/` root:

```swift
enum OnboardingExit: Equatable {
  case skipped
  case completed(SBOnboardingModel.CaptureSelection)
}

struct OnboardingExitPlan: Equatable {
  let analyticsOutcome: AnalyticsOutcome
  let shouldPresentOpener: Bool
  let shouldLandAsJustCompleted: Bool
  let launchAtLoginEnabled: Bool
  let transcriptionIntentEnabled: Bool
  let systemAudioMode: AssistantSettings.SystemAudioCaptureMode?
  let shouldStartTranscriptionSession: Bool
  let screenAnalysisIntentEnabled: Bool
  let shouldStartMonitoringIfPermitted: Bool
}
```

Names may follow repository conventions, but the behavior and one-call boundary are fixed by the requirements. `SBOnboardingModel` asks the pure policy for a plan, then a narrow effect executor invokes existing owners: Analytics, `LaunchAtLoginManager`, `AssistantSettings`, `AppState`, `ProactiveAssistantsPlugin`, `ChatProvider`, and the completion flag. Tests substitute only these true effect boundaries and assert ordered outcomes. Do not introduce a second capture, login-item, analytics, or journal service.

The execution order is:

```text
tear down step-owned work
  -> persist explicit local intent/mode
  -> request login-item state
  -> start/stop retained runtime owners as the plan directs
  -> finish and clear local setup journal
  -> publish the completion flag and Home landing/opener state
```

Journal completion must finish before the main timeline is exposed. A failed external/non-production login-item request is diagnosed and remains visible in its own status; it does not fake success or reclassify Skip/completion.

### Answer authority

- `AuthService` owns local name projection plus Firebase display-name update and owner fencing.
- `OnboardingAnswerWriteGate` has one retained field: name. Acquisition and language do not enter an async cloud queue.
- `OnboardingAcquisitionSourceRecorder` owns local acquisition plus one bounded event.
- `AssistantSettings.voiceLanguages` owns onboarding's spoken-language choice. Existing backend language Settings/Chat owners remain separate.
- Backend `database.auth.get_user_name` reads Firebase. It no longer falls back to `users/{uid}.name`. The profile route/export explicitly exclude `name`; S-08 later composes final account metadata and S-23 may delete historical fields after live-data authorization.

### Persistence authority

- `OnboardingFlow` enumerates only retained setup defaults. `hasCompletedOnboarding` stays with `AppState`.
- The current raw resume marker gets a bounded local schema conversion for the removed role value; subsequent order must not depend on subtracting raw integers across a deleted case.
- `ChatProvider+OnboardingJournal`/kernel journal owns live demo/setup conversation state. No replacement Boolean persistence is created.
- Normal Chat history, product databases, Firebase tokens, system TCC grants, and user-created data remain outside cleanup.

## 11. Ordered TDD cycles

Each cycle is a vertical tracer bullet. Write only its named behavioral RED, observe the expected failure for the stated reason, make the minimum production change for GREEN, run focused proof, and commit that independently green behavior. Do not bulk-write later tests. Refactoring and automation wait until the responsible GREEN.

### Cycle 1 — remove role while protecting the retained conversation state machine

**RED:** Through `SBOnboardingModel` public actions, assert the exact retained `Step.allCases`, language -> mic advance, mic -> language Back, resume from every retained stage, one-time conversion of the removed role raw marker to mic, editable acquisition/language restoration, transcript preservation, and first-step Back stop. Keep existing behavioral PTT warmup/cleanup tests and clearly labelled static UI tripwires for Return, no-progress, 540 x 640 layout, backdrop/fallback, and `ViewThatFits`.

**Why RED:** `Step` still contains `.role`; `pickLanguage` advances there; `goBack` subtracts raw values; role drafts/defaults/tests are live.

**GREEN:** Remove role enum/UI/message/widget/model/default code. Give retained step order an explicit previous/next mapping that tolerates the deleted raw value, update resume rehydration, and remove stale comments claiming role/backend answers. Do not rewrite streaming timing, transcript, permission checks, shortcut/demo behavior, layout, or artwork.

**Retained behavior:** IR-125/126, IR-138-142, IR-149-154, IR-162-169.

**Expected files:** the three Second Brain files, `OnboardingFlow.swift`, `DefaultsKey.swift`, `OnboardingFlowTests.swift`, `SBOnboardingBackNavigationTests.swift`, related layout/language tests, and stale flow documentation.

**Focused proof:** `OnboardingFlowTests`, `SBOnboardingBackNavigationTests`, `SBOnboardingLayoutTests`, `SBOnboardingLanguageCopyTests`, shortcut/PTT demo tests, and desktop test-quality check.

**Deletion enabled:** role screen, storage key, state, copy, UI, tests, and old wizard keys proven caller-free.

**Stop:** a refreshed active caller uses role for retained behavior or the live ledger changes. Do not keep a hidden role alias.

### Cycle 2 — make onboarding answers local/Firebase authoritative

**RED:** At controllable production seams, drive two Back revisions of name and assert only the newest owner-current Firebase display-name update and local projection win; drive acquisition with a URL protocol that fails any network call and assert one local value/event; drive spoken-language selection and assert local `voiceLanguages`, immediate mic advance, and zero backend calls. Exercise an owner switch between name submissions.

**Why RED:** name still issues ghost backend PATCH and initializes from backend GET; language still queues `/v1/users/language`; the write gate includes `.language`; navigation still targets role before Cycle 1.

**GREEN:** Narrow `AuthService.updateGivenName` to local + Firebase while preserving impersonation and owner/ABA fences; replace backend name loading with Firebase/local loading; remove Mac profile GET/PATCH helpers and caller-free hand-written DTO; narrow `OnboardingAnswerWriteGate` to name; remove only onboarding's `updateUserLanguage`; retain acquisition recorder and generic Settings/Chat language APIs.

**Retained behavior:** name prefill/async arrival, Back revisions, owner isolation, local acquisition, PostHog, local voice language, S-08 auth/session semantics.

**Expected files:** `SBOnboardingModel.swift`, `OnboardingAnswerWriteGate.swift`, `AuthService.swift`, `APIClient+Settings.swift`, acquisition/name/write-gate tests, API decoding tests if DTO deletion makes them obsolete, and comments/docs.

**Focused proof:** `OnboardingAcquisitionSourceTests`, `OnboardingAnswerWriteGateTests`, new Firebase-name behavior tests, owner-authority tests, and retained transcription Settings tests.

**Deletion enabled:** onboarding backend profile request, cloud language queue/branch, unused DTO, and stale retry/error copy.

**Stop:** do not delete `/v1/users/language` while retained Settings/Chat callers exist; do not weaken auth owner fencing to make a test easy.

### Cycle 3 — remove the Firestore profile-name duplicate without absorbing S-08/S-23

**RED:** Through authenticated backend behavior, seed a Firestore profile containing `name` plus retained account metadata and assert GET `/v1/users/profile` returns retained metadata but no `name`; server export's interim profile fragment excludes `name`; backend name resolution uses Firebase display name and never reads Firestore; speaker-name enrichment receives the Firebase name. Keep GET/PATCH `/v1/users/onboarding` at 404. Add an OpenAPI contract expectation for the narrowed profile schema.

**Why RED:** `UserProfileResponse` declares and `extra='allow'` exposes `name`; `_get_firestore_user_name`, `populate_speaker_names`, and current export still read it.

**GREEN:** Remove the profile-name response field and explicitly filter the Firestore document at retained response/export boundaries; delete the Firestore fallback and use the existing Firebase `get_user_name` seam at retained enrichment callers. Keep other profile/account metadata and S-08's future export boundary. Regenerate the app-client snapshot and any generated non-Windows Swift output from source; never hand-edit generated files. Do not mutate live documents.

**Retained behavior:** Firebase Apple/Google names, account metadata GET, conversation speaker labelling, S-08 export handoff, negative onboarding routes.

**Expected files:** `backend/routers/users.py`, `backend/database/auth.py`, `backend/utils/conversations/render.py`, `backend/services/users/data_export.py`, their tests, `docs/api-reference/app-client-openapi.json`, and generated non-Windows Swift only if the generator changes it.

**Focused proof:** backend auth/profile/render/export tests, `testing/e2e/test_user_auth_profile.py`, route policy, OpenAPI export check, Swift generator check, and no-network OpenAPI bootstrap.

**Deletion enabled:** all repository readers/exposure of `users/{uid}.name`. Historical field/data deletion remains S-23/live-operation work.

**Stop:** if a retained backend consumer cannot move to Firebase or a released client is proven to require the field, stop for an explicit contract decision. Do not return `name: null` as a shell.

### Cycle 4 — make every retained permission truthful and consent-only

**RED:** Drive the production permission transition through injected native permission boundaries and assert each grant updates/checks/advances but records no transcription start, screen-monitor start, or capture-intent change. Assert the System Audio path requires a successful real-tap result; Screen Recording primes once and discards; polling is bounded/cancellable; a late grant cannot advance a departed step. Assert Accessibility copy names global PTT and precise Rewind/Focus, while the resolver prefers AX and falls back to CGWindow. Add labelled static absence tripwires for a live Automation/FDA stage or Apple Events entitlement/usage description.

**Why RED:** capture absence lacks one behavioral effect recorder, Accessibility copy says “click and type,” and orphan `openAutomationPreferences()` remains.

**GREEN:** Add the narrow permission-effect seam needed to observe existing production behavior, rewrite only the false Accessibility explanation/widget help, and delete the orphan Automation preference opener. Preserve native request/check/poll/prime implementations and generic Chat/realtime permission tools. Do not alter TCC grants or start capture in the permission callback.

**Retained behavior:** all four optional stages, Skip per stage, truthful precheck, bounded retry, real system tap, prime capture, shortcut/AX/CGWindow behavior.

**Expected files:** Second Brain model/steps/view, `AppState+Permissions.swift`, permission/back tests, `SpatialOverlayResolverTests`, `ScreenRecordingPermissionPolicyTests`, and narrowly related docs.

**Focused proof:** onboarding permission behavior tests, system-audio permission tests, screen-recording policy tests, spatial overlay tests, `OnboardingPermissionToolTests`, and test-quality checker.

**Deletion enabled:** Automation opener and current live false claims; unexplained FDA/Automation residue.

**Stop:** an apparent Automation/FDA match belongs to `DesktopAutomationBridge`, external-target denial policy, terminal diagnostics, or historical changelog. Classify and preserve it rather than deleting by noun.

### Cycle 5 — make the final listening choice explicit and restartable

**RED:** At the pure exit-plan seam, assert meeting-only persists `.onlyDuringMeetings`, enables transcription intent, starts one transcription session/meeting detector, and leaves mic/System Audio idle without an active call; continuous persists `.always`, enables intent, and captures immediately. Assert both choices are independent of Calendar and permission grants. Relaunch with persisted intent and assert the same mode restores through `PersistedCaptureLaunchPolicy`.

**Why RED:** the current model starts a session directly only for continuous and relies on registered defaults/Home side effects for meeting-only; UI still says “from my calendar.”

**GREEN:** Make `capture(selection)` pass the choice into the explicit outcome plan; set transcription intent and mode before starting the existing session owner for both modes; let `reconcileCapture()` enforce meeting gating; replace Calendar copy with call-detection truth. Do not add a second detector or capture coordinator.

**Retained behavior:** meeting-only primary button, continuous alternative, existing detector semantics, persisted restart, local capture owners.

**Expected files:** exit policy/effect implementation, model/view, `PersistedCaptureLaunchPolicyTests`, capture-selection/transcription tests, and copy flow.

**Focused proof:** `SBOnboardingCaptureSelectionTests`, new exit-plan tests, persisted capture tests, focused meeting-detector/reconcile tests, and offline restart harness.

**Deletion enabled:** implicit default-driven meeting setup and Calendar explanation.

**Stop:** if meeting-only cannot be armed without an external backend after S-16 refresh, stop and resolve the retained transient-listen boundary; never fake a started session.

### Cycle 6 — make global Skip a no-capture, no-opener exit

**RED:** From every retained step, drive visible `skip()` and assert one `Onboarding Skipped` event, no `Onboarding Completed`, no opener, neutral Home landing, completion flag only after journal finish, transcription/screen intents false, active services stopped, Launch at Login disabled, all step work cancelled, and no capture restoration on Home appear, settings sync, app activation, or relaunch. Seed registered-default and old migration-marker combinations so the test cannot pass vacuously.

**Why RED:** current Skip emits completed, sets completion landing, shows opener, leaves capture defaults/migrations able to start services, and does not disable login item.

**GREEN:** Route Skip through `.skipped`; explicitly write false intents and disable runtime/login owners; emit one bounded skipped event; finish the retained journal; set the completion flag; land normally without opener/just-completed marker. Delete or fence the old screen-auto-start migrations so they cannot overwrite an explicit skipped outcome. Do not change `--skip-onboarding`.

**Retained behavior:** global button position/availability, teardown, Home access, setup journal cleanup, completion UI gate.

**Expected files:** outcome policy/executor, model, `DesktopHomeView`, Analytics/PostHog, capture policy tests, new Skip behavior tests, and flow.

**Focused proof:** Skip outcome tests across stages, persisted capture tests, analytics shape test, onboarding journal tests, Home lifecycle tests, offline relaunch.

**Deletion enabled:** shared completed/opener path for Skip and legacy Home migration branches that violate the explicit choice.

**Stop:** if a retained Home migration is still required for this unreleased fork, require an explicit decision distinguishing its population from Skip; do not key a workaround off permission state.

### Cycle 7 — delete stale suggestion and Calendar inputs from the retained opener

**RED:** Seed every orphan suggestion default and compose/present a completion opener. Assert only `HomeSuggestionsStore` questions are used, no popup/banner notification appears, and no meeting/Calendar title can enter greeting, subline, or starters. Assert normal Home suggestions still de-duplicate/cap correctly.

**Why RED:** stale `PostOnboardingPromptSuggestions` values still flow into the opener/Dashboard/popup; the composer still accepts meetings.

**GREEN:** Remove `PostOnboardingPromptSuggestions`, `TryAskingPopupView`, `.showTryAskingPopup`, DesktopHome/Dashboard popup/banner/readers, and old defaults. Narrow `OnboardingOpenerComposer` to name + local listening mode + normal starter questions; remove `OnboardingMeetingBrief` and meeting branches/tests. Preserve ordinary Home suggestion composition and the visual opener component.

**Retained behavior:** local completion greeting, listening summary, starter chips, normal personalized questions, first-message dismissal.

**Expected files:** suggestion store/view, Dashboard/DesktopHome, ChatProvider opener, composer/view/tests, Home suggestion tests, defaults cleanup.

**Focused proof:** `OnboardingOpenerComposerTests`, `HomeSuggestionsStoreTests`, new stale-default behavior test, Dashboard/Home focused tests, test-quality checker.

**Deletion enabled:** complete orphan suggestion/popup family and latent Calendar enrichment.

**Stop:** if a refreshed writer exists, identify its reviewed owner. Do not silently retain an unreviewed onboarding recommendation product.

### Cycle 8 — make genuine completion own launch, monitoring, opener, and journal handoff

**RED:** Drive `.completed(.onlyDuringMeetings)` and `.completed(.continuous)` through an effect recorder. For both, assert completed analytics (never skipped), `setEnabled(true)` regardless of prior status, disclosed UI copy, screen intent true and monitoring start only through permission/paywall/key gates, listening behavior from Cycle 5, one simplified opener, no goal generation, ordered journal finish/main reload, completion landing marker, and completion flag last. Assert Settings can subsequently disable Launch at Login.

**Why RED:** current completion preserves a stale `launchAtLogin` snapshot, has no disclosure, can disable screen intent for lazy dev builds, calls `GoalGenerationService`, and shares opener/landing semantics with Skip.

**GREEN:** Route completion through the outcome executor, always request login-item enablement, add a concise factual disclosure on the final choice, explicitly enable screen intent for both modes and call the existing permission-gated monitor owner, remove goal generation, present the Cycle 7 opener once, finish journal, then publish completion/landing. Keep login failure honest; no fake enabled state.

**Retained behavior:** both audio modes, monitoring permission/paywall/key gates, Home opener, main-chat restoration, Settings off switch.

**Expected files:** outcome policy/executor, model/view, `LaunchAtLoginManager` only if a testable external seam is needed, completion/login tests, monitor policy tests, journal/opener tests, changelog fragment.

**Focused proof:** rewritten `SBOnboardingLaunchAtLoginCompletionTests` citing IR-145 as the external expected-value authority, outcome tests, capture/monitor tests, onboarding journal/continuity tests, and Settings toggle tests.

**Deletion enabled:** `launchAtLogin` snapshot field, preserve-selection implementation, goal-generation side effect, duplicate completion teardown.

**Stop:** actual registration failure in a named bundle is expected; do not weaken `AppBuild.isProductionBundle`. A production-family failure blocks G1/S-29 evidence, not repository GREEN.

### Cycle 9 — delete legacy login migration while fencing direct bypass and AppKit lifecycle

**RED:** Through small production decision seams, assert command-line arguments containing `--skip-onboarding` only set completion; visible Skip/completion effects are not called. Assert last-window close returns terminate only before completion. Assert AppKit relaunch-at-logout stays disabled during onboarding and enabled after completion for production bundles, while non-production remains suppressed. Assert completion/resume/journal disagreement emits bounded content-free fields with completion as winner. Add absence coverage for the migration call/function/key.

**Why RED:** the migration and `didMigrateLaunchAtLoginV1` still exist; current lifecycle coverage is fragmented and the direct flag reads global arguments.

**GREEN:** Delete `migrateLaunchAtLoginDefault`, its launch call, marker, logs, and obsolete tests. Extract only the minimal pure argument/termination decisions needed for behavioral tests while keeping actual AppDelegate behavior unchanged. Preserve `updateOnboardingLifecyclePolicy` and diagnostics.

**Retained behavior:** IR-733 direct bypass, IR-734 process quit, IR-147 relaunch, IR-735 authority diagnostics.

**Expected files:** `OmiApp.swift`, lifecycle/diagnostic tests, removed migration tests/docs.

**Focused proof:** direct-flag tests, last-window policy tests, `QuitAndReopenActionTests`, `RestartRelaunchCommandTests`, `DesktopDiagnosticsManagerTests`, and existing AppBuild identity tests.

**Deletion enabled:** entire legacy Omi login-item migration.

**Stop:** do not convert `--skip-onboarding` into a debug-only flag or route it through the visible Skip policy; the ledger explicitly protects its published behavior.

### Cycle 10 — delete the unreachable AI onboarding engine, not retained Chat/PTT

**RED:** At generated/runtime public seams, assert `set_user_preferences`, `ask_followup`, and `complete_onboarding` are absent from manifest, execution policy, fixture, generated dispatch, and ChatToolExecutor handling. Assert unknown deleted names are unhandled/fail closed. In the same cycle, prove `request_permission`, `check_permission_status`, normal Chat tools, realtime tools, local managed Pi bridge, `.onboarding()` local journal, and the real PTT demo remain functional.

**Why RED:** the generator explicitly injects three onboarding commands; `ChatToolExecutor`, policy, manifest, callbacks, persistence, fixture, and tests still support them.

**GREEN:** Remove the three tools from source manifest/generator special cases/policy, delete their executor cases/methods/callbacks and `OnboardingChatPersistence`, remove exclusive analytics/call-site formatting/tests, and regenerate `GeneratedToolCapabilities.swift`, `GeneratedRealtimeTools.swift`, `GeneratedToolExecutors.swift`, and tool fixture. Retain generic permission executors; rename onboarding-specific permission constants only if it improves their now-generic truth without changing behavior. Do not hand-edit generated files.

**Retained behavior:** normal Chat/PTT/realtime tools, owner authorization, current-turn permission consent, local journal isolation, live demo, main timeline continuity.

**Expected files:** `ChatToolExecutor.swift`, limited `ChatProvider.swift`, `AnalyticsManager.swift`, deleted persistence file, agent manifest/policy/generator/fixture/tests, generated Swift, tool/journal/continuity tests.

**Focused proof:** `scripts/test-tool-surfaces.sh`, `OnboardingPermissionToolTests`, `AuthorizedToolExecutionTests`, `OnboardingQuerySurfaceIsolationTests`, journal Node tests, `agent-logic-harness.sh`, and generated drift check.

**Deletion enabled:** the complete model-driven onboarding engine and its exclusive support surface.

**Stop:** a generic retained tool or `.onboarding()` journal match is not AI-engine residue. Stop if the refreshed live fixed flow actually calls one of the three tools; repair reachability ownership before deletion.

### Cycle 11 — narrow reset/sign-out persistence and automate the real two-exit flow

**RED:** With isolated defaults and a temporary owner journal, seed every retained and retired setup key. Drive shared cleanup, confirmed Settings reset, immediate menu reset, non-production automation reset, sign-out, and restart. Assert only retained setup state is cleared, both capture services/intents stop before replay, completion resets, setup journal clears locally with `deleteBackend=false`, normal main-chat/user data remains, and a second account sees no prior answer. Assert `reset_onboarding` is unavailable for production-family builds. Run the rewritten onboarding flow twice.

**Why RED:** the shared key list still includes old wizard/role/goal/trigger state; reset/sign-out still clear `OnboardingChatPersistence`; reset depends on view notification for transcription and does not own a complete no-monitor replay boundary; current E2E still expects Goal -> Tasks.

**GREEN:** Narrow `OnboardingFlow.persistedStateKeys`, remove AI clear calls, centralize the retained replay/sign-out preparation without broadening ordinary data deletion, explicitly stop transcription/monitoring and write safe intents, preserve local journal clearing, and update reset callers/tests. Rewrite `onboarding-flow.yaml` and `onboarding-smoke.yaml` to the actual stages, permission-no-start assertions, Back revision, visible Skip, both completion modes, relaunch, and no-role/no-connector/no-BYOK claims. Add a content-free bridge snapshot field only if existing state/log/defaults cannot automate a repeated assertion; cover it in the existing harness/CI lane.

**Retained behavior:** all three reset entrances, real same-bundle restart, sign-out ordering, account isolation, local journal, normal data, `--skip-onboarding` distinction.

**Expected files:** `OnboardingFlow.swift`, `DefaultsKey.swift`, `AuthService.swift`, `AppState+SystemActions.swift`, `DesktopHomeView.swift`, reset/persistence tests, two E2E flows, `CORE_E2E.md`/component docs if behavior/commands changed, and optional existing bridge snapshot/tests.

**Focused proof:** behavioral `OnboardingPersistenceClearingTests`, sign-out lifecycle tests, reset action tests, journal isolation tests, owner-switch tests, desktop-core self-check, and two consecutive named-bundle flow runs.

**Deletion enabled:** obsolete defaults/comments/static source inspections and stale Goal/Tasks onboarding coverage; final duplicate exit/cleanup code can now simplify.

**Stop:** never clear Firebase tokens, normal Chat, local conversations/memories/tasks/Rewind data, or system TCC grants as setup cleanup. Never expose reset automation in beta/stable.

## 12. Cross-slice ownership and handoffs

| Slice | Relationship to S-17 |
|---|---|
| S-06 | Hard predecessor. S-17 consumes one active conversational flow and deleted connector/FDA/Automation pages. It preserves managed Pi, explicit attachments, local journal, and `DesktopAutomationBridge`. |
| S-07 | Hard predecessor. S-17 keeps setup free of customer keys and does not change managed provider routing. |
| S-08 | Hard predecessor and later acceptance owner. S-17 consumes auth/session/sign-out and the deleted backend onboarding record. S-17 removes Firestore name authority/exposure; S-08's final server export must keep that exclusion while composing account metadata. |
| S-09 | Owns telemetry project/consent/provider policy. S-17 adds only the bounded outcome event and removes AI-tool events made exclusive by deletion. |
| S-10 through S-15 | Own local domain authorities and Rewind cloud-copy removal. S-17 does not migrate their data; it preserves setup inputs and local capture/journal seams. |
| S-16 | Owns the wider transient `/v4/listen` protocol and deletes `OnboardingHandler` under IR-395. S-17 leaves a pre-S-16 handler for that owner and never restores it after S-16, while preserving retained transient streaming. |
| S-21 | Consumes the narrowed flow/reset/settings result and later removes shell residue. S-17 changes only onboarding-owned rows/copy, not Settings/navigation architecture. |
| S-22 | Owns model/provider portfolio. S-17 deletes only unreachable onboarding-only tools and preserves normal managed model surfaces. |
| S-23 | Receives historical rejected Firestore profile/onboarding field cleanup after repository writers/readers are gone and live-data authorization exists. S-17 performs no production data deletion. |
| S-28 | Consumes the final retained onboarding defaults/login-item storage shape for clean product namespaces. S-17 does not perform global bundle/defaults/Keychain migration. |
| S-29 | Owns signed candidate identity. It supplies G1 proof that genuine completion registers the production-family login item without weakening named-bundle refusal. |
| S-30 | Owns final product identity, image, repository link, and broad privacy/cloud promise rewrite. S-17 removes known-false functional claims now but keeps replaceable neutral copy seams. |
| S-31 | Runs final end-to-end onboarding/login/reboot acceptance and consumes S-17 repository plus G1 evidence. |

Shared-file rule: `AuthService.swift`, `DesktopHomeView.swift`, `OmiApp.swift`, `ChatProvider.swift`, `ChatToolExecutor.swift`, backend user/profile surfaces, agent manifests, OpenAPI, and generated Swift are shared trunks. Refresh all callers after every predecessor integration and change only S-17-owned behavior. No temporary old/new adapter is authorized.

## 13. Repository residue-search strategy

Run before Cycle 1, after the owning GREEN, and at closure. Save the classified output in the PR evidence; absence tests supplement behavior but never replace it.

```bash
# Active/deleted flow state and false copy
rg -n 'onboardingRole|roleDraft|pickRole|onboardingGoalDraft|onboardingStep|onboardingFurthestStep|hasTriggered(Notification|ScreenRecording|Microphone|SystemAudio|Accessibility)|hasSeenRewindIntro' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests
rg -n 'from my calendar|click and type|click/type|Full Disk Access|Privacy_Automation|openAutomationPreferences|Automation permission' \
  desktop/macos --glob '!changelog/releases/**'

# Answer/backend authority
rg -n 'loadNameFromBackendIfNeeded|updateUserProfile|getUserProfile|_get_firestore_user_name|users.*/.*name|profile.*name' \
  desktop/macos/Desktop/Sources backend --glob '*.{swift,py}'
rg -n '/v1/users/onboarding|v1/users/onboarding' backend desktop/macos docs --glob '!**/windows/**'

# Exit/migration/orphan residue
rg -n 'didMigrateLaunchAtLoginV1|migrateLaunchAtLoginDefault|screenAnalysisAutoStartFixed_v[23]|GoalGenerationService.*generateNow|PostOnboardingPromptSuggestions|showTryAskingPopup|TryAskingPopupView|OnboardingMeetingBrief' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests desktop/macos/e2e

# AI-only engine/tool surface
rg -n 'OnboardingChatPersistence|set_user_preferences|ask_followup|complete_onboarding|onCompleteOnboarding|onQuickReplyOptions|onQuickReplyQuestion' \
  desktop/macos/Desktop/Sources desktop/macos/Desktop/Tests desktop/macos/agent

# Retained-neighbor fences; these should remain explained, not become empty
rg -n 'request_permission|check_permission_status|AgentSurfaceReference\.onboarding|beginOnboardingJournal|finishOnboardingJournal|DesktopAutomationBridge|OnboardingHandler|CGWindowList|AXUIElement' \
  desktop/macos backend --glob '*.{swift,ts,py}'

# Generated/contracts and Windows exclusion
rg -n 'set_user_preferences|ask_followup|complete_onboarding|UserProfileResponse|/v1/users/profile' \
  docs/api-reference/app-client-openapi.json desktop/macos/Desktop/Sources/Generated desktop/macos/agent/tests/fixtures
```

Expected explained survivors:

- `/v1/users/onboarding` appears in the negative 404 test and may appear in historical planning/docs; it must not be a registered route/client helper.
- `OnboardingHandler` under `/v4/listen` may survive only on a pre-S-16 execution head, where it is an explicit IR-395/S-16 handoff. After S-16 it must be absent, and S-17 must not restore it.
- `DesktopAutomationBridge` and the word “automation” in test tooling/external-target denial are retained.
- Full Disk Access in historical release notes and the terminal-host TCC inspection message remains historical/operator truth.
- `onboarding` remains a local journal surface and analytics/lifecycle concept.
- Windows matches are ignored completely.

Any other live match needs a caller, owner, and disposition. “Looks dead” is not closure evidence.

## 14. Focused and component-level verification commands

### Planning/entry checks

```bash
git merge-base --is-ancestor 0d9934c HEAD
python3 bootstrap-scaffold/validate-requirements-ledger.py
git status --short --branch
```

### Focused Swift loop

Use one filter per active tracer bullet; do not bulk-run future RED tests:

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift 'OnboardingFlowTests'
./scripts/dev-feedback.py --once swift 'OnboardingAnswerAuthorityTests'
./scripts/dev-feedback.py --once swift 'OnboardingPermissionBehaviorTests'
./scripts/dev-feedback.py --once swift 'OnboardingExitPolicyTests'
./scripts/dev-feedback.py --once swift 'OnboardingPersistenceClearingTests'
./scripts/dev-feedback.py --once swift 'OnboardingOpenerComposerTests'
./scripts/dev-feedback.py --once swift 'SBOnboardingLaunchAtLoginCompletionTests'
```

Also run the retained focused classes affected by the active cycle:

```bash
xcrun swift test -c debug --package-path Desktop --filter SBOnboardingBackNavigationTests
xcrun swift test -c debug --package-path Desktop --filter SBOnboardingCaptureSelectionTests
xcrun swift test -c debug --package-path Desktop --filter OnboardingAcquisitionSourceTests
xcrun swift test -c debug --package-path Desktop --filter OnboardingPermissionToolTests
xcrun swift test -c debug --package-path Desktop --filter PersistedCaptureLaunchPolicyTests
xcrun swift test -c debug --package-path Desktop --filter DesktopDiagnosticsManagerTests
xcrun swift test -c debug --package-path Desktop --filter QuitAndReopenActionTests
xcrun swift test -c debug --package-path Desktop --filter RestartRelaunchCommandTests
python3 scripts/check_desktop_test_quality.py
```

### Agent/tool generation and retained runtime

After editing source manifest/generator, regenerate from the compiled source and then run the authoritative check:

```bash
cd desktop/macos/agent
npm run build --silent
node --experimental-strip-types scripts/generate-tool-surfaces.mjs
cd ..
./scripts/test-tool-surfaces.sh
./scripts/agent-logic-harness.sh
```

If the shell's `node` is not Node 22.6+ with `--experimental-strip-types`, use the Node 22 binary selected by `scripts/test-tool-surfaces.sh`; do not alter generated files manually.

### Backend profile/OpenAPI loop

```bash
cd backend
.venv/bin/python -m pytest -q testing/e2e/test_user_auth_profile.py
.venv/bin/python -m pytest -q tests/unit/test_user_profile_people_response_models.py
.venv/bin/python -m pytest -q tests/unit/test_folder_name_enrichment.py
.venv/bin/python -m pytest -q tests/services/users/test_data_export.py
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --write
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
scripts/openapi_runner.sh scripts/export_openapi.py --surface app-client --check
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
scripts/openapi_runner.sh scripts/route_policy_inventory.py --manifest route_policy_manifest.yaml --check --report-only
```

Use `backend/test.sh` rather than putting a new test in an undiscovered location. The final backend component gate is:

```bash
cd backend
bash test-preflight.sh
bash test.sh
```

### Desktop and repository gates

```bash
cd desktop/macos
xcrun swift build -c debug --package-path Desktop
./scripts/swift-format-wrapper.sh lint -r $(./scripts/swift-format-wrapper.sh scope)
./scripts/swiftlint-wrapper.sh lint
./scripts/desktop-core-harness.sh --self-check
./test.sh

cd ../..
git diff --check
python3 bootstrap-scaffold/validate-requirements-ledger.py
make preflight
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
```

Before these checks, format touched Swift with `desktop/macos/scripts/swift-format-wrapper.sh format -i <files>` and touched Python with the repository Black command. Record exact commands, elapsed times, pass/fail counts, pre-existing failures, and the tested commit in the PR. A compile is not a user-path pass.

## 15. Real named-bundle/user-path acceptance

Use a unique named non-production bundle, the offline local harness, and a synthetic Firebase Auth emulator user. Because onboarding itself is under test, do **not** use `omi-auth-seed.sh`, clone `hasCompletedOnboarding`, or launch with `--skip-onboarding`.

```bash
# Repo root
PROVIDER_MODE=offline make dev-up
make seed-memory-scenario SCENARIO=happy_path
make desktop-run-local DESKTOP_APP_NAME=omi-s17-onboarding DESKTOP_USER=alice

# In another shell, use the worktree-specific port printed by run.sh
cd desktop/macos
OMI_AUTOMATION_PORT=<PORT> ./scripts/omi-ctl health
OMI_AUTOMATION_PORT=<PORT> ./scripts/omi-ctl action reset_onboarding
# Wait for the old listener PID to be replaced and reconnect with fresh omi-ctl calls.
python3 scripts/omi-harness run e2e/flows/onboarding-flow.yaml \
  --lane ui --port <PORT> --bundle-id com.omi.omi-s17-onboarding
```

The updated live flow must collect screenshots, AX snapshots, safe state/defaults, and the named bundle's exact log path. It exercises:

1. **Graph and revisions:** real sign-in -> trust -> name -> acquisition -> language -> mic, with no role/BYOK/connector/FDA/Automation screen; Back revises name/language; relaunch resumes the exact retained stage; Return and Back/Skip fallback work at 540 x 640.
2. **Permission no-start:** on a fresh named bundle, grant or detect each available permission, verify its truthful checkmark/advance, and prove transcription and monitoring remain inactive before final choice. Skip individual grants where macOS or hardware makes them unavailable and record that limitation; never test on production bundles.
3. **Visible global Skip:** reset, use the actual Skip button from an intermediate stage, assert neutral Home, one skipped event in local capture/log evidence, no opener, both persisted intents false, no active transcription/monitoring, no login-item registration attempt to true, and the same no-capture state after quit/reopen and app activation.
4. **Meeting-only completion:** reset and walk the whole real flow, including the actual shortcut and authenticated PTT demo. Choose meeting-only, assert completion opener and disclosure, transcription session awaiting a call with no mic/System Audio capture outside a call, monitoring only when Screen Recording plus other retained gates permit it, and mode/state restored after same-bundle quit/reopen.
5. **Continuous completion:** reset and walk again, choose continuous, assert immediate transcription plus the same completion-only opener/monitoring/login policy. Use a synthetic/no-sensitive audio path; do not assert exact model wording.
6. **Reset/sign-out/owner isolation:** exercise confirmed Settings reset, immediate status-menu reset, and `reset_onboarding`; verify new PID/same named bundle/real first step. Sign out Alice, sign in Bob through the emulator, and prove no Alice answer/setup journal or active capture survives.
7. **Lifecycle fences:** close the last window before completion and prove the named process exits; after completion close it and prove the menu-bar process remains. Separately invoke `quit_and_reopen` after completion and prove same bundle/owner/completion on the same bridge port.

Run `onboarding-flow.yaml` twice consecutively after Cycle 11 and retain both summaries. Run `onboarding-smoke.yaml` as the independent reset/restart check. Read the bundle log from `./scripts/omi-ctl log-path`, not `/private/tmp/omi.log`. Do not touch stable/beta processes or bundles.

Named-bundle acceptance proves real local behavior but cannot prove `SMAppService.mainApp.register()` succeeds because non-production is deliberately refused. Attach the G1 signed-candidate/login proof later rather than weakening that guard.

## 16. Repository closure versus live operational closure

### Repository closure owned by S-17

S-17 repository closure requires all eleven cycles green, all in-tree callers migrated/deleted, generated outputs fresh, unexplained residue absent, component/preflight gates green, the named user paths exercised, and docs/copy truthful at the S-17 boundary. The backend may retain other account metadata. The separately owned `/v4/listen` handler is allowed only as an explicit pre-S-16 handoff and must remain absent when S-16 is integrated. No repository reader/writer/response/export may treat Firestore `users.name` as authority.

This slice may delete code, tests, generated contracts, local defaults, and dead documentation in its implementation PR. It does not delete production records or infrastructure.

### Separately authorized live/operational closure

The following are not silently authorized by repository implementation:

- deleting historical `users/{uid}.name`, old onboarding maps, or other Firestore fields;
- changing production TCC grants, login items, apps, or user settings;
- deploying backend/desktop builds;
- changing Firebase/PostHog/Sentry projects, secrets, IAM, queues, or services;
- promoting a signed candidate or rebooting a release machine.

S-23 owns historical rejected-data cleanup after read-only inventory, retention review, authorization, mutation, and post-delete evidence. S-29/S-31 own G1 signed-candidate login-item/reboot proof. If no owned live population exists, record the read-only evidence; do not invent an Omi customer migration or access upstream Omi data.

Repository closure and live closure must be reported separately. A stale production record does not justify retaining a repository reader, and a green repository test does not claim live data/login-item cleanup.

## 17. Risks, ambiguities, and explicit stop points

| Risk/ambiguity | Planned control | Stop point |
|---|---|---|
| Skip looks harmless in `skip()` but Home defaults/migrations start capture | Outcome test seeds absent/true/default/migration combinations and proves launch/activation/settings-sync behavior. | Any Home path can override explicit skipped intent. |
| Removing role shifts raw resume indices | Explicit ordered navigation plus bounded local schema conversion; test every stage and old role marker. | A retained current local marker cannot be mapped without losing the reviewed resume contract. |
| Firestore `name` has backend consumers | Move retained consumers to Firebase and filter current profile/export; S-23 gets historical cleanup. | A retained caller requires Firestore name and cannot use Firebase under current decisions. |
| Rewriting a launch-at-login test reverses its old expectation | Cite IR-145 as the external product authority in the rewritten test/PR and test the real production seam through injected `setEnabled`. | No authoritative requirement supports the new expected value (currently resolved by IR-145). |
| Named bundles refuse login registration | Treat refusal as a safety invariant; hermetic policy proof now and signed candidate G1 later. | Never weaken the production-bundle guard to make named acceptance green. |
| AI-tool deletion accidentally removes generic permission tools or the journal | Same-cycle retained tool/journal/PTT fences plus generated manifest/harness tests. | Refreshed normal Chat/PTT caller depends on code labelled exclusive. |
| Broad Automation/FDA search deletes test tooling/history | Classify `DesktopAutomationBridge`, external-target denial, changelogs, and terminal diagnostics explicitly. | Ownership is uncertain after caller search. |
| S-30 copy boundary | S-17 fixes only known functional lies and leaves replaceable product wording/artwork. | A change requires selecting final name/legal/privacy architecture. |
| S-08 final export is not closed | Filter name from the current export only; do not implement the final local/server export composition. | S-17 would need to migrate product-content authorities. |
| Reset/sign-out cleanup erases product data or TCC | Isolated defaults/temp journal tests; exact allowlist; no system permission reset. | Any implementation reaches normal owner data, Keychain tokens beyond existing sign-out, or system TCC. |
| Tests regress into source scraping | Production actions/policies are behavioral; static checks are labelled forbidden-pattern/generated/contract tripwires and carry repository-required reasons. | A claimed behavioral guard only reads source text. |
| Current target branch changes during implementation | Rebase/integrate, repeat caller/residue inventory, rerun overlapping suites. | `0d9934c` no longer ancestor or predecessor shape changed incompatibly. |

There is no unresolved provider, credential, customer ID, project ID, or commercial input for repository Cycles 1-11. G1 is an evidence/operational gate, not permission to guess a release identity.

## 18. Final completion checklist

- [ ] `0d9934c` remains an ancestor of the implementation head; current target-branch work and all relevant predecessor changes are integrated.
- [ ] The live requirements ledger validates and every IR-050-052, IR-124-169, and IR-733-735 outcome above is still authoritative.
- [ ] Exactly one active conversational graph remains, with no role/connector/BYOK/FDA/Automation stage and no old paged renderer/state.
- [ ] Retained trust, answer, permission, shortcut, demo, listening, resume, Back, typing, transcript, Return, layout, backdrop/fallback, cleanup, and diagnostic behaviors have behavioral coverage.
- [ ] Name is local + Firebase only; acquisition is local + bounded PostHog; onboarding language is local only; Back revisions and owner switches cannot reorder name writes.
- [ ] Profile GET/interim export/backend name resolution no longer expose/read Firestore `users.name`; S-08/S-23 handoffs are recorded; no live data was mutated.
- [ ] GET/PATCH `/v1/users/onboarding` still fail 404; a pre-S-16 `/v4/listen` `OnboardingHandler` is left for IR-395/S-16, while an integrated S-16 deletion remains absent and is never restored.
- [ ] Every permission grant is proven consent-only; System Audio uses a real tap; Screen Recording primes/discards; Accessibility copy and AX->CGWindow ownership are truthful.
- [ ] Meeting-only arms the retained session and waits for a call; continuous starts immediately; both restore their local mode after restart.
- [ ] Visible Skip emits skipped only, shows no opener, disables both capture intents/services and Launch at Login, and stays quiet across Home/activation/sync/relaunch.
- [ ] Genuine completion emits completed only, enables/discloses Launch at Login, enables permission-gated monitoring for both listening modes, shows one local opener, clears the setup journal, and performs no goal generation.
- [ ] `--skip-onboarding`, pre-completion quit, AppKit relaunch policy, Settings off switch, completion-flag winner, and content-free disagreement diagnostics remain exact.
- [ ] Legacy login and screen-auto-start migrations that violate the reviewed boundary are gone.
- [ ] Orphan suggestions/Calendar inputs and the unreachable AI onboarding tool/persistence family are gone; generated outputs are fresh.
- [ ] Generic permission tools, normal Chat/PTT/realtime, managed Pi/private bridge, local onboarding journal, explicit attachments, Rewind/Focus, `DesktopAutomationBridge`, and historical/operator records remain green.
- [ ] Shared reset/sign-out cleanup contains only retained setup keys, stops capture before replay, isolates owners, and never deletes normal data or TCC grants.
- [ ] Updated onboarding flows pass twice on `omi-s17-onboarding` without seeded completion or `--skip-onboarding`; evidence covers both exits, both listening modes, reset, sign-out, owner switch, relaunch, and last-window behavior.
- [ ] Focused Swift/backend/tool tests, generated checks, desktop/backend component suites, residue searches, formatter/lint, `make preflight`, PR preflight, and ledger validator pass at the final commit with commands/results recorded.
- [ ] User-visible behavior has one changelog fragment; component/product docs describe the narrowed boundary without making S-30's final brand/privacy decisions.
- [ ] Repository closure and G1/S-23 live operational handoffs are reported separately; no deploy, production app automation, data deletion, or infrastructure mutation is implied.
- [ ] Independent review checks the final diff against this plan, the assigned detailed IRs, root/backend/desktop guides, and the deletion map's shared closure contract; every accepted finding is resolved and affected evidence rerun.

S-17 is not closed by removing visible pages, compiling, changing Skip copy, setting booleans in one call site, leaving dead generated tools, or replacing any deleted behavior with a no-op. It closes only when the narrowed retained path is authoritative end to end and the real named-bundle behaviors above are proven.
