"""Bounded Firestore list reads for retained hosted products."""

from unittest.mock import patch


def test_legacy_get_memories_no_first_page_5000_force():
    import routers.memories as mem

    calls = []

    def fake_get(uid, limit, offset):
        calls.append((uid, limit, offset))
        return []

    with patch.object(mem.memories_db, 'get_memories', side_effect=fake_get):
        mem._legacy_get_memories('u', limit=100, offset=0)
    assert calls == [('u', 100, 0)]

    with patch.object(mem.memories_db, 'get_memories', side_effect=fake_get):
        mem._legacy_get_memories('u', limit=9999, offset=0)
    assert calls[-1] == ('u', 500, 0)
