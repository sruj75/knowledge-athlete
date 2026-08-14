"""Tests for locked conversation bypass fixes (#6089).

Verifies that is_locked conversations/memories are properly guarded
across all previously-bypassed endpoints by calling the real code paths.
"""

from unittest.mock import patch, MagicMock
import os
import pytest
import sys
from datetime import datetime, timedelta, timezone, tzinfo
from types import ModuleType, SimpleNamespace
from zoneinfo import ZoneInfo

os.environ.setdefault('OPENAI_API_KEY', 'sk-test-not-real')
os.environ.setdefault('ENCRYPTION_SECRET', 'omi_ZwB2ZNqB2HHpMK6wStk7sTpavJiPTFg7gXUHnc4tFABPU6pZ2c2DKgehtfgi4RZv')

# ---- Stub heavy deps before importing application code ----


class _AutoMockModule(ModuleType):
    """Module stub that returns MagicMock for any missing attribute."""

    def __getattr__(self, name):
        if name.startswith('__') and name.endswith('__'):
            raise AttributeError(name)
        mock = MagicMock()
        setattr(self, name, mock)
        return mock


class _ToolWrapper:
    """Tiny LangChain tool stand-in for tests that call `.invoke(...)`."""

    def __init__(self, fn):
        self.fn = fn
        self.name = fn.__name__

    def __call__(self, *args, **kwargs):
        return self.fn(*args, **kwargs)

    def invoke(self, args=None, config=None):
        if args is not None and not isinstance(args, dict):
            if config is not None:
                return self.fn(args, config=config)
            return self.fn(args)

        kwargs = dict(args or {})
        if config is not None:
            kwargs['config'] = config
        return self.fn(**kwargs)


class _PytzZoneInfo(tzinfo):
    """Minimal pytz timezone stand-in with `.localize(...)` for summary tests."""

    def __init__(self, key):
        try:
            self._zone = ZoneInfo(key)
        except Exception:
            if key == 'UTC':
                self._zone = timezone.utc
            elif key == 'Asia/Kolkata':
                self._zone = timezone(timedelta(hours=5, minutes=30), key)
            else:
                raise

    def localize(self, value):
        if value.tzinfo is not None:
            return value.astimezone(self)
        return value.replace(tzinfo=self)

    def _delegate_value(self, value):
        if value is not None and value.tzinfo is self:
            return value.replace(tzinfo=self._zone)
        return value

    def utcoffset(self, value):
        return self._zone.utcoffset(self._delegate_value(value))

    def dst(self, value):
        return self._zone.dst(self._delegate_value(value))

    def tzname(self, value):
        return self._zone.tzname(self._delegate_value(value))

    def fromutc(self, value):
        localized = value.replace(tzinfo=timezone.utc).astimezone(self._zone)
        return localized.replace(tzinfo=self)


def _tool(func=None, *args, **kwargs):
    def decorator(fn):
        return _ToolWrapper(fn)

    if callable(func):
        return decorator(func)
    return decorator


_stubs = [
    'anthropic',
    'av',
    'database._client',
    'database.cache',
    'database.redis_db',
    'database.conversations',
    'database.memories',
    'database.action_items',
    'database.folders',
    'database.users',
    'database.user_usage',
    'database.vector_db',
    'database.chat',
    'database.goals',
    'database.notifications',
    'database.daily_summaries',
    'database.fair_use',
    'database.auth',
    'database.llm_usage',
    'database.phone_calls',
    'deepgram',
    'deepgram.clients',
    'deepgram.clients.live',
    'deepgram.clients.live.v1',
    'firebase_admin',
    'firebase_admin.messaging',
    'firebase_admin.auth',
    'google.cloud.firestore',
    'google.cloud.tasks_v2',
    'google.cloud.firestore_v1',
    'google.cloud.firestore_v1.FieldFilter',
    'langchain_core',
    'langchain_core.callbacks',
    'langchain_core.language_models',
    'langchain_core.messages',
    'langchain_core.output_parsers',
    'langchain_core.outputs',
    'langchain_core.prompts',
    'langchain_core.runnables',
    'langchain_core.tools',
    'langchain_google_genai',
    'langchain_openai',
    'openai',
    'openai.types',
    'openai.types.beta',
    'openai.types.beta.threads',
    'openai.types.chat',
    'PIL',
    'PIL.Image',
    'pinecone',
    'pycountry',
    'pytz',
    'scipy',
    'scipy.spatial',
    'scipy.spatial.distance',
    'tiktoken',
    'twilio',
    'twilio.jwt',
    'twilio.jwt.access_token',
    'twilio.jwt.access_token.grants',
    'twilio.request_validator',
    'twilio.rest',
    'typesense',
    'opuslib',
    'pydub',
    'pusher',
    'modal',
    'utils.other.storage',
    'utils.other.endpoints',
    'utils.stt.pre_recorded',
    'utils.stt.vad',
    'utils.fair_use',
    'utils.subscription',
    'utils.conversations.process_conversation',
    'utils.notifications',
    'utils.llm.clients',
    'utils.llm.memories',
    'utils.llm.chat',
    'utils.llm.usage_tracker',
    'websockets',
]
for mod_name in _stubs:
    if mod_name not in sys.modules:
        sys.modules[mod_name] = _AutoMockModule(mod_name)

# Concrete attributes used by imported modules during lightweight tests.
sys.modules['langchain_core.callbacks'].BaseCallbackHandler = object
sys.modules['langchain_core.outputs'].LLMResult = object
sys.modules['langchain_core.runnables'].RunnableConfig = dict
sys.modules['langchain_core.tools'].tool = _tool
sys.modules['pytz'].timezone = _PytzZoneInfo
sys.modules['pytz'].utc = timezone.utc

