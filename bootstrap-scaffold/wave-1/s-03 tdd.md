# S-03 TDD plan — remove hosted GPU Parakeet and every Deepgram branch

## Plan record

| Field | Value |
|---|---|
| Status | `researched` — **public seams plus the IR-228, IR-400, and model-order decisions require human approval before implementation starts** |
| Wave | 1 |
| Owning subagent | S-03 |
| Authorizing decisions | IR-019, IR-062, IR-887, IR-888, IR-889 |
| Protecting decisions | IR-023, IR-054, IR-055, IR-059 through IR-061, IR-069, IR-071, IR-072, IR-115 through IR-119, IR-228, IR-400 through IR-405, IR-891 |
| Coordinated owners | S-07 for customer-BYOK/key deletion; S-16 for the wider `/v4/listen` wire-contract cleanup; S-30 for Local VAD Gate truthfulness if the copy conflict is not resolved here |
| Dependencies | None |
| Target baseline | `origin/main`; re-fetch and record the exact merge-base when implementation starts |
| Research snapshot | Current checkout at `5ecb5e17aeab01955aff150a22054a957e15a48e`; requirements and source must be rechecked if the merge-base changes |
| Postcondition | Mac-local embedded Parakeet remains the only Parakeet runtime. Modulate is the only managed STT adapter for continuous, prerecorded, and PTT-fallback transcription. Hosted GPU Parakeet and managed/self-hosted Deepgram have no executable code, selectable tokens, images, charts, workflows, credentials, configuration, monitoring, tests, fixtures, benchmarks, or live product/documentation claims. OpenAI/Gemini PTT and the provider-neutral listen/transcript contracts remain intact. |

### Known research baseline

- The requirements ledger passes: 710 indexed rows, 710 detailed sections, all reviewed.
- Development and production runtime-env validation pass with workflow checks.
- The 28 focused policy/configuration/async-offload tests that can collect in the current environment pass.
- The wider focused backend selection is not a known product failure, but it cannot collect in this shell yet: `backend/.venv` is absent and global Python lacks `fal_client` and `ulid`. `engineering:implement` must begin with `make setup` and the documented backend environment, then establish a full clean baseline before the first RED.
- `scripts/pr-preflight --suggest` currently fails before S-03 code is considered because this no-history product snapshot excludes `docs/product/invariants/`. Do not disable or weaken the check in S-03. Record it as a baseline blocker, assign/restore the missing invariant source through the repository owner, and require the normal check before closure.
- Product source under the S-03 paths matches `origin/main` at this snapshot; the branch is one bootstrap-scaffold documentation commit ahead. The repository cannot supply granular upstream STT history, so the current code, requirements ledger, and executable contracts are the authoritative evidence.

## How this plan is executed

1. After the seams below are approved, start with [engineering:implement](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/implement/SKILL.md), using this file as the implementation spec. Its first setup operation is `make setup`, followed by a clean baseline in the documented backend/Desktop environments. Work on the current branch, use the RED → GREEN cycles in order, and commit locally in testable vertical slices. Do not push or open a PR without a separate user request.
2. Use [engineering:tdd](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/tdd/SKILL.md) throughout implementation. A new test must fail for the intended behavioral reason before production code changes; implement only enough to make that test pass. Do not write all tests first.
3. Apply the interface rules from [engineering:codebase-design](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/codebase-design/SKILL.md): keep the retained STT boundary provider-neutral and small, put provider behavior behind it, and delete the provider-selection abstraction that no longer has multiple production implementations.
4. After all cycles and full verification are green, finish with [engineering:code-review](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/code-review/SKILL.md). Pin the review fixed point to the freshly fetched `origin/main`, use this file as the spec, review Standards and Spec Compliance separately, fix findings, and rerun the affected checks.

## Decision summary and non-goals

“Parakeet” names two different systems in the current repository. This slice deletes only the hosted backend/GPU service and its client. It does not delete the embedded Mac model.

The resulting engine boundary is:

```text
Mac ambient transcription
  ├─ Apple Silicon + healthy model ──> embedded Mac-local Parakeet
  └─ Intel or local-model failure ───> authenticated /v4/listen ──> Modulate

Mac push to talk
  ├─ native OpenAI Realtime / Gemini Live
  ├─ retained intermediate realtime relay (/v1/omni/relay)
  └─ retained managed STT fallback (streaming or completed-turn batch) ──> Modulate
```

