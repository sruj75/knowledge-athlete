# S-22 TDD plan — narrow managed models to explicit retained transient workloads

## 1. Slice identity

| Field | Value |
|---|---|
| Wave | **3** |
| Slice | **S-22** |
| Type | Model-portfolio deletion and result-ownership adaptation |
| Named development bundle | `omi-wave3-s22` (`com.omi.omi-wave3-s22`) |
| Baseline | Wave 2 closeout `711269baf5e653bd62132688998732207f11dd3c` |
| Target branch | `origin/main` |
| Product authority | [`../../PRODUCT.md`](../../PRODUCT.md) |
| Requirements authority | [`../requirements-challenge.md`](../requirements-challenge.md) |
| Roadmap | [`../deletion-map.md`](../deletion-map.md), S-22 |
| Failure-class candidates | `FC-split-mutation-authority` for delayed-result ownership; `FC-public-web-routing-parity` lifecycle is handled exactly as described below |

## 2. Planning status and pinned baseline

**Status:** ready to start. Cycles 1–4 and 6–11 are immediately safe after their named predecessors; later cycles and final closure retain their explicit gates.

Planning was performed from a clean checkout whose `HEAD` is exactly the completed
Wave 2 closeout:

```text
git merge-base --is-ancestor 711269baf5e653bd62132688998732207f11dd3c HEAD
  -> exit 0
git rev-parse HEAD
  -> 711269baf5e653bd62132688998732207f11dd3c
git status --short --branch
  -> ## audit-wave-2-slices...origin/audit-wave-2-slices
git log --oneline 711269baf5e653bd62132688998732207f11dd3c..HEAD
  -> no commits
```

There are therefore no additional product changes beyond the required baseline.
The live ledger validator passed during planning:

```text
python3 bootstrap-scaffold/validate-requirements-ledger.py
  -> PASS (714 indexed rows, 714 detailed sections, all reviewed)
```

The existing generated tool-surface check and its runtime suites also passed while
the current S-19/S-22 shared surface was being inventoried: generated outputs matched,
47 Node test files / 452 tests passed, and the packaged Pi extension passed 9/9.
That is planning evidence about the baseline, not implementation acceptance.

Before implementation, rerun the three baseline commands and the ledger validator.
Because S-19 and possibly other Wave 3 work will then be integrated, rebase onto that
result and refresh every inventory in Sections 6 and 7. Do not implement this plan
against the pre-S-19 tree merely because this planning baseline is valid.

## 3. Outcome

When S-22 closes:

1. Every retained managed-model workload has one explicit caller, provider/model
   route, bounded input contract, transient response contract, result owner, usage
   owner, and failure behavior.
2. Local Mac stores remain authoritative. A successful provider response has no
   durable product effect until the owning local transaction validates the original
   `RuntimeOwnerAuthorizationSnapshot`, request/generation identity, input revision,
   candidate references, and persistence result.
3. Normal Chat remains the local Node/Pi model/tool/model loop using managed Anthropic
   Sonnet through authenticated `/v2/chat/completions`; it does not regain a cloud
   journal, provider switch, customer key, Opus path, or public-web tool.
4. Realtime PTT still supports Auto, Gemini Live, OpenAI Realtime, daily Artificial
   Analysis selection, explicit switching, and eligible cross-provider failover.
   S-22 consumes S-19's final tool manifest and does not redesign the PTT lifecycle.
5. Gemini generation and embeddings retain the authenticated non-streaming proxy,
   Vertex-when-configured plus platform AI Studio fallback, exact shared request
   ceilings, Flash/Flash-Lite/embedding models, and the preview-to-Flash rewrite.
   Product-dead Pro admission and the callerless streaming proxy are absent.
6. Retained OpenAI conversation, Memory, greeting, and translation workloads call
   their explicit providers directly from the canonical Python backend. Their prompts,
   schemas, thresholds, language/time handling, retry/fail-safe behavior, and usage
   accounting do not change.
7. The global Premium/Max/BYOK profiles, independent LLM gateway mediation, unread
   attempt documents, rejected provider integrations, and callerless model endpoints
   are gone from S-22-owned application surfaces. Deployment/live-resource teardown
   remains separately owned and authorized.
8. LangSmith tracing and Prompt Hub fallback behavior remain available exactly to the
   extent authorized by IR-827/IR-828/IR-832; no in-app ratings product is restored.

This slice changes routing, authority, and deletion topology. It does **not** redesign
prompts, model semantics, classifier thresholds, proactive cadence, result admission,
Chat tools, PTT transport, quota bands, warning copy, notifications, or local schemas.

## 4. Authorizing requirements

The live detailed decisions, not feature names in old code, authorize this plan.

| Decision | Binding S-22 interpretation | Cycles / proof |
|---|---|---|
| IR-053 | Keep transient `gemini-embedding-001`; all vectors, indexes, similarity, and search authority stay on the Mac. | C1–C3, C16 |
| IR-113 | Keep local Node/Pi Chat plus managed Claude `/v2/chat/completions` exactly for v1. | C1, C4, C16 |
| IR-600 | Keep Auto/Gemini/OpenAI choice, daily Artificial Analysis scoring/cache, manual choice, and failover. | C5, C16 |
| IR-601 | Delete realtime `ask_higher_model`; S-19 owns the tool/manifests/Mac dispatch and S-22 consumes its absence. | C5 gate, C16 |
| IR-602 | Delete the false voice live-web claim with IR-601; never replace it. | C5 gate, C16 |
| IR-603 | Keep deterministic/prefetched Agent Pill metadata; cosmetic Haiku title/ack compute remains absent. | C11, C16 |
| IR-604 | Chat Prompt Lab and its direct Anthropic BYOK remain absent from the shipped app. | C11, C16 |
| IR-605 | Pin normal Chat and background agent launches to Sonnet; remove dormant Opus selection/aliases after released-contract proof. | C4, C16 |
| IR-606 | Remove orphaned Haiku/ChatLab identities only after caller tracing; do not delete unrelated provider workloads by model-name resemblance. | C4, C11 |
| IR-607 | Delete `llm_gateway_attempts` and its non-authoritative delivery path; keep actual quota/usage and low-cardinality metrics. | C14 |
| IR-608 | Retained Python workloads call providers in-process; remove the extra gateway application boundary and hand deployed-service teardown to S-25. | C4, C7–C10, C13–C14 |
| IR-609 | Replace global `premium`/`max`/`byok` maps and the default fallback with one explicit route per surviving workload. | C1, C13 |
| IR-710 | Keep OpenAI GPT-4.1-mini `memory_l2`; Mac selects, revision-validates, retries, receipts, and commits. | C9 |
| IR-711 | Delete dead Mac Premium/Max selection; pin current reachable Gemini defaults. | C2–C3 |
| IR-712 | Keep Vertex when configured and credentialed plus platform AI Studio for local development/credential-acquisition fallback. | C2 |
| IR-713 | Keep Firebase/trial gate, shared 30/60s and 1,500/day Redis limits, fail-closed limiter, 5 MiB body, one candidate, 8,192 output cap, thinking bound, and sanitization. | C2–C3 |
| IR-714 | Delete callerless ElevenLabs `/v2/tts/synthesize`; preserve live OpenAI `/v1/tts/synthesize` and shared rate limiter. | C6 |
| IR-715 | Delete Perplexity/Sonar and exclusive provider/config/test support. | C5 |
| IR-716 | Delete general public-web behavior from typed Chat and voice without replacement; private local retrieval remains. | C5 |
| IR-717 | Delete `gemini-2.5-pro` admission and exclusive downgrade/tier policy. | C2 |
| IR-718 | Delete `/v1/proxy/gemini-stream/{path}` and `streamGenerateContent`; retain normal generation and embeddings. | C2 |
| IR-719 | Preserve the `gemini-3-flash-preview` to `gemini-2.5-flash` compatibility rewrite and its test. | C2 |
| IR-720 | Record Wrapped's sole OpenRouter binding as an exact S-23 handoff. S-23 deletes Wrapped and then its now-exclusive OpenRouter integration; S-22 is not reopened. | C12 handoff; S-23 C10 |
| IR-721 | Keep Gemini 2.5 Flash-Lite automatic title compute; local catalog alone commits the accepted title. | C7 |
| IR-722 | Keep OpenAI GPT-5.4-mini greeting compute; local journal alone commits the accepted turn. | C7 |
| IR-723 | Cloud Mentor/App proactive model workload remains absent; local Mac assistants and Gemini compute remain. | C3, C11 |
| IR-724 | GPT-personalized purchase/limit push copy remains absent; authoritative state and fixed local presentation remain. | C11 |
| IR-725 | OpenGlass/smart-glasses image-description compute remains absent; Mac screenshots/OCR/vision are protected siblings. | C11 |
| IR-726 | Retained managed-STT translation uses only Gemini 2.5 Flash-Lite; NLLB remains absent and original transcript survives failure. | C10 |
| IR-727 | Keep separate OpenAI GPT-5.4-mini structure and action-item jobs; Mac validates/commits local conversation/task results. | C8 |
| IR-728 | Keep OpenAI GPT-4.1-mini `memory_l1`, grounded evidence rules, 32-item bound, and local Short-term admission. | C9 |
| IR-729 | Delete legacy `memories`, `learnings`, and `memory_category`; keep only L1/L2/conflict Memory workloads. | C9, C11 |
| IR-730 | Keep OpenAI GPT-4.1-mini `memory_conflict`, conservation/reference validation, and atomic local lifecycle commit. | C9 |
| IR-731 | Delete old `chat_extraction`/`chat_graph` model routes and hosted RAG/persona helpers; preserve local Pi and private local retrieval. | C11, S-23 handoff |
| IR-732 | Keep OpenAI GPT-4.1-nano `conv_discard`, empty/over-100-word fast paths, short-duration bar, and keep-on-failure local behavior. | C8 |
| IR-827 | Keep LangSmith tracing configuration, callbacks/run metadata, startup status, and this product's project. | C15 |
| IR-828 | Keep Prompt Hub fetch/version/TTL/render/fallback behavior and later repoint product identity without deleting the repository fallback. | C15 |

IR-832 protects operator-side LangSmith annotation/evaluation while keeping the
in-app rating product deleted. It resolves IR-827's old “feedback” wording: S-22
must not restore thumbs-up/down, cloud Chat copies, or a user-feedback endpoint.

## 5. Dependencies and entry gates

### Integrated predecessors

| Owner | Shape consumed by S-22 | Entry check / stop condition |
|---|---|---|
| S-05 | One managed Pi adapter, local Node journal/kernel, product-owned Sonnet transport, private `OMI_BRIDGE_PIPE`, no customer-provider selection. | Re-run Pi package/runtime tests. Stop if another production adapter or customer key can select the normal-Chat provider. |
| S-07 | Product-owned credentials only; no BYOK forwarding or entitlement bypass. | Search Mac, Node, backend headers/config. Do not recreate a BYOK route while removing profiles. |
| S-10 | Local conversation and segment authority plus discard/structure/action candidate seams. | Run local enrichment owner/generation tests. Stop if Python again owns conversation IDs, state, or commits. |
| S-11 | Owner-scoped Node journal/catalog; greeting/title candidates commit locally. | Protect first-exchange/manual-rename and greeting journal admission. |
| S-12 | Local Memory authority and authenticated L1/L2/conflict candidate APIs. | Protect request/revision/generation/evidence validation and no-write backend contract. |
| S-13 | Local Tasks/Goals and `ActionItemStorage`, including conversation action admission. | Do not restore hosted task IDs/writes or change extraction/admission semantics. |
| S-14 | Local Focus/Insights/profile/settings and Mac proactive assistants; cloud proactive/notification model routes are absent. | Preserve assistant prompts/cadence/thresholds/local persistence and negative retirement tests. |
| S-16 | `/v4/listen` transient Modulate, Gemini-only translation, local segment commit; NLLB is absent. | Do not restore provider lists/NLLB or change listen protocol. |
| Wave 2 closeout | One authorization snapshot crosses user-derived compute and every later side effect. | Every modified delayed path tests A→B and same-UID ABA, failure, and persistence-before-publication. |
| S-18 checkpoint | `BILLING_MODE=disabled`; retained entitlement/quota seams exist but no provider transaction is authorized. | Do not activate Dodo/Stripe, grant entitlement, or add a paywall. |

