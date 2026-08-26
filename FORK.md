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

The emulators replace Google, not the AI vendors. For a hermetic local stack,
run `PROVIDER_MODE=offline make dev-up` without provider credentials. Real mode
requires OpenAI, Modulate, Gemini, and Anthropic keys in
`backend/.env.local-dev`; `make dev-init` creates that untracked file.

`desktop/macos/run.sh --yolo` skips all local infrastructure and points at omi's
hosted dev backend. Convenient, but per upstream's own warning it uses **production
Firebase identities and data stores**. Use the emulator path instead.

Prerequisites: Xcode + an Apple signing identity, `brew install webp`, Node 22.x
(`>=22.19 <23`), pnpm, Python 3.11 + `uv`, JDK 21+ (the Firebase emulators need it),
ffmpeg, opus.

## Rebrand checklist — before shipping your own build

Every item below is omi's identity baked into the source. The build succeeds without
changing them, which is exactly why they are easy to ship by accident.

### Will break your product if missed

- **Sparkle update keypair** — `desktop/macos/Desktop/Info.plist:66` pins
  `SUPublicEDKey` to omi's public key, and `:65` points `SUFeedURL` at
  `https://api.omi.me/v2/desktop/appcast.xml`. Generate your own EdDSA keypair
  (Sparkle's `generate_keys`) and repoint the feed. Ship as-is and your own updates
  fail signature validation and never install — while your users poll omi's feed.
- **Update asset origin** — `backend/routers/updates.py:375` hardcodes
  `https://github.com/BasedHardware/omi/releases/download/`. Your generated appcast
  will hand out omi's binaries.
- **Windows publish target** — `desktop/windows/electron-builder.config.mjs:178`
  publishes to `owner: 'BasedHardware', repo: 'omi'`.

### Identity / credentials

- **Firebase projects** — production/dev macOS and Windows config use
  `based-hardware`; the local macOS profile uses emulator-only
  `demo-omi-local`. See `desktop/macos/Desktop/Sources/GoogleService-Info{,-Dev,-Local}.plist`,
  `desktop/windows/.env.example:7`, and the public web API key at
  `desktop/macos/run.sh:111`.
- **Bundle IDs and OAuth scheme** — `com.omi.*` in `desktop/macos/scripts/app-config.sh:23,38`;
  `com.omi.computer-macos` in the Firebase plist; URL scheme `omi-computer-dev`.
- **API base URLs** — `desktop/macos/Desktop/Sources/DesktopBackendEnvironment.swift:4,6`
  (`api.omi.me`, `api.omiapi.com`); share links at `APIClient.swift:704` (`h.omi.me`).
- **PostHog** — key `phc_z3qU…` is hardcoded at `PostHogManager.swift:14` and
  `desktop/windows/.env.example:20`. Your telemetry lands in omi's project otherwise.
- **Sentry DSN**, and the provisioning profiles `desktop/macos/Desktop/embedded{,-dev}.provisionprofile`
  (omi's — replace with yours).

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

## Current architecture and as-is rebrand audit

This current-state audit is anchored to baseline commit
`81b5b889cad9eabe7477c9ff6a167a46f56912b6` and the upstream source snapshot
listed above. The inventory below records what owns each identity today. It
deliberately does not choose replacements or prescribe migration order.

**Coupling legend:** **visible brand** is user-facing copy or imagery;
**external identifier** is registered outside the process; **persistent
identity** partitions user data or operating-system grants; **service
endpoint** selects a network/data owner; **release infrastructure** selects or
authenticates a shipped artifact; **internal-only symbol** is an in-repository
name with no direct user-visible identity.

### macOS identity and persistence

| Surface | Current identity | Authority | Role | Ownership | Coupling |
|---|---|---|---|---|---|
| Product and bundle names | `omi`, `Omi`, `Omi Beta`, `Omi Dev`, Swift package/executable `Omi Computer` | `desktop/macos/Desktop/Info.plist`, `desktop/macos/Desktop/Package.swift`, `desktop/macos/run.sh`, `desktop/macos/scripts/create-omi-beta-variant.sh` | Finder, menus, onboarding, permission copy, and signed bundle names continue to show Omi while unchanged. | Omi/BasedHardware | visible brand |
| Brand assets | `OmiIcon`, `omi_app_icon.png`, `omi_text_logo.png`, `omi_menu_bar_icon.png`, `omi_notch_logo.svg`, Omi demo media, and related source names | `desktop/macos/Desktop/Sources/Resources/`, `desktop/macos/omi_icon.icns` | Packaged app, menu bar, onboarding, chat, and installer artwork remain Omi artwork. | Omi/BasedHardware | visible brand |
| Stable/beta identity | `com.omi.computer-macos`, `com.omi.computer-macos.beta` | `desktop/macos/Desktop/Sources/AppBuild.swift`, `desktop/macos/Desktop/Sources/OmiSupport/DesktopLocalProfile.swift`, `desktop/macos/scripts/smoke-signed-desktop-artifact.sh` | Selects production-family routing and partitions TCC, UserDefaults, Keychain ACLs, login items, single-instance locks, updates, and beta storage. | Omi/BasedHardware | external identifier; persistent identity |
| Development/preview identity | `com.omi.desktop-dev`, `com.omi.omi-<slug>`, `com.omi.preview.<id>` | `desktop/macos/scripts/app-config.sh`, `desktop/macos/Desktop/Sources/AppBuild.swift`, `backend/database/desktop_previews.py` | Controls local automation, dev backend defaults, isolated state, and whether Sparkle is allowed. | Omi/BasedHardware | persistent identity |
| OAuth callback schemes | Production `omi-computer`; dev `omi-computer-dev`; named bundles `omi-<slug>`; previews `omi-preview-<id>` | `desktop/macos/Desktop/Info.plist`, `desktop/macos/scripts/app-config.sh`, `desktop/macos/scripts/smoke-signed-desktop-artifact.sh`, `backend/routers/auth.py`, `backend/database/desktop_previews.py` | OAuth providers and macOS route callbacks only to registered schemes; unchanged callbacks remain in the Omi namespace. | Omi/BasedHardware plus provider registration | external identifier |
| Google OAuth/Firebase app registrations | Production client `208440318997-suqloh00q5r3ovgoqikvsrf9aqn1t54e.apps.googleusercontent.com`, reversed client `com.googleusercontent.apps.208440318997-suqloh00q5r3ovgoqikvsrf9aqn1t54e`, app `1:208440318997:ios:5a9bb6d5a555e8d90e421c`; development client `208440318997-68pb7d72igtvl7jgr1ep6d3m6qn4pnbo.apps.googleusercontent.com`, reversed client `com.googleusercontent.apps.208440318997-68pb7d72igtvl7jgr1ep6d3m6qn4pnbo`, app `1:208440318997:ios:a1906bb92fe244810e421c`; local emulator client `local-omi-dev-local.apps.localhost`, app `1:000000000000:ios:omi-dev-local` | `desktop/macos/Desktop/Sources/GoogleService-Info.plist`, `desktop/macos/Desktop/Sources/GoogleService-Info-Dev.plist`, `desktop/macos/Desktop/Sources/GoogleService-Info-Local.plist` | Production and development Google sign-in remain bound to the upstream OAuth registrations; the local values are emulator-only and do not identify a hosted Google application. | Omi/BasedHardware; local harness; Google | external identifier |
| Firebase apps | Production/dev project `based-hardware`; local project `demo-omi-local`; production bundle `com.omi.computer-macos` | `desktop/macos/Desktop/Sources/GoogleService-Info.plist`, `desktop/macos/Desktop/Sources/GoogleService-Info-Dev.plist`, `desktop/macos/Desktop/Sources/GoogleService-Info-Local.plist` | Default sign-in uses Omi Firebase identities; local profiles use emulators and a non-production project name. | Omi/BasedHardware; local harness | service endpoint; external identifier |
| API routing | Canonical production `api.omi.me`, development `api.omiapi.com`, share host `h.omi.me` | `desktop/macos/Desktop/Sources/DesktopBackendEnvironment.swift`, `desktop/macos/Desktop/Sources/APIClient.swift`, `desktop/macos/run.sh` | Production-family builds use one fail-closed backend data-plane URL; named/dev bundles may explicitly override `OMI_PYTHON_API_URL`. Auth callback routing remains an explicit separate rule. | Omi/BasedHardware | service endpoint |
| PostHog | Hardcoded publishable token `phc_z3qU…v3sez3Y` at `us.i.posthog.com` | `desktop/macos/Desktop/Sources/PostHogManager.swift` | Product analytics and feature flags report to the existing Omi PostHog project. | Omi/BasedHardware; PostHog | service endpoint |
| Sentry | Organization/project `o4511085999816704 / 4511086024851456` | `desktop/macos/Desktop/Sources/OmiApp.swift` | Production crashes, hangs, feedback, and diagnostics report to the existing Sentry project. | Omi/BasedHardware; Sentry | service endpoint |
| Sparkle feed and trust key | `https://api.omi.me/v2/desktop/appcast.xml`; EdDSA public key `vWleho4gIOl932wM4v9Gz+FTCt90+vUVdPHsRReFX40=` | `desktop/macos/Desktop/Info.plist`, `desktop/macos/Desktop/Sources/AppBuild.swift` | Stable/beta clients poll Omi's feed and accept only update archives signed by the matching private key. | Omi/BasedHardware | service endpoint; release infrastructure |
| Release channels | Stable and beta; beta bundle is pinned to beta; GitHub tags use `v<version>+<build>-macos` | `desktop/macos/Desktop/Sources/AppBuild.swift`, `backend/desktop_release_manifest.py`, `.github/workflows/desktop_auto_release.yml` | Channel state determines backend routing, appcast items, manual downloads, telemetry cohort, and promotion evidence. | Omi/BasedHardware | release infrastructure; persistent identity |
| Signing profiles | Committed profiles `desktop/macos/Desktop/embedded.provisionprofile` and `desktop/macos/Desktop/embedded-dev.provisionprofile`, Apple Team `S6DP5HF77G` (`Matthew Diakonov`) | Those profiles, `desktop/macos/Desktop/Omi-Release.entitlements`, `desktop/macos/run.sh` | A different team cannot use these profiles as its own signing/notarization identity; ad-hoc builds do not reproduce stable TCC/Keychain behavior. | Current Apple developer team | external identifier; release infrastructure |
| Keychain services | Bases `com.omi.desktop.firebase-rest-session`, `com.omi.desktop.local-agent-api`, `com.omi.client-device-id`, scoped by Team ID and bundle ID | `desktop/macos/Desktop/Sources/DesktopKeychainStore.swift`, `desktop/macos/Desktop/Sources/AuthService.swift` | Auth, local-agent credentials, and device identity remain stored under Omi-namespaced service identifiers; scope prevents cross-team/bundle reuse. | Local user Keychain; Omi namespace | persistent identity |
| Local storage | Stable `~/Library/Application Support/Omi`; beta `Omi Beta`; named bundles `Omi Dev Bundles/<bundle-id>`; per-user GRDB/SQLite below each root | `desktop/macos/Desktop/Sources/OmiSupport/DesktopLocalProfile.swift`, `desktop/macos/Desktop/Sources/Rewind/Core/RewindDatabase.swift`, `desktop/macos/run.sh` | Existing capture, rewind, task, graph, and agent state remains attached to these directory and bundle identities. | Local user | persistent identity |
| Development controls | `OMI_*` environment variables, `omi-*` bundle requirement, `omi-*` scripts and test flows | `desktop/macos/run.sh`, `desktop/macos/scripts/`, `desktop/macos/tests/`, `desktop/macos/e2e/` | These names form the current operator/test interface; changing them independently would break harness and release contracts even though most are not user-facing. | Repository-local | internal-only symbol |

### Windows and shared desktop identity

| Surface | Current identity | Authority | Role | Ownership | Coupling |
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

| Surface | Current identity | Authority | Role | Ownership | Coupling |
|---|---|---|---|---|---|
| GitHub source/releases | `BasedHardware/omi`; this fork's remote is `sruj75/knowledge-athlete` | Backend update routes, `desktop/macos/Desktop/Sources/AppBuild.swift`, Electron builder/updater, desktop workflows | Changelogs, update assets, preview admission, release evidence, and allowlists still resolve or require the upstream repository. | Omi/BasedHardware; local fork | service endpoint; release infrastructure |
| GCP/Firebase projects | Externally supplied development/production project IDs, project numbers, Firebase projects, networks, service accounts, and resource names | `backend/deploy/runtime_env.yaml`, `.github/workflows/gcp_backend*.yml`, `.github/workflows/gcp_firestore_indexes.yml` | The tracked contract rejects inherited defaults and requires environment-scoped owned inputs. This snapshot does not claim those resources exist, match the declaration, or that inherited live resources are safe to remove; that needs verified read-only inventory and separately authorized mutation. | Product cloud operator; Google Cloud | external identifier; release infrastructure |
| Canonical backend deployment identity | One `backend` Cloud Run service per environment in `us-west1`, built in regional Artifact Registry with a full commit-SHA tag and deployed by captured digest | `backend/deploy/runtime_env.yaml`, `backend/runtime_images.json`, `.github/workflows/gcp_backend.yml`, `.github/workflows/gcp_backend_auto_dev.yml` | One manifest/renderer owns capacity, probes, networking, runtime identity, exact secret versions, stable discovered `run.app` URL, candidate acceptance, traffic, rollback, and evidence. Short SHA is revision-display-only; no custom backend domain or floating image tag is declared. | Repository contract; product cloud operator; Google Cloud | external identifier; release infrastructure |
| CI control-plane credentials | Backend and Firestore workflows use environment-scoped WIF provider plus distinct deploy, read-only index, and create-only index-writer service accounts; desktop/Codemagic/Azure release credentials remain separately inventoried | `.github/workflows/gcp_*.yml`, `.github/workflows/desktop_*.yml`, `.github/AGENTS.md`, `desktop/macos/AGENTS.md`, `desktop/windows/docs/release-pipeline.md` | Backend cloud workflows no longer accept long-lived Google JSON keys. Exact numeric GitHub claims, provider/IAM existence, GitHub environment population, and negative cross-environment proof are external operational evidence, not facts implied by this checkout. | Product cloud operator; Google Cloud; Codemagic; Azure | external identifier; release infrastructure |
| Public domains | Desktop consumers still contain `api.omi.me`, `api.omiapi.com`, `h.omi.me`, `macos.omi.me`, `windows.omi.me`, and retained service-specific Omi hosts; backend deployment acceptance uses its owned stable `run.app` URL | Desktop clients and release workflows; backend deploy workflows | S-27 removes inherited DNS from backend deployment authority without absorbing S-29's desktop routing, feeds, downloads, signing, or channel migration. | Omi/BasedHardware for retained desktop endpoints; product cloud operator for backend `run.app` | service endpoint |
| Update asset origin | `https://github.com/BasedHardware/omi/releases/download/` | `backend/routers/updates.py` | Generated macOS appcasts and Windows feed directories hand clients Omi-hosted binaries. | Omi/BasedHardware | service endpoint; release infrastructure |
| Backend data plane | Externally named Firestore plus environment-isolated private Redis, one retained update/preview GCS bucket, the account-deletion queue, and canonical Cloud Run, all in `us-west1` | `backend/database/`, `backend/config/desktop_storage.py`, `backend/deploy/runtime_env.yaml`, backend workflows | The manifest owns the redacted shape: ADC/exact secrets, Redis AUTH and verified TLS, survivor-only create-safe indexes, update/preview prefixes, queue signer/audience, logging/alerts/budgets, and dry-run-only registry cleanup. Mac conversations and Memories remain excluded; live conformance remains unverified. | Repository contract; product cloud operator; cloud providers | service endpoint; persistent identity |
| Provider credentials | OpenAI, Anthropic, Gemini, Modulate, Dodo Payments, email, connector, and related environment-backed accounts | Backend env templates, runtime env contract, and workflow secrets | Values are not selected by a visual rebrand. Billing is disabled by default; an operator must explicitly select Dodo test or live mode and supply its API key, webhook key, and normalized server-owned offer catalog. | Third-party accounts configured by operator | service endpoint |
| macOS build lane | External workflow identity `omi-desktop-swift-release`, `CODEMAGIC_API_TOKEN`, self-hosted `omi-qual-m1-studio`, then GitHub promotion workflows | `desktop/macos/AGENTS.md`, release docs, `.github/workflows/desktop_*.yml` | GitHub can observe same-tag provider intake and qualify/publish an artifact, but this checkout has no tracked build-provider definition. S-29 owns adding that definition before the lane is self-contained. | Omi/BasedHardware; external build provider/self-hosted runner | release infrastructure |
| Internal source naming | `Omi*` Swift/Python/TypeScript symbols plus repository-local `OMI_*` variables and `omi-*` development scripts/test conventions | Retained source and tests; macOS development controls are inventoried above | These symbols can remain without contacting Omi and do not by themselves preserve an upstream account, endpoint, shipped bundle identity, or deployment resource. Blind renames would still require coordinated in-tree caller and test changes. | Local repository | internal-only symbol |
| Legal provenance | MIT copyright and license from the upstream snapshot | [LICENSE](LICENSE), this file's provenance section | Redistribution must retain the license notice; the code license does not transfer Omi trademark or service ownership. | Upstream authors | external identifier |

### Current retained boundaries

- `app/`, `web/`, `omi/`, `omiGlass/`, `plugins/`, `sdks/`, `mcp/`, `docs/`,
  and the root Mac build-provider definition are absent.
- Repository preflight, CI routing, runtime-image ownership, OpenAPI generation,
  and live agent documentation cover only present backend and desktop sources.
- Backend cloud ownership is a direct v1 workflow/WIF plus redacted manifest
  contract, not an in-repository IaC platform. Creation, IAM changes, deploys,
  traffic changes, and cleanup require separately authorized operator evidence.
- GitHub retains candidate tagging and intake observation plus qualification,
  preview, promotion, retry, recovery, and rollback controls. S-29 owns adding a
  fresh Mac build/sign/notarize provider definition; until then this checkout
  does not claim a self-contained artifact-production lane.
- The universal dylibs in `desktop/macos/vendor/libwebp/` now have checked-in
  checksum/architecture/install-name/deployment-target/dependency verification,
  a pinned source-rebuild fallback, and nested-signing preparation scripts.
  Those repository contracts are not proof that the still-missing provider lane
  exists or that a signed artifact has been produced.
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
OpenAI GPT-4.1-mini compute and cannot assign a durable Memory identity or
persist input/output. Gemini embedding remains a transient shared proxy; the
Mac owns the resulting vectors. S-22 may replace provider routing, S-23 owns
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
