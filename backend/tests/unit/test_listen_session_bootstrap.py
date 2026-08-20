"""Account-only bootstrap coverage for transient listen."""

import pytest

from utils import listen_session_bootstrap as bootstrap


@pytest.mark.asyncio
async def test_admission_reads_only_account_and_entitlement_state(monkeypatch):
    calls = []

    async def immediate(_executor, function, *args, **kwargs):
        calls.append((function, args, kwargs))
        if function is bootstrap.user_db.is_exists_user:
            return True
        if function is bootstrap.has_transcription_credits:
            return True
        raise AssertionError(f"unexpected listen bootstrap read: {function}")

    monkeypatch.setattr(bootstrap, "run_blocking", immediate)
    monkeypatch.setattr(bootstrap, "FAIR_USE_ENABLED", False)

    snapshot = await bootstrap.load_listen_admission("uid-1")

    assert snapshot.user_exists is True
    assert snapshot.user_has_credits is True
    assert calls == [
        (bootstrap.user_db.is_exists_user, ("uid-1",), {}),
        (bootstrap.has_transcription_credits, ("uid-1",), {"source": None}),
    ]


@pytest.mark.asyncio
async def test_restrict_stage_loads_only_fair_use_account_state(monkeypatch):
    calls = []

    async def immediate(_executor, function, *args, **kwargs):
        calls.append(function)
        values = {
            bootstrap.user_db.is_exists_user: True,
            bootstrap.has_transcription_credits: False,
            bootstrap.get_enforcement_stage: "restrict",
            bootstrap.is_managed_stt_budget_exhausted: True,
        }
        return values[function]

    monkeypatch.setattr(bootstrap, "run_blocking", immediate)
    monkeypatch.setattr(bootstrap, "FAIR_USE_ENABLED", True)
    monkeypatch.setattr(bootstrap, "FAIR_USE_RESTRICT_DAILY_MANAGED_STT_MS", 60_000)

    snapshot = await bootstrap.load_listen_admission("uid-1")

    assert snapshot.fair_use_track_managed_stt_usage is True
    assert snapshot.fair_use_managed_stt_budget_exhausted is True
    assert calls == [
        bootstrap.user_db.is_exists_user,
        bootstrap.has_transcription_credits,
        bootstrap.get_enforcement_stage,
        bootstrap.is_managed_stt_budget_exhausted,
    ]