# Override specific attributes that need concrete values
sys.modules['firebase_admin.auth'].InvalidIdTokenError = type('InvalidIdTokenError', (Exception,), {})
sys.modules['firebase_admin.auth'].ExpiredIdTokenError = type('ExpiredIdTokenError', (Exception,), {})
sys.modules['firebase_admin.auth'].RevokedIdTokenError = type('RevokedIdTokenError', (Exception,), {})
sys.modules['firebase_admin.auth'].CertificateFetchError = type('CertificateFetchError', (Exception,), {})
sys.modules['firebase_admin.auth'].UserNotFoundError = type('UserNotFoundError', (Exception,), {})


class TestLightweightStubHelpers:
    """Keep lightweight dependency stubs aligned with the real interfaces tests rely on."""

    def test_tool_wrapper_invoke_accepts_string_input(self):
        def echo(value):
            return value

        wrapped = _tool(echo)

        assert wrapped.invoke('hello') == 'hello'

    def test_pytz_stub_supports_localize_and_datetime_now(self):
        import pytz

        user_tz = pytz.timezone('UTC')
        localized = user_tz.localize(datetime(2026, 6, 10, 12, 0, 0))

        assert localized.tzinfo is user_tz
        assert localized.astimezone(pytz.utc).hour == 12
        assert datetime.now(user_tz).tzinfo is user_tz


def _make_conversation(locked=False, conversation_id='conv-1'):
    """Create a minimal conversation dict for DB-layer return values."""
    return {
        'id': conversation_id,
        'is_locked': locked,
        'structured': {
            'title': 'Test Conversation',
            'overview': 'Test overview',
            'action_items': [{'description': 'do something'}],
            'events': [{'title': 'event1', 'start': '2024-01-01T12:00:00'}],
            'category': 'personal',
        },
        'transcript_segments': [{'text': 'hello', 'speaker_id': 0, 'is_user': False, 'start': 0.0, 'end': 1.0}],
        'audio_files': [
            {
                'id': 'af-1',
                'uid': 'test-uid',
                'conversation_id': conversation_id,
                'chunk_timestamps': [1.0],
                'duration': 60.0,
            }
        ],
        'started_at': '2024-01-01T00:00:00',
        'finished_at': '2024-01-01T01:00:00',
        'created_at': 1704067200,
        'discarded': False,
        'visibility': 'private',
        'geolocation': None,
        'language': 'en',
        'status': 'completed',
        'source': 'friend',
    }


def _make_memory(locked=False, memory_id='mem-1'):
    """Create a minimal memory dict compatible with MemoryDB model."""
    return {
        'id': memory_id,
        'uid': 'test-uid',
        'is_locked': locked,
        'content': 'This is a secret memory that should not be visible when locked',
        'category': 'interesting',
        'created_at': '2024-01-01T00:00:00',
        'updated_at': '2024-01-01T00:00:00',
    }


def _force_legacy_chat_memory_path(module):
    from utils.memory.default_read_rollout import MemoryReadDecision
    from utils.memory import memory_service
    from utils.memory.memory_system import MemorySystem

    legacy = SimpleNamespace(read_decision=MemoryReadDecision.USE_LEGACY_SAFE, memories=[], text=None)
    allowed_write = SimpleNamespace(allowed=True, detail={})
    module.pin_memory_system = MagicMock(return_value=MemorySystem.LEGACY)
    if hasattr(module, 'read_default_read_rollout'):
        module.read_default_read_rollout = MagicMock(return_value=legacy)
    for attr in ('list_default_chat_memories_decision_text',):
        if hasattr(module, attr):
            setattr(module, attr, MagicMock(return_value=legacy))
    if hasattr(module, 'guard_legacy_memory_write'):
        module.guard_legacy_memory_write = MagicMock(return_value=allowed_write)
    memory_service.guard_legacy_memory_write = MagicMock(return_value=allowed_write)


# =============================================================================
# Test sync.py audio endpoints — call the real router functions
# =============================================================================


class TestSyncAudioLockEnforcement:
    """H2-H4: Audio sync endpoints must return 402 for locked conversations."""

    def test_precache_rejects_locked(self):
        """H4: precache_conversation_audio_endpoint must raise 402 for locked."""
        import database.conversations as conversations_db

        conversations_db.get_conversation = MagicMock(return_value=_make_conversation(locked=True))

        from routers.sync import precache_conversation_audio_endpoint
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc_info:
            precache_conversation_audio_endpoint(conversation_id='conv-1', uid='test-uid')
        assert exc_info.value.status_code == 402

    def test_precache_allows_unlocked(self):
        """Unlocked conversations should proceed past the lock check."""
        import database.conversations as conversations_db

        conversations_db.get_conversation = MagicMock(return_value=_make_conversation(locked=False))

        from routers.sync import precache_conversation_audio_endpoint

        # Should not raise 402 — may still fail on infra, that's OK
        try:
            precache_conversation_audio_endpoint(conversation_id='conv-1', uid='test-uid')
        except Exception as e:
            if hasattr(e, 'status_code'):
                assert e.status_code != 402

    def test_urls_rejects_locked(self):
        """H2: get_audio_signed_urls_endpoint must raise 402 for locked."""
        import database.conversations as conversations_db

        conversations_db.get_conversation = MagicMock(return_value=_make_conversation(locked=True))

        from routers.sync import get_audio_signed_urls_endpoint
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc_info:
            get_audio_signed_urls_endpoint(conversation_id='conv-1', uid='test-uid')
        assert exc_info.value.status_code == 402

    def test_download_rejects_locked(self):
        """H3: download_audio_file_endpoint must raise 402 for locked."""
        import database.conversations as conversations_db

        conversations_db.get_conversation = MagicMock(return_value=_make_conversation(locked=True))

        from routers.sync import download_audio_file_endpoint
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc_info:
            download_audio_file_endpoint(
                conversation_id='conv-1', audio_file_id='af-1', uid='test-uid', request=MagicMock()
            )
        assert exc_info.value.status_code == 402


