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

This version proves the backend can boot hermetically and that selected Memory CRUD, user/account, storage, listen-routing, retrieval/search, and legacy-shape paths can execute without real Firestore, Redis, GCS, Pinecone, Typesense, Google ADC, or production API keys. Conversation CRUD and task/goal CRUD are deliberately absent: the Mac owns those products locally, while hosted listen persistence remains an internal S-16/S-23 handoff.

| Scenario | Status | Notes |
|---|---:|---|
| CRUD golden path | ✅ Green | Memories use real create/update/delete routes. Public conversation CRUD was retired by S-10; hosted task/goal CRUD was retired by S-13. |
| Canonical Memory ingress | ✅ | The Memory pipeline test invokes the retained server-internal processing seam directly; it does not restore the retired public conversation processing API. |
| Listen/STT route seam | ✅ | `/v4/web/listen` websocket auth/query parsing/custom-STT dispatch is covered; managed-STT scenarios run the real Modulate socket against a loopback peer and inspect retained server-internal persistence directly. S-16 owns final web-listen/protocol retirement. |
| Storage / speech profile | ✅ Green | `google.cloud.storage.Client` is patched to a temp-dir fake; speech-profile presence, signed URL, sample list, and delete paths run through real routes/helpers. |
| User/auth/profile/account | ✅ Green | Auth guard, profile, onboarding, general language, notification/assistant settings, and AI profile are covered. S-10 removed Mac transcription preferences and People CRUD. Account deletion additionally exercises its real admission route, durable marker, opaque Cloud Tasks payload, worker claim, required-purge retry, and idempotent redelivery against local fakes. Firebase deletion, billing lookup, Twilio, and derived-data purge stay controlled test seams. |
| Retrieval/search | ✅ Partial | Memory, conversation summary, and transcript-chunk retrieval routes run through real public APIs with Firestore-backed records and a deterministic in-memory replacement for Pinecone/OpenAI embeddings at the `database.vector_db` client seam. Full Pinecone/Typesense service compatibility remains out of scope. |
| Failure / edge modes | ✅ Partial | Invalid input and edge-case coverage runs. Redis-unavailable, LLM 500, and STT timeout cases are explicitly skipped or deferred until per-test failure fakes are wired. |
| Legacy shape compatibility | ✅ Green | Exercises retained server-internal conversation storage and legacy Memory shapes plus deterministic fake-store repeated writes. It does not expose conversation routes or execute production migration scripts. |

## What is faked or disabled

| Dependency | v1 behavior | Why |
|---|---|---|
| Firestore | `fake-firestore` `MockFirestore` | In-memory datastore backing the real database modules. |
| Redis | `fakeredis` | In-memory Redis replacement. |
| Google Cloud Storage | `google.cloud.storage.Client` patched to a filesystem-backed fake | Enables storage-backed routes without GCS credentials/network. |
| Cloud Tasks / OIDC | Strict in-memory `tasks_v2.CloudTasksClient` plus a local token-verification seam in the account-deletion lifecycle test | Exercises the production task protobuf, queue payload, OIDC identity/audience, and retry headers without a Cloud Tasks control plane or Google token verification. |
| Google ADC | `google.auth.default` returns anonymous credentials | Prevents real credential lookup at import time. |
| Pinecone | `PINECONE_API_KEY` removed globally; targeted retrieval/search tests monkeypatch `database.vector_db.index` to a deterministic in-memory fake | Keeps app import hermetic while allowing route-level vector upsert/query/delete assertions without real Pinecone. |
| Typesense | Dummy host/port/API key | Lets import-time Typesense client construction succeed; retrieval/search tests rely on vector results and fail-open keyword search rather than real Typesense compatibility. |
| Google Translate | Anonymous Google credentials | Allows import-time client construction; v1 tests do not call live translation. |
| LLM/STT/VAD/embeddings | Fake modules scaffolded; route and custom-STT suggested-transcript seams covered where deterministic patching is practical | Kept as v2 work where scenarios need real outbound HTTP/WS/provider assertions. |

## What's real

- FastAPI app import via `main.app`
- Routers, middleware, auth dependency, websocket route entrypoints, Pydantic request/response validation
- Database modules and model serialization/deserialization
- Firestore query/update/delete code paths, backed by `MockFirestore`
- Redis client construction and delegated fakeredis operations
- Storage helper code paths, backed by temp-dir fake GCS

