"""Runtime configuration contract for managed pre-recorded transcription."""

from __future__ import annotations

import os
from collections.abc import Mapping
from enum import Enum

MODULATE_API_KEY_ENV = 'MODULATE_API_KEY'
MODULATE_PROVIDER = 'modulate'


class TranscriptionOutcome(str, Enum):
    """Closed, low-cardinality vocabulary for every accepted transcription."""

    SUCCESS = 'success'
    EXPECTED_SILENCE = 'expected_silence'
    EMPTY_UNEXPECTED = 'empty_unexpected'
    TIMEOUT = 'timeout'
    UPSTREAM_ERROR = 'upstream_error'
    CONFIG_ERROR = 'config_error'
    INVALID_INPUT = 'invalid_input'


class PrerecordedSTTConfigurationError(RuntimeError):
    """The fixed managed STT adapter is not configured on this runtime."""

    def __init__(self, missing_env: str = MODULATE_API_KEY_ENV):
        self.provider = MODULATE_PROVIDER
        self.missing_env = missing_env
        super().__init__(f'managed pre-recorded STT requires {missing_env}')


def required_managed_stt_environment() -> tuple[str, ...]:
    """Return the deployment binding required by the fixed managed adapter."""

    return (MODULATE_API_KEY_ENV,)


def missing_managed_stt_environment(env: Mapping[str, str] | None = None) -> tuple[str, ...]:
    source = os.environ if env is None else env
    return tuple(name for name in required_managed_stt_environment() if not (source.get(name) or '').strip())


def require_managed_stt_environment(env: Mapping[str, str] | None = None) -> None:
    missing = missing_managed_stt_environment(env)
    if missing:
        raise PrerecordedSTTConfigurationError(missing[0])
