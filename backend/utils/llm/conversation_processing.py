import logging
import unicodedata
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
from typing import Any, Dict, List, Optional, Tuple, cast

from langchain_core.output_parsers import PydanticOutputParser
from langchain_core.prompts import ChatPromptTemplate
from pydantic import BaseModel, Field

from models.structured import Event, Structured
from models.structured_extraction import StructuredExtraction
from .clients import get_workload_client, parser
from .discard_parser import DiscardConversation, LenientDiscardParser

logger = logging.getLogger(__name__)


class SpeakerIdMatch(BaseModel):
    speaker_id: int = Field(description="The speaker id assigned to the segment")


def _word_count(text: str) -> int:
    if not text:
        return 0
    cjk_chars = sum(1 for c in text if unicodedata.east_asian_width(c) in ('W', 'F', 'H'))
    if cjk_chars > len(text) * 0.3:
        return cjk_chars // 2
    return len(text.split())


def _content_str(response: Any) -> str:
    content = response.content
    return content if isinstance(content, str) else str(content)


def _coerce_structured(response: Structured | StructuredExtraction) -> Structured:
    if isinstance(response, StructuredExtraction):
        return response.to_structured()
    return response


def should_discard_conversation(
    transcript: str,
    duration_seconds: Optional[float] = None,
    *,
    raise_on_error: bool = False,
) -> bool:
    # If there's a long transcript, it's very unlikely we want to discard it.
    # This is a performance optimization to avoid unnecessary LLM calls.
    word_count = _word_count(transcript) if transcript and transcript.strip() else 0
    if word_count > 100:
        return False
    context_parts: List[str] = []
    if transcript and transcript.strip():
        context_parts.append(f"Transcript: ```{transcript.strip()}```")

    # If there is no transcript content to process, discard.
    if not context_parts:
        return True

    full_context = "\n\n".join(context_parts)

    # Add duration metadata so the LLM can make duration-aware decisions
    duration_context = ""
    if duration_seconds is not None:
        duration_context = f"\nConversation duration: {int(duration_seconds)} seconds. Word count: {word_count} words."
        if duration_seconds < 120:
            duration_context += (
                "\nNote: This is a very short conversation (under 2 minutes). "
                "Apply a higher bar for keeping — only KEEP if the content is clearly actionable "
                "(a specific task, reminder, name/person, appointment, or meaningful request like 'call mom' or 'buy milk'). "
                "Generic filler words, acknowledgments, or incomplete thoughts in short conversations should be discarded."
            )

    prompt_template = '''You will receive a transcript. Your task is to decide if this content is meaningful enough to be saved as a memory.

Task: Decide if the content should be saved as conversation summary.
{duration_context}

KEEP (output: discard = False) if the content contains any of the following:
• A task, request, or action item (e.g., "call John before 5", "buy groceries", "remind me to email Sarah").
• A decision, commitment, or plan.
• A question that requires follow-up.
• Personal facts, preferences, or details likely useful later (e.g., remembering a person, place, or object).
• An important event, social interaction, or significant moment with meaningful context or consequences.
• An insight, summary, or key takeaway that provides value.

DISCARD (output: discard = True) if the content is:
• Trivial conversation snippets (e.g., brief apologies, casual remarks, single-sentence comments without context).
• Very brief interactions (5-10 seconds) that lack actionable content or meaningful context.
• Casual acknowledgments, greetings, or passing comments that don't contain useful information (e.g., "okay", "hmm", "yeah sure", "sorry", "hello", "alright").
• Incomplete or fragmented speech that doesn't convey a clear meaning.
• Content that doesn't meet the KEEP criteria above.
• Feels like asking Siri or other AI assistant something in 1-2 sentences or using voice to type something in a chat for 5-10 seconds.

Return exactly one line:
discard = <True|False>

Content:
{full_context}

{format_instructions}'''.replace(
        '    ', ''
    ).strip()
    custom_parser = LenientDiscardParser(pydantic_object=DiscardConversation)
    prompt_values = {
        'full_context': full_context,
        'duration_context': duration_context,
        'format_instructions': custom_parser.get_format_instructions(),
    }

    prompt = cast(Any, ChatPromptTemplate).from_messages([prompt_template])
    chain = prompt | get_workload_client('conv_discard') | custom_parser
    try:
        response: DiscardConversation = chain.invoke(prompt_values)
        return response.discard

    except Exception:
        logger.error('Error determining conversation discard')
        if raise_on_error:
            raise RuntimeError('conversation discard compute failed') from None
        return False


