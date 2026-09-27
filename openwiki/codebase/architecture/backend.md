---
type: Codebase guide
title: Managed Python backend
description: Explain canonical app composition, route admission, executor boundaries and transient product compute.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-27T17:33:01.317Z
sources:
  - id: openwiki-source-fcffbe3e28749eaf9a39557c
    resource: repo://backend/main.py
  - id: openwiki-source-3d8afb7041d02c932bf3f465
    resource: repo://backend/routers/conversation_compute.py
  - id: openwiki-source-436c23d0e71e7e8c078ad9ef
    resource: repo://backend/routers/desktop_supervisor.py
  - id: openwiki-source-62abf112d5ded48560527143
    resource: repo://backend/routers/memory_compute.py
  - id: openwiki-source-068f72d8a1a874d1c411a1d0
    resource: repo://backend/services/desktop_inference.py
  - id: openwiki-source-5fe974b198877ecf775fae46
    resource: repo://backend/tests/unit/test_memory_compute.py
  - id: openwiki-source-acc64814c71f2ca88d2965f7
    resource: repo://backend/tests/unit/test_s26_canonical_backend_app.py
  - id: openwiki-source-01c563e69975269a5c47bffa
    resource: repo://backend/utils/observability/ai_evaluation.py
generated: { by: "codex", at: "2026-09-27T17:33:01.317Z" }
---
# Managed Python backend

The FastAPI application in `backend/main.py` is the common backend entrypoint. It mounts account/auth, transient conversation and Memory compute, speech, desktop model proxies, billing, fair-use, and update routes. Client-specific router names do not indicate independently deployed copies of the application.

## Request and state boundaries

A managed desktop request carries Firebase identity. Participant admission and endpoint rate limiting happen through the dependencies selected by each route. The route policy manifest records authentication expectations, while its inventory tests detect mismatches against the composed app. Account export/deletion has a different admission purpose from ordinary product compute; do not infer that participant exclusion removes account lifecycle access.

Conversation compute accepts bounded transcripts and a generation UUID and returns discard, structure, or action-item candidates. The Mac remains responsible for committing those results. Memory extract, normalize, and consolidate routes similarly return validated proposals. Invalid provider shapes become bounded `502` errors; routes log failure categories rather than dumping the supplied content.

The backend still owns retained account/subscription, usage, fair-use and update-control facts. “Transient compute” describes the product-content routes, not every backend database operation. Cloud Run, Firestore, Redis, Cloud Tasks and artifact storage have concrete roles in the deployment contract.

## Supervisor and evaluation intake

`POST /v1/supervisor/evaluate` authenticates a participant through the shared desktop admission gate and shares Gemini inference quotas with desktop background generation. The request contains a bounded observation, owner-independent session/observation IDs and context epoch. The authenticated owner scopes the deterministic decision ID; caller-supplied context never supplies authority.

Each valid evaluation makes one managed Gemini call and validates `wait`, `guide_next_turn` or `intervene` plus an optional private note. The server owns the model, schema and no-tools contract. Missing managed B instructions produce `wait` before inference; provider errors or invalid output degrade to `wait`. The route retains no product records and returns the selected prompt receipt with the decision.

`POST /v1/ai/observations` accepts typed terminal outcomes, decision examples and helpful/unhelpful scores under a separate bounded quota. Its export helper catches telemetry failures. Backend B traces always contain metadata; optional text arrives through the client's current consent boundary so an old evaluation cannot export text after local revocation. See [Supervisor conversation](../workflows/supervisor-conversation.md) and [telemetry](../integrations/telemetry.md).

## Extension and verification

Trace a route through its auth dependency, request/response model, compute helper and local client consumer before adding work. Blocking SDK operations belong in the existing executor boundary; async WebSocket tasks need supervised shutdown. The exact engineering requirements are in [Backend guidance](../../INSTRUCTIONS.md#backend-guidance).

The canonical-app tests verify router composition; Memory tests inject compute results and malformed proposals. Deployment claims require the [release workflow](../operations/releases.md), not just successful FastAPI import. Follow [capture](../workflows/capture-transcription.md), [Memory](../workflows/memory.md), and [account lifecycle](../workflows/account-lifecycle.md) for end-to-end boundaries.

## Source evidence

- [backend/main.py](../../../backend/main.py#L76-L119)
- [backend/tests/unit/test_s26_canonical_backend_app.py](../../../backend/tests/unit/test_s26_canonical_backend_app.py)
- [backend/routers/memory_compute.py](../../../backend/routers/memory_compute.py)
- [backend/tests/unit/test_memory_compute.py](../../../backend/tests/unit/test_memory_compute.py)
- [backend/routers/conversation_compute.py](../../../backend/routers/conversation_compute.py#L22-L137)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
