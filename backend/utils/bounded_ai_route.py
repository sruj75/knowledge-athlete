"""Enforce the desktop AI packet limit before JSON validation allocates a body."""

from collections.abc import Callable, Coroutine
from typing import Any

from fastapi import HTTPException, Request, Response
from fastapi.routing import APIRoute
from starlette.types import Message


class BoundedAIRoute(APIRoute):
    def get_route_handler(self) -> Callable[[Request], Coroutine[Any, Any, Response]]:
        handler = super().get_route_handler()

        async def bounded(request: Request) -> Response:
            received = 0
            receive = request.receive

            async def bounded_receive() -> Message:
                nonlocal received
                message = await receive()
                if message['type'] == 'http.request':
                    received += len(message.get('body', b''))
                    if received > 4_000_000:
                        raise HTTPException(status_code=413, detail='Request body is too large')
                return message

            return await handler(Request(request.scope, receive=bounded_receive))

        return bounded
