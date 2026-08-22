"""Canonical guard after S-23 retired product vector maintenance.

The historical failure class covered best-effort product query/upsert helpers.
Those helpers no longer exist. The only retained boundary is the S-24-owned,
fail-closed account-deletion purge, whose retention obligation is explicitly
outside that failure class.
"""

import pytest

import database.vector_db as vector_db


def test_product_vector_maintenance_helpers_remain_retired():
    for name in (
        'query_vectors_by_metadata',
        'upsert_vector2',
        'update_vector_metadata',
    ):
        assert not hasattr(vector_db, name)


def test_account_deletion_purge_stays_loud_without_the_s24_index(monkeypatch):
    monkeypatch.setattr(vector_db, 'index', None)

    with pytest.raises(RuntimeError, match='Pinecone index not initialized'):
        vector_db.purge_user_vectors('owner-1')
