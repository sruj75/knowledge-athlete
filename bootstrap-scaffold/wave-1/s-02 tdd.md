# S-02 TDD Plan — Remove wearable devices, Omi WAL, and device-audio ingestion

## Plan record

| Field | Decision |
|---|---|
| Artifact | `bootstrap-scaffold/wave-1/s-02 tdd.md` |
| Status | `ready to start` — requirements-backed public TDD seams are recorded; repository Cycles 0-6 are executable and destructive live closeout remains separately gated |
| Wave / owner | Wave 1 / S-02 |
| Authorizing decisions | IR-012, IR-013, IR-014, IR-359, IR-823 |
| Protecting decisions | IR-007, IR-017, IR-018, IR-019, IR-021, IR-022, IR-023, IR-069, IR-070, IR-898 |
| Coordinated owners | S-06 for historical Dashboard Omi content and the separate hosted Limitless ZIP importer; S-25 for final shared worker/service deletion |
| Dependencies | None |
| Baseline | `origin/main`; fetch and record the exact merge-base when implementation starts |
| Research evidence | Requirements validator currently passes: 714 indexed rows, 714 detailed sections, all reviewed |
| Delivery | One slice and eventual PR, with separate vertical commits; no push or PR without a new user request |
| Postcondition | The Mac records only approved Mac audio sources; no direct Omi or third-party wearable runtime—including the Limitless adapter—Omi raw-audio WAL, wearable upload, conversation-photo protocol, or hardware firmware API remains, while Mac capture, PTT, local persistence, ordinary Bluetooth audio devices, historical source decoding, and shared backend jobs continue working. |

S-02 becomes code-complete after repository verification, but remains `operational closeout pending` until any destructive live-cloud cleanup receives fresh explicit approval and is verified.

## Execution workflow

1. Begin implementation with [engineering:implement](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/implement/SKILL.md), using this plan as the specification. Run `make setup`, preserve existing scaffold edits, stay on the current branch, and commit locally by vertical tracer.
2. Apply [engineering:tdd](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/tdd/SKILL.md): observe one intended RED, implement the minimum GREEN, then continue to the next tracer. Do not write every test first.
3. Apply [engineering:codebase-design](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/codebase-design/SKILL.md) when collapsing the one-case desktop audio-source API and separating shared job locks from wearable sync ownership. Add no compatibility aliases or hypothetical provider abstractions.
4. Finish with [engineering:code-review](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/code-review/SKILL.md), fixed to the freshly fetched `origin/main`. Run its independent Standards and Spec Compliance reviews against this plan, fix valid findings, and rerun affected verification.

## Boundary and current flow

```text
BLE discovery/pairing
  → Omi/OpenGlass/Bee/Fieldy/Friend/Limitless/Plaud/Frame adapter
  → device transport, codec, buttons, battery, storage and firmware
  → live frames or storage/Wi-Fi recovery
  → BleAudioService / BleAudioProcessor
  → Omi WAL files
  → /v1 or /v2/sync-local-files
  → async job, decoding, STT and hosted conversation processing
  → wearable photo and firmware surfaces
```

| Action | Required boundary |
|---|---|
| **KEEP AS IS** | Mac microphone/system audio, meeting detection, three-way System Audio mode, local Parakeet, managed Modulate fallback, PTT/realtime voice, manual microphone selection, `TranscriptionStorage`, GRDB and SQLite `omi.db-wal`, generic diarization/local labels, ordinary Bluetooth CoreAudio devices, Rewind/PTT/Chat images, Sparkle updates |
| **ADAPT** | Make desktop transcription inherently Mac-sourced; make new conversations `.desktop`; remove live device state from Dashboard while retaining account-history content; extract shared backend job locks to a neutral module without changing keys or semantics |
| **DELETE** | CoreBluetooth wearable stack, every Omi and third-party device provider/adapter—including `LimitlessDeviceConnection`—exclusive codecs/UI, Omi WAL and recovery, wearable ingestion routes/jobs/queues/staging, conversation-photo protocol/storage, wearable firmware API, exclusive tests/generated contracts/configuration/docs |
| **SIMPLIFY / OPTIMIZE AFTER** | Remove the resulting one-case `AudioSource` abstraction, dead state and imports only after the relevant GREEN; shrink mixed sync modules without moving retained playback/voice helpers unnecessarily |
| **ACCELERATE AFTER** | `none`; record cycle timings but add no speculative performance work |
| **AUTOMATE LAST** | Adapt existing route, runtime-manifest and deployment checks in their current CI lanes; add no free-floating residue checker |
| **OUT OF SCOPE / DEFERRED** | Windows, hosted STT-provider deletion, server conversation-authority deletion, Dashboard historical Omi badge/link, generic playback/audio merge, final `backend-sync` removal, historical data purge without approval |

