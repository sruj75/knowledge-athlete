---
type: Codebase guide
title: Telemetry and privacy boundaries
description: Explain PostHog, Sentry, Langfuse and fallback logging without inventing retention or compliance promises.
tags: [intentive, codebase]
verified:
  - by: openwiki/0.5.2
    at: 2026-09-15T13:05:19.246Z
sources:
  - id: openwiki-source-cf1f9de8bf8d48d97d4711c9
    resource: repo://backend/tests/unit/test_posthog_telemetry.py
  - id: openwiki-source-6ed02d397c8d55b9cc49657f
    resource: repo://backend/utils/observability/fallback.py
  - id: openwiki-source-f9d11dfba78f4997c5569f63
    resource: repo://backend/utils/observability/langfuse.py
  - id: openwiki-source-e711d9b61bda7bb73f34522f
    resource: repo://desktop/macos/Desktop/Sources/Observability/SentryBeforeSendPolicy.swift
  - id: openwiki-source-c2b1bb99ebb64c26ca0bc0e2
    resource: repo://desktop/macos/Desktop/Sources/Privacy/ProductAnalyticsConsentController.swift
generated: { by: "codex", at: "2026-09-15T13:05:19.246Z" }
---
# Telemetry and privacy boundaries

Product analytics, crash diagnostics and model tracing serve different owners. PostHog captures product events under its consent/configuration boundary. Sentry handles crash/error diagnostics through its before-send policy. Langfuse supports managed Chat tracing and prompt operations. One preference must not be described as disabling all three systems unless the actual callers enforce that.

## Backend tracing and fallback reporting

Langfuse client construction is lazy and requires the public/secret key pair. The default endpoint and optional override are read from environment configuration. Status logging reports whether configuration is present without printing either key. Correlation IDs are normalized to a bounded opaque format.

The shared `record_fallback` helper records component, from/to modes, reason and outcome. Unknown component/reason values are bucketed; invalid outcomes become degraded, and the helper must not raise into the user path. This bounds metric cardinality while keeping operational recovery visible.

## Desktop consent and sanitization

Trace a proposed event through `AnalyticsManager` and `ProductAnalyticsConsentController`; trace an error through `SentryBeforeSendPolicy`. The policy and source payloads, rather than a marketing label, determine what data leaves the Mac. Backend logging has a separate sanitizer boundary.

The [authored privacy and product constraints](../../INSTRUCTIONS.md#product-constraints) forbid raw sensitive logging. Asset/identity and legal handoffs do not establish a retention duration, legal operator, or compliance promise. This wiki adds none.

## Verification

Backend PostHog tests cover telemetry behavior. When changing observability, add coverage at the owning consent, sanitization or fallback seam and verify the actual emitted shape. Live project configuration and provider availability are dated operational evidence, not facts that can be inferred from a checked-in environment contract.

## Source evidence

- [backend/utils/observability/langfuse.py](../../../backend/utils/observability/langfuse.py#L20-L85)
- [backend/utils/observability/fallback.py](../../../backend/utils/observability/fallback.py)
- [desktop/macos/Desktop/Sources/Privacy/ProductAnalyticsConsentController.swift](../../../desktop/macos/Desktop/Sources/Privacy/ProductAnalyticsConsentController.swift)
- [desktop/macos/Desktop/Sources/Observability/SentryBeforeSendPolicy.swift](../../../desktop/macos/Desktop/Sources/Observability/SentryBeforeSendPolicy.swift)
- [backend/tests/unit/test_posthog_telemetry.py](../../../backend/tests/unit/test_posthog_telemetry.py)

[Start here](../../quickstart.md) · [Authored guidance](../../INSTRUCTIONS.md)
