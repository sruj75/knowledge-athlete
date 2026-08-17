from __future__ import annotations

import logging
import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, cast

from fastapi import HTTPException
from firebase_admin import auth as firebase_auth

from config.free_plan import (
    FREE_CHAT_QUESTIONS_PER_MONTH,
    TRIAL_FEATURES,
    get_default_free_subscription,
    get_free_plan_limits,
)
import database.user_usage as user_usage_db
import database.users as users_db
from database import redis_db
from models.users import PlanLimits, PlanType, Subscription, TrialMetadata
from utils.observability.fallback import record_fallback

logger = logging.getLogger(__name__)


def _get_user(uid: str) -> Any:
    return firebase_auth.get_user(uid)  # type: ignore[reportUnknownMemberType]


DESKTOP_ACCESS_TIER_FREE = 'desktop_free'
DESKTOP_ACCESS_TIER_FULL = 'desktop_full'


def is_paid_plan(plan: PlanType) -> bool:
    return plan in {PlanType.bounded, PlanType.unlimited}


def plan_grants_desktop(plan: PlanType, subscription: Optional[Subscription] = None) -> bool:
    del subscription
    return is_paid_plan(plan)


def effective_desktop_access_tier(plan: PlanType, subscription: Optional[Subscription] = None) -> str:
    return DESKTOP_ACCESS_TIER_FULL if plan_grants_desktop(plan, subscription) else DESKTOP_ACCESS_TIER_FREE


def desktop_trial_paywall_eligible(plan: PlanType, subscription: Optional[Subscription] = None) -> bool:
    del subscription
    return plan is PlanType.free


def should_defer_desktop_processing(uid: str) -> bool:
    try:
        subscription = users_db.get_user_valid_subscription(uid)
        plan = subscription.plan if subscription else PlanType.free
        return effective_desktop_access_tier(plan, subscription) == DESKTOP_ACCESS_TIER_FREE
    except Exception as exc:
        logger.warning('should_defer_desktop_processing lookup failed for uid=%s: %s', uid, exc)
        return False


TRIAL_LENGTH_SECONDS = 3 * 24 * 60 * 60
TRIAL_PAYWALL_ENABLED = os.getenv('TRIAL_PAYWALL_ENABLED', 'false').lower() == 'true'
DESKTOP_PLATFORMS = {'macos', 'windows'}
_TRIAL_PAYWALL_DESKTOP_TOKENS = DESKTOP_PLATFORMS | {'desktop'}
_TRIAL_PAYWALL_CACHE_TTL_SECONDS = 300


def get_plan_limits(value: PlanType | Subscription) -> PlanLimits:
    if isinstance(value, Subscription):
        return value.limits
    if value is PlanType.free:
        return get_free_plan_limits()
    return PlanLimits()


def get_plan_features(value: PlanType | Subscription, simplified: bool = False) -> List[str]:
    del simplified
    if isinstance(value, Subscription):
        return list(value.features)
    if value is PlanType.free:
        return list(get_default_free_subscription().features)
    return []


def get_plan_display_name(value: PlanType | Subscription) -> str:
    if isinstance(value, Subscription):
        return value.plan_name
    return 'Free' if value is PlanType.free else value.value.capitalize()


def _is_trial_expired_uncached(uid: str) -> bool:
    try:
        subscription = users_db.get_user_valid_subscription(uid)
        plan = subscription.plan if subscription else PlanType.free
        if not desktop_trial_paywall_eligible(plan, subscription):
            return False
        user_record = _get_user(uid)
        creation_ms: int = cast(int, user_record.user_metadata.creation_timestamp)
        if not creation_ms:
            return False
        return time.time() - (creation_ms / 1000) > TRIAL_LENGTH_SECONDS
    except Exception as exc:
        logger.warning('trial paywall lookup failed for uid=%s: %s', uid, exc)
        return False


def _is_trial_expired_cached(uid: str) -> bool:
    cache_key = f'trial_paywall:expired:{uid}'
    cached = redis_db.get_generic_cache(cache_key)
    if cached is not None:
        if cached:
            try:
                subscription = users_db.get_user_valid_subscription(uid)
                plan = subscription.plan if subscription else PlanType.free
                if not desktop_trial_paywall_eligible(plan, subscription):
                    clear_trial_paywall_cache(uid)
                    record_fallback(
                        component='other',
                        from_mode='trial_paywall',
                        to_mode=effective_desktop_access_tier(plan, subscription),
                        reason='local_heal',
                        outcome='recovered',
                        log=logger,
                    )
                    return False
            except Exception as exc:
                logger.warning('trial paywall cache revalidation failed for uid=%s: %s', uid, exc)
                return False
        return bool(cached)
    expired = _is_trial_expired_uncached(uid)
    try:
        redis_db.set_generic_cache(cache_key, expired, ttl=_TRIAL_PAYWALL_CACHE_TTL_SECONDS)
    except Exception as exc:
        logger.debug('trial paywall cache set failed for uid=%s: %s', uid, exc)
    return expired


def is_trial_paywalled(uid: str, platform: Optional[str]) -> bool:
    if not TRIAL_PAYWALL_ENABLED:
        return False
    if not platform or platform.lower() not in _TRIAL_PAYWALL_DESKTOP_TOKENS:
        return False
    return _is_trial_expired_cached(uid)