# =============================================================================
# Test folders.py — call the real router function
# =============================================================================


class TestFolderConversationRedaction:
    """H1: Folder listing must redact locked conversation content via the real endpoint."""

    def test_folder_endpoint_redacts_locked(self):
        """get_folder_conversations must redact locked fields."""
        import database.folders as folders_db

        folders_db.get_folder = MagicMock(return_value={'id': 'f1', 'name': 'Work'})
        folders_db.get_conversations_in_folder = MagicMock(
            return_value=[_make_conversation(locked=True), _make_conversation(locked=False, conversation_id='conv-2')]
        )

        from routers.folders import get_folder_conversations

        result = get_folder_conversations(folder_id='f1', limit=100, offset=0, include_discarded=False, uid='test-uid')

        locked = result[0].model_dump()
        assert locked['structured']['action_items'] == []
        assert locked['structured']['events'] == []
        assert locked['transcript_segments'] == []

        unlocked = result[1].model_dump()
        assert len(unlocked['structured']['action_items']) == 1
        assert len(unlocked['transcript_segments']) == 1

    def test_folder_endpoint_preserves_title_for_locked(self):
        """Locked conversations should still show title/overview."""
        import database.folders as folders_db

        folders_db.get_folder = MagicMock(return_value={'id': 'f1', 'name': 'Work'})
        folders_db.get_conversations_in_folder = MagicMock(return_value=[_make_conversation(locked=True)])

        from routers.folders import get_folder_conversations

        result = get_folder_conversations(folder_id='f1', limit=100, offset=0, include_discarded=False, uid='test-uid')
        assert result[0].model_dump()['structured']['title'] == 'Test Conversation'


# =============================================================================
# Test search redaction — call the real search_conversations function
# =============================================================================


class TestSearchRedaction:
    """M1: Search results must exclude locked conversations entirely to prevent inference leaks."""

    def test_search_excludes_locked_results(self):
        """search_conversations must exclude locked hits entirely (not just redact)."""
        mock_client = MagicMock()
        mock_client.collections.__getitem__.return_value.documents.search.return_value = {
            'hits': [
                {
                    'document': {
                        **_make_conversation(locked=True),
                        'created_at': 1704067200,
                        'started_at': 1704067200,
                        'finished_at': 1704070800,
                    }
                },
                {
                    'document': {
                        **_make_conversation(locked=False, conversation_id='conv-2'),
                        'created_at': 1704067200,
                        'started_at': 1704067200,
                        'finished_at': 1704070800,
                    }
                },
            ],
            'found': 2,
        }

        with patch('utils.conversations.search.client', mock_client):
            from utils.conversations.search import search_conversations

            result = search_conversations(uid='test-uid', query='test')

        # Locked item must be excluded entirely (prevents inference leak)
        assert len(result['items']) == 1
        unlocked_item = result['items'][0]
        assert unlocked_item['structured']['title'] == 'Test Conversation'
        assert unlocked_item['structured']['overview'] == 'Test overview'
        assert len(unlocked_item['structured']['action_items']) == 1
        assert len(unlocked_item['transcript_segments']) == 1
        # total_pages uses page-level signal, not global found count
        assert result['total_pages'] == 1

    def test_search_skips_malformed_timestamp_hit(self):
        """A single hit with a missing/null timestamp must be skipped, not 500 the whole page."""
        mock_client = MagicMock()
        mock_client.collections.__getitem__.return_value.documents.search.return_value = {
            'hits': [
                {
                    'document': {
                        **_make_conversation(locked=False, conversation_id='good'),
                        'created_at': 1704067200,
                        'started_at': 1704067200,
                        'finished_at': 1704070800,
                    }
                },
                {
                    'document': {
                        # null started_at -> utcfromtimestamp(None) raises; finished_at missing entirely
                        **_make_conversation(locked=False, conversation_id='bad'),
                        'created_at': 1704067200,
                        'started_at': None,
                    }
                },
            ],
            'found': 2,
        }

        with patch('utils.conversations.search.client', mock_client):
            from utils.conversations.search import search_conversations

            result = search_conversations(uid='test-uid', query='test')

        # Does not raise; only the well-formed hit survives, with ISO-string timestamps.
        assert len(result['items']) == 1
        kept = result['items'][0]
        assert isinstance(kept['created_at'], str) and 'T' in kept['created_at']
        assert isinstance(kept['started_at'], str)

    def test_search_all_malformed_returns_empty_page_not_500(self):
        """If every hit is malformed, return an empty page instead of 500ing the whole request."""
        mock_client = MagicMock()
        mock_client.collections.__getitem__.return_value.documents.search.return_value = {
            'hits': [
                {'document': {**_make_conversation(locked=False, conversation_id='bad1'), 'created_at': None}},
                {
                    'document': {
                        **_make_conversation(locked=False, conversation_id='bad2'),
                        'created_at': 1704067200,
                        'started_at': None,
                    }
                },
            ],
            'found': 2,
        }

        with patch('utils.conversations.search.client', mock_client):
            from utils.conversations.search import search_conversations

            result = search_conversations(uid='test-uid', query='test', page=2)

        assert result['items'] == []
        assert result['total_pages'] == 2  # falls back to the page param, not inflated
        assert result['current_page'] == 2

    def test_search_total_pages_does_not_leak_locked_count(self):
        """total_pages must not inflate from locked docs on other pages."""
        mock_client = MagicMock()
        # Simulate: found=6 globally, per_page=5, 4 locked + 1 unlocked on this page
        hits = [
            {
                'document': {
                    **_make_conversation(locked=True, conversation_id=f'locked-{i}'),
                    'created_at': 1704067200,
                    'started_at': 1704067200,
                    'finished_at': 1704070800,
                }
            }
            for i in range(4)
        ] + [
            {
                'document': {
                    **_make_conversation(locked=False, conversation_id='unlocked-1'),
                    'created_at': 1704067200,
                    'started_at': 1704067200,
                    'finished_at': 1704070800,
                }
            }
        ]
        mock_client.collections.__getitem__.return_value.documents.search.return_value = {
            'hits': hits,
            'found': 6,
        }
        with patch('utils.conversations.search.client', mock_client):
            from utils.conversations.search import search_conversations

            result = search_conversations(uid='test-uid', query='test', per_page=5)

        assert len(result['items']) == 1
        # total_pages derived from visible items (1 < per_page=5), not raw hits or found count
        assert result['total_pages'] == 1

    def test_search_total_pages_last_page_no_leak(self):
        """When Typesense returns fewer than per_page hits, total_pages = current page."""
        mock_client = MagicMock()
        # Only 2 hits (< per_page=5), all locked → 0 items, total_pages=1
        hits = [
            {
                'document': {
                    **_make_conversation(locked=True, conversation_id=f'locked-{i}'),
                    'created_at': 1704067200,
                    'started_at': 1704067200,
                    'finished_at': 1704070800,
                }
            }
            for i in range(2)
        ]
        mock_client.collections.__getitem__.return_value.documents.search.return_value = {
            'hits': hits,
            'found': 2,
        }
        with patch('utils.conversations.search.client', mock_client):
            from utils.conversations.search import search_conversations

            result = search_conversations(uid='test-uid', query='test', per_page=5)

        assert len(result['items']) == 0
        # Not a full page → total_pages = current page (1), not found/per_page
        assert result['total_pages'] == 1


