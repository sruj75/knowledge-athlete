from __future__ import annotations

from typing import List, Dict, Any, Optional
import os
import asyncio

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ConfigDict, Field

from database import user_usage as user_usage_db, llm_usage as llm_usage_db
from database.job_run_locks import release_job_run_lock, try_acquire_job_run_lock
from services.users.data_export import iter_user_data_export
from services.users.account_deletion import background_wipe_user_data, start_account_deletion
from database.app_review_config import should_hide_subscription_ui
from database.users import (
    claim_deletion_wipe_for_task,
    resolve_deletion_wipe_job_id,
    resolve_legacy_deletion_wipe_uid,
)
from config.stt_provider_policy import supports_live_multilingual_mode
from config.free_plan import get_default_free_subscription
from utils.user_language import normalize_user_language
from database.users import *
from models.shared import StatusResponse
from datetime import datetime

from models.users import (
    ChatUsageQuota,
    ChatQuotaUnit,
    UserSubscriptionResponse,
    SubscriptionPlan,
    PlanType,
    PricingOption,
    TrialMetadata,
)
from utils.subscription import (
    get_chat_quota_snapshot,
    get_plan_limits,
    get_plan_features,
    get_monthly_usage_for_subscription,
    is_trial_paywalled,
    get_trial_metadata,
)
from utils.billing.service import catalog_price_strings_for_config, load_billing_config
from utils.cloud_tasks import (
    AccountDeletionTaskAuthentication,
    get_account_deletion_tasks_max_attempts,
    verify_account_deletion_cloud_tasks_oidc,
)
from utils.executors import cleanup_executor, db_executor, run_blocking
from utils.log_sanitizer import sanitize
from utils.other import endpoints as auth
import logging

logger = logging.getLogger(__name__)

router = APIRouter()


class UserStatusResponse(BaseModel):
    status: str
    message: Optional[str] = None


class UserProfileResponse(BaseModel):
    # The account profile is an explicit retained-control projection. Product
    # fields left in an inherited Firestore document must never become API
    # compatibility surface merely because they are present in that document.
    model_config = ConfigDict(extra='ignore')

    uid: str
    email: Optional[str] = None
    time_zone: Optional[str] = None
    created_at: Optional[datetime] = None
    motivation: Optional[str] = None
    use_case: Optional[str] = None
    job: Optional[str] = None
    company: Optional[str] = None


class UserDataExportResponse(BaseModel):
    schema_version: int
    account: Dict[str, Any] = Field(default_factory=dict)
    subscription: Optional[Dict[str, Any]] = None
    usage: Dict[str, Any] = Field(default_factory=dict)


class UserLanguageResponse(BaseModel):
    language: Optional[str] = None


class UserLanguageUpdateResponse(UserStatusResponse):
    single_language_mode: bool


@router.get('/v1/users/profile', tags=['v1'], response_model=UserProfileResponse)
def get_user_profile_endpoint(uid: str = Depends(auth.get_current_user_uid)):
    """Return the retained account profile projection."""
    profile = get_user_profile(uid)
    if not profile:
        raise HTTPException(status_code=410, detail="User not found")
    profile.pop('name', None)
    profile.setdefault('uid', uid)
    return profile


@router.delete('/v1/users/delete-account', tags=['v1'], response_model=UserStatusResponse)
def delete_account(uid: str = Depends(auth.get_current_user_uid)):
    try:
        return start_account_deletion(uid)
    except Exception as e:
        logger.info(f'delete_account {sanitize(str(e))}')
        raise HTTPException(status_code=500, detail='Could not delete account. Please try again.')