This slice does **not**:

- replace or redesign Modulate;
- delete, redesign, or choose between OpenAI Realtime and Gemini Live;
- redesign PTT state, UI, TTS, relay, local speech admission, or language authority;
- remove `/v4/listen`, translation, VAD, generic speaker labels, ready/failure events, or fallback telemetry;
- remove the embedded Mac Parakeet model or its local/cloud fallback;
- complete the product-wide customer-BYOK deletion owned by S-07, except where an S-03-owned provider surface cannot compile or close while retaining a Deepgram key field;
- complete the broader listen-protocol cleanup owned by S-16;
- alter Windows code or historical changelogs.

## Current flow and failure boundary

Today the public Mac transports are mostly provider-neutral, but their implementations and route vocabulary still fan out by retired provider:

1. `AppState+Transcription.swift` chooses embedded `LocalTranscriptionService` or the cloud `TranscriptionService` transport. The cloud transport connects to `/v4/listen`.
2. `backend/routers/listen/receiver.py` and `backend/utils/stt/streaming.py` select among Modulate, hosted Parakeet, and Deepgram/self-hosted Deepgram. Provider policy, language/model aliases, backoff, and fallback circuitry keep all branches live.
3. PTT first tries its retained OpenAI/Gemini routes. Its streaming and completed-turn fallbacks enter `/v2/voice-message/transcribe-stream` and `/v2/voice-message/transcribe`; the backend again selects a managed STT provider. Swift still calls these routes `deepgramLive` and `deepgramBatch` even when the endpoint does not use Deepgram.
4. Deployment manifests, Helm values, image registries, workflows, secrets, dashboards, alerts, tests, benchmarks, and docs independently preserve hosted Parakeet and Deepgram as operable services.

The failed ownership boundary is therefore larger than a client deletion: provider choice is duplicated across runtime code, desktop vocabulary, and the deployment control plane. S-03 closes that whole failure class by making **Modulate the fixed backend adapter**, while leaving local-vs-cloud selection on the Mac and PTT route selection in the voice-turn domain.

The researched owner inventory at the snapshot is:

| Layer | Current owners and mixed seams |
|---|---|
| Backend policy/config | `backend/config/stt_provider_policy.py`, `backend/config/prerecorded_stt.py`, and `backend/deploy/runtime_env.yaml` retain service enums, provider order, model aliases, URLs, and credentials. |
| Backend runtime | `backend/utils/stt/streaming.py`, `pre_recorded.py`, `safe_socket.py`, and `vad_gate.py`; `backend/routers/listen/receiver.py` and `backend/routers/chat.py`. The VAD/outcome portions are shared keep surfaces; the provider clients and switches are deletion surfaces. |
| Desktop runtime | `LocalTranscriptionService.swift`, `TranscriptionService.swift`, `AppState+Transcription.swift`, `VoiceTurnStateMachine.swift`, `PushToTalkManager.swift`, and `VoiceTurnCoordinator.swift`. Public transports are retained; provider-named route cases, comments, key forwarding, and copy are mixed cleanup/handoff surfaces. |
| Hosted services | `backend/parakeet/**`, `backend/charts/parakeet/**`, and `backend/charts/deepgram-self-hosted/**`. |
| Deployment/control plane | `.github/workflows/gcp_parakeet.yml`, `.github/workflows/parakeet_gpu_tests.yml`, shared backend/listen/pusher workflows, `backend/runtime_images.json`, listen/secrets Helm values, `config/deployment-setting-classification.json`, and provider-specific monitoring assets. |
| Dependencies/support | `deepgram-sdk` in backend/pusher/OpenAPI requirements and lockfiles; provider-specific benchmarks, repro tools, fixtures, container tests, unit tests, runbooks, environment templates, and current docs. |
| Existing regression fences | Backend provider-policy, prerecorded-config/language, Modulate, listen-pipeline/failure/VAD, desktop-transcribe, voice-message, runtime-env, Helm, workflow, and runtime-image tests; Swift listen-protocol, transport, reducer, coordinator, and PTT state-machine tests. Source-inspection tripwires do not substitute for these behavioral seams. |