# =============================================
#       SHARED CONVERSATION CONTEXT BUILDER
# =============================================


def _build_conversation_context(transcript: str) -> str:
    """Build the deterministic transcript-only context used by retained compute."""
    return f"Transcript: ```{transcript.strip()}```" if transcript and transcript.strip() else ''


def _local_started_at_iso(started_at: datetime, tz: Optional[str]) -> str:
    """Render the capture time as the user's local wall-clock for prompt date context (#4773).

    The LLM is unreliable at converting UTC to the user's timezone, which mislabels the time of day
    in titles and overviews. Convert deterministically here instead. Naive datetimes are treated as
    UTC; a missing or invalid timezone falls back to UTC.
    """
    try:
        user_tz = ZoneInfo(tz) if tz else timezone.utc
    except Exception:  # noqa: BLE001 - any unknown/invalid tz falls back to UTC
        user_tz = timezone.utc
    aware = started_at if started_at.tzinfo is not None else started_at.replace(tzinfo=timezone.utc)
    return aware.astimezone(user_tz).replace(tzinfo=None).isoformat()


def get_transcript_structure(
    transcript: str,
    started_at: datetime,
    language_code: str,
    tz: str,
    uid: str,
    output_language_code: Optional[str] = None,
) -> Structured:
    # Keep this import at the invocation boundary: selected unit tests load
    # this pure processing module in isolation without the full LLM package.
    from utils.llm.usage_tracker import Features, track_usage

    conversation_context = _build_conversation_context(transcript)
    if not conversation_context:
        return Structured()  # Should be caught by discard logic, but as a safeguard.

    response_language = output_language_code or language_code

    # First system message: task-specific instructions (static prefix enables cross-conversation caching)
    # NOTE: language instructions are in context_message (second message) to keep this prefix fully static.
    instructions_text = '''You are an expert content analyzer. Your task is to analyze the provided transcript and provide structure and clarity.

    For the title, Write a clear, compelling headline (≤ 10 words) that captures the central topic and outcome. Use Title Case, avoid filler words, and include a key noun + verb where possible (e.g., "Team Finalizes Q2 Budget" or "Family Plans Weekend Road Trip").
    For the overview, condense the content into a summary with the main topics discussed or scenes observed, making sure to capture the key points and important details.
    For the emoji, select a single emoji that vividly reflects the core subject, mood, or outcome of the content. Strive for an emoji that is specific and evocative, rather than generic (e.g., prefer 🎉 for a celebration over 👍 for general agreement, or 💡 for a new idea over 🧠 for general thought).

    For the category, classify the content into one of the available categories.

    For Calendar Events, apply strict filtering to include ONLY events that meet ALL these criteria:
    • **Confirmed commitment**: Not suggestions or "maybe" - actual scheduled events
    • **User involvement**: The user is expected to attend, participate, or take action
    • **Specific timing**: Has concrete date/time, not vague references like "sometime" or "soon"
    • **Important/actionable**: Missing it would have real consequences or impact

    INCLUDE these event types:
    • Meetings & appointments (business meetings, doctor visits, interviews)
    • Hard deadlines (project due dates, payment deadlines, submission dates)
    • Personal commitments (family events, social gatherings user committed to)
    • Travel & transportation (flights, trains, scheduled pickups)
    • Recurring obligations (classes, regular meetings, scheduled calls)

    EXCLUDE these:
    • Casual mentions ("we should meet sometime", "maybe next week")
    • Historical references (past events being discussed)
    • Other people's events (events user isn't involved in)
    • Vague suggestions ("let's grab coffee soon")
    • Hypothetical scenarios ("if we meet Tuesday...")

    {format_instructions}'''.replace(
        '    ', ''
    ).strip()

    # Second system message contains every per-conversation value, including timestamp.
    context_message = (
        'The content language is {language_code}. You MUST respond entirely in {response_language}.\n\n'
        'For date context, this content was captured at {started_at}, which is already the user\'s local time ({tz}). '
        'Interpret it as-is and describe times of day in the title and overview accordingly; do not re-interpret this '
        'timestamp as UTC.\n\nContent:\n{conversation_context}'
    )
    prompt = cast(Any, ChatPromptTemplate).from_messages(
        [
            ('system', instructions_text),
            ('system', context_message),
        ]
    )
    legacy_prompt_values = {
        'conversation_context': conversation_context,
        'language_code': language_code,
        'response_language': response_language,
        'started_at': _local_started_at_iso(started_at, tz),
        'tz': tz or 'UTC',
    }
    legacy_prompt_values['format_instructions'] = parser.get_format_instructions()

    with track_usage(uid, Features.CONVERSATION_STRUCTURE):
        structure_llm = get_workload_client('conv_structure')
        chain = prompt | structure_llm | parser
        response = _coerce_structured(chain.invoke(legacy_prompt_values))

    for event in response.events or []:
        if event.duration > 180:
            event.duration = 180
        event.created = False

    return response


