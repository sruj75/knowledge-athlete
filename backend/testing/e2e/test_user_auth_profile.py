"""
User/auth/profile/account e2e coverage.

These tests exercise real user/account routes through the FastAPI app while
using fake Firestore/Redis and local-development auth.
"""

from fakes.firestore import get_mock_firestore


def _seed_user(uid="123", **fields):
    data = {"id": uid, "uid": uid, "name": "E2E User", "email": "e2e@example.com"}
    data.update(fields)
    get_mock_firestore().collection("users").document(uid).set(data)
    return data


def test_backend_onboarding_state_is_not_exposed(client, auth_headers):
    read = client.get("/v1/users/onboarding", headers=auth_headers)
    assert read.status_code == 404

    write = client.patch(
        "/v1/users/onboarding",
        json={"completed": True, "acquisition_source": "friend", "device_onboarding_completed": True},
        headers=auth_headers,
    )
    assert write.status_code == 404


def test_profile_410_then_seeded_profile(client, auth_headers):
    missing = client.get("/v1/users/profile", headers=auth_headers)
    assert missing.status_code == 410

    seeded = _seed_user(data_protection_level="standard")
    resp = client.get("/v1/users/profile", headers=auth_headers)
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert "name" not in body
    assert body["email"] == seeded["email"]
    assert body["data_protection_level"] == "standard"


def test_language_roundtrip(client, auth_headers):
    language = client.get("/v1/users/language", headers=auth_headers)
    assert language.status_code == 200, language.text
    assert language.json() == {"language": None}

    set_language = client.patch("/v1/users/language", json={"language": "en"}, headers=auth_headers)
    assert set_language.status_code == 200, set_language.text
    assert set_language.json()["status"] == "ok"

    language = client.get("/v1/users/language", headers=auth_headers)
    assert language.status_code == 200, language.text
    assert language.json() == {"language": "en"}
