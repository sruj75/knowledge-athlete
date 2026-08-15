from datetime import datetime, timezone

from utils.goals_response import normalize_goal_history_entry, normalize_goal_response


def test_goal_response_normalization_repairs_legacy_goal_docs_before_response_validation():
    normalized = normalize_goal_response(
        {
            'id': 'goal_legacy',
            'title': 'Read',
            'is_active': True,
            'created_at': '2026-01-01T00:00:00Z',
        }
    )

    assert normalized['id'] == 'goal_legacy'
    assert normalized['title'] == 'Read'
    assert normalized['goal_type'] == 'scale'
    assert normalized['target_value'] == 0
    assert normalized['current_value'] == 0
    assert normalized['min_value'] == 0
    assert normalized['max_value'] == 10
    assert normalized['created_at'] == datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert normalized['updated_at'].tzinfo is not None


def test_goal_history_normalization_repairs_legacy_history_docs_before_response_validation():
    normalized = normalize_goal_history_entry({'date': '2026-01-01', 'value': '4.5'})

    assert normalized['date'] == '2026-01-01'
    assert normalized['value'] == 4.5
    assert normalized['recorded_at'].tzinfo is not None