# =============================================================================
# Test conversation_tools.py — verify filtering logic in real module
# =============================================================================


class TestConversationToolFiltering:
    """H5: Chat/RAG conversation tools must filter out locked conversations."""

    def test_get_conversations_tool_filters_locked(self):
        """get_conversations_tool must exclude locked conversations from results."""
        import database.conversations as conversations_db
        import database.users as users_db

        data = [
            _make_conversation(locked=True),
            _make_conversation(locked=False, conversation_id='conv-2'),
            _make_conversation(locked=True, conversation_id='conv-3'),
        ]
        conversations_db.get_conversations = MagicMock(return_value=data)
        users_db.get_people_by_ids = MagicMock(return_value=[])

        from utils.retrieval.tools.conversation_tools import get_conversations_tool

        config = {'configurable': {'user_id': 'test-uid', 'conversations_collected': []}}
        result = get_conversations_tool.invoke({'limit': 10, 'offset': 0}, config=config)
        # Result is a string with "Conversation #N" format; should have exactly 1 conversation
        assert 'Conversation #1' in result
        assert 'Conversation #2' not in result  # Only 1 unlocked conv should appear

    def test_search_tool_filters_locked(self):
        """search_conversations_tool must exclude locked results."""
        import database.conversations as conversations_db
        import database.vector_db as vector_db
        import database.users as users_db

        data = [
            _make_conversation(locked=True),
            _make_conversation(locked=False, conversation_id='conv-2'),
        ]
        conversations_db.get_conversations_by_id = MagicMock(return_value=data)
        vector_db.query_vectors = MagicMock(return_value=[{'id': 'conv-1'}, {'id': 'conv-2'}])
        users_db.get_people_by_ids = MagicMock(return_value=[])

        from utils.retrieval.tools.conversation_tools import search_conversations_tool

        config = {'configurable': {'user_id': 'test-uid', 'conversations_collected': []}}
        result = search_conversations_tool.invoke({'query': 'test'}, config=config)
        # Only 1 unlocked conv should appear
        assert 'Conversation #1' in result
        assert 'Conversation #2' not in result


# =============================================================================
# Test memory_tools.py — verify filtering logic in real module
# =============================================================================


class TestMemoryToolFiltering:
    """M6: Chat/RAG memory tools must filter out locked memories."""

    def test_get_memories_filters_locked(self):
        """get_memories_tool must exclude locked memories from results."""
        import database.memories as memory_db

        locked_mem = _make_memory(locked=True)
        locked_mem['content'] = 'LOCKED_SECRET_CONTENT'
        unlocked_mem = _make_memory(locked=False, memory_id='mem-2')
        unlocked_mem['content'] = 'UNLOCKED_VISIBLE_CONTENT'
        memory_db.get_memories = MagicMock(return_value=[locked_mem, unlocked_mem])

        from utils.retrieval.tools import memory_tools
        from utils.retrieval.tools.memory_tools import get_memories_tool

        config = {'configurable': {'user_id': 'test-uid'}}
        _force_legacy_chat_memory_path(memory_tools)
        result = get_memories_tool.invoke({'limit': 10, 'offset': 0}, config=config)
        # Only unlocked memory content should appear; locked must be filtered
        assert 'UNLOCKED_VISIBLE_CONTENT' in result
        assert 'LOCKED_SECRET_CONTENT' not in result
        assert '1 shown' in result  # Only 1 memory should appear

    def test_search_memories_filters_locked(self):
        """search_memories_tool must exclude locked memories from results."""
        import database.memories as memory_db
        import database.vector_db as vector_db

        data = [_make_memory(locked=True), _make_memory(locked=True, memory_id='mem-2')]
        memory_db.get_memories_by_ids = MagicMock(return_value=data)
        vector_db.find_similar_memories = MagicMock(return_value=[{'id': 'mem-1'}, {'id': 'mem-2'}])

        from utils.retrieval.tools.memory_tools import search_memories_tool

        config = {'configurable': {'user_id': 'test-uid'}}
        result = search_memories_tool.invoke({'query': 'test'}, config=config)
        # All memories locked, so result should indicate nothing found
        assert 'no' in result.lower() or 'mem-1' not in result


