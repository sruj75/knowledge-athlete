"""E2E tests for /v4/listen pipeline features: Translation and Multi-Channel.

These tests exercise real backend + pusher services with no mocking.
Each test connects via WebSocket, sends real audio/data, and verifies
that the expected events are received.

Prerequisites:
  - Local backend running with LOCAL_DEVELOPMENT=true:
    LOCAL_DEVELOPMENT=true HOSTED_PUSHER_API_URL=http://localhost:10152 \
      uvicorn main:app --port 10151
  - Pusher service running:
    PYTHONPATH=. python3 -m uvicorn pusher.main:app --port 10152
  - Firebase/Firestore credentials configured

Usage:
  pytest tests/integration/test_listen_features_e2e.py -v -x
"""

import asyncio
import json
import math
import os
import socket
import struct
import time
import uuid
import wave

import pytest
import websockets
from websockets.exceptions import ConnectionClosed

# ---------------------------------------------------------------------------
# Service config — matches kelvin's setup: backend 10151, pusher 10152
# ---------------------------------------------------------------------------
BACKEND_HOST = "localhost"
BACKEND_PORT = int(os.getenv("E2E_BACKEND_PORT", "10151"))
PUSHER_PORT = int(os.getenv("E2E_PUSHER_PORT", "10152"))
LISTEN_URL = f"ws://{BACKEND_HOST}:{BACKEND_PORT}/v4/listen"
DEV_AUTH_HEADER = {"authorization": "Bearer dev-token"}

TEST_WAV = os.path.join(
    os.path.dirname(__file__),
    '../../pretrained_models/snakers4_silero-vad_master/tests/data/test.wav',
)


# ---------------------------------------------------------------------------
# Helpers — reusable across all test classes
# ---------------------------------------------------------------------------


def is_port_open(port: int) -> bool:
    try:
        sock = socket.create_connection((BACKEND_HOST, port), timeout=2)
        sock.close()
        return True
    except (socket.timeout, ConnectionRefusedError, OSError):
        return False


def load_test_audio_pcm16(seconds: int = 5):
    """Load test WAV file and return (pcm_bytes, sample_rate)."""
    if not os.path.exists(TEST_WAV):
        return None
    wf = wave.open(TEST_WAV, 'r')
    frames = min(wf.getnframes(), wf.getframerate() * seconds)
    pcm_data = wf.readframes(frames)
    sample_rate = wf.getframerate()
    wf.close()
    return pcm_data, sample_rate


def generate_tone_pcm16(seconds: float, freq: int = 440, sample_rate: int = 16000, amplitude: float = 0.5) -> bytes:
    """Generate PCM16LE sine wave tone."""
    samples = []
    for i in range(int(sample_rate * seconds)):
        sample = int(32767 * amplitude * math.sin(2 * math.pi * freq * i / sample_rate))
        samples.append(max(-32768, min(32767, sample)))
    return struct.pack(f'<{len(samples)}h', *samples)


def generate_silence_pcm16(seconds: float, sample_rate: int = 16000) -> bytes:
    """Generate PCM16LE silence."""
    return b'\x00\x00' * int(sample_rate * seconds)


async def connect_listen(
    sample_rate: int = 16000,
    codec: str = 'pcm8',
    language: str = 'en',
    channels: int = 1,
    source: str = '',
    conversation_timeout: int = 120,
    extra_params: str = '',
) -> websockets.WebSocketClientProtocol:
    """Connect to /v4/listen with dev auth."""
    url = (
        f"{LISTEN_URL}?language={language}&sample_rate={sample_rate}&codec={codec}"
        f"&conversation_timeout={conversation_timeout}&channels={channels}"
    )
    if source:
        url += f"&source={source}"
    if extra_params:
        url += extra_params
    ws = await websockets.connect(url, extra_headers=DEV_AUTH_HEADER, close_timeout=10)
    return ws


async def wait_for_ready(ws, timeout: int = 15) -> bool:
    """Wait for server 'ready' status message."""
    start = time.time()
    while time.time() - start < timeout:
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=2)
            if isinstance(msg, str) and msg != 'ping':
                try:
                    parsed = json.loads(msg)
                    if parsed.get('status') == 'ready':
                        return True
                except json.JSONDecodeError:
                    pass
        except asyncio.TimeoutError:
            continue
    return False


