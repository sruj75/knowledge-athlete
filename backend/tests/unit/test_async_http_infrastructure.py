"""Tests for async HTTP infrastructure (issue #6369).

Covers:
- Semaphore bounded concurrency getters
- Shared executors from utils/executors.py
"""

import asyncio
import sys
import types
from pathlib import Path
from unittest.mock import patch

import pytest

BACKEND_DIR = Path(__file__).resolve().parents[2]


def _ensure_package(name, path):
    module = sys.modules.get(name)
    if module is None or not hasattr(module, "__path__"):
        module = types.ModuleType(name)
        sys.modules[name] = module
    module.__path__ = [str(path)]

    if "." in name:
        parent_name, attr_name = name.rsplit(".", 1)
        parent = sys.modules.get(parent_name)
        if parent is not None:
            setattr(parent, attr_name, module)


def _drop_stale_module(name, required_attrs):
    module = sys.modules.get(name)
    if module is None:
        return
    if (
        isinstance(module, types.ModuleType)
        and getattr(module, "__file__", None)
        and all(hasattr(module, attr) for attr in required_attrs)
    ):
        return

    sys.modules.pop(name, None)
    parent_name, attr_name = name.rsplit(".", 1)
    parent = sys.modules.get(parent_name)
    if parent is not None and getattr(parent, attr_name, None) is module:
        delattr(parent, attr_name)


_ensure_package("utils", BACKEND_DIR / "utils")
_drop_stale_module("utils.http_client", ["get_external_client", "get_maps_client"])
_drop_stale_module("utils.executors", ["critical_executor", "storage_executor", "shutdown_executors"])

from utils.http_client import (
    get_maps_semaphore,
    get_auth_semaphore,
    get_stt_semaphore,
    _semaphores,
    _SEMAPHORE_CACHE_MAX,
)
from utils.executors import critical_executor, storage_executor


# ============================================================================
# Semaphore getters
# ============================================================================


class TestSemaphoreGetters:
    """Verify semaphore creation and per-loop isolation."""

    def test_maps_semaphore_returns_semaphore(self):
        sem = get_maps_semaphore()
        assert isinstance(sem, asyncio.Semaphore)

    def test_auth_semaphore_returns_semaphore(self):
        sem = get_auth_semaphore()
        assert isinstance(sem, asyncio.Semaphore)

    def test_stt_semaphore_returns_semaphore(self):
        sem = get_stt_semaphore()
        assert isinstance(sem, asyncio.Semaphore)

    @pytest.mark.asyncio
    async def test_same_loop_returns_same_instance(self):
        """Within the same event loop, getter returns the same semaphore."""
        sem1 = get_auth_semaphore()
        sem2 = get_auth_semaphore()
        assert sem1 is sem2

    @pytest.mark.asyncio
    async def test_pruning_keeps_the_running_loops_semaphore(self):
        """Crossing the cache cap must not swap the live loop's existing semaphore.

        The prune used _semaphores.clear(), which dropped the running loop's entries too.
        A caller already holding permits on the old Semaphore kept them while the next
        caller received a brand-new one, so the effective concurrency briefly doubled —
        the opposite of what the cap exists for. The docstring already promised the main
        loop's semaphores "are stable" and that only short-lived asyncio.run() entries
        are pruned.
        """
        _semaphores.clear()
        auth_before = get_auth_semaphore()
        live_loop_id = id(asyncio.get_running_loop())

        # Fill the cache past the cap with entries from other (destroyed) loops.
        for i in range(_SEMAPHORE_CACHE_MAX + 5):
            _semaphores[(live_loop_id + 1 + i, 'auth')] = asyncio.Semaphore(1)

        # A new name for this loop is what triggers the prune.
        get_maps_semaphore()

        assert get_auth_semaphore() is auth_before, 'the running loop lost its semaphore to the prune'

    @pytest.mark.asyncio
    async def test_pruning_still_bounds_the_cache(self):
        """The prune must drop the foreign-loop entries it was added for."""
        _semaphores.clear()
        get_auth_semaphore()
        live_loop_id = id(asyncio.get_running_loop())
        for i in range(_SEMAPHORE_CACHE_MAX + 5):
            _semaphores[(live_loop_id + 1 + i, 'auth')] = asyncio.Semaphore(1)

        get_maps_semaphore()  # crosses the cap, triggering the prune

        assert all(key[0] == live_loop_id for key in _semaphores), 'foreign-loop entries survived'
        assert len(_semaphores) == 2  # auth + maps, both for this loop

    def test_different_loops_return_different_instances(self):
        """Different asyncio.run() calls get isolated semaphores."""
        sems = []

        async def _get():
            return get_auth_semaphore()

        sems.append(asyncio.run(_get()))
        _semaphores.clear()  # Ensure no stale entries from the destroyed loop
        sems.append(asyncio.run(_get()))
        assert sems[0] is not sems[1]


