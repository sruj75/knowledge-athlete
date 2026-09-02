# Fork provenance & rebrand checklist

## Provenance

Snapshot (no history) of a subset of [BasedHardware/omi](https://github.com/BasedHardware/omi).

| | |
|---|---|
| Source commit | `99e0e60be67a4f727ddfab4858184d75da2494a5` |
| Source tag | `v0.12.147+12147-macos` |
| Snapshot date | 2026-07-30 |
| Upstream license | MIT |

This fork has not shipped an application build or public API contract and has
no existing product users. The upstream tag records code provenance only; it
does not create a released-client compatibility population for this product.

Upstream paths were preserved verbatim, so a future `git diff` against upstream at
this SHA is meaningful and cherry-picking upstream commits still applies cleanly.

## What was included

| Path | Why |
|---|---|
| `desktop/macos/` | Native Swift 6 / SwiftUI app + bundled Node agent runtime |
| `desktop/windows/` | Electron + React + TS app (also builds mac/linux targets) |
| `backend/` | FastAPI + Firestore/Redis + direct managed providers, deployed through canonical Cloud Run workflows |
| `scripts/` | `dev-instance.sh` (sourced by `desktop/macos/run.sh`) and `dev-harness/` (local emulator stack) |
| `.github/` | CI + the desktop release chain |
| `config/`, `contract_tests/` | Build-contract JSON and backend parity fixtures |
| Root `Makefile`, `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `package.json` | Load-bearing: the harness hard-fails without the firebase trio; the Makefile is the only entry point to `dev-harness` |

## What was excluded

`app/` (Flutter mobile), `web/`, `omi/` (firmware/hardware), `omiGlass/`, `plugins/`,
`sdks/`, `mcp/`, `docs/`, and root `Package.swift` (the iOS SDK).

Roughly 1.24 GB upstream to ~129 MB here.

Repository controls are narrowed to retained backend and desktop sources.
Absent-product workflows, manifest entries, and local routing branches are not
kept as dormant restoration scaffolding.

## Running it

```bash
make dev-up          # Firebase Auth + Firestore emulators + local Redis
make dev-desktop     # the above, then launch the macOS app against it
```

The emulators replace Google, not the managed providers. For a hermetic local stack,
run `PROVIDER_MODE=offline make dev-up` without provider credentials. Real mode
uses Gemini for model compute, Modulate for speech-to-text, OpenAI for TTS only,
and Langfuse for tracing/prompt management. Their credentials belong in
`backend/.env.local-dev`; `make dev-init` creates that untracked file.

`desktop/macos/run.sh --yolo` skips the local backend and targets the owned
`knowledge-athlete-dev` Cloud Run URL recorded in `OWNER-PROVIDER-DECISIONS.md`. Cloud Run
admits internet traffic so native clients can reach FastAPI; protected routes still require
the owned Firebase user's bearer token. The local emulator path remains the hermetic default.

Prerequisites: Xcode + an Apple signing identity, `brew install webp`, Node 22.x
(`>=22.19 <23`), pnpm, Python 3.11 + `uv`, JDK 21+ (the Firebase emulators need it),
ffmpeg, opus.

## Rebrand checklist — before shipping your own build

The historical inventory later in this file records Omi identity that was baked into
the source. The build could succeed without changing those values, which is exactly
why each current successor or protected exception needs explicit ownership.

### Owner-approved successor identity

The MVP stays in the existing `knowledge-athlete` repository. It does not require a
new GitHub organization or a new Google Cloud project. Provider login email addresses
and the current external-resource handoff are recorded in
[`OWNER-PROVIDER-DECISIONS.md`](OWNER-PROVIDER-DECISIONS.md).

| Surface | Owned value |
|---|---|
| Visible product | `Intentive` |
| macOS application filename | `Intentive.app` |
| Shared technical slug | `heyintentive` |
| Public domain | `heyintentive.com` |
| Stable / Beta / canonical development bundles | `com.heyintentive.intentive`, `com.heyintentive.intentive.beta`, `com.heyintentive.intentive.dev` |
| Named development / preview prefixes | `com.heyintentive.intentive.dev.`, `com.heyintentive.intentive.preview.` |
| Google Cloud project | existing Firebase/GCP project `knowledge-athlete`; billing active, with a permanent-Free-Tier operating constraint |
| Development Cloud Run service | public-ingress `knowledge-athlete-dev` in `knowledge-athlete/us-west1`; protected routes enforce Firebase authentication and development desktop defaults target its discovered URL |
| Container repository | `knowledge-athlete/us-west1/intentive/backend`; the active development revision uses an owned immutable digest and no longer reads a cross-project recovery image |
| Firebase project | existing `knowledge-athlete` for owned development Auth and Firestore |
| Sentry | organization `heyintentive`, macOS project `desktop-macos` |
| PostHog | unconfigured; the Mac fails closed until an owned project token and HTTPS host are supplied through the Intentive configuration keys |
| Langfuse | owned US Cloud project `Intentive`; tracing and Prompt Management remain fail-open observability, not product-data authority |

`intentive.life` and `intuitive.life` are not product domains. They must not be
used for product URLs, support/privacy addresses, bundle identity, or public copy.

### Current macOS safety boundary

- Stable, Beta, development, named-development, and preview bundle/scheme/storage
  identities are now typed under `com.heyintentive.intentive` / `heyintentive`.
- The checked-in Mac app has blank Sparkle feed, Sparkle public key, production API,
  public/legal, and manual-download release metadata. Production-family updates and
  routing fail closed until the signed provider supplies a complete owned configuration.
- The retained Mac backend update resolver and release manifests use
  `sruj75/knowledge-athlete` and Intentive asset names. Windows release ownership is
  intentionally unchanged because S-29 excludes Windows.
- The deny-all Firestore database and owned development Firebase app exist. The public-ingress
  `knowledge-athlete-dev` bootstrap service and free Upstash Redis are verified, including
  per-route Firebase rejection, Firebase-authenticated Firestore write/read, and Redis
  coordination. Development desktop defaults target it; it is not production authority.
- Sentry runtime ingestion and dSYM publication target owned organization
  `heyintentive`, project `desktop-macos`.
- PostHog has no approved project token. Product analytics therefore stays off;
  the inherited Omi token is neither embedded nor used as a fallback.
- Existing Omi icon, logo, and backdrop bytes remain unchanged placeholders until
  the owner supplies and approves an Intentive asset pack. They are not shippable assets.

### Remaining release blockers

- The inherited provisioning profiles are evidence of upstream configuration, not
  shippable Intentive credentials. Owned profiles and Apple capability/provider
  identifiers must replace them; agents must never cosmetically edit inherited
  credentials.
- Apple Team `24D6NXS6H7` has an installed Developer ID Application identity valid
  through 2030-11-18. Codemagic still needs the supplied `.p12` password, active Apple
  membership, and notarization credentials.
- Root `codemagic.yaml` owns Codemagic application `6a8ff0296fc70d39540cb56a` and workflows
  `intentive-macos-release` / `intentive-macos-preview`. Protected provider groups, the GitHub
  release app/token boundary, trusted Intentive M1 runner, production backend/feed, public site,
  and approved legal/support destinations are not configured.
- An approved Intentive app icon, mark, wordmark, and any replacement sign-in backdrop
  are still required before a candidate can be called visually rebranded.
- The complete beginner-facing checklist and account map are tracked in
  [`OWNER-PROVIDER-DECISIONS.md`](OWNER-PROVIDER-DECISIONS.md).

### Signing & distribution

- macOS: Developer ID certificate + notarization. `run.sh:447` already hard-errors
  without a signing identity; ad-hoc signing makes macOS reset TCC permissions on
  every build.
- Windows: the committed `electron-builder.config.mjs:101` is unsigned, while
  `.github/workflows/desktop_windows_release.yml:213` conditionally injects Azure
  Trusted Signing when all seven required secrets exist. Its fallback artifact
  is unsigned and triggers the "unknown publisher" warning.

### Legal

MIT permits rebranding and commercial redistribution, but requires you keep the
copyright notice and license text (`LICENSE`). The license covers the *code* — it
does not grant rights to the "omi" name or logo, so the rename is not optional if
you are shipping this as your own product.

### Current Firebase packaging boundary

S-30 removed the inherited committed production plist. Development packages the
owned `knowledge-athlete` registration, local harnesses use the synthetic
`demo-heyintentive-local` registration, and release builds inject an owned
protected plist or fail closed. Both local and release bundlers remove any nested
Firebase plist left in SwiftPM output.

## Inherited snapshot architecture and as-is rebrand audit (historical)

This historical upstream audit is anchored to baseline commit
`81b5b889cad9eabe7477c9ff6a167a46f56912b6` and the upstream source snapshot
listed above. The inventory below records what owned each identity at that baseline. It
deliberately does not choose replacements or prescribe migration order.

**Coupling legend:** **visible brand** is user-facing copy or imagery;
**external identifier** is registered outside the process; **persistent
identity** partitions user data or operating-system grants; **service
endpoint** selects a network/data owner; **release infrastructure** selects or
authenticates a shipped artifact; **internal-only symbol** is an in-repository
name with no direct user-visible identity.

### macOS identity and persistence

| Surface | Baseline identity | Authority | Role | Ownership | Coupling |
|---|---|---|---|---|---|
| Product and bundle names | `omi`, `Omi`, `Omi Beta`, `Omi Dev`, Swift package/executable `Omi Computer` | Historical upstream plist/package/run configuration and the predecessor of `desktop/macos/scripts/create-intentive-beta-variant.sh` | Finder, menus, onboarding, permission copy, and signed bundle names continued to show Omi in the inherited snapshot. | Omi/BasedHardware | visible brand |
| Brand assets | `OmiIcon`, `omi_app_icon.png`, `omi_text_logo.png`, `omi_menu_bar_icon.png`, `omi_notch_logo.svg`, Omi demo media, and related source names | `desktop/macos/Desktop/Sources/Resources/`, `desktop/macos/omi_icon.icns` | Packaged app, menu bar, onboarding, chat, and installer artwork remain Omi artwork. | Omi/BasedHardware | visible brand |
| Stable/beta identity | `com.omi.computer-macos`, `com.omi.computer-macos.beta` | `desktop/macos/Desktop/Sources/AppBuild.swift`, `desktop/macos/Desktop/Sources/OmiSupport/DesktopLocalProfile.swift`, `desktop/macos/scripts/smoke-signed-desktop-artifact.sh` | Selects production-family routing and partitions TCC, UserDefaults, Keychain ACLs, login items, single-instance locks, updates, and beta storage. | Omi/BasedHardware | external identifier; persistent identity |
| Development/preview identity | `com.omi.desktop-dev`, `com.omi.omi-<slug>`, `com.omi.preview.<id>` | `desktop/macos/scripts/app-config.sh`, `desktop/macos/Desktop/Sources/AppBuild.swift`, `backend/database/desktop_previews.py` | Controls local automation, dev backend defaults, isolated state, and whether Sparkle is allowed. | Omi/BasedHardware | persistent identity |
| OAuth callback schemes | Production `omi-computer`; dev `omi-computer-dev`; named bundles `omi-<slug>`; previews `omi-preview-<id>` | `desktop/macos/Desktop/Info.plist`, `desktop/macos/scripts/app-config.sh`, `desktop/macos/scripts/smoke-signed-desktop-artifact.sh`, `backend/routers/auth.py`, `backend/database/desktop_previews.py` | OAuth providers and macOS route callbacks only to registered schemes; unchanged callbacks remain in the Omi namespace. | Omi/BasedHardware plus provider registration | external identifier |
| Google OAuth/Firebase app registrations | `GoogleService-Info.plist` contained the inherited production client/app for `com.omi.computer-macos`. | Baseline `desktop/macos/Desktop/Sources/GoogleService-Info.plist` | The inherited app supplied Google/Firebase identifiers to packaged macOS builds. | Omi/BasedHardware; Google | external identifier |
| Firebase apps | Production project `based-hardware`, app `com.omi.computer-macos`, plus its storage bucket and API key. | Baseline `desktop/macos/Desktop/Sources/GoogleService-Info.plist` | The inherited plist selected the Firebase project and app embedded by SwiftPM. | Omi/BasedHardware; Firebase | service endpoint; external identifier |
| API routing | Production Python `https://api.omi.me/`, development Python `https://api.omiapi.com/`, production Rust desktop backend `desktop-backend-hhibjajaja-uc.a.run.app`, development Rust desktop backend `desktop-backend-dt5lrfkkoa-uc.a.run.app` | Baseline `desktop/macos/Desktop/Sources/DesktopBackendEnvironment.swift` and `APIClient.swift` | Production and development bundle families selected separate inherited Python and Rust service endpoints. | Omi/BasedHardware | service endpoint |
| PostHog | Hardcoded publishable token `phc_z3qU…v3sez3Y` at `us.i.posthog.com` | `desktop/macos/Desktop/Sources/PostHogManager.swift` | Product analytics and feature flags report to the existing Omi PostHog project. | Omi/BasedHardware; PostHog | service endpoint |
| Sentry | Organization/project `o4511085999816704 / 4511086024851456` | `desktop/macos/Desktop/Sources/OmiApp.swift` | Production crashes, hangs, feedback, and diagnostics report to the existing Sentry project. | Omi/BasedHardware; Sentry | service endpoint |
| Sparkle feed and trust key | `https://api.omi.me/v2/desktop/appcast.xml`; EdDSA public key `vWleho4gIOl932wM4v9Gz+FTCt90+vUVdPHsRReFX40=` | `desktop/macos/Desktop/Info.plist`, `desktop/macos/Desktop/Sources/AppBuild.swift` | Stable/beta clients poll Omi's feed and accept only update archives signed by the matching private key. | Omi/BasedHardware | service endpoint; release infrastructure |
| Release channels | Stable and beta; beta bundle is pinned to beta; GitHub tags use `v<version>+<build>-macos` | `desktop/macos/Desktop/Sources/AppBuild.swift`, `backend/desktop_release_manifest.py`, `.github/workflows/desktop_auto_release.yml` | Channel state determines backend routing, appcast items, manual downloads, telemetry cohort, and promotion evidence. | Omi/BasedHardware | release infrastructure; persistent identity |
| Signing profiles | Committed profiles `desktop/macos/Desktop/embedded.provisionprofile` and `desktop/macos/Desktop/embedded-dev.provisionprofile`, Apple Team `S6DP5HF77G` (`Matthew Diakonov`) | Those profiles, `desktop/macos/Desktop/Omi-Release.entitlements`, `desktop/macos/run.sh` | A different team cannot use these profiles as its own signing/notarization identity; ad-hoc builds do not reproduce stable TCC/Keychain behavior. | Current Apple developer team | external identifier; release infrastructure |
| Keychain services | Bases `com.omi.desktop.firebase-rest-session`, `com.omi.desktop.local-agent-api`, `com.omi.client-device-id`, scoped by Team ID and bundle ID | `desktop/macos/Desktop/Sources/DesktopKeychainStore.swift`, `desktop/macos/Desktop/Sources/AuthService.swift` | Auth, local-agent credentials, and device identity remain stored under Omi-namespaced service identifiers; scope prevents cross-team/bundle reuse. | Local user Keychain; Omi namespace | persistent identity |
| Local storage | Stable `~/Library/Application Support/Omi`; beta `Omi Beta`; named bundles `Omi Dev Bundles/<bundle-id>`; per-user GRDB/SQLite below each root | `desktop/macos/Desktop/Sources/OmiSupport/DesktopLocalProfile.swift`, `desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift`, `desktop/macos/run.sh` | Existing capture, rewind, task, graph, and agent state remains attached to these directory and bundle identities. | Local user | persistent identity |
| Development controls | `OMI_*` environment variables, `omi-*` bundle requirement, `omi-*` scripts and test flows | `desktop/macos/run.sh`, `desktop/macos/scripts/`, `desktop/macos/tests/`, `desktop/macos/e2e/` | These names form the current operator/test interface; changing them independently would break harness and release contracts even though most are not user-facing. | Repository-local | internal-only symbol |

### Windows and shared desktop identity

| Surface | Baseline identity | Authority | Role | Ownership | Coupling |
|---|---|---|---|---|---|
| Windows package | App ID `com.omiwindows.app`, product `Omi for Windows`, executable `omi-windows`, installer `Omi-for-Windows-Setup-*` | `desktop/windows/electron-builder.config.mjs`, `desktop/windows/package.json` | Windows install, shortcuts, uninstall entry, process, and artifact names remain Omi-branded. | Omi/BasedHardware | visible brand; external identifier |
| Windows assets/copy | Committed Omi icons plus Omi website, help, terms, pricing, referral, device, and source links | `desktop/windows/resources/`, renderer settings/home components | Packaged UI and external navigation continue to present or open Omi properties. | Omi/BasedHardware | visible brand; service endpoint |
| Windows Firebase/API | Firebase project `based-hardware`; `https://api.omi.me`; production desktop backend Cloud Run URL | `desktop/windows/.env.example`, `desktop/windows/src/main/ipc/auth.ts`, renderer API helpers | Default sign-in, product requests, live audio, sync, MCP, billing, and agent tools use Omi accounts and data services. | Omi/BasedHardware | service endpoint; external identifier |
| Windows telemetry | Same default PostHog project as macOS; Sentry only when `VITE_SENTRY_DSN` is supplied | `desktop/windows/.env.example`, `desktop/windows/src/renderer/src/lib/analytics.ts`, renderer entry points | Default analytics joins the Omi desktop project; crash reporting follows the build-supplied DSN. | Omi/BasedHardware; PostHog/Sentry | service endpoint |
| Windows persistence | Electron `userData`; `omi.db`; `omi-windows-prefs-v1`; `omi-windows-install-id`; auth, MCP, connector, rewind, and log files | `desktop/windows/src/main/ipc/db.ts`, `desktop/windows/src/main/ipc/authStore.ts`, `desktop/windows/src/renderer/src/lib/preferences.ts`, `desktop/windows/src/renderer/src/lib/clientDevice.ts` | Local identity and user state remain under Omi keys and the Electron app identity. | Local user | persistent identity |
| Windows updates | Backend-selected immutable feed whose URLs must match `BasedHardware/omi/releases/download/<windows-tag>/` | `desktop/windows/src/main/updater.ts`, `desktop/windows/src/main/windowsUpdateFeed.ts`, `desktop/windows/electron-builder.config.mjs`, `backend/routers/updates.py` | Production updates resolve and download Omi GitHub release assets. | Omi/BasedHardware | service endpoint; release infrastructure |
| Windows signing | Conditional Azure Trusted Signing using `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_CODE_SIGNING_ENDPOINT`, `AZURE_CODE_SIGNING_ACCOUNT`, `AZURE_CERT_PROFILE_NAME`, and `AZURE_PUBLISHER_NAME`; unsigned fallback when any value is absent | `.github/workflows/desktop_windows_release.yml`, `desktop/windows/docs/release-pipeline.md`, `desktop/windows/electron-builder.config.mjs` | A complete secret set signs with the configured Azure account/profile/publisher; an incomplete set produces an unsigned installer identified as an unknown publisher. The tracked snapshot cannot prove which GitHub environment secrets are currently populated. | Omi/BasedHardware operator; Azure; local unsigned fallback | external identifier; release infrastructure |
| Electron bridge names | `window.omi`, `window.omiOverlay`, `window.omiBar`, `window.omiGlow`; Omi-named IPC, types, tests, and helpers | `desktop/windows/src/preload/index.ts` and shared types | These are process-internal contracts; a blind rename would require coordinated main/preload/renderer/test changes but would not by itself change product ownership. | Repository-local | internal-only symbol |

### Backend, cloud, and release ownership

| Surface | Baseline identity | Authority | Role | Ownership | Coupling |
|---|---|---|---|---|---|
| GitHub source/releases | `BasedHardware/omi` | Baseline backend update routes, `desktop/macos/Desktop/Sources/AppBuild.swift`, Electron builder/updater, and desktop workflows | Changelogs, update assets, preview admission, release evidence, and allowlists resolved to the upstream repository. | Omi/BasedHardware | service endpoint; release infrastructure |
| GCP/Firebase projects | Development project `based-hardware-dev`, runtime project `based-hardware`, `us-central1`, and Omi-namespaced GKE/Helm resources | Baseline `backend/deploy/runtime_env.yaml` and `.github/workflows/gcp_*.yml` | The inherited manifest selected Omi's development/production cloud projects, networks, services, and secret/config-map names. | Omi/BasedHardware; Google Cloud | external identifier; release infrastructure |
| Backend deployment identity | Cloud Run `backend`, `backend-sync`, `backend-sync-backfill`, and `backend-integration` services plus separately deployed GKE workloads; GCR images used `latest` and short-SHA tags | Baseline `.github/workflows/gcp_backend*.yml`, Helm charts, and deploy scripts | Multiple workflows owned overlapping Cloud Run/GKE build, deploy, traffic, and recovery behavior in `us-central1`. | Omi/BasedHardware; Google Cloud | external identifier; release infrastructure |
| CI control-plane credentials | Long-lived Google JSON secrets including `GCP_CREDENTIALS` and dedicated Firestore credential JSON | Baseline `.github/workflows/gcp_*.yml` | GitHub Actions authenticated the inherited cloud deploy and index lanes with repository/environment secrets. | Omi/BasedHardware; Google Cloud; GitHub | external identifier; release infrastructure |
| Public domains | `api.omi.me`, `api.omiapi.com`, `h.omi.me`, `macos.omi.me`, `windows.omi.me`, and service-specific Omi hosts | Baseline desktop clients, backend sources, and release/deploy workflows | Product APIs, sharing, update/download routing, and service discovery resolved to inherited Omi domains or generated Google service URLs. | Omi/BasedHardware; cloud providers | service endpoint |
| Update asset origin | `https://github.com/BasedHardware/omi/releases/download/` | `backend/routers/updates.py` | Generated macOS appcasts and Windows feed directories hand clients Omi-hosted binaries. | Omi/BasedHardware | service endpoint; release infrastructure |
| Backend data plane | Omi-owned Firestore, Redis/config-map/secret bindings, GCS/update resources, Cloud Run services, and GKE workloads across development and production manifests | Baseline `backend/database/`, `backend/deploy/runtime_env.yaml`, charts, and backend workflows | The inherited deployment graph selected Omi's persistent data, coordination, update, and service infrastructure. | Omi/BasedHardware; cloud providers | service endpoint; persistent identity |
| Provider credentials | OpenAI and Anthropic model credentials, Gemini/Vertex inference, Modulate and Parakeet speech-to-text, plus other service-specific inherited bindings | Baseline backend env templates, `backend/deploy/runtime_env.yaml`, charts, and agent runtime | Multiple provider paths supplied chat, embeddings, translation, realtime/agent behavior, and transcription; provider ownership was not isolated to the later Intentive selection. | Omi/BasedHardware; third-party providers | service endpoint |
| macOS build lane | GitHub candidate/promotion workflows, Codemagic workflow `omi-desktop-swift-release`, Omi-named trusted-runner labels, and Omi Bot tag publication | Baseline `.github/workflows/desktop_*.yml` and release scripts | The inherited lane planned and tagged GitHub releases, delegated Mac builds to the Omi Codemagic workflow, and qualified/promoted artifacts through Omi-owned automation. | Omi/BasedHardware; Codemagic; GitHub; trusted self-hosted runner | release infrastructure |
| Internal source naming | `Omi*` Swift/Python/TypeScript symbols plus `OMI_*` variables and `omi-*` development scripts/test conventions | Baseline source and tests | These names formed in-repository compiler, process, and operator contracts in addition to the separately inventoried external identities. | Omi/BasedHardware repository | internal-only symbol |
| Legal provenance | MIT copyright and license from the upstream snapshot | [LICENSE](LICENSE), this file's provenance section | Redistribution must retain the license notice; the code license does not transfer Omi trademark or service ownership. | Upstream authors | external identifier |

### Current retained boundaries

- `app/`, `web/`, `omi/`, `omiGlass/`, `plugins/`, `sdks/`, `mcp/`, and `docs/`
  are absent. The root Mac build-provider definition is now tracked as `codemagic.yaml`.
- Repository preflight, CI routing, runtime-image ownership, OpenAPI generation,
  and live agent documentation cover only present backend and desktop sources.
- Backend cloud ownership is a direct v1 workflow/WIF plus redacted manifest
  contract, not an in-repository IaC platform. Creation, IAM changes, deploys,
  traffic changes, and cleanup require separately authorized operator evidence.
- GitHub retains candidate tagging and intake observation plus qualification,
  preview, promotion, retry, recovery, and rollback controls. The new Mac provider
  definition owns build/sign/notarize/package/smoke/publish but stays fail-closed until
  the remaining protected provider-group fields and production/public inputs are configured.
- The universal dylibs in `desktop/macos/vendor/libwebp/` now have checked-in
  checksum/architecture/install-name/deployment-target/dependency verification,
  a pinned source-rebuild fallback, and nested-signing preparation scripts.
  Those repository contracts and the provider definition are not proof that a signed
  artifact has been produced or accepted by Apple.
- `.github/workflows/desktop-core-contracts.yml` keeps the independent
  `desktop-core-e2e-t0` self-check. S-10 removed conversation parity and S-12
  removed the final hosted Memory parity contract, fixture, job, discovery
  registry, and guard residue.

### Local conversation authority and exact handoffs

The macOS app is authoritative for conversations in its owner-scoped local
GRDB store. Its ordinary code has no hosted conversation/folder/People/audio
playback caller. `/v4/listen` is now only an authenticated, fixed-PCM transient
Modulate transport: it returns canonical segments and optional keyed
translations without creating or mutating product data. The remaining
server-side residue is intentionally bounded:

| Retained residue | Later owner | Why it remains after S-10 |
|---|---|---|
| Historical conversation columns in `RewindDatabase.swift`, `RewindDatabase+ConversationLocalAuthority.swift`, and `ConversationLocalAuthorityMigrationTests.swift` | S-10 migration ledger | Retired server/cache names occur only while creating the old schema, migrating it once, and proving the new live schema excludes them. They are not current model or caller fields. |
| Historical action-item/staged-task and goal cloud columns in `RewindDatabase.swift` | S-13 migration ledger | The live task/simple-goal schema and every retained caller are local-authoritative. Old names remain only while constructing the inherited schema and proving the forward rebuild removes them; S-10 supplies the stable local conversation source and atomic cascade hooks. |
| Proactive/focus backend identity and sync fields in the shared Rewind store | S-14 | Profile/language authority is separately owned; these matches are not conversation, task, or goal authority. |
| PTT provider-result telemetry in `TranscriptionService.swift` and `PushToTalkManager.swift` | S-19 | Batch PTT still records the backend-selected provider as transient diagnostics; ambient conversation capture neither sends nor persists a provider identity. |
| Generated speech-profile DTO/client residue in `OmiApi.generated.swift` | S-23 | The app-client generator still exports the separately owned speech-profile surface. S-10 removed all Mac People and persistent voice-identity callers; S-16 removed listen's dependency without hand-editing shared generated output. |
| Backend People, speech-profile, speaker-matching, and reusable person-ID helpers/models | S-23 | Server-only historical workflows still own these internals. Listen no longer reads profiles, matches persistent voices, or returns person identity. |
| Local PTT conversation list and hybrid search | S-19 | Owner-fenced GRDB summaries plus local FTS5/persisted vectors replace the retired `/v1/tools/conversations*` boundary. Shared hosted Conversation persistence, transcript hydration, and vector infrastructure remain for S-23/S-24. |
| `backend/database/conversations.py`, `backend/database/folders.py`, hosted finalization/process helpers, and their direct tests/fixtures | S-23 | Existing server workflows still require the datastore; S-10 stops new Mac projection but does not wipe live data or remove shared persistence. |
| `conv_discard`, `conv_structure`, and `conv_action_items` model-policy configuration | S-22 | S-10 consumes these existing feature keys through stateless compute routes; model routing remains independently owned. |

S-24 removes the hosted Typesense and Pinecone search handoff left after S-23.
Local macOS FTS5 and persisted-vector search remain authoritative and do not
depend on those providers.

S-25 removed the private-sync audio worker, queue, playback helpers, and rejected
storage branch. The independently owned desktop update and preview buckets
remain with their release owners.

### Local Chat authority and exact handoffs

The owner-scoped `omi-agentd.sqlite3` catalog and journal are authoritative for
ordinary macOS Chat identity, metadata, turns, and activity. Swift owns drafts
and app-managed attachment bytes. The backend stores none of that normal Chat
product data; its greeting, title, and managed-answer routes are transient
compute only. The remaining similarly named backend residue has separate live
callers and later owners:

| Retained residue | Later owner | Why it remains after S-11 |
|---|---|---|
| `chat_responses`, `session_titles`, and their typed model-policy artifacts | Retained direct-model owners | `session_titles` is the pinned transient S-11 title workload; retained Chat/model compute uses explicit direct provider clients and workload-owned QoS. |
| `/v2/voice-messages`, `/v2/voice-message/transcribe`, `/v2/voice-message/transcribe-stream`, and their multipart, duration, `load_voice_message_segment_bytes`, and `transcribe_voice_message_bytes` helpers | S-19 | Voice-message and push-to-talk speech transport are transient STT, distinct from the deleted hosted Chat persona and from local Chat persistence. |

S-24 removes the final hosted file/session helpers, OpenAI Files/Assistants
integration, cloud thumbnails, and `/v1/files`. Ordinary attachments remain
owner-local, app-managed files.

### Local Memory authority and exact handoffs

The macOS app is authoritative for Memories in its effective-owner `omi.db`.
`MemoryStorage` owns all durable reads, mutations, lifecycle leases,
transition receipts, provenance, and local vectors. The Memories page, local
automation, Chat/PTT/Pi tools, screenshot and proactive writers, and profile or
suggestion readers share that boundary. Hosted Memory product routes,
Firestore Memory documents/rules/indexes, vector/search projections,
maintenance jobs, parity fixtures, and generated hosted DTOs are absent.

The backend retains exactly three authenticated stateless proposal routes:
`/v1/memory/compute/extract`, `/normalize`, and `/consolidate`. They use pinned
Gemini 3.7 Flash compute and cannot assign a durable Memory identity or persist
input/output. Gemini embedding remains a transient shared proxy; the Mac owns
the resulting vectors. S-23 owns
remaining hosted conversation internals, and S-24/S-25 own their separately
listed cloud-state and operational teardown boundaries.

### Payment activation checkpoint

No payment feature is currently live. The MVP stays free through all six waves,
with `BILLING_MODE=disabled`, no purchasable catalog, **Skip** as the usage-limit
action, no entitlement grant, and zero Dodo or Stripe calls. The permanent
operator handoff is [`bootstrap-scaffold/dodo-integration.md`](bootstrap-scaffold/dodo-integration.md).

- [x] Free MVP and disabled billing checkpoint are the current repository state.
- [x] Wave 3 may consume this repository checkpoint without activating payments.
- [x] Checkout, webhook, portal, plan-change, cancellation, quota/fair-use, and
  account-deletion behavior remain retained behind the disabled boundary.
- [ ] After Wave 6, run the complete Dodo test-mode E2E and preserve evidence.
- [ ] Obtain separate authorization before configuring live Dodo resources.
- [ ] Mark S-18 complete only after the bounded live transaction, cancellation,
  monitoring, cleanup, and rollback proof pass.
