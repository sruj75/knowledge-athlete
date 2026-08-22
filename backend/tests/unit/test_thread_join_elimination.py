"""Tests for Phase 3: Thread+join elimination (issue #6369).

Verifies that production code no longer uses Thread+join patterns
where ThreadPoolExecutor or asyncio.gather can be used instead.
"""

import ast
import importlib
import importlib.util
import os
import re
import sys
import tempfile
import textwrap
import types
from pathlib import Path

import pytest

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def _read_source(filepath: str) -> str:
    return Path(filepath).read_text(encoding='utf-8')


def _load_lint_module():
    """Load the lint_async_blockers module without executing __main__ block."""
    lint_path = os.path.join(BACKEND_DIR, 'scripts', 'lint_async_blockers.py')
    spec = importlib.util.spec_from_file_location('lint_async_blockers', lint_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _count_thread_join_patterns(filepath: str) -> list:
    """Find Thread+join patterns: list-comp joins and direct .join() on thread variables."""
    source = _read_source(filepath)

    patterns = []
    # Match list-comprehension join patterns like: [t.join() for t in threads]
    patterns.extend(re.findall(r'\[t\.join\(\)\s+for\s+t\s+in\s+\w+\]', source))
    # Match direct thread.join() calls (e.g. thread.join(), t.join())
    # but exclude string.join() and os.path.join() via context check
    for match in re.finditer(r'(\w+)\.join\(\)', source):
        var_name = match.group(1)
        if var_name in ('thread', 't', 'thr') or var_name.startswith('thread'):
            patterns.append(match.group(0))

    return patterns


class TestNoThreadJoinInMigratedFiles:
    """Phase 3 target files should not use Thread+join patterns."""

    def test_process_conversation_no_thread_join(self):
        filepath = os.path.join(BACKEND_DIR, 'utils', 'conversations', 'process_conversation.py')
        patterns = _count_thread_join_patterns(filepath)
        assert patterns == [], f"Thread+join still in process_conversation.py: {patterns}"

    def test_sync_no_thread_join(self):
        filepath = os.path.join(BACKEND_DIR, 'routers', 'sync.py')
        patterns = _count_thread_join_patterns(filepath)
        assert patterns == [], f"Thread+join still in sync.py: {patterns}"


class TestThreadPoolExecutorUsed:
    """Verify retained migrated files use shared executors or asyncio.gather."""

    def test_sync_uses_shared_executor_or_gather(self):
        filepath = os.path.join(BACKEND_DIR, 'routers', 'sync.py')
        source = _read_source(filepath)
        assert 'critical_executor' in source or 'storage_executor' in source or 'asyncio.gather' in source


class TestAsyncSTTVariants:
    """Phase 4: verify async STT variants exist."""

    def test_async_vad_exists(self):
        filepath = os.path.join(BACKEND_DIR, 'utils', 'stt', 'vad.py')
        source = _read_source(filepath)
        assert 'async def async_vad_is_empty(' in source

    def test_stt_async_uses_httpx_client(self):
        """Async STT variants should use shared httpx client, not create per-call clients."""
        for filename in ['vad.py']:
            filepath = os.path.join(BACKEND_DIR, 'utils', 'stt', filename)
            source = _read_source(filepath)
            assert 'get_stt_client' in source, f"{filename} should use shared get_stt_client()"

    def test_stt_async_offloads_file_io(self):
        """Async STT variants should offload file reads via run_blocking."""
        for filename in ['vad.py']:
            filepath = os.path.join(BACKEND_DIR, 'utils', 'stt', filename)
            source = _read_source(filepath)
            assert 'run_blocking(storage_executor' in source, f"{filename} should offload file I/O via storage_executor"


@pytest.mark.slow
class TestAsyncSTTBehavior:
    """Runtime behavior tests for async STT variants."""

    @pytest.mark.asyncio
    async def test_async_vad_local_fallback(self, monkeypatch):
        """When hosted VAD URL is unset, async_vad_is_empty should fall back to local VAD."""
        from unittest.mock import patch

        ort_mod = types.ModuleType('onnxruntime')

        class SessionOptions:
            pass

        class InferenceSession:
            pass

        class ExecutionMode:
            ORT_SEQUENTIAL = object()

        ort_mod.SessionOptions = SessionOptions
        ort_mod.InferenceSession = InferenceSession
        ort_mod.ExecutionMode = ExecutionMode
        pydub_mod = types.ModuleType('pydub')
        pydub_mod.AudioSegment = type('AudioSegment', (), {})
        monkeypatch.setitem(sys.modules, 'onnxruntime', ort_mod)
        monkeypatch.setitem(sys.modules, 'pydub', pydub_mod)
        monkeypatch.delitem(sys.modules, 'utils.stt.vad', raising=False)

        with patch.dict(os.environ, {}, clear=False):
            # Ensure HOSTED_VAD_API_URL is not set
            os.environ.pop('HOSTED_VAD_API_URL', None)
            mod = importlib.import_module('utils.stt.vad')
            with patch.object(mod, '_run_file_vad', return_value=[]) as mock_local:
                result = await mod.async_vad_is_empty('/tmp/nonexistent.wav')
                mock_local.assert_called_once_with('/tmp/nonexistent.wav')
                assert result is True  # empty segments = True


class TestLintScript:
    """Phase 6: verify lint script exists and is functional."""

    def test_lint_script_exists(self):
        filepath = os.path.join(BACKEND_DIR, 'scripts', 'lint_async_blockers.py')
        assert os.path.exists(filepath)

    def test_lint_script_parses(self):
        filepath = os.path.join(BACKEND_DIR, 'scripts', 'lint_async_blockers.py')
        source = _read_source(filepath)
        # Should parse without errors
        ast.parse(source)


class TestLintScriptDetection:
    """Verify the lint script detects actual violations and clears clean code."""

    @staticmethod
    def _scan_source(code: str) -> list:
        """Write code to a temp file and run scan_file on it."""
        mod = _load_lint_module()
        with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
            f.write(textwrap.dedent(code))
            tmp_path = Path(f.name)
        try:
            return mod.scan_file(tmp_path)
        finally:
            tmp_path.unlink(missing_ok=True)

    def test_detects_requests_get_in_async(self):
        """requests.get inside an async function must be a violation."""
        code = """\
            import requests

            async def fetch(url):
                return requests.get(url)
        """
        violations = self._scan_source(code)
        assert len(violations) >= 1, f"Expected at least 1 violation, got: {violations}"
        assert any('requests' in msg for _, msg in violations), f"Expected requests violation, got: {violations}"

    def test_detects_time_sleep_in_async(self):
        """time.sleep() inside an async function must be a violation."""
        code = """\
            import time

            async def pause():
                time.sleep(1)
        """
        violations = self._scan_source(code)
        assert len(violations) >= 1, f"Expected at least 1 violation, got: {violations}"
        assert any('time.sleep' in msg for _, msg in violations), f"Expected time.sleep violation, got: {violations}"

    def test_detects_thread_start_in_async(self):
        """Thread().start() inside an async function must be a violation."""
        code = """\
            from threading import Thread

            async def spawn():
                Thread(target=lambda: None).start()
        """
        violations = self._scan_source(code)
        assert len(violations) >= 1, f"Expected at least 1 violation, got: {violations}"
        assert any('Thread' in msg for _, msg in violations), f"Expected Thread violation, got: {violations}"

    def test_clean_code_has_no_violations(self):
        """Code with no blocking patterns must produce zero violations."""
        code = """\
            import asyncio
            import httpx

            async def fetch(url: str) -> dict:
                async with httpx.AsyncClient() as client:
                    response = await client.get(url)
                return response.json()

            async def pause():
                await asyncio.sleep(1)

            def sync_helper():
                import time
                time.sleep(0.1)  # OK — not in async function
        """
        violations = self._scan_source(code)
        assert violations == [], f"Expected no violations for clean code, got: {violations}"

    def test_sync_function_with_blocking_is_clean(self):
        """Blocking calls in ordinary (non-async) functions must not be flagged."""
        code = """\
            import requests

            def sync_fetch(url):
                return requests.get(url)
        """
        violations = self._scan_source(code)
        assert violations == [], f"Blocking in sync function should not be flagged, got: {violations}"