## Proposed public seams — approval gate

Implementation must not begin until the following observable seams are accepted. Tests target these interfaces, not private call order or source-string placement.

| Seam | Contract to preserve/prove | Main test surface |
|---|---|---|
| Mac ambient engine choice | A healthy supported Mac uses embedded Parakeet. Intel/model-load failure uses the authenticated cloud transport. A cloud failure can still follow the existing local fallback policy. No backend-hosted Parakeet is involved. | Existing `AppState`/local transcription behavior tests plus a named-bundle exercise; add a new test only if the production seam lacks behavioral coverage |
| Managed live transcription | `/v4/listen` accepts the existing provider-neutral audio framing and emits the retained ready, transcript, generic speaker, translation, and terminal-failure behaviors through a Modulate adapter. Remove the Parakeet-only `stt_service` hint end to end; all other S-16-owned fields remain unchanged. | WebSocket/listen receiver with a controllable Modulate fake; existing listen protocol and failure tests |
| Managed PTT transcription | `/v2/voice-message/transcribe-stream` and `/v2/voice-message/transcribe` retain their public success, silence, language, finalization, and typed-error behavior, backed only by Modulate. | Endpoint tests through the public router with a controllable Modulate fake |
| Voice-turn fallback | A native hub/relay failure can reach a capability-named managed streaming/batch route without changing turn ownership, UI state, terminal state, journaling, or TTS. | `VoiceTurnStateMachine`, reducer, and coordinator behavioral tests |
| Operator/deployment contract | Every backend runtime, image, secret, workflow, and chart resolves to Modulate-only STT; a retired provider cannot be selected or deployed. | Existing runtime-env, Helm-default, runtime-image, workflow, and deploy-preflight contract tests |

### One requirements conflict to approve

IR-228 says to preserve the Local VAD Gate card, state, restart behavior, disconnected `VADGateService`, diagnostics, tests, **and exact current copy**. That copy says the feature reduces “Deepgram API usage.” IR-889 and S-03 require all live Deepgram product claims to disappear. Both cannot be true at closure.

Recommended interpretation: IR-889 supersedes only the retired provider noun. Keep every IR-228 behavior and the rest of the copy unchanged, but replace “Deepgram API usage” with “managed cloud transcription usage.” Do not wire up, repair, remove, or otherwise redesign the Local VAD Gate. If exact IR-228 wording must instead remain, S-03 cannot meet its no-live-Deepgram-residue postcondition; record an explicit exception owned by S-30 and leave this plan blocked rather than declaring it complete.

Two narrower design choices are part of the proposed seam approval:

- S-03 removes IR-400's `stt_service` query field and preferred-provider reordering end to end because its only behavior is to bias hosted Parakeet. Keeping it as an ignored field would be a forbidden compatibility shell. If the human assigns public-schema deletion to S-16 instead, S-03 still removes all routing effect and records the exact contract/file handoff.
- S-03 deletes `STT_SERVICE_MODELS` and `STT_PRERECORDED_MODEL` end to end. With one managed adapter, retaining comma-list parsing or a one-element “provider order” is misleading configuration. The deploy contract should instead prove the fixed Modulate policy and its product-owned `MODULATE_API_KEY` binding.

## Action ledger

This ledger is the implementation scope. Before the first RED cycle, turn each grouped row into an exact tracked-file inventory at the pinned merge-base; every discovered provider hit must be assigned to one row or explicitly excluded as historical/Windows/local-Parakeet.

