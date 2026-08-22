"""Regression tests for retained async and HTTP-client migration boundaries."""

import os
import re

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _read_source(rel_path: str) -> str:
    """Read source file directly to avoid import-time side effects (Firestore init, etc.)."""
    with open(os.path.join(BACKEND_DIR, rel_path)) as f:
        return f.read()


# Round 2: requests → httpx migrations in 6 more files


class TestVadHttpxMigration:
    """Verify VAD sync functions use requests with proper timeout (sync path retained for onnx compat)."""

    def test_vad_uses_requests_with_timeout(self):
        """VAD sync path uses requests.post with explicit timeout (not migrated to httpx yet)."""
        src = _read_source('utils/stt/vad.py')
        assert 'import requests' in src
        assert 'requests.post(' in src

    def test_vad_hosted_has_timeout(self):
        """Hosted VAD call must have explicit timeout to prevent hanging."""
        src = _read_source('utils/stt/vad.py')
        assert 'timeout=300' in src

    def test_vad_no_threading_thread(self):
        """No bare threading.Thread usage in VAD module."""
        src = _read_source('utils/stt/vad.py')
        assert 'threading.Thread(' not in src


class TestLocationHttpxMigration:
    """Verify location geocoding uses httpx, not requests."""

    def test_location_uses_httpx(self):
        src = _read_source('utils/conversations/location.py')
        assert 'import httpx' in src
        assert 'import requests' not in src

    def test_location_uses_httpx_get(self):
        src = _read_source('utils/conversations/location.py')
        assert 'httpx.get(' in src


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
    """Verify utils/chat.py uses storage_executor for file cleanup."""

    def test_no_threading_thread(self):
        src = _read_source('utils/chat.py')
        assert 'threading.Thread' not in src

    def test_uses_storage_executor(self):
        src = _read_source('utils/chat.py')
        storage_src = _read_source('utils/other/storage.py')
        assert 'schedule_syncing_temporal_file_deletion' in src
        assert 'time.sleep(480)' not in src
        assert 'DeferredDeleter' in storage_src
        assert 'def schedule_syncing_temporal_file_deletion' in storage_src


class TestStorageExecutorMigration:
    """Verify storage uses storage_executor, not ad-hoc ThreadPoolExecutor."""

    def test_no_ad_hoc_thread_pool_executor(self):
        src = _read_source('utils/other/storage.py')
        assert 'ThreadPoolExecutor(' not in src

    def test_uses_storage_executor(self):
        src = _read_source('utils/other/storage.py')
        assert 'storage_executor' in src


class TestNoRequestsInProductionCode:
    """Global check: zero import requests in non-test, non-script production code."""

    def test_no_import_requests_in_routers(self):
        routers_dir = os.path.join(BACKEND_DIR, 'routers')
        for fname in os.listdir(routers_dir):
            if fname.endswith('.py'):
                src = _read_source(f'routers/{fname}')
                assert 'import requests' not in src, f'routers/{fname} still imports requests'

    def test_no_import_requests_in_utils(self):
        # vad.py retains requests for sync onnx-compatible path (not yet migrated)
        excluded = {'utils/stt/vad.py'}
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
