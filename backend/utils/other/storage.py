"""GCS helpers retained only for signed desktop update and preview artifacts."""

import datetime
import os
import threading
from typing import Any

from google.auth.transport.requests import Request
from google.cloud import storage
from config.desktop_storage import desktop_updates_bucket, retained_desktop_artifact_path
from database.redis_db import cache_signed_url, get_cached_signed_url


storage_client = None
_storage_client_lock = threading.Lock()


def _get_storage_client() -> Any:
    """Return the GCS client lazily so imports never probe ADC/GCE metadata."""
    global storage_client
    if storage_client is None:
        with _storage_client_lock:
            if storage_client is None:
                project = (
                    os.environ.get('GOOGLE_CLOUD_PROJECT') or os.environ.get('FIREBASE_PROJECT_ID') or ''
                ).strip()
                storage_client = storage.Client(project=project) if project else storage.Client()
    return storage_client


def _hosted_signing_kwargs(client: Any) -> dict[str, Any]:
    """Use IAM signBlob with attached ADC instead of a downloaded private key."""
    if os.getenv('OMI_ENV_STAGE', '').strip().lower() not in {'dev', 'prod'}:
        return {}
    service_account_email = os.getenv('BACKEND_RUNTIME_SERVICE_ACCOUNT', '').strip()
    if not service_account_email:
        raise RuntimeError('BACKEND_RUNTIME_SERVICE_ACCOUNT is required for hosted signed URLs')
    credentials = getattr(client, '_credentials', None)
    if credentials is None:
        raise RuntimeError('hosted Storage ADC credentials are unavailable')
    if not getattr(credentials, 'token', None) or not getattr(credentials, 'valid', False):
        credentials.refresh(Request())
    access_token = getattr(credentials, 'token', None)
    if not access_token:
        raise RuntimeError('hosted Storage ADC credentials did not yield an access token')
    return {
        'credentials': credentials,
        'service_account_email': service_account_email,
        'access_token': access_token,
    }


def _get_signed_url(blob: Any, minutes: int, *, client: Any) -> str:
    if cached := get_cached_signed_url(blob.name):
        return cached

    signed_url: str = blob.generate_signed_url(
        version='v4',
        expiration=datetime.timedelta(minutes=minutes),
        method='GET',
        **_hosted_signing_kwargs(client),
    )
    cache_signed_url(blob.name, signed_url, minutes * 60)
    return signed_url


def get_desktop_update_signed_url(blob_path: str, expiration_hours: int = 1) -> str:
    """Generate a short-lived signed URL for one retained update artifact."""
    bucket_name = desktop_updates_bucket()
    retained_path = retained_desktop_artifact_path(blob_path)
    client = _get_storage_client()
    bucket = client.bucket(bucket_name)
    return _get_signed_url(bucket.blob(retained_path), expiration_hours * 60, client=client)