| Required action stage | Slice-level commitment |
|---|---|
| **KEEP AS IS** | Embedded Mac-local Parakeet; reviewed Modulate behavior; public listen/transcript framing; generic speaker, translation, VAD, and ready/failure contracts; retained OpenAI/Gemini/relay PTT behavior |
| **ADAPT** | Collapse managed STT to a fixed Modulate adapter and make Mac voice-turn routes capability-named without changing their lifecycle behavior |
| **DELETE** | Hosted GPU Parakeet plus managed and self-hosted Deepgram across runtime, deploy, configuration, credentials, support assets, dependencies, tests, and current docs |
| **SIMPLIFY / OPTIMIZE AFTER** | After every RED/GREEN cycle is green, shrink provider-neutral interfaces, remove compatibility shells, and make ownership read as Mac local/cloud choice → voice route choice → one backend adapter |
| **ACCELERATE AFTER** | `none` planned. Record focused-loop durations reported by `dev-feedback.py`, but do not invent a performance objective for a deletion slice. Any later acceleration needs a measured S-03 bottleneck and its own evidence. |
| **AUTOMATE LAST** | `none` new planned. Adapt already-enforced manifest/runtime contract tests in their existing CI lane. Residue classification remains closure evidence; do not add a new permanent source scraper without a qualifying shipped failure. |
| **OUT OF SCOPE / DEFERRED** | Windows; Gemini-vs-OpenAI choice; PTT/translation/persistence redesign; product-wide BYOK work owned by S-07; broad listen-protocol cleanup owned by S-16 |

| Action | Surface | Planned treatment |
|---|---|---|
| **KEEP AS IS** | `desktop/macos/Desktop/Sources/LocalTranscriptionService.swift` and the embedded model/runtime | Preserve Mac-local Parakeet and its successful transcript path. Do not rename it merely because the hosted service is deleted. |
| **KEEP AS IS** | `AppState/AppState+Transcription.swift` local-vs-cloud selection | Preserve the Intel/model-failure cloud fallback and existing cloud-to-local behavior. Adapt only retired provider vocabulary or credentials that S-07 explicitly co-owns. |
| **KEEP AS IS** | Modulate streaming and prerecorded adapter behavior | Preserve language routing, transient processing, connection/error handling, generic diarization, VAD integration, and transcript outcomes. |
| **KEEP AS IS** | `/v4/listen`, `/v2/voice-message/transcribe-stream`, `/v2/voice-message/transcribe` public behavior | Keep framing, auth, ready/failure events, transcript/translation shape, silence and finalization semantics. Preserve the live Modulate-backed PTT WebSocket even though stale comments call it Deepgram. Provider-selection hints are not part of the retained contract. |
| **KEEP AS IS** | OpenAI/Gemini PTT, `/v1/omni/relay`, TTS, local speech admission, and PTT language authority | These are neighboring routes, not Deepgram branches. Protect them with existing reducer/coordinator/harness coverage. |
| **ADAPT** | `backend/config/stt_provider_policy.py` and `backend/config/prerecorded_stt.py` | Collapse all three managed STT surfaces to Modulate. Delete selectable Deepgram/Parakeet enums, aliases, model maps, defaults, `STT_SERVICE_MODELS`, and `STT_PRERECORDED_MODEL`. Fail clearly when required Modulate configuration is absent; do not silently revive another provider. |
| **ADAPT** | `backend/utils/stt/streaming.py`, `pre_recorded.py`, and `vad_gate.py` | Retain a small provider-neutral socket/transcript boundary and the Modulate adapter. Delete provider selection, remote-Parakeet circuits, Deepgram adapters/backoff, aliases such as `GatedDeepgramSocket`, and provider-specific internal names. Preserve provider-neutral VAD and outcome helpers. |
| **ADAPT** | `backend/routers/listen/receiver.py` and `backend/routers/chat.py` | Inject/use the fixed Modulate adapter. Remove provider switches and rename generic locals/comments. Preserve endpoint response and failure contracts. |
| **ADAPT** | `TranscriptionService.swift`, `VoiceTurnStateMachine.swift`, `PushToTalkManager.swift`, and `VoiceTurnCoordinator.swift` | Keep transports and behavior; replace `.deepgramBatch` with a capability name such as `.managedBatch`, use `.managedStream` only if it is a real distinct route, delete dead `.deepgramLive`, and remove misleading comments/telemetry labels. Do not add compatibility enum cases or provider aliases. |
| **DELETE** | `backend/parakeet/**` and `backend/charts/parakeet/**` | Delete the hosted GPU Parakeet server, image definition, chart, and service-specific documentation. |
| **DELETE** | Hosted-Parakeet client code and support | Delete remote socket/client, model/language maps, URL/capacity/order settings, fallback circuit, benchmarks, GPU/OOM scripts, container/GPU tests, fixtures, and exclusive docs. |
| **DELETE** | Managed Deepgram code | Delete SDK client/imports, API-key and endpoint handling on S-03-owned STT surfaces, model/alias parsing, backoff/socket helpers, benchmarks, tests, and docs. |
| **DELETE** | `backend/charts/deepgram-self-hosted/**` | Delete the complete vendored self-hosted Deepgram chart and its service-specific configuration. Do not leave a dormant chart. |
| **DELETE** | `backend/utils/stt/safe_socket.py` | Delete after proving it has no retained non-Deepgram caller. |
| **DELETE** | Provider deployments and controls | Remove `gcp_parakeet.yml`, `parakeet_gpu_tests.yml`, retired-provider steps from shared workflows, runtime image registration, Helm values, runtime-env fields, secret bindings, dashboards, alert rules, runbooks, and deployment-setting classification. |
| **DELETE/ADAPT** | Tests, fakes, scripts, and docs | Delete tests that assert an exclusive retired implementation. Adapt shared public-contract tests to Modulate-only behavior. Update component guides and current architecture/product docs; keep historical changelogs untouched. |
| **ADAPT** | Mixed VAD/failure tests and offline harnesses | Keep `test_vad_gate.py`, `test_live_stt_failure.py`, their retained generic sections, and IR-891 offline STT scenarios. Replace Deepgram/Parakeet sockets with the small provider-neutral fake and preserve VAD, teardown, terminal-failure, framing, and Modulate behavior. |
| **COORDINATE** | Deepgram customer keys and BYOK UI/API surfaces | S-07 owns product-wide deletion. S-03 removes a field now only when it is inside an S-03-owned interface or blocks removal of a live Deepgram branch; otherwise record the exact S-07 handoff and do not duplicate work. The final integrated tree must contain no live Deepgram key path. |
| **OUT OF SCOPE / DEFERRED** | Windows, unrelated translation implementation, conversation persistence redesign, Gemini-vs-OpenAI choice | Leave unchanged. Classify search hits rather than expanding this slice. |

