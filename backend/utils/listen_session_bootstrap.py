"""Account-only admission snapshot for transient listen sessions."""

from __future__ import annotations

from dataclasses import dataclass

import database.users as user_db
from utils.executors import db_executor, run_blocking
from utils.fair_use import (
    FAIR_USE_ENABLED,
    FAIR_USE_RESTRICT_DAILY_MANAGED_STT_MS,
    get_enforcement_stage,
    is_managed_stt_budget_exhausted,
)
from utils.subscription import has_transcription_credits


@dataclass(frozen=True)
class ListenAdmissionSnapshot:
    user_exists: bool
    user_has_credits: bool
    fair_use_track_managed_stt_usage: bool
    fair_use_managed_stt_budget_exhausted: bool


async def load_listen_admission(uid: str) -> ListenAdmissionSnapshot:
    """Load account/entitlement state without hydrating product configuration."""
    user_exists = await run_blocking(db_executor, user_db.is_exists_user, uid)
    user_has_credits = await run_blocking(db_executor, has_transcription_credits, uid, source=None)

    track_managed_usage = False
    managed_budget_exhausted = False
    if FAIR_USE_ENABLED:
        stage = await run_blocking(db_executor, get_enforcement_stage, uid)
        if stage == "restrict" and FAIR_USE_RESTRICT_DAILY_MANAGED_STT_MS > 0:
            track_managed_usage = True
            managed_budget_exhausted = await run_blocking(db_executor, is_managed_stt_budget_exhausted, uid)

    return ListenAdmissionSnapshot(
        user_exists=user_exists,
        user_has_credits=user_has_credits,
        fair_use_track_managed_stt_usage=track_managed_usage,
        fair_use_managed_stt_budget_exhausted=managed_budget_exhausted,
    )
