"""
Pytest configuration and shared fixtures for hermetic e2e tests.

The harness imports the REAL FastAPI backend and uses fake or disabled
external-service boundaries for the v1 scenarios. Tests fail on non-local
network attempts so accidental real service calls are surfaced.
"""

import os
import sys
from pathlib import Path
from typing import Generator

# ─── CRITICAL: Patch Google auth BEFORE any Firestore import ──────────
# database/_client.py calls firestore.Client() at MODULE level (line 14).
# If google.auth.default tries real credentials → DefaultCredentialsError.
# We intercept it here so the client constructor never hits the network.
import google.auth.credentials
import google.auth as _ga_mod

_original_ga_default = getattr(_ga_mod, 'default', None)


def _fake_google_auth_default(scopes=None, request=None, **kwargs):
    """Return anonymous credentials so Google clients can construct without ADC lookup."""
    return google.auth.credentials.AnonymousCredentials(), "test-e2e-project"


if _original_ga_default is not None:
    _ga_mod.default = _fake_google_auth_default

import dotenv
import pytest

# ─── Paths ──────────────────────────────────────────────────────────────

E2E_DIR = Path(__file__).parent
BACKEND_DIR = E2E_DIR.parent.parent
PROJECT_ROOT = BACKEND_DIR.parent

# Insert backend dir first so `from database import ...` resolves
backend_str = str(BACKEND_DIR)
if backend_str not in sys.path:
    sys.path.insert(0, backend_str)

# Also insert e2e dir for fakes package
e2e_str = str(E2E_DIR)
if e2e_str not in sys.path:
    sys.path.insert(0, e2e_str)

from testing.hermetic_network import block_outbound_network


# ─── Environment variables (set BEFORE any omi imports) ────────────────


def _set_e2e_env():
    """Configure environment so the backend runs in hermetic test mode.

    Deliberately overwrite external-service credentials instead of using
    setdefault() so a developer's shell cannot leak real API keys into e2e runs.
    """
    os.environ["PYTHON_DOTENV_DISABLED"] = "1"
    os.environ["LOCAL_DEVELOPMENT"] = "true"
    os.environ["FIREBASE_PROJECT_ID"] = "test-e2e-project"
    os.environ["GOOGLE_CLOUD_PROJECT"] = "test-e2e-project"
    os.environ.pop("SERVICE_ACCOUNT_JSON", None)
    os.environ.pop("GOOGLE_APPLICATION_CREDENTIALS", None)
    os.environ["REDIS_DB_HOST"] = "localhost"
    os.environ["REDIS_DB_PORT"] = "6379"
    os.environ["REDIS_DB_PASSWORD"] = ""
    os.environ["OPENAI_API_KEY"] = "fake-openai-key"
    os.environ["GEMINI_API_KEY"] = "fake-gemini-key"
    os.environ["BUCKET_DESKTOP_UPDATES"] = "desktop-updates"
    os.environ["DEV_WEBHOOK_RETRY_DELAYS"] = "0,0,0"
    os.environ["BILLING_MODE"] = "disabled"
    os.environ["ADMIN_KEY"] = ""
    for proxy_var in (
        "HTTP_PROXY",
        "HTTPS_PROXY",
        "ALL_PROXY",
        "NO_PROXY",
        "http_proxy",
        "https_proxy",
        "all_proxy",
        "no_proxy",
    ):
        os.environ.pop(proxy_var, None)


def _disabled_load_dotenv(*args, **kwargs):
    """Prevent backend/main.py from rehydrating real local secrets from .env."""
    return False


_set_e2e_env()
dotenv.load_dotenv = _disabled_load_dotenv


# ─── Network guard ──────────────────────────────────────────────────────

_network_guard = None


def pytest_sessionstart(session):
    """Install the shared fail-closed socket guard before test collection."""
    global _network_guard
    _network_guard = block_outbound_network()
    _network_guard.__enter__()


def pytest_sessionfinish(session, exitstatus):
    global _network_guard
    if _network_guard is not None:
        _network_guard.__exit__(None, None, None)
        _network_guard = None


# ─── Fake service initialization ───────────────────────────────────────


@pytest.fixture(scope="session")
def fake_firestore():
    """Session-scoped MockFirestore — initialized once, shared across all tests."""
    from fakes.firestore import setup_fake_firestore, teardown_fake_firestore

    store = setup_fake_firestore()
    yield store
    teardown_fake_firestore()


