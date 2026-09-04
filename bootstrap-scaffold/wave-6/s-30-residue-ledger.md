LIFECYCLE: permanent

# S-30 Intentive identity, truth, and residue ledger

This is the execution ledger for [`s-30 tdd.md`](s-30%20tdd.md). It records the
repository state implemented from the approved identity and provider decisions,
the intentionally retained exceptions, and the owner inputs that are still
required. It does not represent publication, production deployment, legal
approval, or ownership of a live external destination.

## Authorities and execution boundary

| Authority | Use in S-30 |
|---|---|
| [`OWNER-PROVIDER-DECISIONS.md`](../../OWNER-PROVIDER-DECISIONS.md) | Product `Intentive`; `heyintentive`; `heyintentive.com`; bundle family; repository; existing provider and infrastructure ownership; explicit external blockers. |
| [`requirements-challenge.md`](../requirements-challenge.md) | Retained behavior, exact strings, provider deletion decisions, and non-Windows scope. |
| [`deletion-map.md`](../deletion-map.md) | Predecessor slice ownership and retained internal compatibility boundaries. |
| [`s-30 tdd.md`](s-30%20tdd.md) | Cycle ordering, search matrix, real-app acceptance, and closure rules. |
| User direction, 2026-09-02 | Finish the code cycles with visual placeholders, do not alter inherited Omi assets, then request one consolidated Intentive asset pack. |
| User asset handoff, 2026-09-03 | Canonical Intentive icon, moss-garden source, experimental grass-material Dock reference, and Claude-style DMG reference approved; generate clean slideshow frames, preserve the complete moss source, evaluate the Dock treatment at native size, and delete caller-free inherited assets. Native-size review rejected the grass treatment because it read as flat green; the Dock returned to canonical black-and-white. |

The repository has no released Intentive client population. Current in-tree
producers and consumers therefore move atomically to the owned external values;
no dual-name compatibility aliases are introduced. Production Omi applications,
live provider configuration, DNS, email, signing, publication, and customer data
are outside this execution boundary.

## External identity migration map

Rows may cover a path group when every match has the same authority and
disposition. Symbols identify the reviewable seam more reliably than mutable
line numbers.

