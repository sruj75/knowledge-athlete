# Real-Traffic Journey Outcomes

`omi_journey_*` and `omi_live_stt_*` measure user-originated traffic only. They do not create test
accounts, synthetic canaries, or generated requests. Dev/beta and production
remain isolated, with no cross-environment comparison or labels.

## Closed metric contract

| Metric | Labels | Meaning |
| --- | --- | --- |
| `omi_journey_accepted_total` | `journey` | A production boundary accepted work. |
| `omi_journey_terminal_total` | `journey`, `outcome` | A one-shot terminal outcome for accepted work. |
| `omi_journey_latency_seconds` | `journey`, `outcome` | Acceptance-to-terminal latency. |
| `omi_live_stt_accepted_total` | `provider`, `client_platform`, `deployment_environment` | A listener accepted its first nontrivial live-STT audio frame. |
| `omi_live_stt_terminal_total` | `provider`, `outcome`, `client_platform`, `deployment_environment`, `phase` | A one-shot terminal outcome for an accepted live-STT attempt. |
| `omi_live_stt_terminal_failures_total` | `provider`, `outcome`, `client_platform`, `deployment_environment`, `phase` | Provider failure detail correlated with a live-STT terminal. |
| `omi_account_deletion_*` | bounded lifecycle labels | Admission, claim, terminal cleanup, and retry-safe durable deletion outcomes. |

`journey` is the closed `chat_response` value. Generic journey `outcome` is
exactly `success`, `failure`, `cancelled`, or `stale`. Live-STT terminal `outcome` is exactly `success`, `failure`,
or `cancelled`; its terminal `phase` is exactly `transcript_delivery`,
`initialization`, `connection`, `send`, or `teardown`. `provider` and
`client_platform` use their existing closed vocabularies, and
`deployment_environment` is one of `prod`, `dev`, `local`, `offline`, or
`unknown`. There are no user, conversation, request, error-text, revision,
image, provider-model, or content labels.

## Boundary semantics

- Live STT is accepted when `/v4/listen` receives its first
  nontrivial audio frame. `success` is recorded only after the server has sent
  the first nonempty transcript payload to that WebSocket. This cannot prove
  the client rendered the payload. An upstream/live-session failure or an
  unexpected listen worker failure is `failure`; all other endings before a
  transcript send are `cancelled`. Provider failures preserve their bounded
  provider outcome and phase in `omi_live_stt_terminal_failures_total`; the
  matching accepted attempt has one `failure` terminal in
  `omi_live_stt_terminal_total`.
- Account deletion is admitted only after its durable marker is written. The
  dedicated Cloud Tasks worker claims that marker, records a bounded terminal
  state, and remains idempotent under redelivery. The legacy identity/audience
  seam is bounded explicitly until live drain evidence permits its removal.

## Metrics export boundary

The authenticated `/metrics` route retains the closed journey counters for
service-owned consumers. Metric children are initialized at process startup,
so an idle process exports zeros rather than omitting the series. The repository
does not own a standalone dashboard, alerting, or scrape deployment for these
metrics.

Known blind spots: a server can only observe the HTTP/WS boundary it controls,
not client rendering, and metrics do not replace the durable account-deletion
state used for retry and recovery.
