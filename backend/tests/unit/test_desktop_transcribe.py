"""Tests for desktop PTT transcription migration (#6286).

Verifies:
- managed_stt_prerecorded_from_bytes passes encoding/language/model correctly
- transcribe_pcm_bytes language/model selection and error propagation
"""

import importlib.util
import os
import shutil as _shutil
import sys
import threading
import time
from pathlib import Path
from types import ModuleType, SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from starlette.websockets import WebSocketDisconnect

# ---------------------------------------------------------------------------
# Module-level dependency stubs for this focused suite
# ---------------------------------------------------------------------------

BACKEND_DIR = Path(__file__).resolve().parents[2]


def _ensure_package(name, path):
    module = sys.modules.get(name)
    if module is None or not hasattr(module, '__path__'):
        module = ModuleType(name)
        sys.modules[name] = module
    module.__path__ = [str(path)]

    if '.' in name:
        parent_name, attr_name = name.rsplit('.', 1)
        parent = sys.modules.get(parent_name)
        if parent is not None:
            setattr(parent, attr_name, module)

    return module


def _install_module(name):
    module = ModuleType(name)
    sys.modules[name] = module
    if '.' in name:
        parent_name, attr_name = name.rsplit('.', 1)
        parent = sys.modules.get(parent_name)
        if parent is not None:
            setattr(parent, attr_name, module)
    return module


def _attach_existing_module(name):
    if '.' not in name or name not in sys.modules:
        return
    parent_name, attr_name = name.rsplit('.', 1)
    parent = sys.modules.get(parent_name)
    if parent is not None:
        setattr(parent, attr_name, sys.modules[name])


def _restore_package_paths():
    _ensure_package('models', BACKEND_DIR / 'models')
    _ensure_package('database', BACKEND_DIR / 'database')
    _ensure_package('utils', BACKEND_DIR / 'utils')
    _ensure_package('utils.stt', BACKEND_DIR / 'utils' / 'stt')
    for name in [
        'utils.chat',
        'utils.stt.pre_recorded',
        'utils.stt.speaker_embedding',
        'google.cloud',
        'google.cloud.storage',
    ]:
        _attach_existing_module(name)
    notifications = sys.modules.get('utils.notifications')
    if notifications is not None and not hasattr(notifications, 'send_notification'):
        notifications.send_notification = MagicMock()
    redis_db = sys.modules.get('database.redis_db')
    if redis_db is not None:
        redis_db.check_rate_limit = MagicMock(return_value=(True, 99, 0))
        redis_db.try_acquire_listen_lock = MagicMock(return_value=True)
        redis_db.try_acquire_goal_extraction_lock = MagicMock(return_value=True)
        redis_db.store_chat_share = MagicMock()
        redis_db.get_chat_share = MagicMock(return_value=None)


from testing.import_isolation import stub_modules


