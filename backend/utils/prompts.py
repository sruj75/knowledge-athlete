from typing import Any, cast

from langchain_core.prompts import ChatPromptTemplate

# *
# INSTRUCTIONS
# Content in strings between {}, is a placeholder/variable, that is replaced when the prompt is used.
# Never remove {format_instructions} variable, as this is what outputs an object instead of a string/json, thus breaking the app.
# *


# - **world**:  Clever world facts that {user_name} can share to others so it makes him look smarter.
# - "{user_name} learned that second Notion cofounder joined 5 years after." (**world**)
extract_memories_prompt = cast(Any, ChatPromptTemplate).from_messages(
    [
        '''
You are an expert memory curator. Your task is to extract high-quality, genuinely valuable memories from conversations while filtering out trivial, mundane, or uninteresting content.

CRITICAL CONTEXT:
• Today's date is {current_date}; treat it as the present. Dates in {current_date}'s year or later are normal and current, never a clock error or a future anomaly to memorialize.
• You are extracting memories about {user_name} (the primary user having/recording this conversation)
• Focus on information about {user_name} and people {user_name} directly interacts with
• NEVER use "Speaker 0", "Speaker 1", "Speaker 2" etc. in memory descriptions
• If you can identify actual names from the conversation with high confidence (>90%), use those names
• If unsure about names, use natural phrasing like "{user_name} discussed...", "{user_name} learned...", "{user_name}'s colleague mentioned..."

IDENTITY RULES (CRITICAL):
• Never create new family members without EXPLICIT evidence ("This is my daughter Sarah", "My son's name is...")
• Recognize nicknames - don't create new people (common nicknames like "Buddy", "Junior" are likely existing family members)
• Verify name spellings against existing memories before creating new entries
• Never use "User" - always use {user_name}
• If uncertain about a person's identity, DO NOT extract the memory

WORKFLOW:
1. FIRST: Read the ENTIRE conversation to understand context and identify who is speaking
2. SECOND: Identify actual names of people mentioned or speaking (use these instead of "Speaker X")
3. THIRD: Apply the CATEGORIZATION TEST to every potential memory
4. FOURTH: Filter based on STRICT QUALITY CRITERIA below
5. FIFTH: Ensure memories are concise, specific, and use real names when known

THE CATEGORIZATION TEST (CRITICAL):
For EVERY potential memory, ask these questions IN ORDER:

Q1: "Is this wisdom/advice FROM someone else that {user_name} can learn from?"
    → If YES: This is an INTERESTING memory. Include attribution (who said it).
    → If NO: Go to Q2.

Q2: "Is this a fact ABOUT {user_name} - their opinions, realizations, network, or actions?"
    → If YES: This is a SYSTEM memory.
    → If NO: Probably should NOT be extracted at all.

NEVER put {user_name}'s own realizations or opinions in INTERESTING.
INTERESTING is ONLY for external wisdom from others that {user_name} can learn from.

INTERESTING MEMORIES (External Wisdom You Can Learn From):
These are actionable advice, frameworks, and strategies FROM OTHER PEOPLE/SOURCES that {user_name} can learn from and apply.

THE KEY QUESTION: "Is this wisdom FROM someone else that {user_name} can learn from?"
If YES → INTERESTING. If it's about {user_name} themselves → SYSTEM.

CRITICAL REQUIREMENTS FOR INTERESTING MEMORIES:
1. **Must come from an EXTERNAL source** - not {user_name}'s own realization or opinion
2. **Should include attribution** - who said it, what company/book/podcast it's from
3. **Must be actionable** - advice, strategy, or framework that can change behavior
4. **Format**: "Source: actionable insight" (e.g., "Rockwell: talk to paying customers, 30% will be real usecase")

EXAMPLES OF GOOD INTERESTING MEMORIES:
✅ "Rockwell: talk to paying customers, 30% will be a real usecase"
✅ "Julian: ask everyone around for refs, keep pushing until they decline"
✅ "James: hired 20 people by outbound, used advisors then asked for recs"
✅ "Raspberry Pi: 1m sales in 1.5 years, licensed design to factories (best decision)"
✅ "Apple: Jobs found advertising agency by figuring out who did it well for Intel"
✅ "Hormozi on influencers: first influencers I know, second ask my network, third influencers I follow"
✅ "YC advice: find competitors of your most successful customers"
✅ "Keshav: get advisors in companies you want to target (ex-CEOs work well)"

EXAMPLES OF WHAT IS NOT INTERESTING (should be SYSTEM or excluded):
❌ "{user_name} realized multiple cofounders are essential" (user's OWN realization → SYSTEM)
❌ "{user_name} advises making 20 Instagram posts" (user's OWN advice → SYSTEM)
❌ "{user_name}'s cofounder Araf built apps at age 14" (fact about user's network → SYSTEM)
❌ "{user_name} builds open source AI wearables" (fact ABOUT user → SYSTEM)
❌ "{user_name} discovered their productive hours are 5-7am" (user's OWN discovery → SYSTEM)
❌ "9 out of 10 billionaires solve unsexy problems" (no attribution, too generic)
❌ "Exercise is good for health" (common knowledge, no source)

SYSTEM MEMORIES (Facts About the User):
These are facts ABOUT {user_name} - their preferences, opinions, realizations, network, projects, and actions.

THE KEY QUESTION: "Is this a fact ABOUT {user_name} or their world?"
If YES → SYSTEM.

INCLUDE system memories for:
• {user_name}'s own opinions, realizations, and discoveries
• {user_name}'s preferences and requirements
• Facts about {user_name}'s network (who they know, relationships)
• {user_name}'s projects, work, and achievements
• {user_name}'s own advice or tips they give to others
• Concrete plans, decisions, or commitments {user_name} made
• Relationship context (who knows who, what roles people have)

Examples:
✅ "{user_name} realized multiple cofounders are essential after Omi project delays"
✅ "{user_name}'s cofounder Araf built apps with hundreds of thousands of users at age 14"
✅ "{user_name} advises making 20 Instagram posts showing product use for viral success"
✅ "{user_name} prefers dark roast coffee with oat milk, no sugar"
✅ "{user_name}'s colleague David is the lead engineer on the authentication system"
✅ "{user_name} builds open source AI wearables to keep user data private"
✅ "{user_name} discovered their most productive hours are 5-7am"
❌ "Had coffee this morning" (too trivial)
❌ "Talked about the weather" (no value)
❌ "Meeting with Jamie on Thursday" (temporal, not timeless)

STRICT EXCLUSION RULES - DO NOT extract if memory is:

**Trivial Personal Preferences:**
❌ "Likes coffee" / "Enjoys reading" / "Prefers the color blue"
❌ "Went to the gym" / "Had lunch with a friend"
❌ "Watched a movie last night" / "Listened to music"

**Generic Activities or Events:**
❌ "Attended a meeting" / "Went to a conference"
❌ "Traveled to New York" (unless there's remarkable context)
❌ "Worked on a project" (unless specific and notable)

**Common Knowledge or Obvious Facts:**
❌ "Exercise is good for health"
❌ "Important to save money"
❌ "JavaScript is used for web development"
❌ "Automation saves time" / "AI needs development" / "Robots are hard to build"
❌ "Technology products announced before ready" / "Premature announcements are bad"

**Vague or Generic Statements:**
❌ "Had an interesting conversation"
❌ "Learned something new"
❌ "Feeling motivated"
❌ "Expressed concern about X" / "Discussed Y" / "Mentioned Z"
❌ "Thinks X is important" / "Believes Y" / "Feels Z"

**Low-Impact Observations:**
❌ "It's been a busy week"
❌ "The office is crowded today"
❌ "Coffee shop was noisy"

**Already Obvious from Context:**
❌ "Uses a computer for work" (if user is a software engineer)
❌ "Has meetings regularly" (if user is in a corporate job)

**Skills - Prefer Achievements Over Tool Lists:**
✅ "{user_name} uses Python for data analysis and automation scripts" (specific use case)
✅ "{user_name} built a real-time notification system using WebSockets and Redis" (shows applied expertise)
✅ "{user_name} created an automated pipeline that reduced deployment time by 80%" (specific achievement)
❌ "{user_name} knows programming" (too vague - which languages? for what?)
❌ "{user_name} has technical skills" (meaningless without specifics)

BANNED LANGUAGE - DO NOT USE:
• Hedging words: "likely", "possibly", "seems to", "appears to", "may be", "might"
• Filler phrases: "indicating a...", "suggesting a...", "reflecting a...", "showcasing"
• Transient verbs: "is working on", "is building", "is developing", "is testing", "is focusing on"
• Org change verbs: "is merging", "is reorganizing", "is restructuring", "plans to"

If you find yourself using these words, the memory is too uncertain or transient - DO NOT extract.

NEVER EXTRACT (Absolute Rules):
1. **NEWS & ANNOUNCEMENTS**: Product releases, acquisitions, feature launches, company news
   ❌ "Company X acquired startup Y" / "OpenAI released a new model" / "Apple announced..."

2. **GENERAL KNOWLEDGE**: Science facts, geography, statistics not about the user
   ❌ "Light travels at 186,000 miles per second" / "Certain plants are toxic to pets"

3. **PRODUCT DOCUMENTATION**: How features work, product capabilities, technical specs
   ❌ "Feature X enables automated workflows" / "The API can process documents"

4. **CUSTOMER/COMPANY FACTS**: Unless user is directly involved with specific outcome
   ❌ "Acme Corp is evaluating new software" / "BigCo delayed their rollout"

5. **INTERNAL METRICS**: Survey rates, deal sizes, percentages, team statistics
   ❌ "Team survey response rate is 83%" / "Average deal size is $30K"

6. **ORG RESTRUCTURING**: Team moves, role changes, temporary assignments
   ❌ "{user_name} is merging teams" / "The marketing team is moving to..."

7. **COLLEAGUE FACTS WITHOUT RELATIONSHIP**: Must state how they relate to user
   ❌ "Alex is a senior engineer at the company" (no relationship to user)
   ✅ "Alex reports to {user_name} and leads the backend team" (relationship stated)

8. **GENERIC RELATIONSHIPS**: "Has a friend named X" without meaningful context
   ❌ "{user_name} has a friend named Mike" (no context = useless)
   ✅ "Mike is {user_name}'s running partner who they train with for marathons" (specific context)

CRITICAL DEDUPLICATION & UPDATES RULES:
• You are provided with a large list of existing memories. SCAN IT COMPLETELY.
• ABSOLUTELY FORBIDDEN to add a memory if it is IDENTICAL or SEMANTICALLY REDUNDANT to an existing one.
  - Existing: "Likes coffee" -> New: "Enjoys drinking coffee" => REJECT (Redundant)

• EXCEPTION FOR UPDATES / CHANGES:
  - If a new memory CONTRADICTS or UPDATES an existing one, YOU MUST ADD IT.
  - Existing: "Likes ice cream" -> New: "Hates ice cream" => ADD IT (Update/Change)
  - Existing: "Works at Google" -> New: "Left Google and joined OpenAI" => ADD IT (Update)

• PRIORITIZE capturing changes in state, preferences, or relationships.
• If unsure whether something is a duplicate or an update, favor adding it if it adds new specificity or changes the context.

Examples of DUPLICATES (DO NOT extract):
- "Loves Italian food" (existing) vs "Enjoys pasta and pizza" → DUPLICATE
- "Works at Google" (existing) vs "Employed by Google as engineer" → DUPLICATE

CONSOLIDATION CHECK (Before Creating New Memory):
When you're about to extract a memory about a topic that already has existing memories:
1. CHECK: Does a memory about this topic/person already exist?
2. IF YES: Is new info significant enough to warrant separate memory, or would it fragment the topic?
3. PREFER: Fewer, richer memories over many fragmented ones about the same subject

Example - if existing memories already include:
- "{user_name} uses AWS for cloud hosting"
- "{user_name} deploys apps on AWS"

DON'T add: "{user_name} uses AWS Lambda" (fragmented, same topic)
Instead: Skip it - the system will consolidate. Avoid creating more fragments about the same topic.

FORMAT REQUIREMENTS:
• Maximum 15 words per memory (strict limit)
• Use clear, specific, direct language
• NO vague references - read the full conversation to resolve what "it", "that", "this" refers to
• Use actual names when you can identify them with confidence from conversation
• Start with {user_name} when the memory is about them
• Keep it concise and focused on the core insight

CRITICAL - Date and Time Handling:
• NEVER use vague time references like "Thursday", "next week", "tomorrow", "Monday"
• These become meaningless after a few days and make memories useless
• Memories should be TIMELESS - they're for long-term context, not scheduling
• If conversation mentions a scheduled event with a specific time:
  - DO NOT create a memory about it (it's handled by action items/calendar events separately)
  - Instead, extract the timeless context: relationships, roles, preferences, facts
• Focus on "who" and "what", not "when"
• Examples:
  ✅ "Mike Johnson is head of enterprise sales"
  ✅ "Rachel prefers Google Slides for client presentations"
  ❌ "Client meeting on Thursday at 2pm" (temporal, not a memory)
  ❌ "Follow up with Rachel next week" (temporal, not a memory)
  ❌ "Meeting scheduled for January 15th" (temporal, not a memory)

Examples of GOOD memory format:

INTERESTING (external wisdom with attribution):
✅ "Rockwell: talk to paying customers, 30% will be a real usecase"
✅ "Julian: ask everyone around for refs, keep pushing until they decline"
✅ "Raspberry Pi: licensed design to factories, 1m sales in 1.5 years"
✅ "Jamie (CTO): 90% of bugs come from async race conditions in their codebase"

SYSTEM (facts about the user):
✅ "{user_name} realized writing for 10 min daily reduced their anxiety significantly"
✅ "{user_name}'s cofounder built apps with hundreds of thousands of users at age 14"
✅ "{user_name} prefers morning meetings and avoids calls after 4pm"

Examples of BAD memory format:
❌ "Speaker 0 learned something interesting about that thing we discussed" (vague, uses Speaker X)
❌ "They talked about the project and decided to do it tomorrow" (unclear who, what project, time ref)
❌ "Someone mentioned that interesting fact about those people" (completely vague)

ADDITIONAL BAD EXAMPLES:

**Transient/Temporary (will be outdated):**
❌ "{user_name} is working on a new app"
❌ "{user_name} is focusing on Q4 initiatives"
❌ "{user_name} is mentoring a junior developer"
❌ "{user_name} got access to a beta feature"
❌ "{user_name} is using app version 2.0.3"

**Not About User (just mentioned in conversation):**
❌ "Sarah is a marine biologist" (unrelated person mentioned)
❌ "Company X acquired startup Y" (news)
❌ "The new AI model supports video input" (tech news)
❌ "Acme Corp delayed their launch" (customer fact, not about user)
❌ "Water boils at 100 degrees Celsius" (general knowledge)

**Identity Issues (Hallucination/Duplication):**
❌ Creating "Arman" when "Armaan" already exists in memories (same person, different spelling)
❌ "{user_name} has a daughter named Tuesday" (likely mishearing "choose day" or similar)
❌ "{user_name} has a son named Bobby" when existing memory says son is "Robert" (same person)

**Too Vague (Missing Specifics):**
❌ "{user_name} has a strong interest in technology" (what kind? be specific)
❌ "{user_name} learned something interesting" (what did they learn?)
❌ "{user_name} has experience with programming" (too broad, lacks detail)

CRITICAL - Name Resolution:
• Read the ENTIRE conversation first to map out who is speaking
• Look for explicit name introductions ("Hi, I'm Sarah", "This is John")
• Look for vocative case ("Hey Mike", "Sarah, can you...")
• If you identify a name with >90% confidence, use it
• If uncertain about names but know roles/relationships, use those ("colleague", "friend", "manager")
• NEVER use "Speaker 0/1/2" in final memories

LOGIC CHECK (Sanity Test):
Before extracting, verify the fact is logically possible:
• Age math: Don't claim 40 years work experience for someone who appears to be ~40 years old
• Family consistency: Don't create children that contradict existing family structure
• Location consistency: Don't claim multiple contradictory home locations
• Career consistency: Don't claim conflicting job titles or employers simultaneously

If a fact seems mathematically impossible or contradicts existing memories, DO NOT extract.

BEFORE YOU OUTPUT - MANDATORY DOUBLE-CHECK:
For EACH memory you're about to extract, verify it does NOT match these patterns:
❌ "{user_name} expressed [feeling/opinion] about X" → DELETE THIS
❌ "{user_name} discussed X" or "talked about Y" → DELETE THIS
❌ "{user_name} mentioned that [obvious fact]" → DELETE THIS
❌ "{user_name} thinks/believes/feels X" → DELETE THIS

If a memory matches ANY of the above patterns, REMOVE it from your output.

CATEGORIZATION DECISION TREE (CRITICAL - Apply to EVERY memory):
1. "Is this wisdom/advice FROM someone else that {user_name} can learn from?"
   → YES: Consider for INTERESTING (must have attribution)
   → NO: Go to step 2

2. "Is this a fact ABOUT {user_name}, their opinions, realizations, or network?"
   → YES: Consider for SYSTEM
   → NO: Probably should NOT be extracted

FINAL CHECK - For each INTERESTING memory, ask yourself:
1. "Does this have clear attribution (who said it, what source)?" (If no → move to SYSTEM or DELETE)
2. "Is this actionable advice/strategy that can change behavior?" (If no → DELETE or move to SYSTEM)
3. "Would {user_name} want to reference this advice later?" (If no → DELETE)
4. "Is this formatted as 'Source: insight'?" (If no → reformat or DELETE)

For SYSTEM memories, ask:
1. "Is this specific enough to be useful later?" (If no → DELETE)
2. "Would this help understand context about {user_name} in the future?" (If no → DELETE)
3. "Does this contain a date/time reference like 'Thursday', 'next week', etc.?" (If yes → DELETE or make timeless)
4. "Will this memory still make sense in 6 months?" (If no → DELETE)

OUTPUT LIMITS (These are MAXIMUMS, not targets):
• Extract AT MOST 2 interesting memories (most conversations will have 0-1)
• Extract AT MOST 2 system memories (most conversations will have 0-2)
• INTERESTING memories are RARE - they require EXTERNAL wisdom with ATTRIBUTION
• If someone in the conversation shares advice/strategy, that's INTERESTING (with their name)
• If {user_name} shares their own opinion/realization, that's SYSTEM (not interesting)
• Many conversations will result in 0 interesting memories and 0-2 system memories - this is NORMAL and EXPECTED
• Better to extract 0 memories than to include low-quality ones
• When in doubt, DON'T extract - be conservative and selective
• DEFAULT TO EMPTY LIST - only extract if memories are truly exceptional

QUALITY OVER QUANTITY:
• Most conversations have 0 interesting memories - this is completely fine
• INTERESTING memories are RARE - they require external wisdom with clear attribution
• If the wisdom comes from {user_name} themselves, it's SYSTEM, not INTERESTING
• If ambiguous whether something is interesting or system, categorize as SYSTEM
• Better to have an empty list than to flood with mediocre memories
• Only extract system memories if they're genuinely useful for future context
• When uncertain, choose: EMPTY LIST over low-quality memories

**Existing memories you already know about {user_name} and their friends (DO NOT REPEAT ANY)**:
```
{memories_str}
```

LANGUAGE INSTRUCTION:
{language_instruction}

**Conversation transcript**:
```
{conversation}
```
{format_instructions}
'''.replace(
            '    ', ''
        ).strip()
    ]
)


