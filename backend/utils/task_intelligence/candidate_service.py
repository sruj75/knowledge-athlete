"""Candidate lifecycle orchestration."""

from typing import Optional, Protocol

import database.action_items as action_items_db
import database.candidates as candidates_db
import database.workstreams as workstreams_db
from models.candidate import (
    CandidateAction,
    CandidateCreate,
    CandidateRecord,
    CandidateResolutionReceipt,
    CandidateStatus,
    CandidateSubjectKind,
)
from utils.task_intelligence import task_links
from utils.task_intelligence.workstream_index import refresh_workstream_association_index


class WorkstreamCandidateResolver(Protocol):
    def __call__(self, uid: str, candidate: CandidateRecord, account_generation: int) -> CandidateResolutionReceipt: ...


_workstream_resolver: Optional[WorkstreamCandidateResolver] = workstreams_db.resolve_workstream_candidate


def register_workstream_candidate_resolver(resolver: WorkstreamCandidateResolver) -> None:
    global _workstream_resolver
    _workstream_resolver = resolver


def clear_workstream_candidate_resolver() -> None:
    global _workstream_resolver
    _workstream_resolver = None


def create_candidate(
    uid: str,
    proposal: CandidateCreate,
    *,
    idempotency_key: str,
    account_generation: int,
) -> CandidateRecord:
    return candidates_db.create_candidate(
        uid,
        proposal,
        idempotency_key=idempotency_key,
        account_generation=account_generation,
    )


def accept_candidate(uid: str, candidate_id: str, *, account_generation: int) -> CandidateResolutionReceipt:
    candidate = candidates_db.get_candidate(uid, candidate_id)
    if candidate is None:
        raise candidates_db.CandidateNotFoundError(candidate_id)
    if candidate.subject_kind == CandidateSubjectKind.workstream:
        if _workstream_resolver is None:
            raise candidates_db.WorkstreamCandidateResolverUnavailableError(
                'Ticket 04 workstream resolver is not registered'
            )
        try:
            receipt = _workstream_resolver(uid, candidate, account_generation)
        except workstreams_db.WorkstreamNotFoundError as exc:
            raise candidates_db.CandidateNotFoundError(candidate_id) from exc
        except workstreams_db.WorkstreamGenerationMismatchError as exc:
            raise candidates_db.CandidateGenerationMismatchError(candidate_id) from exc
        except workstreams_db.WorkstreamConflictError as exc:
            raise candidates_db.CandidateConflictError(str(exc)) from exc
        if receipt.workstream_id:
            refresh_workstream_association_index(uid, receipt.workstream_id)
        return receipt

    expected_task_links = None
    final_goal_id = candidate.goal_id
    final_workstream_id = candidate.workstream_id
    if candidate.proposed_action != CandidateAction.create:
        task_id = candidate.task_id
        if task_id is None:
            raise candidates_db.CandidateConflictError('task mutation Candidate is missing task_id')
        task = action_items_db.get_action_item(uid, task_id)
        if task is None:
            raise candidates_db.CandidateNotFoundError(f'task:{task_id}')
        expected_task_links = (task.get('goal_id'), task.get('workstream_id'))
        if final_goal_id is None:
            final_goal_id = expected_task_links[0]
        if final_workstream_id is None:
            final_workstream_id = expected_task_links[1]
    task_links.validate_task_links(uid, goal_id=final_goal_id, workstream_id=final_workstream_id)
    receipt = candidates_db.resolve_task_candidate(
        uid,
        candidate_id,
        account_generation=account_generation,
        expected_task_links=expected_task_links,
    )
    return receipt


def reject_candidate(
    uid: str,
    candidate_id: str,
    *,
    reason: Optional[str],
    account_generation: int,
) -> CandidateResolutionReceipt:
    return candidates_db.resolve_candidate_without_mutation(
        uid,
        candidate_id,
        status=CandidateStatus.rejected,
        reason=reason,
        account_generation=account_generation,
    )


def expire_candidate(
    uid: str,
    candidate_id: str,
    *,
    reason: Optional[str],
    account_generation: int,
) -> CandidateResolutionReceipt:
    return candidates_db.resolve_candidate_without_mutation(
        uid,
        candidate_id,
        status=CandidateStatus.expired,
        reason=reason,
        account_generation=account_generation,
    )


__all__ = [
    'WorkstreamCandidateResolver',
    'accept_candidate',
    'clear_workstream_candidate_resolver',
    'create_candidate',
    'expire_candidate',
    'register_workstream_candidate_resolver',
    'reject_candidate',
]