## Interface design

The target is not a new provider framework. With one managed provider, an enum-and-switch “provider policy” adds states the product no longer supports.

- Keep the existing provider-neutral transcript/socket concepts used by the listen receiver and router as the public test seam. Shrink them to what Modulate and a hermetic test fake both need: audio input, lifecycle/close, transcript callback, and typed failure/outcome.
- Put Modulate connection details behind that boundary. Backend callers request “managed streaming” or “managed prerecorded transcription”; they do not pass a provider token.
- Keep local-vs-cloud selection in the Mac application. The backend must not model Mac-local Parakeet.
- Keep voice-turn routing capability-based (`native hub`, `relay`, `managed streaming`, `managed batch`) and separate from the managed adapter identity.
- Do not add deprecated aliases, compatibility initializers, unused adapter registries, or fallback booleans for retired provider names. One external Modulate adapter plus a test fake is enough to justify the interface; a hypothetical future provider is not.
- Retain `record_fallback`/`recordFallback` wherever a branch changes correctness or mode. Change dimensions/labels from a retired provider name to the capability name only when the observable event contract remains coherent.

## Ordered TDD implementation cycles

### Cycle 0 — freeze the keep boundary (no new passing “characterization” test)

Before changing code, run and record the existing tests for Mac-local Parakeet selection, cloud fallback, listen framing/events, Modulate behavior, PTT state transitions, translation, VAD, and generic speaker labels. If an observable keep-boundary lacks coverage, do not add a test that passes against the old code and call that TDD. Instead, make the first corresponding deletion produce a real behavioral RED through the public seam, then restore only the retained behavior.

Also pin the exact file/hit inventory and classify each hit as S-03, S-07, S-16, historical, Windows, or embedded local Parakeet. This classification is evidence, not a new source-scraping guard.

### Cycle 1 — one managed-provider policy

**RED:** Through the public provider/configuration API, assert that continuous, prerecorded, and PTT managed transcription resolve to Modulate without accepting a Deepgram or hosted-Parakeet token, and that missing Modulate configuration returns the intended configuration failure rather than selecting a fallback provider. Observe the test fail on the current multi-provider policy.