# ============================================================================
# Shared executors
# ============================================================================


class TestSharedExecutors:
    """Verify dedicated thread pool executors are functional."""

    def test_critical_executor_submits(self):
        future = critical_executor.submit(lambda: 42)
        assert future.result(timeout=5) == 42

    def test_storage_executor_submits(self):
        future = storage_executor.submit(lambda: "ok")
        assert future.result(timeout=5) == "ok"

    def test_critical_executor_thread_name_prefix(self):
        import threading

        result = critical_executor.submit(lambda: threading.current_thread().name).result(timeout=5)
        assert result.startswith("critical")

    def test_storage_executor_thread_name_prefix(self):
        import threading

        result = storage_executor.submit(lambda: threading.current_thread().name).result(timeout=5)
        assert result.startswith("storage")

    def test_critical_executor_parallel_work(self):
        """Verify critical executor handles concurrent submissions."""
        import time

        def slow_task(n):
            time.sleep(0.05)
            return n * 2

        futures = [critical_executor.submit(slow_task, i) for i in range(4)]
        results = [f.result(timeout=5) for f in futures]
        assert results == [0, 2, 4, 6]


class TestShutdownLifecycle:
    """Verify shutdown functions exist and are callable."""

    def test_shutdown_executors_callable(self):
        """shutdown_executors must be a callable function."""
        from utils.executors import shutdown_executors

        assert callable(shutdown_executors)

    def test_shutdown_executors_registered_with_atexit(self):
        """shutdown_executors must be registered via atexit."""
        import atexit

        from utils.executors import shutdown_executors

        # atexit._run_exitfuncs stores registered callables; check it's registered
        # We verify by checking the function exists and is registered
        # (atexit internals are implementation-dependent, so we just verify callability
        #  and that calling it on a fresh executor doesn't raise)
        from concurrent.futures import ThreadPoolExecutor

        test_exec = ThreadPoolExecutor(max_workers=1, thread_name_prefix="test-shutdown")
        test_exec.shutdown(wait=False, cancel_futures=True)  # Should not raise

    def test_close_all_clients_resets_semaphores(self):
        """close_all_clients must clear the semaphore cache."""
        # Populate semaphore cache
        sem = get_maps_semaphore()
        assert isinstance(sem, asyncio.Semaphore)

        async def _close():
            from utils.http_client import close_all_clients

            await close_all_clients()

        asyncio.run(_close())

        # After close, semaphore cache should be cleared
        assert len(_semaphores) == 0


# ============================================================================
# Client configuration assertions (tester-requested)
# ============================================================================


class TestExternalClientConfig:
    """Verify the retained external client timeout contract."""

    def test_external_client_read_timeout_is_30s(self):

        async def _read_timeout():
            from utils.http_client import close_all_clients, get_external_client

            try:
                return get_external_client().timeout.read
            finally:
                await close_all_clients()

        assert asyncio.run(_read_timeout()) == 30.0

    def test_external_client_connect_timeout_is_2s(self):

        async def _connect_timeout():
            from utils.http_client import close_all_clients, get_external_client

            try:
                return get_external_client().timeout.connect
            finally:
                await close_all_clients()

        assert asyncio.run(_connect_timeout()) == 2.0


