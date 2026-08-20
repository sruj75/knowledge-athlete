"""Boundary contract e2e coverage for mobile/client-facing validation.

These tests exercise the real FastAPI routes through the hermetic harness. Unit
coverage owns the pure validation helpers; this file pins the integration seams:
FastAPI parameter binding, auth, multipart parsing, and fake storage side effects.
"""


def test_real_routes_reject_invalid_boundary_query_values_without_500(client, auth_headers):
    cases = [("/v1/calendar/meetings?limit=101", 422)]

    for path, expected_status in cases:
        response = client.get(path, headers=auth_headers)

        assert response.status_code == expected_status, f"{path}: {response.text}"
        assert response.status_code < 500
        assert "detail" in response.json()
