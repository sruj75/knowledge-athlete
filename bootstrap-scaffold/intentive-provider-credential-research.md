# Intentive provider and credential research

**Status:** Superseded pre-migration audit. Subsequent implementation removed Anthropic, Artificial Analysis, LangSmith, provider selection, OpenAI text/realtime, and Calendar credentials; Gemini now owns managed text/embeddings/realtime voice, Langfuse owns tracing/prompt management, OpenAI is TTS-only, and Modulate batch STT remains retained but postponed. Use this report only for the historical caller evidence it captured.

**Audited commit:** `98ff1714b125b09b17d3ca741d090232be95901c`

**Audited on:** 2026-08-30

**Scope:** macOS and the canonical Python backend; Windows is excluded
**External changes made by this research:** none

## Plain-English answer

Do **not** copy every secret from Omi's deployment file.

Intentive really does retain OpenAI, Anthropic, Gemini, Modulate, PostHog,
LangSmith, and Artificial Analysis for specific first-release jobs. They are not
all needed to boot the server or test Google sign-in, and some should be
configured only when their owning slice is ready.

Intentive does **not** need a Google Calendar API key or the separately named
`DESKTOP_LEGACY_ANTHROPIC_KEY`. Those are live-looking leftovers in the current
deployment declaration. The current Mac cannot consume the legacy Anthropic
field, and the requirements explicitly delete external Google Calendar access.

The simplest safe order is:

1. finish the provider report and route decision first;
2. configure canonical Anthropic and OpenAI credentials;
3. configure one Gemini Developer API key and make the backend consistently use
   the intended Gemini route;
4. configure an owned PostHog project during S-30;
5. configure Modulate when the owner is ready to unpause managed cloud STT;
6. configure Artificial Analysis and LangSmith only after their current wiring
   gaps and privacy boundaries are closed;
7. leave Apple until membership is renewed; and
8. leave Dodo test/live credentials until the separately authorized post-Wave-6
   billing run.

