"""Provider retry decision guard retained for the open failure-class registry.

S-11 removes the hosted Chat agent loop that originally consumed these helpers.
The failure-class lifecycle changes in a separate registry PR, so this file keeps
the still-valid pure classification and retry-budget contract without restoring
the deleted agent harness.
"""

import types

from utils.retrieval.safety import (
    is_transient_provider_error,
    provider_fallback_reason,
    should_retry_provider_error,
)


class ReadTimeout(Exception):
    pass


class RemoteProtocolError(Exception):
    pass


class _StatusError(Exception):
    def __init__(self, status_code):
        super().__init__(f'status {status_code}')
        self.status_code = status_code


class InternalServerError(_StatusError):
    def __init__(self):
        super().__init__(500)


class BadRequestError(_StatusError):
    def __init__(self):
        super().__init__(400)


class RateLimitError(_StatusError):
    def __init__(self):
        super().__init__(429)


class TestIsTransientProviderError:
    def test_transport_errors_are_transient(self):
        assert is_transient_provider_error(ReadTimeout())
        assert is_transient_provider_error(RemoteProtocolError())

    def test_provider_5xx_is_transient(self):
        assert is_transient_provider_error(InternalServerError())
        assert is_transient_provider_error(_StatusError(503))
        assert is_transient_provider_error(_StatusError(529))

    def test_client_errors_are_not_transient(self):
        assert not is_transient_provider_error(BadRequestError())
        assert not is_transient_provider_error(_StatusError(401))

    def test_rate_limit_is_not_retried_within_the_turn(self):
        assert not is_transient_provider_error(RateLimitError())

    def test_unknown_exception_is_not_transient(self):
        assert not is_transient_provider_error(ValueError('boom'))

    def test_status_wins_over_a_transport_sounding_name(self):
        class ReadTimeout(_StatusError):  # noqa: F811 - status must win over the name
            def __init__(self):
                super().__init__(400)

        assert not is_transient_provider_error(ReadTimeout())

    def test_status_read_from_a_response_attribute(self):
        error = Exception('wrapped')
        error.response = types.SimpleNamespace(status_code=503)
        assert is_transient_provider_error(error)


class TestProviderFallbackReason:
    def test_timeout(self):
        assert provider_fallback_reason(ReadTimeout()) == 'timeout'

    def test_provider_5xx(self):
        assert provider_fallback_reason(InternalServerError()) == 'provider_5xx'

    def test_provider_429(self):
        assert provider_fallback_reason(RateLimitError()) == 'provider_429'

    def test_unclassified(self):
        assert provider_fallback_reason(RemoteProtocolError()) == 'other'
        assert provider_fallback_reason(BadRequestError()) == 'other'

    def test_reasons_are_in_the_shared_bounded_set(self):
        from utils.observability.fallback import ALLOWED_REASONS

        for error in (ReadTimeout(), InternalServerError(), RateLimitError(), BadRequestError()):
            assert provider_fallback_reason(error) in ALLOWED_REASONS


class TestShouldRetryProviderError:
    def _decide(self, error=None, **overrides):
        kwargs = {
            'attempts_made': 1,
            'max_attempts': 3,
            'text_already_streamed': False,
            'seconds_remaining': 150.0,
            'min_headroom_seconds': 45.0,
        }
        kwargs.update(overrides)
        return should_retry_provider_error(error or ReadTimeout(), **kwargs)

    def test_transient_failure_before_any_output_is_retried(self):
        assert self._decide() is True

    def test_streamed_text_blocks_a_retry(self):
        assert self._decide(text_already_streamed=True) is False

    def test_attempt_budget_is_respected(self):
        assert self._decide(attempts_made=2, max_attempts=3) is True
        assert self._decide(attempts_made=3, max_attempts=3) is False

    def test_no_retry_that_cannot_finish_in_the_remaining_time(self):
        assert self._decide(seconds_remaining=44.0, min_headroom_seconds=45.0) is False
        assert self._decide(seconds_remaining=45.0, min_headroom_seconds=45.0) is True

    def test_non_transient_failure_is_not_retried(self):
        assert self._decide(error=BadRequestError()) is False