@pytest.fixture(scope="module", autouse=True)
def _desktop_transcribe_isolation():
    """Original module-scope stubs (database/utils/models tree + models.chat real
    load) moved into a fixture so they don't leak across test files. The stubs are
    load-bearing for runtime (tests exercise utils.chat/transcribe_pcm_bytes which
    call into database.* / managed STT at runtime). stub_modules-style teardown evicts
    everything loaded here on exit."""
    import sys as _sys

    # Full object snapshot, not just a key set: a prior test file may have
    # imported the real ``utils.stt.speaker_embedding`` / ``utils.conversations.factory``
    # which this fixture replaces with ModuleType stubs. Evicting only *new* keys
    # (the original ``_saved_keys = set(_sys.modules)`` approach) leaves those stubs
    # in place — the real module object is never restored and the hermeticity guard
    # flags them as leaked stubs shadowing real source. Mirroring the sanctioned
    # ``stub_modules`` teardown: evict new keys AND restore swapped values.
    _saved_modules = dict(_sys.modules)
    _saved_keys = set(_saved_modules)
    try:
        _restore_package_paths()

        # Stub models package (required before importing utils.stt.pre_recorded)
        _models_pkg = sys.modules['models']

        for _msub in [
            'other',
            'transcript_segment',
            'chat',
            'conversation',
            'notification_message',
            'app',
            'memory',
            'action_item',
        ]:
            _mfull = f'models.{_msub}'
            if _mfull not in sys.modules:
                _mm = MagicMock()
                sys.modules[_mfull] = _mm
                setattr(_models_pkg, _msub, _mm)

        # Stub database package
        _database_pkg = sys.modules['database']

        for _sub in [
            '_client',
            'action_items',
            'announcements',
            'apps',
            'auth',
            'cache',
            'cache_manager',
            'calendar_meetings',
            'chat',
            'conversations',
            'daily_summaries',
            'dev_api_key',
            'fair_use',
            'folders',
            'goals',
            'helpers',
            'import_jobs',
            'knowledge_graph',
            'llm_usage',
            'mcp_api_key',
            'mem_db',
            'memories',
            'notifications',
            'phone_calls',
            'redis_db',
            'redis_pubsub',
            'screen_activity',
            'tasks',
            'trends',
            'user_usage',
            'users',
            'vector_db',
            'wrapped',
            'people',
            'processing_memories',
            'plugins',
        ]:
            _full = f'database.{_sub}'
            if _full not in sys.modules:
                _m = MagicMock()
                sys.modules[_full] = _m
                setattr(_database_pkg, _sub, _m)

        _redis_db_stub = sys.modules['database.redis_db']
        _redis_db_stub.check_rate_limit = MagicMock(return_value=(True, 99, 0))
        _redis_db_stub.try_acquire_listen_lock = MagicMock(return_value=True)
        _redis_db_stub.try_acquire_goal_extraction_lock = MagicMock(return_value=True)
        _redis_db_stub.store_chat_share = MagicMock()
        _redis_db_stub.get_chat_share = MagicMock(return_value=None)

        _fb = MagicMock()
        _fb.__path__ = ['firebase_admin']
        sys.modules.setdefault('firebase_admin', _fb)
        sys.modules.setdefault('firebase_admin.messaging', _fb.messaging)
        sys.modules.setdefault('firebase_admin.auth', _fb.auth)
        if not hasattr(sys.modules['firebase_admin.auth'], 'InvalidIdTokenError'):
            sys.modules['firebase_admin.auth'].InvalidIdTokenError = type('InvalidIdTokenError', (Exception,), {})
        sys.modules['firebase_admin'].auth = sys.modules['firebase_admin.auth']

        def _parse_options_header(value):
            if value is None:
                return b'', {}
            if isinstance(value, str):
                value = value.encode('latin-1')

            parts = value.split(b';')
            disposition = parts[0].strip().lower()
            options = {}
            for part in parts[1:]:
                if b'=' not in part:
                    continue
                key, raw_value = part.split(b'=', 1)
                raw_value = raw_value.strip()
                if len(raw_value) >= 2 and raw_value[:1] == b'"' and raw_value[-1:] == b'"':
                    raw_value = raw_value[1:-1]
                options[key.strip().lower()] = raw_value
            return disposition, options

        class _QuerystringParser:
            def __init__(self, callbacks):
                self.callbacks = callbacks
                self.data = bytearray()

            def write(self, data):
                self.data.extend(data)

            def finalize(self):
                for item in bytes(self.data).split(b'&'):
                    if not item:
                        continue
                    name, _, value = item.partition(b'=')
                    self.callbacks['on_field_start']()
                    self.callbacks['on_field_name'](name, 0, len(name))
                    self.callbacks['on_field_data'](value, 0, len(value))
                    self.callbacks['on_field_end']()
                self.callbacks['on_end']()

        class _MultipartParser:
            def __init__(self, boundary, callbacks):
                self.boundary = boundary.encode('latin-1') if isinstance(boundary, str) else boundary
                self.callbacks = callbacks
                self.data = bytearray()

            def write(self, data):
                self.data.extend(data)

            def finalize(self):
                delimiter = b'--' + self.boundary
                for part in bytes(self.data).split(delimiter):
                    part = part.strip(b'\r\n')
                    if not part or part == b'--':
                        continue
                    if part.endswith(b'--'):
                        part = part[:-2].strip(b'\r\n')
                    if b'\r\n\r\n' not in part:
                        continue

                    header_blob, body = part.split(b'\r\n\r\n', 1)
                    self.callbacks['on_part_begin']()
                    for header in header_blob.split(b'\r\n'):
                        name, _, value = header.partition(b':')
                        name = name.strip()
                        value = value.strip()
                        self.callbacks['on_header_field'](name, 0, len(name))
                        self.callbacks['on_header_value'](value, 0, len(value))
                        self.callbacks['on_header_end']()
                    self.callbacks['on_headers_finished']()
                    self.callbacks['on_part_data'](body, 0, len(body))
                    self.callbacks['on_part_end']()
                self.callbacks['on_end']()

        def _install_multipart_stub_if_missing():
            if importlib.util.find_spec('python_multipart') is None and 'python_multipart' not in sys.modules:
                python_multipart = ModuleType('python_multipart')
                python_multipart.__version__ = '0.0.20'
                python_multipart.MultipartParser = _MultipartParser
                python_multipart.QuerystringParser = _QuerystringParser

                python_multipart_submodule = ModuleType('python_multipart.multipart')
                python_multipart_submodule.parse_options_header = _parse_options_header

                sys.modules['python_multipart'] = python_multipart
                sys.modules['python_multipart.multipart'] = python_multipart_submodule

            if importlib.util.find_spec('multipart') is None and 'multipart' not in sys.modules:
                multipart = ModuleType('multipart')
                multipart.__version__ = '0.0.20'
                multipart.MultipartParser = _MultipartParser
                multipart.QuerystringParser = _QuerystringParser

                multipart_submodule = ModuleType('multipart.multipart')
                multipart_submodule.parse_options_header = _parse_options_header
                multipart_submodule.shutil = _shutil

                sys.modules['multipart'] = multipart
                sys.modules['multipart.multipart'] = multipart_submodule

            try:
                import starlette.formparsers as formparsers
            except ImportError:
                return
            formparsers.multipart = sys.modules.get('python_multipart') or sys.modules.get('multipart')
            formparsers.parse_options_header = _parse_options_header

        _install_multipart_stub_if_missing()

        _speaker_embedding = ModuleType('utils.stt.speaker_embedding')
        _speaker_embedding.SPEAKER_MATCH_THRESHOLD = 0.45
        _speaker_embedding.compare_embeddings = MagicMock(return_value=0.0)
        _speaker_embedding.extract_embedding_from_bytes = MagicMock()
        _speaker_embedding.async_extract_embedding_from_bytes = AsyncMock(return_value=None)
        sys.modules['utils.stt.speaker_embedding'] = _speaker_embedding
        _attach_existing_module('utils.stt.speaker_embedding')

        _ensure_package('google', BACKEND_DIR / 'tests')
        _ensure_package('google.cloud', BACKEND_DIR / 'tests')
        _ensure_package('google.auth', BACKEND_DIR / 'tests')
        _google_auth_exceptions = _install_module('google.auth.exceptions')
        _google_auth_exceptions.DefaultCredentialsError = type('DefaultCredentialsError', (Exception,), {})
        _google_auth_transport = _install_module('google.auth.transport')
        _google_auth_transport_requests = _install_module('google.auth.transport.requests')
        _google_auth_transport_requests.Request = MagicMock
        _ensure_package('google.api_core', BACKEND_DIR / 'tests')
        _api_core_exceptions = _install_module('google.api_core.exceptions')
        _api_core_exceptions.AlreadyExists = type('AlreadyExists', (Exception,), {})
        _api_core_exceptions.Conflict = type('Conflict', (Exception,), {})
        _api_core_exceptions.NotFound = type('NotFound', (Exception,), {})
        _gcs = _install_module('google.cloud.storage')
        _gcs.Client = MagicMock
        _tasks_v2 = _install_module('google.cloud.tasks_v2')
        _tasks_v2.CloudTasksClient = MagicMock
        _ensure_package('google.oauth2', BACKEND_DIR / 'tests')
        _id_token = _install_module('google.oauth2.id_token')
        _id_token.verify_oauth2_token = MagicMock()
        _ensure_package('google.protobuf', BACKEND_DIR / 'tests')
        _duration_pb2 = _install_module('google.protobuf.duration_pb2')
        _duration_pb2.Duration = MagicMock

        os.environ.setdefault('OPENAI_API_KEY', 'sk-fake-for-test')
        os.environ.setdefault(
            'ENCRYPTION_SECRET', 'omi_ZwB2ZNqB2HHpMK6wStk7sTpavJiPTFg7gXUHnc4tFABPU6pZ2c2DKgehtfgi4RZv'
        )
        os.makedirs('/tmp', exist_ok=True)

        # Stub transitive imports for utils.chat (avoid pulling in all of utils.llm etc.)
        # Do NOT stub utils.other.endpoints — it contains the @timeit decorator that must
        # be a real function (not MagicMock) or it corrupts decorated function signatures.
        for _ufull in [
            'utils.llm',
            'utils.llm.memories',
            'utils.llm.persona',
            'utils.llm.chat',
            'utils.llm.goals',
            'utils.llm.usage_tracker',
            'utils.conversations.process_conversation',
            'utils.notifications',
            'utils.other.storage',
            'utils.other.chat_file',
            'utils.apps',
            'utils.retrieval',
            'utils.retrieval.graph',
            'utils.fair_use',
            'utils.cloud_tasks',
            'utils.log_sanitizer',
            'models.fair_use',
            'models.processing_memory',
            'models.integrations',
            'models.goal',
        ]:
            sys.modules.setdefault(_ufull, MagicMock())

        _utils_conversations_pkg = ModuleType('utils.conversations')
        _utils_conversations_pkg.__path__ = []
        _utils_conversations_pkg.__package__ = 'utils.conversations'
        _utils_conversations_factory = ModuleType('utils.conversations.factory')
        _utils_conversations_factory.deserialize_conversation = MagicMock(side_effect=lambda conversation: conversation)
        sys.modules['utils.conversations'] = _utils_conversations_pkg
        sys.modules['utils.conversations.factory'] = _utils_conversations_factory
        setattr(_utils_conversations_pkg, 'factory', _utils_conversations_factory)

        # Force-import real models.chat (has no project deps, needed for FastAPI response_model)
        import importlib.util as _ilu

        _chat_spec = _ilu.spec_from_file_location(
            'models.chat', os.path.join(os.path.dirname(__file__), '..', '..', 'models', 'chat.py')
        )
        _real_chat = _ilu.module_from_spec(_chat_spec)
        _chat_spec.loader.exec_module(_real_chat)
        sys.modules['models.chat'] = _real_chat
        setattr(_models_pkg, 'chat', _real_chat)

        # Import the production helper during fixture setup so its transitive
        # import cost is not charged to the first fast-unit call phase.
        importlib.import_module('utils.chat')
        yield
    finally:
        import sys as _sys2

        # evict modules added during the block, restoring process state
        for _k in list(_sys2.modules.keys() - _saved_keys):
            _sys2.modules.pop(_k, None)

        # restore existing keys whose object was swapped in place by this fixture
        # (e.g. ``utils.stt.speaker_embedding`` replaced with a ModuleType stub)
        for _k, _orig in _saved_modules.items():
            _cur = _sys2.modules.get(_k)
            if _cur is not None and _cur is not _orig:
                _sys2.modules[_k] = _orig


