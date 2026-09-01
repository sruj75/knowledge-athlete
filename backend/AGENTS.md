# Backend (Python) — Developer Guide

Inherits all rules from the root `../AGENTS.md`. This file adds backend-specific development guidance.

## Setup

Python 3.11 is required (not 3.12+ — Dockerfile pins 3.11). Backend local dev pins the exact interpreter in `.python-version` and uses `uv` for reproducible dependency sync. Also needs FFmpeg, Opus (`opuslib`), Redis (optional).

```bash
cp .env.template .env          # Fill in required values (see .env.template for full list)
./scripts/sync-python-deps.sh  # creates .venv from .python-version + pylock.toml
source .venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8080
```

**Env stages** (`OMI_ENV_STAGE`): `local` (emulator harness, `.env.local-dev`), `offline` (fake-backed providers, `.env.offline`), `dev` (remote dev GCP, `.env.dev`), `prod` (reference only, `.env.prod`). `load_backend_env()` loads the stage file then `backend/.env` overrides. Templates: `backend/.env.*.template`. Harness: `PROVIDER_MODE=offline make dev-up` or `OMI_ENV_STAGE=offline`. Offline harness app factories install the shared hermetic Modulate fake for managed live and prerecorded STT without provider credentials. Billing is independently selected by `BILLING_MODE=disabled|dodo_test|dodo_live`; disabled is the default and ignores billing credentials. Active modes fail startup unless `DODO_PAYMENTS_API_KEY`, `DODO_PAYMENTS_WEBHOOK_KEY`, and the normalized `DODO_BILLING_CATALOG_JSON` are all present.

Parity-pack capture is a dev-only, allowlisted, local persistence path. `OMI_PARITY_PACK_CAPTURE`, `OMI_PARITY_PACK_ALLOWED_PRINCIPALS`, and an absolute external `OMI_PARITY_PACK_ROOT` are its complete runtime configuration; it never exports cassettes or constructs a cloud-storage client.

When intentionally changing backend Python dependencies, edit the relevant `requirements*.txt` input file and refresh the lock:

```bash
./scripts/update-python-lock.sh
```

By default, the lock refresh preserves already-locked package versions so unrelated transitive upgrades do not sneak into infrastructure changes. Set `PYLOCK_UPGRADE=1` only when intentionally refreshing dependency versions.

Key env vars: `OPENAI_API_KEY` (LLM calls — not `OPENAI_ADMIN_KEY` which is billing-only), `MODULATE_API_KEY` (managed live and prerecorded STT), `GEMINI_API_KEY` and `ANTHROPIC_API_KEY` (canonical Chat/realtime), `LANGFUSE_PUBLIC_KEY` plus `LANGFUSE_SECRET_KEY` (fail-open Chat prompt/tracing; both are required to enable it), and `REDIS_DB_HOST` / `REDIS_DB_PASSWORD` / `REDIS_DB_CA_CERT_PEM` (the hosted verified-TLS Redis boundary). Langfuse uses `LANGFUSE_BASE_URL`, `LANGFUSE_TRACING_ENVIRONMENT`, `LANGFUSE_PROMPT_NAME`, and `LANGFUSE_PROMPT_CACHE_TTL_SECONDS` as non-secret runtime configuration. Hosted `dev`/`prod` uses the Cloud Run runtime service account through ADC and rejects `SERVICE_ACCOUNT_JSON` and `GOOGLE_APPLICATION_CREDENTIALS`; explicit credential files remain local-tool/test-only. Dodo billing is enabled only by the explicit billing mode above; checkout accepts an opaque server-owned offer ID, and the provider webhook is the only authority that projects paid entitlement state.

