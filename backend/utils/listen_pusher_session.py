"""Callerless S-25 handoff for the retained Pusher finalization control plane.

Slice 23 removes live transcript, audio, identity, and private-cloud product frames.
This module intentionally knows only how to deliver already-admitted durable
finalization jobs to the still-deployed Pusher service. Slice 25 owns deleting the
service topology after its backlog and rollback window are closed.
"""

from __future__ import annotations

import asyncio
import json
import logging
import struct
from dataclasses import dataclass
from typing import Any, Awaitable, Callable, Dict, Optional, Protocol, cast

from utils.observability.fallback import record_fallback
from utils.pusher import connect_to_trigger_pusher

logger = logging.getLogger(__name__)

FINALIZATION_REQUEST_HEADER = 104
FINALIZATION_RESULT_HEADER = 201


class PusherSocket(Protocol):
    async def send(self, data: bytes) -> None: ...

    async def recv(self) -> bytes: ...

    async def close(self) -> None: ...


@dataclass(frozen=True)
class ListenPusherSessionConfig:
    uid: str
    session_id: str
    sample_rate: int
    language: str
    max_pending_requests: int = 100


@dataclass(frozen=True)
class ListenPusherSessionDeps:
    on_conversation_processed: Callable[[str], None]
    connect_to_pusher: Callable[..., Awaitable[Optional[PusherSocket]]] = cast(
        Callable[..., Awaitable[Optional[PusherSocket]]], connect_to_trigger_pusher
    )


class ListenPusherSession:
    """Buffers and replays only S-25-owned durable finalization control frames."""

    def __init__(self, config: ListenPusherSessionConfig, deps: ListenPusherSessionDeps):
        self.config = config
        self.deps = deps
        self.pusher_ws: Optional[PusherSocket] = None
        self.pending_conversation_requests: Dict[str, Dict[str, Any]] = {}

    def _buffer(
        self,
        conversation_id: str,
        *,
        finalization_job_id: str,
        dispatch_generation: int,
    ) -> None:
        if (
            conversation_id not in self.pending_conversation_requests
            and len(self.pending_conversation_requests) >= self.config.max_pending_requests
        ):
            oldest_id = next(iter(self.pending_conversation_requests))
            del self.pending_conversation_requests[oldest_id]
            record_fallback(
                component='pusher',
                from_mode='durable_pending_buffer',
                to_mode='evicted_oldest_request',
                reason='capacity_full',
                outcome='degraded',
                log=logger,
            )
        self.pending_conversation_requests[conversation_id] = {
            'finalization_job_id': finalization_job_id,
            'dispatch_generation': dispatch_generation,
        }

    @staticmethod
    def _frame(conversation_id: str, language: str, pending: Dict[str, Any]) -> bytes:
        payload = {
            'conversation_id': conversation_id,
            'language': language,
            'finalization_job_id': pending['finalization_job_id'],
            'dispatch_generation': pending['dispatch_generation'],
        }
        return struct.pack('<I', FINALIZATION_REQUEST_HEADER) + json.dumps(payload).encode('utf-8')

    async def connect(self) -> bool:
        socket = await self.deps.connect_to_pusher(
            self.config.uid,
            self.config.sample_rate,
        )
        if socket is None:
            return False
        self.pusher_ws = socket
        for conversation_id, pending in self.pending_conversation_requests.items():
            await socket.send(self._frame(conversation_id, self.config.language, pending))
        return True

    async def request_conversation_processing(
        self,
        conversation_id: str,
        *,
        finalization_job_id: str,
        dispatch_generation: int,
    ) -> bool:
        self._buffer(
            conversation_id,
            finalization_job_id=finalization_job_id,
            dispatch_generation=dispatch_generation,
        )
        if self.pusher_ws is None:
            return False
        await self.pusher_ws.send(
            self._frame(conversation_id, self.config.language, self.pending_conversation_requests[conversation_id])
        )
        return True

    async def receive_once(self) -> None:
        if self.pusher_ws is None:
            raise RuntimeError('Pusher finalization control socket is not connected')
        message = await self.pusher_ws.recv()
        if len(message) < 4 or struct.unpack('<I', message[:4])[0] != FINALIZATION_RESULT_HEADER:
            raise ValueError('Unexpected Pusher control frame')
        result = json.loads(message[4:].decode('utf-8'))
        conversation_id = str(result.get('conversation_id') or '')
        if not conversation_id:
            raise ValueError('Pusher finalization result omitted conversation_id')
        if result.get('error') and not result.get('terminal'):
            return
        self.pending_conversation_requests.pop(conversation_id, None)
        if not result.get('error'):
            self.deps.on_conversation_processed(conversation_id)

    async def close(self) -> None:
        socket, self.pusher_ws = self.pusher_ws, None
        if socket is not None:
            await socket.close()
