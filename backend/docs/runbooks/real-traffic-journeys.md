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
| `omi_capture_finalization_reconciliations_total` | `outcome` | A stale durable capture job was requeued, or its requeue handoff failed. |
| `listen_finalization_oldest_nonterminal_age_seconds` | none | Age of the oldest queued or leased capture finalization job. |
| `listen_finalization_durable_jobs` | `state` | Authoritative Firestore job projection: `accepted`, `success`, `failure`, `stale`, `nonterminal`, or `terminal_unknown`. |

`journey` remains a closed metric label: `pusher_session`,
`capture_finalization`, or the reserved legacy `chat_response` value. S-11 has
no hosted Chat response producer. Generic journey `outcome` is exactly `success`, `failure`,
`cancelled`, or `stale`; reconciliation `outcome` is exactly `requeued` or
`enqueue_failed`. Live-STT terminal `outcome` is exactly `success`, `failure`,
or `cancelled`; its terminal `phase` is exactly `transcript_delivery`,
`initialization`, `connection`, `send`, or `teardown`. `provider` and
`client_platform` use their existing closed vocabularies, and
`deployment_environment` is one of `prod`, `dev`, `local`, `offline`, or
`unknown`. There are no user, conversation, request, error-text, revision,
image, provider-model, or content labels.

## Boundary semantics

- `pusher_session` is accepted only after `/v1/trigger/listen` completes its
  WebSocket accept. Close codes `1000` and `1001` are `success` unless the
  server has already identified an application failure. A `1011` or stronger
  application failure is `failure`; other transport/client endings are
  `cancelled`, not product failures.
- Live STT is accepted when `/v4/listen` receives its first
  nontrivial audio frame. `success` is recorded only after the server has sent
  the first nonempty transcript payload to that WebSocket. This cannot prove
  the client rendered the payload. An upstream/live-session failure or an
  unexpected listen worker failure is `failure`; all other endings before a
  transcript send are `cancelled`. Provider failures preserve their bounded
  provider outcome and phase in `omi_live_stt_terminal_failures_total`; the
  matching accepted attempt has one `failure` terminal in
  `omi_live_stt_terminal_total`.
- `capture_finalization` is accepted only once, when the Firestore finalization
  outbox creates a new durable job. Successful completion is `success`, a
  dead-letter is `failure`, and a lifecycle-fenced durable job is `stale`.
  Existing job re-dispatches do not increment acceptance. Historical terminal
  rows without the bounded field are `terminal_unknown`. This Firestore projection is the capture
  denominator: PromQL takes `max` across listener pods, then uses
  `clamp_min(delta(...), 0)` for movement. It never sums replicated global
  gauges. A dead-emission condition is bounded new `accepted` movement with
  zero new `success`/`failure`/`stale` movement.

## Metrics export boundary

The authenticated `/metrics` route retains the closed journey counters for
service-owned consumers. Metric children are initialized at process startup,
so an idle process exports zeros rather than omitting the series. The repository
does not own a standalone dashboard, alerting, or scrape deployment for these
metrics.

Known blind spots: a server can only observe the SSE/WS boundary it controls,
not client rendering; process restarts may defer a terminal metric until the
durable worker/reconciler resumes; and a durable job still within its bounded
reconcile delay is deliberately nonterminal rather than an immediate failure.
