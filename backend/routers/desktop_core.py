import os

from fastapi import APIRouter, Depends
from fastapi.responses import PlainTextResponse

from utils.other.endpoints import get_current_user_uid

router = APIRouter()

BACKEND_VERSION = "0.1.0"
BACKEND_SERVICE = "omi-backend"
CHAT_CONTRACT_VERSION = "2"


def health_response() -> dict[str, str]:
    return {
        "status": "healthy",
        "service": BACKEND_SERVICE,
        "version": BACKEND_VERSION,
        "chat_contract_version": CHAT_CONTRACT_VERSION,
    }


@router.get("/")
def health_check() -> dict[str, str]:
    return health_response()


@router.get("/v1/config/api-keys")
def get_api_keys(_: str = Depends(get_current_user_uid)) -> dict[str, str]:
    return {
        response_field: value
        for response_field, environment_name in (
            ("firebase_api_key", "FIREBASE_API_KEY"),
            ("google_calendar_api_key", "GOOGLE_CALENDAR_API_KEY"),
        )
        if (value := os.getenv(environment_name)) is not None
    }


@router.get("/.well-known/apple-developer-domain-association.txt", response_class=PlainTextResponse)
def apple_domain_association() -> str:
    return ""
