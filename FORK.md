# Fork provenance & rebrand checklist

## Provenance

Snapshot (no history) of a subset of [BasedHardware/omi](https://github.com/BasedHardware/omi).

| | |
|---|---|
| Source commit | `99e0e60be67a4f727ddfab4858184d75da2494a5` |
| Source tag | `v0.12.147+12147-macos` |
| Snapshot date | 2026-07-30 |
| Upstream license | MIT |

Upstream paths were preserved verbatim, so a future `git diff` against upstream at
this SHA is meaningful and cherry-picking upstream commits still applies cleanly.

## What was included

| Path | Why |
|---|---|
| `desktop/macos/` | Native Swift 6 / SwiftUI app + bundled Node agent runtime |
| `desktop/windows/` | Electron + React + TS app (also builds mac/linux targets) |
| `desktop/shared-rust/` | Carried per request; not built by either app today |
| `backend/` | FastAPI + Firestore/Redis/LLM gateway, Helm charts |
| `scripts/` | `dev-instance.sh` (sourced by `desktop/macos/run.sh`) and `dev-harness/` (local emulator stack) |
| `.github/` | CI + the desktop release chain |
| `infrastructure/opentofu/` | GCP foundation + workload-identity-federation setup |
| `config/`, `contract_tests/` | Build-contract JSON and backend parity fixtures |
| Root `Makefile`, `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `package.json` | Load-bearing: the harness hard-fails without the firebase trio; the Makefile is the only entry point to `dev-harness` |

## What was excluded

`app/` (Flutter mobile), `web/`, `omi/` (firmware/hardware), `omiGlass/`, `plugins/`,
`sdks/`, `mcp/`, `docs/`, root `Package.swift` (the iOS SDK), `codemagic.yaml` (mobile CI).

Roughly 1.24 GB upstream to ~129 MB here.

Some retained workflows have `paths:` filters pointing at excluded directories
(`runtime_image_contracts.yml` → `plugins/**`, `public-build-config-preflight.yml` →
`web/**`). They simply never trigger. Harmless, but they are dead weight if you
never restore those directories.

## Running it

```bash
make dev-up          # Firebase Auth + Firestore emulators + local Redis
make dev-desktop     # the above, then launch the macOS app against it
```

The emulators replace Google, not the AI vendors — you still need OpenAI, Deepgram,
and Pinecone keys in `backend/.env` for the app to do anything useful.

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

- **Firebase project `based-hardware`** — `desktop/macos/Desktop/Sources/GoogleService-Info{,-Dev,-Local}.plist`,
  `desktop/windows/.env.example:7`, and a hardcoded key at `desktop/macos/run.sh:111`.
- **Bundle IDs and OAuth scheme** — `com.omi.*` in `desktop/macos/scripts/app-config.sh:23,38`;
  `com.omi.computer-macos` in the Firebase plist; URL scheme `omi-computer-dev`.
- **API base URLs** — `desktop/macos/Desktop/Sources/DesktopBackendEnvironment.swift:4,6`
  (`api.omi.me`, `api.omiapi.com`); share links at `APIClient.swift:704` (`h.omi.me`).
- **PostHog** — key `phc_z3qU…` is hardcoded at `PostHogManager.swift:14` and
  `desktop/windows/.env.example:20`. Your telemetry lands in omi's project otherwise.
- **Sentry DSN**, and the provisioning profiles `desktop/macos/Desktop/embedded{,-dev}.provisionprofile`
  (omi's — replace with yours).

### Signing & distribution

- macOS: Developer ID certificate + notarization. `run.sh:442` already hard-errors
  without a signing identity; ad-hoc signing makes macOS reset TCC permissions on
  every build.
- Windows: **currently unsigned** (see `electron-builder.config.mjs:101`). SmartScreen
  will warn "unknown publisher" until you add an EV / Azure Trusted Signing cert.

### Legal

MIT permits rebranding and commercial redistribution, but requires you keep the
copyright notice and license text (`LICENSE`). The license covers the *code* — it
does not grant rights to the "omi" name or logo, so the rename is not optional if
you are shipping this as your own product.
