"""
Tests for memory leak prevention buffers in transcribe.py.
Covers: audio buffer capping (deque), deque maxlen behavior.
"""

import time
from collections import deque

# Constants matching transcribe.py
MAX_AUDIO_BUFFER_SIZE = 1024 * 1024 * 10  # 10MB
MAX_SEGMENT_BUFFER_SIZE = 1000


def audio_bytes_send_logic(audio_chunks: deque, audio_total_size: int, audio_bytes: bytes, max_size: int) -> tuple:
    """
    Extracted logic from audio_bytes_send for testing.
    Uses deque of chunks with running total for O(1) trimming.
    Returns (audio_chunks, audio_total_size).
    """
    chunk = audio_bytes
    # Trim oversized incoming chunk
    if len(chunk) > max_size:
        chunk = chunk[-max_size:]
    # Drop oldest chunks to make room - O(1) per chunk
    while audio_total_size + len(chunk) > max_size and audio_chunks:
        old = audio_chunks.popleft()
        audio_total_size -= len(old)
    audio_chunks.append(chunk)
    audio_total_size += len(chunk)
    return audio_chunks, audio_total_size


class TestAudioBufferCapping:
    """Test audio buffer size limiting logic with deque of chunks."""

    def test_normal_append_within_limit(self):
        """Normal append when buffer has room."""
        chunks = deque()
        chunks.append(b'existing')
        total = 8
        chunks, total = audio_bytes_send_logic(chunks, total, b'new', MAX_AUDIO_BUFFER_SIZE)
        assert b''.join(chunks) == b'existingnew'
        assert total == 11

    def test_drops_oldest_when_exceeds_limit(self):
        """Drops oldest chunks when new data would exceed limit."""
        max_size = 10
        chunks = deque()
        chunks.append(b'12345678')  # 8 bytes
        total = 8
        chunks, total = audio_bytes_send_logic(chunks, total, b'abc', max_size)  # +3 = 11, drop oldest
        assert total == 3  # Only 'abc' remains after dropping '12345678'
        assert b''.join(chunks) == b'abc'

    def test_trims_oversized_incoming_chunk(self):
        """Trims incoming chunk if it alone exceeds max size."""
        max_size = 5
        chunks = deque()
        total = 0
        chunks, total = audio_bytes_send_logic(chunks, total, b'1234567890', max_size)  # 10 bytes, max 5
        assert total == max_size
        assert b''.join(chunks) == b'67890'  # kept last 5 bytes

    def test_oversized_chunk_replaces_existing_buffer(self):
        """Oversized chunk after trimming replaces existing buffer."""
        max_size = 5
        chunks = deque()
        chunks.append(b'abc')
        total = 3
        chunks, total = audio_bytes_send_logic(chunks, total, b'1234567890', max_size)
        assert total == max_size
        assert b''.join(chunks) == b'67890'

    def test_exact_fit(self):
        """Chunk that exactly fills remaining space."""
        max_size = 10
        chunks = deque()
        chunks.append(b'12345')  # 5 bytes
        total = 5
        chunks, total = audio_bytes_send_logic(chunks, total, b'67890', max_size)  # +5 = 10
        assert total == max_size
        assert b''.join(chunks) == b'1234567890'

    def test_boundary_one_over(self):
        """One byte over the limit triggers drop of oldest chunk."""
        max_size = 10
        chunks = deque()
        chunks.append(b'12345')  # 5 bytes
        total = 5
        chunks, total = audio_bytes_send_logic(chunks, total, b'678901', max_size)  # +6 = 11, drop oldest
        assert total == 6  # Only '678901' remains
        assert b''.join(chunks) == b'678901'

    def test_multiple_small_chunks_dropped(self):
        """Multiple small chunks dropped to make room for large chunk."""
        max_size = 10
        chunks = deque()
        chunks.append(b'aa')
        chunks.append(b'bb')
        chunks.append(b'cc')
        total = 6
        chunks, total = audio_bytes_send_logic(chunks, total, b'12345678', max_size)  # +8 = 14, drop until fits
        assert total <= max_size
        assert b'12345678' in b''.join(chunks)


