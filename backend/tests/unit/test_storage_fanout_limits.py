"""Tests for bounded fan-out concurrency limits in storage operations (#7387).

Verifies that storage_executor submissions are gated by semaphores to prevent
queue spikes from unbounded parallel chunk downloads.

Source-level tests (no heavy module imports) — checks code structure, not runtime.
Behavioral tests use a standalone sliding-window implementation to verify the pattern.
"""

import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED
import pytest


def _read_source(rel_path):
    base = os.path.join(os.path.dirname(__file__), '..', '..')
    with open(os.path.join(base, rel_path), encoding='utf-8') as f:
        return f.read()


class TestChunkDownloadSlidingWindow:
    """download_audio_chunks_and_merge must use a sliding window, not submit all at once."""

    def test_chunk_semaphore_exists_at_module_level(self):
        """Module must define _STORAGE_CHUNK_SEM."""
        src = _read_source('utils/other/storage.py')
        assert '_STORAGE_CHUNK_SEM' in src
        assert 'BoundedSemaphore' in src

    def test_chunk_window_size_defined(self):
        """Module must define _CHUNK_WINDOW_SIZE = 8."""
        src = _read_source('utils/other/storage.py')
        assert '_CHUNK_WINDOW_SIZE = 8' in src

    def test_global_chunk_semaphore_is_32(self):
        """Global chunk semaphore must be BoundedSemaphore(32)."""
        src = _read_source('utils/other/storage.py')
        assert 'BoundedSemaphore(32)' in src

    def test_sliding_window_uses_wait_first_completed(self):
        """download_audio_chunks_and_merge must use FIRST_COMPLETED wait for sliding window."""
        src = _read_source('utils/other/storage.py')
        assert 'FIRST_COMPLETED' in src
        func_start = src.index('def download_audio_chunks_and_merge')
        next_def = src.index('\ndef ', func_start + 1)
        func_body = src[func_start:next_def]
        assert 'FIRST_COMPLETED' in func_body

    def test_chunk_sem_acquired_before_submit(self):
        """Chunk semaphore must be acquired before storage_executor.submit, not inside the task."""
        src = _read_source('utils/other/storage.py')
        func_start = src.index('def download_audio_chunks_and_merge')
        next_def = src.index('\ndef ', func_start + 1)
        func_body = src[func_start:next_def]
        assert '_STORAGE_CHUNK_SEM.acquire()' in func_body

    def test_chunk_sem_released_in_done_callback(self):
        """Chunk semaphore must be released via done callback for exception safety."""
        src = _read_source('utils/other/storage.py')
        func_start = src.index('def download_audio_chunks_and_merge')
        next_def = src.index('\ndef ', func_start + 1)
        func_body = src[func_start:next_def]
        assert '_STORAGE_CHUNK_SEM.release()' in func_body
        assert 'add_done_callback' in func_body

    def test_no_unbounded_dict_comprehension_submit(self):
        """Old pattern of submitting all futures via dict comprehension must be gone."""
        src = _read_source('utils/other/storage.py')
        func_start = src.index('def download_audio_chunks_and_merge')
        next_def = src.index('\ndef ', func_start + 1)
        func_body = src[func_start:next_def]
        assert 'storage_executor.submit(download_single_chunk, ts): ts for ts' not in func_body
        assert '{storage_executor.submit' not in func_body

    def test_combined_job_stream(self):
        """Individual chunks and batch blobs must be treated as one job stream."""
        src = _read_source('utils/other/storage.py')
        func_start = src.index('def download_audio_chunks_and_merge')
        next_def = src.index('\ndef ', func_start + 1)
        func_body = src[func_start:next_def]
        assert "('individual'" in func_body or "('batch'" in func_body


