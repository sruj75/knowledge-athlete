from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

router = APIRouter()

_ROUTES = {
    "/v2/chat-context": ("POST",),
    "/v2/chat/initial-message": ("POST",),
    "/v2/chat/generate-title": ("POST",),
    "/v2/chat-sessions": ("GET", "POST"),
    "/v2/chat-sessions/{id}": ("GET", "PATCH", "DELETE"),
    "/v1/advice": ("GET", "POST"),
    "/v1/advice/{id}": ("PATCH", "DELETE"),
    "/v1/advice/mark-all-read": ("POST",),
    "/v1/focus-sessions": ("GET", "POST"),
    "/v1/focus-sessions/{id}": ("DELETE",),
    "/v1/focus-stats": ("GET",),
    "/v1/users/me/llm-usage": ("POST",),
    "/v1/users/me/llm-usage/total": ("GET",),
    "/v1/users/stats/chat-messages": ("GET",),
    "/v2/messages": ("GET", "POST", "DELETE"),
    "/v2/messages/{id}/rating": ("PATCH",),
    "/v1/users/daily-summary-settings": ("GET", "PATCH"),
    "/v1/users/language": ("GET", "PATCH"),
    "/v1/users/notification-settings": ("GET", "PATCH"),
    "/v1/users/profile": ("GET", "PATCH"),
    "/v1/users/ai-profile": ("GET", "PATCH"),
    "/v1/users/assistant-settings": ("GET", "PATCH"),
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
