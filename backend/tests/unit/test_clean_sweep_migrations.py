"""Regression tests for retained async and HTTP-client migration boundaries."""

import os
import re

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _read_source(rel_path: str) -> str:
    """Read source file directly to avoid import-time side effects (Firestore init, etc.)."""
    with open(os.path.join(BACKEND_DIR, rel_path)) as f:
        return f.read()


class TestHumeHttpxMigration:
    """Verify Hume client uses httpx, not requests."""

    def test_hume_uses_httpx_not_requests(self):
        """HumeClient should import httpx, not requests."""
        src = _read_source('utils/other/hume.py')
        assert 'import httpx' in src
        assert 'import requests' not in src

    def test_hume_uses_follow_redirects(self):
        """httpx.post call must include follow_redirects=True (requests follows by default)."""
        src = _read_source('utils/other/hume.py')
        assert 'follow_redirects=True' in src

    def test_hume_catches_request_error(self):
        """Exception handler should catch httpx.RequestError (closest to requests.RequestException)."""
        src = _read_source('utils/other/hume.py')
        assert 'httpx.RequestError' in src

    def test_hume_catches_timeout(self):
        """Exception handler should catch httpx.TimeoutException."""
        src = _read_source('utils/other/hume.py')
        assert 'httpx.TimeoutException' in src

    def test_hume_catches_too_many_redirects(self):
        """Exception handler should catch httpx.TooManyRedirects."""
        src = _read_source('utils/other/hume.py')
        assert 'httpx.TooManyRedirects' in src


# Round 2: requests → httpx migrations in 6 more files


class TestSpeakerEmbeddingHttpxMigration:
    """Verify speaker_embedding sync functions use httpx, not requests."""

    def test_speaker_embedding_uses_httpx(self):
        src = _read_source('utils/stt/speaker_embedding.py')
        assert 'import httpx' in src
        assert 'import requests' not in src

    def test_extract_embedding_uses_httpx_post(self):
        src = _read_source('utils/stt/speaker_embedding.py')
        assert 'httpx.post(' in src

    def test_extract_embedding_has_float_timeout(self):
        src = _read_source('utils/stt/speaker_embedding.py')
        assert 'timeout=300.0' in src


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


class TestSpeechProfileHttpxMigration:
    """Verify speech_profile sync functions use httpx, not requests."""

    def test_speech_profile_uses_httpx(self):
        src = _read_source('utils/stt/speech_profile.py')
        assert 'import httpx' in src
        assert 'import requests' not in src

    def test_speech_profile_uses_httpx_post(self):
        src = _read_source('utils/stt/speech_profile.py')
        assert 'httpx.post(' in src


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


class TestActionItemsExecutorMigration:
    """Verify retained action-item routes do not spawn bare threads."""

    def test_no_threading_thread(self):
        src = _read_source('routers/action_items.py')
        assert 'threading.Thread' not in src


class TestChatExecutorMigration:
    """Verify chat router uses llm_executor for goal extraction, critical_executor for rate limit."""

    def test_no_threading_thread(self):
        src = _read_source('routers/chat.py')
        assert 'threading.Thread' not in src

    def test_uses_llm_executor_for_goals(self):
        src = _read_source('routers/chat.py')
        assert 'llm_executor.submit(' in src

    def test_uses_critical_executor_for_rate_limit(self):
        src = _read_source('routers/chat.py')
        assert 'critical_executor' in src


class TestWrappedExecutorMigration:
    """Verify wrapped router uses llm_executor."""

    def test_no_threading_thread(self):
        src = _read_source('routers/wrapped.py')
        assert 'threading.Thread' not in src

    def test_uses_llm_executor(self):
        src = _read_source('routers/wrapped.py')
        assert 'llm_executor' in src


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


class TestPostprocessExecutorMigration:
    """Verify postprocess_conversation uses storage_executor for audio cleanup."""

    def test_no_threading_thread(self):
        src = _read_source('utils/conversations/postprocess_conversation.py')
        assert 'threading.Thread' not in src

    def test_uses_storage_executor(self):
        src = _read_source('utils/conversations/postprocess_conversation.py')
        assert 'storage_executor.submit(' in src


class TestNotificationsExecutorMigration:
    """Verify notifications uses postprocess_executor for batch cron work (#7387), not threading.Thread."""

    def test_no_threading_thread(self):
        src = _read_source('utils/other/notifications.py')
        assert 'threading.Thread' not in src

    def test_uses_postprocess_executor(self):
        """Batch notification work uses postprocess_executor for retained LLM and database work."""
        src = _read_source('utils/other/notifications.py')
        assert 'postprocess_executor' in src

    def test_does_not_use_storage_executor(self):
        """Batch notification work must not use storage_executor (wrong pool, #7387)."""
        src = _read_source('utils/other/notifications.py')
        assert 'storage_executor' not in src

    def test_does_not_use_critical_executor(self):
        """Batch cron work must not use critical_executor (would starve request-path)."""
        src = _read_source('utils/other/notifications.py')
        assert 'critical_executor' not in src


class TestStorageExecutorMigration:
    """Verify storage uses storage_executor, not ad-hoc ThreadPoolExecutor."""

    def test_no_ad_hoc_thread_pool_executor(self):
        src = _read_source('utils/other/storage.py')
        assert 'ThreadPoolExecutor(' not in src

    def test_uses_storage_executor(self):
        src = _read_source('utils/other/storage.py')
        assert 'storage_executor' in src


class TestPerplexityHttpxMigration:
    """Verify perplexity_tools uses httpx, not requests."""

    def test_uses_httpx(self):
        src = _read_source('utils/retrieval/tools/perplexity_tools.py')
        assert 'import httpx' in src
        assert 'import requests' not in src


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
