"""Shared authentication and budget gates for managed desktop background inference."""

import os

from fastapi import Depends, HTTPException

from database import redis_db
from database import llm_usage as llm_usage_db
from utils.executors import critical_executor, db_executor, run_blocking
from utils.other.endpoints import get_current_participant_uid
from utils.subscription import enforce_chat_quota, is_trial_paywalled
from utils.llm.gemini_usage import GeminiUsage


async def enforce_conversation_quota(uid: str, turn_id: str) -> None:
    await run_blocking(db_executor, enforce_chat_quota, uid, platform='desktop')
    try:
        allowed, _, retry_after = await run_blocking(
            critical_executor, redis_db.check_rate_limit, uid, 'desktop_conversation_burst', 30, 60
        )
    except Exception as exc:
        raise HTTPException(status_code=503, detail='Conversation rate limiter is unavailable') from exc
    if not allowed:
        raise HTTPException(
            status_code=429,
            detail='Conversation request limit exceeded',
            headers={'Retry-After': str(max(1, retry_after))},
        )
    await run_blocking(
        db_executor,
        llm_usage_db.record_chat_quota_question,
        uid,
        f'conversation:{turn_id}',
        'desktop_chat',
        platform='desktop',
    )


async def record_conversation_usage(uid: str, usage: GeminiUsage) -> None:
    values = usage.wire()
    await run_blocking(
        db_executor,
        llm_usage_db.record_llm_usage_bucket,
        uid,
        values['input_tokens'],
        values['output_tokens'] + values['thinking_tokens'],
        values['cached_input_tokens'],
        0,
        usage.totalTokenCount if usage.totalTokenCount is not None else sum(values.values()),
        0.0,
    )


async def authorized_desktop_user(uid: str = Depends(get_current_participant_uid)) -> str:
    if await run_blocking(db_executor, is_trial_paywalled, uid, 'desktop'):
        raise HTTPException(status_code=402, detail='trial_expired')
    return uid


async def enforce_desktop_gemini_quota(uid: str) -> None:
    try:
        for policy, limit, window in [('desktop_gemini_burst', 30, 60), ('desktop_gemini_daily', 1500, 86_400)]:
            allowed, _, _ = await run_blocking(critical_executor, redis_db.check_rate_limit, uid, policy, limit, window)
            if not allowed:
                detail = (
                    'Daily Gemini request limit exceeded'
                    if policy == 'desktop_gemini_daily'
                    else 'Gemini request limit exceeded'
                )
                raise HTTPException(status_code=429, detail=detail)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail='Gemini rate limiter is unavailable') from exc


async def enforce_supervisor_quota(uid: str) -> None:
    daily_limit = 1500
    if os.environ.get('OMI_ENV_STAGE', '').strip().lower() in {'dev', 'local'}:
        try:
            configured = int(os.environ.get('SUPERVISOR_DAILY_REQUEST_LIMIT', '1500'))
            if 1 <= configured <= 100_000:
                daily_limit = configured
        except ValueError:
            pass
    try:
        for policy, limit, window, reason in [
            ('desktop_supervisor_burst', 30, 60, 'burst_quota'),
            ('desktop_supervisor_daily', daily_limit, 86_400, 'daily_quota'),
        ]:
            allowed, _, retry_after = await run_blocking(
                critical_executor, redis_db.check_rate_limit, uid, policy, limit, window
            )
            if not allowed:
                retry_after = max(1, retry_after)
                raise HTTPException(
                    status_code=429,
                    detail={'reason': reason, 'retry_after_seconds': retry_after},
                    headers={'Retry-After': str(retry_after)},
                )
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=503, detail='Supervisor rate limiter is unavailable') from exc


async def enforce_ai_observation_quota(uid: str) -> None:
    try:
        allowed, _, _ = await run_blocking(
            critical_executor, redis_db.check_rate_limit, uid, 'desktop_ai_observations', 120, 60
        )
    except Exception as exc:
        raise HTTPException(status_code=503, detail='Observation rate limiter is unavailable') from exc
    if not allowed:
        raise HTTPException(status_code=429, detail='Observation request limit exceeded')