### Mandatory Wave 3 rebase gate

S-19 is not integrated in this planning tree: `ask_higher_model`, its generated
tool surface, `APIClient+HigherModel.swift`, and Mac dispatch are still present.
Before C5 or final acceptance:

1. integrate S-19;
2. rebase S-22 onto it without switching this worktree's branch;
3. rerun caller/model/tool inventories and `desktop/macos/scripts/test-tool-surfaces.sh`;
4. consume S-19's final generated manifests and local product-data tools; and
5. verify `ask_higher_model` is absent rather than deleting it a second time.

S-19 owns the realtime tool declaration, generated OpenAI/Gemini schemas,
authorization/dispatch switch, `escalateToHigherModel`, `APIClient+HigherModel`,
and PTT lifecycle coverage. S-22 owns normal-Chat public-web routing, Perplexity,
model profiles, provider aliases, and provider/gateway routing. Shared fixture or
prompt edits happen after S-19, never by maintaining two versions.

### S-20 non-absorption gate

The current fair-use classifier couples managed GPT-5.1 compute to hosted Firestore
evidence. S-20 moves only the durable evidence authority to local GRDB and retains the
existing GPT-5.1 classifier as bounded transient backend compute. S-20 owns the exact
model, prompt, recipes, parser/output, cadence, thresholds, strikes, support reset,
restricted allowance, and content-free durable enforcement facts. S-22 must preserve
that explicit OpenAI GPT-5.1 workload while removing generic profile/gateway routing;
it must not select another model, delete the feature key before replacing it with the
explicit route, or alter fair-use behavior.

### S-23/S-25 owner boundary

The current tree still has live rejected-product callers:

- `backend/routers/users.py` Joan follow-up -> `get_llm('followup')`;
- `backend/routers/wrapped.py` -> `utils/wrapped/generate_2025.py` ->
  `get_llm('wrapped_analysis')`/OpenRouter;
- hosted conversation finalization -> `assign_conversation_to_folder` ->
  `get_llm('conv_folder')`;
- `backend/utils/onboarding.py` and `backend/utils/llm/trends.py` remain source
  residue, although their current production callers are absent or separate.

S-23 owns Joan, Wrapped, Trends, hosted conversation/folder, their product routes/data,
and the provider integration that becomes exclusive when Wrapped is removed. S-25 owns
deployed LLM-gateway service/image/workflow/secret/traffic closure. The deletion map and
cross-slice owner correction record the mechanical order:

1. S-22 closes every retained/S-22-owned workload and records exactly three rejected
   live S-23 handoffs: `followup -> Joan`, `conv_folder -> automatic folder assignment`,
   and `wrapped_analysis/OpenRouter -> Wrapped`.
2. S-23 deletes each binding together with its complete product: automatic folder
   assignment in Cycle 6, Wrapped/OpenRouter in Cycle 10, and Joan/followup in Cycle 12.
   It then runs S-22's retained-provider regression suite.
3. S-25 deletes the already-callerless deployed gateway topology.

S-22 does not wait for or reopen after S-23. Any second OpenRouter caller, generic default
route, or rejected-product model binding outside those exact three handoffs is a defect
that blocks S-22 closure.
No no-op route, fake success, deprecated alias, or ignored model field may bridge the
handoff.

### Released-contract gate

Before removing accepted `/v2/chat/completions` aliases, `/v2/tts/synthesize`, Gemini
streaming/Pro shapes, or generated app-client operations, inspect the restored
app-client OpenAPI snapshot, release history, and current non-Windows consumers. This
unreleased fork needs no invented old-customer compatibility, but an actually released
contract requires an explicit version/sunset decision. No fake compatibility shell.

## 6. Current production codeflow

### 6.1 Normal Chat and background agents

```text
Home / floating Chat
  -> ChatProvider + owner-scoped local Node catalog/journal
  -> agent/src/index.ts creates pi-mono session with modelProfile=omi-sonnet
  -> pi-mono-extension registers managed Omi Sonnet provider
  -> authenticated POST /v2/chat/completions
  -> desktop_chat._request translates OpenAI-compatible messages/tools
  -> utils.llm.clients.anthropic_client
       direct Anthropic OR gateway-only client when feature mode=gateway
  -> Anthropic Messages stream/create
  -> count-only usage/quota
  -> Node journal accepts turn
  -> ChatProvider projects accepted local journal row
```

The Mac/Node side is already pinned to `omi-sonnet`. The backend still accepts Opus,
dated Sonnet/Opus, and Haiku aliases in `_MODEL_MAP`. `clients._AnthropicClientProxy`
can replace the direct Anthropic client with `gateway_anthropic` and the
`omi:auto:chat-agent` lane. Those are the remaining IR-605/606/608 adaptation points.

The Pi adapter also calls `routePromptForPublicWeb`, injects public-web instructions,
emits synthetic `web_search` progress, strips availability denials, and advertises
public web in `ChatPrompts.desktopChat`. These are IR-716 deletion targets. Private
local SQL/typed-tool retrieval is a protected sibling.

### 6.2 Realtime PTT

```text
Advanced Settings Voice Model
  -> RealtimeOmniSettings: Auto | Gemini | OpenAI
  -> AutoModelSelector -> GET /v1/auto/model-pick
       -> Artificial Analysis 65/35 quality/speed score + 24h server cache
       -> once-per-local-day Mac cache; Gemini only when no last-good pick
  -> RealtimeHubSettings effective provider
  -> POST /v2/realtime/session (OpenAI or Gemini token mint)
  -> provider-native audio/function-call session
  -> eligible failure tries alternate provider
  -> local streaming journal / local tool execution
  -> POST /v2/realtime/usage count/cost facts
```

`RealtimeHubProvider` currently names `gpt-realtime-2` and
`gemini-3.1-flash-live-preview`. `desktop_realtime.py` mints product-owned tokens and
currently writes best-effort `realtime_sessions` audit documents; S-19 owns that
session-audit deletion boundary. S-22 protects both providers, Auto/manual switching,
fallback, native speech, interruption, tool behavior, and usage accounting.

The baseline still advertises `ask_higher_model`, dispatches it through
`RealtimeHubController+SessionDelegate`, constructs an `omi_web_search` body, and calls
`APIClient+HigherModel`. S-19 removes that complete PTT branch before S-22 C5.

### 6.3 Authenticated Gemini proxy and Mac-local result owners

`backend/routers/desktop_proxy.py` currently permits four actions and four models:

```text
actions: generateContent, streamGenerateContent, embedContent, batchEmbedContents
models:  gemini-2.5-flash, gemini-2.5-flash-lite,
         gemini-2.5-pro, gemini-embedding-001
```

It rewrites the retained `gemini-3-flash-preview` name to Flash, authenticates and
entitlement-gates the account, applies shared Redis 30/60s and 1,500/day limits,
fails closed when the limiter fails, validates action/model/body/candidate/output
shape, strips unsafe controls, and selects Vertex when configured or platform AI
Studio otherwise. The proxy adapts Vertex embedding shapes. It also still exposes a
callerless streaming route and Pro soft-downgrade policy.

Mac callers use `GeminiClient` or `EmbeddingService`:

- Focus, screenshot Memory, Task extraction, Insight, AI Profile, Home suggestions,
  Live Notes, PTT vocabulary, and Live Suggestions send bounded local inputs;
- `EmbeddingService` supplies task, Memory, conversation similarity and
  `OCREmbeddingService`/Rewind vectors;
- results commit only through their local stores or remain transient UI/context; and
- Wave 2 owner snapshots fence network suspension, index load/update, persistence,
  telemetry, notification, and publication.

`ModelQoS.swift` still persists a private Premium/Max tier and maps Max to Pro.
Only tests write the tier. The retained reachable values are Flash for proactive,
Task, Insight, Profile, Home, Live Notes, and PTT vocabulary; Flash-Lite (with current
Flash fallback) for Live Suggestions; and the embedding model for vectors.

### 6.4 Chat greeting and title candidates

```text
ChatProvider local new-session flow
  -> bounded local profile/memory OR first accepted exchange
  -> APIClient+ChatCompute
  -> /v2/chat/initial-message -> OpenAI GPT-5.4-mini
  -> /v2/chat/generate-title -> Gemini 2.5 Flash-Lite
  -> candidate only
  -> owner/generation check
  -> local Node journal/catalog commit
```

The backend routes in `chat_sessions.py` are already stateless. Their `get_llm`
resolution still crosses the global profile/gateway client layer. Manual rename and
non-fatal `New Chat`/welcome fallbacks are local and protected.

### 6.5 Conversation candidates

```text
final owner-local transcript
  -> ConversationDiscardAdmission / ConversationStructureEnrichment /
     ConversationActionItemEnrichment
  -> APIClient+ConversationCompute with one owner authorization snapshot
  -> /v1/conversation-compute/discard|structure|action-items
  -> conversation_processing.get_llm(conv_discard|conv_structure|conv_action_items)
  -> candidate response echoes generation_id
  -> Mac validates generation/references/current local state
  -> local conversation and ActionItemStorage transaction
  -> UI/events only after persistence
```

Models still resolve from global profiles: GPT-4.1-nano discard and GPT-5.4-mini
structure/action items in the reachable default. The backend candidate routes own no
conversation/task persistence, but `get_llm` may still route them through the LLM
gateway. The old hosted conversation finalizer/folder route is separate S-23 residue.

### 6.6 Memory candidates

```text
LocalMemoryLifecycleRunner
  -> bounded local explicit assertion, transcript segments, or due Short-term batch
  -> APIClient+MemoryCompute with request/revision/generation snapshot
  -> /v1/memory/compute/normalize|extract|consolidate
  -> utils.llm.memory_compute pinned direct OpenAI GPT-4.1-mini
  -> strict proposal/reference validation
  -> Mac revalidates local revision/generation/evidence
  -> atomic MemoryStorage lifecycle/audit/vector commit
```

This path already bypasses `get_llm` and stores no backend Memory. S-22 protects it,
then removes obsolete model-profile vocabulary and legacy route residue without
moving the prompt or API key to the Mac.

### 6.7 Managed-STT translation

`/v4/listen` supplies bounded transcript batches to `translation_core`, whose current
Gemini 2.5 Flash-Lite route still calls `get_llm('translation')`. S-16 has already
removed NLLB source/deployment residue and makes the translated candidate commit only
to the matching local segment. S-22 replaces profile/gateway mediation with the one
explicit direct Gemini route; it does not alter target-language rules, planner,
caches, splitting, cardinality, metrics, UI, or original-transcript fallback.

### 6.8 TTS

`/v1/tts/synthesize` is the live authenticated OpenAI `gpt-4o-mini-tts` route used by
the Mac's Onyx/Shimmer/Coral/Nova controls, cloud voice playback, and system-speech
fallback. `/v2/tts/synthesize` is an ElevenLabs route with arbitrary voice/model/output
settings and no retained Mac caller. Both touch shared TTS rate-limit primitives;
only the `/v2` slice and its exclusive config/model/OpenAPI support are deleted.

### 6.9 Global profiles, providers, gateway, and accounting

`model_config.py` contains duplicated `premium` and `max` maps, pinned features,
provider-only sets, OpenRouter temperature, a default OpenAI fallback for unknown
features, and a startup `MODEL_QOS` switch. `clients.get_llm` may route every feature
to `omi:auto:<feature>` when `OMI_LLM_GATEWAY_FEATURE_MODE=gateway`, otherwise it
constructs direct OpenAI/Gemini/OpenRouter clients. Gateway shadow/circuit/serving and
Anthropic wrappers add a second control plane.

