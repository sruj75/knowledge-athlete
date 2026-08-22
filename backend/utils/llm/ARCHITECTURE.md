# `backend/utils/llm`

This package owns explicit, transient managed-model workloads. The route authority is
`model_config.py`: every constructible workload names one provider/model, bounded input,
output contract, result owner, usage feature, failure policy, and lifecycle. Unknown keys
fail closed. Environment variables do not select a quality profile, provider, or gateway.

## Direct-provider core

- `model_config.py` — exhaustive workload contracts and provider-owned options.
- `clients.py` — lazy direct clients plus workload lookup, cache-key binding, output caps,
  shared embeddings, and structured parser primitives.
- `providers.py` — small OpenAI, Gemini, and OpenRouter construction primitives.
- `provider_errors.py` — sanitized managed-provider failure reporting.
- `usage_tracker.py` — feature-level authoritative quota and usage accounting.
- `vertex_auth.py` — shared bounded Vertex token refresh for the desktop Gemini proxy.

The standalone `backend/llm_gateway` deployment is not an application transport. Its
remaining repository topology is a callerless S-25 teardown handoff; do not add a caller
or import its auto-lane/config surface here.

## Retained workload groups

- `conversation_processing.py` — transient discard, structure, and action-item candidates.
- `memory_compute.py` — transient Memory extraction, normalization, and conflict proposals.
- `fair_use_classifier.py` — S-20's pinned direct OpenAI classification dependency.
- `followup.py` and `conversation_folder.py` — unresolved S-23-owned product bindings;
  S-22 cannot close while these remain executable.
- `wrapped/generate_2025.py` (outside this package) — the one permitted S-23 successor
  handoff and the sole OpenRouter workload.
- `temporal.py` and prompt/parser modules — deterministic prompt support only.

## Conventions

- Add a workload contract before adding a managed-model call; do not add defaults,
  aliases, profile maps, customer-provider selection, or gateway fallback.
- Keep prompts and validation in the owning workload; only the local/product owner may
  commit a returned candidate.
- Construct clients lazily, bound inputs and output tokens, and never log raw prompts or
  provider responses.
- Bug fixes require behavioral coverage through the production workload seam.
