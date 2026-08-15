from __future__ import annotations

from llm_gateway.gateway.auth import ServiceCaller
from llm_gateway.gateway.credentials import build_omi_managed_credential_context, is_fallback_eligible_by_default
from llm_gateway.gateway.schemas import CredentialPolicy, FailureClass


def test_managed_credential_context_contains_only_authenticated_caller():
    caller = ServiceCaller(name='backend', user_uid='user-123')

    context = build_omi_managed_credential_context(caller)

    assert context.caller == caller
    assert context.safe_model_dump() == {
        'caller': {
            'name': 'backend',
            'user_uid': 'user-123',
            'tenant_id': None,
        }
    }


def test_managed_policy_exposes_only_configured_fallbacks():
    policy = CredentialPolicy(
        fallback_eligible_failure_classes=[
            FailureClass.TIMEOUT_BEFORE_OUTPUT,
            FailureClass.PROVIDER_429_OMI_PAID,
            FailureClass.PROVIDER_5XX_OMI_PAID,
        ],
        never_fallback_failure_classes=[FailureClass.INVALID_CONFIG],
    )

    assert is_fallback_eligible_by_default(FailureClass.TIMEOUT_BEFORE_OUTPUT, policy)
    assert is_fallback_eligible_by_default(FailureClass.PROVIDER_429_OMI_PAID, policy)
    assert is_fallback_eligible_by_default(FailureClass.PROVIDER_5XX_OMI_PAID, policy)
    assert not is_fallback_eligible_by_default(FailureClass.INVALID_CONFIG, policy)
