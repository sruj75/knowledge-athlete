"""Protocol helpers for the temporary S-25 finalization control socket."""

import json
import struct
from typing import Any, Dict

from utils.observability.journeys import JourneyOutcome

MIN_SAMPLE_RATE = 8000
MAX_SAMPLE_RATE = 48000


def frame_header(data: bytes) -> int:
    """Return a retained control-frame header.

    S-23 retired audio, transcript, speaker-profile, and private-cloud product
    frames. Heartbeats (100) and durable-finalization requests (104) remain
    only until S-25 removes the operational Pusher topology.
    """
    if len(data) < 4:
        raise ValueError('frame header is incomplete')
    header_type = struct.unpack('<I', data[:4])[0]
    if header_type not in {100, 104}:
        raise ValueError('retired or unknown frame type')
    return header_type


def json_object(data: bytes) -> Dict[str, Any]:
    value = json.loads(bytes(data[4:]).decode('utf-8'))
    if not isinstance(value, dict):
        raise ValueError('frame payload must be an object')
    return value


def pusher_session_outcome(close_code: int, *, application_failed: bool = False) -> JourneyOutcome:
    """Classify accepted sessions without counting normal disconnects as failures."""
    if application_failed or close_code == 1011:
        return 'failure'
    if close_code in {1000, 1001}:
        return 'success'
    return 'cancelled'