# =============================================================================
# Test action_items.py — call the real endpoint
# =============================================================================


class TestActionItemsLockEnforcement:
    """M4: Per-conversation action items endpoint must return 402 for locked."""

    def test_conversation_action_items_rejects_locked(self):
        """get_conversation_action_items must raise 402 for locked conversations."""
        import database.conversations as conversations_db

        conversations_db.get_conversation = MagicMock(return_value=_make_conversation(locked=True))

        from routers.action_items import get_conversation_action_items
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc_info:
            get_conversation_action_items(conversation_id='conv-1', uid='test-uid')
        assert exc_info.value.status_code == 402

    def test_conversation_action_items_allows_unlocked(self):
        """get_conversation_action_items should proceed for unlocked conversations."""
        import database.conversations as conversations_db
        import database.action_items as action_items_db

        conversations_db.get_conversation = MagicMock(return_value=_make_conversation(locked=False))
        action_items_db.get_action_items_by_conversation = MagicMock(return_value=[])

        from routers.action_items import get_conversation_action_items

        result = get_conversation_action_items(conversation_id='conv-1', uid='test-uid')
        assert result['conversation_id'] == 'conv-1'

    def test_conversation_action_items_404_missing(self):
        """get_conversation_action_items should return 404 when conversation doesn't exist."""
        import database.conversations as conversations_db

        conversations_db.get_conversation = MagicMock(return_value=None)

        from routers.action_items import get_conversation_action_items
        from fastapi import HTTPException

        with pytest.raises(HTTPException) as exc_info:
            get_conversation_action_items(conversation_id='missing', uid='test-uid')
        assert exc_info.value.status_code == 404


# =============================================================================
# Test users.py endpoints
# =============================================================================


class TestUsersLockEnforcement:
    """L2/L3: Users endpoints must enforce lock."""

    def test_followup_question_rejects_locked(self):
        """L2: delete_person_endpoint must raise 402 for locked conversations."""
        from routers.users import delete_person_endpoint
        from fastapi import HTTPException

        with patch('routers.users.get_conversation', return_value=_make_conversation(locked=True)):
            with pytest.raises(HTTPException) as exc_info:
                delete_person_endpoint(memory_id='conv-1', uid='test-uid')
            assert exc_info.value.status_code == 402

    def test_followup_question_allows_unlocked(self):
        """delete_person_endpoint should proceed for unlocked conversations."""
        from routers.users import delete_person_endpoint

        with patch('routers.users.get_conversation', return_value=_make_conversation(locked=False)):
            with patch('routers.users.followup_question_prompt', return_value='test result'):
                result = delete_person_endpoint(memory_id='conv-1', uid='test-uid')
        assert result['result'] == 'test result'

    def test_daily_summary_excludes_locked(self):
        """L3: test_daily_summary must filter locked conversations before processing."""
        import database.conversations as conversations_db
        import database.notifications as notification_db
        import database.daily_summaries as daily_summaries_db

        data = [
            _make_conversation(locked=True),
            _make_conversation(locked=False, conversation_id='conv-2'),
            _make_conversation(locked=True, conversation_id='conv-3'),
        ]
        conversations_db.get_conversations = MagicMock(return_value=data)
        notification_db.get_user_time_zone = MagicMock(return_value=None)
        notification_db.get_all_tokens = MagicMock(return_value=['token1'])
        daily_summaries_db.create_daily_summary = MagicMock(return_value='summary-1')

        from routers.users import test_daily_summary

        mock_gen = MagicMock(return_value={'headline': 'Test', 'overview': 'Overview'})
        with patch('routers.users.generate_comprehensive_daily_summary', mock_gen):
            with patch('routers.users.send_notification'):
                result = test_daily_summary(uid='test-uid')

        # Verify only unlocked conversations were passed to summary generation
        call_args = mock_gen.call_args
        conversations_passed = call_args[0][1]  # second positional arg
        assert len(conversations_passed) == 1
        assert conversations_passed[0].id == 'conv-2'

    def test_gdpr_export_includes_locked(self):
        """H6: GDPR export must include locked conversations (Art. 15)."""
        import database.conversations as conversations_db
        import database.memories as memories_db
        import database.chat as chat_db

        locked_conv = _make_conversation(locked=True)
        unlocked_conv = _make_conversation(locked=False, conversation_id='conv-2')
        conversations_db.iter_all_conversations = MagicMock(return_value=iter([locked_conv, unlocked_conv]))
        memories_db.get_non_filtered_memories = MagicMock(return_value=[])
        chat_db.iter_all_messages = MagicMock(return_value=iter([]))

        # The export generator lives in services.users.data_export, which binds
        # these helpers at module level. Patch the service-level symbols so the
        # stub environment returns controlled data instead of MagicMock defaults.
        # Patches must stay active during body consumption since the generator is lazy.
        with patch('services.users.data_export.get_user_profile', return_value={'name': 'Test'}):
            with patch('services.users.data_export.get_people', return_value=[]):
                with patch('services.users.data_export.get_standalone_action_items', return_value=[]):
                    from routers.users import export_all_user_data

                    response = export_all_user_data(uid='test-uid')

                    # Consume body inside patches — the generator is lazy.
                    # StreamingResponse wraps sync generators as async iterators,
                    # so iterate the underlying generator directly.
                    import asyncio

                    async def _consume():
                        parts = []
                        async for chunk in response.body_iterator:
                            parts.append(chunk)
                        return ''.join(parts)

                    body = asyncio.run(_consume())

        import json

        data = json.loads(body)
        # Both locked and unlocked conversations must be in the export
        assert len(data['conversations']) == 2
        assert data['conversations'][0]['is_locked'] is True
        assert data['conversations'][1]['id'] == 'conv-2'