## Running individual scenarios

```bash
# CRUD / data shape
bash backend/testing/e2e/run.sh -k "test_crud"

# Listen/STT websocket route seam
bash backend/testing/e2e/run.sh -k "listen_stt"

# Storage-backed speech profile routes
bash backend/testing/e2e/run.sh -k "storage_speech_profile"

# Retrieval/search seams
bash backend/testing/e2e/run.sh -k "search or retrieval or embedding or vector"

# User/auth/profile/account routes
bash backend/testing/e2e/run.sh -k "user_auth_profile"

# Durable account-deletion Cloud Tasks lifecycle
bash backend/testing/e2e/run.sh -k "account_deletion_cloud_tasks"

# Failure / edge modes
bash backend/testing/e2e/run.sh -k "test_failure_modes"

# Legacy shape compatibility
bash backend/testing/e2e/run.sh -k "test_migration_safety"
```

## Architecture

```text
run.sh
  └── pytest testing/e2e/
        ├── conftest.py                         # env, auth, fake setup, TestClient
        ├── fakes/
        │   ├── firestore.py                    # MockFirestore + seed/read helpers
        │   ├── redis.py                        # FakeRedis + redis.Redis patch
        │   ├── storage.py                      # filesystem-backed fake GCS client
        │   ├── vector_search.py                # deterministic embeddings + in-memory Pinecone-like index
        │   ├── llm.py                          # deterministic LLM fake scaffold
        │   ├── stt.py                          # deterministic custom and managed-STT socket helpers
        │   └── embeddings.py                   # VAD/diarization/embedding fake scaffold
        ├── fixtures/
        │   ├── conversations.json
        │   └── memories.json
        ├── test_crud.py
        ├── test_canonical_memory_pipeline.py
        ├── test_account_deletion_cloud_tasks.py
        ├── test_failure_modes.py
        ├── test_harness_guards.py
        ├── test_listen_stt.py
        ├── test_migration_safety.py
        ├── test_retrieval_search.py
        ├── test_storage_speech_profile.py
        ├── test_user_auth_profile.py
        └── test_webhooks.py
```

## Test lifecycle

1. Set hermetic env vars before importing backend modules.
2. Patch Google auth before any Firestore/Translate client construction.
3. Build in-memory Firestore/Redis fakes and temp-dir fake GCS.
4. Disable dotenv loading so local `.env` files cannot rehydrate real credentials.
5. Patch Firestore/Redis/Storage client constructors before `import main`.
6. Import the real FastAPI app and wrap it with `TestClient`.
7. Clear fake Firestore/Redis/Storage state around each test.
8. Seed retained server-internal data only where a later-slice contract requires it.
9. Run route-level assertions through the real app.

## Adding tests

Prefer real retained public routes. For S-16/S-23-owned listen or datastore behavior, seed through `fakes.firestore.seed_*` and inspect the direct internal seam; do not recreate a public conversation compatibility route.

```python
from fakes.firestore import read_conversation, seed_conversation


def test_server_internal_conversation_fixture(sample_conversation_data):
    seed_conversation("123", sample_conversation_data)
    stored = read_conversation("123", sample_conversation_data["id"])
    assert stored is not None
```

## Current limitations / v2 work

- [x] Add hermetic core-flow coverage for custom-STT listen reconnect/finalize and conversation finalization.
- [ ] Wire deterministic LLM endpoints into all OpenAI/Anthropic/OpenRouter clients used by processing code.
- [ ] Add per-test HTTP failure injection for LLM 500 / timeout scenarios.
- [ ] Add real Redis-unavailable fail-open tests; v1 uses fakeredis-backed paths.
- [ ] Execute production migration scripts against fake fixtures if migration-script coverage is needed.
- [ ] Expand retrieval/search beyond the deterministic in-memory vector seam to cover real Typesense keyword behavior and closer Pinecone response compatibility if those service contracts become in-scope.
- [x] Run under Python 3.11 in CI-like environments; the required `Backend Hermetic E2E` GitHub Action now installs dependencies, prewarms tokenizer cache, and runs the harness.

## Dependencies

- omi backend dependencies from `requirements.txt`
- e2e-only dependencies from `testing/e2e/requirements.txt`
