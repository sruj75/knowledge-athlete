# Gemini Chat and Langfuse Migration Research

**Status:** Superseded implementation research. The repository subsequently migrated managed Chat to Gemini and LangSmith to Langfuse (`bee479e7`, `f3c9a4f4`, `aaa93207`, `7251e6a5`, `f007efc1`). Read this document as the pre-implementation evidence, not the current runtime declaration. Live development Gemini/Langfuse secret binding and provider proof remain open.

**Audited commit:** `98ff1714b125b09b17d3ca741d090232be95901c`

**Audited on:** 2026-09-01

**Scope:** Normal typed/floating-bar Chat only for the Anthropic-to-Gemini question, and the retained tracing, prompt-management, annotation, dataset, and evaluation boundary for the LangSmith-to-Langfuse question. Realtime PTT, Gemini Live, title generation, translation, embeddings, and OpenAI-owned memory/TTS workloads are separate.

**Source policy:** Local production source plus official Google, Langfuse, and LangSmith documentation/source only.

## Plain-English answer

Yes, both replacements are technically reasonable, but neither is a credential-only swap.

- **Anthropic can be replaced by Gemini for floating-bar Chat without rewriting the floating bar.** The Mac and local Pi runtime already talk to an Intentive-owned, OpenAI-shaped `/v2/chat/completions` contract. The backend is the Anthropic-specific part. Keep that Intentive contract stable and replace its provider adapter.
- **The fact that Intentive already uses Gemini does not make normal Chat plug-compatible.** The existing authenticated Gemini proxy is non-streaming, allows only Gemini 2.5 Flash/Flash-Lite generation plus embeddings, and does not implement the multi-turn streaming tool protocol required by Chat.
- **Gemini tool continuation metadata is the largest compatibility boundary.** Gemini 3 function calls carry encrypted thought signatures that must be returned unchanged during the tool round. In Google's OpenAI-compatible shape this lives in `tool_calls[].extra_content.google.thought_signature`. Intentive's current adapter drops that field. A migration that streams text successfully but loses this value will fail on real tool loops.
- **Langfuse can replace LangSmith, and this is a good time to do it because the checked-in LangSmith Chat/prompt helpers are not called by a production Chat path.** The only definite production call found is startup status logging. This does not prove that a remote LangSmith project contains no historical data, so any real project must still be inventoried before deletion.
- **OpenTelemetry makes tracing portable, not the whole AI-development platform.** It can carry trace/span context and attributes to either LangSmith or Langfuse. Prompt versions, deployment labels, datasets, experiment runs, evaluator definitions, scores, annotation queues, and UI deep links remain vendor-specific objects and need an explicit one-time migration or recreation.
- **The current v1 decision explicitly forbids the Langfuse migration.** IR-827, IR-828, and IR-832 retain LangSmith tracing, Prompt Hub, and website-side evaluation. Those decisions must be reopened and superseded before implementation. This report does not alter them.

My recommendation is therefore:

1. approve Langfuse as a deliberate single destination, not dual delivery;
2. preserve the Intentive `/v2/chat/completions` contract and build a dedicated Gemini Chat adapter behind it;
3. choose the exact Gemini model only after a repository-owned streaming/tool/prompt quality evaluation;
4. remove Anthropic only after the real floating-bar tool loop passes end to end.

## What actually runs today

```text
Floating bar / Swift
        |
        v
local Node + Pi runtime
  provider = "omi"
  model = "omi-sonnet"
  API shape = OpenAI chat completions
        |
        | Firebase bearer token
        v
POST /v2/chat/completions
        |
        | OpenAI messages/tools -> Anthropic Messages translation
        | Anthropic events -> OpenAI SSE translation
        v
Claude Sonnet 4.6
```