**GREEN:** Collapse `stt_provider_policy.py` and `prerecorded_stt.py` to the Modulate contract. Remove retired enums, aliases, model maps, default order, and environment parsing. Update only callers needed to compile and pass this vertical contract.

Delete `STT_SERVICE_MODELS` and `STT_PRERECORDED_MODEL` from the code/config/deploy contract in this cycle; do not replace them with a one-element list. The surviving required secret is the product-owned `MODULATE_API_KEY`.

**Verify before next cycle:** focused provider-policy and prerecorded-config tests; a residue search limited to these modules and their direct callers.

### Cycle 2 — `/v4/listen` through Modulate only

**RED:** Exercise the real listen receiver/WebSocket boundary with a controllable Modulate fake. Prove the main success path (ready + transcript, including retained generic speaker/translation behavior) and the main error path (adapter initialization or terminal upstream failure produces the retained failure behavior and cleanup). Make the assertion fail because the current receiver can still select a retired branch or exposes its vocabulary.

**GREEN:** Remove Deepgram and hosted-Parakeet selection/connect/process paths from the receiver and streaming module. Delete remote-Parakeet fallback circuitry and the exclusive Deepgram safe-socket/backoff path once no retained caller remains. Keep the Modulate adapter, provider-neutral VAD, outcomes, callbacks, ready/failure events, and fallback telemetry.

Remove `stt_service` from `backend/routers/listen/contracts.py`, runtime selection, desktop query construction if present, pusher/replay fixtures, and public wire-contract tests. If schema ownership is explicitly reassigned to S-16, remove its routing effect here and record the exact remaining field/test handoff.

**Verify before next cycle:** focused Modulate, listen-pipeline, live-failure, VAD-gate, outcome, and listen WebSocket tests. Adapt `test_vad_gate.py` and `test_live_stt_failure.py` to a provider-neutral fake; do not delete their mixed retained coverage.

### Cycle 3 — managed PTT streaming fallback

**RED:** Through `/v2/voice-message/transcribe-stream`, use the Modulate fake to prove transcript delivery/finalization and the primary terminal-error path. Assert the public behavior without inspecting private call order. The test must expose a current retired-provider branch or name and fail for that reason.

**GREEN:** Collapse the streaming PTT endpoint to the fixed Modulate adapter. Rename `dg_socket`-style locals and comments; remove hosted-Parakeet/Deepgram branches. Preserve framing, authorization, close/finalization, language, silence, and typed-error behavior.

**Verify before next cycle:** focused desktop-transcribe, voice-message async/stream, language, and chat-stream fallback tests.

### Cycle 4 — managed completed-turn/prerecorded fallback

**RED:** Through `/v2/voice-message/transcribe` and the public prerecorded seam, prove Modulate success and the main error/silence outcome. Cover retained automatic language behavior without encoding a provider model name. Observe failure while the public configuration/client still accepts retired providers.

**GREEN:** Delete managed Deepgram and hosted-Parakeet prerecorded adapters, token parsing, credentials, model aliases, and diarization implementations exclusive to those adapters. Keep Modulate and the provider-neutral transcript/outcome shape. Do not broaden this cycle into PTT language-policy redesign; IR-072 remains authoritative for its owner.

**Verify before next cycle:** focused prerecorded language/config, endpoint, upstream-boundary, and transcription-outcome tests.

### Cycle 5 — provider-neutral Mac voice-turn routes

**RED:** In `VoiceTurnStateMachine`/reducer/coordinator tests, assert that a native hub/relay failure reaches the capability-named managed fallback and preserves turn ownership, terminal state, presentation, journaling, and TTS behavior. Assert that no selectable route represents a retired Deepgram-only live path. Observe the test fail on `.deepgramBatch`/`.deepgramLive`.

**GREEN:** Rename the real batch route to `.managedBatch`, add a managed-stream name only if production actually selects a separate route, and delete dead `.deepgramLive`. Update coordinator labels, manager branches, telemetry dimensions, comments, and behavioral tests without adding a compatibility alias. Keep `.omniSTT` and native OpenAI/Gemini routes unchanged.

**Verify before next cycle:** focused voice-turn reducer, fuzz, coordinator, PTT state-machine, transport, and listen-protocol tests; then the Swift-only agent-logic harness.

### Cycle 6 — undeploy both retired services

