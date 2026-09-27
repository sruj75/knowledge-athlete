"""Shared authentication and budget gates for managed desktop background inference."""

from fastapi import Depends, HTTPException

from database import redis_db
from utils.executors import critical_executor, db_executor, run_blocking
from utils.other.endpoints import get_current_participant_uid
from utils.subscription import is_trial_paywalled


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


async def enforce_ai_observation_quota(uid: str) -> None:
    try:
        allowed, _, _ = await run_blocking(
            critical_executor, redis_db.check_rate_limit, uid, 'desktop_ai_observations', 120, 60
        )
    except Exception as exc:
        raise HTTPException(status_code=503, detail='Observation rate limiter is unavailable') from exc
    if not allowed:
        raise HTTPException(status_code=429, detail='Observation request limit exceeded')
