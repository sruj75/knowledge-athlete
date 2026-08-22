"""S-23 contract: ordinary clients cannot create hosted recording products."""

from fastapi.testclient import TestClient

import main
from utils.other import storage


def test_hosted_recording_routes_are_404_without_touching_product_storage(monkeypatch) -> None:
    def fail_if_storage_is_reached():
        raise AssertionError('retired recording route reached product storage')

    monkeypatch.setattr(storage, '_get_storage_client', fail_if_storage_is_reached)
    client = TestClient(main.app)

    responses = [
        client.post('/v3/upload-audio'),
        client.get('/v1/conversations/recording-1'),
        client.get('/v1/conversations/recording-1/playback'),
    ]

    assert [response.status_code for response in responses] == [404, 404, 404]