**RED:** Extend the existing runtime-env/Helm/runtime-image/workflow contract tests so the deployable graph contains Modulate but cannot render, reference, or select hosted Parakeet or Deepgram. Use existing manifest contract surfaces; do not add a free-floating script that CI never runs. Observe failures from the current images, values, secrets, and workflows.

**GREEN:** Remove the hosted-Parakeet image/service/chart/workflows and the full self-hosted Deepgram chart. Remove retired runtime-env keys, model orders, URLs, secret bindings, deployment classification, shared-workflow steps, dashboards, alerts, and runbooks. Update mixed operational assets to Modulate-only wording rather than deleting unrelated observability.

**Verify before next cycle:** focused runtime-env render/validator, listen Helm defaults, runtime-image source closure, workflow contract tests, and `backend/scripts/pre-deploy-check.sh`.

### Cycle 7 — delete exclusive code, dependencies, tests, and docs

**RED:** Use the closest existing behavioral or deployment contract for each remaining live owner. If a leftover is unreachable and has no public behavior, the failing proof is the existing build/import/dependency/manifest contract—not a brittle source-order assertion. Record why each deletion is exclusive.

**GREEN:** Delete `backend/parakeet/**`, both retired service charts, exclusive GPU/container tests, SDK clients, fixtures, benchmarks, repro scripts, and current docs. Remove `deepgram-sdk` only after proving no retained import; regenerate all affected lockfiles with the repository script. Update `backend/AGENTS.md`, backend setup/env docs, the listen/pusher pipeline documentation where present, and current Mac product copy. Apply the approved IR-228 wording decision without changing Local VAD Gate behavior.

**Verify before review:** no unexplained live retired-provider residue; focused component suites remain green; dependency locks reproduce.

## Review and simplification — only after GREEN

Do not refactor while a RED cycle is unresolved. After Cycle 7 is green:

1. Delete unnecessary provider-policy types, duplicate configuration layers, compatibility initializers, dead route cases, aliases, provider-specific locals, and unreachable fallback branches revealed by the now-single-adapter design.
2. Check that the retained interface can explain the module without exposing Modulate-specific connection details. If the public surface still has provider selection with only one implementation, shrink it.
3. Check every moved responsibility: Mac chooses local versus cloud; voice-turn chooses route capability; backend chooses no provider; the Modulate adapter owns provider details; deployment owns one managed-provider configuration.
4. Run the deletion test mentally and mechanically: removing the Modulate adapter should leave its small interface/fake consumers clear, while removing either retired provider should leave no compatibility shell.
5. Invoke `engineering:code-review` with fixed point `origin/main` and this spec. Run the required independent Standards and Spec Compliance reviews, aggregate them separately, fix all valid findings, and rerun the checks affected by each fix.

## Verification and closure evidence

Implementation is not complete until all applicable evidence below is captured with command, exit status, and a short result. Commands may be adjusted to current documented component runners, but a skipped real path must be reported as a blocker, not implied green.

### Focused and full automated checks

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py

python3 backend/scripts/validate-backend-runtime-env.py --env dev --check-workflows
python3 backend/scripts/validate-backend-runtime-env.py --env prod --check-workflows

cd backend
python3 -m pytest tests/unit/test_stt_provider_policy.py \
  tests/unit/test_prerecorded_stt_config.py \
  tests/unit/test_prerecorded_language_coverage.py \
  tests/unit/test_modulate_stt.py \
  tests/unit/test_desktop_transcribe.py \
  tests/unit/test_voice_message_transcribe_async.py \
  tests/unit/test_backend_runtime_env_validator.py \
  tests/unit/test_render_backend_runtime_env.py \
  tests/unit/test_backend_listen_helm_defaults.py
./scripts/pre-deploy-check.sh
bash test.sh

cd ../desktop/macos
./scripts/dev-feedback.py --once swift 'VoiceTurn|PushToTalk|Transcription|ListenProtocol'
./scripts/agent-logic-harness.sh --swift-only
xcrun swift build -c debug --package-path Desktop

