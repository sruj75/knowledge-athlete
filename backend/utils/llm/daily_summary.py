from __future__ import annotations

import json
import logging
import re
import uuid
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, cast

import pytz
from pydantic import ValidationError

import database.users as users_db
from models.conversation import Conversation
from models.daily_summary_payload import DailySummaryPayload
from models.other import Person
from utils.conversations.render import conversations_to_string
from utils.llm.clients import get_llm
from utils.llm.usage_tracker import Features, track_usage
from utils.llms.memory import get_prompt_memories
from utils.log_sanitizer import sanitize, sanitize_validation_error

logger = logging.getLogger(__name__)


def _content_str(response: Any) -> str:
    content = response.content
    return content if isinstance(content, str) else str(content)


def _basic_daily_summary(
    date_str: str,
    total_conversations: int,
    total_duration_minutes: float,
    locations: List[Dict[str, Any]],
) -> Dict[str, Any]:
    return {
        "id": str(uuid.uuid4()),
        "date": date_str,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "headline": "Your Day in Review",
        "overview": f"You had {total_conversations} conversations today.",
        "day_emoji": "📅",
        "stats": {
            "total_conversations": total_conversations,
            "total_duration_minutes": int(total_duration_minutes),
        },
        "highlights": [],
        "unresolved_questions": [],
        "decisions_made": [],
        "knowledge_nuggets": [],
        "locations": locations,
    }