`backend/llm_gateway/**`, `backend/charts/llm-gateway/**`, gateway scripts, runtime
image/workflow entries, backend-listen/runtime env, service token, Helm/GKE ingress,
and multiple workflows operate that extra service. Its non-fatal accounting sink
writes immutable `llm_gateway_attempts` documents that no product reader consumes.

S-22 migrates application callers, removes route/profile/gateway application code and
the unread ledger. S-25 owns independently deployed service/workflow/image/secret/
traffic and live-resource closure after S-22 proves zero callers.

### 6.10 LangSmith and Prompt Hub

`main.py` calls `log_langsmith_status`; LangChain can trace globally from environment.
`utils/observability/langsmith.py` exposes scoped tracer/run helpers, while
`langsmith_prompts.py` implements prompt name, five-minute TTL, version metadata,
safe rendering, remote fetch, and a large repository fallback. Current-tree tracing
and prompt tests exist.

Repository-wide non-test search finds no current caller of
`get_agentic_system_prompt_template`, `get_prompt_metadata`,
`get_chat_tracer_callbacks`, or `bind_current_langsmith_run` outside their exports;
only startup status and LangChain's environment-driven tracing are directly reachable.
IR-827/828 nevertheless say to retain these lifecycles. C15 preserves them and blocks
any invented new production wiring until the requirement owner names the surviving
consumer or confirms helper-level availability is the intended v1 behavior.

## 7. Complete caller and dependency inventory

### Retained workload matrix

| Workload / model | Current caller and public seam | Compute owner | Durable/result owner | S-22 action |
|---|---|---|---|---|
| Normal Chat — Anthropic `claude-sonnet-4-6` / public `omi-sonnet` | Node Pi adapter -> `POST /v2/chat/completions` | Canonical Python backend, currently direct-or-gateway | Owner-scoped Node journal/catalog | ADAPT to direct only; pin aliases; preserve stream/tools/quota |
| Realtime OpenAI `gpt-realtime-2` | PTT -> `/v2/realtime/session` -> native provider | Backend token mint; provider-native session | Local streaming journal; usage facts only in backend | KEEP; S-19 owns tools/session-audit changes |
| Realtime Gemini `gemini-3.1-flash-live-preview` | Same PTT seam | Same | Same | KEEP |
| Auto provider picker | Settings/launch -> `GET /v1/auto/model-pick` | Backend AA fetch/cache | Mac last-good daily preference; no product data | KEEP exactly |
| Gemini Flash | Focus, screenshot Memory, Task, Insight, Profile, Home, Live Notes, PTT vocabulary -> non-stream proxy | Authenticated Gemini proxy | FocusStorage, MemoryStorage, ActionItemStorage, local profile/history, or transient context | ADAPT only fixed explicit model; preserve local commits |
| Gemini Flash-Lite | Live Suggestions plus title/translation workloads | Proxy for Mac generation; direct Python for title/translation after adaptation | Local journal/catalog/segment/UI | KEEP explicit routes and current fallback semantics |
| Gemini embedding-001 | `EmbeddingService`/`OCREmbeddingService` for tasks, Memory lifecycle/recall, conversation similarity, Rewind search/indexing | Authenticated Gemini proxy | Local GRDB/SQLite vectors and in-memory indexes | KEEP transient compute; never add cloud vectors |
| OpenAI GPT-5.4-mini greeting | `/v2/chat/initial-message` | Canonical backend | Local Node journal turn | ADAPT to explicit direct route |
| Gemini 2.5 Flash-Lite title | `/v2/chat/generate-title` | Canonical backend | Local session catalog | ADAPT to explicit direct route |
| OpenAI GPT-4.1-nano discard | `/v1/conversation-compute/discard` | Canonical backend | Local keep/discard/finalization transaction | ADAPT to explicit direct route |
| OpenAI GPT-5.4-mini structure | `/v1/conversation-compute/structure` | Canonical backend | Local conversation title/overview/emoji/commitments | ADAPT to explicit direct route |
| OpenAI GPT-5.4-mini action items | `/v1/conversation-compute/action-items` | Canonical backend | `ActionItemStorage` and linked local transaction | ADAPT to explicit direct route |
| OpenAI GPT-4.1-mini Memory L1 | `/v1/memory/compute/extract` | Canonical backend direct client | Local Short-term Memory/audit | KEEP; remove surrounding profile residue |
| OpenAI GPT-4.1-mini Memory L2 | `/v1/memory/compute/normalize` | Same | Local explicit assertion revision/receipt | KEEP |
| OpenAI GPT-4.1-mini Memory conflict | `/v1/memory/compute/consolidate` | Same | Atomic local lifecycle/audit | KEEP |
| Gemini 2.5 Flash-Lite translation | `/v4/listen` translation coordinator | Canonical backend | Matching local transcript segment | ADAPT to explicit direct route; NLLB stays absent |
| OpenAI `gpt-4o-mini-tts` | `POST /v1/tts/synthesize` | Canonical backend | Transient audio playback; no product record | KEEP exactly |
| LangSmith tracing | LangChain env + startup/scoped helpers | Canonical backend / LangSmith | Operator trace project only | KEEP, privacy disclosure handoff |
| LangSmith Prompt Hub | helper fetch/cache/fallback; current production consumer unresolved | Canonical backend / LangSmith | In-process TTL cache; repository fallback | KEEP; C15 closure gate |
| OpenAI GPT-5.1 fair-use classifier | S-20 bounded classify route with exact retained prompt/recipes/parser | Canonical backend direct OpenAI route | Local GRDB evidence remains canonical; request content is transient; durable enforcement facts are content-free | KEEP exact model/behavior; S-20 owns semantics, S-22 removes only generic routing |

### Rejected or successor-owned model families

| Family | Verified current state | Owner/action |
|---|---|---|
| PTT `ask_higher_model` / voice live web | Present in source/generated surfaces on baseline | S-19 deletes; S-22 verifies and deletes normal-Chat web siblings only |
| Agent Pill Haiku title/ack | Production caller already absent | Keep deterministic metadata; remove only remaining alias/config residue after audit |
| Chat Prompt Lab/BYOK | No `ChatLab`/Prompt Lab production files found | Preserve absence; do not recreate internal harness in customer app |
| Opus/Haiku/dormant model aliases | Mac/Node live calls are Sonnet; backend still accepts aliases; one test fixture carries historical `omi-opus` | S-22 after released-contract check |
| Perplexity/Sonar | `perplexity_tools.py`, model profiles, gateway/config/tests/env remain | S-22 C5 |
| General public web | Pi route classifier/prompt/progress fixture and Chat prompt remain | S-22 C5 after S-19 rebase |
| Gemini Pro | Proxy allowlists, soft downgrade, Mac hidden Max tier remain | S-22 C2 |
| Gemini streaming proxy | Route/action/helpers/tests remain; no retained Mac caller | S-22 C2 |
| Preview-name rewrite | Live defensive rewrite and test | KEEP, not residue |
| ElevenLabs `/v2` TTS | Route/model/config/tests/OpenAPI; no Mac caller | S-22 C6 |
| NLLB | No current repository source/config hits | Preserve negative closure; S-16 already removed |
| Cloud proactive/notification models | Negative tests prove workload/config absence | Preserve absence; S-23 owns remaining FCM/product cleanup |
| OpenGlass/smart-glasses model routes | Negative tests prove model/feature helper absence; generic historical enum/backfill words remain | Preserve absence; S-23 owns product records/routes |
| Legacy Memory routes | Canonical compute only; legacy model entries/functions absent | Preserve absence and negative tests |
| `chat_extraction`/`chat_graph` | No current model route/caller found | Preserve absence; S-23 owns hosted Chat/persona product residue |
| Wrapped/OpenRouter | Live Wrapped generator uses `wrapped_analysis`; OpenRouter config/provider support remains | Preserve as the one exact S-23 successor handoff; S-23 C10 deletes both and reruns retained-provider tests. Not an S-22 reopen gate. |
| Joan follow-up | Live route in `users.py` uses `followup` | Preserve as the exact Joan S-23 handoff; S-23 deletes route/helper/model binding vertically. |
| Hosted folder assignment | Hosted processing imports `conv_folder` | Preserve as the exact automatic-folder-assignment S-23 handoff; S-23 deletes prompt/model/state with the product. |
| Trends/onboarding helpers | Model helpers remain; live route/caller is absent or non-model database presentation | Delete only after final reference trace and owner check |
| Independent LLM gateway | Application clients/service/source/config/accounting/deploy topology remain | S-22 caller/application collapse; S-25 deployed topology/live decommission |

### Shared contracts, configuration, tests, and documentation

| Surface | Current files | Required treatment |
|---|---|---|
| Router registration | `backend/main.py` | Remove only S-22-owned routes; S-23 routes remain behind owner gate |
| Route policy/OpenAPI | route-policy manifest/baseline, `docs/api-reference/app-client-openapi.json`, generated `OmiApi.generated.swift` | Regenerate/check from live app-client surface; never hand-edit generated Swift |
| Model inventory | `backend/docs/llm/model_endpoint_inventory.yaml` | Replace gateway-centric inventory with final explicit caller/owner truth |
| Runtime env | `backend/deploy/runtime_env.yaml`, env templates, backend-listen and backend-secrets charts | Remove application-consumed obsolete variables in S-22; S-25 owns final deployed-service/secret deletion |
| Gateway app | `backend/llm_gateway/**`, `backend/database/llm_gateway_accounting.py`, `backend/utils/llm/gateway_*` | Delete after all retained callers are direct; preserve shared provider helpers only when independently used |
| Gateway deployment | charts, runtime image, deploy/smoke/probe scripts, `gcp_llm_gateway.yml`, mixed deploy workflows | Handoff to S-25 after zero-caller proof; no live mutation here |
| Tool generation | `agent/src/runtime/omi-tool-manifest.ts`, generator, generated Swift, fixture, `test-tool-surfaces.sh` | S-19 first; S-22 consumes and never hand-edits generated outputs |
| Public-web failure class | fixture/docs/tests plus `.github/failure-classes/FC-public-web-routing-parity.json` | Delete behavior fixture/consumers in implementation PR; only after merge, separate registry PR marks dormant with `dormant_since` |
| Provider credentials | OpenAI, Anthropic, Gemini, Artificial Analysis, LangSmith retained; Perplexity/ElevenLabs/gateway token candidates; OpenRouter is the exact Wrapped-only S-23 handoff | Remove S-22-exclusive bindings; preserve only the enumerated OpenRouter handoff until S-23 C10. Live Secret Manager deletion needs later inventory/authorization |
| Account deletion/export | provider routes should own no product record; gateway attempt collection may be enumerated only if cleanup exists | Verify deletion/export tests; S-23/S-25 own product/deployed resource cleanup |
| Docs | component AGENTS, model architecture/inventory, runbooks, privacy/provider disclosures | Update behavior/config truth with implementation; privacy/product identity final wording hands to S-30 |

## 8. Behavior classification

