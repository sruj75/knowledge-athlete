import Foundation

// MARK: - Chat Prompts
// Converted from OMI Python backend: backend/utils/llm/chat.py
// These prompts use template variables that should be replaced at runtime:
// - {user_name} - User's display name
// - {tz} - User's timezone identifier
// - {current_datetime_str} - Formatted datetime string
// - {memories_section} - Formatted memories section
// - {goal_section} - User's current goal

struct ChatPrompts {

  // MARK: - Desktop Chat Prompt (Simplified for Client-Side)

  /// Simplified prompt for desktop client-side chat (no tool instructions)
  /// This is what we use in ChatProvider.swift
  /// Variables: {user_name}, {tz}, {current_datetime_str}, {memories_section}
  static let desktopChat = """
    <assistant_role>
    You are Omi, an AI assistant & mentor for {user_name}. You are a smart friend who gives honest and concise feedback and responses to user's questions in the most personalized way possible.
    </assistant_role>

    <user_context>
    Current date/time in {user_name}'s timezone ({tz}): {current_datetime_str}
    {memories_section}
    {goal_section}{tasks_section}{ai_profile_section}
    </user_context>

    <mentor_behavior>
    You're a mentor, not a yes-man. When you see a critical gap between {user_name}'s plan and their goal:
    - Call it out directly - don't bury it after paragraphs of summary
    - Only challenge when it matters - not every message needs pushback
    - Be direct - "why not just do X?" rather than "Have you considered the alternative approach of X?"
    - Never summarize what they just said - jump straight to your reaction/advice
    - Give one clear recommendation, not 10 options
    </mentor_behavior>

    <response_style>
    Write like a smart friend texting — casual, specific, brief.

    Bright lines:
    - Default 2-8 lines; quick replies 1-3; "I don't know" answers 1-2 lines max.
    - Never open by summarizing or praising what they just said — jump straight to your reaction or answer.
    - No section headers in conversational replies. Reflections/planning may run longer.

    One example carries the register:
    - Not: "Great reflection! Based on your recorded conversations, here's a summary of what you did..."
    - But: "you spent most of the day in Xcode — mostly the omi fix. want the breakdown?"
    </response_style>

    <critical_accuracy_rules>
    Everything you state about {user_name} must come from tool results or the context above — never from plausible invention.

    Bright lines:
    1. Look it up before saying you don't know; say "I don't know" only after a tool came back empty.
    2. An empty result gets a short human answer, then stop: "I don't remember that coming up" — not "no data available", not paragraphs about why, not offers to reconstruct.
    3. People are the strictest case: state nothing about a person that a tool did not return.
    </critical_accuracy_rules>

    <retrieval_source_rules>
    Choose the source that matches the user's request:
    - Public internet, external companies/products/people, current facts, news, weather, prices, or explicit requests to search online → use web_search.
    - The user's private history, conversations, memories, tasks, screen activity, or things they previously said/did → use the matching Omi tool, not web_search.
    - A direct URL → read that URL before answering.
    - For short follow-ups such as "look it up," resolve "it" from the recent exchange. If it is a public entity, search the web. If it refers to the user's private history, search Omi.
    - If both public and private information are requested, retrieve both and clearly distinguish them.
    Never claim that public information is unavailable merely because it was not found in Omi's private data.
    </retrieval_source_rules>

    <tools>
    \(DesktopCapabilityRegistry.desktopToolPrompt)

    {database_schema}

    **Common SQL patterns:**

    -- Look up personal facts/preferences (ALWAYS try this for personal questions):
    SELECT content FROM memories WHERE deleted = 0 AND isDismissed = 0
    ORDER BY createdAt DESC LIMIT 50

    -- Search memories by keyword:
    SELECT content, category, createdAt FROM memories
    WHERE deleted = 0 AND isDismissed = 0 AND content LIKE '%keyword%'
    ORDER BY createdAt DESC

    -- Daily recap (run ALL 3 for "what did I do" questions — use -1 day for yesterday, -7 day for past week):
    -- Q1: App usage
    SELECT appName, COUNT(*) as count, ROUND(COUNT(*) * 10.0 / 60, 1) as minutes,
    MIN(time(timestamp, 'localtime')) as first_seen, MAX(time(timestamp, 'localtime')) as last_seen
    FROM screenshots WHERE timestamp >= datetime('now', 'start of day', '-1 day', 'localtime')
    AND timestamp < datetime('now', 'start of day', 'localtime')
    AND appName IS NOT NULL AND appName != '' GROUP BY appName ORDER BY count DESC
    -- Q2: Conversations
    SELECT title, overview, emoji, startedAt, finishedAt,
    ROUND((julianday(finishedAt) - julianday(startedAt)) * 1440, 1) as duration_min
    FROM transcription_sessions WHERE startedAt >= datetime('now', 'start of day', '-1 day', 'localtime')
    AND startedAt < datetime('now', 'start of day', 'localtime') AND deleted = 0 AND discarded = 0
    ORDER BY startedAt DESC
    -- Q3: Tasks
    SELECT description, completed, priority FROM action_items
    WHERE createdAt >= datetime('now', 'start of day', '-1 day', 'localtime')
    AND createdAt < datetime('now', 'start of day', 'localtime') AND deleted = 0
    ORDER BY createdAt DESC

    -- Recent screenshots with context:
    SELECT timestamp, appName, windowTitle, substr(ocrText, 1, 200) as preview
    FROM screenshots WHERE timestamp >= datetime('now', '-1 day', 'localtime')
    ORDER BY timestamp DESC LIMIT 20

    -- Active tasks:
    SELECT id, description, priority, dueAt, createdAt FROM action_items
    WHERE completed = 0 AND deleted = 0 ORDER BY createdAt DESC

    -- Create a task:
    INSERT INTO action_items (description, priority, completed, deleted, source, createdAt, updatedAt)
    VALUES ('task text', 'medium', 0, 0, 'chat', datetime('now'), datetime('now'))

    -- Recent conversations:
    SELECT id, title, overview, emoji, startedAt, finishedAt FROM transcription_sessions
    WHERE deleted = 0 AND discarded = 0 ORDER BY startedAt DESC LIMIT 10

    -- Conversation transcript:
    SELECT ts.text, ts.speaker, ts.startTime FROM transcription_segments ts
    WHERE ts.sessionId = ? ORDER BY ts.segmentOrder

    -- Search conversation content:
    SELECT s.id, s.title, s.overview, s.startedAt FROM transcription_sessions s
    JOIN transcription_segments seg ON seg.sessionId = s.id
    WHERE s.deleted = 0 AND seg.text LIKE '%keyword%'
    GROUP BY s.id ORDER BY s.startedAt DESC LIMIT 10

    -- Time in user's timezone: use datetime('now', 'localtime') or datetime('now', '-N hours', 'localtime')
    -- "yesterday": datetime('now', 'start of day', '-1 day', 'localtime') to datetime('now', 'start of day', 'localtime')
    -- FTS search: SELECT * FROM screenshots WHERE id IN (SELECT rowid FROM screenshots_fts WHERE screenshots_fts MATCH 'keyword')

    **Timezone handling:**
    All timestamps in the database are stored in UTC. When displaying dates/times from query results to the user, convert them to {user_name}'s timezone ({tz}). When filtering by date/time in WHERE clauses, use datetime('now', 'localtime') which SQLite handles automatically.
    </tools>

    <initiative>
    You are expected to act, not just answer.
    - Read-only lookups (SQL, search, recap, screen history): just run them — never ask permission to look something up.
    - Local changes {user_name} asked for (create/complete/delete a task, save a memory): do them and confirm in one line.
    - Ask first only when an action leaves this machine (sending, posting, sharing, purchasing) or is destructive and wasn't explicitly requested.
    - If tool results surface something that changes the answer or that {user_name} clearly needs to know, say it unprompted.
    </initiative>

    <instructions>
    - Be casual, concise, and direct—text like a friend.
    - Give specific feedback/advice; never generic.
    - Always answer the question directly; no extra info, no fluff.
    - Use what you know about {user_name} to personalize your responses.
    - Show times/dates in {user_name}'s timezone ({tz}), in a natural, friendly way.
    - When searching screen history, summarize findings naturally — don't dump raw data.
    </instructions>
    """

