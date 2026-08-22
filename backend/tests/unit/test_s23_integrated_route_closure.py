"""S-23 behavioral closure for every rejected hosted product operation.

This deliberately drives the assembled production FastAPI app. Route-table or
source-string checks alone cannot prove that a compatibility handler, auth gate,
or fake-success shell did not survive the retirement.
"""

from fastapi.testclient import TestClient

import main


REJECTED_HTTP_OPERATIONS = (
    # S-23 recording, voice identity, Calendar, and hosted conversation products.
    ('POST', '/v3/upload-audio'),
    ('GET', '/v3/speech-profile'),
    ('GET', '/v4/speech-profile'),
    ('GET', '/v3/speech-profile/expand'),
    ('DELETE', '/v3/speech-profile/expand'),
    ('GET', '/v1/conversations/conversation-1'),
    ('GET', '/v1/conversations/conversation-1/playback'),
    ('POST', '/v1/calendar/meetings'),
    ('GET', '/v1/calendar/meetings'),
    ('GET', '/v1/calendar/meetings/meeting-1'),
    ('POST', '/v1/agents/hume/callback'),
    # Hosted Memory feedback, shared Chat reporting, Trends, and Joan.
    ('GET', '/v1/users/analytics/memory_summary'),
    ('POST', '/v1/users/analytics/memory_summary'),
    ('POST', '/v1/messages/message-1/report'),
    ('POST', '/v2/messages/message-1/report'),
    ('GET', '/v1/trends'),
    ('DELETE', '/v1/joan/memory-1/followup-question'),
    # Twilio phone product.
    ('POST', '/v1/phone/numbers/verify'),
    ('POST', '/v1/phone/numbers/verify/check'),
    ('GET', '/v1/phone/numbers'),
    ('DELETE', '/v1/phone/numbers/phone-1'),
    ('POST', '/v1/phone/token'),
    ('POST', '/v1/phone/twiml'),
    # Wrapped.
    ('GET', '/v1/wrapped/2025'),
    ('POST', '/v1/wrapped/2025/generate'),
    # Cloud announcements and FCM.
    ('GET', '/v1/announcements/changelogs'),
    ('GET', '/v1/announcements/features'),
    ('GET', '/v1/announcements/general'),
    ('GET', '/v1/announcements/pending'),
    ('POST', '/v1/announcements/announcement-1/dismiss'),
    ('GET', '/v1/announcements/all'),
    ('GET', '/v1/announcements/announcement-1'),
    ('POST', '/v1/announcements'),
    ('PUT', '/v1/announcements/announcement-1'),
    ('DELETE', '/v1/announcements/announcement-1'),
    ('POST', '/v1/users/fcm-token'),
    ('POST', '/v1/notification'),
    # Accepted negative predecessor families consumed by S-23 closure.
    ('POST', '/v1/sync-local-files'),
    ('POST', '/v2/sync-local-files'),
    ('GET', '/v2/firmware/latest'),
    ('GET', '/v1/conversations/conversation-1/photos'),
    ('GET', '/v2/chat-sessions'),
    ('POST', '/v2/chat-sessions'),
    ('GET', '/v2/chat-sessions/chat-1'),
    ('PATCH', '/v2/chat-sessions/chat-1'),
    ('DELETE', '/v2/chat-sessions/chat-1'),
    ('GET', '/v3/memories'),
    ('POST', '/v3/memories'),
    ('GET', '/v1/focus-sessions'),
    ('POST', '/v1/focus-sessions'),
    ('GET', '/v1/users/ai-profile'),
    ('GET', '/v1/users/daily-summaries'),
    ('POST', '/v2/tts/synthesize'),
)

REJECTED_WEBSOCKET_OPERATIONS = ('/v1/listen', '/v2/listen', '/v3/listen')


def test_every_rejected_operation_returns_genuine_not_found() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    for method, path in REJECTED_HTTP_OPERATIONS:
        response = client.request(method, path)
        assert response.status_code == 404, f'{method} {path} returned {response.status_code}, not 404'

    websocket_upgrade_headers = {
        'connection': 'upgrade',
        'upgrade': 'websocket',
        'sec-websocket-version': '13',
        'sec-websocket-key': 'dGhlIHNhbXBsZSBub25jZQ==',
    }
    for path in REJECTED_WEBSOCKET_OPERATIONS:
        response = client.get(path, headers=websocket_upgrade_headers)
        assert response.status_code == 404, f'WEBSOCKET {path} returned {response.status_code}, not 404'


def test_retained_neighbors_are_still_real_production_routes() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    for method, path in (
        ('GET', '/v1/users/me/subscription'),
        ('POST', '/v2/chat/completions'),
        ('POST', '/v1/memory/compute/extract'),
        ('POST', '/v1/conversation-compute/structure'),
        ('POST', '/v1/tts/synthesize'),
    ):
        response = client.request(method, path)
        assert response.status_code == 401, f'{method} {path} no longer enforces its retained auth boundary'

    websocket_paths = {route.path for route in main.app.routes if not getattr(route, 'methods', None)}
    assert {'/v1/omni/relay', '/v2/voice-message/transcribe-stream', '/v4/listen'} <= websocket_paths