Chat SSE deadlines: `AGENT_STREAM_FIRST_EVENT_TIMEOUT_SECONDS` (default `25`), `AGENT_STREAM_PROGRESS_HEARTBEAT_SECONDS` (default `20`), `AGENT_STREAM_MAX_DURATION_SECONDS` (default `150`), and `AGENT_STREAM_CANCEL_GRACE_SECONDS` (default `2`) bound silent setup/producer work and keep valid long tool calls observable. Values must be positive. The agent's direct managed-Anthropic call is re-issued on transport-class failures up to `AGENT_STREAM_PROVIDER_MAX_ATTEMPTS` (default `3`), spaced by `AGENT_STREAM_PROVIDER_RETRY_BACKOFF_SECONDS` (default `1`), and only while at least `AGENT_STREAM_PROVIDER_MIN_RETRY_HEADROOM_SECONDS` (default `45`) of the turn budget remains. Do not route normal Chat through an auto lane or introduce a per-request provider switch.

## Directory Structure

```
backend/
  main.py                 # FastAPI entry and retained route registration
  models/                 # Pydantic request/response schemas (conversation, transient Memory compute, chat, subscription, etc.)
  database/               # All persistence — 25+ domain modules
    _client.py            #   Firestore singleton + document_id_from_seed utility
    redis_db.py           #   Cache, rate limiting (Lua scripts), pub/sub, locks, geolocation
    users.py              #   Retained account, subscription, deletion, and language state
    fair_use.py           #   Usage limits and soft-cap tracking
    ...                   #   + auth, billing, updates, and operational job state
  routers/                # FastAPI route handlers, one per retained feature domain
    transcribe.py         #   /v4/listen WebSocket — auth + exact transient session contract
    listen/               #   Modulate transport, VAD, metering, canonical segments, direct translation
    chat.py               #   stateless Chat compute and transient voice STT
    chat_sessions.py      #   stateless /v2/chat greeting and title compute
    conversation_compute.py # /v1/conversation-compute — stateless discard/structure/action-item candidates
    memory_compute.py     #   Three authenticated, bounded, stateless Memory proposal routes
    auth.py               #   Google/Apple OAuth callbacks, session management
    users.py              #   Account profile, subscription, usage, export, and deletion routes
    ...                   #   + payment and other retained product routes
  utils/                  # Business logic — 60+ files (never import from routers/)
    llm/                  #   LLM orchestration: stateless Chat/conversation/Memory compute,
                          #   fair-use classification, and usage tracking
      clients.py          #     Explicit direct workload clients with prompt caching and usage callbacks
    stt/                  #   Managed Modulate speech-to-text and provider-neutral VAD gating
    retrieval/            #   Retained explicit-file/web/chart tools; no hosted product search
    other/                #   Auth, timeout middleware, and retained update/preview storage helpers
    log_sanitizer.py      #   sanitize() / sanitize_pii() — required for all logging
    encryption.py         #   AES-256-GCM per-user encryption (HKDF-SHA256 key derivation)
    fair_use.py           #   Rolling speech-hour tracking via Redis minute buckets, soft-cap enforcement
    translation.py        #   Multi-language translation coordination
  tests/unit/            # 50+ unit tests (no external service deps)
  tests/integration/     # Integration tests (need Redis, Firebase, API keys)
  scripts/run-unit-ci.sh # Full CI unit-test contract
  test.sh                # Selected-suite executor used by the shared contract
  test-preflight.sh      # Env validator (Python, pytest, packages, Redis)
```

## Service Map

```
Shared: Firestore, Redis

backend (main.py, canonical Cloud Run service)
  ├── ──────► modulate (managed STT API; in-process Silero VAD gate)
  ├── ──────► managed model providers through explicit in-process workload clients
  ├── ──────► langfuse (fail-open Chat prompt management and generation evidence)
  └── ──────► Cloud Tasks queue `account-deletion` ──► POST /v1/users/account-deletion-wipes/run (OIDC, same service)

```

Managed STT is fixed to Modulate. `config/stt_provider_policy.py` owns its language/capability policy, and the runtime manifest binds `MODULATE_API_KEY` on the canonical backend.

