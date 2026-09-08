from __future__ import annotations

import pytest

from config.participant_admission import (
    ParticipantAdmissionConfigurationError,
    ParticipantNotAdmittedError,
    RELEASE_PROBE_UID,
    require_hosted_participant,
)
from scripts.firebase_release_probe_token import PROBE_UID


def _hosted_env(participants: str) -> dict[str, str]:
    return {
        'OMI_ENV_STAGE': 'prod',
        'INTENTIVE_HOSTED_PARTICIPANT_UIDS': participants,
    }


@pytest.mark.parametrize('count', range(1, 6))
def test_hosted_runtime_admits_one_through_five_exact_firebase_uids(count: int):
    participants = [f'firebase-owner-{index}' for index in range(count)]
    env = _hosted_env(','.join(participants))

    for uid in participants:
        require_hosted_participant(uid, env)


@pytest.mark.parametrize('uid', ['firebase-owner', 'FIREBASE-OWNER', 'firebase-owner-extra', ''])
def test_hosted_runtime_denies_every_uid_without_an_exact_list_hit(uid: str):
    with pytest.raises(ParticipantNotAdmittedError, match='^participant_not_admitted$'):
        require_hosted_participant(uid, _hosted_env('firebase-owner-1,firebase-owner-2'))


@pytest.mark.parametrize(
    'participants',
    [
        '',
        '   ',
        'firebase-owner-1,',
        'firebase-owner-1,,firebase-owner-2',
        ' firebase-owner-1',
        'firebase-owner-1 ',
        'firebase-owner-1,firebase-owner-1',
        'firebase-1,firebase-2,firebase-3,firebase-4,firebase-5,firebase-6',
        RELEASE_PROBE_UID,
    ],
)
def test_hosted_runtime_rejects_missing_ambiguous_or_over_capacity_configuration(participants: str):
    with pytest.raises(ParticipantAdmissionConfigurationError, match='^participant_admission_unavailable$'):
        require_hosted_participant('firebase-owner-1', _hosted_env(participants))


def test_release_probe_is_a_reserved_system_principal_after_human_configuration_validates():
    require_hosted_participant(RELEASE_PROBE_UID, _hosted_env('firebase-owner-1'))

    with pytest.raises(ParticipantAdmissionConfigurationError, match='^participant_admission_unavailable$'):
        require_hosted_participant(RELEASE_PROBE_UID, _hosted_env(''))


def test_release_probe_uid_matches_the_existing_token_minter_contract():
    assert RELEASE_PROBE_UID == PROBE_UID


@pytest.mark.parametrize(
    'env',
    [
        {'OMI_ENV_STAGE': 'local'},
        {'OMI_ENV_STAGE': 'offline'},
        {'PROVIDER_MODE': 'offline'},
        {'LOCAL_DEVELOPMENT': 'true'},
    ],
)
def test_local_and_offline_runtimes_do_not_require_participant_configuration(env: dict[str, str]):
    require_hosted_participant('unlisted-local-user', env)


@pytest.mark.parametrize('credential_name', ['SERVICE_ACCOUNT_JSON', 'GOOGLE_APPLICATION_CREDENTIALS'])
def test_real_firebase_credentials_keep_local_development_flag_from_bypassing_hosted_admission(
    credential_name: str,
):
    env = {'LOCAL_DEVELOPMENT': 'true', credential_name: 'configured'}

    with pytest.raises(ParticipantAdmissionConfigurationError, match='^participant_admission_unavailable$'):
        require_hosted_participant('unlisted-local-user', env)


def test_invalid_environment_stage_fails_closed_without_reflecting_participant_values():
    private_uid = 'private-firebase-uid'
    env = {
        'OMI_ENV_STAGE': 'typo',
        'INTENTIVE_HOSTED_PARTICIPANT_UIDS': private_uid,
    }

    with pytest.raises(ParticipantAdmissionConfigurationError) as caught:
        require_hosted_participant(private_uid, env)

    assert str(caught.value) == 'participant_admission_unavailable'
    assert private_uid not in str(caught.value)