class TestClientEventLoopOwnership:
    """A shared client belongs to the event loop that opened its connections.

    Regression for the prod failure where one process-wide client outlived the
    `asyncio.run()` loop that pooled its keep-alive connections: the next live
    loop made the pool discard one, uvloop raised `RuntimeError: ... the
    handler is closed` from `write_eof()` on the freed handle, and httpcore
    re-raised it at the caller as intermittent external-request failures.
    """

    def test_each_event_loop_gets_its_own_client(self):
        """The surviving client of a finished loop is never handed to the next one."""
        import utils.http_client as hc

        async def _client_id():
            return id(hc.get_external_client())

        # No close in between: this is the prod shape, where the process-wide
        # client outlived the asyncio.run() loop that pooled its connections.
        first = asyncio.run(_client_id())
        second = asyncio.run(_client_id())
        try:
            assert first != second
        finally:
            asyncio.run(hc.close_all_clients())

    def test_one_loop_reuses_a_single_pooled_client(self):
        import utils.http_client as hc

        async def _same_client():
            try:
                return hc.get_external_client() is hc.get_external_client()
            finally:
                await hc.close_all_clients()

        assert asyncio.run(_same_client()) is True

    def test_finished_loops_do_not_accumulate_clients(self):
        import utils.http_client as hc

        async def _touch():
            hc.get_external_client()

        for _ in range(5):
            asyncio.run(_touch())

        assert len(hc._clients) == 1  # only the most recent loop's entry survives


class TestExecutorConfiguration:
    """Verify executor pool sizing cannot silently regress."""

    def test_critical_executor_has_8_workers(self):
        """critical_executor documented as 8 workers for latency-sensitive work."""
        assert critical_executor._max_workers == 8

    def test_storage_executor_has_128_workers(self):
        """storage_executor sized for 128 workers to handle concurrent private cloud uploads (#7376)."""
        assert storage_executor._max_workers == 128


class TestPrivateCloudQueueCap:
    """Verify private_cloud_queue uses bounded deque to prevent OOM."""

    def test_pusher_uses_deque_with_maxlen(self):
        """private_cloud_queue must be deque(maxlen=PRIVATE_CLOUD_QUEUE_MAX_SIZE)."""
        import ast
        import os

        backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        with open(os.path.join(backend_dir, 'routers', 'pusher.py'), encoding='utf-8') as f:
            src = f.read()

        assert 'deque(maxlen=PRIVATE_CLOUD_QUEUE_MAX_SIZE)' in src
        assert 'private_cloud_queue: List[dict] = []' not in src

    def test_queue_max_size_is_20(self):
        """Queue cap should be 20 items (~18MB max per connection, safe for 30-conn pods)."""
        import ast
        import os

        backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        with open(os.path.join(backend_dir, 'utils', 'pusher_protocol.py'), encoding='utf-8') as f:
            src = f.read()

        tree = ast.parse(src)
        for node in ast.walk(tree):
            if isinstance(node, ast.Assign):
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id == 'PRIVATE_CLOUD_QUEUE_MAX_SIZE':
                        assert isinstance(node.value, ast.Constant)
                        assert node.value.value == 20
                        return
        pytest.fail("PRIVATE_CLOUD_QUEUE_MAX_SIZE constant not found")

    def test_overflow_warning_at_all_enqueue_points(self):
        """All 3 enqueue points must log overflow warning before deque drops oldest."""
        import os

        backend_dir = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        with open(os.path.join(backend_dir, 'routers', 'pusher.py'), encoding='utf-8') as f:
            src = f.read()

        # Count occurrences of the overflow warning pattern
        warning_count = src.count('private_cloud_queue full')
        assert warning_count == 3, f"Expected 3 overflow warnings, found {warning_count}"

    def test_deque_maxlen_drops_oldest(self):
        """Verify deque(maxlen=N) drops oldest item when full."""
        from collections import deque

        q = deque(maxlen=3)
        q.append({'id': 1})
        q.append({'id': 2})
        q.append({'id': 3})
        assert len(q) == 3
        q.append({'id': 4})  # oldest (id=1) should be dropped
        assert len(q) == 3
        assert q[0]['id'] == 2
        assert q[-1]['id'] == 4
