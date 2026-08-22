# Hermetic Backend E2E Harness

A manually runnable integration test suite that imports the **real omi FastAPI backend** and exercises selected routes against **faked or disabled external dependencies**. It is intended as a local dogfood harness and a required GitHub Actions check for backend PRs that touch `backend/**`.

The run installs a local-only socket guard before importing backend code. Any non-local DNS/socket attempt raises an assertion, so real API calls fail the harness instead of silently leaking. The runner also wraps pytest in a process-level timeout (`E2E_PYTEST_TIMEOUT`, default `120s`) so websocket/provider-seam regressions fail instead of hanging indefinitely.

Run it with:

```bash
bash backend/testing/e2e/run.sh
```

Install e2e-only dependencies once with:

```bash
cd backend
python -m pip install -r testing/e2e/requirements.txt
```

`run.sh` verifies these dependencies are present but does not install them dynamically, so the test entrypoint itself does not reach PyPI before pytest imports the socket guard.

## Scope of v1

This version proves the backend can boot hermetically and that selected retained user/account and durable account-deletion paths execute without real Firestore, Redis, GCS, Google ADC, or production API keys. Conversation, Memory, task, goal, People, notification, and recording products are deliberately absent because the Mac owns those products locally. The authenticated transient listen route is exercised separately by `tests/unit/test_listen_transient_contract.py` with the real FastAPI route/runtime and a fake Modulate socket.

| Scenario | Status | Notes |
|---|---:|---|
| Listen/STT route seam | ✅ | `/v4/listen` authentication, exact query parsing, fixed audio contract, managed Modulate transport, direct segment delivery, and optional translation are covered without server conversation persistence. `/v4/web/listen` is retired. |
| Storage bootstrap | ✅ Green | `google.cloud.storage.Client` is patched to a temp-dir fake so the S-25-owned finalization drain cannot contact GCS. No customer recording or speech-profile route is exercised. |
| User/auth/profile/account | ✅ Green | Auth guard, account profile, and general language are covered. Account deletion additionally exercises its real admission route, durable marker, opaque Cloud Tasks payload, worker claim, retained fail-closed cleanup, and idempotent redelivery against local fakes. Firebase deletion and billing lookup stay controlled test seams. |
| Removed product boundaries | ✅ Green | Product route/schema absence is owned by the focused S-23 unit contracts; the harness contains no hosted conversation, People, recording, notification, or retrieval fixture. |

## What is faked or disabled

| Dependency | v1 behavior | Why |
|---|---|---|
| Firestore | `fake-firestore` `MockFirestore` | In-memory datastore backing the real database modules. |
| Redis | `fakeredis` | In-memory Redis replacement. |
| Google Cloud Storage | `google.cloud.storage.Client` patched to a filesystem-backed fake | Keeps shared S-25 drain imports hermetic without restoring customer storage routes. |
| Cloud Tasks / OIDC | Strict in-memory `tasks_v2.CloudTasksClient` plus a local token-verification seam in the account-deletion lifecycle test | Exercises the production task protobuf, queue payload, OIDC identity/audience, and retry headers without a Cloud Tasks control plane or Google token verification. |
| Google ADC | `google.auth.default` returns anonymous credentials | Prevents real credential lookup at import time. |
| Google Translate | Anonymous Google credentials | Allows import-time client construction; v1 tests do not call live translation. |
| LLM/STT/VAD/embeddings | Fake modules scaffolded; route and custom-STT suggested-transcript seams covered where deterministic patching is practical | Kept as v2 work where scenarios need real outbound HTTP/WS/provider assertions. |

## What's real

- FastAPI app import via `main.app`
- Routers, middleware, auth dependency, websocket route entrypoints, Pydantic request/response validation
- Retained account database modules and profile serialization
- Firestore query/update/delete code paths, backed by `MockFirestore`
- Redis client construction and delegated fakeredis operations
- Storage client construction, backed by temp-dir fake GCS

## Running individual scenarios

```bash
# User/auth/profile/account routes
bash backend/testing/e2e/run.sh -k "user_auth_profile"

# Durable account-deletion Cloud Tasks lifecycle
bash backend/testing/e2e/run.sh -k "account_deletion_cloud_tasks"

# Hermetic boot and socket guards
bash backend/testing/e2e/run.sh -k "harness_guards"
```

## Architecture

```text
run.sh
  └── pytest testing/e2e/
        ├── conftest.py                         # env, auth, fake setup, TestClient
        ├── fakes/
        │   ├── firestore.py                    # MockFirestore retained-account support
        │   ├── redis.py                        # FakeRedis + redis.Redis patch
        │   ├── storage.py                      # filesystem-backed fake GCS client
        │   ├── llm.py                          # deterministic LLM fake scaffold
        │   ├── stt.py                          # deterministic custom and managed-STT socket helpers
        │   └── embeddings.py                   # VAD/diarization/embedding fake scaffold
        ├── test_account_deletion_cloud_tasks.py
        ├── test_harness_guards.py
        └── test_user_auth_profile.py
```

## Test lifecycle

1. Set hermetic env vars before importing backend modules.
2. Patch Google auth before any Firestore/Translate client construction.
3. Build in-memory Firestore/Redis fakes and temp-dir fake GCS.
4. Disable dotenv loading so local `.env` files cannot rehydrate real credentials.
5. Patch Firestore/Redis/Storage client constructors before `import main`.
6. Import the real FastAPI app and wrap it with `TestClient`.
7. Clear fake Firestore/Redis/Storage state around each test.
8. Seed only retained account state or an exact later-slice handoff.
9. Run route-level assertions through the real app.

## Adding tests

Prefer real retained public routes and durable worker paths. Product absence belongs in focused assembled-app 404/schema tests; do not add hosted conversation, People, notification, recording, or retrieval fixtures to this harness.

## Current limitations / v2 work

- [x] Add hermetic core-flow coverage for custom-STT listen reconnect/finalize and conversation finalization.
- [ ] Wire deterministic retained LLM endpoints into all in-scope provider clients.
- [ ] Add per-test HTTP failure injection for LLM 500 / timeout scenarios.
- [ ] Add real Redis-unavailable fail-open tests; v1 uses fakeredis-backed paths.
- [x] Run under Python 3.11 in CI-like environments; the required `Backend Hermetic E2E` GitHub Action now installs dependencies, prewarms tokenizer cache, and runs the harness.

## Dependencies

- omi backend dependencies from `requirements.txt`
- e2e-only dependencies from `testing/e2e/requirements.txt`