The extension registers an `omi` provider with the `openai-completions` API and the backend base URL; it does not hold an Anthropic key ([extension source](../desktop/macos/pi-mono-extension/index.ts#L306-L324)). The local adapter explicitly deletes `ANTHROPIC_API_KEY`, authenticates to Intentive with the Firebase token, and pins `omi/omi-sonnet` ([Pi adapter](../desktop/macos/agent/src/adapters/pi-mono.ts#L254-L303), [session pin](../desktop/macos/agent/src/adapters/pi-mono.ts#L377-L403)).

The backend publicly accepts `omi-sonnet`, resolves it to the `chat_agent` workload, and owns the provider translation ([desktop Chat route](../backend/routers/desktop_chat.py#L68-L73), [workload inventory](../backend/utils/llm/model_config.py#L129-L139)). It converts OpenAI roles, image data, function declarations, tool calls, and tool results into Anthropic Messages input ([request translation](../backend/routers/desktop_chat.py#L123-L205)); converts Anthropic stop reasons and usage back to OpenAI output ([response translation](../backend/routers/desktop_chat.py#L208-L255)); and converts Anthropic-native stream events to OpenAI SSE chunks ([stream translation](../backend/routers/desktop_chat.py#L282-L393)).

This is the important architectural conclusion: **the floating bar is coupled to Intentive's Chat contract, while the current backend implementation of that contract is coupled to Anthropic.** The provider change belongs behind the backend boundary.

### Why the existing Gemini path cannot simply be reused

The current desktop Gemini proxy admits only `generateContent`, `embedContent`, and `batchEmbedContents`, and only Gemini 2.5 Flash, Gemini 2.5 Flash-Lite, and `gemini-embedding-001` ([proxy allowlist](../backend/routers/desktop_proxy.py#L19-L38)). It forwards a complete HTTP request and returns a complete response; there is no `streamGenerateContent` action or streaming response bridge ([proxy request](../backend/routers/desktop_proxy.py#L186-L218)).

That proxy is suitable for its existing bounded Mac Gemini workloads. Normal Chat additionally requires:

- long-lived SSE delivery and keep-alives;
- streamed tool name/argument assembly;
- multi-turn tool-result continuation;
- provider stop/refusal normalization;
- usage emission and authoritative quota accounting;
- cancellation, first-event timeout, total deadline, and pre-first-event retry behavior;
- the larger context/output contract currently advertised to Pi.

Therefore, Chat should get a dedicated Gemini adapter behind `/v2/chat/completions`, not be squeezed through the existing generic desktop proxy.

## Anthropic-to-Gemini compatibility boundary

| Surface | What can stay | What must change or be proved |
|---|---|---|
| Mac/Swift UI | Floating-bar send, stream display, local journal, tool execution | No provider noun or stale Sonnet model identity should remain in user-visible/runtime configuration |
| Pi-facing protocol | Intentive's OpenAI-shaped messages, tools, SSE chunks, usage chunk, `[DONE]`, Firebase auth, contract version | Add and test an opaque Gemini continuation-metadata path for thought signatures |
| Model route | One explicit `chat_agent` workload | Change `anthropic/claude-sonnet-4-6` to the selected Gemini route; rename `omi-sonnet`/`Omi Sonnet` truthfully |
| System prompt | Pi can keep supplying the system prompt at subprocess start | Map it to Gemini `system_instruction`; preserve the current subprocess-restart behavior when it changes |
| Text and images | Existing OpenAI text and data-URL inputs can remain public | Translate to Gemini contents/parts and validate the selected model's image and context limits |
| Tools | Existing function schemas, tool-call IDs, and tool-result journal can remain | Map tool-choice modes, function calls, streamed JSON arguments, tool responses, and thought signatures |
| Streaming | Existing OpenAI SSE output contract can remain | Translate Gemini events/deltas, terminal usage, finish reasons, safety blocks, errors, cancellation, and keep-alives |
| Retry/deadlines | Preserve the product-owned 25-second first-event, 20-second heartbeat, 150-second turn, three-attempt, pre-first-event-only retry policy | Disable or reconcile Google SDK retry so SDK, backend, and Pi retries do not multiply each other |
| Usage | Existing server-owned usage/quota boundary can remain | Map prompt, output, cached, and thinking token fields without double-counting or silently dropping chargeable tokens |
| Privacy | Mac remains the conversation/journal authority; no cloud conversation copy | Send only the bounded turn to Google; do not use provider-stored conversation state; document Google processing/retention accurately |

### Streaming is compatible, but it needs a new translator

Google officially supports streaming for Gemini. The newer Interactions API emits server-sent events such as interaction creation, step start/delta/stop, and interaction completion, including function-call steps and terminal usage ([Google streaming guide](https://ai.google.dev/gemini-api/docs/streaming)). Google's OpenAI compatibility endpoint also supports streamed chat completions and function calling ([OpenAI compatibility guide](https://ai.google.dev/gemini-api/docs/openai)).

Intentive cannot return those provider events directly. Pi expects OpenAI chat-completion chunks, while the backend also owes the product keep-alives, usage accounting, a stable request ID, cancellation, and a final `[DONE]`. A Gemini adapter must perform the same provider-neutral job that `_stream` performs today for Anthropic.

The provider's first data event should remain the boundary after which the backend does not automatically replay a turn. Replaying after text or a tool call has begun can duplicate visible output or side effects.

### Tool use is compatible, with one critical opaque field

Gemini supports function declarations, function calls, tool responses, automatic/required/specific tool selection, and sequential or parallel calls. The ordinary schema and tool-result concepts therefore match Pi's agent loop.

The critical difference is Gemini thought signatures. Google's official guidance says Gemini 3 function calls include an encrypted signature representing the model's internal reasoning context. The application must return it exactly in the subsequent tool round; omission or corruption can produce a `400` error. With the OpenAI compatibility API, Google places it at `tool_calls[].extra_content.google.thought_signature` ([thought-signature guide](https://ai.google.dev/gemini-api/docs/generate-content/thought-signatures)).

Intentive currently rebuilds assistant tool calls using only `id`, `type`, function `name`, and JSON `arguments`, then translates only those values into Anthropic `tool_use` blocks ([current request parser](../backend/routers/desktop_chat.py#L142-L173)). Its streamed response similarly emits only the standard tool-call fields ([current tool stream](../backend/routers/desktop_chat.py#L315-L365)). There is no defined opaque continuation field in Chat contract v1.

Before using a Gemini model that requires signatures, add a behavioral contract test proving this complete round trip:

```text
Gemini streamed function call + thought signature
  -> backend OpenAI-shaped SSE
  -> Pi/local journal
  -> tool execution
  -> next /v2/chat/completions request
  -> backend Gemini request containing the exact same signature
```

Do not parse, rewrite, summarize, or invent the signature. Treat it as opaque provider continuation metadata. If the installed Pi transport cannot preserve Google's `extra_content` extension, contract v2 needs a provider-neutral opaque field or the Pi bridge must gain an explicit mapping.

### System prompts are straightforward

Google supports system instructions, including through its OpenAI-compatible `system` role ([OpenAI compatibility guide](https://ai.google.dev/gemini-api/docs/openai)). A native adapter should map Intentive's system/developer input to Gemini's `system_instruction` rather than inserting it as ordinary user content.

The local runtime already makes system-prompt changes explicit: Pi has no RPC to change the prompt, so the adapter restarts the subprocess when the session's prompt changes ([Pi adapter](../desktop/macos/agent/src/adapters/pi-mono.ts#L269-L273), [restart behavior](../desktop/macos/agent/src/adapters/pi-mono.ts#L380-L387)). The provider migration should preserve that ownership and not introduce provider-side prompt memory.

### Preserve the retry budget; do not stack retries

The current direct-Chat transport deliberately owns its safety budget: first event within 25 seconds, progress heartbeat every 20 seconds, 150-second total duration, up to three provider attempts, and at least 45 seconds of remaining headroom before retry ([policy](../backend/utils/llm/anthropic_transport.py#L20-L42)). Streaming retries happen only before any provider event has been emitted ([stream policy](../backend/utils/llm/anthropic_transport.py#L81-L170)). The Anthropic SDK is constructed with `max_retries=0`, so it cannot silently multiply the application policy ([client](../backend/utils/llm/clients.py#L15-L31)).

Google's SDK troubleshooting documentation describes automatic retry for transient network, timeout, `429`, and `5xx` failures ([Gemini troubleshooting](https://ai.google.dev/gemini-api/docs/troubleshooting)). A direct replacement must either disable those SDK retries or make the product-owned transport delegate to a single documented retry owner. Otherwise one Pi retry can contain several backend attempts, each of which can contain several hidden SDK attempts.

The existing file and environment names are Anthropic-specific. The behavior should move into a provider-neutral managed-Chat transport rather than duplicating the policy in a new Gemini-only file.

### Safety blocks and stop reasons need explicit semantics

Gemini can return a blocked prompt through `promptFeedback.blockReason` or finish a candidate with a safety-related reason and no normal content ([safety settings](https://ai.google.dev/gemini-api/docs/safety-settings), [API error guidance](https://ai.google.dev/gemini-api/docs/api-errors)). The current Anthropic adapter maps every unknown stop reason to ordinary `stop` ([stop mapping](../backend/routers/desktop_chat.py#L226-L229)). Reusing that default would turn a blocked/invalid Gemini result into a misleading successful empty answer.

The adapter should define provider-neutral outcomes for at least:

- normal completion;
- output limit;
- tool call;
- safety/refusal block;
- malformed function call or missing thought signature;
- retryable transport/rate-limit failure;
- terminal provider failure.

Only normal completion, length, and valid tool call should become ordinary successful OpenAI finish reasons. The rest should surface as typed provider errors or an intentional refusal presentation.

### API choice: use native semantics for production; treat OpenAI compatibility as a spike

There are three plausible Google call surfaces:

| Option | Advantage | Cost/risk | Assessment |
|---|---|---|---|
| Gemini OpenAI compatibility endpoint | Smallest initial request/response shape change | Google labels compatibility support beta; Google-specific fields such as thought signatures still escape the standard OpenAI shape | Good for a short contract spike, not a reason to skip provider-specific tests |
| Native `generateContent`/`streamGenerateContent` | Mature native Gemini content/tool schema; explicit control over signatures and usage | Intentive must own more translation code; the existing desktop proxy no longer admits streaming | Viable production implementation |
| Gemini Interactions API | Google marks it GA and recommends it for new projects; first-class streaming steps and tool interactions | Newer API and event model; `store=true` by default unless disabled | Strong production candidate if used with `store=false` and full-history resend |

Google's Interactions documentation says stored interactions are the default. With `store=false`, the service does not persist the interaction object and `previous_interaction_id` cannot be used, so the client must resend the necessary history ([Interactions overview](https://ai.google.dev/gemini-api/docs/interactions-overview)). That matches Intentive's Mac-owned conversation authority better than provider-owned conversation state.

If Interactions is selected, set `store=false` explicitly on every call and keep resending only the bounded owner-scoped context already assembled by the local runtime. If native GenerateContent is selected instead, it already receives the supplied contents per request; do not add a separate Google conversation store.

### Privacy is a processor change, not a local-authority change

Using the paid Gemini API does not make prompts local. Intentive sends the bounded system prompt, conversation context, images, and tool results to Google instead of Anthropic.

Google's paid-services terms say submitted content is not used to improve Google's products and is processed under the applicable data-processing terms ([Gemini API terms](https://ai.google.dev/gemini-api/terms)). Separately, Google's abuse-monitoring policy says prompts, context, and outputs may be retained for 55 days for policy enforcement and may be reviewed when flagged ([usage policies](https://ai.google.dev/gemini-api/docs/usage-policies)). Google logging is another separately controlled surface with its own retention/sharing behavior ([logs and datasets policy](https://ai.google.dev/gemini-api/docs/logs-policy)).

`store=false` on Interactions disables stored interaction state; it does **not** override abuse-monitoring retention. The product disclosure should distinguish those two boundaries.

Use a billing-enabled Intentive-owned Google project, keep prompt/response logging and sharing disabled unless separately approved, sanitize application logs, and send no more local context than the existing bounded Chat contract permits.

### Do not select the model by reuse alone

The current Gemini proxy's Flash/Flash-Lite models serve different workloads and do not prove quality for a long-context tool-using assistant. The current Chat contract advertises a 200,000-token context window, 16,384 output tokens, text/images, reasoning, streamed function calls, and a local tool loop ([extension model contract](../desktop/macos/pi-mono-extension/index.ts#L306-L319)).

The strongest current candidate is `gemini-3.7-flash`, not either of the 2.5
models already admitted by the generic proxy. Google describes 3.7 Flash as a
GA model for complex agentic workflows, with a 1,048,576-token input limit,
65,536-token output limit, function calling, and low/medium/high thinking
levels ([model overview](https://ai.google.dev/gemini-api/docs/models/gemini-3.7-flash),
[latest-model guide](https://ai.google.dev/gemini-api/docs/latest-model)). At
current paid-tier list prices it is $0.75 per million input tokens and $3.75 per
million output tokens through December 31, 2026, rising to $1.50/$7.50 on
January 1, 2027 ([Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing)).
The currently pinned Claude Sonnet 4.6 route is now classified as legacy and
lists $3/$15 ([Claude Sonnet 4.6](https://platform.claude.com/docs/en/models/sonnet-4-6/overview)).
That makes Gemini nominally four times cheaper at today's introductory token
rates and two times cheaper after the announced increase, but only an
end-to-end replay can show whether different thinking/tool-loop token use keeps
the real turn cost lower.

Before pinning a Gemini model, run a hermetic provider-contract suite plus a controlled live evaluation covering:

- simple text streaming and cancellation;
- the production system prompt and representative long local context;
- image input;
- one tool call, sequential tool calls, and parallel tool calls;
- exact thought-signature continuation;
- malformed tool arguments and failed tool results;
- safety block and empty response;
- first-event timeout, midstream disconnect, `429`, and `5xx`;
- usage including cached/thinking tokens;
- latency, answer quality, tool-selection accuracy, and cost against the current Claude baseline.

The result should select one explicit managed Gemini model. Do not add customer selection, per-request Anthropic fallback, or a permanent dual-provider branch merely to make migration safer.

## LangSmith-to-Langfuse compatibility boundary

### What is wired today

The backend has three LangSmith-specific surfaces:

1. environment/status helpers and a startup log ([status helpers](../backend/utils/observability/langsmith.py#L15-L95), [startup call](../backend/main.py#L45-L60));
2. a LangChain tracer callback and current LangSmith run-ID binder ([tracing helpers](../backend/utils/observability/langsmith.py#L98-L161));
3. Prompt Hub pull, extraction, five-minute in-process cache, commit metadata, and repository fallback ([prompt helper](../backend/utils/observability/langsmith_prompts.py#L21-L177)).

The dependency is pinned as `langsmith==0.8.5` ([requirements](../backend/requirements.txt#L103)). The message model still names LangSmith run/prompt fields ([message model](../backend/models/chat.py#L47-L65)).

A repository-wide Python call search found no production caller of `get_chat_tracer_callbacks`, `bind_current_langsmith_run`, `get_agentic_system_prompt_template`, or `get_prompt_metadata`; the names appear in their modules, exports, and focused unit tests. The current production path definitely calls only `log_langsmith_status`. This means the checked-in Chat path is not currently depending on those helper outputs.

This reduces migration risk, but it is not evidence that a configured LangSmith project is empty. Before deleting a real credential or project, inventory remote prompts, traces, datasets, annotation queues, evaluators, and experiments.

### What OpenTelemetry does and does not replace

Both platforms support OpenTelemetry:

- Langfuse's current Python and JavaScript SDKs are built on OpenTelemetry, and it can ingest OTLP/HTTP ([Langfuse SDK overview](https://langfuse.com/docs/observability/sdk/overview), [public API/OTLP](https://langfuse.com/docs/api-and-data-platform/features/public-api)).
- LangSmith also accepts OpenTelemetry traces ([LangSmith OpenTelemetry guide](https://docs.langchain.com/langsmith/trace-with-opentelemetry)).

So this part is portable:

```text
application operation
  -> W3C trace/span context + GenAI attributes
  -> OTLP exporter
  -> chosen trace backend
```

But these parts are not standardized by OpenTelemetry:

| Capability | LangSmith object | Langfuse object | Migration consequence |
|---|---|---|---|
| Prompt deployment | prompt commit/tag | immutable prompt version/label | Recreate versions and map production labels deliberately |
| Prompt variables | LangChain prompt/template conventions, currently `{name}` in this repo | Langfuse variables use `{{name}}` | Convert syntax and test rendering |
| Prompt retrieval | `Client.pull_prompt(...)` returns LangChain prompt objects | `get_prompt(...)` returns a Langfuse prompt client | Rewrite extraction/rendering and metadata |
| Availability cache | repository-owned five-minute cache/fallback | SDK cache, stale-while-revalidate, configurable TTL, optional fallback | Preserve the intended 300-second/fallback contract explicitly |
| Trace identity | LangSmith run ID/run tree | W3C trace ID plus Langfuse observation IDs | Rename persisted/operator-link metadata; do not pretend IDs are interchangeable |
| Generations | LangChain tracer/run metadata | Langfuse generation observations and model/usage fields | Add semantic generation attributes; generic spans alone are too weak |
| Feedback/scores | LangSmith feedback/evaluation records | Langfuse scores | One-time mapping/recreation if records exist |
| Dataset/experiment | LangSmith dataset and experiment APIs | Langfuse dataset, item, experiment/run APIs | Recreate; an OTLP exporter does not move them |
| Annotation UI | LangSmith annotation queues/workflows | Langfuse trace/session review and scores | Recreate operator workflow and permissions |

Langfuse documents immutable prompt versions and movable labels such as `production`, SDK caching/stale-while-revalidate, and a fallback value for guaranteed availability ([prompt management](https://langfuse.com/docs/prompt-management/overview), [version control](https://langfuse.com/docs/prompt-management/features/prompt-version-control), [caching](https://langfuse.com/docs/prompt-management/features/caching), [guaranteed availability](https://langfuse.com/docs/prompt-management/features/guaranteed-availability)). LangSmith likewise has its own prompt commit/tag and programmatic pull lifecycle ([LangSmith prompt management](https://docs.langchain.com/langsmith/manage-prompts-programmatically)). These are similar product concepts, not wire-compatible objects.

The same distinction applies to evaluation. Both platforms support datasets and experiments, but each owns its dataset, experiment, evaluator, score, and annotation data model ([Langfuse evaluation concepts](https://langfuse.com/docs/evaluation/core-concepts), [LangSmith evaluation concepts](https://docs.langchain.com/langsmith/evaluation-concepts)).

### Recommended Langfuse architecture

Use one application-owned instrumentation boundary rather than scattering Langfuse imports through provider code:

```text
Intentive Chat operation
  parent trace: authenticated request / local turn identity
    child generation: provider, model, prompt version, timings, token usage
    child tool span(s): safe tool name + outcome, never raw sensitive results by default
    child retry/fallback event(s): existing bounded labels
```

Required properties:

- W3C trace IDs and explicit parent/child context;
- provider and model on each generation;
- input/output token usage, cached/thinking usage where available, and cost only when trustworthy;
- prompt name, immutable version, and environment label;
- safe request/session/user correlation using internal pseudonymous identifiers rather than raw emails or prompt text;
- flush/shutdown behavior appropriate for Cloud Run;
- observability failure remains non-fatal to Chat;
- masking happens before the Langfuse exporter.

Langfuse's SDK supports explicit observations/generations and current trace IDs ([instrumentation guide](https://langfuse.com/docs/observability/sdk/instrumentation)). Its masking hook runs before data is sent by the Langfuse exporter, but separate OpenTelemetry exporters still receive their own unmodified copies ([masking guide](https://langfuse.com/docs/observability/features/masking)). Therefore “we use OTel” is not a privacy boundary. Each exporter and collector needs its own filtering decision.

### Managed Langfuse versus self-hosting

Langfuse is open source and can be self-hosted ([official repository](https://github.com/langfuse/langfuse), [self-hosting docs](https://langfuse.com/self-hosting)). Self-hosting can improve infrastructure and retention control, but it adds a stateful production stack, backups, upgrades, access control, incident response, and cost. It is not automatically the smaller v1 decision.

For either managed or self-hosted Langfuse:

- choose and document retention;
- mask or omit raw prompts, screenshots, transcripts, tool results, and local memory by default;
- use pseudonymous account/trace correlation;
- restrict project access;
- verify deletion/export behavior;
- keep telemetry disclosures truthful.

Langfuse documents configurable retention behavior ([data retention](https://langfuse.com/docs/administration/data-retention)). Its self-hosted telemetry documentation says raw traces, prompts, scores, and datasets are not sent to Langfuse, and documents how open-source deployments can disable usage telemetry ([self-hosted telemetry](https://langfuse.com/self-hosting/security/telemetry)).

### Migration sequence if Langfuse is approved

1. Inventory any real LangSmith project before deleting anything: prompts, tags/commits, traces, datasets, evaluators, experiments, feedback, and annotation queues.
2. Define the privacy allowlist and masking tests first.
3. Add one Intentive observability interface backed by Langfuse/OTel. Do not dual-deliver in production.
4. Replace LangSmith run IDs with provider-neutral trace IDs in internal metadata and operator links. Migrate every in-tree caller in the same change rather than adding compatibility aliases.
5. Recreate any live prompt in Langfuse with `{{variable}}` syntax, an immutable version, a `production` label, a 300-second cache policy, and the versioned repository fallback. Test both remote and fallback rendering.
6. Recreate only the datasets/evaluations/annotations that actually exist and remain useful. OTLP will not move them.
7. Verify a real Chat trace contains the correct hierarchy, model, prompt version, usage, retry/tool outcomes, and masked content.
8. Remove LangSmith env vars, status code, helpers, direct requirement pin,
   fields, tests, and secret/deployment wiring in the same cutover. The
   `langsmith` Python package may remain in the lockfile as a transitive
   LangChain dependency; that does not require a LangSmith account, key, or
   telemetry destination.

## Existing decision conflict

The technical answer does not override the repository's approved v1 requirements:

- IR-827 says to keep the current LangSmith lifecycle and explicitly says, “Do not replace LangSmith with Langfuse or add dual delivery for v1” ([IR-827](requirements-challenge.md#ir-827---langsmith-llm-tracing-observability-and-feedback)).
- IR-828 keeps Prompt Hub plus the repository fallback and says not to migrate that lifecycle to Langfuse for v1 ([IR-828](requirements-challenge.md#ir-828---langsmith-prompt-hub)).
- IR-832 keeps LangSmith website-side annotation, datasets, and evaluation ([IR-832](requirements-challenge.md#ir-832---langsmith-feedback-without-restoring-the-in-app-rating-product)).

Replacing LangSmith therefore requires an explicit product decision to reopen and supersede IR-827, IR-828, and IR-832, followed by synchronization of the owner/provider decisions and affected slice plans. This report intentionally does not edit those files.

Normal Chat is also presently an explicit `anthropic / claude-sonnet-4-6` workload, so the Gemini migration must update the workload inventory and its owning product/contract tests. It is a product model change, not cleanup of a dead compatibility field.

## Recommended order

1. **Reopen the provider decisions.** Approve one Gemini Chat provider/model evaluation and one Langfuse destination; supersede the explicit LangSmith v1 decisions.
2. **Cut over Langfuse before building LangSmith assets.** Inventory first, then implement one tracing/prompt/eval boundary and remove LangSmith in the same change. Do not create parallel production histories.
3. **Build a Gemini Chat contract spike.** Keep `/v2/chat/completions`; prove text streaming, tools, exact thought-signature continuation, safety/error mapping, cancellation, and usage through the installed Pi runtime.
4. **Run a controlled live quality evaluation.** Compare candidate Gemini model(s) with the current Claude route using the real system prompt and representative tool tasks. Select one explicit model.
5. **Implement the dedicated Gemini adapter.** Make the retry/stream transport provider-neutral, preserve server-side quota/usage ownership, use `store=false` if Interactions is selected, and keep the Mac journal authoritative.
6. **Activate the existing Gemini secret rather than creating another.** The earlier credential audit found an Intentive-owned restricted `GEMINI_API_KEY` in Secret Manager but no binding on the active Cloud Run revision ([provider credential audit](intentive-provider-credential-research.md#important-gemini-update)). Reverify that deployment state at implementation time.
7. **Exercise the real floating-bar path.** Verify normal text, image input, system-prompt change, tools, retry/error cases, and restart recovery in a named development bundle.
8. **Remove Anthropic last.** Delete the Anthropic client/dependency/secret/wiring and stale Sonnet identities only after the Gemini route has passed the real user-facing path. Keep OpenAI because its surviving workloads are independent.

## Final decision statement

**Gemini for normal typed/floating-bar Chat:** feasible and a sensible provider-consolidation candidate. Keep the Intentive OpenAI-shaped Chat contract and replace the backend's Anthropic adapter. Treat the existing Gemini proxy as evidence that credentials/routing exist, not as a reusable Chat transport. The migration is ready only after streamed tools preserve Gemini thought signatures, the retry/usage/safety contracts are explicit, and one Gemini model passes a real quality evaluation.

**Langfuse instead of LangSmith:** feasible and likely lower risk now than later because the checked-in LangSmith Chat/prompt helpers are not production-called. OpenTelemetry is a good common tracing foundation, but prompt management, datasets, evaluations, scores, annotations, and operator links require a deliberate migration. The current IR-827/828/832 prohibition must be explicitly superseded first.
