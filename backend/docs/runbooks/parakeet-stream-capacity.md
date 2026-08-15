# Parakeet — streaming capacity per ready replica

**What it means:** Production Parakeet has less streaming headroom per ready
replica than intended. This is an infrastructure signal: it can precede live
transcription delay or rejected streams, but does not by itself prove a user
outage.

**Owner:** speech-processing / platform team.

The `/v3/stream` server owns a hard per-pod admission gate. Every one of the
27 backend-listen replicas connects to that boundary, and each Parakeet pod
runs one Uvicorn process for its GPU, so listener count cannot multiply the
configured limit. Rejected handshakes close with code `1013` and reason
`capacity_full` or `allocation_rejected`; listeners may then connect to
Modulate before accepting audio.

## Deployment settings

The Parakeet Helm values and `backend/deploy/runtime_env.yaml` explicitly own:

| Setting | Production value | Meaning |
| --- | --- | --- |
| `PARAKEET_STREAM_CAPACITY` | `25` | Maximum admitted `/v3/stream` sessions in one Parakeet pod. |
| `PARAKEET_STREAM_ALLOCATION_PERCENT` | `100` | Percentage of new Parakeet handshakes eligible for admission. |

Both settings are validated at service startup and the server fails to start
when either is absent or invalid. Changing either setting requires the normal
Parakeet Helm rollout; it is not a live runtime switch. Keep the HPA target
strictly below the hard capacity so scaling starts before rejection.

## Evidence boundary

Parakeet retains the `parakeet_active_streams` service metric behind its
authenticated metrics boundary. The repository no longer owns a dashboard,
scrape deployment, or alert rule for this signal. When an environment owner has
configured an authenticated metrics consumer, calculate:

```promql
sum(parakeet_active_streams{container="parakeet", namespace="prod-omi-backend"}) / clamp_min(sum(kube_deployment_status_replicas_ready{deployment="prod-omi-parakeet", namespace="prod-omi-backend"}), 1)
```

The metric is the sum of active WebSocket streams divided by ready deployment
replicas. It deliberately follows the currently serving replica count, so a
cluster-total stream count cannot hide a per-pod capacity problem while the HPA
is catching up.

The former repository-owned warning (15 for five minutes) and critical (20 for
two minutes) alerts were removed with the standalone monitoring product. They
are reference thresholds, not active alerts. If no owned consumer exposes the
metric, record stream headroom as **unproven**. Missing metrics are never proof
of healthy capacity.

## First checks

1. If an environment-owned consumer is available, confirm the ratio remains
   above a reference threshold for the stated duration and that its
   ready-replica value is current. Otherwise record this signal as unproven.
2. Compare HPA desired, total, and ready replicas. A desired-versus-ready gap
   points to scheduling, image startup, readiness, or node-capacity delay—not a
   reason to change the capacity threshold.
3. Inspect Parakeet pod readiness, restarts, GPU OOM events, and bounded service
   logs. Use GPU utilization, queue duration, latency, and request error metrics
   only through an environment-owned authenticated consumer. Correlate with
   production traffic before declaring user impact.
4. Allow the HPA to add healthy replicas first. If it has reached its configured
   maximum with sustained demand, change the deploy-owned capacity only after
   confirming node and GPU availability, then use the normal Parakeet Helm
   rollout.

Do not force-scale, install an ad hoc scrape, change the reference thresholds,
or state that users are affected from this metric alone. It measures serving
headroom; request errors, latency, and queueing provide the user-path
corroboration when those signals are actually available.
