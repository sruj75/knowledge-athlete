import pytest

from models.task_intelligence import TaskWorkflowMode
from utils.task_intelligence.rollout import resolve_task_intelligence_for_user, resolve_task_intelligence_rollout


@pytest.mark.parametrize('mode', list(TaskWorkflowMode))
def test_rollout_matrix_is_owned_by_the_task_workflow(mode):
    decision = resolve_task_intelligence_rollout(uid='user-1', workflow_mode=mode, account_generation=7)

    assert decision.workflow_mode == mode
    assert decision.account_generation == 7
    assert decision.legacy_reads_authoritative is (mode != TaskWorkflowMode.read)
    assert decision.legacy_writes_enabled is (mode != TaskWorkflowMode.read)
    assert decision.intelligence_evaluation_enabled is (mode != TaskWorkflowMode.off)
    assert decision.canonical_sidecar_writes_enabled is (mode in {TaskWorkflowMode.write, TaskWorkflowMode.read})
    assert decision.canonical_reads_authoritative is (mode == TaskWorkflowMode.read)
    assert decision.compatibility_projection_required is (mode == TaskWorkflowMode.read)
    assert decision.intelligence_product_enabled is (mode == TaskWorkflowMode.read)


def test_production_resolver_ignores_the_retired_database_selector():
    decision = resolve_task_intelligence_for_user(
        uid='user-1', workflow_mode='read', account_generation=3, db_client=object()
    )

    assert decision.account_generation == 3
    assert decision.canonical_reads_authoritative is True
    assert decision.intelligence_product_enabled is True


def test_rollout_rejects_invalid_identity_and_generation():
    with pytest.raises(ValueError, match='uid is required'):
        resolve_task_intelligence_rollout(uid='', workflow_mode='off')
    with pytest.raises(ValueError, match='nonnegative'):
        resolve_task_intelligence_rollout(uid='user-1', workflow_mode='write', account_generation=-1)