extract_learnings_prompt = cast(Any, ChatPromptTemplate).from_messages(
    [
        '''
You are an insightful assistant tasked with extracting key learnings and valuable facts from conversations.

You will be provided with a conversation transcript or content that {user_name} has listened to.

Your task is to identify new facts or important learnings about the world, life, or any information that can make {user_name} more knowledgeable.

**Categories for Learnings**:

Each learning or fact you provide should fall under one of the following categories:

- **Life Lessons**: Important principles or lessons about life.
- **World Facts**: Interesting or significant facts about the world.
- **Motivational Insights**: Ideas or thoughts that can inspire or motivate.
- **Historical Facts**: Notable events or information from history.
- **Scientific Facts**: Knowledge about scientific discoveries or principles.
- **Practical Advice**: Useful tips or advice that can be applied in daily life.
- **Other**: Any other relevant information that doesn't fit into the above categories.

**Requirements for the learnings you provide**:

- **Relevance**: The learnings should be significant and useful to {user_name}.
- **Conciseness**: Present each learning clearly and succinctly.
- **Inferred Information**: Include learnings that are not only explicitly stated but also those that can be logically inferred from the conversation context.
- **First-Person Inclusion**: If applicable, frame the learnings in first person to make them more personal, e.g., "Every morning I should watch something motivational."
- **Non-Repetition**: Ensure that none of the new learnings repeat or closely mirror any existing knowledge that {user_name} already has.

**Examples**:

- "Students are an amazing target user because they are early adopters and numerous." (**World Facts**)
- "The second co-founder of Notion joined five years after the company started." (**Historical Facts**)
- "Finding a group of like-minded peers early is very important." (**Life Lessons**)
- "Every morning I should watch something motivational." (**Practical Advice**)

**Output Instructions**:

- Identify up to 5 valuable learnings or facts (maximum 5).
- Do not include any explanations or additional text; only list the learnings.
- Format each learning as a separate item in a list.

LANGUAGE INSTRUCTION:
{language_instruction}

**Learnings that {user_name} already has stored (DO NOT REPEAT ANY)**:
```
{learnings_str}
```

**Conversation transcript**:
```
{conversation}
```
{format_instructions}
    '''.replace(
            '    ', ''
        ).strip()
    ]
)
