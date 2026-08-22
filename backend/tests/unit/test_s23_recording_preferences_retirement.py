"""S-23 contract: hosted recording preferences are not product profile state."""

from fastapi.testclient import TestClient

import main
from routers import users
from utils.other import endpoints as auth


def test_profile_omits_retired_recording_preferences(monkeypatch) -> None:
    main.app.dependency_overrides[auth.get_current_user_uid] = lambda: 'owner-a'
    monkeypatch.setattr(
        users,
        'get_user_profile',
        lambda _uid: {
            'uid': 'owner-a',
            'email': 'owner@example.com',
            'store_recording_permission': True,
            'private_cloud_sync_enabled': True,
            'training_data_opt_in': {'status': 'pending_review'},
        },
    )

    try:
        response = TestClient(main.app).get('/v1/users/profile')
    finally:
        main.app.dependency_overrides.clear()

    assert response.status_code == 200
    payload = response.json()
    assert payload['uid'] == 'owner-a'
    assert payload['email'] == 'owner@example.com'
    assert {'store_recording_permission', 'private_cloud_sync_enabled', 'training_data_opt_in'}.isdisjoint(payload)