  // MARK: - Onboarding Chat Prompt

  static let tableAnnotations: [String: String] = [
    "screenshots": "captured screen frames with OCR text",
    "action_items": "tasks (bidirectional sync with backend)",
    "transcription_sessions": "voice recordings / conversations",
    "transcription_segments": "transcript text with speaker/timing",
    "proactive_extractions": "memories, advice, tasks extracted from screenshots",
    "focus_sessions": "focus tracking",
    "live_notes": "AI-generated notes during recording",
    "memories":
      "user facts, preferences, personal details (age, relationships, habits, interests) — PRIMARY source for personal questions",
    "ai_user_profiles": "daily AI-generated user profile summaries",
    "goals": "user goals with progress tracking",
    "staged_tasks": "AI-extracted task candidates pending user review",
    "task_chat_messages": "Claude Code agent ↔ user chat history, one thread per task (action item)",
    "observations": "per-screenshot AI observations used to detect tasks and activities",
  ]

  /// Per-column descriptions for every non-excluded table.
  /// Used by formatSchema() to annotate each column with a human-readable hint.
  /// Key = table name, value = (column name → description).
  static let columnAnnotations: [String: [String: String]] = [
    "screenshots": [
      "timestamp": "When the screenshot was captured",
      "appName": "Active application name at capture time",
      "windowTitle": "Active window title at capture time",
      "ocrText": "Full OCR-extracted text from the screen",
      "focusStatus": "Whether user was focused or distracted (focused/distracted)",
      "skippedForBattery":
        "Legacy flag for screenshots captured before battery mode switched to adaptive capture cadence",
      "deviceName": "Computer name that captured this screenshot (optional; absent when provenance is unknown)",
      "clientDeviceId": "Stable capture-device identifier used for canonical memory provenance",
    ],
    "action_items": [
      "description": "The task text shown to the user",
      "completed": "Whether the task is marked done",
      "deleted": "Soft-delete flag",
      "source": "Origin: screenshot | conversation | omi | manual",
      "conversationId": "Backend conversation ID if extracted from a voice session",
      "priority": "high | medium | low",
      "category": "AI-assigned category label",
      "tagsJson": "JSON array of tag strings",
      "deletedBy": "Who deleted it: user | ai_dedup",
      "dueAt": "Optional due date/time",
      "screenshotId": "FK to screenshots — screen context at extraction time",
      "confidence": "Extraction confidence 0–1",
      "sourceApp": "App that was active when task was extracted",
      "windowTitle": "Window title at extraction time",
      "contextSummary": "AI summary of what was happening on screen",
      "currentActivity": "Short label of user activity at capture time",
      "metadataJson": "Arbitrary extra metadata JSON",
      "sortOrder": "Manual user-defined sort position",
      "indentLevel": "Nesting level 0–3 for subtasks",
      "relevanceScore": "AI-scored relevance 0–100; higher = more important",
      "scoredAt": "When relevanceScore was last computed",
      "agentStatus": "AI agent execution state: pending | processing | editing | completed | failed",
      "agentSessionName": "tmux session name for the running agent",
      "agentPrompt": "Prompt that was sent to the Claude agent",
      "agentPlan": "Claude agent's response / execution plan",
      "agentStartedAt": "When the agent started working on this task",
      "agentCompletedAt": "When the agent finished",
      "agentEditedFilesJson": "JSON array of file paths the agent modified",
      "chatSessionId": "Firestore session ID for the task-scoped sidebar chat",
      "recurrenceRule": "Recurrence pattern: daily | weekdays | weekly | biweekly | monthly",
      "recurrenceParentId": "backendId of the parent recurring task template",
    ],
    "task_chat_messages": [
      "taskId": "FK to action_items.backendId — which task this message belongs to",
      "messageId": "Stable UUID for this message (dedup key)",
      "sender": "user | ai",
      "messageText": "Plain text content of the message",
      "contentBlocksJson": "JSON-encoded Claude content blocks: text, toolCall, thinking",
      "createdAt": "When the message was sent",
      "updatedAt": "Last modification time",
    ],
    "memories": [
      "content": "The remembered fact, preference, or personal detail",
      "category": "system | interesting | manual",
      "tagsJson": "JSON array of tag strings (e.g. [\"tip\", \"preference\"])",
      "visibility": "private | public",
      "reviewed": "Whether a human has reviewed this memory",
      "userReview": "User thumbs-up (true) / thumbs-down (false) / unreviewed (null)",
      "manuallyAdded": "True if user typed this directly rather than AI-extracted",
      "scoring": "Internal scoring metadata from extraction",
      "source": "desktop | omi | screenshot | phone — how the memory was created",
      "conversationId": "Backend conversation ID if extracted from a voice session",
      "screenshotId": "FK to screenshots if extracted from screen",
      "confidence": "Extraction confidence 0–1",
      "reasoning": "AI reasoning for why this was saved as a memory",
      "sourceApp": "App that was active when memory was extracted",
      "windowTitle": "Window title at extraction time",
      "contextSummary": "AI summary of screen context at extraction",
      "currentActivity": "User activity label at extraction time",
      "inputDeviceName": "Audio device used if from a voice session",
      "isRead": "Whether the user has seen this memory in the UI",
      "isDismissed": "Whether the user dismissed this memory",
      "deleted": "Soft-delete flag",
    ],
    "transcription_sessions": [
      "startedAt": "When recording began",
      "finishedAt": "When recording ended (null if still recording)",
      "source": "Recording source: desktop | omi | phone | etc",
      "language": "BCP-47 language code (e.g. en, fr)",
      "timezone": "IANA timezone of the device at recording time",
      "inputDeviceName": "Audio input device name",
      "status": "recording | pending_upload | uploading | completed | failed",
      "retryCount": "Number of upload retry attempts",
      "lastError": "Last upload error message if status=failed",
      "title": "AI-generated session title",
      "overview": "AI-generated session summary",
      "emoji": "AI-assigned emoji representing the session",
      "category": "AI-assigned topic category",
      "actionItemsJson": "JSON array of tasks extracted by backend",
      "eventsJson": "JSON array of calendar events detected",
      "geolocationJson": "Location data if available",
      "conversationStatus": "User-set status label for the conversation",
      "discarded": "True if user discarded/deleted this session",
      "deleted": "Soft-delete flag",
      "isLocked": "True if user has locked the session from edits",
      "starred": "True if user starred/favorited this session",
      "folderId": "Folder the session is organized into",
    ],
    "transcription_segments": [
      "sessionId": "FK to transcription_sessions",
      "speaker": "Speaker index (0, 1, 2…) within this session",
      "text": "Transcribed text for this segment",
      "startTime": "Segment start time in seconds from session start",
      "endTime": "Segment end time in seconds from session start",
      "segmentOrder": "Sequential order within the session",
      "segmentId": "Backend segment ID",
      "speakerLabel": "Human-readable speaker label if identified",
      "isUser": "True if this speaker is the primary user",
      "personId": "Identified person ID if speaker was recognized",
    ],
    "live_notes": [
      "sessionId": "FK to transcription_sessions — which session this note belongs to",
      "text": "Note text content",
      "timestamp": "When the note was created",
      "isAiGenerated": "True if AI generated; false if user typed manually",
      "segmentStartOrder": "First segment order this note references",
      "segmentEndOrder": "Last segment order this note references",
    ],
    "proactive_extractions": [
      "screenshotId": "FK to screenshots — source screen",
      "type": "memory | task | advice",
      "content": "The extracted text content",
      "category": "Topic category assigned by AI",
      "confidence": "Extraction confidence 0–1",
      "reasoning": "AI explanation for this extraction",
      "sourceApp": "App active at extraction time",
      "contextSummary": "AI summary of screen context",
      "priority": "Priority if type=task: high | medium | low",
      "isRead": "Whether user has seen this extraction",
      "isDismissed": "Whether user dismissed it",
    ],
    "focus_sessions": [
      "screenshotId": "FK to screenshots",
      "status": "focused | distracted",
      "appOrSite": "App or website being used",
      "windowTitle": "Window title at the time",
      "description": "AI description of what the user was doing",
      "message": "Motivational or coaching message for the user",
      "durationSeconds": "How long the focus/distraction period lasted",
    ],
    "observations": [
      "screenshotId": "FK to screenshots",
      "appName": "App that was active",
      "contextSummary": "AI-generated summary of what was happening",
      "currentActivity": "Short activity label",
      "hasTask": "Whether a task was found in this screenshot",
      "taskTitle": "Task title if hasTask=true",
      "sourceCategory": "High-level category (work/personal/social/etc)",
      "sourceSubcategory": "More specific subcategory",
      "metadataJson": "Additional structured metadata",
    ],
    "goals": [
      "title": "Short goal name shown in UI",
      "goalDescription": "Longer description of the goal",
      "goalType": "boolean (done/not done) | scale (0–N) | numeric (measured value)",
      "targetValue": "The value to reach for completion",
      "currentValue": "Current progress value",
      "minValue": "Minimum possible value",
      "maxValue": "Maximum possible value",
      "unit": "Unit label (e.g. km, hours, pages)",
      "isActive": "Whether goal is currently being tracked",
      "completedAt": "When the goal was completed (null if in progress)",
      "deleted": "Soft-delete flag",
    ],
    "staged_tasks": [
      "description": "Task text proposed by AI",
      "completed": "Whether promoted task was completed",
      "deleted": "Soft-delete flag",
      "source": "Origin: screenshot | conversation | omi",
      "conversationId": "Backend conversation ID if from voice",
      "priority": "high | medium | low",
      "category": "AI-assigned category",
      "tagsJson": "JSON array of tag strings",
      "deletedBy": "user | ai_dedup",
      "dueAt": "Proposed due date",
      "screenshotId": "FK to screenshots",
      "confidence": "Extraction confidence 0–1",
      "sourceApp": "App active at extraction",
      "windowTitle": "Window title at extraction",
      "contextSummary": "AI summary of screen context",
      "currentActivity": "Activity label at extraction time",
      "metadataJson": "Extra metadata JSON",
      "relevanceScore": "AI relevance score 0–100",
      "scoredAt": "When relevanceScore was computed",
    ],
    "ai_user_profiles": [
      "profileText": "Full AI-generated profile summary text",
      "dataSourcesUsed": "Bitmask of data sources used to generate the profile",
      "generatedAt": "When this profile was generated",
    ],
  ]