| Category | Exact behavior and source boundary |
|---|---|
| **KEEP AS IS** | Normal Chat's local Pi loop/tools/journal, Sonnet prompt/stream/tool semantics, quota and count usage; both realtime providers, Auto/manual choice, AA scoring/cache, failover, speech/barge-in/interruption/journal; Gemini Flash/Flash-Lite/embedding generation through authenticated proxy, Vertex plus platform Studio fallback, exact limits/bounds/preview rewrite; OpenAI Memory/conversation/greeting prompts and validation; Gemini translation semantics; OpenAI `/v1` TTS catalog/fallback; local proactive prompts/cadence/thresholds; LangSmith and Prompt Hub lifecycle; all owner/ABA fences and persistence-before-publication behavior. |
| **ADAPT** | Make each retained Python call a direct explicit provider/model workload; pin reachable Mac Gemini values and remove the hidden tier; narrow Gemini proxy admission to non-stream Flash/Flash-Lite/embedding; keep bounded inputs/transient results and local result commits; replace gateway/profile routing with one explicit registry; update model/provider observability and docs without raw content. |
| **DELETE** | S-22-owned public web/Perplexity, Pro/streaming proxy, `/v2` ElevenLabs, dormant aliases and Mac tier, unread attempt ledger, global profiles/default route, gateway application mediation/source after callers migrate, obsolete model config and already-dead Pill/ChatLab/cloud-model residue. S-19 deletes realtime higher-model tool; S-23 deletes rejected product routes/data; S-25 deletes deployed gateway topology/live resources. |
| **SIMPLIFY AFTER** | After behavior GREEN, collapse provider factories to the smallest shared in-process client layer, remove one-item provider lists and compatibility/default branches, keep one typed workload registry and one error/usage callback path, update model inventory, and remove dead tests/docs/config. No broad refactor of Chat, proactive assistants, local stores, listen, or billing. |
| **ACCELERATE AFTER** | Measure focused explicit-workload/provider contract tests, generated-contract checks, and named-bundle managed-compute time after GREEN. Improve only a measured repeated bottleneck; otherwise `none`. |
| **AUTOMATE LAST** | Once the caller/result-owner inventory is stable, register only a deterministic recurring inventory or residue check in existing local and CI lanes and cite the real failure it prevents; otherwise `none`. |
| **OUT OF SCOPE / DEFERRED** | S-19 local PTT tools/lifecycle and session-audit removal; S-20 fair-use evidence transport/classifier semantics/enforcement; S-23 hosted products/routes/data; S-24 Typesense/Pinecone/OpenAI Files/GCS product data; S-25 jobs/services/deploy/live gateway decommission; S-30 product/privacy/rebrand truth; S-18 Dodo activation; future choice of one realtime provider; model upgrades/prompt redesign; Windows; live provider/cloud mutation. |

Five-step delivery remains explicit: revalidate decisions; delete only rejected paths;
simplify after parity; measure focused edit/test/named-bundle time; automate only a
stable repeated inventory/check by registering it in an existing local and CI lane.

## 9. Retained behavioral invariants

1. One authorization snapshot is captured before any user-derived async compute and
   survives credential mint/refresh, provider call, validation, persistence, vector
   update, telemetry terminal, notification, and publication.
2. Revalidate after every suspension and immediately before every side effect. A UID
   string, fresh credential, or matching request ID alone cannot authorize a result.
3. A→B and same-UID A→nil→A reject stale results and clear model/index/cache work owned
   by the old generation.
4. Provider success never implies durable product success. Persistence completes first;
   failure produces no phantom row, title, task, vector, event, notification, or trace
   association claiming product admission.
5. Bounded local inputs are the only product context sent. Backend routes store no raw
   prompts, screenshots, transcript, Memory, task, greeting, title, embedding text, or
   provider output as product data.
6. Raw sensitive data never enters logs, metrics, fallback telemetry, route inventories,
   failure-class artifacts, or attempt records.
7. Normal Chat remains Sonnet, streaming, tool-capable, locally journaled, restart-safe,
   and non-provider-switchable. It has no cloud history fallback.
8. Deleting public web changes capability truth only: private local retrieval remains,
   and responses never falsely claim browsing/current verification.
9. Realtime PTT retains Auto/Gemini/OpenAI, daily picker, manual switch, eligible
   failover, warm/reconnect behavior, native speech, barge-in, interrupted continuity,
   screen evidence, local tools, diagnostics, and usage accounting.
10. `ask_higher_model` removal does not route PTT through normal Chat or change normal
    Chat's endpoint/model.
11. Gemini proxy exact authentication, entitlement, burst/daily limits, fail-closed
    Redis, payload/output/thinking bounds, safe controls, and sanitized errors remain.
12. Vertex ordinary non-success is returned; only credential acquisition falls back to
    platform AI Studio. No request is silently replayed across providers.
13. The preview-name rewrite remains. Pro and `streamGenerateContent` fail closed/404 as
    applicable after removal.
14. Embedding batch cardinality/order is exact; vectors normalize and commit only to the
    matching local record/current generation. Index deletion follows local deletion.
15. Proactive prompts, thresholds, cadence, dedup, notification identifiers/copy, Focus,
    Task, Insight, Memory and Profile behavior are unchanged.
16. Greeting failure remains non-fatal and title failure remains `New Chat`; manual rename
    wins; accepted candidates enter the local journal/catalog exactly once.
17. Conversation empty/long/short discard policy, keep-on-failure, structure/action
    prompts, time-zone/language handling, task dedup/admission, and manual edit precedence
    remain exact.
18. Memory L1 evidence and 32-item bound, L2 detail-preserving normalization, conflict
    conservation/reference/relationship rules, retry/review behavior, and atomic local
    lifecycle commit remain exact.
19. Translation keeps target/language/split/batch/cardinality/cache/metrics behavior and
    original text on failure; local Parakeet text is not uploaded for translation.
20. `/v1/tts/synthesize` voice catalog, Shimmer default, instructions, preview/prewarm,
    speed, system fallback, entitlement, and shared rate limit remain exact.
21. Actual quota/usage counters survive gateway/accounting deletion; no detailed unread
    attempt document becomes a billing or entitlement source.
22. LangSmith never restores in-app ratings or cloud Chat copies. Prompt fallback remains
    versioned in the repository and remote/fallback source metadata stays truthful.
23. Unknown/deleted model feature names fail closed; there is no default model, provider
    guess, ignored field, dormant switch, no-op service, or fake-success response.
24. Billing remains disabled and provider transactions are not enabled by this slice.

## 10. Target authority, result ownership, and service-topology model

```text
owner-local source rows + RuntimeOwnerAuthorizationSnapshot + input revision
                               |
                               v
                    bounded workload request
                               |
              Firebase auth / entitlement / quota / rate limits
                               |
        +----------------------+----------------------+
        |                      |                      |
 direct Anthropic        direct OpenAI         Gemini boundary
 normal Chat             named workloads       - Mac proxy: Vertex/Studio
                                                - Python direct translation/title
        |                      |                      |
        +----------------------+----------------------+
                               |
                    transient validated candidate
                               |
         revalidate owner + request/generation/revision/references
                               |
                      owning local transaction
                               |
         local journal / GRDB / SQLite vectors / transient UI context
                               |
                    publish only after commit
```

The final Python routing surface is a typed, exhaustive workload registry, not a
customer- or deployment-wide QoS profile. Each entry has at minimum:

```text
workload key
provider + exact model
allowed caller/route
input/output bound owner
timeout/retry/fallback policy
usage/entitlement feature
content-free observability label
durable result owner (always Mac-local or none)
```

No registry entry may use a default provider/model. Provider failover exists only where
an assigned requirement explicitly retains it: realtime cross-provider failover,
Vertex credential fallback to platform Studio, Live Suggestions' current fixed fallback,
and workload-owned bounded failure behavior. Removing the standalone gateway does not
invent direct-provider fallback for workloads that did not have one.

Service topology after S-22 application closure:

```text
Mac -> canonical authenticated Python backend -> retained managed providers
                                            -> Redis/account/quota/usage facts

Mac local stores = product authority
canonical backend = transient compute/admission boundary
LLM gateway       = zero callers and application code removed
S-25              = deployment/image/workflow/secret/traffic/live-resource closure
```

## 11. Ordered TDD cycles

The cycles are sequential. Every RED uses production behavior through a controllable
seam; source/residue assertions are explicitly labelled static tripwires.

### Cycle 1 — executable caller, route, model, and result-owner contract

- **Behavioral RED:** Through real FastAPI routes and Mac/Node public seams with fake
  providers/stores, enumerate every retained and retiring model workload. Assert an
  exact caller, route, provider/model, bounded input/output, usage feature, and durable
  result owner. An unknown feature and a deleted feature must fail closed rather than
  resolve to `_DEFAULT_CONFIG`. Run a Sonnet Chat turn, one Gemini generation, one
  embedding, one conversation candidate, and one Memory candidate to prove inventory
  entries describe executable behavior rather than strings.
- **Why RED now:** routing is split across Swift `ModelQoS`, Python profile maps,
  pinned maps, default fallback, gateway-generated lanes, provider-only sets, route
  files, and a gateway-centric YAML inventory. Unknown feature names silently receive
  OpenAI GPT-4.1-mini.
- **Minimum GREEN:** introduce one typed exhaustive workload inventory used by routing
  validation and diagnostics, classify temporary retiring entries with their owning
  deletion cycle, remove the unknown-feature fallback, and make route construction
  require a known entry. Do not add a second provider adapter or change any model yet.
- **Retained behavior:** all current retained calls, payloads, prompts, usage, errors,
  and local commits.
- **Authority before / after:** before, profile/default/gateway config appears to own
  routes; after, the typed workload record owns route identity while local stores still
  own product state.
- **Expected change:** `model_config.py`, `clients.py`, provider construction,
  `model_endpoint_inventory.yaml`, focused routing tests; only narrow test injection
  seams in routes/Mac if current seams cannot control provider/store results.
- **Focused verification:** backend routing/model-config tests, `test_desktop_chat.py`,
  `test_desktop_proxy.py`, conversation/Memory route tests; focused Swift
  `ModelQoSTests|EmbeddingServiceOwnerFenceTests`; Pi managed-provider test.
- **Deletion/simplification enabled:** safe removal of profiles/default/gateway lanes
  and precise successor handoffs.
- **Stop:** an executable workload lacks an authorizing IR or result owner; the live
  code has an unreviewed provider; or the inventory can be green only by blessing an
  implicit default.

### Cycle 2 — pin reachable Mac Gemini models and narrow the authenticated proxy

- **Behavioral RED:** From each live `ModelQoS.Gemini` caller, assert fixed current
  model values independent of UserDefaults. Through the real proxy, assert Flash,
  Flash-Lite, embedding, and preview-rewrite requests preserve Vertex/Studio shape;
  Pro receives 403; the streaming route is a genuine 404; `streamGenerateContent` is
  rejected; ordinary generation and single/batch embeddings still succeed. Cover
  Vertex token-acquisition fallback, ordinary Vertex non-success no-replay, and local
  platform Studio development.
- **Why RED now:** `ModelTier`, private defaults, Pro branches/allowlists/soft downgrade,
  `OMI_MODEL_TIER`, and `/gemini-stream` remain live.
- **Minimum GREEN:** replace tier-dependent Mac accessors with fixed defaults; delete
  tier defaults/notification/description/tests; remove Pro and its downgrade/env path;
  delete streaming route/action/helpers/tests. Preserve preview rewrite and the normal
  proxy.
- **Retained behavior:** prompts, cadence, fallback models, non-stream response/error
  handling, auth/entitlement/limits/bounds, Vertex/Studio adaptation, embeddings.
- **Authority before / after:** hidden Mac preference can select model before; explicit
  caller/workload route selects model after. Result authority remains local.
- **Expected change:** `ModelQoS.swift`, callers/tests only as needed for fixed accessors,
  `desktop_proxy.py`, route-policy/contract docs/tests; no proactive prompt changes.
- **Focused verification:** `test_desktop_proxy.py`, proxy route/limit tests,
  `ModelQoSTests`, proactive/Task/Insight/Suggestion/Profile/PTT vocabulary tests.
- **Deletion/simplification enabled:** Pro model/config/tests, hidden tier and streaming
  plumbing.
- **Stop:** a production writer for `modelQoS_activeTier` appears; a retained caller uses
  streaming or Pro; or released-contract evidence requires an explicit sunset.

