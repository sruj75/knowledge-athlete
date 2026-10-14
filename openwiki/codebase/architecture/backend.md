---
type: Codebase guide
title: Managed Python backend
description: Explain canonical app composition, route admission, executor boundaries and transient product compute.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-10-14T14:40:28.560Z
sources:
  - id: openwiki-source-fcffbe3e28749eaf9a39557c
    resource: repo://backend/main.py
  - id: openwiki-source-7646818ba161efdbdeee5234
    resource: repo://backend/models/desktop_conversation.py
  - id: openwiki-source-3d8afb7041d02c932bf3f465
    resource: repo://backend/routers/conversation_compute.py
  - id: openwiki-source-477ee7f176f7957c006c22b7
    resource: repo://backend/routers/desktop_conversation.py
  - id: openwiki-source-436c23d0e71e7e8c078ad9ef
    resource: repo://backend/routers/desktop_supervisor.py
  - id: openwiki-source-62abf112d5ded48560527143
    resource: repo://backend/routers/memory_compute.py
  - id: openwiki-source-068f72d8a1a874d1c411a1d0
    resource: repo://backend/services/desktop_inference.py
  - id: openwiki-source-5fe974b198877ecf775fae46
    resource: repo://backend/tests/unit/test_memory_compute.py
  - id: openwiki-source-01c563e69975269a5c47bffa
    resource: repo://backend/utils/observability/ai_evaluation.py
  - id: openwiki-source-e0e1aceea6bbd06a72738ece
    resource: repo://desktop/macos/Desktop/Sources/ProactiveAssistants/Supervisor/SupervisorService.swift
generated: { by: "codex", at: "2026-10-14T14:40:28.560Z" }
---
# Managed Python backend

The FastAPI application in `backend/main.py` is the common backend entrypoint. It mounts account/auth, transient conversation and Memory compute, speech, desktop model proxies, billing, fair-use, and update routes. Client-specific router names do not indicate independently deployed copies of the application.

## Request and state boundaries

A managed desktop request carries Firebase identity. Participant admission and endpoint rate limiting happen through the dependencies selected by each route. The route policy manifest records authentication expectations, while its inventory tests detect mismatches against the composed app. Account export/deletion has a different admission purpose from ordinary product compute; do not infer that participant exclusion removes account lifecycle access.

Conversation compute accepts bounded transcripts and a generation UUID and returns discard or structure candidates. The Mac remains responsible for committing those results. Memory extract, normalize, and consolidate routes similarly return validated proposals. Invalid provider shapes become bounded `502` errors; routes log failure categories rather than dumping the supplied content.

The backend still owns retained account/subscription, usage, fair-use and update-control facts. “Transient compute” describes the product-content routes, not every backend database operation. Cloud Run, Firestore, Redis, Cloud Tasks and artifact storage have concrete roles in the deployment contract.

## Direct conversational A

`POST /v1/conversation/session` resolves A's immutable prompt receipt before a Live connection is attempted. `POST /v1/conversation/respond` accepts bounded dialogue, current input, permitted context, private guidance and correlation IDs. The server resolves the receipt's exact version/hash and constructs the system instruction; clients cannot supply system policy or tool definitions. `/v2/realtime/session` accepts the same receipt. A creation-time repository fallback is versioned and tool-free.

The direct stream emits `text_delta`, then `done` with usage/model metadata and the optional fixed `end_conversation` signal. Unsupported functions, partial provider failure or incomplete streams produce a bounded error rather than a successful terminal reply or automatic replay. The desktop owns durable acceptance and final playback. No route restores Pi or a general execution loop.

Both A and B reject bodies above 4 MB. B retains the 2 MB decoded screen limit and separately bounded camera input. Its burst and daily counters are independent of other workloads; hosted daily admission remains 1,500. Only explicit dev/local configuration can select the 6,000-request development allowance. Quota failures return a retry time rather than inviting an immediate retry loop.

## Supervisor and evaluation intake

`POST /v1/supervisor/evaluate` authenticates a participant through the shared desktop admission gate and uses a separate Supervisor quota ledger. The request contains separately identified screen/webcam images, availability and capture times, bounded transcript revisions, conversation state, owner-independent session/observation IDs and context epoch. The authenticated owner scopes the deterministic decision ID; caller-supplied context never supplies authority.

Each valid evaluation makes one managed Gemini call and validates `wait`, `guide_next_turn` or `intervene` plus an optional private note. The server owns the model, schema and no-tools contract. Missing managed B instructions produce `wait` before inference; invalid provider output returns `wait` with a degraded outcome. The route retains no product records and returns the selected prompt receipt with accepted decisions.

Provider HTTP and transport failures record a correlated degraded observation before returning a safe HTTP error. Upstream rate limiting remains `429`; provider authentication, billing and server failures become `503`, other rejected requests become `502`, and transport failures become `503`. Fixed error text and bounded fallback reasons exclude provider bodies, credentials and observation content. The Mac enters a visible degraded state and respects the permitted retry time, without mistaking provider authentication or billing for Firebase session failure or an expired desktop trial.

`POST /v1/ai/observations` accepts typed terminal outcomes, decision examples and helpful/unhelpful scores under a separate bounded quota. Its export helper catches telemetry failures. Backend B traces always contain metadata; optional text arrives through the client's current consent boundary so an old evaluation cannot export text after local revocation. See [Supervisor conversation](../workflows/supervisor-conversation.md) and [telemetry](../integrations/telemetry.md).

## Extension and verification

Trace a route through its auth dependency, request/response model, compute helper and local client consumer before adding work. Blocking SDK operations belong in the existing executor boundary; async WebSocket tasks need supervised shutdown. The exact engineering requirements are in [Backend guidance](../../INSTRUCTIONS.md#backend-guidance).

The canonical-app tests verify router composition; Memory tests inject compute results and malformed proposals. Supervisor endpoint tests exercise upstream status and transport failures, one-call admission, preserved prompt/observation correlation and private-content exclusion. Deployment claims require the [release workflow](../operations/releases.md), not just successful FastAPI import. Follow [capture](../workflows/capture-transcription.md), [Memory](../workflows/memory.md), and [account lifecycle](../workflows/account-lifecycle.md) for end-to-end boundaries.

## Source evidence

- [Direct A contracts](../../../backend/models/desktop_conversation.py)
- [Direct A routing](../../../backend/routers/desktop_conversation.py)
- [Quota ownership](../../../backend/services/desktop_inference.py)
- [backend/main.py](../../../backend/main.py#L76-L119)
- [backend/tests/unit/test_s26_canonical_backend_app.py](../../../backend/tests/unit/test_s26_canonical_backend_app.py)
- [backend/routers/memory_compute.py](../../../backend/routers/memory_compute.py)
- [backend/tests/unit/test_memory_compute.py](../../../backend/tests/unit/test_memory_compute.py)
- [backend/routers/conversation_compute.py](../../../backend/routers/conversation_compute.py#L22-L137)
- [backend/routers/desktop_supervisor.py](../../../backend/routers/desktop_supervisor.py#L80-L199)
- [backend/tests/unit/test_desktop_supervisor.py](../../../backend/tests/unit/test_desktop_supervisor.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