| Path / symbol | Audience and reachability | Previous value | Current value | Authority | Disposition / cycle | Evidence |
|---|---|---|---|---|---|---|
| `DesktopProductIdentity`, `Info.plist`, `AppBuild` | Finder, bundle routing, OAuth, updater | Omi bundle/display family | `Intentive`; `com.heyintentive.intentive{,.beta,.dev}`; owned named/preview prefixes | Owner decisions; S-28/S-29 | Migrated, C1 | `AppBuildIdentityTests`, `AppBuildBetaIdentityTests`, named-bundle health/state |
| `Info.plist` permission descriptions | macOS system prompts | Omi | Intentive | Owner decisions | Migrated, C1 | `AppBuildIdentityTests`; compiled named bundle |
| `AuthOwnerTransition`, `AuthStorageCanary`, OAuth callback surfaces | Keychain/defaults/callback | Omi user-visible identity and old callback scheme | Intentive copy and `heyintentive://auth/callback` family | S-08/S-28 | Migrated, C2 | `SignInIdentityPresentationTests`, `OAuthLoopbackCallbackServerTests`, backend redirect tests |
| `AuthLogPrivacy`, `AuthService` diagnostics | Local logs and submitted redacted diagnostics | OAuth callback URLs and raw Firebase response bodies could expose credentials/PII | Event, operation, and HTTP status only; response bytes are deliberately ignored | Logging security rule; S-09 | Sanitized, C2/C10 | `AuthTokenDecodingTests` privacy cases |
| Firebase desktop configuration, SwiftPM resources, and bundlers | App authentication and packaged bytes | inherited `based-hardware` configuration could be embedded as a nested dead resource, including from an incremental SwiftPM cache | committed resources contain only owned development and emulator configurations; local and release bundlers remove nested plists; releases inject an owned protected plist and fail closed without it | S-08; S-28; owner decisions | Inherited fallback deleted, C10 | focused package build; named-bundle resource inspection; app-config tests |
| `SignInView`, `OAuthLoopbackCallbackServer` | Sign-in screen and browser return HTML | Omi | Intentive | Owner decisions | Migrated, C2 | rendered named-bundle onboarding; callback tests |
| `SBOnboarding*`, opener and permission guidance | Onboarding UI | Omi identity/repository text | Intentive and `sruj75/knowledge-athlete` | S-17; owner decisions | Migrated without state-machine change, C3 | onboarding copy/repository/flow tests |
| `DesktopShellIdentityCopy` and current shell call sites | Home, Chat, floating bar, menu, accessibility | Omi user-visible nouns | Intentive | Owner decisions | Migrated, C4 | shell identity and affected view-model tests; named-bundle flows |
| Memory empty/location strings | Memory UI | Retained exact product contract | Exact IR-269 and IR-287 strings unchanged | Requirements ledger | Protected fence, C4 | exact-string tests and final fixed-string searches |
| `PrivacyTruthPresentation` | Privacy & Data UI | False local/security absolutes and generic provider claims | Local-store boundary plus explicit managed processing, provider roles, and disabled billing | S-09/S-21/S-22/S-26; owner decisions | Replaced, C5 | `PrivacyTruthPresentationTests`; named-bundle privacy snapshot |
| `ProductAnalyticsConsentController`, `PostHogManager` | Product analytics preference/runtime | Inherited token and ambiguous control | Owned-config-only startup; saved opt-out; identity reset; fail closed without config | S-09; owner decisions | Migrated, C5 | analytics configuration and consent tests |
| Sentry and Enhanced Diagnostics settings | Crash/report diagnostics | Conflated privacy wording | Independent from PostHog preference | S-09 | Clarified, C5 | privacy/settings behavioral tests |
| `AppBuild.settingsExternalDestinations`, About UI | Settings/About navigation | Inherited web/help destinations | Local Privacy & Data; only owned configured Website/Terms URLs; no Help Center | S-29; owner decisions | Fail closed, C6 | `SettingsDestinationContractTests`, `AboutUserCardTests`, named-bundle About snapshot |
| lifecycle/error/update/fair-use sources | Notifications, errors, What's New, recovery | Omi visible identity | Intentive/neutral copy, behavior unchanged | S-20/S-29 | Migrated, C7 | lifecycle, notification, update, fair-use focused tests |
| local export and diagnostic archives | Finder/attachments | `omi-*` filenames | `intentive-*` filenames | S-30 external identity | Migrated, C7/C8 | export and diagnostics tests; export E2E contract |
| `AnalyticsManager`, feature emitters | PostHog event stream | Brand-bearing Omi events | Intentive event names; payload meaning retained | S-09 | Atomic producer/test migration, C8 | `TelemetryIdentityContractTests`; opt-out recorder tests |
| `DesktopAutomationSnapshot`, action/surface names | Local automation protocol | `ask_omi`, `open_ask_omi`, `omi:default` | `ask_intentive`, `open_ask_intentive`, `intentive:default` | S-28/S-30 | Atomic producer/consumer/flow migration, C8 | bridge tests, renamed E2E flows, strict flow coverage |
| bundled agent/Pi extension manifests and relay | Local agent protocol and logs | provider/client/tool labels `omi` | `intentive` / `intentive-control-tools` / `intentive-tools` | S-22/S-28 | Atomic migration, C8 | agent and extension tests; generated-manifest checks |
| `metrics.py`, Firestore/translation metrics, `record_fallback` | Prometheus/log operators | `omi_*`, `omi_fallback_event` | `intentive_*`, `intentive_fallback_event` | S-27/S-30 | Atomic emitter/runbook/test migration, C8 | metrics and fallback observability tests |
| `/v1/health` service payload and release probes | Desktop/release operators | `omi-backend` | internal/runtime label `backend`; Cloud Run resource remains `knowledge-athlete-dev` | Owner decision 2026-08-29 | Migrated without live rename, C8 | desktop core and candidate/release doctor tests |
| release schemas, receipts, workflows, planner | Release operators and immutable evidence | Omi repositories/checks/receipt identity | `sruj75/knowledge-athlete`, Intentive checks, `intentive-desktop-pre-tag-readiness-v1` | S-29; owner decisions | Migrated, C8/C9 | release script/schema/guard tests |
| backend synthetic probes and temporary fixtures | Operators and logs | Omi suite/file prefixes | Intentive suite/file prefixes | S-27/S-30 | Migrated, C8 | Firebase, transcription, product-capability tests |
| account export and usage default | Download/API payload | Omi filename/account placeholder | `intentive-account-metadata.json`, `intentive` | S-08/S-30 | Migrated, C8 | account deletion, user usage, migration tests |
| backend metrics/runbooks/docs and root product docs | Current operator/contributor guidance | inherited topology and identity prose | one owned `us-west1` development backend; exact retained provider roles; billing disabled | S-27; owner decisions | Reconciled, C9 | runtime/deploy tests, doc review, residue classification |
| `.envrc.example` | Local backend operators | Omi environment-stage heading and retired `based-hardware-dev` project | Intentive stages and owned `knowledge-athlete` development project | S-27; owner decisions | Migrated, C10 | source inspection |
| Dodo `BillingConfig` | API/UI billing behavior | inherited API fallback | disabled means no provider/base URL/calls; enabled mode requires explicit base URL | Post-Wave-6 gate | Fail closed, C5/C9 | billing-mode and config tests |
| Modulate reproduction script | Developer-only diagnostic | inherited `omi-pr-assets` download | caller supplies an approved local fixture | Owner asset/provenance rule | Inherited network asset deleted, C10 | script/README inspection |
| `utils/retrieval/tools/omi_tools.py` | No reachable runtime caller | obsolete Omi product-info helper | deleted with package export and orphaned unit test | IR-897; caller proof | Deleted, C10 | repository caller search |
| task source storage, display, Chat SQL/schema, and analytics | Current local database, task UI, Gemini context, and analytics | caller-free `transcription:omi` value/label/icon and incomplete origin instruction | one-time migration rewrites the stored value to neutral `task`; defensive projections remain; model schema enumerates every current writer plus the migrated value | S-30 current rendered/model identity | Removed/neutralized, C10 | migration-backed `execute_sql`, task metadata, and Chat discoverability tests |
| `backend/.github/workflows/{push_replicate,google-cloudrun-docker}.yml` | Inert nested workflow controls | absent Replicate VAD tree and inherited Cloud Run service | deleted | IR-897 | Deleted, C10 | source/caller search |
| onboarding Figma sync install/run/uninstall scripts | Local LaunchAgent and external Figma mutation | broken source path plus inherited, unapproved Figma destination | deleted; no external sync occurs until an owned destination is supplied | Owner asset gate; S-30 no-live-mutation rule | Fail closed, C10 | source/caller search |

