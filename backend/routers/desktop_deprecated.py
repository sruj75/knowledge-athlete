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
    "/v1/goals": ("POST",),
    "/v1/goals/all": ("GET",),
    "/v1/goals/completed": ("GET",),
    "/v1/goals/{id}": ("PATCH", "DELETE"),
    "/v1/goals/{id}/progress": ("PATCH",),
    "/v1/goals/{id}/history": ("GET",),
    "/v1/daily-score": ("GET",),
    "/v1/scores": ("GET",),
    "/v1/users/me/llm-usage": ("POST",),
    "/v1/users/me/llm-usage/total": ("GET",),
    "/v1/users/stats/chat-messages": ("GET",),
    "/v2/messages": ("GET", "POST", "DELETE"),
    "/v2/messages/{id}/rating": ("PATCH",),
    "/v1/action-items": ("GET", "POST"),
    "/v1/action-items/batch": ("POST", "PATCH"),
    "/v1/action-items/batch-scores": ("PATCH",),
    "/v1/action-items/accept": ("POST",),
    "/v1/action-items/{id}": ("GET", "PATCH", "DELETE"),
    "/v1/action-items/{id}/soft-delete": ("POST",),
    "/v1/staged-tasks": ("GET", "POST"),
    "/v1/staged-tasks/batch-scores": ("PATCH",),
    "/v1/staged-tasks/promote": ("POST",),
    "/v1/staged-tasks/migrate": ("POST",),
    "/v1/staged-tasks/migrate-conversation-items": ("POST",),
    "/v1/staged-tasks/{id}": ("DELETE",),
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