def clear_trial_paywall_cache(uid: str) -> None:
    redis_db.delete_generic_cache(f'trial_paywall:expired:{uid}')


def get_trial_metadata(uid: str) -> TrialMetadata:
    try:
        if not TRIAL_PAYWALL_ENABLED:
            return TrialMetadata(
                trial_expired=False,
                trial_duration_seconds=TRIAL_LENGTH_SECONDS,
                trial_features=TRIAL_FEATURES,
                plan_after_trial='Free',
            )
        subscription = users_db.get_user_valid_subscription(uid)
        plan = subscription.plan if subscription else PlanType.free
        if not desktop_trial_paywall_eligible(plan, subscription):
            return TrialMetadata(
                trial_expired=False,
                trial_duration_seconds=TRIAL_LENGTH_SECONDS,
                trial_features=TRIAL_FEATURES,
                plan_after_trial='Free',
            )
        user_record = _get_user(uid)
        creation_ms: int = cast(int, user_record.user_metadata.creation_timestamp)
        if not creation_ms:
            raise ValueError('account has no creation timestamp')
        started_at = int(creation_ms / 1000)
        ends_at = started_at + TRIAL_LENGTH_SECONDS
        remaining = max(0, ends_at - int(time.time()))
        return TrialMetadata(
            trial_started_at=started_at,
            trial_ends_at=ends_at,
            trial_remaining_seconds=remaining,
            trial_expired=remaining == 0,
            trial_duration_seconds=TRIAL_LENGTH_SECONDS,
            trial_features=TRIAL_FEATURES,
            plan_after_trial='Free',
        )
    except Exception as exc:
        logger.warning('get_trial_metadata failed for uid=%s: %s', uid, exc)
        return TrialMetadata(
            trial_expired=False,
            trial_duration_seconds=TRIAL_LENGTH_SECONDS,
            trial_features=TRIAL_FEATURES,
            plan_after_trial='Free',
        )


def get_chat_quota_snapshot(uid: str, platform: Optional[str] = None) -> Dict[str, Any]:
    usage = user_usage_db.get_monthly_chat_usage(uid)
    if is_trial_paywalled(uid, platform):
        return {
            'plan': PlanType.free,
            'plan_name': 'Free',
            'unit': 'questions',
            'used': float(FREE_CHAT_QUESTIONS_PER_MONTH),
            'limit': float(FREE_CHAT_QUESTIONS_PER_MONTH),
            'allowed': False,
            'reset_at': usage['reset_at'],
        }

    subscription = users_db.get_user_valid_subscription(uid) or get_default_free_subscription()
    limits = subscription.limits if is_paid_plan(subscription.plan) else get_free_plan_limits()
    if limits.chat_cost_usd_per_month is not None:
        unit = 'cost_usd'
        used = float(usage['cost_usd'])
        limit_value = float(limits.chat_cost_usd_per_month)
    else:
        unit = 'questions'
        used = float(usage['questions'])
        limit_value = float(limits.chat_questions_per_month) if limits.chat_questions_per_month is not None else None
    allowed = limit_value is None or limit_value <= 0 or used < limit_value
    return {
        'plan': subscription.plan,
        'plan_name': subscription.plan_name,
        'unit': unit,
        'used': used,
        'limit': limit_value,
        'allowed': allowed,
        'reset_at': usage['reset_at'],
    }


def enforce_chat_quota(uid: str, platform: Optional[str] = None) -> None:
    snapshot = get_chat_quota_snapshot(uid, platform=platform)
    if snapshot['allowed']:
        return
    raise HTTPException(
        status_code=402,
        detail={
            'error': 'quota_exceeded',
            'plan': snapshot['plan_name'],
            'plan_type': snapshot['plan'].value,
            'unit': snapshot['unit'],
            'used': snapshot['used'],
            'limit': snapshot['limit'],
            'reset_at': snapshot['reset_at'],
        },
    )


def get_monthly_usage_for_subscription(uid: str) -> Dict[str, Any]:
    launch_date_raw = os.getenv('SUBSCRIPTION_LAUNCH_DATE')
    if not launch_date_raw:
        return {}
    try:
        launch_date = datetime.strptime(launch_date_raw, '%Y-%m-%d').replace(tzinfo=timezone.utc)
    except ValueError:
        return {}
    now = datetime.now(timezone.utc)
    if now < launch_date:
        return {}
    return user_usage_db.get_monthly_usage_stats_since(uid, now, launch_date)


def has_transcription_credits(uid: str, source: Optional[str] = None) -> bool:
    if is_trial_paywalled(uid, source):
        return False
    subscription = users_db.get_user_valid_subscription(uid) or get_default_free_subscription()
    limit = subscription.limits.transcription_seconds
    if limit is None or limit <= 0:
        return True
    usage = get_monthly_usage_for_subscription(uid)
    return int(usage.get('transcription_seconds', 0)) < limit


def get_remaining_transcription_seconds(uid: str, source: Optional[str] = None) -> int | None:
    if is_trial_paywalled(uid, source):
        return 0
    subscription = users_db.get_user_valid_subscription(uid) or get_default_free_subscription()
    limit = subscription.limits.transcription_seconds
    if limit is None or limit <= 0:
        return None
    usage = get_monthly_usage_for_subscription(uid)
    return max(0, limit - int(usage.get('transcription_seconds', 0)))