## Data-flow truth matrix

| Owner / store or provider | Data and purpose currently represented in code | Control / retention boundary | Repository status and evidence |
|---|---|---|---|
| macOS local databases and files | transcripts, memories, tasks, insights, focus history, Rewind, chat/agent journals | owner-scoped local storage; export and deletion are separate concrete paths | Disclosed as local data, without claiming all processing is local; privacy/export tests |
| Firebase Auth / minimal account data | authentication and minimal account identity/metadata | protected backend routes; account export/deletion paths | Retained and named in Privacy; auth/account tests |
| Firestore / Redis / Cloud Tasks / GCS | backend persistence, coordination, deletion tasks, and update/preview artifacts at their owning routes | owned development identities/manifests; no live mutation in S-30 | Current operator docs and manifest tests; not presented as local-only |
| Google Gemini | normal managed AI, embeddings, and realtime voice | selected input may leave the Mac for processing | Sole managed text/realtime disclosure; provider contract tests |
| Modulate | live and overflow transcription | selected audio is managed provider input; transient listen segments stay non-product data | Privacy disclosure and listen/transcription contract tests |
| OpenAI | `gpt-4o-mini-tts` text-to-speech only | no text inference, embeddings, or realtime role | Narrow role disclosed and guarded by current provider configuration |
| Langfuse | model traces and prompt management | existing owned Intentive project/config owner; no raw secret in source | Named in Privacy/operator docs; config/runtime tests |
| PostHog | bounded product events, state/count/classification, signed-in identity fields, some app/record identifiers | user preference defaults on; stops sharing and resets identity when off; no inherited token fallback | Exact category/boundary copy plus no-config and consent tests |
| Sentry | crashes, errors, and submitted report diagnostics | separate from PostHog preference | Explicit separate disclosure and scrub/release tests |
| Enhanced Diagnostics | user-controlled diagnostic detail | separate from PostHog and Sentry crash collection | Explicit separate settings copy and tests |
| Dodo Payments | no current runtime purpose because billing is disabled | `BILLING_MODE=disabled` supplies no provider/base URL and makes no checkout/portal call | Exact disabled statement and billing tests |
| Deleted providers | Anthropic, Artificial Analysis, Vertex AI, OpenAI text/embeddings/realtime | no fallback/compatibility role | Retired by S-22/S-26 decisions; current provider searches/tests |