# response_model omitted: include_in_schema=False Cloud Tasks handler; JSONResponse
# status codes drive queue retry/ack behavior.
@router.post('/v1/users/account-deletion-wipes/run', include_in_schema=False)
async def run_account_deletion_wipe(
    request: Request,
    task_authentication: AccountDeletionTaskAuthentication = Depends(verify_account_deletion_cloud_tasks_oidc),
):
    try:
        payload = await request.json()
        if not isinstance(payload, dict):
            raise ValueError('payload must be a JSON object')
        if 'job_id' in payload:
            wipe_job_id = payload['job_id']
            if not isinstance(wipe_job_id, str) or not wipe_job_id:
                raise ValueError('job_id must be a non-empty string')
            resolution_fn = resolve_deletion_wipe_job_id
            resolution_arg = wipe_job_id
            payload_kind = 'job_id'
        else:
            # TODO(#9760): Remove this legacy branch after the Cloud Tasks max-retry window has elapsed.
            legacy_uid = payload.get('uid')
            if not isinstance(legacy_uid, str) or not legacy_uid:
                raise ValueError('job_id must be a non-empty string')
            resolution_fn = resolve_legacy_deletion_wipe_uid
            resolution_arg = legacy_uid
            payload_kind = 'legacy_uid'
    except Exception as e:
        logger.error(f'account_deletion handler: invalid payload, dropping task: {sanitize(str(e))}')
        return JSONResponse(status_code=200, content={'status': 'dropped', 'reason': 'invalid_payload'})

    if task_authentication.audience == 'legacy' and payload_kind != 'legacy_uid':
        logger.warning('account_deletion handler: dropping job-ID payload with legacy audience')
        return JSONResponse(status_code=200, content={'status': 'dropped', 'reason': 'legacy_audience_for_job_id'})

    if payload_kind == 'legacy_uid' and task_authentication.audience != 'legacy':
        logger.warning('account_deletion handler: dropping legacy uid payload with non-legacy audience')
        return JSONResponse(
            status_code=200, content={'status': 'dropped', 'reason': 'legacy_uid_requires_legacy_audience'}
        )

    try:
        resolution = await run_blocking(db_executor, resolution_fn, resolution_arg)
    except Exception as e:
        logger.error(f'account_deletion handler: job resolution failed, will retry: {sanitize(str(e))}')
        return JSONResponse(status_code=500, content={'status': 'retry'})

    resolution_outcome = resolution.get('outcome') if isinstance(resolution, dict) else None
    uid = resolution.get('uid') if isinstance(resolution, dict) else None
    if resolution_outcome != 'resolved' or not isinstance(uid, str) or not uid:
        logger.warning(
            'account_deletion handler: dropping task payload_kind=%s resolution=%s', payload_kind, resolution_outcome
        )
        return JSONResponse(
            status_code=200, content={'status': 'dropped', 'reason': resolution_outcome or 'invalid_job'}
        )

    lock_key = f'account-deletion:{uid}'
    lock_token = await run_blocking(db_executor, try_acquire_job_run_lock, lock_key)
    if not lock_token:
        logger.warning(f'account_deletion handler: run-lock held for {uid}, deferring')
        return JSONResponse(status_code=409, content={'status': 'locked'})

    release_lock = True
    try:
        claim_status = await run_blocking(db_executor, claim_deletion_wipe_for_task, uid)
        if claim_status == 'completed':
            return JSONResponse(status_code=200, content={'status': 'acked', 'job_status': 'completed'})
        if claim_status == 'running':
            return JSONResponse(status_code=409, content={'status': 'running'})
        if claim_status != 'claimed':
            logger.warning(f'account_deletion handler: non-actionable task for {uid}, claim_status={claim_status}')
            return JSONResponse(status_code=200, content={'status': 'dropped', 'reason': claim_status})

        max_attempts = get_account_deletion_tasks_max_attempts()
        terminal = task_authentication.retry_count >= max_attempts - 1
        ok = await run_blocking(
            cleanup_executor,
            background_wipe_user_data,
            uid,
            task_authentication.retry_count,
            terminal,
        )
        if ok:
            return JSONResponse(status_code=200, content={'status': 'done'})

        if terminal:
            logger.error(
                f'account_deletion handler: final attempt {task_authentication.retry_count + 1} failed for {uid}'
            )
            return JSONResponse(status_code=200, content={'status': 'failed_final'})

        logger.warning(
            f'account_deletion handler: attempt {task_authentication.retry_count + 1} failed for {uid}, will retry'
        )
        return JSONResponse(status_code=500, content={'status': 'retry'})
    except asyncio.CancelledError:
        release_lock = False
        logger.warning(f'account_deletion handler cancelled for {uid}; preserving run-lock until TTL')
        raise
    finally:
        if release_lock:
            await run_blocking(db_executor, release_job_run_lock, lock_key, lock_token)


