# Model Inventory

Last audited against the current checkout: 2026-09-01.

This is the repository-wide inventory of runtime AI/ML models used by the
Python backend and the macOS and Windows desktop applications. It includes
generative models, embeddings, realtime voice, speech-to-text, text-to-speech,
OCR, VAD, and local classifiers.

An **Omi endpoint** is the authenticated application boundary. An **upstream
endpoint** is the provider connection behind it. `None (local)` means the model
runs on the user's computer or inside the backend process without a separate
model API request.

Status meanings:

- **Active**: reachable from current production code.
- **Conditional**: active only after a feature gate, fallback, or review trigger.
- **Registered**: the endpoint is mounted, but it is not the primary path.
- **Declared, unused**: a model client or inventory entry exists without a
  production caller.
- **Mismatch**: current caller and backend contracts do not agree, so the model
  does not reach its provider.
- **Metadata only**: used to choose or label another model, not for inference.

## Architecture at a glance

The diagram below is the active macOS scope. Windows remains outside the macOS
roadmap and was neither inspected nor modified by this provider simplification.

```text
macOS desktop
    |-- Chat + structured compute ---------> Omi backend ---> Gemini Developer API
    |-- Gemini generation + embeddings ----> Omi proxy -----> Gemini Developer API
    |-- realtime token mint ---------------> Omi backend
    |                                         `-------------> direct Gemini Live WebSocket
    |-- Live failure after release --------> Modulate STT --> Gemini Chat --> OpenAI TTS
    |-- ambient/PTT cloud audio -----------> Omi STT -------> Modulate Velma-2
    `-- OCR, Parakeet, VAD, classifiers ----> local inference (no Omi model endpoint)
```

## Backend-managed generative workloads

These are the explicit workloads in
[`model_config.py`](backend/utils/llm/model_config.py). Purposes remain separate
even where they share a model.

| Status | Purpose | Provider | Model | Omi endpoint | Upstream endpoint / transport |
|---|---|---|---|---|---|
| Active | Main Chat, floating-bar typed answers, transcript-to-text answers, and the Pi agent/tool loop | Google | Gemini 3.7 Flash (`gemini-3.7-flash`) | `POST /v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse` | Native Gemini Developer API SSE; the backend injects its key and preserves Gemini content/tool/thought-signature bytes |
| Active | Initial Chat greeting | Google | Gemini 3.7 Flash (`gemini-3.7-flash`) | `POST /v2/chat/initial-message` | Gemini Developer API `:generateContent` |
| Active | Chat session title | Google | Gemini 2.5 Flash-Lite (`gemini-2.5-flash-lite`) | `POST /v2/chat/generate-title` | Gemini Developer API `:generateContent` |
| Active | Conversation discard/keep decision | Google | Gemini 3.7 Flash (`gemini-3.7-flash`) | `POST /v1/conversation-compute/discard` | Gemini Developer API `:generateContent` |
| Active | Conversation structure | Google | Gemini 3.7 Flash (`gemini-3.7-flash`) | `POST /v1/conversation-compute/structure` | Gemini Developer API `:generateContent` |
| Active | Conversation action-item candidates | Google | Gemini 3.7 Flash (`gemini-3.7-flash`) | `POST /v1/conversation-compute/action-items` | Gemini Developer API `:generateContent` |
| Active | Memory extraction | Google | Gemini 3.7 Flash (`gemini-3.7-flash`) | `POST /v1/memory/compute/extract` | Gemini Developer API `:generateContent` |
| Active | Memory assertion normalization | Google | Gemini 3.7 Flash (`gemini-3.7-flash`) | `POST /v1/memory/compute/normalize` | Gemini Developer API `:generateContent` |
| Active | Memory conflict/consolidation proposals | Google | Gemini 3.7 Flash (`gemini-3.7-flash`) | `POST /v1/memory/compute/consolidate` | Gemini Developer API `:generateContent` |
| Active | Translation of managed-STT transcript segments | Google | Gemini 2.5 Flash-Lite (`gemini-2.5-flash-lite`) | Runs inside `WebSocket /v4/listen` | Gemini Developer API `:generateContent` |
| Conditional | Fair-use review classification | Google | Gemini 3.7 Flash (`gemini-3.7-flash`), contract `gemini/gemini-3.7-flash:prompt-v2` | `POST /v1/fair-use/reviews/{review_id}/classify` | Gemini Developer API `:generateContent` |