# ---------------------------------------------------------------------------
# managed_stt_prerecorded_from_bytes: encoding/language/model options
# ---------------------------------------------------------------------------


class TestTranscribePcmBytes:
    """Behavioral coverage for the public desktop batch-transcription helper."""

    def test_multilingual_success_forwards_audio_options_and_joins_segments(self):
        from utils import chat

        words = [object()]
        with (
            patch.object(chat, 'get_prerecorded_service', return_value=('modulate', 'multi', 'modulate-velma-2')),
            patch.object(chat, 'linear16_pcm_is_silent', return_value=False),
            patch.object(chat, 'prerecorded_from_bytes', return_value=(words, 'en')) as transcribe,
            patch.object(
                chat,
                'postprocess_words',
                return_value=[SimpleNamespace(text='Hello'), SimpleNamespace(text='world')],
            ),
        ):
            result = chat.transcribe_pcm_bytes(
                b'\x01\x00' * 160,
                uid='user-1',
                language='multi',
                encoding='linear16',
                sample_rate=16000,
                channels=1,
                keywords=['Omi'],
            )

        assert result == ('Hello world', 'en')
        transcribe.assert_called_once_with(
            b'\x01\x00' * 160,
            sample_rate=16000,
            diarize=False,
            encoding='linear16',
            channels=1,
            language='multi',
            return_language=True,
            keywords=['Omi'],
        )

    def test_linear16_silence_returns_without_calling_provider(self):
        from utils import chat

        with (
            patch.object(chat, 'get_prerecorded_service', return_value=('modulate', 'en', 'modulate-velma-2')),
            patch.object(chat, 'linear16_pcm_is_silent', return_value=True),
            patch.object(chat, 'prerecorded_from_bytes') as transcribe,
        ):
            result = chat.transcribe_pcm_bytes(b'\x00' * 320, uid='user-1', language='en')

        assert result == (None, 'en')
        transcribe.assert_not_called()

    def test_provider_timeout_becomes_typed_modulate_failure(self):
        from utils import chat
        from utils.stt.outcomes import TranscriptionFailure

        with (
            patch.object(chat, 'get_prerecorded_service', return_value=('modulate', 'multi', 'modulate-velma-2')),
            patch.object(chat, 'linear16_pcm_is_silent', return_value=False),
            patch.object(chat, 'prerecorded_from_bytes', side_effect=TimeoutError('provider detail')),
        ):
            with pytest.raises(TranscriptionFailure) as exc_info:
                chat.transcribe_pcm_bytes(b'\x01\x00' * 160, uid='user-1', language='multi')

        assert exc_info.value.outcome.value == 'timeout'
        assert exc_info.value.provider == 'modulate'
        assert exc_info.value.retryable is True