# ***************************************
# ************* Language ****************
# ***************************************


@router.get('/v1/users/language', tags=['v1'], response_model=UserLanguageResponse)
def get_user_language(uid: str = Depends(auth.get_current_user_uid)):
    """Get the user's preferred language."""
    language = get_user_language_preference(uid)
    return {'language': language or None}


class SetUserLanguageRequest(BaseModel):
    language: str


@router.patch('/v1/users/language', tags=['v1'], response_model=UserLanguageUpdateResponse)
def set_user_language(data: SetUserLanguageRequest, uid: str = Depends(auth.get_current_user_uid)):
    """Set the user's preferred language (e.g., 'en', 'vi', etc.)."""
    language = normalize_user_language(data.language)
    if not language:
        raise HTTPException(status_code=400, detail="A supported language code is required")
    set_user_language_preference(uid, language)
    single_language_mode = not supports_live_multilingual_mode(language)
    return {'status': 'ok', 'single_language_mode': single_language_mode}


# **************************************
# ************* Usage ******************
# **************************************


@router.get('/v1/users/me/subscription', tags=['v1'], response_model=UserSubscriptionResponse)
def get_user_subscription_endpoint(
    uid: str = Depends(auth.get_current_user_uid),
    x_app_platform: Optional[str] = Header(None, alias='X-App-Platform'),
    x_app_version: Optional[str] = Header(None, alias='X-App-Version'),
):
    """Return the server-owned subscription, usage, and billing capability."""
    billing_config = load_billing_config()
    subscription = get_user_valid_subscription(uid)
    if not subscription:
        subscription = get_default_free_subscription()

    subscription.limits = get_plan_limits(subscription)
    is_mobile = x_app_platform in ('ios', 'android')
    subscription.features = get_plan_features(subscription, simplified=is_mobile)

    usage = get_monthly_usage_for_subscription(uid)
    transcription_seconds_used = usage.get('transcription_seconds', 0)
    words_transcribed_used = usage.get('words_transcribed', 0)
    insights_gained_used = usage.get('insights_gained', 0)
    transcription_seconds_limit = subscription.limits.transcription_seconds or 0
    words_transcribed_limit = subscription.limits.words_transcribed or 0
    insights_gained_limit = subscription.limits.insights_gained or 0
    available_plans: List[SubscriptionPlan] = []
    if billing_config.catalog is not None:
        catalog_prices = catalog_price_strings_for_config(billing_config)
        available_plans = [
            SubscriptionPlan(
                id=plan.id,
                title=plan.title,
                subtitle=plan.subtitle,
                description=plan.description,
                eyebrow=plan.eyebrow,
                features=plan.features,
                prices=[
                    PricingOption(
                        id=offer.id,
                        title=offer.title,
                        price_string=catalog_prices[offer.id],
                        description=offer.description,
                        interval=offer.interval,
                    )
                    for offer in plan.offers
                ],
            )
            for plan in billing_config.catalog.plans
        ]

    show_subscription_ui = not should_hide_subscription_ui(uid, x_app_platform, x_app_version)

    # Chat quota — reuse the shared snapshot helper
    chat_snapshot = get_chat_quota_snapshot(uid, platform=x_app_platform)
    chat_percent = 0.0
    if chat_snapshot['limit'] is not None and chat_snapshot['limit'] > 0:
        chat_percent = min(100.0, round(100.0 * chat_snapshot['used'] / chat_snapshot['limit'], 2))
    chat_allowed = chat_snapshot['allowed']

    return UserSubscriptionResponse(
        subscription=subscription,
        transcription_seconds_used=transcription_seconds_used,
        transcription_seconds_limit=transcription_seconds_limit,
        words_transcribed_used=words_transcribed_used,
        words_transcribed_limit=words_transcribed_limit,
        insights_gained_used=insights_gained_used,
        insights_gained_limit=insights_gained_limit,
        available_plans=available_plans,
        billing_availability=billing_config.availability,
        show_subscription_ui=show_subscription_ui,
        chat_quota_used=round(chat_snapshot['used'], 4),
        chat_quota_unit=chat_snapshot['unit'],
        chat_quota_percent=chat_percent,
        chat_quota_allowed=chat_allowed,
        chat_quota_reset_at=chat_snapshot['reset_at'],
    )


