from typing import Optional
import uuid
from datetime import datetime, timezone
from pydantic import BaseModel, Field


class NotificationMessage(BaseModel):
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    created_at: str = Field(default_factory=lambda: datetime.now(tz=timezone.utc).isoformat())
    sender: str = Field(default='ai')
    type: str
    notification_type: str
    text: Optional[str] = ""
    navigate_to: Optional[str] = None

    @staticmethod
    def get_message_as_dict(
        message: 'NotificationMessage',
    ) -> dict[str, object]:

        message_dict = message.model_dump()

        if message.navigate_to is None:
            del message_dict['navigate_to']

        return message_dict