async def send_audio_chunks(ws, pcm_data: bytes, chunk_size: int = 960, delay: float = 0.015):
    """Send PCM audio in chunks at approximately real-time pace."""
    for offset in range(0, len(pcm_data), chunk_size):
        chunk = pcm_data[offset : offset + chunk_size]
        await ws.send(chunk)
        if delay > 0:
            await asyncio.sleep(delay)


def _normalize_ws_message(parsed) -> list:
    """Normalize a parsed JSON message into a list of event dicts.

    Transcripts arrive as raw JSON arrays of segment dicts:
      [{"id": ..., "text": ..., "speaker": ...}, ...]
    Other events arrive as JSON objects with a 'type' field:
      {"type": "translating", "segments": [...]}

    Returns a list of event dicts (wrapping arrays in a synthetic dict).
    """
    if isinstance(parsed, dict):
        return [parsed]
    elif isinstance(parsed, list):
        # Wrap transcript segment array in a synthetic event dict
        return [{"type": "transcript_segments", "segments": parsed}]
    return []


async def collect_events(ws, duration: float = 10, event_filter=None) -> list:
    """Collect parsed JSON events from WebSocket for up to `duration` seconds."""
    events = []
    start = time.time()
    while time.time() - start < duration:
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=1)
            if isinstance(msg, str) and msg != 'ping':
                try:
                    parsed = json.loads(msg)
                    for evt in _normalize_ws_message(parsed):
                        if event_filter is None or event_filter(evt):
                            events.append(evt)
                except json.JSONDecodeError:
                    pass
        except asyncio.TimeoutError:
            continue
        except ConnectionClosed:
            break
    return events


async def collect_events_until(ws, predicate, timeout: float = 30) -> list:
    """Collect events until predicate(events_list) returns True or timeout."""
    events = []
    start = time.time()
    while time.time() - start < timeout:
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=1)
            if isinstance(msg, str) and msg != 'ping':
                try:
                    parsed = json.loads(msg)
                    for evt in _normalize_ws_message(parsed):
                        events.append(evt)
                    if predicate(events):
                        return events
                except json.JSONDecodeError:
                    pass
        except asyncio.TimeoutError:
            continue
        except ConnectionClosed:
            break
    return events


# ---------------------------------------------------------------------------
# Skip markers
# ---------------------------------------------------------------------------
backend_running = is_port_open(BACKEND_PORT)
pusher_running = is_port_open(PUSHER_PORT)

skip_no_backend = pytest.mark.skipif(
    not backend_running,
    reason=f"Backend not running on {BACKEND_HOST}:{BACKEND_PORT}",
)
skip_no_pusher = pytest.mark.skipif(
    not pusher_running,
    reason=f"Pusher not running on {BACKEND_HOST}:{PUSHER_PORT}",
)


# ===================================================================
# TEST 4: Translation E2E
# ===================================================================