### Cycle 3 — prove Gemini generation and embeddings remain local-result-authoritative

- **Behavioral RED:** Suspend fake Gemini generation/embedding across A→B and same-UID
  ABA, then return valid results. Assert no Focus/Memory/Task/Insight/Profile row,
  suggestion/journal/notification, task/conversation/Rewind vector, index entry,
  telemetry success, or publication. Inject persistence failure and batch count/order
  mismatch. Same-generation success commits once before publication; query embeddings
  remain transient; delete/restart/offline preserve local index truth.
- **Why RED now:** C2 changes shared model/proxy selection. A route-level 200 test cannot
  prove each downstream caller still preserves Wave 2 owner and commit fences.
- **Minimum GREEN:** pass the existing immutable authorization snapshot through any
  changed request construction and preserve/reinforce the current generation/revision
  checks; add only missing narrow injection seams. No prompt, cadence, threshold,
  schema, or storage redesign.
- **Retained behavior:** exact proactive behavior, local semantic search, 3,072-dim
  normalization, batch cardinality, backfill limits, Rewind 100/50 result behavior,
  local owner resets.
- **Authority before / after:** unchanged local stores/indexes; proxy remains transient.
- **Expected change:** mostly behavioral tests around `GeminiClient`, `EmbeddingService`,
  `OCREmbeddingService`, assistants and local stores; production changes only for a
  discovered missing fence caused by C2.
- **Focused verification:** embedding owner/reset tests; local Memory lifecycle; Task
  similarity; Rewind semantic search; proactive assistant owner/publication tests.
- **Deletion/simplification enabled:** confidence to remove remaining tier/proxy aliases
  without preserving defensive dual paths.
- **Stop:** any result owner is cloud/unknown, a raw prompt reaches telemetry, or a
  missing owner fence requires behavior broader than S-22; repair the owning boundary
  or stop rather than add a call-site boolean.

### Cycle 4 — one direct managed Sonnet route for normal Chat

- **Behavioral RED:** Drive non-stream and streaming `/v2/chat/completions` with a fake
  direct Anthropic client through the local Pi loop. Prove tool calls, partial text,
  usage, quota, request correlation, cancellation/provider error mapping, journal
  acceptance, restart, and owner switch. Assert the Mac/Node sends only `omi-sonnet`,
  Opus/Haiku/dormant selection is unreachable, and no gateway URL/token/lane is used.
- **Why RED now:** backend aliases accept Opus/Haiku/dated IDs and the client proxy can
  route Sonnet through `omi:auto:chat-agent`/gateway.
- **Minimum GREEN:** construct managed Anthropic directly in the canonical backend;
  delete Chat gateway proxy/circuit/lane selection; narrow accepted in-tree identity to
  canonical Sonnet after released-contract proof; remove Opus/Haiku/selection residue
  with no surviving caller. Keep provider construction lazy/import-pure.
- **Retained behavior:** local Pi model/tool/model loop, tools/approvals, prompt,
  streaming, retry/error contract, journal, attachments, quota and count usage.
- **Authority before / after:** local journal remains Chat authority; compute moves from
  independent gateway to canonical backend direct Anthropic.
- **Expected change:** `desktop_chat.py`, `clients.py`, provider factories, Node model
  profile/fixtures/tests, backend chat tests and contract docs. No local journal schema.
- **Focused verification:** `test_desktop_chat.py`, offline LLM stub, agent runtime and
  Pi extension suites, Chat catalog/journal/owner-bound auth Swift tests.
- **Deletion/simplification enabled:** `gateway_anthropic.py`, Chat gateway lanes and
  aliases after no other caller remains.
- **Stop:** released non-Windows clients require an alias without a sunset decision; a
  Pi/background caller genuinely selects Opus; or direct Anthropic changes request/tool
  semantics. Do not silently keep gateway fallback.

### Cycle 5 — delete public web and Perplexity after consuming S-19

- **Behavioral RED:** After mandatory S-19 rebase, run the local Pi Chat path with a
  current-facts prompt. Assert no public-web classifier/prompt injection, synthetic
  progress, denial stripping, provider-native `web_search`, Perplexity call, or browsing
  claim; the model may answer from knowledge or state it cannot verify. Assert local
  conversations/memories/tasks/goals/files/Rewind tools still work. Run PTT through both
  realtime providers and Auto/failover and prove `ask_higher_model` is already absent.
  **Static tripwire:** the named public-web fixture and consumers are absent.
- **Why RED now:** baseline Pi adapter/prompt/fixture and Perplexity profile/tool/config
  remain; S-19-owned higher-model surfaces are present until predecessor integration.
- **Minimum GREEN:** consume S-19-generated outputs; delete Pi public-web routing,
  `ChatPrompts` web instructions, synthetic projection/denial manipulation, Perplexity
  tool/provider/model/config/tests/docs, and public-web fixture/consumers. Do not edit
  S-19 tool removal again and do not delete private URL/file/local retrieval by name.
- **Retained behavior:** normal Chat, all private local tools, explicit user-supplied URL
  behavior governed elsewhere, both realtime providers/Auto/failover, truthful errors.
- **Authority before / after:** no public-web provider remains; local data owners and
  selected model knowledge answer remain unchanged.
- **Expected change:** Pi adapter/runtime tests, `ChatPrompts`, Perplexity/model config,
  gateway/provider residue, docs/fixtures; generated tool surfaces only via the S-19
  source generator if refreshed integration requires it.
- **Focused verification:** Pi adapter/runtime suites, `test-tool-surfaces.sh`, Chat
  prompt/discoverability tests, both realtime provider harnesses, model routing tests.
- **Deletion/simplification enabled:** Perplexity key/lane/provider and public-web failure
  contract.
- **Stop:** S-19 is absent; a match is private retrieval/explicit URL rather than general
  web; or failure-class lifecycle is being combined with behavior deletion. The registry
  is marked dormant only in a separate PR after this behavior PR merges.

### Cycle 6 — delete callerless ElevenLabs while preserving live TTS

- **Behavioral RED:** Through the real app, `/v1/tts/synthesize` with each retained
  voice and the system fallback still plays/returns the same audio/error behavior;
  entitlement and rate-limit failures remain typed. Assert `/v2/tts/synthesize` is 404,
  arbitrary ElevenLabs settings are absent, generated app-client has no operation, and
  the shared rate limiter remains used by `/v1`.
- **Why RED now:** `/v2`, `models/tts.py`, ElevenLabs HTTP/semaphore/config/tests and
  committed OpenAPI operation remain.
- **Minimum GREEN:** remove the `/v2` route/registration/model/exclusive client/config/
  env/test/docs and regenerate app-client OpenAPI/Swift. Delete shared code only after
  `/v1` caller proof.
- **Retained behavior:** OpenAI model/voices/default/instructions/prewarm/speed/fallback,
  auth, entitlement, shared Redis limit.
- **Authority before / after:** both are transient playback; after, only the live OpenAI
  route exists.
- **Expected change:** `tts.py`, `models/tts.py`, env/http/rate config where exclusive,
  OpenAPI/generated Swift, backend/Mac tests/docs.
- **Focused verification:** `test_tts.py`, TTS rate/text-bound tests, Mac playback/TTS
  tests, OpenAPI freshness and route policy.
- **Deletion/simplification enabled:** ElevenLabs secret/template/harness binding proven
  exclusive to this route.
- **Stop:** another retained deployment uses the same credential/client or a released
  client requires `/v2` without an adopted removal transition.

### Cycle 7 — explicit direct greeting and title compute with local-only commits

- **Behavioral RED:** Through new local Chat creation and first accepted exchange,
  suspend greeting/title provider calls across A→B and same-UID ABA, return valid/empty/
  oversized/late candidates, fail provider/persistence, and manually rename mid-flight.
  Assert direct GPT-5.4-mini greeting and Gemini Flash-Lite title routing, bounded local
  inputs, no gateway/cloud session access, one local journal/catalog commit, no phantom
  preview/count, `New Chat`/welcome fallback, and manual rename precedence.
- **Why RED now:** result ownership is local, but both backend helpers still resolve
  through `get_llm` profile/gateway mediation.
- **Minimum GREEN:** bind each route to its explicit in-process provider/model using the
  shared direct client layer; retain output caps and usage. Remove only profile/lane
  dependencies and any hosted-Chat vocabulary left exclusive to these routes.
- **Retained behavior:** prompts, one-attempt timing, context bounds, authentication,
  rate/usage, fallback, local commit and UI behavior.
- **Authority before / after:** local journal/catalog before and after; canonical backend
  replaces gateway as compute caller.
- **Expected change:** `chat_sessions.py`, direct provider registry/client, focused
  backend tests; Mac only if a missing existing owner fence is exposed.
- **Focused verification:** chat session route tests, API client routing, Home catalog,
  kernel turn projection, owner-bound auth, one-assistant contract.
- **Deletion/simplification enabled:** greeting/title profile entries and gateway lanes.
- **Stop:** route reads/writes a backend Chat session, input grows beyond approved local
  bounds, or model/prompt/fallback would change.

### Cycle 8 — explicit direct conversation candidate compute

- **Behavioral RED:** Use real candidate routes with fake providers and strict spies at
  Firestore/task/index/notification boundaries. Cover empty, >100-word, short-duration,
  valid, parse failure, timeout, local generation change, related-task target mismatch,
  persistence failure, and independent structure/action failure. Assert exact GPT-4.1-
  nano/GPT-5.4-mini routes, keep-on-failure, no cloud write, and local commit/publication
  ordering.
- **Why RED now:** candidate endpoints are stateless, but `conversation_processing`
  still receives routes from profiles/gateway; old hosted processing shares helpers.
- **Minimum GREEN:** inject explicit direct workload clients into discard/structure/
  action helpers, retain prompts/parsers/cache options and usage, and separate small
  provider-neutral helpers from hosted finalizer dependencies. Do not delete hosted
  product routes here.
- **Retained behavior:** IR-727/732 prompts, thresholds, time/language normalization,
  event/action schemas, dedup, task admission, manual edits and independent failures.
- **Authority before / after:** Mac conversation/task stores throughout; backend direct
  compute replaces gateway mediation.
- **Expected change:** conversation compute/processing direct route construction and
  tests; no local schema or product policy change.
- **Focused verification:** `tests/routers/test_conversation_compute.py`, conversation
  processing tests, three Swift enrichment/admission suites, owner fence and persistence
  publication tests.
- **Deletion/simplification enabled:** retained conversation model profile/gateway lanes;
  clearer S-23 boundary around hosted finalization/folder code.
- **Stop:** provider-neutral helper cannot be separated without changing hosted product
  behavior; S-23 owner work is required; or accepted candidate semantics would change.

### Cycle 9 — keep only Memory L1/L2/conflict compute with local lifecycle authority

- **Behavioral RED:** Through all three real routes and `LocalMemoryLifecycleRunner`,
  suspend across owner/ABA and revision changes; inject unknown evidence/targets,
  subject/sensitivity changes, duplicate/superseded targets, restricted material,
  provider/parse/persistence failure, and retry. Assert fixed GPT-4.1-mini direct route,
  no backend persistence, no invalid mutation, and exact atomic local transitions.
  **Static tripwire:** legacy `memories`, `learnings`, `memory_category`, selectors and
  cloud writes remain absent.
- **Why RED now:** canonical path is already direct and local-authoritative; S-22 routing
  cleanup could accidentally pull it back under a generic profile/gateway or preserve
  dead Memory vocabulary.
- **Minimum GREEN:** register the existing pinned direct client as the sole three Memory
  workloads, remove any remaining profile/lane/usage/config aliases, and retain negative
  retirement checks. Production prompt/validation code changes only if generic routing
  is still coupled.
- **Retained behavior:** every L1/L2/conflict invariant and local lifecycle policy.
- **Authority before / after:** unchanged `MemoryStorage`/local runner authority.
- **Expected change:** workload registry/client wiring, Memory compute tests and model
  inventory; no prompt/schema/storage redesign.