No affirmative retention duration, encryption, sale/sharing, regional privacy,
company, or legal compliance promise is added where the repository and owner
packet do not prove it.

## Classified retained matches

| Path / symbol group | Audience / reachability | Classification | Authority and protected reason | Action / evidence |
|---|---|---|---|---|
| `FORK.md`, `LICENSE*` | Provenance readers | Historical/legal | Accurate upstream origin must remain | Retain; the historical table is baseline-only and current ownership stays in separately labelled sections |
| `desktop/macos/CHANGELOG.json`, `.github/failure-classes/**`, upstream issue links | Historical release/incident evidence | Historical | Rewriting prior facts would corrupt evidence | Retain; excluded/protected search lane |
| `desktop/windows/**` and Windows-only update/workflow branches | Windows product | Deferred product boundary | S-30 is macOS/non-Windows only | Retain untouched; explicit Windows exclusion |
| Swift module/type names including `OmiApp`, `OmiSupport`, `OmiMarkdown`, `OmiFont` | Compiler-only identifiers | Internal | No renderer/payload/bundle/service/log/analytics effect after caller review | Retain; behavioral tests and final caller searches cover reachable surfaces |
| Swift package/executable/resource bundle names needed by the current build | Build tooling | Internal | Renaming has no external S-30 benefit and creates broad dependency churn | Retain; debug build and package tests |
| `OMI_*` environment variables and `omi-ctl` / `omi-harness` / `omi-*` developer scripts | Existing private development interfaces | Internal/operator compatibility | Explicitly retained by predecessor contracts; not customer-visible product identity | Retain; current docs explain their purpose |
| local Memory database filename `omi.db` | Existing local persistence | Protected storage identity | Renaming/importing risks old-state takeover or loss; S-30 must not redesign storage | Retain; PRODUCT local-authority fence |
| old bundle/URL/service values inside rejection, migration, foreign-app, and safety tests | Test-only | Explicit old-value rejection/migration | Needed to prove inherited identity is rejected and no state is imported | Retain; tests assert the negative boundary |
| `omi-wave6-s30` | Test bundle display slug | Assignment exception | Exact temporary name required by S-30; resolved bundle ID is `com.heyintentive.intentive.dev.omi-wave6-s30` | Retain for acceptance evidence only |
| `/tmp/omi-*` qualification/runtime paths and POSIX/container user `omi` | Machine-local internals | Internal | No user-visible, protocol, service, metric, log, or external ownership meaning | Retain after caller/context review |
| generated Windows/absent-web `OmiApi` tooling | Excluded generator output | Deferred/missing product | Its consumers are excluded Windows or absent upstream surfaces | Retain; do not regenerate nonexistent clients |
| inherited hosts in routing/release guard deny-lists | Safety policy | Explicit rejection | The old value must remain recognizable so the build/deploy fails closed | Retain; guard tests assert rejection |

