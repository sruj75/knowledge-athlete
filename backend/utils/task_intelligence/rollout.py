"""Pure task-intelligence workflow-migration decisions."""

# LIFECYCLE: permanent

from models.task_intelligence import TaskIntelligenceRolloutDecision, TaskWorkflowMode


def resolve_task_intelligence_rollout(
    *,
    uid: str,
    workflow_mode: TaskWorkflowMode | str,
    account_generation: int = 0,
) -> TaskIntelligenceRolloutDecision:
    mode = workflow_mode if isinstance(workflow_mode, TaskWorkflowMode) else TaskWorkflowMode(workflow_mode)
    if not uid:
        raise ValueError('uid is required')
    if account_generation < 0:
        raise ValueError('account_generation must be nonnegative')

    if mode == TaskWorkflowMode.off:
        return TaskIntelligenceRolloutDecision(
            uid=uid,
            workflow_mode=mode,
            account_generation=account_generation,
            legacy_reads_authoritative=True,
            legacy_writes_enabled=True,
            intelligence_evaluation_enabled=False,
            canonical_sidecar_writes_enabled=False,
            canonical_reads_authoritative=False,
            compatibility_projection_required=False,
            intelligence_product_enabled=False,
        )

    canonical_writes = mode in {TaskWorkflowMode.write, TaskWorkflowMode.read}
    canonical_reads = mode == TaskWorkflowMode.read
    return TaskIntelligenceRolloutDecision(
        uid=uid,
        workflow_mode=mode,
        account_generation=account_generation,
        legacy_reads_authoritative=not canonical_reads,
        legacy_writes_enabled=not canonical_reads,
        intelligence_evaluation_enabled=True,
        canonical_sidecar_writes_enabled=canonical_writes,
        canonical_reads_authoritative=canonical_reads,
        compatibility_projection_required=canonical_reads,
        intelligence_product_enabled=canonical_reads,
    )


def resolve_task_intelligence_for_user(
    *,
    uid: str,
    workflow_mode: TaskWorkflowMode | str,
    account_generation: int = 0,
    db_client=None,
) -> TaskIntelligenceRolloutDecision:
    """Resolve the retained workflow mode without a product-Memory dependency."""

    del db_client
    return resolve_task_intelligence_rollout(
        uid=uid,
        workflow_mode=workflow_mode,
        account_generation=account_generation,
    )


__all__ = ['resolve_task_intelligence_for_user', 'resolve_task_intelligence_rollout']