- **Focused verification:** `test_memory_compute.py`, local Memory lifecycle/owner tests,
  semantic vector/source-deletion tests, negative legacy-route tests.
- **Deletion/simplification enabled:** old Memory feature keys and gateway/profile lanes.
- **Stop:** current direct model differs from the live decision, a legacy caller is real,
  or S-12 local owner contract is not integrated.

### Cycle 10 — one direct Gemini translation route, with S-16 behavior unchanged

- **Behavioral RED:** Through `/v4/listen`, translate split/batched segments using a fake
  direct Gemini Flash-Lite provider. Cover target/language validation, cardinality,
  empty/negative cache, timeout/provider error, stale local generation, local commit,
  original transcript preservation, and no NLLB/gateway call. Local Parakeet remains
  untranslated/upload-free.
- **Why RED now:** NLLB is absent but `translation_core.providers` still obtains the
  model from `get_llm('translation')`, which may select the gateway/profile.
- **Minimum GREEN:** construct the explicit direct Gemini Flash-Lite structured-output
  client in the canonical backend; remove translation profile/lane/provider-list
  residue while preserving planner/cache/metrics and usage.
- **Retained behavior:** all S-16/IR-726 semantics and local segment authority.
- **Authority before / after:** local segment store throughout; backend direct compute
  replaces gateway mediation.
- **Expected change:** translation provider construction/model inventory and focused
  tests; no listen wire or Mac UI change.
- **Focused verification:** four translation optimization/cache suites, transient listen
  route tests, local ingestion/translation Swift tests, NLLB residue search.
- **Deletion/simplification enabled:** translation profile/gateway lane and any one-item
  provider abstraction with no other caller.
- **Stop:** S-16 behavior is not integrated, a provider list still owns a live fallback,
  or live ledger model conflicts with Flash-Lite.

### Cycle 11 — close already-dead model families without absorbing product owners

- **Behavioral RED:** Exercise deterministic Agent Pill lifecycle, Advanced Settings,
  local proactive assistants/notifications, Mac screenshots/OCR/vision, and local Pi
  retrieval. Assert no cosmetic Pill provider request, Chat Lab/BYOK window, cloud
  proactive/notification model call, glasses vision-model event, legacy Memory model,
  `chat_extraction`, or `chat_graph`. Unknown retired feature names fail closed.
  **Static tripwires:** exact source/config/model-route residue lists for these families.
- **Why RED now:** principal callers are already absent, but generic aliases/profile/
  tests/docs and same-named product residue can survive; broad deletion could also hit
  protected Mac behavior or S-23 data.
- **Minimum GREEN:** remove only callerless S-22-owned aliases/config/tests/docs and keep
  negative behavioral contracts. Classify generic `openglass` signup/history enums,
  notification journal origin, and hosted product data as S-23/non-model residue.
- **Retained behavior:** deterministic Pill titles/status, agent runs/journal, Settings,
  local assistants/macOS notifications, screenshot/OCR/Chat images, local retrieval.
- **Authority before / after:** unchanged local owners; rejected compute remains absent.
- **Expected change:** model aliases/config, focused negative tests/docs; no broad product
  route/data deletion.
- **Focused verification:** Agent Pill lifecycle, S-14 retirement tests, wearable model
  retirement, proactive assistant suites, local screenshot/vision and Pi tests.
- **Deletion/simplification enabled:** Haiku/ChatLab/cloud-model vocabulary proven
  exclusive; clean handoff list for S-23.
- **Stop:** a match is a retained local surface or S-23 product record; a backend alias
  has released-contract evidence; or removal would change Pill/assistant behavior.

### Cycle 12 — close S-22 with three exact successor-owned model bindings

- **Behavioral RED:** Build the executable caller/result-owner inventory and prove every
  S-22-owned rejected workload is absent. The only permitted rejected live bindings are
  `followup -> Joan`, `conv_folder -> automatic folder assignment`, and
  `backend/routers/wrapped.py -> wrapped_analysis -> OpenRouter`. A second OpenRouter
  caller, generic unknown/default route, Trends/onboarding model binding, any fourth
  rejected binding, or unowned provider configuration fails the contract. Retained
  direct OpenAI/Anthropic/Gemini workloads remain green.
- **Why RED now:** the current registry contains several rejected-product callers and
  broad provider/profile configuration, so the successor handoff is not yet isolated.
- **Minimum GREEN:** delete callerless S-22-owned model routes/provider entries and make
  the exhaustive inventory fail closed. Preserve only the smallest existing bindings
  for Joan/followup, automatic folder assignment/`conv_folder`, and
  Wrapped/`wrapped_analysis`/OpenRouter; record their exact files/config/tests as the
  S-23 handoff. Do not delete or change those routes, data, prompts, model semantics, or
  isolated product pieces in S-22.
- **Retained behavior:** all retained workloads and adjacent route 404/auth behavior.
- **Authority before / after:** rejected hosted product owners disappear vertically;
  no new authority replaces them.
- **Expected change:** S-22 provider/model inventory, fail-closed registry/config/tests,
  and three precise S-23 handoffs; no hosted product route/data schema.
- **Focused verification:** executable workload inventory, retained direct-provider
  tests, route policy/OpenAPI, unknown/default failure tests, and an exact assertion that
  Wrapped is the sole OpenRouter caller.
- **Deletion/simplification enabled:** S-22 can close without a dependency cycle; S-23
  can delete Wrapped and OpenRouter together.
- **Stop:** any handoff is not one of the exact three, preserving one requires a generic
  fallback, product behavior would change, a second OpenRouter caller exists, or any
  additional rejected caller remains.

### Cycle 13 — delete global QoS profiles and implicit routing

- **Behavioral RED:** Restart the backend with absent, `premium`, `max`, `byok`, invalid,
  and gateway-mode env. For each surviving workload, assert the same one explicit route
  every time; deleted/unknown names fail closed. No customer key, global env, hidden
  Mac preference, or gateway override changes a route. Workload-owned fallbacks alone
  remain.
- **Why RED now:** duplicated maps, `_active_profile`, `_DEFAULT_CONFIG`, startup
  `MODEL_QOS`, provider-only sets, profile logs/tests, and request-time gateway routing
  remain.
- **Minimum GREEN:** make the C1 exhaustive inventory the sole route authority; delete
  profiles, active profile/accessors, default, QoS env, BYOK upgrade, generated auto
  lanes, profile-only structured sets/options/logs/tests/docs. Keep small provider
  construction primitives shared by explicit routes.
- **Retained behavior:** exact models selected by IRs, prompt cache/output caps, usage/
  error callbacks, auth/entitlement, and workload-specific failure behavior.
- **Authority before / after:** global deployment profile/gateway before; explicit
  workload route after. Local product owners unchanged.
- **Expected change:** `model_config.py`, `clients.py`, `providers.py`, tests/env/docs and
  model inventory.
- **Focused verification:** exhaustive workload contract, all retained route tests,
  no-unknown/default tests, test isolation/import purity.
- **Deletion/simplification enabled:** profile/gateway compatibility wrappers and broad
  integration tests over rejected feature maps.
- **Stop:** the C12 successor handoff cannot survive without implicit profile routing,
  S-20's fair-use workload is not explicitly pinned to direct OpenAI GPT-5.1, or any
  final route is inferred/defaulted rather than decided.

### Cycle 14 — remove unread accounting and collapse gateway application code

- **Behavioral RED:** Run every retained Python workload with the gateway endpoint
  unreachable and assert direct provider fakes receive the request, workload-owned
  failures remain exact, authoritative quota/usage counters update, and no
  `llm_gateway_attempts` write occurs. Application startup/imports must require no
  gateway URL/token/chart. A strict inventory must show zero application caller.
- **Why RED now:** gateway client/shadow/resilience/serving/observability modules,
  service source, attempt sink/collection, cost cards, route artifacts and application
  env contracts remain.
- **Minimum GREEN:** delete unread accounting writer/queue/config/rate cards/metrics;
  delete application gateway clients, lanes, shadow/promotion/circuit/transport wrappers
  and standalone service source once zero callers are proven. Retain direct provider
  timeout/retry/error/usage and low-cardinality workload metrics. Produce the exact S-25
  deployed-topology handoff rather than mutating it live.
- **Retained behavior:** Chat and candidate APIs, quota/usage, provider metrics/errors,
  auth, cancellation, and import purity.
- **Authority before / after:** independent gateway mediates before; canonical backend
  directly owns transient calls after. No product data authority changes.
- **Expected change:** gateway application/source/accounting modules and application
  config/tests/docs. Charts/workflows/runtime image/secret/traffic entries change only
  according to the resolved S-25 owner split.
- **Focused verification:** retained route suites; quota/usage tests; import purity;
  runtime image source closure; backend env validation; account deletion/export
  enumeration; zero-caller search.
- **Deletion/simplification enabled:** S-25 can remove the independently deployed service,
  images, workflows, GKE/ingress/VPC/secret/alerts and later live resources.
- **Stop:** any retained caller still uses gateway; S-25 split is unresolved; a shared
  provider/metric primitive has another caller; or live resource mutation would occur.

### Cycle 15 — preserve LangSmith and Prompt Hub without restoring ratings

- **Behavioral RED:** With hermetic fake LangSmith clients, exercise disabled/global/
  scoped tracing status, project/endpoint/key selection, tracer construction, current
  run binding, Prompt Hub success/version metadata, TTL hit/expiry/invalidation, safe
  render, malformed/network/key failure, and repository fallback. Assert no in-app
  thumbs rating, Firestore Chat copy, or submit-feedback endpoint is created and no raw
  content enters ordinary logs.
- **Why RED now:** helpers/tests exist, but current non-test caller tracing finds only
  startup/global environment reachability; the intended surviving Prompt Hub/scoped
  consumer is not named.
- **Minimum GREEN:** preserve and simplify only the authorized helper/config/dependency
  surface; attach content-free workload metadata where the current tracing mechanism
  already supports it. Do not wire a new remote prompt into local Pi or reintroduce a
  hosted Chat path merely to manufacture a caller. Rebranding of default project/prompt
  names waits for S-30 unless separately authorized.
- **Retained behavior:** IR-827/828 plus IR-832 operator-side annotation/evaluation;
  Sentry/PostHog remain separate; repository fallback remains available.
- **Authority before / after:** LangSmith prompt when fetched, repository fallback on
  failure; local product stores remain authoritative for Chat/data.
- **Expected change:** observability tests/docs and possibly direct workload callback
  plumbing only if an existing reachable consumer is verified. No ratings UI/routes.
- **Focused verification:** LangSmith tracing boundary, prompt cache/client/config/
  metadata safety tests, startup/import/log sanitization tests.
- **Deletion/simplification enabled:** gateway-specific tracing labels and stale Omi
  identity only in the later S-30 pass.
- **Stop:** no surviving consumer can be named and closure is interpreted to require new
  product wiring; product owner must clarify helper availability versus live use.

### Cycle 16 — integrated repository and named-bundle closure

- **Behavioral RED:** Run one hermetic end-to-end matrix covering normal Chat, both PTT
  providers and Auto/failover, Gemini generation/embedding, greeting/title, discard/
  structure/action items, Memory L1/L2/conflict, translation, and OpenAI TTS. For every
  local-result workload cover success, offline/provider failure, restart, A→B, same-UID
  ABA, persistence failure, and late result. Removed routes fail genuine 404/403 as
  designed. Run the equivalent real user paths in `omi-wave3-s22` without touching
  production bundles.
- **Why RED now:** focused GREENs do not prove cross-domain owner resets, generated
  contracts, route policy, config/docs, zero residue, or full PTT/Chat adjacency.
- **Minimum GREEN:** repair only integration defects within prior cycles; regenerate
  contracts/tool surfaces from source; update component guides/model inventory/privacy
  handoff; run closure searches. No new feature or provider.
