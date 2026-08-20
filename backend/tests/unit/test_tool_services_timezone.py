"""The shared chat/agent timestamp formatters render in the user's timezone."""

import os
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

os.environ.setdefault(
    "ENCRYPTION_SECRET",
    "omi_ZwB2ZNqB2HHpMK6wStk7sTpavJiPTFg7gXUHnc4tFABPU6pZ2c2DKgehtfgi4RZv",
)
os.environ.setdefault("OPENAI_API_KEY", "test-openai-key-not-real")

import utils.conversations.render as render  # noqa: E402

UTC_INSTANT = datetime(2026, 6, 26, 22, 0, 0, tzinfo=timezone.utc)
UTC_AFTER_MIDNIGHT = datetime(2026, 6, 27, 1, 30, 0, tzinfo=timezone.utc)
SAO_PAULO = "America/Sao_Paulo"


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
