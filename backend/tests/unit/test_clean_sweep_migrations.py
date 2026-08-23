"""Regression tests for retained async and HTTP-client migration boundaries."""

import os
import re
from pathlib import Path

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _read_source(rel_path: str) -> str:
    """Read source file directly to avoid import-time side effects (Firestore init, etc.)."""
    with open(os.path.join(BACKEND_DIR, rel_path)) as f:
        return f.read()


# Round 2: requests → httpx migrations in 6 more files


class TestLocalVadBoundary:
    """Verify the retained VAD cannot restore the hosted HTTP boundary."""

    def test_vad_has_no_hosted_http_client(self):
        src = _read_source('utils/stt/vad.py')
        assert 'import requests' not in src
        assert 'requests.post(' not in src
        assert 'httpx.' not in src

    def test_vad_no_threading_thread(self):
        """No bare threading.Thread usage in VAD module."""
        src = _read_source('utils/stt/vad.py')
        assert 'threading.Thread(' not in src


# Round 3: threading.Thread → executor and more requests → httpx


class TestChatExecutorMigration:
    """Verify the retained chat router uses the shared rate-limit executor."""

    def test_no_threading_thread(self):
        src = _read_source('routers/chat.py')
        assert 'threading.Thread' not in src

    def test_uses_critical_executor_for_rate_limit(self):
        src = _read_source('routers/chat.py')
        assert 'critical_executor' in src


class TestChatUtilsExecutorMigration:
    """Verify utils/chat.py does not create unmanaged worker threads."""

    def test_no_threading_thread(self):
        src = _read_source('utils/chat.py')
        assert 'threading.Thread' not in src


class TestHostedSearchProviderRetirement:
    """Static tripwire for the deleted hosted search/vector boundary."""

    def test_production_has_no_hosted_search_provider_boundary(self):
        backend_path = Path(BACKEND_DIR)
        assert not (backend_path / 'database' / 'vector_db.py').exists()
        assert not (backend_path / 'typesense' / 'conversations.schema').exists()

        forbidden = ('database.vector_db', 'database import vector_db', 'pinecone', 'typesense')
        for root_name in ('database', 'models', 'routers', 'services', 'utils'):
            for path in (backend_path / root_name).rglob('*.py'):
                source = path.read_text(encoding='utf-8').lower()
                matches = [token for token in forbidden if token in source]
                assert not matches, f'{path.relative_to(backend_path)} restores hosted search/vector residue: {matches}'


class TestNoRequestsInProductionCode:
    """Global check: zero import requests in non-test, non-script production code."""

    def test_no_import_requests_in_routers(self):
        routers_dir = os.path.join(BACKEND_DIR, 'routers')
        for fname in os.listdir(routers_dir):
            if fname.endswith('.py'):
                src = _read_source(f'routers/{fname}')
                assert 'import requests' not in src, f'routers/{fname} still imports requests'

    def test_no_import_requests_in_utils(self):
        excluded: set[str] = set()
        for root, dirs, files in os.walk(os.path.join(BACKEND_DIR, 'utils')):
            for fname in files:
                if fname.endswith('.py'):
                    rel = os.path.relpath(os.path.join(root, fname), BACKEND_DIR)
                    if rel in excluded:
                        continue
                    src = _read_source(rel)
                    bare_import = re.search(r'^\s*import requests\b', src, re.MULTILINE)
                    from_import = re.search(r'^\s*from requests\b', src, re.MULTILINE)
                    assert bare_import is None and from_import is None, f'{rel} still imports requests'

    def test_no_threading_thread_start_in_routers(self):
        # users.py retains threading.Thread for background wipe (long-running, not executor-suitable)
        excluded = {'users.py'}
        routers_dir = os.path.join(BACKEND_DIR, 'routers')
        for fname in os.listdir(routers_dir):
            if fname.endswith('.py') and fname not in excluded:
                src = _read_source(f'routers/{fname}')
                assert 'threading.Thread(' not in src, f'routers/{fname} still uses threading.Thread'
