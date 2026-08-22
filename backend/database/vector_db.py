"""Exact S-24 Pinecone account-deletion handoff.

S-23 removes every product query/upsert/metadata reader. S-24 owns physical
Pinecone teardown and will delete this final purge seam.
"""

from __future__ import annotations

import os
from typing import Any

from pinecone import Pinecone

TRANSCRIPT_CHUNKS_NAMESPACE = 'ns_tchunks'

_api_key = os.getenv('PINECONE_API_KEY')
_index_name = os.getenv('PINECONE_INDEX_NAME')
index: Any = None
if _api_key and _index_name:
    index = Pinecone(api_key=_api_key).Index(_index_name)


def purge_user_vectors(uid: str) -> int:
    """Delete one owner's two historical namespaces or fail closed."""
    if index is None:
        raise RuntimeError('Pinecone index not initialized for account deletion')
    for namespace in ('ns1', TRANSCRIPT_CHUNKS_NAMESPACE):
        index.delete(filter={'uid': {'$eq': uid}}, namespace=namespace)
    return 2
