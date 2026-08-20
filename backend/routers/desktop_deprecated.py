from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

router = APIRouter()

_ROUTES = {
    "/v2/chat-context": ("POST",),
    "/v1/advice": ("GET", "POST"),
    "/v1/advice/{id}": ("PATCH", "DELETE"),
    "/v1/advice/mark-all-read": ("POST",),
    "/v1/users/me/llm-usage": ("POST",),
    "/v1/users/me/llm-usage/total": ("GET",),
    "/v1/users/language": ("GET", "PATCH"),
    "/v1/users/profile": ("GET", "PATCH"),
    "/v1/users/delete-account": ("DELETE",),
}


async def deprecated_handler(request: Request) -> JSONResponse:
    method = request.method
    path = request.url.path
    return JSONResponse(
        status_code=410,
        content={
            "error": "gone",
            "message": (
                f"This endpoint ({method} {path}) is deprecated and no longer served by the desktop backend. "
                "See https://api.omi.me for supported endpoints."
            ),
            "migration": "https://api.omi.me",
        },
    )


for route_path, route_methods in _ROUTES.items():
    router.add_api_route(route_path, deprecated_handler, methods=list(route_methods))