No provider key belongs in Git. The repository itself says hosted credentials
must be exact Secret Manager references and public evidence must contain only
names, fingerprints, or version numbers, never secret bytes
([requirements, IR-846](requirements-challenge.md#L18519-L18527)).

## Read-only check of the interrupted Gemini setup

The earlier interrupted setup did make **partial external state**, but it did
not make Gemini available to the running app:

- Google Cloud contains an API key named `Intentive development Gemini`,
  restricted to the Gemini API;
- Secret Manager contains `GEMINI_API_KEY` version `1`;
- `knowledge-athlete-dev-runtime` has secret-level accessor permission; and
- the active Cloud Run revision `knowledge-athlete-dev-00002-pjn` has **no
  `GEMINI_API_KEY` environment/secret binding**. Its secret bindings remain
  Redis, Google OAuth, and Firebase only.

Therefore the key is currently **dormant**: the running backend cannot read or
use it. This research neither exposed its value nor changed/deleted the key,
secret, IAM grant, or Cloud Run revision. Leave this partial state unchanged
until the owner reviews the route decision in this report. Afterwards, either
adopt and verify this exact restricted key through the one-by-one Gemini step or
remove it as an explicit, separately authorized cleanup; do not create a second
Gemini key in the meantime.

## How the classifications work

| Classification | Meaning |
|---|---|
| **Already needed/configured infrastructure** | The current development path needs it and the S-30 execution refresh records it as configured. This audit did not read secret values. |
| **Required before a real Beta/S-31** | A retained user-facing path has a real caller and final provider qualification cannot pass without it. It may still be unnecessary for server health or Google sign-in today. |
| **Required later, but not ready to configure** | The requirements retain it, but the account is deliberately paused or the checked-in wiring is incomplete/inconsistent. |
| **Not needed; remove residue** | No surviving product behavior is allowed to use it. Do not create a placeholder secret merely to satisfy inherited YAML. |
| **Separate release/operations credential** | It may be needed, but it is not a managed AI/STT/telemetry provider decision and has a different owner. |

## Decision table

| Provider or credential | Decision | When | What breaks without it |
|---|---|---|---|
| `GOOGLE_CLIENT_ID` + `GOOGLE_CLIENT_SECRET` | **Keep** | Already needed/configured | Hosted Google sign-in cannot authorize or exchange the callback. |
| `FIREBASE_API_KEY` + Firebase project/runtime identity | **Keep** | Already needed/configured | Firebase custom-token sign-in exchange and authenticated desktop/backend requests fail. |
| Redis host/password/TLS configuration | **Keep** | Already needed/configured | OAuth single-use state, rate limits, and other correctness boundaries fail. Redis is infrastructure, not a model provider. |
| `OPENAI_API_KEY` | **Keep** | Before real Beta and S-31 provider proof | Conversation processing, Memory compute, greeting, fair-use classification, OpenAI Realtime, OpenAI relay, and managed TTS are unavailable. |
| canonical `ANTHROPIC_API_KEY` | **Keep** | Before real Beta and S-31 provider proof | Normal managed typed Chat through `/v2/chat/completions` is unavailable. |
| `GEMINI_API_KEY` | **Keep** | Before real Beta and S-31 provider proof | Gemini Live mint/relay, and—when AI Studio is selected—Gemini generation, translation, and embedding calls are unavailable. |
| Vertex AI through Cloud Run ADC | **Optional route, not a replacement for every Gemini caller** | Decide before configuring Gemini | It can serve selected generation/embedding paths, but the current realtime mint and relay still require `GEMINI_API_KEY`. |
| `MODULATE_API_KEY` | **Keep, deliberately postponed** | Before real managed-STT/Beta/S-31 proof | `/v4/listen`, completed-turn voice STT, and prerecorded managed transcription cannot use the retained cloud path. |
| owned PostHog project token/host | **Keep** | S-30, before shipping Beta | Product analytics and the backend's account-deletion operational event are skipped; the Mac currently points at an inherited token. |
| `LANGSMITH_API_KEY` + owned project/prompt name | **Retained, but do not configure yet** | After current caller/runtime gap is resolved; before final v1 acceptance if IR-827/828 remain | Current startup merely reports LangSmith status; the retained trace/Prompt Hub requirement is not fully connected to a production caller in this checkout. |
| `ARTIFICIALANALYSIS_API_KEY` | **Keep, lower priority** | Before final Auto-provider acceptance | Auto voice selection falls back to Gemini instead of refreshing the daily quality/speed choice. |
| `APPLE_CLIENT_ID`, team/key IDs, private key | **Keep, postponed** | After Apple membership is renewed | Hosted Apple sign-in cannot complete. Google sign-in remains usable. |
| `DODO_PAYMENTS_API_KEY`, webhook key, catalog | **Do not configure now** | Separately authorized after S-31 | Nothing in the free MVP: `BILLING_MODE=disabled` intentionally ignores them. |
| `GOOGLE_CALENDAR_API_KEY` / `DESKTOP_GOOGLE_CALENDAR_API_KEY` | **Do not create** | Remove from retained runtime declaration | No retained product path should break; external Calendar creation/connectors are deleted. |
| `DESKTOP_LEGACY_ANTHROPIC_KEY` | **Do not create** | Remove from route/deploy/workflow residue | No current Mac DTO or managed Pi runtime consumes it. Canonical server-side Anthropic continues through `ANTHROPIC_API_KEY`. |
| Deepgram, hosted Parakeet, OpenRouter, Perplexity, Groq, Hugging Face tokens | **Do not create** | Keep absent/remove residue | Their product/provider branches are deleted, absent, or only names in defensive secret-blocking code/templates. |
| Sentry DSN and symbol-upload token | **Keep; already owned/configured according to the current tree** | Release/observability owner | Crash ingestion or symbol upload fails. This is already separate from the provider work below. |
| GitHub release app/token, preview key, Beta promotion token, Sparkle/Apple signing credentials | **Keep, separate S-29 work** | Candidate/Beta/Stable release work | Release publication, qualification, promotion, signing, or updates fail; model calls are unaffected. |

## Caller-by-caller evidence

### 1. OpenAI — required

The explicit workload registry assigns these retained jobs to OpenAI:

- conversation action items and structure use `gpt-5.4-mini`;
- discard classification uses `gpt-4.1-nano`;
- the initial Chat greeting uses `gpt-5.4-mini`;
- fair-use classification uses `gpt-5.1`; and
- the three Memory proposal routes use `gpt-4.1-mini`.

That registry is executable configuration, not prose
([model_config.py](../backend/utils/llm/model_config.py#L62-L184)). The concrete
callers invoke it from conversation processing
([conversation_processing.py](../backend/utils/llm/conversation_processing.py#L139-L148),
[conversation_processing.py](../backend/utils/llm/conversation_processing.py#L388-L395),
[conversation_processing.py](../backend/utils/llm/conversation_processing.py#L545-L548)),
Chat greeting
([chat_sessions.py](../backend/routers/chat_sessions.py#L50-L82)), Memory compute
([memory_compute.py](../backend/utils/llm/memory_compute.py#L86-L104)), and the
fair-use route
([fair_use_classifier.py](../backend/utils/llm/fair_use_classifier.py#L154-L190)).

The same credential also has three retained voice callers:

- short-lived OpenAI Realtime client-secret minting
  ([desktop_realtime.py](../backend/routers/desktop_realtime.py#L116-L143));
- the authenticated OpenAI realtime WebSocket relay
  ([omni_relay.py](../backend/routers/omni_relay.py#L38-L52)); and
- managed OpenAI TTS
  ([desktop_tts_updates.py](../backend/routers/desktop_tts_updates.py#L198-L235)).

Therefore this is one canonical server credential, not a customer BYOK key. The
Mac tests explicitly prevent legacy customer OpenAI/Anthropic/Gemini keys from
affecting managed access
([ManagedAccessDecisionTests.swift](../desktop/macos/Desktop/Tests/ManagedAccessDecisionTests.swift#L6-L31)).

One nuance: `backend/utils/llm/clients.py` still defines an OpenAI embeddings
proxy, but no production caller invokes `generate_embedding` in this checkout
([clients.py](../backend/utils/llm/clients.py#L34-L58),
[clients.py](../backend/utils/llm/clients.py#L96-L105)). That dead helper is not
an extra credential requirement; the retained local semantic-search embedding
path is Gemini, described below.

**Conclusion:** create/configure one owned, budget-limited `OPENAI_API_KEY`
before real provider qualification. It is not necessary merely to boot the
backend or test Google sign-in.

### 2. Anthropic — canonical key required; legacy desktop key not required

Normal managed typed Chat is deliberately pinned to Anthropic Claude Sonnet:

- the explicit workload is `chat_agent -> anthropic -> claude-sonnet-4-6`
  ([model_config.py](../backend/utils/llm/model_config.py#L129-L139));
- `/v2/chat/completions` streams or creates messages through the managed
  Anthropic client
  ([desktop_chat.py](../backend/routers/desktop_chat.py#L282-L392),
  [desktop_chat.py](../backend/routers/desktop_chat.py#L415-L474)); and
- the client is constructed lazily and reads the canonical Anthropic SDK
  environment
  ([clients.py](../backend/utils/llm/clients.py#L15-L31)).

That makes canonical server-side `ANTHROPIC_API_KEY` required for the intended
Chat experience.

`DESKTOP_LEGACY_ANTHROPIC_KEY` is different. The backend still offers an
`anthropic_api_key` response field when that environment value exists
([desktop_core.py](../backend/routers/desktop_core.py#L29-L39)), but the current
Mac `ApiKeysResponse` has **no Anthropic property**
([APIClient+Account.swift](../desktop/macos/Desktop/Sources/Services/APIClient/APIClient+Account.swift#L78-L96)).
The regression test proves that an incoming `anthropic_api_key` field is ignored
([PiMonoWiringTests.swift](../desktop/macos/Desktop/Tests/PiMonoWiringTests.swift#L26-L39)),
and the managed Pi subprocess actively removes `ANTHROPIC_API_KEY` from its
environment before pointing itself at the backend
([AgentRuntimeProcess.swift](../desktop/macos/Desktop/Sources/Chat/AgentRuntimeProcess.swift#L2575-L2604)).

**Conclusion:** configure `ANTHROPIC_API_KEY`; do not create
`DESKTOP_LEGACY_ANTHROPIC_KEY`. Remove the legacy response/deploy/workflow
contract in its owning cleanup change instead of manufacturing a secret for a
consumer that does not exist.

### 3. Gemini and Vertex — Gemini is required, but the route policy needs one cleanup

Gemini owns several retained jobs:

- Chat title generation and live-transcript translation use
  `gemini-2.5-flash-lite`
  ([model_config.py](../backend/utils/llm/model_config.py#L107-L128));
- authenticated desktop generation and `gemini-embedding-001` requests use the
  canonical proxy
  ([desktop_proxy.py](../backend/routers/desktop_proxy.py#L21-L38),
  [EmbeddingService.swift](../desktop/macos/Desktop/Sources/ProactiveAssistants/Services/EmbeddingService.swift#L48-L88));
- Gemini Live mints a short-lived token using `GEMINI_API_KEY`
  ([desktop_realtime.py](../backend/routers/desktop_realtime.py#L144-L165)); and
- the Gemini relay places `GEMINI_API_KEY` on the provider WebSocket URL
  ([omni_relay.py](../backend/routers/omni_relay.py#L31-L52)).

The semantic-search decision explicitly keeps transient Gemini embeddings while
vectors and similarity search remain on the Mac
([requirements, IR-053](requirements-challenge.md#L22023-L22068)). Realtime voice
also deliberately retains both Gemini Live and OpenAI Realtime, including
cross-provider failover
([requirements, IR-061](requirements-challenge.md#L22886-L22917)).

There are two backend authentication paths for some non-realtime Gemini work:

1. **Vertex AI ADC.** `get_or_create_gemini_llm` chooses Vertex when
   `USE_VERTEX_AI=true` and `GOOGLE_CLOUD_PROJECT` exists
   ([providers.py](../backend/utils/llm/providers.py#L137-L181)). The desktop
   proxy can also obtain a Cloud Run service-account token and call Vertex
   ([desktop_proxy.py](../backend/routers/desktop_proxy.py#L108-L138)).
2. **Gemini Developer API / AI Studio.** The same clients use `GEMINI_API_KEY`
   when Vertex is not selected or available.

These are **not** complete substitutes in the present code. The realtime mint
and relay do not have a Vertex branch; they require `GEMINI_API_KEY` directly.
Also, the desktop proxy currently tries Vertex whenever
`GOOGLE_CLOUD_PROJECT` exists, without checking `USE_VERTEX_AI`, while the
LangChain workload client does check that flag. The checked-in runtime manifest
sets `USE_VERTEX_AI=true` and also binds `GEMINI_API_KEY`
([runtime_env.yaml](../backend/deploy/runtime_env.yaml#L175-L181),
[runtime_env.yaml](../backend/deploy/runtime_env.yaml#L220-L225)). That dual
binding is partly justified by the realtime callers, but the two proxy policies
still disagree.

**Recommended MVP direction:** use one owned, restricted Gemini Developer API
key as the required Gemini credential, keep Vertex disabled for the cost-safe
development path, and make every non-realtime caller honor that selection before
claiming the configuration is complete. Choosing Vertex later is allowed, but
it would be an additional route for selected workloads—not a way to eliminate
the Gemini API key while current Live mint/relay behavior remains.

**Conclusion:** Gemini is required. Do not blindly enable Vertex and create
roles merely because Omi's manifest mentions it. First align the route policy;
then configure and qualify `GEMINI_API_KEY` through the owned development
backend.

### 4. Modulate — genuinely retained, but deliberately postponed

Modulate is not leftover Omi configuration. The retained policy names it as the
only managed cloud STT adapter across streaming, prerecorded, and PTT surfaces
([stt_provider_policy.py](../backend/config/stt_provider_policy.py#L1-L16)).

The real callers read `MODULATE_API_KEY` and send audio to Modulate:

- streaming `/v4/listen` and voice-message STT
  ([streaming.py](../backend/utils/stt/streaming.py#L423-L454),
  [receiver.py](../backend/routers/listen/receiver.py#L21-L45)); and
- managed prerecorded transcription
  ([pre_recorded.py](../backend/utils/stt/pre_recorded.py#L75-L96)).

The runtime validator intentionally fails a retained Cloud Run declaration that
omits this binding
([validate-backend-runtime-env.py](../backend/scripts/validate-backend-runtime-env.py#L367-L397)).
The product decision is equally explicit: keep Modulate using our account and
truthful disclosure; delete hosted GPU Parakeet and Deepgram instead
([requirements, IR-887](requirements-challenge.md#L19133-L19147),
[deletion map, S-03](deletion-map.md#L617-L680)).

Mac-local Parakeet is a separate on-device path. It does not prove Intel/cloud
fallback, `/v4/listen`, or the S-31 managed-provider rows.

**Conclusion:** the user's instruction to skip Modulate means **postpone the
account/key setup**, not delete the dependency. It must return before real
managed-STT/Beta qualification unless the reviewed product decision is
explicitly reopened.

### 5. PostHog — retained and needs an owned project, but it is not a core-server blocker

The Mac has a large set of real product-event callers through
`AnalyticsManager`. Production initialization deliberately skips development
builds and forwards to `PostHogManager`
([AnalyticsManager.swift](../desktop/macos/Desktop/Sources/AnalyticsManager.swift#L61-L90)).
`PostHogManager` currently contains a hardcoded token and host, identifies the
signed-in Firebase user, and captures events
([PostHogManager.swift](../desktop/macos/Desktop/Sources/PostHogManager.swift#L6-L49),
[PostHogManager.swift](../desktop/macos/Desktop/Sources/PostHogManager.swift#L51-L110)).

The backend also has one retained, fail-open PostHog boundary for account
deletion operational events. If `POSTHOG_PROJECT_API_KEY` is absent, it disables
itself rather than breaking the deletion job
([posthog_telemetry.py](../backend/utils/posthog_telemetry.py#L16-L63),
[account_deletion.py](../backend/services/users/account_deletion.py#L1-L45)).

The product decision is to keep PostHog but move every event to an Intentive-owned
project
([requirements, IR-115](requirements-challenge.md#L22308-L22354)). S-30 also
requires the owned project/token/host and a truthful tracking disclosure before
that cycle can close
([S-30 G2](wave-6/s-30%20tdd.md#L169-L181),
[S-30 Cycle 5](wave-6/s-30%20tdd.md#L418-L434)).

**Conclusion:** create/configure one owned PostHog project during S-30. It is
not required for health, auth, Chat, or transcription to run, but shipping with
the inherited desktop token is not acceptable. Configuring only the backend
secret is insufficient; the Mac token/host and consent/disclosure owner must
move together.

### 6. Google Calendar — not needed

The requirements delete every external Calendar dependency relevant to this
credential:

- realtime external Calendar event creation is deleted under IR-106
  ([requirements index](requirements-challenge.md#L150-L152),
  [detailed decision](requirements-challenge.md#L17180-L17208));
- connector onboarding is deleted under IR-142;
- Calendar-enriched onboarding copy is deleted under IR-144; and
- linked external Google Calendar events are deleted under IR-375
  ([requirements index](requirements-challenge.md#L187-L189),
  [requirements index](requirements-challenge.md#L420-L420)).

The surviving "calendar commitments" are only candidate title/description/time
data stored with a local conversation. The decision explicitly forbids Google
Calendar, EventKit, OAuth, invitations, or external writes
([requirements, IR-357](requirements-challenge.md#L13389-L13409)).

What remains is compatibility residue:

- the backend may still return `google_calendar_api_key`
  ([desktop_core.py](../backend/routers/desktop_core.py#L29-L39));
- the Mac DTO/service still accepts and exports it to the process environment
  ([APIClient+Account.swift](../desktop/macos/Desktop/Sources/Services/APIClient/APIClient+Account.swift#L78-L96),
  [APIKeyService.swift](../desktop/macos/Desktop/Sources/APIKeyService.swift#L48-L74),
  [APIKeyService.swift](../desktop/macos/Desktop/Sources/APIKeyService.swift#L104-L132)); and
- the runtime declaration still asks for `DESKTOP_GOOGLE_CALENDAR_API_KEY`
  ([runtime_env.yaml](../backend/deploy/runtime_env.yaml#L235-L240)).

No surviving source caller uses that value to read or write Google Calendar.
The Chat startup comment that says it waits for "Firebase, Calendar" is stale;
the bridge uses backend-managed Chat and no Calendar key
([ChatProvider.swift](../desktop/macos/Desktop/Sources/Providers/ChatProvider.swift#L1459-L1474)).

**Conclusion:** do not create a Calendar API key or Calendar OAuth integration.
Delete the compatibility field/service wiring and its deploy/test variables in
the owning cleanup change.

This is separate from `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`, which are
required for **Google account sign-in**. Removing Calendar must not remove Google
sign-in.

### 7. LangSmith — retained by decision, but current production wiring is incomplete

The requirements retain LangSmith tracing, Prompt Hub, operator-side annotation,
and evaluation for v1 under an owned project
([requirements, IR-827/828](requirements-challenge.md#L18171-L18201),
[requirements, IR-832](requirements-challenge.md#L18265-L18277)).

The checkout still contains:

- environment/status helpers that recognize `LANGSMITH_API_KEY`, tracing,
  endpoint, and project
  ([langsmith.py](../backend/utils/observability/langsmith.py#L15-L95));
- tracer callback and current-run binding helpers
  ([langsmith.py](../backend/utils/observability/langsmith.py#L98-L160)); and
- Prompt Hub fetch/cache/fallback code
  ([langsmith_prompts.py](../backend/utils/observability/langsmith_prompts.py#L58-L177)).

However, the only non-test production caller found outside those modules is the
startup status log in `backend/main.py`. No current Chat/model caller invokes
`get_chat_tracer_callbacks`, `bind_current_langsmith_run`,
`get_agentic_system_prompt_template`, or `get_prompt_metadata`. The runtime
manifest also does not bind `LANGSMITH_API_KEY` or its project configuration.

That means two statements are simultaneously true:

1. product requirements say LangSmith remains in v1; and
2. adding a key today does not complete the retained scoped-tracing/Prompt Hub
   flow described by those requirements.

Global LangSmith environment tracing can also transmit model inputs/outputs, so
turning it on before S-30's fact-reviewed privacy matrix would be premature.

**Conclusion:** do not delete LangSmith, but do not ask the owner for a key yet.
First return the missing production caller/runtime integration to its owning
slice or explicitly revisit IR-827/828. Then configure the owned project and
truthful disclosure as one reviewed unit.

### 8. Artificial Analysis — retained for Auto, but safe to configure after the core model keys

The authenticated `/v1/auto/model-pick` route reads
`ARTIFICIALANALYSIS_API_KEY`, refreshes its quality/speed choice once per day,
and falls back to Gemini when no key or usable result exists
([auto_model.py](../backend/routers/auto_model.py#L15-L100)).

IR-600 explicitly retains that dependency and the Auto/Gemini/OpenAI picker
([requirements, IR-600](requirements-challenge.md#L22925-L22967)). S-31's physical
provider matrix requires Auto and failover behavior on the final SHA
([S-31 Cycle 13](wave-6/s-31%20tdd.md#L922-L947)).

But neither `backend/deploy/runtime_env.yaml` nor the current environment
templates declare this key. Missing it degrades to a deterministic Gemini pick,
so it does not block backend startup or manual Gemini/OpenAI selection.

**Conclusion:** it is a real retained credential, but lower priority than
OpenAI/Anthropic/Gemini/Modulate. Add its owned runtime binding and test it before
final Auto acceptance; do not let this secondary ranking API delay core model
provider setup.

### 9. Dodo — intentionally not needed now

The runtime is deliberately `BILLING_MODE=disabled` in both declared
environments
([runtime_env.yaml](../backend/deploy/runtime_env.yaml#L160-L166),
[runtime_env.yaml](../backend/deploy/runtime_env.yaml#L421-L427)). In disabled
mode the code returns before reading any Dodo key and constructs no billing
provider configuration
([billing/config.py](../backend/utils/billing/config.py#L51-L89)).

S-31 forbids creating or using Dodo test/live resources. Test setup happens only
after all six waves close, with a separate authorization; live mode then needs a
second authorization
([S-31 G4](wave-6/s-31%20tdd.md#L312-L319),
[Dodo handoff](dodo-integration.md#L1-L9)).

**Conclusion:** do not request `DODO_PAYMENTS_API_KEY`, webhook key, or catalog
now. Their absence is correct for the free MVP and does not keep S-31 open.

### 10. Apple sign-in — retained, but postponed with membership

The hosted auth route requires Apple client/team/key IDs and the Apple private
key to exchange the authorization code
([auth.py](../backend/routers/auth.py#L900-L928)). The retained hosted OAuth
decision includes Apple and Google under Intentive-owned configuration
([requirements, IR-171](requirements-challenge.md#L5336-L5393)).

The environment templates name these values, but the current Cloud Run runtime
manifest does not bind them. The S-30 execution refresh records Apple acceptance
as blocked on renewed membership and restored identifiers/capabilities
([S-30 execution refresh](wave-6/s-30%20tdd.md#L67-L70)).

**Conclusion:** Apple credentials are needed for Apple sign-in, but not for a
Google-only development or early Beta path. Keep the Firebase Apple provider as
it is; return to account membership, identifiers, private key, signing, and
notarization together later.

## Other inherited or adjacent credentials

### Do not provision these retired/unused provider keys

- **Deepgram:** deleted along with both managed compatibility and the self-hosted
  GKE product; the runtime validator treats `DEEPGRAM_API_KEY` as forbidden
  ([validator test](../backend/tests/unit/test_backend_runtime_env_validator.py#L772-L801)).
- **Hosted Parakeet:** the cloud GPU service is deleted; keep only Mac-local
  Parakeet and Modulate
  ([deletion map](deletion-map.md#L631-L680)).
- **OpenRouter and Perplexity:** the surviving model portfolio deletes their
  exclusive callers and secret wiring
  ([deletion map, S-22](deletion-map.md#L1332-L1362)).
- **Groq:** `GROQ_API_KEY` appears only in local-harness secret-blocking lists,
  not in a provider specification or production caller
  ([providers.py](../scripts/dev-harness/dev_harness/providers.py#L30-L36),
  [providers.py](../scripts/dev-harness/dev_harness/providers.py#L128-L195)).
- **Hugging Face:** `HUGGINGFACE_TOKEN` appears only as a blank entry in
  `.env.dev.template`; no production caller was found.
- **ElevenLabs:** the managed portfolio decision already classifies the remaining
  occurrence as callerless/deleted; retained TTS is OpenAI
  ([deletion map, S-22](deletion-map.md#L1340-L1354)).

### Keep these separate from the provider-key conversation

- `FIREBASE_API_KEY` is app/auth configuration, not an AI provider secret.
- Redis credentials are database/infrastructure credentials.
- Sentry's DSN is a public ingestion destination; `SENTRY_AUTH_TOKEN` is the
  private release-time symbol-upload credential. The current tree points to
  `heyintentive/desktop-macos`
  ([DesktopSentryConfiguration.swift](../desktop/macos/Desktop/Sources/Observability/DesktopSentryConfiguration.swift#L3-L10),
  [publish-desktop-debug-symbols.sh](../desktop/macos/scripts/publish-desktop-debug-symbols.sh#L1-L11)).
- `DESKTOP_PREVIEW_PUBLISH_KEY`, `BETA_PROMOTION_TOKEN`, GitHub release app/token,
  Sparkle private key, Developer ID certificate, and notarization credentials
  belong to S-29 release publication—not model-provider setup
  ([S-31 release gate](wave-6/s-31%20tdd.md#L321-L327)).
- `METRICS_SECRET` is an operational endpoint guard, not an external provider
  account.

## Deployment declaration gaps this audit found

The current `backend/deploy/runtime_env.yaml` is **not yet a clean list of only
the credentials Intentive needs**.

### False-positive declarations to remove

Both dev and prod still bind:

- `GOOGLE_CALENDAR_API_KEY`; and
- `DESKTOP_LEGACY_ANTHROPIC_KEY`.

The preflight tests also require version variables for both
([test_preflight_cloud_run_deploy.py](../backend/tests/unit/test_preflight_cloud_run_deploy.py#L15-L28)).
Removing these is therefore a coordinated source/manifest/workflow/test cleanup,
not merely omitting two secrets in Google Cloud.

### Retained dependencies missing from the declaration

- `ARTIFICIALANALYSIS_API_KEY` is retained by IR-600 but absent from the runtime
  manifest and templates.
- LangSmith project/tracing/key configuration is retained by IR-827/828 but
  absent from the runtime manifest, and its production caller chain is currently
  incomplete.
- Apple hosted OAuth configuration appears in templates and auth code but not in
  the runtime manifest; it is deliberately postponed.

### Mixed Gemini policy to resolve

- the explicit LLM client checks `USE_VERTEX_AI` before choosing Vertex;
- the desktop Gemini proxy checks only `GOOGLE_CLOUD_PROJECT`; and
- realtime Gemini always requires `GEMINI_API_KEY`.

Until those three facts are expressed as one deliberate policy, "Gemini is
configured" would be too broad a claim.

## What is needed now versus later

### Nothing more is needed merely to keep today's development health/auth path alive

The S-30 execution refresh records Firebase's Development/Beta/Stable apps,
Google Firebase Auth, the owned development Cloud Run revision, Firestore,
Upstash Redis, Firebase API key, and Google OAuth as present; health and the
Google authorize-to-provider boundary passed
([S-30 execution refresh](wave-6/s-30%20tdd.md#L57-L80)). This research did not
read secret values or repeat live provider calls.

### Needed to exercise the intended retained product before a real Beta

1. `ANTHROPIC_API_KEY` for managed typed Chat.
2. `OPENAI_API_KEY` for conversation/Memory/greeting/fair-use, OpenAI realtime,
   relay, and TTS.
3. `GEMINI_API_KEY` plus one consistent AI Studio/Vertex routing policy for
   titles, translation, proactive compute, embeddings, Gemini Live, and failover.
4. `MODULATE_API_KEY` when the current deliberate pause ends, for managed STT.
5. an owned PostHog project/token/host and S-30 privacy/consent reconciliation.
6. `ARTIFICIALANALYSIS_API_KEY` for the exact retained daily Auto behavior.
7. LangSmith only after its caller/runtime gap is resolved and its data boundary
   is approved.

S-31 makes the core non-production provider credentials explicit and leaves
missing credentials as open rows, not optional waivers
([S-31 G2](wave-6/s-31%20tdd.md#L286-L299)).

### Correctly postponed

- Apple membership, hosted Apple OAuth credentials, Developer ID signing, and
  notarization.
- Dodo test/live credentials and resources until the post-Wave-6 S-18 run.
- Beta/Stable/public release mutations until their separate explicit approvals.

### Never request for the current v1 plan

- Google Calendar API/OAuth access.
- `DESKTOP_LEGACY_ANTHROPIC_KEY`.
- Deepgram, hosted Parakeet, OpenRouter, Perplexity, Groq, Hugging Face, or
  ElevenLabs credentials.

## Recommended one-by-one configuration sequence

After this report is reviewed, use this order so each key has a small, testable
purpose:

1. **Anthropic:** configure the server key; exercise one authenticated typed Chat
   turn through `/v2/chat/completions`; confirm no key reaches the Mac process.
2. **OpenAI:** configure the server key; exercise one bounded stateless compute
   route, then the realtime mint and TTS error/success boundaries with strict
   spend limits.
3. **Gemini:** first make the AI Studio/Vertex selection consistent; then
   configure one restricted Gemini API key and exercise title/translation,
   embedding proxy, Gemini Live mint, and relay separately.
4. **PostHog:** create the owned project; move both desktop and backend
   destinations; verify dev suppression, identity detach, bounded properties,
   and the S-30 disclosure.
5. **Modulate:** only when the owner explicitly resumes it; configure the key and
   run one synthetic/local-QA streaming sample and one prerecorded sample without
   retaining audio in evidence.
6. **Artificial Analysis:** add the missing owned binding and verify the daily
   Auto pick plus no-key/provider-failure fallback.
7. **LangSmith:** only after reconnecting the retained caller and approving the
   trace/prompt data matrix; use a dedicated Intentive project and test the local
   prompt fallback.
8. **Apple and release credentials:** return after membership renewal.
9. **Dodo:** run only after S-31 closes and the separate test-mode authorization
   is given.

At each step, store secret values only in the provider's secret store and Google
Secret Manager/Codemagic protected groups as appropriate. Record only the secret
name, exact version, owner, and a redacted verification result in repository or
PR evidence.

## Final answer

The inherited Omi provider list contains **five core retained runtime providers**
for the intended Beta—OpenAI, Anthropic, Gemini, Modulate, and PostHog—but they
serve different jobs and should not be configured as one bulk operation.
LangSmith and Artificial Analysis are also retained, lower-priority dependencies
with current integration gaps. Google Calendar and the legacy desktop Anthropic
key are proven residue and must not be provisioned. Dodo and Apple are valid
future needs, but both are correctly postponed under the current launch plan.
