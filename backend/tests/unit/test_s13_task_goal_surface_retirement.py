"""S-13 contract: tasks and simple goals have no hosted product authority."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def _router_source() -> str:
    return '\n'.join(path.read_text(encoding='utf-8') for path in sorted((ROOT / 'routers').glob('*.py')))


def test_task_goal_score_candidate_and_workstream_routes_are_absent() -> None:
    retired_prefixes = (
        '/v1/action-items',
        '/v1/tools/action-items',
        '/v1/staged-tasks',
        '/v1/candidates',
        '/v1/task-intelligence',
        '/v1/task-recommendations',
        '/v1/what-matters-now',
        '/v1/goals',
        '/v1/work-intents',
        '/v1/workstreams',
        '/v1/workflow-migrations/task-goal-links',
        '/v1/daily-score',
        '/v1/scores',
    )

    source = _router_source()
    assert [prefix for prefix in retired_prefixes if prefix in source] == []


def test_retired_hosted_authority_modules_are_deleted() -> None:
    retired = (
        'database/action_items.py',
        'database/candidates.py',
        'database/goals.py',
        'database/staged_tasks.py',
        'database/task_recommendations.py',
        'database/workstreams.py',
        'routers/action_items.py',
        'routers/candidates.py',
        'routers/goals.py',
        'routers/scores.py',
        'routers/staged_tasks.py',
        'routers/task_recommendations.py',
        'routers/workstreams.py',
        'utils/retrieval/tool_services/action_items.py',
        'utils/retrieval/tools/action_item_tools.py',
        'utils/task_intelligence/__init__.py',
    )

    assert [path for path in retired if (ROOT / path).exists()] == []


def test_transient_conversation_candidate_and_retained_retrieval_routes_remain() -> None:
    source = _router_source()
    for path in (
        '/v1/conversation-compute/action-items',
        '/v1/tools/conversations',
        '/v1/tools/conversations/search',
        '/v1/tools/memories',
        '/v1/tools/memories/search',
    ):
        assert path in source, f'retained route {path} was removed'
