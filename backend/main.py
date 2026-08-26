import asyncio
import logging
import os

from utils.env_loader import load_backend_env

load_backend_env()  # No-op if no env files exist (production); stage + local overrides otherwise

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

import firebase_admin
from fastapi import FastAPI
from starlette.middleware.cors import CORSMiddleware

from database.google_credentials import prepare_google_credentials

prepare_google_credentials()

from routers import (
    chat,
    transcribe,
    omni_relay,
    auto_model,
    users,
    payment,
    auth,
    other,
    updates,
    metrics,
    fair_use_admin,
    fair_use_reviews,
    advice,
    chat_sessions,
    desktop_chat,
    desktop_core,
    desktop_proxy,
    desktop_realtime,
    desktop_tts_updates,
    conversation_compute,
    memory_compute,
)

from utils.other.timeout import TimeoutMiddleware
from utils.observability import log_langsmith_status
from utils.billing.config import validate_billing_config
from utils.http_client import close_all_clients
from utils.executors import (
    drain_background_tasks,
    log_executor_health,
    run_blocking,
    db_executor,
)
from utils.executors import start_background_task
from utils.cloud_tasks import validate_account_deletion_dispatch_configuration
from services.users.account_deletion import reconcile_pending_deletion_wipes

# Log LangSmith tracing status at startup
log_langsmith_status()

# Validate active billing configuration without constructing a provider client.
validate_billing_config()

_auth_emulator_host = os.environ.get("FIREBASE_AUTH_EMULATOR_HOST", "").strip()
if _auth_emulator_host:
    for _adc_key in ("GOOGLE_APPLICATION_CREDENTIALS", "SERVICE_ACCOUNT_JSON"):
        os.environ.pop(_adc_key, None)
    _firebase_project_id = (
        os.environ.get("FIREBASE_AUTH_PROJECT_ID") or os.environ.get("FIREBASE_PROJECT_ID") or "demo-omi-local"
    )
    firebase_admin.initialize_app(options={"projectId": _firebase_project_id})  # type: ignore[reportUnknownMemberType]  # firebase_admin untyped
else:
    firebase_admin.initialize_app()  # type: ignore[reportUnknownMemberType]  # firebase_admin untyped

app = FastAPI()

# Explicit, default-deny CORS: this API is Bearer-token authenticated (mobile/
# desktop apps, not ambient browser cookies), so no cross-origin browser
# caller needs to be allowed by default. CORS_ALLOWED_ORIGINS lets an operator
# opt a specific web frontend in (comma-separated exact origins — never "*",
# and never combined with allow_credentials, which would let any site read
# authenticated responses for a signed-in visitor).
_cors_allowed_origins = [o.strip() for o in os.getenv('CORS_ALLOWED_ORIGINS', '').split(',') if o.strip()]
if '*' in _cors_allowed_origins:
    raise RuntimeError('CORS_ALLOWED_ORIGINS must not contain "*" — list explicit origins instead')
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_allowed_origins,
    allow_credentials=False,
    allow_methods=['*'],
    allow_headers=['*'],
)

app.include_router(transcribe.router)
app.include_router(omni_relay.router)
app.include_router(auto_model.router)
app.include_router(chat.router)
# app.include_router(screenpipe.router)
app.include_router(users.router)
app.include_router(conversation_compute.router)
app.include_router(memory_compute.router)

app.include_router(other.router)

app.include_router(updates.router)

app.include_router(auth.router)  # Added auth router (for the main Omi App, this is the core auth router)


app.include_router(payment.router)
app.include_router(metrics.router)
app.include_router(fair_use_admin.router)
app.include_router(fair_use_reviews.router)
app.include_router(advice.router)
app.include_router(chat_sessions.router)
app.include_router(desktop_core.router)
app.include_router(desktop_chat.router)
app.include_router(desktop_proxy.router)
app.include_router(desktop_realtime.router)
app.include_router(desktop_tts_updates.router)


methods_timeout = {
    "GET": os.environ.get('HTTP_GET_TIMEOUT'),
    "POST": os.environ.get('HTTP_POST_TIMEOUT'),
    "PUT": os.environ.get('HTTP_PUT_TIMEOUT'),
    "PATCH": os.environ.get('HTTP_PATCH_TIMEOUT'),
    "DELETE": os.environ.get('HTTP_DELETE_TIMEOUT'),
}

paths_timeout = {
    "/v1/users/account-deletion-wipes/run": os.environ.get('HTTP_ACCOUNT_DELETION_WIPE_RUN_TIMEOUT', 1500),
}

app.add_middleware(TimeoutMiddleware, methods_timeout=methods_timeout, paths_timeout=paths_timeout)


@app.on_event("startup")  # type: ignore[reportDeprecated]  # FastAPI on_event still functional; lifespan migration would change app wiring
async def startup_event():
    validate_account_deletion_dispatch_configuration()
    asyncio.create_task(log_executor_health())
    # Drain account-deletion wipes orphaned by a previous deploy/restart. Offloaded
    # to db_executor so the blocking Firestore queries don't stall event-loop startup.
    start_background_task(
        run_blocking(db_executor, _drain_pending_deletion_wipes),
        name='startup_deletion_wipe_reconcile',
    )
    # Periodic reconciliation ensures stale retrying claims (worker crashed) and
    # new pending/failed wipes are retried without requiring a restart.
    start_background_task(_periodic_deletion_wipe_reconcile(), name='periodic_deletion_wipe_reconcile')


def _drain_pending_deletion_wipes():
    """Best-effort reconciliation of pending/failed account-deletion wipes on startup."""
    try:
        result = reconcile_pending_deletion_wipes()
        if result.get('requeued'):
            logger.info(f"Startup deletion-wipe reconciliation: {result}")
    except Exception as e:
        logger.error(f"Startup deletion-wipe reconciliation failed: {e}")


async def _periodic_deletion_wipe_reconcile(interval_seconds: int = 300):
    """Periodically reconcile orphaned or failed account-deletion wipes.

    Runs every 5 minutes (default) so stale retrying claims and new
    pending/failed wipes are retried without requiring a restart.
    """
    while True:
        await asyncio.sleep(interval_seconds)
        try:
            result = await run_blocking(db_executor, reconcile_pending_deletion_wipes)
            if result.get('requeued'):
                logger.info(f"Periodic deletion-wipe reconciliation: {result}")
        except Exception as e:
            logger.error(f"Periodic deletion-wipe reconciliation failed: {e}")


@app.on_event("shutdown")  # type: ignore[reportDeprecated]  # FastAPI on_event still functional; lifespan migration would change app wiring
async def shutdown_event():
    # Cloud Run sends SIGKILL about ten seconds after SIGTERM. Leave margin for
    # uvicorn/process teardown after bounded task drain and client closure.
    await drain_background_tasks(timeout=7.0)
    try:
        await asyncio.wait_for(close_all_clients(), timeout=1.0)
    except TimeoutError:
        logger.warning('HTTP client shutdown exceeded its one-second budget')