## Public interface changes and agreed test seams

- Desktop transcription becomes source-free: remove `.bleDevice`, `audioSource`, forced-cloud wearable policy and source parameters. Preserve local/cloud fallback behavior and write new sessions as `.desktop`.
- Preserve historical `ConversationSource` decoding values so existing records remain readable.
- Remove these backend routes and generated bindings with no compatibility shell:
  - `POST /v1/sync-local-files`
  - `POST /v2/sync-local-files`
  - `GET /v2/sync-local-files/{job_id}`
  - `POST /v2/sync-capture-manifest`
  - `POST /v2/sync-jobs/run`
  - wearable firmware `/v2/firmware/*`
- A stale client sending a valid `image_chunk` over `/v4/listen` must fail closed with WebSocket policy code `1008`, create no photo data, and invoke no vision provider. Remove photo events and models from the supported contract.
- Preserve `/v1/sync/audio/*`, audio-merge execution, multipart voice decoding, account deletion, conversation finalization and their Cloud Tasks behavior.
- Move shared run-lock functions into `backend/database/job_run_locks.py`, retaining their signatures and Redis-key semantics for rolling-deploy safety.
- Preserve the shared `backend-sync` deployment and any still-consumed shared invoker configuration until S-25.

## Ordered TDD cycles

### Cycle 0 — baseline and inventory

Run the ledger validator and focused retained tests before editing. Record every device—including every `LimitlessDeviceConnection` caller—WAL, sync, photo and firmware reference as S-02-owned, retained shared code, historical data compatibility, Windows, or a named later-slice handoff. Classify the separate hosted Limitless ZIP importer to S-06; it is not a reason to retain direct hardware support.

A passing characterization test is baseline evidence, not a RED.

### Cycle 1 — Mac-only transcription

**RED:** Change `STTSessionState` and AppState behavior tests to the source-free API. Assert retained Apple-Silicon local selection, Intel/cloud selection, local-to-cloud and cloud-to-local fallback, meeting/system-audio gating, `.desktop` persistence and historical source decoding. Observe the current source-taking API fail to compile or violate the new contract.

**GREEN:** Remove `.bleDevice`, forced-cloud routing, wearable button/start/stop paths and device labels. Collapse the transcription entry point to Mac capture without changing the retained mode policy.

With the behavior green, delete the now-unreachable CoreBluetooth device tree, every Omi and third-party provider/adapter including Limitless, exclusive codecs/services, device permission state, onboarding defaults and `NSBluetoothAlwaysUsageDescription`. Remove only live `DeviceProvider` coupling from Dashboard; retain its backend-derived history presentation.

### Cycle 2 — Omi WAL closure

**RED:** Extend the desktop package/build contract to reject an exposed `OmiWAL` product while retained `TranscriptionStorage` recovery tests continue proving GRDB durability.

**GREEN:** Remove the SwiftPM target, raw-frame WAL/storage/Wi-Fi recovery, upload/poll clients, models, UI and exclusive tests. Do not match `WAL` generically: preserve SQLite `omi.db-wal`, Calendar database journaling and agent-turn WAL concepts.

Package/source-absence checks are closure tripwires; they do not replace the retained persistence behavior tests.

### Cycle 3 — wearable backend ingestion

**RED:** Through FastAPI’s public router, assert every removed upload, polling, manifest and internal execution route returns `404`, while retained playback/audio-merge routes remain registered and functional.

**GREEN:** Remove wearable route handlers, sync ledger/job lifecycle, content identity, lanes, backfill, capture manifest, rate limiting, staging and pipeline code. Retain shared decoding used by voice messages and retained playback.

Move shared run locks to the neutral module and migrate account deletion, audio merge and conversation-finalization callers in the same change. Remove wearable queue dispatch while preserving generic Cloud Tasks machinery.

### Cycle 4 — wearable conversation photos

