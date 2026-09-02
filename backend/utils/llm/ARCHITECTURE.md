# `backend/utils/llm`

This package owns explicit, transient managed-model workloads. The route authority is
`model_config.py`: every constructible workload names one provider/model, bounded input,
output contract, result owner, usage feature, failure policy, and lifecycle. Unknown keys
fail closed. Environment variables do not select a quality profile, provider, or gateway.

## Direct-provider core

- `model_config.py` — exhaustive workload contracts and provider-owned options.
- `clients.py` — lazy direct clients plus workload lookup, cache-key binding, output caps,
  shared embeddings, and structured parser primitives.
- `managed_stream_transport.py` — bounded direct Chat deadlines, pre-output transport retry,
  progress heartbeat, and cancellation cleanup.
- `providers.py` — small Gemini construction primitives.
- `provider_errors.py` — sanitized managed-provider failure reporting.
- `usage_tracker.py` — feature-level authoritative quota and usage accounting.

## Retained workload groups

- `conversation_processing.py` — transient discard, structure, and action-item candidates.
- `memory_compute.py` — transient Memory extraction, normalization, and conflict proposals.
- `fair_use_classifier.py` — S-20's pinned Gemini classification dependency.
- `temporal.py` and prompt/parser modules — deterministic prompt support only.

Joan follow-ups, automatic folder assignment, Wrapped, the application OpenRouter
binding, and the standalone routing service were deleted by S-23 and S-25.

## Conventions

- Add a workload contract before adding a managed-model call; do not add defaults,
  aliases, profile maps, customer-provider selection, or gateway fallback.
- Keep prompts and validation in the owning workload; only the local/product owner may
  commit a returned candidate.
- Construct clients lazily, bound inputs and output tokens, and never log raw prompts or
  provider responses.
- Bug fixes require behavioral coverage through the production workload seam.
