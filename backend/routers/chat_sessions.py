"""Stateless Chat greeting and title compute for the local desktop authority."""

from typing import Annotated, Any, Callable, cast

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from models.chat_session import (
    GenerateTitleResponse,
    InitialMessageResponse,
)
from utils.llm.clients import bind_llm_output_token_limit, get_llm
from utils.llm.usage_tracker import Features, track_usage
from utils.other import endpoints as auth

router = APIRouter()

_GREETING_MAX_OUTPUT_TOKENS = 96
_TITLE_MAX_OUTPUT_TOKENS = 32
_GREETING_MAX_CHARACTERS = 500
_TITLE_MAX_CHARACTERS = 120

# `utils.other.endpoints.with_rate_limit` has an untyped `auth_dependency`
# parameter; route access through a cast so this strict-checked file sees a
# concrete callable type instead of `Unknown`.
_auth_module = cast(Any, auth)


# ============================================================================
# MODELS
# ============================================================================


class InitialMessageRequest(BaseModel):
    profile_text: str = Field(default='', max_length=8_000)
    memories: list[Annotated[str, Field(max_length=1_000)]] = Field(default_factory=list, max_length=20)


class GenerateTitleRequest(BaseModel):
    user_text: str = Field(..., min_length=1, max_length=12_000)
    assistant_text: str = Field(..., min_length=1, max_length=12_000)


# ============================================================================
# CHAT AI ENDPOINTS (migrated from Rust desktop backend)
# ============================================================================


@router.post('/v2/chat/initial-message', tags=['chat-sessions'], response_model=InitialMessageResponse)
def create_initial_message(
    request: InitialMessageRequest,
    uid: str = Depends(
        cast(Callable[..., str], _auth_module.with_rate_limit(auth.get_current_user_uid, "chat:initial"))
    ),
):
    """Compute a greeting from bounded Mac-owned context without product-data access."""
    memories = '\n'.join(f'- {memory}' for memory in request.memories)
    prompt = f"""
You are Omi, a friendly and helpful assistant who aims to make the user's life better 10x.

Approved local profile:
{request.profile_text or 'No profile is available yet.'}

Approved local memories:
{memories or '- No memories are available yet.'}

Compose a short, warm, engaging welcome that starts the conversation naturally. Light humor is welcome when
appropriate. Do not say that you are an assistant or that this is an initial message. Return only the message.
""".strip()
    with track_usage(uid, Features.CHAT):
        response = cast(
            Any,
            bind_llm_output_token_limit('chat_greeting', get_llm('chat_greeting'), _GREETING_MAX_OUTPUT_TOKENS).invoke(
                prompt
            ),
        )
    message = str(response.content).strip()
    if not message:
        raise HTTPException(status_code=502, detail='Greeting generation returned no message')
    if len(message) > _GREETING_MAX_CHARACTERS:
        raise HTTPException(status_code=502, detail='Greeting generation exceeded the output limit')
    return {'message': message}


@router.post('/v2/chat/generate-title', tags=['chat-sessions'], response_model=GenerateTitleResponse)
def generate_session_title(
    request: GenerateTitleRequest,
    uid: str = Depends(
        cast(Callable[..., str], _auth_module.with_rate_limit(auth.get_current_user_uid, "chat:initial"))
    ),
):
    """Compute a title from the first real local exchange without storing it."""
    conversation = f"human: {request.user_text}\nai: {request.assistant_text}"
    prompt = (
        "Generate a short, descriptive title (max 6 words) for this chat conversation. "
        "Return ONLY the title text, no quotes or punctuation.\n\n"
        f"{conversation}"
    )
    # `BaseChatModel.invoke(...).content` is typed `str | list[str | dict]` by
    # langchain's stubs; session-title responses are plain strings, so reach
    # the response through `Any` and annotate the result as `str`.
    with track_usage(uid, Features.CHAT):
        response = cast(
            Any,
            bind_llm_output_token_limit('session_titles', get_llm('session_titles'), _TITLE_MAX_OUTPUT_TOKENS).invoke(
                prompt
            ),
        )
    title: str = response.content.strip().strip('"\'')
    if not title:
        title = 'New Chat'
    if len(title) > _TITLE_MAX_CHARACTERS:
        raise HTTPException(status_code=502, detail='Title generation exceeded the output limit')

    return {'title': title}