**RED:** Send a valid `image_chunk` through the listen WebSocket. Assert policy close `1008`, no image-description call, no photo write/event and continued normal transcript behavior in a separate session.

**GREEN:** Remove chunk envelopes/buffers, photo processing events, `ConversationPhoto`, Firestore photo read/write/encryption, conversation photo fields, LLM photo inputs, Mac no-op handlers, generated types and `photosJson`.

Preserve Rewind screenshots, frozen PTT screenshot grounding, Chat attachments and historical `ConversationSource.openglass` decoding.

### Cycle 5 — wearable firmware API

**RED:** Assert `/v2/firmware/latest`, `/stable` and `/version` return `404`, while retained desktop updater/Sparkle and shared GitHub-release-helper tests remain green.

**GREEN:** Delete the firmware router, registration, hardware mappings, OTA parsing/cache use, generated methods and exclusive tests. Keep shared GitHub release utilities required by the Mac updater.

### Cycle 6 — operational and contract closure

**RED:** Update existing runtime/deployment contract tests to require no `backend-sync-backfill`, wearable queues, ingestion variables, route-policy entries or generated API operations, while still requiring retained shared workloads.

**GREEN:** Remove exclusive workflows, actions, queue/service declarations, secrets, alerts, metrics, fixtures, replay/sync harnesses and current documentation. Update the backend listen-pusher documentation, component guides, desktop E2E flows, OpenAPI export/inventory and generated Swift client.

Do not delete `backend-sync`, retained shared invoker configuration or shared playback/voice helpers merely because their names contain `sync`.

## Review, verification, and live closeout

After all RED/GREEN cycles are green:

- Remove dead one-case interfaces, imports and compatibility scaffolding; do not redesign retained capture, PTT, STT or persistence.
- Run scoped residue searches with explicit allowances for CoreAudio Bluetooth devices, SQLite/agent WALs, historical source enums, retained `/v1/sync/audio`, Windows and immutable historical records.
- Run focused Swift tests for session policy, system audio/meeting behavior, storage recovery, PTT and updater behavior, followed by `cd desktop/macos && bash test.sh`.
- Run focused backend route, listen, playback, audio-merge, Cloud Tasks, run-lock and GitHub-release tests, followed by `cd backend && bash test-preflight.sh && bash test.sh`.
- Run runtime-env validation, backend pre-deploy checks, OpenAPI/route-policy generation checks, `make preflight`, `git diff --check`, the requirements validator and `scripts/pr-preflight --suggest`.
- Launch only a uniquely named development bundle such as `omi-s02-wearable-removal`. Exercise continuous microphone transcription under all three System Audio modes, meeting gating, local persistence/recovery and an authenticated PTT turn. Never touch the production Omi bundles.
- Capture commands, exit statuses and user-path evidence in the commit/PR record. Any rewritten expectation must cite the authorizing IR.
- Review the complete three-dot diff against `origin/main`; stop at local commits unless separately authorized to publish.

Live teardown is a separate approval gate after the code/config deployment:

1. Inventory and drain `backend-sync-backfill`, wearable queues, pending sync jobs, staging objects, ledgers, secrets and alerts.
2. Report resource names, counts, retention implications and rollback/backup options without exposing user content.
3. Request fresh explicit approval before deleting live services, queues, secrets, Firestore records, GCS objects or historical photo subcollections.
4. After approval, delete only the inventoried wearable-exclusive resources and verify retained account-deletion, finalization and audio-merge workloads.
5. Without that approval, leave historical data inaccessible but intact and report S-02 as `operational closeout pending`, not fully closed.

## Acceptance criteria

- No direct wearable—including Limitless—can be discovered, paired, controlled, decoded, displayed or updated by the Mac.
- No Omi raw-audio WAL or wearable upload/poll path remains.
- No wearable audio, photo or firmware route remains in the Python backend or generated clients.
- Mac microphone/system audio, all System Audio modes, meeting behavior, local/managed STT, PTT and local GRDB persistence pass automated and real-path verification.
- Ordinary Bluetooth headphones/microphones, historical source records, Rewind/PTT/Chat images, playback/audio merge and Sparkle remain operational.
- Every remaining device/WAL/sync/photo/firmware reference is explained by a retained boundary, historical evidence, Windows exclusion or named later-slice owner.
- `engineering:code-review` completes both review axes against `origin/main`, all valid findings are resolved, and affected checks are rerun.
