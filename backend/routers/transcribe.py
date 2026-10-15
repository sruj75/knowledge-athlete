"""Authenticated transient managed-STT WebSocket route."""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends
from fastapi.websockets import WebSocket

from routers.listen.contracts import ListenContractError, ListenRequest, ListenSessionConfig
from routers.listen.runtime import run_listen_session
from utils.other import endpoints as auth

logger = logging.getLogger(__name__)

router = APIRouter()


def _coarse_platform(websocket: WebSocket) -> str:
    raw = websocket.headers.get("X-App-Platform", "unknown").strip().lower()
    normalized = "".join(character for character in raw if character.isalnum() or character in {"-", "_"})
    return normalized[:32] or "unknown"


@router.websocket("/v4/listen")
async def listen_handler(
    websocket: WebSocket,
    uid: str = Depends(auth.get_current_user_uid_ws_listen),
) -> None:
    try:
        config = ListenSessionConfig.from_query(websocket.query_params.multi_items())
    except ListenContractError as error:
        logger.info("Rejected listen session contract reason=%s", str(error))
        await websocket.close(code=1008, reason=str(error))
        return

    try:
        await websocket.accept()
    except RuntimeError as error:
        logger.warning("Listen accept failed type=%s", type(error).__name__)
        return

    await run_listen_session(
        ListenRequest(
            websocket=websocket,
            uid=uid,
            config=config,
            platform=_coarse_platform(websocket),
        )
    )