  /// Tables to exclude from the schema prompt (internal/GRDB tables)
  static let excludedTablePrefixes = ["sqlite_", "grdb_"]
  /// Any table whose name contains "_fts" is an FTS virtual or internal table — exclude all.
  /// Specific infra tables also excluded.
  static let excludedTables: Set<String> = ["migration_status", "task_dedup_log"]

  /// Infrastructure columns to strip from schema — file paths, binary blobs, sync state, internal flags.
  /// New migrations are still picked up automatically; only these specific names are hidden.
  /// Claude can always query: SELECT sql FROM sqlite_master WHERE name='table_name'
  static let excludedColumns: Set<String> = [
    "imagePath", "videoChunkPath", "frameOffset",
    "ocrDataJson", "extractedTasksJson", "adviceJson",
    "isIndexed", "backendId", "backendSynced", "backendSyncedAt",
    "embeddingData", "embedding", "normalizedOcrTextId",
    "fromStaged",
  ]

  /// Static suffix appended after the dynamic schema — FTS tables, relationships, and query patterns
  static let schemaFooter = """
    **FTS5 full-text search tables** (use MATCH for keyword search, BM25 for ranking):
    - screenshots_fts(ocrText, windowTitle, appName)
    - action_items_fts(description)
    - staged_tasks_fts(description)
    - task_chat_messages_fts(messageText)
    - proactive_extractions_fts(content, reasoning, contextSummary)

    FTS query patterns:
    -- Keyword search with JOIN:
    SELECT s.* FROM screenshots s JOIN screenshots_fts ON screenshots_fts.rowid = s.id WHERE screenshots_fts MATCH 'keyword'
    -- BM25-ranked search (lower rank = better match):
    SELECT a.*, bm25(action_items_fts) as rank FROM action_items a JOIN action_items_fts ON action_items_fts.rowid = a.id WHERE action_items_fts MATCH 'keyword' ORDER BY rank
    -- Multi-word: 'word1 word2' (AND), 'word1 OR word2' (OR), '"exact phrase"'

    **Table relationships** (JOIN on these foreign keys):
    - action_items.screenshotId → screenshots.id (screen context at extraction)
    - action_items.conversationId → transcription_sessions.backendId (voice session source)
    - transcription_segments.sessionId → transcription_sessions.id (transcript lines)
    - observations.screenshotId → screenshots.id (screen context)
    - focus_sessions.screenshotId → screenshots.id (screen context)
    - memories.screenshotId → screenshots.id (screen context)
    - memories.conversationId → transcription_sessions.backendId (voice session source)
    - live_notes.sessionId → transcription_sessions.id (recording notes)
    - staged_tasks.screenshotId → screenshots.id (screen context)
    - proactive_extractions.screenshotId → screenshots.id (source screen)

    Full DDL for any table: SELECT sql FROM sqlite_master WHERE name='table_name'
    """

}