@pytest.fixture(scope="session")
def fake_redis():
    """Session-scoped FakeRedis — initialized once."""
    from fakes.redis import setup_fake_redis, teardown_fake_redis

    r = setup_fake_redis()
    yield r
    teardown_fake_redis()


@pytest.fixture(scope="session")
def fake_storage():
    """Session-scoped temp-dir storage fake."""
    from fakes.storage import setup_fake_storage, teardown_fake_storage

    s = setup_fake_storage()
    yield s
    teardown_fake_storage()


# ─── Backend app factory (cached per-session) ───────────────────────────

_app_cache = None


def _create_backend_app(fake_firestore_instance, fake_redis_instance, fake_storage_instance):
    """
    Create the real FastAPI app with patched dependencies.

    This is called once per session and cached. Returns the raw app object,
    not a TestClient (TestClient is created per-test for isolation).
    """
    global _app_cache
    if _app_cache is not None:
        return _app_cache

    from fakes.firestore import patch_google_firestore
    from fakes.redis import patch_redis_client
    from fakes.storage import patch_google_storage

    # Patch must happen before database/storage modules are imported
    patch_google_firestore()
    patch_redis_client()
    patch_google_storage()

    # Initialize Firebase Admin SDK with fake credentials
    import firebase_admin

    try:
        firebase_admin.get_app()
    except ValueError:
        try:
            firebase_admin.initialize_app(
                firebase_admin.credentials.Certificate(
                    {
                        "type": "service_account",
                        "project_id": "test-e2e-project",
                        "private_key_id": "fake",
                        "private_key": "fake",
                        "client_email": "fake@test-e2e-project.iam.gserviceaccount.com",
                        "client_id": "123",
                    }
                )
            )
        except Exception:
            pass  # May fail in test env; ok for LOCAL_DEVELOPMENT mode

    # Import the real FastAPI app (triggers all backend module imports)
    import main as backend_main

    # Some backend modules bind ``db`` with ``from database._client import db``
    # at import time. Relink that legacy Firestore singleton while Redis uses its
    # explicit injectable production boundary.
    import database._client as db_client
    from database.redis_connection import set_redis_client_for_testing

    old_db = db_client.db
    db_client.db = fake_firestore_instance
    set_redis_client_for_testing(fake_redis_instance)
    for module in list(sys.modules.values()):
        if module is None:
            continue
        for attr_name, attr_value in list(vars(module).items()):
            try:
                if attr_value is old_db:
                    setattr(module, attr_name, fake_firestore_instance)
            except Exception:
                continue

    _app_cache = backend_main.app
    return _app_cache


# ─── Backend TestClient — function scoped for test isolation ─────────────


@pytest.fixture()
def client(fake_firestore, fake_redis, fake_storage):
    """
    Build a FastAPI TestClient wrapping the REAL omi backend.

    This is the core fixture — it patches Firestore/Redis at the network
    boundary, sets env vars, then imports and wraps the actual app.
    All router logic, auth, encryption, middleware runs for real.
    """
    app = _create_backend_app(fake_firestore, fake_redis, fake_storage)

    from fastapi.testclient import TestClient
    import logging

    logging.disable(logging.CRITICAL)
    tc = TestClient(app)
    yield tc
    logging.disable(logging.NOTSET)


# ─── Auth helpers ───────────────────────────────────────────────────────

DEV_UID = "123"
DEV_AUTH_HEADERS = {"Authori" + "zation": "Bearer dev-token"}


@pytest.fixture(autouse=True)
def isolate_e2e_state(fake_firestore, fake_redis, fake_storage):
    """Clear mutable fake service state before and after each test."""
    from fakes.firestore import clear_user_data
    from fakes.storage import clear_fake_storage

    def clear_state():
        clear_user_data(DEV_UID)
        fake_redis.flushall()
        clear_fake_storage()
        try:
            import utils.http_client as http_client

            http_client._webhook_circuit_breakers.clear()
        except Exception:
            pass
        try:
            from database.redis_connection import set_redis_client_for_testing

            set_redis_client_for_testing(fake_redis)
        except Exception:
            pass

    clear_state()
    yield
    clear_state()


@pytest.fixture()
def auth_headers():
    """Return dev-token auth headers for each test."""
    return dict(DEV_AUTH_HEADERS)


# ─── Test data fixtures ────────────────────────────────────────────────


@pytest.fixture()
def test_uid():
    """Return the fixed dev-test UID."""
    return DEV_UID


# ─── Utility fixtures ──────────────────────────────────────────────────


@pytest.fixture()
def fresh_uid():
    """Generate a unique UID per test for isolation."""
    import uuid

    return str(uuid.uuid4())