- **backend** (`main.py`) — The one REST/WebSocket Cloud Run service. `/v4/listen` applies in-process `VADStreamingGate`, streams fixed PCM directly to Modulate, and returns transient canonical segments without a side channel, People, or conversation storage. Retained Python model workloads call their declared providers directly through `utils/llm/clients.py`.
- **Fair-use review** — `/v4/listen` owns speech meters, thresholds, cooldown, enforcement, and the restricted managed-cloud budget. It requests one content-free review from the authenticated owner Mac; `POST /v1/fair-use/reviews/{review_id}/classify` accepts only the bounded seven-day local evidence projection, invokes direct OpenAI GPT-5.1 transiently, and persists only content-free classifier/enforcement facts. Conversation evidence never becomes backend authority or durable case data.
- **modulate** — The fixed managed STT adapter for configured languages. Called by transcription-capable services through their `MODULATE_API_KEY` binding.
- **account deletion** — `ACCOUNT_DELETION_DISPATCH_MODE=cloud_tasks` and the complete dedicated `ACCOUNT_DELETION_*` bindings enqueue opaque job IDs to the canonical backend's OIDC handler. Startup rejects inline or incomplete configuration, reconciliation only re-dispatches tasks, and API success follows persisted deletion intent plus durable enqueue. A bounded legacy audience/payload branch remains only because no live queue-drain proof was authorized for S-25.

### macOS conversation boundary

macOS conversation persistence is owner-scoped GRDB, not this backend. Do not
add `/v1/conversations`, `/v1/folders`, public conversation-audio playback, or
People/settings compatibility routes for the Mac. `/v4/listen` is a transient
speech transport for macOS and `/v1/conversation-compute/{discard,structure,action-items}`
returns candidate data without writing conversation records. Hosted listen and
conversation lifecycle are gone; shared historical datastore internals remain
only for the later-slice owners recorded in `FORK.md`.

### macOS Chat and Home boundary

The owner-scoped desktop Node SQLite catalog and journal are the sole durable
authority for normal Chat sessions, titles/stars, turns, and activity metadata;
Swift owns drafts and app-managed attachment bytes. Do not add backend session,
message, rating, attachment, projection, reconcile, import, or count authority
for macOS Chat. `POST /v2/chat/initial-message` and
`POST /v2/chat/generate-title` are authenticated, bounded, stateless compute:
they return only a greeting or title and never read or write Chat product data.
Managed answers continue through the desktop Pi `/v2/chat/completions` boundary;
the Python hosted persona/RAG route is retired. Real Anthropic calls create one
fail-open Langfuse generation, while the offline stub performs no prompt or
observability network work. The optional `X-Omi-Session-Id` header is bounded
correlation metadata only and never restores backend session ownership.

### macOS Memory boundary

The effective owner's `omi.db` is the sole durable Memory authority. The backend exposes only
`POST /v1/memory/compute/{extract,normalize,consolidate}`: authenticated, bounded, stateless
proposal computation pinned to OpenAI GPT-4.1-mini. These modules must not import Firestore,
Redis, hosted vectors, product Memory stores, or log request/response bodies. The retained Gemini
embedding proxy is transient compute; vector storage and similarity remain local on macOS.

### macOS Focus, Insights, profile, and settings boundary

Focus sessions, `tips` Insights, AI Profile history, assistant controls, and the
master notification/frequency controls are Mac-local authorities. Do not add
backend Focus/stat APIs, AI Profile persistence, assistant/notification/Mentor
settings mirrors, Daily Summary, personalized purchase/quota push generation,
or a notifications cron job. Cloud FCM delivery is retired; authoritative
fair-use facts are presented by the Mac through fixed in-app and local OS copy.
Managed Gemini remains transient compute and owns no product records.

Backend runtime and foundation contract: `backend/deploy/runtime_env.yaml` is the single redacted declaration for exact WIF claim inputs, ADC/secret bindings, Cloud Run, network/Redis, Firestore, retained GCS, Tasks, Artifact Registry, logging, alerts, and budgets. Keep its claim-policy evaluator, renderer, validator, preflight, and both deploy workflows aligned. Manual `foundation-readiness` performs read-only sanitized live drift checks, and `artifact-cleanup-dry-run` only records candidates; neither declaration nor dry run proves a resource was created or authorizes mutation. Run `backend/scripts/pre-deploy-check.sh` after runtime, foundation, or deploy-workflow changes.