## Desktop generative and vision workloads

| Status | Purpose | Desktop | Provider / model | Omi endpoint | Upstream endpoint / transport |
|---|---|---|---|---|---|
| Active | Focus, task extraction, memory extraction, insight generation, Live Notes, Home questions, goals, and screen synthesis; image-capable calls carry screenshots to the model | macOS and Windows, with feature-specific differences | Google Gemini 2.5 Flash (`gemini-2.5-flash`) | `POST /v1/proxy/gemini/models/gemini-2.5-flash:generateContent` | Gemini Developer API `POST /v1beta/models/gemini-2.5-flash:generateContent` |
| Active | Frequent proactive/live Suggestions | macOS | Google Gemini 2.5 Flash-Lite (`gemini-2.5-flash-lite`) | `POST /v1/proxy/gemini/models/gemini-2.5-flash-lite:generateContent` | Gemini Developer API `:generateContent` route |
| Declared, unused | PTT transcript cleanup helper | macOS | Google Gemini 2.5 Flash (`gemini-2.5-flash`) | Would use the normal Flash proxy route | The active PTT handoff explicitly skips this additional LLM call |
| Not re-audited | Windows AI Profile, calendar/Gmail/sticky-note/memory/KG synthesis, conversation topics, and local planner | Windows | Pre-existing Claude/Pi contracts | Outside this macOS-only change | Windows remains excluded from this audit; no compatibility claim is made |

The authenticated Gemini proxy only permits `generateContent`, `embedContent`,
and `batchEmbedContents` for Flash, Flash-Lite, and `gemini-embedding-001`.
All model inference uses the Gemini Developer API and the server-held
`GEMINI_API_KEY`; Cloud Run ADC remains for non-model GCP infrastructure.

## Embedding models

| Status | Purpose | Desktop | Provider / model | Omi endpoint | Upstream endpoint / transport |
|---|---|---|---|---|---|
| Active | Rewind OCR screenshot indexing/search; task and action-item similarity; conversation semantic recall; Memory semantic recall and lifecycle work | macOS and Windows | Google Gemini Embedding (`gemini-embedding-001`, 3072 dimensions by default) | `POST /v1/proxy/gemini/models/gemini-embedding-001:embedContent`<br>`POST /v1/proxy/gemini/models/gemini-embedding-001:batchEmbedContents` | Gemini Developer API `:embedContent` / `:batchEmbedContents` |

The Rewind chain the user noticed is therefore:

```text
screenshot -> local OCR text -> add app/window context
           -> gemini-embedding-001 -> normalized 3072-float vector
           -> local database -> cosine-similarity screen search
```

## Realtime voice models

| Status | Purpose | Provider / model | Omi endpoint(s) | Direct/upstream endpoint |
|---|---|---|---|---|
| Active macOS | Bidirectional speech, reasoning, tool choice, screen evidence, input/output transcription, and native audio reply | Google `gemini-3.1-flash-live-preview` | `POST /v2/realtime/session` mints one ephemeral token; `POST /v2/realtime/usage` records usage | macOS connects directly to `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained` |

Provider selection, OpenAI Realtime, the opaque omni relay, and the Artificial
Analysis Auto selector are deleted. A failed Gemini Live turn keeps its bounded
PCM and turn identity; after release it uses the managed Modulate batch-STT
route, Gemini Chat, and the unchanged OpenAI TTS route.

## Cloud speech-to-text and text-to-speech

