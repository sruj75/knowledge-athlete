---
type: Codebase guide
title: Telemetry and privacy boundaries
description: Explain PostHog, Sentry, Langfuse and fallback logging without inventing retention or compliance promises.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-27T18:59:28.091Z
sources:
  - id: openwiki-source-cf1f9de8bf8d48d97d4711c9
    resource: repo://backend/tests/unit/test_posthog_telemetry.py
  - id: openwiki-source-01c563e69975269a5c47bffa
    resource: repo://backend/utils/observability/ai_evaluation.py
  - id: openwiki-source-7a2df7cc5618bf28aacb09df
    resource: repo://backend/utils/observability/chat_evaluation.py
  - id: openwiki-source-b3299dfb12739d9027fe4b72
    resource: repo://backend/utils/observability/evaluation_policy.py
  - id: openwiki-source-6ed02d397c8d55b9cc49657f
    resource: repo://backend/utils/observability/fallback.py
  - id: openwiki-source-f9d11dfba78f4997c5569f63
    resource: repo://backend/utils/observability/langfuse.py
  - id: openwiki-source-0e6529a61b1ecfbe5f7d9c90
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/AIEvaluationObservation.swift
  - id: openwiki-source-e0ddaa9325c2b96bfacccfee
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/AIEvaluationReporter.swift
  - id: openwiki-source-0f0462a4bfd1de02ce1949b1
    resource: repo://desktop/macos/Desktop/Sources/AIObservability/APIClient%2BSupervisor.swift
  - id: openwiki-source-88c3ed3955da0f57bcfd5d9f
    resource: repo://desktop/macos/Desktop/Sources/DesktopBackendEnvironment.swift
  - id: openwiki-source-e711d9b61bda7bb73f34522f
    resource: repo://desktop/macos/Desktop/Sources/Observability/SentryBeforeSendPolicy.swift
  - id: openwiki-source-c2b1bb99ebb64c26ca0bc0e2
    resource: repo://desktop/macos/Desktop/Sources/Privacy/ProductAnalyticsConsentController.swift
  - id: openwiki-source-c8eeff499a30efe076e6b5cf
    resource: repo://desktop/macos/Desktop/Tests/APIClientAuthRetryTests.swift
  - id: openwiki-source-abb5b57da8acacb3c7b68515
    resource: repo://desktop/macos/Desktop/Tests/APIClientRoutingTests.swift
generated: { by: "codex", at: "2026-09-27T18:59:28.091Z" }
---
# Telemetry and privacy boundaries

Product analytics, crash diagnostics and model tracing serve different owners. PostHog captures product events under its consent/configuration boundary. Sentry handles crash/error diagnostics through its before-send policy. Langfuse supports managed Chat, A (Live voice) and B (supervisor) tracing and prompt operations. One preference must not be described as disabling all three systems unless the actual callers enforce that.

## Backend tracing and fallback reporting

Langfuse client construction is lazy and requires the public/secret key pair. The default endpoint and optional override are read from environment configuration. Status logging reports whether configuration is present without printing either key. Correlation IDs are normalized to a bounded opaque format.

The shared `record_fallback` helper records component, from/to modes, reason and outcome. Unknown component/reason values are bucketed; invalid outcomes become degraded, and the helper must not raise into the user path. This bounds metric cardinality while keeping operational recovery visible.

## Desktop consent and sanitization

Trace a proposed event through `AnalyticsManager` and `ProductAnalyticsConsentController`; trace an error through `SentryBeforeSendPolicy`. The policy and source payloads, rather than a marketing label, determine what data leaves the Mac. Backend logging has a separate sanitizer boundary.

The [authored privacy and product constraints](../../INSTRUCTIONS.md#product-constraints) forbid raw sensitive logging. Asset/identity and legal handoffs do not establish a retention duration, legal operator, or compliance promise. This wiki adds none.

## Chat, A and B evaluation export

Normal sessions send only identifiers, prompt names/versions/sources, timings, counts, outcomes and scores. The session-scoped **evaluation sharing** control starts off and is not persisted. Selecting a disposable test session permits bounded conversation and guidance text through the typed `/v1/ai/observations` intake. The export model has no fields for raw audio, screenshots, copied Memory/profile context, credentials or tool payloads. Backend Chat provider input/output tracing is metadata only even in selected sessions; reviewed Chat text comes from canonical journal acceptance on the Mac.

`AIEvaluationReporter` captures an owner and consent ticket at turn/evaluation admission. Tickets include a session and consent epoch. Disabling sharing cancels pending exports; an off/on transition cannot release text captured under the old ticket. Session end or owner revocation resets sharing and receipts. The API client rechecks authority and consent after asynchronous token lookup, immediately before encoding the wire body. Supervisor and observation routes use paths relative to the canonical trailing-slash backend URL; `APIClientRoutingTests` checks the actual resulting POST paths. Its best-effort request has no automatic replay, authentication refresh or sign-out on failure.

B's backend generation uses an owner/session/decision trace ID and records the observation ID and B prompt version without observation text. A's terminal receipt joins the same decision trace with its turn ID, physical-session A prompt receipt and actual playback outcome. Helpful/unhelpful controls on the resulting message attach a Boolean score to that trace. Unguided A turns use their own trace identity.

Chat uses the successful managed request ID. A short-lived Redis receipt stores only the actual Chat prompt reference under an owner/request hash; selected accepted Chat text and feedback join the existing Chat trace. Missing receipts drop the optional example rather than guessing a prompt version. The reporter bounds pending work and retained UI receipts; telemetry failures do not block speech or change authentication.

`AIEvaluationExportTests` tests the export allowlist and consent epochs. Production API tests suspend token lookup, revoke and re-enable sharing, then inspect the actual request body for both Chat and B. They also verify that a telemetry 401 performs one request without refresh or sign-out. Backend observation tests exercise prompt correlation, scores, idempotency and the normal/selected export boundary.

## Verification

Backend PostHog tests cover telemetry behavior. When changing observability, add coverage at the owning consent, sanitization or fallback seam and verify the actual emitted shape. Live project configuration and provider availability are dated operational evidence, not facts that can be inferred from a checked-in environment contract.

## Source evidence

- [backend/utils/observability/langfuse.py](../../../backend/utils/observability/langfuse.py#L20-L85)
- [backend/utils/observability/fallback.py](../../../backend/utils/observability/fallback.py)
- [desktop/macos/Desktop/Sources/Privacy/ProductAnalyticsConsentController.swift](../../../desktop/macos/Desktop/Sources/Privacy/ProductAnalyticsConsentController.swift)
- [desktop/macos/Desktop/Sources/Observability/SentryBeforeSendPolicy.swift](../../../desktop/macos/Desktop/Sources/Observability/SentryBeforeSendPolicy.swift)
- [backend/tests/unit/test_posthog_telemetry.py](../../../backend/tests/unit/test_posthog_telemetry.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