@pytest.mark.slow
class TestSlidingWindowBehavior:
    """Behavioral tests verifying the sliding-window + semaphore pattern at runtime."""

    def test_sliding_window_caps_inflight(self):
        """Sliding window must never have more than WINDOW_SIZE futures in-flight."""
        WINDOW_SIZE = 4
        GLOBAL_SEM = threading.BoundedSemaphore(16)
        executor = ThreadPoolExecutor(max_workers=8, thread_name_prefix="test-sw")
        high_water = {'max': 0}
        active = {'count': 0}
        lock = threading.Lock()

        def tracked_work(idx):
            with lock:
                active['count'] += 1
                if active['count'] > high_water['max']:
                    high_water['max'] = active['count']
            time.sleep(0.02)
            with lock:
                active['count'] -= 1
            return idx

        jobs = list(range(20))
        results = []

        def submit_job(job):
            GLOBAL_SEM.acquire()
            try:
                f = executor.submit(tracked_work, job)
                f.add_done_callback(lambda _: GLOBAL_SEM.release())
                return f
            except Exception:
                GLOBAL_SEM.release()
                raise

        pending = {}
        job_iter = iter(jobs)
        for job in job_iter:
            f = submit_job(job)
            pending[f] = job
            if len(pending) >= WINDOW_SIZE:
                break

        while pending:
            done, _ = wait(pending.keys(), return_when=FIRST_COMPLETED)
            for future in done:
                results.append(future.result())
                del pending[future]
            for job in job_iter:
                f = submit_job(job)
                pending[f] = job
                if len(pending) >= WINDOW_SIZE:
                    break

        executor.shutdown(wait=True)
        assert high_water['max'] <= WINDOW_SIZE + 1, f"High water {high_water['max']} exceeds window {WINDOW_SIZE}"
        assert sorted(results) == list(range(20)), "All jobs must complete"

    def test_semaphore_released_on_exception(self):
        """Semaphore must not leak when submitted tasks raise exceptions."""
        SEM = threading.BoundedSemaphore(4)
        executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="test-exc")

        def failing_work(idx):
            if idx % 2 == 0:
                raise RuntimeError(f"fail-{idx}")
            return idx

        futures = []
        for i in range(8):
            SEM.acquire()
            try:
                f = executor.submit(failing_work, i)
                f.add_done_callback(lambda _: SEM.release())
                futures.append(f)
            except Exception:
                SEM.release()
                raise

        for f in futures:
            try:
                f.result()
            except RuntimeError:
                pass

        executor.shutdown(wait=True)

        available = 0
        while SEM.acquire(blocking=False):
            available += 1
        for _ in range(available):
            SEM.release()
        assert available == 4, f"Semaphore leaked: {available} slots available, expected 4"

    def test_global_semaphore_limits_cross_request(self):
        """Global semaphore must limit total inflight across concurrent callers."""
        GLOBAL_SEM = threading.BoundedSemaphore(6)
        executor = ThreadPoolExecutor(max_workers=12, thread_name_prefix="test-global")
        high_water = {'max': 0}
        active = {'count': 0}
        lock = threading.Lock()

        def tracked_work(idx):
            with lock:
                active['count'] += 1
                if active['count'] > high_water['max']:
                    high_water['max'] = active['count']
            time.sleep(0.02)
            with lock:
                active['count'] -= 1
            return idx

        def run_batch(start, count):
            futures = []
            for i in range(start, start + count):
                GLOBAL_SEM.acquire()
                try:
                    f = executor.submit(tracked_work, i)
                    f.add_done_callback(lambda _: GLOBAL_SEM.release())
                    futures.append(f)
                except Exception:
                    GLOBAL_SEM.release()
                    raise
            return [f.result() for f in futures]

        threads = []
        results = [None, None, None]
        for batch_idx in range(3):

            def worker(idx=batch_idx):
                results[idx] = run_batch(idx * 10, 10)

            t = threading.Thread(target=worker)
            threads.append(t)
            t.start()

        for t in threads:
            t.join()

        executor.shutdown(wait=True)
        assert high_water['max'] <= 6 + 1, f"Global high water {high_water['max']} exceeds cap 6"
        for r in results:
            assert r is not None and len(r) == 10
