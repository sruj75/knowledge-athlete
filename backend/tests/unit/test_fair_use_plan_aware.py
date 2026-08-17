"""Tests for plan-aware fair-use soft caps and the hard daily-audio ceiling
(utils/fair_use.py).

``utils.fair_use`` imports cleanly; we toggle ``FAIR_USE_ENABLED`` per-test via
``patch.object`` and drive the pure detection functions with injected
``speech_totals`` so no Redis is touched. See backend/docs/test_isolation.md.
"""

from unittest.mock import patch

import utils.fair_use as fair_use_mod
from models.fair_use import SoftCapTrigger
from models.users import PlanType

BOUNDED_POLICIES = [PlanType.bounded, PlanType.free, None]


def _totals(daily_ms=0, three_day_ms=0, weekly_ms=0):
    return {'daily_ms': daily_ms, 'three_day_ms': three_day_ms, 'weekly_ms': weekly_ms}


class TestFairUseCapsForEntitlement:
    def test_bounded_or_missing_policy_gets_bounded_caps(self):
        expected = (
            fair_use_mod.FAIR_USE_DAILY_SPEECH_MS,
            fair_use_mod.FAIR_USE_3DAY_SPEECH_MS,
            fair_use_mod.FAIR_USE_WEEKLY_SPEECH_MS,
        )
        for policy in BOUNDED_POLICIES:
            assert fair_use_mod.fair_use_caps_for_entitlement(policy) == expected, policy

    def test_unlimited_tier_plans_get_raised_caps(self):
        expected = (
            fair_use_mod.FAIR_USE_DAILY_SPEECH_MS_UNLIMITED,
            fair_use_mod.FAIR_USE_3DAY_SPEECH_MS_UNLIMITED,
            fair_use_mod.FAIR_USE_WEEKLY_SPEECH_MS_UNLIMITED,
        )
        assert fair_use_mod.fair_use_caps_for_entitlement(PlanType.unlimited) == expected

    def test_unlimited_daily_cap_is_higher_than_default(self):
        # Guards the whole point of the feature: Unlimited must tolerate more before scrutiny.
        assert fair_use_mod.FAIR_USE_DAILY_SPEECH_MS_UNLIMITED > fair_use_mod.FAIR_USE_DAILY_SPEECH_MS

    def test_unknown_raw_policy_fails_closed(self):
        assert fair_use_mod.fair_use_caps_for_entitlement('retired-plan') == (
            fair_use_mod.FAIR_USE_DAILY_SPEECH_MS,
            fair_use_mod.FAIR_USE_3DAY_SPEECH_MS,
            fair_use_mod.FAIR_USE_WEEKLY_SPEECH_MS,
        )


class TestCheckSoftCapsPlanAware:
    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    def test_default_tier_triggers_daily_at_three_hours(self):
        totals = _totals(daily_ms=fair_use_mod.FAIR_USE_DAILY_SPEECH_MS + 1)
        triggers = [t['trigger'] for t in fair_use_mod.check_soft_caps('u', totals, PlanType.bounded)]
        assert SoftCapTrigger.DAILY in triggers

    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    def test_unlimited_tier_does_not_trigger_below_its_higher_daily_cap(self):
        # Just over the DEFAULT daily cap but under the UNLIMITED daily cap.
        totals = _totals(daily_ms=fair_use_mod.FAIR_USE_DAILY_SPEECH_MS + 1)
        assert fair_use_mod.check_soft_caps('u', totals, PlanType.unlimited) == []

    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    def test_unlimited_tier_triggers_daily_above_its_own_cap(self):
        totals = _totals(daily_ms=fair_use_mod.FAIR_USE_DAILY_SPEECH_MS_UNLIMITED + 1)
        triggers = [t['trigger'] for t in fair_use_mod.check_soft_caps('u', totals, PlanType.unlimited)]
        assert SoftCapTrigger.DAILY in triggers

    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    def test_plan_none_is_backwards_compatible_default_tier(self):
        totals = _totals(daily_ms=fair_use_mod.FAIR_USE_DAILY_SPEECH_MS + 1)
        triggers = [t['trigger'] for t in fair_use_mod.check_soft_caps('u', totals)]
        assert SoftCapTrigger.DAILY in triggers

    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    def test_reported_threshold_matches_the_tier(self):
        totals = _totals(daily_ms=fair_use_mod.FAIR_USE_DAILY_SPEECH_MS_UNLIMITED + 1)
        [daily] = [
            t
            for t in fair_use_mod.check_soft_caps('u', totals, PlanType.unlimited)
            if t['trigger'] == SoftCapTrigger.DAILY
        ]
        assert daily['threshold_ms'] == fair_use_mod.FAIR_USE_DAILY_SPEECH_MS_UNLIMITED


class TestDailyAudioCeiling:
    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    def test_exceeded_at_or_above_ceiling(self):
        totals = _totals(daily_ms=fair_use_mod.MAX_DAILY_AUDIO_MS)
        assert fair_use_mod.is_daily_audio_ceiling_exceeded('u', totals) is True

    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    def test_not_exceeded_below_ceiling(self):
        totals = _totals(daily_ms=fair_use_mod.MAX_DAILY_AUDIO_MS - 1)
        assert fair_use_mod.is_daily_audio_ceiling_exceeded('u', totals) is False

    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    @patch.object(fair_use_mod, 'MAX_DAILY_AUDIO_MS', 0)
    def test_disabled_when_ceiling_is_zero(self):
        totals = _totals(daily_ms=10**12)
        assert fair_use_mod.is_daily_audio_ceiling_exceeded('u', totals) is False

    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', False)
    def test_disabled_when_fair_use_off(self):
        totals = _totals(daily_ms=10**12)
        assert fair_use_mod.is_daily_audio_ceiling_exceeded('u', totals) is False

    @patch.object(fair_use_mod, 'FAIR_USE_ENABLED', True)
    def test_exempt_uid_bypasses_ceiling(self):
        totals = _totals(daily_ms=10**12)
        with patch.object(fair_use_mod, 'FAIR_USE_EXEMPT_UIDS', {'vip'}):
            assert fair_use_mod.is_daily_audio_ceiling_exceeded('vip', totals) is False
