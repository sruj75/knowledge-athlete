"""Fail-open durable export of dev-only parity-pack cassettes to GCS."""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from pathlib import Path
from typing import Mapping
from urllib.parse import urlparse

from google.cloud import storage
from google.oauth2 import service_account

logger = logging.getLogger(__name__)

_DEFAULT_EXPORT_INTERVAL_SECONDS = 3600
_reconcile_lock = threading.Lock()
_reconcile_started = False
_client = None
_client_lock = threading.Lock()


def _parse_gcs_uri(uri: str) -> tuple[str, str] | None:
    value = (uri or "").strip()
    if not value or not value.startswith("gs://"):
        return None
    parsed = urlparse(value)
    bucket = parsed.netloc.strip()
    if not bucket:
        return None
    return bucket, parsed.path.lstrip("/").rstrip("/")


def resolve_export_target(environ: Mapping[str, str] | None = None) -> tuple[str, str] | None:
    env = os.environ if environ is None else environ
    parsed = _parse_gcs_uri((env.get("OMI_PARITY_PACK_GCS_URI") or "").strip())
    if parsed is not None:
        return parsed
    bucket = (env.get("OMI_PARITY_PACK_GCS_BUCKET") or "").strip()
    if not bucket:
        return None
    prefix = (env.get("OMI_PARITY_PACK_GCS_PREFIX") or "parity-pack/v0").strip().strip("/")
    return bucket, prefix


def _object_name(prefix: str, local_path: Path, root: Path) -> str:
    try:
        relative = local_path.resolve().relative_to(root.resolve())
    except ValueError:
        relative = Path("cassettes") / local_path.name
    value = relative.as_posix().lstrip("/")
    return f"{prefix.rstrip('/')}/{value}" if prefix else value


def _storage_client():
    global _client
    if _client is not None:
        return _client
    with _client_lock:
        if _client is not None:
            return _client
        if os.environ.get("SERVICE_ACCOUNT_JSON"):
            info = json.loads(os.environ["SERVICE_ACCOUNT_JSON"])
            credentials = service_account.Credentials.from_service_account_info(info)
            _client = storage.Client(credentials=credentials)
        else:
            project = (os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("FIREBASE_PROJECT_ID") or "").strip()
            _client = storage.Client(project=project) if project else storage.Client()
        return _client


def _record_export_failure() -> None:
    try:
        from utils.observability.fallback import record_fallback

        record_fallback(
            component="other",
            from_mode="parity_pack_gcs_export",
            to_mode="local_only",
            reason="other",
            outcome="degraded",
        )
    except Exception:
        pass


def export_cassette_file(local_path: Path, *, environ: Mapping[str, str] | None = None) -> bool:
    """Upload one local cassette JSON without raising into its product surface."""

    env = os.environ if environ is None else environ
    target = resolve_export_target(env)
    root_value = (env.get("OMI_PARITY_PACK_ROOT") or "").strip()
    path = Path(local_path)
    if target is None or not root_value or not path.is_file():
        return False
    bucket_name, prefix = target
    object_name = _object_name(prefix, path, Path(root_value))
    try:
        blob = _storage_client().bucket(bucket_name).blob(object_name)
        blob.upload_from_filename(str(path), content_type="application/json")
        logger.info("Parity pack cassette exported bucket=%s object=%s", bucket_name, object_name)
        return True
    except Exception as error:
        logger.warning("Parity pack cassette export failed error_type=%s", type(error).__name__)
        _record_export_failure()
        return False


def reconcile_local_cassettes(*, environ: Mapping[str, str] | None = None) -> int:
    env = os.environ if environ is None else environ
    root_value = (env.get("OMI_PARITY_PACK_ROOT") or "").strip()
    if resolve_export_target(env) is None or not root_value:
        return 0
    cassettes = Path(root_value) / "cassettes"
    if not cassettes.is_dir():
        return 0
    return sum(export_cassette_file(path, environ=env) for path in sorted(cassettes.glob("*.json")))


def _export_interval_seconds(environ: Mapping[str, str]) -> int:
    raw = (environ.get("OMI_PARITY_PACK_EXPORT_INTERVAL_SECONDS") or "").strip()
    if not raw:
        return _DEFAULT_EXPORT_INTERVAL_SECONDS
    try:
        return max(60, int(raw))
    except ValueError:
        return _DEFAULT_EXPORT_INTERVAL_SECONDS


def ensure_reconcile_loop(*, environ: Mapping[str, str] | None = None) -> None:
    """Start one daemon that periodically retries local cassette exports."""

    global _reconcile_started
    env = dict(os.environ if environ is None else environ)
    if resolve_export_target(env) is None:
        return
    with _reconcile_lock:
        if _reconcile_started:
            return
        _reconcile_started = True
    interval = _export_interval_seconds(env)

    def _loop() -> None:
        while True:
            try:
                time.sleep(interval)
                reconcile_local_cassettes(environ=env)
            except Exception as error:
                logger.warning("Parity pack cassette reconcile error type=%s", type(error).__name__)

    threading.Thread(target=_loop, name="omi-parity-pack-export-reconcile", daemon=True).start()