- **Retained behavior:** every invariant in Section 9.
- **Authority before / after:** final target model in Section 10.
- **Expected change:** integration tests, generated outputs only when source contracts
  changed, model inventory/docs; product changes remain those already authorized.
- **Focused verification:** Section 14 complete matrix, Section 15 named bundle, route/
  OpenAPI/tool freshness, component suites, preflight.
- **Deletion/simplification enabled:** final S-22 closure and exact S-23/S-25 handoffs.
- **Stop:** C12–C15 gates remain, a model/provider has no named retained caller/result
  owner, live credentials/hardware are unavailable for required real-provider proof, or
  repository closure would be confused with live decommission. Record `NOT_RUN` for
  unavailable external evidence; never fake a pass.

## 12. Cross-slice ownership and handoffs

| Slice | S-22 consumes / hands off | S-22 must not do |
|---|---|---|
| S-05 | Consume one managed Pi/Sonnet/local journal and private bridge. | Restore adapters, customer provider choices, broad execution, or alternate transports. |
| S-07 | Consume product-owned credentials. | Restore BYOK/config forwarding or entitlement bypass. |
| S-10 | Consume local conversation authority and candidate seams. | Redesign conversation schemas/search/finalization or hosted teardown. |
| S-11 | Consume local Chat greeting/title/journal/catalog. | Restore backend Chat sessions/messages/ratings or change Home shell. |
| S-12 | Consume local Memory candidate/lifecycle authority. | Change lifecycle rules or hosted Memory product teardown. |
| S-13 | Consume local Task/Goal stores and action admission. | Change Task policies or restore hosted tasks. |
| S-14 | Consume local proactive/Profile/Focus/Insights and negative cloud-model proof. | Change prompts/cadence/thresholds/settings/notification copy. |
| S-16 | Consume Gemini-only translation and transient listen. | Change STT protocol/providers or restore NLLB. |
| S-19 | Consume final tool manifest and absence of higher-model voice escalation; preserve both providers. | Re-delete/rewrite PTT tools, lifecycle, local grounding, or session audit. |
| S-20 | Consume its local-GRDB evidence seam and retain direct OpenAI GPT-5.1 transient classification while removing obsolete generic gateway/profile routing. | Change its model, prompt, recipes, output/parser, cadence, thresholds, fail-open behavior, evidence bounds, or enforcement semantics. |
| S-21 | Hand final Settings/model-entry absence to shell convergence. | Redesign Settings/navigation or Voice Model picker. |
| S-23 | Hand exactly three rejected live bindings—Joan/followup, automatic folder assignment/`conv_folder`, and Wrapped/`wrapped_analysis` through OpenRouter—plus zero other generic provider residue. S-23 deletes each with its complete product and runs S-22 retained-provider tests; S-22 is not reopened. | Delete isolated product pieces, redesign hosted product behavior, or preserve any fourth rejected binding/second OpenRouter caller/default. |
| S-24 | Hand proof that embeddings are transient and vectors/indexes local. | Delete Typesense/Pinecone/OpenAI Files/GCS product data. |
| S-25 | Hand zero gateway callers plus exact deployment/image/workflow/secret inventory. | Deploy, decommission, delete live resources, or retarget unrelated jobs. |
| S-26/S-27 | Hand one explicit provider layer inside canonical backend and reduced env contract. | Broaden backend/deployment consolidation. |
| S-30 | Hand provider/privacy/model/Prompt Hub disclosures and stale Omi identities. | Perform final brand/legal rewrite. |
| S-31 | Hand commands, timings, named-bundle evidence, and unavailable external proof. | Claim overall release closure. |

## 13. Repository residue-search strategy

Run searches after each owning cycle and again on the final integrated tree. Classify
historical requirements/roadmap/changelog matches rather than deleting them.

### Retained route/model inventory

```bash
rg -n 'get_llm\(|get_model\(|get_provider\(|ModelQoS\.|gemini-|gpt-|claude-' \
  backend desktop/macos --glob '!**/windows/**' --glob '!**/vendor/**' \
  --glob '!**/.venv/**' --glob '!**/.openapi-venv/**' --glob '!**/__pycache__/**'

rg -n '/v2/chat/completions|/v2/realtime/session|/v1/auto/model-pick|/v1/proxy/gemini|conversation-compute|memory/compute|/v1/tts/synthesize' \
  backend desktop/macos docs --glob '!**/windows/**'
```

Every production hit maps to the Section 7 retained table or an explicit successor
handoff. Unknown/default feature resolution is zero.

### Profiles, aliases, rejected providers, and routes

```bash
rg -n 'MODEL_QOS|ModelTier|modelQoS_activeTier|modelTierDidChange|OMI_MODEL_TIER|premium|max|byok|omi-opus|claude-opus|claude-haiku' \
  backend desktop/macos .github docs --glob '!**/windows/**' --glob '!**/changelog/**'

rg -n -i 'perplexity|sonar-pro|openrouter|elevenlabs|/v2/tts/synthesize|nllb|gemini-stream|streamGenerateContent|gemini-2.5-pro' \
  backend desktop/macos .github docs --glob '!**/windows/**' --glob '!**/changelog/**'
```

Final production/config/test/doc hits for deleted S-22 families are zero. Generic words
in decision records or historical changelogs are classified. Before S-23, rejected
model bindings must equal the exact three handoffs and OpenRouter hits must remain
Wrapped-only; S-25 deployment hits are listed exactly.

### Public web and S-19 boundary

```bash
rg -n 'ask_higher_model|escalateToHigherModel|omi_web_search|routePromptForPublicWeb|web_search|public-web-routing-contract|Perplexity|Sonar' \
  desktop/macos backend .github docs --glob '!**/windows/**' --glob '!**/changelog/**'
```

Private local search, explicit URL readers governed elsewhere, historical failure-class
record, and decision docs are classified. Production public-web and higher-model hits
are zero after S-19 + S-22. The failure-class JSON persists until its separate dormant
lifecycle PR.

### Gateway and accounting

```bash
rg -n 'llm_gateway|llm-gateway|LLM_GATEWAY|omi:auto:|llm_gateway_attempts|gateway_shadow|gateway_anthropic|gateway_serving' \
  backend .github desktop/macos docs --glob '!**/__pycache__/**'
```

Application caller/source hits are zero at S-22 closure. Any S-25-owned deploy/live
handoff is enumerated by exact file/resource name and cannot be silently counted as
S-22 closure.

### Already-retired workload guards

```bash
rg -n -i 'generateTitleAndAck|ChatLab|chat_lab|chatlab_anthropic_api_key|proactive_notification|chat_extraction|chat_graph|memory_category|_extract_memories_legacy|openglass|smart_glasses|image_chunk|photo_described' \
  backend desktop/macos --glob '!**/windows/**' --glob '!**/changelog/**'
```

Classify retained journal origin/local assistants and historical signup enums; do not
bulk-delete same-named non-model behavior.

### Secrets, deployment, docs, account lifecycle

```bash
rg -n 'OPENAI_API_KEY|ANTHROPIC_API_KEY|GEMINI_API_KEY|ARTIFICIALANALYSIS_API_KEY|LANGSMITH|LANGCHAIN|PERPLEXITY_API_KEY|OPENROUTER_API_KEY|ELEVENLABS|OMI_LLM_GATEWAY_SERVICE_TOKEN' \
  backend .github desktop/macos docs --glob '!**/windows/**'

rg -n 'llm_gateway_attempts|model|provider|prompt|trace' \
  backend/database backend/routers/users.py backend/tests docs --glob '!**/__pycache__/**'
```

Retained credential names map to exact retained workloads. Rejected secret names have
no repository consumer; live Secret Manager state remains unknown until later read-only
inventory and authorization.

## 14. Focused and component-level verification commands

Exact test selections may be extended after implementation inventory refresh; never
claim a command passed unless it was actually run.

### Planning/ledger and focused backend

```bash
python3 bootstrap-scaffold/validate-requirements-ledger.py

cd backend
pytest -q \
  tests/unit/test_desktop_chat.py \
  tests/unit/test_desktop_proxy.py \
  tests/unit/test_desktop_realtime.py \
  tests/routers/test_conversation_compute.py \
  tests/unit/test_memory_compute.py \
  tests/unit/test_translation_optimization.py \
  tests/unit/test_translation_cost_optimization.py \
  tests/unit/test_translation_dedup_edge_cases.py \
  tests/unit/test_translation_negative_cache_detection.py \
  tests/unit/test_tts.py \
  tests/unit/test_tts_ratelimit_async.py \
  tests/unit/test_tts_request_text_bound.py \
  tests/unit/test_langsmith_tracing_boundary.py \
  tests/unit/test_prompt_caching.py \
  tests/unit/test_prompt_cache_client_config.py \
  tests/unit/test_prompt_metadata_safety.py
```

Add the final explicit-workload, no-default, public-web absence, gateway zero-caller,
route 404, quota/usage, import-purity, runtime-env, account deletion/export, and
successor-product tests to this focused set by their actual discovered filenames.

### OpenAPI, route policy, runtime contracts

```bash
cd backend
scripts/openapi_runner.sh scripts/route_policy_inventory.py \
  --check --enforce-missing-baseline
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py --check
scripts/openapi_runner.sh pytest -q tests/unit/test_openapi_contract.py
cd ..
make runtime-image-source-closure
```

When an app-client route changes, regenerate using the live surface:

```bash
cd backend
scripts/openapi_runner.sh scripts/generate_swift_openapi_types.py
```

Never hand-edit `desktop/macos/Desktop/Sources/Generated/OmiApi.generated.swift`.

### Focused Mac/Node/tool surfaces

```bash
cd desktop/macos
./scripts/dev-feedback.py --once swift \
  'ModelQoSTests|EmbeddingServiceOwnerFenceTests|OCREmbeddingServiceOwnerResetTests|ConversationDiscardAdmissionTests|ConversationStructureEnrichmentTests|ConversationActionItemEnrichmentTests|LocalMemoryLifecycleRunnerTests|HomeChatCatalogTests|KernelJournalOwnerBoundAuthTests|RealtimeManagedAuthenticationTests|RealtimeHub|ChatPromptsTests'

./scripts/test-tool-surfaces.sh
./scripts/agent-logic-harness.sh
```

Add focused proactive, Profile, Rewind semantic search, TTS playback, API routing, and
translation tests by exact test name after changed-file selection is known.

### Official component and repository acceptance

```bash
cd backend && bash test.sh
cd ../desktop/macos && ./test.sh
cd ../..
python3 bootstrap-scaffold/validate-requirements-ledger.py
git diff --check
make preflight
scripts/pr-preflight --suggest
# Write the real PR body, including Failure-Class, then:
scripts/pr-preflight --pr-body-file /tmp/pr-body.md
```

Before a `fix:` commit/PR, follow the repository failure-class rule. The public-web
behavior PR and later dormant-registry PR remain separate. Any new stable inventory
checker must be registered in `.github/checks-manifest.yaml` with local and CI lanes in
the same PR and must cite the merged incident/PR it would have caught.

## 15. Real named-bundle and retained user-path acceptance

Build and run only the assigned non-production bundle:

```bash
cd desktop/macos
export OMI_AUTOMATION_PORT=47822
OMI_APP_NAME="omi-wave3-s22" ./run.sh --full
./scripts/omi-ctl wait-ready
agent-swift connect --bundle-id com.omi.omi-wave3-s22
```

If port `47822` is occupied, choose one free high port and use that exact value for
the launch and every `omi-ctl` or harness command in the acceptance run.

Seed normal auth/settings only when the tested path is not authentication/onboarding.
Read the exact private log via `./scripts/omi-ctl log-path`. Never start, stop, restart,
overwrite, seed, or automate `/Applications/Omi.app`, `/Applications/Omi Beta.app`,
`com.omi.computer-macos`, or `com.omi.computer-macos.beta`.