# =============================================================================
# Test scheduled daily summary excludes locked conversations
# =============================================================================


class TestScheduledDailySummaryLockFilter:
    """Scheduled daily summary must exclude locked conversations from LLM context."""

    def test_scheduled_summary_excludes_locked(self):
        """_send_summary_notification filters locked conversations before generating summary."""
        import database.conversations as conversations_db
        import database.daily_summaries as daily_summaries_db

        locked_conv = _make_conversation(locked=True)
        unlocked_conv = _make_conversation(locked=False, conversation_id='conv-2')
        conversations_db.get_conversations = MagicMock(return_value=[locked_conv, unlocked_conv])

        with patch('utils.other.notifications.try_acquire_daily_summary_lock', return_value=True):
            with patch(
                'utils.other.notifications.generate_comprehensive_daily_summary',
                return_value={'headline': 'Test', 'day_emoji': '📅', 'overview': 'ok'},
            ) as mock_gen:
                daily_summaries_db.create_daily_summary = MagicMock(return_value='summary-1')
                daily_summaries_db.get_daily_summary_by_date = MagicMock(return_value=None)
                with patch('utils.other.notifications.send_notification'):
                    from utils.other.notifications import _send_summary_notification

                    _send_summary_notification(('test-uid', 'token', 'UTC'))

        # generate_comprehensive_daily_summary must be called only with unlocked conversations
        mock_gen.assert_called_once()
        conversations_passed = mock_gen.call_args[0][1]
        assert len(conversations_passed) == 1
        assert conversations_passed[0].id == 'conv-2'

    def test_scheduled_summary_skips_when_all_locked(self):
        """_send_summary_notification returns early when all conversations are locked."""
        import database.conversations as conversations_db
        import database.daily_summaries as daily_summaries_db

        conversations_db.get_conversations = MagicMock(return_value=[_make_conversation(locked=True)])
        daily_summaries_db.get_daily_summary_by_date = MagicMock(return_value=None)

        with patch('utils.other.notifications.try_acquire_daily_summary_lock', return_value=True):
            with patch('utils.other.notifications.generate_comprehensive_daily_summary') as mock_gen:
                from utils.other.notifications import _send_summary_notification

                _send_summary_notification(('test-uid', 'token', 'UTC'))

        # Should not call LLM when no unlocked conversations remain
        mock_gen.assert_not_called()


# =============================================================================
# Test goal context excludes locked conversations and memories
# =============================================================================


class TestGoalContextLockFilter:
    """Goal suggestion/advice must exclude locked conversations and memories."""

    def test_get_goal_context_filters_locked_conversations(self):
        """_get_goal_context excludes locked conversations from vector and recent results."""
        import database.conversations as conversations_db
        import database.memories as memories_db
        import database.chat as chat_db

        locked_conv = _make_conversation(locked=True)
        locked_conv['structured']['overview'] = 'SECRET_LOCKED_OVERVIEW'
        unlocked_conv = _make_conversation(locked=False, conversation_id='conv-2')
        unlocked_conv['structured']['overview'] = 'VISIBLE_UNLOCKED_OVERVIEW'

        # Mock vector search to return both conv IDs
        with patch('utils.llm.goals.vector_search', return_value=['conv-1', 'conv-2']):
            conversations_db.get_conversations_by_id = MagicMock(return_value=[locked_conv, unlocked_conv])
            conversations_db.get_conversations = MagicMock(return_value=[])
            chat_db.get_messages = MagicMock(return_value=[])
            memories_db.get_memories = MagicMock(return_value=[])

            from utils.llm.goals import _get_goal_context

            result = _get_goal_context('test-uid', 'Exercise more')

        # Locked overview must not appear in context
        assert 'SECRET_LOCKED_OVERVIEW' not in result['conversation_context']
        assert 'VISIBLE_UNLOCKED_OVERVIEW' in result['conversation_context']

    def test_get_goal_context_filters_locked_memories(self):
        """_get_goal_context excludes locked memories from context."""
        import database.conversations as conversations_db
        import database.memories as memories_db
        import database.chat as chat_db

        locked_mem = {'content': 'LOCKED_SECRET_MEMORY', 'is_locked': True}
        unlocked_mem = {'content': 'VISIBLE_UNLOCKED_MEMORY', 'is_locked': False}

        with patch('utils.llm.goals.vector_search', return_value=[]):
            conversations_db.get_conversations_by_id = MagicMock(return_value=[])
            conversations_db.get_conversations = MagicMock(return_value=[])
            chat_db.get_messages = MagicMock(return_value=[])
            memories_db.get_memories = MagicMock(return_value=[locked_mem, unlocked_mem])

            from utils.llm.goals import _get_goal_context

            result = _get_goal_context('test-uid', 'Read more')

        assert 'LOCKED_SECRET_MEMORY' not in result['memory_context']
        assert 'VISIBLE_UNLOCKED_MEMORY' in result['memory_context']