def _stub_router_deps():
    """Stub all transitive dependencies needed to import routers.chat via importlib."""
    extra_models = [
        'models.fair_use',
        'models.users',
        'models.processing_memory',
        'models.integrations',
        'models.goal',
        'models.screen_pipe',
    ]
    extra_database = ['database.user_usage']
    extra_utils = [
        'utils.fair_use',
        'utils.log_sanitizer',
        'utils.subscription',
        'utils.social',
        'utils.speaker_assignment',
        'utils.speaker_identification',
        'utils.stt.speaker_embedding',
        'utils.stt.vad',
        'utils.stt.streaming',
        'utils.stt.vad_gate',
    ]
    for mod in extra_models + extra_database + extra_utils:
        sys.modules.setdefault(mod, MagicMock())
    opuslib_stub = ModuleType('opuslib')
    opuslib_stub.Decoder = MagicMock()
    sys.modules['opuslib'] = opuslib_stub
    pydub_stub = ModuleType('pydub')
    pydub_stub.AudioSegment = MagicMock()
    sys.modules['pydub'] = pydub_stub
    limiter_stub = ModuleType('utils.voice_duration_limiter')
    limiter_stub.compute_pcm_duration_ms = lambda byte_count, sample_rate, channels: int(
        byte_count / (sample_rate * channels * 2) * 1000
    )
    limiter_stub.read_wav_duration_ms = MagicMock(return_value=1000)
    limiter_stub.try_consume_budget = MagicMock(return_value=(True, 0, 7200000))
    limiter_stub.check_budget = MagicMock(return_value=(True, 0, 7200000))
    limiter_stub.record_actual_duration = MagicMock()
    sys.modules['utils.voice_duration_limiter'] = limiter_stub
    subscription_stub = sys.modules.setdefault('utils.subscription', MagicMock())
    subscription_stub.enforce_chat_quota = MagicMock()
    subscription_stub.is_trial_paywalled = MagicMock(return_value=False)
    # Ensure redis_db.check_rate_limit returns (True, 99, 0)
    rdb = sys.modules.get('database.redis_db')
    if rdb:
        rdb.check_rate_limit = MagicMock(return_value=(True, 99, 0))


