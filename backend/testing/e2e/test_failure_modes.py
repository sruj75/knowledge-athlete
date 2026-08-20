"""
Scenario 3: Failure Modes

Tests that selected invalid inputs and edge cases behave deterministically.
Full LLM, Redis-unavailable, and STT failure simulations are explicit v2 work.
"""


class TestRedisFakePaths:
    """Verify CRUD routes work with fakeredis-backed Redis paths."""

    def test_crud_works_with_fake_redis(self, client, auth_headers):
        """Basic CRUD operations succeed with fakeredis-backed Redis operations."""
        # Create action item (triggers rate limiting + Redis ops)
        resp = client.post(
            "/v1/action-items",
            json={"description": "Redis fail-open test"},
            headers=auth_headers,
        )
        assert resp.status_code == 200, f"Should succeed with fakeredis: {resp.text}"

    def test_empty_action_item_description_rejected(self, client, auth_headers):
        """Empty descriptions are rejected by TaskCreate min_length=1 validation."""
        resp = client.post(
            "/v1/action-items",
            json={"description": ""},
            headers=auth_headers,
        )
        assert resp.status_code == 422, resp.text


class TestEdgeCases:
    """Edge cases and boundary conditions."""

    def test_long_action_item_description(self, client, auth_headers):
        """Very long descriptions are handled correctly."""
        long_desc = "A" * 1000
        resp = client.post(
            "/v1/action-items",
            json={"description": long_desc},
            headers=auth_headers,
        )
        assert resp.status_code == 200, f"Long AI should work: {resp.text}"
        ai_id = resp.json()["id"]
        read_resp = client.get(f"/v1/action-items/{ai_id}", headers=auth_headers)
        assert read_resp.status_code == 200, read_resp.text
        assert read_resp.json()["description"] == long_desc
