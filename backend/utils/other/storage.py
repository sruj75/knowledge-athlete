import datetime
import hashlib
import json
import os
import struct
import threading
from typing import Any, Dict, List, Optional, Tuple
from concurrent.futures import wait, FIRST_COMPLETED

from utils.executors import storage_executor

try:
    import opuslib
except Exception as e:
    opuslib = None
    _opus_import_error: Optional[Exception] = e
else:
    _opus_import_error = None
from google.cloud import storage
from google.oauth2 import service_account
from google.cloud.exceptions import NotFound as BlobNotFound

from database.redis_db import cache_signed_url, get_cached_signed_url
from utils import encryption
import logging

logger = logging.getLogger(__name__)

# Per-request fan-out limits for storage_executor (#7387)
_STORAGE_CHUNK_SEM = threading.BoundedSemaphore(32)
_CHUNK_WINDOW_SIZE = 8

# Opus encoding constants
OPUS_SAMPLE_RATE = 16000
OPUS_CHANNELS = 1
OPUS_FRAME_DURATION_MS = 20  # 20ms frames (standard for voice)
OPUS_FRAME_SIZE = OPUS_SAMPLE_RATE * OPUS_FRAME_DURATION_MS // 1000  # 320 samples per frame

# Valid private cloud sync extensions (longest first for correct matching)
PRIVATE_CLOUD_EXTENSIONS = ['.batch.enc', '.batch.bin', '.opus.enc', '.opus', '.enc', '.bin']

storage_client = None
_storage_client_lock = threading.Lock()


def _get_storage_client() -> Any:
    """Return the GCS client lazily so importing this module never probes ADC/GCE metadata."""
    global storage_client
    if storage_client is None:
        with _storage_client_lock:
            if storage_client is None:
                if os.environ.get('SERVICE_ACCOUNT_JSON'):
                    service_account_info = json.loads(os.environ["SERVICE_ACCOUNT_JSON"])
                    credentials = service_account.Credentials.from_service_account_info(service_account_info)  # type: ignore[reportUnknownMemberType]  # google.oauth2 partial stubs
                    storage_client = storage.Client(credentials=credentials)
                else:
                    _gcs_project = (
                        os.environ.get('GOOGLE_CLOUD_PROJECT') or os.environ.get('FIREBASE_PROJECT_ID') or ''
                    ).strip()
                    storage_client = storage.Client(project=_gcs_project) if _gcs_project else storage.Client()
    return storage_client


private_cloud_sync_bucket = os.getenv('BUCKET_PRIVATE_CLOUD_SYNC', 'omi-private-cloud-sync')
desktop_updates_bucket = os.getenv('BUCKET_DESKTOP_UPDATES')
PLAYBACK_ARTIFACT_PREFIX = 'playback'
CONVERSATION_ARTIFACT_NAME = 'conversation'


def _get_opuslib() -> Any:
    if opuslib is None:
        raise RuntimeError(
            'Opus support requires opuslib and the native libopus library. '
            'Install the OS-level Opus package before encoding or decoding .opus audio.'
        ) from _opus_import_error
    return opuslib


# ************************************************
# *********** PRIVATE CLOUD SYNC *****************
# ************************************************


def decode_opus_to_pcm(opus_data: bytes, sample_rate: int = OPUS_SAMPLE_RATE, channels: int = OPUS_CHANNELS) -> bytes:
    """
    Decode length-prefixed Opus packets back to PCM16.

    Args:
        opus_data: Length-prefixed Opus packets (from encode_pcm_to_opus)
        sample_rate: Sample rate in Hz (default 16000)
        channels: Number of audio channels (default 1)

    Returns:
        Raw PCM16 audio bytes

    Raises:
        ValueError: If opus_data is too short or has invalid header/packet structure
    """
    if len(opus_data) < 8:
        raise ValueError(f"Opus data too short: {len(opus_data)} bytes (need at least 8 for header)")

    frame_size = sample_rate * OPUS_FRAME_DURATION_MS // 1000

    offset = 0
    packet_count = struct.unpack_from('<I', opus_data, offset)[0]
    offset += 4
    original_pcm_len = struct.unpack_from('<I', opus_data, offset)[0]
    offset += 4

    packets: List[bytes] = []
    for i in range(packet_count):
        if offset + 2 > len(opus_data):
            raise ValueError(f"Truncated Opus data: expected packet {i}/{packet_count} length at offset {offset}")
        pkt_len = struct.unpack_from('<H', opus_data, offset)[0]
        offset += 2
        if offset + pkt_len > len(opus_data):
            raise ValueError(
                f"Truncated Opus data: packet {i} needs {pkt_len} bytes at offset {offset}, only {len(opus_data) - offset} available"
            )
        packets.append(opus_data[offset : offset + pkt_len])
        offset += pkt_len

    opus = _get_opuslib()
    decoder = opus.Decoder(sample_rate, channels)

    pcm_parts: List[bytes] = []
    for pkt_data in packets:
        decoded = decoder.decode(pkt_data, frame_size)
        pcm_parts.append(decoded)

    result = b''.join(pcm_parts)
    # Trim to original PCM length to remove padding from partial final frame
    if original_pcm_len > 0 and original_pcm_len < len(result):
        result = result[:original_pcm_len]
    return result