| Status | Purpose | Provider / model | Omi endpoint(s) | Upstream endpoint |
|---|---|---|---|---|
| Active | Ambient cloud transcription, PTT streaming fallback, PTT/mobile batch transcription, and legacy voice-message SSE transcription | Modulate Velma-2; internal identifier `modulate-velma-2` | `WebSocket /v4/listen`<br>`WebSocket /v2/voice-message/transcribe-stream`<br>`POST /v2/voice-message/transcribe`<br>`POST /v2/voice-messages` | Streaming: `wss://platform.modulate.ai/api/velma-2-stt-streaming` or `wss://modulate-developer-apis.com/api/velma-2-stt-streaming`<br>Batch: `https://modulate-developer-apis.com/api/velma-2-stt-batch` |
| Active | Speaks text-chat answers; desktop falls back to an OS voice on failure | OpenAI `gpt-4o-mini-tts` | `POST /v1/tts/synthesize` | `POST https://api.openai.com/v1/audio/speech`, returning MP3 |

The realtime models' native audio generation is part of the realtime table, not
a second TTS endpoint.

## Local and bundled models

| Status | Host | Model / system | Purpose | Endpoint / model source |
|---|---|---|---|---|
| Active local | macOS Apple Silicon | FluidInference/NVIDIA `parakeet-tdt-0.6b-v2-coreml` | Primary English ambient STT, with separate microphone and system-audio lanes | None; FluidAudio downloads the Core ML weights from Hugging Face on first use and caches them |
| Active local | macOS Apple Silicon | FluidInference/NVIDIA `parakeet-tdt-0.6b-v3-coreml` | Non-English ambient STT and a separate PTT-language-identification decode | None; FluidAudio/Hugging Face download and local Core ML/Neural Engine inference |
| Active local | macOS | Silero VAD v5, bundled `silero_vad.onnx` | Ambient cloud-audio gate and PTT/realtime speech admission | None; bundled ONNX Runtime model |
| Active local | Backend | Silero VAD v6, tracked `backend/utils/stt/assets/silero_vad.onnx` | In-process speech gate before `/v4/listen` audio is sent to Modulate | Internal to `WebSocket /v4/listen` |
| Active local | Windows | Silero VAD v5, `silero_vad_v5.onnx` | Microphone/system-audio speech gate | Local `/vad/silero_vad_v5.onnx`, staged from `@ricky0123/vad-web`; a legacy asset is packaged defensively but the runtime loads v5 |
| Active local | Windows | MediaPipe YAMNet float32 v1, `yamnet.tflite` | Classifies VAD-passed loopback windows so music can be suppressed | Local `/vad/yamnet.tflite`; build tooling pins Google's MediaPipe model URL and SHA-256 |
| Active local | macOS | Apple Vision `VNRecognizeTextRequest` (`.accurate`, `en-US`; no public model ID) | Screenshot/Rewind OCR with text boxes and confidence | None; Apple Vision framework |
| Active local | Windows | Windows.Media.Ocr `OcrEngine` (user-profile language; no public model ID) | Screenshot/Rewind OCR with line boxes | None; supervised local `.NET` helper |
| Conditional local | Linux build of the Windows/Electron app | Tesseract CLI (installed model/language depends on the machine) | Protocol-compatible OCR fallback | None; local `tesseract ... stdout --psm 6` helper |
| Active local | macOS | Apple SoundAnalysis classifier `.version1` | Detects music/singing before Parakeet; fails open to transcription | None; `SNClassifySoundRequest` |
| Active local | macOS | Apple Natural Language recognizer (no public model ID) | Chooses a language from the user's set after local Parakeet PTT decoding | None; `NLLanguageRecognizer` |
| Active local fallback | macOS | Apple system speech voice (no fixed model ID) | TTS fallback when managed OpenAI speech fails | None; `AVSpeechSynthesizer` |
| Active local fallback | Windows | Chromium/OS system speech voice (no fixed model ID) | TTS fallback when managed OpenAI speech fails | None; Web Speech `SpeechSynthesisUtterance` |

## Aliases, selectors, and non-execution model strings

