# Pusher — degraded session ratio high

**What it means:** More than 5% of active listener WebSocket sessions are in degraded mode because the listener cannot use Pusher and routes audio elsewhere. This is a likely user-impact signal, not proof that every listener lost data.

**Derived expression (through an environment-owned authenticated metrics
consumer only):** `sum(pusher_sessions_degraded{job="backend-listen-metrics"}) / clamp_min(sum(backend_listen_active_ws_connections{job="backend-listen-metrics"}), 1)`

The repository no longer owns a dashboard, scrape deployment, or alert rule for
this expression. If the environment has no configured consumer, record the
degraded-session ratio as **unproven**; do not curl authenticated endpoints or
install an ad hoc scraper.

The degraded-session gauge is emitted by the backend-listen reconnect loop. Do not query the similarly named Pusher-process connection metric: it does not own this outcome.

**Owner:** listen/pusher team.

**First checks:**
1. Pusher pod health and circuit breaker state (`pusher_circuit_breaker_state`, rejections).
2. Recent pusher deploys or upstream STT/diarizer outages.
3. Error-rate and active-connection metrics, only when exposed by an
   environment-owned authenticated consumer; otherwise inspect bounded Pusher
   and backend-listen service logs and record the metric evidence as unproven.

**Note:** Degraded sessions are a silent heal path; sustained elevation means pusher is unhealthy for a large share of listeners.