Firestore index boundary: backend deploy workflows run `reconcile_firestore_indexes.py --check-only` against `RUNTIME_GCP_PROJECT_ID` in an isolated approved-source job using the dedicated WIF read-only principal. Auto-dev deploys accept only a first-attempt successful same-repository `Release Eligibility` proof for `main` whose `head_sha` still equals freshly fetched and checked-out `main`, then use that admitted SHA for every source-derived step; manual **deploy** mode accepts only an exact main SHA with the same successful proof. Traffic-only repair leaves that input empty and stays source-independent because it changes no source-derived runtime state. A failed gate writes and locally revalidates a short-lived, redacted create-only proposal before upload; only the separate manual WIF writer may create missing indexes, and no lane deletes indexes.

Keep this map up to date. When adding, removing, or changing inter-service calls, update this section and the executable workflow-contract tests in the same PR.

## Import Rules

All imports at module top level — never inside functions. Strict hierarchy:

```
database/  →  utils/  →  routers/  →  main.py
```

Higher imports from lower, never reverse. Cross-importing between routers will break. `main.py:app` is the only production application entrypoint; route behavior and generated contracts must be checked through that assembled app.

Runtime-selected providers must keep model-token parsing and required environment bindings in a pure `config/` module. Read mutable env at the call boundary rather than snapshotting it during import, and construct SDK clients lazily. For pre-recorded STT, `config/prerecorded_stt.py` is the single source of truth used by both `utils/stt/pre_recorded.py` and the deploy manifest validator; adding a provider or model token requires updating that contract and its runtime/deploy tests together.

## Database

**Firestore** (primary store): use `get_firestore_client()` from `database._client` at call time, and add optional keyword-only `firestore_client` parameters on converted database helpers so tests can inject fake clients. `db` remains a legacy lazy compatibility proxy only; do not use it in new code. Never construct Firestore clients at import time. Collection group queries need explicit indexes (will 500 with no useful error). Segments are encrypted at rest — direct Firestore reads return opaque blobs. Feature gating via user fields: e.g., translation requires `users/{uid}.language` non-empty — silently disabled if missing.

**Redis** (cache/rate-limiting/locks): use the process-scoped lazy client from `database.redis_connection`; never construct a second client or perform Redis I/O during import. Hosted profiles require AUTH and verified TLS with the declared CA and have no plaintext fallback; local/offline profiles retain the explicit plaintext fake/local seam. Preserve each caller's existing failure policy—ordinary caches may fail open, while OAuth single-use, listen locks, and other correctness/security boundaries fail closed. Rate limiting uses lazily registered Lua scripts; `try_acquire_listen_lock(uid)` prevents duplicate WS connections.

## Auth

HTTP endpoints: `uid: str = Depends(get_current_user_uid)` from `utils.other.endpoints`.

WebSocket endpoints: use `WebSocketException(code=1008)`, **not** `HTTPException` — HTTPException exits ASGI without handshake, causing LB 5xx.

Rate limiting: `Depends(auth.with_rate_limit(get_current_user_uid, "policy_name"))` — policies in `utils/rate_limit_config.py`.

Managed provider proxies return provider-owned auth and quota failures as typed JSON with
`reason`, `provider`, `backend_route`, `upstream_status_code`, and `retryable`. Clients must
classify these fields at the backend boundary; never infer provider credential ownership from
human-readable error text.

## Logging Security

Never log raw sensitive data. Use `sanitize()` and `sanitize_pii()` from `utils.log_sanitizer`.

- `sanitize()` for `response.text`, API responses, error bodies.
- `sanitize_pii()` for names, emails, user text.
- Keep UIDs, IPs, status codes visible for debugging.
- Never put raw `response.text` in exception messages.

## Resource Management

