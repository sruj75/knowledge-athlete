"""
Scenario 1: CRUD Golden Path

Tests basic create-read-update-delete round-trips for action items and memories
through the real API with fake backend services.

Assertions focus on real route behavior and durable postconditions through the
request → router → database → response cycle.
"""


class TestActionItemCRUD:
    """Action item lifecycle: create → read → update → delete."""

    def test_create_and_read_action_item(self, client, auth_headers, sample_action_item_data):
        """Create an action item and read it back."""
        resp = client.post(
            "/v1/action-items",
            json=sample_action_item_data,
            headers=auth_headers,
        )
        assert resp.status_code == 200, f"Create AI failed: {resp.text}"

        body = resp.json()
        ai_id = body["id"]
        assert body["description"] == sample_action_item_data["description"]
        assert body["completed"] is False
        assert ai_id is not None

        # Read back
        resp = client.get(f"/v1/action-items/{ai_id}", headers=auth_headers)
        assert resp.status_code == 200
        assert resp.json()["description"] == sample_action_item_data["description"]

    def test_list_action_items(self, client, auth_headers):
        """Create multiple action items and list them."""
        create_a = client.post("/v1/action-items", json={"description": "Task A"}, headers=auth_headers)
        create_b = client.post("/v1/action-items", json={"description": "Task B"}, headers=auth_headers)
        assert create_a.status_code == 200, create_a.text
        assert create_b.status_code == 200, create_b.text
        created_ids = {create_a.json()["id"], create_b.json()["id"]}

        resp = client.get("/v1/action-items", headers=auth_headers)
        assert resp.status_code == 200

        body = resp.json()
        items = body.get("action_items", [])
        by_id = {i["id"]: i for i in items}
        assert created_ids.issubset(by_id.keys())
        assert {by_id[item_id]["description"] for item_id in created_ids} == {"Task A", "Task B"}

    def test_update_action_item(self, client, auth_headers):
        """Update an action item's description."""
        create_resp = client.post(
            "/v1/action-items",
            json={"description": "Original task"},
            headers=auth_headers,
        )
        assert create_resp.status_code == 200, create_resp.text
        ai_id = create_resp.json()["id"]

        resp = client.patch(
            f"/v1/action-items/{ai_id}",
            json={"description": "Updated task description"},
            headers=auth_headers,
        )
        assert resp.status_code == 200
        assert resp.json()["description"] == "Updated task description"

    def test_delete_action_item(self, client, auth_headers):
        """Delete an action item and verify it's gone."""
        create_resp = client.post(
            "/v1/action-items",
            json={"description": "To be deleted"},
            headers=auth_headers,
        )
        assert create_resp.status_code == 200, create_resp.text
        ai_id = create_resp.json()["id"]

        resp = client.delete(f"/v1/action-items/{ai_id}", headers=auth_headers)
        assert resp.status_code in (200, 204)

        resp = client.get(f"/v1/action-items/{ai_id}", headers=auth_headers)
        assert resp.status_code == 404

    def test_complete_action_item(self, client, auth_headers):
        """Mark an action item as completed."""
        create_resp = client.post(
            "/v1/action-items",
            json={"description": "Complete me"},
            headers=auth_headers,
        )
        assert create_resp.status_code == 200, create_resp.text
        ai_id = create_resp.json()["id"]

        resp = client.patch(
            f"/v1/action-items/{ai_id}/completed",
            params={"completed": True},
            headers=auth_headers,
        )
        assert resp.status_code == 200
        assert resp.json()["completed"] is True