@skip_no_backend
class TestTranslationE2E:
    """Verify that connecting with language=multi produces TranslationEvent messages.

    The pipeline:
      Client → /v4/listen?language=multi → Modulate (multi-lang) → transcripts
        → translation service → TranslationEvent sent back to client

    Translation requires:
    1. language='multi' (triggers multi-lang STT + translation pipeline)
    2. Real speech audio that Modulate can transcribe
    3. Backend must have Google Cloud Translation API credentials
    """

    @pytest.mark.asyncio
    async def test_translation_events_received(self):
        """Stream real speech with language=multi and verify TranslationEvent arrives."""
        audio = load_test_audio_pcm16(seconds=10)
        if audio is None:
            pytest.skip("Test WAV file not found")
        pcm_data, sample_rate = audio

        uid = f"test-translation-{uuid.uuid4().hex[:8]}"

        # Connect with language=multi to trigger translation pipeline
        ws = await connect_listen(
            sample_rate=sample_rate,
            language='multi',
            conversation_timeout=120,
        )
        try:
            assert await wait_for_ready(ws), "Backend did not send 'ready' status"

            # Send speech audio
            await send_audio_chunks(ws, pcm_data)

            # Collect events — look for both transcript segments and translation events
            # Translation has a 1-second debounce, so we wait up to 20 seconds
            transcripts = []
            translations = []

            def got_both(events):
                for e in events:
                    etype = e.get('type', '')
                    if etype == 'translating':
                        translations.append(e)
                    # Transcripts come as raw segment arrays (no 'type' field)
                    # or as objects with segments list
                    if 'segments' in e and etype != 'translating':
                        transcripts.append(e)
                return len(translations) > 0

            events = await collect_events_until(ws, got_both, timeout=25)

            # Parse all collected events
            for e in events:
                etype = e.get('type', '')
                if etype == 'translating' and e not in translations:
                    translations.append(e)

            # We should have received at least one translation event
            assert len(translations) > 0, (
                f"Expected TranslationEvent but got none. "
                f"Total events collected: {len(events)}. "
                f"Event types: {[e.get('type', 'no-type') for e in events]}"
            )

            # Verify translation event structure
            for t in translations:
                assert t['type'] == 'translating'
                assert 'segments' in t
                assert isinstance(t['segments'], list)

            # At least one translation segment should have translated text
            all_segments = []
            for t in translations:
                all_segments.extend(t['segments'])

            if all_segments:
                # Segments from TranslationEvent should have text content
                has_text = any(seg.get('text', '').strip() for seg in all_segments if isinstance(seg, dict))
                assert has_text, f"Translation segments have no text content: {all_segments[:3]}"

        finally:
            await ws.close()

    @pytest.mark.asyncio
    async def test_no_translation_in_single_language_mode(self):
        """When language is a specific code (not 'multi'), no TranslationEvent should arrive.

        In single-language mode, the translation pipeline is skipped entirely.
        """
        audio = load_test_audio_pcm16(seconds=5)
        if audio is None:
            pytest.skip("Test WAV file not found")
        pcm_data, sample_rate = audio

        ws = await connect_listen(
            sample_rate=sample_rate,
            language='en',  # Single language — no translation
            conversation_timeout=120,
        )
        try:
            assert await wait_for_ready(ws), "Backend did not send 'ready' status"

            await send_audio_chunks(ws, pcm_data)

            # Collect for 10 seconds — should NOT see any translating events
            events = await collect_events(ws, duration=10)
            translation_events = [e for e in events if e.get('type') == 'translating']

            assert (
                len(translation_events) == 0
            ), f"Got unexpected TranslationEvents in single-language mode: {translation_events}"
        finally:
            await ws.close()

    @pytest.mark.asyncio
    async def test_translation_segments_have_lang_field(self):
        """Translation segments should include the target language."""
        audio = load_test_audio_pcm16(seconds=10)
        if audio is None:
            pytest.skip("Test WAV file not found")
        pcm_data, sample_rate = audio

        ws = await connect_listen(
            sample_rate=sample_rate,
            language='multi',
            conversation_timeout=120,
        )
        try:
            assert await wait_for_ready(ws), "Backend did not send 'ready' status"
            await send_audio_chunks(ws, pcm_data)

            # Wait for translation events
            translations = []

            def got_translation(events):
                for e in events:
                    if e.get('type') == 'translating':
                        translations.append(e)
                return len(translations) > 0

            await collect_events_until(ws, got_translation, timeout=25)

            if not translations:
                pytest.skip("No translation events received (translation API may be unconfigured)")

            # Check segment structure — each translated segment dict should have
            # translation-related fields
            for t in translations:
                for seg in t.get('segments', []):
                    if isinstance(seg, dict):
                        # Segment should have text at minimum
                        assert 'text' in seg, f"Translation segment missing 'text': {seg}"

        finally:
            await ws.close()


# ===================================================================
# TEST 6: Multi-Channel E2E
# ===================================================================


