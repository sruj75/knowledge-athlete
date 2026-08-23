"""GCS helpers retained only for signed desktop update and preview artifacts."""

import datetime
import json
import os
import threading
from typing import Any

from google.cloud import storage
from google.oauth2 import service_account

from database.redis_db import cache_signed_url, get_cached_signed_url


storage_client = None
_storage_client_lock = threading.Lock()
desktop_updates_bucket = os.getenv('BUCKET_DESKTOP_UPDATES')


def _get_storage_client() -> Any:
    """Return the GCS client lazily so imports never probe ADC/GCE metadata."""
    global storage_client
    if storage_client is None:
        with _storage_client_lock:
            if storage_client is None:
                if os.environ.get('SERVICE_ACCOUNT_JSON'):
                    service_account_info = json.loads(os.environ['SERVICE_ACCOUNT_JSON'])
                    credentials = service_account.Credentials.from_service_account_info(service_account_info)  # type: ignore[reportUnknownMemberType]  # google.oauth2 partial stubs
                    storage_client = storage.Client(credentials=credentials)
                else:
                    project = (
                        os.environ.get('GOOGLE_CLOUD_PROJECT') or os.environ.get('FIREBASE_PROJECT_ID') or ''
                    ).strip()
                    storage_client = storage.Client(project=project) if project else storage.Client()
    return storage_client


def _get_signed_url(blob: Any, minutes: int) -> str:
    if cached := get_cached_signed_url(blob.name):
        return cached

    signed_url: str = blob.generate_signed_url(
        version='v4', expiration=datetime.timedelta(minutes=minutes), method='GET'
    )
    cache_signed_url(blob.name, signed_url, minutes * 60)
    return signed_url


def get_desktop_update_signed_url(blob_path: str, expiration_hours: int = 1) -> str:
    """Generate a short-lived signed URL for one retained update artifact."""
    bucket = _get_storage_client().bucket(desktop_updates_bucket)
    return _get_signed_url(bucket.blob(blob_path), expiration_hours * 60)
