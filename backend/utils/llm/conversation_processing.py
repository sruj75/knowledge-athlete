import logging
import unicodedata
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from typing import Any, Dict, List, Optional, Tuple, cast

from langchain_core.output_parsers import PydanticOutputParser
from langchain_core.prompts import ChatPromptTemplate
from pydantic import BaseModel, Field

from models.structured import ActionItem, Event, Structured
from models.structured_extraction import ActionItemsExtraction, StructuredExtraction
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


def _coerce_action_items(response: ActionItemsExtraction) -> List[ActionItem]:
    return response.to_action_items()


def _content_str(response: Any) -> str:
    content = response.content
    return content if isinstance(content, str) else str(content)


def _coerce_structured(response: Structured | StructuredExtraction) -> Structured:
    if isinstance(response, StructuredExtraction):
        return response.to_structured()
    return response


def _normalize_action_item_due_dates(
    action_items: List[ActionItem],
    *,
    user_tz: Any,
    now: datetime,
    log_past_due_clears: bool,
) -> List[ActionItem]:
    for action_item in action_items:
        if action_item.due_at is None:
            continue
        if action_item.due_at.tzinfo is None:
            action_item.due_at = action_item.due_at.replace(tzinfo=user_tz).astimezone(timezone.utc)
        else:
            action_item.due_at = action_item.due_at.astimezone(timezone.utc)
        if action_item.due_at < now - timedelta(days=1):
            if log_past_due_clears:
                logger.warning('Clearing action-item due date outside the retained time boundary')
            action_item.due_at = None
    return action_items


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