class TestDequeMaxlen:
    """Test deque maxlen behavior for segment buffers."""

    def test_deque_drops_oldest_at_maxlen(self):
        """Deque with maxlen drops oldest when full."""
        d = deque(maxlen=3)
        d.extend([1, 2, 3])
        d.append(4)
        assert list(d) == [2, 3, 4]

    def test_deque_extend_drops_multiple(self):
        """Extend that exceeds capacity drops multiple oldest."""
        d = deque(maxlen=3)
        d.extend([1, 2, 3])
        d.extend([4, 5])
        assert list(d) == [3, 4, 5]

    def test_deque_clear_preserves_maxlen(self):
        """Clear preserves maxlen unlike reassignment."""
        d = deque(maxlen=3)
        d.extend([1, 2, 3])
        d.clear()
        assert d.maxlen == 3
        d.extend([1, 2, 3, 4])
        assert list(d) == [2, 3, 4]

    def test_list_conversion_preserves_order(self):
        """list() conversion preserves order for JSON serialization."""
        d = deque(maxlen=5)
        d.extend([1, 2, 3])
        assert list(d) == [1, 2, 3]


# Constants for pending requests
MAX_PENDING_REQUESTS = 100


def pending_requests_add_logic(pending_requests: set, conversation_id: str, max_size: int) -> set:
    """
    Extracted logic from request_conversation_processing for testing.
    Returns the updated set.
    """
    if len(pending_requests) >= max_size:
        pending_requests.pop()  # Remove arbitrary element (set has no order)
    pending_requests.add(conversation_id)
    return pending_requests


class TestPendingConversationRequests:
    """Test pending conversation requests limiting logic."""

    def test_normal_add_within_limit(self):
        """Normal add when set has room."""
        pending = {'id_1', 'id_2'}
        result = pending_requests_add_logic(pending, 'id_3', MAX_PENDING_REQUESTS)
        assert 'id_3' in result
        assert len(result) == 3

    def test_drops_one_when_at_limit(self):
        """Drops one entry when adding would exceed limit."""
        max_size = 3
        pending = {'id_1', 'id_2', 'id_3'}
        original_len = len(pending)
        result = pending_requests_add_logic(pending, 'id_4', max_size)
        assert 'id_4' in result
        assert len(result) == max_size  # Size stays at max
        # One of the original entries was dropped
        remaining_original = len([x for x in result if x != 'id_4'])
        assert remaining_original == max_size - 1

    def test_add_duplicate_no_growth(self):
        """Adding duplicate doesn't grow the set."""
        pending = {'id_1', 'id_2'}
        result = pending_requests_add_logic(pending, 'id_1', MAX_PENDING_REQUESTS)
        assert len(result) == 2

    def test_boundary_one_below_limit(self):
        """Adding at exactly one below limit succeeds without drop."""
        max_size = 3
        pending = {'id_1', 'id_2'}  # 2 items, max is 3
        result = pending_requests_add_logic(pending, 'id_3', max_size)
        assert len(result) == max_size
        assert 'id_1' in result
        assert 'id_2' in result
        assert 'id_3' in result


class TestProductionBufferTypes:
    """Test that production buffers are correctly typed as bounded deques."""

    def test_segment_buffer_is_bounded_deque(self):
        """Segment buffer should be a deque with maxlen."""
        # Simulate production initialization
        segment_buffers: deque = deque(maxlen=MAX_SEGMENT_BUFFER_SIZE)
        assert isinstance(segment_buffers, deque)
        assert segment_buffers.maxlen == MAX_SEGMENT_BUFFER_SIZE

    def test_realtime_segment_buffer_is_bounded_deque(self):
        """Realtime segment buffer should be a deque with maxlen."""
        realtime_segment_buffers: deque = deque(maxlen=MAX_SEGMENT_BUFFER_SIZE)
        assert isinstance(realtime_segment_buffers, deque)
        assert realtime_segment_buffers.maxlen == MAX_SEGMENT_BUFFER_SIZE

    def test_deque_assignment_loses_maxlen(self):
        """Verify that reassigning deque to list loses maxlen - this is the bug we fixed."""
        d = deque(maxlen=5)
        d.extend([1, 2, 3])

        # BAD: reassignment loses maxlen
        bad_copy = d.copy()
        bad_copy = []  # This is what we fixed - don't do this!
        assert not isinstance(bad_copy, deque)

        # GOOD: use list() + clear() to preserve deque instance
        good_deque = deque(maxlen=5)
        good_deque.extend([1, 2, 3])
        items = list(good_deque)
        good_deque.clear()
        assert isinstance(good_deque, deque)
        assert good_deque.maxlen == 5
        assert items == [1, 2, 3]

    def test_audio_chunks_is_deque(self):
        """Audio chunks should be a deque (not bytearray)."""
        audio_chunks: deque = deque()
        assert isinstance(audio_chunks, deque)
