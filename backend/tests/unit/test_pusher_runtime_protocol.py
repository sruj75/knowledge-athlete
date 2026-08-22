import asyncio
import json
import struct
from collections import deque
from unittest.mock import MagicMock

import pytest
from fastapi.websockets import WebSocketDisconnect
from starlette.websockets import WebSocketState

import routers.pusher as pusher


class FakeWebSocket:
    def __init__(self, frames=()):
        self.frames = deque(frames)
        self.client_state = WebSocketState.CONNECTED
        self.close_code = None

    async def accept(self):
        return None

    async def close(self, code=1000, reason=None):
        del reason
        self.close_code = code
        self.client_state = WebSocketState.DISCONNECTED

    async def receive_bytes(self):
        await asyncio.sleep(0)
        if self.frames:
            return self.frames.popleft()
        raise WebSocketDisconnect(1000)


@pytest.fixture(autouse=True)
def runtime(monkeypatch):
    monkeypatch.setattr(pusher, 'PUSHER_ACTIVE_WS_CONNECTIONS', MagicMock())


@pytest.mark.asyncio
@pytest.mark.parametrize('sample_rate', [0, 7999, 48001])
async def test_invalid_sample_rate_closes_with_policy_violation(sample_rate):
    websocket = FakeWebSocket()

    await pusher._websocket_util_trigger(websocket, 'uid', sample_rate)

    assert websocket.close_code == 1008


@pytest.mark.asyncio
@pytest.mark.parametrize('retired_frame', [101, 102, 103, 105])
async def test_retired_product_frames_are_rejected(retired_frame):
    websocket = FakeWebSocket([struct.pack('<I', retired_frame) + b'product-data'])

    await pusher._websocket_util_trigger(websocket, 'uid', 8000)

    assert websocket.close_code == 1003


@pytest.mark.asyncio
async def test_finalization_control_frame_keeps_s25_drain_functional(monkeypatch):
    started = MagicMock()
    monkeypatch.setattr(pusher, 'start_background_task', started)
    websocket = FakeWebSocket(
        [
            struct.pack('<I', 100),
            struct.pack('<I', 104)
            + json.dumps(
                {
                    'conversation_id': 'conversation-1',
                    'language': 'en',
                    'finalization_job_id': 'job-1',
                    'dispatch_generation': 2,
                }
            ).encode(),
        ]
    )

    await pusher._websocket_util_trigger(websocket, 'uid', 8000)

    assert websocket.close_code == 1000
    started.assert_called_once()
    started.call_args.args[0].close()
