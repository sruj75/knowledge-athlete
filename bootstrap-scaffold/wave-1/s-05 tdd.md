# S-05 TDD Plan — make managed Pi the only local agent entrance

## Plan record

| Field | Value |
|---|---|
| Target artifact | `bootstrap-scaffold/wave-1/s-05 tdd.md` |
| Status | Ready to start; requirements-backed public seams are recorded and `omi-tools-stdio` is resolved for deletion |
| Wave / owner | Wave 1 / S-05 |
| Decisions | IR-015, IR-048, IR-049, IR-113, IR-213–218, IR-603–606, IR-800–802, IR-922–924, IR-936, IR-937 |
| Dependencies | None |
| Coordination | S-06 connectors/MCP, S-07 BYOK, S-17 onboarding/permissions, S-19 PTT tools, S-22 model aliases, S-28/S-30 identity |
| Baseline | Re-fetch `origin/main` when implementation starts; current researched base is `97e4b8aef93912e47caf4ccb52fac53e12cbbd86` |
| Postcondition | Normal Chat, background work, and retained voice-triggered work can start only managed Pi. Pi exposes only scoped typed tools through its owned Unix-socket extension. Port 47778, alternate adapters, browser/general execution, provider overrides, compatibility surfaces, and dead transport artifacts are absent. |

Research established that `omi-tools-stdio` has no retained production consumer: Pi ignores its MCP configuration and instead uses `pi-mono-extension` plus `OMI_BRIDGE_PIPE`. Delete stdio rather than rewiring the working Pi path.

## Execution workflow and public seams

1. Start implementation with [engineering:implement](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/implement/SKILL.md), using this file as the spec. Run `make setup`, re-fetch `origin/main`, record the merge-base, stay on the current branch, and commit locally in vertical slices. Do not push or open a PR without a separate request.
2. Follow [engineering:tdd](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/tdd/SKILL.md): one behavioral RED, minimum GREEN, then the next cycle. Do not write all tests first or refactor during a failing cycle.
3. Apply [engineering:codebase-design](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/codebase-design/SKILL.md): retain one deep internal `RuntimeAdapter` seam for Pi and test fakes, but remove public multi-provider configuration, redundant MCP plumbing, and compatibility aliases.
4. Finish with [engineering:code-review](/Users/srujanu/.codex/plugins/cache/local-workspace/engineering/0.2.0/skills/code-review/SKILL.md), fixed at `origin/main`, with separate Standards and Spec Compliance reviews. Resolve findings and rerun affected and full gates.

The requirements-backed public seams are:

| Seam | Contract |
|---|---|
| Pi-only execution | Chat, background Pills, and realtime spawn tools always resolve to `pi-mono`/managed Sonnet. Spawn and protocol schemas cannot represent a provider override. Missing managed authentication fails explicitly without another adapter. |
| Scoped Pi tools | Pi loads only the owned extension and retained typed manifest. Built-in shell/file tools, ambient skills, context files, prompt templates, and ambient extensions are disabled. Ask Mode remains default-off and behaves exactly as it currently does; do not transplant or repair the unreachable stdio SQL check. |
| Pill and voice lifecycle | Preserve spawn, progress, artifacts, follow-up, stop, restart, reconciliation, journal, dismissal, expiry, and trim behavior. Use the deterministic local Pill title and authoritative router acknowledgement. Voice completion remains bounded and exactly-once for `floating_bar` and `service`, but not `workstream`. |
| External entrance removal | No listener, token, settings, routes, or wrappers remain for port 47778. The development-only automation bridge on 47777 and its behavioral parser coverage continue working. |
| Packaged runtime | The application bundles only Pi’s production adapter and owned extension. ACP, Hermes, OpenClaw, Playwright, `omi-tools-stdio`, `local-agent-api`, the ACP bridge, and their dependencies/generated projections are absent. |

## Action ledger and interface changes