- `del` byte arrays after processing and `.clear()` dicts/lists holding data.

## Testing

```bash
bash test-preflight.sh   # Verify env
bash test.sh             # Run all tests (CI source of truth)
```

**Tests are selector-driven.** `scripts/run-unit-ci.sh` is the full GitHub Actions contract: it selects changed-file tests on PRs, runs preflight and type-checking, then invokes `test.sh`; main CI uses it with `--all`. Local pre-push intentionally keeps its own 40-file cap and runs changed test files when a broad selector exceeds that budget. Do not make the hook call the CI runner: bounded push latency protects the normal development loop. Local `test.sh` runs the selected set from `tests/unit/`, `tests/services/`, and `tests/routers/` via `scripts/select_backend_unit_tests.py`. Tests that need live services (Redis, Firebase, real API keys) go in `tests/integration/`, which is not part of selector auto-discovery; note in the PR how you ran them.

**Runtime image contracts.** `runtime_images.json` registers each deployed Python image, its Dockerfile, build context, entrypoints, and deployment workflows. Run `make runtime-image-source-closure` to verify final-stage first-party source closure and that every registered deployment workflow smokes its declared Dockerfile; it is the fast pre-push and CI gate. `make runtime-image-smoke SERVICE=backend` builds one image and checks every reachable third-party module is installed offline. PR CI builds every registry-selected CPU image; deployment workflows build and push the full-SHA tag, capture its digest, smoke the published digest, then deploy that same digest. Do not add a hand-maintained image-layout test or workflow mapping; add the service to the registry instead.

**OpenAPI contract runner** — OpenAPI contract checks use `backend/scripts/openapi_runner.sh`, which syncs the pinned `backend/openapi-requirements.txt` runner env and prewarms `tiktoken`; CI and `scripts/pre-push` must use this same path.

**Desktop app-client generation** — `backend/scripts/generate_swift_openapi_types.py` derives its default schema directly from the live `app-client` FastAPI surface. The pinned `backend/scripts/openapi_runner.sh` environment must validate the committed macOS DTO output; explicit `--spec` remains fixture-only.

The app-client snapshot begins at the S-06 retained-product boundary. The pinned pre-S-06 base had neither this snapshot nor its compatibility checker, so the retired developer, integration, MCP, and app routes were never released through this workflow. Future retained-surface changes keep freshness strict.

**Test isolation / import purity** — never mutate `sys.modules` at module scope in tests; production modules must not construct clients or do IO at import time. Sanctioned seams: `monkeypatch.setattr` on a lazy-held singleton, FastAPI `app.dependency_overrides`. Enforced by `python scripts/check_module_stub_pollution.py` and `python scripts/scan_import_time_side_effects.py`. Full prescription: `backend/docs/test_isolation.md`.

**Firestore transaction fakes** — a fake at this service boundary must enforce its ordering and constraint semantics. Use `tests.unit.fixtures.strict_firestore_transaction.StrictFirestore` for transaction tests that need document-reference reads plus `set`/`update`: it rejects reads after the first write, the production rule that #9739's lenient fake missed. If an incident requires queries, deletes, retry, or contention behavior, first cover it with the Firestore emulator; extend the fixture only for a proven hermetic guard.

Pre-mock heavy deps before importing the module under test. Use `patch.object(target_module, "func")` not string-based `patch("module.func")` — the string form silently patches the wrong reference if the function was already imported. When modules construct objects at import time, use lazy getters to avoid triggering heavy init in tests.

## Self-Testing a Change (run the real path)

A passing unit test is not the same as exercising the endpoint. Before putting a change in a PR:

1. **Serve locally**: `./scripts/dev-serve.sh` (per-worktree port) or `uvicorn main:app --port 8080`. No GCP credentials? The offline harness covers fake-backed providers with no external services, including managed live and prerecorded STT through the shared hermetic Modulate fake.
2. **Authenticate without a client**: set `ADMIN_KEY` in `.env`, then call endpoints as any uid with `Authorization: Bearer <ADMIN_KEY><uid>` (the key concatenated with the uid).
3. **Hit the changed endpoints** with curl and read the server logs — verify the behavior changed as intended, not just that the route returns 200.
4. **Record the commands and output** in the PR description (root `AGENTS.md` → Definition of Done).

