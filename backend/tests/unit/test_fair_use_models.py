"""Tests for fair-use Pydantic models (models/fair_use.py)."""

from datetime import datetime

import pytest
from pydantic import ValidationError

from models.fair_use import (
    UsageType,
    FairUseEvent,
    FairUseStage,
    FairUseState,
    FairUseUserSummary,
    SoftCapTrigger,
)


class TestEnums:
    def test_fair_use_stages(self):
        assert FairUseStage.NONE.value == 'none'
        assert FairUseStage.WARNING.value == 'warning'
        assert FairUseStage.THROTTLE.value == 'throttle'
        assert FairUseStage.RESTRICT.value == 'restrict'

    def test_usage_types(self):
        assert UsageType.AUDIOBOOK.value == 'audiobook'
        assert UsageType.PODCAST.value == 'podcast'
        assert UsageType.COMMERCIAL.value == 'commercial'

    def test_soft_cap_triggers(self):
        assert SoftCapTrigger.DAILY.value == 'daily'
        assert SoftCapTrigger.THREE_DAY.value == '3day'
        assert SoftCapTrigger.WEEKLY.value == 'weekly'


class TestFairUseState:
    def test_defaults(self):
        state = FairUseState()
        assert state.stage == FairUseStage.NONE
        assert state.violation_count_7d == 0
        assert state.throttle_until is None
        assert state.restrict_until is None

    def test_throttled_state(self):
        state = FairUseState(
            stage=FairUseStage.THROTTLE,
            violation_count_7d=3,
            throttle_until=datetime(2026, 4, 1),
        )
        assert state.stage == FairUseStage.THROTTLE
        assert state.throttle_until == datetime(2026, 4, 1)


class TestFairUseEvent:
    def test_defaults(self):
        event = FairUseEvent()
        assert event.enforcement_action == ''
        assert event.resolved is False
        assert event.trigger == SoftCapTrigger.DAILY

    def test_content_bearing_classifier_fields_are_forbidden(self):
        with pytest.raises(ValidationError):
            FairUseEvent.model_validate({'classifier_score': 0.8, 'reasoning': 'must not persist'})


class TestFairUseUserSummary:
    def test_summary(self):
        summary = FairUseUserSummary(
            uid='user-123',
            stage=FairUseStage.WARNING,
            speech_hours_today=1.5,
            speech_hours_7d=8.0,
        )
        assert summary.uid == 'user-123'
        assert summary.speech_hours_today == 1.5
