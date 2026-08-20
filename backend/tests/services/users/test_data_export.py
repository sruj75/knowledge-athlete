import importlib.abc
import importlib.machinery
import json
import sys
import types
from datetime import datetime, timezone
from unittest.mock import MagicMock


class _AutoMockModule(types.ModuleType):
    __path__ = []

    def __getattr__(self, name):
        if name.startswith('__') and name.endswith('__'):
            raise AttributeError(name)
        mock = MagicMock()
        setattr(self, name, mock)
        return mock


_STUB_PREFIXES = (
    'database',
    'firebase_admin',
    'google.cloud',
    'google.api_core',
    'pinecone',
    'typesense',
    'utils',
)


def _should_stub(name: str) -> bool:
    return any(name == prefix or name.startswith(prefix + '.') for prefix in _STUB_PREFIXES)


class _StubFinder(importlib.abc.MetaPathFinder, importlib.abc.Loader):
    def __init__(self):
        self._created: set[str] = set()

    def find_spec(self, name, path=None, target=None):
        if _should_stub(name):
            return importlib.machinery.ModuleSpec(name, self, is_package=True)
        return None

    def create_module(self, spec):
        self._created.add(spec.name)
        return _AutoMockModule(spec.name)

    def exec_module(self, module):
        pass


_finder = _StubFinder()
sys.meta_path.insert(0, _finder)
try:
    from services.users import data_export  # noqa: E402
finally:
    # Remove the meta-path finder and clear *only* the modules that the
    # stub finder actually created. Broadly deleting every module matching
    # _STUB_PREFIXES (database, utils, …) would also evict real project
    # modules imported by other tests collected in the same pytest process.
    sys.meta_path.remove(_finder)
    for _name in list(_finder._created):
        sys.modules.pop(_name, None)
    # The imported service module itself was loaded against the MagicMock
    # stubs (its globals hold MagicMock objects for database, utils, etc.).
    # Pop it — along with its parent packages — so a later test that imports
    # the real service reloads it with production dependencies instead of
    # reusing this mock-backed copy.
    for _svc_name in ('services.users.data_export', 'services.users', 'services'):
        sys.modules.pop(_svc_name, None)


def test_iter_user_data_export_streams_all_top_level_sections(monkeypatch):
    now = datetime(2026, 1, 2, 3, 4, 5, tzinfo=timezone.utc)
    monkeypatch.setattr(
        data_export,
        'get_user_profile',
        MagicMock(return_value={'name': 'Legacy Firestore Name', 'created_at': now}),
    )
    monkeypatch.setattr(data_export, 'get_people', MagicMock(return_value=[{'id': 'person1'}]))
    monkeypatch.setattr(
        data_export.conversations_db,
        'iter_all_conversations',
        MagicMock(return_value=iter([{'id': 'conv1', 'is_locked': True}, {'id': 'conv2'}])),
    )
    monkeypatch.setattr(
        data_export.chat_db, 'iter_all_messages', MagicMock(return_value=iter([{'id': 'msg1', 'created_at': now}]))
    )

    body = ''.join(data_export.iter_user_data_export('uid1'))
    payload = json.loads(body)

    assert payload == {
        'profile': {'created_at': '2026-01-02T03:04:05+00:00'},
        'conversations': [{'id': 'conv1', 'is_locked': True}, {'id': 'conv2'}],
        'people': [{'id': 'person1'}],
        'chat_messages': [{'id': 'msg1', 'created_at': '2026-01-02T03:04:05+00:00'}],
    }
    data_export.conversations_db.iter_all_conversations.assert_called_once_with('uid1', include_discarded=True)
    data_export.chat_db.iter_all_messages.assert_called_once_with('uid1')


def test_iter_user_data_export_uses_empty_profile_object(monkeypatch):
    monkeypatch.setattr(data_export, 'get_user_profile', MagicMock(return_value=None))
    monkeypatch.setattr(data_export, 'get_people', MagicMock(return_value=[]))
    monkeypatch.setattr(data_export.conversations_db, 'iter_all_conversations', MagicMock(return_value=iter([])))
    monkeypatch.setattr(data_export.chat_db, 'iter_all_messages', MagicMock(return_value=iter([])))

    payload = json.loads(''.join(data_export.iter_user_data_export('uid1')))

    assert payload['profile'] == {}


def test_iter_user_data_export_yields_before_heavy_reads(monkeypatch):
    get_profile = MagicMock(return_value={})
    monkeypatch.setattr(data_export, 'get_user_profile', get_profile)
    monkeypatch.setattr(data_export, 'get_people', MagicMock(return_value=[]))
    monkeypatch.setattr(data_export.conversations_db, 'iter_all_conversations', MagicMock(return_value=iter([])))
    monkeypatch.setattr(data_export.chat_db, 'iter_all_messages', MagicMock(return_value=iter([])))

    chunks = data_export.iter_user_data_export('uid1')

    assert next(chunks) == '{\n'
    get_profile.assert_not_called()
