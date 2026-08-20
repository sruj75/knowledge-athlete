"""Chat/agent tool timestamps render in the user's timezone (issue #6214).

``/v1/tools/*`` (``routers/tools.py``) is the tool surface desktop, web, and managed agent clients
call. ``search_memories_text`` / ``search_memories_tool`` emitted a bare UTC calendar date, which is a
  day late for a user west of Greenwich in the evening.

The modules under test are imported normally and their collaborators are swapped with
``monkeypatch.setattr``, so the assertions run the real formatting code.
"""

import os
from datetime import datetime, timezone
from types import SimpleNamespace
from zoneinfo import ZoneInfo

import pytest

os.environ.setdefault(
    "ENCRYPTION_SECRET",
    "omi_ZwB2ZNqB2HHpMK6wStk7sTpavJiPTFg7gXUHnc4tFABPU6pZ2c2DKgehtfgi4RZv",
)
os.environ.setdefault("OPENAI_API_KEY", "test-openai-key-not-real")

import utils.conversations.render as render  # noqa: E402
import utils.retrieval.tool_services.memories as memories_svc  # noqa: E402
import utils.retrieval.tools.memory_tools as memory_tools  # noqa: E402
from utils.memory.memory_system import MemorySystem  # noqa: E402

# 22:00 UTC on 2026-06-26 is 19:00 the same day in Sao Paulo (UTC-3) — the reporter's 3-hour skew.
UTC_INSTANT = datetime(2026, 6, 26, 22, 0, 0, tzinfo=timezone.utc)
# 01:30 UTC on the 27th is still the 26th in Sao Paulo: the UTC date rolls over at a different
# instant than the user's, which is what made memory dates a day late.
UTC_AFTER_MIDNIGHT = datetime(2026, 6, 27, 1, 30, 0, tzinfo=timezone.utc)
SAO_PAULO = "America/Sao_Paulo"


@pytest.fixture
def user_tz(monkeypatch):
    """Set the timezone every module under test reads when rendering timestamps."""

    def _set(tz, *, fail=False):
        def _get_user_time_zone(uid):
            if fail:
                raise RuntimeError("firestore down")
            return tz

        for mod in (memories_svc, memory_tools):
            monkeypatch.setattr(mod.notification_db, "get_user_time_zone", _get_user_time_zone)

    return _set


def _memory(created_at):
    return SimpleNamespace(
        content="Likes espresso",
        created_at=created_at,
        category=SimpleNamespace(value="preferences"),
    )


def _stub_canonical_memory_search(monkeypatch, module, memories):
    """Point ``module`` at the canonical memory system and return ``memories`` from its search."""
    matches = [SimpleNamespace(memory=m, score=0.9) for m in memories]
    monkeypatch.setattr(module, "pin_memory_system", lambda *a, **k: MemorySystem.CANONICAL)
    monkeypatch.setattr(
        module,
        "MemoryService",
        lambda *a, **k: SimpleNamespace(search=lambda *sa, **sk: matches),
    )


# ---------------------------------------------------------------------------
# The shared formatters
# ---------------------------------------------------------------------------
class TestRenderFormatters:
    def test_time_converted_and_labelled(self):
        assert render.format_local_time(UTC_INSTANT, ZoneInfo(SAO_PAULO), SAO_PAULO) == (
            f"2026-06-26 19:00:00 {SAO_PAULO}"
        )

    def test_time_naive_value_treated_as_utc(self):
        naive = datetime(2026, 6, 26, 22, 0, 0)
        assert render.format_local_time(naive, ZoneInfo(SAO_PAULO), SAO_PAULO) == (f"2026-06-26 19:00:00 {SAO_PAULO}")

    def test_date_rolls_back_across_utc_midnight(self):
        assert render.format_local_date(UTC_AFTER_MIDNIGHT, ZoneInfo(SAO_PAULO)) == "2026-06-26"

    def test_date_naive_value_treated_as_utc(self):
        naive = datetime(2026, 6, 27, 1, 30, 0)
        assert render.format_local_date(naive, ZoneInfo(SAO_PAULO)) == "2026-06-26"

    def test_utc_fallback_unchanged(self):
        assert render.format_local_time(UTC_INSTANT, timezone.utc, "UTC") == "2026-06-26 22:00:00 UTC"
        assert render.format_local_date(UTC_AFTER_MIDNIGHT, timezone.utc) == "2026-06-27"


# ---------------------------------------------------------------------------
# Memory dates — REST tool service and the agentic tool
# ---------------------------------------------------------------------------
class TestMemoryDateTimezone:
    def test_service_search_date_uses_user_timezone(self, monkeypatch, user_tz):
        user_tz(SAO_PAULO)
        _stub_canonical_memory_search(monkeypatch, memories_svc, [_memory(UTC_AFTER_MIDNIGHT)])
        out = memories_svc.search_memories_text(uid="test-uid", query="coffee")
        assert "date: 2026-06-26" in out
        assert "date: 2026-06-27" not in out

    def test_tool_search_date_uses_user_timezone(self, monkeypatch, user_tz):
        user_tz(SAO_PAULO)
        _stub_canonical_memory_search(monkeypatch, memory_tools, [_memory(UTC_AFTER_MIDNIGHT)])
        out = memory_tools.search_memories_tool.func(
            query="coffee",
            config={"configurable": {"user_id": "test-uid"}},
        )
        assert "date: 2026-06-26" in out
        assert "date: 2026-06-27" not in out

    def test_unset_timezone_falls_back_to_utc_date(self, monkeypatch, user_tz):
        user_tz(None)
        _stub_canonical_memory_search(monkeypatch, memories_svc, [_memory(UTC_AFTER_MIDNIGHT)])
        out = memories_svc.search_memories_text(uid="test-uid", query="coffee")
        assert "date: 2026-06-27" in out

    def test_missing_created_at_still_renders(self, monkeypatch, user_tz):
        user_tz(SAO_PAULO)
        _stub_canonical_memory_search(monkeypatch, memories_svc, [_memory(None)])
        out = memories_svc.search_memories_text(uid="test-uid", query="coffee")
        assert "date: Unknown" in out
