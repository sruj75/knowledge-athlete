"""Deterministic Firestore document id helpers.

Keep natural-key seed construction in one low-dependency module so database
callers do not hand-roll subtly different id formats.
"""

import hashlib
import uuid


def document_id_from_seed(seed: str) -> str:
    """Return a stable UUIDv4-shaped document id for a natural-key seed."""
    seed_hash = hashlib.sha256(seed.encode('utf-8')).digest()
    return str(uuid.UUID(bytes=seed_hash[:16], version=4))
