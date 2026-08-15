from __future__ import annotations

import pytest

from config.prerecorded_stt import (
    MODULATE_PROVIDER,
    PrerecordedSTTConfigurationError,
    require_managed_stt_environment,
    required_managed_stt_environment,
)


def test_managed_stt_has_one_product_owned_runtime_binding():
    assert required_managed_stt_environment() == ('MODULATE_API_KEY',)


def test_missing_modulate_configuration_fails_without_selecting_a_fallback():
    with pytest.raises(PrerecordedSTTConfigurationError) as exc_info:
        require_managed_stt_environment({})

    assert exc_info.value.provider == MODULATE_PROVIDER
    assert exc_info.value.missing_env == 'MODULATE_API_KEY'


def test_whitespace_only_modulate_binding_is_missing():
    with pytest.raises(PrerecordedSTTConfigurationError):
        require_managed_stt_environment({'MODULATE_API_KEY': '   '})


def test_nonempty_modulate_binding_satisfies_the_contract():
    require_managed_stt_environment({'MODULATE_API_KEY': 'configured'})
