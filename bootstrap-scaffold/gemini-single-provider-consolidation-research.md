# Gemini Single-Provider Consolidation Research

**Status:** Superseded implementation research. The repository subsequently consolidated managed text, embeddings, and realtime voice on Gemini while retaining OpenAI only for TTS (`7251e6a5`, `f007efc1`). Modulate batch STT remains retained but postponed. Read the model alternatives below as historical analysis, not the current runtime declaration.

**Audited commit:** `98ff1714b125b09b17d3ca741d090232be95901c`

**Audited on:** 2026-09-01

**Question:** Can Intentive remove both managed Anthropic and managed OpenAI credentials and run every retained generative-AI workload through one paid Gemini API project and key?

**Source policy:** Current repository source plus official Google documentation only. The companion typed-Chat analysis is [Gemini Chat and Langfuse Migration Research](gemini-chat-langfuse-migration-research.md).

## Executive answer

**Yes for the retained generative-model workloads. No if “one key” literally includes the product's managed transcription provider and every development/CI integration.**

Intentive can make Google the only managed generative-model provider and remove the production `ANTHROPIC_API_KEY` and `OPENAI_API_KEY` after a contract-by-contract migration. A single paid **Gemini Developer API** project and one server-side Gemini **authorization key** can authorize the required Gemini model families:

- `gemini-3.7-flash` for normal typed/floating Chat and higher-risk classification;
- `gemini-3.5-flash-lite` as the low-cost candidate for greetings, conversation processing, Memory proposal computation, titles, and translation;
- `gemini-3.1-flash-live-preview` for realtime speech-to-speech;
- `gemini-3.1-flash-tts-preview` for selected-voice text-to-speech;
- the already integrated stable `gemini-embedding-001`, or a separately evaluated
  `gemini-embedding-2-preview`, for embeddings;
- `gemini-3.5-transcribe` / `gemini-3.5-transcribe-live` if Intentive later chooses to redesign managed transcription.

