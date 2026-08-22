"""Account deletion retains one exact S-24-owned Pinecone purge handoff."""

from unittest.mock import MagicMock

import pytest

from database import vector_db


def test_purge_user_vectors_deletes_the_owner_filter_from_both_known_namespaces(monkeypatch):
    index = MagicMock()
    monkeypatch.setattr(vector_db, 'index', index)

    assert vector_db.purge_user_vectors('owner-a') == 2

    assert index.delete.call_args_list == [
        ((), {'filter': {'uid': {'$eq': 'owner-a'}}, 'namespace': 'ns1'}),
        ((), {'filter': {'uid': {'$eq': 'owner-a'}}, 'namespace': vector_db.TRANSCRIPT_CHUNKS_NAMESPACE}),
    ]


def test_purge_user_vectors_fails_closed_when_provider_is_not_configured(monkeypatch):
    monkeypatch.setattr(vector_db, 'index', None)

    with pytest.raises(RuntimeError, match='Pinecone index not initialized'):
        vector_db.purge_user_vectors('owner-a')
