from datetime import datetime, timezone
from enum import Enum
from typing import Optional, List

from pydantic import BaseModel, ConfigDict, Field


class PlanType(str, Enum):
    free = 'free'
    bounded = 'bounded'
    unlimited = 'unlimited'


class SubscriptionStatus(str, Enum):
    active = 'active'
    on_hold = 'on_hold'
    cancelled = 'cancelled'
    failed = 'failed'
    expired = 'expired'
    inactive = 'inactive'


class BillingPresentation(str, Enum):
    skip = 'skip'
    checkout = 'checkout'


class PlanLimits(BaseModel):
    transcription_seconds: Optional[int] = None
    words_transcribed: Optional[int] = None
    insights_gained: Optional[int] = None
    # Chat caps. Exactly one of these is set per plan: `free` and `unlimited`
    # (displayed as "Plus") cap by question count; `architect` caps by cost_usd.
    chat_questions_per_month: Optional[int] = None
    chat_cost_usd_per_month: Optional[float] = None


class ChatQuotaUnit(str, Enum):
    questions = 'questions'
    cost_usd = 'cost_usd'


class ChatUsageQuota(BaseModel):
    plan: str
    plan_type: str
    unit: ChatQuotaUnit
    used: float
    limit: Optional[float] = None  # None = unlimited (fallback)
    percent: float = 0.0
    allowed: bool = True
    reset_at: Optional[int] = None  # unix seconds — start of next month UTC


class Subscription(BaseModel):
    plan: PlanType = PlanType.free
    plan_name: str = 'Free'
    offer_id: Optional[str] = None
    billing_customer_id: Optional[str] = None
    billing_subscription_id: Optional[str] = None
    billing_product_id: Optional[str] = None
    entitlement_policy: PlanType = PlanType.bounded
    status: SubscriptionStatus = SubscriptionStatus.active
    current_period_end: Optional[int] = None
    current_period_start: Optional[int] = None
    cancel_at_next_billing_date: bool = False
    billing_interval: Optional[str] = None
    price_string: Optional[str] = None
    provider_updated_at: Optional[int] = None
    features: List[str] = Field(default_factory=list)
    limits: PlanLimits = Field(default_factory=PlanLimits)

    def is_current_paid_entitlement(self, now: Optional[datetime] = None) -> bool:
        """Fail closed unless this is a complete, current provider projection."""

        has_provider_identity = all(
            (self.offer_id, self.billing_customer_id, self.billing_subscription_id, self.billing_product_id)
        )
        has_bounded_allowances = (
            self.limits.transcription_seconds is not None
            and self.limits.transcription_seconds > 0
            and ((self.limits.chat_questions_per_month or 0) > 0 or (self.limits.chat_cost_usd_per_month or 0) > 0)
        )
        if not (
            self.plan in {PlanType.bounded, PlanType.unlimited}
            and self.entitlement_policy is self.plan
            and self.status is SubscriptionStatus.active
            and self.current_period_end is not None
            and self.provider_updated_at is not None
            and self.provider_updated_at > 0
            and has_provider_identity
            and has_bounded_allowances
        ):
            return False
        current_time = now or datetime.now(timezone.utc)
        return self.current_period_end >= int(current_time.timestamp())


class PricingOption(BaseModel):
    id: str
    title: str
    description: Optional[str] = None
    price_string: str
    interval: str


class SubscriptionPlan(BaseModel):
    id: str
    title: str
    subtitle: Optional[str] = None  # e.g. "500 questions per month" — rendered under the title
    description: Optional[str] = None  # longer copy rendered below price
    eyebrow: Optional[str] = None  # e.g. "Most popular" — rendered above the title
    features: List[str] = Field(default_factory=list)
    prices: List[PricingOption] = Field(default_factory=list)


class BillingAvailability(BaseModel):
    model_config = ConfigDict(frozen=True)

    checkout_enabled: bool
    portal_enabled: bool
    presentation: BillingPresentation


class TrialMetadata(BaseModel):
    """Structured trial state for desktop clients to render countdown UI."""

    trial_started_at: Optional[int] = None  # unix seconds
    trial_ends_at: Optional[int] = None  # unix seconds
    trial_remaining_seconds: int = 0
    trial_expired: bool = False
    trial_duration_seconds: int = 0  # configured trial length
    trial_features: List[str] = []
    plan_after_trial: str = 'Free'  # display name of fallback plan


class UserSubscriptionResponse(BaseModel):
    subscription: Subscription
    transcription_seconds_used: int
    transcription_seconds_limit: int
    words_transcribed_used: int
    words_transcribed_limit: int
    insights_gained_used: int
    insights_gained_limit: int
    available_plans: List[SubscriptionPlan] = []
    billing_availability: BillingAvailability
    show_subscription_ui: bool = True
    # Chat quota usage — derived from llm_usage collection
    chat_quota_used: float = 0.0
    chat_quota_unit: Optional[ChatQuotaUnit] = None
    chat_quota_percent: float = 0.0
    chat_quota_allowed: bool = True
    chat_quota_reset_at: Optional[int] = None