These are **several models behind one provider credential**, not several API keys. Google documents that every Gemini API key belongs to a Google Cloud project and that Gemini API rate limits are applied per project, not per key ([API-key guide](https://ai.google.dev/gemini-api/docs/api-key), [rate limits](https://ai.google.dev/gemini-api/docs/rate-limits)). Creating one key per model would not give each model an independent project quota.

The migration is not a model-name substitution. The current OpenAI key owns four different protocol families—ordinary LLM calls, realtime voice authentication, TTS, and some non-production tooling—while Anthropic owns the streaming Chat adapter. Each boundary must be migrated and verified before either provider secret is deleted.

My recommendation is:

1. standardize production generative AI on one paid Gemini Developer API project and one production authorization key;
2. keep a separate development key instead of reusing the production key on developer machines;
3. remove OpenAI as the realtime alternate and use `Gemini Live -> legacy cascade` as the voice recovery chain;
4. migrate the legacy cascade itself to Gemini Chat and either Gemini TTS or the existing macOS system voice;
5. retain Modulate until a separate transcription migration can preserve the continuous speaker-segment contract;
6. delete Anthropic/OpenAI runtime secrets only after the real typed Chat, PTT, Memory, conversation, fair-use, and selected-voice paths pass their provider gates.

That gives Intentive one generative-AI vendor, not one universal failure-independent service. An invalid Gemini key, project-wide quota exhaustion, or project billing problem would affect Chat, Live, TTS, titles, translation, embeddings, and compute together.

## First untangle “provider,” “model,” and “key”

The checked-out application does not use “two Anthropic models and one OpenAI model.” Its managed-model registry contains:

- one Anthropic model route: `claude-sonnet-4-6` for the Chat agent;
- several OpenAI model routes under the same `OPENAI_API_KEY`;
- several Gemini model routes under the Gemini/Google project boundary.

The authoritative registry shows the single Anthropic Chat route and eight OpenAI-backed bounded workloads ([model registry](../backend/utils/llm/model_config.py#L62-L184)). OpenAI realtime and OpenAI TTS are adjacent direct surfaces outside that registry.

The useful mental model is:

```text
provider/project       credential                  model + API surface
----------------       ----------                  -------------------
Google Gemini          one GEMINI_API_KEY    --->  Flash / Flash-Lite generateContent
                                               -->  Interactions or streaming Chat
                                               -->  Live API WebSocket + auth token mint
                                               -->  TTS generateContent/streaming
                                               -->  embedContent
                                               -->  Transcribe Interactions/Live
```

The key identifies and authorizes the project. The request chooses a model. Different models do not normally require different keys.

## Exact current inventory

### Production generative and voice surfaces

| Current workload | Current provider/model | Credential use | Exact Gemini replacement | Can the same Gemini Developer API key cover it? | Main gap before deletion |
|---|---|---|---|---|---|
| Normal typed/floating-bar Chat | Anthropic `claude-sonnet-4-6` | Backend Messages API stream | `gemini-3.7-flash` through a dedicated streaming Chat adapter | Yes | Preserve Pi's OpenAI-shaped SSE/tool contract and round-trip Gemini thought signatures exactly |
| Initial Chat greeting | OpenAI `gpt-5.4-mini` | Ordinary bounded generation | `gemini-3.5-flash-lite` candidate | Yes | Real output/latency evaluation; preserve 96-token and 500-character limits |
| Chat title | Gemini `gemini-2.5-flash-lite` | Already Gemini | Move deliberately to a supported stable Lite model such as `gemini-3.5-flash-lite` | Yes | Model-version evaluation only |
| Conversation discard | OpenAI `gpt-4.1-nano` | Small classification | `gemini-3.5-flash-lite` with a boolean/enum structured schema | Yes | Re-run keep-on-failure and short-conversation regression corpus |
| Conversation structure | OpenAI `gpt-5.4-mini` | Structured candidate generation | Start with `gemini-3.5-flash-lite`; promote to `gemini-3.7-flash` if the quality gate fails | Yes | Pydantic/date/category/one-grapheme output contract and transcript replay |
| Conversation action items | OpenAI `gpt-5.4-mini` | Structured candidate generation | Same Lite-first evaluation | Yes | Ownership, deduplication, due-date, and target-token behavioral evaluation |
| Memory extraction | OpenAI `gpt-4.1-mini` | Structured proposal generation | Same Lite-first evaluation | Yes | Grounding/evidence conservation; no mutation on invalid output |
| Memory normalization | OpenAI `gpt-4.1-mini` | Structured proposal generation | Same Lite-first evaluation | Yes | Preserve revision/provenance shape and retry semantics |
| Memory consolidation | OpenAI `gpt-4.1-mini` | Structured proposal generation | Same Lite-first evaluation | Yes | Preserve lifecycle conservation and relationship validation |
| Fair-use classification | OpenAI `gpt-5.1` | Frozen JSON classification contract | `gemini-3.7-flash` with structured output | Yes | This is an enforcement boundary: version a new classifier contract and re-baseline labeled evidence before changing it |
| Translation | Gemini `gemini-2.5-flash-lite` | Already Gemini | `gemini-3.5-flash-lite` candidate | Yes | Preserve cardinality and original-text-on-failure behavior |
| Desktop proactive generation | Gemini 2.5 Flash/Flash-Lite | Already Gemini through authenticated proxy | A deliberate supported Flash/Lite version | Yes | The current proxy allowlist must be updated; do not silently change output behavior |
| Desktop semantic embeddings | Gemini `gemini-embedding-001` | Already Gemini through authenticated proxy | Keep it initially, or separately evaluate `gemini-embedding-2-preview` and re-index | Yes | Embeddings from different models/spaces cannot be mixed; local vectors must be rebuilt for a model/dimension change |
| Realtime PTT speech-to-speech | Gemini Live primary/choice plus OpenAI `gpt-realtime-2` alternate | Provider-specific ephemeral token mint or relay | Gemini `gemini-3.1-flash-live-preview` only | Yes | Delete OpenAI picker/alternate logic; accept that Gemini Live is preview and no second-vendor recovery remains |
| Selected cloud voice / legacy-cascade TTS | OpenAI `gpt-4o-mini-tts`, MP3, OpenAI voice IDs | Direct backend `/v1/audio/speech` call | `gemini-3.1-flash-tts-preview`, or macOS `AVSpeechSynthesizer` | Yes for Gemini TTS; no cloud key for system voice | Gemini TTS is preview, uses different voice names/config, and returns 24 kHz PCM that must be wrapped/encoded for the current MP3/AVAudioPlayer/cache contract |
| Managed continuous and prerecorded transcription | Modulate Velma, not OpenAI or Anthropic | `MODULATE_API_KEY` | Possible future Gemini 3.5 Transcribe redesign | The Gemini key can call Transcribe, but it is not a drop-in replacement | Live Transcribe sessions are limited to 10 minutes and have no streaming speaker diarization; current product contract requires continuous stable speaker segments |

The model registry directly declares the OpenAI conversation, greeting, fair-use, and Memory routes and the Anthropic Chat route ([source](../backend/utils/llm/model_config.py#L62-L184)). Realtime and TTS are separately hard-coded in the direct routes ([realtime](../backend/routers/desktop_realtime.py#L21-L24), [TTS](../backend/routers/desktop_tts_updates.py#L20-L30)).

### Apparently retained OpenAI artifacts that are not production callers

Two inventory entries overstate the live OpenAI requirement:

- `utils/llm/clients.py` still constructs `text-embedding-3-large`, but a repository-wide production-source search finds no caller of `generate_embedding`; the Mac's live semantic path already uses Gemini embeddings ([callerless helper](../backend/utils/llm/clients.py#L34-L58), [construction](../backend/utils/llm/clients.py#L96-L105)). Delete this helper rather than migrate an unused path.
- `backend/docs/llm/model_endpoint_inventory.yaml` lists an OpenAI `gpt-4.1` `file_chat` surface, but current production source contains no `gpt-4.1` file-Chat call. Verify the owning file lifecycle once more during implementation and remove the stale inventory row if it remains callerless ([inventory](../backend/docs/llm/model_endpoint_inventory.yaml#L67-L87)).

### Non-production and out-of-scope OpenAI references

Deleting the managed runtime key is not the same as erasing every literal `OPENAI_API_KEY` in the repository:

- live/evaluation tests use OpenAI models as systems under test or judges; migrate or retire those before expecting a clean real-provider test environment;
- the manually dispatched Entelligence PR-review workflow passes a GitHub `OPENAI_API_KEY`; it must be replaced or retired separately ([workflow](../.github/workflows/entelligence-pr-reviewer.yml#L18-L27));
- hermetic tests intentionally contain fake provider-key names and values; these are contract fixtures, not credentials;
- Windows Codex integration can inject a **user-supplied** OpenAI credential into a local Codex subprocess. That is not Intentive's managed AI provider key and should not be silently removed as part of the Mac/backend provider migration.

## Why ordinary Flash can replace the OpenAI bounded workloads

The OpenAI-backed greeting, conversation, Memory, and fair-use surfaces are all bounded text-in/candidate-out computation. They do not depend on an OpenAI-hosted conversation database or an OpenAI-only tool runtime. Their durable authorities remain on the Mac.

Gemini supports structured output from a supplied JSON Schema, including objects, arrays, enums, numeric constraints, required fields, and `additionalProperties` ([structured-output guide](https://ai.google.dev/gemini-api/docs/structured-output)). That matches the repository's candidate-validation approach: generate a candidate, parse it, validate it with Pydantic, and commit only if the local owner still accepts it.

This makes a stable Flash-Lite model a reasonable **candidate** for:

- the greeting;
- discard classification;
- conversation structure and action-item candidates;
- Memory extract/normalize/consolidate proposals;
- titles and translation.

It is not evidence that the cheapest Lite model will meet every quality boundary. Conversation action ownership, grounded Memory conservation, and multilingual structure are behavioral contracts. The migration should replay representative approved inputs and validate the existing route response models, not accept “valid JSON” as proof of equivalent behavior.

Use `gemini-3.7-flash` for typed Chat and initially for fair-use classification because Google lists it as a GA, production-ready model for reliable agentic and multi-step execution with a 1M-token context window and function calling ([3.7 Flash guide](https://ai.google.dev/gemini-api/docs/latest-model), [function calling](https://ai.google.dev/gemini-api/docs/function-calling)). Google lists `gemini-3.5-flash-lite` as a stable, cost-effective high-throughput model ([model catalog](https://ai.google.dev/gemini-api/docs/models)).

The exact model choice remains a product evaluation result, not an API-key decision.

## Why typed Chat needs an adapter, not just a Flash model name

The floating bar does not call Anthropic directly. Pi speaks Intentive's authenticated OpenAI-shaped `/v2/chat/completions` contract; the backend translates it to Anthropic and translates the stream back. Therefore the UI and Pi loop can remain while the backend provider adapter changes.

Gemini supports text/image input, streaming, function calls, tool results, and parallel/sequential tools. The difficult difference is continuation metadata: Gemini 3 function calls include thought signatures that must be returned exactly in the subsequent tool round. The complete compatibility and evaluation boundary is documented in the companion [Chat migration report](gemini-chat-langfuse-migration-research.md#tool-use-is-compatible-with-one-critical-opaque-field).

For this route, use one of:

- native `streamGenerateContent`, translating native Gemini stream events into the current Pi-facing SSE contract; or
- the Interactions API in stateless mode with `store=false`, resending the exact history including model-generated thought/function steps.

Google's Interactions function-calling guide requires full model steps to be preserved exactly in stateless mode ([official function-calling guide](https://ai.google.dev/gemini-api/docs/function-calling)). Ordinary non-streaming `generateContent` through the existing desktop proxy cannot serve the current long-lived Chat contract.

## Realtime voice: yes, remove the OpenAI alternate deliberately

The Mac already implements Gemini Live. It already mints a short-lived Gemini token from `GEMINI_API_KEY`, and it already knows how to open a Gemini native-audio session. OpenAI is currently not merely a “fallback model” in the abstract; it is encoded as the alternate provider:

```text
Auto/user primary (often Gemini)
        -> the other realtime provider (OpenAI)
        -> legacy STT + Chat + selected TTS cascade
```

The provider enum explicitly exposes Gemini and GPT Realtime ([settings](../desktop/macos/Desktop/Sources/RealtimeOmni/RealtimeOmniSettings.swift#L15-L46)), and `RealtimeHubProvider.alternate` swaps Gemini and OpenAI ([hub settings](../desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubSettings.swift#L17-L52)). The controller then tries the alternate before the legacy cascade ([failover](../desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubController.swift#L691-L723)).

If Intentive chooses single-provider simplicity, change the contract to:

```text
Gemini 3.1 Flash Live
        -> legacy Modulate STT + Gemini Chat + Gemini TTS/system voice
        -> truthful failure
```

That is reasonable. It removes OpenAI model selection, OpenAI ephemeral-token minting, OpenAI relay support, OpenAI-specific sample-rate/protocol branches, and the Artificial Analysis provider choice if there is no second candidate to select.

The same Gemini Developer API key can mint Live ephemeral tokens and call the Live API. Google documents that the backend creates a short-lived token using `GEMINI_API_KEY`, and that the token is restricted to Live API/WebSocket use ([ephemeral-token guide](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens)). The long-lived key must remain server-side.

The tradeoff is real: the current UI calls OpenAI Realtime GA while Gemini 3.1 Flash Live is preview. More importantly, provider diversity disappears. A Gemini Live model-specific outage may still recover through ordinary Gemini generation, but an invalid shared key, project billing failure, project-wide quota failure, or broader Gemini outage can also break the legacy cascade.

## TTS: replaceable, but currently the least mature production substitution

The current `/v1/tts/synthesize` route guarantees:

- OpenAI `gpt-4o-mini-tts`;
- a fixed set of OpenAI voice identifiers;
- optional natural-language instructions;
- an `audio/mpeg` response;
- retry, entitlement, burst, and daily-character policies.

The current voice picker is not provider-neutral: all four configured choices—Onyx, Shimmer, Coral, and Nova—are explicitly OpenAI voices, and Shimmer is the default ([picker source](../desktop/macos/Desktop/Sources/FloatingControlBar/ShortcutSettings.swift#L443-L527)). The macOS system voice exists as an error fallback inside playback, not as one of those four configured cloud-voice choices.

The Mac stores some generated acknowledgements under `.mp3` names and feeds returned bytes to `AVAudioPlayer` ([playback route](../desktop/macos/Desktop/Sources/FloatingControlBar/FloatingBarVoicePlaybackService.swift#L221-L285), [backend call](../desktop/macos/Desktop/Sources/FloatingControlBar/FloatingBarVoicePlaybackService.swift#L829-L859)).

Gemini TTS can generate controllable single- or multi-speaker speech with style, accent, pace, and tone instructions. `gemini-3.1-flash-tts-preview` now supports streaming, but the TTS family remains preview ([speech-generation guide](https://ai.google.dev/gemini-api/docs/speech-generation), [release note](https://ai.google.dev/gemini-api/docs/changelog)). Google's example returns 24 kHz, mono, 16-bit PCM and wraps it as WAV. Therefore a backend migration must either:

1. map product voice choices to Gemini voice names, wrap/encode the PCM as WAV/MP3, keep the present response contract, and version the cache; or
2. change the route/client media contract and teach playback to consume PCM/WAV; or
3. retire cloud-selected voices and use the existing macOS `AVSpeechSynthesizer` fallback, which removes the TTS cloud dependency but changes voice quality/consistency.

Do not continue presenting OpenAI voice IDs after the provider changes. Do not label raw PCM as `audio/mpeg`.

## Transcription determines whether “one provider” is literal

Neither the Anthropic key nor the OpenAI key currently owns managed transcription. Continuous `/v4/listen`, PTT cascade transcription, and prerecorded voice-message transcription use Modulate. Deleting OpenAI and Anthropic therefore still leaves `MODULATE_API_KEY`.

Google now offers stable `gemini-3.5-transcribe` and a Live counterpart. The Gemini Developer API key can authenticate those calls. The official prerecorded API supports language detection, diarization, word timestamps, and custom vocabulary ([Transcribe guide](https://ai.google.dev/gemini-api/docs/transcribe)).

It is not a drop-in replacement for the present continuous product contract. Google's Live Transcribe documentation states:

- continuous streaming sessions last up to 10 minutes;
- speaker diarization is not supported in live streaming;
- word-level timestamps are not supported live (only utterance-level timestamps);
- raw audio input is 16-bit PCM ([Live Transcribe guide](https://ai.google.dev/gemini-api/docs/live-api/live-transcribe)).

Intentive's current product contract expects one long-running authenticated socket, continuous canonical segments, ordered vocabulary, and numeric speaker labels. Replacing Modulate requires an explicit rollover/stitching and speaker-identity design or a product-contract change. It should not be bundled into the Anthropic/OpenAI key cleanup.

So there are two honest outcomes:

- **One generative-AI provider:** Gemini for Chat, compute, Live, TTS, translation, and embeddings; Modulate remains specialized STT. This is feasible now.
- **One AI provider credential total:** Gemini also replaces Modulate. This is not currently behavior-preserving without a larger transcription redesign.

## One Developer API key versus Vertex AI

The repository currently contains two different Google call styles:

1. the desktop proxy, Gemini Live token mint, and relay directly call the Gemini Developer API using `GEMINI_API_KEY` ([proxy](../backend/routers/desktop_proxy.py#L113-L138), [realtime mint](../backend/routers/desktop_realtime.py#L145-L163), [relay](../backend/routers/omni_relay.py#L38-L50));
2. the shared LangChain Gemini constructor prefers Vertex AI whenever `USE_VERTEX_AI=true` and `GOOGLE_CLOUD_PROJECT` is set, only falling back to `GEMINI_API_KEY` otherwise ([constructor](../backend/utils/llm/providers.py#L137-L181)).

The checked-in dev and prod runtime declarations set `USE_VERTEX_AI=true` and also bind `GEMINI_API_KEY` ([dev](../backend/deploy/runtime_env.yaml#L172-L230), [prod](../backend/deploy/runtime_env.yaml#L407-L463)). That is one Google project boundary but two authentication paths: Cloud Run ADC/service-account identity for Vertex calls and the API key for direct Gemini Developer API calls.

Google treats the Gemini Developer API and Vertex/Enterprise API as distinct products behind the same unified SDK. Google recommends the Developer API for most developers; moving to the enterprise/Vertex route uses Google Cloud service-account authentication and may have different regional/model availability ([official comparison](https://ai.google.dev/gemini-api/docs/migrate-to-cloud)).

If the requirement is specifically **one Gemini API key for every generative workload**, standardize on the Gemini Developer API:

- stop preferring Vertex for these model calls;
- construct one official Google GenAI client from `GEMINI_API_KEY`;
- use the appropriate Gemini endpoint per workload;
- keep Cloud Run's service-account/ADC identity for Firestore, Secret Manager, Tasks, and other Google Cloud infrastructure. ADC is not another AI API key.

Do not assume that setting `USE_VERTEX_AI=true` still means calls consume the Gemini Developer API key. In the present constructor it explicitly causes the project/location Vertex branch to win.

## Does one key actually cover every Gemini surface?

For the Gemini **Developer API**, yes, subject to the project's paid tier, model availability, and quotas:

| API surface | Model examples | Credential presented by the backend |
|---|---|---|
| `generateContent` / `streamGenerateContent` | Flash, Flash-Lite, TTS | `GEMINI_API_KEY` |
| Interactions API | Chat, structured work, TTS, prerecorded Transcribe | `GEMINI_API_KEY` |
| `embedContent` / batch embeddings | `gemini-embedding-001`, `gemini-embedding-2-preview` | `GEMINI_API_KEY` |
| Live auth-token provisioning | Gemini Live | `GEMINI_API_KEY`; produces a short-lived client token |
| Live WebSocket | Gemini Live or Live Transcribe | short-lived token minted from that key, or the server-side key on the relay |

Google's API reference says Gemini API requests include the API key, and its key documentation covers the project association and server-side environment variable ([API reference](https://ai.google.dev/api), [API-key guide](https://ai.google.dev/gemini-api/docs/api-key)). No model-specific key is required.

However, one key does not create independent failure or quota domains. Google applies limits per project. Multiple keys in the same project share quota, so creating extra keys would help rotation/attribution but not capacity isolation ([rate limits](https://ai.google.dev/gemini-api/docs/rate-limits)).

## Key type and environment recommendation

Google is transitioning the Gemini API from standard API keys to service-account-bound authorization keys. Its current documentation says new AI Studio keys are authorization keys and that standard keys will be rejected in September 2026 ([API-key guide](https://ai.google.dev/gemini-api/docs/api-key)). Because this audit date is September 1, 2026, “reuse the existing restricted key” is safe only after verifying its **key type**, not merely that it has an API restriction.

Recommended credential shape:

```text
Intentive production Gemini project
  -> one paid, Generative-Language-only authorization key
  -> Secret Manager GEMINI_API_KEY
  -> all production Gemini model/API surfaces

Intentive development Gemini project (or at minimum a separate dev key)
  -> separate authorization key
  -> development only
```

A literally shared dev-and-prod key is technically possible but not reasonable. Local leakage, accidental load, rotation, or quota use would affect production. This still reduces the production provider secrets from three (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`) to one without making developer machines production principals.

If the dormant existing key is a standard key, create exactly one replacement authorization key, cut over, verify, and then revoke the old key. Do not create separate keys for Flash, Live, TTS, and embeddings.

## What must change before the two provider secrets can be deleted

### Anthropic removal gate

- replace the Anthropic request/stream translator behind `/v2/chat/completions`;
- preserve tool calls, tool results, images, usage, cancellations, deadlines, retries, and Gemini thought signatures;
- rename `omi-sonnet` and any Sonnet/Anthropic-facing model identity truthfully;
- pass real floating-bar text, image, sequential-tool, parallel-tool, cancellation, retry, and long-context paths;
- remove the Anthropic SDK/direct client only after no production import remains;
- remove `ANTHROPIC_API_KEY`, `DESKTOP_ANTHROPIC_API_KEY`, and the already-dead legacy Anthropic secret wiring from manifests/workflows/templates.

### OpenAI removal gate

- change all eight managed registry workloads from OpenAI to explicitly evaluated Gemini models;
- version and re-baseline the fair-use classifier contract (`openai/gpt-5.1:prompt-v2` is embedded in backend and Swift acceptance logic today);
- remove `.openai`/`gptRealtime2` from realtime settings, mint, relay, provider failover, diagnostics, model selection, and tests;
- replace or retire the OpenAI TTS route, voice choices, cache namespace, and MP3 assumptions;
- delete the callerless OpenAI embeddings helper and verify/remove the stale file-Chat inventory row;
- migrate or retire OpenAI-backed live evals and the manually dispatched Entelligence workflow;
- update runtime/env/deploy validation so `OPENAI_API_KEY_VERSION` is no longer required;
- only then remove the OpenAI secret/version variables from development and production deployment wiring.

### Single-Gemini reliability gate

- one provider-neutral model registry must name every model and failure policy;
- model-specific quota and usage accounting must map Gemini input, output, cached, thinking, and audio tokens correctly;
- project-wide auth/quota failures must produce one truthful account-wide state instead of attempting another Gemini endpoint as if it were independent;
- Live-specific failure may recover through the Gemini legacy cascade, but the UI must not claim that is provider redundancy;
- retain local/system fallbacks that remain truthful: `New Chat`, original untranslated text, no Memory mutation, keep-on-discard failure, macOS system speech, and explicit voice failure.

## Decision

It is reasonable to remove both managed Anthropic and managed OpenAI from Intentive.

The clean target is:

```text
one production Gemini Developer API project
one production Gemini authorization key

Gemini 3.7 Flash       -> typed/floating Chat + fair-use candidate
Gemini 3.5 Flash-Lite  -> bounded low-cost structured/text jobs
Gemini 3.1 Flash Live  -> realtime speech-to-speech
Gemini 3.1 Flash TTS   -> selected cloud voice, if preview risk is accepted
Gemini Embedding       -> local semantic vectors

Modulate               -> managed STT, retained until a separate contract-preserving migration
macOS local authority  -> all durable product state and truthful local fallbacks
```

Do not describe this as “use Flash instead of the OpenAI and Anthropic keys.” Describe it as **one Gemini provider credential serving several deliberately selected Gemini models and API surfaces**.

This consolidation reduces vendor operations, billing accounts, secret rotation, and cross-provider adapters. It also concentrates auth, quota, billing, model-family, and outage risk in one Google project. That is a reasonable startup tradeoff if Intentive explicitly accepts it and keeps product-owned failure behavior; it is not free redundancy.