# =============================================================================
# Test notification LLM excludes locked memories
# =============================================================================


class TestNotificationLlmLockFilter:
    """Credit-limit and subscription notifications must exclude locked memories."""

    @pytest.mark.asyncio
    async def test_get_relevant_memories_filters_locked(self):
        """get_relevant_memories must exclude locked memories from LLM context."""
        import database.memories as memories_db

        locked_mem = {'content': 'LOCKED_SECRET', 'is_locked': True}
        unlocked_mem = {'content': 'VISIBLE_CONTENT', 'is_locked': False}
        memories_db.get_memories = MagicMock(return_value=[locked_mem, unlocked_mem])

        from utils.llm.notifications import get_relevant_memories

        result = await get_relevant_memories('test-uid')

        assert len(result) == 1
        assert result[0]['content'] == 'VISIBLE_CONTENT'


# =============================================================================
# Test get_prompt_data excludes locked memories
# =============================================================================


class TestPromptDataLockFilter:
    """get_prompt_data (shared utility) must exclude locked memories."""

    def test_get_prompt_data_filters_locked_memories(self):
        """get_prompt_data must not include locked memories in prompt context."""
        import database.memories as memories_db
        from utils.memory.memory_system import MemorySystem

        locked_mem = {
            'id': 'mem-1',
            'uid': 'test-uid',
            'content': 'LOCKED_SECRET',
            'is_locked': True,
            'manually_added': False,
            'category': 'interesting',
            'created_at': '2024-01-01T00:00:00+00:00',
            'updated_at': '2024-01-01T00:00:00+00:00',
        }
        unlocked_mem = {
            'id': 'mem-2',
            'uid': 'test-uid',
            'content': 'VISIBLE_CONTENT',
            'is_locked': False,
            'manually_added': False,
            'category': 'interesting',
            'created_at': '2024-01-01T00:00:00+00:00',
            'updated_at': '2024-01-01T00:00:00+00:00',
        }
        memories_db.get_memories = MagicMock(return_value=[locked_mem, unlocked_mem])

        with (
            patch('utils.llms.memory.resolve_memory_system', return_value=MemorySystem.LEGACY),
            patch('utils.llms.memory.get_user_name', return_value='Test'),
        ):
            from utils.llms.memory import get_prompt_data

            _, baseline, user_made, generated = get_prompt_data('test-uid')

        # Only unlocked memory should appear
        all_mems = baseline + user_made + generated
        assert len(all_mems) == 1
        assert all_mems[0].content == 'VISIBLE_CONTENT'


# =============================================================================
# Test conversations list endpoint redacts locked conversations
# =============================================================================


class TestConversationListRedaction:
    """get_conversations router endpoint must redact locked conversation content."""

    def test_conversation_list_redacts_locked(self):
        """Main conversation list must clear action_items/events/transcript for locked."""
        import database.conversations as conversations_db

        locked_conv = _make_conversation(locked=True)
        unlocked_conv = _make_conversation(locked=False, conversation_id='conv-2')

        conversations_db.get_conversations_without_photos = MagicMock(return_value=[locked_conv, unlocked_conv])

        with patch('routers.conversations.auth') as mock_auth:
            mock_auth.get_current_user_uid = MagicMock(return_value='test-uid')

            from routers.conversations import get_conversations

            result = get_conversations(
                limit=100,
                offset=0,
                statuses='completed',
                include_discarded=False,
                start_date=None,
                end_date=None,
                folder_id=None,
                starred=None,
                uid='test-uid',
            )

        assert len(result) == 2
        locked = [c for c in result if c.get('is_locked')]
        assert len(locked) == 1
        assert locked[0]['structured']['action_items'] == []
        assert locked[0]['structured']['events'] == []
        assert locked[0]['transcript_segments'] == []

        unlocked = [c for c in result if not c.get('is_locked')]
        assert len(unlocked) == 1
        assert len(unlocked[0]['structured']['action_items']) == 1
        assert len(unlocked[0]['transcript_segments']) == 1


# =============================================================================
# Test suggest_goal excludes locked memories
# =============================================================================


class TestSuggestGoalLockFilter:
    """suggest_goal must exclude locked memories from context."""

    def test_suggest_goal_filters_locked_memories(self):
        """suggest_goal must not include locked memories in AI prompt context."""
        import database.memories as memories_db

        locked_mem = _make_memory(locked=True)
        locked_mem['content'] = 'LOCKED_SECRET'
        unlocked_mem = _make_memory(locked=False, memory_id='mem-2')
        unlocked_mem['content'] = 'visible goal-related memory'

        memories_db.get_memories = MagicMock(return_value=[locked_mem, unlocked_mem])

        mock_llm_response = MagicMock()
        mock_llm_response.content = '{"suggested_title": "Test Goal", "suggested_type": "scale", "suggested_target": 10, "suggested_min": 0, "suggested_max": 10, "reasoning": "test"}'

        mock_track = MagicMock()
        mock_track.__enter__ = MagicMock(return_value=None)
        mock_track.__exit__ = MagicMock(return_value=False)

        with patch('utils.llm.goals.track_usage', return_value=mock_track):
            with patch('utils.llm.goals.get_llm') as mock_get_llm:
                mock_llm = MagicMock()
                mock_llm.invoke.return_value = mock_llm_response
                mock_get_llm.return_value = mock_llm

                from utils.llm.goals import suggest_goal

                result = suggest_goal('test-uid')

        # Verify the prompt sent to the LLM did not contain locked content
        call_args = mock_llm.invoke.call_args[0][0]
        prompt_text = str(call_args)
        assert 'LOCKED_SECRET' not in prompt_text
        assert 'visible goal-related memory' in prompt_text


