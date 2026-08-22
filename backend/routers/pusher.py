"""Temporary S-25 finalization control socket.

S-23 removes every private-cloud audio and persistent-speaker frame. The
deployed socket remains only so S-25 can drain the finalization topology.
"""

import asyncio
import logging
import struct

from fastapi import APIRouter
from fastapi.websockets import WebSocket, WebSocketDisconnect
from starlette.websockets import WebSocketState

from utils.executors import start_background_task
from utils.metrics import PUSHER_ACTIVE_WS_CONNECTIONS
from utils.observability.journeys import JourneyAttempt
from utils.pusher_finalization import process_conversation_task
from utils.pusher_protocol import (
    MAX_SAMPLE_RATE,
    MIN_SAMPLE_RATE,
    frame_header,
    json_object,
    pusher_session_outcome,
)
from utils.readiness import ReadinessGate

logger = logging.getLogger(__name__)
router = APIRouter()

WS_RECEIVE_TIMEOUT = 300.0


async def _websocket_util_trigger(
    websocket: WebSocket,
    uid: str,
    sample_rate: int = 8000,
) -> None:
    try:
        await websocket.accept()
    except RuntimeError as error:
        logger.error(error)
        await websocket.close(code=1011, reason="Dirty state")
        return
    if not MIN_SAMPLE_RATE <= sample_rate <= MAX_SAMPLE_RATE:
        await websocket.close(code=1008, reason="Invalid sample rate")
        return
    if not ReadinessGate.is_serving():
        await websocket.close(code=1001)
        return

    journey_attempt = JourneyAttempt('pusher_session')
    close_code = 1000
    application_failed = False
    try:
        PUSHER_ACTIVE_WS_CONNECTIONS.inc()
        while True:
            data = await asyncio.wait_for(websocket.receive_bytes(), timeout=WS_RECEIVE_TIMEOUT)
            header_type = frame_header(data)
            if header_type == 100:
                continue
            if header_type != 104:
                raise ValueError('retired pusher product-data frame')

            payload = json_object(data)
            conversation_id = payload.get('conversation_id')
            language = payload.get('language', 'en')
            finalization_job_id = payload.get('finalization_job_id')
            dispatch_generation = payload.get('dispatch_generation')
            if not isinstance(conversation_id, str) or not conversation_id or not isinstance(language, str):
                raise ValueError('invalid finalization control frame')
            if finalization_job_id is not None and not isinstance(finalization_job_id, str):
                raise ValueError('invalid finalization job id')
            if dispatch_generation is not None and (
                isinstance(dispatch_generation, bool) or not isinstance(dispatch_generation, int)
            ):
                raise ValueError('invalid dispatch generation')

            start_background_task(
                process_conversation_task(
                    uid,
                    conversation_id,
                    language,
                    websocket,
                    finalization_job_id,
                    dispatch_generation,
                ),
                name=f'pusher_finalization:{uid}:{conversation_id}',
            )
    except asyncio.TimeoutError:
        close_code = 1011
        application_failed = True
    except (ValueError, struct.error, UnicodeDecodeError):
        close_code = 1003
    except WebSocketDisconnect as error:
        close_code = error.code or 1006
    except asyncio.CancelledError:
        close_code = 1006
        raise
    except Exception as error:
        logger.error('Pusher finalization socket failed: %s', error)
        close_code = 1011
        application_failed = True
    finally:
        PUSHER_ACTIVE_WS_CONNECTIONS.dec()
        journey_attempt.finish(pusher_session_outcome(close_code, application_failed=application_failed))
        if websocket.client_state == WebSocketState.CONNECTED:
            try:
                await websocket.close(code=close_code)
            except Exception as error:
                logger.error('Error closing WebSocket: %s', error)


@router.websocket('/v1/trigger/listen')
async def websocket_endpoint_trigger(
    websocket: WebSocket,
    uid: str,
    sample_rate: int = 8000,
) -> None:
    await _websocket_util_trigger(websocket, uid, sample_rate)