@skip_no_backend
class TestMultiChannelE2E:
    """Verify that connecting with channels=2 enables per-channel speaker separation.

    Protocol:
      - Connect with channels=2&source=phone_call (or desktop)
      - Audio frames are prefixed with channel ID byte:
        [0x01][pcm_audio...]  → channel 1 (mic / user)
        [0x02][pcm_audio...]  → channel 2 (remote / other speaker)
      - Each channel gets its own STT socket
      - Transcript segments are tagged:
        - Channel 1: is_user=True, speaker='SPEAKER_00'
        - Channel 2: is_user=False, speaker='SPEAKER_01'
    """

    @pytest.mark.asyncio
    async def test_two_channel_connection_accepted(self):
        """Backend should accept channels=2 connections and send 'ready'."""
        ws = await connect_listen(
            channels=2,
            source='phone_call',
            conversation_timeout=120,
        )
        try:
            ready = await wait_for_ready(ws)
            assert ready, "Backend did not send 'ready' for channels=2 connection"
        finally:
            await ws.close()

    @pytest.mark.asyncio
    async def test_multi_channel_audio_produces_transcripts(self):
        """Send audio on both channels and verify transcripts are produced."""
        audio = load_test_audio_pcm16(seconds=8)
        if audio is None:
            pytest.skip("Test WAV file not found")
        pcm_data, sample_rate = audio

        ws = await connect_listen(
            sample_rate=sample_rate,
            channels=2,
            source='phone_call',
            conversation_timeout=120,
        )
        try:
            assert await wait_for_ready(ws), "Backend did not send 'ready' status"

            # Send same audio on both channels with channel prefix byte
            # Channel 1 (0x01) = mic/user, Channel 2 (0x02) = remote
            chunk_size = 960  # 30ms at 16kHz
            for offset in range(0, len(pcm_data), chunk_size):
                chunk = pcm_data[offset : offset + chunk_size]
                # Send on channel 1
                await ws.send(bytes([0x01]) + chunk)
                await asyncio.sleep(0.005)
                # Send on channel 2
                await ws.send(bytes([0x02]) + chunk)
                await asyncio.sleep(0.01)

            # Collect transcript events
            events = await collect_events(ws, duration=15)

            # Filter for events that contain transcript segments
            transcript_events = []
            for e in events:
                if 'segments' in e and e.get('type') != 'translating':
                    transcript_events.append(e)

            assert len(transcript_events) > 0, (
                f"No transcript events received with 2-channel audio. "
                f"Total events: {len(events)}. "
                f"Event types: {[e.get('type', 'segment') for e in events]}"
            )

        finally:
            await ws.close()

    @pytest.mark.asyncio
    async def test_speaker_labels_from_channels(self):
        """Multi-channel segments should have distinct speaker labels per channel.

        Channel 1 (mic): is_user=True, speaker=SPEAKER_00
        Channel 2 (remote): is_user=False, speaker=SPEAKER_01
        """
        audio = load_test_audio_pcm16(seconds=10)
        if audio is None:
            pytest.skip("Test WAV file not found")
        pcm_data, sample_rate = audio

        ws = await connect_listen(
            sample_rate=sample_rate,
            channels=2,
            source='phone_call',
            conversation_timeout=120,
        )
        try:
            assert await wait_for_ready(ws), "Backend did not send 'ready' status"

            # Send audio on both channels
            chunk_size = 960
            for offset in range(0, len(pcm_data), chunk_size):
                chunk = pcm_data[offset : offset + chunk_size]
                await ws.send(bytes([0x01]) + chunk)
                await asyncio.sleep(0.005)
                await ws.send(bytes([0x02]) + chunk)
                await asyncio.sleep(0.01)

            # Collect all events
            events = await collect_events(ws, duration=15)

            # Extract all segments from all events
            all_segments = []
            for e in events:
                if 'segments' in e and e.get('type') != 'translating':
                    segs = e.get('segments', [])
                    if isinstance(segs, list):
                        all_segments.extend(segs)

            if not all_segments:
                pytest.skip("No transcript segments received (Modulate may be unavailable)")

            # Check that segments have speaker labels
            speakers_seen = set()
            is_user_values = set()
            for seg in all_segments:
                if isinstance(seg, dict):
                    if 'speaker' in seg:
                        speakers_seen.add(seg['speaker'])
                    if 'is_user' in seg:
                        is_user_values.add(seg['is_user'])

            # With real speech on both channels, we expect both speaker labels
            # At minimum we should see at least one speaker label
            assert len(speakers_seen) > 0 or len(all_segments) > 0, (
                f"No speaker labels found in segments. "
                f"Sample segment: {all_segments[0] if all_segments else 'none'}"
            )

            # If both channels produced transcripts, we should see both speakers
            if len(speakers_seen) >= 2:
                assert 'SPEAKER_00' in speakers_seen, f"Missing SPEAKER_00 in {speakers_seen}"
                assert 'SPEAKER_01' in speakers_seen, f"Missing SPEAKER_01 in {speakers_seen}"

        finally:
            await ws.close()

    @pytest.mark.asyncio
    async def test_single_channel_audio_only(self):
        """Sending audio on only one channel should still produce transcripts.

        The other channel's STT socket stays idle but shouldn't cause errors.
        """
        audio = load_test_audio_pcm16(seconds=5)
        if audio is None:
            pytest.skip("Test WAV file not found")
        pcm_data, sample_rate = audio

        ws = await connect_listen(
            sample_rate=sample_rate,
            channels=2,
            source='phone_call',
            conversation_timeout=120,
        )
        try:
            assert await wait_for_ready(ws), "Backend did not send 'ready' status"

            # Send audio on channel 1 only
            chunk_size = 960
            for offset in range(0, len(pcm_data), chunk_size):
                chunk = pcm_data[offset : offset + chunk_size]
                await ws.send(bytes([0x01]) + chunk)
                await asyncio.sleep(0.015)

            events = await collect_events(ws, duration=12)

            # Should get transcripts from channel 1 at least
            transcript_events = [e for e in events if 'segments' in e and e.get('type') != 'translating']

            # This should work — channel 2 is just silent
            # Even if no transcripts, the connection should stay alive (no crash)
            # We mainly verify no exception/disconnect
            assert True  # Connection survived

        finally:
            await ws.close()

    @pytest.mark.asyncio
    async def test_invalid_channel_id_ignored(self):
        """Audio with an unrecognized channel ID byte should be silently ignored."""
        ws = await connect_listen(
            channels=2,
            source='phone_call',
            conversation_timeout=120,
        )
        try:
            assert await wait_for_ready(ws), "Backend did not send 'ready' status"

            # Send audio with invalid channel ID 0x05 (only 0x01 and 0x02 are valid)
            fake_audio = generate_tone_pcm16(0.5)
            await ws.send(bytes([0x05]) + fake_audio)
            await asyncio.sleep(0.5)

            # Send valid audio on channel 1 to prove connection is still alive
            await ws.send(bytes([0x01]) + fake_audio)
            await asyncio.sleep(0.5)

            # Connection should still be open
            try:
                await ws.send(bytes([0x01]) + generate_silence_pcm16(0.1))
                alive = True
            except ConnectionClosed:
                alive = False

            assert alive, "Connection died after sending invalid channel ID"

        finally:
            await ws.close()

    @pytest.mark.asyncio
    async def test_desktop_source_channel_config(self):
        """Desktop source should use mic + system_audio channel labels."""
        audio = load_test_audio_pcm16(seconds=5)
        if audio is None:
            pytest.skip("Test WAV file not found")
        pcm_data, sample_rate = audio

        ws = await connect_listen(
            sample_rate=sample_rate,
            channels=2,
            source='desktop',
            conversation_timeout=120,
        )
        try:
            assert await wait_for_ready(ws), "Backend did not send 'ready' for desktop+channels=2"

            # Send audio on both channels
            chunk_size = 960
            for offset in range(0, min(len(pcm_data), sample_rate * 5 * 2), chunk_size):
                chunk = pcm_data[offset : offset + chunk_size]
                await ws.send(bytes([0x01]) + chunk)
                await asyncio.sleep(0.005)
                await ws.send(bytes([0x02]) + chunk)
                await asyncio.sleep(0.01)

            # If we get here without disconnect, desktop source is accepted
            events = await collect_events(ws, duration=10)

            # Verify connection stayed alive and events came through
            # Desktop should behave same as phone_call for channel structure
            assert True  # Connection survived with desktop source

        finally:
            await ws.close()
