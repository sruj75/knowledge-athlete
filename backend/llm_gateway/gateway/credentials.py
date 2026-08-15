from __future__ import annotations

from llm_gateway.gateway.auth import ServiceCaller
from llm_gateway.gateway.schemas import CredentialPolicy, FailureClass, StrictBaseModel


class CredentialContext(StrictBaseModel):
    """Authenticated managed-service caller context for provider execution."""

    caller: ServiceCaller

    def safe_model_dump(self) -> dict[str, object]:
        return self.model_dump(mode='json')


def build_omi_managed_credential_context(caller: ServiceCaller) -> CredentialContext:
    return CredentialContext(caller=caller)


def is_fallback_eligible_by_default(
    failure_class: FailureClass | str,
    credential_policy: CredentialPolicy,
) -> bool:
    failure_value = failure_class.value if isinstance(failure_class, FailureClass) else failure_class
    if failure_value in {
        item.value if isinstance(item, FailureClass) else item
        for item in credential_policy.never_fallback_failure_classes
    }:
        return False
    return failure_value in {
        item.value if isinstance(item, FailureClass) else item
        for item in credential_policy.fallback_eligible_failure_classes
    }