class TestMemoryCRUD:
    """Memory lifecycle: create → read → edit → delete."""

    def test_create_and_read_memory(self, client, auth_headers, sample_memory_data):
        """Create a memory and read it back."""
        resp = client.post(
            "/v3/memories",
            json=sample_memory_data,
            headers=auth_headers,
        )
        assert resp.status_code == 200, f"Create memory failed: {resp.text}"

        body = resp.json()
        mem_id = body["id"]
        assert body["content"] == sample_memory_data["content"]
        assert body["category"] == sample_memory_data["category"]

        # Read back
        resp = client.get("/v3/memories", headers=auth_headers)
        assert resp.status_code == 200

        memories = resp.json()
        found = any(m["id"] == mem_id for m in memories)
        assert found, f"Memory {mem_id} not found in list"

    def test_list_memories(self, client, auth_headers):
        """Create multiple memories and list them."""
        create_a = client.post(
            "/v3/memories", json={"content": "Memory A", "category": "interesting"}, headers=auth_headers
        )
        create_b = client.post("/v3/memories", json={"content": "Memory B", "category": "system"}, headers=auth_headers)
        assert create_a.status_code == 200, create_a.text
        assert create_b.status_code == 200, create_b.text
        created_ids = {create_a.json()["id"], create_b.json()["id"]}

        resp = client.get("/v3/memories", headers=auth_headers)
        assert resp.status_code == 200

        body = resp.json()
        by_id = {m["id"]: m for m in body}
        assert created_ids.issubset(by_id.keys())
        assert {by_id[mem_id]["content"] for mem_id in created_ids} == {"Memory A", "Memory B"}

    def test_edit_memory(self, client, auth_headers):
        """Edit a memory's content."""
        create_resp = client.post(
            "/v3/memories",
            json={"content": "Original content", "category": "manual"},
            headers=auth_headers,
        )
        assert create_resp.status_code == 200, create_resp.text
        mem_id = create_resp.json()["id"]

        resp = client.patch(
            f"/v3/memories/{mem_id}",
            params={"value": "Edited content"},
            headers=auth_headers,
        )
        assert resp.status_code == 200, f"Edit failed: {resp.text}"
        list_resp = client.get("/v3/memories", headers=auth_headers)
        assert list_resp.status_code == 200, list_resp.text
        found = [m for m in list_resp.json() if m["id"] == mem_id]
        assert found and found[0]["content"] == "Edited content"

    def test_delete_memory(self, client, auth_headers):
        """Delete a memory and verify it's gone."""
        create_resp = client.post(
            "/v3/memories",
            json={"content": "Delete me", "category": "interesting"},
            headers=auth_headers,
        )
        assert create_resp.status_code == 200, create_resp.text
        mem_id = create_resp.json()["id"]

        resp = client.delete(f"/v3/memories/{mem_id}", headers=auth_headers)
        assert resp.status_code == 200, f"Delete failed: {resp.text}"
        assert resp.json()["status"] == "ok"
        list_resp = client.get("/v3/memories", headers=auth_headers)
        assert list_resp.status_code == 200, list_resp.text
        assert mem_id not in {m["id"] for m in list_resp.json()}

    def test_batch_create_memories(self, client, auth_headers):
        """Create multiple memories in a single batch request."""
        resp = client.post(
            "/v3/memories/batch",
            json={
                "memories": [
                    {"content": "Batch memory 1", "category": "interesting"},
                    {"content": "Batch memory 2", "category": "system"},
                    {"content": "Batch memory 3", "category": "manual"},
                ]
            },
            headers=auth_headers,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["created_count"] == 3
        assert len(body["memories"]) == 3
        created_ids = {m["id"] for m in body["memories"]}
        list_resp = client.get("/v3/memories", headers=auth_headers)
        assert list_resp.status_code == 200, list_resp.text
        assert created_ids.issubset({m["id"] for m in list_resp.json()})


class TestDataShapePreservation:
    """Verify that round-trips preserve all expected fields."""

    def test_action_item_fields_preserved(self, client, auth_headers):
        """Action item fields survive create→read round-trip."""
        resp = client.post(
            "/v1/action-items",
            json={
                "description": "Field check task",
                "completed": False,
                "due_at": "2025-02-01T00:00:00Z",
            },
            headers=auth_headers,
        )
        assert resp.status_code == 200

        body = resp.json()
        assert body["description"] == "Field check task"
        assert body["completed"] is False
        assert body.get("due_at") is not None
        for field in [
            "id",
            "description",
            "completed",
            "created_at",
            "updated_at",
            "is_locked",
            "exported",
            "sort_order",
            "indent_level",
        ]:
            assert field in body, f"Missing AI field: {field}"