## Visual and media asset completion ledger

The owner asset gate closed on 2026-09-03. Product-brand derivatives and their
source hashes are recorded in `desktop/macos/ASSET-PROVENANCE.md`. Third-party
provider logos are outside the product-brand replacement and remain subject to
their own provider trademark terms.

| Current file(s) | Runtime state | Completed disposition |
|---|---|---|
| `desktop/macos/intentive_icon.icns`, `Desktop/Sources/Resources/intentive_app_icon.png` | Finder, bundle, Dock, and runtime app identity | Exact owner-supplied black-and-white icon uniformly inset on the 1024 px canvas to match the standard Notes/Freeform/Discord Dock boundary; its original internal mark already matches the stronger Chrome/ChatGPT visual weight; `CFBundleIconFile` and every bundler now use `IntentiveIcon` |
| `intentive_mark.png`, `intentive_menu_bar_icon.png` | Sign-in, Home, What's New, About, onboarding/Rewind/Second Brain, menu bar, and idle notch | Exact canonical mark geometry is reused; AppKit renders the menu asset as a 21 × 21 template image with an Intentive accessibility label |
| `intentive_signin_backdrop.png` | Sign-in and onboarding backdrop | 4096 × 2304 side extension retains the complete source square, centered and uncropped; generated pixels fill only the left/right gap |
| `intentive_permission_01_privacy.png` through `intentive_permission_04_return.png` | Active permission tutorial | Four clean 4:3 frames replace the inherited recording and loop as a timed SwiftUI slideshow with hover pause and Reduce Motion handling; corrected frames preserve the full canonical mark |
| `intentive_microphone_settings.png` | Active microphone guidance | Intentive replacement preserves the system-settings guidance semantics |
| `docs/oauth-callback-success-preview.png` | Documentation preview | Updated to the exact Intentive return identity |
| `dmg-assets/background.png`, `background@2x.png` | Mounted installer background | Approved warm Claude-style composition; Finder supplies the live app and Applications icons so no duplicate bitmap icons are baked into the background |
| Inherited Omi icon/GIF/logo/tray/onboarding/demo/folder and unused DMG-option assets | No retained caller | Deleted after owner approval and caller/provenance review; git history remains the recovery record |
| `backend/scripts/stt/modulate_repro/test_audio.wav` | Required local fixture is absent | Still needs an owned/licensed 38 s mono PCM16 16 kHz fixture, or explicit retirement of the repro; this is not a product-brand asset |

## Owner and operational rows

The S-30 execution originally recorded PostHog ownership and the next full
development deployment as open inputs. The dated reconciliation below preserves
that historical fact while separating it from current status.

### Currently open

| Missing input / resource | Current safe repository behavior | Closure owner |
|---|---|---|
| Owned Figma file/page destination for any future onboarding sync | Destination-mutating local LaunchAgent scripts are absent. A manual GitHub workflow can still export and publish the repository onboarding bundle, including Figma's capture helper, but it does not select or mutate an external design file. | Product/design owner |
| Published `heyintentive.com` product/download/preview/Terms/Privacy/support destinations | Website/Terms entries are absent unless an owned HTTPS URL is injected; Privacy & Data remains local; Help Center is absent | Product/legal/release owner |
| Approved support/privacy contacts | No guessed `support@heyintentive.com` or `privacy@heyintentive.com` ships | Product/legal owner |
| Approved Terms/Privacy text and legal operator name | No invented company or affirmative legal promise ships | Legal/product owner |
| Production Cloud Run and public release endpoints | Production remains unconfigured/fail closed; development resource names remain accurate | Infrastructure/release owner with fresh authorization |
| Complete Codemagic Apple signing/notarization/preview secrets and trusted runner | Repository dry-run fixtures only; no signing/publication/promotion performed | Release owner with fresh authorization |