def extract_action_items(
    transcript: str,
    started_at: datetime,
    language_code: str,
    tz: str,
    existing_action_items: Optional[List[Dict[str, Any]]] = None,
    output_language_code: Optional[str] = None,
    raise_on_error: bool = False,
) -> List[ActionItem]:
    """
    Dedicated function to extract action items from conversation content.

    Args:
        transcript: Conversation transcript
        started_at: When the conversation started
        language_code: Language code for the conversation
        tz: User's timezone
        existing_action_items: Open action items semantically related to this
            conversation (top vector matches, recently active). Caller is
            expected to pre-filter to open items only; this function defends
            in depth by skipping any item that arrives marked completed.

    Returns:
        List of extracted ActionItem objects
    """
    conversation_context = _build_conversation_context(transcript)
    if not conversation_context:
        return []

    existing_items_context = ""
    if existing_action_items:
        items_list: List[str] = []
        for item in existing_action_items:
            # Defensive: the rendered section is "OPEN TASKS"; a completed item
            # leaking through (e.g. a future caller that doesn't pre-filter)
            # would mislead the LLM into suppressing valid new tasks.
            if item.get('completed', False):
                continue
            desc = item.get('description', '')
            due = item.get('due_at')
            due_str = due.strftime('%Y-%m-%d %H:%M UTC') if due else 'No due date'
            task_id = item.get('id')
            id_prefix = f"ID {task_id}: " if task_id else ''
            items_list.append(f"  • {id_prefix}{desc} (Due: {due_str})")

        if items_list:
            existing_items_context = (
                f"\n\nPOTENTIALLY RELATED OPEN TASKS — recently active, semantically similar ({len(items_list)} items):\n"
                + "\n".join(items_list)
            )

    commitment_capture_rules = '''COMMITMENT CAPTURE:
    • Extract a concrete future commitment even when phrased as "I will" or "I'll do it".
    • Skip only work demonstrably completed in the current moment; an immediate but still-open commitment is capturable.
    • For every item set capture_kind to exactly one of explicit_command, clear_commitment, direct_request, inferred_next_step.
    • Set capture_owner to user, other, or unknown and emit capture_confidence and ownership_confidence from 0 to 1.
    • A concrete request addressed directly to the primary user has capture_kind=direct_request,
      capture_owner=user, and high ownership_confidence. Use unknown only when the addressee is genuinely unclear.
    • A request addressed to someone else or broadcast without a direct mention is not owned by the primary user.
    • Set concrete_deliverable true only when the commitment names a specific deliverable or outcome; vague "I'll handle it" is false.'''
    workflow_filter_rules = '''3. THIRD: Select only concrete, useful actions:
       - Extract explicit commands, direct requests, and clear future commitments even when work is about to start.
       - Do not skip solely because the user says "I'll", "let me", or is beginning the work now.
       - Skip work only when the transcript demonstrates it is already complete.
       - NEVER extract multiple items about the same topic from a single conversation.'''
    live_work_exclusion_rules = '''• Work demonstrably completed in the transcript (ongoing or about-to-start work remains eligible)
    • Past actions being discussed without an open follow-up'''
    completion_targeting_rule = '''• If the user says an existing supplied task is done, emit candidate_action=complete with that exact
      target_task_id. Do not create a new item for completed work.'''
    quality_threshold_rules = '''• Always extract concrete explicit commands, direct requests, and clear commitments.
    • Be conservative only with model-inferred next steps.'''
    strict_filter_intro = (
        'STRICT FILTERING RULES - ownership and a concrete action are required; timing and importance are signals:'
    )
    timing_importance_rules = '''3. **Timing Signal**: Capture timing when present, but do not require a deadline for a concrete explicit
       command, direct request, or clear commitment.

    4. **Importance Signal**: Consequences increase confidence, but a concrete direct request remains eligible
       without high stakes. Use importance to filter only inferred or vague next steps.'''

    # First system message: task-specific instructions (static prefix enables cross-conversation caching)
    # NOTE: {language_code} is in the context message, not here, to keep this prefix fully static across all languages.
    instructions_text = '''You are an expert action item extractor. Your sole purpose is to identify and extract high-quality, actionable tasks from the provided content.

    DEDUPLICATION RULES — be conservative about suppressing:
    • The "POTENTIALLY RELATED OPEN TASKS" section lists open items recently active in the user's task list, semantically similar to this conversation. They may or may not be true duplicates.
    • Only suppress a candidate if you are 100% confident the existing task captures this EXACT intent and the user is just re-mentioning it (not re-doing it).
    • EXTRACT (do not suppress) when the user signals re-occurrence or distinct scope:
      - Re-occurrence cues: "again", "another", "still need to", "I forgot to", "more", "one more"
      - Different person, scope, or deadline ("Submit report by March 1" vs "Submit report by April 15" — different deadlines, both valid)
      - Existing item describes a one-off task that's already in progress; user is starting a new instance
    {completion_targeting_rule}
    • Examples of true DUPLICATES (suppress):
      - "Call John" said today, existing open "Call John" from this morning, no new context → DUPLICATE
      - "Email Sarah about meeting" said today, existing "Email Sarah about meeting" still open → DUPLICATE (same intent re-mentioned)
    • Examples of NOT duplicates (extract anyway):
      - Existing: "Buy milk" (open). User says "I need to buy more milk" → EXTRACT (re-occurrence cue)
      - Existing: "Submit report by March 1" (open). User says "Submit report by April 15" → EXTRACT (different deadline)
      - Existing: "Call dentist" (open). User says "Call plumber" → EXTRACT (different scope)
    • When unsure → EXTRACT. A duplicate the user can delete is recoverable; a silently-suppressed real task is not.
    • SINGLE-TOPIC LIMIT: Within THIS conversation, extract AT MOST 1 action item per topic — not one per variation, option, or detail. (This rule applies within the current transcript, not across conversations.)

    WORKFLOW:
    1. FIRST: Read the ENTIRE conversation carefully to understand the full context
    2. SECOND: Identify all topics, people, places, or things being discussed
    {workflow_filter_rules}
    4. FOURTH: Extract ONLY action items that passed step 3, using specific names/details
    5. FIFTH: Extract timing information separately and put it in the due_at field
    6. SIXTH: Clean the description - remove ALL time references and vague words
    7. SEVENTH: Final check - description should be timeless and specific (e.g., "Buy groceries" NOT "buy them by tomorrow")

    CRITICAL CONTEXT:
    • These action items are primarily for the PRIMARY USER who is having/recording this conversation
    • The user is the person wearing the device or initiating the conversation
    • Focus on tasks the primary user needs to track and act upon
    • Include tasks for OTHER people ONLY if:
      - The primary user is dependent on that task being completed
      - It's super crucial for the primary user to track it
      - The primary user needs to follow up on it

    QUALITY OVER QUANTITY:
    • Better to have 0 action items than to flood the user with unnecessary ones
    {quality_threshold_rules}
    • Think: "Would a busy person want to be reminded of this?"

    {strict_filter_intro}

    1. **Clear Ownership & Relevance to Primary User**:
       - Identify which speaker is the primary user based on conversational context
       - Look for cues: who is asking questions, who is receiving advice/tasks, who initiates topics
       - For tasks assigned to the primary user: phrase them directly (start with verb)
       - For tasks assigned to others: include them ONLY if primary user is dependent on them or needs to track them
       - NEVER use "Speaker 0", "Speaker 1", etc. in the final action item description
       - If unsure about names, use natural phrasing like "Follow up on...", "Ensure...", etc.

    2. **Concrete Action**: The task describes a specific, actionable next step (not vague intentions)

    {timing_importance_rules}

    5. **Commitment state**:
       {commitment_capture_rules}
       - "I want to X" → SKIP unless paired with a concrete deadline
       - Always extract a real future deadline that could be forgotten.

    EXCLUDE these types of items (be aggressive about exclusion):
    {live_work_exclusion_rules}
    • Casual mentions or updates ("I'm working on X", "currently doing Y")
    • Vague suggestions without commitment ("we should grab coffee sometime", "let's meet up soon")
    • Casual mentions without commitment ("maybe I'll check that out")
    • General goals without specific next steps ("I need to exercise more")
    • Hypothetical scenarios ("if we do X, then Y")
    • Trivial tasks with no real consequences
    • Tasks assigned to others that don't impact the primary user
    • Routine daily activities the user already knows about
    • Things that are obvious or don't need a reminder
    • Updates or status reports about ongoing work

    FORMAT REQUIREMENTS:
    • Keep each action item SHORT and concise (maximum 15 words, strict limit)
    • Use clear, direct language
    • Start with a verb when possible (e.g., "Call", "Send", "Review", "Pay", "Open", "Submit", "Finish", "Complete")
    • Include only essential details

    • CRITICAL - Resolve ALL vague references:
      - Read the ENTIRE conversation to understand what is being discussed
      - If you see vague references like:
        * "the feature" → identify WHAT feature from conversation
        * "this project" → identify WHICH project from conversation
        * "that task" → identify WHAT task from conversation
        * "it" → identify what "it" refers to from conversation
      - Look for keywords, topics, or subjects mentioned earlier in the conversation
      - Replace ALL vague words with specific names from the conversation context
      - Examples:
        * User says: "planning Sarah's birthday party" then later "buy decorations for it"
          → Extract: "Buy decorations for Sarah's birthday party"
        * User says: "car making weird noise" then later "take it to mechanic"
          → Extract: "Take car to mechanic"
        * User says: "quarterly sales report" then later "send it to the team"
          → Extract: "Send quarterly sales report to team"

    • CRITICAL - Remove time references from description (they go in due_at field):
      - NEVER include timing words in the action item description itself
      - Remove: "by tomorrow", "by evening", "today", "next week", "by Friday", etc.
      - The timing information is captured in the due_at field separately
      - Focus ONLY on the action and what needs to be done
      - Examples:
        * "buy groceries by tomorrow" → "Buy groceries"
        * "call dentist by next Monday" → "Call dentist"
        * "pay electricity bill by Friday" → "Pay electricity bill"
        * "submit insurance claim today" → "Submit insurance claim"
        * "book flight tickets by evening" → "Book flight tickets"

    • Remove filler words and unnecessary context
    • Merge duplicates
    • Order by: due date → urgency → alphabetical

    CANONICAL TARGETING (only when canonical task-intelligence mode is active):
    • Set candidate_action to create, update, or complete.
    • For update/complete, target_task_id MUST exactly match an ID shown in POTENTIALLY RELATED OPEN TASKS.
    • Never invent a task ID. If no supplied ID is an exact target, use candidate_action=create and omit target_task_id.

    DUE DATE EXTRACTION:
    Resolve each due date in the user's LOCAL time. NEVER produce a past date.

    {format_instructions}'''.replace(
        '    ', ''
    ).strip()

    response_language = output_language_code or language_code
    action_items_parser = PydanticOutputParser(pydantic_object=ActionItemsExtraction)
    # Second system message: conversation context + existing items (dynamic, per-conversation)
    context_message = '''The content language is {language_code}. You MUST respond entirely in {response_language}.

    DUE DATE EXTRACTION:
    REFERENCE_TIME (user's local time): If {started_at_local} is >7 days before {current_time_local}, use {current_time_local} (historical reprocessing). Otherwise use {started_at_local}.
    Date resolution: "today" → REFERENCE_TIME date, "tomorrow" → next day, weekday names → next occurrence, "next week" → +7 days.
    Time resolution: "morning" → 9AM, "afternoon" → 2PM, "evening" → 6PM, "noon" → 12PM, "end of day"/"midnight" → 11:59PM, no time → 11:59PM. "urgent"/"ASAP" → 2h from REFERENCE_TIME.
    Output the resolved value as the user's LOCAL wall-clock time in ISO 8601 with NO timezone suffix or offset (no 'Z', no '+05:30') — the server converts it to UTC. Verify it is in the future relative to REFERENCE_TIME; if past, omit due_at.
    Example: REFERENCE_TIME "2025-10-03T13:25:00", "tomorrow before 10am" → "2025-10-04T10:00:00"
    Format: naive local ISO 8601, no suffix (e.g., "2025-10-04T10:00:00").
    Conversation started at (local): {started_at_local}
    Current time (local): {current_time_local}
    User timezone: {tz}

    Content:
    {conversation_context}{existing_items_context}'''
    prompt = cast(Any, ChatPromptTemplate).from_messages(
        [
            ('system', instructions_text),
            ('system', context_message),
        ]
    )
    action_items_llm = get_workload_client('conv_action_items')
    chain = prompt | action_items_llm | action_items_parser

    current_time = datetime.now(timezone.utc)

    # Resolve the user's timezone once; fall back to UTC on an invalid/missing tz (and log it).
    # The LLM emits naive LOCAL wall-clock due dates (see prompt); we convert them to UTC here
    # deterministically instead of trusting the model to do the timezone math (the cause of #7059).
    try:
        user_tz = ZoneInfo(tz) if tz else timezone.utc
    except Exception:
        logger.warning(f'Invalid timezone {tz!r} for action item extraction; falling back to UTC')
        user_tz = timezone.utc

    started_at_local = (started_at if started_at.tzinfo else started_at.replace(tzinfo=timezone.utc)).astimezone(
        user_tz
    )
    current_time_local = current_time.astimezone(user_tz)
    prompt_values = {
        'conversation_context': conversation_context,
        'language_code': language_code,
        'response_language': response_language,
        'started_at_local': started_at_local.replace(tzinfo=None).isoformat(),
        'current_time_local': current_time_local.replace(tzinfo=None).isoformat(),
        'tz': tz or 'UTC',
        'existing_items_context': existing_items_context,
    }
    prompt_values.update(
        {
            'format_instructions': action_items_parser.get_format_instructions(),
            'commitment_capture_rules': commitment_capture_rules,
            'workflow_filter_rules': workflow_filter_rules,
            'live_work_exclusion_rules': live_work_exclusion_rules,
            'completion_targeting_rule': completion_targeting_rule,
            'quality_threshold_rules': quality_threshold_rules,
            'strict_filter_intro': strict_filter_intro,
            'timing_importance_rules': timing_importance_rules,
        }
    )

    try:
        response = chain.invoke(prompt_values)
        action_items = _coerce_action_items(response)

        # Set created_at for action items if not already set
        now = current_time
        for action_item in action_items:
            if action_item.created_at is None:
                action_item.created_at = now
        # The LLM returns naive LOCAL time; convert to UTC deterministically (and normalize any
        # tz-aware value), then clear due dates more than 1 day in the past.
        _normalize_action_item_due_dates(action_items, user_tz=user_tz, now=now, log_past_due_clears=True)

        return action_items

    except Exception:
        logger.error('Error extracting action items')
        if raise_on_error:
            raise
        return []


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