## Formatting

```bash
black --line-length 120 --skip-string-normalization <files>
```

`--skip-string-normalization` is critical — without it, black flips all quotes and diffs explode.

## Async I/O (3-Lane Architecture)

Never block the event loop — it freezes health checks, HPA scaling, and all concurrent connections.

- **Lane 1 — Async HTTP** (`utils/http_client.py`): Shared `httpx.AsyncClient` pools with semaphore-bounded concurrency. Never `requests.*` or sync `httpx.*` in async code.
  - Clients: `get_webhook_client()`, `get_maps_client()`, `get_auth_client()`, `get_stt_client()`
  - Semaphores: always wrap calls — `async with get_webhook_semaphore(): await client.post(...)`
  - Circuit breakers: `get_webhook_circuit_breaker(url)` for external targets — call `cb.record_success()`/`cb.record_failure()`
  - Lifecycle: lazy singletons, closed at shutdown via `close_all_clients()`
- **Lane 2 — Executors** (`utils/executors.py`): 7 purpose-specific thread pools. Never ad-hoc `Thread`/`ThreadPoolExecutor`.
  - **Async dispatch rules** (choose the right primitive):
    - `await run_blocking(executor, fn)` — sync/CPU-bound work where the caller needs the result before continuing.
    - `start_background_task(coro, name=...)` — async fire-and-forget work (pipelines, post-processing). Tracks the task, logs exceptions, cleans up references. Never use bare `asyncio.create_task()` for production background work.
    - `submit_with_context(executor, fn)` — short sync fire-and-forget only (precache, small cleanups). Never for pipelines that hold a slot >10s.
  - **Long-running pipelines must be async coordinators.** Each blocking step uses `await run_blocking(pool, fn)`, borrowing a thread only for that step. Never hold a thread pool slot across await points or for >60s.
  - **Pool assignment** (match work type to pool):
    - `critical_executor` (8w) — auth gates only: `_verify_ws_auth`, `check_rate_limit`, `is_hard_restricted`, session/code Redis ops in `auth.py`
    - `db_executor` (24w) — Firestore/Redis CRUD, vector DB queries
    - `llm_executor` (6w) — retained explicit-workload provider calls and first-party generation/classification work
    - `billing_executor` (4w) — billing-provider API calls
    - `sync_executor` (16w) — retained voice-message and file-VAD compute
    - `cleanup_executor` (4w) — durable account-deletion provider and Firestore cleanup
    - `storage_executor` (128w) — GCS uploads/downloads, audio chunk I/O (fan-out gated by semaphores: 32 global chunks, 8 per-call window, 4 concurrent precache files)
  - **Deadlock prevention — 4 rules:**
    1. **Worker threads are leaf operations only.** Never `.result()` on another pool from inside a worker thread. If pool A thread submits to pool B and calls `.result()`, and vice versa, both pools deadlock.
    2. **Orchestration stays in async code.** The async handler coordinates via `await run_blocking(pool, fn)` — sequentially or with `asyncio.gather`. The event loop never blocks, pools stay independent.
    3. **Coordinators must not share a pool with their children.** If a function fans out work to `storage_executor` and waits on `.result()`, that function must run on a different owning pool, never on `storage_executor` itself — otherwise all threads become coordinators and children can't run.
    4. **Long-running coordinators need async orchestration or sized pools.** If a coordinator holds a thread pool slot for >10s, it must either use async coordination (`asyncio.create_task` + `await run_blocking(...)`) or run on a pool sized for `hold_time × peak_concurrency`. Prefer async coordination for any coordinator with hold time >60s — thread slots occupied by sleeping coordinators waste memory and starve other work.
  - **Audit command:** `grep -rn '\.result()' --include="*.py" | grep -v tests/ | grep -v __pycache__` — every hit must be a leaf operation or a coordinator on a different pool from its children.
  - **Pool observability:** `get_executor_metrics()` returns active count, queue depth, and utilization % for all pools. `log_executor_health()` runs every 60s, warns when any pool exceeds 70% utilization. Wired in `main.py` startup event.