@router.get('/v1/users/me/usage-quota', tags=['users'], response_model=ChatUsageQuota)
def get_user_chat_usage_quota(
    uid: str = Depends(auth.get_current_user_uid),
    x_app_platform: Optional[str] = Header(None, alias='X-App-Platform'),
):
    """Current-month chat usage for the user, plus their plan's cap.

    Used by the desktop app. Mobile uses the subscription endpoint instead.
    """
    snapshot = get_chat_quota_snapshot(uid, platform=x_app_platform)
    plan = snapshot['plan']

    if snapshot['limit'] is not None and snapshot['limit'] > 0:
        percent = min(100.0, round(100.0 * snapshot['used'] / snapshot['limit'], 2))
    else:
        percent = 0.0

    return ChatUsageQuota(
        plan=snapshot['plan_name'],
        plan_type=plan.value,
        unit=ChatQuotaUnit(snapshot['unit']),
        used=round(snapshot['used'], 4),
        limit=snapshot['limit'],
        percent=percent,
        allowed=snapshot['allowed'],
        reset_at=snapshot['reset_at'],
    )


class PaywallStatusResponse(BaseModel):
    paywalled: bool


@router.get('/v1/users/me/paywall', tags=['users'], response_model=PaywallStatusResponse)
def get_user_paywall_status(
    uid: str = Depends(auth.get_current_user_uid),
    x_app_platform: Optional[str] = Header(None, alias='X-App-Platform'),
    platform: Optional[str] = Query(None),
):
    """Trial-paywall status for the calling user on the given platform.

    Used by canonical desktop provider paths to decide whether to admit
    paid LLM / TTS traffic. Mirrors the exact semantics of
    `is_trial_paywalled`: basic plan + Firebase Auth account >3d old + platform
    in {macos, desktop}. Mobile platforms always
    return `paywalled=false`.

    Platform comes from `X-App-Platform` header (preferred) or `platform`
    query param (fallback). Unknown / missing platforms are never paywalled.
    """
    resolved_platform = x_app_platform or platform
    return PaywallStatusResponse(paywalled=is_trial_paywalled(uid, resolved_platform))


@router.get('/v1/users/me/trial', tags=['users'], response_model=TrialMetadata)
def get_user_trial_status(uid: str = Depends(auth.get_current_user_uid)):
    """Structured trial metadata for the calling user.

    Returns trial timing info (start, end, remaining seconds, expired flag)
    plus the list of features available during trial and the plan the user
    falls to after trial expiry. Used by desktop clients to render countdown
    banners and pre-expiry upgrade nudges.

    Paid-plan users get `trial_expired=False` with zeroed timing because the
    account-age trial is irrelevant to them.
    """
    return get_trial_metadata(uid)


class LlmTotalCostResponse(BaseModel):
    total_cost_usd: float


# response_model omitted: this streams a chunked JSON document via StreamingResponse (not a single JSON object);
# the responses= override documents the streamed shape in OpenAPI without enforcing response_model validation.
@router.get('/v1/users/export', tags=['v1'], responses={200: {'model': UserDataExportResponse}})
def export_all_user_data(uid: str = Depends(auth.get_current_user_uid)):
    """Export retained server-owned account and entitlement metadata."""
    return StreamingResponse(
        iter_user_data_export(uid),
        media_type='application/json',
        headers={'Content-Disposition': 'attachment; filename="intentive-account-metadata.json"'},
    )


@router.get('/v1/users/me/llm-usage/total', tags=['users'], response_model=LlmTotalCostResponse)
def get_total_llm_cost(uid: str = Depends(auth.get_current_user_uid)):
    total = llm_usage_db.get_total_llm_cost(uid)
    return {'total_cost_usd': total}
