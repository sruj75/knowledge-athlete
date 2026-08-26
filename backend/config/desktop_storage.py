"""Validated coordinate for the retained desktop update/preview bucket."""

from __future__ import annotations

import os
import re

_BUCKET_RE = re.compile(r'^[a-z0-9][a-z0-9._-]{1,61}[a-z0-9]$')
_RETAINED_PREFIXES = ('updates/', 'previews/')


def desktop_updates_bucket() -> str:
    bucket = os.getenv('BUCKET_DESKTOP_UPDATES', '').strip()
    if not bucket:
        raise RuntimeError('BUCKET_DESKTOP_UPDATES is required')
    if not _BUCKET_RE.fullmatch(bucket):
        raise RuntimeError('BUCKET_DESKTOP_UPDATES must be a valid explicit GCS bucket name')
    return bucket


def retained_desktop_artifact_path(path: str) -> str:
    normalized = path.strip().lstrip('/')
    if not normalized.startswith(_RETAINED_PREFIXES) or '..' in normalized.split('/'):
        raise ValueError('desktop artifact path must remain under updates/ or previews/')
    return normalized
