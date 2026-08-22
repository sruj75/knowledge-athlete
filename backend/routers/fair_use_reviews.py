"""Authenticated transient fair-use classification handoff from the owner Mac."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException

from database.fair_use import (
    FairUseReviewProcessingClaimLost,
    apply_fair_use_review_result,
    claim_fair_use_review_processing,
    claim_fair_use_review_notification,
    get_fair_use_review_receipt,
    mark_fair_use_review_notification_sent,
    release_fair_use_review_processing,
    release_fair_use_review_notification,
)
from models.fair_use import FairUseClassificationRequest, FairUseClassificationResponse
from utils.executors import db_executor, run_blocking
from utils.fair_use import invalidate_enforcement_cache, send_fair_use_notification
from utils.fair_use_reviews import (
    get_pending_fair_use_review,
    mark_fair_use_review_consumed,
)
from utils.llm.fair_use_classifier import classify_fair_use_evidence
from utils.other.endpoints import get_current_user_uid

router = APIRouter()


def _utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _now() -> datetime:
    return datetime.now(timezone.utc)


def validate_pending_still_active(pending: dict) -> None:
    try:
        expires_at = datetime.fromisoformat(str(pending['expires_at']).replace('Z', '+00:00')).astimezone(timezone.utc)
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=404, detail='review_not_found') from None
    if _now() >= expires_at:
        raise HTTPException(status_code=404, detail='review_not_found')


def validate_evidence_window(request: FairUseClassificationRequest, pending: dict) -> None:
    try:
        requested_at = datetime.fromisoformat(str(pending['requested_at']).replace('Z', '+00:00')).astimezone(
            timezone.utc
        )
    except (KeyError, TypeError, ValueError):
        raise HTTPException(status_code=404, detail='review_not_found') from None

    previous: datetime | None = None
    oldest = requested_at - timedelta(days=7)
    for item in request.conversations:
        created_at = _utc(item.created_at)
        if created_at < oldest or created_at > requested_at or (previous is not None and created_at > previous):
            raise HTTPException(status_code=422, detail='invalid_evidence_window')
        previous = created_at


async def send_fair_use_notification_if_pending(uid: str, receipt: dict, *, allow_idempotent: bool = False) -> None:
    if (receipt.get('idempotent') and not allow_idempotent) or receipt.get('action') == 'none':
        return
    review_id = str(receipt['review_id'])
    claim_token = await run_blocking(db_executor, claim_fair_use_review_notification, uid, review_id)
    if claim_token is None:
        return
    delivered = False
    try:
        delivered = await send_fair_use_notification(
            uid, str(receipt['action']), case_ref=str(receipt.get('case_ref', ''))
        )
        if not delivered:
            raise RuntimeError('fair_use_notification_delivery_failed')
        await run_blocking(
            db_executor,
            mark_fair_use_review_notification_sent,
            uid,
            review_id,
            claim_token,
        )
    except Exception:
        # A definite pre-delivery failure is safe to retry. Once FCM reports a
        # successful send, retain the durable lease if marking fails: releasing
        # it would immediately admit a duplicate visible notification.
        if not delivered:
            await run_blocking(db_executor, release_fair_use_review_notification, uid, review_id, claim_token)
        raise


@router.post(
    '/v1/fair-use/reviews/{review_id}/classify',
    tags=['fair_use'],
    response_model=FairUseClassificationResponse,
)
async def classify_review(
    review_id: str,
    request: FairUseClassificationRequest,
    uid: str = Depends(get_current_user_uid),
) -> FairUseClassificationResponse:
    receipt = await run_blocking(db_executor, get_fair_use_review_receipt, uid, review_id)
    if receipt is not None:
        await run_blocking(db_executor, invalidate_enforcement_cache, uid)
        await send_fair_use_notification_if_pending(uid, receipt, allow_idempotent=True)
        return FairUseClassificationResponse.model_validate(receipt)

    pending = await run_blocking(db_executor, get_pending_fair_use_review, uid, review_id)
    if pending is None:
        raise HTTPException(status_code=404, detail='review_not_found')

    validate_evidence_window(request, pending)
    claim_token = await run_blocking(db_executor, claim_fair_use_review_processing, uid, review_id)
    if claim_token is None:
        receipt = await run_blocking(db_executor, get_fair_use_review_receipt, uid, review_id)
        if receipt is not None:
            await run_blocking(db_executor, invalidate_enforcement_cache, uid)
            await send_fair_use_notification_if_pending(uid, receipt, allow_idempotent=True)
            return FairUseClassificationResponse.model_validate(receipt)
        raise HTTPException(status_code=409, detail='review_in_progress')

    try:
        # A prior worker can commit between the route's first receipt read and
        # our atomic processing create/update. Recheck after ownership so that
        # race never pays for a duplicate GPT invocation.
        receipt = await run_blocking(db_executor, get_fair_use_review_receipt, uid, review_id)
        if receipt is not None:
            await run_blocking(db_executor, invalidate_enforcement_cache, uid)
            await send_fair_use_notification_if_pending(uid, receipt, allow_idempotent=True)
            return FairUseClassificationResponse.model_validate(receipt)
        evidence = [item.model_dump(mode='json') for item in request.conversations]
        classifier_result = await classify_fair_use_evidence(uid, evidence)
        # The model boundary can suspend. Recheck the admitted request's exact
        # server expiry immediately before enforcement. A concurrent accepted
        # request is fenced by the transactional durable receipt below.
        validate_pending_still_active(pending)
        receipt = await run_blocking(
            db_executor,
            apply_fair_use_review_result,
            uid,
            pending,
            classifier_result,
            claim_token=claim_token,
        )
        await run_blocking(db_executor, invalidate_enforcement_cache, uid)
        await run_blocking(db_executor, mark_fair_use_review_consumed, uid, review_id)
        await send_fair_use_notification_if_pending(uid, receipt)
        return FairUseClassificationResponse.model_validate(receipt)
    except FairUseReviewProcessingClaimLost:
        receipt = await run_blocking(db_executor, get_fair_use_review_receipt, uid, review_id)
        if receipt is not None:
            await run_blocking(db_executor, invalidate_enforcement_cache, uid)
            await send_fair_use_notification_if_pending(uid, receipt, allow_idempotent=True)
            return FairUseClassificationResponse.model_validate(receipt)
        raise HTTPException(status_code=409, detail='review_in_progress') from None
    finally:
        await run_blocking(db_executor, release_fair_use_review_processing, uid, review_id, claim_token)
