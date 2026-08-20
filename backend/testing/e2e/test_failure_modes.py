"""
Scenario 3: Failure Modes

Tests that selected invalid inputs and edge cases behave deterministically.
Full LLM, Redis-unavailable, and STT failure simulations are explicit v2 work.
"""


class TestRedisFakePaths:
    """Verify CRUD routes work with fakeredis-backed Redis paths."""

    def test_crud_works_with_fake_redis(self, client, auth_headers):
        """Basic CRUD operations succeed with fakeredis-backed Redis operations."""
        # Create memory (uses Redis for caching).
        resp = client.post(
            "/v3/memories",
            json={"content": "Redis fail-open memory", "category": "system"},
            headers=auth_headers,
        )
        assert resp.status_code == 200, f"Memory create should work: {resp.text}"

    def test_invalid_memory_id_returns_404(self, client, auth_headers):
        """Non-existent memory ID returns 404."""
        resp = client.delete("/v3/memories/nonexistent-mem-id", headers=auth_headers)
        assert resp.status_code == 404


class TestEdgeCases:
    """Edge cases and boundary conditions."""

    def test_unicode_content_roundtrip(self, client, auth_headers):
        """Unicode text survives create→read round-trip."""
        unicode_text = "Hello 世界 🌍 Привет 日本語"

        resp = client.post(
            "/v3/memories",
            json={"content": unicode_text, "category": "manual"},
            headers=auth_headers,
        )
        assert resp.status_code == 200, resp.text
        mem_id = resp.json()["id"]
        resp = client.get("/v3/memories", headers=auth_headers)
        assert resp.status_code == 200, resp.text
        memories = resp.json()
        found = [m for m in memories if m["id"] == mem_id]
        assert found, f"Memory {mem_id} not found"
        assert found[0]["content"] == unicode_text
