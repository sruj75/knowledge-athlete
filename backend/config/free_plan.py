import os

from models.users import PlanLimits, PlanType, Subscription, SubscriptionStatus


FREE_CHAT_QUESTIONS_PER_MONTH = int(os.getenv('FREE_CHAT_QUESTIONS_PER_MONTH', '30'))
FREE_TIER_MINUTES_LIMIT_PER_MONTH = int(os.getenv('FREE_TIER_MINUTES_LIMIT_PER_MONTH', '0'))
FREE_TIER_MONTHLY_SECONDS_LIMIT = FREE_TIER_MINUTES_LIMIT_PER_MONTH * 60
FREE_TIER_WORDS_TRANSCRIBED_LIMIT_PER_MONTH = int(os.getenv('FREE_TIER_WORDS_TRANSCRIBED_LIMIT_PER_MONTH', '0'))
FREE_TIER_INSIGHTS_GAINED_LIMIT_PER_MONTH = int(os.getenv('FREE_TIER_INSIGHTS_GAINED_LIMIT_PER_MONTH', '0'))

TRIAL_FEATURES = [
    'unlimited_listening',
    'unlimited_transcription',
    'unlimited_memories',
    'unlimited_insights',
    f'{FREE_CHAT_QUESTIONS_PER_MONTH}_chat_questions_per_month',
]


def get_free_plan_limits() -> PlanLimits:
    return PlanLimits(
        transcription_seconds=FREE_TIER_MONTHLY_SECONDS_LIMIT or None,
        words_transcribed=FREE_TIER_WORDS_TRANSCRIBED_LIMIT_PER_MONTH or None,
        insights_gained=FREE_TIER_INSIGHTS_GAINED_LIMIT_PER_MONTH or None,
        chat_questions_per_month=FREE_CHAT_QUESTIONS_PER_MONTH,
    )


def get_default_free_subscription() -> Subscription:
    return Subscription(
        plan=PlanType.free,
        plan_name='Free',
        entitlement_policy=PlanType.bounded,
        status=SubscriptionStatus.active,
        limits=get_free_plan_limits(),
        features=['listening', 'memories', f'{FREE_CHAT_QUESTIONS_PER_MONTH}_chat_questions_per_month'],
    )