- **Lane 3 — Lint**: `python scripts/scan_async_blockers.py --dirs routers utils` catches blocking calls in async routes and helpers.
  The scanner follows direct calls through module-local sync helpers transitively, so moving blocking I/O behind a wrapper is not an escape; offload the helper at the async boundary with `run_blocking`.
  Run from `backend/` before committing. From the repository root, use `python backend/scripts/scan_async_blockers.py --dirs backend/routers backend/utils`.
- **Shutdown**: `close_all_clients()` + `shutdown_executors()` are wired in `main.py`.

## WebSocket Concurrency (Long-Lived Connections)

The WS handler in `routers/listen/runtime.py` manages concurrent tasks per connection. Use `utils/async_tasks.py` utilities — never raw `asyncio.gather()` or bare `await receive_task`.

- **Supervision**: `supervise_tasks()` wraps `asyncio.wait(FIRST_COMPLETED)` — detects both client disconnect and bg task crashes immediately. Classify tasks as finite (can complete during session) or lifetime (completion = session ending).
- **Drain**: `drain_tasks()` cancels remaining bg tasks with bounded timeout, force-cancels stragglers via `asyncio.wait` (not `asyncio.gather`, which hangs if a task suppresses CancelledError).
- **Fan-out**: `gather_safe()` replaces `asyncio.gather(return_exceptions=True)` — semaphore-bounded concurrency, per-item exception logging, typed `GatherResult[T]` return.
- **Interruptible sleep**: `wait_for_event(event, seconds)` replaces `asyncio.sleep()` in polling loops — wakes instantly on disconnect via per-connection `asyncio.Event`. Never bare `asyncio.sleep()` in WS task loops.
- **Receive timeouts**: every `websocket.receive()` must be wrapped in `asyncio.wait_for(..., timeout=WS_RECEIVE_TIMEOUT)`.
- **Gauge placement**: `GAUGE.inc()` inside `try` body, `GAUGE.dec()` in `finally`. Init `bg_main_tasks = []` before `try`.
- **Task naming**: `create_named_task()` for WS-scoped tasks (tracked in task_set for supervise/drain). Use `start_background_task()` from `utils/executors.py` for fire-and-forget work that outlives the handler.
- **Prometheus labels**: static low-cardinality only (e.g. "listen", "chat") — never uid/session_id.
- **Module-level dicts**: add TTL-based eviction or cap size — they grow forever otherwise.

## Common Gotchas

1. **Python 3.11 only** — no 3.12+ syntax (nested same-type quotes in f-strings break the Docker build)
2. **Never `time.sleep()` in async** — use `asyncio.sleep()`. For blocking work: `await run_blocking(executor, fn)` with the appropriate pool
3. **Sync `requests` in async is silent poison** — no error raised, just blocks the entire event loop. All connections freeze, health checks fail, HPA can't scale.
4. **Semaphores are event-loop-bound** — `http_client.py` handles this via `(loop_id, name)` keying. Don't create raw `asyncio.Semaphore` outside that module.
5. **Webhook timeout = 30s** — partner integrations depend on this window. Don't change `httpx.Timeout(30.0, connect=2.0)`.
6. **Firestore collection group queries** need explicit indexes — 500 with no useful error
7. **Mutable WebSocket state races** — snapshot `nonlocal` variables before spawning async work
8. **Silent fire-and-forget drops** — functions gating on connection state must log when dropping work
9. **New fallbacks** — call `utils.observability.fallback.record_fallback`; do not invent a new `*_fallback_total` Counter
10. **`langdetect` unreliable on short text** — don't use on <20 chars or gate paid API calls on interim streaming text