Acceptance matrix:

1. **Normal Chat:** create a new ordinary Chat, receive the greeting, exchange text and
   one local tool call, restart, and prove the journal/catalog survives. Trigger title,
   manually rename, and prove late title cannot overwrite it. Ask for a current fact and
   verify no browsing/progress/citation claim while private local retrieval still works.
2. **Realtime providers:** exercise manual OpenAI, manual Gemini, Auto primary, and an
   injected eligible primary failure that reaches the alternate. Verify native audio,
   interruption/barge-in, local journal/tool behavior, and no higher-model tool.
3. **Gemini generation:** exercise Focus, Task, Insight, Memory screenshot, Profile,
   Home/Live suggestion or the nearest stable automation actions. Confirm current model
   behavior and local-only result state.
4. **Embeddings/search:** add/search/delete one Memory or Task, run local conversation
   similarity, and run Rewind text+semantic search. Restart and repeat offline for local
   reads; provider-offline query embedding may fail visibly without corrupting indexes.
5. **Conversation compute:** finalize a short meaningful local conversation and exercise
   discard/structure/action candidates; inject one provider failure and prove transcript
   stays, independent jobs continue, and no phantom task/title appears.
6. **Memory compute:** explicit Add/Edit normalization, conversation extraction, and one
   consolidation run; inject failure/late owner transition and prove local revision and
   lifecycle truth.
7. **Translation:** use managed STT translation, preserve original transcript on injected
   translation failure, and verify local segment display/commit.
8. **TTS:** exercise each retained voice choice or stable catalog contract, preview/play,
   and injected cloud failure leading to the existing system voice fallback. No `/v2`
   ElevenLabs request occurs.
9. **Owner isolation:** sign out Alice, sign in Bob, repeat representative Chat,
   embedding, candidate and proactive paths, then return to Alice. No stale result,
   cache, vector, notification, usage terminal, or journal turn crosses owners.
10. **Disabled billing:** verify current free/disabled entitlement presentation remains
    unchanged and produces no Dodo/Stripe/provider transaction.

Record timestamps, bundle ID/path, commands, test/fault mode, redacted request IDs,
screenshots/log excerpts, local row counts, provider used, and pass/fail/`NOT_RUN`.
Hermetic fakes prove code contracts but are not real-provider evidence. If development
OpenAI/Anthropic/Gemini/Artificial Analysis/LangSmith credentials are unavailable,
record the corresponding live-provider rows `NOT_RUN` with the exact blocker; do not
invent secrets or report a fake as live.

## 16. Repository closure versus separately authorized live operational closure

Repository implementation does not authorize a deployment or external mutation.

For the independent gateway, Firestore `llm_gateway_attempts`, Secret Manager keys,
GKE/Helm releases, internal ingress/static address, VPC connectors, service accounts/
IAM, container images, workflows, metrics/alerts, OpenRouter/Perplexity/ElevenLabs
accounts, LangSmith project/prompt, or provider credentials:

1. S-22 records likely resources only from repository names.
2. S-25/later operations perform a read-only inventory using verified project,
   environment, namespace, region, account, and resource identifiers.
3. Classify each resource retained, rejected, shared, unknown, or already absent and
   attach traffic/caller evidence.
4. Review backup, retention, legal/privacy, rollback, billing/contract, and audit needs.
5. Obtain explicit authorization before disabling traffic, deleting data/secrets/IAM/
   service/image, changing LangSmith resources, or deploying.
6. Verify zero traffic/caller, bounded rollback, deletion result, and surviving backend
   health after any separately authorized operation.

Do not guess project IDs, cluster names, credentials, customer data, provider contracts,
or live state. Repository removal of `llm_gateway_attempts` writers does not authorize
historical collection deletion. Prompt/project rebranding does not authorize mutating a
live LangSmith project or prompt. Billing stays disabled through all six waves; the Dodo
acceptance in `../dodo-integration.md` remains a separate post-Wave-6 operation.

## 17. Risks, ambiguities, and explicit stop points

| Risk / ambiguity | Safe response and evidence needed |
|---|---|
| S-19 not integrated | Rebase and refresh; consume its generated tool result. C5/final PTT proof stop until then. |
| S-20 local-evidence classify route is not integrated | Preserve the current GPT-5.1 workload without changing it; wait for S-20's bounded local-GRDB evidence contract. C13 cannot delete its feature route before replacing generic routing with the explicit direct GPT-5.1 route. |
| S-23 model handoffs differ from the exact three | S-22 stops and classifies the caller. Closure permits only Joan/followup, automatic folder assignment/`conv_folder`, and Wrapped/`wrapped_analysis`/OpenRouter; S-23 deletes each vertically without reopening S-22. |
| Gateway application deletion overlaps S-25 deployed service ownership | S-22 proves/migrates zero callers; S-25 owns deploy/live teardown. Record exact file split before C14. |
| Prompt Hub/scoped LangSmith helpers have no non-test consumer | Preserve authorized helpers; do not wire a new product path. C15/final closure needs owner clarification if “live consumer” is required. |
| Backend accepted Chat aliases may be released | Inspect app-client/release evidence; stop for explicit sunset/versioning. Do not keep dormant in-tree selection as fake compatibility. |
| Generic `get_llm` callers include rejected products | Classify each caller; delete with owning product or stop. Never make unknown fallback the migration path. |
| Provider model IDs may drift externally | Implementation uses live ledger/current code; any model upgrade requires separate evidence/decision. Do not browse/upgrade merely for freshness during this plan. |
| Direct client behavior differs from gateway | Characterize streaming/tool/error/cache/output/usage first; preserve workload semantics, not gateway internals. Stop on unowned failover behavior. |
| Shared provider factory/config match has another owner | Reference trace before deletion; move small provider-neutral primitive only when retained caller proof exists. |
| Local-result fence is incomplete | Repair the authoritative transaction/fence with behavioral regression coverage; do not add observer booleans or call-site exceptions. |
| Public-web terms overlap explicit URL/private retrieval | Delete only general public-web behavior; classify and retain independently authorized URL/local tools. |
| NLLB/model routes already absent | Preserve negative contracts; do not recreate work to make the cycle nonempty. |
| Live credentials/hardware unavailable | Run hermetic and named-bundle local paths, mark external rows `NOT_RUN`; no invented key/model/live state. |
| Live gateway/provider resources still exist | Repository work may proceed within owner split; operational mutation remains blocked on inventory + authorization. |
| An official affected component suite is red | The slice remains open. Fix an owned regression or close independently owned suite debt before closure; focused passing or baseline comparison is not a substitute. |

Missing inputs and reopening evidence:

- **S-19 integration SHA and final generated tool manifest** — affects C5/C16; supplied by
  S-19 owner/integration. Safe work: C1–C4 and C6–C11.
- **Exact three S-23 model handoffs** — resolved by the owner correction; C12 must prove
  Joan/followup, automatic folder assignment/`conv_folder`, and
  Wrapped/`wrapped_analysis`/OpenRouter are the complete set. Any additional rejected
  binding reopens classification, not S-23-first staging.
- **S-25 repository/deploy split** — affects C14 and operational handoff; supplied by
  S-25 plan/integration owner. Safe work: direct caller migration and zero-caller proof.
- **Prompt Hub/scoped tracing surviving consumer interpretation** — affects C15 final
  closure only; supplied by product/requirements owner or verified integrated caller.
- **Released alias/route evidence** — affects exact removals, supplied by repository
  release/OpenAPI history; ordinary unreleased-fork deletion proceeds only after check.
- **Real development provider credentials** — affect live-provider acceptance rows only,
  supplied through authorized local/development secret management; never stored here.

## 18. Final completion checklist

- [ ] Baseline/rebase checks and 714/714 ledger validator pass on implementation HEAD.
- [ ] Every assigned IR-053, IR-113, IR-600–609, IR-710–732, IR-827 and IR-828 is represented by a cycle, retained proof, or explicit owner gate.
- [ ] S-19 is integrated; higher-model voice tool is absent; both realtime providers,
      Auto/manual choice and failover pass without S-22 reimplementing S-19.
- [ ] S-20 local-GRDB/transient-GPT-5.1 boundary is consumed without changing its model,
      classifier semantics, evidence bounds, fail-open behavior, or enforcement.
- [ ] Every surviving model identifier has one named caller, exact route/provider,
      bounded contract, usage owner, failure policy, and local/no-result owner.
- [ ] Unknown/deleted workload keys fail closed; global profiles, defaults, hidden tiers,
      BYOK upgrades, dormant provider switches and one-item provider lists are absent.
- [ ] Gemini proxy keeps auth/entitlement/limits/bounds/Vertex+Studio/preview rewrite;
      Pro and streaming are genuinely rejected/404 with retained generation/embeddings green.
- [ ] Gemini generation/embedding results pass offline/restart/failure/A→B/same-UID ABA/
      persistence-failure/late-result tests with local-only state.
- [ ] Normal Chat is direct managed Sonnet with local Pi/tools/journal, no Opus/Haiku/
      gateway/public web, and exact stream/quota/error behavior.
- [ ] Perplexity/Sonar/public-web behavior is absent; private local retrieval remains;
      failure-class dormant transition is a later separate PR.
- [ ] Callerless `/v2` ElevenLabs is 404 and removed from app-client contracts; live
      `/v1` OpenAI TTS and shared rate limit remain exact.
- [ ] Greeting/title, conversation, Memory, and translation workloads use explicit direct
      models and commit only through current owner-local transactions.
- [ ] Agent Pill/ChatLab/cloud proactive/notification/glasses/legacy Memory/hosted Chat
      model routes remain absent without deleting retained adjacent Mac behavior.
- [ ] The only S-22 successor-owned rejected bindings are `followup` for Joan,
      `conv_folder` for automatic folder assignment, and `wrapped_analysis` through
      OpenRouter for Wrapped; S-23 owns deleting each with its complete product and
      S-22 needs no reopen.
- [ ] `llm_gateway_attempts` writer and gateway application caller/source are absent;
      actual quota/usage and workload metrics pass.
- [ ] S-25 has an exact zero-caller deployment/image/workflow/secret/live-resource handoff;
      no external mutation occurred in S-22.
- [ ] LangSmith tracing and Prompt Hub fallback tests pass; no in-app ratings/cloud Chat
      copy is restored; unresolved consumer interpretation is explicitly closed or gated.
- [ ] Route policy, OpenAPI and generated non-Windows Swift are fresh; tool surfaces are
      generated from source and pass the official test.
- [ ] Account deletion/export, import purity, runtime image/env, logging sanitization,
      docs and model inventory describe the surviving topology truthfully.
- [ ] Focused tests, official affected backend/desktop suites, `git diff --check`,
      `make preflight`, PR preflight, and failure-class validation all pass.
- [ ] `omi-wave3-s22` acceptance covers retained Chat/PTT/models/local owners and records
      unavailable provider evidence as `NOT_RUN` rather than pass.
- [ ] Production Omi bundles, billing providers, live cloud/provider resources, Windows,
      push/PR/merge/deploy, and external infrastructure were untouched unless separately
      authorized outside this planning slice.

## 19. Integrated closeout record — 2026-08-23

S-22 implementation merged in PR #40 at `5d6573ff`. Its required registry-only
lifecycle transition merged in PR #45 at `402d9fea`, and stale OpenRouter fake,
endpoint, comment, and secret vocabulary was removed in `4b032fce`. Direct-route,
removed-route, `/v4/listen`, and metrics tests are green. S-22 is **implemented
but not repository-closed** because the real OpenAI/Gemini/Auto/failover matrix
and physical/controller PTT acceptance are not green. See
[`../wave-4/wave-3-4-closeout tdd.md`](../wave-4/wave-3-4-closeout%20tdd.md).