def get_reprocess_transcript_structure(
    transcript: str,
    started_at: datetime,
    language_code: str,
    tz: str,
    output_language_code: Optional[str] = None,
) -> Structured:
    context_parts: List[str] = []
    if transcript and transcript.strip():
        context_parts.append(f"Transcript: ```{transcript.strip()}```")

    if not context_parts:
        return Structured()

    full_context = "\n\n".join(context_parts)
    response_language = output_language_code or language_code

    prompt_text = '''You are an expert content analyzer. Your task is to analyze the provided transcript and provide structure and clarity.
    The content language is {language_code}. You MUST respond entirely in {response_language}.

    For the title, generate a concise title from the current content. Do not reuse a previous title.
    For the overview, condense the content into a summary with the main topics discussed or scenes observed, making sure to capture the key points and important details.
    For the emoji, select a single emoji that vividly reflects the core subject, mood, or outcome of the content. Strive for an emoji that is specific and evocative, rather than generic (e.g., prefer 🎉 for a celebration over 👍 for general agreement, or 💡 for a new idea over 🧠 for general thought).

    For the category, classify the content into one of the available categories.

    For Calendar Events, apply strict filtering to include ONLY events that meet ALL these criteria:
    • **Confirmed commitment**: Not suggestions or "maybe" - actual scheduled events
    • **User involvement**: The user is expected to attend, participate, or take action
    • **Specific timing**: Has concrete date/time, not vague references like "sometime" or "soon"
    • **Important/actionable**: Missing it would have real consequences or impact
    
    INCLUDE these event types:
    • Meetings & appointments (business meetings, doctor visits, interviews)
    • Hard deadlines (project due dates, payment deadlines, submission dates)
    • Personal commitments (family events, social gatherings user committed to)
    • Travel & transportation (flights, trains, scheduled pickups)
    • Recurring obligations (classes, regular meetings, scheduled calls)
    
    EXCLUDE these:
    • Casual mentions ("we should meet sometime", "maybe next week")
    • Historical references (past events being discussed)
    • Other people's events (events user isn't involved in)
    • Vague suggestions ("let's grab coffee soon")
    • Hypothetical scenarios ("if we meet Tuesday...")
    
    For date context, this content was captured at {started_at}, which is already the user's local time ({tz}). Interpret it as-is and describe times of day in the title and overview accordingly; do not re-interpret this timestamp as UTC.

    Content:
    {full_context}

    {format_instructions}'''.replace(
        '    ', ''
    ).strip()

    prompt = cast(Any, ChatPromptTemplate).from_messages([('system', prompt_text)])
    structure_llm = get_workload_client('conv_structure')
    chain = prompt | structure_llm | parser

    response = _coerce_structured(
        chain.invoke(
            {
                'full_context': full_context,
                'format_instructions': parser.get_format_instructions(),
                'language_code': language_code,
                'response_language': response_language,
                'started_at': _local_started_at_iso(started_at, tz),
                'tz': tz or 'UTC',
            }
        )
    )

    for event in response.events or []:
        if event.duration > 180:
            event.duration = 180
        event.created = False

    return response