# =============================================================================
# Test folder move — is_locked enforcement (#6511)
# =============================================================================


class TestFolderMoveLockEnforcement:
    """Gap 10 + bonus: Folder move must reject locked conversations."""

    def test_move_conversation_rejects_locked(self):
        import database.conversations as conversations_db

        conversations_db.get_conversation = MagicMock(return_value=_make_conversation(locked=True))

        from routers.folders import move_conversation_to_folder, MoveConversationRequest

        request = MoveConversationRequest(folder_id='folder-1')
        try:
            move_conversation_to_folder('conv-1', request, uid='test-uid')
            assert False, "Should have raised HTTPException"
        except Exception as e:
            assert e.status_code == 402

    def test_move_conversation_allows_unlocked(self):
        import database.conversations as conversations_db
        import database.folders as folders_db

        conversations_db.get_conversation = MagicMock(return_value=_make_conversation(locked=False))
        folders_db.get_folder = MagicMock(return_value={'id': 'folder-1', 'name': 'Test'})
        folders_db.move_conversation_to_folder = MagicMock()

        from routers.folders import move_conversation_to_folder, MoveConversationRequest

        request = MoveConversationRequest(folder_id='folder-1')
        result = move_conversation_to_folder('conv-1', request, uid='test-uid')
        assert result == {"status": "ok", "conversation": _make_conversation(locked=False)}

    def test_bulk_move_rejects_if_any_locked(self):
        import database.conversations as conversations_db
        import database.folders as folders_db

        conversations_db.get_conversation = MagicMock(
            side_effect=[
                _make_conversation(locked=False, conversation_id='conv-1'),
                _make_conversation(locked=True, conversation_id='conv-2'),
            ]
        )
        folders_db.get_folder = MagicMock(return_value={'id': 'folder-1', 'name': 'Test'})

        from routers.folders import bulk_move_conversations, BulkMoveConversationsRequest

        request = BulkMoveConversationsRequest(conversation_ids=['conv-1', 'conv-2'])
        try:
            bulk_move_conversations('folder-1', request, uid='test-uid')
            assert False, "Should have raised HTTPException"
        except Exception as e:
            assert e.status_code == 402

    def test_bulk_move_allows_all_unlocked(self):
        import database.conversations as conversations_db
        import database.folders as folders_db

        conversations_db.get_conversation = MagicMock(
            side_effect=[
                _make_conversation(locked=False, conversation_id='conv-1'),
                _make_conversation(locked=False, conversation_id='conv-2'),
            ]
        )
        folders_db.get_folder = MagicMock(return_value={'id': 'folder-1', 'name': 'Test'})
        folders_db.bulk_move_conversations_to_folder = MagicMock(return_value=2)

        from routers.folders import bulk_move_conversations, BulkMoveConversationsRequest

        request = BulkMoveConversationsRequest(conversation_ids=['conv-1', 'conv-2'])
        result = bulk_move_conversations('folder-1', request, uid='test-uid')
        assert result == {"status": "ok", "moved_count": 2}


class TestConversationCanonicalMutationResponses:
    def test_title_endpoint_returns_post_write_canonical_snapshot(self, monkeypatch):
        import database.conversations as conversations_db
        from routers import conversations as conversations_router

        before = {'id': 'conversation-1', 'structured': {'title': 'Before'}}
        canonical = {
            'id': 'conversation-1',
            'updated_at': datetime(2026, 7, 9, 12, 0, tzinfo=timezone.utc),
            'structured': {'title': 'Renamed', 'overview': 'Processing finished'},
        }
        responses = iter([before, canonical])
        monkeypatch.setattr(conversations_router, '_get_valid_conversation_by_id', lambda *_args: next(responses))
        update_title = MagicMock()
        monkeypatch.setattr(conversations_db, 'update_conversation_title', update_title)

        result = conversations_router.patch_conversation_title('conversation-1', 'Renamed', uid='user-1')

        assert result == {'status': 'Ok', 'conversation': canonical}
        update_title.assert_called_once_with('user-1', 'conversation-1', 'Renamed')

    def test_star_endpoint_returns_post_write_processing_state(self, monkeypatch):
        import database.conversations as conversations_db
        from routers import conversations as conversations_router

        before = {'id': 'conversation-1', 'starred': False, 'status': 'processing'}
        canonical = {
            'id': 'conversation-1',
            'updated_at': datetime(2026, 7, 9, 12, 0, tzinfo=timezone.utc),
            'starred': True,
            'status': 'completed',
            'structured': {'overview': 'Processing finished'},
        }
        responses = iter([before, canonical])
        monkeypatch.setattr(conversations_router, '_get_valid_conversation_by_id', lambda *_args: next(responses))
        set_starred = MagicMock()
        monkeypatch.setattr(conversations_db, 'set_conversation_starred', set_starred)

        result = conversations_router.set_conversation_starred('conversation-1', True, uid='user-1')

        assert result == {'status': 'Ok', 'conversation': canonical}
        set_starred.assert_called_once_with('user-1', 'conversation-1', True)