### Resolved after the historical S-30 execution — 2026-09-04

| Former missing input / resource | Verified current status | Remaining boundary |
|---|---|---|
| Owned PostHog project ID/token | Owned `Intentive Desktop` project ID `397035` exists at `https://us.i.posthog.com`; its project token is stored outside Git in the Codemagic shared signing group and ignored local environment, and an ingestion probe was accepted and observed. | Final-SHA repository integration and telemetry qualification remain separate; no token value belongs in this ledger. |
| Next full development deploy with prepared Gemini/OpenAI/Modulate/Langfuse bindings | `knowledge-athlete-dev-0ea29f5-33868830964-1` serves 100% of development traffic from exact source SHA `0ea29f5c30cdf93ae3a76ac70f21d7a8bb148977`; the prepared Gemini v2, OpenAI TTS v1, Modulate v1, and Langfuse v1 bindings are present and their development checks passed. | S-31/BL-001 still requires its one-final-SHA physical/provider continuity evidence; this does not authorize production or publication. |

## Verification evidence

| Surface | Evidence |
|---|---|
| Named bundle | `/Applications/omi-wave6-s30.app`; bundle `com.heyintentive.intentive.dev.omi-wave6-s30`; automation port `47945`; production Omi apps were not touched. |
| Required bridge flows | `.harness/runs/20260902-201046-navigation`, `20260902-201047-home-stage`, `20260902-201049-privacy-settings`, `20260902-201049-about-settings`: all passed. |
| Tier 2 | `.harness/desktop-core/20260902T144126Z-t2`: 30/32 plus spatial overlay passed; the two chat reply checks failed because the offline local agent token is intentionally invalid, not because of S-30 identity behavior. |
| Manual render | Initial identity pass: `/tmp/s30-onboarding.png`, `/tmp/s30-privacy.png`, `/tmp/s30-about.png`. Final asset pass: `/tmp/s30-assets-signin-clean.png`, `/tmp/s30-assets-exports/09-permissions.png`, `/tmp/s30-dmg-window.png`. `/tmp/s30-black-dock-final.png` verifies the final canonical black-and-white Dock icon: standard tile boundary, strong internal mark, and parity with Chrome, ChatGPT, Notes, Freeform, and Discord. Menu-bar/notch marks remain monochrome. |
| Desktop tests | Final focused identity/truth suite: 43 passed; strict changed-source flow coverage passes 135/135. The component runner's launcher, packaging, release, E2E, and embedded-backend stages pass. Its isolated Swift lane reports 393/402 suites green; nine inherited suites fail in unchanged boundaries: seven abort when the XCTest host reaches the fail-closed production URL rule, and `RewindRetentionCleanupTests` / `RewindStorageVideoFrameExtractionTests` retain stale pre-S-28 storage expectations. The failed test files and routing/storage owners have no S-30 diff. |
| Backend tests | S-30 identity/provider/release groups are recorded with the final command results; the full runner's unrelated stale Redis/Firestore/CPU-threshold failures remain assigned to their owning future deletion work. |
| Agent runtime | build and focused runtime/manifests/context tests pass; Pi extension 11/11 passes. The agent-logic harness reaches its unchanged Swift lane and then hits the same inherited XCTest-host production-URL abort; both routing owners are byte-identical to `origin/main`. |
| Requirements validator | The S-30 implementation does not alter the requirements packet; currently reopened Gemini rows are recorded as upstream ledger state rather than rewritten by this slice. |
| Asset integrity | Focused final suite passes 25/25. `BrandAssetContractTests` verifies required packaged PNGs, renderer dimensions, the standard Dock tile/internal-mark bounds, the four-frame loop, and absence of retired inherited identity resources; the Retina DMG background contract passes; `ASSET-PROVENANCE.md` records canonical source hashes and transformations. |

Final commit, post-commit preflight, review findings, and exact asset hashes are
recorded in the local commit/hand-off evidence rather than predicting a SHA in
this ledger.