cd ../..
make runtime-image-source-closure
make preflight
git diff --check
```

If test names or runner options change before implementation, derive the replacement from the component `AGENTS.md`; do not silently drop a covered contract. Refresh Python locks with `backend/scripts/update-python-lock.sh` after dependency removal and verify the hook is installed before committing.

### Residue closure

Run scoped searches over production source, app source, tests, workflows, deploy/config, secrets, monitoring, scripts, current docs, fixtures, and dependencies. At minimum search case-insensitively for:

- `deepgram`, `nova`, Deepgram endpoint/key/model aliases, self-hosted chart/release names;
- hosted Parakeet URLs, images, charts, workflow names, capacity/model-order settings, and backend client classes;
- provider selection/order fields and old Swift route/telemetry labels.

Every remaining match must be classified in the plan evidence as one of:

1. embedded Mac-local Parakeet (required keep);
2. immutable historical changelog/requirement evidence;
3. Windows (out of scope);
4. an exact, named handoff to S-07/S-16/S-30 with a reason it cannot leave in S-03.

There may be no unexplained live production, UI, config, secret, job, infra, metric, alert, test, fixture, contract, or current-doc match. A passing structural validator alone is not closure.

### Real user-facing exercises

Use a uniquely named development bundle and never stop, replace, or attach to `/Applications/Omi.app` or `Omi Beta.app`:

```bash
cd desktop/macos
OMI_APP_NAME=omi-s03-stt ./run.sh
```

1. Run a natural ambient transcription on supported Apple Silicon and prove the transcript came from embedded local Parakeet.
2. Force the documented local-model failure/unsupported-CPU seam and prove the same public flow reaches `/v4/listen` and receives a live Modulate transcript.
3. Exercise a normal authenticated PTT turn through the retained OpenAI/Gemini path.
4. Exercise the managed streaming or completed-turn PTT fallback against the development backend and prove Modulate success, terminal error handling, and final UI/turn state.
5. Run the provider/deploy inline probe required by the desktop guide, and inspect sanitized backend and named-bundle logs for retired-provider selection or credential lookup.

For the managed release-authority path, use the repository's redacting capability probe against the exact candidate rather than printing keys, protected URLs, audio, or transcript text:

```bash
python3 backend/scripts/transcription_capability_probe.py \
  --candidate-api-url "$CANDIDATE_URL" \
  --bearer-token-file "$TOKEN_FILE"
```

Hermetic fakes prove control flow; they do not replace the live Modulate exercise. If credentials or a safe development backend are unavailable, state that exact blocker and do not mark S-03 complete.

### Final repository proof

- Re-run `scripts/pr-preflight --suggest` and record every matched invariant/failure-class requirement before drafting any `fix:` PR body.
- Re-run `make preflight` and the component suites after review fixes.
- Inspect `git diff origin/main...HEAD`, `git status --short`, and the commit series for accidental user-file changes or unrelated scope.
- Confirm docs, component guides, environment templates, lockfiles, and deployment manifests moved with the code.
- Confirm each commit records verification evidence and any `fix:` commit has the required `Failure-Class` trailer.
- Stop at local commits unless the user separately authorizes push/PR creation.

## Completion checklist

- [ ] The five public seams and the IR-228 copy, IR-400 `stt_service`, and model-order-knob interpretations were approved before tests were written.
- [ ] Every new test was observed RED for the intended behavioral reason, then GREEN with the minimum implementation.
- [ ] Embedded Mac-local Parakeet passed automated and real-path verification.
- [ ] Modulate passed managed live, prerecorded, and PTT-fallback success/error verification.
- [ ] OpenAI/Gemini PTT, relay, VAD, translation, generic diarization, ready/failure events, and telemetry remained green.
- [ ] Hosted GPU Parakeet and both Deepgram branches were deleted across code and every control-plane/support surface.
- [ ] Deepgram SDK imports/dependencies and hosted-Parakeet image/dependencies were removed and locks regenerated.
- [ ] All remaining provider-name search hits were classified; no unexplained live residue remained.
- [ ] S-07/S-16/S-30 handoffs, if any, named exact files/fields and did not conceal a live selectable provider.
- [ ] Focused tests, full component suites, deploy checks, named-bundle exercises, and `make preflight` passed with recorded evidence.
- [ ] `engineering:code-review` completed both review axes against `origin/main`; findings were fixed and checks rerun.
