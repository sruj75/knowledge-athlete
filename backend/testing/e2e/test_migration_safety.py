"""
Scenario 4: Legacy Shape Compatibility

Tests that old-format Firestore documents remain readable by current code and
that fake-store overwrite behavior is deterministic. These tests do not execute
production migration scripts.
"""

from fakes.firestore import read_conversation, read_memories, seed_conversation, seed_memory


class TestLegacyFormatReading:
    """Current code can read old-format Firestore documents."""

    def test_read_legacy_memory_format(self, client, auth_headers, memory_fixture):
        """Old-format memories (missing scoring, category mapping) are readable."""

        legacy_mem = dict(memory_fixture["legacy_format_memory"])
        seed_memory("123", legacy_mem)

        resp = client.get("/v3/memories", headers=auth_headers)
        assert resp.status_code == 200, resp.text
        memories = resp.json()
        found = [m for m in memories if m["id"] == legacy_mem["id"]]
        assert found, f"Legacy memory {legacy_mem['id']} not returned"
        assert found[0]["content"] == legacy_mem["content"]


class TestFakeStoreIdempotency:
    """Fake-store repeated writes should be deterministic."""

    def test_double_write_same_id(self, client, auth_headers):
        """
        Writing a document twice with the same ID overwrites (not duplicates).

        This does not execute production migration scripts; it verifies the
        fake store has deterministic overwrite semantics for stable IDs.
        """

        conv_data = {
            "id": "migration-idempotent-001",
            "created_at": "2025-01-15T17:00:00Z",
            "started_at": "2025-01-15T17:00:00Z",
            "finished_at": "2025-01-15T17:02:00Z",
            "source": "omi",
            "structured": {
                "title": "Migration Test",
                "overview": "",
                "emoji": "🧠",
                "category": "other",
                "action_items": [],
                "events": [],
            },
            "transcript_segments": [],
            "discarded": False,
            "status": "completed",
            "is_locked": False,
        }

        # First write
        seed_conversation("123", conv_data)

        # Second write with same ID should overwrite deterministically.
        updated = dict(conv_data, structured={**conv_data["structured"], "title": "Updated Title"})
        seed_conversation("123", updated)

        # Verify only one doc exists with latest data
        result = read_conversation("123", conv_data["id"])
        assert result is not None
        assert result["structured"]["title"] == "Updated Title"

    def test_memory_migration_idempotency(self, client, auth_headers):
        """
        Writing a memory twice with same ID produces single document.
        """

        mem_data = {
            "id": "mem-mig-idem-001",
            "content": "Migration test memory",
            "category": "interesting",
            "created_at": "2025-01-15T17:00:00Z",
            "updated_at": "2025-01-15T17:00:00Z",
        }

        seed_memory("123", mem_data)
        seed_memory("123", dict(mem_data, content="Updated content"))

        memories = read_memories("123")
        matching = [m for m in memories if m["id"] == mem_data["id"]]
        assert len(matching) == 1
        assert matching[0]["content"] == "Updated content"


class TestFieldShapeEvolution:
    """Test that field shape changes don't break reads."""


class TestCategoryEnumMigration:
    """Test that old category values map to new ones."""

    def test_legacy_category_mapping(self, client, auth_headers):
        """
        Memories with old category values ('core', 'hobbies', etc.) map to
        'system' per the Memory model's validator.
        """

        old_category_mem = {
            "id": "mem-old-cat-001",
            "content": "Memory with legacy category",
            "category": "core",  # Legacy value → maps to 'system'
            "created_at": "2025-01-15T20:00:00Z",
            "updated_at": "2025-01-15T20:00:00Z",
        }
        seed_memory("123", old_category_mem)

        resp = client.post(
            "/v3/memories",
            json={"content": "Trigger read", "category": "manual"},
            headers=auth_headers,
        )

        # List should include the legacy-category memory with mapped value
        resp = client.get("/v3/memories", headers=auth_headers)
        assert resp.status_code == 200, resp.text
        memories = resp.json()
        found = [m for m in memories if m["id"] == old_category_mem["id"]]
        assert found, f"Legacy category memory {old_category_mem['id']} not returned"
        assert found[0]["category"] == "system"