def _get_extension_for_path(path: str) -> str:
    """Extract the private cloud sync extension from a GCS path."""
    if path.endswith('.batch.enc'):
        return 'batch.enc'
    elif path.endswith('.batch.bin'):
        return 'batch.bin'
    elif path.endswith('.opus.enc'):
        return 'opus.enc'
    elif path.endswith('.opus'):
        return 'opus'
    elif path.endswith('.enc'):
        return 'enc'
    elif path.endswith('.bin'):
        return 'bin'
    return 'bin'


def _strip_extension(filename: str) -> str:
    """Strip private cloud sync extension to get the timestamp string.

    Handles both single-chunk filenames (e.g. '1000.000.opus') and
    batch filenames (e.g. '1000.000-1010.000.batch.bin').
    """
    for ext in ('.batch.enc', '.batch.bin', '.opus.enc', '.opus', '.enc', '.bin'):
        if filename.endswith(ext):
            return filename[: -len(ext)]
    return filename.rsplit('.', 1)[0]


def list_audio_chunks(uid: str, conversation_id: str) -> List[Dict[str, Any]]:
    """
    List all audio chunks for a conversation.

    Returns:
        List of dicts with chunk info: {'timestamp': float, 'path': str, 'size': int}
    """
    bucket = _get_storage_client().bucket(private_cloud_sync_bucket)
    prefix = f'chunks/{uid}/{conversation_id}/'
    blobs = bucket.list_blobs(prefix=prefix)

    chunks: List[Dict[str, Any]] = []
    for blob in blobs:
        # Extract timestamp from filename
        # Supports single-chunk: '1234567890.123.opus', '1234567890.123.opus.enc', etc.
        # Supports batch: '1234567890.123-1234567900.123.batch.bin', '1234567890.123.batch.enc'
        filename = blob.name.split('/')[-1]
        has_valid_ext = any(filename.endswith(ext) for ext in PRIVATE_CLOUD_EXTENSIONS)
        if has_valid_ext:
            try:
                timestamp_str = _strip_extension(filename)
                is_batch = '.batch.' in filename

                if is_batch and '-' in timestamp_str:
                    # Batch blob with timestamp range: "first_ts-last_ts"
                    first_ts_str, _ = timestamp_str.split('-', 1)
                    timestamp = float(first_ts_str)
                else:
                    timestamp = float(timestamp_str)

                chunks.append(
                    {
                        'timestamp': timestamp,
                        'path': blob.name,
                        'size': blob.size,
                        'is_batch': is_batch,
                    }
                )
            except ValueError:
                continue

    return sorted(chunks, key=lambda x: x['timestamp'])


