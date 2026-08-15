"""Historical Ray-Ban Meta source values remain decodable."""

import sys
from unittest.mock import MagicMock

from models.conversation_enums import ConversationSource

_FIREBASE_STUBS = [
    'firebase_admin',
    'firebase_admin.firestore',
    'firebase_admin.auth',
    'firebase_admin.credentials',
    'google.cloud.firestore',
    'google.auth.transport.requests',
    'google.oauth2.id_token',
    'google.cloud.firestore_v1',
    'google.cloud.firestore_v1.base_query',
]


class TestRayBanMetaSourceEnum:
    def test_rayban_meta_is_known_member(self):
        result = ConversationSource('rayban_meta')
        assert result == ConversationSource.rayban_meta
        assert result.value == 'rayban_meta'

    def test_rayban_meta_does_not_degrade_to_unknown(self):
        assert ConversationSource('rayban_meta') != ConversationSource.unknown

    def test_conversation_model_accepts_rayban_meta(self, monkeypatch):
        # Stub heavy deps per-test via monkeypatch (never module-scope mutation).
        for mod in _FIREBASE_STUBS:
            if mod not in sys.modules:
                monkeypatch.setitem(sys.modules, mod, MagicMock())
        from models.conversation import Conversation
        from models.structured import Structured

        conv = Conversation(
            id='test-rbm-1',
            created_at='2026-07-06T18:00:00Z',
            started_at='2026-07-06T18:00:00Z',
            finished_at='2026-07-06T18:15:00Z',
            source='rayban_meta',
            structured=Structured(title='Test', overview='Test overview', emoji='🕶️'),
        )
        assert conv.source == ConversationSource.rayban_meta