| Action | Exact treatment |
|---|---|
| **KEEP AS IS** | Managed Pi, Node kernel and journal, `AgentRuntimeProcess`, `ChatToolExecutor`, `AgentToolBridgeServer`, explicit attachments/artifacts, read-only Accessibility, current Ask Mode semantics, full Agent Pill lifecycle, and both OpenAI/Gemini realtime providers. |
| **ADAPT** | Collapse `ProductionAdapterId` and runtime creation to Pi; remove provider/model/working-directory selection from public schemas; canonicalize persisted sessions; harden Pi launch flags; narrow `pi-mono-extension`; move Ask Mode into Advanced AI Setup; relocate shared loopback parsing under `Desktop/Sources/Automation`; remove `workstream` from completion delivery. |
| **DELETE** | ACP, Hermes, OpenClaw, the broken ACP bridge, provider discovery/OAuth/overrides, `configure_default_execution_profile`, directed-provider spawn fields, Playwright MCP and browser setup, stdio MCP, port 47778 API, provider/model/workspace/Dev Mode/Claude configuration and skills UI, Prompt Lab, Pi BYOK/Opus/skills/audit/YOLO logic, broad execution, and cosmetic Haiku title generation. |
| **SIMPLIFY / OPTIMIZE AFTER** | Once every cycle is green, remove redundant adapter registries, capability matrices, MCP hashes/types, wrappers, stale analytics, fixtures, and generated surfaces. Keep an internal runtime abstraction only where Pi plus a behavioral fake actually use it. |
| **ACCELERATE AFTER** | None. Record any package-size or test-time improvement from deletion, but do not add unrelated performance work. |
| **AUTOMATE LAST** | No standalone checker. Strengthen existing behavioral, package-manifest, signed-artifact, and preflight contracts only where this change already has an owning CI lane. |
| **OUT OF SCOPE / DEFERRED** | Broader Memory Export/connectors deletion, product-wide BYOK, onboarding/permission redesign, PTT data-tool redesign, backend released-client model aliases, final storage namespace/product identity, Windows, and historical changelogs. |

Public/internal interface decisions:

- `ProductionAdapterId` becomes Pi-only; provider-directed fields and default-profile configuration messages are removed rather than ignored.
- `mcpServers` and stdio-specific tool projections leave the Pi runtime boundary. The tool manifest advertises only the retained Pi extension surface.
- Pi launches with `--no-builtin-tools --no-skills --no-context-files --no-prompt-templates --no-extensions -e <owned-extension>`. These flags are supported by the pinned Pi CLI; `--no-extensions` still permits explicitly supplied `-e` extensions. See the official [Pi v0.81.1 usage documentation](https://raw.githubusercontent.com/earendil-works/pi/v0.81.1/packages/coding-agent/docs/usage.md).
- Add a one-time store migration before startup reconciliation. Any current non-Pi or non-Sonnet profile receives a new immutable generation using `pi-mono`, managed-cloud credentials, `omi-sonnet`, the private artifacts directory, and the same execution role. Its active bindings become stale; normal startup reconciliation orphans interrupted attempts. Journals, completed runs, and historical profiles remain intact but cannot select future execution.
- Delete default execution preferences after canonicalization. New and reopened surfaces derive their fixed profile internally.
- Internal `omi` wire identifiers required by the current managed gateway may remain until their owning identity slice; remove user-visible, extension-visible, and nonessential identity residue now.
- Do not delete the backend `omi-opus` compatibility alias unless the released-client contract independently proves it safe. S-05 removes all in-tree desktop/Pi selection of it.

## Ordered TDD cycles

### Cycle 0 — baseline and inventory

Run existing Pi chat, background/Pill, voice-delivery, tool-manifest, parser, automation-bridge, runtime-restart, and package tests. Record every alternate-provider, port 47778, stdio, Playwright, Prompt Lab, and Claude-compatibility hit as S-05, coordinated, historical, Windows, or retained internal wire compatibility.

Do not create a new passing characterization test. The first new test in each cycle must fail for the intended behavior.

### Cycle 1 — canonical Pi execution and upgrade migration

**RED:** Through Node runtime/protocol and Swift coordinator seams, prove:

- alternate/default provider input is unrepresentable or rejected;
- a database containing an ACP/Hermes/OpenClaw or Opus current profile upgrades to Pi/Sonnet/private-artifacts while preserving journal history;
- missing Pi authentication produces the managed-provider error and never starts a fallback adapter.

**GREEN:** Fix production registration to Pi, remove provider-directed spawn/configuration fields and settings authority, install the one-time profile migration, invalidate legacy bindings, and preserve normal startup reconciliation.

### Cycle 2 — isolate Pi and narrow its extension

**RED:** At the child-process and advertised-tool seams, assert the hardened launch flags, managed Sonnet, owned extension, exact retained typed-tool snapshot, and absence of built-in execution, skills, Opus, BYOK, audit, and YOLO behavior. Keep existing bridge failure/correlation/reasoning tests green.

**GREEN:** Add the Pi isolation flags and strip rejected extension behavior. Preserve managed authentication, correlation IDs, reasoning effort, Unix-socket tool calls, and scoped Swift execution. Remove stdio-only onboarding tool definitions without changing the real onboarding flow owned by S-17.

### Cycle 3 — one packaged runtime and one private bridge

**RED:** Extend existing adapter/tool/package contracts so the production runtime contains only Pi, its extension, and the socket relay. The test must fail while alternate adapters, MCP child builders, Playwright, stdio, ACP assets, or their dependencies remain.

**GREEN:** Delete alternate adapter implementations and discovery, `omi-tools-stdio`, MCP-server plumbing, Playwright lifecycle/configuration, `desktop/macos/acp-bridge/`, obsolete generated projections, exclusive fixtures, and dependencies. Regenerate both relevant npm locks through their package-manager workflow.

### Cycle 4 — remove the port 47778 API

**RED:** Use the existing packaged-app/smoke boundary to prove the production app does not start or contain the Local Agent API while the 47777 automation bridge still parses requests and serves its retained health/actions contract.

**GREEN:** Relocate `LoopbackHTTPParsing` before deleting `LocalAgentAPIServer`; then remove its startup call, settings, Keychain token, routes, API-only tool wrappers, generator output, scripts, tests, and only the Local-Agent coupling from Memory Export. Do not delete Memory Export itself.

### Cycle 5 — remove alternate user entrances and compatibility UI

**RED:** Through settings navigation/search models and Chat behavior, prove there is no AI Chat destination, provider/model/browser/workspace/Dev Mode/Claude skills/Prompt Lab surface, while Ask Mode appears in Advanced AI Setup, remains default-off, and retains current per-turn Ask/Act behavior.

**GREEN:** Delete those settings and compatibility flows, global/project Claude readers, workspace changes, browser setup sheets, Prompt Lab windows/direct Anthropic calls, obsolete defaults and analytics. Preserve generic browser target helpers still used outside Playwright and any live non-ChatLab synthesis caller.

### Cycle 6 — preserve Pills while narrowing title and voice completion

**RED:** Add behavioral tests proving:

- a cosmetic Haiku result cannot replace the deterministic local three-word uppercase title or authoritative acknowledgement;
- terminal `workstream` work does not inject voice context or advance a checkpoint;
- `floating_bar` and `service` successes still deliver at most five completions from the prior hour, checkpoint only after successful injection, retry failures, and work with both realtime providers.

**GREEN:** Delete Haiku title/ack calls and late mutation logic, remove provider presentation residue, and narrow the voice trigger set without changing the rest of the Pill lifecycle.

## Review, verification, and closure

After all GREEN cycles:

1. Perform the separate simplification pass; do not retain no-op adapters, deprecated fields, compatibility aliases, empty projections, or hypothetical provider frameworks.
2. Update `agent/src/ARCHITECTURE.md`, the desktop component guide, current developer documentation, and changelog fragment where the changed runtime/settings contract requires it.
3. Run:

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py

cd desktop/macos/agent
npm run build
npm test

cd ../pi-mono-extension
npm test

cd ..
xcrun swift test -c debug --package-path Desktop \
  --filter 'AgentRuntimeProcess|DesktopCoordinatorService|AgentPill|AgentCompletionVoiceDelivery|LoopbackHTTPContentLength'
./scripts/agent-logic-harness.sh
./scripts/agent-logic-harness.sh --cross-surface-smoke
xcrun swift build -c debug --package-path Desktop

cd ../../..
make preflight
scripts/pr-preflight --suggest
git diff --check
```

4. Run `OMI_APP_NAME=omi-s05-agent ./run.sh --full`, never touching production Omi bundles. Exercise normal Chat with a retained typed tool, a background Pill through progress/artifact/follow-up/stop or completion/dismissal, one completion-to-voice path, and one Ask turn.
5. Confirm `lsof -nP -iTCP:47778 -sTCP:LISTEN` is empty; confirm the named bundle’s 47777 automation health/actions path still works; confirm no ACP, Hermes, OpenClaw, Playwright, or stdio child process starts.
6. Run the continuity gauntlet against the named bundle because journal, bindings, Pills, and completion delivery are touched.
7. Search production source, settings, tests, scripts, package locks, generated contracts, and current docs for alternate providers, `chatBridgeMode`, `omi-tools-stdio`, `local-agent-api`, `47778`, Playwright, Prompt Lab, Claude compatibility, `OMI_YOLO_MODE`, Opus, Haiku title generation, and `workstream` delivery. Remaining matches must be historical requirements/changelogs, migration fixtures, Windows, a documented backend compatibility alias, or an exact adjacent-slice handoff.
8. Run `engineering:code-review` against `origin/main...HEAD`, fix valid findings, rerun affected checks plus the full harness and preflight, and inspect the final diff/status for unrelated user changes. No push or PR is part of this plan.
