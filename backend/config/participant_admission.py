"""Fail-closed participant admission for hosted compute surfaces."""

from __future__ import annotations

import os

from utils.env_loader import EnvStage, stage_from_env

PARTICIPANT_UIDS_ENV = "INTENTIVE_HOSTED_PARTICIPANT_UIDS"
MAX_HUMAN_PARTICIPANTS = 5
RELEASE_PROBE_UID = "intentive-release-probe"

_FIREBASE_CREDENTIAL_ENV_KEYS = (
    "SERVICE_ACCOUNT_JSON",
    "GOOGLE_APPLICATION_CREDENTIALS",
)


class ParticipantAdmissionConfigurationError(RuntimeError):
    """The hosted participant policy is absent or invalid."""

    def __init__(self) -> None:
        super().__init__("participant_admission_unavailable")


class ParticipantNotAdmittedError(PermissionError):
    """The authenticated Firebase principal is not an admitted participant."""

    def __init__(self) -> None:
        super().__init__("participant_not_admitted")


def _is_local_or_offline(environ: dict[str, str]) -> bool:
    try:
        stage = stage_from_env(environ)
    except ValueError as exc:
        raise ParticipantAdmissionConfigurationError() from exc

    # Cloud Run injects K_SERVICE even when a local stage was mistakenly configured.
    if environ.get("K_SERVICE", "").strip() or stage in {EnvStage.DEV.value, EnvStage.PROD.value}:
        return False

    if stage in {EnvStage.LOCAL.value, EnvStage.OFFLINE.value}:
        return True

    no_firebase_credentials = not any(environ.get(key, "").strip() for key in _FIREBASE_CREDENTIAL_ENV_KEYS)
    return environ.get("LOCAL_DEVELOPMENT") == "true" and no_firebase_credentials


def _configured_human_uids(environ: dict[str, str]) -> frozenset[str]:
    raw = environ.get(PARTICIPANT_UIDS_ENV, "")
    uids = raw.split(",")

    if (
        not raw.strip()
        or any(not uid for uid in uids)
        or any(uid != uid.strip() for uid in uids)
        or len(uids) > MAX_HUMAN_PARTICIPANTS
        or len(set(uids)) != len(uids)
        or RELEASE_PROBE_UID in uids
    ):
        raise ParticipantAdmissionConfigurationError()

    return frozenset(uids)


def require_hosted_participant(uid: str, environ: dict[str, str] | None = None) -> None:
    """Admit an exact configured human UID or the reserved release-probe UID."""

    source = dict(os.environ) if environ is None else environ
    if _is_local_or_offline(source):
        return

    human_uids = _configured_human_uids(source)
    if uid == RELEASE_PROBE_UID or uid in human_uids:
        return

    raise ParticipantNotAdmittedError()