| Entry | Status | Meaning / endpoint |
|---|---|---|
| `gemini-3-flash-preview` | Compatibility alias | The Gemini proxy rewrites this incoming path segment to `gemini-2.5-flash` before allowlist validation. No current production caller was found. |
| `VITE_GEMINI_MODEL` | Bounded configuration input | Windows may override its default generation model, but the backend proxy still rejects anything outside Flash, Flash-Lite, and `gemini-embedding-001`. |

Deterministic dHash deduplication, cosine similarity, energy thresholds, and the
local silence/speech thresholds are algorithms, not models.

## Agent runtimes without one pinned provider model

The bundled Claude Code/ACP runtime can use a model selected by Claude Code or
the user; the Omi repository does not pin one provider model for that surface.
The macOS Pi runtime is different: it is pinned to the actual
`gemini-3.7-flash` model ID through the managed native Gemini route.
Hermes/OpenClaw-style external adapters likewise do not establish a new
fixed model in this repository merely by existing as adapters.

## Intentionally non-production entries

- Evaluation and integration scripts may name judge models; they are not product
  endpoints and are not counted as runtime traffic here.
- Old changelogs, generated clients, Windows parity notes, and bootstrap plans
  are not route authority.
- Retired surfaces include Perplexity/Sonar, ElevenLabs `/v2` TTS, Gemini Pro,
  streaming Gemini desktop-proxy routes, global premium/max/BYOK profiles, and
  the former application LLM gateway.

## Maintenance and sources of truth

This root document is intentionally broader than
[`model_endpoint_inventory.yaml`](backend/docs/llm/model_endpoint_inventory.yaml),
which covers managed LLM workloads plus selected adjacent surfaces but omits
active STT, TTS, local speech, OCR, VAD, and classifier models.

When a model or route changes, update this file and the owning source:

- Backend LLM ownership: [`model_config.py`](backend/utils/llm/model_config.py)
- Backend model inventory subset:
  [`model_endpoint_inventory.yaml`](backend/docs/llm/model_endpoint_inventory.yaml)
- Desktop Gemini proxy: [`desktop_proxy.py`](backend/routers/desktop_proxy.py)
- Desktop Chat allowlist: [`desktop_chat.py`](backend/routers/desktop_chat.py)
- Realtime token mint and usage: [`desktop_realtime.py`](backend/routers/desktop_realtime.py)
- Managed STT policy: [`stt_provider_policy.py`](backend/config/stt_provider_policy.py)
- Managed TTS: [`desktop_tts_updates.py`](backend/routers/desktop_tts_updates.py)
- macOS model constants: [`ModelQoS.swift`](desktop/macos/Desktop/Sources/ModelQoS.swift)
- macOS embeddings: [`EmbeddingService.swift`](desktop/macos/Desktop/Sources/ProactiveAssistants/Services/EmbeddingService.swift)
- macOS realtime model IDs: [`RealtimeHubSettings.swift`](desktop/macos/Desktop/Sources/FloatingControlBar/RealtimeHubSettings.swift)
- macOS local STT: [`LocalTranscriptionService.swift`](desktop/macos/Desktop/Sources/LocalTranscriptionService.swift)
- macOS OCR: [`RewindOCRService.swift`](desktop/macos/Desktop/Sources/Rewind/Core/RewindOCRService.swift)
- Windows Gemini transport: [`geminiClient.ts`](desktop/windows/src/renderer/src/lib/geminiClient.ts)
- Windows embeddings: [`embeddingClient.ts`](desktop/windows/src/main/rewind/embeddingClient.ts)
- Windows realtime IDs: [`tokenMint.ts`](desktop/windows/src/renderer/src/lib/voice/tokenMint.ts)
- Windows local VAD/YAMNet: [`vadModel.ts`](desktop/windows/src/renderer/src/lib/capture/vadModel.ts) and [`yamnetClassifier.ts`](desktop/windows/src/renderer/src/lib/capture/yamnetClassifier.ts)
- Windows OCR helper: [`Program.cs`](desktop/windows/src/main/ocr/win-ocr-helper/Program.cs)

The FastAPI routers named above are mounted in [`main.py`](backend/main.py).
