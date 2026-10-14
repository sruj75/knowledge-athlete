"""Bounded conversational compute contracts, independent of agent execution."""

from typing import Literal, Self

from pydantic import Field, model_validator

from models.desktop_ai import JPEGImage, OpaqueID, WireModel


class ConversationPromptReference(WireModel):
    name: Literal['intentive-live-system']
    version: str = Field(pattern=r'^(?:[1-9][0-9]{0,9}|conversation-v1)$')
    source: Literal['langfuse', 'fallback']
    sha256: str = Field(pattern=r'^[0-9a-f]{64}$')

    @model_validator(mode='after')
    def validate_source_version(self) -> Self:
        if (self.source == 'fallback') != (self.version == 'conversation-v1'):
            raise ValueError('prompt version does not match its source')
        return self


class ConversationPromptReceipt(ConversationPromptReference):
    text: str = Field(min_length=1, max_length=32000)

    def reference(self) -> ConversationPromptReference:
        return ConversationPromptReference.model_validate(self.model_dump(exclude={'text'}))


class ConversationSessionRequest(WireModel):
    conversation_id: OpaqueID


class ConversationSessionResponse(WireModel):
    conversation_id: OpaqueID
    prompt: ConversationPromptReceipt


class ConversationHistoryItem(WireModel):
    role: Literal['user', 'assistant']
    text: str = Field(min_length=1, max_length=4000)


class ConversationRespondRequest(WireModel):
    conversation_id: OpaqueID
    turn_id: OpaqueID
    prompt_ref: ConversationPromptReference
    history: list[ConversationHistoryItem] = Field(default_factory=list[ConversationHistoryItem], max_length=64)
    message: str = Field(min_length=1, max_length=12000)
    context: str = Field(default='', max_length=16000)
    guidance: str | None = Field(default=None, max_length=2000)
    image: JPEGImage | None = None


class RealtimeSessionResponse(WireModel):
    provider: Literal['gemini']
    token: str
    expires_at: str
    prompt: ConversationPromptReceipt
