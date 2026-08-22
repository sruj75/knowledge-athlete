"""
Simple per-UID rate limiting config.

Each policy defines (max_requests, window_seconds). One window per policy —
no multi-tier caps. Fair use already handles budget enforcement; this layer
prevents abuse and protects backend resources.

Tuning knobs:
    RATE_LIMIT_BOOST: float multiplier on all limits (default 1.0).
        Set > 1.0 during events to relax limits, < 1.0 to tighten.
        Read from env var RATE_LIMIT_BOOST at startup.

    RATE_LIMIT_SHADOW: defaults OFF (enforcement/429 rejections). Set env var
        RATE_LIMIT_SHADOW_MODE=true to revert to shadow/log-only mode.

Redis efficiency:
    Each check = 1 Lua script call (atomic INCR + TTL check).
    Multi-instance safe — all state in Redis, no in-process caching.
"""

import os

# ---------------------------------------------------------------------------
# Global knobs (read at import time from env vars)
# ---------------------------------------------------------------------------

RATE_LIMIT_BOOST: float = float(os.getenv("RATE_LIMIT_BOOST", "1.0"))
RATE_LIMIT_SHADOW: bool = os.getenv("RATE_LIMIT_SHADOW_MODE", "false").lower() == "true"

# ---------------------------------------------------------------------------
# Policies: "name" -> (max_requests, window_seconds)
#
# max_requests is the BASE limit before boost is applied.
# Effective limit = int(max_requests * boost).
# ---------------------------------------------------------------------------

RATE_POLICIES: dict[str, tuple[int, int]] = {
    # Conversations — each triggers ~22 OpenAI calls
    "conversations:create": (10, 3600),
    "conversations:reprocess": (3, 3600),
    "conversations:merge": (5, 3600),
    # From-segments: on-device-STT upload path (segments already transcribed, so
    # cheaper than :create — no managed STT, just LLM structuring). Used per finished
    # conversation by Parakeet/local-STT users, so a bit more headroom than :create.
    "conversations:from-segments": (30, 3600),
    # Chat — 2-6 LLM calls per message
    "chat:send_message": (120, 3600),
    "chat:initial": (60, 3600),
    # Voice — managed STT + LLM
    "voice:transcribe": (60, 3600),
    "voice:transcribe_stream": (60, 3600),
    "voice:message": (60, 3600),
    "file:upload": (40, 3600),
    # Agent — bursty retained tool calls
    "agent:execute_tool": (120, 3600),
    # Platform tools — backend RAG endpoints
    "tools:search": (60, 3600),
    "tools:mutate": (60, 3600),
    # Action items — lightweight Firestore writes; an automated caller can loop,
    # so cap creation per hour.
    "action_items:write": (120, 3600),
    # Goals — single LLM call
    "goals:suggest": (30, 3600),
    "goals:advice": (30, 3600),
    "goals:extract": (30, 3600),
    # Memory compute — paid, bounded model judgments selected by the local lifecycle.
    "memory:extract": (30, 3600),
    "memory:normalize": (60, 3600),
    "memory:consolidate": (30, 3600),
    # Search
    "conversations:search": (60, 3600),
    # Expensive background ops
    "wrapped:generate": (2, 86400),
    # Phone verification uses IP-based rate_limit_dependency (pre-auth, no UID).
    # Not migrated to per-UID Lua limiter intentionally.
    # Test
    "test:prompt": (30, 3600),
}


def get_effective_limit(policy_name: str, boost: float | None = None) -> tuple[int, int]:
    """Return (effective_max_requests, window_seconds) with boost applied."""
    base_max, window = RATE_POLICIES[policy_name]
    b = boost if boost is not None else RATE_LIMIT_BOOST
    return max(1, int(base_max * b)), window
