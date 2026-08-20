"""
Scenario 4: Legacy Shape Compatibility

Tests that old-format Firestore documents remain readable by current code and
that fake-store overwrite behavior is deterministic. These tests do not execute
production migration scripts.
"""

from fakes.firestore import read_conversation, seed_conversation


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
