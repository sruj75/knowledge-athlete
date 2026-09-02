from datetime import datetime
from enum import Enum
from typing import List, Literal, Optional, Union

from pydantic import BaseModel


class MessageSender(str, Enum):
    ai = 'ai'
    human = 'human'


class MessageType(str, Enum):
    text = 'text'


class MessageConversationStructured(BaseModel):
    title: str
    emoji: str


class MessageConversation(BaseModel):
    id: str
    structured: MessageConversationStructured
    created_at: datetime


class ChartDataPoint(BaseModel):
    label: str
    value: float


class ChartDataset(BaseModel):
    label: str
    data_points: List[ChartDataPoint]
    color: Optional[str] = None  # hex color, e.g. "#4CAF50"


class ChartData(BaseModel):
    chart_type: Literal['line', 'bar']
    title: str
    x_label: Optional[str] = None
    y_label: Optional[str] = None
    datasets: List[ChartDataset]


class Message(BaseModel):
    id: str
    text: str
    created_at: datetime
    sender: MessageSender
    type: MessageType
    memories_id: List[str] = []  # used in db
    memories: List[MessageConversation] = []  # used front facing
    reported: bool = False
    report_reason: Optional[str] = None
    chat_session_id: Optional[str] = None
    session_id: Optional[str] = None
    # Desktop journal compatibility fields. These are optional so the existing
    # message response remains readable by older clients while a new client can
    # reconcile the canonical turn identity and structured payload exactly.
    metadata: Optional[str] = None
    client_message_id: Optional[str] = None
    message_source: Optional[str] = None
    journal_revision: Optional[int] = None
    chart_data: Optional[Union[ChartData, dict]] = None  # Inline chart visualization data

    @classmethod
    def deserialize_many_safe(cls, records, on_error=None) -> List['Message']:
        """Build Message objects from raw stored records, skipping any that fail
        validation so one malformed or legacy chat message cannot 500 a whole history
        load. on_error(record, exception), when provided, is called for each skip."""
        parsed: List['Message'] = []
        for record in records:
            try:
                parsed.append(cls(**record))
            except Exception as exc:  # noqa: BLE001 - one bad record must not break the history
                if on_error is not None:
                    on_error(record, exc)
        return parsed

    @staticmethod
    def get_messages_as_string(
        messages: List['Message'],
        use_user_name_if_available: bool = False,
    ) -> str:
        sorted_messages = sorted(messages, key=lambda m: m.created_at)

        def get_sender_name(message: Message) -> str:
            if message.sender == 'human':
                return 'User'
            return message.sender.upper()

        formatted_messages = []
        for message in sorted_messages:
            msg_text = (
                f"({message.created_at.strftime('%d %b %Y at %H:%M UTC')}) {get_sender_name(message)}: {message.text}"
            )

            formatted_messages.append(msg_text)

        return '\n'.join(formatted_messages)

    @staticmethod
    def get_messages_as_xml(
        messages: List['Message'],
        use_user_name_if_available: bool = False,
    ) -> str:
        sorted_messages = sorted(messages, key=lambda m: m.created_at)

        def get_sender_name(message: Message) -> str:
            if message.sender == 'human':
                return 'User'
            return message.sender.upper()

        formatted_messages = []
        for message in sorted_messages:
            msg = f"""<message>
<created_at>{message.created_at.strftime('%d %b %Y at %H:%M UTC')}</created_at>
<sender>{get_sender_name(message)}</sender>
<content>{message.text}</content>
</message>"""

            # Only strip the block's surrounding whitespace. The template above is flush-left, so a
            # .replace('    ', '') here would instead delete 4-space runs from message.text (code,
            # tables, aligned or pasted text), corrupting the history shown to the LLM.
            formatted_messages.append(msg.strip())

        return '\n'.join(formatted_messages)