def download_audio_chunks_and_merge(
    uid: str,
    conversation_id: str,
    timestamps: List[float],
    fill_gaps: bool = True,
    sample_rate: int = 16000,
) -> bytes:
    """
    Download and merge audio chunks on-demand, handling mixed encryption states.
    Downloads chunks in parallel.
    Normalizes all chunks to unencrypted PCM format for consistent merging.
    Supports both single-chunk blobs and batch blobs (from upload_audio_chunks_batch).

    Args:
        uid: User ID
        conversation_id: Conversation ID
        timestamps: List of chunk timestamps to merge
        fill_gaps: If True, insert silence (zero bytes) between chunks to maintain
                   continuous time-aligned audio. Default True.
        sample_rate: Audio sample rate in Hz (default 16000)

    Returns:
        Merged audio bytes (PCM16)
    """

    bucket = _get_storage_client().bucket(private_cloud_sync_bucket)

    # Resolve actual GCS paths — needed to find batch blobs whose filenames
    # contain timestamp ranges instead of single timestamps
    actual_chunks = list_audio_chunks(uid, conversation_id)
    ts_set = {round(ts, 3) for ts in timestamps}

    # Build batch blob map: for batch blobs, track which timestamps they cover
    batch_paths: Dict[str, Dict[str, Any]] = {}  # path -> chunk_info (deduplicate downloads)
    ts_to_batch_path: Dict[float, str] = {}  # timestamp -> batch_path (for timestamps inside batch range)
    single_chunk_timestamps: List[float] = []  # timestamps that have individual blobs

    for chunk in actual_chunks:
        if chunk.get('is_batch'):
            path = chunk['path']
            batch_paths[path] = chunk

            # Parse batch range to determine covered timestamps
            filename = path.split('/')[-1]
            ts_str = _strip_extension(filename)
            if '-' in ts_str:
                start_str, end_str = ts_str.split('-', 1)
                batch_start = float(start_str)
                batch_end = float(end_str)
            else:
                batch_start = batch_end = float(ts_str)

            # Map requested timestamps that fall within this batch's range
            for ts in timestamps:
                if batch_start <= round(ts, 3) <= batch_end:
                    ts_to_batch_path[round(ts, 3)] = path
        elif round(chunk['timestamp'], 3) in ts_set:
            single_chunk_timestamps.append(chunk['timestamp'])

    def _download_and_decode_blob(path: str) -> bytes | None:
        """Download a blob and decode/decrypt based on extension."""
        ext = _get_extension_for_path(path)
        encrypted = ext in ('opus.enc', 'enc', 'batch.enc')
        is_opus = ext in ('opus.enc', 'opus')

        try:
            chunk_data = bucket.blob(path).download_as_bytes()
        except BlobNotFound:
            return None

        try:
            if encrypted:
                raw_data = encryption.decrypt_audio_file(chunk_data, uid)
            else:
                raw_data = chunk_data

            if is_opus:
                pcm_data = decode_opus_to_pcm(raw_data, sample_rate=sample_rate)
                del raw_data
            else:
                pcm_data = raw_data

            return pcm_data
        except Exception as e:
            logger.warning(f"Failed to decode/decrypt {path}: {e}")
            return None

    def download_single_chunk(timestamp: float) -> tuple[float, bytes | None]:
        """Download a single-chunk blob by trying extensions in priority order."""
        formatted_timestamp = f'{timestamp:.3f}'

        extensions_to_try = [
            ('opus.enc', True, True),  # (ext, encrypted, opus)
            ('enc', True, False),
            ('opus', False, True),
            ('bin', False, False),
        ]

        for ext, encrypted, opus in extensions_to_try:
            chunk_path = f'chunks/{uid}/{conversation_id}/{formatted_timestamp}.{ext}'
            try:
                chunk_data = bucket.blob(chunk_path).download_as_bytes()
            except BlobNotFound:
                continue

            try:
                if encrypted:
                    raw_data = encryption.decrypt_audio_file(chunk_data, uid)
                else:
                    raw_data = chunk_data

                if opus:
                    pcm_data = decode_opus_to_pcm(raw_data, sample_rate=sample_rate)
                    del raw_data
                else:
                    pcm_data = raw_data

                return (timestamp, pcm_data)
            except Exception as e:
                logger.warning(
                    f"Failed to decode/decrypt {ext} chunk at {formatted_timestamp}: {e}, trying next format"
                )
                continue

        logger.warning(f"Warning: Chunk not found for timestamp {formatted_timestamp}")
        return (timestamp, None)

    # Download data with bounded concurrency (sliding window + global semaphore, #7387)
    chunk_results: Dict[float, bytes] = {}

    individual_timestamps = [ts for ts in timestamps if round(ts, 3) not in ts_to_batch_path]
    unique_batch_paths = list(set(ts_to_batch_path.values()))

    # Build unified job list: ('individual', ts) or ('batch', path)
    jobs = [('individual', ts) for ts in individual_timestamps] + [('batch', p) for p in unique_batch_paths]

    def _submit_job(job: Tuple[str, Any]) -> Tuple[Any, str, Any]:
        kind, key = job
        _STORAGE_CHUNK_SEM.acquire()
        try:
            if kind == 'individual':
                f = storage_executor.submit(download_single_chunk, key)
            else:
                f = storage_executor.submit(_download_and_decode_blob, key)
            f.add_done_callback(lambda _: _STORAGE_CHUNK_SEM.release())
            return (f, kind, key)
        except Exception:
            _STORAGE_CHUNK_SEM.release()
            raise

    # Sliding window: at most _CHUNK_WINDOW_SIZE in-flight per call
    pending: Dict[Any, Tuple[Any, str, Any]] = {}
    job_iter = iter(jobs)
    for job in job_iter:
        finfo = _submit_job(job)
        pending[finfo[0]] = finfo
        if len(pending) >= _CHUNK_WINDOW_SIZE:
            break

    while pending:
        done, _ = wait(pending.keys(), return_when=FIRST_COMPLETED)
        for future in done:
            _, kind, key = pending.pop(future)
            try:
                if kind == 'individual':
                    timestamp, pcm_data = future.result()
                    if pcm_data is not None:
                        chunk_results[timestamp] = pcm_data
                else:
                    pcm_data = future.result()
                    if pcm_data is not None:
                        batch_info = batch_paths[key]
                        chunk_results[batch_info['timestamp']] = pcm_data
            except Exception as e:
                logger.warning(f"Chunk download failed ({kind}={key}): {e}")

        for job in job_iter:
            finfo = _submit_job(job)
            pending[finfo[0]] = finfo
            if len(pending) >= _CHUNK_WINDOW_SIZE:
                break

    # Merge chunks
    merged_data = bytearray()

    if fill_gaps and timestamps and chunk_results:
        # Sort timestamps to ensure proper ordering
        sorted_timestamps = sorted(timestamps)
        first_timestamp = sorted_timestamps[0]
        current_time = first_timestamp  # Track current audio end time in seconds

        for timestamp in sorted_timestamps:
            if timestamp not in chunk_results:
                continue

            pcm_data = chunk_results[timestamp]

            # Calculate gap from current position to this chunk's start
            gap_seconds = timestamp - current_time
            if gap_seconds > 0:
                # Insert silence: 16-bit mono = 2 bytes per sample
                gap_samples = int(gap_seconds * sample_rate)
                silence_bytes = bytes(gap_samples * 2)  # Zero bytes for silence
                merged_data.extend(silence_bytes)
                logger.debug(f"Filled {gap_seconds:.3f}s gap ({len(silence_bytes)} bytes) before chunk at {timestamp}")

            merged_data.extend(pcm_data)

            # Update current time based on chunk duration
            # PCM16 mono: 2 bytes per sample
            chunk_duration = len(pcm_data) / (sample_rate * 2)
            current_time = timestamp + chunk_duration
    else:
        # Original behavior - just concatenate without gap filling
        for timestamp in timestamps:
            if timestamp in chunk_results:
                merged_data.extend(chunk_results[timestamp])

    # Free memory from chunk results immediately after merging
    chunk_results.clear()

    if not merged_data:
        raise FileNotFoundError(f"No chunks found for conversation {conversation_id}")

    return bytes(merged_data)