def generate_comprehensive_daily_summary(
    uid: str,
    conversations: List[Conversation],
    date_str: str,
    start_date_utc: Optional[datetime] = None,
    end_date_utc: Optional[datetime] = None,
) -> Dict[str, Any]:
    """
    Generate a comprehensive daily summary with structured data for storage.

    Returns a dictionary matching the DailySummary model structure.
    """
    # Get user's timezone
    user_profile = users_db.get_user_profile(uid)
    user_tz_str = user_profile.get('time_zone', 'UTC')
    try:
        user_tz = pytz.timezone(user_tz_str)
    except Exception:
        user_tz = pytz.UTC

    user_name, memories_str = get_prompt_memories(uid)

    # Get user's language preference for generating summary in their language
    output_language = user_profile.get('language', '') or 'en'

    all_person_ids: List[str] = []
    for m in conversations:
        all_person_ids.extend(m.get_person_ids())

    people: List[Person] = []
    if all_person_ids:
        people_data = users_db.get_people_by_ids(uid, list(set(all_person_ids)))
        people = [Person(**p) for p in people_data]

    conversation_history = conversations_to_string(conversations, people=people)

    # Calculate stats - exclude discarded conversations
    non_discarded = [c for c in conversations if not c.discarded]
    total_conversations = len(non_discarded)
    total_duration_minutes = sum(
        (c.finished_at - c.started_at).total_seconds() / 60 for c in non_discarded if c.finished_at and c.started_at
    )

    # Extract ALL locations from non-discarded conversations.
    # latitude/longitude are required floats on the Geolocation model, so guarding on
    # their truthiness wrongly drops a valid coordinate of exactly 0.0 (for example
    # longitude 0.0 on the prime meridian). Guard on the geolocation's presence instead.
    locations: List[Dict[str, Any]] = []
    for c in non_discarded:
        if c.geolocation:
            # Convert UTC time to user's local timezone
            local_time = None
            if c.started_at:
                utc_time = c.started_at
                if utc_time.tzinfo is None:
                    utc_time = pytz.UTC.localize(utc_time)
                local_time = utc_time.astimezone(user_tz).strftime("%H:%M")
            locations.append(
                {
                    "latitude": c.geolocation.latitude,
                    "longitude": c.geolocation.longitude,
                    "address": c.geolocation.address,
                    "conversation_id": c.id,
                    "time": local_time,
                }
            )

    # Build conversation ID mapping for the LLM
    convo_id_map = {i + 1: c.id for i, c in enumerate(non_discarded)}

    prompt = f"""You are creating a daily summary for {user_name}. {memories_str}
OUTPUT LANGUAGE: {output_language}. You MUST write every word of this summary in {output_language}, regardless of the language the conversations are in.

Today's date: {date_str}
Conversations: {total_conversations}

Here are {user_name}'s conversations from today (numbered 1-{total_conversations}):
```
{conversation_history}
```

Generate a JSON response. ONLY include sections with genuinely useful content - skip sections entirely if data is thin or low quality.

{{
    "headline": "Catchy one-liner (max 8 words)",
    "overview": "2-3 snappy lines. Crisp, insightful, no fluff.",
    "day_emoji": "Single emoji",
    "highlights": [
        {{
            "topic": "Short topic name",
            "emoji": "🎯",
            "summary": "One crisp sentence.",
            "conversation_numbers": [1, 2]
        }}
    ],
    "unresolved_questions": [
        {{
            "question": "Short question that wasn't answered",
            "conversation_number": 1
        }}
    ],
    "decisions_made": [
        {{
            "decision": "Short decision or conclusion",
            "conversation_number": 1
        }}
    ],
    "knowledge_nuggets": [
        {{
            "insight": "Short interesting fact or tip learned",
            "conversation_number": 1
        }}
    ]
}}

RULES:
- highlights: Max 4. One sentence each.
- unresolved_questions: Max 3. Short, punchy questions only. Keep each question short and snappy, less than 15 words.
- decisions_made: Max 3. Concrete decisions only. Only add here if it is something that the user has decided on. Tasks or action items don't belong here. Keep each decision short and snappy, less than 15 words.
- knowledge_nuggets: Max 3. Genuinely interesting learnings. Learnings are new learnings for the user, not something they might have already known. Shouldn't be very generic, should be a very specific learning. Keep each learning short and snappy, less than 15 words.
- conversation_number: Reference which conversation (1-{total_conversations}) it came from.
- SKIP sections entirely if no quality content.
- Be snappy. No fluff. No corporate speak. Only include sections that are genuinely useful and relevant.
- OUTPUT LANGUAGE: Every word — headline, overview, highlights, questions, decisions, knowledge nuggets — MUST be in {output_language}. Do not use any other language.

Respond with ONLY valid JSON. Do not include any other text or comments."""

    try:
        with track_usage(uid, Features.DAILY_SUMMARY):
            response = _content_str(get_llm('daily_summary', cache_key='omi-daily-summary').invoke(prompt))
        # Clean up response - remove markdown if present
        response = response.strip()
        if response.startswith('```'):
            response = response.split('```')[1]
            if response.startswith('json'):
                response = response[4:]
        response = response.strip()

        # Try to repair common JSON issues from LLM
        response = re.sub(r':\s*\\"([^"]*)\\"', r': "\1"', response)
        response = response.replace('\\"', '"')

        summary_data = DailySummaryPayload.model_validate(json.loads(response))

        # Helper to map conversation number to ID
        def get_convo_id(num: Any):
            if num and isinstance(num, int) and num in convo_id_map:
                return convo_id_map[num]
            return None

        # Process highlights - map conversation_numbers to conversation_ids
        highlights: List[Dict[str, Any]] = []
        for h in summary_data.highlights:
            convo_nums = h.conversation_numbers
            convo_ids = [get_convo_id(n) for n in convo_nums if get_convo_id(n)]
            highlights.append(
                {
                    "topic": h.topic,
                    "emoji": h.emoji or "💡",
                    "summary": h.summary,
                    "conversation_ids": convo_ids,
                }
            )

        # Process unresolved questions
        unresolved_questions: List[Dict[str, Any]] = []
        for q in summary_data.unresolved_questions:
            unresolved_questions.append(
                {"question": q.question, "conversation_id": get_convo_id(q.conversation_number)}
            )

        # Process decisions made
        decisions_made: List[Dict[str, Any]] = []
        for d in summary_data.decisions_made:
            decisions_made.append({"decision": d.decision, "conversation_id": get_convo_id(d.conversation_number)})

        # Process knowledge nuggets
        knowledge_nuggets: List[Dict[str, Any]] = []
        for k in summary_data.knowledge_nuggets:
            knowledge_nuggets.append({"insight": k.insight, "conversation_id": get_convo_id(k.conversation_number)})

        # Build the complete summary object
        summary_id = str(uuid.uuid4())
        return {
            "id": summary_id,
            "date": date_str,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "headline": summary_data.headline,
            "overview": summary_data.overview,
            "day_emoji": summary_data.day_emoji,
            "stats": {
                "total_conversations": total_conversations,
                "total_duration_minutes": int(total_duration_minutes),
            },
            "highlights": highlights,
            "unresolved_questions": unresolved_questions,
            "decisions_made": decisions_made,
            "knowledge_nuggets": knowledge_nuggets,
            "locations": locations,
        }
    except json.JSONDecodeError as e:
        logger.error("Failed to decode daily summary payload JSON: %s", sanitize(str(e)))
        return _basic_daily_summary(date_str, total_conversations, total_duration_minutes, locations)
    except ValidationError as e:
        logger.error("Failed to validate daily summary payload: %s", sanitize_validation_error(cast(Any, e)))
        return _basic_daily_summary(date_str, total_conversations, total_duration_minutes, locations)
