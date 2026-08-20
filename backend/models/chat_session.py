"""Response wire shapes for stateless desktop Chat compute."""

from pydantic import BaseModel, Field


class InitialMessageResponse(BaseModel):
    """Response for ``POST /v2/chat/initial-message``."""

    message: str = Field(max_length=500, description='Generated greeting message text.')


class GenerateTitleResponse(BaseModel):
    """Response for ``POST /v2/chat/generate-title``."""

    title: str = Field(max_length=120, description='Generated session title.')