// MARK: - Prompt Builder

/// Helper class to build prompts with template variables
struct ChatPromptBuilder {

  /// Shared formatter — `DateFormatter` is expensive to construct, and
  /// `currentDatetimeString` is on the per-query hot path. Configured once and
  /// only read afterwards (safe for concurrent formatting).
  private static let datetimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    f.timeZone = .current
    return f
  }()

  /// Human-readable "now" in the user's timezone ("yyyy-MM-dd HH:mm:ss").
  /// Single source for the {current_datetime_str} substitution and the
  /// floating-bar live-context line, so the cached prefix and live tail can't
  /// drift in datetime format.
  static func currentDatetimeString(_ date: Date = Date()) -> String {
    datetimeFormatter.string(from: date)
  }

  /// Build a system prompt with the given variables
  static func build(
    template: String,
    userName: String,
    timezone: String = TimeZone.current.identifier,
    currentDatetime: String? = nil,
    currentDatetimeISO: String? = nil,
    memoriesSection: String = "",
    goalSection: String = ""
  ) -> String {
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.timeZone = TimeZone.current

    let now = Date()
    let datetime = currentDatetime ?? currentDatetimeString(now)
    let datetimeISO = currentDatetimeISO ?? isoFormatter.string(from: now)
    let utcFormatter = DateFormatter()
    utcFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    utcFormatter.timeZone = TimeZone(identifier: "UTC")
    let currentDatetimeUTC = utcFormatter.string(from: now)

    var prompt = template

    // Replace all template variables
    prompt = prompt.replacingOccurrences(of: "{user_name}", with: userName)
    prompt = prompt.replacingOccurrences(of: "{tz}", with: timezone)
    prompt = prompt.replacingOccurrences(of: "{current_datetime_str}", with: datetime)
    prompt = prompt.replacingOccurrences(of: "{current_datetime_iso}", with: datetimeISO)
    prompt = prompt.replacingOccurrences(of: "{current_datetime_utc}", with: currentDatetimeUTC)
    prompt = prompt.replacingOccurrences(of: "{memories_section}", with: memoriesSection)
    prompt = prompt.replacingOccurrences(of: "{goal_section}", with: goalSection)

    return prompt
  }

  /// Build the desktop chat system prompt
  static func buildDesktopChat(
    userName: String,
    memoriesSection: String = "",
    goalSection: String = "",
    tasksSection: String = "",
    aiProfileSection: String = "",
    databaseSchema: String = "",
    currentDatetime: String? = nil
  ) -> String {
    var prompt = build(
      template: ChatPrompts.desktopChat,
      userName: userName,
      currentDatetime: currentDatetime,
      memoriesSection: memoriesSection,
      goalSection: goalSection
    )
    prompt = prompt.replacingOccurrences(of: "{tasks_section}", with: tasksSection)
    prompt = prompt.replacingOccurrences(of: "{ai_profile_section}", with: aiProfileSection)
    prompt = prompt.replacingOccurrences(of: "{database_schema}", with: databaseSchema)
    return prompt
  }

}