def _make_chat_client():
    """Build a TestClient for the chat router with mocked auth."""
    import importlib.util
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    saved = {k: v for k, v in sys.modules.items()}

    _stub_router_deps()

    sys.modules.pop('routers.chat', None)
    spec = importlib.util.spec_from_file_location(
        'routers_chat_test',
        os.path.join(os.path.dirname(__file__), '..', '..', 'routers', 'chat.py'),
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    async def drain_stt_socket(socket):
        drain = getattr(socket, 'drain_and_close', None)
        if callable(drain):
            result = drain()
            if hasattr(result, '__await__'):
                await result
                return
        socket.finish()

    # utils.stt.streaming is intentionally stubbed for these broad router tests.
    # Preserve the managed socket's teardown contract explicitly; its connection
    # and telemetry behavior have focused tests of their own.
    module.drain_stt_socket = drain_stt_socket

    # These router tests exercise request validation and error handling, not
    # Firestore preference lookup or provider selection. Keep both boundaries
    # deterministic and aligned with the fixed managed serving policy.
    module.resolve_voice_message_language = lambda _uid, language: language or 'multi'
    module.get_prerecorded_service = lambda language: ('modulate', language or 'multi', 'modulate-velma-2')

    app = FastAPI()
    app.include_router(module.router)

    # Override the rate-limited auth dependency for all endpoints
    for route in app.routes:
        if hasattr(route, 'dependant'):
            for dep in route.dependant.dependencies:
                if dep.call is not None:
                    app.dependency_overrides[dep.call] = lambda: 'test-uid'

    client = TestClient(app)
    return client, module, saved


def _cleanup_chat_client(saved):
    to_remove = [k for k in sys.modules if k not in saved]
    for k in to_remove:
        del sys.modules[k]


class TestVoiceMessageTranscribeEndpoint:
    """Test /v2/voice-message/transcribe content-type dispatch and validation."""

    def test_openapi_declares_typed_transcription_failures(self):
        client, module, saved = _make_chat_client()
        try:
            operation = client.get('/openapi.json').json()['paths']['/v2/voice-message/transcribe']['post']
            for status in ('400', '502', '503', '504'):
                schema = operation['responses'][status]['content']['application/json']['schema']
                assert schema['$ref'].endswith('/TranscriptionErrorResponse')
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_returns_transcript(self, mock_transcribe):
        """application/octet-stream should dispatch to PCM path and return JSON."""
        mock_transcribe.return_value = ('Hello world', 'en')
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?keywords=Aarav,Ansh,Aarav',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 200
            data = resp.json()
            assert data['transcript'] == 'Hello world'
            assert data['language'] == 'en'
            assert data['stt_provider'] == 'modulate'
            assert data['stt_model'] == 'modulate-velma-2'
            assert data['outcome'] == 'success'
            assert mock_transcribe.call_args.kwargs['keywords'] == ['Aarav', 'Ansh']
        finally:
            _cleanup_chat_client(saved)

    def test_octet_stream_empty_body_400(self):
        """Empty octet-stream body should return 400."""
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe',
                content=b'',
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 400
            assert 'No audio data' in resp.json()['detail']
        finally:
            _cleanup_chat_client(saved)

    def test_octet_stream_bad_sample_rate_400(self):
        """Non-integer sample_rate returns a typed invalid-input failure."""
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?sample_rate=abc',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 400
            assert resp.json()['detail']['outcome'] == 'invalid_input'
        finally:
            _cleanup_chat_client(saved)

    def test_octet_stream_bad_channels_400(self):
        """Non-integer channels returns a typed invalid-input failure."""
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?channels=',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 400
            assert resp.json()['detail']['outcome'] == 'invalid_input'
        finally:
            _cleanup_chat_client(saved)

    def test_octet_stream_sample_rate_zero_400(self):
        """sample_rate=0 returns a typed invalid-input failure."""
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?sample_rate=0',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 400
            assert resp.json()['detail']['outcome'] == 'invalid_input'
        finally:
            _cleanup_chat_client(saved)

    def test_octet_stream_channels_zero_400(self):
        """channels=0 returns a typed invalid-input failure."""
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?channels=0',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 400
            assert resp.json()['detail']['outcome'] == 'invalid_input'
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_no_speech_empty_transcript(self, mock_transcribe):
        """No speech detected should return 200 with empty transcript (not 422)."""
        mock_transcribe.return_value = (None, 'en')
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 200
            assert resp.json()['transcript'] == ''
            assert resp.json()['outcome'] == 'expected_silence'
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_runtime_error_returns_safe_502(self, mock_transcribe):
        """Provider failures return a typed safe payload without exception text."""
        mock_transcribe.side_effect = RuntimeError('secret upstream response body')
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 502
            detail = resp.json()['detail']
            assert detail['error'] == 'stt_upstream_error'
            assert detail['outcome'] == 'upstream_error'
            assert detail['retryable'] is True
            assert 'secret upstream response body' not in resp.text
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_timeout_returns_safe_504(self, mock_transcribe):
        """A typed timeout has distinct status and safe retry metadata."""
        from utils.stt.outcomes import TranscriptionFailure, TranscriptionOutcome

        mock_transcribe.side_effect = TranscriptionFailure(TranscriptionOutcome.TIMEOUT, provider='managed_stt')
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe',
                content=b'\x01' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 504
            assert resp.json()['detail']['outcome'] == 'timeout'
            assert resp.json()['detail']['retryable'] is True
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_provider_empty_returns_safe_502(self, mock_transcribe):
        """Speech-positive empty output is distinct from the 200 silence path."""
        from utils.stt.outcomes import TranscriptionFailure, TranscriptionOutcome

        mock_transcribe.side_effect = TranscriptionFailure(
            TranscriptionOutcome.EMPTY_UNEXPECTED,
            provider='managed_stt',
        )
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe',
                content=b'\x01' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 502
            assert resp.json()['detail']['outcome'] == 'empty_unexpected'
            assert resp.json()['detail']['retryable'] is True
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_missing_managed_configuration_returns_controlled_503(self, mock_transcribe):
        """A selected provider missing runtime config must not escape as a generic 500."""
        from utils.stt.pre_recorded import PrerecordedSTTConfigurationError

        mock_transcribe.side_effect = PrerecordedSTTConfigurationError()
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?language=en',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 503
            detail = resp.json()['detail']
            assert detail['error'] == 'stt_provider_configuration_error'
            assert detail['outcome'] == 'config_error'
            assert detail['provider'] == 'modulate'
            assert detail['retryable'] is False
            assert 'MODULATE_API_KEY' not in resp.text
        finally:
            _cleanup_chat_client(saved)

    @pytest.mark.parametrize(
        ('suffix', 'content_type'),
        [('webm', 'audio/webm'), ('mp4', 'audio/mp4')],
    )
    def test_multipart_browser_container_preserves_extension_for_prerecorded_stt(self, suffix, content_type):
        """Browser MediaRecorder uploads must not be stored as WAV files."""
        client, module, saved = _make_chat_client()
        try:
            with patch.object(
                module, 'transcribe_voice_message_segment', return_value=('Hello world', 'en')
            ) as transcribe:
                response = client.post(
                    '/v2/voice-message/transcribe',
                    files={'files': (f'audio.{suffix}', b'containerized-audio', content_type)},
                )

            assert response.status_code == 200
            assert response.json()['transcript'] == 'Hello world'
            assert transcribe.call_args.args[0].endswith(f'.{suffix}')
        finally:
            _cleanup_chat_client(saved)


# ---------------------------------------------------------------------------
# WebSocket endpoint tests: /v2/voice-message/transcribe-stream
# ---------------------------------------------------------------------------


class TestTranscribeStreamWebSocket:
    """Test /v2/voice-message/transcribe-stream WebSocket endpoint."""

    def test_ws_connects_and_receives_segments(self):
        """WebSocket accepts connection and forwards managed STT segments."""
        client, module, saved = _make_chat_client()
        try:
            mock_stt_socket = MagicMock()
            mock_stt_socket.is_connection_dead = False
            mock_stt_socket.death_reason = None

            async def mock_process_audio_modulate(stream_transcript, sample_rate, language):
                def fake_send(data):
                    stream_transcript(
                        [
                            {
                                'speaker': 'SPEAKER_00',
                                'start': 0.0,
                                'end': 1.0,
                                'text': 'Hello',
                                'is_user': False,
                                'person_id': None,
                            }
                        ]
                    )
                    return True

                mock_stt_socket.send = MagicMock(side_effect=fake_send)
                mock_stt_socket.finalize = MagicMock()
                mock_stt_socket.finish = MagicMock()
                return mock_stt_socket

            with patch.object(module, 'check_budget', return_value=(True, 0, 7200000)):
                with patch.object(module, 'process_audio_modulate', side_effect=mock_process_audio_modulate):
                    with client.websocket_connect(
                        '/v2/voice-message/transcribe-stream?language=en&sample_rate=16000'
                    ) as ws:
                        # Send enough audio to trigger a 30ms flush (16000 * 2 * 0.03 = 960 bytes)
                        ws.send_bytes(b'\x00' * 960)
                        data = ws.receive_json()
                        assert isinstance(data, list)
                        assert len(data) == 1
                        assert data[0]['text'] == 'Hello'
                        assert data[0]['speaker'] == 'SPEAKER_00'
        finally:
            _cleanup_chat_client(saved)

    def test_ws_provider_connection_failure_closes_1011(self):
        """A managed adapter connection failure closes with 1011."""
        client, module, saved = _make_chat_client()
        try:

            async def mock_process_audio_modulate_fail(stream_transcript, sample_rate, language):
                return None

            with patch.object(module, 'process_audio_modulate', side_effect=mock_process_audio_modulate_fail):
                with pytest.raises(Exception):
                    with client.websocket_connect('/v2/voice-message/transcribe-stream') as ws:
                        ws.receive_json()  # Should not get here
        finally:
            _cleanup_chat_client(saved)


class TestVoiceMessageTranscribeBoundary:
    """Boundary tests for /v2/voice-message/transcribe REST endpoint."""

    def test_octet_stream_sample_rate_above_48000_rejected(self):
        """sample_rate > 48000 returns a typed invalid-input failure."""
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?sample_rate=96000',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 400
            assert resp.json()['detail']['outcome'] == 'invalid_input'
        finally:
            _cleanup_chat_client(saved)

    def test_octet_stream_channels_above_2_rejected(self):
        """channels > 2 returns a typed invalid-input failure."""
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?channels=3',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 400
            assert resp.json()['detail']['outcome'] == 'invalid_input'
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_accepts_boundary_sample_rate_8000(self, mock_transcribe):
        """sample_rate=8000 (lower bound) should be accepted."""
        mock_transcribe.return_value = ('hello', 'en')
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?sample_rate=8000',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 200
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_accepts_boundary_sample_rate_48000(self, mock_transcribe):
        """sample_rate=48000 (upper bound) should be accepted."""
        mock_transcribe.return_value = ('hello', 'en')
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?sample_rate=48000',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 200
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_accepts_channels_2(self, mock_transcribe):
        """channels=2 (upper bound) should be accepted."""
        mock_transcribe.return_value = ('hello', 'en')
        client, module, saved = _make_chat_client()
        try:
            resp = client.post(
                '/v2/voice-message/transcribe?channels=2',
                content=b'\x00' * 3200,
                headers={'Content-Type': 'application/octet-stream'},
            )
            assert resp.status_code == 200
        finally:
            _cleanup_chat_client(saved)


# ---------------------------------------------------------------------------
# Duration budget enforcement: octet-stream, multipart, and WebSocket
# ---------------------------------------------------------------------------


class TestDurationBudgetEnforcement:
    """Test daily budget enforcement across all three endpoints."""

    def test_octet_stream_budget_exhausted_429(self):
        """Octet-stream request with exhausted budget should return 429."""
        client, module, saved = _make_chat_client()
        try:
            with patch.object(module, 'try_consume_budget', return_value=(False, 7200000, 0)):
                resp = client.post(
                    '/v2/voice-message/transcribe',
                    content=b'\x00' * 3200,
                    headers={'Content-Type': 'application/octet-stream'},
                )
                assert resp.status_code == 429
                assert 'budget exhausted' in resp.json()['detail']
        finally:
            _cleanup_chat_client(saved)

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_octet_stream_budget_consumed_with_correct_duration(self, mock_transcribe):
        """Successful octet-stream request should consume budget with correct duration_ms."""
        mock_transcribe.return_value = ('hello', 'en')
        client, module, saved = _make_chat_client()
        try:
            with patch.object(module, 'try_consume_budget', return_value=(True, 1000, 7199000)) as mock_budget:
                resp = client.post(
                    '/v2/voice-message/transcribe',
                    # 32000 bytes at 16kHz mono = 1 second = 1000ms
                    content=b'\x00' * 32000,
                    headers={'Content-Type': 'application/octet-stream'},
                )
                assert resp.status_code == 200
                mock_budget.assert_called_once()
                call_args = mock_budget.call_args[0]
                assert call_args[0] == 'test-uid'
                assert call_args[1] == 1000  # 32000 / (16000*1*2) * 1000
        finally:
            _cleanup_chat_client(saved)

    def test_multipart_budget_exhausted_429(self):
        """Multipart upload with exhausted budget should return 429."""
        import io

        client, module, saved = _make_chat_client()
        try:
            with patch.object(module, 'read_wav_duration_ms', return_value=60_000):
                with patch.object(module, 'try_consume_budget', return_value=(False, 7200000, 0)):
                    resp = client.post(
                        '/v2/voice-message/transcribe',
                        files=[('files', ('test.wav', io.BytesIO(b'\x00' * 100), 'audio/wav'))],
                    )
                    assert resp.status_code == 429
                    assert 'budget exhausted' in resp.json()['detail']
        finally:
            _cleanup_chat_client(saved)


class TestVoiceMessagesEndpointBudget:
    """Test /v2/voice-messages daily budget enforcement."""

    def test_voice_messages_budget_exhausted_429(self):
        """Exhausted budget on /v2/voice-messages should return 429."""
        import io

        client, module, saved = _make_chat_client()
        try:
            with patch.object(module, 'retrieve_file_paths', return_value=['/tmp/test_vm.wav']):
                with patch.object(module, 'decode_files_to_wav', return_value=['/tmp/test_vm_decoded.wav']):
                    with patch.object(module, 'read_wav_duration_ms', return_value=60_000):
                        with patch.object(module, 'try_consume_budget', return_value=(False, 7200000, 0)):
                            resp = client.post(
                                '/v2/voice-messages',
                                files=[('files', ('test.wav', io.BytesIO(b'\x00' * 100), 'audio/wav'))],
                            )
                            assert resp.status_code == 429
                            assert 'budget exhausted' in resp.json()['detail']
        finally:
            _cleanup_chat_client(saved)


class TestWsBudgetAndSessionCap:
    """Test WS budget gate and actual duration recording."""

    def test_ws_budget_exhausted_rejects_at_connect(self):
        """WS should close with 1008 if daily budget is exhausted at connect."""
        client, module, saved = _make_chat_client()
        try:
            with patch.object(module, 'check_budget', return_value=(False, 7200000, 0)):
                with pytest.raises(Exception):
                    with client.websocket_connect('/v2/voice-message/transcribe-stream') as ws:
                        ws.receive_json()
        finally:
            _cleanup_chat_client(saved)


class TestOctetStreamBodySizeGuard:
    """Test that octet-stream rejects oversized payloads before buffering."""

    @patch('utils.chat.transcribe_pcm_bytes')
    def test_oversized_body_rejected_413(self, mock_transcribe):
        """Body exceeding _MAX_PCM_BODY_BYTES should be rejected with 413."""
        client, module, saved = _make_chat_client()
        try:
            with patch.object(module, '_MAX_PCM_BODY_BYTES', 1000):
                resp = client.post(
                    '/v2/voice-message/transcribe',
                    content=b'\x00' * 1500,
                    headers={'Content-Type': 'application/octet-stream'},
                )
                assert resp.status_code == 413
                mock_transcribe.assert_not_called()
        finally:
            _cleanup_chat_client(saved)
