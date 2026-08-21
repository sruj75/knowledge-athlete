from datetime import datetime, timedelta, timezone

from database.fair_use import _qualifying_violation_times


def test_only_scores_at_or_above_threshold_after_latest_reset_count():
    now = datetime(2026, 8, 21, 12, tzinfo=timezone.utc)
    reset_at = now - timedelta(days=3)
    events = [
        {'created_at': now - timedelta(days=2), 'classifier_score': 0.69},
        {'created_at': now - timedelta(days=2), 'classifier_score': 0.7},
        {'created_at': now - timedelta(days=4), 'classifier_score': 1.0},
        {'created_at': now - timedelta(days=1), 'classifier_score': 0.9},
    ]

    assert _qualifying_violation_times(events, reset_at=reset_at, now=now) == [
        now - timedelta(days=2),
        now - timedelta(days=1),
    ]