def _playback_artifact_blob(uid: str, conversation_id: str, audio_file_id: str):
    bucket = _get_storage_client().bucket(private_cloud_sync_bucket)
    return bucket.blob(f'{PLAYBACK_ARTIFACT_PREFIX}/{uid}/{conversation_id}/{audio_file_id}.mp3')


def get_playback_artifact_signed_url(uid: str, conversation_id: str, audio_file_id: str):
    blob = _playback_artifact_blob(uid, conversation_id, audio_file_id)
    if not blob.exists():
        return None
    return _get_signed_url(blob, 60)


def upload_playback_artifact(uid: str, conversation_id: str, audio_file_id: str, mp3_data: bytes) -> None:
    blob = _playback_artifact_blob(uid, conversation_id, audio_file_id)
    blob.upload_from_string(mp3_data, content_type='audio/mpeg')


def _playback_unavailable_blob(uid: str, conversation_id: str, audio_file_id: str):
    bucket = _get_storage_client().bucket(private_cloud_sync_bucket)
    return bucket.blob(f'{PLAYBACK_ARTIFACT_PREFIX}/{uid}/{conversation_id}/{audio_file_id}.unavailable')


def mark_playback_unavailable(uid: str, conversation_id: str, audio_file_id: str, reason: str) -> None:
    """Mark an audio file as unbuildable (e.g. source chunks gone).

    Without this, /urls would report the file as pending forever and clients
    would poll to exhaustion. The marker lives under playback/ so the 30-day
    lifecycle rule grants even these a retry eventually.
    """
    blob = _playback_unavailable_blob(uid, conversation_id, audio_file_id)
    blob.upload_from_string(reason, content_type='text/plain')


def compute_audio_files_fingerprint(audio_files: List[Dict[str, Any]]) -> str:
    """Content fingerprint of a conversation's audio_files (id + chunk count +
    last chunk timestamp per part, order-insensitive). Stamped on the doc at
    build time; a mismatch with the current audio_files means the artifact is
    stale. Also embedded in the Cloud Tasks task name so rebuilds after late
    chunks aren't swallowed by named-task dedup."""
    parts = sorted(
        [
            [af['id'], len(af['chunk_timestamps']), round(sorted(af['chunk_timestamps'])[-1], 3)]
            for af in audio_files
            if af.get('id') and af.get('chunk_timestamps')
        ],
        key=lambda p: p[0],
    )
    return hashlib.sha1(json.dumps(parts).encode()).hexdigest()[:12]


def _conversation_playback_blob(uid: str, conversation_id: str):
    bucket = _get_storage_client().bucket(private_cloud_sync_bucket)
    return bucket.blob(f'{PLAYBACK_ARTIFACT_PREFIX}/{uid}/{conversation_id}/{CONVERSATION_ARTIFACT_NAME}.mp3')


def get_conversation_playback_signed_url(uid: str, conversation_id: str):
    blob = _conversation_playback_blob(uid, conversation_id)
    if not blob.exists():
        return None
    return _get_signed_url(blob, 60)


def upload_conversation_playback_artifact(uid: str, conversation_id: str, mp3_data: bytes) -> None:
    blob = _conversation_playback_blob(uid, conversation_id)
    blob.upload_from_string(mp3_data, content_type='audio/mpeg')


def _conversation_playback_unavailable_blob(uid: str, conversation_id: str):
    bucket = _get_storage_client().bucket(private_cloud_sync_bucket)
    return bucket.blob(f'{PLAYBACK_ARTIFACT_PREFIX}/{uid}/{conversation_id}/{CONVERSATION_ARTIFACT_NAME}.unavailable')


def mark_conversation_playback_unavailable(uid: str, conversation_id: str, fingerprint: str, reason: str) -> None:
    """Marker content carries the fingerprint it was written for: a marker for a
    stale fingerprint is ignored on read (late chunks may fix a chunks_missing verdict)."""
    blob = _conversation_playback_unavailable_blob(uid, conversation_id)
    blob.upload_from_string(f'{fingerprint}:{reason}', content_type='text/plain')


def _get_signed_url(blob: Any, minutes: int) -> str:
    if cached := get_cached_signed_url(blob.name):
        return cached

    signed_url: str = blob.generate_signed_url(
        version="v4", expiration=datetime.timedelta(minutes=minutes), method="GET"
    )
    cache_signed_url(blob.name, signed_url, minutes * 60)
    return signed_url


# **************************************************
# ************* DESKTOP UPDATES ********************
# **************************************************


def get_desktop_update_signed_url(blob_path: str, expiration_hours: int = 1) -> str:
    """
    Generate a signed URL for a desktop update file (ZIP).

    Args:
        blob_path: Path to the blob in GCS (e.g., "1.0.78+474-macos/1.0.78+474-macos.zip")
        expiration_hours: Hours until the URL expires (default: 1 hour)

    Returns:
        Signed URL valid for the specified duration
    """
    bucket = _get_storage_client().bucket(desktop_updates_bucket)
    blob = bucket.blob(blob_path)

    # Use existing _get_signed_url helper with caching
    return _get_signed_url(blob, expiration_hours * 60)
